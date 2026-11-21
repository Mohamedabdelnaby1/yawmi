part of 'main.dart';

extension _Personalization on _HomeState {
  Widget _setupConditions() {
    const common = {
      'diabetes2': 'glucose',
      'hypertension': 'pressure',
      'asthma': 'peak_flow',
      'coronary': 'pulse',
    };
    final active = _activeConditionSelection(data);
    final families = active.keys.map(conditionFamilyId).toSet();
    final additional = active.values.where(
      (c) => !common.containsKey(conditionFamilyId(c['id'] as String)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldBanner(
          title: t('اختار حالاتك الصحية', 'Choose your health conditions'),
          detail: '',
          accent: mint,
          bottom: Text(
            t(
              'اختار حالة أو أكتر، ويومي هيجهّز لك المتابعات المناسبة.',
              'Choose one or more conditions to get relevant trackers.',
            ),
            style: const TextStyle(color: mint, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        ControlCard(
          title: t(
            'اختار من مكتبة الحالات',
            'Choose from the condition library',
          ),
          subtitle: t(
            'ابحث بالاسم أو أضف حالة باسمها',
            'Search by name or add a condition',
          ),
          icon: Icons.search_rounded,
          tonalColor: lavender,
          onTap: _pickConditions,
        ),
        SectionTitle(t('حالات شائعة', 'Common conditions')),
        LayoutBuilder(
          builder: (c, box) {
            final single =
                box.maxWidth < 310 || MediaQuery.textScalerOf(c).scale(16) > 22;
            final width = single ? box.maxWidth : (box.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: id, value: iconTracker)
                    in common.entries)
                  SizedBox(
                    width: width,
                    child: TrackerChoice(
                      key: ValueKey('setup-condition-$id'),
                      id: iconTracker,
                      label: id == 'hypertension'
                          ? t('ضغط الدم', 'Blood pressure')
                          : catalogCondition(id)!.name(ar),
                      selected: families.contains(id),
                      onTap: () => _toggleSetupCondition(catalogCondition(id)!),
                    ),
                  ),
              ],
            );
          },
        ),
        if (additional.isNotEmpty) ...[
          SectionTitle(t('حالات أخرى اخترتها', 'Other selected conditions')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final condition in additional)
                InputChip(
                  label: Text(conditionName(condition, ar)),
                  onDeleted: () => save((draft) {
                    final selected = _activeConditionSelection(draft)
                      ..remove(condition['id']);
                    _applyConditionSelection(draft, selected);
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Map<String, JournalRow> _activeConditionSelection(JournalRow state) => {
    for (final condition in rows(state['conditions']))
      if (condition['archived'] != true) condition['id'] as String: condition,
  };

  Iterable<String> _primaryConditionTrackers(Iterable<JournalRow> conditions) =>
      conditions
          .map((c) => strings(c['links']).firstOrNull)
          .whereType<String>();

  JournalRow _catalogSelection(CatalogEntry entry, JournalRow? saved) => {
    'id': entry.id,
    'name': entry.name(ar),
    'links': suggestedFor(entry),
    ...?saved,
    'archived': false,
  };

  Future<void> _toggleSetupCondition(CatalogEntry condition) => save((draft) {
    final selection = _activeConditionSelection(draft);
    final ids = selection.keys
        .where((id) => conditionFamilyId(id) == condition.id)
        .toList();
    if (ids.isEmpty) {
      final saved = rows(
        draft['conditions'],
      ).where((row) => row['id'] == condition.id).firstOrNull;
      selection[condition.id] = _catalogSelection(condition, saved);
    } else {
      ids.forEach(selection.remove);
    }
    _applyConditionSelection(draft, selection);
  });

  void _applyConditionSelection(
    JournalRow draft,
    Map<String, JournalRow> selection, {
    bool withoutConditions = false,
  }) {
    final original = _activeConditionSelection(draft);
    final preferred = strings(draft['enabled']).toSet();
    final hidden = strings(draft['hidden']).toSet();
    final auto = strings(draft['setupAuto']).toSet();
    final linked = selection.values.expand((c) => strings(c['links'])).toSet();
    final removed = auto.difference(linked);
    auto.removeAll(removed);
    preferred.removeAll(removed);
    for (final c in original.values) {
      if (!selection.containsKey(c['id'])) {
        upsert(draft, 'conditions', {...c, 'archived': true});
      }
    }
    for (final c in selection.values) {
      upsert(draft, 'conditions', c);
      if (!original.containsKey(c['id'])) {
        for (final id in strings(c['links'])) {
          if (!hidden.contains(id) && preferred.add(id)) auto.add(id);
        }
      }
    }
    draft['enabled'] = {
      if (draft['stage'] != 3)
        ..._primaryConditionTrackers(
          selection.values,
        ).where(preferred.contains),
      ...preferred,
    }.toList();
    draft['setupAuto'] = auto.toList();
    if (draft['stage'] != 3) {
      draft['setupWithoutConditions'] = selection.isEmpty && withoutConditions;
    } else if (selection.isNotEmpty) {
      draft.remove('earlyCustomization');
    }
  }

  Widget _onboardChoose() {
    final active = rows(
      data['conditions'],
    ).where((c) => c['archived'] != true).toList();
    final enabled = cardPlan(data).toSet();
    final recommended = recommendations(data, ar);
    final main = {
      ..._primaryConditionTrackers(active).where(recommended.containsKey),
    }.take(3).toSet();
    final optional = <String>{
      ...enabled,
      'symptom',
      'note',
      'medicine',
      'sleep',
      'activity',
      'water',
    }.difference(recommended.keys.toSet());

    Widget trackerGrid(Iterable<String> ids) => LayoutBuilder(
      builder: (c, box) {
        final columns =
            MediaQuery.textScalerOf(c).scale(16) > 22 || box.maxWidth < 304
            ? 1
            : box.maxWidth > 600
            ? 3
            : 2;
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in ids)
              SizedBox(
                width: width,
                child: TrackerChoice(
                  key: ValueKey(id),
                  label: cardName(data, id, ar),
                  id: id,
                  selected: enabled.contains(id),
                  onTap: () => _setTrackerVisible(id, !enabled.contains(id)),
                ),
              ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JournalCover(
          title: t('اختار بطاقاتك', 'Choose your cards'),
          icon: Icons.tune_rounded,
          art: JournalArt.mosaic,
          subtitle: t(
            'اللي تختاره هنا هيظهر في «اليوم». تقدر تضيف أو تشيل أي بطاقة.',
            'Your choices appear in Today. Add or remove any card.',
          ),
        ),
        const SizedBox(height: 16),
        if (active.isEmpty && enabled.isEmpty)
          ControlCard(
            title: t('ابدأ بالمتابعات اليومية', 'Start with daily habits'),
            subtitle: t('المياه، النوم والنشاط', 'Water, sleep and activity'),
            icon: Icons.bolt_outlined,
            tonalColor: mint,
            onTap: () => save((d) {
              const daily = {'water', 'sleep', 'activity'};
              d['enabled'] = {...strings(d['enabled']), ...daily}.toList();
              d['hidden'] = strings(
                d['hidden'],
              ).where((id) => !daily.contains(id)).toList();
            }),
          ),
        if (active.isNotEmpty)
          ControlCard(
            title: t('اختياراتك من الحالات', 'Your selected conditions'),
            subtitle: active.map((c) => conditionName(c, ar)).join(' · '),
            icon: Icons.medical_information_outlined,
            tonalColor: rose,
            onTap: _pickConditions,
          ),
        if (main.isNotEmpty) ...[
          SectionTitle(t('أهم متابعاتك', 'Your main trackers')),
          trackerGrid(main),
        ],
        if (recommended.keys.any((id) => !main.contains(id))) ...[
          SectionTitle(t('مقترحة لحالاتك', 'Suggested for your conditions')),
          trackerGrid(recommended.keys.where((id) => !main.contains(id))),
        ],
        SectionTitle(
          recommended.isEmpty
              ? t('متابعات شائعة', 'Popular trackers')
              : t('متابعات إضافية', 'More trackers'),
          action: TextButton(
            onPressed: _chooseTrackers,
            child: Text(t('كل المتابعات', 'All trackers')),
          ),
        ),
        trackerGrid(optional),
        const SizedBox(height: 12),
        ControlCard(
          title: t('اعمل متابعة باسمك', 'Create a custom tracker'),
          subtitle: t(
            'اختار اسمها ونوع البيانات',
            'Name it and choose a data type',
          ),
          icon: Icons.add_rounded,
          onTap: _customTracker,
        ),
      ],
    );
  }

  Widget _onboardReview() {
    final plan = cardPlan(data);
    final colors = Theme.of(context).colorScheme;
    final conditions = rows(
      data['conditions'],
    ).where((c) => c['archived'] != true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JournalCover(
          title: t('رتّب يومك', 'Make it yours'),
          icon: Icons.dashboard_customize_outlined,
          accent: lavender,
          subtitle: t(
            'البطاقات دي هتظهر في صفحة اليوم. اختار الترتيب اللي يسهّل عليك المتابعة.',
            'These cards will appear in Today. Arrange them in the order that makes sense for you.',
          ),
        ),
        if (plan.isNotEmpty) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('هيظهر في «اليوم»', 'What appears in Today'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 7,
                    children: [
                      for (final id in plan.take(3))
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TileIcon(id, size: 25),
                                const SizedBox(width: 6),
                                Flexible(child: Text(cardName(data, id, ar))),
                              ],
                            ),
                          ),
                        ),
                      if (plan.length > 3)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            t(
                              '+ ${plan.length - 3} متابعات',
                              '+ ${plan.length - 3} trackers',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.reorder_rounded),
            title: Text(t('رتّب البطاقات وثبّتها', 'Order and pin cards')),
            children: [
              _cardControls(
                data,
                (update) => save(update),
                isToday: true,
                onlySelected: true,
              ),
            ],
          ),
        ],
        TextButton.icon(
          onPressed: _chooseTrackers,
          icon: const Icon(Icons.add),
          label: Text(t('عدّل البطاقات', 'Edit selected cards')),
        ),
        if (conditions.isNotEmpty) ...[
          SectionTitle(t('تخصيص الحالات', 'Condition settings')),
          for (final condition in conditions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ControlCard(
                title: conditionName(condition, ar),
                subtitle: t(
                  'النوع والاسم والمتابعات المرتبطة',
                  'Type, name and linked trackers',
                ),
                icon: Icons.medical_information_outlined,
                tonalColor: rose,
                onTap: () => _conditionLinks(condition),
              ),
            ),
        ],
        SectionTitle(t('ابدأ بصفحة', 'Open Today on')),
        SegmentedControl(
          labels: [t('متابعاتي', 'My tracking'), t('الجرعات', 'Doses')],
          index: data['startSection'] == 'doses' ? 1 : 0,
          onChanged: (i) async {
            if (await save(
                  (d) => d['startSection'] = i == 1 ? 'doses' : 'tracking',
                ) &&
                mounted) {
              _redraw(() => _dashboardSection = i);
            }
          },
        ),
        const SizedBox(height: 9),
        ControlCard(
          title: t(
            'اقتراحات تذكير حسب روتيني',
            'Reminder suggestions from my routine',
          ),
          subtitle: t(
            'يومي يلاحظ مواعيد التسجيل على الجهاز بعد التفعيل.',
            'Yawmi learns from your log times on this device when enabled.',
          ),
          icon: Icons.auto_awesome_outlined,
          tonalColor: mint,
          selected: data['discoverReminders'] == true,
          onTap: () => save(
            (d) => d['discoverReminders'] = d['discoverReminders'] != true,
          ),
        ),
      ],
    );
  }

  Future<void> _setTrackerVisible(String id, bool on) => save((draft) {
    final enabled = strings(draft['enabled']).toSet();
    final hidden = strings(draft['hidden']).toSet();
    if (on) {
      enabled.add(id);
      hidden.remove(id);
    } else {
      hidden.add(id);
    }
    draft['enabled'] = enabled.toList();
    draft['hidden'] = hidden.toList();
    draft['setupAuto'] = strings(
      draft['setupAuto'],
    ).where((key) => key != id).toList();
  });

  Future<void> _chooseTrackers() async {
    var filter = '';
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, update) => ListenableBuilder(
          listenable: widget.db,
          builder: (c, _) {
            final selected = cardPlan(data).toSet();
            final suggested = recommendations(data, ar);
            final ids =
                <String>{
                      ...suggested.keys,
                      ...selected,
                      'medicine',
                      ...allTrackers(data).map((t) => t.id),
                    }
                    .where(
                      (id) => normalize(
                        cardName(data, id, ar),
                      ).contains(normalize(filter)),
                    )
                    .toList();
            return Scaffold(
              appBar: AppBar(
                title: Text(t('اختار متابعاتك', 'Choose trackers')),
                actions: [
                  IconButton(
                    onPressed: _customTracker,
                    icon: const Icon(Icons.add),
                    tooltip: t('متابعة مخصصة', 'Custom tracker'),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
                    child: TextField(
                      onChanged: (x) => update(() => filter = x),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: t('ابحث في المتابعات', 'Find a tracker'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: ids.length,
                      itemBuilder: (c, i) {
                        final id = ids[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ControlCard(
                            title: cardName(data, id, ar),
                            subtitle: suggested[id]?.join(' · '),
                            icon: glyph(id),
                            tonalColor: tint(id),
                            selected: selected.contains(id),
                            onTap: () =>
                                _setTrackerVisible(id, !selected.contains(id)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: JournalButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(t('تم', 'Done')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickConditions() async {
    final moveToTrackers = data['stage'] == 1;
    final conditions = rows(data['conditions']);
    final known = {for (final c in conditions) c['id'] as String: c};
    final selection = _activeConditionSelection(data);
    var query = '', category = '';
    final accepted = await _page<bool>(
      (_) => StatefulBuilder(
        builder: (c, update) {
          final browse = category.isEmpty && normalize(query).isEmpty;
          final choices = (browse ? catalogOverview : catalog)
              .where(
                (e) =>
                    (category.isEmpty || category == e.category) &&
                    e.matches(query),
              )
              .toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(t('مكتبة الحالات', 'Condition library')),
            ),
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          onChanged: (x) => update(() => query = x),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: t(
                              'اسم الحالة أو المرادف',
                              'Condition name or alias',
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        SizedBox(
                          height: MediaQuery.textScalerOf(c).scale(16) > 22
                              ? 64
                              : 52,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final (key, name) in [
                                ('', t('كل الفئات', 'All categories')),
                                for (final e in categories.entries)
                                  (e.key, t(e.value.$1, e.value.$2)),
                              ])
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 8,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(name),
                                    selected: key == category,
                                    onSelected: (_) =>
                                        update(() => category = key),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(
                              t('أضف حالة باسمها', 'Add a named condition'),
                            ),
                            onPressed: () async {
                              final name = await _textPrompt(
                                t('حالة مخصصة', 'Custom condition'),
                                t('اسم الحالة', 'Condition name'),
                              );
                              if (name == null ||
                                  name.isEmpty ||
                                  !c.mounted ||
                                  selection.values.any(
                                    (e) =>
                                        normalize(conditionName(e, ar)) ==
                                        normalize(name),
                                  ))
                                return;
                              final id = newId();
                              update(
                                () => selection[id] = {
                                  'id': id,
                                  'name': name,
                                  'links': suggestedFor(null),
                                  'archived': false,
                                },
                              );
                            },
                          ),
                        ),
                        if (selection.isNotEmpty)
                          SizedBox(
                            height: MediaQuery.textScalerOf(c).scale(16) > 22
                                ? 64
                                : 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final c in selection.values)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 5,
                                    ),
                                    child: InputChip(
                                      label: Text(conditionName(c, ar)),
                                      onDeleted: () => update(
                                        () => selection.remove(c['id']),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (choices.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        t(
                          'مفيش نتائج. تقدر تضيف حالة باسمها.',
                          'No matches. You can add a named condition.',
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverList.builder(
                      itemCount: choices.length,
                      itemBuilder: (c, i) {
                        final e = choices[i];
                        final selectedIds = selection.keys
                            .where((id) => conditionFamilyId(id) == e.id)
                            .toList();
                        final isSelected = selectedIds.isNotEmpty;
                        final hints = suggestedFor(e);
                        final label = categories[e.category]!;
                        return Padding(
                          key: ValueKey(e.id),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ControlCard(
                            title: e.name(ar),
                            subtitle: t(label.$1, label.$2),
                            icon: glyph(hints.first),
                            tonalColor: tint(hints.first),
                            selected: isSelected,
                            onTap: () => update(() {
                              if (!isSelected) {
                                selection[e.id] = _catalogSelection(
                                  e,
                                  known[e.id],
                                );
                              } else {
                                for (final id in selectedIds) {
                                  selection.remove(id);
                                }
                              }
                            }),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: JournalButton(
                  onPressed: moveToTrackers && selection.isEmpty
                      ? null
                      : () => Navigator.pop(c, true),
                  child: Text(
                    [
                      moveToTrackers
                          ? t('راجع المتابعات', 'Review trackers')
                          : t('احفظ الاختيارات', 'Save selections'),
                      selection.length,
                    ].join(' · '),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (accepted != true || !mounted) return;
    await save((draft) {
      _applyConditionSelection(
        draft,
        selection,
        withoutConditions: !moveToTrackers,
      );
      if (moveToTrackers) draft['stage'] = 4;
    });
  }
}
