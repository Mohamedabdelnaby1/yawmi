import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/reminder_schedule.dart';
import 'package:yawmi/transfer.dart';
import 'package:yawmi/widgets.dart';

import 'yawmi_test.dart' show MemoryJournal;

void main() {
  test(
    'Water slots stop at bedtime and carry selected wake days across midnight',
    () {
      expect(waterSlots(1320, 120, 60, 30), [
        (minute: 1350, shift: 0, untilSleep: 60),
        (minute: 1410, shift: 0, untilSleep: 60),
        (minute: 30, shift: 1, untilSleep: 60),
        (minute: 90, shift: 1, untilSleep: 30),
      ]);
      expect(waterSlots(420, 420, 60, 0), isEmpty);
      expect(waterSlots(420, 450, 90, 60), isEmpty);
      final state = freshState()
        ..['waterReminder'] = {
          'enabled': true,
          'wake': 1320,
          'sleep': 120,
          'interval': 60,
          'first': 30,
          'days': [7],
        };
      final alarms = notificationRules(state, false);
      expect(alarms.map((rule) => rule['days']), [
        [7],
        [7],
        [1],
        [1],
      ]);
      expect(alarms.last['maxDelay'], 30);
      expect(alarms.every((rule) => rule['type'] == 'habit'), isTrue);
    },
  );

  test(
    'Each clock has its own key and per-reminder repeat overrides the group',
    () {
      final state = freshState()
        ..['repeatPreferences'] = {
          'tracking': {'count': 2, 'minutes': 20},
        }
        ..['reminders'] = [
          {
            'id': 'pressure',
            'name': 'Blood pressure',
            'tracker': 'pressure',
            'minute': 480,
            'times': [480, 510, 480],
            'enabled': true,
            'days': allDays,
            'start': '2026-11-01',
          },
          {
            'id': 'glucose',
            'name': 'Blood glucose',
            'tracker': 'glucose',
            'minute': 520,
            'enabled': true,
            'days': allDays,
            'repeat': {'count': 0, 'minutes': 15},
          },
        ];
      final rules = notificationRules(state, false);
      expect(rules.map((r) => r['id']), [
        'pressure@480',
        'pressure@510',
        'glucose',
      ]);
      expect(rules.map((r) => r['repeatCount']), [2, 2, 0]);
      expect(rules.first['repeatMinutes'], 20);
      expect(rules.first['maxDelay'], 30);
      final day = DateTime(2026, 11, 21);
      final items = journalAgenda(state, day);
      expect(items.map((e) => e.at.minute), [0, 30, 40]);
      expect(
        items.map((e) => reminderOccurrence(e.row!['id'], day)).toSet(),
        hasLength(3),
      );
    },
  );

  test(
    'Encrypted backup keeps water and repeat preferences with delivery paused',
    () async {
      final state = freshState()
        ..['waterReminder'] = {
          'enabled': true,
          'wake': 420,
          'sleep': 1380,
          'interval': 120,
          'first': 30,
          'days': [1, 3, 5],
        }
        ..['repeatPreferences'] = {
          'habit': {'count': 3, 'minutes': 30},
        };
      const password = 'reminder schedule demo';
      final restored = await openBackup(
        await makeBackup(state, password),
        password,
      );
      expect(restored['waterReminder']['enabled'], isFalse);
      expect(restored['waterReminder']['days'], [1, 3, 5]);
      expect(restored['waterReminder']['interval'], 120);
      expect(readRepeat(restored['repeatPreferences']['habit']), (
        count: 3,
        minutes: 30,
      ));
      expect(notificationRules(restored, false), isEmpty);
    },
  );

  testWidgets(
    'Notifications center enables a water plan with previewed times',
    (tester) async {
      tester.view.physicalSize = const Size(414, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final journal = MemoryJournal(
        freshState()
          ..['language'] = 'en'
          ..['stage'] = 3,
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reminders & notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water throughout the day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable water schedule'));
      await tester.pumpAndSettle();
      final preview = find.text('Schedule preview');
      await tester.scrollUntilVisible(
        preview,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('07:30'), findsOneWidget);
      await tester.tap(find.text('Save water schedule'));
      await tester.pumpAndSettle();
      expect(journal.state['waterReminder']['enabled'], isTrue);
      expect(
        notificationRules(journal.state, false).map((r) => r['minute']).first,
        450,
      );
      expect(find.text('Water throughout the day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Widget panels have smaller corners than their frame, including thin layouts',
    () {
      final state = freshState()..['enabled'] = ['water', 'glucose'];
      final config = widgetConfig(state);
      for (final size in [
        ...widgetSizes,
        const Size(48, 48),
        const Size(540, 48),
      ]) {
        final scene = WidgetScene.responsive(state, config, true, size);
        final inner = scene.panelCorner(
          size.width - 2 * scene.inset,
          size.height - 2 * scene.inset,
        );
        expect(inner, lessThan(scene.outerCorner));
        expect(inner, greaterThan(0));
        expect(
          scene.panelCorner(24, 24, extraInset: 5),
          lessThanOrEqualTo(inner),
        );
      }
    },
  );
}
