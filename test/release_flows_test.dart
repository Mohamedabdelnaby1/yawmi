import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/design.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/main.dart';
import 'package:yawmi/transfer.dart';
import 'package:yawmi/widgets.dart';

import 'yawmi_test.dart' show MemoryJournal, reading;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Onboarding starts with health conditions and personalizes Today',
    (tester) async {
      tester.view.physicalSize = const Size(432, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final journal = MemoryJournal(freshState()..['language'] = 'en');
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      expect(find.text('Log your first reading'), findsNothing);
      expect(find.byType(Dock), findsNothing);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your health conditions'), findsOneWidget);
      final next = find.ancestor(
        of: find.text('Continue to trackers'),
        matching: find.byType(JournalButton),
      );
      expect(tester.widget<JournalButton>(next).onPressed, isNull);
      final diabetes = find.byKey(const ValueKey('setup-condition-diabetes2'));
      await tester.tap(diabetes);
      await tester.pumpAndSettle();
      await tester.tap(diabetes);
      await tester.pumpAndSettle();
      expect(tester.widget<JournalButton>(next).onPressed, isNull);
      await tester.tap(diabetes);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('setup-condition-hypertension')),
      );
      await tester.pumpAndSettle();
      expect(journal.state['stage'], 1);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(journal.state['stage'], 4);
      expect(find.text('Suggested for your conditions'), findsOneWidget);
      expect(cardPlan(journal.state).take(2), ['glucose', 'pressure']);
      expect(cardPlan(journal.state), isNot(contains('peak_flow')));
      final glucose = find.byKey(const ValueKey('glucose'));
      await tester.ensureVisible(glucose);
      await tester.tap(glucose);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Yawmi'));
      await tester.pumpAndSettle();
      expect(journal.state['stage'], 3);
      expect(cardPlan(journal.state), contains('pressure'));
      expect(cardPlan(journal.state), isNot(contains('glucose')));
      expect(find.byType(Dock), findsOneWidget);
    },
  );

  testWidgets(
    'Condition selection remains usable with large text in landscape',
    (tester) async {
      tester.view.physicalSize = const Size(780, 410);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final journal = MemoryJournal(
        freshState()
          ..['stage'] = 1
          ..['language'] = 'ar'
          ..['reduce'] = true,
      );
      await tester.pumpWidget(Yawmi(journal));
      await tester.pumpAndSettle();
      final asthma = find.byKey(const ValueKey('setup-condition-asthma'));
      await tester.scrollUntilVisible(asthma, 180);
      await tester.ensureVisible(asthma);
      await tester.pumpAndSettle();
      await tester.tap(asthma);
      await tester.pumpAndSettle();
      expect(tester.widget<TrackerChoice>(asthma).selected, isTrue);
      expect(cardPlan(journal.state), contains('peak_flow'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Report preview honors the exact search selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().subtract(const Duration(minutes: 5));
    final journal = MemoryJournal(
      freshState()
        ..['stage'] = 3
        ..['language'] = 'en'
        ..['entries'] = [
          reading('matches-search', 'glucose', now, 137, 'mg/dL'),
          reading('outside-search', 'glucose', now, 191, 'mg/dL'),
        ],
    );
    await tester.pumpWidget(Yawmi(journal));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dock), matching: find.text('History')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '137');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share report'));
    await tester.pumpAndSettle();
    expect(find.text('Selected entries · 1'), findsOneWidget);
    expect(find.textContaining('137'), findsOneWidget);
    expect(find.textContaining('191'), findsNothing);
    await tester.tap(find.text('One-page visit summary'));
    await tester.pumpAndSettle();
    expect(find.text('Share summary'), findsOneWidget);
    expect(find.text('Selected entries · 1'), findsOneWidget);
    expect(find.textContaining('191'), findsNothing);
  });

  test(
    'Ordinary Yawmi CSV reimports pressure and preserves dates and note text',
    () async {
      final state = freshState();
      final at = DateTime.utc(2026, 11, 21, 8);
      final pressure = reading('bp', 'pressure', at, 118, 'mmHg')
        ..['values'] = {'systolic': 118, 'diastolic': 76, 'pulse': 73}
        ..['note'] = '=Quoted "text"\nملاحظة';
      final imported = await readJournalCsv(
        state,
        makeCsv([
          pressure,
          {
            'id': 'dose',
            'tracker': 'medicine',
            'status': 'taken',
            'at': at.toIso8601String(),
          },
        ], notes: true),
      );
      final row = imported.entries.single;
      expect(imported.skipped, 1);
      expect(row['values'], pressure['values']);
      expect(row['at'], pressure['at']);
      expect(row['note'], pressure['note']);
      state['entries'] = newCsvEntries(state, imported.entries);
      expect(newCsvEntries(state, imported.entries), isEmpty);
      expect(
        readJournalCsv(
          state,
          Uint8List.fromList(utf8.encode('legacy,header\nunsupported')),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'One page report keeps entry totals and exports in both languages',
    () async {
      final state = freshState();
      final at = DateTime(2026, 11, 20, 12);
      final entries = [
        reading('b', 'pressure', at, 118, 'mmHg')
          ..['values'] = {'systolic': 118, 'diastolic': 76},
        reading('g', 'glucose', at, 103, 'mg/dL'),
        reading('w', 'water', at, 250, 'mL'),
        {
          'id': 'dose',
          'tracker': medicineCard,
          'at': at.toUtc().toIso8601String(),
          'status': 'taken',
        },
        for (final tracker
            in trackers
                .where(
                  (t) =>
                      t.kind == 'number' &&
                      t.fields.length == 1 &&
                      !['glucose', 'water'].contains(t.id),
                )
                .take(9))
          reading(tracker.id, tracker.id, at, 1, tracker.units.first),
      ];
      final into = Platform.environment['YAWMI_PDF_SAMPLES'];
      for (final ar in [true, false]) {
        final groups = visitSummary(state, entries, ar);
        expect(groups, hasLength(8));
        expect(groups.fold(0, (n, e) => n + e.count), entries.length);
        final bytes = await makeVisitSummaryPdf(
          state,
          entries,
          ar,
          '2026-11-20 – 2026-11-21',
        );
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
          1,
        );
        if (into != null) {
          final sample = await makeVisitSummaryPdf(
            state,
            [
              ...entries.take(4),
              reading(
                'b2',
                'pressure',
                at.add(const Duration(days: 1)),
                121,
                'mmHg',
              )..['values'] = {'systolic': 121, 'diastolic': 79},
            ],
            ar,
            '2026-11-20 – 2026-11-21',
          );
          Directory(into).createSync(recursive: true);
          File(
            '$into/yawmi-visit-synthetic-${ar ? 'ar' : 'en'}.pdf',
          ).writeAsBytesSync(sample);
        }
      }
    },
  );

  test(
    'Widget daily snapshot prepares the next day without exposing private values',
    () {
      final at = DateTime(2026, 11, 20, 23, 58);
      final state = freshState()
        ..['enabled'] = ['water', 'glucose', medicineCard]
        ..['entries'] = [reading('w', 'water', at, 250, 'mL')]
        ..['meds'] = [
          {
            'id': 'demo',
            'name': 'Example',
            'revision': 1,
            'times': [480],
            'start': '2026-11-20',
            'days': allDays,
          },
        ];
      final preset = widgetConfig(state)..['values'] = true;
      state['widgets'] = [preset];
      final result = widgetSnapshot(state, false, at);
      final layouts = result['layouts'] as Map;
      final cards = rows(layouts[preset['id']]['cards']);
      final water = cards.firstWhere((r) => r['id'] == 'water');
      expect(water['value'], '250');
      expect(water['advance']['2026-11-21']['value'], '0');
      final medicine = cards.firstWhere((r) => r['id'] == medicineCard);
      expect(medicine['advance']['2026-11-21']['route'], startsWith('dose/'));
      final automatic = rows(layouts[automaticWidgetId]['cards']);
      expect(
        automatic.firstWhere(
          (r) => r['id'] == 'water',
        )['advance']['2026-11-21']['value'],
        '•••',
      );
      expect(result['offset'], at.timeZoneOffset.inMinutes);
    },
  );
}
