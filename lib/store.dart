import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'domain.dart';

abstract class Journal extends ChangeNotifier {
  JournalRow get state;
  Future<void> change(void Function(JournalRow draft) mutation);

  static Future<Journal> open() async {
    final db = await openDatabase(
      path.join(await getDatabasesPath(), 'yawmi.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA secure_delete = ON'),
      onCreate: (db, _) => db.execute(
        'CREATE TABLE journal (id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)',
      ),
    );
    final data = await db.query('journal', where: 'id = 1');
    final state = data.isEmpty
        ? freshState()
        : await compute(_decodeJournal, data.single['payload'] as String);
    return _SqliteJournal(db, state);
  }
}

class _SqliteJournal extends Journal {
  _SqliteJournal(this._db, this.state);
  final Database _db;
  @override
  JournalRow state;
  Future<void> _tail = Future.value();

  @override
  Future<void> change(void Function(JournalRow draft) mutation) {
    final result = _tail.then((_) async {
      final next = cloneJournal(state);
      mutation(next);
      final payload = await compute(jsonEncode, next);
      await _db.transaction(
        (tx) => tx.insert('journal', {
          'id': 1,
          'payload': payload,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
      );
      state = next;
      notifyListeners();
    });
    _tail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

JournalRow _decodeJournal(String payload) => jsonDecode(payload) as JournalRow;

JournalRow cloneJournal(JournalRow state) => _copyValue(state) as JournalRow;

Object? _copyValue(Object? value) => switch (value) {
  final Map map => <String, dynamic>{
    for (final entry in map.entries)
      entry.key as String: _copyValue(entry.value),
  },
  final List list => [for (final item in list) _copyValue(item)],
  _ => value,
};

void upsert(JournalRow draft, String collection, JournalRow entry) {
  draft[collection] = [
    ...rows(draft[collection]).where((e) => e['id'] != entry['id']),
    entry,
  ];
}

void removeRow(JournalRow draft, String collection, String id) {
  draft[collection] = rows(
    draft[collection],
  ).where((e) => e['id'] != id).toList();
}

void rememberTracker(JournalRow draft, String id) {
  draft['recent'] = [
    id,
    ...strings(draft['recent']).where((x) => x != id),
  ].take(4).toList();
}
