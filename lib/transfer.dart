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
import 'care_data.dart';
import 'app_copy.dart';
import 'dated_alerts.dart';
import 'design.dart';
import 'domain.dart';
import 'reminder_schedule.dart';
import 'widgets.dart' show restoreWidgetDesigns;

part 'journal_pdf.dart';

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
    if (raw['visits'] != null) 'visits',
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
    require(e['sourceRecordId'] == null || text(e['sourceRecordId']));
    require(
      e['moodTone'] == null ||
          t.id == 'mood' && moodChoices.containsKey(e['moodTone']),
    );
    require(
      e['readingSource'] == null ||
          readingSources.containsKey(e['readingSource']),
    );
    require(
      e['mealMinutes'] == null ||
          e['mealMinutes'] is int &&
              (e['mealMinutes'] as int) >= 0 &&
              (e['mealMinutes'] as int) <= 1440,
    );
    require(
      e['labDetails'] == null ||
          t.id == 'lab' && readLabDetails(e['labDetails']) != null,
    );
    if (e['labAttachment'] case final Map attachment) {
      final encoded = attachment['data'];
      require(
        t.id == 'lab' &&
            text(attachment['name']) &&
            encoded is String &&
            encoded.length <= ((maxLabAttachmentBytes + 2) ~/ 3) * 4,
      );
      final bytes = base64Decode(encoded as String);
      final mime = labAttachmentFormat(bytes);
      require(
        bytes.length <= maxLabAttachmentBytes &&
            mime != null &&
            mime == attachment['format'],
      );
    } else {
      require(e['labAttachment'] == null);
    }
    if (e['pressureSession'] case final List pair) {
      require(
        t.id == 'pressure' &&
            pair.length == 2 &&
            pair.every(
              (p) =>
                  p is Map &&
                  ['systolic', 'diastolic'].every(
                    (key) =>
                        p[key] is num &&
                        (p[key] as num).isFinite &&
                        (p[key] as num) > 0,
                  ),
            ),
      );
    } else {
      require(e['pressureSession'] == null);
    }
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
          (m['strength'] == null || text(m['strength'])) &&
          (m['administration'] == null || text(m['administration'])) &&
          (m['directions'] == null || text(m['directions'])),
    );
    strings(m['links']);
    if (m['changes'] != null) {
      require(
        m['changes'] is List &&
            (m['changes'] as List).length <= 50 &&
            rows(m['changes']).every(
              (r) =>
                  stamp(r['at']) &&
                  [
                    'previous',
                    'dose',
                    'strength',
                    'administration',
                  ].every((key) => text(r[key])),
            ),
      );
    }
    if (m.containsKey('mealSlots')) {
      m['mealSlots'] = readDoseMeals(m['mealSlots'], ints(m['times']));
    }
    if (m['inventory'] != null) {
      final stock = MedicationStock.read(m['inventory']);
      require(stock != null);
      m['inventory'] = {...stock!.toRow(), 'notify': false};
    }
    m.remove('forecastLead');
    if (m['expiry'] != null) {
      final alert = DateAlert.read(m['expiry']);
      require(alert != null);
      m['expiry'] = alert!.toRow(pause: true);
    }
    if (m['packs'] != null) {
      final packs = rows(m['packs']);
      require(
        packs.length <= 30 &&
            packs.map((p) => p['id']).toSet().length == packs.length,
      );
      for (final pack in packs) {
        final alert = DateAlert.read(pack['expiry']);
        final count = pack['count'];
        require(
          text(pack['id']) &&
              text(pack['name']) &&
              count is num &&
              count.isFinite &&
              count >= 0 &&
              count <= 100000000 &&
              alert != null,
        );
        pack['expiry'] = alert!.toRow(pause: true);
      }
      m['packs'] = packs;
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
          (plan['sourceEntry'] == null || text(plan['sourceEntry'])) &&
          (plan['completedAt'] == null || stamp(plan['completedAt'])) &&
          alert != null,
    );
    plan['alert'] = alert!.toRow(pause: true);
  }
  clean['followUps'] = followUps;
  for (final visit in rows(clean['visits'])) {
    require(
      text(visit['name']) &&
          day(visit['date']) &&
          (visit['condition'] == null || text(visit['condition'])) &&
          text(visit['questions']) &&
          text(visit['outcome']) &&
          (visit['followUp'] == null || text(visit['followUp'])) &&
          (visit['reviewedAt'] == null || stamp(visit['reviewedAt'])) &&
          visit['linkedEntries'] is List &&
          (visit['linkedEntries'] as List).length <= 80 &&
          (visit['linkedEntries'] as List).every(text),
    );
  }
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
  if (['log', 'goal', 'limit'].contains(raw['waterMode']))
    clean['waterMode'] = raw['waterMode'];
  if (text(raw['allergyNotes'])) clean['allergyNotes'] = raw['allergyNotes'];
  if (raw['carePlans'] case final Map plans) {
    clean['carePlans'] = {
      for (final plan in plans.entries)
        if (plan.key is String &&
            plan.value is Map &&
            [
              'measure',
              'timing',
              'target',
            ].every((key) => text(plan.value[key])) &&
            (plan.value['review'] == null ||
                parseCalendarDate(plan.value['review']) != null))
          plan.key: {
            for (final key in ['measure', 'timing', 'target', 'review'])
              if (plan.value[key] != null) key: plan.value[key],
            if (stamp(plan.value['updatedAt']))
              'updatedAt': plan.value['updatedAt'],
          },
    };
  }
  if (raw['routineShifts'] case final Map shifts) {
    clean['routineShifts'] = {
      for (final mode in routineModes)
        if (shifts[mode] case final int shift
            when shift.abs() <= 180 && shift % 30 == 0)
          mode: shift,
    };
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
        e['status'] == 'taken' ? 'اتسجّل' : 'اتخطّى',
        e['status'] == 'taken' ? 'Taken' : 'Skipped',
      )
    : [
        valueText(e, ar),
        if (readLabDetails(e['labDetails']) case final lab?) ...[
          number((lab['result'] as num).toDouble()),
          lab['unit'] as String,
        ] else
          e['unit'] as String? ?? '',
        if (e['legacyCarbs'] case final num grams)
          number(grams.toDouble()) + tr(ar, ' غ كربوهيدرات', ' g carbs'),
      ].where((s) => s.isNotEmpty).join(' ');

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
              "${tr(ar, 'اتسجّل', 'Taken')} "
              "${group.value.where((row) => row['status'] == 'taken').length} · "
              "${tr(ar, 'اتخطّى', 'Skipped')} "
              "${group.value.where((row) => row['status'] == 'skipped').length}",
        )
      else
        (
          id: group.key,
          title: cardName(state, group.key, ar),
          count: group.value.length,
          detail: trackerFor(state, group.key)?.kind == 'number'
              ? _visitTrend(state, group.key, group.value, ar)
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

String _visitTrend(
  JournalRow state,
  String id,
  List<JournalRow> entries,
  bool ar,
) {
  final trend = careTrend(state, id, entries);
  if (trend == null) return _visitLatest(entries, ar);
  final secondary = trend.secondaryMean;
  final mean = secondary == null
      ? number(trend.mean)
      : '${number(trend.mean)} / ${number(secondary)}';
  return '${tr(ar, 'متوسط', 'Mean')} $mean ${trend.unit} · ${trend.count} ${tr(ar, 'قراءة', 'readings')} · ${trend.days} ${tr(ar, 'يوم', 'days')}';
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
