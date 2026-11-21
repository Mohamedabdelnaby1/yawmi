import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'domain.dart';
part 'motion.dart';

const plum = Color(0xff58628b);
const ink = Color(0xff172c25);
const cream = Color(0xfff5f3ea);
const lavender = Color(0xffddd9ed);
const mint = Color(0xffd7ece0);
const rose = Color(0xfff9ded0);
const honey = Color(0xfff2daa1);
const night = Color(0xff122c24);
const ice = Color(0xffd4eaf0);
const paper = Color(0xfffffdf5);
const evergreen = Color(0xff215b47);
const leaf = Color(0xffddf19b);
const brightBlue = Color(0xffbbdded);
const fontUi = 'PlexArabic';

ThemeData yawmiTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: evergreen,
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xff172c26) : paper,
        surfaceContainerLow: dark ? const Color(0xff172c26) : paper,
        surfaceContainer: dark
            ? const Color(0xff223c32)
            : const Color(0xffeceee1),
        surfaceContainerHigh: dark
            ? const Color(0xff2b473a)
            : const Color(0xffe2e9da),
        onSurface: dark ? const Color(0xfff4f5e8) : ink,
        primary: dark ? leaf : evergreen,
        onPrimary: dark ? ink : paper,
        primaryContainer: dark ? leaf : const Color(0xffdcedcb),
        onPrimaryContainer: ink,
        secondary: dark ? mint : evergreen,
        onSurfaceVariant: dark
            ? const Color(0xffbbcec2)
            : const Color(0xff465e52),
        outlineVariant: dark
            ? const Color(0xff406052)
            : const Color(0xffced9cc),
        secondaryContainer: dark
            ? const Color(0xff2c493c)
            : const Color(0xffe4eddf),
        onSecondaryContainer: dark ? paper : ink,
      );
  return ThemeData(
    brightness: brightness,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: JournalPageTransitions()},
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xff101f1b) : cream,
    fontFamily: fontUi,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 15, 16, 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 51),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(
          fontFamily: fontUi,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      hoverElevation: 0,
      focusElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: .14),
      height: 72,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: fontUi,
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      titleTextStyle: TextStyle(
        fontFamily: fontUi,
        fontSize: 23,
        color: scheme.onSurface,
        fontWeight: FontWeight.bold,
        height: 1.2,
      ),
      contentTextStyle: TextStyle(
        fontFamily: fontUi,
        fontSize: 16,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    chipTheme: ChipThemeData(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: night,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: fontUi,
        fontSize: 16,
      ),
      actionTextColor: mint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

IconData glyph(String id) => switch (id) {
  'medicine' => Icons.medication_outlined,
  'pressure' => Icons.monitor_heart_outlined,
  'glucose' => Icons.opacity_rounded,
  'water' => Icons.water_drop_outlined,
  'sleep' => Icons.dark_mode_outlined,
  'temperature' => Icons.thermostat,
  'oxygen' => Icons.air,
  'weight' => Icons.scale_outlined,
  'pulse' => Icons.favorite_border,
  'symptom' => Icons.healing_outlined,
  'note' => Icons.notes,
  'pain' => Icons.flash_on_outlined,
  'peak_flow' => Icons.air_outlined,
  'activity' => Icons.directions_walk_outlined,
  'a1c' => Icons.science_outlined,
  'meal' => Icons.restaurant_outlined,
  'mood' => Icons.sentiment_satisfied_outlined,
  'cycle' => Icons.loop_rounded,
  'visit' => Icons.event_outlined,
  'lab' => Icons.biotech_outlined,
  'question' => Icons.chat_bubble_outline_rounded,
  'refill' => Icons.medical_services_outlined,
  _ => Icons.add_chart_outlined,
};

Color tint(String id) => switch (id) {
  'pressure' || 'pulse' || 'pain' || 'symptom' => rose,
  'glucose' || 'temperature' || 'meal' => honey,
  'water' || 'oxygen' || 'peak_flow' => ice,
  'activity' || 'medicine' || 'visit' => mint,
  _ => lavender,
};

class Mark extends StatelessWidget {
  const Mark({super.key, this.size = 44, this.variant = 0});
  final double size;
  final int variant;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: variant == 1 ? ice : mint,
      borderRadius: BorderRadius.circular(size * .29),
    ),
    child: CustomPaint(painter: _MarkPainter(variant)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.variant);
  final int variant;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final p = Paint()
      ..color = ink
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (variant == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(11, 13, 26, 25),
          const Radius.circular(6),
        ),
        p,
      );
      canvas.drawLine(const Offset(17, 10), const Offset(17, 17), p);
      canvas.drawLine(const Offset(31, 10), const Offset(31, 17), p);
      canvas.drawPath(
        Path()
          ..moveTo(18, 27)
          ..lineTo(22, 31)
          ..lineTo(30, 23),
        p,
      );
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(8, 29)
        ..cubicTo(11, 16, 20, 16, 25, 24)
        ..cubicTo(29, 30, 36, 31, 40, 23)
        ..cubicTo(36, 34, 28, 37, 22, 28)
        ..cubicTo(17, 20, 12, 23, 8, 29)
        ..close(),
      p..strokeWidth = 2.4,
    );
    canvas.drawCircle(
      const Offset(32, 14),
      3.0,
      Paint()..color = const Color(0xffab5a2d),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.variant != variant;
}

class DayDial extends CustomPainter {
  const DayDial(this.progress, this.accent, this.track);
  final double progress;
  final Color accent, track;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 9;
    final ring = Rect.fromCircle(center: center, radius: radius - 6);
    final shadow = ring.shift(const Offset(0, 4));
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      shadow,
      -math.pi / 2,
      2 * math.pi,
      false,
      brush..color = track.withValues(alpha: .25),
    );
    canvas.drawArc(
      ring,
      -math.pi / 2,
      2 * math.pi,
      false,
      brush..color = track.withValues(alpha: .55),
    );
    if (progress > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, .997),
        false,
        brush..color = accent,
      );
    }
    final tick = Paint()
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12 - math.pi / 2;
      final unit = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + unit * (radius + 2),
        center + unit * (radius + (i % 6 == 0 ? 6 : 4)),
        tick..color = progress > 0 && i / 24 <= progress ? accent : track,
      );
    }
  }

  @override
  bool shouldRepaint(DayDial oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track;
}

class Pressable extends StatelessWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
    this.radius = 26,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final double radius;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    child: SpringTouch(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          splashColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: .13),
          onTap: onTap,
          child: child,
        ),
      ),
    ),
  );
}

class Dock extends StatelessWidget {
  const Dock(
    this.items,
    this.index,
    this.onSelect, {
    super.key,
    this.onAdd,
    this.addLabel,
  });
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;
  final String? addLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 5, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? colors.surfaceContainer : colors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: LayoutBuilder(
            builder: (context, bounds) {
              const addWidth = 54.0;
              final slotWidth =
                  (bounds.maxWidth - (onAdd == null ? 0 : addWidth)) /
                  items.length;
              final pillWidth = math.min(55.0, slotWidth - 4);
              final center =
                  (index + .5) * slotWidth +
                  (onAdd != null && index >= items.length ~/ 2 ? addWidth : 0);
              return Stack(
                children: [
                  AnimatedPositionedDirectional(
                    duration: motion(context, 405),
                    curve: Curves.easeOutBack,
                    start: center - pillWidth / 2,
                    top: 4,
                    width: pillWidth,
                    height: 31,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: .14),
                            blurRadius: 9,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final (i, (icon, label)) in items.indexed) ...[
                        if (i == items.length ~/ 2 && onAdd != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: SpringTouch(
                              emphasis: 1.4,
                              child: SizedBox.square(
                                dimension: 48,
                                child: IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: leaf,
                                    foregroundColor: ink,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: onAdd,
                                  tooltip: addLabel,
                                  icon: const Icon(Icons.add_rounded, size: 26),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Semantics(
                            selected: i == index,
                            child: Pressable(
                              onTap: () => onSelect(i),
                              label: label,
                              radius: 15,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 27,
                                      child: AnimatedScale(
                                        scale: i == index ? 1.12 : 1,
                                        duration: motion(context, 390),
                                        curve: Curves.easeOutBack,
                                        child: TweenAnimationBuilder<Color?>(
                                          tween: ColorTween(
                                            end: i == index
                                                ? colors.onPrimaryContainer
                                                : colors.onSurfaceVariant,
                                          ),
                                          duration: motion(context, 260),
                                          builder: (_, color, _) => Icon(
                                            icon,
                                            size: 21,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: i == index
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                        fontWeight: i == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.background,
    this.foreground,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color? background, foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: ShapeDecoration(
      color: background ?? Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    child: Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        Positioned.fill(
          child: AnimatedAlign(
            duration: motion(context, 290),
            curve: Curves.easeOutBack,
            alignment: AlignmentDirectional(
              index * 2.0 / (labels.length - 1) - 1,
              0,
            ),
            child: FractionallySizedBox(
              widthFactor: 1 / labels.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: StadiumBorder(),
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            for (final (i, label) in labels.indexed)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  child: Pressable(
                    radius: 20,
                    onTap: () => onChanged(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 3,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == index
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : foreground ??
                                    Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

Duration motion(BuildContext context, [int ms = 260]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

class ControlCard extends StatelessWidget {
  const ControlCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.tonalColor = lavender,
    this.selected,
    this.trailing,
    this.emphasized = false,
    this.toned = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color tonalColor;
  final bool? selected;
  final bool emphasized;
  final bool toned;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = selected == true;
    final accent = emphasized ? mint : tonalColor;
    final background = emphasized
        ? night
        : active
        ? colors.secondaryContainer
        : toned
        ? Color.lerp(
            colors.surface,
            tonalColor,
            Theme.of(context).brightness == Brightness.dark ? .15 : .64,
          )!
        : colors.surface;
    final foreground = emphasized ? paper : colors.onSurface;
    final muted = emphasized ? lavender : colors.onSurfaceVariant;
    final outline = emphasized
        ? night
        : active
        ? colors.secondary
        : colors.outlineVariant;
    const radius = 17.0;
    return Semantics(
      selected: selected,
      enabled: onTap != null,
      child: AnimatedContainer(
        duration: motion(context, 325),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: outline),
        ),
        child: Pressable(
          radius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 12, 11),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 22, color: ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16,
                          height: 1.23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: muted,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    ExcludeSemantics(
                      child: AnimatedSwitcher(
                        duration: motion(context, 170),
                        child: selected == null
                            ? Icon(
                                Icons.chevron_right_rounded,
                                color: emphasized ? mint : colors.secondary,
                              )
                            : Container(
                                key: ValueKey(active),
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? colors.primary
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: active
                                        ? colors.primary
                                        : colors.outline,
                                  ),
                                ),
                                child: active
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: colors.onPrimary,
                                        size: 18,
                                      )
                                    : null,
                              ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrackerChoice extends StatelessWidget {
  const TrackerChoice({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id, label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: motion(context, 200),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : colors.surface,
          borderRadius: const BorderRadiusDirectional.only(
            topStart: Radius.circular(23),
            topEnd: Radius.circular(23),
            bottomStart: Radius.circular(23),
            bottomEnd: Radius.circular(7),
          ).resolve(Directionality.of(context)),
          border: Border.all(
            color: selected ? colors.secondary : colors.outlineVariant,
          ),
        ),
        child: Pressable(
          radius: 17,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TileIcon(id, size: 34),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: motion(context, 180),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        key: ValueKey(selected),
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum JournalArt { cover, pulse, schedule, archive, mosaic, transfer }

class SetupRail extends StatelessWidget {
  const SetupRail({super.key, required this.labels, required this.index});
  final List<String> labels;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: labels[index],
      value: '${index + 1} / ${labels.length}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, text) in labels.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: colors.outlineVariant,
                        ),
                        child: SizedBox(
                          height: 5,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: i <= index ? 1 : 0),
                              duration: motion(context, 680),
                              curve: motionArrival,
                              builder: (_, amount, _) => FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: amount,
                                child: ColoredBox(color: colors.primary),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          color: i == index
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: i == index
                              ? FontWeight.bold
                              : FontWeight.normal,
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
  }
}

class JournalIllustration extends StatelessWidget {
  const JournalIllustration({
    super.key,
    required this.art,
    required this.accent,
    this.expanded = false,
  });

  final JournalArt art;
  final Color accent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: motion(context, 630),
          curve: const Cubic(.18, .86, .27, 1),
          builder: (_, progress, _) => CustomPaint(
            painter: _JournalPainter(art, accent, dark, progress),
            child: SizedBox(
              width: expanded ? double.infinity : 106,
              height: expanded ? 206 : 88,
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalPainter extends CustomPainter {
  const _JournalPainter(this.art, this.accent, this.dark, this.progress);
  final JournalArt art;
  final Color accent;
  final bool dark;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 184, size.height / 144);
    canvas.save();
    canvas.translate((size.width - 184 * s) / 2, (size.height - 144 * s) / 2);
    canvas.scale(s, s);
    final color = dark ? brightBlue : evergreen;
    final base = dark ? const Color(0xff222c50) : const Color(0xffe9edff);
    final sheet = dark ? const Color(0xff313d63) : paper;
    final opacity = (progress * 1.2).clamp(0.0, 1.0);
    Color at(Color c) => c.withValues(alpha: opacity);
    void tile(Rect r, Color tone, {double radius = 14}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(radius)),
        Paint()..color = at(tone),
      );
    }

    void dot(Offset o, double radius, Color tone) => canvas.drawCircle(
      o,
      radius * (0.7 + .3 * progress),
      Paint()..color = at(tone),
    );

    void trace(List<Offset> points, Color tone, {double width = 3}) {
      final path = Path()..addPolygon(points, false);
      canvas.drawPath(
        path,
        Paint()
          ..color = at(tone)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void rotated(Rect r, double angle, Color tone) {
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.rotate(angle * (.55 + .45 * progress));
      tile(
        Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height),
        tone,
      );
      canvas.restore();
    }

    final orbit = Paint()
      ..color = color.withValues(alpha: opacity * .36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    canvas.save();
    canvas.translate(89, 73);
    canvas.rotate(-.30);
    canvas.drawOval(const Rect.fromLTWH(-84, -42, 168, 86), orbit);
    canvas.drawOval(const Rect.fromLTWH(-77, -55, 155, 106), orbit);
    canvas.restore();
    dot(const Offset(25, 26), 6, accent);
    dot(const Offset(157, 104), 6, accent);
    dot(const Offset(153, 28), 3, color);
    switch (art) {
      case JournalArt.cover:
      case JournalArt.pulse:
        rotated(
          const Rect.fromLTWH(
            41,
            27,
            108,
            88,
          ).shift(Offset(0, 15 * (1 - progress))),
          -.16,
          color,
        );
        rotated(
          const Rect.fromLTWH(
            45,
            34,
            108,
            86,
          ).shift(Offset(8 * (1 - progress), 0)),
          .14,
          accent,
        );
        tile(const Rect.fromLTWH(52, 35, 90, 80), sheet);
        trace(const [
          Offset(64, 79),
          Offset(81, 79),
          Offset(89, 66),
          Offset(100, 92),
          Offset(108, 75),
          Offset(128, 75),
        ], color);
        tile(const Rect.fromLTWH(64, 47, 29, 5), base, radius: 4);
        tile(const Rect.fromLTWH(64, 100, 47, 4), base, radius: 4);
      case JournalArt.schedule:
        rotated(const Rect.fromLTWH(42, 34, 101, 77), -.11, accent);
        tile(const Rect.fromLTWH(51, 35, 88, 77), sheet);
        for (var row = 0; row < 2; row++) {
          for (var col = 0; col < 3; col++) {
            final x = 61 + col * 23.0, y = 61 + row * 19.0;
            tile(
              Rect.fromLTWH(x, y, 15, 11),
              row == 0 && col == 1 ? color : base,
              radius: 4,
            );
          }
        }
        tile(const Rect.fromLTWH(60, 45, 36, 5), color, radius: 3);
        dot(const Offset(133, 104), 15, accent);
        trace(
          const [Offset(128, 105), Offset(132, 109), Offset(140, 99)],
          ink,
          width: 2.4,
        );
      case JournalArt.archive:
      case JournalArt.transfer:
        rotated(const Rect.fromLTWH(48, 27, 91, 86), -.14, accent);
        tile(const Rect.fromLTWH(50, 37, 90, 76), sheet);
        for (var i = 0; i < 3; i++) {
          final dy = 52 + i * 17.0;
          dot(Offset(64, dy + 2), 3, color);
          tile(Rect.fromLTWH(76, dy, i == 1 ? 37 : 47, 4), base, radius: 3);
        }
        dot(const Offset(133, 104), 16, color);
        if (art == JournalArt.transfer) {
          trace(
            const [Offset(127, 101), Offset(133, 107), Offset(139, 101)],
            dark ? ink : paper,
            width: 2.6,
          );
        } else {
          trace(
            const [Offset(128, 103), Offset(132, 106), Offset(140, 99)],
            dark ? ink : paper,
            width: 2.6,
          );
        }
      case JournalArt.mosaic:
        rotated(const Rect.fromLTWH(45, 28, 104, 91), -.12, color);
        tile(const Rect.fromLTWH(48, 34, 102, 85), sheet);
        tile(const Rect.fromLTWH(54, 40, 41, 35), accent, radius: 8);
        tile(const Rect.fromLTWH(99, 40, 43, 35), base, radius: 8);
        tile(const Rect.fromLTWH(54, 79, 41, 33), base, radius: 8);
        tile(
          const Rect.fromLTWH(99, 79, 43, 33),
          dark ? color : const Color(0xffdce4ff),
          radius: 8,
        );
        trace(
          const [
            Offset(63, 65),
            Offset(70, 58),
            Offset(77, 61),
            Offset(85, 52),
          ],
          ink,
          width: 2.3,
        );
        dot(const Offset(120, 57), 7, color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JournalPainter old) =>
      old.art != art ||
      old.accent != accent ||
      old.dark != dark ||
      old.progress != progress;
}

class JournalCover extends StatelessWidget {
  const JournalCover({
    super.key,
    required this.title,
    required this.subtitle,
    this.kicker,
    this.icon = Icons.auto_graph_rounded,
    this.accent = mint,
    this.action,
    this.trailing,
    this.titleTag,
    this.art,
  });
  final String title, subtitle;
  final String? kicker;
  final IconData icon;
  final Color accent;
  final Widget? action;
  final Widget? trailing;
  final Object? titleTag;
  final JournalArt? art;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final illustration =
        art ??
        (accent == rose
            ? JournalArt.schedule
            : accent == honey
            ? JournalArt.archive
            : accent == lavender
            ? JournalArt.mosaic
            : JournalArt.pulse);
    final heading = Text(
      title,
      style: TextStyle(
        color: colors.onSurface,
        fontWeight: FontWeight.bold,
        height: 1.14,
        fontSize: 34,
        fontFamily: Directionality.of(context) == TextDirection.rtl
            ? 'Tajawal'
            : 'Manrope',
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(27),
          topEnd: Radius.circular(27),
          bottomStart: Radius.circular(27),
          bottomEnd: Radius.circular(12),
        ),
        border: Border.all(color: colors.outlineVariant),
        color: Color.lerp(colors.surface, accent, dark ? .13 : .48),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(17, 14, 13, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ExcludeSemantics(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(icon, color: ink, size: 18),
                              ),
                            ),
                          ),
                          if (kicker != null) ...[
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                kicker!,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      titleTag == null
                          ? heading
                          : Hero(
                              tag: titleTag!,
                              child: Material(
                                color: Colors.transparent,
                                child: heading,
                              ),
                            ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ] else if (MediaQuery.textScalerOf(context).scale(16) < 23)
                  JournalIllustration(art: illustration, accent: accent),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 13), action!],
          ],
        ),
      ),
    );
  }
}

class Enter extends StatelessWidget {
  const Enter({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const timing = Duration(milliseconds: 460);
    return child
        .animate(delay: Duration(milliseconds: delay))
        .fade(begin: .22, duration: timing, curve: Curves.easeOut)
        .moveY(begin: 19, duration: timing, curve: motionArrival)
        .scaleXY(begin: .985, duration: timing, curve: motionArrival);
  }
}

class JournalLoading extends StatelessWidget {
  const JournalLoading({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    Widget block({required double h, double? w}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    );
    final silhouette = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        block(h: 44, w: 105),
        const SizedBox(height: 22),
        block(h: 62),
        const SizedBox(height: 14),
        block(h: 232),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(child: block(h: 99)),
            const SizedBox(width: 9),
            Expanded(child: block(h: 99)),
          ],
        ),
      ],
    );
    return Semantics(
      label: tr(arabic, 'جاري فتح يومي', 'Opening Yawmi'),
      liveRegion: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: MediaQuery.disableAnimationsOf(context)
              ? ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    colors.outlineVariant,
                    BlendMode.srcIn,
                  ),
                  child: silhouette,
                )
              : Shimmer.fromColors(
                  baseColor: colors.outlineVariant,
                  highlightColor: colors.surface,
                  child: silhouette,
                ),
        ),
      ),
    );
  }
}

class TileIcon extends StatelessWidget {
  const TileIcon(this.id, {super.key, this.size = 42});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint(id),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(glyph(id), size: size * .51, color: ink),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 23, bottom: 9),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                fontFamily: Directionality.of(context) == TextDirection.rtl
                    ? 'Tajawal'
                    : 'Manrope',
              ),
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel(
    this.icon,
    this.title,
    this.description, {
    super.key,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 31, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(description, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 13), action!],
        ],
      ),
    ),
  );
}

String cardName(JournalRow state, String id, bool ar) => id == medicineCard
    ? tr(ar, 'الأدوية', 'Medication')
    : trackerFor(state, id)?.name(ar) ?? id;
