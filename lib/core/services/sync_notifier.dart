import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'preference_service.dart';

/// 同步通知 —— 由原生 `notifications/SyncServiceNotifications.kt` 移植。
///
/// 通道 id 与原生保持一致（含 `com.jleoz.sync.` 前缀），
/// 这样从原生版升级过来的用户不会被重复建通道。
class SyncNotifier {
  SyncNotifier._();

  static final SyncNotifier instance = SyncNotifier._();

  /// 与原生 `SyncServiceNotifications.CHANNEL_ID` 一致。
  static const String channelProgress = 'com.jleoz.sync.sync_service';
  static const String channelSuccess = 'com.jleoz.sync.sync_service_success';
  static const String channelFail = 'com.jleoz.sync.sync_service_fail';

  /// 应用更新通知通道。
  static const String channelUpdate = 'com.jleoz.sync.app_update';

  /// 与原生 `GROUP_ID` 一致。
  static const String groupId = 'com.jleoz.sync.sync_service.group';

  /// 与原生 `PERSISTENT_NOTIFICATION_ID_FOR_SYNC` 一致。
  static const int progressNotificationId = 162;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _createChannels();
      _ready = true;
    } on Object catch (error) {
      debugPrint('SyncNotifier.initialize 失败：$error');
    }
  }

  Future<void> _createChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelProgress,
        '同步正在进行',
        description: '显示正在运行的同步任务',
        importance: Importance.low,
        groupId: groupId,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelSuccess,
        '同步完成',
        description: '同步成功后的汇总通知',
        importance: Importance.defaultImportance,
        groupId: groupId,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelFail,
        '同步失败',
        description: '同步出错时的通知',
        importance: Importance.high,
        groupId: groupId,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelUpdate,
        '应用更新',
        description: '发现新版本时的提醒',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// 「合并同步报告」开启时，所有结果共用一条通知（与原生
  /// `notification_reports` 的「unified report」语义一致 —— 单条、会被
  /// 下一次结果覆盖），而不是每个任务各占一条。
  bool get _unifiedReports {
    try {
      return PreferenceService.instance.notificationReports;
    } on Object {
      return false;
    }
  }

  /// 统一报告使用的固定通知 id。
  static const int summaryNotificationId = 9000;

  /// 更新提醒使用的固定通知 id。
  static const int updateNotificationId = 7200;

  /// 应用更新提醒 —— 对应原生 `UpdateNotificationHelper`。
  Future<void> showUpdate({required String version}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        updateNotificationId,
        '发现新版本',
        'LeoSync $version 已可用',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelUpdate,
            '应用更新',
            channelDescription: '发现新版本时的提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('showUpdate 失败：$error');
    }
  }

  /// 常驻进度通知（一个任务同时只显示一条，用固定 id 覆盖）。
  Future<void> showProgress({
    required String title,
    required String body,
    double? ratio,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        progressNotificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelProgress,
            '同步正在进行',
            channelDescription: '显示正在运行的同步任务',
            groupKey: groupId,
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            showProgress: ratio != null,
            maxProgress: 100,
            progress: ((ratio ?? 0) * 100).round(),
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('showProgress 失败：$error');
    }
  }

  Future<void> cancelProgress() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(progressNotificationId);
    } on Object {
      // 通知不存在时忽略。
    }
  }

  Future<void> showSuccess({
    required String title,
    required String body,
    required int taskId,
  }) async {
    if (!_ready) return;
    final bool unified = _unifiedReports;
    try {
      await _plugin.show(
        unified ? summaryNotificationId : _resultId(taskId, success: true),
        unified ? '同步报告' : title,
        unified ? '$body ✓' : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelSuccess,
            '同步完成',
            channelDescription: '同步成功后的汇总通知',
            groupKey: groupId,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('showSuccess 失败：$error');
    }
  }

  Future<void> showFailure({
    required String title,
    required String body,
    required int taskId,
  }) async {
    if (!_ready) return;
    final bool unified = _unifiedReports;
    try {
      await _plugin.show(
        unified ? summaryNotificationId : _resultId(taskId, success: false),
        unified ? '同步报告' : title,
        unified ? '$body ✗' : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelFail,
            '同步失败',
            channelDescription: '同步出错时的通知',
            groupKey: groupId,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('showFailure 失败：$error');
    }
  }

  /// 成功 / 失败用不同的通知 id，避免互相覆盖 —— 与原生一致。
  static int _resultId(int taskId, {required bool success}) =>
      success ? 100000 + taskId : 200000 + taskId;
}
