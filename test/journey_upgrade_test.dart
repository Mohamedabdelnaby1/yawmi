import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/reminder_schedule.dart';
import 'package:yawmi/store.dart';
import 'package:yawmi/widgets.dart';

import 'yawmi_test.dart' show MemoryJournal;

void main() {
  final today = DateTime(2026, 11, 22, 10);
  JournalRow medicine() => {
    'id': 'tablet',
    'name': 'Test medicine',
    'start': '2026-01-01',
    'revision': 1,
    'times': [480, 1080],
    'days': allDays,
    'notify': true,
    'inventory': MedicationStock(
      cycle: 'count-1',
      countedAt: today,
      count: 2,
      perDose: 1,
      threshold: 0,
      notify: true,
    ).toRow(),
  };

  test(
    'Stock uses future scheduled doses, skips resolved doses, and stops at the schedule end',
    () {
      final med = medicine();
      final balance = medicationStockBalance(med, [])!;
      expect(projectedRefill(med, balance, today), DateTime(2026, 11, 23, 18));
      final evening = dosesOn({
        'meds': [med],
      }, today).last;
      expect(
        projectedRefill(
          med,
          balance,
          today,
          doses: [
            {'id': evening.id, 'status': 'skipped'},
          ],
        ),
        DateTime(2026, 11, 24, 8),
      );
      expect(
        projectedRefill({...med, 'end': '2026-11-22'}, balance, today),
        isNull,
      );
    },
  );

  test(
    'Profiles stay separate, share language, and keep owner-specific reminder keys',
    () async {
      final base = MemoryJournal(freshState()..['stage'] = 3);
      final journal = ProfileJournal(base);
      await journal.change(
        (d) => d['entries'] = [
          {'id': 'mine'},
        ],
      );
      await journal.addProfile('Family');
      final other = journal.activeId;
      expect(journal.state['stage'], 0);
      expect(rows(journal.state['entries']), isEmpty);
      await journal.change((d) {
        d['language'] = 'en';
        d['entries'] = [
          {'id': 'theirs'},
        ];
        d['meds'] = [medicine()];
      });
      final familyRules = rulesForProfile(journal.state, false, other);
      expect(
        familyRules
            .where((rule) => rule['medicine'] == 'tablet')
            .first['owner'],
        other,
      );
      expect(
        profileRuleId('water-plan@480:2026-11-22', other),
        isNot('water-plan@480:2026-11-22'),
      );
      await journal.switchTo(ProfileJournal.personal);
      expect(journal.state['language'], 'en');
      expect(rows(journal.state['entries']).single['id'], 'mine');
      expect(journal.state.containsKey('localProfiles'), isFalse);
      await journal.switchTo(other);
      expect(rows(journal.state['entries']).single['id'], 'theirs');
      await journal.remove(other);
      expect(journal.activeId, ProfileJournal.personal);
      journal.dispose();
    },
  );

  testWidgets(
    'Switching profile starts its own setup and returns to the personal journal',
    (tester) async {
      final db = ProfileJournal(
        MemoryJournal(
          freshState()
            ..['stage'] = 3
            ..['language'] = 'en',
        ),
      );
      await tester.pumpWidget(Yawmi(db));
      await tester.pumpAndSettle();
      expect(find.text('Daily summary'), findsNothing);
      await db.addProfile('Family member');
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      await db.switchTo(ProfileJournal.personal);
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsNothing);
      expect(find.text('Today'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Routine mode shifts water and eligible trackers within its date range only',
    () {
      final state = freshState()
        ..['meds'] = [medicine()]
        ..['reminders'] = [
          {
            'id': 'flex',
            'tracker': 'glucose',
            'enabled': true,
            'minute': 540,
            'days': allDays,
            'learn': 'suggest',
          },
          {
            'id': 'fixed',
            'tracker': 'pressure',
            'enabled': true,
            'minute': 540,
            'days': allDays,
            'learn': 'off',
          },
        ]
        ..['routineMode'] = {
          'id': 'travel',
          'shift': 60,
          'start': '2026-11-22',
          'end': '2026-11-22',
        };
      final schedules = trackingSchedules(state, false);
      final flex = schedules.firstWhere((r) => r['id'] == 'flex');
      final fixed = schedules.firstWhere((r) => r['id'] == 'fixed');
      expect(reminderTimeOn(flex, today)?.hour, 10);
      expect(reminderTimeOn(flex, DateTime(2026, 11, 23))?.hour, 9);
      expect(reminderTimeOn(fixed, today)?.hour, 9);
      expect(dosesOn(state, today).last.time.hour, 18);
    },
  );

  test(
    'Camera candidates require explicit selection and ambiguous package dates stay out',
    () {
      expect(scanCandidates('Glucose ١١٥\n6٫4 mmol/L', ScanField.number), [
        '115',
        '6.4',
      ]);
      expect(scanCandidates('Test 6.4 mmol / L', ScanField.unit), ['mmol/L']);
      expect(
        scanCandidates(
          '2027-12-28\n26/04/2028\n03/04/2028\n2027-02-30',
          ScanField.expiry,
        ),
        ['2027-12-28', '2028-04-26'],
      );
    },
  );

  test(
    'Timeline merges links and visit summaries preserve chosen older labs and questions',
    () {
      final state = freshState()
        ..['entries'] = [
          {
            'id': 'lab',
            'tracker': 'lab',
            'at': '2026-09-01T12:00:00',
            'values': {'value': 'Lab'},
            'conditions': [
              {'id': 'other'},
            ],
          },
          {
            'id': 'symptom',
            'tracker': 'symptom',
            'at': '2026-11-22T09:30:00',
            'values': {'value': 'Note'},
            'conditions': [
              {'id': 'diabetes'},
            ],
          },
        ]
        ..['visits'] = [
          {
            'id': 'visit',
            'name': 'Visit',
            'date': '2026-11-22',
            'condition': 'diabetes',
            'questions': 'When to return?',
            'linkedEntries': ['lab'],
            'reviewedAt': '2026-11-22T18:00:00',
          },
        ];
      final visit = rows(state['visits']).single;
      expect(careTimeline(state).map((event) => event.kind), [
        'visit',
        'entry',
        'entry',
      ]);
      final source = sourceForVisit(
        state,
        visit,
        DateTimeRange(start: DateTime(2026, 11, 1), end: today),
      );
      expect(source.map((row) => row['id']), [
        'visit-questions:visit',
        'lab',
        'symptom',
      ]);
    },
  );

  test(
    'Large widget adds upcoming medication only when its value is visible',
    () {
      final state = freshState()..['meds'] = [medicine()];
      final config = {
        'enabled': [medicineCard],
        'names': true,
        'showShortcut': false,
      };
      final medium = WidgetScene.responsive(
        state,
        config,
        false,
        const Size(332, 144),
        today: today,
      );
      final large = WidgetScene.responsive(
        state,
        config,
        false,
        const Size(332, 308),
        today: today,
      );
      final private = WidgetScene.responsive(
        state,
        {...config, 'names': false},
        false,
        const Size(332, 308),
        today: today,
      );
      expect(medium.footerAction, isNull);
      expect(large.footerAction?.minute, 1080);
      expect(large.footerAction?.label, 'Next · Test medicine');
      expect(private.footerAction, isNull);
    },
  );
}
