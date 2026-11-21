import 'domain.dart';

const moodChoices = {
  'easy': ('رايق', 'At ease'),
  'steady': ('عادي', 'Steady'),
  'heavy': ('اليوم تقيل', 'A tough day'),
};

String? loggedMood(Iterable<JournalRow> entries, DateTime now) {
  DateTime? newest;
  String? choice;
  for (final entry in entries) {
    if (entry['tracker'] != 'mood' ||
        !moodChoices.containsKey(entry['moodTone']))
      continue;
    final at = DateTime.tryParse(entry['at']?.toString() ?? '')?.toLocal();
    if (at == null ||
        dayKey(at) != dayKey(now) ||
        at.isAfter(now) ||
        newest != null && !at.isAfter(newest))
      continue;
    newest = at;
    choice = entry['moodTone'] as String;
  }
  return choice;
}

String todayCopy(
  bool ar, {
  required int entries,
  required bool hasLate,
  String? mood,
  String? routine,
}) {
  if (hasLate)
    return mood == 'heavy'
        ? tr(
            ar,
            'خدها واحدة واحدة. في ميعاد فات ولسه مفيش تسجيل ليه.',
            'Take it one entry at a time. A past appointment still has no entry.',
          )
        : tr(
            ar,
            'في ميعاد فات ولسه مفيش تسجيل ليه. تقدر تراجعه من «دلوقتي».',
            'A past appointment still has no entry. You can review it below.',
          );
  return switch (mood) {
    'heavy' => tr(
      ar,
      'لو اليوم تقيل، سجّل أهم حاجة عندك دلوقتي.',
      'If today feels difficult, start with the entry that matters most.',
    ),
    'easy' => tr(
      ar,
      'سجّل اللي حابب تفتكره من يومك.',
      'Save what you’d like to remember from today.',
    ),
    _ when routine != null => routine,
    _ when entries == 0 => tr(
      ar,
      'ابدأ بأول تسجيل يهمّك النهارده.',
      'Start with the entry that matters today.',
    ),
    _ => tr(
      ar,
      'تسجيلات النهارده جاهزة تراجعها في أي وقت.',
      'Today’s entries are ready to review.',
    ),
  };
}

String? routineCopy(JournalRow state, DateTime now, bool ar) {
  if (!['auto', 'suggest'].contains(state['layoutLearning'])) return null;
  final active = cardPlan(state).toSet()
    ..remove('mood')
    ..remove('symptom');
  final first = DateTime(now.year, now.month, now.day - 6);
  final days = <String, Set<String>>{};
  for (final row in (state['entries'] as List? ?? []).cast<JournalRow>()) {
    final id = row['tracker'] as String;
    if (!active.contains(id) ||
        row['legacyUndated'] == true ||
        row['planned'] == true)
      continue;
    final at = eventTime(row);
    if (!at.isBefore(first) && !at.isAfter(now)) {
      days.putIfAbsent(id, () => <String>{}).add(dayKey(at));
    }
  }
  final sorted = days.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  final top = sorted.firstOrNull;
  if (top == null || top.value.length < 3) return null;
  final label = trackerFor(state, top.key)?.name(ar) ?? top.key;
  final count = top.value.length;
  return tr(
    ar,
    '$label · سجّلتها في $count أيام من آخر ٧ أيام.',
    '$label · Logged on $count of the last 7 days.',
  );
}

String agendaCopy(
  bool ar,
  DateTime due,
  DateTime now, {
  required bool dose,
  bool visit = false,
}) {
  final minutes = now.difference(due).inMinutes;
  if (due.isAfter(now)) {
    return due.difference(now) <= const Duration(minutes: 15)
        ? tr(ar, 'ميعاده قرب', 'Due soon')
        : tr(ar, 'لسه ميعاده مجاش', 'Coming up');
  }
  if (minutes == 0) return tr(ar, 'ميعاده دلوقتي', 'Due now');
  if (dose) {
    return minutes >= 60
        ? tr(
            ar,
            'ميعاد الجرعة فات ولسه مفيش تسجيل',
            'Dose time passed · no entry yet',
          )
        : tr(ar, 'ميعاد الجرعة عدى من شوية', 'Dose time just passed');
  }
  return visit
      ? tr(
          ar,
          'الميعاد عدى. راجع حالة المتابعة.',
          'Time passed · review follow-up',
        )
      : tr(ar, 'ميعاد التسجيل عدى', 'Logging time passed');
}
