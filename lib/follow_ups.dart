part of 'main.dart';

extension _FollowUps on _HomeState {
  List<Widget> _followUpShortcuts() => [
    ControlCard(
      title: t('خزانة الأدوية', 'Medicine cabinet'),
      subtitle: t(
        'راجع الكميات والصلاحية وتنبيهات إعادة الصرف.',
        'Check quantities, expiry dates, and refill alerts.',
      ),
      icon: Icons.inventory_2_outlined,
      tonalColor: mint,
      onTap: _medicineCabinet,
    ),
    const SizedBox(height: 8),
    ControlCard(
      title: t('المتابعات القادمة', 'Upcoming follow-ups'),
      subtitle: t(
        'خطّط لإعادة تحليل أو زيارة أو أي متابعة بتاريخ.',
        'Plan a repeat test, a visit, or any dated follow-up.',
      ),
      icon: Icons.event_repeat_outlined,
      tonalColor: lavender,
      onTap: () => _followUpCenter(),
    ),
  ];

  String _dateStatus(DateTime date, {bool expiry = false}) {
    final days = calendarDaysUntil(date, DateTime.now());
    return switch (days) {
      < 0 =>
        expiry
            ? t('تاريخ الصلاحية عدى', 'Expiry date passed')
            : t('الموعد فات', 'Overdue'),
      0 => t('النهارده', 'Today'),
      1 => t('بكرة', 'Tomorrow'),
      _ => t('بعد $days يوم', 'In $days days'),
    };
  }

  Future<void> _followUpCenter({Tracker? tracker}) => _page<void>((_) {
    var showCompleted = false;
    return StatefulBuilder(
      builder: (c, redraw) => ListenableBuilder(
        listenable: widget.db,
        builder: (c, _) {
          final plans =
              (showCompleted
                      ? rows(data['followUps'])
                            .where((r) => r['completedAt'] != null)
                            .toList()
                            .reversed
                      : pendingFollowUps(data))
                  .where((r) => tracker == null || r['tracker'] == tracker.id)
                  .toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(t('المتابعات القادمة', 'Upcoming follow-ups')),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _openFollowUp(null, suggested: tracker),
              icon: const Icon(Icons.add_rounded),
              label: Text(t('أضف موعد', 'Add follow-up')),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 98),
              children: [
                JournalCover(
                  title:
                      tracker?.name(ar) ??
                      t('خطّط للمتابعة الجاية', 'Plan what comes next'),
                  subtitle: t(
                    'اختار التاريخ والوقت اللي تحب يومي يفكّرك فيه.',
                    'Choose a due date and when you want Yawmi to remind you.',
                  ),
                  icon: Icons.event_repeat_outlined,
                  accent: lavender,
                ),
                const SizedBox(height: 14),
                SegmentedControl(
                  labels: [t('القادمة', 'Pending'), t('تمّت', 'Completed')],
                  index: showCompleted ? 1 : 0,
                  onChanged: (index) =>
                      redraw(() => showCompleted = index == 1),
                ),
                const SizedBox(height: 12),
                if (plans.isEmpty)
                  EmptyPanel(
                    Icons.event_note_outlined,
                    showCompleted
                        ? t('لسه مفيش مواعيد تمّت', 'No completed follow-ups')
                        : t('مفيش مواعيد متابعة', 'No pending follow-ups'),
                    showCompleted
                        ? ''
                        : t(
                            'ضيف تاريخ إعادة تحليل أو زيارة أو أي مهمة متابعة.',
                            'Add a repeat test, visit, or another follow-up.',
                          ),
                  ),
                for (final (index, plan) in plans.indexed)
                  if (DateAlert.read(plan['alert']) case final alert?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Enter(
                        key: ValueKey(plan['id']),
                        delay: index.clamp(0, 5) * 35,
                        child: ControlCard(
                          title: plan['name'],
                          subtitle: [
                            prettyDate(alert.date, 'd MMM yyyy'),
                            if (!showCompleted) _dateStatus(alert.date),
                            if (!showCompleted && !alert.armed)
                              t('التنبيه مقفول', 'Alerts off'),
                          ].join(' · '),
                          icon: showCompleted
                              ? Icons.task_alt_rounded
                              : glyph(plan['tracker'] as String? ?? ''),
                          tonalColor: showCompleted ? mint : lavender,
                          onTap: () => _openFollowUp(plan['id']),
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  });

  Future<void> _openFollowUp(
    String? id, {
    Tracker? suggested,
    String? suggestedName,
    DateTime? suggestedDate,
    String? sourceEntry,
    String? visitId,
  }) async {
    final existing = rows(
      data['followUps'],
    ).where((r) => r['id'] == id).firstOrNull;
    if (id != null && existing == null) return;
    final tracker = existing?['tracker'] as String? ?? suggested?.id;
    final done = existing?['completedAt'] != null;
    await _dateAlertEditor(
      heading: t('موعد متابعة', 'Follow-up'),
      initialName: existing?['name'] as String? ?? suggestedName ?? '',
      tracker: tracker,
      current: DateAlert.read(existing?['alert']),
      initialDate: suggestedDate,
      completed: done,
      onSave: (name, trackerId, alert) {
        final pendingId = id ?? newId();
        return save((d) {
          final visit = rows(
            d['visits'],
          ).where((row) => row['id'] == visitId).firstOrNull;
          if (visitId != null && visit == null) return;
          upsert(d, 'followUps', {
            ...?existing,
            'id': pendingId,
            'name': name,
            'tracker': trackerId,
            if (sourceEntry != null) 'sourceEntry': sourceEntry,
            'alert': alert.toRow(),
          });
          if (visit != null)
            upsert(d, 'visits', {...visit, 'followUp': pendingId});
        });
      },
      onDone: existing == null || done
          ? null
          : () => save(
              (d) => upsert(d, 'followUps', {
                ...existing,
                'completedAt': DateTime.now().toUtc().toIso8601String(),
              }),
            ),
      onRemove: id == null
          ? null
          : () => save((d) => removeRow(d, 'followUps', id)),
    );
  }

  Future<void> _editMedicationExpiry(String id) async {
    final med = rows(data['meds']).where((m) => m['id'] == id).firstOrNull;
    if (med == null || med['archived'] == true) return;
    Future<bool> update(DateAlert? alert) => save((d) {
      final current = rows(d['meds']).where((m) => m['id'] == id).firstOrNull;
      if (current == null || current['archived'] == true) return;
      final changed = {...current};
      if (alert == null) {
        changed.remove('expiry');
      } else {
        changed['expiry'] = alert.toRow();
      }
      upsert(d, 'meds', changed);
    });
    final existing = DateAlert.read(med['expiry']);
    await _dateAlertEditor(
      heading: t('صلاحية الدواء', 'Medication expiry'),
      initialName: med['name'] as String,
      current: existing,
      expiry: true,
      onSave: (_, _, alert) => update(alert),
      onRemove: existing == null ? null : () => update(null),
    );
  }

  Future<void> _dateAlertEditor({
    required String heading,
    required String initialName,
    required DateAlert? current,
    required Future<bool> Function(String, String?, DateAlert) onSave,
    String? tracker,
    DateTime? initialDate,
    bool expiry = false,
    bool completed = false,
    Future<bool> Function()? onDone,
    Future<bool> Function()? onRemove,
  }) async {
    final enteredAt = DateTime.now();
    var name = initialName;
    var linked = tracker;
    var date =
        (expiry ? initialDate : null) ??
        current?.date ??
        initialDate ??
        shiftCalendarDate(enteredAt, 7);
    var minute = current?.minute ?? 540;
    final leads = {...?current?.leads};
    if (current == null) leads.addAll([7, 1, 0]);
    var enabled = !completed && (current?.armed ?? false);
    var repeat = current?.repeat ?? (count: 0, minutes: 15);
    var busy = false;
    final form = GlobalKey<FormState>();
    final result = await _sheet<String>(
      (_) => StatefulBuilder(
        builder: (c, redraw) {
          final trackers = allTrackers(data);
          final upcoming = [
            for (final lead in alertLeadDays.where(leads.contains))
              DateTime(
                date.year,
                date.month,
                date.day - lead,
                minute ~/ 60,
                minute % 60,
              ),
          ].where((time) => !time.isBefore(DateTime.now())).toList();
          Future<void> persist(
            Future<bool> Function() action,
            String result,
          ) async {
            redraw(() => busy = true);
            final saved = await action();
            if (!c.mounted) return;
            if (saved) {
              Navigator.pop(c, result);
            } else {
              redraw(() => busy = false);
            }
          }

          return _JournalPanel(
            heading: AppBar(
              title: Text(heading),
              leading: const CloseButton(),
              actions: [
                if (onRemove != null)
                  IconButton(
                    tooltip: t('احذف الموعد', 'Delete date'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: busy
                        ? null
                        : () async {
                            if (await _confirm(
                                  t('احذف الموعد؟', 'Delete this date?'),
                                  t(
                                    'هتتوقف التنبيهات بتاعة الميعاد ده.',
                                    'Its scheduled alerts will be cancelled.',
                                  ),
                                  t('احذف', 'Delete'),
                                ) &&
                                c.mounted) {
                              await persist(onRemove, 'removed');
                            }
                          },
                  ),
              ],
            ),
            footer: JournalButton.icon(
              icon: Icon(completed ? Icons.close_rounded : Icons.check_rounded),
              label: Text(
                completed ? t('اقفل', 'Close') : t('احفظ الموعد', 'Save date'),
              ),
              onPressed: busy
                  ? null
                  : completed
                  ? () => Navigator.pop(c)
                  : () {
                      if (!form.currentState!.validate()) return;
                      if (enabled && upcoming.isEmpty) {
                        _toast(
                          t(
                            'اختار تنبيه وقته لسه مجاش.',
                            'Choose an alert time that is still ahead.',
                          ),
                        );
                        return;
                      }
                      final leadsChanged =
                          current == null ||
                          !setEquals(leads, current.leads.toSet());
                      final keepArmedAt =
                          current?.armed == true &&
                          !leadsChanged &&
                          dayKey(date) == dayKey(current.date) &&
                          minute == current.minute;
                      final next = DateAlert(
                        date: date,
                        minute: minute,
                        leads: alertLeadDays.where(leads.contains).toList(),
                        armed: enabled,
                        armedAt: keepArmedAt ? current.armedAt : DateTime.now(),
                        repeat: repeat,
                      );
                      persist(
                        () => onSave(name.trim(), linked, next),
                        enabled ? 'armed' : 'saved',
                      );
                    },
            ),
            body: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                JournalCover(
                  title: expiry
                      ? initialName
                      : completed
                      ? t('متابعة مكتملة', 'Completed follow-up')
                      : t('خلي الموعد قدامك', 'Keep the next date in sight'),
                  subtitle: expiry
                      ? t(
                          'اكتب التاريخ الموجود على عبوة الدواء.',
                          'Use the date printed on the medication package.',
                        )
                      : t(
                          'خطّط للتحاليل أو الزيارات أو متابعة من اختيارك.',
                          'Plan a lab recheck, visit, or a follow-up of your choice.',
                        ),
                  icon: expiry
                      ? Icons.inventory_2_outlined
                      : Icons.event_repeat_outlined,
                  accent: expiry ? honey : lavender,
                ),
                const SizedBox(height: 14),
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!expiry) ...[
                        TextFormField(
                          initialValue: name,
                          enabled: !completed && !busy,
                          maxLength: 100,
                          onChanged: (value) => name = value,
                          decoration: InputDecoration(
                            labelText: t('اسم المتابعة', 'Follow-up name'),
                            counterText: '',
                          ),
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : t(
                                  'اكتب اسم المتابعة',
                                  'Enter a follow-up name',
                                ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue:
                              trackers.any((item) => item.id == linked)
                              ? linked
                              : '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t(
                              'اربط بمتابعة (اختياري)',
                              'Link to tracker (optional)',
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                t('متابعة عامة', 'General follow-up'),
                              ),
                            ),
                            for (final item in trackers)
                              DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.name(ar),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: completed || busy
                              ? null
                              : (value) => redraw(
                                  () => linked = value?.isEmpty == true
                                      ? null
                                      : value,
                                ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      ControlCard(
                        title: expiry
                            ? t('تاريخ الصلاحية', 'Expiry date')
                            : t('تاريخ المتابعة', 'Follow-up date'),
                        subtitle:
                            '${prettyDate(date, 'd MMM yyyy')} · ${_dateStatus(date, expiry: expiry)}',
                        icon: Icons.calendar_today_outlined,
                        onTap: completed || busy
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: c,
                                  initialDate: date.clampCalendar(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200, 12, 31),
                                );
                                if (picked != null && c.mounted)
                                  redraw(() => date = picked);
                              },
                      ),
                      if (!completed)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t('فعّل تنبيهات الموعد', 'Enable date alerts'),
                          ),
                          value: enabled,
                          onChanged: busy
                              ? null
                              : (value) => redraw(() => enabled = value),
                        ),
                      AnimatedSize(
                        curve: Curves.easeOutCubic,
                        duration: motion(c, 280),
                        alignment: Alignment.topCenter,
                        child: !enabled
                            ? const SizedBox(width: double.infinity)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ControlCard(
                                    title: t('وقت إرسال التنبيه', 'Alert time'),
                                    subtitle: clockText(minute),
                                    icon: Icons.alarm_outlined,
                                    onTap: busy
                                        ? null
                                        : () async {
                                            final time = await showTimePicker(
                                              context: c,
                                              initialTime: TimeOfDay(
                                                hour: minute ~/ 60,
                                                minute: minute % 60,
                                              ),
                                            );
                                            if (time != null && c.mounted)
                                              redraw(
                                                () => minute =
                                                    time.hour * 60 +
                                                    time.minute,
                                              );
                                          },
                                  ),
                                  SectionTitle(
                                    t(
                                      'إمتى تحب تتنبّه؟',
                                      'When should alerts arrive?',
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      for (final lead in alertLeadDays)
                                        FilterChip(
                                          selected: leads.contains(lead),
                                          label: Text(switch (lead) {
                                            0 => t('نفس اليوم', 'On the day'),
                                            1 => t('قبل بيوم', '1 day before'),
                                            _ => t(
                                              'قبل $lead يوم',
                                              '$lead days before',
                                            ),
                                          }),
                                          onSelected: busy
                                              ? null
                                              : (on) => redraw(
                                                  () => on
                                                      ? leads.add(lead)
                                                      : leads.remove(lead),
                                                ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ControlCard(
                                    title: t(
                                      'تكرار كل تنبيه',
                                      'Repeat each alert',
                                    ),
                                    subtitle: _repeatLabel(repeat),
                                    icon: Icons.repeat_rounded,
                                    onTap: busy
                                        ? null
                                        : () async {
                                            final selected =
                                                await _repeatPicker(repeat);
                                            if (selected != null && c.mounted)
                                              redraw(() => repeat = selected);
                                          },
                                  ),
                                  SectionTitle(
                                    t(
                                      'مواعيد التنبيهات الجاية',
                                      'Upcoming alert dates',
                                    ),
                                  ),
                                  if (upcoming.isEmpty)
                                    Text(
                                      t(
                                        'اختار تنبيه وقته لسه مجاش.',
                                        'Choose an alert time that is still ahead.',
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final next in upcoming)
                                          Chip(
                                            label: Text(
                                              prettyDate(next, 'd MMM · HH:mm'),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                      ),
                      if (onDone != null) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.task_alt_rounded),
                          onPressed: busy
                              ? null
                              : () => persist(onDone, 'done'),
                          label: Text(
                            t(
                              'علّم إن المتابعة تمّت',
                              'Mark follow-up complete',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'armed') await _requestNotifications();
    if (mounted) {
      _toast(switch (result) {
        'done' => t(
          'المتابعة تمّت والتنبيهات اتوقفت',
          'Follow-up completed and alerts cleared',
        ),
        'removed' => t('الموعد اتمسح', 'Date deleted'),
        _ => t('الموعد اتحفظ', 'Date saved'),
      }, sealed: true);
    }
  }
}

extension on DateTime {
  DateTime clampCalendar() => year < 1900
      ? DateTime(1900)
      : year > 2200
      ? DateTime(2200, 12, 31)
      : this;
}
