part of 'main.dart';

typedef CareEvent = ({
  DateTime at,
  String kind,
  String id,
  List<String> conditions,
  JournalRow row,
});

List<CareEvent> careTimeline(JournalRow state) {
  final items = <CareEvent>[];
  final medicines = {for (final row in rows(state['meds'])) row['id']: row};
  void add(
    Object? time,
    String kind,
    String id,
    List<String> conditions,
    JournalRow row,
  ) {
    final at = DateTime.tryParse(time?.toString() ?? '')?.toLocal();
    if (at != null)
      items.add((at: at, kind: kind, id: id, conditions: conditions, row: row));
  }

  for (final row in rows(state['entries'])) {
    if (row['legacyUndated'] == true ||
        isPlannedEntry(row) && row['planCompletedAt'] == null)
      continue;
    add(
      row['planCompletedAt'] ?? row['at'],
      'entry',
      row['id'],
      rows(row['conditions']).map((c) => c['id']).whereType<String>().toList(),
      row,
    );
  }
  for (final row in rows(state['doses'])) {
    add(
      row['at'],
      'dose',
      row['id'],
      strings(medicines[row['medicine']]?['links']),
      row,
    );
  }
  for (final row in medicines.values) {
    for (final change in rows(row['changes'])) {
      add(change['at'], 'change', row['id'], strings(row['links']), {
        ...change,
        'name': row['name'],
      });
    }
    add(row['effective'], 'schedule', row['id'], strings(row['links']), row);
  }
  final plans = state['carePlans'] as Map? ?? {};
  for (final plan in plans.entries) {
    if (plan.key is! String || plan.value is! Map) continue;
    final row = Map<String, dynamic>.from(plan.value as Map);
    add(row['updatedAt'], 'plan', plan.key, [plan.key], row);
  }
  for (final row in rows(state['visits'])) {
    add(row['reviewedAt'], 'visit', row['id'], [
      if (row['condition'] case final String id) id,
    ], row);
  }
  return items..sort((a, b) => b.at.compareTo(a.at));
}

extension _CareJourney on _HomeState {
  Future<void> _timeline() {
    var days = 30;
    String? condition;
    return _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => ListenableBuilder(
          listenable: widget.db,
          builder: (c, _) {
            final now = DateTime.now();
            final first = shiftCalendarDate(now, 1 - days);
            final visible = careTimeline(data)
                .where(
                  (item) =>
                      !item.at.isBefore(first) &&
                      (condition == null ||
                          item.conditions.contains(condition)),
                )
                .toList();
            return Scaffold(
              appBar: AppBar(title: Text(t('خط المتابعة', 'Care timeline'))),
              body: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          JournalCover(
                            title: t(
                              'المتابعة بالترتيب',
                              'Your care over time',
                            ),
                            subtitle: t(
                              'القياسات والأعراض والجرعات وتغييرات المتابعة في نفس المكان.',
                              'Readings, symptoms, doses, and care changes in one place.',
                            ),
                            icon: Icons.timeline_rounded,
                            accent: mint,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final period in [7, 30, 90])
                                ChoiceChip(
                                  label: Text(t('$period يوم', '$period days')),
                                  selected: days == period,
                                  onSelected: (_) =>
                                      redraw(() => days = period),
                                ),
                            ],
                          ),
                          _choiceSetting(
                            c,
                            t('الحالة', 'Condition'),
                            condition ?? '',
                            [
                              ('', t('كل الحالات', 'All conditions')),
                              for (final row in rows(data['conditions']))
                                (row['id'] as String, conditionName(row, ar)),
                            ],
                            (id) => redraw(
                              () => condition = id.isEmpty ? null : id,
                            ),
                            icon: Icons.filter_list_rounded,
                          ),
                          if (visible.isEmpty)
                            EmptyPanel(
                              Icons.timeline_rounded,
                              t(
                                'مفيش تسجيلات في الفترة دي',
                                'No entries in this period',
                              ),
                              '',
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (c, index) {
                        final item = visible[index];
                        final startsDay =
                            index == 0 ||
                            dayKey(visible[index - 1].at) != dayKey(item.at);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (startsDay)
                              SectionTitle(prettyDate(item.at, 'EEEE، d MMMM')),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _timelineEvent(item),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _timelineEvent(CareEvent event) {
    final row = event.row;
    final tracker = event.kind == 'entry'
        ? trackerFor(data, row['tracker'])
        : null;
    final (title, details, icon, action) = switch (event.kind) {
      'dose' => (
        _doseName(row),
        row['status'] == 'taken'
            ? t('اتسجّلت كأُخذت', 'Marked taken')
            : t('اتخطّت', 'Skipped'),
        Icons.medication_outlined,
        () => _doseHistory(row),
      ),
      'change' => (
        t('تغيير جرعة · ${row['name']}', 'Dose change · ${row['name']}'),
        '${row['previous']} → ${row['dose']}',
        Icons.edit_calendar_outlined,
        () => _medDetails(event.id),
      ),
      'schedule' => (
        t(
          'تعديل المواعيد · ${row['name']}',
          'Schedule changed · ${row['name']}',
        ),
        ints(row['times']).map(clockText).join(' · '),
        Icons.schedule_rounded,
        () => _medDetails(event.id),
      ),
      'plan' => (
        t('تعديل خطة المتابعة', 'Care plan updated'),
        _planLabel(event.id),
        Icons.fact_check_outlined,
        () => _editCarePlan(event.id),
      ),
      'visit' => (
        row['name'] as String,
        t('ملاحظات بعد الزيارة', 'After-visit notes'),
        Icons.event_available_outlined,
        () => _visit(event.id),
      ),
      _ => (
        tracker?.name(ar) ?? t('تسجيل', 'Entry'),
        reportValue(row, ar),
        glyph(row['tracker']),
        tracker == null ? null : () => _entry(tracker, item: row),
      ),
    };
    return ControlCard(
      title: title,
      subtitle:
          '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(event.at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} · $details',
      icon: icon,
      tonalColor: tracker == null ? mint : tint(tracker.id),
      onTap: action,
    );
  }

  Future<void> _visits() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final visits = rows(
          data['visits'],
        )..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
        return Scaffold(
          appBar: AppBar(title: Text(t('زياراتي', 'Visits'))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editVisit(),
            icon: const Icon(Icons.add_rounded),
            label: Text(t('زيارة جديدة', 'New visit')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 94),
            children: [
              JournalCover(
                title: t('حضّر للزيارة وتابع بعدها', 'Prepare and follow up'),
                subtitle: t(
                  'أسئلتك والنتايج والمواعيد في صفحة لكل زيارة.',
                  'Questions, results, and follow-up in one place per visit.',
                ),
                icon: Icons.event_note_outlined,
                accent: lavender,
              ),
              const SizedBox(height: 12),
              if (visits.isEmpty)
                EmptyPanel(
                  Icons.event_outlined,
                  t('لسه مفيش زيارات', 'No visits yet'),
                  '',
                ),
              for (final visit in visits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ControlCard(
                    title: visit['name'],
                    subtitle:
                        '${prettyDate(parseCalendarDate(visit['date'])!)} · ${visit['reviewedAt'] == null ? t('قبل الزيارة', 'Preparing') : t('بعد الزيارة', 'Follow-up')}',
                    icon: Icons.event_available_rounded,
                    tonalColor: lavender,
                    onTap: () => _visit(visit['id']),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _visit(String id) => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final visit = rows(
          data['visits'],
        ).where((row) => row['id'] == id).firstOrNull;
        if (visit == null) return Scaffold(appBar: AppBar());
        final day = parseCalendarDate(visit['date'])!;
        final linked = strings(visit['linkedEntries']);
        final attached = rows(
          data['entries'],
        ).where((entry) => linked.contains(entry['id'])).toList();
        final plan = rows(
          data['followUps'],
        ).where((item) => item['id'] == visit['followUp']).firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(t('تفاصيل الزيارة', 'Visit details')),
            actions: [
              IconButton(
                tooltip: t('عدّل الزيارة', 'Edit visit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editVisit(existing: visit),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              JournalCover(
                title: visit['name'],
                subtitle: prettyDate(day, 'EEEE d MMMM yyyy'),
                icon: Icons.event_note_outlined,
                accent: lavender,
              ),
              SectionTitle(t('قبل الزيارة', 'Before the visit')),
              if ((visit['questions'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(visit['questions']),
                ),
              ControlCard(
                title: t(
                  'اختار تحاليل وأسئلة من السجل',
                  'Link labs and questions',
                ),
                subtitle: t(
                  '${attached.length} مرفق من السجل',
                  '${attached.length} linked records',
                ),
                icon: Icons.attach_file,
                onTap: () => _linkVisitEntries(visit),
              ),
              for (final entry in attached)
                if (trackerFor(data, entry['tracker']) case final tracker?)
                  ListTile(
                    title: Text(reportValue(entry, ar)),
                    subtitle: Text(prettyDate(eventTime(entry), 'd MMM yyyy')),
                    onTap: () => _entry(tracker, item: entry),
                  ),
              OutlinedButton.icon(
                onPressed: () {
                  final period = DateTimeRange(
                    start: shiftCalendarDate(day, -30),
                    end: day,
                  );
                  final entries = sourceForVisit(data, visit, period);
                  final start = entries
                      .map(eventTime)
                      .fold(
                        period.start,
                        (start, entry) => entry.isBefore(start) ? entry : start,
                      );
                  final end = entries
                      .map(eventTime)
                      .fold(
                        period.end,
                        (end, entry) => entry.isAfter(end) ? entry : end,
                      );
                  _report(
                    presetRange: DateTimeRange(start: start, end: end),
                    sourceOverride: entries,
                    onePage: true,
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(t('جهّز ملخص الزيارة', 'Prepare visit summary')),
              ),
              SectionTitle(t('بعد الزيارة', 'After the visit')),
              if ((visit['outcome'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(visit['outcome']),
                ),
              ControlCard(
                title: t(
                  'دوّن اللي اتفقت عليه',
                  'Record the agreed next steps',
                ),
                icon: Icons.edit_note_rounded,
                onTap: () => _editVisit(existing: visit, after: true),
              ),
              const SizedBox(height: 8),
              ControlCard(
                title:
                    plan?['name'] as String? ??
                    t('اضبط موعد متابعة', 'Schedule a follow-up'),
                icon: Icons.event_repeat_outlined,
                subtitle: plan == null
                    ? null
                    : _dateStatus(DateAlert.read(plan['alert'])!.date),
                onTap: () => _openFollowUp(
                  plan?['id'] as String?,
                  visitId: id,
                  suggestedName: t(
                    'متابعة ${visit['name']}',
                    'Follow-up · ${visit['name']}',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _editVisit({JournalRow? existing, bool after = false}) async {
    var name = existing?['name'] as String? ?? '';
    var questions = existing?['questions'] as String? ?? '';
    var outcome = existing?['outcome'] as String? ?? '';
    var date =
        parseCalendarDate(existing?['date']) ??
        DateUtils.dateOnly(DateTime.now());
    var condition = existing?['condition'] as String?;
    final id = existing?['id'] as String? ?? newId();
    var busy = false;
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => _JournalPanel(
          heading: AppBar(
            title: Text(
              after
                  ? t('بعد الزيارة', 'After the visit')
                  : t('بيانات الزيارة', 'Visit information'),
            ),
            leading: const CloseButton(),
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              if (after)
                _careTextField(
                  t('اللي اتفقت عليه', 'Agreed next steps'),
                  outcome,
                  (v) => outcome = v,
                  lines: 4,
                )
              else ...[
                _careTextField(
                  t('اسم الزيارة', 'Visit name'),
                  name,
                  (v) => redraw(() => name = v),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: c,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null && c.mounted)
                      redraw(() => date = selected);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(prettyDate(date, 'd MMM yyyy')),
                ),
                _choiceSetting(
                  c,
                  t('الحالة', 'Condition'),
                  condition ?? '',
                  [
                    ('', t('بدون ربط', 'Unlinked')),
                    for (final row in rows(data['conditions']))
                      (row['id'] as String, conditionName(row, ar)),
                  ],
                  (id) => redraw(() => condition = id.isEmpty ? null : id),
                  icon: Icons.link,
                ),
                const SizedBox(height: 10),
                _careTextField(
                  t('أسئلة للزيارة', 'Questions for the visit'),
                  questions,
                  (v) => questions = v,
                  lines: 3,
                ),
              ],
            ],
          ),
          footer: JournalButton.icon(
            label: Text(t('احفظ', 'Save')),
            icon: const Icon(Icons.check_rounded),
            onPressed: name.trim().isEmpty || busy
                ? null
                : () async {
                    redraw(() => busy = true);
                    final saved = await save(
                      (d) => upsert(d, 'visits', {
                        ...?existing,
                        'id': id,
                        'name': name.trim(),
                        'date': dayKey(date),
                        'questions': questions.trim(),
                        'outcome': outcome.trim(),
                        'condition': condition,
                        'linkedEntries': strings(existing?['linkedEntries']),
                        if (after)
                          'reviewedAt': DateTime.now()
                              .toUtc()
                              .toIso8601String(),
                      }),
                    );
                    if (!c.mounted) return;
                    if (saved) {
                      Navigator.pop(c);
                    } else {
                      redraw(() => busy = false);
                    }
                  },
          ),
        ),
      ),
    );
  }

  Future<void> _linkVisitEntries(JournalRow visit) async {
    final selected = strings(visit['linkedEntries']).toSet();
    final available =
        rows(data['entries'])
            .where((entry) => ['lab', 'question'].contains(entry['tracker']))
            .toList()
          ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
    await _sheet<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => _JournalPanel(
          heading: AppBar(
            title: Text(t('ربط من السجل', 'Link from the journal')),
            leading: const CloseButton(),
          ),
          body: ListView.builder(
            shrinkWrap: true,
            itemCount: available.length,
            itemBuilder: (c, index) {
              final row = available[index];
              return CheckboxListTile(
                title: Text(reportValue(row, ar)),
                subtitle: Text(prettyDate(eventTime(row), 'd MMM yyyy')),
                value: selected.contains(row['id']),
                onChanged: (checked) => redraw(() {
                  if (checked == true && selected.length < 80) {
                    selected.add(row['id']);
                  } else if (checked == false) {
                    selected.remove(row['id']);
                  }
                }),
              );
            },
          ),
          footer: JournalButton(
            onPressed: () async {
              final ok = await save((d) {
                final current = rows(
                  d['visits'],
                ).where((row) => row['id'] == visit['id']).firstOrNull;
                if (current != null)
                  upsert(d, 'visits', {
                    ...current,
                    'linkedEntries': selected.toList(),
                  });
              });
              if (ok && c.mounted) Navigator.pop(c);
            },
            child: Text(t('احفظ', 'Save')),
          ),
        ),
      ),
    );
  }
}

List<JournalRow> sourceForVisit(
  JournalRow state,
  JournalRow visit,
  DateTimeRange period,
) {
  final linked = strings(visit['linkedEntries']).toSet();
  final condition = visit['condition'];
  final last = shiftCalendarDate(period.end, 1);
  return [
    if ((visit['questions'] as String? ?? '').isNotEmpty)
      {
        'id': 'visit-questions:${visit['id']}',
        'at': period.end.toUtc().toIso8601String(),
        'tracker': 'question',
        'values': {'value': visit['questions']},
      },
    for (final row in rows(state['entries']))
      if (linked.contains(row['id']) ||
          (!eventTime(row).isBefore(period.start) &&
              eventTime(row).isBefore(last) &&
              (condition == null ||
                  rows(
                    row['conditions'],
                  ).any((link) => link['id'] == condition))))
        row,
    for (final row in rows(state['doses']))
      if (!eventTime(row).isBefore(period.start) &&
          eventTime(row).isBefore(last) &&
          (condition == null ||
              rows(state['meds']).any(
                (med) =>
                    med['id'] == row['medicine'] &&
                    strings(med['links']).contains(condition),
              )))
        {...row, 'tracker': medicineCard},
  ];
}
