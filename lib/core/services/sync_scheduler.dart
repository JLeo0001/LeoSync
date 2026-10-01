import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../controllers/task_controller.dart';
import '../models/remote.dart';
import '../models/sync_filter.dart';
import '../models/sync_task.dart';
import '../models/trigger.dart';
import '../engine/engine_client.dart';
import '../engine/engine_paths.dart';
import '../engine/transfer_progress.dart';
import 'app_database.dart';
import 'connectivity_service.dart';
import 'preference_service.dart';
import 'sync_notifier.dart';
import 'trigger_scheduler.dart';

/// 后台调度器 —— 由原生 `workmanager/SyncManager.kt` + `Services/TriggerService.java` 移植。
///
/// 原生的分工是：
/// * **排期**用 `AlarmManager`（`setExact` / `setInexactRepeating`）——
///   时刻精确，但需要 `SCHEDULE_EXACT_ALARM` 权限；
/// * **执行**用 WorkManager（`SyncWorker`）。
///
/// Flutter 侧统一走 WorkManager：
/// * 手动 / 触发式的一次性同步 → `registerOneOffTask`
/// * 间隔触发器 → `registerPeriodicTask`
/// * 按时刻触发器 → 用一次性任务 + `initialDelay`，"跑完再排下一次"
///
/// ⚠️ 代价：WorkManager 的**最小粒度是 15 分钟**，且系统可能为省电延后。
/// 原生用精确闹钟，可以做到"整点整分触发"。这是本移植已知的行为退化。
class SyncScheduler {
  SyncScheduler._();

  /// 按时刻触发器的串行任务名。
  static const String triggerTask = 'leosync.trigger';

  /// 一次性同步任务名。
  static const String oneOffTask = 'leosync.sync.once';

  /// 间隔触发器的周期任务名。
  static const String periodicTask = 'leosync.sync.periodic';

  static bool _initialized = false;

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// 在 `main()` 里调用一次。失败时只记录日志，不影响 App 启动。
  static Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    try {
      await Workmanager().initialize(backgroundCallbackDispatcher);
      _initialized = true;
    } on Object catch (error) {
      debugPrint('SyncScheduler.initialize 失败：$error');
    }
  }

  // ── 排期 ────────────────────────────────────────────────────────────

  /// 按当前时间把触发器排上（对应 `TriggerService.queueSingleTrigger()`）。
  static Future<void> scheduleTrigger(Trigger trigger) async {
    if (!isSupported || !trigger.isEnabled) {
      await cancelTrigger(trigger);
      return;
    }

    final String uniqueName = TriggerScheduler.uniqueNameFor(trigger);
    // 先取消旧的排期，原生也是 `am.cancel(pi)` 后再设。
    await Workmanager().cancelByUniqueName(uniqueName);

    if (trigger.type == TriggerType.interval) {
      await Workmanager().registerPeriodicTask(
        uniqueName,
        periodicTask,
        inputData: <String, Object?>{
          'kind': 'trigger',
          'triggerId': trigger.id,
        },
        frequency: TriggerScheduler.effectiveInterval(trigger),
        // workmanager 0.6.x 用的是统一的 ExistingWorkPolicy。
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      return;
    }

    final Duration delay = TriggerScheduler.nextScheduleDelay(
      trigger,
      DateTime.now(),
    );
    await Workmanager().registerOneOffTask(
      uniqueName,
      triggerTask,
      inputData: <String, Object?>{
        'kind': 'trigger',
        'triggerId': trigger.id,
      },
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> cancelTrigger(Trigger trigger) async {
    if (!isSupported) return;
    await Workmanager().cancelByUniqueName(
      TriggerScheduler.uniqueNameFor(trigger),
    );
  }

  /// 手动触发一次任务（对应 `SyncManager.queue(task)`）。
  static Future<void> runTaskOnce(SyncTask task) async {
    if (!isSupported) return;
    await Workmanager().registerOneOffTask(
      TriggerScheduler.uniqueNameForTask(task.id),
      oneOffTask,
      inputData: <String, Object?>{
        'kind': 'task',
        'taskId': task.id,
      },
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// 重新排所有启用的触发器（App 启动 / 开机后调用）。
  static Future<void> rescheduleAll(List<Trigger> triggers) async {
    for (final Trigger trigger in triggers) {
      await scheduleTrigger(trigger);
    }
  }
}

/// 后台 isolate 的入口。`@pragma('vm:entry-point')` 必需，
/// 否则 AOT 编译会把函数裁掉。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask(_handleBackgroundTask);
}

Future<bool> _handleBackgroundTask(
  String taskName,
  Map<String, dynamic>? inputData,
) async {
  try {
    final EnginePaths paths = await EnginePaths.resolve();
    final PreferenceService preferences = await PreferenceService.init();
    final EngineClient client = EngineClient(
      paths: paths,
      settings: preferences.readEngineSettings(),
    );
    final AppDatabase database = await AppDatabase.open();

    final String kind = (inputData?['kind'] as String?) ?? 'task';

    if (kind == 'trigger') {
      final int triggerId = _asInt(inputData?['triggerId']);
      final Trigger? trigger = await _findTrigger(database, triggerId);
      if (trigger == null) return true; // 触发器已被删除，正常结束

      // 星期过滤发生在触发时 —— 对应原生 `TriggerService.startTask()`。
      if (TriggerScheduler.shouldSkipNow(trigger, DateTime.now())) {
        final Duration delay = TriggerScheduler.nextScheduleDelay(
          trigger,
          DateTime.now(),
        );
        await Workmanager().registerOneOffTask(
          TriggerScheduler.uniqueNameFor(trigger),
          SyncScheduler.triggerTask,
          inputData: <String, Object?>{
            'kind': 'trigger',
            'triggerId': trigger.id,
          },
          initialDelay: delay,
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );
        return true;
      }

      final bool ok = await _runTaskById(
        database,
        client,
        trigger.triggerTarget,
      );
      // 跑完立刻排下一次 —— 对应原生 `queueSingleTrigger(t)`。
      if (trigger.type == TriggerType.schedule) {
        await SyncScheduler.scheduleTrigger(trigger);
      }
      return ok;
    }

    final int taskId = _asInt(inputData?['taskId']);
    return _runTaskById(database, client, taskId);
  } on Object catch (error) {
    debugPrint('后台任务执行失败：$error');
    return false;
  }
}

Future<Trigger?> _findTrigger(AppDatabase database, int id) async {
  final List<Trigger> all = await database.triggers();
  for (final Trigger trigger in all) {
    if (trigger.id == id) return trigger;
  }
  return null;
}

Future<bool> _runTaskById(
  AppDatabase database,
  EngineClient client,
  int taskId,
) async {
  final List<SyncTask> all = await database.tasks();
  SyncTask? task;
  for (final SyncTask candidate in all) {
    if (candidate.id == taskId) {
      task = candidate;
      break;
    }
  }
  if (task == null) return true; // 任务已被删除

  // 解析远端，构造 `Remote` 供参数拼装使用。
  final List<Remote> remotes = await client.getRemotes();
  Remote? remote;
  for (final Remote candidate in remotes) {
    if (candidate.name == task.remoteId) {
      remote = candidate;
      break;
    }
  }
  if (remote == null) return false;

  // 仅 Wi-Fi 门禁 —— 任务级开关 + 全局开关取并集。
  bool wifiOnly = task.wifiOnly;
  try {
    wifiOnly = wifiOnly || PreferenceService.instance.wifiOnlyTransfers;
  } on Object {
    // 偏好服务未初始化时按任务级开关处理。
  }
  if (wifiOnly) {
    final DataConnection connection = await ConnectivityService.current();
    if (!connection.allowsUnmetered) return true; // 条件不满足，等下次调度
  }

  final SyncFilter? filter = await _findFilter(database, task.filterId);
  final List<String> args = client.syncArgs(
    remote: remote,
    task: task,
    filters: filter?.entries ?? const <FilterEntry>[],
  );
  if (args.isEmpty) return false;

  final String label = task.title.isEmpty ? '未命名任务' : task.title;
  final SyncNotifier notifier = SyncNotifier.instance;
  await notifier.initialize();
  await notifier.showProgress(title: '正在同步：$label', body: '准备中…');

  try {
    await client.runSync(
      args,
      onProgress: (TransferProgress progress) => unawaited(
        notifier.showProgress(
          title: '正在同步：$label',
          body: '${progress.humanReadableBytes} / '
              '${progress.humanReadableTotal}  ETA ${progress.humanReadableEta}',
          ratio: progress.hasTotal ? progress.ratio : null,
        ),
      ),
    );
    await notifier.cancelProgress();
    await notifier.showSuccess(
      title: '同步完成',
      body: label,
      taskId: task.id,
    );
    await _runFollowupInBackground(database, client, task.onSuccessFollowup, 0);
    return true;
  } on Object catch (error) {
    await notifier.cancelProgress();
    await notifier.showFailure(
      title: '同步失败',
      body: '$label\n$error',
      taskId: task.id,
    );
    await _runFollowupInBackground(database, client, task.onFailFollowup, 0);
    return false;
  }
}

/// 后台里跑后继任务 —— 对应原生 `SyncWorker.followupTask()`。
///
/// 加了层数上限，避免用户把任务的后继设成自己导致无限循环。
Future<void> _runFollowupInBackground(
  AppDatabase database,
  EngineClient client,
  int? followupId,
  int depth,
) async {
  if (followupId == null || followupId <= 0) return;
  if (depth >= TaskController.maxFollowupDepth) return;
  await Future<void>.delayed(const Duration(seconds: 1));
  await _runTaskById(database, client, followupId);
}

Future<SyncFilter?> _findFilter(AppDatabase database, int? id) async {
  if (id == null) return null;
  final List<SyncFilter> all = await database.filters();
  for (final SyncFilter filter in all) {
    if (filter.id == id) return filter;
  }
  return null;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
