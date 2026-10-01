import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quick_actions/quick_actions.dart';

import 'app.dart';
import 'core/controllers/engine_controller.dart';
import 'core/controllers/settings_controller.dart';
import 'core/controllers/task_controller.dart';
import 'core/engine/engine_client.dart';
import 'core/engine/engine_paths.dart';
import 'core/services/app_database.dart';
import 'core/services/app_log.dart';
import 'core/services/native_bridge.dart';
import 'core/services/preference_service.dart';
import 'core/services/sync_notifier.dart';
import 'core/services/third_party_licenses.dart';
import 'core/services/update_checker.dart';
import 'core/services/sync_scheduler.dart';

/// 应用快捷方式（长按图标）的类型标识 —— 对应原生 `AppShortcutsHelper`。
const String _shortcutRemotes = 'leosync.shortcut.remotes';
const String _shortcutNewTask = 'leosync.shortcut.newtask';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. 注册随包分发的第三方组件许可（内嵌引擎是 MIT，声明必须随二进制分发）
  registerThirdPartyLicenses();

  // 1. 与原生宿主的通道（nativeLibraryDir、系统分享）
  NativeBridge.initialize();

  // 2. 定位 engine 引擎（Android 上是 nativeLibraryDir 里的 engine.so）
  final EnginePaths paths = await EnginePaths.resolve();

  // 3. 读取偏好，并把代理 / 日志开关同步给引擎
  final PreferenceService preferences = await PreferenceService.init();
  final EngineClient client = EngineClient(
    paths: paths,
    settings: preferences.readEngineSettings(),
  );

  // 4. 日志文件（对应原生 Log2File）
  final Directory support = await getApplicationSupportDirectory();
  final AppLog log = await AppLog.initialize(filesDir: support.path);
  log.setEnabled(preferences.loggingEnabled);
  log.info('LeoSync 启动，engine=$paths.binary');

  // 5. 打开本地库（任务 / 触发器 / 过滤器），schema 与原生一致
  final AppDatabase database = await AppDatabase.open();

  // 6. 后台调度器 + 通知通道
  await SyncScheduler.initialize();
  await SyncNotifier.instance.initialize();

  // 7. 状态中枢
  final EngineController engineController = EngineController(
    client: client,
    preferences: preferences,
  );
  final TaskController taskController = TaskController(
    database: database,
    client: client,
  );
  final SettingsController settingsController = SettingsController(
    preferences: preferences,
  );

  runApp(
    LeoSyncApp(
      engineController: engineController,
      taskController: taskController,
      settingsController: settingsController,
    ),
  );

  // 8. 首帧之后拉数据，避免阻塞启动
  await engineController.load();
  taskController.remotes = engineController.remotes;
  await taskController.load();
  // 重新排所有启用的触发器 —— 对应原生 MainActivity 里的 queueTrigger()。
  // WorkManager 自身会在重启后恢复已注册的周期任务，所以不需要额外的
  // BootReceiver；这里只是把「理论上可能丢失」的一次性任务补回来。
  unawaited(taskController.rescheduleTriggers());

  // 9. 应用快捷方式
  unawaited(_setupQuickActions());

  // 10. 应用更新提醒（仅在设置里开启「应用更新通知」时检查）
  unawaited(_maybeNotifyUpdate());

  // 10. 处理冷启动时的系统分享
  final List<String>? initialShare = await NativeBridge.takeInitialShare();
  if (initialShare != null && initialShare.isNotEmpty) {
    _handleSharedFiles(initialShare);
  }
  // 热启动分享
  NativeBridge.sharedFiles.listen(_handleSharedFiles);
}

/// 设置里开启「应用更新通知」时，启动后静默检查一次最新 release。
Future<void> _maybeNotifyUpdate() async {
  bool enabled = false;
  try {
    enabled = PreferenceService.instance.updateNotifications;
  } on Object {
    return;
  }
  if (!enabled) return;
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final UpdateInfo? update =
        await UpdateChecker.defaultChecker.check(info.version);
    if (update != null && update.isNewer) {
      await SyncNotifier.instance.initialize();
      await SyncNotifier.instance.showUpdate(version: update.displayVersion);
    }
  } on Object {
    // 更新检查失败静默处理，不打断启动。
  }
}

Future<void> _setupQuickActions() async {  try {
    final QuickActions quickActions = QuickActions();
    await quickActions.initialize((String type) {
      switch (type) {
        case _shortcutRemotes:
          homeTabNotifier.value = 0;
        case _shortcutNewTask:
          homeTabNotifier.value = 1;
      }
    });
    await quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(type: _shortcutRemotes, localizedTitle: '远端'),
      const ShortcutItem(type: _shortcutNewTask, localizedTitle: '新建任务'),
    ]);
  } on Object catch (error) {
    // 桌面或测试环境没有快捷方式能力，忽略。
    debugPrint('设置应用快捷方式失败：$error');
  }
}

void _handleSharedFiles(List<String> paths) {
  AppLog.instance.info('收到系统分享：${paths.length} 个文件');
  // 切到「远端」页，具体落到哪个远端由用户决定。
  homeTabNotifier.value = 0;
  shareIntakeNotifier.value = paths;
}
