part of 'main.dart';

extension _TrackerPreferences on _HomeState {
  String _modeName(String mode) => switch (mode) {
    'average' => t('متوسط القراءات', 'Average readings'),
    'total' => t('الإجمالي', 'Total'),
    'count' => t('عدد الإدخالات', 'Entry count'),
    _ => t('آخر إدخال', 'Latest entry'),
  };

  Future<void> _trackerPreferences(Tracker tracker) async {
    final view = trackerView(data, tracker);
    var mode = view.mode, days = view.days, filter = view.context;
    var secondary = view.secondary,
        doseSummary = view.doseSummary,
        busy = false;
    var unit = displayUnit(data, tracker);
    var goal = (data['waterGoal'] as num?)?.toString() ?? '';
    final presets = waterCups(data).map((n) => n.toString()).toList();
    var defaultIndex = waterCups(data).indexOf(defaultWaterCup(data));
    final water = tracker.id == 'water';
    final modes = trackerViewModes(tracker);
    final form = GlobalKey<FormState>();
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final draft = {
            'mode': mode,
            'days': days,
            'context': filter,
            'secondary': secondary,
            'doseSummary': doseSummary,
          };
          final snapshot = {
            ...data,
            'trackerViews': {
              ...(data['trackerViews'] as Map? ?? {}),
              tracker.id: draft,
            },
            'unitPrefs': {
              ...(data['unitPrefs'] as Map? ?? {}),
              tracker.id: unit,
            },
          };
          final preview = summaryFor(snapshot, tracker.id, ar, DateTime.now());
          final colors = Theme.of(c).colorScheme;
          Widget selector(
            String label,
            String value,
            List<(String, String)> options,
            ValueChanged<String> select,
          ) => _choiceSetting(
            c,
            label,
            value,
            options,
            (next) => redraw(() => select(next)),
          );
          return _JournalPanel(
            heightFactor: .86,
            heading: AppBar(
              leading: const CloseButton(),
              title: Text(t('إعدادات المتابعة', 'Tracker settings')),
            ),
            footer: JournalButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      final volumes = presets
                          .map((value) => int.tryParse(normalize(value)))
                          .toList();
                      final target = readNumber(goal);
                      if (water &&
                          (volumes.any(
                                (n) => n == null || n <= 0 || n > 10000,
                              ) ||
                              volumes.toSet().length != volumes.length ||
                              goal.trim().isNotEmpty &&
                                  (target == null || target <= 0))) {
                        _toast(
                          t(
                            'راجع الهدف وأحجام الأكواب.',
                            'Check the goal and cup sizes.',
                          ),
                        );
                        return;
                      }
                      redraw(() => busy = true);
                      final ok = await save((d) {
                        final views = Map<String, dynamic>.from(
                          d['trackerViews'] as Map? ?? {},
                        );
                        views[tracker.id] = draft;
                        d['trackerViews'] = views;
                        if (unit.isNotEmpty)
                          (d['unitPrefs'] as Map)[tracker.id] = unit;
                        if (water) {
                          final sizes = volumes.cast<int>();
                          d['waterCups'] = sizes;
                          d['waterDefaultCup'] = sizes[defaultIndex];
                          d['waterGoal'] = target;
                        }
                      });
                      if (!c.mounted) return;
                      if (ok) {
                        Navigator.pop(c);
                        _toast(
                          t(
                            'اتحفظت إعدادات المتابعة',
                            'Tracker settings saved',
                          ),
                        );
                      } else {
                        redraw(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.check),
              label: Text(t('احفظ الإعدادات', 'Save settings')),
            ),
            body: Form(
              key: form,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 7, 18, 15),
                children: [
                  _entryHeading(
                    tracker,
                    t('الوحدة وطريقة الحساب', 'Unit and calculation'),
                    c,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('معاينة بطاقة اليوم', 'Today card preview'),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        AnimatedSwitcher(
                          duration: motion(c, 385),
                          transitionBuilder: valueMotion,
                          child: Align(
                            key: ValueKey(
                              [preview.value, preview.unit].join('|'),
                            ),
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              [
                                preview.value,
                                preview.unit,
                              ].where((x) => x.isNotEmpty).join(' '),
                              textDirection: tracker.kind == 'number'
                                  ? TextDirection.ltr
                                  : null,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Text(preview.context),
                      ],
                    ),
                  ),
                  SectionTitle(t('الحساب والعرض', 'Calculation and display')),
                  if (modes.length > 1)
                    selector(t('طريقة الحساب', 'Calculation'), mode, [
                      for (final m in modes) (m, _modeName(m)),
                    ], (v) => mode = v)
                  else
                    Text(
                      t(
                        'المياه تُعرض كإجمالي الكمية اللي سجلتها.',
                        'Water shows the total amount you recorded.',
                      ),
                    ),
                  if (mode != 'latest') ...[
                    const SizedBox(height: 10),
                    Text(t('الفترة المتحركة', 'Rolling period')),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final n in summaryWindows)
                          ChoiceChip(
                            label: Text(summaryPeriod(n, ar)),
                            selected: n == days,
                            onSelected: (_) => redraw(() => days = n),
                          ),
                      ],
                    ),
                  ],
                  if (tracker.units.length > 1) ...[
                    const SizedBox(height: 9),
                    selector(t('وحدة العرض', 'Display unit'), unit, [
                      for (final u in tracker.units) (u, u),
                    ], (v) => unit = v),
                  ],
                  if (tracker.id == 'glucose') ...[
                    const SizedBox(height: 9),
                    selector(
                      t('القراءات الداخلة في العرض', 'Readings to include'),
                      filter,
                      [
                        ('', t('كل القراءات', 'All readings')),
                        for (final key in glucoseContexts)
                          (key, entryContext(key, ar)),
                      ],
                      (v) => filter = v,
                    ),
                  ],
                  if (mode == 'latest' || mode == 'average')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        mode == 'average'
                            ? t('أظهر عدد القراءات', 'Show number of readings')
                            : t(
                                'أظهر تاريخ آخر إدخال',
                                'Show latest entry date',
                              ),
                      ),
                      value: secondary,
                      onChanged: (on) => redraw(() => secondary = on),
                    ),
                  if (tracker.id == 'glucose')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t(
                          'أظهر ملخص السكر عند تسجيل جرعة',
                          'Show glucose summary when logging a dose',
                        ),
                      ),
                      value: doseSummary,
                      onChanged: (on) => redraw(() => doseSummary = on),
                    ),
                  if (water) ...[
                    SectionTitle(
                      t('هدف اليوم وأحجام الأكواب', 'Daily goal and cup sizes'),
                    ),
                    TextFormField(
                      initialValue: goal,
                      onChanged: (value) => goal = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t(
                          'هدفك اليومي (مل) · اختياري',
                          'Your daily goal (mL) · optional',
                        ),
                      ),
                      validator: (value) =>
                          value == null ||
                              value.trim().isEmpty ||
                              (readNumber(value) ?? 0) > 0
                          ? null
                          : t(
                              'اكتب قيمة أكبر من صفر',
                              'Enter a value above zero',
                            ),
                    ),
                    const SizedBox(height: 9),
                    for (final (i, preset) in presets.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: TextFormField(
                          key: ValueKey(i),
                          initialValue: preset,
                          onChanged: (value) => presets[i] = value,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: [
                              t('الكوب', 'Cup'),
                              i + 1,
                              '· mL',
                            ].join(' '),
                            suffixIcon: IconButton(
                              icon: Icon(
                                i == defaultIndex
                                    ? Icons.star
                                    : Icons.star_border,
                              ),
                              tooltip: t(
                                'استخدم كمقاس افتراضي',
                                'Set as default cup',
                              ),
                              onPressed: () => redraw(() => defaultIndex = i),
                            ),
                          ),
                          validator: (value) {
                            final n = int.tryParse(normalize(value ?? ''));
                            if (n == null || n <= 0 || n > 10000)
                              return t(
                                'اكتب حجمًا صحيحًا بالمل',
                                'Enter a whole amount in mL',
                              );
                            if (presets
                                    .where(
                                      (x) => int.tryParse(normalize(x)) == n,
                                    )
                                    .length >
                                1) {
                              return t(
                                'اختار حجمًا مختلفًا',
                                'Choose a different amount',
                              );
                            }
                            return null;
                          },
                        ),
                      ),
                    Text(
                      t(
                        'المقاس الافتراضي يُستخدم في الإضافة السريعة والويدجت.',
                        'The default size is used by quick log and widgets.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
