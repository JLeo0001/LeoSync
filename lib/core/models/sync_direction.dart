/// 同步方向 —— 由原生 `Items/SyncDirectionObject.java` 移植。
///
/// 数值必须与原生一致：任务表里 `task_direction` 存的就是这些数字，
/// 改数值会导致老用户的任务对不上。
enum SyncDirection {
  syncLocalToRemote(1, 'sync', '本地 → 远端（镜像，会删除远端多余文件）'),
  syncRemoteToLocal(2, 'sync', '远端 → 本地（镜像，会删除本地多余文件）'),
  copyLocalToRemote(3, 'copy', '本地 → 远端（只增不删）'),
  copyRemoteToLocal(4, 'copy', '远端 → 本地（只增不删）'),
  // 双向同步在原生里已定义但**未启用**：
  // `values/sync_direction_array.xml` 里这一项被注释掉，且 `Engine.sync()`
  // 对 5/6 直接返回 null。这里保留数值以免与老数据冲突。
  bisyncInitial(5, 'bisync', '双向同步（首次，需要 --resync）'),
  bisync(6, 'bisync', '双向同步');

  const SyncDirection(this.value, this.operation, this.label);

  /// 写入数据库的数字值。
  final int value;

  /// 对应 engine 子命令。
  final String operation;

  final String label;

  /// 是否已在原生实现中启用。bisync 两项为 `false`。
  bool get isSupported => this == syncLocalToRemote ||
      this == syncRemoteToLocal ||
      this == copyLocalToRemote ||
      this == copyRemoteToLocal;

  /// 界面上可选的项（与原生 `sync_direction_array.xml` 一致）。
  static List<SyncDirection> get selectable =>
      values.where((SyncDirection d) => d.isSupported).toList(growable: false);

  /// 双向同步需要 `--resync` 才能首次建立基线。
  bool get needsResync => this == bisyncInitial;

  static SyncDirection fromValue(int value) {
    for (final SyncDirection direction in SyncDirection.values) {
      if (direction.value == value) return direction;
    }
    return SyncDirection.syncLocalToRemote;
  }
}
