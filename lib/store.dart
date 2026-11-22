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
    return ProfileJournal(_SqliteJournal(db, state));
  }
}

/// Presents one local journal at a time while keeping device preferences shared.
class ProfileJournal extends Journal {
  ProfileJournal(this._storage) {
    _sync();
    _storage.addListener(_sync);
  }

  static const personal = 'personal';
  static const _preferences = ['theme', 'language', 'reduce'];
  static const _metadata = ['localProfiles', 'activeProfile', 'personalName'];
  final Journal _storage;
  late JournalRow _state;
  String? pendingRoute;

  String get activeId => _storage.state['activeProfile'] as String? ?? personal;
  String? get activeName =>
      profiles.where((profile) => profile.id == activeId).firstOrNull?.name;

  List<({String id, String? name})> get profiles => [
    (id: personal, name: _storage.state['personalName'] as String?),
    for (final row in rows(_storage.state['localProfiles']))
      (id: row['id'] as String, name: row['name'] as String),
  ];

  Iterable<(String, JournalRow)> get journals sync* {
    yield (personal, _personalState(_storage.state));
    for (final row in rows(_storage.state['localProfiles'])) {
      yield (
        row['id'] as String,
        _withPreferences(row['journal'] as JournalRow, _storage.state),
      );
    }
  }

  static JournalRow _personalState(JournalRow source) => {
    for (final e in source.entries)
      if (!_metadata.contains(e.key)) e.key: e.value,
  };

  static JournalRow _withPreferences(JournalRow profile, JournalRow root) => {
    ...profile,
    for (final key in _preferences) key: root[key] ?? freshState()[key],
  };

  void _sync() {
    _state =
        journals.where((row) => row.$1 == activeId).firstOrNull?.$2 ??
        _personalState(_storage.state);
    notifyListeners();
  }

  @override
  JournalRow get state => _state;

  @override
  Future<void> change(void Function(JournalRow draft) mutation) {
    final id = activeId;
    return _storage.change((root) {
      if (id == personal) {
        final meta = {
          for (final k in _metadata)
            if (root.containsKey(k)) k: root[k],
        };
        for (final k in _metadata) {
          root.remove(k);
        }
        mutation(root);
        root.addAll(meta);
        return;
      }
      final list = rows(root['localProfiles']);
      final index = list.indexWhere((row) => row['id'] == id);
      if (index < 0) return;
      final draft = _withPreferences(
        list[index]['journal'] as JournalRow,
        root,
      );
      mutation(draft);
      for (final key in _preferences) {
        if (draft.containsKey(key)) root[key] = draft.remove(key);
      }
      list[index] = {...list[index], 'journal': draft};
      root['localProfiles'] = list;
    });
  }

  Future<void> switchTo(String id) => _storage.change((draft) {
    if (id == personal ||
        rows(draft['localProfiles']).any((row) => row['id'] == id)) {
      draft['activeProfile'] = id;
    }
  });

  Future<void> addProfile(String name) => _storage.change((draft) {
    final list = rows(draft['localProfiles']);
    final label = name.trim();
    if (label.isEmpty || label.length > 40 || list.length >= 8) return;
    final id = newId();
    draft['localProfiles'] = [
      ...list,
      {'id': id, 'name': label, 'journal': freshState()},
    ];
    draft['activeProfile'] = id;
  });

  Future<void> rename(String id, String name) => _storage.change((draft) {
    final label = name.trim();
    if (label.isEmpty || label.length > 40) return;
    if (id == personal) {
      draft['personalName'] = label;
    } else {
      draft['localProfiles'] = [
        for (final row in rows(draft['localProfiles']))
          row['id'] == id ? {...row, 'name': label} : row,
      ];
    }
  });

  Future<void> remove(String id) => _storage.change((draft) {
    if (id == personal) return;
    draft['localProfiles'] = rows(
      draft['localProfiles'],
    ).where((row) => row['id'] != id).toList();
    if (draft['activeProfile'] == id) draft['activeProfile'] = personal;
  });

  @override
  void dispose() {
    _storage.removeListener(_sync);
    super.dispose();
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
