part of 'design.dart';

const motionArrival = Cubic(.16, .86, .25, 1);

class SpringTouch extends StatefulWidget {
  const SpringTouch({
    super.key,
    required this.child,
    this.enabled = true,
    this.emphasis = 1,
    this.accent,
  });

  final Widget child;
  final bool enabled;
  final double emphasis;
  final Color? accent;

  @override
  State<SpringTouch> createState() => _SpringTouchState();
}

class _SpringTouchState extends State<SpringTouch>
    with TickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );
  int? _pointer;
  Offset _origin = Offset.zero;

  void _release({required bool confirm}) {
    if (_pointer == null) return;
    _pointer = null;
    _press.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 530, damping: 25),
        _press.value,
        0,
        0,
      ),
    );
    if (confirm) _wave.forward(from: 0);
  }

  @override
  void dispose() {
    _press.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) || !widget.enabled) {
      return widget.child;
    }
    return Listener(
      onPointerDown: (event) {
        if (_pointer != null || event.buttons != 1) return;
        _pointer = event.pointer;
        _origin = event.localPosition;
        _wave.value = 1;
        _press.animateTo(
          1,
          duration: const Duration(milliseconds: 85),
          curve: Curves.easeOut,
        );
      },
      onPointerMove: (event) {
        if (_pointer == event.pointer &&
            (event.localPosition - _origin).distance > 15) {
          _release(confirm: false);
        }
      },
      onPointerUp: (event) {
        if (_pointer == event.pointer) _release(confirm: true);
      },
      onPointerCancel: (event) {
        if (_pointer == event.pointer) _release(confirm: false);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _wave]),
        child: widget.child,
        builder: (c, child) {
          final force = _press.value * widget.emphasis;
          final pulse = _wave.value;
          return Transform.scale(
            alignment: Alignment.center,
            scale: 1 - force * .044,
            child: Transform.translate(
              offset: Offset(0, force * 2.7),
              child: CustomPaint(
                foregroundPainter: pulse >= 1
                    ? null
                    : _TouchEcho(
                        _origin,
                        pulse,
                        widget.accent ?? Theme.of(c).colorScheme.primary,
                      ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TouchEcho extends CustomPainter {
  const _TouchEcho(this.origin, this.phase, this.color);
  final Offset origin;
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
    );
    final reach = math.max(origin.dx, size.width - origin.dx);
    final radius = 9 + reach * .76 * motionArrival.transform(phase);
    final light = 1 - phase;
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .18 * light),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: origin, radius: radius)),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..color = color.withValues(alpha: .38 * light)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * light,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TouchEcho old) =>
      old.origin != origin || old.phase != phase || old.color != color;
}

class DirectionFlow extends StatefulWidget {
  const DirectionFlow({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<DirectionFlow> createState() => _DirectionFlowState();
}

class _DirectionFlowState extends State<DirectionFlow> {
  double _direction = 1;

  @override
  void didUpdateWidget(DirectionFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return KeyedSubtree(key: ValueKey(widget.index), child: widget.child);
    }
    final mirror = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 565),
        reverseDuration: const Duration(milliseconds: 435),
        layoutBuilder: (current, earlier) => Stack(
          fit: StackFit.expand,
          children: [
            for (final old in earlier)
              IgnorePointer(
                child: ExcludeSemantics(
                  child: HeroMode(enabled: false, child: old),
                ),
              ),
            ?current,
          ],
        ),
        transitionBuilder: (child, animation) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (_, child) {
            final current = child!.key == ValueKey(widget.index);
            final phase = current
                ? 1 - motionArrival.transform(animation.value)
                : motionArrival.transform(1 - animation.value);
            final position =
                (current ? .17 : -.081) * phase * _direction * mirror;
            return FractionalTranslation(
              translation: Offset(
                position,
                current ? phase * .036 : -phase * .02,
              ),
              child: Transform.scale(
                scale: 1 - phase * (current ? .032 : .059),
                child: Opacity(
                  opacity: (1 - phase * (current ? .38 : .62)).clamp(0, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(phase * 26),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(phase * 26),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
      ),
    );
  }
}

class PageLift extends StatelessWidget {
  const PageLift({
    super.key,
    required this.animation,
    required this.behind,
    required this.child,
  });

  final Animation<double> animation, behind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, behind]),
      child: child,
      builder: (c, child) {
        final entering = 1 - motionArrival.transform(animation.value);
        final recede = motionArrival.transform(behind.value);
        final radius = entering * 32 + recede * 19;
        return FractionalTranslation(
          translation: Offset(
            (entering * .24 - recede * .043) * (rtl ? -1 : 1),
            entering * .055,
          ),
          child: Transform.scale(
            alignment: AlignmentDirectional.bottomEnd.resolve(
              Directionality.of(c),
            ),
            scale: 1 - entering * .085 - recede * .055,
            child: Opacity(
              opacity: 1 - entering * .44 - recede * .08,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .18 * entering),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class JournalPageTransitions extends PageTransitionsBuilder {
  const JournalPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => PageLift(animation: animation, behind: secondaryAnimation, child: child);
}

class SheetLift extends StatelessWidget {
  const SheetLift({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final lift =
            1 -
            const Interval(
              .12,
              .94,
              curve: Cubic(.24, .73, .25, 1),
            ).transform(animation.value);
        return Transform.translate(
          offset: Offset(0, 48 * lift),
          child: Transform.scale(
            alignment: Alignment.bottomCenter,
            scale: 1 - lift * .075,
            child: Opacity(opacity: 1 - lift * .62, child: child),
          ),
        );
      },
    );
  }
}

class SaveSeal extends StatelessWidget {
  const SaveSeal({super.key, this.color = mint, this.size = 34});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, 840),
      builder: (_, progress, _) => CustomPaint(
        painter: _SealPainter(progress, color),
        size: Size.square(size),
      ),
    ),
  );
}

class _SealPainter extends CustomPainter {
  const _SealPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 40;
    canvas.scale(u);
    const center = Offset(20, 20);
    final reveal = motionArrival.transform((progress / .62).clamp(0, 1));
    final tick = motionArrival.transform(((progress - .25) / .53).clamp(0, 1));
    final burst = ((progress - .32) / .68).clamp(0.0, 1.0);
    canvas.drawCircle(center, 14 * reveal, Paint()..color = color);
    final brush = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.7;
    final check = Path()
      ..moveTo(13, 20)
      ..lineTo(18, 25)
      ..lineTo(27, 15);
    final track = check.computeMetrics().first;
    canvas.drawPath(track.extractPath(0, track.length * tick), brush);
    if (burst > 0 && burst < 1) {
      final length = 16 + burst * 6;
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3 + .2;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * length,
          center + direction * (length + 3 * (1 - burst)),
          brush
            ..color = color.withValues(alpha: 1 - burst)
            ..strokeWidth = 1.8,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.progress != progress || old.color != color;
}

Widget valueMotion(Widget child, Animation<double> progress) => FadeTransition(
  opacity: progress.drive(CurveTween(curve: Curves.easeOut)),
  child: SlideTransition(
    position: Tween(
      begin: const Offset(0, .5),
      end: Offset.zero,
    ).chain(CurveTween(curve: motionArrival)).animate(progress),
    child: child,
  ),
);

class JournalButton extends StatelessWidget {
  const JournalButton({
    super.key,
    required this.onPressed,
    required Widget child,
    this.style,
  }) : label = child,
       icon = null;

  const JournalButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) => SpringTouch(
    enabled: onPressed != null,
    emphasis: 1.35,
    accent: Theme.of(context).colorScheme.onPrimary,
    child: icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: label)
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon!,
            label: label,
          ),
  );
}

class UpdateFlash extends StatefulWidget {
  const UpdateFlash({
    super.key,
    required this.value,
    required this.color,
    required this.child,
  });

  final Object? value;
  final Color color;
  final Widget child;

  @override
  State<UpdateFlash> createState() => _UpdateFlashState();
}

class _UpdateFlashState extends State<UpdateFlash>
    with SingleTickerProviderStateMixin {
  late final _light = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );

  @override
  void didUpdateWidget(UpdateFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !MediaQuery.disableAnimationsOf(context)) {
      _light.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _UpdateLight(
      _light,
      widget.color,
      Directionality.of(context) == TextDirection.rtl,
    ),
    child: widget.child,
  );
}

class _UpdateLight extends CustomPainter {
  _UpdateLight(this.phase, this.color, this.rtl) : super(repaint: phase);
  final Animation<double> phase;
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    if (t >= 1) return;
    final track = motionArrival.transform(t);
    final x = size.width * (rtl ? 1.25 - track * 1.5 : track * 1.5 - .25);
    final width = size.width * .64;
    final area = Rect.fromLTWH(x - width / 2, 0, width, size.height);
    final alpha = math.sin(t * math.pi) * .23;
    final clear = color.withValues(alpha: 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            clear,
            color.withValues(alpha: alpha),
            clear,
          ],
        ).createShader(area),
    );
  }

  @override
  bool shouldRepaint(_UpdateLight old) =>
      old.color != color || old.rtl != rtl || old.phase != phase;
}
