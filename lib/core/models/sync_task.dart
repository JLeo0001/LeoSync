import 'sync_direction.dart';

/// 一条同步任务 —— 由原生 `Items/Task.kt` 移植。
///
/// **表名与列名与原生完全一致**，这样将来可以把老用户的
/// `leosync.db` 直接搬过来，无需写转换脚本。
class SyncTask {
  const SyncTask({
    this.id = 0,
    this.title = '',
    this.remoteId = '',
    this.remoteType = 0,
    this.remotePath = '',
    this.localPath = '',
    this.direction = SyncDirection.syncLocalToRemote,
    this.useMd5Sum = false,
    this.wifiOnly = false,
    this.filterId,
    this.deleteExcluded = false,
    this.onFailFollowup,
    this.onSuccessFollowup,
  });

  final int id;
  final String title;

  /// 远端名称（`engine.conf` 里的节名）。
  final String remoteId;

  /// 原生遗留的远端类型数字，保留以便读写老数据。
  final int remoteType;

  final String remotePath;
  final String localPath;
  final SyncDirection direction;

  /// 用 `--checksum` 而非默认的修改时间 + 大小判断是否需要传输。
  final bool useMd5Sum;

  final bool wifiOnly;

  /// 关联的过滤规则 id（可为空）。
  final int? filterId;

  /// 配合过滤器使用：把被排除的文件也从目标端删除。
  final bool deleteExcluded;

  /// 失败 / 成功后要触发的后续任务 id（原生 `FollowupTask` 机制）。
  final int? onFailFollowup;
  final int? onSuccessFollowup;

  static const String tableName = 'task_table';
  static const String columnId = 'task_id';
  static const String columnTitle = 'task_title';
  static const String columnRemoteId = 'task_remote_id';
  static const String columnRemoteType = 'task_remote_type';
  static const String columnRemotePath = 'task_remote_path';
  static const String columnLocalPath = 'task_local_path';
  static const String columnDirection = 'task_direction';
  static const String columnMd5Sum = 'task_use_md5sum';
  static const String columnWifiOnly = 'task_use_only_wifi';
  static const String columnFilterId = 'task_filter_id';
  static const String columnDeleteExcluded = 'task_delete_excluded';
  static const String columnOnFail = 'task_onFailFollowupTask';
  static const String columnOnSuccess = 'task_onSuccessFollowupTask';

  SyncTask copyWith({
    int? id,
    String? title,
    String? remoteId,
    int? remoteType,
    String? remotePath,
    String? localPath,
    SyncDirection? direction,
    bool? useMd5Sum,
    bool? wifiOnly,
    int? filterId,
    bool clearFilterId = false,
    bool? deleteExcluded,
    int? onFailFollowup,
    int? onSuccessFollowup,
  }) {
    return SyncTask(
      id: id ?? this.id,
      title: title ?? this.title,
      remoteId: remoteId ?? this.remoteId,
      remoteType: remoteType ?? this.remoteType,
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      direction: direction ?? this.direction,
      useMd5Sum: useMd5Sum ?? this.useMd5Sum,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      filterId: clearFilterId ? null : (filterId ?? this.filterId),
      deleteExcluded: deleteExcluded ?? this.deleteExcluded,
      onFailFollowup: onFailFollowup ?? this.onFailFollowup,
      onSuccessFollowup: onSuccessFollowup ?? this.onSuccessFollowup,
    );
  }

  static SyncTask fromRow(Map<String, Object?> row) => SyncTask(
        id: (row[columnId] as int?) ?? 0,
        title: (row[columnTitle] as String?) ?? '',
        remoteId: (row[columnRemoteId] as String?) ?? '',
        remoteType: (row[columnRemoteType] as int?) ?? 0,
        remotePath: (row[columnRemotePath] as String?) ?? '',
        localPath: (row[columnLocalPath] as String?) ?? '',
        direction: SyncDirection.fromValue((row[columnDirection] as int?) ?? 1),
        useMd5Sum: _bool(row[columnMd5Sum]),
        wifiOnly: _bool(row[columnWifiOnly]),
        filterId: row[columnFilterId] as int?,
        deleteExcluded: _bool(row[columnDeleteExcluded]),
        onFailFollowup: row[columnOnFail] as int?,
        onSuccessFollowup: row[columnOnSuccess] as int?,
      );

  /// 不带 id 的版本，用于 INSERT（让 SQLite 自增）。
  Map<String, Object?> toRow({bool includeId = true}) => <String, Object?>{
        if (includeId) columnId: id,
        columnTitle: title,
        columnRemoteId: remoteId,
        columnRemoteType: remoteType,
        columnRemotePath: remotePath,
        columnLocalPath: localPath,
        columnDirection: direction.value,
        columnMd5Sum: useMd5Sum ? 1 : 0,
        columnWifiOnly: wifiOnly ? 1 : 0,
        columnFilterId: filterId,
        columnDeleteExcluded: deleteExcluded ? 1 : 0,
        columnOnFail: onFailFollowup,
        columnOnSuccess: onSuccessFollowup,
      };

  /// 原生 `SQLiteDatabase` 里布尔是 0/1 整数。
  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  /// `本地路径 ⇄ 远端路径` 的一行摘要，用于列表副标题。
  String get pathSummary =>
      '${direction.operation == 'sync' ? '⇅' : '→'} '
      '${remoteId.isEmpty ? '?' : remoteId}:$remotePath  ⇄  $localPath';

  @override
  String toString() => 'SyncTask($id, $title, ${direction.name})';
}
