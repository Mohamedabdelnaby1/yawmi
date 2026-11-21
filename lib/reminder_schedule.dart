import 'dart:math' as math;

import 'domain.dart';
import 'care_data.dart';

const repeatIntervals = [10, 15, 20, 30, 45, 60];
const waterIntervals = [30, 45, 60, 90, 120, 150, 180, 240];
const firstWaterDelays = [0, 15, 30, 60];

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
  return [
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
}
