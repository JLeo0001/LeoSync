import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/sync_filter.dart';
import '../models/sync_task.dart';
import '../models/trigger.dart';

/// 本地数据库 —— 由原生 `Database/DatabaseInfo.kt` + `DatabaseHandler.kt` 移植。
///
/// **表名、列名、版本号都与原生保持一致**（`leosync.db` / v6），
/// 这样老用户把原版的数据库文件放到应用目录即可无缝接管；
/// 新建用户则直接按完整 schema 建表。
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// 与原生 `DatabaseInfo.DATABASE_VERSION` 一致。
  static const int schemaVersion = 6;

  /// 与原生 `DatabaseInfo.DATABASE_NAME` 一致。
  static const String fileName = 'leosync.db';

  static AppDatabase? _instance;

  static AppDatabase get instance {
    final AppDatabase? value = _instance;
    if (value == null) {
      throw StateError('AppDatabase 尚未初始化，请先 await AppDatabase.open()');
    }
    return value;
  }

  Database get raw => _db;

  static Future<AppDatabase> open({String? directory}) async {
    final String dir = directory ?? await getDatabasesPath();
    final Database db = await openDatabase(
      p.join(dir, fileName),
      version: schemaVersion,
      onConfigure: (Database db) async {
        // 原生用 ON DELETE SET NULL，外键必须显式打开。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _instance = AppDatabase._(db);
  }

  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }

  // ── 建表 ────────────────────────────────────────────────────────────

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute(
      'CREATE TABLE ${SyncTask.tableName} ('
      '${SyncTask.columnId} INTEGER PRIMARY KEY,'
      '${SyncTask.columnTitle} TEXT,'
      '${SyncTask.columnRemoteId} TEXT,'
      '${SyncTask.columnRemoteType} INTEGER,'
      '${SyncTask.columnRemotePath} TEXT,'
      '${SyncTask.columnLocalPath} TEXT,'
      '${SyncTask.columnDirection} INTEGER,'
      '${SyncTask.columnMd5Sum} INTEGER,'
      '${SyncTask.columnWifiOnly} INTEGER,'
      '${SyncTask.columnFilterId} INTEGER REFERENCES '
      '${SyncFilter.tableName}(${SyncFilter.columnId}) ON DELETE SET NULL,'
      '${SyncTask.columnDeleteExcluded} INTEGER,'
      '${SyncTask.columnOnFail} INTEGER,'
      '${SyncTask.columnOnSuccess} INTEGER)',
    );
    await db.execute(
      'CREATE TABLE ${Trigger.tableName} ('
      '${Trigger.columnId} INTEGER PRIMARY KEY,'
      '${Trigger.columnTitle} TEXT,'
      '${Trigger.columnEnabled} INTEGER,'
      '${Trigger.columnTime} INTEGER,'
      '${Trigger.columnWeekday} INTEGER,'
      '${Trigger.columnTarget} INTEGER,'
      '${Trigger.columnType} INTEGER DEFAULT ${0})',
    );
    await db.execute(
      'CREATE TABLE ${SyncFilter.tableName} ('
      '${SyncFilter.columnId} INTEGER PRIMARY KEY,'
      '${SyncFilter.columnTitle} TEXT,'
      '${SyncFilter.columnFilters} TEXT)',
    );
  }

  /// 原生从 v1 一路 `ALTER TABLE` 加到 v6，这里把那条链路原样重放。
  ///
  /// 每条都是 `ADD COLUMN`，用 try/catch 吞掉「列已存在」，
  /// 因此对任意起始版本都安全（幂等）。
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    const List<String> migrations = <String>[
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnMd5Sum} INTEGER',
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnWifiOnly} INTEGER',
      'ALTER TABLE ${Trigger.tableName} ADD COLUMN '
          '${Trigger.columnType} INTEGER DEFAULT ${0}',
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnFilterId} INTEGER REFERENCES '
          '${SyncFilter.tableName}(${SyncFilter.columnId}) ON DELETE SET NULL',
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnDeleteExcluded} INTEGER',
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnOnFail} INTEGER',
      'ALTER TABLE ${SyncTask.tableName} ADD COLUMN '
          '${SyncTask.columnOnSuccess} INTEGER',
    ];
    for (final String sql in migrations) {
      try {
        await db.execute(sql);
      } on DatabaseException {
        // 列已存在（例如从 v6 降级再升级），忽略即可。
      }
    }
  }

  // ── 任务 ────────────────────────────────────────────────────────────

  Future<List<SyncTask>> tasks() async {
    final List<Map<String, Object?>> rows = await _db.query(
      SyncTask.tableName,
      orderBy: '${SyncTask.columnTitle} COLLATE NOCASE ASC',
    );
    return rows.map(SyncTask.fromRow).toList(growable: false);
  }

  Future<SyncTask> insertTask(SyncTask task) async {
    final int id = await _db.insert(
      SyncTask.tableName,
      task.toRow(includeId: false),
    );
    return task.copyWith(id: id);
  }

  Future<void> updateTask(SyncTask task) async {
    await _db.update(
      SyncTask.tableName,
      task.toRow(includeId: false),
      where: '${SyncTask.columnId} = ?',
      whereArgs: <Object?>[task.id],
    );
  }

  Future<void> deleteTask(int id) async {
    await _db.delete(
      SyncTask.tableName,
      where: '${SyncTask.columnId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ── 触发器 ──────────────────────────────────────────────────────────

  Future<List<Trigger>> triggers() async {
    final List<Map<String, Object?>> rows =
        await _db.query(Trigger.tableName, orderBy: Trigger.columnId);
    return rows.map(Trigger.fromRow).toList(growable: false);
  }

  Future<Trigger> insertTrigger(Trigger trigger) async {
    final int id = await _db.insert(
      Trigger.tableName,
      trigger.toRow(includeId: false),
    );
    return trigger.copyWith(id: id);
  }

  Future<void> updateTrigger(Trigger trigger) async {
    await _db.update(
      Trigger.tableName,
      trigger.toRow(includeId: false),
      where: '${Trigger.columnId} = ?',
      whereArgs: <Object?>[trigger.id],
    );
  }

  Future<void> deleteTrigger(int id) async {
    await _db.delete(
      Trigger.tableName,
      where: '${Trigger.columnId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ── 过滤器 ──────────────────────────────────────────────────────────

  Future<List<SyncFilter>> filters() async {
    final List<Map<String, Object?>> rows =
        await _db.query(SyncFilter.tableName, orderBy: SyncFilter.columnId);
    return rows.map(SyncFilter.fromRow).toList(growable: false);
  }

  Future<SyncFilter> insertFilter(SyncFilter filter) async {
    final int id = await _db.insert(
      SyncFilter.tableName,
      <String, Object?>{
        SyncFilter.columnTitle: filter.title,
        SyncFilter.columnFilters: SyncFilter.serialize(filter.entries),
      },
    );
    return SyncFilter(id: id, title: filter.title, entries: filter.entries);
  }

  Future<void> updateFilter(SyncFilter filter) async {
    await _db.update(
      SyncFilter.tableName,
      <String, Object?>{
        SyncFilter.columnTitle: filter.title,
        SyncFilter.columnFilters: SyncFilter.serialize(filter.entries),
      },
      where: '${SyncFilter.columnId} = ?',
      whereArgs: <Object?>[filter.id],
    );
  }

  Future<void> deleteFilter(int id) async {
    await _db.delete(
      SyncFilter.tableName,
      where: '${SyncFilter.columnId} = ?',
      whereArgs: <Object?>[id],
    );
  }
}
