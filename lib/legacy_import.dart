import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

import 'csv_table.dart';
import 'domain.dart';

const _magic = 'YAWMI001';
const _csvColumns = [
  'id',
  'measured_at_iso',
  'entered_at_iso',
  'kind',
  'value_original',
  'second_value',
  'unit',
  'context',
  'status',
  'note',
  'source',
  'planned_at_iso',
];

bool isLegacyBackup(Uint8List bytes) =>
    bytes.length >= 8 && String.fromCharCodes(bytes.take(8)) == _magic;

class LegacyImport {
  const LegacyImport(
    this.entries,
    this.medicines,
    this.doses, {
    this.prefs = const {},
    this.unscheduled = 0,
  });
  final List<JournalRow> entries, medicines, doses;
  final JournalRow prefs;
  final int unscheduled;

  Map<String, int> additions(JournalRow state) {
    int count(String key, List<JournalRow> incoming) {
      final ids = rows(state[key]).map((x) => x['id']).toSet();
      return incoming.where((x) => ids.add(x['id'])).length;
    }

    return {
      'entries': count('entries', entries),
      'meds': count('meds', medicines),
      'doses': count('doses', doses),
    };
  }

  void appendTo(
    JournalRow state, {
    bool preferences = false,
    bool addCards = true,
  }) {
    void append(String key, List<JournalRow> incoming) {
      final existing = rows(state[key]);
      final ids = existing.map((e) => e['id']).toSet();
      state[key] = [...existing, ...incoming.where((e) => ids.add(e['id']))];
    }

    append('entries', entries);
    append('meds', medicines);
    append('doses', doses);
    final linked = {
      for (final dose in doses)
        if (dose['medicine'] != null) dose['id']: dose,
    };
    if (linked.isNotEmpty) {
      state['doses'] = [
        for (final row in rows(state['doses']))
          if (linked[row['id']] case final JournalRow full
              when row['source'] == 'legacy' && row['medicine'] == null)
            {
              ...row,
              for (final key in [
                'medicine',
                'amount',
                'directions',
                'legacyOccurrence',
                'legacyDue',
              ])
                if (full[key] != null) key: full[key],
              if (row['name'] == '') 'name': full['name'],
            }
          else
            row,
      ];
    }
    if (addCards) {
      final imported = {
        ...entries.map((e) => e['tracker'] as String),
        if (medicines.isNotEmpty || doses.isNotEmpty) medicineCard,
      };
      state['enabled'] = {...strings(state['enabled']), ...imported}.toList();
      state['hidden'] = strings(
        state['hidden'],
      ).where((id) => !imported.contains(id)).toList();
      state['setupAuto'] = strings(
        state['setupAuto'],
      ).where((id) => !imported.contains(id)).toList();
    }
    if (preferences) {
      for (final k in ['waterGoal', 'waterCups', 'waterDefaultCup']) {
        if (prefs.containsKey(k)) state[k] = prefs[k];
      }
      for (final k in ['unitPrefs', 'trackerViews']) {
        state[k] = {...(state[k] as Map? ?? {}), ...(prefs[k] as Map? ?? {})};
      }
    }
  }
}

Future<LegacyImport> readLegacy(Uint8List bytes, {String? password}) =>
    compute(_readLegacy, (bytes, password));

Future<LegacyImport> _readLegacy((Uint8List, String?) args) async {
  final (bytes, password) = args;
  if (bytes.length > 16000000)
    throw const FormatException('Legacy file is too large');
  if (isLegacyBackup(bytes)) {
    if (bytes.length < 52 || password == null)
      throw const FormatException('Missing encrypted data');
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: bytes.sublist(8, 24));
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        bytes.sublist(36, bytes.length - 16),
        nonce: bytes.sublist(24, 36),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: key,
      aad: ascii.encode(_magic),
    );
    final root = jsonDecode(utf8.decode(plain)) as JournalRow;
    if (root['schema'] != 1 ||
        root['entries'] is! List ||
        root['medications'] is! List) {
      throw const FormatException('Unsupported legacy schema');
    }
    return _convertLegacy(
      rows(root['entries']),
      rows(root['medications']),
      care: rows((root['care'] as Map?)?['items']),
      prefs: (root['preferences'] as Map?) ?? {},
    );
  }
  final grid = parseCsvTable(utf8.decode(bytes));
  if (grid.isEmpty ||
      grid.first.length != _csvColumns.length ||
      grid.first.join(',') != _csvColumns.join(',')) {
    throw const FormatException('Not a diabetes edition CSV file');
  }
  final entries = [
    for (final line in grid.skip(1))
      if (line.length != _csvColumns.length)
        throw const FormatException('Incomplete CSV record')
      else
        <String, dynamic>{
          'id': line[0],
          'time': line[1],
          'created': line[2],
          'kind': line[3],
          'value': line[4],
          'second': line[5],
          'unit': line[6],
          'context': line[7],
          'status': line[8],
          'note': line[9],
          'planned': line[11],
        },
  ];
  return _convertLegacy(entries, const []);
}

String _key(String type, Object? source) {
  if (source is! String || source.isEmpty || source.length > 200) {
    throw const FormatException('Bad legacy id');
  }
  return 'legacy_' +
      type +
      '_' +
      base64Url.encode(utf8.encode(source)).replaceAll('=', '');
}

String _text(Object? v) => v is String ? v : '';

String _stamp(Object? value) {
  final date = value is int && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
      : value is String && value.isNotEmpty
      ? DateTime.tryParse(value)?.toUtc()
      : null;
  if (date == null || date.year < 1900 || date.year > 2200) {
    throw const FormatException('Invalid legacy date');
  }
  return date.toIso8601String();
}

bool _hasTime(Object? value) =>
    value is int ? value > 0 : value is String && value.isNotEmpty;

double _measure(Object? value) {
  final n = value is num ? value.toDouble() : readNumber(_text(value));
  if (n == null || !n.isFinite)
    throw const FormatException('Invalid legacy measurement');
  return n;
}

String _context(String code) => switch (code) {
  'before' => 'before meal',
  'after' => 'after meal',
  _ => code,
};

int? _minute(String value) {
  final match = RegExp(
    r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$',
  ).firstMatch(value);
  return match == null
      ? null
      : int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

LegacyImport _convertLegacy(
  List<JournalRow> source,
  List<JournalRow> medicineRows, {
  List<JournalRow> care = const [],
  Map prefs = const {},
}) {
  if (source.length > 100000 ||
      medicineRows.length > 500 ||
      care.length > 500) {
    throw const FormatException('Too many legacy records');
  }
  final entries = <JournalRow>[], meds = <JournalRow>[], doses = <JournalRow>[];
  var unscheduled = 0;
  for (final m in medicineRows) {
    final name = _text(m['name']).trim();
    if (name.isEmpty) throw const FormatException('Invalid medication name');
    final mode = _text(m['mode']).isEmpty ? 'daily' : _text(m['mode']);
    final times = strings(
      m['times'],
    ).map(_minute).whereType<int>().toSet().toList()..sort();
    final weekdays =
        (m['weekdays'] as List? ?? [])
            .map((v) => int.tryParse(v.toString()))
            .whereType<int>()
            .where(allDays.contains)
            .toSet()
            .toList()
          ..sort();
    final known =
        times.isNotEmpty &&
        (mode == 'daily' || mode == 'weekly' && weekdays.isNotEmpty);
    if (!known && m['active'] != false) unscheduled++;
    meds.add({
      'id': _key('med', m['id']),
      'name': name,
      'amount': [
        _text(m['dose']),
        _text(m['strength']),
      ].where((s) => s.isNotEmpty).join(' · '),
      'directions': _text(m['instructions']),
      'links': <String>[],
      'start': dayKey(DateTime.parse(_stamp(m['anchor'])).toLocal()),
      'end': null,
      'revision': 1,
      'times': known ? times : <int>[],
      'days': mode == 'weekly' && weekdays.isNotEmpty ? weekdays : allDays,
      'archived': m['active'] == false,
      'notify': false,
      'legacySchedule': {
        'mode': mode,
        'times': m['times'],
        'weekdays': weekdays,
        'anchor': m['anchor'],
        'intervalHours': m['intervalHours'],
        'meal': m['meal'],
        'relation': m['relation'],
        'offsetMinutes': m['offsetMinutes'],
        'plannedTime': m['plannedTime'],
        'stock': m['stock'],
        'stockPerDose': m['stockPerDose'],
        'refillAt': m['refillAt'],
        'review': !known,
      },
    });
  }
  final medIndex = {for (final m in meds) m['id']: m};
  final ids = <String>{};
  for (final e in source) {
    final id = _key('record', e['id']);
    if (!ids.add(id))
      throw const FormatException('Duplicate legacy id in file');
    final kind = _text(e['kind']);
    final at = _stamp(e['time']);
    final created = _hasTime(e['created']) ? _stamp(e['created']) : at;
    final note = _text(e['note']);
    final status = _text(e['status']);
    final context = _context(_text(e['context']));
    if (kind == 'dose' && ['taken', 'skipped'].contains(status)) {
      final ref = _text(e['medicationId']);
      final med = ref.isEmpty ? null : medIndex[_key('med', ref)];
      final scheduled = _hasTime(e['planned']) ? _stamp(e['planned']) : null;
      final due = scheduled == null
          ? null
          : DateTime.parse(scheduled).toLocal();
      doses.add({
        'id': id,
        'at': at,
        'created': created,
        'status': status,
        'note': note,
        'source': 'legacy',
        'name': med?['name'] ?? note.split(' · ').first.trim(),
        'medicine': ref.isEmpty ? null : _key('med', ref),
        'amount': med?['amount'],
        'revision': 1,
        'directions': med?['directions'],
        'scheduled': scheduled,
        'legacyOccurrence': _text(e['occurrence']),
        'legacyDoseValue': e['value'],
        if (due != null && med != null)
          'legacyDue': Dose(med, due, due.hour * 60 + due.minute).id,
      });
      continue;
    }
    final tracker = switch (kind) {
      'glucose' ||
      'water' ||
      'pressure' ||
      'weight' ||
      'a1c' ||
      'meal' ||
      'symptom' => kind,
      _ => 'note',
    };
    final spec = trackerFor(const {}, tracker)!;
    var unit = _text(e['unit']);
    if (unit.isEmpty && spec.units.isNotEmpty) unit = spec.units.first;
    double? carbs;
    final values = <String, dynamic>{};
    if (spec.kind == 'number') {
      if (!spec.units.contains(unit))
        throw const FormatException('Unknown legacy unit');
      if (tracker == 'pressure') {
        values['systolic'] = _measure(e['value']);
        values['diastolic'] = _measure(e['second']);
      } else {
        values['value'] = _measure(e['value']);
      }
    } else {
      values['value'] = switch (tracker) {
        'symptom' => context.isEmpty ? note : context,
        'meal' => note.isEmpty ? context : note,
        _ => [
          kind,
          context,
          note,
          if (status.isNotEmpty) status,
        ].where((s) => s.isNotEmpty).join(' · '),
      };
      if (tracker == 'meal' &&
          (e['value'] is num || _text(e['value']).isNotEmpty)) {
        carbs = _measure(e['value']);
      }
      unit = '';
    }
    entries.add({
      'id': id,
      'tracker': tracker,
      'revision': 1,
      'values': values,
      'unit': unit,
      'at': at,
      'created': created,
      'source': 'legacy',
      'note': note,
      if (carbs != null && carbs != 0) 'legacyCarbs': carbs,
      if (status.isNotEmpty) 'legacyStatus': status,
      'context':
          tracker == 'symptom' &&
              ['mild', 'moderate', 'severe'].contains(status)
          ? status
          : context,
    });
  }
  for (final item in care) {
    final id = _key('care', item['id']);
    if (!ids.add(id)) throw const FormatException('Duplicate legacy care id');
    final kind = _text(item['kind']);
    final title = _text(item['title']);
    final known = [
      'visit',
      'lab',
      'question',
      'sleep',
      'refill',
    ].contains(kind);
    final dated = _hasTime(item['time']);
    final at = dated
        ? _stamp(item['time'])
        : DateTime.now().toUtc().toIso8601String();
    final sleeping = kind == 'sleep' && dated && _hasTime(item['end']);
    final hours = sleeping
        ? DateTime.parse(
                _stamp(item['end']),
              ).difference(DateTime.parse(at)).inMinutes /
              60
        : 0.0;
    entries.add({
      'id': id,
      'tracker': sleeping || known && kind != 'sleep' ? kind : 'note',
      'revision': 1,
      'values': {'value': sleeping ? hours : title},
      'unit': sleeping ? 'h' : '',
      'at': at,
      'created': at,
      'source': 'legacy',
      'note': sleeping ? title : '',
      'context': item['done'] == true ? 'legacy_done' : '',
      'legacyUndated': !dated,
      if (item['alert'] == true) 'legacyCareAlert': true,
    });
  }
  final cup = prefs['cup'];
  final goal = prefs['waterGoal'];
  final unit = prefs['unit'];
  final volumeUnit = prefs['waterViewUnit'];
  final gd = prefs['glucoseViewDays'], wd = prefs['waterViewDays'];
  final context = _context(_text(prefs['glucoseViewContext']));
  return LegacyImport(
    entries,
    meds,
    doses,
    unscheduled: unscheduled,
    prefs: {
      if (goal is int && goal > 0 && goal <= 10000) 'waterGoal': goal,
      if (cup is int && cup > 0 && cup <= 10000) ...{
        'waterCups': {cup, ...defaultCups}.take(3).toList()..sort(),
        'waterDefaultCup': cup,
      },
      'unitPrefs': {
        if (['mg/dL', 'mmol/L'].contains(unit)) 'glucose': unit,
        if (['mL', 'L'].contains(volumeUnit)) 'water': volumeUnit,
      },
      'trackerViews': {
        if (summaryWindows.contains(gd))
          'glucose': {
            'mode': prefs['glucoseViewMetric'] == 'latest'
                ? 'latest'
                : 'average',
            'days': gd,
            'context': glucoseContexts.contains(context) ? context : '',
          },
        if (summaryWindows.contains(wd)) 'water': {'mode': 'total', 'days': wd},
      },
    },
  );
}

