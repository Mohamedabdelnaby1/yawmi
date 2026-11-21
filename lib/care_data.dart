import 'domain.dart';

int calendarSpan(DateTime from, DateTime through) =>
    DateTime.utc(
      through.year,
      through.month,
      through.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
    1;

typedef CareTrend = ({
  String unit,
  int count,
  int days,
  double first,
  double last,
  double mean,
  double? secondaryMean,
  double? secondaryLast,
  double low,
  double high,
  List<double> points,
});

CareTrend? careTrend(
  JournalRow state,
  String id,
  Iterable<JournalRow> entries,
) {
  final tracker = trackerFor(state, id);
  if (tracker == null ||
      tracker.kind != 'number' ||
      tracker.units.isEmpty ||
      ['water', 'sleep', 'activity'].contains(id))
    return null;
  final field = tracker.fields.first.id;
  final unit = displayUnit(state, tracker);
  final readings =
      entries
          .where(
            (row) =>
                row['tracker'] == id &&
                row['legacyUndated'] != true &&
                tracker.units.contains(row['unit']) &&
                row['values'] is Map &&
                row['values'][field] is num,
          )
          .toList()
        ..sort((a, b) => eventTime(a).compareTo(eventTime(b)));
  if (readings.isEmpty) return null;
  final points = [
    for (final row in readings)
      convert(id, (row['values'][field] as num).toDouble(), row['unit'], unit),
  ];
  final sorted = [...points]..sort();
  final secondary = [
    if (id == 'pressure')
      for (final row in readings)
        if (row['values']['diastolic'] case final num value) value,
  ];
  return (
    count: readings.length,
    days: readings.map((r) => dayKey(eventTime(r))).toSet().length,
    unit: unit,
    first: points.first,
    last: points.last,
    mean: points.reduce((a, b) => a + b) / points.length,
    secondaryMean: secondary.isEmpty
        ? null
        : secondary.reduce((a, b) => a + b) / secondary.length,
    secondaryLast: secondary.lastOrNull?.toDouble(),
    low: sorted.first,
    high: sorted.last,
    points: points,
  );
}

typedef DoseCoverage = ({int taken, int skipped, int unlogged, int scheduled});

DoseCoverage doseCoverage(
  JournalRow state,
  DateTime start,
  DateTime through, {
  int? fromHour,
  int? toHour,
  DateTime? clock,
}) {
  final now = clock ?? DateTime.now();
  final actual = <String, String>{
    for (final row in rows(state['doses']))
      for (final id in [row['id'], row['legacyDue']])
        if (id is String && ['taken', 'skipped'].contains(row['status']))
          id: row['status'],
  };
  var taken = 0, skipped = 0, unlogged = 0;
  final days = calendarSpan(start, through).clamp(0, 366);
  for (var i = 0; i < days; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    if (day.isAfter(now)) break;
    for (final dose in dosesOn(state, day)) {
      if (dose.time.isAfter(now) ||
          (fromHour != null && dose.time.hour < fromHour) ||
          (toHour != null && dose.time.hour >= toHour))
        continue;
      switch (actual[dose.id]) {
        case 'taken':
          taken++;
        case 'skipped':
          skipped++;
        default:
          unlogged++;
      }
    }
  }
  return (
    taken: taken,
    skipped: skipped,
    unlogged: unlogged,
    scheduled: taken + skipped + unlogged,
  );
}

const readingSources = {
  'manual': ('تسجيل يدوي', 'Manual'),
  'meter': ('جهاز قياس', 'Meter'),
  'cgm': ('مراقبة مستمرة', 'CGM'),
  'health-connect': ('Health Connect', 'Health Connect'),
};

String waterTrackingMode(JournalRow state) => switch (state['waterMode']) {
  'log' => 'log',
  'limit' => 'limit',
  'goal' => 'goal',
  _ => state['waterGoal'] is num ? 'goal' : 'log',
};

String readingSourceLabel(Object? source, bool ar) {
  final pair = readingSources[source];
  return pair == null
      ? tr(ar, 'غير محدد', 'Unspecified')
      : tr(ar, pair.$1, pair.$2);
}

JournalRow? readLabDetails(Object? raw) {
  if (raw is! Map ||
      raw['result'] is! num ||
      !(raw['result'] as num).isFinite ||
      raw['unit'] is! String ||
      (raw['unit'] as String).trim().isEmpty)
    return null;
  return {
    'result': raw['result'],
    'unit': (raw['unit'] as String).trim(),
    for (final key in ['laboratory', 'reference'])
      if (raw[key] is String) key: (raw[key] as String).trim(),
  };
}

const maxLabAttachmentBytes = 2 * 1024 * 1024;

String? labAttachmentFormat(List<int> bytes) {
  bool starts(List<int> prefix) =>
      bytes.length >= prefix.length &&
      prefix.indexed.every((pair) => bytes[pair.$1] == pair.$2);
  if (starts([0x25, 0x50, 0x44, 0x46, 0x2d])) return 'pdf';
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (starts([0xff, 0xd8, 0xff])) return 'jpg';
  return null;
}

List<JournalRow> healthImportRows(
  JournalRow state,
  List<Object?> records,
  DateTime now,
) {
  final seen = <String>{
    for (final row in (state['entries'] as List? ?? []))
      if (row is Map && row['sourceRecordId'] is String)
        row['sourceRecordId'] as String,
  };
  final result = <JournalRow>[];
  for (final raw in records) {
    if (raw is! Map) continue;
    final id = raw['sourceRecordId'];
    final tracker = raw['tracker'];
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    final values = raw['values'];
    final fields = switch (tracker) {
      'glucose' => ['value'],
      'pressure' => ['systolic', 'diastolic'],
      _ => <String>[],
    };
    if (id is! String ||
        !id.startsWith('health-connect:$tracker:') ||
        id.length > 180 ||
        at == null ||
        at.isAfter(now) ||
        fields.isEmpty ||
        values is! Map ||
        raw['unit'] != (tracker == 'glucose' ? 'mmol/L' : 'mmHg') ||
        !fields.every(
          (key) =>
              values[key] is num &&
              (values[key] as num).isFinite &&
              (values[key] as num) > 0,
        ) ||
        !seen.add(id))
      continue;
    result.add({
      'id': newId(),
      'tracker': tracker,
      'unit': raw['unit'],
      'at': at.toUtc().toIso8601String(),
      'created': now.toUtc().toIso8601String(),
      'values': {for (final key in fields) key: values[key]},
      'sourceRecordId': id,
      'readingSource': 'health-connect',
    });
  }
  return result;
}
