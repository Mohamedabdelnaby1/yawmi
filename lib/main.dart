import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'catalog.dart';
import 'design.dart';
import 'domain.dart';
import 'dated_alerts.dart';
import 'care_data.dart';
import 'app_copy.dart';
import 'excel_export.dart';
import 'reminder_schedule.dart';
import 'store.dart';
import 'transfer.dart';
import 'widgets.dart';

part 'screens.dart';
part 'editors.dart';
part 'studio.dart';
part 'routine.dart';
part 'sharing.dart';
part 'hydration.dart';
part 'tracker_preferences.dart';
part 'adaptive.dart';
part 'personalization.dart';
part 'dedication.dart';
part 'overview.dart';
part 'daily.dart';
part 'stock.dart';
part 'follow_ups.dart';
part 'notifications.dart';
part 'updates.dart';
part 'care_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    FutureBuilder<Journal>(
      future: Journal.open(),
      builder: (context, snapshot) {
        final db = snapshot.data;
        if (db != null) return Yawmi(db, showDedication: true);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: yawmiTheme(Brightness.light),
          darkTheme: yawmiTheme(Brightness.dark),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: snapshot.hasError
                ? Builder(
                    builder: (c) => Center(
                      child: Text(
                        tr(
                          Localizations.localeOf(c).languageCode == 'ar',
                          'ماقدرناش نفتح سجل يومي',
                          'Could not open your Yawmi journal',
                        ),
                      ),
                    ),
                  )
                : const JournalLoading(),
          ),
        );
      },
    ),
  );
}

class Yawmi extends StatelessWidget {
  const Yawmi(this.db, {super.key, this.showDedication = false});
  final Journal db;
  final bool showDedication;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: db,
    builder: (context, _) {
      final state = db.state;
      return MaterialApp(
        title: 'يومي · Yawmi',
        debugShowCheckedModeBanner: false,
        theme: yawmiTheme(Brightness.light),
        darkTheme: yawmiTheme(Brightness.dark),
        themeMode: switch (state['theme']) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        },
        locale: state['language'] == 'system'
            ? null
            : Locale(state['language']),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          final canvas = ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: child!,
              ),
            ),
          );
          final content = showDedication
              ? _StartupDedication(child: canvas)
              : canvas;
          if (state['reduce'] != true) return content;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: content,
          );
        },
        home: _Home(db),
      );
    },
  );
}

class _Home extends StatefulWidget {
  const _Home(this.db);
  final Journal db;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  final _publisher = WidgetPublisher();
  final _search = TextEditingController();
  final _entryDrafts = <String, JournalRow>{};
  int tab = 0, period = 0;
  int _dashboardSection = 0;
  int _doseFilter = 0;
  DateTime? _focusedDay;
  String? filter;
  String? conditionFilter;
  DateTimeRange? dates;
  bool _handlingRoute = false;
  bool _notifying = false;
  bool _exact = false;
  bool _widgetError = false;
  bool _addingWater = false;
  bool _hasUpdateChannel = false;
  bool _syncingUpdates = false;
  String? _availableUpdate;
  Timer? _refresh, _clock;
  DateTime now = DateTime.now();
  JournalRow get data => widget.db.state;
  void _redraw(VoidCallback action) => setState(action);
  bool get ar => Localizations.localeOf(context).languageCode == 'ar';
  String t(String a, String e) => tr(ar, a, e);

  @override
  void initState() {
    super.initState();
    _dashboardSection = data['startSection'] == 'doses' ? 1 : 0;
    WidgetsBinding.instance.addObserver(this);
    widget.db.addListener(_changed);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final next = DateTime.now();
      final newDay = dayKey(now) != dayKey(next);
      setState(() => now = next);
      if (newDay) {
        _changed();
        unawaited(_autoArrange(next));
      }
    });
    if (Platform.isAndroid) {
      platform.setMethodCallHandler((call) async {
        if (call.method == 'open') await _route(call.arguments as String);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  @override
  void dispose() {
    widget.db.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) platform.setMethodCallHandler(null);
    _search.dispose();
    _clock?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume();
  }

  @override
  void didChangePlatformBrightness() => _changed();

  @override
  void didChangeLocales(List<Locale>? locales) => _changed();

  Future<void> _resume() async {
    if (!mounted) return;
    setState(() => now = DateTime.now());
    _changed();
    unawaited(_autoArrange(now));
    unawaited(clearSharedReports().catchError((Object _) {}));
    if (!Platform.isAndroid) return;
    unawaited(_refreshUpdateOffer());
    try {
      final route = await platform.invokeMethod<String>('takeRoute');
      if (route != null && mounted) await _route(route);
    } catch (_) {
      if (mounted)
        _toast(t('ماقدرناش نفتح الاختصار', 'Could not open shortcut'));
    }
  }

  void _changed() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      await _applyAutomatic();
      if (!mounted || !Platform.isAndroid) return;
      final state = data;
      try {
        final result = await platform.invokeMapMethod<String, bool>(
          'reconcile',
          {
            'rules': jsonEncode(notificationRules(state, ar)),
            'resolved': jsonEncode([
              for (final dose in rows(state['doses'])) ...[
                dose['id'],
                if (dose['legacyDue'] is String) dose['legacyDue'],
              ],
              ...rows(
                state['entries'],
              ).map(entryReminderOccurrence).whereType<String>(),
            ]),
            'lang': ar ? 'ar' : 'en',
          },
        );
        if (mounted) {
          setState(() {
            _notifying = result?['allowed'] == true;
            _exact = result?['exact'] == true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _notifying = false);
      }
      if (!mounted) return;
      try {
        await _publisher.update(data, ar);
        if (mounted && _widgetError) setState(() => _widgetError = false);
      } catch (_) {
        if (mounted) setState(() => _widgetError = true);
      }
    });
  }

  Future<bool> save(void Function(JournalRow) mutation) async {
    try {
      await widget.db.change(mutation);
      return true;
    } catch (_) {
      if (mounted) {
        _toast(
          t('التسجيل ما اتحفظش. جرّب تاني.', 'Could not save. Try again.'),
        );
      }
      return false;
    }
  }

  void _toast(String message, {SnackBarAction? action, bool sealed = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: sealed
              ? Row(
                  children: [
                    const ExcludeSemantics(child: SaveSeal()),
                    const SizedBox(width: 8),
                    Expanded(child: Text(message)),
                  ],
                )
              : Text(message),
          action: action,
          behavior: sealed ? SnackBarBehavior.floating : null,
        ),
      );
  }

  Future<T?> _page<T>(WidgetBuilder builder) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        transitionDuration: motion(context, 590),
        reverseTransitionDuration: motion(context, 425),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (_, anim, secondary, child) =>
            PageLift(animation: anim, behind: secondary, child: child),
      ),
    );
  }

  Future<T?> _sheet<T>(WidgetBuilder builder) => showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 600),
            reverseDuration: Duration(milliseconds: 420),
          ),
    builder: (context) => SheetLift(child: builder(context)),
  );

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            JournalButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _route(String route) async {
    if (!mounted ||
        _handlingRoute ||
        (data['stage'] != 3 && route != 'privacy'))
      return;
    _handlingRoute = true;
    try {
      final parts = route.split('/');
      switch (parts) {
        case ['today']:
          setState(() => tab = 0);
        case ['cup']:
          setState(() => tab = 0);
          await _addWater(defaultWaterCup(data));
        case ['cup', final condition]:
          setState(() => tab = 0);
          await _addWater(defaultWaterCup(data), condition);
        case ['studio']:
          await _openStudio();
        case ['studio', final id] when int.tryParse(id) != null:
          await _openWidgetInstance(int.parse(id));
        case ['routine']:
          setState(() => tab = 2);
        case ['privacy']:
          await _privacy();
        case ['updates']:
          await _openUpdates();
        case ['stock', final id]:
          setState(() => tab = 2);
          final med = rows(
            data['meds'],
          ).where((row) => row['id'] == id).firstOrNull;
          if (med != null && med['archived'] != true) await _medDetails(id);
        case ['expiry', final id]:
          setState(() => tab = 2);
          await _editMedicationExpiry(id);
        case ['packs', final id]:
          setState(() => tab = 2);
          await _medicationPacks(id);
        case ['follow-up', final id]:
          setState(() => tab = 2);
          await _openFollowUp(id);
        case ['reminder', final id, final day]:
          final rule = trackingSchedules(
            data,
            ar,
          ).where((r) => r['id'] == id).firstOrNull;
          final date = DateTime.tryParse(day);
          final trackerId = rule?['tracker'];
          final tracker = trackerId is String
              ? trackerFor(data, trackerId)
              : null;
          if (rule != null &&
              date != null &&
              !date.isAfter(DateTime.now()) &&
              tracker != null &&
              reminderTimeOn(rule, date) != null) {
            final key = reminderOccurrence(id, date);
            if (!rows(
              data['entries'],
            ).any((row) => entryReminderOccurrence(row) == key)) {
              await _entry(tracker, initialDay: date, occurrence: key);
            }
          }
        case ['tracker', final id]:
          final tracker = trackerFor(data, id);
          if (id == 'water') {
            await _hydrationDetails();
          } else if (tracker != null) {
            await _details(tracker);
          }
        case ['tracker', final id, final condition]:
          final tracker = trackerFor(data, id);
          if (tracker != null) await _details(tracker, condition: condition);
        case ['add', final id]:
          final tracker = trackerFor(data, id);
          if (tracker != null) await _entry(tracker);
        case ['add', final id, final condition]:
          final tracker = trackerFor(data, id);
          if (tracker != null)
            await _entry(tracker, suggestedCondition: condition);
        case ['dose', final id]:
          setState(() => tab = 2);
          final fields = id.split(':');
          final day = fields.length == 4 ? DateTime.tryParse(fields[2]) : null;
          final dose = dosesOn(
            data,
            day ?? DateTime.now(),
          ).where((x) => x.id == id).firstOrNull;
          if (dose != null) await _actDose(dose);
      }
    } finally {
      _handlingRoute = false;
    }
  }

  String prettyDate(DateTime date, [String pattern = 'EEE، d MMM']) =>
      DateFormat(
        ar ? pattern : pattern.replaceAll('،', ','),
        ar ? 'ar' : 'en',
      ).format(date);

  @override
  Widget build(BuildContext context) {
    if (data['stage'] != 3) return onboarding();
    final size = MediaQuery.sizeOf(context);
    final hasRail = size.width >= 870 && size.height >= 510;
    final labels = [
      (Icons.wb_sunny_outlined, t('اليوم', 'Today')),
      (Icons.history_rounded, t('السجل', 'History')),
      (Icons.event_repeat_rounded, t('روتيني', 'Routine')),
      (Icons.grid_view_outlined, t('المزيد', 'More')),
    ];
    final page = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 830),
        child: DirectionFlow(
          index: tab,
          child: switch (tab) {
            0 => today(),
            1 => history(),
            2 => routine(),
            _ => more(),
          },
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 61,
        title: Row(
          children: [
            const _IdentityMark(size: 36),
            const SizedBox(width: 9),
            Text(
              t('يومي', 'Yawmi'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: ar ? 'Tajawal' : 'Manrope',
                fontSize: 28,
                letterSpacing: -.35,
              ),
            ),
          ],
        ),
        actions: [
          if (_availableUpdate != null)
            IconButton.filledTonal(
              onPressed: _openUpdates,
              tooltip: t('تحديث جديد متاح', 'Update available'),
              icon: const Icon(Icons.system_update_rounded),
            ),
          if (tab == 0)
            IconButton.filledTonal(
              onPressed: _notificationSettings,
              tooltip: t('التذكيرات والتنبيهات', 'Reminders & notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          if (tab == 0)
            IconButton.filledTonal(
              onPressed: _openStudio,
              tooltip: t('استوديو الويدجت', 'Widget Studio'),
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
          if (tab == 1)
            IconButton(
              onPressed: () => _report(fromHistory: true),
              tooltip: t('مشاركة تقرير', 'Share report'),
              icon: const Icon(Icons.ios_share),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: hasRail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => _redraw(() => tab = i),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: IconButton.filled(
                      onPressed: _quickAdd,
                      tooltip: t('إضافة', 'Add'),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                  destinations: [
                    for (final (icon, label) in labels)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        label: Text(label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            )
          : page,
      bottomNavigationBar: hasRail
          ? null
          : Dock(
              labels,
              tab,
              (i) => _redraw(() => tab = i),
              onAdd: _quickAdd,
              addLabel: t('إضافة', 'Add'),
            ),
    );
  }
}
