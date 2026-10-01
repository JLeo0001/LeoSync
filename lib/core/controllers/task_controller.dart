import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/remote.dart';
import '../models/sync_filter.dart';
import '../models/sync_task.dart';
import '../models/trigger.dart';
import '../engine/engine_client.dart';
import '../engine/transfer_progress.dart';
import '../services/app_database.dart';
import '../services/connectivity_service.dart';
import '../services/sync_notifier.dart';
import '../services/sync_scheduler.dart';

/// 一条任务的运行态。
class TaskRunState {
  const TaskRunState({
    this.running = false,
    this.progress = const TransferProgress(),
    this.lastError,
    this.lastFinishedAt,
  });

  final bool running;
  final TransferProgress progress;
  final String? lastError;
  final DateTime? lastFinishedAt;

  bool get succeeded => lastError == null && lastFinishedAt != null;

  TaskRunState copyWith({
    bool? running,
    TransferProgress? progress,
    String? lastError,
    bool clearError = false,
    DateTime? lastFinishedAt,
  }) {
    return TaskRunState(
      running: running ?? this.running,
      progress: progress ?? this.progress,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastFinishedAt: lastFinishedAt ?? this.lastFinishedAt,
    );
  }
}

/// 任务 / 触发器 / 过滤器 的状态中枢。
///
/// 对应原生 `Fragments/TasksFragment.java` + `workmanager/SyncManager.kt`
/// + `Services/SyncService.kt` 三者的职责合集。
class TaskController extends ChangeNotifier {
  TaskController({required this.database, required this.client});

  final AppDatabase database;
  final EngineClient client;

  List<SyncTask> _tasks = const <SyncTask>[];
  List<Trigger> _triggers = const <Trigger>[];
  List<SyncFilter> _filters = const <SyncFilter>[];
  final Map<int, TaskRunState> _runStates = <int, TaskRunState>{};
  Process? _activeProcess;
  bool _loading = false;

  List<SyncTask> get tasks => _tasks;

  List<Trigger> get triggers => _triggers;

  List<SyncFilter> get filters => _filters;

  bool get isLoading => _loading;

  TaskRunState stateOf(int taskId) =>
      _runStates[taskId] ?? const TaskRunState();

  bool get isAnyRunning =>
      _runStates.values.any((TaskRunState s) => s.running);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _tasks = await database.tasks();
      _triggers = await database.triggers();
      _filters = await database.filters();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── 任务 CRUD ───────────────────────────────────────────────────────

  Future<void> saveTask(SyncTask task) async {
    if (task.id == 0) {
      await database.insertTask(task);
    } else {
      await database.updateTask(task);
    }
    await load();
  }

  Future<void> deleteTask(int id) async {
    // 先清掉引用该任务的后继任务，避免留下悬空 id。
    for (final SyncTask other in _tasks) {
      if (other.onFailFollowup == id || other.onSuccessFollowup == id) {
        await database.updateTask(
          other.copyWith(
            onFailFollowup: other.onFailFollowup == id ? 0 : null,
            onSuccessFollowup: other.onSuccessFollowup == id ? 0 : null,
          ),
        );
      }
    }
    await database.deleteTask(id);
    _runStates.remove(id);
    await load();
  }

  // ── 过滤器 CRUD ─────────────────────────────────────────────────────

  Future<void> saveFilter(SyncFilter filter) async {
    if (filter.id == 0) {
      await database.insertFilter(filter);
    } else {
      await database.updateFilter(filter);
    }
    await load();
  }

  Future<void> deleteFilter(int id) async {
    await database.deleteFilter(id);
    await load();
  }

  SyncFilter? filterById(int? id) {
    if (id == null) return null;
    for (final SyncFilter filter in _filters) {
      if (filter.id == id) return filter;
    }
    return null;
  }

  // ── 触发器 CRUD ─────────────────────────────────────────────────────

  Future<void> saveTrigger(Trigger trigger) async {
    final Trigger saved;
    if (trigger.id == 0 || trigger.id == Trigger.idDoesNotExist) {
      saved = await database.insertTrigger(trigger);
    } else {
      await database.updateTrigger(trigger);
      saved = trigger;
    }
    // 排期跟随数据变化 —— 对应原生 `TriggerService.queueSingleTrigger()`。
    await SyncScheduler.scheduleTrigger(saved);
    await load();
  }

  Future<void> deleteTrigger(int id) async {
    // 先取消闹钟，再删数据；顺序反了会留下永远不触发的僵尸排期。
    for (final Trigger trigger in _triggers) {
      if (trigger.id == id) {
        await SyncScheduler.cancelTrigger(trigger);
        break;
      }
    }
    await database.deleteTrigger(id);
    await load();
  }

  /// 重新排所有触发器（App 启动时调用一次，对应原生 `MainActivity` 里的
  /// `triggerService.queueTrigger()`）。
  Future<void> rescheduleTriggers() async {
    await SyncScheduler.rescheduleAll(
      _triggers.where((Trigger t) => t.isEnabled).toList(growable: false),
    );
  }

  // ── 执行 ────────────────────────────────────────────────────────────

  /// 手动运行一条任务。
  ///
  /// 对应原生 `SyncManager.queue(task)` → `SyncWorker`。
  /// 后台调度（WorkManager）尚未接入，目前是前台执行 + 进度回调。
  /// 后继任务的最大链长。原生 `SyncWorker.followupTask()` 没有这个保护，
  /// 一旦用户把任务 A 的成功后继设成 A 自己，就会无限循环。
  static const int maxFollowupDepth = 5;

  Future<void> runTask(
    SyncTask task, {
    Remote? remote,
    int followupDepth = 0,
  }) async {
    if (task.id == 0) return;
    final Remote? target = remote ?? _remoteFor(task);
    if (target == null) {
      _fail(task.id, '找不到远端「${task.remoteId}」，请先重新配置');
      return;
    }

    // ── 仅 Wi-Fi 门禁 ────────────────────────────────────────────────
    // 对应原生 `SyncWorker` 里的 `mTask.wifionly && METERED → 稍后重试`。
    if (task.wifiOnly) {
      final DataConnection connection = await ConnectivityService.current();
      if (!connection.allowsUnmetered) {
        _fail(task.id, '当前不是非计费网络，已跳过（该任务勾选了「仅 Wi-Fi」）');
        return;
      }
    }

    final SyncFilter? filter = filterById(task.filterId);
    final List<String> args = client.syncArgs(
      remote: target,
      task: task,
      filters: filter?.entries ?? const <FilterEntry>[],
    );
    if (args.isEmpty) {
      _fail(task.id, '该同步方向暂不支持');
      return;
    }

    _setState(task.id, TaskRunState(running: true));
    await SyncNotifier.instance.showProgress(
      title: '正在同步：${task.title.isEmpty ? '未命名任务' : task.title}',
      body: '准备中…',
    );

    var succeeded = false;
    String? error;
    try {
      await client.runSync(
        args,
        onProcess: (Process process) => _activeProcess = process,
        onProgress: (TransferProgress progress) {
          _setState(
            task.id,
            TaskRunState(running: true, progress: progress),
          );
          unawaited(
            SyncNotifier.instance.showProgress(
              title: '正在同步：${task.title.isEmpty ? '未命名任务' : task.title}',
              body: '${progress.humanReadableBytes} / '
                  '${progress.humanReadableTotal}  '
                  'ETA ${progress.humanReadableEta}',
              ratio: progress.hasTotal ? progress.ratio : null,
            ),
          );
        },
      );
      succeeded = true;
    } on EngineException catch (e) {
      error = e.message;
    } finally {
      _activeProcess = null;
      await SyncNotifier.instance.cancelProgress();
    }

    final String label = task.title.isEmpty ? '未命名任务' : task.title;
    if (succeeded) {
      _setState(task.id, TaskRunState(lastFinishedAt: DateTime.now()));
      await SyncNotifier.instance.showSuccess(
        title: '同步完成',
        body: label,
        taskId: task.id,
      );
    } else {
      _fail(task.id, error ?? '同步失败');
      await SyncNotifier.instance.showFailure(
        title: '同步失败',
        body: '$label\n${error ?? ''}'.trim(),
        taskId: task.id,
      );
    }

    await _runFollowup(
      succeeded ? task.onSuccessFollowup : task.onFailFollowup,
      followupDepth,
    );
  }

  /// 翻译自 `SyncWorker.followupTask()`：先等 1 秒，再排下一个任务。
  Future<void> _runFollowup(int? followupId, int depth) async {
    if (followupId == null || followupId <= 0) return;
    if (depth >= maxFollowupDepth) {
      debugPrint('后继任务链超过 $maxFollowupDepth 层，已中止（疑似成环）');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));

    SyncTask? next;
    for (final SyncTask candidate in _tasks) {
      if (candidate.id == followupId) {
        next = candidate;
        break;
      }
    }
    if (next == null) return;
    await runTask(next, followupDepth: depth + 1);
  }

  void _fail(int taskId, String message) {
    _setState(
      taskId,
      TaskRunState(lastError: message, lastFinishedAt: DateTime.now()),
    );
  }

  /// 取消正在运行的任务。
  void cancelRunning() {
    _activeProcess?.kill(ProcessSignal.sigkill);
    _activeProcess = null;
  }

  void _setState(int taskId, TaskRunState state) {
    _runStates[taskId] = state;
    notifyListeners();
  }

  /// 任务 → 对应的 [Remote]。由调用方注入远端列表，避免这里再查一次 engine。
  List<Remote> remotes = const <Remote>[];

  Remote? _remoteFor(SyncTask task) {
    for (final Remote remote in remotes) {
      if (remote.name == task.remoteId) return remote;
    }
    return null;
  }
}
