import 'dart:io';


import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Low-level per-account SQLite storage.
///
/// The database stores ONLY encrypted payloads for every secret-bearing record.
/// Plaintext columns are limited to opaque ids, the (random) folder id, and
/// timestamps — none of which reveal vault contents. Decryption happens in the
/// app layer with the in-memory master key.
///
/// Cross-platform: on Android the default sqflite plugin is used; on
/// Linux/Windows desktop we initialise the FFI factory (backed by the bundled
/// sqlite3 native library from `sqlite3_flutter_libs`).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static bool _ffiInitialised = false;

  /// Must be called once at startup (before any DB access) on desktop.
  static void initPlatform() {
    if (_ffiInitialised) return;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialised = true;
  }

  Database? _db;
  String? _openPath;

  bool get isOpen => _db != null;

  Future<Database> open(String path) async {
    if (_db != null && _openPath == path) return _db!;
    await close();
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (d, v) async {
          await d.execute('''
            CREATE TABLE folders (
              id         TEXT PRIMARY KEY,
              created_at INTEGER NOT NULL,
              payload    TEXT NOT NULL
            )''');
          await d.execute('''
            CREATE TABLE entries (
              id         TEXT PRIMARY KEY,
              folder_id  TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              payload    TEXT NOT NULL
            )''');
          await d.execute('''
            CREATE TABLE notes (
              id         TEXT PRIMARY KEY,
              folder_id  TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              payload    TEXT NOT NULL
            )''');
          await d.execute('''
            CREATE TABLE meta (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )''');
        },
      ),
    );
    _db = db;
    _openPath = path;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _openPath = null;
  }

  Database get _require {
    final d = _db;
    if (d == null) {
      throw StateError('Database not open');
    }
    return d;
  }

  // ---- folders -----------------------------------------------------------
  Future<List<Map<String, Object?>>> readFolders() =>
      _require.query('folders', orderBy: 'created_at ASC');

  Future<void> upsertFolder(
      {required String id, required int createdAt, required String payload}) async {
    await _require.insert(
      'folders',
      {'id': id, 'created_at': createdAt, 'payload': payload},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteFolder(String id) async {
    await _require.delete('folders', where: 'id = ?', whereArgs: [id]);
    // Orphan the entries/notes that referenced this folder.
    await _require
        .update('entries', {'folder_id': null}, where: 'folder_id = ?', whereArgs: [id]);
    await _require
        .update('notes', {'folder_id': null}, where: 'folder_id = ?', whereArgs: [id]);
  }

  // ---- entries -----------------------------------------------------------
  Future<List<Map<String, Object?>>> readEntries() =>
      _require.query('entries', orderBy: 'updated_at DESC');

  Future<void> upsertEntry({
    required String id,
    required String? folderId,
    required int createdAt,
    required int updatedAt,
    required String payload,
  }) async {
    await _require.insert(
      'entries',
      {
        'id': id,
        'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'payload': payload,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteEntry(String id) async {
    await _require.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  // ---- notes -------------------------------------------------------------
  Future<List<Map<String, Object?>>> readNotes() =>
      _require.query('notes', orderBy: 'updated_at DESC');

  Future<void> upsertNote({
    required String id,
    required String? folderId,
    required int createdAt,
    required int updatedAt,
    required String payload,
  }) async {
    await _require.insert(
      'notes',
      {
        'id': id,
        'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'payload': payload,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteNote(String id) async {
    await _require.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// Writes already-encrypted rows into a fresh vault file (device linking).
  Future<void> importRows({
    required String path,
    required List<Map<String, Object?>> folders,
    required List<Map<String, Object?>> entries,
    required List<Map<String, Object?>> notes,
  }) async {
    final db = await open(path);
    await db.transaction((txn) async {
      for (final r in folders) {
        await txn.insert('folders', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in entries) {
        await txn.insert('entries', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in notes) {
        await txn.insert('notes', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await close();
  }

  // ---- bulk (used when re-encrypting on master-password change) ----------
  Future<void> replaceAllPayloads({
    required List<Map<String, Object?>> folders,
    required List<Map<String, Object?>> entries,
    required List<Map<String, Object?>> notes,
  }) async {
    await _require.transaction((txn) async {
      for (final f in folders) {
        await txn.update('folders', {'payload': f['payload']},
            where: 'id = ?', whereArgs: [f['id']]);
      }
      for (final e in entries) {
        await txn.update('entries', {'payload': e['payload']},
            where: 'id = ?', whereArgs: [e['id']]);
      }
      for (final n in notes) {
        await txn.update('notes', {'payload': n['payload']},
            where: 'id = ?', whereArgs: [n['id']]);
      }
    });
  }
}
