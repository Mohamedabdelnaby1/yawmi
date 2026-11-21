import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'csv_table.dart';
import 'dated_alerts.dart';
import 'design.dart';
import 'domain.dart';
import 'reminder_schedule.dart';
import 'widgets.dart' show restoreWidgetDesigns;

const maxBackupBytes = 20 * 1024 * 1024;
const _backupMagic = 'yawmi/backup/1';
final _associated = utf8.encode(_backupMagic);
final _aes = AesGcm.with256bits();
final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

Future<Uint8List> makeBackup(JournalRow state, String password) =>
    compute(_seal, (state, password));

Future<Uint8List> _seal((JournalRow, String) input) async {
  final copy = {...input.$1, 'snoozes': <JournalRow>[]};
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final key = await _kdf.deriveKeyFromPassword(password: input.$2, nonce: salt);
  final encrypted = await _aes.encrypt(
    utf8.encode(jsonEncode(copy)),
    secretKey: key,
    aad: _associated,
  );
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': _backupMagic,
        'salt': base64Encode(salt),
        'nonce': base64Encode(encrypted.nonce),
        'cipher': base64Encode(encrypted.cipherText),
        'tag': base64Encode(encrypted.mac.bytes),
      }),
    ),
  );
  if (bytes.length > maxBackupBytes) {
    throw const FormatException('Backup is too large');
  }
  return bytes;
}

Future<JournalRow> openBackup(Uint8List bytes, String password) =>
    compute(_unseal, (bytes, password));

Future<JournalRow> _unseal((Uint8List, String) input) async {
  if (input.$1.length > maxBackupBytes) {
    throw const FormatException('Backup is too large');
  }
  final pack = jsonDecode(utf8.decode(input.$1)) as JournalRow;
  if (pack['format'] != _backupMagic) {
    throw const FormatException('Unsupported backup');
  }
  final salt = base64Decode(pack['salt'] as String);
  final nonce = base64Decode(pack['nonce'] as String);
  final tag = base64Decode(pack['tag'] as String);
  if (salt.length != 16 || nonce.length != 12 || tag.length != 16) {
    throw const FormatException('Invalid encryption metadata');
  }
  final key = await _kdf.deriveKeyFromPassword(password: input.$2, nonce: salt);
  final data = await _aes.decrypt(
    SecretBox(
      base64Decode(pack['cipher'] as String),
      nonce: nonce,
      mac: Mac(tag),
    ),
    secretKey: key,
    aad: _associated,
  );
  final raw = jsonDecode(utf8.decode(data)) as JournalRow;
  return _validate(raw);
}

JournalRow _validate(JournalRow raw) {
  void require(bool condition) {
    if (!condition) throw const FormatException('Invalid journal data');
  }

  bool text(Object? value) => value is String && value.length <= 4000;
  bool stamp(Object? value) =>
      value is String && DateTime.tryParse(value) != null;
  bool day(Object? value) =>
      value is String &&
      RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(value) &&
      stamp(value);
  bool slot(Object? value) => value is int && value >= 0 && value < 1440;
  bool scheduleDays(Object? value) =>
      value is List &&
      value.isNotEmpty &&
      value.every((e) => e is int && allDays.contains(e));
  require(raw['version'] == 1);
  final clean = freshState();
  for (final k in [
    'conditions',
    'custom',
    'entries',
    'meds',
    'doses',
    'reminders',
    if (raw['followUps'] != null) 'followUps',
  ]) {
    require(raw[k] is List);
    final collection = rows(raw[k]);
    require(
      collection.every((e) => text(e['id']) && (e['id'] as String).isNotEmpty),
    );
    require(collection.map((e) => e['id']).toSet().length == collection.length);
    clean[k] = collection;
  }
  for (final tracker in rows(clean['custom'])) {
    require(
      text(tracker['name']) &&
          text(tracker['unit']) &&
          ['number', 'bool', 'text'].contains(tracker['kind']),
    );
    require(
      !trackers.any((t) => t.id == tracker['id']) &&
          tracker['id'] != medicineCard,
    );
  }
  for (final c in rows(clean['conditions'])) {
    require(text(c['name']));
    for (final field in ['label', 'profileNote', 'variant']) {
      require(c[field] == null || text(c[field]));
    }
    strings(c['links']);
  }
  for (final e in rows(clean['entries'])) {
    require(text(e['tracker']) && stamp(e['at']) && stamp(e['created']));
    final t = trackerFor(clean, e['tracker'] as String);
    if (t == null) throw const FormatException('Unknown tracker');
    require(
      e['unit'] == (t.units.isEmpty ? '' : e['unit']) &&
          (t.units.isEmpty || t.units.contains(e['unit'])),
    );
    final v = e['values'] as Map;
    if (t.kind == 'number') {
      for (final field in t.fields) {
        final n = v[field.id];
        require((field.optional && n == null) || n is num && n.isFinite);
      }
    } else if (t.kind == 'bool') {
      require(v['value'] is bool);
    } else {
      require(text(v['value']));
    }
    require(e['note'] == null || text(e['note']));
    require(e['context'] == null || text(e['context']));
    require(e['planned'] == null || e['planned'] is bool);
    require(e['planCompletedAt'] == null || stamp(e['planCompletedAt']));
    require(e['reminderOccurrence'] == null || text(e['reminderOccurrence']));
    require(
      rows(e['conditions']).every((c) => text(c['id']) && text(c['name'])),
    );
  }
  final medicines = rows(clean['meds']);
  for (final m in medicines) {
    require(
      text(m['name']) &&
          day(m['start']) &&
          (m['end'] == null || day(m['end'])) &&
          m['revision'] is int &&
          (m['effective'] == null || stamp(m['effective'])) &&
          m['times'] is List &&
          (m['times'] as List).every(slot) &&
          scheduleDays(m['days']) &&
          (m['amount'] == null || text(m['amount'])) &&
          (m['directions'] == null || text(m['directions'])),
    );
    strings(m['links']);
    if (m.containsKey('mealSlots')) {
      m['mealSlots'] = readDoseMeals(m['mealSlots'], ints(m['times']));
    }
    if (m['inventory'] != null) {
      final stock = MedicationStock.read(m['inventory']);
      require(stock != null);
      m['inventory'] = {...stock!.toRow(), 'notify': false};
    }
    if (m['expiry'] != null) {
      final alert = DateAlert.read(m['expiry']);
      require(alert != null);
      m['expiry'] = alert!.toRow(pause: true);
    }
  }
  final followUps = rows(clean['followUps']);
  for (final plan in followUps) {
    final alert = DateAlert.read(plan['alert']);
    require(
      text(plan['name']) &&
          (plan['name'] as String).trim().isNotEmpty &&
          (plan['name'] as String).length <= 100 &&
          (plan['tracker'] == null || text(plan['tracker'])) &&
          (plan['completedAt'] == null || stamp(plan['completedAt'])) &&
          alert != null,
    );
    plan['alert'] = alert!.toRow(pause: true);
  }
  clean['followUps'] = followUps;
  for (final d in rows(clean['doses'])) {
    require(
      text(d['name']) &&
          stamp(d['at']) &&
          ['taken', 'skipped'].contains(d['status']) &&
          (d['scheduled'] == null || stamp(d['scheduled'])) &&
          (d['amount'] == null || text(d['amount'])) &&
          (d['stockCycle'] == null ||
              (text(d['stockCycle']) &&
                  d['stockUsed'] is num &&
                  (d['stockUsed'] as num).isFinite &&
                  (d['stockUsed'] as num) > 0 &&
                  (d['stockUsed'] as num) <= 100000000 &&
                  stamp(d['stockChangedAt']))),
    );
  }
  for (final r in rows(clean['reminders'])) {
    require(
      text(r['name']) &&
          day(r['start']) &&
          (r['end'] == null || day(r['end'])) &&
          slot(r['minute']) &&
          (r['times'] == null ||
              (r['times'] is List &&
                  (r['times'] as List).isNotEmpty &&
                  (r['times'] as List).length <= 12 &&
                  (r['times'] as List).every(slot))) &&
          (r['effective'] == null || stamp(r['effective'])) &&
          scheduleDays(r['days']) &&
          r['revision'] is int &&
          slot(r['low']) &&
          slot(r['high']) &&
          ['off', 'suggest', 'auto'].contains(r['learn']) &&
          (r['tracker'] == null ||
              (text(r['tracker']) && trackerFor(clean, r['tracker']) != null)),
    );
    r['enabled'] = false;
  }
  clean['reminders'] = rows(
    clean['reminders'],
  ).map((r) => {...r, 'enabled': false}).toList();
  clean['meds'] = medicines.map((r) => {...r, 'notify': false}).toList();
  if (raw['repeatPreferences'] case final Map preferences) {
    clean['repeatPreferences'] = {
      for (final type in ['medicine', 'tracking', 'habit'])
        if (preferences[type] is Map)
          type: {
            'count': readRepeat(preferences[type]).count,
            'minutes': readRepeat(preferences[type]).minutes,
          },
    };
  }
  if (raw['waterReminder'] case final Map plan
      when slot(plan['wake']) &&
          slot(plan['sleep']) &&
          waterIntervals.contains(plan['interval']) &&
          firstWaterDelays.contains(plan['first']) &&
          plan['days'] is List &&
          (plan['days'] as List).every(
            (day) => day is int && allDays.contains(day),
          ) &&
          (plan['effective'] == null || stamp(plan['effective']))) {
    clean['waterReminder'] = {
      'wake': plan['wake'],
      'sleep': plan['sleep'],
      'interval': plan['interval'],
      'first': plan['first'],
      'days': plan['days'],
      'effective': plan['effective'],
      'enabled': false,
      if (plan['repeat'] is Map) 'repeat': plan['repeat'],
    };
  }
  for (final k in [
    'enabled',
    'hidden',
    'pinned',
    'order',
    'recent',
    'setupAuto',
  ]) {
    clean[k] = strings(raw[k])
        .where((id) => id == medicineCard || trackerFor(clean, id) != null)
        .toSet()
        .toList();
  }
  final units = raw['unitPrefs'] as Map? ?? {};
  clean['unitPrefs'] = {
    for (final e in units.entries)
      if (e.key is String &&
          trackerFor(clean, e.key)?.units.contains(e.value) == true)
        e.key: e.value,
  };
  for (final (key, valid) in [
    ('theme', ['system', 'light', 'dark']),
    ('language', ['system', 'ar', 'en']),
    ('startSection', ['tracking', 'doses']),
    ('layoutLearning', ['off', 'suggest', 'auto']),
  ]) {
    if (valid.contains(raw[key])) clean[key] = raw[key];
  }
  clean['widgets'] = restoreWidgetDesigns(clean, raw['widgets']);
  if (rows(
    clean['widgets'],
  ).any((layout) => layout['id'] == raw['widgetDefault'])) {
    clean['widgetDefault'] = raw['widgetDefault'];
  }
  if (raw['waterGoal'] case final num n when n.isFinite && n > 0) {
    clean['waterGoal'] = n;
  }
  clean['glucoseAverage'] = raw['glucoseAverage'] == true;
  final savedViews = raw['trackerViews'];
  if (savedViews is Map) {
    final views = <String, JournalRow>{};
    for (final tracker in allTrackers(clean)) {
      final original = savedViews[tracker.id];
      if (original is! Map) continue;
      final computed = trackerView({
        'trackerViews': {tracker.id: original},
      }, tracker);
      views[tracker.id] = {
        'mode': computed.mode,
        'days': computed.days,
        'context': computed.context,
        'secondary': computed.secondary,
        'doseSummary': computed.doseSummary,
      };
    }
    clean['trackerViews'] = views;
  }
  final cups = raw['waterCups'];
  if (cups is List && cups.every((x) => x is int)) {
    clean['waterCups'] = waterCups(raw);
    clean['waterDefaultCup'] = defaultWaterCup(raw);
  }
  clean['reduce'] = raw['reduce'] == true;
  clean['todayCompact'] = raw['todayCompact'] == true;
  clean['quickPins'] = quickPins({...clean, 'quickPins': raw['quickPins']});
  clean['discoverReminders'] = raw['discoverReminders'] == true;
  clean['quiet'] = {
    for (final c in ['medicine', 'tracking', 'habit'])
      if ((raw['quiet'] as Map?)?[c] case final Map q
          when ['off', 'silent', 'skip', 'defer'].contains(q['mode']) &&
              slot(q['start']) &&
              slot(q['end']))
        c: q,
  };
  clean['stage'] = 3;
  return clean;
}

String _cell(Object? value) {
  var cell = value?.toString() ?? '';
  if (RegExp(r"^[\s]*[=+@\-\t\r\n]").hasMatch(cell)) cell = "'$cell";
  return '"${cell.replaceAll('"', '""')}"';
}

Uint8List makeCsv(List<JournalRow> entries, {required bool notes}) {
  final out = StringBuffer('\uFEFF$_journalCsvHeader\r\n');
  for (final e in entries) {
    final fields = e['tracker'] == medicineCard
        ? {'status': e['status']}
        : {
            ...e['values'] as Map,
            if (e['legacyCarbs'] is num) 'carbohydrates': e['legacyCarbs'],
          };
    for (final f in fields.entries) {
      out.writeln(
        [
              e['id'],
              e['legacyUndated'] == true ? '' : e['at'],
              e['tracker'],
              f.key,
              f.value,
              switch (f.key) {
                'pulse' => 'bpm',
                'carbohydrates' => 'g',
                _ => e['unit'],
              },
              e['context'],
              if (notes) e['note'],
            ].map(_cell).join(',') +
            (notes ? '\r' : ',\r'),
      );
    }
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

const csvMaxBytes = 16 * 1024 * 1024;
const _journalCsvHeader =
    'id,timestamp_utc,tracker,field,value,unit,context,note';

typedef CsvImport = ({List<JournalRow> entries, int skipped});

Future<CsvImport> readJournalCsv(JournalRow state, Uint8List bytes) =>
    compute(_readJournalCsv, (state['custom'], bytes));

CsvImport _readJournalCsv((Object?, Uint8List) input) {
  final (custom, bytes) = input;
  if (bytes.length > csvMaxBytes)
    throw const FormatException('CSV is too large');
  final table = parseCsvTable(utf8.decode(bytes));
  if (table.isEmpty || table.first.join(',') != _journalCsvHeader) {
    throw const FormatException('Expected the Yawmi CSV columns');
  }
  final records = <String, List<List<String>>>{};
  for (final row in table.skip(1)) {
    if (row.length != 8 || row.first.isEmpty || row.first.length > 4000) {
      throw const FormatException('Incomplete CSV record');
    }
    (records[row.first] ??= []).add(row);
  }
  final entries = <JournalRow>[];
  var skipped = 0;
  for (final columns in records.values) {
    final record = _journalCsvEntry({'custom': custom}, columns);
    if (record == null) {
      skipped++;
    } else {
      entries.add(record);
    }
  }
  return (entries: entries, skipped: skipped);
}

JournalRow? _journalCsvEntry(JournalRow state, List<List<String>> columns) {
  final [id, timestamp, trackerId, _, _, _, context, note] = columns.first;
  final tracker = trackerFor(state, trackerId);
  final at = DateTime.tryParse(timestamp)?.toUtc();
  if (tracker == null ||
      at == null ||
      at.year < 1900 ||
      at.year > 2200 ||
      context.length > 4000 ||
      note.length > 4000) {
    return null;
  }
  final allowed = {for (final field in tracker.fields) field.id: field};
  final values = <String, dynamic>{};
  String? unit;
  for (final [_, date, type, field, raw, fieldUnit, detail, memo] in columns) {
    if (date != timestamp ||
        type != trackerId ||
        detail != context ||
        memo != note)
      return null;
    if (field == 'carbohydrates')
      continue; // Optional archival column in CSV exports.
    if (!allowed.containsKey(field) || values.containsKey(field)) return null;
    if (trackerId != 'pressure' || field != 'pulse') {
      if (unit != null && unit != fieldUnit) return null;
      unit = fieldUnit;
    } else if (fieldUnit != 'bpm') {
      return null;
    }
    final value = switch (tracker.kind) {
      'number' => readNumber(raw),
      'bool' =>
        raw == 'true'
            ? true
            : raw == 'false'
            ? false
            : null,
      _ => raw.trim().isNotEmpty && raw.length <= 4000 ? raw : null,
    };
    if (value == null) return null;
    values[field] = value;
  }
  if (unit == null ||
      (tracker.units.isEmpty ? unit != '' : !tracker.units.contains(unit)) ||
      allowed.values.any(
        (field) => !field.optional && !values.containsKey(field.id),
      )) {
    return null;
  }
  final stamp = at.toIso8601String();
  return {
    'id': id,
    'tracker': trackerId,
    'values': values,
    'unit': unit,
    'context': context,
    'note': note,
    'at': stamp,
    'created': stamp,
    'conditions': <JournalRow>[],
  };
}

List<JournalRow> newCsvEntries(
  JournalRow state,
  Iterable<JournalRow> incoming,
) {
  final ids = rows(state['entries']).map((row) => row['id']).toSet();
  return incoming.where((row) => ids.add(row['id'])).toList();
}

String reportValue(JournalRow e, bool ar) => e['tracker'] == medicineCard
    ? tr(
        ar,
        e['status'] == 'taken' ? 'تم التسجيل' : 'تم التخطي',
        e['status'] == 'taken' ? 'Taken' : 'Skipped',
      )
    : [
        valueText(e, ar),
        e['unit'] as String? ?? '',
        if (e['legacyCarbs'] case final num grams)
          number(grams.toDouble()) + tr(ar, ' غ كربوهيدرات', ' g carbs'),
      ].where((s) => s.isNotEmpty).join(' ');

Future<Uint8List> makePdf(
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
  String range, {
  required bool notes,
}) async {
  final base = pw.Font.ttf(await rootBundle.load('assets/Tajawal-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/Tajawal-Bold.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
  final direction = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: direction,
      margin: const pw.EdgeInsets.all(37),
      maxPages: 1000,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            tr(ar, 'يومي | تقرير السجل', 'Yawmi | Journal report'),
            textDirection: direction,
            style: pw.TextStyle(
              color: PdfColor.fromHex('#172431'),
              fontWeight: pw.FontWeight.bold,
              fontSize: 21,
            ),
          ),
          pw.Text(range, textDirection: pw.TextDirection.ltr),
          pw.SizedBox(height: 9),
        ],
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('${c.pageNumber} / ${c.pagesCount}'),
      ),
      build: (_) => [
        pw.Text(
          '${tr(ar, 'عدد الإدخالات', 'Number of entries')} · ${entries.length}',
          textDirection: direction,
        ),
        pw.SizedBox(height: 7),
        for (final e in entries)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 7),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: .5),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  e['tracker'] == medicineCard
                      ? e['name']
                      : cardName(state, e['tracker'], ar),
                  textDirection: direction,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  e['legacyUndated'] == true
                      ? tr(ar, 'مستورد من غير تاريخ', 'Imported without a date')
                      : '${dayKey(eventTime(e))} · ${clockText(eventTime(e).hour * 60 + eventTime(e).minute)}',
                  textDirection: e['legacyUndated'] == true
                      ? direction
                      : pw.TextDirection.ltr,
                ),
                pw.Text(reportValue(e, ar), textDirection: direction),
                if (entryContext(e['context'], ar).isNotEmpty)
                  pw.Text(
                    entryContext(e['context'], ar),
                    textDirection: direction,
                  ),
                if (notes &&
                    e['note'] is String &&
                    (e['note'] as String).isNotEmpty)
                  pw.Text(
                    e['note'],
                    textDirection: direction,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  return doc.save();
}

typedef VisitGroup = ({String id, String title, String detail, int count});

List<VisitGroup> visitSummary(
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
) {
  final groups = <String, List<JournalRow>>{};
  for (final row in entries) {
    groups.putIfAbsent(row['tracker'] as String, () => []).add(row);
  }
  final sorted = groups.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  const limit = 8;
  return [
    for (final group in sorted.take(sorted.length > limit ? limit - 1 : limit))
      if (group.key == medicineCard)
        (
          id: group.key,
          title: cardName(state, group.key, ar),
          count: group.value.length,
          detail:
              "${tr(ar, 'تم التسجيل', 'Taken')} "
              "${group.value.where((row) => row['status'] == 'taken').length} · "
              "${tr(ar, 'تم التخطي', 'Skipped')} "
              "${group.value.where((row) => row['status'] == 'skipped').length}",
        )
      else
        (
          id: group.key,
          title: cardName(state, group.key, ar),
          count: group.value.length,
          detail: trackerFor(state, group.key)?.kind == 'number'
              ? _visitLatest(group.value, ar)
              : tr(ar, 'إدخالات خلال الفترة', 'Entries during the period'),
        ),
    if (sorted.length > limit)
      (
        id: 'other',
        title: tr(ar, 'متابعات أخرى', 'Other trackers'),
        detail: tr(
          ar,
          'تفاصيلها متاحة في التقرير الكامل',
          'Details are in the full report',
        ),
        count: sorted.skip(limit - 1).fold(0, (n, e) => n + e.value.length),
      ),
  ];
}

String _visitLatest(List<JournalRow> entries, bool ar) {
  final last = entries.reduce(
    (a, b) => eventTime(a).isBefore(eventTime(b)) ? b : a,
  );
  final value = reportValue(last, ar);
  return '$value · ${dayKey(eventTime(last))}';
}

Future<Uint8List> makeVisitSummaryPdf(
  JournalRow state,
  List<JournalRow> entries,
  bool ar,
  String range,
) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/Tajawal-Regular.ttf'),
  );
  final bold = pw.Font.ttf(await rootBundle.load('assets/Tajawal-Bold.ttf'));
  final groups = visitSummary(state, entries, ar);
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            tr(ar, 'ملخّص زيارة · يومي', 'Visit summary · Yawmi'),
            style: pw.TextStyle(font: bold, fontSize: 24),
          ),
          pw.SizedBox(height: 9),
          pw.Text('$range  ·  ${entries.length} ${tr(ar, 'إدخال', 'entries')}'),
          pw.SizedBox(height: 18),
          for (final group in groups)
            pw.Container(
              height: 56,
              padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 7),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey400),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    '${group.title}  ·  ${group.count}',
                    maxLines: 1,
                    style: pw.TextStyle(font: bold, fontSize: 14),
                  ),
                  pw.Text(
                    group.detail,
                    maxLines: 1,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            tr(
              ar,
              'الملخّص مبني على إدخالات السجل المختارة.',
              'Summary based on the selected journal entries.',
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

Future<Directory> _shareDirectory() async => Directory.fromUri(
  (await getTemporaryDirectory()).uri.resolve('yawmi-share/'),
);

Future<void> clearSharedReports({bool all = false}) async {
  final directory = await _shareDirectory();
  if (!await directory.exists()) return;
  final now = DateTime.now();
  await for (final f in directory.list(followLinks: false)) {
    if (f is File &&
        (all ||
            now.difference(await f.lastModified()) >
                const Duration(hours: 1))) {
      await f.delete();
    }
  }
}

Future<void> shareBytes(Uint8List bytes, String filename, String mime) async {
  final directory = await _shareDirectory();
  await directory.create(recursive: true);
  await clearSharedReports();
  final file = File.fromUri(directory.uri.resolve('${newId()}_$filename'));
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mime)],
      fileNameOverrides: [filename],
    ),
  );
}
