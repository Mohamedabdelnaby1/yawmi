import 'dart:math' as math;

import 'domain.dart';
import 'care_data.dart';

const repeatIntervals = [10, 15, 20, 30, 45, 60];
const waterIntervals = [30, 45, 60, 90, 120, 150, 180, 240];
const firstWaterDelays = [0, 15, 30, 60];
const routineModes = ['work', 'dayOff', 'travel'];
const plannedTrackers = {'visit', 'lab', 'refill'};
const reminderMatchWindow = Duration(minutes: 30);

bool isPlannedEntry(JournalRow row) {
  if (!plannedTrackers.contains(row['tracker'])) return false;
  if (row['planned'] is bool) return row['planned'] == true;
  final created = DateTime.tryParse(row['created'] as String? ?? '');
  return created != null && eventTime(row).isAfter(created);
}

String reminderOccurrence(String id, DateTime day) => '$id:${dayKey(day)}';

String? entryReminderOccurrence(JournalRow row) =>
    row['reminderOccurrence'] is String
    ? row['reminderOccurrence'] as String
    : null;

bool canCompleteTrackingReminder(JournalRow entry, DateTime day) =>
    entry['id'] is String &&
    entry['legacyUndated'] != true &&
    !isPlannedEntry(entry) &&
    (entry['at'] is String && DateTime.tryParse(entry['at']) != null) &&
    dayKey(eventTime(entry)) == dayKey(day);

/// Resolve each occurrence with one real entry. Explicit links get first
/// choice, then nearby readings are matched closest-first within the same day.
Map<String, String> trackingReminderMatches(
  JournalRow state,
  DateTime day, {
  Iterable<JournalRow>? schedules,
}) {
  final slots = <String, ({String tracker, DateTime at})>{
    for (final rule in schedules ?? trackingSchedules(state, false))
      if (rule['tracker'] case final String tracker)
        if (reminderTimeOn(rule, day) case final at?)
          reminderOccurrence(rule['id'], day): (tracker: tracker, at: at),
  };
  if (slots.isEmpty) return {};

  final entries = rows(
    state['entries'],
  ).where((entry) => canCompleteTrackingReminder(entry, day)).toList();
  final completed = <String, String>{};
  final used = <String>{};
  for (final entry in entries) {
    final key = entryReminderOccurrence(entry);
    if (key == null ||
        slots[key]?.tracker != entry['tracker'] ||
        completed.containsKey(key))
      continue;
    completed[key] = entry['id'];
    used.add(entry['id']);
  }

  final candidates =
      <
        ({String key, String id, Duration gap, DateTime due, DateTime entryAt})
      >[];
  for (final entry in entries) {
    if (used.contains(entry['id'])) continue;
    final at = eventTime(entry);
    for (final slot in slots.entries) {
      if (completed.containsKey(slot.key) ||
          slot.value.tracker != entry['tracker'])
        continue;
      final gap = at.difference(slot.value.at).abs();
      if (gap <= reminderMatchWindow) {
        candidates.add((
          key: slot.key,
          id: entry['id'],
          gap: gap,
          due: slot.value.at,
          entryAt: at,
        ));
      }
    }
  }
  candidates.sort((a, b) {
    final gap = a.gap.compareTo(b.gap);
    if (gap != 0) return gap;
    final time = a.due.compareTo(b.due);
    if (time != 0) return time;
    final entryOrder = a.entryAt.compareTo(b.entryAt);
    if (entryOrder != 0) return entryOrder;
    final ruleOrder = a.key.compareTo(b.key);
    return ruleOrder != 0 ? ruleOrder : a.id.compareTo(b.id);
  });
  for (final candidate in candidates) {
    if (!completed.containsKey(candidate.key) && used.add(candidate.id)) {
      completed[candidate.key] = candidate.id;
    }
  }
  return completed;
}

typedef ReminderRepeat = ({int count, int minutes});
typedef WaterSlot = ({int minute, int shift, int untilSleep});

ReminderRepeat readRepeat(Object? raw) {
  final rule = raw is Map ? raw : const {};
  final count = rule['count'], period = rule['minutes'];
  return (
    count: count is int && count >= 0 && count <= 3 ? count : 0,
    minutes: period is int && repeatIntervals.contains(period) ? period : 15,
  );
}

List<int> reminderMinutes(JournalRow rule) {
  final raw = rule['times'];
  final candidates = raw is List && raw.isNotEmpty ? raw : [rule['minute']];
  return candidates
      .whereType<int>()
      .where((n) => n >= 0 && n < 1440)
      .toSet()
      .take(12)
      .toList()
    ..sort();
}

int minutesUntilNextSlot(List<int> times, int minute) {
  var next = times.reduce(math.min) + 1440;
  for (final time in times) {
    if (time > minute) next = math.min(next, time);
  }
  return next - minute;
}

Iterable<JournalRow> _trackerSlots(JournalRow rule) sync* {
  final times = reminderMinutes(rule);
  for (final minute in times) {
    yield {
      ...rule,
      'groupId': rule['id'],
      'id': times.length == 1 ? rule['id'] : "${rule['id']}@$minute",
      'minute': minute,
      if (times.length > 1) 'maxDelay': minutesUntilNextSlot(times, minute),
    };
  }
}

List<WaterSlot> waterSlots(int wake, int sleep, int interval, int first) {
  if (wake < 0 ||
      wake >= 1440 ||
      sleep < 0 ||
      sleep >= 1440 ||
      !waterIntervals.contains(interval) ||
      !firstWaterDelays.contains(first))
    return [];
  final duration = (sleep - wake + 1440) % 1440;
  return [
    for (var passed = first; passed < duration; passed += interval)
      (
        minute: (wake + passed) % 1440,
        shift: (wake + passed) ~/ 1440,
        untilSleep: math.min(duration - passed, interval),
      ),
  ];
}

List<JournalRow> trackingSchedules(JournalRow state, bool ar) {
  final water = state['waterReminder'];
  final slots =
      water is Map &&
          waterTrackingMode(state) != 'limit' &&
          water['enabled'] == true &&
          water['wake'] is int &&
          water['sleep'] is int &&
          water['interval'] is int &&
          water['first'] is int
      ? waterSlots(
          water['wake'],
          water['sleep'],
          water['interval'],
          water['first'],
        )
      : const <WaterSlot>[];
  final schedules = <JournalRow>[
    for (final rule in rows(
      state['reminders'],
    ).where((row) => row['enabled'] == true))
      ..._trackerSlots(rule),
    if (water is Map && water['days'] is List)
      for (final slot in slots)
        {
          'id': "water-plan@${slot.minute}",
          'tracker': 'water',
          'minute': slot.minute,
          'name': tr(ar, 'اشرب مياه', 'Drink water'),
          'days': [
            for (final day in (water['days'] as List).whereType<int>().where(
              allDays.contains,
            ))
              (day - 1 + slot.shift) % 7 + 1,
          ],
          'enabled': true,
          'waterPlan': true,
          'maxDelay': slot.untilSleep,
          'repeat': water['repeat'],
          'effective': water['effective'],
        },
  ];
  final override = state['routineMode'];
  if (override is! Map || !routineModes.contains(override['id']))
    return schedules;
  final shift = override['shift'];
  final start = override['start'];
  final end = override['end'];
  if (shift is! int ||
      shift == 0 ||
      shift.abs() > 180 ||
      start is! String ||
      end is! String)
    return schedules;
  return [
    for (final rule in schedules)
      if (rule['waterPlan'] == true ||
          ['suggest', 'auto'].contains(rule['learn']))
        {...rule, 'shiftMinutes': shift, 'shiftStart': start, 'shiftEnd': end}
      else
        rule,
  ];
}

int reminderMinuteOn(JournalRow rule, String date, int base) {
  final start = rule['shiftStart'];
  final end = rule['shiftEnd'];
  final shift = rule['shiftMinutes'];
  if (shift is! int ||
      start is! String ||
      end is! String ||
      date.compareTo(start) < 0 ||
      date.compareTo(end) > 0)
    return base;
  final candidate = base + shift;
  return candidate >= 0 && candidate < 1440 ? candidate : base;
}

DateTime? reminderTimeOn(JournalRow rule, DateTime day) {
  final date = dayKey(day);
  final minute = rule['minute'];
  if (rule['enabled'] != true ||
      minute is! int ||
      minute < 0 ||
      minute >= 1440 ||
      !ints(rule['days']).contains(day.weekday) ||
      (rule['start'] is String && date.compareTo(rule['start']) < 0) ||
      (rule['end'] is String && date.compareTo(rule['end']) > 0))
    return null;
  final adjusted = reminderMinuteOn(rule, date, minute);
  final at = DateTime(
    day.year,
    day.month,
    day.day,
    adjusted ~/ 60,
    adjusted % 60,
  );
  final effective = DateTime.tryParse(rule['effective'] as String? ?? '');
  return effective != null && at.isBefore(effective) ? null : at;
}
