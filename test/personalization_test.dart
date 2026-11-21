import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/design.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/legacy_import.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/transfer.dart';
import 'package:yawmi/widgets.dart';

import 'yawmi_test.dart' show MemoryJournal;

Uint8List _csv(List<List<String>> rows) => Uint8List.fromList(
  utf8.encode(
    '\uFEFF' +
        [
          'id,measured_at_iso,entered_at_iso,kind,value_original,second_value,unit,context,status,note,source,planned_at_iso',
          for (final row in rows)
            row.map((v) => '"' + v.replaceAll('"', '""') + '"').join(','),
        ].join('\r\n'),
  ),
);

void main() {
  test(
    'Java backup preserves legacy data, dates, formulas and flexible schedules',
    () async {
      // Synthetic schema-1 file encrypted with the old app's Java BackupCipher.
      final bytes = await File(
        'test/fixtures/old-diabetes-synthetic.yawmi',
      ).readAsBytes();
      expect(isLegacyBackup(bytes), isTrue);
      await expectLater(
        readLegacy(bytes, password: 'incorrect password'),
        throwsA(anything),
      );
      final imported = await readLegacy(bytes, password: 'تجربة-wasM-123');
      expect(imported.unscheduled, 1);
      final state = freshState()..['enabled'] = ['note'];
      final csv = await readLegacy(
        _csv([
          [
            'glucose-1',
            '2026-03-01T09:30:00Z',
            '2026-03-01T09:31:00Z',
            'glucose',
            '6.2',
            '',
            'mmol/L',
            'before',
            '',
            'قبل الفطار',
            'local',
            '',
          ],
          [
            'dose-1',
            '2026-03-01T09:30:00Z',
            '',
            'dose',
            '1',
            '',
            '',
            '',
            'taken',
            'Sample medication · 1',
            'local',
            '2026-03-01T09:25:00Z',
          ],
          [
            'csv-only',
            '2026-03-01T09:30:00Z',
            '',
            'meal',
            '42',
            '0',
            'g',
            'lunch',
            '',
            "'=sample, \"two\"\nSecond line",
            'local',
            '',
          ],
        ]),
      );
      csv.appendTo(state, addCards: false);
      expect(cardPlan(state), ['note']);
      expect(imported.additions(state), {'entries': 6, 'meds': 2, 'doses': 0});
      imported.appendTo(state, preferences: true);
      imported.appendTo(state);
      expect(imported.additions(state), {'entries': 0, 'meds': 0, 'doses': 0});
      final glucose = entriesFor(state, 'glucose').single;
      expect(glucose['at'], '2026-03-01T09:30:00.000Z');
      expect(glucose['unit'], 'mmol/L');
      expect(glucose['values']['value'], 6.2);
      expect(glucose['context'], 'before meal');
      expect(entriesFor(state, 'pressure').single['values'], {
        'systolic': 119.0,
        'diastolic': 77.0,
      });
      expect(entriesFor(state, 'question').single['legacyUndated'], isTrue);
      expect(entriesFor(state, 'sleep').single['values']['value'], 8.0);
      expect(
        entriesFor(state, 'meal').map((e) => e['note']),
        contains('=sample, "two"\nSecond line'),
      );
      expect(
        entriesFor(state, 'meal').map((e) => e['legacyCarbs']),
        everyElement(42),
      );
      final med = rows(state['meds']).first;
      final interval = rows(state['meds']).last;
      final dose = rows(state['doses']).single;
      expect(dose['medicine'], med['id']);
      expect(doseEvent(state, dose['legacyDue'])?['status'], 'taken');
      expect(med['times'], [480, 860]);
      expect(med['days'], [1, 5]);
      expect(med['notify'], isFalse);
      expect(interval['legacySchedule']['intervalHours'], 18);
      expect(interval['times'], isEmpty);
      expect(trackerView(state, trackerFor(state, 'glucose')!).days, 0);
      expect(defaultWaterCup(state), 300);
      final now = DateTime.parse('2026-11-20T11:00:00Z').toLocal();
      expect(summaryFor(state, 'glucose', false, now).value, '6.2');
      expect(summaryFor(state, 'water', false, now).value, '0');
      final backup = await makeBackup(state, 'new test password');
      final restored = await openBackup(backup, 'new test password');
      expect(restored['entries'], state['entries']);
      expect(restored['doses'], state['doses']);
    },
  );

  test(
    'Widget scope inherits Today and each widget keeps independent controls',
    () async {
      final now = DateTime(2026, 11, 20, 12);
      final state = freshState()
        ..['startSection'] = 'doses'
        ..['enabled'] = ['glucose', 'water', 'peak_flow', 'symptom']
        ..['conditions'] = [
          {
            'id': 'asthma',
            'name': 'Asthma',
            'links': ['peak_flow', 'symptom'],
          },
        ]
        ..['entries'] = [
          {
            'id': 'p1',
            'tracker': 'peak_flow',
            'unit': 'L/min',
            'at': now.toIso8601String(),
            'created': now.toIso8601String(),
            'values': {'value': 345},
          },
        ];
      final scoped = widgetConfig(state)
        ..['condition'] = 'asthma'
        ..['cardOptions'] = {
          'peak_flow': {
            'show': true,
            'context': false,
            'unit': false,
            'action': 'add',
            'mode': 'average',
            'days': 1,
            'title': 'Peak flow log',
          },
        };
      final custom = widgetConfig(state, empty: true)
        ..['enabled'] = ['water']
        ..['cardOptions'] = {
          'water': {'action': 'cup'},
        };
      var scene = WidgetScene(state, scoped, false, 2, today: now);
      expect(scene.cards, ['peak_flow', 'symptom']);
      expect(scene.route('peak_flow'), 'add/peak_flow/asthma');
      expect(scene.title('peak_flow'), 'Peak flow log');
      expect(scene.card('peak_flow'), (value: '345', unit: '', context: ''));
      expect(scene.isDaily('peak_flow'), isTrue);
      expect(scene.card('symptom').value, '•••');
      state['hidden'] = ['symptom'];
      expect(scene.cards, ['peak_flow']);
      state['widgets'] = [scoped, custom];
      final restored = await openBackup(
        await makeBackup(state, 'portable test password'),
        'portable test password',
      );
      final layouts = rows(restored['widgets']);
      expect(restored['startSection'], 'doses');
      scene = WidgetScene(restored, layouts[0], false, 2, today: now);
      expect(scene.cards, ['peak_flow']);
      expect(scene.card('peak_flow').value, '345');
      expect(WidgetScene(restored, layouts[1], false, 2).cards, ['water']);
      expect(WidgetScene(restored, layouts[1], false, 2).route('water'), 'cup');
    },
  );

  testWidgets('Setup supports two unrelated conditions plus a manual tracker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 875);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journal = MemoryJournal(freshState()..['language'] = 'en');
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    expect(find.text('Import data or restore a backup'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(cardPlan(journal.state), isEmpty);
    await tester.tap(find.text('Choose from the condition library'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'asthma');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asthma'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'migraine');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ControlCard),
        matching: find.text('Headaches & migraine'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review trackers · 2'));
    await tester.pumpAndSettle();
    expect(
      cardPlan(journal.state),
      containsAll(['peak_flow', 'pain', 'symptom']),
    );
    expect(cardPlan(journal.state), isNot(contains('glucose')));
    expect(journal.state['stage'], 4);
    await tester.ensureVisible(find.text('Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(cardPlan(journal.state), contains('water'));
    await tester.ensureVisible(find.text('Preview Today'));
    await tester.tap(find.text('Preview Today'));
    await tester.pumpAndSettle();
    expect(find.text('Make it yours'), findsOneWidget);
    await tester.ensureVisible(find.text('Open Yawmi'));
    await tester.tap(find.text('Open Yawmi'));
    await tester.pumpAndSettle();
    expect(journal.state['stage'], 3);
    expect(rows(journal.state['conditions']), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  test(
    'One widget expands with its available space and keeps shortcut order',
    () {
      final ids = [
        'water',
        'peak_flow',
        'glucose',
        'pressure',
        'sleep',
        'activity',
        'pulse',
        'pain',
      ];
      final state = freshState()..['enabled'] = ids;
      final config = widgetConfig(state)
        ..['cardOptions'] = {
          'water': {'action': 'cup'},
          'glucose': {'action': 'add'},
        };
      for (final (i, capacity) in [1, 3, 4, 2, 3, 3, 7, 8].indexed) {
        final scene = WidgetScene(state, config, true, i);
        expect(scene.cards, ids.take(capacity));
        expect(scene.route('water'), 'cup');
        expect(scene.route('glucose'), 'add/glucose');
      }
      config['columns'] = 3;
      config['featured'] = false;
      expect(WidgetScene(state, config, true, 4).columns, 1);
      expect(WidgetScene(state, config, true, 7).columns, 3);
      expect(WidgetScene(state, config, true, 7).grid, hasLength(3));
      config['customColor'] = 0x185345;
      config['style'] = 4;
      config['largeValues'] = true;
      final saved = restoreWidgetDesigns(state, [config]).single;
      expect(saved['columns'], 3);
      expect(saved['customColor'], 0x185345);
      expect(saved['style'], 4);
      expect(saved['largeValues'], isTrue);
    },
  );

  testWidgets(
    'Condition search scrolls while keyboard and enlarged type are active',
    (tester) async {
      final platform = tester.binding.platformDispatcher;
      tester.view.physicalSize = const Size(824, 418);
      tester.view.devicePixelRatio = 1;
      platform.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(platform.clearTextScaleFactorTestValue);
      final state = freshState()
        ..['stage'] = 1
        ..['language'] = 'en'
        ..['theme'] = 'dark'
        ..['reduce'] = true
        ..['conditions'] = [
          {
            'id': 'asthma',
            'name': 'Asthma',
            'links': ['symptom'],
          },
        ];
      await tester.pumpWidget(Yawmi(MemoryJournal(state)));
      final open = find.text('Choose from the condition library');
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'diabetes');
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Diabetes'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Diabetes'), findsOneWidget);
    },
  );
}
