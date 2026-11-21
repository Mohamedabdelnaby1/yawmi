part of 'main.dart';

class _JournalPanel extends StatelessWidget {
  const _JournalPanel({
    required this.heading,
    required this.body,
    this.footer,
    this.heightFactor = .78,
  });

  final Widget heading, body;
  final Widget? footer;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (c, box) {
        final available = math.max(0.0, box.maxHeight - keyboard);
        return AnimatedPadding(
          duration: motion(c, 250),
          curve: motionArrival,
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: keyboard > 0 ? available : available * heightFactor,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 49, child: heading),
                  Flexible(child: body),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(17, 7, 17, 10),
                      child: footer,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntrySignal extends StatelessWidget {
  const _EntrySignal(this.value, this.color);
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(
        end: value == null ? 0 : (math.log(value!.abs() + 1) / 7).clamp(.18, 1),
      ),
      duration: motion(context, 510),
      curve: const Cubic(.21, .67, .20, 1),
      builder: (_, signal, _) => CustomPaint(
        size: const Size(74, 48),
        painter: _EntryWave(signal, color),
      ),
    ),
  );
}

class _EntryWave extends CustomPainter {
  const _EntryWave(this.level, this.color);
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(14)),
      Paint()..color = color.withValues(alpha: .11),
    );
    final y = size.height * .55;
    final trace = Path()
      ..moveTo(5, y)
      ..cubicTo(15, y, 17, y, 23, y)
      ..lineTo(31, y - 18 * level)
      ..lineTo(40, y + 12 * level)
      ..lineTo(50, y - 7 * level)
      ..quadraticBezierTo(55, y, 67, y);
    final fill = Path.from(trace)
      ..lineTo(67, 42)
      ..lineTo(5, 42)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: level * .19),
    );
    canvas.drawPath(
      trace,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(67, y), 2.4 + level * 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EntryWave old) =>
      old.level != level || old.color != color;
}

extension _Editors on _HomeState {
  Future<void> _quickAdd() async {
    final selected = cardPlan(data);
    if (selected.length == 1) {
      await _openSelectedEntry(selected.single);
      return;
    }
    final ids = {
      ...quickPins(data),
      ...strings(data['recent']).where(selected.contains),
      ...selected,
    }.toList();
    if (ids.isEmpty) {
      final configure = await _sheet<bool>(
        (c) => Padding(
          padding: const EdgeInsets.fromLTRB(17, 4, 17, 20),
          child: EmptyPanel(
            Icons.dashboard_customize_outlined,
            t('اختار أول متابعة', 'Choose a tracker'),
            t(
              'اختياراتك هتظهر هنا وفي «اليوم».',
              'Your selections appear here and in Today.',
            ),
            action: JournalButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('اختيار المتابعات', 'Choose trackers')),
            ),
          ),
        ),
      );
      if (configure == true && mounted) await _chooseTrackers();
      return;
    }
    var filter = '';
    final choice = await _sheet<String>(
      (c) => StatefulBuilder(
        builder: (c, redraw) {
          final matches = ids
              .where(
                (id) => normalize(
                  cardName(data, id, ar),
                ).contains(normalize(filter)),
              )
              .toList();
          final searchable = ids.length >= 7;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(c).height * .74,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t('تسجّل إيه؟', 'What are you logging?'),
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: () async {
                              Navigator.pop(c, 'preferences');
                            },
                            icon: const Icon(Icons.push_pin_outlined, size: 19),
                            tooltip: t(
                              'اختصارات التسجيل',
                              'Quick entry favorites',
                            ),
                          ),
                        ],
                      ),
                      if (searchable) ...[
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (value) => redraw(() => filter = value),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            labelText: t('ابحث عن متابعة', 'Find a tracker'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final id = matches[index];
                      return ControlCard(
                        title: cardName(data, id, ar),
                        icon: glyph(id),
                        tonalColor: _todayTone(id),
                        toned: true,
                        trailing: const Icon(Icons.add_rounded),
                        onTap: () => Navigator.pop(c, id),
                      );
                    },
                  ),
                ),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    child: Text(
                      t('مفيش متابعة بالاسم ده.', 'No matching tracker.'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (choice == 'preferences' && mounted) {
      await _quickFavorites();
    } else if (choice != null && mounted && cardPlan(data).contains(choice)) {
      await _openSelectedEntry(choice);
    }
  }

  Future<void> _openSelectedEntry(String id) async {
    final past = tab == 0 && _focusedDay != null ? _focusedDay : null;
    if (id == medicineCard && past != null) {
      _redraw(() => _dashboardSection = 1);
      return;
    }
    if (id == medicineCard) return _quickMedication();
    if (id == 'water' && past == null) return _hydrationDetails();
    if (trackerFor(data, id) case final Tracker tracker) {
      await _entry(tracker, initialDay: past);
    }
  }

  Future<void> _quickMedication() async {
    final meds = rows(
      data['meds'],
    ).where((m) => m['archived'] != true).toList();
    if (meds.isEmpty) return _medicine();
    final pending = outstanding(data, DateTime.now());
    if (pending.length == 1 && meds.length == 1)
      return _actDose(pending.single);
    if (pending.isEmpty && meds.length == 1)
      return _medDetails(meds.single['id']);
    final target = await _sheet<({Dose? dose, String? medicine})>(
      (c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * .72,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(17, 0, 17, 19),
          children: [
            SectionTitle(t('اختار الجرعة', 'Choose a dose')),
            for (final dose in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: ControlCard(
                  title: dose.medicine['name'],
                  subtitle: [
                    clockText(dose.minute),
                    ?doseMealLabel(dose.mealSlot, ar),
                  ].join(' · '),
                  icon: Icons.event_available_outlined,
                  tonalColor: mint,
                  onTap: () => Navigator.pop(c, (dose: dose, medicine: null)),
                ),
              ),
            SectionTitle(t('تسجيل جرعة يدويًا', 'Log an unscheduled dose')),
            for (final med in meds)
              ControlCard(
                title: med['name'],
                icon: Icons.medication_outlined,
                onTap: () => Navigator.pop(c, (
                  dose: null,
                  medicine: med['id'] as String,
                )),
              ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;
    if (target.dose case final Dose dose) {
      await _actDose(dose);
    } else if (target.medicine case final String id) {
      await _medDetails(id);
    }
  }

  Future<void> _entry(
    Tracker tracker, {
    JournalRow? item,
    String? suggestedCondition,
    DateTime? initialDay,
    String? occurrence,
  }) async {
    final canPlan = plannedTrackers.contains(tracker.id);
    final id = item?['id'] as String? ?? newId();
    final draftKey = item == null
        ? [
            tracker.id,
            suggestedCondition,
            if (initialDay != null) dayKey(initialDay),
            occurrence,
          ].whereType<String>().join('|')
        : id;
    final previous = _entryDrafts[draftKey];
    final input = <String, String>{
      if (item != null)
        for (final e in (item['values'] as Map).entries)
          e.key as String: e.value.toString(),
      if (previous != null)
        ...Map<String, String>.from(previous['input'] as Map),
    };
    final stamp = DateTime.now();
    var at =
        previous?['at'] as DateTime? ??
        (item != null
            ? eventTime(item)
            : initialDay == null
            ? stamp
            : DateTime(
                initialDay.year,
                initialDay.month,
                initialDay.day,
                stamp.hour,
                stamp.minute,
              ));
    var unit =
        previous?['unit'] as String? ??
        item?['unit'] as String? ??
        displayUnit(data, tracker);
    var note = previous?['note'] as String? ?? item?['note'] as String? ?? '';
    var contextValue =
        previous?['context'] as String? ?? item?['context'] as String? ?? '';
    var linked =
        previous?['condition'] as String? ??
        rows(item?['conditions']).firstOrNull?['id'] as String? ??
        suggestedCondition;
    var working = false;
    var scheduleFollowUp = false;
    final form = GlobalKey<FormState>();
    final finished = await _sheet<bool>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final boolValue = input['value'] == 'true';
          final signal = tracker.fields.isEmpty
              ? null
              : readNumber(input[tracker.fields.first.id] ?? '');
          final dateLabel = dayKey(at) == dayKey(DateTime.now())
              ? t('تسجيل اليوم', 'Logging for today')
              : prettyDate(at, 'EEEE، d MMMM');
          final activeConditions = rows(
            data['conditions'],
          ).where((e) => e['archived'] != true || e['id'] == linked).toList();
          Future<void> commit() async {
            if (!form.currentState!.validate()) return;
            if (!canPlan && at.isAfter(DateTime.now())) {
              _toast(t('اختار وقتًا حصل بالفعل', 'Choose a time in the past'));
              return;
            }
            redraw(() => working = true);
            final condition = activeConditions
                .where((e) => e['id'] == linked)
                .firstOrNull;
            final values = tracker.kind == 'number'
                ? {
                    for (final field in tracker.fields)
                      if (readNumber(input[field.id] ?? '') case final double n)
                        field.id: n,
                  }
                : {
                    'value': tracker.kind == 'bool'
                        ? boolValue
                        : input['value']!.trim(),
                  };
            final success = await save((d) {
              final reminder =
                  occurrence ??
                  (item == null ? null : entryReminderOccurrence(item));
              final linkedReminder =
                  reminder != null &&
                  reminder.endsWith(':${dayKey(at)}') &&
                  !rows(d['entries']).any(
                    (e) =>
                        e['id'] != id && entryReminderOccurrence(e) == reminder,
                  );
              final planned =
                  canPlan &&
                  (at.isAfter(DateTime.now()) ||
                      (item != null && isPlannedEntry(item)));
              upsert(d, 'entries', {
                ...?item,
                'id': id,
                'tracker': tracker.id,
                'revision': 1,
                'values': values,
                'unit': unit,
                'at': at.toUtc().toIso8601String(),
                'created':
                    item?['created'] ??
                    DateTime.now().toUtc().toIso8601String(),
                'zone': at.timeZoneName,
                'note': note.trim(),
                'context': contextValue,
                if (canPlan) 'planned': planned,
                if (canPlan && at.isAfter(DateTime.now()))
                  'planCompletedAt': null,
                if (reminder != null)
                  'reminderOccurrence': linkedReminder ? reminder : null,
                if (item?['legacyUndated'] == true &&
                    !at.isAtSameMomentAs(eventTime(item!)))
                  'legacyUndated': false,
                'conditions': [
                  if (condition != null)
                    {
                      'id': condition['id'],
                      'name': conditionName(condition, ar),
                    },
                ],
              });
              rememberTracker(d, tracker.id);
            });
            if (c.mounted) {
              if (success) {
                Navigator.pop(c, true);
                unawaited(HapticFeedback.lightImpact());
                _toast(
                  t('اتحفظ في السجل', 'Saved to your journal'),
                  sealed: true,
                );
              } else {
                redraw(() => working = false);
              }
            }
          }

          return _JournalPanel(
            footer: JournalButton.icon(
              onPressed: working ? null : commit,
              icon: working
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(t('احفظ الإدخال', 'Save entry')),
            ),
            heading: AppBar(
              leading: const CloseButton(),
              title: Text(
                item == null
                    ? t('تسجيل جديد', 'New entry')
                    : t('تعديل الإدخال', 'Edit entry'),
              ),
              actions: [
                if (item != null)
                  IconButton(
                    icon: const Icon(Icons.event_repeat_outlined),
                    tooltip: t('خطّط لمتابعة', 'Plan a follow-up'),
                    onPressed: working
                        ? null
                        : () {
                            scheduleFollowUp = true;
                            Navigator.pop(c);
                          },
                  ),
                if (item != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t('حذف', 'Delete'),
                    onPressed: working
                        ? null
                        : () async {
                            if (!await _confirm(
                              t('حذف الإدخال؟', 'Delete entry?'),
                              t(
                                'هتتم إزالته من السجل والملخصات.',
                                'It will be removed from your journal and summaries.',
                              ),
                              t('احذف', 'Delete'),
                            )) {
                              return;
                            }
                            if (await save(
                                  (d) => removeRow(d, 'entries', id),
                                ) &&
                                c.mounted) {
                              Navigator.pop(c, true);
                            }
                          },
                  ),
              ],
            ),
            body: Form(
              key: form,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 5, 18, 10),
                children: [
                  _entryHeading(
                    tracker,
                    dateLabel,
                    c,
                    indicator: tracker.kind == 'number'
                        ? ExcludeSemantics(
                            child: _EntrySignal(
                              signal,
                              Theme.of(c).colorScheme.primary,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 14),
                  if (tracker.kind == 'bool')
                    SegmentedControl(
                      labels: [t('لا', 'No'), t('نعم', 'Yes')],
                      index: boolValue ? 1 : 0,
                      onChanged: (i) =>
                          redraw(() => input['value'] = (i == 1).toString()),
                    )
                  else
                    LayoutBuilder(
                      builder: (_, bounds) {
                        final fields = tracker.fields;
                        final compactPair =
                            tracker.id == 'pressure' &&
                            bounds.maxWidth >= 300 &&
                            MediaQuery.textScalerOf(c).scale(16) <= 22;
                        Widget field(FieldSpec field) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: TextFormField(
                            key: ValueKey((field.id, unit)),
                            initialValue: input[field.id],
                            maxLength: tracker.kind == 'number' ? 18 : 250,
                            textDirection: tracker.kind == 'number'
                                ? TextDirection.ltr
                                : null,
                            textAlign: tracker.kind == 'number'
                                ? TextAlign.center
                                : TextAlign.start,
                            style: tracker.kind == 'number'
                                ? TextStyle(
                                    fontSize: fields.length == 1 ? 38 : 28,
                                    height: 1.2,
                                    fontFamily: 'Manrope',
                                    fontWeight: FontWeight.bold,
                                  )
                                : null,
                            keyboardType: tracker.kind == 'number'
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  )
                                : TextInputType.text,
                            textInputAction:
                                !field.optional && fields.last != field
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted:
                                field.optional || fields.last == field
                                ? (_) => FocusManager.instance.primaryFocus
                                      ?.unfocus()
                                : null,
                            decoration: InputDecoration(
                              labelText: tracker.kind == 'symptom'
                                  ? t('اسم العرض', 'Symptom name')
                                  : fields.length == 1
                                  ? tracker.name(ar)
                                  : field.name(ar),
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              suffixText:
                                  tracker.kind == 'number' &&
                                      field.id != 'pulse'
                                  ? unit
                                  : null,
                              suffixStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Manrope',
                              ),
                              hintText: tracker.kind == 'number' ? '—' : null,
                              counterText: '',
                            ),
                            onChanged: (value) {
                              input[field.id] = value;
                              if (tracker.kind == 'number') redraw(() {});
                            },
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return field.optional
                                    ? null
                                    : t('اكتب قيمة', 'Enter a value');
                              }
                              if (tracker.kind != 'number') return null;
                              final n = readNumber(value);
                              return n == null ||
                                      (n < 0 && tracker.id != 'temperature') ||
                                      (tracker.id == 'oxygen' && n > 100) ||
                                      ([
                                            'glucose',
                                            'pressure',
                                            'water',
                                          ].contains(tracker.id) &&
                                          n <= 0)
                                  ? t('اكتب قيمة صالحة', 'Enter a valid value')
                                  : null;
                            },
                          ),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (compactPair)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: field(fields[0])),
                                  const SizedBox(width: 8),
                                  Expanded(child: field(fields[1])),
                                ],
                              ),
                            for (final spec
                                in compactPair ? fields.skip(2) : fields)
                              field(spec),
                          ],
                        );
                      },
                    ),
                  if (tracker.units.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final u in tracker.units)
                            ChoiceChip(
                              label: Text(u),
                              selected: unit == u,
                              onSelected: (_) {
                                if (unit == u) return;
                                redraw(() {
                                  final amount = readNumber(
                                    input['value'] ?? '',
                                  );
                                  if (amount != null)
                                    input['value'] = number(
                                      convert(tracker.id, amount, unit, u),
                                    );
                                  unit = u;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  if (tracker.id == 'glucose' || tracker.id == 'symptom') ...[
                    Text(
                      tracker.id == 'symptom'
                          ? t('الشدة (اختياري)', 'Severity (optional)')
                          : t('السياق (اختياري)', 'Context (optional)'),
                    ),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final (key, a, e)
                            in tracker.id == 'symptom'
                                ? [
                                    ('mild', 'خفيف', 'Mild'),
                                    ('moderate', 'متوسط', 'Moderate'),
                                    ('severe', 'شديد', 'Severe'),
                                  ]
                                : [
                                    ('fasting', 'صايم', 'Fasting'),
                                    ('not_fasting', 'غير صايم', 'Not fasting'),
                                    ('before meal', 'قبل الأكل', 'Before meal'),
                                    ('after meal', 'بعد الأكل', 'After meal'),
                                  ])
                          FilterChip(
                            label: Text(t(a, e)),
                            selected: contextValue == key,
                            onSelected: (on) =>
                                redraw(() => contextValue = on ? key : ''),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  ExpansionTile(
                    maintainState: true,
                    initiallyExpanded:
                        item != null ||
                        note.isNotEmpty ||
                        dayKey(at) != dayKey(DateTime.now()),
                    title: Text(
                      t('الوقت والملاحظة والربط', 'Time, note and condition'),
                    ),
                    subtitle: Text(clockText(at.hour * 60 + at.minute)),
                    leading: const Icon(Icons.tune_rounded),
                    children: [
                      if (activeConditions.isNotEmpty)
                        _choiceSetting(
                          c,
                          t('ربط بحالة', 'Link to a condition'),
                          linked ?? '',
                          [
                            ('', t('بدون ربط', 'Unlinked')),
                            for (final condition in activeConditions)
                              (
                                condition['id'] as String,
                                conditionName(condition, ar),
                              ),
                          ],
                          (value) => redraw(
                            () => linked = value.isEmpty ? null : value,
                          ),
                          icon: Icons.link_rounded,
                        ),
                      const SizedBox(height: 9),
                      TextFormField(
                        initialValue: note,
                        maxLines: 2,
                        maxLength: 1000,
                        decoration: InputDecoration(
                          labelText: t('ملاحظة (اختياري)', 'Note (optional)'),
                          counterText: '',
                        ),
                        onChanged: (x) => note = x,
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.schedule),
                          title: Text(
                            '${prettyDate(at)} · ${clockText(at.hour * 60 + at.minute)}',
                          ),
                          subtitle: Text(
                            t('وقت حدوث الإدخال', 'Time of entry'),
                          ),
                          onTap: () async {
                            final today = DateTime.now();
                            final last = canPlan
                                ? DateTime(today.year + 10)
                                : today;
                            final date = await showDatePicker(
                              context: c,
                              firstDate: DateTime(1900),
                              lastDate: last,
                              initialDate: at.isAfter(last) ? last : at,
                            );
                            if (date == null || !c.mounted) return;
                            final tm = await showTimePicker(
                              context: c,
                              initialTime: TimeOfDay.fromDateTime(at),
                            );
                            if (tm != null && c.mounted) {
                              redraw(
                                () => at = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  tm.hour,
                                  tm.minute,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (finished == true) {
      _entryDrafts.remove(draftKey);
    } else {
      _entryDrafts[draftKey] = {
        'input': input,
        'at': at,
        'unit': unit,
        'note': note,
        'context': contextValue,
        'condition': linked,
      };
    }
    if (scheduleFollowUp && item != null && mounted) {
      final value = item['values']['value'];
      await _openFollowUp(
        null,
        suggested: tracker,
        suggestedName: tracker.kind == 'text' && value is String
            ? value.length <= 100
                  ? value
                  : tracker.name(ar)
            : tracker.name(ar),
        suggestedDate: isPlannedEntry(item) ? eventTime(item) : null,
      );
    }
  }

  Future<void> _addWater([int volume = 250, String? condition]) async {
    if (_addingWater) return;
    _redraw(() => _addingWater = true);
    final id = newId();
    final at = DateTime.now();
    final ok = await save((d) {
      final linked = rows(
        d['conditions'],
      ).where((c) => c['id'] == condition && c['archived'] != true).firstOrNull;
      upsert(d, 'entries', {
        'id': id,
        'tracker': 'water',
        'revision': 1,
        'unit': 'mL',
        'values': {'value': volume},
        'at': at.toUtc().toIso8601String(),
        'created': at.toUtc().toIso8601String(),
        'zone': at.timeZoneName,
        if (linked != null)
          'conditions': [
            {'id': linked['id'], 'name': conditionName(linked, ar)},
          ],
      });
      rememberTracker(d, 'water');
    });
    if (!mounted) return;
    _redraw(() {
      _addingWater = false;
      now = DateTime.now();
    });
    if (ok) {
      unawaited(HapticFeedback.lightImpact());
      _toast(
        t('اتسجل كوب مياه', 'Cup logged'),
        sealed: true,
        action: SnackBarAction(
          label: t('تراجع', 'Undo'),
          onPressed: () => save((d) => removeRow(d, 'entries', id)),
        ),
      );
    }
  }

  Future<void> _details(Tracker tracker, {String? condition}) async {
    int? span;
    int? pointIndex;
    DateTimeRange? custom;
    var compare = false;
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, change) => ListenableBuilder(
          listenable: widget.db,
          builder: (c, _) {
            final stamp = DateTime.now();
            final prefs = trackerView(data, tracker);
            final window = span ?? prefs.days;
            final all = trackerViewEntries(data, tracker, stamp, prefs)
                .where(
                  (row) =>
                      condition == null ||
                      rows(row['conditions']).any((c) => c['id'] == condition),
                )
                .toList();
            final linked = rows(
              data['conditions'],
            ).where((c) => c['id'] == condition).firstOrNull;
            final end = custom?.end ?? DateTime.now();
            final start =
                custom?.start ??
                (window == 0
                    ? (all.isEmpty ? end : eventTime(all.last))
                    : DateTime(end.year, end.month, end.day - window + 1));
            final days =
                DateTime.utc(end.year, end.month, end.day)
                    .difference(
                      DateTime.utc(start.year, start.month, start.day),
                    )
                    .inDays +
                1;
            final recent = inPeriod(all, end, days);
            final primary = tracker.id == 'pressure' ? 'systolic' : 'value';
            final unit = displayUnit(data, tracker);
            final points = <(double, double)>[],
                secondary = <(double, double)>[];
            final normalizedStart = DateTime.utc(
              start.year,
              start.month,
              start.day,
            );
            final dailyWater = <int, double>{};
            for (final row in recent.reversed) {
              final values = row['values'] as Map;
              final when = eventTime(row);
              final x =
                  DateTime.utc(
                    when.year,
                    when.month,
                    when.day,
                  ).difference(normalizedStart).inDays +
                  (when.hour * 60 + when.minute) / 1440;
              if (values[primary] is num) {
                final value = (values[primary] as num).toDouble();
                final canonical = convert(tracker.id, value, row['unit'], unit);
                if (tracker.id == 'water') {
                  dailyWater.update(
                    x.floor(),
                    (before) => before + canonical,
                    ifAbsent: () => canonical,
                  );
                } else {
                  points.add((x, canonical));
                }
                if (values['diastolic'] is num) {
                  secondary.add((x, (values['diastolic'] as num).toDouble()));
                }
              }
            }
            points.addAll(
              dailyWater.entries.map((entry) => (entry.key + .5, entry.value)),
            );
            final currentPoint = points.isEmpty
                ? 0
                : (pointIndex ?? points.length - 1).clamp(0, points.length - 1);
            final point = points.elementAtOrNull(currentPoint);
            void chooseAt(double x, double width) {
              final where =
                  ((x - 5) / math.max(1, width - 10)).clamp(0, 1) * days;
              var nearest = 0;
              for (var i = 1; i < points.length; i++) {
                if ((points[i].$1 - where).abs() <
                    (points[nearest].$1 - where).abs())
                  nearest = i;
              }
              if (nearest == currentPoint) return;
              change(() => pointIndex = nearest);
              unawaited(HapticFeedback.selectionClick());
            }

            return _JournalPanel(
              heightFactor: .88,
              heading: AppBar(
                leading: const CloseButton(),
                title: Text(t('تفاصيل المتابعة', 'Tracker details')),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: t('إعدادات المتابعة', 'Tracker settings'),
                    onPressed: () => _trackerPreferences(tracker),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_alarm),
                    tooltip: t('أضف تذكير', 'Add reminder'),
                    onPressed: () => _reminder(tracker: tracker.id),
                  ),
                ],
              ),
              body: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 7, 18, 12),
                children: [
                  _entryHeading(
                    tracker,
                    [
                      linked == null
                          ? t('سجل المتابعة', 'Tracker log')
                          : conditionName(linked, ar),
                      unit,
                    ].where((v) => v.isNotEmpty).join(' · '),
                    c,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final d in summaryWindows)
                        ChoiceChip(
                          label: Text(summaryPeriod(d, ar)),
                          selected: window == d && custom == null,
                          onSelected: (_) => change(() {
                            span = d;
                            custom = null;
                            pointIndex = null;
                          }),
                        ),
                      ActionChip(
                        label: Text(
                          custom == null
                              ? t('فترة مخصصة', 'Custom')
                              : '${prettyDate(custom!.start)} – ${prettyDate(custom!.end)}',
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: c,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                            initialDateRange: custom,
                          );
                          if (range != null && c.mounted) {
                            change(() {
                              custom = range;
                              pointIndex = null;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  if (points.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('الاتجاه', 'Trend') +
                                  (unit.isEmpty ? '' : ' · $unit'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            if (secondary.isNotEmpty)
                              Text(
                                t(
                                  '● انقباضي   ◇ انبساطي',
                                  '● Systolic   ◇ Diastolic',
                                ),
                              ),
                            if (tracker.id == 'glucose' &&
                                prefs.mode == 'average')
                              Text(
                                '${t('المتوسط', 'Average')}  ${number(average(recent, tracker, unit)!)} $unit',
                              ),
                            if (tracker.id == 'water')
                              Text(
                                [
                                  t('إجمالي الفترة', 'Period total'),
                                  number(
                                    dailyWater.values.fold<double>(
                                      0,
                                      (total, n) => total + n,
                                    ),
                                  ),
                                  unit,
                                ].join(' '),
                              ),
                            if (point != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: motion(c, 305),
                                      transitionBuilder: valueMotion,
                                      child: Align(
                                        key: ValueKey(point),
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(
                                          [number(point.$2), unit]
                                              .where((v) => v.isNotEmpty)
                                              .join(' '),
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                            fontFamily: 'Manrope',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 29,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton.outlined(
                                    onPressed: currentPoint == 0
                                        ? null
                                        : () => change(
                                            () => pointIndex = currentPoint - 1,
                                          ),
                                    tooltip: t(
                                      'القراءة السابقة',
                                      'Previous reading',
                                    ),
                                    icon: const Icon(
                                      Icons.chevron_left_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton.outlined(
                                    onPressed: currentPoint + 1 >= points.length
                                        ? null
                                        : () => change(
                                            () => pointIndex = currentPoint + 1,
                                          ),
                                    tooltip: t(
                                      'القراءة التالية',
                                      'Next reading',
                                    ),
                                    icon: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            Semantics(
                              label: t(
                                'مخطط القراءات. القيم موجودة في القائمة أدناه.',
                                'Reading chart. Values are listed below.',
                              ),
                              child: LayoutBuilder(
                                builder: (_, box) => GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) => chooseAt(
                                    details.localPosition.dx,
                                    box.maxWidth,
                                  ),
                                  onHorizontalDragUpdate: (details) => chooseAt(
                                    details.localPosition.dx,
                                    box.maxWidth,
                                  ),
                                  child: RepaintBoundary(
                                    child: TweenAnimationBuilder<double>(
                                      key: ValueKey(
                                        [
                                          start,
                                          end,
                                          unit,
                                          points.length,
                                          points.last,
                                        ].join('|'),
                                      ),
                                      tween: Tween(begin: 0, end: 1),
                                      duration: motion(c, 620),
                                      curve: motionArrival,
                                      builder: (c, x, _) => SizedBox(
                                        height: 136,
                                        width: double.infinity,
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween(
                                            end: currentPoint.toDouble(),
                                          ),
                                          duration: motion(c, 360),
                                          curve: Curves.easeOutCubic,
                                          builder: (c, focus, _) => CustomPaint(
                                            painter: _Trend(
                                              points,
                                              secondary,
                                              days,
                                              x,
                                              Theme.of(c).colorScheme.primary,
                                              focus,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              textDirection: TextDirection.ltr,
                              children: [
                                Text(prettyDate(start, 'd MMM')),
                                Text(prettyDate(end, 'd MMM')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (tracker.kind == 'number' &&
                      (window != 0 || custom != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ControlCard(
                        title: t(
                          'قارن بالفترة السابقة',
                          'Compare with the previous period',
                        ),
                        icon: Icons.compare_arrows_rounded,
                        tonalColor: mint,
                        selected: compare,
                        onTap: () => change(() => compare = !compare),
                      ),
                    ),
                  if (compare &&
                      tracker.kind == 'number' &&
                      (window != 0 || custom != null))
                    _periodComparison(
                      tracker,
                      unit,
                      prefs.mode,
                      all,
                      recent,
                      start,
                      days,
                    ),
                  SectionTitle(
                    '${t('الإدخالات', 'Entries')} · ${recent.length}',
                  ),
                  if (recent.isEmpty)
                    EmptyPanel(
                      Icons.insights,
                      t('مفيش إدخالات في الفترة', 'No entries in this period'),
                      t(
                        'سجّل إدخالًا أو غيّر فترة العرض.',
                        'Log a reading or change the date range.',
                      ),
                    ),
                  for (final row in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _logTile(row),
                    ),
                ],
              ),
              footer: JournalButton.icon(
                onPressed: () => _entry(tracker, suggestedCondition: condition),
                icon: const Icon(Icons.add),
                label: Text(t('تسجيل', 'Log')),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _entryHeading(
    Tracker tracker,
    String subtitle,
    BuildContext c, {
    Widget? indicator,
  }) {
    final colors = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(colors.surface, tint(tracker.id), dark ? .15 : .57),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 11, 10),
        child: Row(
          children: [
            TileIcon(tracker.id, size: 41),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tracker.name(ar),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (indicator != null &&
                MediaQuery.textScalerOf(c).scale(16) < 22) ...[
              const SizedBox(width: 7),
              indicator,
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _textPrompt(
    String title,
    String hint, {
    String initial = '',
    bool secret = false,
  }) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          initialValue: initial,
          obscureText: secret,
          maxLength: secret ? 180 : 90,
          decoration: InputDecoration(labelText: hint),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          JournalButton(
            onPressed: () => Navigator.pop(c, secret ? value : value.trim()),
            child: Text(t('متابعة', 'Continue')),
          ),
        ],
      ),
    );
  }
}

class _Trend extends CustomPainter {
  const _Trend(
    this.primary,
    this.secondary,
    this.days,
    this.fraction,
    this.color,
    this.selected,
  );
  final List<(double, double)> primary, secondary;
  final int days;
  final double fraction;
  final Color color;
  final double selected;
  @override
  void paint(Canvas canvas, Size size) {
    final values = [...primary, ...secondary].map((p) => p.$2);
    final high = values.reduce(math.max);
    final low = values.reduce(math.min);
    final range = high - low;
    Offset plot(double x, double y) => Offset(
      5 + x / days * (size.width - 10),
      range < .001
          ? size.height / 2
          : size.height * (.84 - .68 * (y - low) / range),
    );
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = color.withValues(alpha: .15),
      );
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fraction, size.height));
    void line(List<(double, double)> source, Color lineColor, bool hollow) {
      final brush = Paint()
        ..color = lineColor
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round;
      Offset? previous;
      double? previousX;
      for (final (x, y) in source) {
        final point = plot(x, y);
        if (previous != null && x.floor() - previousX!.floor() <= 1) {
          canvas.drawLine(previous, point, brush);
        }
        canvas.drawCircle(
          point,
          3.5,
          Paint()
            ..color = lineColor
            ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 1.7,
        );
        previous = point;
        previousX = x;
      }
    }

    line(primary, color, false);
    line(secondary, const Color(0xffb96747), true);
    final index = selected.clamp(0, primary.length - 1).toDouble();
    final lowPoint = primary[index.floor()];
    final highPoint = primary[index.ceil()];
    final focus = Offset.lerp(
      plot(lowPoint.$1, lowPoint.$2),
      plot(highPoint.$1, highPoint.$2),
      index % 1,
    )!;
    final light = Rect.fromLTWH(focus.dx - 13, 0, 26, size.height);
    final clear = color.withValues(alpha: 0);
    canvas.drawRect(
      light,
      Paint()
        ..shader = LinearGradient(
          colors: [clear, color.withValues(alpha: .16), clear],
        ).createShader(light),
    );
    canvas.drawLine(
      Offset(focus.dx, 3),
      Offset(focus.dx, size.height - 3),
      Paint()
        ..color = color.withValues(alpha: .55)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      focus,
      12,
      Paint()
        ..color = color.withValues(alpha: .57)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(focus, 8, Paint()..color = color.withValues(alpha: .25));
    canvas.drawCircle(focus, 5, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Trend oldDelegate) => true;
}
