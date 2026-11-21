import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'design.dart';
import 'domain.dart';

const platform = MethodChannel('app.yawmi/android');
const widgetSizes = [
  Size(166, 136),
  Size(332, 136),
  Size(332, 224),
  Size(246, 67),
  Size(86, 222),
  Size(168, 310),
  Size(332, 314),
  Size(332, 472),
];
const automaticWidgetId = 'today';
const palettes = [
  Color(0xff00656b),
  Color(0xff443578),
  Color(0xff315f55),
  Color(0xff975036),
  Color(0xff434779),
  Color(0xff48632d),
  Color(0xffa25276),
  Color(0xff56404d),
  evergreen,
];

JournalRow widgetConfig(JournalRow state, {bool empty = false}) => {
  'id': newId(),
  'name': '',
  'palette': palettes.length - 1,
  'style': 1,
  'appearance': 'system',
  'size': 1,
  'automatic': !empty,
  'enabled': <String>[],
  'pinned': <String>[],
  'hidden': <String>[],
  'order': <String>[],
  'values': false,
  'names': false,
  'compact': false,
  'summary': false,
  'add': false,
  'quickWater': false,
  'softCorners': true,
  'opacity': 1.0,
  'header': true,
  if (!empty) 'featured': true,
  'scopeValues': false,
};

Widget wrapNumeric(String s, TextStyle style, {int maxLines = 1}) => Text(
  s,
  textDirection: TextDirection.ltr,
  style: style,
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
);

typedef CardSummary = ({String value, String unit, String context});

CardSummary summaryFor(
  JournalRow state,
  String id,
  bool ar,
  DateTime now, {
  bool summary = false,
  bool demo = false,
}) {
  final t = trackerFor(state, id);
  if (id == medicineCard) {
    final next = outstanding(state, now).firstOrNull;
    if (demo) {
      return (
        value: '08:30',
        unit: '',
        context: tr(ar, 'دواء تجريبي', 'Sample medication'),
      );
    }
    return (
      value: next == null ? '—' : clockText(next.minute),
      unit: '',
      context: next == null
          ? tr(ar, 'لا جرعات معلّقة اليوم', 'No pending doses today')
          : next.medicine['name'] as String,
    );
  }
  if (t == null) return (value: '—', unit: '', context: '');
  final view = trackerView(state, t, widgetAverage: summary);
  final unit = view.mode == 'count' ? '' : displayUnit(state, t);
  final entries = trackerViewEntries(state, t, now, view);
  final range = inPeriod(entries, now, view.days);
  final n = range.length;
  final context = switch (view.mode) {
    'total' =>
      view.days == 1
          ? tr(ar, 'إجمالي اليوم', 'Today’s total')
          : tr(ar, 'إجمالي آخر ', 'Total · ') + summaryPeriod(view.days, ar),
    'average' => tr(ar, 'متوسط ', 'Average · ') + summaryPeriod(view.days, ar),
    'count' =>
      tr(ar, 'عدد الإدخالات · ', 'Entry count · ') +
          summaryPeriod(view.days, ar),
    _ => tr(ar, 'آخر قراءة', 'Latest reading'),
  };
  final filter = entryContext(view.context, ar);
  final description = [
    context,
    if (filter.isNotEmpty) filter,
    if (view.secondary && view.mode == 'average' && !demo)
      n.toString() + tr(ar, ' قراءة', ' readings'),
  ].join(' · ');
  if (demo) {
    final sample = switch (id) {
      'pressure' => '118/76',
      'glucose' => number(convert(id, 104, 'mg/dL', unit)),
      'water' => number(convert(id, 750, 'mL', unit)),
      'sleep' => number(convert(id, 7.5, 'h', unit)),
      'pulse' => '72',
      'peak_flow' => '350',
      'activity' => '35',
      'pain' => '3',
      'weight' => number(convert(id, 72, 'kg', unit)),
      'oxygen' => '98',
      'mood' => tr(ar, 'هادئ', 'Calm'),
      _ => '—',
    };
    return (
      value: view.mode == 'count' ? '3' : sample,
      unit: unit,
      context: tr(ar, 'بيانات تجريبية', 'Sample data'),
    );
  }
  if (view.mode == 'count')
    return (value: n.toString(), unit: '', context: description);
  if (view.mode == 'total') {
    final total = range.fold(
      0.0,
      (sum, e) =>
          sum +
          convert(
            id,
            (e['values']['value'] as num).toDouble(),
            e['unit'],
            unit,
          ),
    );
    return (value: number(total), unit: unit, context: description);
  }
  if (view.mode == 'average') {
    final value = id == 'pressure' && range.isNotEmpty
        ? ['systolic', 'diastolic']
              .map(
                (key) => number(
                  range.fold(0.0, (sum, e) => sum + (e['values'][key] as num)) /
                      n,
                ),
              )
              .join('/')
        : switch (average(range, t, unit)) {
            final double mean => number(mean),
            null => '—',
          };
    return (value: value, unit: unit, context: description);
  }
  final last = entries.firstOrNull;
  if (last == null) return (value: '—', unit: unit, context: description);
  final raw = last['values']['value'];
  final value = raw is num && t.units.isNotEmpty
      ? number(convert(id, raw.toDouble(), last['unit'], unit))
      : valueText(last, ar);
  return (
    value: value,
    unit: unit,
    context: [
      description,
      if (view.secondary) dayKey(eventTime(last)),
    ].join(' · '),
  );
}

String summaryPeriod(int days, bool ar) => switch (days) {
  0 => tr(ar, 'كل السجل', 'All history'),
  1 => tr(ar, 'اليوم', 'Today'),
  _ => days.toString() + tr(ar, ' يوم', ' days'),
};

const widgetActions = [
  'inherit',
  'details',
  'add',
  'cup',
  'routine',
  'confirm',
];
const widgetStyleCount = 5;

void setWidgetCardVisibility(
  JournalRow state,
  JournalRow config,
  String id,
  bool visible,
) {
  config['order'] = {
    ...strings(config['order']),
    ...cardPlan(state, config),
    id,
  }.toList();
  final enabled = strings(config['enabled']).toSet();
  final hidden = strings(config['hidden']).toSet();
  if (visible) {
    enabled.add(id);
    hidden.remove(id);
  } else {
    enabled.remove(id);
    hidden.add(id);
  }
  config['enabled'] = enabled.toList();
  config['hidden'] = hidden.toList();
}

void setWidgetFollowsToday(JournalRow state, JournalRow config, bool follow) {
  if (!follow) {
    final selected = cardPlan(state, config);
    config['enabled'] = selected;
    config['order'] = {...selected, ...strings(config['order'])}.toList();
  }
  config['automatic'] = follow;
}

List<JournalRow> restoreWidgetDesigns(JournalRow state, Object? raw) {
  final seen = <String>{};
  bool valid(String id) => id == medicineCard || trackerFor(state, id) != null;
  return [
    for (final item in rows(raw).take(30))
      if (item['id'] case final String id
          when id != automaticWidgetId &&
              RegExp(r'^[a-zA-Z0-9_-]{1,90}$').hasMatch(id) &&
              seen.add(id))
        {
          ...widgetConfig(state, empty: true),
          'id': id,
          if (item['name'] case final String name when name.length <= 120)
            'name': name,
          for (final key in ['enabled', 'pinned', 'hidden', 'order'])
            key: strings(item[key]).where(valid).toSet().toList(),
          for (final key in [
            'values',
            'names',
            'compact',
            'summary',
            'add',
            'automatic',
            'quickWater',
            'softCorners',
            'header',
            'scopeValues',
            'artwork',
            'icons',
            'largeValues',
            'featured',
            'clock',
            'clockDate',
            'showShortcut',
            'showSettings',
            'showRefresh',
          ])
            if (item[key] is bool) key: item[key],
          for (final (key, limit) in [
            ('palette', palettes.length),
            ('style', widgetStyleCount),
            ('size', widgetSizes.length),
          ])
            if (item[key] case final int n when n >= 0 && n < limit) key: n,
          if (['system', 'light', 'dark'].contains(item['appearance']))
            'appearance': item['appearance'],
          if (['12', '24'].contains(item['clockFormat']))
            'clockFormat': item['clockFormat'],
          if (['ar', 'en'].contains(item['clockLanguage']))
            'clockLanguage': item['clockLanguage'],
          if (['ar', 'en'].contains(item['timeLanguage']))
            'timeLanguage': item['timeLanguage'],
          if (['off', 'suggest', 'auto'].contains(item['layoutLearning']))
            'layoutLearning': item['layoutLearning'],
          if (item['opacity'] case final num opacity when opacity.isFinite)
            'opacity': opacity.toDouble().clamp(.92, 1.0),
          if (item['columns'] case final int columns
              when columns >= 1 && columns <= 3)
            'columns': columns,
          if (item['customColor'] case final int color
              when color >= 0 && color <= 0xffffff)
            'customColor': color,
          if (rows(
            state['conditions'],
          ).any((c) => c['id'] == item['condition']))
            'condition': item['condition'],
          'cardOptions': {
            for (final e in (item['cardOptions'] as Map? ?? {}).entries)
              if (e.key is String && valid(e.key) && e.value is Map)
                e.key: {
                  for (final key in [
                    'show',
                    'unit',
                    'context',
                    'indicator',
                    'icon',
                  ])
                    if (e.value[key] is bool) key: e.value[key],
                  if (widgetActions.contains(e.value['action']))
                    'action': e.value['action'],
                  if (e.value['title'] case final String title
                      when title.length <= 45)
                    'title': title,
                  if (e.value['accent'] case final int n
                      when n >= 0 && n < palettes.length)
                    'accent': n,
                  if (trackerFor(state, e.key) case final Tracker spec)
                    if (trackerViewModes(spec).contains(e.value['mode']))
                      'mode': e.value['mode'],
                  if (trackerFor(
                        state,
                        e.key,
                      )?.units.contains(e.value['displayUnit']) ==
                      true)
                    'displayUnit': e.value['displayUnit'],
                  if (e.key == 'glucose' &&
                      ['all', ...glucoseContexts].contains(e.value['filter']))
                    'filter': e.value['filter'],
                  if (summaryWindows.contains(e.value['days']))
                    'days': e.value['days'],
                },
          },
        },
  ];
}

class WidgetScene {
  WidgetScene(
    JournalRow state,
    JournalRow config,
    bool ar,
    int oldSize, {
    bool demo = false,
    bool systemDark = false,
    DateTime? today,
  }) : this.responsive(
         state,
         config,
         ar,
         widgetSizes[oldSize],
         demo: demo,
         systemDark: systemDark,
         today: today,
       );

  WidgetScene.responsive(
    this.state,
    this.config,
    this.ar,
    this.viewport, {
    this.demo = false,
    this.systemDark = false,
    DateTime? today,
  }) : now = today ?? DateTime.now();

  final JournalRow state, config;
  final bool ar, demo, systemDark;
  final Size viewport;
  final DateTime now;
  static const gap = 6.0;
  double get outerCorner => math.min(
    config['softCorners'] == false
        ? 12.0
        : narrow || slim
        ? 18.0
        : 26.0,
    math.min(viewport.width, viewport.height) * .27,
  );
  double panelCorner(double width, double height, {double extraInset = 0}) =>
      math.min(
        math.max(4.0, outerCorner - inset - extraInset),
        math.min(width, height) * .29,
      );
  bool get slim => viewport.height < 105;
  bool get narrow => viewport.width < 118;
  bool get clock => config['clock'] == true && viewport.height >= 98;
  bool get heading => !clock && !slim && config['header'] != false;
  bool get toolbar =>
      (clock || !slim) &&
      config['showSettings'] != false &&
      viewport.width >= (clock ? 260 : 122);
  bool get refresh =>
      (clock || !slim) &&
      config['showRefresh'] != false &&
      viewport.width >= (clock ? 350 : 177);
  bool get header => clock || heading || toolbar || refresh;
  bool get footer => viewport.height >= 170 && !narrow && shortcut != null;
  double get footerHeight => footer ? 54 : 0;
  int get maxColumns =>
      ((viewport.width - 2 * inset + gap) / 95).floor().clamp(1, 3);
  int get columns => ((config['columns'] as int?) ?? 3).clamp(1, maxColumns);
  int get rowCapacity =>
      ((viewport.height - topInset - inset - footerHeight + gap) / 54)
          .floor()
          .clamp(1, 8);
  bool get featured =>
      config['featured'] == true &&
      columns > 1 &&
      rowCapacity > 1 &&
      cardPlan(state, config).length > 1;
  int get capacity =>
      featured ? (rowCapacity - 1) * columns + 1 : rowCapacity * columns;
  List<({int columns, List<String> cards})> get grid {
    final shown = cards;
    final result = <({int columns, List<String> cards})>[];
    for (var offset = 0; offset < shown.length;) {
      final width = featured && offset == 0 ? 1 : columns;
      result.add((
        columns: math.min(width, shown.length - offset),
        cards: shown.skip(offset).take(width).toList(),
      ));
      offset += width;
    }
    return result;
  }

  double get inset => slim
      ? 6
      : config['compact'] == true
      ? 6
      : 8;
  double get headerHeight => clock ? (narrow ? 47 : 50) : (narrow ? 31 : 48);
  double get topInset => inset + (header ? headerHeight : 0);
  bool get dark =>
      config['appearance'] == 'dark' ||
      ((config['appearance'] ?? 'system') == 'system' && systemDark);
  Color get accent => switch (config['customColor']) {
    final int rgb => Color(0xff000000 | rgb),
    _ =>
      palettes[(config['palette'] as int? ?? 0).clamp(0, palettes.length - 1)],
  };
  List<String> get cards => cardPlan(state, config).take(capacity).toList();
  List<String> get cropped =>
      cardPlan(state, config).skip(cards.length).toList();
  Map options(String id) => (config['cardOptions'] as Map?)?[id] as Map? ?? {};
  String title(String id) {
    final custom = (options(id)['title'] as String?)?.trim() ?? '';
    return custom.isEmpty ? cardName(state, id, ar) : custom;
  }

  Color cardAccent(String id) {
    final pick = options(id)['accent'];
    return pick is int && pick >= 0 && pick < palettes.length
        ? palettes[pick]
        : switch (id) {
            'glucose' => const Color(0xffc4adf4),
            'water' => const Color(0xff9bdff2),
            medicineCard => const Color(0xffffba93),
            _ => tint(id),
          };
  }

  bool get clockDate => config['clockDate'] != false;
  String get clockFormat => config['clockFormat']?.toString() ?? 'system';
  String get clockLanguage => config['clockLanguage']?.toString() ?? 'app';
  String get timeLanguage => config['timeLanguage'] == 'ar' ? 'ar' : 'en';
  bool get dateArabic =>
      clockLanguage == 'ar' || (clockLanguage == 'app' && ar);
  String get dateLocale => dateArabic ? 'ar' : 'en';
  bool get stackedClock => clockDate && viewport.width < 146;
  bool get fullDate => clockDate && viewport.width >= 210;
  double get clockSize => stackedClock
      ? 20
      : viewport.width < 190
      ? 24
      : 29;
  double get clockTimeWidth {
    final chromeWidth = (toolbar ? 48 : 0) + (refresh ? 48 : 0);
    final available = viewport.width - 2 * inset - chromeWidth;
    return (available * .46).clamp(64.0, 142.0);
  }

  String get dateHeading => DateFormat('EEEE', dateLocale).format(now);
  String get dateLine {
    final month = DateFormat(fullDate ? 'MMMM' : 'MMM', dateLocale).format(now);
    return dateArabic ? '${now.day} $month' : '$month ${now.day}';
  }

  ({String label, String route})? get shortcut {
    final id = cardPlan(state, config).firstOrNull;
    if (config['showShortcut'] == false || id == null) return null;
    final scope = config['automatic'] == true
        ? config['condition'] as String?
        : null;
    final target = scope == null ? id : '$id/$scope';
    return switch (id) {
      medicineCard => (
        label: tr(ar, 'مواعيد الدواء', 'Medication schedule'),
        route: 'routine',
      ),
      'glucose' => (
        label: tr(ar, 'سجّل قراءة السكر', 'Log glucose'),
        route: 'add/$target',
      ),
      'water'
          when options(id)['action'] == 'cup' || config['quickWater'] == true =>
        (
          label: tr(ar, 'سجّل كوب مياه', 'Log a cup'),
          route: scope == null ? 'cup' : 'cup/$scope',
        ),
      'water' => (
        label: tr(ar, 'سجّل المياه', 'Log water'),
        route: 'add/$target',
      ),
      _ => (label: tr(ar, 'سجّل ', 'Log ') + title(id), route: 'add/$target'),
    };
  }

  bool reveals(String id) =>
      (options(id)['show'] as bool? ??
      (config[id == medicineCard ? 'names' : 'values'] == true));

  List<double> indicator(String id) {
    if (config['artwork'] == false ||
        options(id)['indicator'] == false ||
        !reveals(id)) {
      return const [];
    }
    final tracker = trackerFor(state, id);
    if (tracker == null || tracker.kind != 'number') return const [];
    final scoped = _cardState(id);
    if (id == 'water') {
      final amount = demo ? 750.0 : waterTotal(scoped, now);
      final goal = demo ? 2000 : scoped['waterGoal'];
      return goal is num && goal > 0 ? [(amount / goal).clamp(0.0, 1.0)] : [];
    }
    if (demo) return [2, 3, 2.5, 5, 4, 5.5, 4.8];
    return trackerViewEntries(
          scoped,
          tracker,
          now,
          trackerView(scoped, tracker),
        )
        .take(9)
        .map((e) {
          final raw = e['values'][id == 'pressure' ? 'systolic' : 'value'];
          return raw is num
              ? convert(
                  id,
                  raw.toDouble(),
                  e['unit'],
                  displayUnit(scoped, tracker),
                )
              : null;
        })
        .whereType<double>()
        .toList()
        .reversed
        .toList();
  }

  JournalRow _cardState(String id) {
    final override = options(id);
    final scope =
        config['automatic'] == true &&
            config['scopeValues'] == true &&
            config['condition'] is String
        ? config['condition'] as String
        : null;
    if ([
          'mode',
          'days',
          'filter',
          'displayUnit',
        ].every((key) => override[key] == null) &&
        scope == null) {
      return state;
    }
    final views = state['trackerViews'] as Map? ?? {};
    return {
      ...state,
      if (scope != null)
        'entries': rows(state['entries'])
            .where(
              (row) => rows(
                row['conditions'],
              ).any((condition) => condition['id'] == scope),
            )
            .toList(),
      if (scope != null && id == medicineCard)
        'meds': rows(
          state['meds'],
        ).where((med) => strings(med['links']).contains(scope)).toList(),
      if (override['displayUnit'] != null)
        'unitPrefs': {
          ...(state['unitPrefs'] as Map? ?? {}),
          id: override['displayUnit'],
        },
      'trackerViews': {
        ...views,
        id: {
          ...(views[id] as Map? ?? {}),
          for (final key in ['mode', 'days'])
            if (override[key] != null) key: override[key],
          if (override['filter'] != null) 'context': override['filter'],
        },
      },
    };
  }

  bool isDaily(String id) {
    if (id == medicineCard) return true;
    final tracker = trackerFor(state, id);
    if (tracker == null) return false;
    final view = trackerView(
      _cardState(id),
      tracker,
      widgetAverage: config['summary'] == true,
    );
    return view.days == 1 && view.mode != 'latest';
  }

  String route(String id) {
    final action = options(id)['action'];
    final scope = config['automatic'] == true && config['condition'] is String
        ? config['condition'] as String
        : '';
    final target = scope.isEmpty ? id : '$id/$scope';
    final details = config['scopeValues'] == true ? target : id;
    if (id == medicineCard) {
      if (action == 'routine') return 'routine';
      final dose = outstanding(_cardState(id), now).firstOrNull;
      return dose == null ? 'routine' : 'dose/${dose.id}';
    }
    if (action == 'details') return 'tracker/$details';
    if (action == 'add') return 'add/$target';
    if (id == 'water' && (action == 'cup' || config['quickWater'] == true)) {
      return scope.isEmpty ? 'cup' : 'cup/$scope';
    }
    return config['add'] == true ? 'add/$target' : 'tracker/$details';
  }

  CardSummary card(String id) {
    final options = this.options(id);
    if (!reveals(id)) {
      return id == medicineCard
          ? (
              value: '••:••',
              unit: '',
              context: options['context'] == false
                  ? ''
                  : tr(ar, 'موعد دواء', 'Medication schedule'),
            )
          : (
              value: '•••',
              unit: '',
              context: options['context'] == false
                  ? ''
                  : tr(ar, 'اضغط للعرض', 'Tap to view'),
            );
    }
    final s = summaryFor(
      _cardState(id),
      id,
      ar,
      now,
      summary: config['summary'] == true,
      demo: demo,
    );
    return (
      value: s.value,
      unit: options['unit'] == false ? '' : s.unit,
      context: options['context'] == false ? '' : s.context,
    );
  }
}

class SceneArt extends StatelessWidget {
  const SceneArt(this.scene, {super.key, this.onTap, this.onCardTap});
  final WidgetScene scene;
  final void Function(String)? onTap;
  final void Function(String)? onCardTap;

  Color get _base => switch (scene.config['style']) {
    0 => scene.dark ? const Color(0xff18302b) : const Color(0xffe7f0e8),
    2 => scene.dark ? const Color(0xff141e33) : const Color(0xffe2ebf8),
    3 => scene.dark ? const Color(0xff282a32) : const Color(0xfffcf9ef),
    4 => Color.lerp(
      scene.dark ? const Color(0xff192926) : Colors.white,
      scene.accent,
      scene.dark ? .30 : .19,
    )!,
    _ => scene.dark ? const Color(0xff182d29) : const Color(0xfff3f0e5),
  };

  Color get _ink =>
      scene.dark ? const Color(0xfff7f6ee) : const Color(0xff152944);
  Color get _button => scene.dark
      ? Color.lerp(scene.accent, const Color(0xffe1f1da), .78)!
      : Color.lerp(scene.accent, const Color(0xff18382f), .68)!;
  Color get _buttonInk => scene.dark ? const Color(0xff152944) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final grid = scene.grid;
    final shortcut = scene.shortcut;
    final opacity = (scene.config['opacity'] as num? ?? 1).toDouble().clamp(
      .92,
      1.0,
    );
    return Directionality(
      textDirection: scene.ar ? TextDirection.rtl : TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: 'Tajawal', color: _ink, height: 1.10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(scene.inset),
          decoration: BoxDecoration(
            color: _base.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(scene.outerCorner),
          ),
          child: Column(
            children: [
              if (scene.header)
                SizedBox(
                  height: scene.headerHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: scene.clock
                            ? _clockPreview(context)
                            : !scene.heading
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 5,
                                ),
                                child: Text(
                                  scene.config['name']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? scene.config['name'] as String
                                      : tr(scene.ar, 'يومي', 'Yawmi'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: scene.narrow ? 13 : 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                      if (scene.refresh)
                        _tool(
                          Icons.refresh_rounded,
                          tr(scene.ar, 'حدّث الويدجت', 'Refresh widget'),
                          'preview/refresh',
                        ),
                      if (scene.toolbar)
                        _tool(
                          Icons.tune_rounded,
                          tr(scene.ar, 'إعدادات الويدجت', 'Widget settings'),
                          'preview/settings',
                        ),
                    ],
                  ),
                ),
              if (grid.isEmpty)
                Expanded(
                  child: scene.clock
                      ? const SizedBox.shrink()
                      : Center(
                          child: Text(
                            tr(
                              scene.ar,
                              'اختار متابعاتك',
                              'Choose your trackers',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                )
              else
                for (final (row, line) in grid.indexed) ...[
                  if (row != 0) const SizedBox(height: WidgetScene.gap),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (col, id) in line.cards.indexed) ...[
                          if (col != 0) const SizedBox(width: WidgetScene.gap),
                          Expanded(child: _cell(context, id)),
                        ],
                      ],
                    ),
                  ),
                ],
              if (scene.footer && shortcut != null) ...[
                const SizedBox(height: WidgetScene.gap),
                GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(shortcut.route),
                  child: Container(
                    height: scene.footerHeight - WidgetScene.gap,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _button,
                      borderRadius: BorderRadius.circular(
                        scene.panelCorner(
                          scene.viewport.width,
                          scene.footerHeight - WidgetScene.gap,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          shortcut.route == 'routine'
                              ? Icons.schedule_rounded
                              : Icons.add_rounded,
                          color: _buttonInk,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            shortcut.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _buttonInk,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, String route) => SizedBox(
    width: 48,
    child: GestureDetector(
      onTap: onTap == null ? null : () => onTap!(route),
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        button: onTap != null,
        child: Center(
          child: Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: _ink.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(
                scene.panelCorner(31, 31, extraInset: 5),
              ),
            ),
            child: Icon(icon, size: 18, color: _ink),
          ),
        ),
      ),
    ),
  );

  Widget _clockPreview(BuildContext context) {
    final use24 =
        scene.clockFormat == '24' ||
        scene.clockFormat == 'system' &&
            MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(
      use24 ? 'HH:mm' : 'h:mm',
      scene.timeLanguage,
    ).format(scene.now);
    final dateDir = scene.dateArabic ? TextDirection.rtl : TextDirection.ltr;
    final surface = _ink.withValues(alpha: .08);
    final clockFace = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            Text(
              time,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: scene.clockSize,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
            ),
          ],
        ),
      ),
    );
    Widget dateLine({required bool full}) => Directionality(
      textDirection: dateDir,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: full ? 8 : 5),
        child: Row(
          mainAxisAlignment: full
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (full) ...[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _ink.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(
                    scene.panelCorner(26, 26, extraInset: 5),
                  ),
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: full
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  if (full)
                    Text(
                      scene.dateHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink.withValues(alpha: .80),
                        fontSize: 10,
                      ),
                    ),
                  Text(
                    scene.dateLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: full ? 14 : 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    Widget panel(Widget child, {bool time = false}) => LayoutBuilder(
      builder: (_, bounds) => DecoratedBox(
        decoration: BoxDecoration(
          color: time
              ? Color.alphaBlend(leaf.withValues(alpha: .15), surface)
              : surface,
          borderRadius: BorderRadius.circular(
            scene.panelCorner(bounds.maxWidth, bounds.maxHeight),
          ),
        ),
        child: SizedBox.expand(child: child),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: WidgetScene.gap),
      child: !scene.clockDate
          ? panel(clockFace, time: true)
          : scene.stackedClock
          ? panel(
              Column(
                children: [
                  Expanded(child: clockFace),
                  SizedBox(height: 16, child: dateLine(full: false)),
                ],
              ),
              time: true,
            )
          : Row(
              children: [
                SizedBox(
                  width: scene.clockTimeWidth,
                  child: panel(clockFace, time: true),
                ),
                const SizedBox(width: WidgetScene.gap),
                Expanded(
                  child: panel(Center(child: dateLine(full: scene.fullDate))),
                ),
              ],
            ),
    );
  }

  Widget _cell(BuildContext context, String id) {
    final item = scene.card(id);
    final name = scene.title(id);
    final tone = scene.cardAccent(id);
    final showIcon =
        scene.config['icons'] != false && scene.options(id)['icon'] != false;
    final points = scene.indicator(id);
    final hasGraph = id == 'water' ? points.isNotEmpty : points.length > 1;
    final widget = LayoutBuilder(
      builder: (_, bounds) {
        final width = bounds.maxWidth;
        final height = bounds.maxHeight;
        final wide = width >= 146 && height >= 55;
        final compact = height < 61;
        final sizable = height >= 74;
        final block = showIcon || hasGraph;
        final toneAmount = scene.config['style'] == 3
            ? .23
            : scene.dark
            ? (wide ? .44 : .32)
            : (wide ? .91 : .68);
        final surface = Color.lerp(_base, tone, toneAmount)!;
        const navy = Color(0xff152944);
        const cream = Color(0xfff7f6ee);
        final luminance = surface.computeLuminance() + .05;
        final foreground = luminance >= 4.5 * (navy.computeLuminance() + .05)
            ? navy
            : (cream.computeLuminance() + .05) >= 4.5 * luminance
            ? cream
            : Colors.black;
        final marker = block && (wide || (width >= 114 && sizable));
        final panelWidth = wide
            ? math.min(112.0, width * (width < 200 ? .34 : .41))
            : 0.0;
        final showContext = height >= 66 && width >= 93;
        final pad = width < 90 ? 5.0 : 8.0;
        Widget label(
          String text,
          double size, {
          bool bold = false,
          bool ltr = false,
        }) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: ltr ? TextDirection.ltr : null,
          style: TextStyle(
            fontSize: size,
            color: foreground,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        );
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(
              scene.panelCorner(width, height),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    label(
                      name,
                      compact || width < 105
                          ? 11
                          : width < 160
                          ? 12
                          : 14,
                      bold: true,
                    ),
                    SizedBox(height: compact ? 0 : 2),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            label(
                              item.value,
                              (compact
                                      ? 19.0
                                      : (wide && sizable ? 30.0 : 23.0)) *
                                  (scene.config['largeValues'] == true
                                      ? 1.14
                                      : 1),
                              bold: true,
                              ltr: RegExp(r'^[0-9•—]').hasMatch(item.value),
                            ),
                            if (item.unit.isNotEmpty && width >= 75) ...[
                              const SizedBox(width: 4),
                              label(item.unit, 10, ltr: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (item.unit.isNotEmpty && width < 75 && height >= 52)
                      label(item.unit, 9, ltr: true),
                    if (showContext && item.context.isNotEmpty)
                      label(item.context, 10),
                  ],
                ),
              ),
              if (marker && wide) ...[
                SizedBox(width: pad),
                SizedBox(
                  width: panelWidth,
                  height: math.min(
                    width < 200 ? 54 : 84,
                    height - 2 * (compact ? 4 : 6),
                  ),
                  child: _visual(id, points, foreground),
                ),
              ] else if (marker && (showIcon || id == 'water' && hasGraph))
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 3),
                  child: _visual(id, points, foreground, mini: true),
                ),
            ],
          ),
        );
      },
    );
    return Semantics(
      button: true,
      label: [
        name,
        item.value,
        item.unit,
        item.context,
      ].where((s) => s.isNotEmpty).join(' '),
      excludeSemantics: true,
      child: onTap == null && onCardTap == null
          ? widget
          : GestureDetector(
              onTap: () {
                if (onCardTap != null) {
                  onCardTap!(id);
                } else {
                  onTap!(scene.route(id));
                }
              },
              child: widget,
            ),
    );
  }

  Widget _visual(
    String id,
    List<double> series,
    Color ink, {
    bool mini = false,
  }) {
    final hasSignal = id == 'water' ? series.isNotEmpty : series.length > 1;
    return LayoutBuilder(
      builder: (_, bounds) => Container(
        width: mini ? 24 : null,
        height: mini ? 24 : null,
        padding: EdgeInsets.all(mini ? 4 : 8),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(
            scene.panelCorner(
              mini ? 24 : bounds.maxWidth,
              mini ? 24 : bounds.maxHeight,
              extraInset: 5,
            ),
          ),
        ),
        child: hasSignal && (!mini || id == 'water')
            ? CustomPaint(painter: _WidgetSignal(series, ink, id == 'water'))
            : Icon(glyph(id), color: ink, size: mini ? 15 : 29),
      ),
    );
  }
}

class _WidgetSignal extends CustomPainter {
  const _WidgetSignal(this.values, this.color, this.water);
  final List<double> values;
  final Color color;
  final bool water;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 4) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    if (water) {
      final diameter = math.min(38.0, size.shortestSide - 4);
      final ring = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: diameter,
        height: diameter,
      );
      paint.strokeWidth = math.min(4.0, diameter / 4);
      paint.style = PaintingStyle.stroke;
      canvas.drawOval(ring, paint..color = color.withValues(alpha: .22));
      if (values.first > 0) {
        canvas.drawArc(
          ring,
          -math.pi / 2,
          values.first * math.pi * 2,
          false,
          paint..color = color,
        );
      }
      if (diameter >= 20) {
        final c = ring.center;
        final drop = Path()
          ..moveTo(c.dx, c.dy - 6)
          ..cubicTo(c.dx - 10, c.dy + 3, c.dx - 3, c.dy + 7, c.dx, c.dy + 6)
          ..cubicTo(c.dx + 3, c.dy + 7, c.dx + 10, c.dy + 3, c.dx, c.dy - 6);
        canvas.drawPath(drop, paint..strokeWidth = 1.6);
      }
      return;
    }
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = math.max(.001, hi - lo);
    final box = (Offset.zero & size).deflate(3);
    final plot = Path();
    Offset? first, last;
    for (final f in [.20, .50, .80]) {
      final y = box.top + box.height * f;
      canvas.drawLine(
        Offset(box.left, y),
        Offset(box.right, y),
        paint
          ..color = color.withValues(alpha: .23)
          ..strokeWidth = 1,
      );
    }
    for (final (i, value) in values.indexed) {
      final point = Offset(
        box.left + box.width * i / (values.length - 1),
        hi == lo
            ? box.center.dy
            : box.bottom - box.height * (.16 + .68 * (value - lo) / span),
      );
      if (i == 0) {
        first = point;
        plot.moveTo(point.dx, point.dy);
      } else {
        plot.lineTo(point.dx, point.dy);
      }
      last = point;
    }
    canvas.drawPath(
      plot,
      paint
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(first!, 2.5, paint);
    canvas.drawCircle(last!, 2.5, paint);
  }

  @override
  bool shouldRepaint(covariant _WidgetSignal oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.water != water;
}

JournalRow widgetSnapshot(JournalRow state, bool ar, DateTime moment) {
  JournalRow nextDayCard(WidgetScene next, String id) {
    final entry = next.card(id);
    return {
      'offset': next.now.timeZoneOffset.inMinutes,
      'value': entry.value,
      'unit': entry.unit,
      'context': entry.context,
      'route': next.route(id),
      'points': id == 'water' && next.indicator(id).isNotEmpty
          ? [0]
          : <double>[],
    };
  }

  final layouts = rows(state['widgets']);
  final automatic = {...widgetConfig(state), 'id': automaticWidgetId};
  final nextDays = {
    for (var offset = 1; offset <= 7; offset++)
      dayKey(DateTime(moment.year, moment.month, moment.day + offset)):
          <JournalRow>[],
  };
  final nextStart = DateTime(moment.year, moment.month, moment.day + 1);
  final cutoff = DateTime(moment.year, moment.month, moment.day + 8);
  for (final row in (state['entries'] as List? ?? []).cast<JournalRow>()) {
    final at = eventTime(row);
    if (!at.isBefore(nextStart) && at.isBefore(cutoff))
      nextDays[dayKey(at)]?.add(row);
  }
  final published = <String, dynamic>{};
  for (final (index, config) in [automatic, ...layouts].indexed) {
    final scene = WidgetScene.responsive(
      state,
      config,
      ar,
      const Size(332, 190),
      today: moment,
    );
    final id = config['id'] as String;
    final name = (config['name'] as String? ?? '').trim();
    final upcoming = [
      for (var offset = 1; offset <= 7; offset++)
        WidgetScene.responsive(
          {
            ...state,
            'entries':
                nextDays[dayKey(
                  DateTime(moment.year, moment.month, moment.day + offset),
                )],
          },
          config,
          ar,
          const Size(332, 190),
          today: DateTime(moment.year, moment.month, moment.day + offset),
        ),
    ];
    final cards = <JournalRow>[];
    for (final tracker in cardPlan(state, config).take(24)) {
      final info = scene.card(tracker);
      cards.add({
        'id': tracker,
        'title': scene.title(tracker),
        'value': info.value,
        'unit': info.unit,
        'context': info.context,
        'daily': scene.isDaily(tracker),
        'accent': scene.cardAccent(tracker).toARGB32(),
        'icon':
            config['icons'] != false && scene.options(tracker)['icon'] != false,
        'route': scene.route(tracker),
        'points': scene.indicator(tracker),
        if (scene.isDaily(tracker))
          'advance': {
            for (final next in upcoming)
              dayKey(next.now): nextDayCard(next, tracker),
          },
      });
    }
    if (index > 0 && id == automaticWidgetId) continue;
    published[id] = {
      'name': id == automaticWidgetId
          ? tr(ar, 'بطاقات اليوم', 'Today’s cards')
          : name.isEmpty
          ? '${tr(ar, 'تركيبة', 'Layout')} $index'
          : name,
      'heading': name.isEmpty ? tr(ar, 'يومي', 'Yawmi') : name,
      if (scene.shortcut case final shortcut?)
        'shortcut': {'label': shortcut.label, 'route': shortcut.route},
      'accent': scene.accent.toARGB32(),
      'columns': config['columns'],
      'featured': config['featured'] == true,
      'compact': config['compact'] == true,
      'clock': config['clock'] == true,
      'clockDate': scene.clockDate,
      'clockFormat': scene.clockFormat,
      'clockLanguage': scene.dateLocale,
      'timeLanguage': scene.timeLanguage,
      'header': config['header'] != false,
      'showSettings': config['showSettings'] != false,
      'showRefresh': config['showRefresh'] != false,
      'artwork': config['artwork'] != false,
      'softCorners': config['softCorners'] != false,
      'appearance': config['appearance'],
      'style': config['style'],
      'opacity': config['opacity'],
      'largeValues': config['largeValues'] == true,
      'cards': cards,
    };
  }
  final preferred = state['widgetDefault'];
  return {
    'day': dayKey(moment),
    'offset': moment.timeZoneOffset.inMinutes,
    'ar': ar,
    'default': published.containsKey(preferred) ? preferred : automaticWidgetId,
    'layouts': published,
  };
}

class WidgetPublisher {
  Future<void> _tail = Future.value();

  Future<void> update(
    JournalRow state,
    bool ar, {
    int? widgetId,
    String? layout,
  }) {
    if (!Platform.isAndroid) return Future.value();
    final run = _tail.then((_) async {
      final snapshot = await compute(_encodeWidgetSnapshot, (
        state,
        ar,
        DateTime.now(),
      ));
      await platform.invokeMethod<void>('publishWidgets', {
        'snapshot': snapshot,
        if (widgetId != null && layout != null) ...{
          'widget': widgetId,
          'layout': layout,
        },
      });
    });
    _tail = run.then((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }
}

String _encodeWidgetSnapshot((JournalRow, bool, DateTime) data) =>
    jsonEncode(widgetSnapshot(data.$1, data.$2, data.$3));
