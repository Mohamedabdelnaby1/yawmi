part of 'main.dart';

extension _Adaptive on _HomeState {
  Future<void> _adaptiveSettings() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final discover = data['discoverReminders'] == true;
        final reminders = rows(data['reminders']);
        final history = rows(data['adaptiveHistory']);
        final suggestions = discover
            ? _discoveredRoutines()
            : <(Tracker, RoutinePattern)>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(t('التكيّف مع روتينك', 'Adaptive routine')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              _FieldBanner(
                title: t('روتينك بيتغيّر', 'A routine that adapts'),
                detail: t('التعلّم على الجهاز', 'On-device learning'),
                accent: mint,
                bottom: Row(
                  children: [
                    Expanded(
                      child: _FieldMetric(
                        value: '${suggestions.length}',
                        label: t('اقتراحات حالية', 'Current suggestions'),
                        icon: Icons.tips_and_updates_outlined,
                        accent: leaf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FieldMetric(
                        value:
                            '${reminders.where((r) => r['enabled'] == true && r['learn'] == 'auto').length}',
                        label: t('تذكيرات مرنة بتتكيّف', 'Adaptive reminders'),
                        icon: Icons.alarm_outlined,
                        accent: honey,
                      ),
                    ),
                  ],
                ),
              ),
              SectionTitle(t('الاقتراحات', 'Suggestions')),
              ControlCard(
                icon: Icons.tips_and_updates_outlined,
                tonalColor: honey,
                title: t(
                  'اقترح تذكيرات من روتيني',
                  'Suggest reminders from my routine',
                ),
                subtitle: t(
                  'يظهر اقتراح بعد تكرار التسجيل قرب نفس الوقت في ٧ أيام مختلفة على الأقل.',
                  'A suggestion appears after logging around the same time on at least 7 different days.',
                ),
                selected: discover,
                onTap: () => save((d) => d['discoverReminders'] = !discover),
              ),
              if (discover && suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: Text(
                    t(
                      'لما يظهر نمط منتظم لمتابعة محتاجة تذكير، هتلاقيه هنا.',
                      'When an unassigned tracker has a consistent routine, a suggestion will appear here.',
                    ),
                  ),
                ),
              for (final (tracker, pattern) in suggestions)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Enter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                TileIcon(tracker.id, size: 34),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tracker.name(ar),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _patternReason(
                                pattern.minute,
                                pattern.matchedDays,
                              ),
                            ),
                            Wrap(
                              spacing: 7,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () => _reminder(
                                    tracker: tracker.id,
                                    suggestedMinute: pattern.minute,
                                  ),
                                  child: Text(
                                    t('راجع التذكير', 'Review reminder'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => save((d) {
                                    final dismissed = Map<String, dynamic>.from(
                                      d['discoveryDismissed'] as Map? ?? {},
                                    );
                                    dismissed[tracker.id] = DateTime.now()
                                        .toUtc()
                                        .toIso8601String();
                                    d['discoveryDismissed'] = dismissed;
                                  }),
                                  child: Text(t('تجاهل', 'Dismiss')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              SectionTitle(t('الضبط التلقائي', 'Automatic adjustments')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    t(
                      'فعّل الضبط من أي تذكير متابعة مرن. يومي يحرّكه داخل النافذة اللي اخترتها، بحد أقصى ١٥ دقيقة في الأسبوع لكل تذكير.',
                      'Enable adjustment in any flexible tracker reminder. Yawmi moves it inside the window you set, by up to 15 minutes a week per reminder.',
                    ),
                  ),
                ),
              ),
              for (final r in reminders.where((r) => r['tracker'] != null))
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.alarm_outlined),
                      title: Text(r['name']),
                      subtitle: Text(
                        [
                          clockText(r['minute']),
                          r['enabled'] != true
                              ? t('التذكير متوقف', 'Reminder paused')
                              : switch (r['learn']) {
                                  'auto' => t('ضبط تلقائي', 'Automatic'),
                                  'suggest' => t(
                                    'اقتراحات فقط',
                                    'Suggest only',
                                  ),
                                  _ => t('التعلّم متوقف', 'Learning off'),
                                },
                        ].join(' · '),
                      ),
                      onTap: () => _reminder(existing: r),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: _dashboard,
                icon: const Icon(Icons.dashboard_outlined),
                label: Text(
                  t(
                    'اضبط تعلّم ترتيب بطاقات اليوم',
                    'Manage adaptive card order',
                  ),
                ),
              ),
              SectionTitle(t('سجل التغييرات', 'Change history')),
              if (history.isEmpty)
                Text(
                  t(
                    'التغييرات التلقائية وأسبابها هتظهر هنا.',
                    'Automatic adjustments and their reasons appear here.',
                  ),
                ),
              for (final event in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _adaptiveEvent(event, reminders),
                    ),
                  ),
                ),
              const SizedBox(height: 9),
              OutlinedButton(
                onPressed: _clearLearning,
                child: Text(t('امسح سجل التعلّم', 'Clear learning history')),
              ),
            ],
          ),
        );
      },
    ),
  );

  String _patternReason(int minute, int days) => [
    t('سجّلت المتابعة قرب', 'You logged around'),
    '\u2066' + clockText(minute) + '\u2069',
    t('في', 'on'),
    days,
    t('أيام من آخر ٢١ يومًا.', 'days in the last 21 days.'),
  ].join(' ');

  List<(Tracker, RoutinePattern)> _discoveredRoutines() {
    final current = DateTime.now();
    final reset = DateTime.tryParse(data['learningReset'] ?? '');
    final assigned = rows(data['reminders']).map((r) => r['tracker']).toSet();
    final declined = data['discoveryDismissed'] as Map? ?? {};
    final result = <(Tracker, RoutinePattern)>[];
    for (final id in cardPlan(data)) {
      final tracker = trackerFor(data, id);
      if (tracker == null || assigned.contains(id)) continue;
      final date = DateTime.tryParse(declined[id] as String? ?? '');
      if (date != null && current.difference(date) < const Duration(days: 14))
        continue;
      final pattern = learnedRoutine(
        entriesFor(data, id),
        current,
        since: reset,
      );
      if (pattern != null) result.add((tracker, pattern));
    }
    return result;
  }

  Widget _adaptiveEvent(JournalRow event, List<JournalRow> reminders) {
    final active = reminders
        .where((r) => r['id'] == event['reminder'])
        .firstOrNull;
    final effective =
        event['undone'] != true &&
        active != null &&
        active['revision'] == event['revision'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event['name'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          [clockText(event['old']), '→', clockText(event['next'])].join(' '),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(_patternReason(event['pattern'], event['days'])),
        Text(prettyDate(eventTime(event))),
        if (event['undone'] == true) Text(t('رجّعنا الإعداد', 'Undone')),
        if (effective)
          TextButton.icon(
            icon: const Icon(Icons.undo),
            label: Text(t('تراجع عن التغيير', 'Undo adjustment')),
            onPressed: () =>
                _undoAdjustment(event['reminder'], event['revision']),
          ),
      ],
    );
  }

  Future<bool> _undoAdjustment(String id, int revision) => save((d) {
    final current = rows(
      d['reminders'],
    ).where((r) => r['id'] == id).firstOrNull;
    if (current == null ||
        current['revision'] != revision ||
        current['previousMinute'] is! int)
      return;
    upsert(d, 'reminders', {
      ...current,
      'minute': current['previousMinute'],
      'previousMinute': null,
      'revision': revision + 1,
      'rejectedAt': DateTime.now().toUtc().toIso8601String(),
    });
    d['adaptiveHistory'] = [
      for (final e in rows(d['adaptiveHistory']))
        if (e['reminder'] == id && e['revision'] == revision)
          {...e, 'undone': true}
        else
          e,
    ];
  });
}
