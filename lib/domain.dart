import 'dart:math' as math;
import 'package:intl/intl.dart';

String tr(bool ar, String arabic, String english) => ar ? arabic : english;
String dayKey(DateTime t) => t.toIso8601String().split('T').first;
String clockText(int minute) => [
  (minute ~/ 60).toString().padLeft(2, '0'),
  (minute % 60).toString().padLeft(2, '0'),
].join(':');
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(0x7fffffff)}';
String normalize(String input) {
  const digits = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  return input
      .replaceAllMapped(
        RegExp('[٠-٩۰-۹]'),
        (m) => (digits.indexOf(m[0]!) % 10).toString(),
      )
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll(RegExp('[ً-ٟـ]'), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}

double? readNumber(String value) {
  final n = double.tryParse(
    normalize(value).replaceAll('٫', '.').replaceAll(',', '.'),
  );
  return n != null && n.isFinite ? n : null;
}

String number(double n) => NumberFormat('0.##', 'en').format(n);
typedef JournalRow = Map<String, dynamic>;
List<String> strings(Object? value) =>
    (value as List? ?? []).cast<String>().toList();
List<JournalRow> rows(Object? value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
List<int> ints(Object? value) => (value as List? ?? []).cast<int>().toList();
const allDays = [1, 2, 3, 4, 5, 6, 7];

class FieldSpec {
  final String id, ar, en;
  final bool optional;
  const FieldSpec(this.id, this.ar, this.en, {this.optional = false});
  String name(bool arabic) => tr(arabic, ar, en);
}

class Tracker {
  final String id, ar, en;
  final List<String> units;
  final List<FieldSpec> fields;
  final String kind;
  const Tracker(
    this.id,
    this.ar,
    this.en,
    this.units, {
    this.fields = const [FieldSpec('value', 'القيمة', 'Value')],
    this.kind = 'number',
  });
  String name(bool arabic) => tr(arabic, ar, en);
}

const trackers = <Tracker>[
  Tracker(
    'pressure',
    'ضغط الدم',
    'Blood pressure',
    ['mmHg'],
    fields: [
      FieldSpec('systolic', 'الانقباضي', 'Systolic'),
      FieldSpec('diastolic', 'الانبساطي', 'Diastolic'),
      FieldSpec('pulse', 'النبض · bpm', 'Pulse · bpm', optional: true),
    ],
  ),
  Tracker('glucose', 'سكر الدم', 'Blood glucose', ['mg/dL', 'mmol/L']),
  Tracker('water', 'المياه', 'Water', ['mL', 'L']),
  Tracker('sleep', 'النوم', 'Sleep', ['h', 'min']),
  Tracker('pulse', 'النبض', 'Heart rate', ['bpm']),
  Tracker('weight', 'الوزن', 'Weight', ['kg', 'lb']),
  Tracker('temperature', 'الحرارة', 'Temperature', ['°C', '°F']),
  Tracker('oxygen', 'تشبع الأكسجين', 'Blood oxygen', ['%']),
  Tracker('peak_flow', 'ذروة تدفق الزفير', 'Peak flow', ['L/min']),
  Tracker('pain', 'الألم', 'Pain', ['0–10']),
  Tracker('activity', 'النشاط', 'Activity', ['min']),
  Tracker('a1c', 'السكر التراكمي', 'HbA1c', ['%']),
  Tracker('meal', 'الوجبات', 'Meals', [], kind: 'text'),
  Tracker('mood', 'المزاج', 'Mood', [], kind: 'text'),
  Tracker('cycle', 'الدورة الشهرية', 'Menstrual cycle', [], kind: 'text'),
  Tracker('visit', 'الزيارات', 'Visits', [], kind: 'text'),
  Tracker('lab', 'التحاليل', 'Lab records', [], kind: 'text'),
  Tracker(
    'question',
    'أسئلة للطبيب',
    'Questions for your clinician',
    [],
    kind: 'text',
  ),
  Tracker('refill', 'إعادة صرف الدواء', 'Medication refills', [], kind: 'text'),
  Tracker('symptom', 'الأعراض', 'Symptoms', [], kind: 'symptom'),
  Tracker('note', 'الملاحظات', 'Notes', [], kind: 'text'),
];
const medicineCard = 'medicine';

double convert(String tracker, double n, String from, String to) {
  if (from == to) return n;
  return switch (tracker) {
    'glucose' => from == 'mmol/L' ? n * 18.0182 : n / 18.0182,
    'weight' => from == 'lb' ? n * 0.45359237 : n / 0.45359237,
    'temperature' => from == '°F' ? (n - 32) * 5 / 9 : n * 9 / 5 + 32,
    'sleep' => from == 'min' ? n / 60 : n * 60,
    'water' => from == 'L' ? n * 1000 : n / 1000,
    _ => n,
  };
}

JournalRow freshState() => {
  'version': 1,
  'stage': 0,
  'conditions': <JournalRow>[],
  'enabled': <String>[],
  'hidden': <String>[],
  'pinned': <String>[],
  'order': <String>[],
  'custom': <JournalRow>[],
  'entries': <JournalRow>[],
  'meds': <JournalRow>[],
  'doses': <JournalRow>[],
  'reminders': <JournalRow>[],
  'followUps': <JournalRow>[],
  'widgets': <JournalRow>[],
  'recent': <String>[],
  'unitPrefs': <String, String>{},
  'trackerViews': <String, JournalRow>{},
  'learning': <String, dynamic>{},
  'theme': 'system',
  'reduce': false,
  'language': 'system',
  'startSection': 'tracking',
  'setupAuto': <String>[],
};

Tracker? trackerFor(JournalRow state, String id) {
  for (final t in trackers) {
    if (t.id == id) return t;
  }
  for (final t in rows(state['custom'])) {
    if (t['id'] == id) {
      final unit = t['unit'] as String? ?? '';
      return Tracker(id, t['name'], t['name'], [
        if (unit.isNotEmpty) unit,
      ], kind: t['kind']);
    }
  }
  return null;
}

List<Tracker> allTrackers(JournalRow state) => [
  ...trackers,
  for (final e in rows(state['custom']))
    if (trackerFor(state, e['id']) case final Tracker t) t,
];

List<String> cardPlan(JournalRow state, [JournalRow? config]) {
  final prefs = config ?? state;
  final allowed = <String>{
    ...strings(prefs['enabled']),
    if (config?['automatic'] == true)
      ...cardPlan(state).where((id) {
        final focus = config?['condition'] as String?;
        if (focus == null || focus.isEmpty) return true;
        final condition = rows(
          state['conditions'],
        ).where((c) => c['id'] == focus && c['archived'] != true).firstOrNull;
        return condition != null && strings(condition['links']).contains(id);
      }),
  };
  allowed.removeAll(strings(prefs['hidden']));
  return {
    ...strings(prefs['pinned']).where(allowed.contains),
    ...strings(prefs['order']).where(allowed.contains),
    ...allowed,
  }.where((id) => id == medicineCard || trackerFor(state, id) != null).toList();
}

List<String> quickPins(JournalRow state) {
  final active = cardPlan(state).toSet();
  return strings(
    state['quickPins'],
  ).where(active.contains).toSet().take(3).toList();
}

DateTime eventTime(JournalRow row) =>
    DateTime.parse(row['at'] as String).toLocal();
List<JournalRow> entriesFor(JournalRow state, String id) => [
  for (final item in _orderedEntries(state, id))
    Map<String, dynamic>.of(item.row),
];

List<({JournalRow row, DateTime stamp})> _orderedEntries(
  JournalRow state,
  String id, {
  DateTime? before,
  String context = '',
}) {
  final matches = <({JournalRow row, DateTime stamp})>[];
  for (final row in (state['entries'] as List? ?? []).cast<JournalRow>()) {
    if (row['tracker'] != id ||
        (context.isNotEmpty && row['context'] != context))
      continue;
    final stamp = eventTime(row);
    if (before == null || !stamp.isAfter(before))
      matches.add((row: row, stamp: stamp));
  }
  return matches..sort((a, b) => b.stamp.compareTo(a.stamp));
}

String displayUnit(JournalRow state, Tracker t) =>
    (state['unitPrefs'] as Map? ?? {})[t.id] as String? ??
    t.units.firstOrNull ??
    '';

String valueText(JournalRow entry, bool ar) {
  final values = entry['values'] as Map;
  if (entry['tracker'] == 'pressure') {
    return [
      values['systolic'],
      values['diastolic'],
    ].map((n) => number((n as num).toDouble())).join('/');
  }
  if (values['value'] is num) {
    return number((values['value'] as num).toDouble());
  }
  if (values['value'] is bool) {
    return values['value'] == true ? tr(ar, 'نعم', 'Yes') : tr(ar, 'لا', 'No');
  }
  return (values['value'] ?? '').toString();
}

String entryContext(Object? code, bool ar) => switch (code) {
  'fasting' => tr(ar, 'صايم', 'Fasting'),
  'before meal' => tr(ar, 'قبل الأكل', 'Before meal'),
  'after meal' => tr(ar, 'بعد الأكل', 'After meal'),
  'not_fasting' => tr(ar, 'غير صايم', 'Not fasting'),
  'legacy_done' => tr(ar, 'مكتمل', 'Completed'),
  'mild' => tr(ar, 'خفيف', 'Mild'),
  'moderate' => tr(ar, 'متوسط', 'Moderate'),
  'severe' => tr(ar, 'شديد', 'Severe'),
  String text => text,
  _ => '',
};
List<JournalRow> inPeriod(List<JournalRow> data, DateTime now, int days) {
  final start = DateTime(now.year, now.month, now.day - days + 1);
  final end = DateTime(now.year, now.month, now.day + 1);
  return data.where((row) {
    final at = eventTime(row);
    return (days == 0 || !at.isBefore(start)) && at.isBefore(end);
  }).toList();
}

double? average(List<JournalRow> entries, Tracker t, String unit) {
  final values = entries
      .where((e) => (e['values'] as Map)['value'] is num)
      .map(
        (e) => convert(
          t.id,
          ((e['values'] as Map)['value'] as num).toDouble(),
          e['unit'],
          unit,
        ),
      )
      .toList();
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

double waterTotal(JournalRow state, DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  final end = DateTime(date.year, date.month, date.day + 1);
  var total = 0.0;
  for (final row in (state['entries'] as List? ?? []).cast<JournalRow>()) {
    if (row['tracker'] != 'water') continue;
    final at = eventTime(row);
    if (!at.isBefore(start) && at.isBefore(end)) {
      total += convert(
        'water',
        (row['values']['value'] as num).toDouble(),
        row['unit'],
        'mL',
      );
    }
  }
  return total;
}

const summaryWindows = [1, 7, 14, 30, 90, 0];
const glucoseContexts = ['fasting', 'not_fasting', 'before meal', 'after meal'];
const defaultCups = [125, 250, 500];

List<String> trackerViewModes(Tracker tracker) => switch (tracker.id) {
  'water' => ['total'],
  'sleep' => ['latest', 'average', 'total'],
  _ when tracker.kind == 'number' => ['latest', 'average'],
  _ => ['latest', 'count'],
};

typedef TrackerView = ({
  String mode,
  int days,
  String context,
  bool secondary,
  bool doseSummary,
});

TrackerView trackerView(
  JournalRow state,
  Tracker tracker, {
  bool widgetAverage = false,
}) {
  final stored = (state['trackerViews'] as Map?)?[tracker.id] as Map? ?? {};
  final modes = trackerViewModes(tracker);
  final legacy =
      widgetAverage ||
      (tracker.id == 'glucose' && state['glucoseAverage'] == true);
  final mode = modes.contains(stored['mode'])
      ? stored['mode'] as String
      : tracker.id == 'glucose' || legacy && modes.contains('average')
      ? 'average'
      : modes.first;
  final days = summaryWindows.contains(stored['days'])
      ? stored['days'] as int
      : tracker.id == 'water'
      ? 1
      : legacy
      ? 7
      : tracker.id == 'glucose'
      ? 30
      : 7;
  final context =
      tracker.id == 'glucose' && glucoseContexts.contains(stored['context'])
      ? stored['context'] as String
      : '';
  return (
    mode: mode,
    days: days,
    context: context,
    secondary: stored['secondary'] != false,
    doseSummary: tracker.id == 'glucose' && stored['doseSummary'] != false,
  );
}

List<JournalRow> trackerViewEntries(
  JournalRow state,
  Tracker tracker,
  DateTime now,
  TrackerView view,
) => [
  for (final item in _orderedEntries(
    state,
    tracker.id,
    before: now,
    context: view.context,
  ))
    Map<String, dynamic>.of(item.row),
];

List<int> waterCups(JournalRow state) {
  final values = ints(state['waterCups']);
  return values.length == 3 &&
          values.toSet().length == 3 &&
          values.every((ml) => ml > 0 && ml <= 10000)
      ? values
      : defaultCups;
}

int defaultWaterCup(JournalRow state) {
  final values = waterCups(state);
  final selected = state['waterDefaultCup'];
  return values.contains(selected) ? selected as int : values[1];
}

const doseMeals = {
  'breakfast': ('الفطار', 'Breakfast'),
  'lunch': ('الغدا', 'Lunch'),
  'dinner': ('العشا', 'Dinner'),
};

const doseMealRelations = {
  'before': ('قبل الوجبة', 'Before meal'),
  'with': ('مع الوجبة', 'With meal'),
  'after': ('بعد الوجبة', 'After meal'),
};

Map<String, String>? readDoseMeal(Object? raw) {
  if (raw is! Map) return null;
  final meal = raw['meal'], relation = raw['relation'];
  if (meal is! String ||
      relation is! String ||
      !doseMeals.containsKey(meal) ||
      !doseMealRelations.containsKey(relation)) {
    return null;
  }
  return {'meal': meal, 'relation': relation};
}

Map<String, Map<String, String>> readDoseMeals(
  Object? raw,
  Iterable<int> times,
) {
  if (raw is! Map) return {};
  return {
    for (final minute in times)
      if (readDoseMeal(raw['$minute']) case final rule?) '$minute': rule,
  };
}

String? doseMealLabel(Object? raw, bool ar) {
  final rule = readDoseMeal(raw);
  if (rule == null) return null;
  final meal = doseMeals[rule['meal']]!;
  final relation = doseMealRelations[rule['relation']]!;
  return '${tr(ar, meal.$1, meal.$2)} · ${tr(ar, relation.$1, relation.$2)}';
}

class Dose {
  final JournalRow medicine;
  final DateTime time;
  final int minute;
  final String id;
  Map<String, String>? get mealSlot {
    final slots = medicine['mealSlots'];
    return slots is Map ? readDoseMeal(slots['$minute']) : null;
  }

  Dose(this.medicine, this.time, this.minute)
    : id = [
        medicine['id'],
        medicine['revision'],
        dayKey(time),
        minute,
      ].join(':');
}

List<Dose> dosesOn(JournalRow state, DateTime date) {
  final day = dayKey(date);
  final result = <Dose>[];
  for (final med in rows(state['meds'])) {
    if (med['archived'] == true || !ints(med['days']).contains(date.weekday)) {
      continue;
    }
    if (day.compareTo(med['start'] as String) < 0 ||
        (med['end'] != null && day.compareTo(med['end'] as String) > 0)) {
      continue;
    }
    for (final minute in ints(med['times'])) {
      final due = DateTime(
        date.year,
        date.month,
        date.day,
        minute ~/ 60,
        minute % 60,
      );
      if (med['effective'] != null &&
          due.isBefore(DateTime.parse(med['effective']))) {
        continue;
      }
      result.add(Dose(med, due, minute));
    }
  }
  return result..sort((a, b) => a.time.compareTo(b.time));
}

JournalRow? doseEvent(JournalRow state, String id) => rows(
  state['doses'],
).where((e) => e['id'] == id || e['legacyDue'] == id).firstOrNull;
List<Dose> outstanding(JournalRow state, DateTime date) {
  final scheduled = dosesOn(state, date);
  if (scheduled.isEmpty) return scheduled;
  final resolved = <String>{};
  for (final row in (state['doses'] as List? ?? []).cast<JournalRow>()) {
    if (row['id'] case final String id) resolved.add(id);
    if (row['legacyDue'] case final String id) resolved.add(id);
  }
  return scheduled.where((dose) => !resolved.contains(dose.id)).toList();
}

int circularDistance(int a, int b) {
  final gap = (a - b).abs();
  return math.min(gap, 1440 - gap);
}

({String tracker, int count, List<String> order})? proposeLayout(
  JournalRow state,
  JournalRow prefs,
  DateTime now, {
  bool widget = false,
}) {
  if (prefs['layoutLearning'] == null || prefs['layoutLearning'] == 'off') {
    return null;
  }
  final started = DateTime.tryParse(state['learningReset'] ?? '');
  final lastDecision = DateTime.tryParse(prefs['layoutDecision'] ?? '');
  if (lastDecision != null &&
      now.difference(lastDecision) < const Duration(days: 14)) {
    return null;
  }
  final pinned = strings(prefs['pinned']);
  final order = cardPlan(
    state,
    widget ? prefs : null,
  ).where((id) => !pinned.contains(id)).toList();
  final seen = <String, Set<String>>{};
  for (final reading in inPeriod(rows(state['entries']), now, 21)) {
    if (reading['source'] == 'legacy') continue;
    final id = reading['tracker'] as String;
    if (!order.contains(id)) continue;
    final at = eventTime(reading);
    final saved = DateTime.parse(reading['created'] as String).toLocal();
    if (started != null && saved.isBefore(started)) continue;
    if (reading['zone'] != null && reading['zone'] != now.timeZoneName) {
      continue;
    }
    final gap = saved.difference(at);
    if (gap.isNegative || gap > const Duration(hours: 2)) continue;
    if (circularDistance(at.hour * 60 + at.minute, now.hour * 60 + now.minute) >
        240) {
      continue;
    }
    (seen[id] ??= {}).add(dayKey(at));
  }
  for (var i = 1; i < order.length; i++) {
    final current = order[i];
    final count = seen[current]?.length ?? 0;
    if (count >= 7 && count >= (seen[order[i - 1]]?.length ?? 0) + 3) {
      order[i] = order[i - 1];
      order[i - 1] = current;
      return (tracker: current, count: count, order: order);
    }
  }
  return null;
}

typedef RoutinePattern = ({int minute, int matchedDays, int sampleDays});

RoutinePattern? learnedRoutine(
  List<JournalRow> entries,
  DateTime now, {
  int start = 0,
  int end = 1439,
  DateTime? since,
}) {
  final days = <String, Set<int>>{};
  final candidates = <int>{};
  bool inWindow(int m) =>
      start <= end ? m >= start && m <= end : m >= start || m <= end;
  for (final e in inPeriod(entries, now, 21)) {
    if (e['source'] == 'legacy') continue;
    final at = eventTime(e);
    final created = DateTime.parse(e['created'] as String).toLocal();
    if (at.isAfter(now) || (since != null && created.isBefore(since))) continue;
    if (e['zone'] != null && e['zone'] != now.timeZoneName) continue;
    final delay = created.difference(at);
    if (delay.isNegative || delay > const Duration(hours: 2)) continue;
    final minute = at.hour * 60 + at.minute;
    days.putIfAbsent(dayKey(at), () => <int>{}).add(minute);
    if (inWindow(minute)) candidates.add(minute);
  }
  if (days.length < 7) return null;
  var count = 0, best = 0, bestSum = 0;
  for (final candidate in candidates.toList()..sort()) {
    var nearby = 0, total = 0;
    for (final minutes in days.values) {
      var gap = 46;
      for (final minute in minutes) {
        if (inWindow(minute))
          gap = math.min(gap, circularDistance(minute, candidate));
      }
      if (gap <= 45) {
        nearby++;
        total += gap;
      }
    }
    if (nearby > count || (nearby == count && total < bestSum)) {
      count = nearby;
      best = candidate;
      bestSum = total;
    }
  }
  if (count < 7 || count * 3 < days.length * 2) return null;
  return (minute: best, matchedDays: count, sampleDays: days.length);
}

(int, int)? proposeTime(
  List<JournalRow> entries,
  DateTime now,
  int current,
  int start,
  int end, {
  DateTime? since,
}) {
  final pattern = learnedRoutine(
    entries,
    now,
    start: start,
    end: end,
    since: since,
  );
  return pattern == null || circularDistance(pattern.minute, current) < 30
      ? null
      : (pattern.minute, pattern.matchedDays);
}

int? automaticReminderMinute(JournalRow reminder, int suggested, DateTime now) {
  if (reminder['learn'] != 'auto' ||
      reminder['flexible'] != true ||
      reminder['enabled'] != true ||
      reminder['tracker'] == null)
    return null;
  final last = DateTime.tryParse(reminder['changedAt'] ?? '');
  if (last != null && now.difference(last) < const Duration(days: 7))
    return null;
  final current = reminder['minute'] as int;
  if (circularDistance(current, suggested) < 30) return null;
  final direction = ((suggested - current + 2160) % 1440) - 720;
  final next = (current + direction.clamp(-15, 15) + 1440) % 1440;
  final low = reminder['low'] as int, high = reminder['high'] as int;
  final withinWindow = low <= high
      ? next >= low && next <= high
      : next >= low || next <= high;
  return withinWindow ? next : null;
}

class MedicationStock {
  const MedicationStock({
    required this.cycle,
    required this.countedAt,
    required this.count,
    required this.perDose,
    required this.threshold,
    required this.notify,
    this.repeatDays = 0,
    this.repeatMinute = 540,
    this.alertsEnabledAt,
  });

  final String cycle;
  final DateTime countedAt;
  final double count, perDose, threshold;
  final bool notify;
  final int repeatDays, repeatMinute;
  final DateTime? alertsEnabledAt;

  static MedicationStock? read(Object? raw) {
    if (raw is! Map) return null;
    final cycle = raw['cycle'];
    final countedAt = DateTime.tryParse(
      raw['countedAt'] is String ? raw['countedAt'] : '',
    );
    final count = raw['count'],
        perDose = raw['perDose'],
        threshold = raw['threshold'];
    bool amount(Object? v) =>
        v is num && v.isFinite && v >= 0 && v <= 100000000;
    if (cycle is! String ||
        cycle.isEmpty ||
        countedAt == null ||
        !amount(count) ||
        !amount(perDose) ||
        (perDose as num) <= 0 ||
        !amount(threshold)) {
      return null;
    }
    return MedicationStock(
      cycle: cycle,
      countedAt: countedAt,
      count: (count as num).toDouble(),
      perDose: perDose.toDouble(),
      threshold: (threshold as num).toDouble(),
      notify: raw['notify'] == true,
      repeatDays: raw['repeatDays'] is int ? raw['repeatDays'] : 0,
      repeatMinute: raw['repeatMinute'] is int ? raw['repeatMinute'] : 540,
      alertsEnabledAt: DateTime.tryParse(
        raw['alertsEnabledAt']?.toString() ?? '',
      ),
    );
  }

  JournalRow toRow() => {
    'cycle': cycle,
    'countedAt': countedAt.toUtc().toIso8601String(),
    'count': count,
    'perDose': perDose,
    'threshold': threshold,
    'notify': notify,
    'repeatDays': repeatDays,
    'repeatMinute': repeatMinute,
    if (alertsEnabledAt != null)
      'alertsEnabledAt': alertsEnabledAt!.toUtc().toIso8601String(),
  };
}

typedef StockBalance = ({
  MedicationStock stock,
  double remaining,
  DateTime updatedAt,
  DateTime? lowSince,
});

StockBalance? medicationStockBalance(
  JournalRow med,
  Iterable<JournalRow> doses,
) {
  final stock = MedicationStock.read(med['inventory']);
  if (stock == null) return null;
  var used = 0.0;
  var updated = stock.countedAt;
  final consumption = <({num amount, DateTime at})>[];
  for (final dose in doses) {
    final amount = dose['stockUsed'];
    if (dose['medicine'] != med['id'] ||
        dose['stockCycle'] != stock.cycle ||
        dose['status'] != 'taken' ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0)
      continue;
    used += amount;
    final changed = DateTime.tryParse(dose['stockChangedAt'] as String? ?? '');
    if (changed != null && changed.isAfter(updated)) updated = changed;
    consumption.add((amount: amount, at: changed ?? stock.countedAt));
  }
  final remaining = math.max(
    0.0,
    double.parse((stock.count - used).toStringAsFixed(4)),
  );
  DateTime? lowSince;
  if (remaining <= stock.threshold) {
    lowSince = stock.countedAt;
    if (stock.count > stock.threshold) {
      consumption.sort((a, b) => a.at.compareTo(b.at));
      var deducted = 0.0;
      for (final dose in consumption) {
        deducted += dose.amount;
        if (double.parse((stock.count - deducted).toStringAsFixed(4)) <=
            stock.threshold) {
          lowSince = dose.at;
          break;
        }
      }
    }
  }
  return (
    stock: stock,
    remaining: remaining,
    updatedAt: updated,
    lowSince: lowSince,
  );
}

JournalRow doseWithInventory(
  JournalRow dose,
  JournalRow medicine,
  DateTime stamp,
) {
  final stock = MedicationStock.read(medicine['inventory']);
  return {
    ...dose,
    if (stock != null) ...{
      'stockCycle': stock.cycle,
      'stockUsed': stock.perDose,
      'stockChangedAt': stamp.toUtc().toIso8601String(),
    },
  };
}
