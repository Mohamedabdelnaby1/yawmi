import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yawmi/domain.dart';
import 'package:yawmi/store.dart';
import 'package:yawmi/transfer.dart';
import 'package:yawmi/widgets.dart';

void main() {
  test('Synthetic desktop journal benchmark', () {
    final at = DateTime(2026, 11, 21, 12);
    final out = StringBuffer(
      'entries,json_bytes,prepare_save_ms,search_ms,full_csv_ms,widget_snapshot_ms\n',
    );
    for (final size in [1000, 10000, 50000]) {
      final state = freshState()
        ..['enabled'] = ['water', 'glucose', medicineCard]
        ..['entries'] = [
          for (var i = 0; i < size; i++)
            _reading(i, at.subtract(Duration(minutes: i * 12))),
        ];
      final save = _measure(() {
        final draft = cloneJournal(state);
        upsert(draft, 'entries', _reading(size, at));
        return jsonEncode(draft).length;
      });
      final search = _measure(() {
        final matching =
            rows(state['entries'])
                .where(
                  (entry) => normalize(
                    "${entry['tracker']} ${reportValue(entry, false)} ${entry['note']}",
                  ).contains('137'),
                )
                .toList()
              ..sort((a, b) => eventTime(b).compareTo(eventTime(a)));
        return matching.length;
      });
      final csv = _measure(
        () => makeCsv(rows(state['entries']), notes: false).length,
      );
      final widget = _measure(() => widgetSnapshot(state, false, at).length);
      final bytes = utf8.encode(jsonEncode(state)).length;
      out.writeln('$size,$bytes,$save,$search,$csv,$widget');
    }
    if (Platform.environment['YAWMI_BENCHMARK_CSV'] case final String target) {
      File(target).writeAsStringSync(out.toString());
    }
  });
}

JournalRow _reading(int id, DateTime moment) {
  final water = id.isEven;
  final stamp = moment.toUtc().toIso8601String();
  return {
    'id': 'synthetic-$id',
    'tracker': water ? 'water' : 'glucose',
    'at': stamp,
    'created': stamp,
    'values': {'value': water ? 250 : 100 + id % 60},
    'unit': water ? 'mL' : 'mg/dL',
    'note': 'Synthetic label for benchmarking',
  };
}

String _measure(int Function() work) {
  work();
  final runs = <int>[];
  for (var i = 0; i < 7; i++) {
    final timer = Stopwatch()..start();
    final used = work();
    timer.stop();
    if (used <= 0) throw StateError('Empty benchmark result');
    runs.add(timer.elapsedMicroseconds);
  }
  runs.sort();
  return (runs[runs.length ~/ 2] / 1000).toStringAsFixed(1);
}
