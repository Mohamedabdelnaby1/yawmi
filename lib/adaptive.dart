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
              ControlCard(
                title: t('أوضاع الروتين', 'Routine modes'),
                subtitle: t(
                  'شغل، إجازة أو سفر بمواعيد مرنة مؤقتة.',
                  'Temporary timing for work, days off, or travel.',
                ),
                icon: Icons.event_repeat_rounded,
                tonalColor: lavender,
                onTap: _routineModes,
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

extension _RoutineModesUi on _HomeState {
  Future<void> _routineModes() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = data['routineMode'] as Map?;
    final savedShifts = Map<String, dynamic>.from(
      data['routineShifts'] as Map? ?? {},
    );
    final expires = parseCalendarDate(current?['end']);
    var selected =
        expires != null &&
            !expires.isBefore(today) &&
            routineModes.contains(current?['id'])
        ? current!['id'] as String
        : 'normal';
    var through = expires != null && !expires.isBefore(today) ? expires : today;
    var offset = savedShifts[selected] is int
        ? savedShifts[selected] as int
        : 0;
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => _JournalPanel(
          heading: AppBar(
            title: Text(t('أوضاع الروتين', 'Routine modes')),
            leading: const CloseButton(),
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t(
                  'اختار تقديم أو تأخير تذكيرات المياه والقياسات المرنة لفترة محددة. مواعيد الدوا والمتابعات بتاريخ ثابت تفضل زي ما هي.',
                  'Temporarily move water and flexible tracking reminders earlier or later. Medication and dated follow-ups keep their set times.',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final (id, label) in [
                    ('normal', t('مواعيدي الأصلية', 'Normal schedule')),
                    ('work', t('يوم شغل', 'Workday')),
                    ('dayOff', t('إجازة', 'Day off')),
                    ('travel', t('سفر', 'Travel')),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: selected == id,
                      onSelected: (_) => redraw(() {
                        selected = id;
                        offset = savedShifts[id] is int
                            ? savedShifts[id] as int
                            : 0;
                      }),
                    ),
                ],
              ),
              if (selected != 'normal') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: ValueKey(selected),
                  initialValue: offset,
                  decoration: InputDecoration(
                    labelText: t('تغيير الميعاد', 'Time offset'),
                  ),
                  items: [
                    for (var minutes = -180; minutes <= 180; minutes += 30)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          minutes == 0
                              ? t('نفس الميعاد', 'Same time')
                              : minutes < 0
                              ? t(
                                  'بدري ${minutes.abs()} دقيقة',
                                  '${minutes.abs()} min earlier',
                                )
                              : t('متأخر $minutes دقيقة', '$minutes min later'),
                        ),
                      ),
                  ],
                  onChanged: (value) => redraw(() => offset = value ?? 0),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: c,
                      initialDate: through,
                      firstDate: today,
                      lastDate: shiftCalendarDate(today, 30),
                    );
                    if (date != null && c.mounted) redraw(() => through = date);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    t(
                      'لحد ${prettyDate(through)}',
                      'Until ${prettyDate(through)}',
                    ),
                  ),
                ),
              ],
            ],
          ),
          footer: JournalButton.icon(
            onPressed: () async {
              final ok = await save((d) {
                if (selected == 'normal') {
                  d.remove('routineMode');
                  return;
                }
                d['routineShifts'] = {...savedShifts, selected: offset};
                d['routineMode'] = {
                  'id': selected,
                  'shift': offset,
                  'start': dayKey(today),
                  'end': dayKey(through),
                };
              });
              if (ok && c.mounted) Navigator.pop(c);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(t('طبّق الوضع', 'Apply mode')),
          ),
        ),
      ),
    );
  }
}
