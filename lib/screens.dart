part of 'main.dart';

Color _todayTone(String id) => id == 'glucose' ? lavender : tint(id);

extension _Screens on _HomeState {
  Widget onboarding() {
    final stage = data['stage'] as int;
    const steps = [1, 4, 2];
    final index = steps.indexOf(stage);
    final onWelcome = index < 0;
    final active = rows(data['conditions']).where((c) => c['archived'] != true);
    final canContinue =
        stage != 1 ||
        active.isNotEmpty ||
        data['setupWithoutConditions'] == true;
    final cards = cardPlan(data);
    final labels = [
      t('الحالات', 'Conditions'),
      t('المتابعات', 'Trackers'),
      t('المراجعة', 'Review'),
    ];
    final colors = Theme.of(context).colorScheme;
    void previous() {
      if (!onWelcome) {
        save((d) => d['stage'] = index == 0 ? 0 : steps[index - 1]);
      }
    }

    return PopScope(
      canPop: onWelcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) previous();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            if (widget.db is ProfileJournal &&
                (widget.db as ProfileJournal).profiles.length > 1)
              IconButton(
                tooltip: t('بدّل ملف المتابعة', 'Switch profile'),
                icon: const Icon(Icons.switch_account_outlined),
                onPressed: _showProfiles,
              ),
          ],
          title: Row(
            children: [
              if (!onWelcome)
                BackButton(onPressed: previous)
              else ...[
                const _IdentityMark(size: 35),
                const SizedBox(width: 8),
                Text(t('يومي', 'Yawmi')),
              ],
              const Spacer(),
              TextButton(
                onPressed: () => save((d) => d['language'] = ar ? 'en' : 'ar'),
                child: Text(t('English', 'العربية')),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ColoredBox(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!onWelcome)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AnimatedSwitcher(
                        duration: motion(context, 170),
                        child: Text(
                          index == 0
                              ? (data['setupWithoutConditions'] == true
                                    ? t('متابعة عامة', 'General tracking')
                                    : "${t('الحالات المختارة', 'Conditions selected')} · ${active.length}")
                              : t('البطاقات المختارة', 'Cards selected') +
                                    ' · ' +
                                    cards.length.toString(),
                          key: ValueKey(
                            [
                              index,
                              active.length,
                              cards.length,
                              canContinue,
                            ].join('/'),
                          ),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (!onWelcome) const SizedBox(height: 5),
                  JournalButton.icon(
                    onPressed: !canContinue
                        ? null
                        : () => save((d) {
                            d['stage'] = onWelcome
                                ? 1
                                : index == 2
                                ? 3
                                : steps[index + 1];
                            if (index == 2) d['firstDayGuide'] = true;
                          }),
                    icon: Icon(
                      index == 2
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(
                      onWelcome
                          ? t('ابدأ', 'Get started')
                          : [
                              t('تابع للمتابعات', 'Continue to trackers'),
                              t('عاين صفحة اليوم', 'Preview Today'),
                              t('افتح يومي', 'Open Yawmi'),
                            ][index],
                    ),
                  ),
                  if (stage == 1 && !canContinue)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => save(
                        (draft) => _applyConditionSelection(
                          draft,
                          const {},
                          withoutConditions: true,
                        ),
                      ),
                      child: Text(
                        t(
                          'مفيش حالات محددة أتابعها',
                          'I don’t track a specific condition',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: DirectionFlow(
            index: index,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 22),
              children: [
                if (onWelcome) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 13, 20, 20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: const BorderRadiusDirectional.only(
                        topStart: Radius.circular(34),
                        topEnd: Radius.circular(34),
                        bottomStart: Radius.circular(34),
                        bottomEnd: Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: AspectRatio(
                            aspectRatio: 2.05,
                            child: Image.asset(
                              'assets/yawmi-field-notes.webp',
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          t(
                            'يومك الصحي،\nعلى طريقتك.',
                            'Your health day,\nyour way.',
                          ),
                          style: TextStyle(
                            color: colors.onSurface,
                            fontFamily: ar ? 'Tajawal' : 'Manrope',
                            fontSize: 42,
                            height: 1.07,
                            letterSpacing: -.6,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'اختار الحالات اللي بتتابعها، ويومي يقترح لك القياسات والأدوات المناسبة.',
                            'Choose the conditions you track and Yawmi will suggest relevant readings and tools.',
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ControlCard(
                    title: t(
                      'استورد بيانات أو استعد نسخة',
                      'Import data or restore a backup',
                    ),
                    subtitle: t(
                      'استعد نسخة يومي أو أضف قياسات من CSV',
                      'Restore a Yawmi backup or add readings from CSV',
                    ),
                    icon: Icons.move_to_inbox_outlined,
                    tonalColor: ice,
                    onTap: _dataCenter,
                  ),
                  TextButton(
                    onPressed: _privacy,
                    child: Text(t('الخصوصية', 'Privacy')),
                  ),
                ] else ...[
                  SetupRail(labels: labels, index: index),
                  const SizedBox(height: 13),
                  switch (stage) {
                    1 => _setupConditions(),
                    4 => _onboardChoose(),
                    _ => _onboardReview(),
                  },
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget today() {
    final date = _focusedDay ?? now;
    final current = dayKey(date) == dayKey(now);
    final cards = cardPlan(data);
    final doses = dosesOn(data, date);
    final hasMedicine = cards.contains(medicineCard) || doses.isNotEmpty;
    final section = hasMedicine ? _dashboardSection : 0;
    final recent = inPeriod(
      [
        ...rows(data['entries']).where(
          (row) =>
              (!current || cards.contains(row['tracker'])) &&
              (!isPlannedEntry(row) || row['planCompletedAt'] != null),
        ),
        if (hasMedicine)
          for (final row in rows(data['doses']))
            {...row, 'tracker': medicineCard},
      ],
      date,
      1,
    )..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
    final pending = outstanding(data, date);
    final agenda = current && section == 0
        ? journalAgenda(data, date, days: 2)
        : const <AgendaItem>[];
    final first = nextJournalAction(
      agenda.where((item) => dayKey(item.at) == dayKey(now)).toList(),
      now,
    );
    final compact = data['todayCompact'] == true;
    final content = section == 1
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (doses.isEmpty)
                EmptyPanel(
                  Icons.event_available_outlined,
                  t('مفيش جرعات مجدولة', 'No scheduled doses'),
                  t(
                    'تقدر تضيف دواء ومواعيده من روتيني.',
                    'Set a medication schedule in Routine.',
                  ),
                  action: TextButton(
                    onPressed: () => _redraw(() => tab = 2),
                    child: Text(t('افتح روتيني', 'Open Routine')),
                  ),
                ),
              for (final (i, d) in doses.indexed)
                Enter(
                  key: ValueKey(d.id),
                  delay: 32 * i.clamp(0, 6),
                  child: _doseTile(d),
                ),
            ],
          )
        : current
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cards.isEmpty)
                EmptyPanel(
                  Icons.add_chart,
                  t('اختار أول متابعة', 'Choose a tracker'),
                  t(
                    'اعرض اللي حابب تسجله كل يوم.',
                    'Choose something you want to log.',
                  ),
                  action: TextButton(
                    onPressed: _chooseTrackers,
                    child: Text(t('اختيار البطاقات', 'Choose cards')),
                  ),
                ),
              if (cards.isNotEmpty)
                AnimatedSwitcher(
                  duration: motion(context, 290),
                  layoutBuilder: (current, previous) => Stack(
                    children: [
                      for (final child in previous)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: HeroMode(
                              enabled: false,
                              child: ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.topCenter,
                                  minHeight: 0,
                                  maxHeight: double.infinity,
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ?current,
                    ],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(compact),
                    child: compact ? _dailySummary(cards) : _cardBoard(cards),
                  ),
                ),
              if (!compact && recent.isNotEmpty) ...[
                SectionTitle(
                  t('قصة يومك', 'Your day’s activity'),
                  action: TextButton(
                    onPressed: () => _redraw(() {
                      tab = 1;
                      dates = null;
                      period = 1;
                      filter = null;
                      conditionFilter = null;
                      _search.clear();
                    }),
                    child: Text(t('السجل', 'View history')),
                  ),
                ),
                for (final row in recent.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _logTile(row),
                  ),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recent.isEmpty)
                EmptyPanel(
                  Icons.history,
                  t('مفيش تسجيلات في اليوم ده', 'No entries for this day'),
                  '',
                ),
              for (final row in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _logTile(row),
                ),
            ],
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 34),
      children: [
        _todayHeader(date, current),
        if (_availableUpdate != null) _releaseBanner(),
        if (current && section == 0)
          _dailyAgenda(first, showDoses: hasMedicine),
        if (current &&
            section == 0 &&
            cards.any((id) => id != medicineCard)) ...[
          const SizedBox(height: 8),
          _todayActions(cards),
        ],
        if (current && section == 0) _upcomingAgenda(agenda, first),
        const SizedBox(height: 12),
        _dateTrack(date),
        if (current)
          _todayContext(
            date,
            recent.length,
            hasMedicine ? pending.length : null,
            hasLate: first != null && now.difference(first.at).inMinutes > 0,
          ),
        if (!current)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _redraw(() {
                _focusedDay = null;
                _dashboardSection = 0;
              }),
              icon: const Icon(Icons.today_outlined),
              label: Text(t('ارجع لليوم', 'Back to today')),
            ),
          ),
        if (current && section == 0 && data['earlyCustomization'] == true)
          ControlCard(
            title: t('اختار حالاتك الصحية', 'Choose your health conditions'),
            subtitle: t(
              'هنقترح عليك متابعات مرتبطة بالحالات اللي تختارها.',
              'Get tracker suggestions for the conditions you select.',
            ),
            icon: Icons.tune_rounded,
            onTap: _pickConditions,
            trailing: IconButton(
              tooltip: t('إخفاء الاقتراح', 'Dismiss suggestion'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => save((d) => d.remove('earlyCustomization')),
            ),
          ),
        if (hasMedicine && (!current || section == 1)) ...[
          const SizedBox(height: 14),
          SegmentedControl(
            labels: [
              current
                  ? t('متابعاتي', 'My tracking')
                  : t('التسجيلات', 'Entries'),
              t('الجرعات', 'Doses'),
            ],
            index: section,
            onChanged: (i) => _redraw(() => _dashboardSection = i),
          ),
        ],
        if (section == 0 && current && cards.isNotEmpty) ...[
          SectionTitle(
            t('ملخّص اليوم', 'Daily summary'),
            action: TextButton.icon(
              onPressed: _dashboard,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(t('رتّب', 'Arrange')),
            ),
          ),
          SegmentedControl(
            labels: [t('مختصر', 'Compact'), t('بطاقات', 'Cards view')],
            index: compact ? 0 : 1,
            onChanged: (i) => save((d) => d['todayCompact'] = i == 0),
          ),
        ],
        if (current && section == 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _weeklyReview,
              icon: const Icon(Icons.calendar_view_week_outlined, size: 18),
              label: Text(t('ملخّص الأسبوع', 'Weekly review')),
            ),
          ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: motion(context, 260),
          layoutBuilder: (child, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              for (final old in previous)
                Positioned.fill(
                  child: IgnorePointer(
                    child: HeroMode(
                      enabled: false,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: old,
                        ),
                      ),
                    ),
                  ),
                ),
              ?child,
            ],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .035), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(dayKey(date) + ':' + section.toString()),
            child: content,
          ),
        ),
      ],
    );
  }

  void _selectDashboardDay(DateTime value) {
    unawaited(HapticFeedback.selectionClick());
    _redraw(() => _focusedDay = dayKey(value) == dayKey(now) ? null : value);
  }

  Widget _dateTrack(DateTime selected) {
    final anchor =
        dayKey(selected) == dayKey(now) || now.difference(selected).inDays <= 4
        ? now
        : selected;
    final values = [
      for (var offset = -4; offset <= 0; offset++)
        DateTime(anchor.year, anchor.month, anchor.day + offset),
    ];
    final activity = <String, int>{};
    for (final entry in inPeriod(
      rows(data['entries']),
      anchor,
      values.length,
    )) {
      activity.update(
        dayKey(eventTime(entry)),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final colors = Theme.of(context).colorScheme;
    const arabicDays = ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
    final chosen = values
        .indexWhere((d) => dayKey(d) == dayKey(selected))
        .clamp(0, 4);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: motion(context, 330),
              curve: const Cubic(.16, .8, .25, 1),
              alignment: AlignmentDirectional(chosen / 2 - 1, 0),
              child: FractionallySizedBox(
                widthFactor: .2,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (index, date) in values.indexed)
                Expanded(
                  child: Semantics(
                    selected: index == chosen,
                    child: Pressable(
                      key: ValueKey('journal-day/${dayKey(date)}'),
                      radius: 17,
                      label:
                          '${prettyDate(date, 'EEEE، d MMMM')} · ${activity[dayKey(date)] ?? 0}',
                      onTap: () => _selectDashboardDay(date),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 2,
                        ),
                        child: Column(
                          children: [
                            Text(
                              ar
                                  ? arabicDays[date.weekday - 1]
                                  : prettyDate(date, 'EEE'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: index == chosen
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              prettyDate(date, 'd'),
                              style: TextStyle(
                                fontFamily: ar ? fontUi : 'Manrope',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: index == chosen
                                    ? colors.onPrimary
                                    : colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedContainer(
                              duration: motion(context, 350),
                              height: 3,
                              width:
                                  4.0 +
                                  (activity[dayKey(date)] ?? 0).clamp(0, 6) * 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: index == chosen
                                    ? colors.onPrimary
                                    : activity.containsKey(dayKey(date))
                                    ? colors.primary
                                    : colors.outlineVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todayActions(List<String> cards) {
    final selected = {
      ...quickPins(data),
      ...cards,
    }.where((id) => id != medicineCard).take(2).toList();
    Widget action(String id) => ControlCard(
      title: id == 'water'
          ? t('سجّل كوب', 'Log a cup')
          : id == 'glucose'
          ? t('سجّل السكر', 'Log glucose')
          : cardName(data, id, ar),
      subtitle: id == 'water'
          ? '\u2066${defaultWaterCup(data)} mL\u2069'
          : t('تسجيل سريع', 'Quick entry'),
      icon: glyph(id),
      tonalColor: _todayTone(id),
      toned: true,
      trailing: const SizedBox.shrink(),
      onTap: id == 'water'
          ? (_addingWater ? null : () => _addWater(defaultWaterCup(data)))
          : () => _entry(trackerFor(data, id)!),
    );
    return LayoutBuilder(
      builder: (c, bounds) {
        final stacked =
            selected.length < 2 ||
            MediaQuery.textScalerOf(c).scale(16) > 22 ||
            bounds.maxWidth < 300;
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, id) in selected.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    action(id),
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: action(selected.first)),
                    const SizedBox(width: 8),
                    Expanded(child: action(selected.last)),
                  ],
                ),
              );
      },
    );
  }

  Widget _dailySummary(List<String> cards) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, id) in cards.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outlineVariant,
                indent: 12,
                endIndent: 12,
              ),
            Enter(delay: (i * 26).clamp(0, 105), child: _dailyRow(id)),
          ],
        ],
      ),
    );
  }

  Widget _dailyRow(String id) {
    final colors = Theme.of(context).colorScheme;
    final tracker = trackerFor(data, id);
    final item = summaryFor(data, id, ar, now);
    final numeric = tracker?.kind == 'number' || id == medicineCard;
    VoidCallback details = id == 'water'
        ? _hydrationDetails
        : tracker == null
        ? () => _redraw(() => _dashboardSection = 1)
        : () => _details(tracker);
    final name = cardName(data, id, ar);
    final outlined = id == 'water'
        ? t('سجّل المياه', 'Log water')
        : tracker == null
        ? t('اعرض الجرعات', 'Show doses')
        : t('سجّل قراءة', 'Log an entry');
    return Row(
      children: [
        Expanded(
          child: Pressable(
            radius: 16,
            onTap: details,
            child: UpdateFlash(
              value: (item.value, item.unit),
              color: colors.primary,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(11, 9, 3, 9),
                child: Row(
                  children: [
                    TileIcon(id, size: 37),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'tracker/$id',
                            child: Material(
                              color: Colors.transparent,
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          if (item.context.isNotEmpty)
                            Text(
                              item.context,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: motion(context, 380),
                        transitionBuilder: valueMotion,
                        child: Text(
                          [item.value, item.unit]
                              .where(
                                (v) =>
                                    v.isNotEmpty &&
                                    !(v == item.unit && item.value == '—'),
                              )
                              .join(' '),
                          key: ValueKey((item.value, item.unit)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: numeric ? TextDirection.ltr : null,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: numeric ? 'Manrope' : fontUi,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: outlined,
          onPressed: tracker == null || id == 'water'
              ? details
              : () => _entry(tracker),
          style: IconButton.styleFrom(
            foregroundColor: colors.primary,
            minimumSize: const Size(48, 48),
          ),
          icon: Icon(
            tracker == null
                ? Icons.chevron_right_rounded
                : Icons.add_circle_outline_rounded,
            size: 22,
          ),
        ),
      ],
    );
  }

  Widget _cardBoard(List<String> cards) => LayoutBuilder(
    builder: (c, space) {
      final columns = space.maxWidth >= 620 ? 3 : 2;
      final mosaic =
          cards.length >= 3 &&
          space.maxWidth >= 310 &&
          MediaQuery.textScalerOf(c).scale(16) < 21;
      return Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final (i, id) in cards.indexed)
            SizedBox(
              key: ValueKey(id),
              width: mosaic && i > 0 && id != medicineCard
                  ? (space.maxWidth - (columns - 1) * 9) / columns
                  : space.maxWidth,
              child: Enter(
                delay: i.clamp(0, 5) * 35,
                child: id == medicineCard
                    ? _medicineCard()
                    : _trackerCard(
                        trackerFor(data, id)!,
                        small: mosaic && i > 0,
                      ),
              ),
            ),
        ],
      );
    },
  );

  Widget _trackerCard(Tracker tracker, {bool small = false}) {
    final id = tracker.id;
    final s = summaryFor(data, id, ar, now);
    final view = trackerView(data, tracker);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = Theme.of(context).colorScheme;
    final accent = _todayTone(id);
    final foreground = dark ? palette.onSurface : ink;
    final indicator = dark ? accent : evergreen;
    final open = id == 'water' ? _hydrationDetails : () => _details(tracker);
    final history = <double>[];
    if (tracker.kind == 'number' && id != 'water') {
      final readings = trackerViewEntries(data, tracker, now, view);
      history.addAll(
        (view.mode == 'latest' ? readings : inPeriod(readings, now, view.days))
            .take(9)
            .map((row) {
              final value =
                  row['values'][id == 'pressure' ? 'systolic' : 'value'];
              return value is num
                  ? convert(id, value.toDouble(), row['unit'], s.unit)
                  : null;
            })
            .whereType<double>()
            .toList()
            .reversed,
      );
    }
    final goal = data['waterGoal'];
    final waterProgress = id == 'water' && goal is num && goal > 0
        ? _waterLevel(waterTotal(data, now))
        : null;
    return Card(
      key: ValueKey('today-card/$id'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: Color.lerp(palette.surface, accent, dark ? .18 : .75),
      child: UpdateFlash(
        value: (s.value, s.unit),
        color: foreground,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TodayBackdrop(
                    indicator,
                    id == 'water',
                    Directionality.of(context) == TextDirection.rtl,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(7, 5, 7, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      radius: 19,
                      onTap: open,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          7,
                          3,
                          6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(glyph(id), color: foreground, size: 21),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Hero(
                                    tag: 'tracker/$id',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Text(
                                        tracker.name(ar),
                                        style: TextStyle(
                                          color: foreground,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            AnimatedSwitcher(
                              duration: motion(context, 380),
                              transitionBuilder: valueMotion,
                              layoutBuilder: (current, previous) => Stack(
                                alignment: AlignmentDirectional.centerStart,
                                children: [...previous, ?current],
                              ),
                              child: small && tracker.kind == 'number'
                                  ? Column(
                                      key: ValueKey((s.value, s.unit)),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            s.value,
                                            textDirection: TextDirection.ltr,
                                            style: TextStyle(
                                              fontFamily: 'Manrope',
                                              color: foreground,
                                              fontSize: 23,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        if (s.unit.isNotEmpty && s.value != '—')
                                          Text(
                                            s.unit,
                                            textDirection: TextDirection.ltr,
                                            style: TextStyle(
                                              fontFamily: 'Manrope',
                                              color: foreground,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    )
                                  : Text(
                                      s.value == '—'
                                          ? '—'
                                          : [s.value, s.unit]
                                                .where(
                                                  (text) => text.isNotEmpty,
                                                )
                                                .join(' '),
                                      key: ValueKey((s.value, s.unit)),
                                      textDirection: tracker.kind == 'number'
                                          ? TextDirection.ltr
                                          : null,
                                      style: TextStyle(
                                        fontFamily: tracker.kind == 'number'
                                            ? 'Manrope'
                                            : fontUi,
                                        fontSize: tracker.kind == 'number'
                                            ? (small ? 21 : 29)
                                            : 18,
                                        fontWeight: FontWeight.bold,
                                        color: foreground,
                                      ),
                                    ),
                            ),
                            if (s.context.isNotEmpty)
                              Text(
                                s.context,
                                style: TextStyle(
                                  color: palette.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!small &&
                      MediaQuery.textScalerOf(context).scale(16) <= 21 &&
                      MediaQuery.sizeOf(context).width >= 340 &&
                      (history.length >= 2 || waterProgress != null))
                    IgnorePointer(
                      child: SizedBox(
                        width: 85,
                        height: 37,
                        child: waterProgress != null
                            ? Center(
                                child: _todayMeter(waterProgress, indicator),
                              )
                            : CustomPaint(
                                painter: _MicroTrace(history, indicator),
                              ),
                      ),
                    ),
                  IconButton(
                    onPressed: id == 'water'
                        ? _hydrationDetails
                        : () => _entry(tracker),
                    tooltip: id == 'water'
                        ? t('سجّل المياه', 'Log water')
                        : t('سجّل قراءة', 'Log an entry'),
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayMeter(double amount, Color color) =>
      TweenAnimationBuilder<double>(
        tween: Tween(end: amount),
        duration: motion(context, 560),
        curve: motionArrival,
        builder: (_, value, _) => LinearProgressIndicator(
          value: value,
          color: color,
          backgroundColor: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(14),
          minHeight: 7,
        ),
      );

  Widget _medicineCard() {
    final doses = dosesOn(data, now);
    final done = doses
        .where((dose) => doseEvent(data, dose.id)?['status'] == 'taken')
        .length;
    final logged = inPeriod(
      rows(data['doses']),
      now,
      1,
    ).where((row) => row['status'] == 'taken').length;
    return ControlCard(
      title: t('الجرعات المسجّلة اليوم', 'Doses logged today'),
      subtitle: doses.isEmpty
          ? '$logged'
          : '$logged · ${t('$done من ${doses.length} في الجدول', '$done of ${doses.length} scheduled')}',
      tonalColor: rose,
      toned: true,
      icon: Icons.medication_outlined,
      onTap: () => _redraw(() => _dashboardSection = 1),
      trailing: doses.isEmpty || MediaQuery.textScalerOf(context).scale(16) > 21
          ? null
          : SizedBox(
              width: 48,
              child: _todayMeter(done / doses.length, evergreen),
            ),
    );
  }

  ({List<JournalRow> visible, List<JournalRow> matching}) _historySelection() {
    final query = normalize(_search.text);
    final list =
        <JournalRow>[
            ...rows(data['entries']),
            for (final d in rows(data['doses']))
              {...d, 'tracker': medicineCard},
          ].where((e) {
            if (filter != null && e['tracker'] != filter) return false;
            if (conditionFilter != null &&
                !rows(e['conditions']).any((c) => c['id'] == conditionFilter)) {
              return false;
            }
            if (query.isEmpty) return true;
            final text = reportValue(e, ar);
            return normalize(
              [
                cardName(data, e['tracker'], ar),
                text,
                if (e['tracker'] == medicineCard) e['name'],
                e['note'],
                e['context'],
                ...rows(e['conditions']).map((c) => c['name']),
              ].whereType<String>().join(' '),
            ).contains(query);
          }).toList()
          ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
    final shown = dates != null
        ? list
              .where(
                (e) =>
                    !eventTime(e).isBefore(dates!.start) &&
                    eventTime(e).isBefore(
                      DateTime(
                        dates!.end.year,
                        dates!.end.month,
                        dates!.end.day + 1,
                      ),
                    ),
              )
              .toList()
        : period == 0
        ? list
        : inPeriod(list, now, period);
    return (visible: shown, matching: list);
  }

  Widget history() {
    final (visible: shown, matching: list) = _historySelection();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 95),
      itemCount: shown.isEmpty ? 2 : shown.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _historyControls(shown, list);
        if (shown.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 13),
            child: EmptyPanel(
              Icons.history,
              t('السجل فاضي هنا', 'No matching entries'),
              t(
                'سجّل حاجة أو غيّر الفلتر.',
                'Log an entry or choose a different filter.',
              ),
            ),
          );
        }
        final item = shown[i - 1];
        final heading =
            i == 1 ||
            dayKey(eventTime(shown[i - 2])) != dayKey(eventTime(item));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading)
              SectionTitle(prettyDate(eventTime(item), 'EEEE، d MMMM')),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _logTile(item),
            ),
          ],
        );
      },
    );
  }

  Widget _historyControls(List<JournalRow> shown, List<JournalRow> matching) {
    final colors = Theme.of(context).colorScheme;
    final active =
        filter != null ||
        conditionFilter != null ||
        dates != null ||
        period != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _journalActivity(shown, matching),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => _redraw(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: t('ابحث في السجل', 'Search history'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: active
                    ? colors.primary
                    : colors.secondaryContainer,
                foregroundColor: active ? colors.onPrimary : colors.onSurface,
              ),
              onPressed: _historyFilters,
              tooltip: t('فلترة السجل', 'Filter history'),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              children: [
                if (filter != null)
                  InputChip(
                    label: Text(cardName(data, filter!, ar)),
                    onDeleted: () => _redraw(() => filter = null),
                  ),
                if (dates != null || period > 0)
                  InputChip(
                    label: Text(
                      dates == null
                          ? period.toString() + t(' أيام', ' days')
                          : prettyDate(dates!.start) +
                                ' – ' +
                                prettyDate(dates!.end),
                    ),
                    onDeleted: () => _redraw(() {
                      dates = null;
                      period = 0;
                    }),
                  ),
                if (conditionFilter != null)
                  InputChip(
                    label: Text(t('حالة محددة', 'Selected condition')),
                    onDeleted: () => _redraw(() => conditionFilter = null),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _historyFilters() {
    var kind = filter ?? '';
    var linked = conditionFilter ?? '';
    var days = period;
    var range = dates;
    return _sheet<void>(
      (c) => StatefulBuilder(
        builder: (c, refresh) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('فلترة السجل', 'Filter history'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final (n, a, e) in [
                      (0, 'الكل', 'All'),
                      (1, 'اليوم', 'Today'),
                      (7, '٧ أيام', '7 days'),
                      (30, '٣٠ يومًا', '30 days'),
                    ])
                      ChoiceChip(
                        label: Text(t(a, e)),
                        selected: range == null && days == n,
                        onSelected: (_) => refresh(() {
                          days = n;
                          range = null;
                        }),
                      ),
                    ActionChip(
                      label: Text(t('فترة مخصصة', 'Custom dates')),
                      avatar: const Icon(Icons.date_range, size: 17),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: c,
                          firstDate: DateTime(1900),
                          lastDate: now,
                          initialDateRange: range,
                        );
                        if (picked != null && c.mounted)
                          refresh(() => range = picked);
                      },
                    ),
                  ],
                ),
                if (range != null)
                  Text(
                    prettyDate(range!.start) + ' – ' + prettyDate(range!.end),
                  ),
                const SizedBox(height: 8),
                _choiceSetting(
                  c,
                  t('نوع التسجيل', 'Entry type'),
                  kind,
                  [
                    ('', t('جميع الأنواع', 'All types')),
                    for (final id in {
                      medicineCard,
                      ...allTrackers(data).map((x) => x.id),
                    })
                      (id, cardName(data, id, ar)),
                  ],
                  (value) => refresh(() => kind = value),
                  icon: Icons.category_outlined,
                ),
                if (rows(data['conditions']).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _choiceSetting(
                    c,
                    t('الحالة المرتبطة', 'Linked condition'),
                    linked,
                    [
                      ('', t('جميع الحالات', 'All conditions')),
                      for (final e in rows(data['conditions']))
                        (e['id'] as String, conditionName(e, ar)),
                    ],
                    (value) => refresh(() => linked = value),
                    icon: Icons.link_rounded,
                  ),
                ],
                const SizedBox(height: 12),
                JournalButton(
                  onPressed: () {
                    _redraw(() {
                      filter = kind.isEmpty ? null : kind;
                      conditionFilter = linked.isEmpty ? null : linked;
                      dates = range;
                      period = days;
                    });
                    Navigator.pop(c);
                  },
                  child: Text(t('اعرض النتائج', 'Show results')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logTile(JournalRow item) {
    final id = item['tracker'] as String;
    final at = eventTime(item);
    final tracker = trackerFor(data, id);
    final dose = id == medicineCard;
    final headline = dose ? _doseName(item) : cardName(data, id, ar);
    final value = dose
        ? item['status'] == 'taken'
              ? t('مسجّلة', 'Taken')
              : t('متخطّية', 'Skipped')
        : [
            valueText(item, ar),
            item['unit'] as String? ?? '',
          ].where((x) => x.isNotEmpty).join(' ');
    final notes = [
      entryContext(item['context'], ar),
      item['note'],
      if (item['legacyCarbs'] case final num grams)
        number(grams.toDouble()) + t(' غ كربوهيدرات', ' g carbs'),
      if (item['legacyUndated'] == true)
        t('مستورد من غير تاريخ', 'Imported without a date'),
    ].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    final colors = Theme.of(context).colorScheme;
    return Pressable(
      radius: 19,
      onTap: dose
          ? () => _doseHistory(item)
          : () => _entry(tracker!, item: item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 66),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
        child: Row(
          children: [
            SizedBox(
              width: 49,
              child: Text(
                item['legacyUndated'] == true
                    ? '—'
                    : clockText(at.hour * 60 + at.minute),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Container(width: 1, height: 27, color: colors.outlineVariant),
            const SizedBox(width: 8),
            TileIcon(id, size: 35),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: tracker?.kind == 'number'
                    ? TextDirection.ltr
                    : null,
                style: TextStyle(
                  fontFamily: tracker?.kind == 'number' ? 'Manrope' : fontUi,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayBackdrop extends CustomPainter {
  const _TodayBackdrop(this.color, this.water, this.rtl);
  final Color color;
  final bool water, rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final direction = rtl ? 1.0 : -1.0;
    final x = rtl ? 0.0 : size.width;
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var i = 0; i < 4; i++) {
      brush.color = color.withValues(alpha: .125 - .021 * i);
      if (water) {
        final y = size.height * (.46 + i * .15);
        canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..cubicTo(
              x + 42 * direction,
              y - 28,
              x + 98 * direction,
              y + 32,
              x + 171 * direction,
              y - 7,
            ),
          brush,
        );
      } else {
        canvas.drawCircle(Offset(x, size.height * .62), 28 + i * 18, brush);
      }
    }
  }

  @override
  bool shouldRepaint(_TodayBackdrop old) =>
      old.color != color || old.water != water || old.rtl != rtl;
}

class _MicroTrace extends CustomPainter {
  const _MicroTrace(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final high = values.reduce(math.max), low = values.reduce(math.min);
    final path = Path();
    for (final (index, value) in values.indexed) {
      final x = 3 + (size.width - 6) * index / (values.length - 1);
      final y = high == low
          ? size.height / 2
          : 3 + (size.height - 6) * (high - value) / (high - low);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      if (index == values.length - 1) {
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_MicroTrace oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
