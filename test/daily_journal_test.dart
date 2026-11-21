import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/design.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/transfer.dart';

import 'yawmi_test.dart' show MemoryJournal, reading;

JournalRow medicine(
  DateTime start, {
  List<int> times = const [480, 720],
  bool inventory = false,
}) => {
  'id': 'sample-med',
  'name': 'Sample medication',
  'start': dayKey(start),
  'days': allDays,
  'times': times,
  'revision': 1,
  'notify': true,
  if (inventory)
    'inventory': MedicationStock(
      cycle: 'initial-count',
      countedAt: start,
      count: 5,
      perDose: .5,
      threshold: 4.5,
      notify: true,
    ).toRow(),
};

void main() {
  final day = DateTime(2026, 11, 21, 9, 30);
  const nextDay = Duration(days: 1);

  test(
    'Agenda prioritizes a due dose and combines all three appointment types',
    () {
      final state = freshState()
        ..['meds'] = [medicine(day)]
        ..['reminders'] = [
          {
            'id': 'r1',
            'name': 'Log pressure',
            'minute': 420,
            'days': allDays,
            'tracker': 'pressure',
            'enabled': true,
            'start': dayKey(day),
          },
          {
            'id': 'off',
            'name': 'Disabled',
            'minute': 360,
            'days': allDays,
            'tracker': 'glucose',
            'enabled': false,
            'start': dayKey(day),
          },
        ]
        ..['entries'] = [
          {
            'id': 'visit',
            'tracker': 'visit',
            'values': {'value': 'Follow-up'},
            'planned': true,
            'created': day.toIso8601String(),
            'at': day.add(const Duration(hours: 2)).toIso8601String(),
          },
          {
            'id': 'done',
            'tracker': 'visit',
            'values': {'value': 'Completed'},
            'planned': true,
            'planCompletedAt': day.toIso8601String(),
            'created': day.toIso8601String(),
            'at': day.toIso8601String(),
          },
        ];
      final items = journalAgenda(state, day);
      expect(items.map((item) => item.kind), [
        AgendaKind.reminder,
        AgendaKind.dose,
        AgendaKind.appointment,
        AgendaKind.dose,
      ]);
      expect(nextJournalAction(items, day)?.dose?.minute, 480);
      final early = nextJournalAction(items, day)!.dose!;
      (state['doses'] as List).add({'id': early.id});
      state['entries'] = [
        ...rows(state['entries']),
        reading('linked', 'pressure', day, 1, 'mmHg')
          ..['reminderOccurrence'] = reminderOccurrence('r1', day),
      ];
      final after = journalAgenda(state, day, days: 2);
      expect(
        after
            .where((item) => dayKey(item.at) == dayKey(day))
            .map((item) => item.kind),
        [AgendaKind.appointment, AgendaKind.dose],
      );
      expect(
        after.where((item) => dayKey(item.at) == dayKey(day.add(nextDay))),
        hasLength(3),
      );
    },
  );

  test(
    'Weekly review counts calendar days, recorded readings and dose statuses',
    () {
      final state = freshState()
        ..['entries'] = [
          reading('now', 'glucose', day, 103, 'mg/dL'),
          reading('day-six', 'glucose', DateTime(2026, 11, 15), 101, 'mg/dL'),
          reading(
            'day-seven',
            'glucose',
            DateTime(2026, 11, 14, 23, 59),
            99,
            'mg/dL',
          ),
          reading(
            'later',
            'water',
            day.add(const Duration(minutes: 30)),
            250,
            'mL',
          ),
          {
            'id': 'plan',
            'tracker': 'lab',
            'planned': true,
            'at': day.toIso8601String(),
          },
        ]
        ..['doses'] = [
          {'id': 'taken', 'at': day.toIso8601String(), 'status': 'taken'},
          {
            'id': 'skip',
            'at': day.subtract(nextDay).toIso8601String(),
            'status': 'skipped',
          },
        ];
      final week = journalWeek(state, day);
      expect(dayKey(week.start), '2026-11-15');
      expect(week.readings, {'glucose': 2});
      expect(week.recordedDays, {
        '2026-11-21': 2,
        '2026-11-15': 1,
        '2026-11-20': 1,
      });
      expect(week.blankDays, 4);
      expect((week.taken, week.skipped, week.entries.length), (1, 1, 4));
    },
  );

  test('Stock uses each logged dose once and ignores previous counts', () {
    final med = medicine(day, inventory: true);
    final first = doseWithInventory(
      {'id': 'dose-1', 'medicine': med['id'], 'status': 'taken'},
      med,
      day,
    );
    final skipped = doseWithInventory(
      {'id': 'dose-2', 'medicine': med['id'], 'status': 'skipped'},
      med,
      day,
    );
    final old = {...first, 'id': 'old', 'stockCycle': 'previous-count'};
    expect(medicationStockBalance(med, [first, skipped, old])?.remaining, 4.5);
    expect(
      medicationStockBalance(med, [
        {...first, 'at': day.subtract(nextDay).toIso8601String()},
        skipped,
      ])?.remaining,
      4.5,
    );
    expect(
      medicationStockBalance(med, [
        {...first, 'status': 'skipped'},
        skipped,
      ])?.remaining,
      5,
    );
    final state = freshState()
      ..['meds'] = [med]
      ..['doses'] = [first, skipped, old];
    final alerts = notificationRules(
      state,
      false,
    ).where((rule) => (rule['id'] as String).startsWith('stock:'));
    expect(alerts.single['route'], 'stock/sample-med');
    expect(alerts.single['stableOnce'], isTrue);
    state['doses'] = [skipped, old];
    expect(
      notificationRules(state, false).where((r) => r['stableOnce'] == true),
      isEmpty,
    );
  });

  test(
    'Encrypted restore preserves correctly counted inventory and pauses its alert',
    () async {
      final med = medicine(day, inventory: true);
      final taken = doseWithInventory(
        {
          'id': 'taken',
          'name': med['name'],
          'medicine': med['id'],
          'status': 'taken',
          'at': day.toIso8601String(),
        },
        med,
        day,
      );
      final state = freshState()
        ..['meds'] = [med]
        ..['doses'] = [taken];
      const password = 'Synthetic-Backup-120';
      final restored = await openBackup(
        await makeBackup(state, password),
        password,
      );
      final balance = medicationStockBalance(
        rows(restored['meds']).single,
        rows(restored['doses']),
      )!;
      expect(balance.remaining, 4.5);
      expect(balance.stock.notify, isFalse);
    },
  );

  testWidgets(
    'Today can record, undo and correct an overdue dose and its inventory',
    (tester) async {
      tester.view.physicalSize = const Size(432, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateUtils.dateOnly(DateTime.now());
      final med = medicine(today, times: [0], inventory: true);
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 3
          ..['language'] = 'en'
          ..['enabled'] = ['glucose', medicineCard]
          ..['meds'] = [med],
      );
      double remaining() =>
          medicationStockBalance(med, rows(journal.state['doses']))!.remaining;
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      final focus = find.byKey(const ValueKey('agenda-focus-dose'));
      Future<void> takeDose() async {
        await tester.tap(focus);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark taken'));
        await tester.pumpAndSettle();
      }

      await takeDose();
      expect(remaining(), 4.5);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(remaining(), 5);
      expect(rows(journal.state['doses']), isEmpty);
      await takeDose();
      final old = rows(journal.state['doses']).single;
      await tester.tap(
        find.descendant(of: find.byType(Dock), matching: find.text('History')),
      );
      await tester.pumpAndSettle();
      final logged = find.text('Sample medication');
      await tester.scrollUntilVisible(
        logged,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(logged);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      final corrected = rows(journal.state['doses']).single;
      expect(corrected['id'], old['id']);
      expect(corrected['scheduled'], old['scheduled']);
      expect(corrected['status'], 'skipped');
      expect(remaining(), 5);
    },
  );

  testWidgets('A reading completes its own measurement reminder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateUtils.dateOnly(DateTime.now());
    final journal = MemoryJournal(
      freshState()
        ..['stage'] = 3
        ..['language'] = 'en'
        ..['enabled'] = ['glucose']
        ..['reminders'] = [
          {
            'id': 'glucose-reminder',
            'name': 'Morning reading',
            'tracker': 'glucose',
            'start': dayKey(today),
            'days': allDays,
            'minute': 0,
            'enabled': true,
          },
        ],
    );
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-focus-reminder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '120');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    final saved = entriesFor(journal.state, 'glucose').single;
    expect(
      entryReminderOccurrence(saved),
      reminderOccurrence('glucose-reminder', today),
    );
    expect(journalAgenda(journal.state, today), isEmpty);
  });

  testWidgets('Weekly review opens a visit report with the same entry scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recent = DateTime.now().subtract(const Duration(minutes: 5));
    final journal = MemoryJournal(
      freshState()
        ..['stage'] = 3
        ..['language'] = 'en'
        ..['enabled'] = ['glucose']
        ..['entries'] = [
          reading('new', 'glucose', recent, 110, 'mg/dL'),
          reading(
            'old',
            'glucose',
            recent.subtract(const Duration(days: 8)),
            131,
            'mg/dL',
          ),
        ],
    );
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    final weekly = find.text('Weekly review');
    await tester.scrollUntilVisible(
      weekly,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(weekly);
    await tester.pumpAndSettle();
    expect(find.text('6 · Days with no entries'), findsOneWidget);
    await tester.tap(find.text('Prepare visit summary'));
    await tester.pumpAndSettle();
    expect(find.text('Share summary'), findsOneWidget);
    expect(find.text('Selected entries · 1'), findsOneWidget);
  });
}
