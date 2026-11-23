part of 'main.dart';

enum AgendaKind { dose, reminder, appointment, followUp }

class AgendaItem {
  const AgendaItem(
    this.kind,
    this.at,
    this.label,
    this.tracker, {
    this.dose,
    this.row,
  });

  final AgendaKind kind;
  final DateTime at;
  final String label, tracker;
  final Dose? dose;
  final JournalRow? row;
}

List<AgendaItem> journalAgenda(
  JournalRow state,
  DateTime from, {
  int days = 1,
}) {
  final start = DateUtils.dateOnly(from);
  final end = DateTime(start.year, start.month, start.day + days);
  final entries = (state['entries'] as List? ?? []).cast<JournalRow>();
  final reminders = trackingSchedules(state, false);
  final result = <AgendaItem>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    final completed = trackingReminderMatches(state, day, schedules: reminders);
    for (final dose in outstanding(state, day)) {
      result.add(
        AgendaItem(
          AgendaKind.dose,
          dose.time,
          dose.medicine['name'],
          medicineCard,
          dose: dose,
        ),
      );
    }
    for (final rule in reminders) {
      final at = reminderTimeOn(rule, day);
      if (at != null &&
          (rule['waterPlan'] != true ||
              from.isBefore(at.add(Duration(minutes: rule['maxDelay'])))) &&
          !completed.containsKey(reminderOccurrence(rule['id'], day))) {
        result.add(
          AgendaItem(
            AgendaKind.reminder,
            at,
            rule['name'],
            rule['tracker'] as String? ?? '',
            row: rule,
          ),
        );
      }
    }
  }
  for (final entry in entries) {
    if (!isPlannedEntry(entry) || entry['planCompletedAt'] != null) continue;
    final at = eventTime(entry);
    if (!at.isBefore(start) && at.isBefore(end)) {
      result.add(
        AgendaItem(
          AgendaKind.appointment,
          at,
          valueText(entry, false),
          entry['tracker'],
          row: entry,
        ),
      );
    }
  }
  for (final plan in pendingFollowUps(state)) {
    final alert = DateAlert.read(plan['alert']);
    if (alert == null) continue;
    final day = alert.date;
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      alert.minute ~/ 60,
      alert.minute % 60,
    );
    if (!at.isBefore(start) && at.isBefore(end)) {
      result.add(
        AgendaItem(
          AgendaKind.followUp,
          at,
          plan['name'],
          plan['tracker'] as String? ?? '',
          row: plan,
        ),
      );
    }
  }
  return result..sort((a, b) {
    final chronological = a.at.compareTo(b.at);
    return chronological == 0
        ? a.kind.index.compareTo(b.kind.index)
        : chronological;
  });
}

AgendaItem? nextJournalAction(List<AgendaItem> agenda, DateTime now) =>
    agenda
        .where((item) => item.kind == AgendaKind.dose && !item.at.isAfter(now))
        .firstOrNull ??
    agenda.firstOrNull;

class JournalWeek {
  JournalWeek(
    this.start,
    this.end,
    this.entries,
    this.recordedDays,
    this.readings,
    this.taken,
    this.skipped,
  );

  final DateTime start, end;
  final List<JournalRow> entries;
  final Map<String, int> recordedDays, readings;
  final int taken, skipped;
  int get blankDays => 7 - recordedDays.length;
}

JournalWeek journalWeek(JournalRow state, DateTime now) {
  final end = DateUtils.dateOnly(now);
  final start = DateTime(end.year, end.month, end.day - 6);
  final entries = <JournalRow>[];
  final recordedDays = <String, int>{};
  final readings = <String, int>{};
  var taken = 0, skipped = 0;
  for (final row in rows(state['entries'])) {
    if (isPlannedEntry(row) && row['planCompletedAt'] == null) continue;
    final at =
        DateTime.tryParse(row['planCompletedAt'] as String? ?? '')?.toLocal() ??
        eventTime(row);
    if (at.isBefore(start) || at.isAfter(now)) continue;
    entries.add({...row, 'at': at.toUtc().toIso8601String()});
    recordedDays.update(dayKey(at), (count) => count + 1, ifAbsent: () => 1);
    final id = row['tracker'] as String;
    if (trackerFor(state, id)?.kind == 'number') {
      readings.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  for (final row in rows(state['doses'])) {
    final at = eventTime(row);
    if (at.isBefore(start) || at.isAfter(now)) continue;
    if (row['status'] == 'taken') taken++;
    if (row['status'] == 'skipped') skipped++;
    entries.add({...row, 'tracker': medicineCard});
    recordedDays.update(dayKey(at), (count) => count + 1, ifAbsent: () => 1);
  }
  return JournalWeek(
    start,
    end,
    entries,
    recordedDays,
    readings,
    taken,
    skipped,
  );
}

extension _Daily on _HomeState {
  String _agendaTime(AgendaItem item, {bool date = false}) => [
    if (date) prettyDate(item.at),
    clockText(item.at.hour * 60 + item.at.minute),
    if (item.dose case final dose?) ?doseMealLabel(dose.mealSlot, ar),
  ].join(' · ');

  IconData _agendaIcon(AgendaItem item) => item.tracker.isEmpty
      ? Icons.notifications_none_rounded
      : glyph(item.tracker);

  String _agendaStatus(AgendaItem item) => agendaCopy(
    ar,
    item.at,
    now,
    dose: item.kind == AgendaKind.dose,
    visit:
        item.kind == AgendaKind.followUp || item.kind == AgendaKind.appointment,
  );

  Future<void> _openTrackedReminder(
    String id,
    String date, {
    bool alreadyLogged = false,
  }) async {
    final day = parseCalendarDate(date);
    if (day == null || day.isAfter(DateTime.now())) return;
    final schedules = trackingSchedules(data, ar);
    final rule = schedules.where((row) => row['id'] == id).firstOrNull;
    final trackerId = rule?['tracker'];
    if (rule == null || trackerId is! String) return;
    final tracker = trackerFor(data, trackerId);
    final due = reminderTimeOn(rule, day);
    if (tracker == null || due == null) return;
    final occurrence = reminderOccurrence(id, day);
    if (trackingReminderMatches(
      data,
      day,
      schedules: schedules,
    ).containsKey(occurrence)) {
      _toast(
        t(
          'التسجيل متسجّل للميعاد ده بالفعل',
          'This reminder already has an entry',
        ),
      );
      return;
    }
    if (alreadyLogged) {
      if (!await _linkSavedReminder(tracker, due, occurrence) &&
          mounted &&
          _unusedReminderEntries(data, tracker, due, occurrence).isEmpty) {
        _toast(
          t(
            'لسه مفيش تسجيل متاح في اليوم ده',
            'No available entry for this day',
          ),
        );
      }
    } else if (tracker.id == 'water') {
      await _waterReminderCups(due, occurrence);
    } else {
      await _entry(tracker, initialDay: due, occurrence: occurrence);
    }
  }

  List<JournalRow> _unusedReminderEntries(
    JournalRow state,
    Tracker tracker,
    DateTime day,
    String occurrence,
  ) {
    final matches = trackingReminderMatches(state, day);
    if (matches.containsKey(occurrence)) return [];
    final used = matches.values.toSet();
    return rows(state['entries'])
        .where(
          (entry) =>
              entry['tracker'] == tracker.id &&
              canCompleteTrackingReminder(entry, day) &&
              !eventTime(entry).isAfter(DateTime.now()) &&
              !used.contains(entry['id']),
        )
        .toList()
      ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
  }

  Future<bool> _linkSavedReminder(
    Tracker tracker,
    DateTime day,
    String occurrence,
  ) async {
    final options = _unusedReminderEntries(data, tracker, day, occurrence);
    if (options.isEmpty) return false;
    final selected = await _sheet<String>(
      (c) => _JournalPanel(
        heightFactor: .62,
        heading: AppBar(
          title: Text(t('اختار تسجيل موجود', 'Choose an existing entry')),
          leading: const CloseButton(),
        ),
        body: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          itemCount: options.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (c, index) {
            final entry = options[index];
            return ControlCard(
              title: reportValue(entry, ar),
              subtitle: prettyDate(eventTime(entry), 'd MMM · HH:mm'),
              icon: glyph(tracker.id),
              onTap: () => Navigator.pop(c, entry['id'] as String),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return false;
    var linked = false;
    final saved = await save((draft) {
      final entry = _unusedReminderEntries(
        draft,
        tracker,
        day,
        occurrence,
      ).where((row) => row['id'] == selected).firstOrNull;
      if (entry == null) return;
      upsert(draft, 'entries', {...entry, 'reminderOccurrence': occurrence});
      linked = true;
    });
    if (!mounted || !saved) return false;
    _toast(
      linked
          ? t('اتربط التسجيل بالميعاد', 'Entry linked to this reminder')
          : t(
              'التسجيل ده مبقاش متاح للربط',
              'That entry is no longer available',
            ),
      sealed: linked,
    );
    return linked;
  }

  Future<void> _openAgendaItem(AgendaItem item) async {
    final today = dayKey(item.at) == dayKey(DateTime.now());
    switch (item.kind) {
      case AgendaKind.dose:
        if (today) {
          await _actDose(item.dose!);
        } else {
          await _medDetails(item.dose!.medicine['id']);
        }
      case AgendaKind.reminder:
        final tracker = trackerFor(data, item.tracker);
        if (today && tracker != null) {
          await _openTrackedReminder(item.row!['id'], dayKey(item.at));
        } else if (item.row?['waterPlan'] == true) {
          await _waterReminder();
        } else {
          final id = item.row?['groupId'] ?? item.row?['id'];
          final original = rows(
            data['reminders'],
          ).where((r) => r['id'] == id).firstOrNull;
          if (original != null) await _reminder(existing: original);
        }
      case AgendaKind.appointment:
        final row = item.row!;
        final tracker = trackerFor(data, item.tracker);
        if (tracker == null) return;
        final action = await _sheet<String>(
          (c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JournalCover(
                  title: item.label,
                  subtitle: _agendaTime(item, date: true),
                  icon: _agendaIcon(item),
                ),
                const SizedBox(height: 10),
                if (!item.at.isAfter(DateTime.now()))
                  JournalButton(
                    onPressed: () => Navigator.pop(c, 'done'),
                    child: Text(
                      t('سجّل إن الموعد تمّ', 'Mark appointment completed'),
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, 'edit'),
                  child: Text(
                    t('راجع أو عدّل الموعد', 'Review or edit appointment'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (action == 'edit' && mounted) {
          await _entry(tracker, item: row);
        } else if (action == 'done' &&
            mounted &&
            await save((d) {
              final latest = rows(
                d['entries'],
              ).where((e) => e['id'] == row['id']).firstOrNull;
              if (latest != null &&
                  !eventTime(latest).isAfter(DateTime.now())) {
                upsert(d, 'entries', {
                  ...latest,
                  'planCompletedAt': DateTime.now().toUtc().toIso8601String(),
                });
              }
            })) {
          _toast(
            t('اتسجّل إن الموعد تمّ', 'Appointment marked completed'),
            sealed: true,
          );
        }
      case AgendaKind.followUp:
        await _openFollowUp(item.row!['id']);
    }
  }

  Widget _dailyAgenda(AgendaItem? first, {required bool showDoses}) {
    final firstTracker = first != null || data['firstDayGuide'] != true
        ? null
        : cardPlan(data)
              .map((id) => trackerFor(data, id))
              .whereType<Tracker>()
              .where((tracker) => tracker.kind == 'number')
              .firstOrNull;
    final needsReading =
        firstTracker != null &&
        !(data['entries'] as List? ?? []).cast<JournalRow>().any(
          (row) => row['tracker'] == firstTracker.id,
        );
    final needsReminder =
        firstTracker != null &&
        !rows(data['reminders']).any(
          (row) => row['tracker'] == firstTracker.id && row['enabled'] == true,
        );
    final receipt = _recentDoseId == null
        ? null
        : doseEvent(data, _recentDoseId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: motion(context, 320),
          transitionBuilder: valueMotion,
          child: receipt == null || dayKey(eventTime(receipt)) != dayKey(now)
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(receipt['id']),
                  padding: const EdgeInsets.only(top: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline_rounded),
                      title: Text(t('جرعة اتسجّلت', 'Dose recorded')),
                      subtitle: Text(_doseName(receipt)),
                      onTap: () => _doseHistory(receipt),
                    ),
                  ),
                ),
        ),
        if (first != null) ...[
          SectionTitle(
            t('دلوقتي', 'Next action'),
            action: showDoses
                ? TextButton(
                    onPressed: () => _redraw(() => _dashboardSection = 1),
                    child: Text(t('الجرعات', 'Doses')),
                  )
                : null,
          ),
          _featuredTodayAction(
            key: ValueKey('agenda-focus-${first.kind.name}'),
            title: first.row?['waterPlan'] == true
                ? t('اشرب مياه', 'Drink water')
                : first.label,
            subtitle: '${_agendaStatus(first)} · ${_agendaTime(first)}',
            icon: _agendaIcon(first),
            tone: first.at.isAfter(now) ? mint : honey,
            action: switch (first.kind) {
              AgendaKind.dose => t('سجّل الجرعة', 'Log dose'),
              AgendaKind.reminder => t('افتح التسجيل', 'Open entry'),
              _ => t('افتح المتابعة', 'Open follow-up'),
            },
            onTap: () => _openAgendaItem(first),
          ),
        ] else if (firstTracker != null && (needsReading || needsReminder)) ...[
          const SizedBox(height: 10),
          ControlCard(
            title: needsReading
                ? t('سجّل أول قياس', 'Log your first reading')
                : t('اضبط موعد المتابعة', 'Set a tracking reminder'),
            subtitle: firstTracker.name(ar),
            icon: glyph(firstTracker.id),
            tonalColor: mint,
            toned: true,
            onTap: needsReading
                ? firstTracker.id == 'water'
                      ? _hydrationDetails
                      : () => _entry(firstTracker)
                : () => _reminder(tracker: firstTracker.id),
            trailing: IconButton(
              tooltip: t('إخفاء الاقتراح', 'Dismiss suggestion'),
              onPressed: () => save((d) => d.remove('firstDayGuide')),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          if (needsReading && needsReminder)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _reminder(tracker: firstTracker.id),
                icon: const Icon(Icons.schedule_rounded),
                label: Text(t('اضبط موعد المتابعة', 'Set a tracking reminder')),
              ),
            ),
        ] else if (showDoses)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _redraw(() => _dashboardSection = 1),
              child: Text(t('الجرعات', 'Doses')),
            ),
          ),
      ],
    );
  }

  Widget _featuredTodayAction({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color tone,
    required String action,
    required VoidCallback onTap,
  }) => Enter(
    key: key,
    child: Material(
      color: night,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        child: CustomPaint(
          painter: _FieldLines(tone, Directionality.of(context)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: tone, size: 25),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: paper,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: tone)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    foregroundColor: ink,
                  ),
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(action),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _upcomingAgenda(List<AgendaItem> agenda, AgendaItem? first) {
    final other = agenda.where((item) => !identical(item, first));
    final next = other.where((item) => item.at.isAfter(now)).firstOrNull;
    final overdue = other.where((item) => !item.at.isAfter(now)).length;
    final contextLabel = [
      if (next != null)
        next.row?['waterPlan'] == true
            ? t('اشرب مياه', 'Drink water')
            : next.label,
      if (next != null) _agendaTime(next, date: dayKey(next.at) != dayKey(now)),
      if (overdue > 0) "${t('فات موعدها', 'Awaiting entry')} · $overdue",
    ].join(' · ');
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        minTileHeight: 50,
        leading: const Icon(Icons.event_note_outlined),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        title: Text(t('المواعيد اللي جاية', 'Upcoming schedule')),
        subtitle: contextLabel.isEmpty
            ? null
            : Text(contextLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _agendaPage,
      ),
    );
  }

  Future<void> _agendaPage() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final items = journalAgenda(data, DateTime.now(), days: 7);
        return Scaffold(
          appBar: AppBar(title: Text(t('مواعيدي', 'My schedule'))),
          body: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyPanel(
                    Icons.event_available_outlined,
                    t(
                      'مفيش مواعيد خلال ٧ أيام',
                      'Nothing scheduled in the next 7 days',
                    ),
                    '',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (c, i) {
                    final item = items[i];
                    return Column(
                      children: [
                        if (i == 0 ||
                            dayKey(item.at) != dayKey(items[i - 1].at))
                          SectionTitle(prettyDate(item.at, 'EEEE، d MMMM')),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ControlCard(
                            title: item.row?['waterPlan'] == true
                                ? t('اشرب مياه', 'Drink water')
                                : item.label,
                            subtitle:
                                '${_agendaTime(item)} · ${_agendaStatus(item)}',
                            icon: _agendaIcon(item),
                            tonalColor: item.at.isAfter(now) ? ice : honey,
                            onTap: () => _openAgendaItem(item),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    ),
  );

  Future<void> _weeklyReview() => _page<void>(
    (_) => ListenableBuilder(
      listenable: widget.db,
      builder: (c, _) {
        final week = journalWeek(data, DateTime.now());
        final range = DateTimeRange(start: week.start, end: week.end);
        final byTracker = week.readings.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return Scaffold(
          appBar: AppBar(title: Text(t('ملخّص الأسبوع', 'Weekly review'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FieldBanner(
                title: t('آخر ٧ أيام', 'Last 7 days'),
                detail: '${prettyDate(week.start)} – ${prettyDate(week.end)}',
                accent: lavender,
                bottom: Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    _weeklyMetric(
                      t('قراءات', 'Readings'),
                      byTracker.fold(0, (sum, item) => sum + item.value),
                    ),
                    _weeklyMetric(
                      t('أيام من غير تسجيل', 'Days with no entries'),
                      week.blankDays,
                    ),
                    _weeklyMetric(
                      t('جرعات أُخذت', 'Doses logged as taken'),
                      week.taken,
                    ),
                    _weeklyMetric(
                      t('جرعات متخطّية', 'Doses skipped'),
                      week.skipped,
                    ),
                  ],
                ),
              ),
              SectionTitle(t('نشاط الأيام', 'Daily activity')),
              LayoutBuilder(
                builder: (c, bounds) {
                  const gap = 6.0;
                  final fitRow =
                      bounds.maxWidth >= 325 &&
                      MediaQuery.textScalerOf(c).scale(14) <= 18;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < 7; i++)
                        SizedBox(
                          width: fitRow
                              ? (bounds.maxWidth - 6 * gap) / 7
                              : null,
                          child: _weeklyDay(
                            DateTime(
                              week.start.year,
                              week.start.month,
                              week.start.day + i,
                            ),
                            week,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (byTracker.isNotEmpty)
                SectionTitle(t('القراءات حسب المتابعة', 'Readings by tracker')),
              for (final item in byTracker)
                ListTile(
                  leading: TileIcon(item.key, size: 34),
                  title: Text(cardName(data, item.key, ar)),
                  trailing: Text(item.value.toString()),
                ),
              if (week.entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                JournalButton.icon(
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(t('جهّز ملخّص الزيارة', 'Prepare visit summary')),
                  onPressed: () => _report(
                    presetRange: range,
                    sourceOverride: week.entries,
                    onePage: true,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _weeklyMetric(String label, int value) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text('$value · $label', style: const TextStyle(color: paper)),
    ),
  );

  Widget _weeklyDay(DateTime day, JournalWeek week) {
    final count = week.recordedDays[dayKey(day)] ?? 0;
    final colors = Theme.of(context).colorScheme;
    const arDays = ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
    return Semantics(
      label: '${prettyDate(day)} · ${t('إدخالات', 'Entries')} $count',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 43),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: count > 0 ? colors.secondaryContainer : colors.surface,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ar ? arDays[day.weekday - 1] : prettyDate(day, 'EEE')),
            Text('$count', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
