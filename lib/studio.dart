part of 'main.dart';

extension _Studio on _HomeState {
  Widget _choiceSetting(
    BuildContext page,
    String label,
    String current,
    List<(String, String)> choices,
    ValueChanged<String> onChanged, {
    IconData icon = Icons.tune_rounded,
  }) => ControlCard(
    title: label,
    subtitle: choices.where((x) => x.$1 == current).firstOrNull?.$2,
    icon: icon,
    onTap: () async {
      final value = await _sheet<String>(
        (c) => SizedBox(
          height: math.min(
            MediaQuery.sizeOf(c).height * .7,
            choices.length * 84.0 + 66,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 10),
                child: Text(
                  label,
                  style: Theme.of(
                    c,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: choices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final (value, label) = choices[index];
                    return ControlCard(
                      title: label,
                      icon: icon,
                      selected: value == current,
                      onTap: () => Navigator.pop(c, value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (page.mounted && value != null) onChanged(value);
    },
  );

  Future<void> _conditions() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final conditions = rows(data['conditions']);
        final custom = rows(data['custom']);
        final active = conditions.where((x) => x['archived'] != true);
        final archived = conditions.where((x) => x['archived'] == true);
        Widget condition(JournalRow row) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: ControlCard(
                  title: conditionName(row, ar),
                  subtitle: strings(
                    row['links'],
                  ).map((id) => cardName(data, id, ar)).join(' · '),
                  icon: Icons.medical_information_outlined,
                  tonalColor: rose,
                  onTap: () => _conditionLinks(row),
                ),
              ),
              if (row['archived'] == true)
                IconButton(
                  tooltip: t('استرجع الحالة', 'Restore condition'),
                  icon: const Icon(Icons.unarchive_outlined),
                  onPressed: () => save(
                    (d) => upsert(d, 'conditions', {...row, 'archived': false}),
                  ),
                ),
            ],
          ),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(t('الحالات والمتابعات', 'Conditions and trackers')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              JournalCover(
                title: t('متابعات على مقاسك', 'Tracking that fits you'),
                subtitle: t(
                  'اختار حالاتك واربط بكل حالة المتابعات اللي تهمك.',
                  'Choose your conditions and link the trackers that matter.',
                ),
                icon: Icons.medical_information_outlined,
                accent: rose,
              ),
              const SizedBox(height: 12),
              ControlCard(
                title: t(
                  'اختار من مكتبة الحالات',
                  'Choose from the condition library',
                ),
                subtitle: t(
                  'ابحث أو تصفّح حسب التخصص',
                  'Search or browse by specialty',
                ),
                icon: Icons.search_rounded,
                tonalColor: mint,
                onTap: _pickConditions,
              ),
              if (active.isNotEmpty) ...[
                SectionTitle(t('حالاتي', 'My conditions')),
                for (final row in active) condition(row),
              ],
              if (archived.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(t('الحالات المؤرشفة', 'Archived conditions')),
                  children: [for (final row in archived) condition(row)],
                ),
              SectionTitle(t('المتابعات', 'Trackers')),
              ControlCard(
                title: t('اختار بطاقاتك', 'Choose your cards'),
                icon: Icons.dashboard_customize_outlined,
                onTap: _chooseTrackers,
              ),
              const SizedBox(height: 8),
              ControlCard(
                title: t('اعمل متابعة باسمك', 'Create a custom tracker'),
                icon: Icons.add_rounded,
                tonalColor: mint,
                onTap: _customTracker,
              ),
              for (final row in custom)
                if (trackerFor(data, row['id']) case final Tracker tracker)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ControlCard(
                      title: tracker.name(ar),
                      icon: glyph(tracker.id),
                      onTap: () => _trackerPreferences(tracker),
                    ),
                  ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _conditionLinks(JournalRow condition) async {
    final id = condition['id'] as String;
    final spec = catalogCondition(id);
    final variants = conditionVariants(conditionFamilyId(id));
    final checked = strings(condition['links']).toSet();
    var label = (condition['label'] as String?) ?? '';
    var note = (condition['profileNote'] as String?) ?? '';
    var variant =
        (condition['variant'] as String?) ??
        (variants.any((e) => e.id == id) && conditionFamilyId(id) != id
            ? id
            : '');
    var filter = '';
    final suggestions = suggestedFor(spec);
    final accepted = await _page<bool>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final ids =
              {
                    ...checked,
                    ...suggestions,
                    medicineCard,
                    ...allTrackers(data).map((x) => x.id),
                  }
                  .where(
                    (id) => normalize(
                      cardName(data, id, ar),
                    ).contains(normalize(filter)),
                  )
                  .toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(t('تخصيص الحالة', 'Customize condition')),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                JournalCover(
                  title: conditionName(condition, ar),
                  subtitle: t(
                    'اختار البطاقات المرتبطة بالحالة وسمّيها بالطريقة اللي تناسبك.',
                    'Choose the trackers linked to this condition and give it a name that works for you.',
                  ),
                  icon: Icons.medical_information_outlined,
                  accent: rose,
                ),
                const SizedBox(height: 12),
                if (variants.isNotEmpty) ...[
                  _choiceSetting(
                    c,
                    t('النوع (اختياري)', 'Type (optional)'),
                    variant,
                    [
                      ('', t('متابعة عامة', 'General tracking')),
                      for (final option in variants)
                        (option.id, option.name(ar)),
                    ],
                    (value) => redraw(() => variant = value),
                    icon: Icons.category_outlined,
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  initialValue: label,
                  maxLength: 65,
                  onChanged: (v) => label = v,
                  decoration: InputDecoration(
                    labelText: t(
                      'اسم العرض (اختياري)',
                      'Display name (optional)',
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: note,
                  maxLength: 300,
                  maxLines: 2,
                  onChanged: (v) => note = v,
                  decoration: InputDecoration(
                    labelText: t(
                      'ملاحظتي عن الحالة',
                      'My note about this condition',
                    ),
                    counterText: '',
                  ),
                ),
                SectionTitle(t('المتابعات المرتبطة', 'Linked trackers')),
                TextField(
                  onChanged: (v) => redraw(() => filter = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    labelText: t('ابحث عن متابعة', 'Find a tracker'),
                  ),
                ),
                const SizedBox(height: 8),
                if (ids.isEmpty)
                  Text(t('مفيش متابعة بالاسم ده.', 'No matching trackers.')),
                for (final id in ids)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ControlCard(
                      title: cardName(data, id, ar),
                      icon: glyph(id),
                      tonalColor: tint(id),
                      selected: checked.contains(id),
                      onTap: () => redraw(() {
                        if (!checked.remove(id)) checked.add(id);
                      }),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: JournalButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(t('احفظ التخصيص', 'Save customization')),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (accepted != true || !mounted) return;
    await save((d) {
      final current = rows(
        d['conditions'],
      ).where((c) => c['id'] == id).firstOrNull;
      if (current == null) return;
      final newlyLinked = checked.difference(strings(current['links']).toSet());
      upsert(d, 'conditions', {
        ...current,
        'links': checked.toList(),
        'label': label.trim(),
        'profileNote': note.trim(),
        'variant': variant,
      });
      if (current['archived'] != true) {
        final enabled = strings(d['enabled']).toSet();
        final hidden = strings(d['hidden']).toSet();
        final auto = strings(d['setupAuto']).toSet();
        for (final id in newlyLinked) {
          if (!hidden.contains(id) && enabled.add(id)) auto.add(id);
        }
        d['enabled'] = enabled.toList();
        d['setupAuto'] = auto.toList();
      }
    });
  }

  Future<void> _dashboard() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) => Scaffold(
        appBar: AppBar(title: Text(t('ترتيب صفحة اليوم', 'Arrange Today'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            JournalCover(
              title: t('بطاقات يومك', 'Your Today cards'),
              subtitle: t(
                'ثبّت المهم في الأول واضغط على البطاقة لتعديل عرضها.',
                'Pin what matters first. Tap a card to change how it reads.',
              ),
              icon: Icons.dashboard_customize_outlined,
            ),
            const SizedBox(height: 12),
            _cardControls(
              data,
              (update) => save(update),
              isToday: true,
              onlySelected: true,
            ),
            ControlCard(
              title: t('اختار البطاقات', 'Choose cards'),
              icon: Icons.add_rounded,
              tonalColor: mint,
              onTap: _chooseTrackers,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text(t('الترتيب حسب الاستخدام', 'Arrange by usage')),
              leading: const Icon(Icons.auto_awesome_outlined),
              children: [
                _layoutLearningControls(data, (update) => save(update)),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _layoutLearningControls(
    JournalRow prefs,
    void Function(void Function(JournalRow)) update, {
    bool widget = false,
  }) {
    final recommendation = proposeLayout(data, prefs, now, widget: widget);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(t('تعلّم ترتيب البطاقات', 'Learn card order')),
          trailing: DropdownButton<String>(
            value: prefs['layoutLearning'] as String? ?? 'off',
            items: [
              DropdownMenuItem(value: 'off', child: Text(t('متوقف', 'Off'))),
              DropdownMenuItem(
                value: 'suggest',
                child: Text(t('اقتراحات', 'Suggest')),
              ),
              DropdownMenuItem(
                value: 'auto',
                child: Text(t('تلقائي', 'Automatic')),
              ),
            ],
            onChanged: (mode) => update((d) => d['layoutLearning'] = mode),
          ),
        ),
        if (recommendation != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('سجّلت ', 'You logged ') +
                        cardName(data, recommendation.tracker, ar) +
                        t(' في ', ' on ') +
                        recommendation.count.toString() +
                        t(
                          ' أيام في الوقت ده تقريبًا.',
                          ' days around this time.',
                        ),
                  ),
                  Wrap(
                    spacing: 5,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => update(
                          (d) => _acceptLayout(
                            d,
                            recommendation.tracker,
                            recommendation.order,
                            now,
                          ),
                        ),
                        child: Text(t('قدّم البطاقة', 'Move card up')),
                      ),
                      TextButton(
                        onPressed: () => update(
                          (d) => d['layoutDecision'] = now.toIso8601String(),
                        ),
                        child: Text(t('تجاهل', 'Dismiss')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (prefs['layoutUndo'] is List)
          ListTile(
            subtitle: Text(
              t('تم تقديم بطاقة ', 'Moved up ') +
                  cardName(data, prefs['layoutChanged'] as String? ?? '', ar),
            ),
            trailing: TextButton(
              onPressed: () => update((d) {
                d['order'] = strings(d.remove('layoutUndo'));
                d['layoutDecision'] = now.toIso8601String();
              }),
              child: Text(t('تراجع', 'Undo')),
            ),
          ),
      ],
    );
  }

  void _acceptLayout(
    JournalRow prefs,
    String tracker,
    List<String> order,
    DateTime stamp,
  ) {
    prefs['layoutManual'] ??= strings(prefs['order']);
    prefs['layoutUndo'] = strings(prefs['order']);
    prefs['layoutChanged'] = tracker;
    prefs['layoutAppliedDay'] = dayKey(stamp);
    prefs['order'] = order;
  }

  Future<void> _autoArrange(DateTime stamp) async {
    bool mayChange(JournalRow prefs) =>
        prefs['layoutLearning'] == 'auto' &&
        prefs['layoutAppliedDay'] != dayKey(stamp);
    final any =
        mayChange(data) && proposeLayout(data, data, stamp) != null ||
        rows(data['widgets']).any(
          (w) =>
              mayChange(w) &&
              proposeLayout(data, w, stamp, widget: true) != null,
        );
    if (!any) return;
    await save((draft) {
      void adjust(JournalRow prefs, {bool widget = false}) {
        if (!mayChange(prefs)) return;
        final advice = proposeLayout(draft, prefs, stamp, widget: widget);
        if (advice != null) {
          _acceptLayout(prefs, advice.tracker, advice.order, stamp);
        }
      }

      adjust(draft);
      final layouts = rows(draft['widgets']);
      for (final layout in layouts) {
        adjust(layout, widget: true);
      }
      draft['widgets'] = layouts;
    });
  }

  Widget _cardControls(
    JournalRow prefs,
    void Function(void Function(JournalRow)) update, {
    bool isToday = false,
    bool onlySelected = false,
  }) {
    final shown = cardPlan(data, isToday ? null : prefs);
    final list = onlySelected
        ? shown
        : {
            ...shown,
            medicineCard,
            ...allTrackers(data).map((x) => x.id),
          }.toList();
    final reasons = recommendations(data, ar);
    void changeVisibility(String id, bool visible) => update((d) {
      if (!isToday) {
        setWidgetCardVisibility(data, d, id, visible);
        return;
      }
      if (visible) {
        d['enabled'] = {...strings(d['enabled']), id}.toList();
        d['hidden'] = strings(d['hidden'])..remove(id);
      } else {
        d['hidden'] = {...strings(d['hidden']), id}.toList();
      }
      d['setupAuto'] = strings(d['setupAuto'])..remove(id);
    });

    return Column(
      children: [
        for (final id in list)
          Padding(
            key: ValueKey(id),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: ControlCard(
                    title: cardName(data, id, ar),
                    subtitle: reasons[id]?.join(' · '),
                    icon: glyph(id),
                    tonalColor: tint(id),
                    selected: isToday ? null : shown.contains(id),
                    onTap: isToday
                        ? () {
                            final tracker = trackerFor(data, id);
                            if (tracker != null) {
                              _trackerPreferences(tracker);
                            } else if (data['stage'] == 3) {
                              _medicine();
                            }
                          }
                        : () => changeVisibility(id, !shown.contains(id)),
                    trailing:
                        isToday && id == medicineCard && data['stage'] != 3
                        ? const SizedBox.shrink()
                        : null,
                  ),
                ),
                if (shown.contains(id))
                  PopupMenuButton<String>(
                    tooltip: t('خيارات البطاقة', 'Card options'),
                    icon: Icon(
                      strings(prefs['pinned']).contains(id)
                          ? Icons.push_pin_outlined
                          : Icons.more_vert_rounded,
                    ),
                    onSelected: (action) {
                      if (action == 'hide') {
                        changeVisibility(id, false);
                        return;
                      }
                      update((d) {
                        final pinned = strings(d['pinned']);
                        if (action == 'pin') {
                          if (!pinned.remove(id)) pinned.add(id);
                          d['pinned'] = pinned;
                          return;
                        }
                        final isPinned = pinned.contains(id);
                        final ordered = shown
                            .where(
                              (other) => pinned.contains(other) == isPinned,
                            )
                            .toList();
                        final from = ordered.indexOf(id);
                        final to = (from + (action == 'up' ? -1 : 1)).clamp(
                          0,
                          ordered.length - 1,
                        );
                        ordered.insert(to, ordered.removeAt(from));
                        d[isPinned ? 'pinned' : 'order'] = ordered;
                      });
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          strings(prefs['pinned']).contains(id)
                              ? t('إلغاء التثبيت', 'Unpin')
                              : t('ثبّت في الأول', 'Pin first'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'up',
                        child: Text(t('حرّك للأعلى', 'Move up')),
                      ),
                      PopupMenuItem(
                        value: 'down',
                        child: Text(t('حرّك للأسفل', 'Move down')),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(t('أخفِ البطاقة', 'Hide card')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _customTracker() async {
    var name = '', unit = '', kind = 'number';
    final chosen = await _sheet<bool>(
      (c) => StatefulBuilder(
        builder: (c, redraw) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(c).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JournalCover(
                  title: t('متابعة مخصصة', 'Custom tracker'),
                  subtitle: t(
                    'اختار نوع القياس واكتب اسم يفكّرك بيه.',
                    'Choose the kind of data and give it a name.',
                  ),
                  icon: Icons.add_chart_outlined,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: t('الاسم', 'Name'),
                    counterText: '',
                  ),
                  onChanged: (x) => name = x,
                ),
                const SizedBox(height: 8),
                _choiceSetting(
                  c,
                  t('نوع القيمة', 'Value type'),
                  kind,
                  [
                    for (final (id, a, e) in [
                      ('number', 'رقم', 'Number'),
                      ('duration', 'مدة', 'Duration'),
                      ('bool', 'نعم أو لا', 'Yes or no'),
                      ('text', 'نص', 'Text'),
                    ])
                      (id, t(a, e)),
                  ],
                  (v) => redraw(() => kind = v),
                  icon: Icons.category_outlined,
                ),
                AnimatedSize(
                  duration: motion(c, 230),
                  alignment: Alignment.topCenter,
                  child: kind == 'number'
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextFormField(
                            maxLength: 16,
                            decoration: InputDecoration(
                              labelText: t(
                                'الوحدة (اختياري)',
                                'Unit (optional)',
                              ),
                              counterText: '',
                            ),
                            onChanged: (x) => unit = x,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                JournalButton(
                  onPressed: () {
                    if (name.trim().isNotEmpty) Navigator.pop(c, true);
                  },
                  child: Text(t('أضف', 'Add')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != true) return;
    final id = newId();
    await save((d) {
      upsert(d, 'custom', {
        'id': id,
        'name': name.trim(),
        'kind': kind == 'duration' ? 'number' : kind,
        'unit': kind == 'duration'
            ? 'min'
            : kind == 'number'
            ? unit.trim()
            : '',
      });
      d['enabled'] = {...strings(d['enabled']), id}.toList();
    });
  }

  Future<void> _openStudio() async {
    var installed = <int>[];
    if (Platform.isAndroid) {
      try {
        installed =
            await platform.invokeListMethod<int>('installedWidgetIds') ?? [];
      } on PlatformException catch (_) {
        // Saved layouts remain available if device widget enumeration fails.
      }
    }
    if (!mounted) return;
    await _page<void>(
      (_) => ListenableBuilder(
        listenable: widget.db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: Text(t('استوديو الويدجت', 'Widget Studio'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 9, 18, 40),
            children: [
              JournalCover(
                kicker: t('الشاشة الرئيسية', 'Home screen'),
                title: t('ويدجت على مقاسك', 'A widget that fits'),
                icon: Icons.widgets_outlined,
                accent: lavender,
                subtitle: t(
                  'اختار البطاقات والشكل والبيانات اللي تحب تظهر على الشاشة الرئيسية.',
                  'Choose the cards, look and information shown on your home screen.',
                ),
              ),
              if (installed.isNotEmpty) ...[
                SectionTitle(t('الويدجتس المثبّتة', 'Installed widgets')),
                for (final (index, id) in installed.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ControlCard(
                      title: t('الويدجت ${index + 1}', 'Widget ${index + 1}'),
                      subtitle: t(
                        'عدّل محتوى النسخة دي على الشاشة الرئيسية',
                        'Edit this widget on your home screen',
                      ),
                      icon: Icons.home_outlined,
                      onTap: () => _openWidgetInstance(id),
                    ),
                  ),
              ],
              if (_widgetError)
                ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(
                    t(
                      'تعذّر تحديث الويدجت. افتح التركيبة واضغط «احفظ» لإعادة المحاولة.',
                      'The widget could not refresh. Open the layout and save it to retry.',
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              ControlCard(
                onTap: () => _widgetEditor(widgetConfig(data)),
                icon: Icons.view_quilt_outlined,
                title: t('ابدأ بالتركيبة المقترحة', 'Use suggested layout'),
                subtitle: t(
                  'تتزامن مع بطاقات اليوم',
                  'Follows your Today cards',
                ),
                tonalColor: mint,
              ),
              const SizedBox(height: 8),
              if (cardPlan(data).where((id) => id != medicineCard).firstOrNull
                  case final String id) ...[
                ControlCard(
                  onTap: () => _widgetEditor(
                    widgetConfig(data, empty: true)
                      ..['enabled'] = [id]
                      ..['columns'] = 1,
                  ),
                  icon: glyph(id),
                  title: t('قياس واحد', 'One tracker'),
                  subtitle: cardName(data, id, ar),
                  tonalColor: ice,
                ),
                const SizedBox(height: 8),
              ],
              ControlCard(
                onTap: () => _widgetEditor(
                  widgetConfig(data, empty: true)
                    ..['enabled'] = [medicineCard]
                    ..['columns'] = 1,
                ),
                icon: Icons.medication_outlined,
                title: t('مواعيد الدوا', 'Medication schedule'),
                subtitle: t(
                  'بطاقة الجرعات واختصار روتيني',
                  'Doses and a Routine shortcut',
                ),
                tonalColor: honey,
              ),
              const SizedBox(height: 8),
              ControlCard(
                onTap: () => _widgetEditor(widgetConfig(data, empty: true)),
                icon: Icons.add_rounded,
                title: t('ابدأ من مساحة فاضية', 'Start from scratch'),
              ),
              if (cardPlan(data).isNotEmpty) ...[
                const SizedBox(height: 8),
                ControlCard(
                  onTap: () => _widgetEditor(
                    widgetConfig(data)
                      ..['clock'] = true
                      ..['columns'] = 3
                      ..['featured'] = false,
                  ),
                  icon: Icons.watch_later_outlined,
                  title: t('ساعة ومتابعات', 'Clock and trackers'),
                  subtitle: t('التاريخ فوق البطاقات', 'Date above your cards'),
                  tonalColor: honey,
                ),
              ],
              if (rows(data['widgets']).isNotEmpty)
                SectionTitle(t('تصميماتي', 'My layouts')),
              for (final (index, w) in rows(data['widgets']).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.widgets_outlined),
                      title: Text(
                        (w['name'] as String).isEmpty
                            ? t('تركيبة ', 'Layout ') + (index + 1).toString()
                            : w['name'],
                      ),
                      onTap: () => _widgetEditor(w),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'copy') {
                            await _widgetEditor({
                              ...w,
                              'id': newId(),
                              'name': '',
                            });
                          } else if (await _confirm(
                            t('حذف التركيبة؟', 'Delete layout?'),
                            t(
                              'الويدجت المرتبط بها هيعرض التركيبة الافتراضية.',
                              'Widgets using this layout will fall back to the default.',
                            ),
                            t('احذف', 'Delete'),
                          )) {
                            await save((d) => removeRow(d, 'widgets', w['id']));
                          }
                        },
                        itemBuilder: (c) => [
                          PopupMenuItem(
                            value: 'copy',
                            child: Text(t('نسخ التركيبة', 'Duplicate layout')),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(t('حذف', 'Delete')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _previewAction(String route, bool demo) {
    final parts = route.split('/');
    if (!demo && parts.first != 'cup') {
      unawaited(_route(route));
      return;
    }
    final id = parts.elementAtOrNull(1) ?? '';
    _toast(switch (parts.first) {
      'cup' => t(
        'الاختصار يسجّل حجم الكوب الافتراضي عند تثبيته',
        'The pinned shortcut logs your default cup',
      ),
      'dose' => t(
        'الاختصار يفتح تأكيد الجرعة',
        'Shortcut opens dose confirmation',
      ),
      'routine' => t('الاختصار يفتح روتيني', 'Shortcut opens Routine'),
      'add' =>
        t('الاختصار يفتح التسجيل في ', 'Shortcut opens logging for ') +
            cardName(data, id, ar),
      _ =>
        t('الاختصار يفتح تفاصيل ', 'Shortcut opens details for ') +
            cardName(data, id, ar),
    });
  }

  Future<void> _openWidgetInstance(int id) async {
    Map<String, dynamic>? binding;
    if (Platform.isAndroid) {
      try {
        binding = await platform.invokeMapMethod<String, dynamic>(
          'activeWidgetLayout',
          id,
        );
      } catch (_) {
        // A new or previously unassigned widget can still start from Today.
      }
    }
    if (!mounted) return;
    final existing = rows(
      data['widgets'],
    ).where((row) => row['id'] == binding?['key']).firstOrNull;
    final draft = existing == null
        ? widgetConfig(data)
        : binding?['editable'] == true
        ? existing
        : {...existing, 'id': newId()};
    final nativeWidth = binding?['width'], nativeHeight = binding?['height'];
    await _widgetEditor(
      draft,
      widgetId: id,
      nativeSize: nativeWidth is num && nativeHeight is num
          ? Size(nativeWidth.toDouble(), nativeHeight.toDouble())
          : null,
    );
  }

  Future<void> _widgetEditor(
    JournalRow source, {
    int? widgetId,
    Size? nativeSize,
  }) {
    final draft = Map<String, dynamic>.from(source)..remove('size');
    var demo = widgetId == null, busy = false;
    var panel = 1;
    var setDefault =
        data['widgetDefault'] == null || data['widgetDefault'] == source['id'];
    var width = (nativeSize?.width ?? 330.0).clamp(48.0, 800.0),
        height = (nativeSize?.height ?? 240.0).clamp(48.0, 900.0);
    return _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final viewport = Size(width, height);
          final scene = WidgetScene.responsive(
            data,
            draft,
            ar,
            viewport,
            demo: demo,
            systemDark: MediaQuery.platformBrightnessOf(c) == Brightness.dark,
          );
          Future<void> editCard(String id) async {
            final changes = await _widgetCardOptions(draft, id);
            if (!c.mounted || changes == null) return;
            final visible = changes.remove('showCard') == true;
            redraw(() {
              if (visible != cardPlan(data, draft).contains(id)) {
                setWidgetCardVisibility(data, draft, id, visible);
              }
              draft['cardOptions'] = {
                ...(draft['cardOptions'] as Map? ?? {}),
                id: changes,
              };
            });
          }

          Future<void> commit({bool pin = false}) async {
            if (busy || pin && !Platform.isAndroid) return;
            redraw(() => busy = true);
            try {
              final bound = pin
                  ? await platform.invokeListMethod<String>('boundLayouts') ??
                        []
                  : const <String>[];
              final chosen = pin && bound.contains(draft['id'])
                  ? {...draft, 'id': newId(), 'name': ''}
                  : <String, dynamic>{...draft};
              if (!await save((d) {
                    upsert(d, 'widgets', chosen);
                    if (widgetId == null && !pin) {
                      if (setDefault) {
                        d['widgetDefault'] = chosen['id'];
                      } else if (d['widgetDefault'] == chosen['id']) {
                        d.remove('widgetDefault');
                      }
                    }
                  }) ||
                  !c.mounted)
                return;
              await _publisher.update(
                data,
                ar,
                widgetId: pin ? null : widgetId,
                layout: chosen['id'] as String,
              );
              if (!c.mounted) return;
              if (!pin) {
                Navigator.pop(c);
                _toast(
                  widgetId == null
                      ? t('اتحفظ التصميم', 'Layout saved')
                      : t('اتحدّث الويدجت', 'Widget updated'),
                );
                return;
              }
              final success = await platform.invokeMethod<bool>('pin', {
                'id': chosen['id'],
              });
              if (c.mounted && success != true) {
                _toast(
                  t(
                    'ضيف «يومي» من قائمة الويدجت في الشاشة الرئيسية.',
                    'Add Yawmi from your home-screen widget picker.',
                  ),
                );
              }
            } catch (_) {
              if (c.mounted)
                _toast(
                  t(
                    'اتحفظ التصميم، وتعذّر تحديث الويدجت على الشاشة الرئيسية.',
                    'The layout was saved, but the home-screen widget could not update.',
                  ),
                );
            } finally {
              if (c.mounted) redraw(() => busy = false);
            }
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(t('تحرير الويدجت', 'Edit widget')),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(53),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: SegmentedControl(
                    labels: [
                      t('البطاقات', 'Cards'),
                      t('الشكل', 'Appearance'),
                      t('الخصوصية', 'Privacy'),
                    ],
                    index: panel == 2 ? 2 : 1 - panel,
                    background: Theme.of(c).colorScheme.surfaceContainerHigh,
                    foreground: Theme.of(c).colorScheme.onSurface,
                    onChanged: (index) =>
                        redraw(() => panel = index == 2 ? 2 : 1 - index),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(15, 8, 15, 9),
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(c).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: JournalButton(
                        onPressed: busy ? null : () => commit(),
                        child: Text(
                          widgetId == null
                              ? t('احفظ', 'Save')
                              : t('احفظ للويدجت ده', 'Save this widget'),
                        ),
                      ),
                    ),
                    if (widgetId == null) const SizedBox(width: 8),
                    if (widgetId == null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => commit(pin: true),
                          icon: const Icon(Icons.add_to_home_screen_outlined),
                          label: Text(t('ثبّت', 'Pin')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            body: ListView(
              key: ValueKey(panel),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                if (panel == 1) ...[
                  ControlCard(
                    title: t('اختار البطاقات', 'Choose cards'),
                    subtitle: scene.cards.isEmpty
                        ? t('مفيش بطاقات مختارة', 'No cards selected')
                        : t(
                            'البطاقات المختارة · ${scene.cards.length + scene.cropped.length}',
                            'Selected cards · ${scene.cards.length + scene.cropped.length}',
                          ),
                    icon: Icons.dashboard_customize_outlined,
                    tonalColor: mint,
                    onTap: () => _chooseWidgetCards(draft, viewport, redraw),
                  ),
                  const SizedBox(height: 8),
                  ControlCard(
                    title: t('عناصر الويدجت', 'Widget elements'),
                    subtitle: t(
                      'الساعة، التاريخ، الأزرار والرسومات',
                      'Clock, date, buttons and artwork',
                    ),
                    icon: Icons.visibility_outlined,
                    onTap: () => _widgetElements(draft, redraw),
                  ),
                  const SizedBox(height: 8),
                ],
                if (panel == 2) ...[
                  SwitchListTile(
                    title: Text(
                      t('إظهار قيم المتابعات', 'Show tracker values'),
                    ),
                    subtitle: Text(
                      t(
                        'الإعداد الافتراضي للبطاقات',
                        'Default for tracker cards',
                      ),
                    ),
                    value: draft['values'] == true,
                    onChanged: (on) => redraw(() => draft['values'] = on),
                  ),
                  SwitchListTile(
                    title: Text(
                      t(
                        'إظهار أسماء ومواعيد الأدوية',
                        'Show medication names and times',
                      ),
                    ),
                    value: draft['names'] == true,
                    onChanged: (on) => redraw(() => draft['names'] = on),
                  ),
                ],
                Card(
                  color: Theme.of(c).colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            t('معاينة الويدجت', 'Widget preview'),
                            style: Theme.of(c).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'كبّر الويدجت من الشاشة الرئيسية عشان تظهر بطاقات أكتر.',
                            'Resize on your home screen to see more cards.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 7),
                        ExpansionTile(
                          key: const PageStorageKey('widget-resize'),
                          leading: const Icon(Icons.open_in_full_rounded),
                          title: Text(
                            t('جرّب تغيير الحجم', 'Preview resizing'),
                          ),
                          children: [
                            Text(t('عرض المعاينة', 'Preview width')),
                            Slider(
                              key: const ValueKey('widget-preview-width'),
                              value: width,
                              min: 48,
                              max: 800,
                              semanticFormatterCallback: (value) =>
                                  '${value.round()} dp',
                              onChanged: (value) => redraw(() => width = value),
                            ),
                            Text(t('ارتفاع المعاينة', 'Preview height')),
                            Slider(
                              key: const ValueKey('widget-preview-height'),
                              value: height,
                              min: 48,
                              max: 900,
                              semanticFormatterCallback: (value) =>
                                  '${value.round()} dp',
                              onChanged: (value) =>
                                  redraw(() => height = value),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 7,
                          runSpacing: 4,
                          children: [
                            FilterChip(
                              avatar: const Icon(
                                Icons.schedule_rounded,
                                size: 18,
                              ),
                              label: Text(
                                scene.clockDate
                                    ? t('ساعة وتاريخ', 'Clock & date')
                                    : t('ساعة', 'Clock'),
                              ),
                              selected: draft['clock'] == true,
                              onSelected: (on) =>
                                  redraw(() => draft['clock'] = on),
                            ),
                            ChoiceChip(
                              label: Text(t('أعمدة تلقائية', 'Auto columns')),
                              selected: draft['columns'] == null,
                              onSelected: (_) =>
                                  redraw(() => draft.remove('columns')),
                            ),
                            for (var n = 1; n <= 3; n++)
                              ChoiceChip(
                                showCheckmark: false,
                                label: Text(t('$n في الصف', '$n per row')),
                                selected: draft['columns'] == n,
                                onSelected: (_) {
                                  unawaited(HapticFeedback.selectionClick());
                                  redraw(() {
                                    draft['columns'] = n;
                                    if (n == 3) draft['featured'] = false;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        AnimatedSize(
                          duration: motion(c, 330),
                          curve: Curves.easeInOutCubic,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final size = viewport;
                              final scale = math.min(
                                1.0,
                                math.min(
                                  box.maxWidth / size.width,
                                  math.max(
                                        138.0,
                                        MediaQuery.sizeOf(c).height * .40,
                                      ) /
                                      size.height,
                                ),
                              );
                              return AnimatedSwitcher(
                                duration: motion(c, 530),
                                reverseDuration: motion(c, 360),
                                transitionBuilder: (child, progress) =>
                                    AnimatedBuilder(
                                      animation: progress,
                                      child: child,
                                      builder: (_, tile) {
                                        final t = motionArrival.transform(
                                          progress.value,
                                        );
                                        final alpha =
                                            progress.status ==
                                                AnimationStatus.reverse
                                            ? Curves.easeInExpo.transform(
                                                progress.value,
                                              )
                                            : const Interval(
                                                .10,
                                                .68,
                                                curve: Curves.easeOut,
                                              ).transform(progress.value);
                                        final rtl =
                                            Directionality.of(c) ==
                                            TextDirection.rtl;
                                        return Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()
                                            ..setEntry(3, 2, .0012)
                                            ..rotateY(
                                              (1 - t) * (rtl ? -.33 : .33),
                                            ),
                                          child: Transform.translate(
                                            offset: Offset(0, 17 * (1 - t)),
                                            child: Transform.scale(
                                              scale: .84 + t * .16,
                                              child: Opacity(
                                                opacity: alpha,
                                                child: tile,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    for (final old in previous)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: old,
                                          ),
                                        ),
                                      ),
                                    ?current,
                                  ],
                                ),
                                child: SizedBox(
                                  key: ValueKey((
                                    scene.rowCapacity,
                                    scene.columns,
                                    scene.clock,
                                    scene.featured,
                                  )),
                                  width: size.width * scale,
                                  height: size.height * scale,
                                  child: FittedBox(
                                    child: SizedBox.fromSize(
                                      size: size,
                                      child: MediaQuery(
                                        data: MediaQuery.of(c).copyWith(
                                          textScaler: TextScaler.noScaling,
                                        ),
                                        child: SceneArt(
                                          scene,
                                          onCardTap: editCard,
                                          onTap: (route) {
                                            if (route == 'preview/settings') {
                                              unawaited(
                                                _widgetElements(draft, redraw),
                                              );
                                            } else if (route ==
                                                'preview/refresh') {
                                              redraw(() {});
                                              _toast(
                                                t(
                                                  'اتحدّثت المعاينة',
                                                  'Preview refreshed',
                                                ),
                                              );
                                            } else {
                                              _previewAction(route, demo);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedControl(
                          labels: [
                            t('بيانات تجريبية', 'Sample data'),
                            t('بياناتي', 'My data'),
                          ],
                          index: demo ? 0 : 1,
                          background: Theme.of(c).colorScheme.surface,
                          foreground: Theme.of(c).colorScheme.onSurface,
                          onChanged: (i) => redraw(() => demo = i == 0),
                        ),
                      ],
                    ),
                  ),
                ),
                if (scene.cropped.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      t('تظهر في حجم أكبر: ', 'Visible in larger sizes: ') +
                          scene.cropped
                              .map((id) => cardName(data, id, ar))
                              .join(' · '),
                    ),
                  ),
                const SizedBox(height: 14),
                if (panel == 0) ...[
                  TextFormField(
                    initialValue: draft['name'],
                    maxLength: 55,
                    onChanged: (x) => draft['name'] = x,
                    decoration: InputDecoration(
                      labelText: t('اسم التركيبة', 'Layout name'),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 3,
                    children: [
                      for (final (index, label) in [
                        t('إيقاع اليوم', 'Daily rhythm'),
                        t('لوحة القياسات', 'Readings board'),
                        t('بطاقة سريعة', 'Quick card'),
                        t('ورق', 'Paper'),
                        t('ألوان', 'Color blocks'),
                      ].indexed)
                        ChoiceChip(
                          label: Text(label),
                          selected: draft['style'] == index,
                          onSelected: (_) =>
                              redraw(() => draft['style'] = index),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 5,
                    children: [
                      for (final (index, color) in palettes.indexed)
                        IconButton(
                          onPressed: () => redraw(() {
                            draft['palette'] = index;
                            draft.remove('customColor');
                          }),
                          tooltip: t('لون ', 'Color ') + (index + 1).toString(),
                          icon: CircleAvatar(
                            radius: 15,
                            backgroundColor: color,
                            child:
                                draft['palette'] == index &&
                                    draft['customColor'] == null
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 17,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (id, a, e) in [
                        ('system', 'حسب النظام', 'System'),
                        ('light', 'فاتح', 'Light'),
                        ('dark', 'داكن', 'Dark'),
                      ])
                        ChoiceChip(
                          label: Text(t(a, e)),
                          selected: draft['appearance'] == id,
                          onSelected: (_) =>
                              redraw(() => draft['appearance'] = id),
                        ),
                    ],
                  ),
                  ControlCard(
                    title: t('لون مخصص', 'Custom color'),
                    subtitle: draft['customColor'] == null
                        ? t('اختار بالكود السداسي', 'Set a hex color')
                        : '#' +
                              (draft['customColor'] as int)
                                  .toRadixString(16)
                                  .padLeft(6, '0')
                                  .toUpperCase(),
                    icon: Icons.palette_outlined,
                    onTap: () async {
                      final rgb = await _textPrompt(
                        t('لون الويدجت', 'Widget color'),
                        t('مثال ‎#185345', 'Example #185345'),
                        initial: scene.accent
                            .toARGB32()
                            .toRadixString(16)
                            .substring(2)
                            .toUpperCase(),
                      );
                      if (!c.mounted || rgb == null) return;
                      if (!RegExp(r'^#?[a-fA-F\d]{6}$').hasMatch(rgb.trim())) {
                        _toast(
                          t(
                            'اكتب ٦ أحرف أو أرقام من كود اللون.',
                            'Enter a six-digit hex color.',
                          ),
                        );
                        return;
                      }
                      redraw(
                        () => draft['customColor'] = int.parse(
                          rgb.replaceAll('#', '').trim(),
                          radix: 16,
                        ),
                      );
                    },
                  ),
                  if (scene.rowCapacity > 1 && scene.columns > 1)
                    SwitchListTile(
                      secondary: const Icon(Icons.view_agenda_outlined),
                      title: Text(
                        t('أول بطاقة بعرض الويدجت', 'Full-width first card'),
                      ),
                      value: scene.featured,
                      onChanged: (on) => redraw(() => draft['featured'] = on),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.add_box_outlined),
                    title: Text(t('زر التسجيل السريع', 'Quick entry button')),
                    subtitle: Text(
                      t(
                        'يظهر تحت البطاقات لو فيه مساحة',
                        'Appears beneath the cards when there is room',
                      ),
                    ),
                    value: draft['showShortcut'] != false,
                    onChanged: (on) => redraw(() => draft['showShortcut'] = on),
                  ),
                  if (draft['clock'] == true) ...[
                    const SizedBox(height: 8),
                    _choiceSetting(
                      c,
                      t('أرقام الساعة', 'Clock digits'),
                      scene.timeLanguage,
                      [
                        ('en', t('English · 09:41', 'English · 09:41')),
                        ('ar', t('العربية · ٠٩:٤١', 'Arabic · ٠٩:٤١')),
                      ],
                      (v) => redraw(() => draft['timeLanguage'] = v),
                      icon: Icons.pin_outlined,
                    ),
                    const SizedBox(height: 8),
                    _choiceSetting(
                      c,
                      t('نظام الوقت', 'Time format'),
                      scene.clockFormat,
                      [
                        ('system', t('تلقائي', 'Automatic')),
                        ('12', t('١٢ ساعة', '12-hour')),
                        ('24', t('٢٤ ساعة', '24-hour')),
                      ],
                      (v) => redraw(() => draft['clockFormat'] = v),
                      icon: Icons.schedule_rounded,
                    ),
                    SwitchListTile(
                      title: Text(t('إظهار التاريخ', 'Show date')),
                      value: scene.clockDate,
                      onChanged: (on) => redraw(() => draft['clockDate'] = on),
                    ),
                    if (scene.clockDate)
                      _choiceSetting(
                        c,
                        t('لغة التاريخ', 'Date language'),
                        scene.clockLanguage,
                        [
                          ('app', t('لغة يومي', 'Yawmi language')),
                          ('ar', 'العربية'),
                          ('en', 'English'),
                        ],
                        (v) => redraw(() => draft['clockLanguage'] = v),
                        icon: Icons.calendar_month_outlined,
                      ),
                  ],
                  for (final (key, title, icon, fallback) in [
                    (
                      'artwork',
                      t('رسومات البطاقات', 'Card artwork'),
                      Icons.texture_rounded,
                      true,
                    ),
                    (
                      'icons',
                      t('أيقونات البطاقات', 'Card icons'),
                      Icons.widgets_outlined,
                      true,
                    ),
                    (
                      'largeValues',
                      t('قيم أكبر', 'Larger values'),
                      Icons.format_size_rounded,
                      false,
                    ),
                  ])
                    SwitchListTile(
                      secondary: Icon(icon),
                      title: Text(title),
                      value: draft[key] as bool? ?? fallback,
                      onChanged: (on) => redraw(() => draft[key] = on),
                    ),
                  SwitchListTile(
                    title: Text(t('عرض مدمج', 'Compact layout')),
                    value: draft['compact'] == true,
                    onChanged: (on) => redraw(() => draft['compact'] = on),
                  ),
                  if (draft['clock'] != true && !scene.slim)
                    SwitchListTile(
                      title: Text(t('إظهار اسم الويدجت', 'Show widget header')),
                      value: draft['header'] != false,
                      onChanged: (on) => redraw(() => draft['header'] = on),
                    ),
                  SwitchListTile(
                    title: Text(t('حواف مستديرة', 'Soft corners')),
                    value: draft['softCorners'] != false,
                    onChanged: (on) => redraw(() => draft['softCorners'] = on),
                  ),
                  ListTile(
                    title: Text(t('عتامة الخلفية', 'Background opacity')),
                    subtitle: Slider(
                      min: .92,
                      max: 1,
                      divisions: 8,
                      value: (draft['opacity'] as num? ?? 1).toDouble().clamp(
                        .92,
                        1.0,
                      ),
                      label:
                          '${((draft['opacity'] as num? ?? 1) * 100).round()}%',
                      onChanged: (n) => redraw(() => draft['opacity'] = n),
                    ),
                  ),
                ],
                if (panel == 1) ...[
                  ExpansionTile(
                    title: Text(t('الترتيب والإجراءات', 'Order and actions')),
                    leading: const Icon(Icons.tune_rounded),
                    children: [
                      if (draft['automatic'] == true)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: draft['condition'] as String? ?? '',
                            decoration: InputDecoration(
                              labelText: t(
                                'نطاق البطاقات التلقائية',
                                'Automatic card scope',
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  t('كل بطاقات اليوم', 'All Today cards'),
                                ),
                              ),
                              for (final condition in rows(data['conditions']))
                                if (condition['archived'] != true ||
                                    condition['id'] == draft['condition'])
                                  DropdownMenuItem(
                                    value: condition['id'] as String,
                                    child: Text(
                                      conditionName(condition, ar),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            ],
                            onChanged: (v) => redraw(() {
                              if (v == null || v.isEmpty) {
                                draft.remove('condition');
                              } else {
                                draft['condition'] = v;
                              }
                            }),
                          ),
                        ),
                      if (draft['automatic'] == true &&
                          draft['condition'] != null)
                        ControlCard(
                          title: t(
                            'اعرض بيانات الحالة فقط',
                            'Use only this condition’s data',
                          ),
                          subtitle: t(
                            'يحسب القيم من الإدخالات المرتبطة بالحالة.',
                            'Summarizes entries linked to the condition.',
                          ),
                          icon: Icons.filter_alt_outlined,
                          selected: draft['scopeValues'] == true,
                          onTap: () => redraw(
                            () => draft['scopeValues'] =
                                draft['scopeValues'] != true,
                          ),
                        ),
                      if (draft['summary'] == true)
                        SwitchListTile(
                          title: Text(
                            t(
                              'استخدم إعداد متوسط ٧ أيام القديم',
                              'Keep the previous 7-day average setting',
                            ),
                          ),
                          value: draft['summary'] == true,
                          onChanged: (on) =>
                              redraw(() => draft['summary'] = on),
                        ),
                      SwitchListTile(
                        title: Text(
                          t(
                            'الضغط يفتح نموذج التسجيل',
                            'Tapping opens the entry form',
                          ),
                        ),
                        value: draft['add'] == true,
                        onChanged: (on) => redraw(() => draft['add'] = on),
                      ),
                      if (cardPlan(data, draft).contains('water'))
                        SwitchListTile(
                          title: Text(
                            t(
                              'زر المياه يسجّل حجم الكوب الافتراضي',
                              'Water shortcut logs the default cup size',
                            ),
                          ),
                          value: draft['quickWater'] == true,
                          onChanged: (on) =>
                              redraw(() => draft['quickWater'] = on),
                        ),
                      _layoutLearningControls(
                        draft,
                        (update) => redraw(() => update(draft)),
                        widget: true,
                      ),
                      ExpansionTile(
                        title: Text(
                          t('رتّب البطاقات المختارة', 'Reorder selected cards'),
                        ),
                        children: [
                          _cardControls(
                            draft,
                            (update) => redraw(() => update(draft)),
                            onlySelected: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widgetId == null)
                    SwitchListTile(
                      title: Text(
                        t('استخدم كتصميم افتراضي', 'Use as default layout'),
                      ),
                      subtitle: Text(
                        t(
                          'يتطبّق على الويدجتس اللي ملهاش تصميم محدد',
                          'Applies to widgets without a specific layout',
                        ),
                      ),
                      value: setDefault,
                      onChanged: (on) => redraw(() => setDefault = on),
                    ),
                  if (cardPlan(data, draft).isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionTitle(
                          t('تخصيص كل بطاقة', 'Customize individual cards'),
                        ),
                        for (final id in cardPlan(data, draft))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ControlCard(
                              icon: glyph(id),
                              tonalColor: tint(id),
                              title: scene.title(id),
                              onTap: () => editCard(id),
                            ),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _chooseWidgetCards(
    JournalRow draft,
    Size viewport,
    StateSetter updateEditor,
  ) async {
    final choices = {
      ...cardPlan(data, draft),
      ...cardPlan(data),
      medicineCard,
      ...allTrackers(data).map((tracker) => tracker.id),
    }.toList();
    var query = '';
    await _sheet<void>(
      (c) => StatefulBuilder(
        builder: (s, repaint) {
          final scene = WidgetScene.responsive(data, draft, ar, viewport);
          final selected = cardPlan(data, draft).toSet();
          final fits = scene.cards.toSet();
          final shown = choices
              .where(
                (id) =>
                    scene.title(id).toLowerCase().contains(query) ||
                    cardName(data, id, ar).toLowerCase().contains(query),
              )
              .toList();
          void change(VoidCallback edit) {
            updateEditor(edit);
            repaint(() {});
          }

          return _JournalPanel(
            heightFactor: .87,
            heading: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t('اختار البطاقات', 'Choose cards'),
                  style: Theme.of(s).textTheme.titleLarge,
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (choices.length > 8)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: t('دوّر على متابعة', 'Find a tracker'),
                      ),
                      onChanged: (text) =>
                          repaint(() => query = text.trim().toLowerCase()),
                    ),
                  ),
                SwitchListTile(
                  title: Text(
                    t('ضيف بطاقات اليوم تلقائيًا', 'Include Today cards'),
                  ),
                  subtitle: Text(
                    t(
                      'تقدر تخفي أي بطاقة هنا حتى لو موجودة في «اليوم».',
                      'You can hide any Today card here.',
                    ),
                  ),
                  value: draft['automatic'] == true,
                  onChanged: (on) =>
                      change(() => setWidgetFollowsToday(data, draft, on)),
                ),
                const Divider(),
                if (shown.isEmpty)
                  ListTile(
                    title: Text(
                      t('مفيش متابعة بالاسم ده', 'No matching trackers'),
                    ),
                  ),
                for (final id in shown)
                  SwitchListTile(
                    key: ValueKey('widget-visibility-$id'),
                    secondary: Icon(glyph(id)),
                    title: Text(scene.title(id)),
                    subtitle: Text(
                      fits.contains(id)
                          ? t('ظاهر في المعاينة', 'Visible in preview')
                          : selected.contains(id)
                          ? t('يظهر في حجم أكبر', 'Visible at a larger size')
                          : t('مخفي', 'Hidden'),
                    ),
                    value: selected.contains(id),
                    onChanged: (on) => change(
                      () => setWidgetCardVisibility(data, draft, id, on),
                    ),
                  ),
              ],
            ),
            footer: JournalButton(
              onPressed: () => Navigator.pop(s),
              child: Text(t('تم', 'Done')),
            ),
          );
        },
      ),
    );
  }

  Future<void> _widgetElements(
    JournalRow draft,
    StateSetter updateEditor,
  ) async {
    await _sheet<void>(
      (c) => StatefulBuilder(
        builder: (s, repaint) {
          final clock = draft['clock'] == true;
          return _JournalPanel(
            heightFactor: .85,
            heading: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t('عناصر الويدجت', 'Widget elements'),
                  style: Theme.of(s).textTheme.titleLarge,
                ),
              ),
            ),
            body: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (key, label, icon, enabled, initial) in [
                  (
                    'clock',
                    t('الساعة', 'Clock'),
                    Icons.schedule_rounded,
                    true,
                    false,
                  ),
                  (
                    'clockDate',
                    t('التاريخ', 'Date'),
                    Icons.calendar_month_outlined,
                    clock,
                    true,
                  ),
                  (
                    'header',
                    t('اسم الويدجت', 'Widget name'),
                    Icons.short_text_rounded,
                    !clock,
                    true,
                  ),
                  (
                    'showShortcut',
                    t('زر التسجيل السريع', 'Quick entry button'),
                    Icons.add_box_outlined,
                    true,
                    true,
                  ),
                  (
                    'showSettings',
                    t('زر الإعدادات', 'Settings button'),
                    Icons.tune_rounded,
                    true,
                    true,
                  ),
                  (
                    'showRefresh',
                    t('زر التحديث', 'Refresh button'),
                    Icons.refresh_rounded,
                    true,
                    true,
                  ),
                  (
                    'icons',
                    t('أيقونات البطاقات', 'Card icons'),
                    Icons.widgets_outlined,
                    true,
                    true,
                  ),
                  (
                    'artwork',
                    t('رسومات البطاقات', 'Card artwork'),
                    Icons.insights_outlined,
                    true,
                    true,
                  ),
                ])
                  SwitchListTile(
                    key: ValueKey('widget-element-$key'),
                    secondary: Icon(icon),
                    title: Text(label),
                    value: (draft[key] as bool?) ?? initial,
                    onChanged: enabled
                        ? (on) {
                            updateEditor(() => draft[key] = on);
                            repaint(() {});
                          }
                        : null,
                  ),
              ],
            ),
            footer: JournalButton(
              onPressed: () => Navigator.pop(s),
              child: Text(t('تم', 'Done')),
            ),
          );
        },
      ),
    );
  }

  Future<JournalRow?> _widgetCardOptions(JournalRow config, String id) async {
    final original = (config['cardOptions'] as Map?)?[id] as Map? ?? {};
    final draft = JournalRow.from(original)
      ..['showCard'] = cardPlan(data, config).contains(id);
    final tracker = trackerFor(data, id);
    final title = TextEditingController(text: draft['title'] as String? ?? '');
    final inherit = t('حسب إعداد الويدجت', 'Use widget default');
    final result = await _page<JournalRow>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          Widget select(
            String key,
            String label,
            List<(String, String)> options,
          ) {
            final value = draft[key]?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _choiceSetting(
                c,
                label,
                value,
                options,
                (v) => redraw(() {
                  if (v.isEmpty) {
                    draft.remove(key);
                  } else {
                    draft[key] = switch (key) {
                      'show' => v == 'true',
                      'days' || 'accent' => int.parse(v),
                      _ => v,
                    };
                  }
                }),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(title: Text(cardName(data, id, ar))),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: Text(
                    t('إظهار البطاقة على الويدجت', 'Show card on widget'),
                  ),
                  value: draft['showCard'] == true,
                  onChanged: (on) => redraw(() => draft['showCard'] = on),
                ),
                TextField(
                  controller: title,
                  maxLength: 45,
                  decoration: InputDecoration(
                    labelText: t(
                      'اسم البطاقة على الويدجت',
                      'Card title on the widget',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                select('accent', t('لون البطاقة', 'Card accent'), [
                  ('', t('لون المتابعة', 'Tracker color')),
                  for (final (index, _) in palettes.indexed)
                    (index.toString(), _widgetColorName(index)),
                ]),
                SwitchListTile(
                  title: Text(t('إظهار الأيقونة', 'Show card icon')),
                  value: config['icons'] != false && draft['icon'] != false,
                  onChanged: config['icons'] == false
                      ? null
                      : (on) => redraw(() => draft['icon'] = on),
                ),
                if (tracker?.kind == 'number')
                  SwitchListTile(
                    title: Text(t('إظهار مؤشر صغير', 'Show mini indicator')),
                    value:
                        config['artwork'] != false &&
                        draft['indicator'] != false,
                    onChanged: config['artwork'] == false
                        ? null
                        : (on) => redraw(() => draft['indicator'] = on),
                  ),
                select('action', t('عند الضغط', 'On tap'), [
                  ('', inherit),
                  if (id == medicineCard) ...[
                    (
                      'routine',
                      t('افتح جدول الأدوية', 'Open medication routine'),
                    ),
                    (
                      'confirm',
                      t(
                        'افتح تأكيد الجرعة التالية',
                        'Open next dose confirmation',
                      ),
                    ),
                  ] else ...[
                    (
                      'details',
                      t('افتح تفاصيل المتابعة', 'Open tracker details'),
                    ),
                    ('add', t('افتح نموذج تسجيل', 'Open entry form')),
                    if (id == 'water')
                      (
                        'cup',
                        t(
                          'سجّل كوب بالمقاس الافتراضي',
                          'Log a default-size cup',
                        ),
                      ),
                  ],
                ]),
                select(
                  'show',
                  t('عرض البيانات الشخصية', 'Show personal data'),
                  [
                    ('', inherit),
                    ('true', t('إظهار', 'Show')),
                    ('false', t('إخفاء', 'Hide')),
                  ],
                ),
                if (tracker != null) ...[
                  select('mode', t('طريقة العرض', 'Display calculation'), [
                    ('', t('حسب إعداد المتابعة', 'Use tracker setting')),
                    for (final mode in trackerViewModes(tracker))
                      (mode, _modeName(mode)),
                  ]),
                  select('days', t('فترة الحساب', 'Summary period'), [
                    ('', t('حسب إعداد المتابعة', 'Use tracker setting')),
                    for (final days in summaryWindows)
                      (days.toString(), summaryPeriod(days, ar)),
                  ]),
                  if (tracker.units.length > 1)
                    select('displayUnit', t('وحدة العرض', 'Display unit'), [
                      ('', t('حسب إعداد المتابعة', 'Use tracker setting')),
                      for (final unit in tracker.units) (unit, unit),
                    ]),
                  if (id == 'glucose')
                    select('filter', t('سياق القراءات', 'Reading context'), [
                      ('', t('حسب إعداد المتابعة', 'Use tracker setting')),
                      ('all', t('كل القراءات', 'All readings')),
                      for (final category in glucoseContexts)
                        (category, entryContext(category, ar)),
                    ]),
                  if (tracker.units.isNotEmpty)
                    SwitchListTile(
                      title: Text(t('إظهار الوحدة', 'Show unit')),
                      value: draft['unit'] != false,
                      onChanged: (on) => redraw(() => draft['unit'] = on),
                    ),
                ],
                SwitchListTile(
                  title: Text(
                    id == medicineCard
                        ? t('إظهار اسم الدواء', 'Show medication name')
                        : t('إظهار وصف القيمة', 'Show value description'),
                  ),
                  value: draft['context'] != false,
                  onChanged: (on) => redraw(() => draft['context'] = on),
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: JournalButton(
                  onPressed: () =>
                      Navigator.pop(c, {...draft, 'title': title.text.trim()}),
                  child: Text(t('احفظ إعدادات البطاقة', 'Save card settings')),
                ),
              ),
            ),
          );
        },
      ),
    );
    // The route still uses its controller during its exit transition.
    Future<void>.delayed(const Duration(milliseconds: 400), title.dispose);
    return result;
  }

  String _widgetColorName(int index) => [
    t('بترولي', 'Teal'),
    t('بنفسجي', 'Violet'),
    t('زمردي', 'Emerald'),
    t('نحاسي', 'Copper'),
    t('نيلي', 'Indigo'),
    t('زيتوني', 'Olive'),
    t('وردي', 'Rose'),
    t('توتي داكن', 'Mulberry'),
    t('أزرق كوبالت', 'Cobalt'),
  ][index];

  Widget more() {
    final colors = Theme.of(context).colorScheme;
    final shortcuts = <(IconData, Color, String, String, VoidCallback)>[
      (
        Icons.medical_information_outlined,
        rose,
        t('الحالات والمتابعات', 'Conditions and trackers'),
        t('اختار إيه اللي تتابعه', 'Choose what to track'),
        _conditions,
      ),
      (
        Icons.dashboard_customize_outlined,
        lavender,
        t('استوديو الويدجت', 'Widget Studio'),
        t('اضبط بطاقات الشاشة الرئيسية', 'Design your home-screen cards'),
        _openStudio,
      ),
      (
        Icons.view_agenda_outlined,
        honey,
        t('ترتيب اليوم', 'Arrange Today'),
        t('رتّب وثبّت بطاقاتك', 'Order and pin your cards'),
        _dashboard,
      ),
      (
        Icons.notifications_active_outlined,
        ice,
        t('التذكيرات والتنبيهات', 'Reminders & notifications'),
        t('المواعيد والتكرار ووصول التنبيه', 'Schedules, repeats and delivery'),
        _notificationSettings,
      ),
      (
        Icons.swap_vert_rounded,
        mint,
        t('الاستيراد والتصدير', 'Import & export'),
        t('انقل السجل أو احفظ نسخة', 'Transfer records or save a backup'),
        _dataCenter,
      ),
    ];
    Widget setting(
      String key,
      IconData icon,
      String label,
      List<(String, String)> choices,
    ) => _choiceSetting(
      context,
      label,
      data[key] as String,
      choices,
      (value) => save((d) => d[key] = value),
      icon: icon,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        _FieldBanner(
          title: t('يومي على طريقتك', 'Yawmi, your way'),
          detail: t('الإعداد والتخصيص', 'Settings & personalization'),
          accent: lavender,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (c, box) {
            final stacked =
                box.maxWidth < 330 || MediaQuery.textScalerOf(c).scale(16) > 21;
            if (stacked) {
              return Column(
                children: [
                  for (final (icon, hue, label, summary, open) in shortcuts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ControlCard(
                        title: label,
                        subtitle: summary,
                        icon: icon,
                        tonalColor: hue,
                        onTap: open,
                      ),
                    ),
                ],
              );
            }
            final dark = Theme.of(c).brightness == Brightness.dark;
            return Column(
              children: [
                for (var row = 0; row < shortcuts.length; row += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = row;
                            index < math.min(row + 2, shortcuts.length);
                            index++
                          ) ...[
                            if (index != row) const SizedBox(width: 8),
                            Expanded(
                              child: _MoreTile(
                                shortcut: shortcuts[index],
                                background: Color.lerp(
                                  colors.surface,
                                  shortcuts[index].$2,
                                  dark ? .12 : .52,
                                )!,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        SectionTitle(t('طريقة الاستخدام', 'Your workflow')),
        ControlCard(
          title: t('اختصارات التسجيل', 'Quick entry favorites'),
          subtitle: t(
            'ثبّت المتابعات اللي بتسجّلها كتير',
            'Pin the trackers you log most',
          ),
          icon: Icons.push_pin_outlined,
          tonalColor: honey,
          onTap: _quickFavorites,
        ),
        SectionTitle(t('اللغة والمظهر', 'Language & appearance')),
        setting('language', Icons.language_rounded, t('اللغة', 'Language'), [
          ('system', t('لغة الجهاز', 'Device language')),
          ('ar', 'العربية'),
          ('en', 'English'),
        ]),
        const SizedBox(height: 8),
        setting('theme', Icons.contrast_rounded, t('المظهر', 'Appearance'), [
          ('system', t('حسب النظام', 'Follow system')),
          ('light', t('نهاري', 'Light')),
          ('dark', t('ليلي', 'Dark')),
        ]),
        const SizedBox(height: 8),
        ControlCard(
          title: t('تقليل الحركة', 'Reduce motion'),
          icon: Icons.motion_photos_off_outlined,
          selected: data['reduce'] == true,
          onTap: () => save((d) => d['reduce'] = d['reduce'] != true),
        ),
        SectionTitle(t('الخصوصية والبيانات', 'Privacy & data')),
        ControlCard(
          title: t('إعادة فتح الإعداد الأول', 'Reopen setup'),
          icon: Icons.replay_rounded,
          onTap: () => save((d) => d['stage'] = 1),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _eraseJournal,
            style: TextButton.styleFrom(foregroundColor: colors.error),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(t('حذف جميع بيانات يومي', 'Delete all Yawmi data')),
          ),
        ),
        const SizedBox(height: 8),
        if (_hasUpdateChannel) ...[
          ControlCard(
            title: t('تحديثات يومي', 'Yawmi updates'),
            subtitle: _availableUpdate == null
                ? t(
                    'افحص أحدث إصدار على GitHub',
                    'Check the latest GitHub release',
                  )
                : t(
                    'الإصدار $_availableUpdate متاح',
                    'Version $_availableUpdate is available',
                  ),
            icon: Icons.system_update_rounded,
            tonalColor: mint,
            toned: _availableUpdate != null,
            onTap: _openUpdates,
          ),
          const SizedBox(height: 8),
        ],
        ControlCard(
          title: t('عن التطبيق', 'About Yawmi'),
          icon: Icons.info_outline_rounded,
          tonalColor: honey,
          onTap: _about,
        ),
        const SizedBox(height: 8),
        ControlCard(
          title: t('الخصوصية', 'Privacy'),
          icon: Icons.privacy_tip_outlined,
          onTap: _privacy,
        ),
      ],
    );
  }

  Future<void> _eraseJournal() async {
    final confirmed = await _confirm(
      t('حذف جميع بيانات يومي؟', 'Delete all Yawmi data?'),
      t(
        'هتتحذف سجلاتك وإعداداتك وتتوقف تذكيراتك ويتفرغ عرض الويدجت.',
        'Your journal and settings will be cleared, reminders stopped, and widget content removed.',
      ),
      t('احذف كل البيانات', 'Delete all data'),
    );
    if (!confirmed) return;
    final cleared = await save((d) {
      d.clear();
      d.addAll(freshState());
    });
    if (!cleared) return;
    try {
      await clearSharedReports(all: true);
    } catch (_) {
      if (mounted)
        _toast(
          t(
            'تعذّر حذف ملفات المشاركة المؤقتة',
            'Could not clear temporary share files',
          ),
        );
    }
    if (!mounted) return;
    _entryDrafts.clear();
    _search.clear();
    _redraw(() {
      tab = 0;
      _focusedDay = null;
      _dashboardSection = 0;
      filter = null;
      conditionFilter = null;
      dates = null;
      period = 0;
    });
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.shortcut, required this.background});
  final (IconData, Color, String, String, VoidCallback) shortcut;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final (icon, hue, label, summary, open) = shortcut;
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Pressable(
        radius: 21,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: hue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: ink, size: 21),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                summary,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
