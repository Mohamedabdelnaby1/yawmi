import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/catalog.dart';
import 'package:yawmi/design.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/store.dart';
import 'package:yawmi/transfer.dart';
import 'package:yawmi/widgets.dart';

class MemoryJournal extends Journal {
  MemoryJournal(this.state);
  @override
  JournalRow state;
  @override
  Future<void> change(void Function(JournalRow draft) mutation) async {
    final next = jsonDecode(jsonEncode(state)) as JournalRow;
    mutation(next);
    state = next;
    notifyListeners();
  }
}

JournalRow reading(
  String id,
  String tracker,
  DateTime stamp,
  num value,
  String unit, {
  DateTime? entered,
}) => {
  'id': id,
  'tracker': tracker,
  'at': stamp.toUtc().toIso8601String(),
  'created': (entered ?? stamp).toUtc().toIso8601String(),
  'zone': stamp.timeZoneName,
  'values': {'value': value},
  'unit': unit,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Thirty-day glucose average rolls while water resets and adds amounts',
    () {
      final day = DateTime(2026, 11, 20, 18);
      final glucose = trackerFor(freshState(), 'glucose')!;
      final state = freshState()
        ..['entries'] = [
          reading('g1', 'glucose', day, 120, 'mg/dL')..['context'] = 'fasting',
          reading(
            'g2',
            'glucose',
            day.subtract(const Duration(days: 14)),
            5,
            'mmol/L',
          )..['context'] = 'fasting',
          reading(
            'g3',
            'glucose',
            day.subtract(const Duration(days: 29)),
            160,
            'mg/dL',
          )..['context'] = 'after meal',
          reading(
            'g4',
            'glucose',
            day.subtract(const Duration(days: 31)),
            900,
            'mg/dL',
          ),
          reading('w1', 'water', day, 250, 'mL'),
          reading('w2', 'water', day, .4, 'L'),
        ];
      expect(trackerView(state, glucose).days, 30);
      expect(summaryFor(state, 'glucose', false, day).value, '123.36');
      expect(summaryFor(state, 'water', false, day).value, '650');
      final tomorrow = day.add(const Duration(days: 1));
      expect(summaryFor(state, 'water', false, tomorrow).value, '0');
      expect(summaryFor(state, 'glucose', false, tomorrow).value, '105.05');
      state['doses'] = [
        {'id': 'recorded'},
      ];
      expect(summaryFor(state, 'glucose', false, day).value, '123.36');
      state['trackerViews'] = {
        'glucose': {'mode': 'average', 'days': 30, 'context': 'fasting'},
        'water': {'mode': 'total', 'days': 7},
      };
      (state['unitPrefs'] as Map)['water'] = 'L';
      expect(summaryFor(state, 'water', false, tomorrow).value, '0.65');
      expect(summaryFor(state, 'glucose', false, day).value, '105.05');
      final config = widgetConfig(state)
        ..['values'] = true
        ..['enabled'] = ['glucose', 'water'];
      final scene = WidgetScene(state, config, false, 2, today: day);
      expect(scene.card('glucose'), summaryFor(state, 'glucose', false, day));
      expect(scene.card('water'), summaryFor(state, 'water', false, day));
    },
  );

  test(
    'Reminder pattern counts distinct days and adjusts only within explicit weekly limits',
    () {
      final now = DateTime(2026, 11, 20, 20);
      final entries = [
        for (var i = 1; i <= 8; i++) ...[
          reading(
            'morning$i',
            'water',
            DateTime(2026, 11, 20 - i, i.isEven ? 6 : 10),
            250,
            'mL',
          ),
          reading(
            'evening$i',
            'water',
            DateTime(2026, 11, 20 - i, 20, 5),
            250,
            'mL',
          ),
        ],
      ];
      final pattern = learnedRoutine(entries, now, start: 1080, end: 1360)!;
      expect(pattern.minute, 1205);
      expect(pattern.matchedDays, 8);
      expect(learnedRoutine(entries.take(12).toList(), now), isNull);
      final old = {
        'learn': 'auto',
        'enabled': true,
        'flexible': true,
        'tracker': 'water',
        'minute': 1140,
        'low': 1100,
        'high': 1320,
      };
      expect(automaticReminderMinute(old, pattern.minute, now), 1155);
      expect(
        automaticReminderMinute(
          {...old, 'learn': 'suggest'},
          pattern.minute,
          now,
        ),
        isNull,
      );
      expect(
        automaticReminderMinute(
          {
            ...old,
            'changedAt': now
                .subtract(const Duration(days: 5))
                .toIso8601String(),
          },
          pattern.minute,
          now,
        ),
        isNull,
      );
      expect(
        automaticReminderMinute({...old, 'high': 1145}, pattern.minute, now),
        isNull,
      );
    },
  );

  testWidgets(
    'System Arabic and English and system appearance mirror every tab',
    (tester) async {
      final platform = tester.binding.platformDispatcher;
      addTearDown(platform.clearLocalesTestValue);
      addTearDown(platform.clearPlatformBrightnessTestValue);
      addTearDown(platform.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      platform.textScaleFactorTestValue = 1.35;
      final state = freshState()
        ..['stage'] = 3
        ..['reduce'] = true
        ..['enabled'] = ['water', 'pressure', 'glucose', 'medicine'];
      final journal = MemoryJournal(state);
      for (final dimensions in [const Size(375, 812), const Size(824, 418)]) {
        tester.view.physicalSize = dimensions;
        for (final ar in [true, false]) {
          platform.localesTestValue = [Locale(ar ? 'ar' : 'en')];
          for (final brightness in Brightness.values) {
            platform.platformBrightnessTestValue = brightness;
            await tester.pumpWidget(Yawmi(journal));
            await tester.pumpAndSettle();
            final dock = find.byType(Dock);
            for (final tab
                in ar
                    ? ['اليوم', 'السجل', 'روتيني', 'المزيد']
                    : ['Today', 'History', 'Routine', 'More']) {
              await tester.tap(
                find.descendant(of: dock, matching: find.text(tab)),
              );
              await tester.pumpAndSettle();
              final context = tester.element(dock);
              expect(Theme.of(context).brightness, brightness);
              expect(
                Directionality.of(context),
                ar ? TextDirection.rtl : TextDirection.ltr,
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );

  testWidgets(
    'Flexible reminder records one reason and can be undone from its history',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['reduce'] = true
          ..['entries'] = [
            for (var offset = 1; offset <= 8; offset++)
              reading(
                'w$offset',
                'water',
                DateTime(now.year, now.month, now.day - offset, 20),
                250,
                'mL',
              ),
          ]
          ..['reminders'] = [
            {
              'id': 'reminder',
              'name': 'Water check',
              'tracker': 'water',
              'enabled': true,
              'learn': 'auto',
              'flexible': true,
              'low': 1080,
              'high': 1320,
              'minute': 1140,
              'manualMinute': 1140,
              'revision': 1,
              'days': allDays,
            },
          ],
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(rows(journal.state['reminders']).single['minute'], 1155);
      expect(rows(journal.state['adaptiveHistory']).single['days'], 8);
      await tester.pump(const Duration(milliseconds: 200));
      expect(rows(journal.state['adaptiveHistory']), hasLength(1));
      await tester.tap(
        find.descendant(of: find.byType(Dock), matching: find.text('Routine')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Adaptive routine'), 180);
      await tester.tap(find.text('Adaptive routine'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Undo adjustment'), 180);
      await tester.ensureVisible(find.text('Undo adjustment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo adjustment'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(rows(journal.state['reminders']).single['minute'], 1140);
      expect(rows(journal.state['adaptiveHistory']).single['undone'], true);
    },
  );

  testWidgets(
    'Dose confirmation shows selected glucose average without resetting it',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now().subtract(const Duration(minutes: 2));
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['enabled'] = ['glucose', 'water', 'medicine']
          ..['entries'] = [
            reading('g1', 'glucose', now, 120, 'mg/dL'),
            reading(
              'g2',
              'glucose',
              now.subtract(const Duration(days: 11)),
              100,
              'mg/dL',
            ),
          ]
          ..['meds'] = [
            {
              'id': 'sample',
              'name': 'Sample dose',
              'start': '2020-01-01',
              'revision': 1,
              'days': allDays,
              'times': [480],
            },
          ],
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sample dose').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('110 mg/dL'), findsOneWidget);
      await tester.tap(find.text('Mark taken'));
      await tester.pumpAndSettle();
      expect(rows(journal.state['doses']).single['status'], 'taken');
      expect(
        summaryFor(journal.state, 'glucose', false, DateTime.now()).value,
        '110',
      );
    },
  );

  testWidgets(
    'Tracker settings save a chosen period and update the Today card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final at = DateTime.now().subtract(const Duration(minutes: 3));
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['enabled'] = ['glucose']
          ..['entries'] = [
            reading('recent', 'glucose', at, 140, 'mg/dL'),
            reading(
              'older',
              'glucose',
              at.subtract(const Duration(days: 19)),
              100,
              'mg/dL',
            ),
          ],
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      final glucoseCard = find.byKey(const ValueKey('today-card/glucose'));
      Finder inGlucoseCard(String label) =>
          find.descendant(of: glucoseCard, matching: find.text(label));
      expect(inGlucoseCard('120 mg/dL'), findsOneWidget);
      await tester.tap(inGlucoseCard('Blood glucose'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tracker settings'));
      await tester.pumpAndSettle();
      final settingsSheet = find.byType(BottomSheet).last;
      await tester.tap(
        find.descendant(of: settingsSheet, matching: find.text('14 days')),
      );
      await tester.pumpAndSettle();
      final save = find.text('Save settings');
      await tester.scrollUntilVisible(
        save,
        140,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        trackerView(journal.state, trackerFor(journal.state, 'glucose')!).days,
        14,
      );
      Navigator.of(tester.element(find.byType(AppBar).last)).pop();
      await tester.pumpAndSettle();
      expect(inGlucoseCard('140 mg/dL'), findsOneWidget);
    },
  );

  testWidgets(
    'Studio animates between small and large without clipping its cards',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'ar'
          ..['enabled'] = ['water', 'pressure', 'glucose', 'medicine'],
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('استوديو الويدجت'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ابدأ بالتركيبة المقترحة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جرّب تغيير الحجم'));
      await tester.pumpAndSettle();
      final width = find.byKey(const ValueKey('widget-preview-width'));
      final height = find.byKey(const ValueKey('widget-preview-height'));
      for (final size in [
        const Size(160, 130),
        const Size(330, 470),
        const Size(88, 220),
        const Size(245, 65),
      ]) {
        tester.widget<Slider>(width).onChanged!(size.width);
        tester.widget<Slider>(height).onChanged!(size.height);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SceneArt>(find.byType(SceneArt)).scene.viewport,
          size,
        );
      }
    },
  );

  test(
    'Search, merge shared pressure recommendation, keep pinned and hidden cards',
    () {
      final state = freshState()
        ..['conditions'] = [
          {'id': 'diabetes2', 'name': 'Diabetes'},
          {'id': 'hypertension', 'name': 'Hypertension'},
          {'id': 'heart-failure', 'name': 'Heart failure'},
        ]
        ..['enabled'] = [
          'medicine',
          'glucose',
          'pressure',
          'pressure',
          'weight',
          'pulse',
        ]
        ..['pinned'] = ['pressure']
        ..['hidden'] = ['weight'];
      expect(catalog.length, inInclusiveRange(25, 45));
      expect(catalog.map((e) => e.id).toSet(), hasLength(catalog.length));
      expect(
        catalog.where((e) => e.matches('سُكّر النوع التاني')).single.id,
        'diabetes2',
      );
      expect(recommendations(state, true)['pressure'], hasLength(2));
      expect(cardPlan(state), ['pressure', 'medicine', 'glucose', 'pulse']);
      final private = widgetConfig(state)..['pinned'] = ['glucose'];
      final scene = WidgetScene(state, private, true, 0);
      expect(scene.cards, ['glucose']);
      expect(scene.card('glucose').value, '•••');
      expect(
        WidgetScene(state, widgetConfig(state), true, 2).cards,
        hasLength(4),
      );
    },
  );

  test(
    'Mixed glucose units and water across midnight use independent dates',
    () {
      final now = DateTime(2026, 11, 20, 17);
      final state = freshState()
        ..['entries'] = [
          reading('g1', 'glucose', now, 100, 'mg/dL'),
          reading(
            'g2',
            'glucose',
            now.subtract(const Duration(days: 2)),
            5.55,
            'mmol/L',
          ),
          reading('w1', 'water', DateTime(2026, 11, 19, 23, 58), 400, 'mL'),
          reading('w2', 'water', DateTime(2026, 11, 20, 0, 1), 250, 'mL'),
        ];
      expect(
        average(
          entriesFor(state, 'glucose'),
          trackerFor(state, 'glucose')!,
          'mg/dL',
        ),
        closeTo(100, .1),
      );
      expect(readNumber('١٢٣٫٧٥'), 123.75);
      expect(waterTotal(state, now), 250);
      expect(waterTotal(state, DateTime(2026, 11, 19)), 400);
      removeRow(state, 'entries', 'w2');
      expect(waterTotal(state, now), 0);
    },
  );

  test('Dose ID is stable and archived medicine preserves action history', () {
    final now = DateTime(2026, 11, 20, 17);
    final state = freshState()
      ..['meds'] = [
        {
          'id': 'm',
          'name': 'Sample medication',
          'revision': 1,
          'times': [480, 1200],
          'days': allDays,
          'start': '2026-11-01',
        },
      ];
    final first = dosesOn(state, now).first;
    expect(first.id, 'm:1:2026-11-20:480');
    upsert(state, 'doses', {'id': first.id, 'status': 'taken'});
    expect(outstanding(state, now), hasLength(1));
    upsert(state, 'meds', {...first.medicine, 'archived': true});
    expect(dosesOn(state, now), isEmpty);
    expect(doseEvent(state, first.id)?['status'], 'taken');
  });

  test('Learning joins a midnight cluster and excludes late entry', () {
    final now = DateTime(2026, 11, 20, 12);
    final samples = [
      for (var i = 0; i < 7; i++)
        reading(
          'sample$i',
          'glucose',
          DateTime(2026, 11, 19 - i, i.isEven ? 23 : 0, i.isEven ? 57 : 5),
          100,
          'mg/dL',
        ),
      reading(
        'late',
        'glucose',
        DateTime(2026, 11, 10, 1),
        100,
        'mg/dL',
        entered: now,
      ),
    ];
    expect(proposeTime(samples.take(6).toList(), now, 100, 1320, 130), isNull);
    final proposal = proposeTime(samples, now, 100, 1320, 130);
    expect(proposal?.$2, 7);
    expect(circularDistance(proposal!.$1, 0), lessThan(10));
  });

  test(
    'Encrypted backup round trip and wrong password; CSV formula escaping',
    () async {
      final entry = reading('e', 'water', DateTime(2026, 11, 20), 250, 'mL')
        ..['note'] = '=1+1';
      final state = freshState()..['entries'] = [entry];
      final bytes = await makeBackup(state, 'sample secret');
      expect(utf8.decode(bytes), isNot(contains('"values"')));
      final restored = await openBackup(bytes, 'sample secret');
      expect(rows(restored['entries']).single, entry);
      await expectLater(
        openBackup(bytes, 'wrong secret'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        openBackup(Uint8List.fromList([1, 2]), 'sample secret'),
        throwsA(isA<FormatException>()),
      );
      expect(utf8.decode(makeCsv([entry], notes: true)), contains("\"'=1+1\""));
    },
  );

  test(
    'Layout learning raises one eligible card and keeps manual constraints',
    () {
      final now = DateTime(2026, 11, 20, 20);
      final state = freshState()
        ..['layoutLearning'] = 'suggest'
        ..['pinned'] = ['medicine']
        ..['hidden'] = ['pressure']
        ..['enabled'] = ['medicine', 'water', 'glucose', 'pressure']
        ..['entries'] = [
          for (var i = 0; i < 8; i++)
            reading(
              'g$i',
              'glucose',
              DateTime(2026, 11, 20 - i, 20),
              104,
              'mg/dL',
            ),
        ];
      final advice = proposeLayout(state, state, now);
      expect(advice?.tracker, 'glucose');
      expect(advice?.order, ['glucose', 'water']);
      state['order'] = advice!.order;
      expect(cardPlan(state), ['medicine', 'glucose', 'water']);
    },
  );

  test('Arabic PDF generates more than one page with embedded font', () async {
    final at = DateTime(2026, 11, 20);
    final entries = [
      for (var i = 0; i < 36; i++)
        reading('w$i', 'water', at, 250, 'mL')
          ..['note'] = 'ملاحظة تجريبية لسجل المياه',
    ];
    final pdf = await makePdf(
      freshState(),
      entries,
      true,
      '2026-11-14 – 2026-11-20',
      notes: true,
    );
    final raw = latin1.decode(pdf);
    expect(raw, startsWith('%PDF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, greaterThan(1));
    expect(raw, contains('/FontFile2'));
  });

  testWidgets('Arabic setup selects water and adds then undoes a custom cup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journal = MemoryJournal(freshState()..['language'] = 'ar');
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    expect(find.text('يومك الصحي،\nعلى طريقتك.'), findsOneWidget);
    await tester.tap(find.text('ابدأ'));
    await tester.pumpAndSettle();
    final withoutConditions = find.text('مفيش حالات محددة أتابعها');
    await tester.ensureVisible(withoutConditions);
    await tester.tap(withoutConditions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تابع للمتابعات'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('المياه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المياه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عاين صفحة اليوم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افتح يومي'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('سجّل أول قياس'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سجّل أول قياس'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('500'));
    await tester.tap(find.text('500'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('سجّل كوب'));
    await tester.tap(find.text('سجّل كوب'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('water-total'))).data,
      '500 mL',
    );
    expect(rows(journal.state['entries']), hasLength(1));
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(find.text('0 mL'), findsOneWidget);
    expect(rows(journal.state['entries']), isEmpty);
  });

  test(
    'Widget snapshots include a private automatic layout before any save',
    () {
      final date = DateTime(2026, 11, 21);
      final state = freshState()
        ..['enabled'] = ['glucose', 'water', 'pressure', 'sleep']
        ..['hidden'] = ['sleep']
        ..['entries'] = [reading('entry', 'glucose', date, 123, 'mg/dL')];
      final initial = widgetSnapshot(state, false, date);
      expect(initial['default'], automaticWidgetId);
      final cards = rows(initial['layouts'][automaticWidgetId]['cards']);
      expect(cards.map((card) => card['id']), ['glucose', 'water', 'pressure']);
      expect(cards.first['value'], '•••');
      expect(cards.first['points'], isEmpty);
      final saved = widgetConfig(state)..['values'] = true;
      state['widgets'] = [saved];
      state['widgetDefault'] = saved['id'];
      final updated = widgetSnapshot(state, false, date);
      expect(updated['default'], saved['id']);
      expect(
        rows(updated['layouts'][saved['id']]['cards']).first['value'],
        '123',
      );
    },
  );

  test(
    'Widget clock keeps three cards per row and survives backup restore',
    () {
      final state = freshState()
        ..['enabled'] = ['glucose', 'water', 'medicine', 'pressure'];
      final prefs = widgetConfig(state)
        ..['columns'] = 3
        ..['clock'] = true
        ..['clockLanguage'] = 'en'
        ..['clockFormat'] = '24';
      final restored = restoreWidgetDesigns(state, [prefs]).single;
      final wide = WidgetScene(state, restored, true, 1);
      expect(wide.topInset, wide.inset + wide.headerHeight);
      expect(wide.clock, isTrue);
      expect(wide.clockFormat, '24');
      expect(wide.clockLanguage, 'en');
      expect(wide.dateArabic, isFalse);
      expect(wide.dateLocale, 'en');
      expect(wide.grid.single.cards, ['glucose', 'water', 'medicine']);
      expect(wide.cropped, ['pressure']);
      final narrow = WidgetScene(state, restored, true, 4);
      expect(narrow.columns, 1);
      expect(narrow.clock, isTrue);
      expect(narrow.stackedClock, isTrue);
      restored['featured'] = true;
      final featured = WidgetScene(state, restored, true, 2);
      expect(featured.grid.map((row) => row.columns), [1, 3]);
      expect(featured.shortcut?.route, 'add/glucose');
      expect(featured.footer, isTrue);
      expect(wide.footer, isFalse);
      restored['showShortcut'] = false;
      final compact = restoreWidgetDesigns(state, [restored]).single;
      expect(WidgetScene(state, compact, true, 2).shortcut, isNull);
      expect(
        (widgetSnapshot(state, true, DateTime(2026, 11, 21))['layouts']
            as Map)['today']['shortcut']['route'],
        'add/glucose',
      );
    },
  );

  testWidgets(
    'Dedication can be read and dismissed with reduced motion enabled',
    (tester) async {
      await tester.pumpWidget(
        Yawmi(
          MemoryJournal(
            freshState()
              ..['language'] = 'ar'
              ..['reduce'] = true,
          ),
          showDedication: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('صدقة جارية'), findsOneWidget);
      expect(find.text('الرجاء الدعاء لهما بالمغفرة والرحمة'), findsOneWidget);
      expect(find.text('اضغط في أي مكان للمتابعة'), findsOneWidget);
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(find.text('صدقة جارية'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dedication completes automatically after three seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      Yawmi(
        MemoryJournal(freshState()..['language'] = 'ar'),
        showDedication: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 2779));
    expect(find.text('صدقة جارية'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.text('صدقة جارية'), findsNothing);
  });

  testWidgets('The dedication separates both names on a compact display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Yawmi(
        MemoryJournal(freshState()..['language'] = 'ar'),
        showDedication: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    final first = find.text('عبدالنبي عبدالفتاح');
    final second = find.text('فاطمه بدير عسل');
    expect(
      tester.getBottomLeft(first).dy + 16,
      lessThan(tester.getTopLeft(second).dy),
    );
    expect(find.text('اضغط في أي مكان للمتابعة').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Widget editor controls cards, elements and privacy independently',
    (tester) async {
      final journal = MemoryJournal(
        freshState()
          ..['language'] = 'en'
          ..['stage'] = 3
          ..['enabled'] = ['glucose', 'water'],
      );
      Future<void> tap(Finder item) async {
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tap(find.byTooltip('Widget Studio'));
      await tap(find.text('Use suggested layout'));
      WidgetScene preview() =>
          tester.widget<SceneArt>(find.byType(SceneArt).last).scene;
      expect(preview().cards, ['glucose', 'water']);
      expect(preview().card('glucose').value, '•••');
      await tap(find.text('Choose cards'));
      final water = find.byKey(const ValueKey('widget-visibility-water'));
      final pressure = find.byKey(const ValueKey('widget-visibility-pressure'));
      await tap(water);
      expect(tester.widget<SwitchListTile>(water).value, isFalse);
      final list = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(pressure, 120, scrollable: list);
      await tap(pressure);
      await tester.scrollUntilVisible(
        find.text('Include Today cards'),
        -120,
        scrollable: list,
      );
      await tap(find.text('Include Today cards'));
      await tap(find.text('Done'));
      expect(preview().cards, ['glucose', 'pressure']);

      await tap(find.text('Widget elements'));
      await tap(find.byKey(const ValueKey('widget-element-clock')));
      await tap(find.byKey(const ValueKey('widget-element-clockDate')));
      await tap(find.byKey(const ValueKey('widget-element-showShortcut')));
      await tap(find.byKey(const ValueKey('widget-element-showSettings')));
      await tap(find.text('Done'));
      expect(preview().clock, isTrue);
      expect(preview().clockDate, isFalse);
      expect(preview().toolbar, isFalse);
      expect(preview().footer, isFalse);

      await tap(find.text('Privacy'));
      await tap(find.text('Show tracker values'));
      expect(preview().card('glucose').value, '104');
      await tap(find.text('Save'));
      final layout = rows(journal.state['widgets']).single;
      expect(cardPlan(journal.state), ['glucose', 'water']);
      expect(cardPlan(journal.state, layout), ['glucose', 'pressure']);
      final snapshot =
          (widgetSnapshot(journal.state, false, DateTime.now())['layouts']
                  as Map)[layout['id']]
              as Map;
      expect(rows(snapshot['cards']).map((row) => row['id']), [
        'glucose',
        'pressure',
      ]);
      expect(snapshot['clockDate'], isFalse);
      expect(snapshot['showSettings'], isFalse);
      expect(snapshot.containsKey('shortcut'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Favorites rank quick entry and preserve the selected journal day',
    (tester) async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['enabled'] = ['water', 'glucose']
          ..['recent'] = ['water'],
      );
      Future<void> tap(Finder item) async {
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tap(find.byTooltip('Add'));
      await tap(find.byTooltip('Quick entry favorites'));
      await tap(find.widgetWithText(ControlCard, 'Blood glucose').last);
      await tap(find.text('Save'));
      expect(quickPins(journal.state), ['glucose']);

      await tap(find.byKey(ValueKey('journal-day/${dayKey(yesterday)}')));
      await tap(find.byTooltip('Add'));
      final sheet = find.byType(BottomSheet);
      final actions = find.descendant(
        of: sheet,
        matching: find.byType(ControlCard),
      );
      expect(
        tester.widgetList<ControlCard>(actions).map((action) => action.title),
        ['Blood glucose', 'Water'],
      );
      await tap(
        find.descendant(of: sheet, matching: find.text('Blood glucose')),
      );
      await tester.enterText(find.byType(TextFormField).first, '119');
      await tap(find.text('Save entry'));
      final row = rows(journal.state['entries']).single;
      expect(row['values']['value'], 119);
      expect(dayKey(eventTime(row)), dayKey(yesterday));
    },
  );

  testWidgets(
    'Tracker comparison uses the previous equal-length calendar window',
    (tester) async {
      final now = DateTime.now();
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['enabled'] = ['glucose']
          ..['entries'] = [
            reading(
              'current',
              'glucose',
              now.subtract(const Duration(days: 1)),
              123,
              'mg/dL',
            ),
            reading(
              'previous',
              'glucose',
              now.subtract(const Duration(days: 9)),
              96,
              'mg/dL',
            ),
          ],
      );
      Future<void> tap(Finder item) async {
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('today-card/glucose'));
      await tester.scrollUntilVisible(card, 180);
      await tap(
        find.descendant(of: card, matching: find.text('Blood glucose')),
      );
      final sheet = find.byType(BottomSheet);
      await tap(find.descendant(of: sheet, matching: find.text('7 days')));
      final scroll = find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first;
      final comparison = find.text('Compare with the previous period');
      await tester.scrollUntilVisible(comparison, 120, scrollable: scroll);
      await tap(comparison);
      final previous = find.text('Previous period');
      await tester.scrollUntilVisible(previous, 120, scrollable: scroll);
      expect(find.text('Period averages'), findsOneWidget);
      expect(find.text('96 mg/dL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Quick entry respects selected cards and opens a single tracker directly',
    (tester) async {
      final journal = MemoryJournal(
        freshState()
          ..['language'] = 'en'
          ..['stage'] = 3
          ..['enabled'] = ['glucose', 'water', 'pressure', 'medicine']
          ..['hidden'] = ['pressure', 'medicine']
          ..['recent'] = ['sleep', 'medicine', 'pressure', 'water'],
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final choices = find.descendant(
        of: sheet,
        matching: find.byType(ControlCard),
      );
      expect(
        tester.widgetList<ControlCard>(choices).map((card) => card.title),
        ['Water', 'Blood glucose'],
      );
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      await journal.change(
        (d) => d['hidden'] = ['pressure', 'medicine', 'water'],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('New entry'),
        ),
        findsOneWidget,
      );
      expect(find.text('What are you logging?'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '113');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final save = find.text('Save entry').hitTestable();
      expect(save, findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(rows(journal.state['entries']).single['values']['value'], 113);
    },
  );

  testWidgets(
    'Meal labels are saved per dose time without changing the reminder times',
    (tester) async {
      final today = DateTime.now();
      final journal = MemoryJournal(
        freshState()
          ..['language'] = 'en'
          ..['stage'] = 3
          ..['meds'] = [
            {
              'id': 'test-med',
              'name': 'Sample medicine',
              'revision': 1,
              'notify': true,
              'times': [480, 1200],
              'days': allDays,
              'start': dayKey(today),
            },
          ],
      );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tap(find.text('Routine'));
      final medicine = find.widgetWithText(ListTile, 'Sample medicine');
      await tester.scrollUntilVisible(
        medicine,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(medicine);
      await tap(find.byTooltip('Edit'));
      final firstTime = find.widgetWithText(ControlCard, '08:00');
      final formScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(firstTime, 180, scrollable: formScroll);
      await tap(firstTime);
      await tap(find.text('Breakfast'));
      await tap(find.text('Before meal'));
      await tap(find.text('Save meal selection'));
      expect(find.text('Breakfast · Before meal'), findsOneWidget);
      final count = find.text('Doses per scheduled day · 2');
      await tester.scrollUntilVisible(count, -120, scrollable: formScroll);
      expect(count, findsOneWidget);
      final save = find.text('Save medication');
      await tester.scrollUntilVisible(save, 180, scrollable: formScroll);
      await tap(save);

      final med = rows(journal.state['meds']).single;
      expect(med['revision'], 1);
      final doses = dosesOn(journal.state, today);
      expect(doses.map((dose) => dose.minute), [480, 1200]);
      expect(doses.first.mealSlot, {'meal': 'breakfast', 'relation': 'before'});
      expect(doses.last.mealSlot, isNull);
      expect(
        notificationRules(journal.state, false).map((rule) => rule['minute']),
        [480, 1200],
      );
    },
  );

  testWidgets(
    'About Yawmi shows the Facebook profile and opens its exact URL',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(platform, null));

      await tester.pumpWidget(
        Yawmi(
          MemoryJournal(
            freshState()
              ..['language'] = 'ar'
              ..['stage'] = 3,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();
      final about = find.text('عن التطبيق');
      await tester.scrollUntilVisible(
        about,
        230,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(about);
      await tester.pumpAndSettle();

      final profile = find.text('fb.com/mr.ropot');
      await tester.scrollUntilVisible(
        profile,
        170,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(profile, findsOneWidget);
      await tester.tap(profile);
      await tester.pumpAndSettle();

      final open = calls.singleWhere((call) => call.method == 'openFacebook');
      expect(open.arguments, 'https://fb.com/mr.ropot');
    },
  );

  testWidgets('Wide pages use reachable navigation in English and Arabic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journal = MemoryJournal(
      freshState()
        ..['stage'] = 3
        ..['language'] = 'en'
        ..['enabled'] = ['glucose', 'water', 'pressure', 'medicine'],
    );
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    await tester.tap(find.descendant(of: rail, matching: find.text('History')));
    await tester.pumpAndSettle();
    expect(find.text('Your health log'), findsOneWidget);
    await journal.change((state) => state['language'] = 'ar');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: rail, matching: find.text('روتيني')));
    await tester.pumpAndSettle();
    expect(find.text('مواعيدك'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RTL four-card scene and English small scene stay inside dimensions',
    (tester) async {
      final state = freshState()
        ..['enabled'] = ['medicine', 'glucose', 'pressure', 'water'];
      for (final (index, size) in widgetSizes.indexed) {
        for (final ar in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: SceneArt(
                    WidgetScene(
                      state,
                      widgetConfig(state)
                        ..['columns'] = 3
                        ..['clock'] = true,
                      ar,
                      index,
                      demo: true,
                      systemDark: ar,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
