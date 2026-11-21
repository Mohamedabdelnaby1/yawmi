part of 'main.dart';

const _waterDark = Color(0xff172b50);
const _aqua = Color(0xffc5fff6);

Color _waterText(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? paper : _waterDark;
Color _waterAccent(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? _aqua : const Color(0xff17607f);

extension _Hydration on _HomeState {
  double _waterLevel(double n) {
    final goal = data['waterGoal'] as num?;
    return goal != null && goal > 0 ? (n / goal).clamp(0, 1) : n / (n + 600);
  }

  Widget _hydrationAmount(
    double amount,
    double fontSize, {
    String unit = 'mL',
  }) => TweenAnimationBuilder<double>(
    tween: Tween(end: amount),
    duration: motion(context, 670),
    curve: const Cubic(.13, .88, .18, 1),
    builder: (c, value, _) => Text(
      '${number(convert('water', unit == 'mL' ? value.roundToDouble() : value, 'mL', unit))} $unit',
      key: const ValueKey('water-total'),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _waterText(c),
        fontFamily: 'Manrope',
        fontSize: fontSize,
        height: 1.16,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
      ),
    ),
  );

  Widget _cupPresets(int selected, ValueChanged<int> select) => Row(
    children: [
      for (final ml in waterCups(data))
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 5),
            child: Semantics(
              selected: selected == ml,
              child: Pressable(
                radius: 12,
                label: '$ml mL',
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  select(ml);
                },
                child: AnimatedContainer(
                  duration: motion(context, 270),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == ml ? _aqua : Colors.transparent,
                    border: Border.all(
                      color: selected == ml
                          ? _waterAccent(context)
                          : _waterAccent(context).withValues(alpha: .55),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$ml',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: selected == ml ? _waterDark : _waterText(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _pourButton(int amount, VoidCallback onTap) => Pressable(
    radius: 16,
    onTap: _addingWater ? null : onTap,
    child: AnimatedContainer(
      duration: motion(context, 225),
      constraints: const BoxConstraints(minHeight: 49),
      decoration: BoxDecoration(
        color: _addingWater ? const Color(0xffa39af1) : _aqua,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t('سجّل كوب', 'Log water'),
              style: const TextStyle(
                color: _waterDark,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '$amount mL',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'Manrope',
              color: _waterDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.add, color: _waterDark, size: 21),
        ],
      ),
    ),
  );

  Widget _vessel(double amount) => Semantics(
    label: t('زجاجة المياه', 'Water bottle'),
    value: number(amount) + ' mL',
    child: _Vessel(level: _waterLevel(amount), volume: amount),
  );

  Future<void> _hydrationDetails() async {
    var selected = defaultWaterCup(data);
    await _page<void>(
      (_) => StatefulBuilder(
        builder: (c, redraw) => ListenableBuilder(
          listenable: widget.db,
          builder: (c, _) {
            final amount = waterTotal(data, DateTime.now());
            final today = inPeriod(
              entriesFor(data, 'water'),
              DateTime.now(),
              1,
            );
            return Scaffold(
              appBar: AppBar(
                title: Text(t('المياه', 'Hydration')),
                actions: [
                  IconButton(
                    onPressed: _waterReminder,
                    tooltip: t('تذكيرات شرب المياه', 'Water reminders'),
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  IconButton(
                    onPressed: () =>
                        _trackerPreferences(trackerFor(data, 'water')!),
                    tooltip: t('إعدادات المتابعة', 'Tracker settings'),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(17, 8, 17, 25),
                children: [
                  _HydrationSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 9),
                        Center(
                          child: _hydrationAmount(
                            amount,
                            53,
                            unit: displayUnit(data, trackerFor(data, 'water')!),
                          ),
                        ),
                        Center(
                          child: Text(
                            t('إجمالي اليوم', 'Today’s total'),
                            style: TextStyle(
                              color: _waterAccent(c),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Center(
                          child: SizedBox(
                            width: 224,
                            height: 216,
                            child: _vessel(amount),
                          ),
                        ),
                        _cupPresets(
                          selected,
                          (ml) => redraw(() => selected = ml),
                        ),
                        const SizedBox(height: 8),
                        _VolumeRuler(
                          value: selected,
                          onChanged: (newValue) =>
                              redraw(() => selected = newValue),
                        ),
                        const SizedBox(height: 10),
                        _pourButton(selected, () async {
                          await _addWater(selected);
                          if (c.mounted) redraw(() {});
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _waterWeek(c),
                  SectionTitle(
                    t('إدخالات اليوم', 'Today’s entries'),
                    action: IconButton(
                      icon: const Icon(Icons.show_chart),
                      tooltip: t('كل الاتجاهات', 'All trends'),
                      onPressed: () => _details(trackerFor(data, 'water')!),
                    ),
                  ),
                  if (today.isEmpty)
                    EmptyPanel(
                      Icons.water_drop_outlined,
                      t('سجّل أول كوب', 'Log your first glass'),
                      '',
                    ),
                  for (final e in today)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _logTile(e),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _waterWeek(BuildContext context) {
    final today = DateTime.now();
    final tracker = trackerFor(data, 'water')!;
    final unit = displayUnit(data, tracker);
    final days = [
      for (var offset = -6; offset <= 0; offset++)
        DateTime(today.year, today.month, today.day + offset),
    ];
    final totals = [for (final day in days) waterTotal(data, day)];
    final peak = totals.fold<double>(1, math.max);
    var chosen = days.length - 1;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.bar_chart_rounded),
        title: Text(t('المياه في آخر ٧ أيام', 'Water over the last 7 days')),
        children: [
          StatefulBuilder(
            builder: (c, paint) {
              final color = Theme.of(c).colorScheme;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSwitcher(
                      duration: motion(c, 370),
                      transitionBuilder: valueMotion,
                      child: Align(
                        key: ValueKey(chosen),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${prettyDate(days[chosen], 'EEE، d MMM')} · ${number(convert('water', totals[chosen], 'mL', unit))} $unit',
                          style: TextStyle(
                            color: color.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (i, day) in days.indexed)
                          Expanded(
                            child: _ActivityDay(
                              label: prettyDate(day, 'd'),
                              description: prettyDate(day, 'EEEE، d MMMM'),
                              count: totals[i].round(),
                              peak: peak.ceil(),
                              selected: chosen == i,
                              onTap: () => paint(() => chosen = i),
                              textColor: color.onSurfaceVariant,
                              barColor: _waterAccent(c),
                              baselineColor: color.outlineVariant,
                              selectionColor: color.onSurface,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HydrationSurface extends StatelessWidget {
  const _HydrationSurface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [Color(0xff233960), _waterDark, Color(0xff253a67)]
              : const [Color(0xffe1f4fd), Color(0xffd0eafa), Color(0xfff6fdff)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _HydrationBackdrop(dark)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 9, 15, 14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _VolumeRuler extends StatefulWidget {
  const _VolumeRuler({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  State<_VolumeRuler> createState() => _VolumeRulerState();
}

class _VolumeRulerState extends State<_VolumeRuler> {
  double _drag = 0;
  int _next(int step) => (widget.value + step * 25).clamp(1, 10000);
  void _nudge(int step) {
    final next = _next(step);
    if (next == widget.value) return;
    widget.onChanged(next);
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final ar = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: tr(ar, 'حجم الكوب', 'Cup size'),
      value: widget.value.toString() + ' mL',
      increasedValue: widget.value < 10000 ? _next(1).toString() + ' mL' : null,
      decreasedValue: widget.value > 1 ? _next(-1).toString() + ' mL' : null,
      onIncrease: widget.value < 10000 ? () => _nudge(1) : null,
      onDecrease: widget.value > 1 ? () => _nudge(-1) : null,
      child: Row(
        children: [
          IconButton(
            onPressed: widget.value > 1 ? () => _nudge(-1) : null,
            tooltip: tr(ar, 'قلّل الكمية', 'Decrease amount'),
            icon: Icon(Icons.remove, color: _waterAccent(context)),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _drag = 0,
              onHorizontalDragUpdate: (d) {
                _drag += d.delta.dx * (ar ? -1 : 1);
                if (_drag.abs() > 13) {
                  _nudge(_drag < 0 ? 1 : -1);
                  _drag = 0;
                }
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.value.toDouble()),
                duration: motion(context, 180),
                curve: Curves.easeOut,
                builder: (c, n, _) => SizedBox(
                  height: 42,
                  child: CustomPaint(painter: _RulerMarks(n, _waterAccent(c))),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: widget.value < 10000 ? () => _nudge(1) : null,
            tooltip: tr(ar, 'زوّد الكمية', 'Increase amount'),
            icon: Icon(Icons.add, color: _waterAccent(context)),
          ),
        ],
      ),
    );
  }
}

class _RulerMarks extends CustomPainter {
  const _RulerMarks(this.amount, this.tone);
  final double amount;
  final Color tone;
  @override
  void paint(Canvas canvas, Size size) {
    final marker = Paint()..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final from = math.max(0, ((amount - size.width) / 25).floor());
    final until = math.min(400, ((amount + size.width) / 25).ceil());
    for (var i = from; i <= until; i++) {
      final distance = (i * 25 - amount) / 25;
      final x = size.width / 2 + distance * 13;
      if (x < 0 || x > size.width) continue;
      marker.color = Color.lerp(
        tone,
        tone.withValues(alpha: .42),
        distance.abs().clamp(0, 6) / 6,
      )!;
      marker.strokeWidth = i % 5 == 0 ? 2.2 : 1.3;
      canvas.drawLine(Offset(x, i % 5 == 0 ? 7 : 14), Offset(x, 33), marker);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: size.center(Offset.zero), width: 4, height: 40),
        const Radius.circular(2),
      ),
      Paint()..color = tone,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RulerMarks oldDelegate) =>
      oldDelegate.amount != amount || oldDelegate.tone != tone;
}

class _Vessel extends StatefulWidget {
  const _Vessel({required this.level, required this.volume});
  final double level, volume;
  @override
  State<_Vessel> createState() => _VesselState();
}

class _VesselState extends State<_Vessel> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1360),
    value: 1,
  );
  late double _start = widget.level;
  double _cup = 0;
  double _position(double target) =>
      _start +
      (target - _start) *
          const Interval(.09, .84, curve: motionArrival).transform(_flow.value);
  @override
  void didUpdateWidget(_Vessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volume == widget.volume) return;
    _start = _position(oldWidget.level);
    _cup = widget.volume - oldWidget.volume;
    if (MediaQuery.disableAnimationsOf(context)) {
      _flow.value = 1;
    } else {
      _flow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _flow,
      builder: (c, _) => CustomPaint(
        painter: _VesselPainter(
          _position(widget.level),
          _flow.value,
          _cup,
          _waterAccent(c),
        ),
      ),
    ),
  );
}

class _HydrationBackdrop extends CustomPainter {
  const _HydrationBackdrop(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .25, size.height * .52);
    final radius = size.shortestSide * .65;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: dark
              ? const [Color(0xff4669b7), Color(0x00282365)]
              : const [Color(0xffb8ddf6), Color(0x00b8ddf6)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      p.color = (dark ? Colors.white : const Color(0xff315d92)).withValues(
        alpha: .14 - i * .027,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * (1 + i * .25),
          height: radius * (.48 + i * .15),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_HydrationBackdrop oldDelegate) =>
      oldDelegate.dark != dark;
}

class _VesselPainter extends CustomPainter {
  const _VesselPainter(this.level, this.phase, this.delta, this.accent);
  final double level, phase, delta;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final u = math.min(size.width / 120, size.height / 156);
    canvas.translate((size.width - 120 * u) / 2, (size.height - 156 * u) / 2);
    canvas.scale(u);
    final strength = (delta.abs() / 165).clamp(.0, 1.35);
    final impulse =
        math.sin(phase * math.pi * 5) *
        (1 - phase) *
        strength *
        (delta < 0 ? -7 : 7);
    final pouring = delta > 0 && phase < 1;
    final airborne = pouring
        ? math.sin(math.pi * const Interval(.0, .81).transform(phase))
        : 0.0;
    if (phase < 1) {
      final echo = const Interval(.14, .98).transform(phase);
      for (var i = 0; i < 2; i++) {
        final ring = (echo * 1.22 - i * .22).clamp(0, 1);
        if (ring == 0 || ring >= 1) continue;
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(60, 141),
            width: 51 + ring * 111,
            height: 8 + ring * 30,
          ),
          Paint()
            ..color = accent.withValues(alpha: (1 - ring) * .46)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
      }
    }
    canvas.drawOval(
      const Rect.fromLTWH(19, 137, 83, 12),
      Paint()..color = const Color(0x66141032),
    );
    if (pouring && phase > .08 && phase < .73) {
      final release = (phase - .08) / .65;
      final stream = Path()
        ..moveTo(125, 0)
        ..cubicTo(94, -2, 70 + math.sin(phase * 12) * 3, 8, 60, 30);
      final track = stream.computeMetrics().first;
      final tip = motionArrival.transform((release * 2.5).clamp(0, 1));
      final tail = ((release - .56) / .44).clamp(0, 1);
      final arc = track.extractPath(track.length * tail, track.length * tip);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = accent.withValues(alpha: .48);
      canvas.drawPath(arc, paint);
      canvas.drawPath(
        arc,
        paint
          ..strokeWidth = 2.3
          ..color = _aqua,
      );
      for (var i = 1; i <= 5; i++) {
        final step = ((release * 1.55) - i * .10).clamp(0, 1);
        if (step == 0 || step >= 1) continue;
        final point = track.getTangentForOffset(track.length * step)!.position;
        canvas.drawCircle(
          point.translate(math.sin(i * 1.8) * 9, 4 - i * 1.1),
          1.9,
          Paint()..color = accent.withValues(alpha: (.8 - step * .52)),
        );
      }
    }
    canvas.save();
    canvas.translate(60 - airborne * 2.5, 82 - airborne * 3.8);
    canvas.rotate(impulse * .02);
    canvas.translate(-60, -82);
    final glass = Path()
      ..moveTo(49, 20)
      ..lineTo(71, 20)
      ..lineTo(71, 35)
      ..cubicTo(74, 47, 94, 47, 94, 64)
      ..lineTo(94, 125)
      ..quadraticBezierTo(94, 143, 76, 143)
      ..lineTo(43, 143)
      ..quadraticBezierTo(26, 143, 26, 125)
      ..lineTo(26, 64)
      ..cubicTo(26, 47, 46, 46, 49, 35)
      ..close();
    const bounds = Rect.fromLTWH(26, 20, 68, 123);
    canvas.drawPath(
      glass,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xaaab9cfb),
            Color(0x26594cb6),
            Color(0x3545399f),
            Color(0xaaa99cff),
          ],
          stops: [0, .19, .76, 1],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipPath(glass);
    if (level > .004) {
      final top = 142 - level.clamp(0.0, 1.0) * 102;
      final wave = Path()
        ..moveTo(22, top + impulse)
        ..cubicTo(
          44,
          top - 10 - impulse * 2,
          74,
          top + 8 + impulse * 2,
          100,
          top - impulse,
        );
      final fill = Path.from(wave)
        ..lineTo(100, 146)
        ..lineTo(22, 146)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xffbcfff9),
              Color(0xff5bbbdc),
              Color(0xff6464e9),
              Color(0xff4d38ba),
            ],
            stops: [0, .24, .67, 1],
          ).createShader(Rect.fromLTRB(22, top, 97, 147)),
      );
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _aqua,
      );
      for (var i = 0; i < 9; i++) {
        final x = 35 + (i * 23 % 49).toDouble() + math.sin(i + phase * 4) * 2;
        final y = top + (141 - top) * ((i * .271 + phase * .58) % .99);
        if (141 - top > 12)
          canvas.drawCircle(
            Offset(x, y),
            1.0 + (i % 3) * .4,
            Paint()..color = _aqua.withValues(alpha: .20 + (1 - phase) * .43),
          );
      }
    }
    const highlight = Rect.fromLTWH(30, 53, 8, 75);
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlight, const Radius.circular(5)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x009bd7ff), Color(0xbce5efff), Color(0x00f6fffd)],
        ).createShader(highlight),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(85, 60, 4, 64),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white24,
    );
    canvas.restore();
    canvas.drawPath(
      glass,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffdcd8ff), Color(0x709c95e3), Color(0xffbab1f8)],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45,
    );
    canvas.save();
    canvas.translate(-15 * airborne, -13 * airborne);
    canvas.rotate(-.035 * airborne);
    const cap = Rect.fromLTWH(42, 9, 36, 17);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cap, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffc0b4fd), Color(0xff6954c4), Color(0xff3b287f)],
        ).createShader(cap),
    );
    canvas.drawLine(
      const Offset(46, 11),
      const Offset(74, 11),
      Paint()
        ..strokeWidth = 1.2
        ..color = const Color(0xffd8ccff),
    );
    for (var i = 0; i < 6; i++) {
      final x = 47 + i * 5.2;
      canvas.drawLine(
        Offset(x, 15),
        Offset(x, 22),
        Paint()
          ..strokeWidth = .8
          ..color = const Color(0x77d2c8fd),
      );
    }
    canvas.restore();
    canvas.restore();
    if (phase < 1 && phase > .08) {
      final show =
          const Interval(.08, .27, curve: motionArrival).transform(phase) *
          (1 - const Interval(.70, 1).transform(phase));
      final sign = delta > 0 ? '+' : '−';
      final label = TextPainter(
        text: TextSpan(
          text: '$sign${number(delta.abs())} mL',
          style: const TextStyle(
            color: _waterDark,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            fontFamily: 'Manrope',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bubble = Rect.fromLTWH(
        88 - label.width * .18,
        64 - phase * 41,
        label.width + 12,
        21,
      );
      final shape = RRect.fromRectAndRadius(bubble, const Radius.circular(10));
      canvas.saveLayer(
        bubble.inflate(3),
        Paint()..color = Colors.white.withValues(alpha: show),
      );
      canvas.drawRRect(shape, Paint()..color = _aqua);
      canvas.drawRRect(
        shape,
        Paint()
          ..color = accent.withValues(alpha: .65)
          ..style = PaintingStyle.stroke,
      );
      label.paint(
        canvas,
        Offset(bubble.left + 6, bubble.center.dy - label.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_VesselPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.phase != phase ||
      oldDelegate.delta != delta ||
      oldDelegate.accent != accent;
}
