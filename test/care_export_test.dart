import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/app_copy.dart';
import 'package:yawmi/care_data.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/excel_export.dart';
import 'package:yawmi/transfer.dart';

JournalRow _row(
  String id,
  String tracker,
  DateTime at,
  JournalRow values,
  String unit,
) => {
  'id': id,
  'tracker': tracker,
  'values': values,
  'unit': unit,
  'at': at.toUtc().toIso8601String(),
  'created': at.toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final first = DateTime(2026, 11, 8);
  final through = DateTime(2026, 11, 22);
  final samples = [
    for (var i = 0; i < 14; i++) ...[
      _row('g$i', 'glucose', DateTime(2026, 11, 8 + i, 9), {
          'value': 110 + i + i % 3 * 4,
        }, 'mg/dL')
        ..['readingSource'] = 'meter'
        ..['context'] = 'after meal'
        ..['mealMinutes'] = 90,
      _row('p$i', 'pressure', DateTime(2026, 11, 8 + i, 18), {
        'systolic': 119 + i % 6,
        'diastolic': 78 + i % 5,
      }, 'mmHg'),
    ],
    _row('l1', 'lab', first, {'value': 'الهيموجلوبين السكري'}, '')
      ..['labDetails'] = {
        'result': 6.1,
        'unit': '%',
        'laboratory': 'معمل تجريبي',
        'reference': '4.0 – 5.6',
      },
    _row('q1', 'question', through, {'value': 'إمتى أراجع نتيجة التحليل؟'}, ''),
    {
      ..._row(
        'med:1:2026-11-08:1140',
        medicineCard,
        DateTime(2026, 11, 8, 19, 7),
        {},
        '',
      ),
      'medicine': 'med',
      'name': 'دواء تجريبي',
      'amount': '١ قرص',
      'strength': '10 mg',
      'administration': 'عن طريق الفم',
      'status': 'taken',
      'scheduled': DateTime(2026, 11, 8, 19).toUtc().toIso8601String(),
    },
  ];
  final state = freshState()
    ..['entries'] = samples
    ..['meds'] = [
      {
        'id': 'med',
        'name': 'دواء تجريبي',
        'start': dayKey(first),
        'times': [1140],
        'days': allDays,
        'revision': 1,
        'changes': [
          {
            'at': first.toUtc().toIso8601String(),
            'previous': '½ قرص',
            'dose': '١ قرص',
          },
        ],
      },
    ]
    ..['doses'] = [
      {'id': 'med:1:2026-11-08:1140', 'status': 'taken'},
      {'id': 'med:1:2026-11-09:1140', 'status': 'skipped'},
    ];

  test('Trend uses local dates and normalized numeric units', () {
    final trend = careTrend(state, 'glucose', samples)!;
    expect(trend.count, 14);
    expect(trend.days, 14);
    expect(trend.unit, 'mg/dL');
    expect(trend.high, 129);
    final doses = doseCoverage(
      state,
      first,
      through,
      clock: DateTime(2026, 11, 22, 9),
    );
    expect(doses, (taken: 1, skipped: 1, unlogged: 12, scheduled: 14));
    expect(careTrend(state, 'lab', samples), isNull);
  });

  test('Device import preserves the source and avoids duplicate records', () {
    final now = DateTime(2026, 11, 22, 18);
    final record = {
      'sourceRecordId': 'health-connect:glucose:device-id',
      'tracker': 'glucose',
      'unit': 'mmol/L',
      'at': DateTime(2026, 11, 22, 10).toUtc().toIso8601String(),
      'values': {'value': 6.2},
    };
    final captured = healthImportRows(freshState(), [
      record,
      record,
      {...record, 'unit': 'mg/dL'},
    ], now);
    expect(captured.single['readingSource'], 'health-connect');
    expect(captured.single['values']['value'], 6.2);
    expect(
      healthImportRows(freshState()..['entries'] = captured, [record], now),
      isEmpty,
    );
  });

  test(
    'Daily copy changes only from a mood choice, actual routine, or a due time',
    () {
      final now = DateTime(2026, 11, 22, 14);
      final mood = _row('m', 'mood', DateTime(2026, 11, 22, 11), {
        'value': 'test',
      }, '')..['moodTone'] = 'heavy';
      expect(loggedMood([mood], now), 'heavy');
      expect(loggedMood([mood], now.add(const Duration(days: 1))), isNull);
      expect(
        todayCopy(true, entries: 1, hasLate: false, mood: 'heavy'),
        contains('اليوم تقيل'),
      );
      expect(
        todayCopy(true, entries: 1, hasLate: true),
        contains('مفيش تسجيل'),
      );
      expect(
        agendaCopy(false, now.add(const Duration(minutes: 8)), now, dose: true),
        'Due soon',
      );
      expect(
        agendaCopy(
          false,
          now.subtract(const Duration(hours: 2)),
          now,
          dose: true,
        ),
        contains('no entry'),
      );
      final data = freshState()
        ..['enabled'] = ['water']
        ..['entries'] = [
          for (var days = 0; days < 4; days++)
            _row('w$days', 'water', now.subtract(Duration(days: days)), {
              'value': 200,
            }, 'mL'),
        ];
      expect(routineCopy(data, now, false), isNull);
      data['layoutLearning'] = 'suggest';
      expect(
        routineCopy(data, now, false),
        'Water · Logged on 4 of the last 7 days.',
      );
    },
  );

  test(
    'Workbook stores numbers and dates as native cells and strings as text',
    () async {
      final workbook = await makeExcel(
        state,
        [
          ...samples,
          _row('formula', 'question', through, {
            'value': '=NOT_A_FORMULA()',
          }, ''),
        ],
        true,
        '2026-11-08 — 2026-11-22',
        notes: false,
      );
      final archive = ZipDecoder().decodeBytes(workbook, verify: true);
      String file(String path) => utf8.decode(archive.findFile(path)!.content);
      expect(file('xl/workbook.xml'), contains('التحاليل'));
      final readings = file('xl/worksheets/sheet2.xml');
      expect(readings, contains('rightToLeft="1"'));
      expect(readings, contains('r="D2" s="3"><v>110</v>'));
      expect(readings, contains('r="A2" s="4"><v>'));
      expect(readings, contains('=NOT_A_FORMULA()'));
      expect(readings, isNot(contains('<f>')));
      expect(file('xl/worksheets/sheet4.xml'), contains('<v>6.1</v>'));
      final preview = Platform.environment['YAWMI_REPORT_PREVIEWS'];
      if (preview != null) {
        final sample = await makeExcel(
          state,
          samples,
          true,
          '2026-11-08 — 2026-11-22',
          notes: false,
        );
        await File('$preview/yawmi.xlsx').writeAsBytes(sample);
      }
    },
  );

  test(
    'Styled one-page summary and multipage journal are valid in both languages',
    () async {
      final preview = Platform.environment['YAWMI_REPORT_PREVIEWS'];
      for (final ar in [true, false]) {
        final lang = ar ? 'ar' : 'en';
        final range = '2026-11-08 – 2026-11-22';
        final sample = [
          for (final row in samples)
            if (ar ||
                !['lab', 'question', medicineCard].contains(row['tracker']))
              row
            else if (row['tracker'] == medicineCard)
              {
                ...row,
                'name': 'Sample medicine',
                'amount': '1 tablet',
                'administration': 'Oral',
              }
            else
              {
                ...row,
                'values': {
                  'value': row['tracker'] == 'lab'
                      ? 'Hemoglobin A1c'
                      : 'When should we review the lab result?',
                },
                if (row['tracker'] == 'lab')
                  'labDetails': {
                    ...row['labDetails'],
                    'laboratory': 'Demo laboratory',
                  },
              },
        ];
        final summary = await makeVisitSummaryPdf(
          state,
          sample,
          ar,
          range,
          notes: true,
          start: first,
          through: through,
          includeDoseCoverage: true,
        );
        final report = await makePdf(
          state,
          [...sample, ...sample, ...sample],
          ar,
          range,
          notes: true,
        );
        expect(ascii.decode(summary.take(4).toList()), '%PDF');
        expect(ascii.decode(report.take(4).toList()), '%PDF');
        if (preview != null) {
          await File('$preview/visit-$lang.pdf').writeAsBytes(summary);
          await File('$preview/journal-$lang.pdf').writeAsBytes(report);
        }
      }
    },
  );
}
