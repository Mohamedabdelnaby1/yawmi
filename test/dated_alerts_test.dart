import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/dated_alerts.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/transfer.dart';

import 'yawmi_test.dart' show MemoryJournal;

const _alert = {
  'date': '2027-01-01',
  'minute': 540,
  'leads': [7, 1, 0],
  'armed': true,
  'repeat': {'count': 2, 'minutes': 20},
};

void main() {
  test('Expiry and follow-up schedule separate local calendar days', () {
    final state = freshState()
      ..['meds'] = [
        {'id': 'rx', 'expiry': _alert},
      ]
      ..['followUps'] = [
        {'id': 'lab', 'name': 'Test', 'tracker': 'lab', 'alert': _alert},
      ];
    final rules = notificationRules(
      state,
      false,
      clock: DateTime(2026, 12, 24),
    );
    expect(rules.length, 6);
    expect(rules.map((row) => row['start']).toSet(), {
      '2026-12-25',
      '2026-12-31',
      '2027-01-01',
    });
    expect(
      rules.every((row) => row['start'] == row['end'] && row['minute'] == 540),
      isTrue,
    );
    expect(
      rules.every(
        (row) => row['repeatCount'] == 2 && row['repeatMinutes'] == 20,
      ),
      isTrue,
    );
    expect(rules.map((row) => row['route']).toSet(), {
      'expiry/rx',
      'follow-up/lab',
    });
    expect(parseCalendarDate('2026-02-30'), isNull);
    expect(
      journalAgenda(state, DateTime(2027, 1, 1)).single.kind,
      AgendaKind.followUp,
    );
    state['followUps'] = [
      {
        ...rows(state['followUps']).single,
        'completedAt': '2026-12-27T14:00:00Z',
      },
    ];
    expect(
      notificationRules(
        state,
        false,
        clock: DateTime(2026, 12, 27),
      ).where((r) => r['route'] == 'follow-up/lab'),
      isEmpty,
    );
    expect(journalAgenda(state, DateTime(2027, 1, 1)), isEmpty);
  });

  test(
    'Low stock starts at threshold crossing, stays anchored, then clears on refill',
    () {
      final initial = DateTime(2026, 11, 21, 9);
      final stock = MedicationStock(
        cycle: 'c1',
        countedAt: initial,
        count: 5,
        perDose: 1,
        threshold: 3,
        notify: true,
        repeatDays: 3,
        repeatMinute: 615,
      );
      final med = {'id': 'rx', 'inventory': stock.toRow()};
      final state = freshState()..['meds'] = [med];
      state['doses'] = [
        for (final day in [3, 1, 2])
          doseWithInventory(
            {'medicine': 'rx', 'status': 'taken'},
            med,
            initial.add(Duration(days: day)),
          ),
      ];
      final balance = medicationStockBalance(med, rows(state['doses']))!;
      final rules = notificationRules(
        state,
        false,
        clock: initial.add(const Duration(days: 3)),
      );
      expect(balance.remaining, 2);
      expect(balance.lowSince!.toLocal(), initial.add(const Duration(days: 2)));
      expect(
        rules.first['when'],
        initial
            .add(const Duration(days: 2, seconds: 1))
            .toUtc()
            .toIso8601String(),
      );
      expect(rules.last['start'], '2026-11-23');
      expect(rules.last['intervalDays'], 3);
      expect(rules.last['minute'], 615);
      med['inventory'] = {...stock.toRow(), 'cycle': 'c2'};
      expect(notificationRules(state, false, clock: initial), isEmpty);
    },
  );

  test(
    'Encrypted backup preserves alert choices and pauses scheduling',
    () async {
      final state = freshState()
        ..['meds'] = [
          {
            'id': 'rx',
            'name': 'Sample',
            'expiry': _alert,
            'days': allDays,
            'start': '2026-11-21',
            'times': <int>[],
            'revision': 1,
          },
        ]
        ..['followUps'] = [
          {
            'id': 'plan',
            'name': 'Lab recheck',
            'tracker': 'lab',
            'alert': _alert,
          },
        ];
      final restored = await openBackup(
        await makeBackup(state, 'sample-passphrase'),
        'sample-passphrase',
      );
      final expiry = DateAlert.read(rows(restored['meds']).single['expiry'])!;
      final followUp = DateAlert.read(
        rows(restored['followUps']).single['alert'],
      )!;
      expect(expiry.armed || followUp.armed, isFalse);
      expect(expiry.leads, [7, 1, 0]);
      expect(followUp.repeat.minutes, 20);
      expect(notificationRules(restored, false), isEmpty);
    },
  );

  testWidgets('Follow-up can be saved with alerts and then completed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journal = MemoryJournal(
      freshState()
        ..['stage'] = 3
        ..['language'] = 'en',
    );
    await tester.pumpWidget(Yawmi(journal, showDedication: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reminders & notifications'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Upcoming follow-ups'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming follow-ups'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add follow-up'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Lab recheck');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final toggle = find.text('Enable date alerts');
    await tester.scrollUntilVisible(
      toggle,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save date'));
    await tester.pumpAndSettle();
    expect(rows(journal.state['followUps']).single['alert']['armed'], true);
    await tester.tap(find.text('Lab recheck'));
    await tester.pumpAndSettle();
    final done = find.text('Mark follow-up complete');
    await tester.scrollUntilVisible(
      done,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(rows(journal.state['followUps']).single['completedAt'], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
