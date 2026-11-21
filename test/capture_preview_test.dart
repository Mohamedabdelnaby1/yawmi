import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/dated_alerts.dart';
import 'package:yawmi/design.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/widgets.dart';
import 'yawmi_test.dart' show MemoryJournal, reading;

class _CsvFixturePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final file = File('test/fixtures/yawmi-readings.csv').absolute;
    return FilePickerResult([
      PlatformFile(
        name: 'yawmi-readings.csv',
        path: file.path,
        size: file.lengthSync(),
      ),
    ]);
  }
}

void main() {
  setUp(() => FilePicker.platform = _CsvFixturePicker());

  testWidgets('Capture the rebuilt experience', (tester) async {
    final captureDirectory = Platform.environment['YAWMI_PREVIEW_DIR'];
    final capture = captureDirectory != null && captureDirectory.isNotEmpty;
    final conditionsOnly =
        capture && Platform.environment['YAWMI_CAPTURE_CONDITIONS_ONLY'] == '1';
    final dailyOnly =
        capture && Platform.environment['YAWMI_CAPTURE_DAILY_ONLY'] == '1';
    final notificationsOnly =
        capture &&
        Platform.environment['YAWMI_CAPTURE_NOTIFICATIONS_ONLY'] == '1';
    final followUpsOnly =
        capture && Platform.environment['YAWMI_CAPTURE_FOLLOW_UPS'] == '1';
    final updateOnly =
        capture && Platform.environment['YAWMI_CAPTURE_UPDATES'] == '1';
    if (capture) {
      for (final (family, assets) in [
        (
          'PlexArabic',
          [
            'assets/IBMPlexSansArabic-Regular.ttf',
            'assets/IBMPlexSansArabic-Bold.ttf',
          ],
        ),
        ('Manrope', ['assets/Manrope.ttf']),
        ('Tajawal', ['assets/Tajawal-Regular.ttf', 'assets/Tajawal-Bold.ttf']),
        ('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']),
      ]) {
        final loader = FontLoader(family);
        for (final asset in assets) {
          loader.addFont(rootBundle.load(asset));
        }
        await loader.load();
      }
      await tester.pump();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();
    Future<void> take(String name) async {
      if (captureDirectory == null || captureDirectory.isEmpty) return;
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final shot = await boundary.toImage(pixelRatio: 2);
        final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
        final into = Directory(captureDirectory);
        await into.create(recursive: true);
        await File(
          into.path + '/' + name + '.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        shot.dispose();
      });
    }

    Future<void> frames(String name, int start, int stop) async {
      for (var i = start; i <= stop; i++) {
        await tester.pump(const Duration(milliseconds: 36));
        await take(name + '_' + i.toString().padLeft(2, '0'));
      }
    }

    Finder tab(String label) =>
        find.descendant(of: find.byType(Dock), matching: find.text(label));
    Finder cardTitle(String title) => find.byWidgetPredicate(
      (widget) => widget is ControlCard && widget.title == title,
    );
    Future<void> open(Finder target, {String? shot, String? animation}) async {
      final active = target.first;
      await tester.ensureVisible(active);
      await tester.pumpAndSettle();
      if (capture && animation != null) {
        final pad = await tester.startGesture(tester.getCenter(active));
        await frames(animation, 0, 2);
        await pad.up();
        await frames(animation, 3, 25);
      } else {
        await tester.tap(active);
      }
      await tester.pumpAndSettle();
      if (shot != null) await take(shot);
    }

    Future<void> closeModal() async {
      final modal = find.byType(BottomSheet).last;
      Navigator.of(tester.element(modal)).pop();
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      Navigator.of(tester.element(find.byType(AppBar).last)).pop();
      await tester.pumpAndSettle();
    }

    Future<void> recordPressure(String language, String saveLabel) async {
      await tester.enterText(
        find.byKey(const ValueKey(('systolic', 'mmHg'))),
        '118',
      );
      await tester.enterText(
        find.byKey(const ValueKey(('diastolic', 'mmHg'))),
        '76',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await take('pressure-filled-$language');
      await open(
        find.text(saveLabel),
        shot: 'pressure-saved-$language',
        animation: 'pressure_save_$language',
      );
    }

    final at = DateTime.now();
    final journal = MemoryJournal(
      freshState()
        ..['language'] = 'ar'
        ..['theme'] = 'light'
        ..['waterGoal'] = 1500
        ..['todayCompact'] = true
        ..['enabled'] = ['water', 'pressure', 'glucose', 'medicine']
        ..['entries'] = [
          reading('w', 'water', at, 500, 'mL'),
          reading('gluc1', 'glucose', at, 104, 'mg/dL')
            ..['context'] = 'fasting',
          reading(
            'gluc2',
            'glucose',
            at.subtract(const Duration(days: 1)),
            112,
            'mg/dL',
          ),
          reading('pressure1', 'pressure', at, 118, 'mmHg')
            ..['values'] = {'systolic': 118, 'diastolic': 76},
          reading(
            'pressure2',
            'pressure',
            at.subtract(const Duration(days: 1)),
            123,
            'mmHg',
          )..['values'] = {'systolic': 123, 'diastolic': 79},
        ]
        ..['meds'] = [
          {
            'id': 'sample-med',
            'name': 'جرعة تجريبية',
            'revision': 1,
            'times': [480, 1260],
            'start': dayKey(at),
            'days': allDays,
          },
        ],
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Yawmi(
          journal,
          showDedication:
              capture &&
              !conditionsOnly &&
              !dailyOnly &&
              !notificationsOnly &&
              !followUpsOnly &&
              !updateOnly,
        ),
      ),
    );
    if (updateOnly) {
      await journal.change((d) => d['stage'] = 3);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(platform, (call) async {
        if (call.method != 'updateStatus') return null;
        return {
          'enabled': true,
          'automatic': true,
          'installed': '1.5.0',
          'version': '1.6.0',
          'size': 66034996,
          'notes':
              '• تحسين عرض الساعة في المساحات الصغيرة.\n• ضبط مواعيد التنبيهات.',
          'progress': -1,
          'checkedAt': at.millisecondsSinceEpoch,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(platform, null));
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(AppBar).first));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const YawmiUpdateCenter(ar: true),
        ),
      );
      await tester.pumpAndSettle();
      await take('updates-ar');
      expect(find.text('نزّل التحديث'), findsOneWidget);
      await back();
      await open(tab('المزيد'));
      await open(find.text('الاستيراد والتصدير'), shot: 'data-ar');
      expect(tester.takeException(), isNull);
      return;
    }
    if (followUpsOnly) {
      await journal.change((d) {
        d['stage'] = 3;
        final med = rows(d['meds']).single;
        d['meds'] = [
          {
            ...med,
            'name': 'دواء تجريبي',
            'inventory': MedicationStock(
              cycle: 'preview',
              countedAt: at,
              count: 4,
              perDose: 1,
              threshold: 5,
              notify: true,
              repeatDays: 3,
            ).toRow(),
            'expiry': {
              'date': dayKey(shiftCalendarDate(at, 5)),
              'minute': 540,
              'leads': [7, 1, 0],
              'armed': true,
            },
          },
        ];
        d['followUps'] = [
          {
            'id': 'sample-lab',
            'name': 'إعادة تحليل تراكمي',
            'tracker': 'lab',
            'alert': {
              'date': dayKey(shiftCalendarDate(at, 13)),
              'minute': 540,
              'leads': [7, 1, 0],
              'armed': true,
              'repeat': {'count': 1, 'minutes': 20},
            },
          },
        ];
      });
      await tester.pumpAndSettle();
      await take('today-ar');
      await open(find.byTooltip('التذكيرات والتنبيهات'), shot: 'reminders-ar');
      await open(find.text('خزانة الأدوية'), shot: 'cabinet-ar');
      await open(
        find.text('صلاحية الدواء'),
        shot: 'expiry-ar',
        animation: 'expiry_open',
      );
      await closeModal();
      await back();
      await open(find.text('المتابعات القادمة'), shot: 'follow-ups-ar');
      await open(find.text('إعادة تحليل تراكمي'));
      await tester.scrollUntilVisible(
        find.text('إمتى تحب تتنبّه؟'),
        225,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('إمتى تحب تتنبّه؟'));
      await tester.pumpAndSettle();
      await take('follow-up-alerts-ar');
      await closeModal();
      await back();
      await back();
      await open(find.byTooltip('استوديو الويدجت'));
      await open(find.text('ساعة ومتابعات'), shot: 'widget-ar');
      await back();
      await back();
      await journal.change((d) {
        d['language'] = 'en';
        d['theme'] = 'dark';
        d['meds'] = [
          {...rows(d['meds']).single, 'name': 'Sample medication'},
        ];
        d['followUps'] = [
          {...rows(d['followUps']).single, 'name': 'Lab recheck'},
        ];
      });
      await tester.pumpAndSettle();
      await take('today-en-dark');
      await open(find.byTooltip('Reminders & notifications'));
      await open(find.text('Medicine cabinet'), shot: 'cabinet-en-dark');
      expect(tester.takeException(), isNull);
      return;
    }
    if (notificationsOnly) {
      await journal.change((d) => d['stage'] = 3);
      await tester.pumpAndSettle();
      await open(
        find.byTooltip('التذكيرات والتنبيهات'),
        shot: 'reminder-center-ar',
      );
      await open(find.text('المياه خلال اليوم'), shot: 'water-schedule-ar');
      await open(find.text('فعّل جدول المياه'));
      final preview = find.text('معاينة المواعيد');
      if (preview.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          preview,
          200,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await take('water-times-ar');
      await open(find.text('احفظ جدول المياه'));
      await back();
      await open(find.byTooltip('استوديو الويدجت'));
      await open(find.text('ساعة ومتابعات'), shot: 'widget-corners-ar');
      expect(tester.takeException(), isNull);
      return;
    }
    if (dailyOnly) {
      await journal.change((d) => d['stage'] = 3);
      await tester.pumpAndSettle();
      await take('daily-today-ar');
      final weekly = find.text('ملخّص الأسبوع');
      await tester.scrollUntilVisible(
        weekly,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await open(weekly, shot: 'daily-week-ar');
      await back();
      await journal.change((d) {
        d['language'] = 'en';
        d['theme'] = 'dark';
      });
      await tester.pumpAndSettle();
      final weekEn = find.text('Weekly review');
      if (weekEn.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          weekEn,
          160,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await open(weekEn, shot: 'daily-week-en');
      expect(tester.takeException(), isNull);
      return;
    }
    if (conditionsOnly) {
      await journal.change((d) {
        d.clear();
        d.addAll(freshState()..['language'] = 'ar');
      });
      await tester.pumpAndSettle();
      await open(find.text('ابدأ'), shot: 'choose-conditions-ar');
      await open(find.byKey(const ValueKey('setup-condition-diabetes2')));
      await open(
        find.byKey(const ValueKey('setup-condition-hypertension')),
        shot: 'selected-conditions-ar',
      );
      await open(find.text('تابع للمتابعات'), shot: 'suggested-trackers-ar');
      await journal.change((d) {
        d['stage'] = 1;
        d['language'] = 'en';
        d['theme'] = 'dark';
      });
      await tester.pumpAndSettle();
      await take('selected-conditions-en-dark');
      expect(tester.takeException(), isNull);
      return;
    }
    if (capture) {
      await frames('dedication_intro', 0, 53);
      expect(find.text('صدقة جارية'), findsOneWidget);
      await take('dedication');
      await open(
        find.text('اضغط في أي مكان للمتابعة'),
        animation: 'dedication_exit',
      );
      if (Platform.environment['YAWMI_CAPTURE_SPLASH_ONLY'] == '1') {
        expect(find.text('صدقة جارية'), findsNothing);
        expect(tester.takeException(), isNull);
        return;
      }
      final originalCards = strings(journal.state['enabled']);
      await journal.change((d) {
        d['stage'] = 1;
        d['enabled'] = ['peak_flow', 'pain', 'symptom', 'sleep'];
        d['conditions'] = [
          {
            'id': 'asthma',
            'name': 'Asthma',
            'links': ['peak_flow', 'symptom'],
          },
          {
            'id': 'migraine',
            'name': 'Migraine',
            'links': ['pain', 'symptom'],
          },
        ];
      });
      await tester.pumpAndSettle();
      await take('setup-ar');
      await journal.change((d) => d['theme'] = 'dark');
      await tester.pumpAndSettle();
      await take('setup-ar-dark');
      await journal.change((d) => d['theme'] = 'light');
      await tester.pumpAndSettle();
      await open(find.text('اختار من مكتبة الحالات'));
      await tester.pumpAndSettle();
      await take('condition-library-ar');
      await back();
      await open(
        find.text('تابع للمتابعات'),
        shot: 'setup-trackers-ar',
        animation: 'setup_trackers',
      );
      await tester.tap(find.text('عاين صفحة اليوم'));
      await tester.pumpAndSettle();
      await take('setup-review-ar');
      await open(
        cardTitle('الربو'),
        shot: 'condition-customize-ar',
        animation: 'condition_open',
      );
      await back();
      await open(find.text('عدّل البطاقات'), shot: 'tracker-library-ar');
      await back();
      await journal.change((d) {
        d['stage'] = 0;
        d['conditions'] = [];
        d['enabled'] = originalCards;
      });
    }
    await tester.pumpAndSettle();
    await take('welcome');
    await journal.change((s) => s['stage'] = 3);
    await tester.pumpAndSettle();
    await take('today-ar');
    if (capture) {
      await open(find.text('بطاقات'));
      await tester.scrollUntilVisible(
        find.byTooltip('اختار التاريخ'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await take('today-detailed-ar');
      await open(find.text('مختصر'));
      final originalRecents = strings(journal.state['recent']);
      await journal.change((d) {
        d['hidden'] = ['pressure', medicineCard];
        d['recent'] = ['sleep', 'pressure', 'glucose'];
      });
      await tester.pumpAndSettle();
      await open(find.byTooltip('إضافة'), shot: 'quick-selected-ar');
      expect(
        tester
            .widgetList<ControlCard>(
              find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(ControlCard),
              ),
            )
            .map((card) => card.title),
        ['سكر الدم', 'المياه'],
      );
      await closeModal();
      await journal.change((d) {
        d['hidden'] = <String>[];
        d['recent'] = originalRecents;
      });
      await tester.pumpAndSettle();
      await open(
        find.byTooltip('إضافة'),
        shot: 'quick-log-ar',
        animation: 'quick_open',
      );
      await open(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: cardTitle('سكر الدم'),
        ),
        shot: 'entry-form-ar',
      );
      await tester.enterText(find.byType(TextFormField).first, '116');
      await frames('entry_signal', 0, 14);
      await tester.pumpAndSettle();
      await open(find.text('قبل الأكل'));
      await open(
        find.text('احفظ الإدخال'),
        shot: 'entry-saved-ar',
        animation: 'entry_save',
      );
      expect(
        entriesFor(journal.state, 'glucose').any(
          (e) => e['values']['value'] == 116 && e['context'] == 'before meal',
        ),
        isTrue,
      );
      await open(cardTitle('ضغط الدم'), shot: 'pressure-form-ar');
      await recordPressure('ar', 'احفظ الإدخال');
      await open(find.text('رتّب'), shot: 'arrange-today-ar');
      await back();
    }
    final glucoseCard = find.text('سكر الدم');
    if (glucoseCard.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        glucoseCard,
        160,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(glucoseCard);
    await tester.pumpAndSettle();
    await tester.tap(glucoseCard);
    if (captureDirectory != null && captureDirectory.isNotEmpty) {
      await frames('reading', 0, 23);
    }
    await tester.pumpAndSettle();
    await take('reading-ar');
    if (capture) {
      await open(
        find.byTooltip('القراءة السابقة'),
        shot: 'reading-scrub-ar',
        animation: 'chart_scrub',
      );
      final details = find.byType(BottomSheet).last;
      final detailScroll = find
          .descendant(of: details, matching: find.byType(Scrollable))
          .first;
      final day = find.descendant(
        of: details,
        matching: find.widgetWithText(ChoiceChip, 'اليوم'),
      );
      await tester.scrollUntilVisible(day, -180, scrollable: detailScroll);
      await open(day);
      final compare = find.text('قارن بالفترة السابقة');
      await tester.scrollUntilVisible(compare, 170, scrollable: detailScroll);
      await open(compare, animation: 'reading_compare');
      await tester.scrollUntilVisible(
        find.text('الفترة السابقة'),
        130,
        scrollable: detailScroll,
      );
      await tester.pumpAndSettle();
      await take('comparison-ar');
    }
    await tester.tap(find.byTooltip('إعدادات المتابعة'));
    await tester.pumpAndSettle();
    await take('glucose-settings');
    await back();
    await back();
    await open(find.byTooltip('سجّل المياه'));
    await take('water_00');
    await tester.tap(find.text('500'));
    await frames('water', 1, 12);
    await tester.tap(find.text('سجّل كوب'));
    await frames('water', 13, 44);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('تراجع'));
    await frames('water', 45, 73);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زوّد الكمية'));
    await tester.pumpAndSettle();
    await take('hydration');
    await tester.tap(find.byTooltip('إعدادات المتابعة'));
    await tester.pumpAndSettle();
    await take('water-settings');
    await back();
    await back();
    if (captureDirectory != null && captureDirectory.isNotEmpty) {
      await journal.change(
        (d) => d['enabled'] = [
          ...strings(d['enabled']),
          'sleep',
          'pulse',
          'peak_flow',
          'activity',
        ],
      );
      await tester.pumpAndSettle();
    }
    if (capture) {
      await open(tab('السجل'), shot: 'history-ar', animation: 'tab_history');
      await tester.enterText(find.byType(TextField), '116');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await take('report-filtered-ar');
      await open(find.byTooltip('مشاركة تقرير'), shot: 'report-preview-ar');
      await open(
        find.text('ملخّص زيارة في صفحة واحدة'),
        shot: 'report-summary-ar',
        animation: 'report_summary_ar',
      );
      await back();
      await tester.enterText(find.byType(TextField), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await open(tab('روتيني'), shot: 'routine-ar', animation: 'tab_routine');
      await open(tab('المزيد'), shot: 'settings-ar', animation: 'tab_more');
      await tester.scrollUntilVisible(
        find.text('عن التطبيق'),
        210,
        scrollable: find.byType(Scrollable).first,
      );
      await open(
        find.text('عن التطبيق'),
        shot: 'about-ar',
        animation: 'about_open',
      );
      await back();
      await open(tab('اليوم'));
      await journal.change(
        (d) => d['order'] = ['glucose', 'water', 'medicine'],
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('استوديو الويدجت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ابدأ بالتركيبة المقترحة'));
    await tester.pumpAndSettle();
    await take('widget-wide');
    final studioScroll = find.byType(Scrollable).first;
    final resizePanel = find.text('جرّب تغيير الحجم');
    final wSlider = find.byKey(const ValueKey('widget-preview-width'));
    final hSlider = find.byKey(const ValueKey('widget-preview-height'));
    await open(resizePanel);
    Future<void> resize(Size size, {String? shot}) async {
      await tester.scrollUntilVisible(
        resizePanel,
        -185,
        scrollable: studioScroll,
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(wSlider).onChanged!(size.width);
      tester.widget<Slider>(hSlider).onChanged!(size.height);
      if (capture && shot == 'widget-dashboard') {
        await frames('widget-resize', 0, 16);
      }
      await tester.pumpAndSettle();
      if (shot != null) await take(shot);
    }

    await resize(const Size(166, 136), shot: 'studio_00');
    await resize(const Size(332, 224), shot: 'studio');
    await open(find.text('الشكل'));
    final readingsBoard = find.text('لوحة القياسات');
    await tester.scrollUntilVisible(
      readingsBoard,
      190,
      scrollable: studioScroll,
    );
    await open(readingsBoard, shot: 'widget-board');
    if (capture) {
      await resize(const Size(332, 136));
      await open(find.text('ساعة وتاريخ'), animation: 'widget_clock');
      await open(
        find.text('3 في الصف'),
        shot: 'widget-clock-three-ar',
        animation: 'widget_three',
      );
      final preview = tester.widget<SceneArt>(find.byType(SceneArt).last);
      expect(preview.scene.clock, isTrue);
      expect(preview.scene.grid.first.cards.length, 3);
      await open(find.text('ساعة وتاريخ'));
      await open(find.text('أعمدة تلقائية'));
    }
    await resize(const Size(166, 136));
    final quick = find.text('بطاقة سريعة');
    await tester.scrollUntilVisible(quick, 190, scrollable: studioScroll);
    await open(quick, shot: 'widget-quick');
    if (capture) {
      final widgetScroll = studioScroll;
      for (final (size, shot) in [
        (const Size(246, 67), 'widget-strip'),
        (const Size(86, 222), 'widget-tower'),
        (const Size(168, 310), 'widget-portrait'),
        (const Size(332, 314), 'widget-grid'),
        (const Size(332, 472), 'widget-dashboard'),
      ]) {
        await resize(size, shot: shot);
      }
      await tester.scrollUntilVisible(
        find.text('داكن'),
        240,
        scrollable: widgetScroll,
      );
      await open(find.text('داكن'));
      await tester.scrollUntilVisible(
        resizePanel,
        -240,
        scrollable: widgetScroll,
      );
      await tester.pumpAndSettle();
      await take('widget-dashboard-dark');
      await tester.scrollUntilVisible(
        find.text('حسب النظام'),
        240,
        scrollable: widgetScroll,
      );
      await open(find.text('حسب النظام'));
      await open(find.text('البطاقات'));
      final customize = find.text('تخصيص كل بطاقة');
      await tester.scrollUntilVisible(customize, 180, scrollable: widgetScroll);
      await tester.pumpAndSettle();
      final card = find.descendant(
        of: find.byType(ControlCard),
        matching: find.text('المياه'),
      );
      await tester.scrollUntilVisible(card, 140, scrollable: widgetScroll);
      await open(card, shot: 'widget-card-ar');
      await back();
      await open(find.text('الخصوصية'), shot: 'widget-privacy-ar');
    }
    await back();
    await back();
    if (capture) {
      await journal.change((s) {
        s['order'] = <String>[];
        s['theme'] = 'dark';
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('اختار التاريخ'),
        -270,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await take('today-ar-dark');
      await open(cardTitle('ضغط الدم'), shot: 'pressure-form-ar-dark');
      await back();
    }
    await journal.change((s) {
      s['theme'] = 'dark';
      s['language'] = 'en';
    });
    await tester.pumpAndSettle();
    await take('today-en-dark');
    if (capture) {
      await open(cardTitle('Blood pressure'), shot: 'pressure-form-en');
      await recordPressure('en', 'Save entry');
      await open(find.byTooltip('Widget Studio'));
      await open(find.text('Use suggested layout'), shot: 'widget-default-en');
      await open(find.text('Preview resizing'));
      tester
          .widget<Slider>(find.byKey(const ValueKey('widget-preview-width')))
          .onChanged!(160);
      tester
          .widget<Slider>(find.byKey(const ValueKey('widget-preview-height')))
          .onChanged!(136);
      await tester.pumpAndSettle();
      await take('widget-small-en');
      await back();
      await back();
    }
    await tester.tap(tab('History'));
    await tester.pumpAndSettle();
    await take('history-en-dark');
    if (capture) {
      await open(
        find.byTooltip('Filter history'),
        shot: 'history-filter-en',
        animation: 'history_filter',
      );
      await closeModal();
      await tester.enterText(find.byType(TextField), '116');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await take('report-filtered-en');
      await open(find.byTooltip('Share report'), shot: 'report-preview-en');
      await open(
        find.text('One-page visit summary'),
        shot: 'report-summary-en',
        animation: 'report_summary_en',
      );
      await back();
    }
    await tester.tap(tab('Routine'));
    await tester.pumpAndSettle();
    await take('routine-en-dark');
    if (capture) {
      await open(
        find.text('جرعة تجريبية'),
        shot: 'dose-confirm-en',
        animation: 'dose_open',
      );
      await open(
        find.text('Mark taken'),
        shot: 'dose-complete-en',
        animation: 'dose_done',
      );
      await tester.scrollUntilVisible(find.byTooltip('Add medication'), -240);
      await open(find.byTooltip('Add medication'), shot: 'medicine-form-en');
      await back();
      await open(find.text('Notifications are off'), shot: 'notifications-en');
      await tester.scrollUntilVisible(find.text('Quiet hours'), 220);
      await open(find.text('Quiet hours'), shot: 'quiet-hours-en');
      await open(find.text('During quiet hours'));
      await open(
        find.text('Silent notification'),
        animation: 'quiet_band',
        shot: 'quiet-window-en',
      );
      await back();
      await tester.scrollUntilVisible(find.byTooltip('New reminder'), 220);
      await open(find.byTooltip('New reminder'), shot: 'reminder-form-en');
      await back();
    }
    await tester.scrollUntilVisible(find.text('Adaptive routine'), 180);
    await open(find.text('Adaptive routine'), shot: 'adaptive-en-dark');
    await back();
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await take('settings-en-dark');
    if (capture) {
      await open(find.text('Conditions and trackers'), shot: 'conditions-en');
      await open(
        find.text('Create a custom tracker'),
        shot: 'custom-tracker-en',
      );
      await closeModal();
      await back();
      await tester.tap(find.text('Import & export'));
      await tester.pumpAndSettle();
      await take('data-center-en-dark');
      await open(
        find.text('Save an encrypted backup'),
        shot: 'backup-password-en',
      );
      await open(find.text('Cancel'));
      await open(find.text('Import readings from CSV'));
      for (
        var attempt = 0;
        attempt < 16 && find.text('Review new readings').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('Review new readings'), findsOneWidget);
      expect(find.text('New readings · 3'), findsOneWidget);
      await take('csv-preview-en');
    }
    if (capture) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Import from welcome leads back to condition setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journal = MemoryJournal(freshState()..['language'] = 'en');
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import data or restore a backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import readings from CSV'));
    final add = find.text('Add to journal');
    for (var attempt = 0; attempt < 25 && add.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(journal.state['stage'], 1);
    expect(rows(journal.state['entries']), hasLength(3));
    expect(find.text('Choose your health conditions'), findsOneWidget);
    expect(find.byType(Dock), findsNothing);
  });
}
