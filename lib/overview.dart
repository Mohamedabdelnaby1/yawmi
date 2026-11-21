part of 'main.dart';

/// Shared artwork and the content surface of the main journal pages.
class _FieldBanner extends StatelessWidget {
  const _FieldBanner({
    required this.title,
    required this.detail,
    required this.accent,
    this.action,
    this.bottom,
  });

  final String title, detail;
  final Color accent;
  final Widget? action, bottom;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: night,
      borderRadius: const BorderRadiusDirectional.only(
        topStart: Radius.circular(29),
        topEnd: Radius.circular(29),
        bottomStart: Radius.circular(29),
        bottomEnd: Radius.circular(12),
      ),
      border: Border.all(color: const Color(0xff35554a)),
    ),
    child: ClipRRect(
      borderRadius: const BorderRadiusDirectional.only(
        topStart: Radius.circular(29),
        topEnd: Radius.circular(29),
        bottomStart: Radius.circular(29),
        bottomEnd: Radius.circular(12),
      ),
      child: CustomPaint(
        painter: _FieldLines(accent, Directionality.of(context)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 15, 17, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail.isNotEmpty)
                          Text(
                            detail,
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          title,
                          style: TextStyle(
                            color: paper,
                            fontSize: 37,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                            fontFamily:
                                Directionality.of(context) == TextDirection.rtl
                                ? 'Tajawal'
                                : 'Manrope',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 8), action!],
                ],
              ),
              if (bottom != null) ...[const SizedBox(height: 12), bottom!],
            ],
          ),
        ),
      ),
    ),
  );
}

class _FieldLines extends CustomPainter {
  const _FieldLines(this.tone, this.direction);

  final Color tone;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (direction == TextDirection.rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = tone.withValues(alpha: .16);
    for (var i = 0; i < 7; i++) {
      final offset = i * 11.0;
      final path = Path()
        ..moveTo(size.width * .35, size.height + offset - 27)
        ..cubicTo(
          size.width * .66,
          size.height + offset - 129,
          size.width * .75,
          size.height + offset - 21,
          size.width + 10,
          -94 + offset,
        );
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _FieldLines oldDelegate) =>
      oldDelegate.tone != tone || oldDelegate.direction != direction;
}

class _FieldMetric extends StatelessWidget {
  const _FieldMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String value, label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    radius: 13,
    child: Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xff233e34),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xff486357)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: motion(context, 390),
                  transitionBuilder: valueMotion,
                  child: FittedBox(
                    key: ValueKey(value),
                    alignment: AlignmentDirectional.centerStart,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: accent,
                        fontFamily: 'Manrope',
                        fontSize: 20,
                        height: 1.14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: paper,
                    fontSize: 12,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if (MediaQuery.textScalerOf(context).scale(16) < 21)
            ExcludeSemantics(child: Icon(icon, color: accent, size: 18)),
        ],
      ),
    ),
  );
}

extension _Overview on _HomeState {
  Widget _periodComparison(
    Tracker tracker,
    String unit,
    String mode,
    List<JournalRow> all,
    List<JournalRow> current,
    DateTime start,
    int days,
  ) {
    final end = DateTime(start.year, start.month, start.day - 1);
    final before = inPeriod(all, end, days);
    final sum = tracker.id == 'water' || mode == 'total';
    String summarize(List<JournalRow> entries) {
      double? calculate(String key) {
        final values = entries
            .where((row) => (row['values'] as Map)[key] is num)
            .map(
              (row) => convert(
                tracker.id,
                ((row['values'] as Map)[key] as num).toDouble(),
                row['unit'] as String? ?? '',
                unit,
              ),
            )
            .toList();
        if (values.isEmpty) return null;
        final total = values.fold(0.0, (a, b) => a + b);
        return sum ? total : total / values.length;
      }

      final primary = calculate(
        tracker.id == 'pressure' ? 'systolic' : 'value',
      );
      final secondary = tracker.id == 'pressure'
          ? calculate('diastolic')
          : null;
      if (primary == null) return '—';
      final value = secondary == null
          ? number(primary)
          : '${number(primary)}/${number(secondary)}';
      return unit.isEmpty ? value : '$value $unit';
    }

    return Enter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _FieldBanner(
          title: sum
              ? t('إجمالي الفترتين', 'Period totals')
              : t('متوسط الفترتين', 'Period averages'),
          detail: t('$days يوم لكل فترة', '$days days per period'),
          accent: mint,
          bottom: Row(
            children: [
              Expanded(
                child: _FieldMetric(
                  value: summarize(current),
                  label: t('الفترة المختارة', 'Selected period'),
                  icon: Icons.today_outlined,
                  accent: leaf,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FieldMetric(
                  value: summarize(before),
                  label: t('الفترة السابقة', 'Previous period'),
                  icon: Icons.history_rounded,
                  accent: honey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quickFavorites() async {
    final allowed = cardPlan(data);
    final pinned = quickPins(data);
    final apply = await _sheet<bool>(
      (_) => StatefulBuilder(
        builder: (c, change) => _JournalPanel(
          heading: AppBar(
            title: Text(t('اختصارات التسجيل', 'Quick entry favorites')),
            leading: const CloseButton(),
          ),
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
            children: [
              Text(
                t(
                  'اختار لحد ٣ متابعات بالترتيب اللي تحب تسجّل بيه.',
                  'Choose up to three trackers in the order you want them.',
                ),
                style: TextStyle(
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (allowed.isEmpty)
                Text(
                  t(
                    'ضيف متابعة من صفحة اليوم عشان تظهر هنا.',
                    'Add a tracker in Today to see it here.',
                  ),
                ),
              for (final id in allowed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ControlCard(
                    title: cardName(data, id, ar),
                    icon: glyph(id),
                    tonalColor: tint(id),
                    selected: pinned.contains(id),
                    trailing: pinned.contains(id)
                        ? Text(
                            '${pinned.indexOf(id) + 1}',
                            style: TextStyle(
                              color: Theme.of(c).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                    onTap: !pinned.contains(id) && pinned.length >= 3
                        ? null
                        : () => change(() {
                            if (!pinned.remove(id)) pinned.add(id);
                          }),
                  ),
                ),
            ],
          ),
          footer: JournalButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('احفظ', 'Save')),
          ),
        ),
      ),
    );
    if (apply == true) await save((d) => d['quickPins'] = pinned);
  }

  Widget _todayMasthead(DateTime date, bool today, int entries, int? doses) =>
      Enter(
        key: ValueKey(dayKey(date)),
        child: _FieldBanner(
          title: today ? t('اليوم', 'Today') : prettyDate(date, 'EEEE'),
          detail: prettyDate(date, today ? 'EEEE، d MMMM' : 'd MMMM yyyy'),
          accent: leaf,
          action: IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: leaf,
              foregroundColor: ink,
            ),
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: now,
                initialDate: date,
              );
              if (selected != null && mounted) _selectDashboardDay(selected);
            },
            tooltip: t('اختار التاريخ', 'Select a date'),
            icon: const Icon(Icons.calendar_today_outlined, size: 19),
          ),
          bottom: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FieldMetric(
                  value: entries.toString(),
                  label: t('إدخالات مسجّلة', 'Journal entries'),
                  icon: Icons.receipt_long_outlined,
                  accent: leaf,
                  onTap: () => _historyDay(date),
                ),
              ),
              if (doses != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _FieldMetric(
                    value: doses.toString(),
                    label: t('جرعات منتظرة', 'Doses pending'),
                    icon: Icons.medication_outlined,
                    accent: honey,
                    onTap: doses == 0
                        ? null
                        : () => _redraw(() => _dashboardSection = 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  void _historyDay(DateTime date) => _redraw(() {
    tab = 1;
    final day = DateUtils.dateOnly(date);
    dates = DateTimeRange(start: day, end: day);
    period = 0;
    filter = null;
    conditionFilter = null;
    _search.clear();
  });

  Widget _journalActivity(List<JournalRow> shown, List<JournalRow> matching) {
    final activeDays = shown
        .map((row) => dayKey(eventTime(row)))
        .toSet()
        .length;
    final end = dates != null && now.difference(dates!.end).inDays >= 7
        ? dates!.end
        : now;
    final counts = <String, int>{};
    for (final row in inPeriod(matching, end, 7)) {
      counts.update(dayKey(eventTime(row)), (n) => n + 1, ifAbsent: () => 1);
    }
    final start = DateTime(end.year, end.month, end.day - 6);
    final days = [
      for (var offset = 0; offset < 7; offset++)
        DateTime(start.year, start.month, start.day + offset),
    ];
    final peak = days.map((d) => counts[dayKey(d)] ?? 0).fold(1, math.max);
    return _FieldBanner(
      title: t('سجلّك الصحي', 'Your health log'),
      detail: t('النشاط والتسجيلات', 'Activity & entries'),
      accent: rose,
      bottom: LayoutBuilder(
        builder: (c, size) {
          final stack =
              size.maxWidth < 290 || MediaQuery.textScalerOf(c).scale(16) > 21;
          final totals = Row(
            children: [
              Expanded(
                child: _FieldMetric(
                  value: '${shown.length}',
                  label: t('إدخالات في الفترة', 'Entries in range'),
                  icon: Icons.receipt_long_outlined,
                  accent: rose,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _FieldMetric(
                  value: '$activeDays',
                  label: t('أيام فيها تسجيل', 'Days with entries'),
                  icon: Icons.event_available_outlined,
                  accent: leaf,
                ),
              ),
            ],
          );
          final graph = Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _ActivityDay(
                    label: prettyDate(day, 'd'),
                    description: prettyDate(day, 'EEEE، d MMMM'),
                    count: counts[dayKey(day)] ?? 0,
                    peak: peak,
                    selected:
                        dates != null &&
                        dayKey(dates!.start) == dayKey(day) &&
                        dayKey(dates!.end) == dayKey(day),
                    onTap: () => _redraw(() {
                      dates = DateTimeRange(start: day, end: day);
                      period = 0;
                    }),
                  ),
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              totals,
              SizedBox(height: stack ? 10 : 8),
              Text(
                t('نشاط ٧ أيام', '7-day activity'),
                style: const TextStyle(color: paper, fontSize: 11),
              ),
              graph,
            ],
          );
        },
      ),
    );
  }
}

class _ActivityDay extends StatelessWidget {
  const _ActivityDay({
    required this.label,
    required this.description,
    required this.count,
    required this.peak,
    required this.selected,
    required this.onTap,
    this.textColor = paper,
    this.barColor = leaf,
    this.baselineColor = const Color(0xff5b7267),
    this.selectionColor = rose,
  });

  final String label, description;
  final int count, peak;
  final bool selected;
  final VoidCallback onTap;
  final Color textColor, barColor, baselineColor, selectionColor;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Pressable(
      onTap: onTap,
      label: '$description · $count',
      radius: 9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          children: [
            SizedBox(
              height: 29,
              width: double.infinity,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: motion(context, 480),
                  curve: Curves.easeOutCubic,
                  height: 4 + 24 * count / peak,
                  width: 11,
                  decoration: BoxDecoration(
                    color: selected
                        ? selectionColor
                        : count > 0
                        ? barColor
                        : baselineColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                height: 1.2,
                color: selected ? selectionColor : textColor,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
