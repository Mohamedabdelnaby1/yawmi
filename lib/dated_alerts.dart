import 'domain.dart';
import 'reminder_schedule.dart';

const alertLeadDays = [30, 14, 7, 3, 1, 0];
const stockRepeatDays = [0, 1, 2, 3, 7, 14];

DateTime? parseCalendarDate(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final date = DateTime.tryParse(raw);
  return date != null && dayKey(date) == raw ? date : null;
}

DateTime shiftCalendarDate(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

int calendarDaysUntil(DateTime date, DateTime now) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

int readAlertMinute(Object? value) =>
    value is int && value >= 0 && value < 1440 ? value : 9 * 60;

int readStockInterval(Object? value) =>
    value is int && stockRepeatDays.contains(value) ? value : 0;

List<int> readAlertLeadDays(Object? value) => value is List
    ? alertLeadDays.where(value.contains).toList()
    : const [7, 1, 0];

class DateAlert {
  const DateAlert({
    required this.date,
    required this.minute,
    required this.leads,
    required this.armed,
    required this.armedAt,
    required this.repeat,
  });

  final DateTime date;
  final int minute;
  final List<int> leads;
  final bool armed;
  final DateTime? armedAt;
  final ReminderRepeat repeat;

  static DateAlert? read(Object? raw) {
    if (raw is! Map) return null;
    final date = parseCalendarDate(raw['date']);
    if (date == null) return null;
    return DateAlert(
      date: date,
      minute: readAlertMinute(raw['minute']),
      leads: readAlertLeadDays(raw['leads']),
      armed: raw['armed'] == true,
      armedAt: DateTime.tryParse(raw['armedAt']?.toString() ?? ''),
      repeat: readRepeat(raw['repeat']),
    );
  }

  JournalRow toRow({bool pause = false}) => {
    'date': dayKey(date),
    'minute': minute,
    'leads': leads,
    'armed': armed && !pause,
    'armedAt': armedAt?.toUtc().toIso8601String(),
    'repeat': {'count': repeat.count, 'minutes': repeat.minutes},
  };
}

Iterable<JournalRow> dateAlertRules(
  DateAlert alert, {
  required String id,
  required String title,
  required String route,
  required DateTime now,
}) sync* {
  if (!alert.armed) return;
  for (final lead in alert.leads) {
    final day = shiftCalendarDate(alert.date, -lead);
    if (calendarDaysUntil(day, now) < -1) continue;
    yield {
      'id': '$id:${dayKey(alert.date)}:$lead',
      'start': dayKey(day),
      'end': dayKey(day),
      'days': allDays,
      'minute': alert.minute,
      'graceMinutes': 480,
      'maxDelay': 1440 - alert.minute,
      'effective': alert.armedAt?.toUtc().toIso8601String(),
      'type': 'tracking',
      'title': title,
      'route': route,
      'repeat': {'count': alert.repeat.count, 'minutes': alert.repeat.minutes},
    };
  }
}

List<JournalRow> pendingFollowUps(JournalRow state) =>
    rows(state['followUps']).where((row) => row['completedAt'] == null).toList()
      ..sort(
        (a, b) => (a['alert']['date'] as String).compareTo(
          b['alert']['date'] as String,
        ),
      );
