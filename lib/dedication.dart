part of 'main.dart';

const _dedicatedEngineer = 'عبدالنبي عبدالفتاح';
const _dedicatedTeacher = 'فاطمه بدير عسل';
const _dedicationNames =
    'المهندس $_dedicatedEngineer\nوالأستاذة $_dedicatedTeacher';
const _dedicationPrayer = 'الرجاء الدعاء لهما بالمغفرة والرحمة';
const _developerCredit = 'برمجة وتصميم المهندس محمد عبدالنبي';
const _facebookProfile = String.fromEnvironment(
  'YAWMI_FACEBOOK_URL',
  defaultValue: 'https://fb.com/mr.ropot',
);

class _StartupDedication extends StatefulWidget {
  const _StartupDedication({required this.child});
  final Widget child;

  @override
  State<_StartupDedication> createState() => _StartupDedicationState();
}

class _StartupDedicationState extends State<_StartupDedication>
    with TickerProviderStateMixin {
  static const _visibleTime = Duration(seconds: 3);
  static const _exitTime = Duration(milliseconds: 220);

  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );
  late final _leave = AnimationController(vsync: this, duration: _exitTime);
  Timer? _display, _autoExit;
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_closed || _leave.isAnimating) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _entrance.value = 1;
    } else if (_entrance.isDismissed) {
      _entrance.forward();
    }
    if (MediaQuery.accessibleNavigationOf(context)) {
      _display?.cancel();
      _autoExit?.cancel();
      _display = null;
      _autoExit = null;
    } else {
      _display ??= Timer(_visibleTime, _close);
      if (!reduceMotion) {
        _autoExit ??= Timer(_visibleTime - _exitTime, _animateExit);
      }
    }
  }

  void _dismiss() {
    if (_closed) return;
    _display?.cancel();
    _autoExit?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _close();
    } else {
      _animateExit();
    }
  }

  void _animateExit() {
    if (_closed || _leave.isAnimating) return;
    unawaited(_leave.forward().whenComplete(_close));
  }

  void _close() {
    if (!mounted || _closed) return;
    _display?.cancel();
    _autoExit?.cancel();
    setState(() => _closed = true);
  }

  @override
  void dispose() {
    _display?.cancel();
    _autoExit?.cancel();
    _entrance.dispose();
    _leave.dispose();
    super.dispose();
  }

  Widget _reveal(
    double start,
    double end,
    Widget child, {
    double travel = 10,
    double fromScale = 1,
  }) => AnimatedBuilder(
    animation: _entrance,
    child: child,
    builder: (_, child) {
      final t = Interval(
        start,
        end,
        curve: motionArrival,
      ).transform(_entrance.value);
      return Transform.translate(
        offset: Offset(0, (1 - t) * travel),
        child: Transform.scale(
          scale: fromScale + (1 - fromScale) * t,
          child: Opacity(opacity: t, child: child),
        ),
      );
    },
  );

  Widget _tribute(bool compact) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 344),
    child: Column(
      children: [
        _reveal(
          0,
          .47,
          _IdentityMark(size: compact ? 52 : 62),
          travel: 15,
          fromScale: .82,
        ),
        SizedBox(height: compact ? 12 : 17),
        _reveal(
          .08,
          .54,
          Text(
            'صدقة جارية',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Tajawal',
              color: const Color(0xffffe0a6),
              fontSize: compact ? 27 : 32,
              height: 1.12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 7),
        _reveal(
          .15,
          .60,
          const Text(
            'على روح المغفور لهما بإذن الله',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xffc5d6c9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        SizedBox(height: compact ? 15 : 25),
        Stack(
          children: [
            Positioned.fill(
              child: _reveal(
                .16,
                .82,
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0x342e674c), Color(0x44213c32)],
                    ),
                    border: Border.all(color: const Color(0x73a0a779)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(33),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(33),
                    ),
                  ),
                ),
                travel: 3,
                fromScale: .97,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: compact ? 12 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _reveal(
                    .24,
                    .73,
                    const _DedicationName(
                      title: 'المهندس',
                      name: _dedicatedEngineer,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _entrance,
                    builder: (_, _) {
                      final width = const Interval(
                        .38,
                        .79,
                        curve: Curves.easeOutCubic,
                      ).transform(_entrance.value);
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 9 : 12,
                        ),
                        child: Center(
                          child: Container(
                            width: 81 * width,
                            height: 1,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x0dfad994),
                                  Color(0xb3fad994),
                                  Color(0x0dfad994),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _reveal(
                    .35,
                    .84,
                    const _DedicationName(
                      title: 'الأستاذة',
                      name: _dedicatedTeacher,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 16 : 24),
        _reveal(
          .48,
          .96,
          const Text(
            _dedicationPrayer,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xffffe0a6),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        ignoring: !_closed,
        child: ExcludeSemantics(
          excluding: !_closed,
          child: TickerMode(enabled: _closed, child: widget.child),
        ),
      ),
      if (!_closed)
        AnimatedBuilder(
          animation: _leave,
          builder: (_, child) {
            final exit = motionArrival.transform(_leave.value);
            return ClipRect(
              child: Transform.scale(
                scale: 1 + .07 * exit,
                child: Opacity(opacity: 1 - exit, child: child),
              ),
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _dismiss,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Material(
                  color: night,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(painter: _DedicationSky(_entrance)),
                      ),
                      SafeArea(
                        child: LayoutBuilder(
                          builder: (_, bounds) {
                            final compact = bounds.maxHeight < 610;
                            return SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                23,
                                compact ? 12 : 19,
                                23,
                                10,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: math.max(
                                    0,
                                    bounds.maxHeight - (compact ? 22 : 29),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const SizedBox.shrink(),
                                    _tribute(compact),
                                    _reveal(
                                      .58,
                                      1,
                                      Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Column(
                                          children: [
                                            const Text(
                                              _developerCredit,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0xffbccdc0),
                                                fontSize: 12,
                                                height: 1.6,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _dismiss,
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xffe8eadc,
                                                ),
                                                textStyle: const TextStyle(
                                                  fontFamily: fontUi,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              child: Text(
                                                tr(
                                                  Localizations.localeOf(
                                                        context,
                                                      ).languageCode ==
                                                      'ar',
                                                  'اضغط في أي مكان للمتابعة',
                                                  'Tap anywhere to continue',
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _DedicationName extends StatelessWidget {
  const _DedicationName({required this.title, required this.name});
  final String title, name;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title $name',
    excludeSemantics: true,
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xffd2ba80),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            color: Color(0xfffffcf2),
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.18,
          ),
        ),
      ],
    ),
  );
}

class _DedicationSky extends CustomPainter {
  _DedicationSky(this.phase) : super(repaint: phase);
  final Animation<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(phase.value);
    final focus = Offset(size.width * .5, size.height * .29);
    final span = size.shortestSide * .92;
    final screen = Offset.zero & size;
    canvas.drawRect(
      screen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff0e211b), Color(0xff17352b), Color(0xff0e231d)],
        ).createShader(screen),
    );
    canvas.drawRect(
      screen,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xff477b5d).withValues(alpha: .48 * t),
            const Color(0x043a664f),
            Colors.transparent,
          ],
          stops: const [0, .73, 1],
        ).createShader(Rect.fromCircle(center: focus, radius: span * .74)),
    );
    canvas.save();
    canvas.translate(focus.dx, focus.dy);
    canvas.rotate(-.33 + .18 * (1 - t));
    for (var i = 0; i < 3; i++) {
      final radius = span * (.28 + .13 * i) * (.84 + t * .16);
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.3,
        height: radius * 1.18,
      );
      final stroke = Paint()
        ..color = const Color(
          0xffd6d49e,
        ).withValues(alpha: (.19 - .038 * i) * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(oval, -.7 + i * .34, 5.5 * t, false, stroke);
    }
    canvas.restore();
    for (var i = 0; i < 9; i++) {
      final x = (i * .219 + .075) % 1;
      final y = (i * .157 + .11) % .86;
      canvas.drawCircle(
        Offset(size.width * x, size.height * y + 18 * (1 - t)),
        i % 4 == 0 ? 2 : 1,
        Paint()..color = const Color(0xffffdfa4).withValues(alpha: t * .42),
      );
    }
  }

  @override
  bool shouldRepaint(_DedicationSky old) => old.phase != phase;
}

class _IdentityMark extends StatelessWidget {
  const _IdentityMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _IdentityPainter());
}

class _IdentityPainter extends CustomPainter {
  const _IdentityPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 108);
    final bounds = RRect.fromRectAndRadius(
      const Rect.fromLTWH(5, 5, 98, 98),
      const Radius.circular(28),
    );
    canvas.drawRRect(bounds, Paint()..color = const Color(0xff214c3c));
    canvas.drawRRect(
      bounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xff76a88e),
    );
    final left = Path()
      ..moveTo(29, 40)
      ..quadraticBezierTo(43, 35, 52, 44)
      ..lineTo(52, 72)
      ..quadraticBezierTo(43, 62, 29, 68)
      ..close();
    final right = Path()
      ..moveTo(56, 44)
      ..quadraticBezierTo(66, 35, 79, 40)
      ..lineTo(79, 68)
      ..quadraticBezierTo(66, 62, 56, 72)
      ..close();
    canvas.drawPath(left, Paint()..color = paper);
    canvas.drawPath(right, Paint()..color = const Color(0xffd7ece0));
    final rule = Paint()
      ..color = evergreen
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(35, 49), const Offset(45, 49), rule);
    canvas.drawLine(const Offset(35, 56), const Offset(44, 56), rule);
    canvas.drawCircle(const Offset(73, 29), 5, Paint()..color = leaf);
  }

  @override
  bool shouldRepaint(_IdentityPainter old) => false;
}

extension _AboutPage on _HomeState {
  Future<void> _about() => _page<void>(
    (c) => Scaffold(
      appBar: AppBar(title: Text(t('عن التطبيق', 'About Yawmi'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          Enter(
            child: JournalCover(
              title: t('يومي', 'Yawmi'),
              subtitle: t(
                'دفتر صحي شخصي يضم قياساتك وأدويتك وروتينك في مكان واحد. اختار اللي تتابعه، ورتّب بطاقاتك حسب يومك، واحتفظ بسجلك على جهازك.',
                'A personal health journal for your readings, medication and routines. Choose what to track, arrange your cards, and keep your journal on your device.',
              ),
              trailing: const _IdentityMark(size: 72),
            ),
          ),
          const SizedBox(height: 14),
          Enter(
            delay: 65,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('إهداء', 'Dedication'),
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        'صدقة جارية على روح المغفور لهما بإذن الله\n'
                        '$_dedicationNames\n\n$_dedicationPrayer',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Enter(
            delay: 130,
            child: Text(
              t(
                _developerCredit,
                'Programming and design by Eng. Mohamed Abdelnaby',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(
                c,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (_facebookProfile.isNotEmpty) ...[
            const SizedBox(height: 8),
            ControlCard(
              title: t('فيسبوك', 'Facebook'),
              subtitle: _facebookProfile.replaceFirst('https://', ''),
              icon: Icons.facebook_rounded,
              trailing: const Icon(Icons.open_in_new_rounded, size: 19),
              onTap: () async {
                try {
                  await platform.invokeMethod<void>(
                    'openFacebook',
                    _facebookProfile,
                  );
                } catch (_) {
                  if (c.mounted) {
                    _toast(t('تعذّر فتح الرابط', 'Could not open the link'));
                  }
                }
              },
            ),
          ],
        ],
      ),
    ),
  );
}
