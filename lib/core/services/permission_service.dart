import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'preference_service.dart';

/// 特权状态快照（由原生 `Privileged.status()` 提供）。
class PrivilegedStatus {
  const PrivilegedStatus({
    required this.packageName,
    required this.sui,
    required this.shizukuInstalled,
    required this.shizukuBinder,
    required this.shizukuGranted,
    required this.dhizukuAvailable,
    required this.dhizukuGranted,
    required this.allFilesGranted,
    required this.notifGranted,
    required this.legacyStorageGranted,
    required this.batteryExempt,
  });

  final String packageName;
  final bool sui;
  final bool shizukuInstalled;
  final bool shizukuBinder;
  final bool shizukuGranted;
  final bool dhizukuAvailable;
  final bool dhizukuGranted;
  final bool allFilesGranted;
  final bool notifGranted;
  final bool legacyStorageGranted;
  final bool batteryExempt;

  static PrivilegedStatus fromMap(Map<Object?, Object?> map) => PrivilegedStatus(
        packageName: map['packageName'] as String? ?? '',
        sui: map['sui'] as bool? ?? false,
        shizukuInstalled: map['shizukuInstalled'] as bool? ?? false,
        shizukuBinder: map['shizukuBinder'] as bool? ?? false,
        shizukuGranted: map['shizukuGranted'] as bool? ?? false,
        dhizukuAvailable: map['dhizukuAvailable'] as bool? ?? false,
        dhizukuGranted: map['dhizukuGranted'] as bool? ?? false,
        allFilesGranted: map['allFilesGranted'] as bool? ?? false,
        notifGranted: map['notifGranted'] as bool? ?? false,
        legacyStorageGranted: map['legacyStorageGranted'] as bool? ?? false,
        batteryExempt: map['batteryExempt'] as bool? ?? false,
      );

  /// Shizuku（或 Sui）可用且已授权。
  bool get shizukuReady => shizukuGranted;

  /// Dhizuku 可用且已授权。
  bool get dhizukuReady => dhizukuAvailable && dhizukuGranted;
}

/// 特权命令的执行结果。
class PrivilegedResult {
  const PrivilegedResult({
    required this.exit,
    required this.out,
    required this.err,
  });

  final int exit;
  final String out;
  final String err;

  bool get isSuccess => exit == 0;

  static PrivilegedResult fromMap(Map<Object?, Object?> map) => PrivilegedResult(
        exit: map['exit'] as int? ?? -1,
        out: map['out'] as String? ?? '',
        err: map['err'] as String? ?? '',
      );

  @override
  String toString() =>
      'exit=$exit${err.trim().isEmpty ? '' : ', err=${err.trim()}'}';
}

/// 权限管理 —— 通知 / 所有文件访问 / 电池优化，以及
/// 经 Shizuku（ADB/Root）或 Dhizuku（设备所有者）代授的「高级权限」。
class PermissionService {
  PermissionService._();

  static const MethodChannel _channel = MethodChannel('com.jleoz.sync/native');

  /// 首次运行时主动申请的标记（每个安装只弹一轮）—— 键名在 PreferenceService 里。

  /// 拉取全部权限状态。
  static Future<PrivilegedStatus?> status() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('privStatus');
      if (raw is Map) {
        return PrivilegedStatus.fromMap(
          raw.map((key, value) => MapEntry(key, value)),
        );
      }
    } on PlatformException catch (error) {
      debugPrint('privStatus 失败：$error');
    } on MissingPluginException {
      // 桌面 / 测试环境。
    }
    return null;
  }

  /// 请求通知 + 旧版存储等运行时权限（结果经事件流回推）。
  static Future<void> requestRuntimePermissions() async {
    try {
      await _channel.invokeMethod<bool>('requestRuntimePerms');
    } on Object catch (error) {
      debugPrint('requestRuntimePerms 失败：$error');
    }
  }

  /// 跳转系统「所有文件访问」设置页。
  static Future<void> openAllFilesSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAllFilesSettings');
    } on Object catch (error) {
      debugPrint('openAllFilesSettings 失败：$error');
    }
  }

  /// 请求电池优化豁免。
  static Future<bool> requestBatteryExemption() async {
    try {
      return await _channel.invokeMethod<bool>('requestBatteryExemption') ?? false;
    } on Object {
      return false;
    }
  }

  /// 发起 Shizuku 授权（弹 Shizuku 管理器的授权框）。
  static Future<bool> requestShizukuPermission() async {
    try {
      return await _channel.invokeMethod<bool>('shizukuRequestPermission') ?? false;
    } on Object {
      return false;
    }
  }

  /// 发起 Dhizuku 授权。
  static Future<bool> requestDhizukuPermission() async {
    try {
      return await _channel.invokeMethod<bool>('dhizukuRequestPermission') ?? false;
    } on Object {
      return false;
    }
  }

  /// 以 [source]（`shizuku` / `dhizuku`）身份执行特权命令。
  static Future<PrivilegedResult?> exec(String source, List<String> cmd) async {
    try {
      final Future<Object?> pending = _channel.invokeMethod<Object?>(
        'privExec',
        <String, Object?>{'source': source, 'cmd': cmd},
      );
      final Object? raw = await pending.timeout(const Duration(seconds: 60));
      if (raw is Map) {
        return PrivilegedResult.fromMap(raw.map((key, value) => MapEntry(key, value)));
      }
    } on Object catch (error) {
      debugPrint('privExec 失败：$error');
    }
    return null;
  }

  /// 经 Shizuku / Dhizuku 一键授予存储相关权限：
  /// 「所有文件访问」（appops）+ 通知 + 旧版存储（pm grant）。
  ///
  /// 单条命令失败不影响其余；整体是否成功看「所有文件访问」的最终状态。
  static Future<bool> grantAllViaPrivileged(
    String source,
    PrivilegedStatus current,
  ) async {
    final String pkg = current.packageName;
    final List<List<String>> commands = <List<String>>[
      <String>['appops', 'set', '--uid', pkg, 'MANAGE_EXTERNAL_STORAGE', 'allow'],
      <String>['pm', 'grant', pkg, 'android.permission.POST_NOTIFICATIONS'],
      <String>['pm', 'grant', pkg, 'android.permission.READ_EXTERNAL_STORAGE'],
      <String>['pm', 'grant', pkg, 'android.permission.WRITE_EXTERNAL_STORAGE'],
    ];
    for (final List<String> cmd in commands) {
      await exec(source, cmd);
    }
    final PrivilegedStatus? after = await status();
    return after?.allFilesGranted ?? false;
  }

  /// 启动时主动申请一轮权限：
  ///  * 通知 + 旧版存储 —— 系统运行时对话框，每次启动缺了就问；
  ///  * 「所有文件访问」—— 系统设置页，仅在**首次安装**后主动带用户去一次
  ///    （否则每次启动都跳转设置会非常恼人；之后可在设置页手动/经 Shizuku 授予）。
  ///  * 电池优化豁免 —— 同样只在首装申请一次。
  static Future<void> ensureStartup() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final PrivilegedStatus? snapshot = await status();
      if (snapshot == null) return;

      if (!snapshot.notifGranted ||
          (!snapshot.legacyStorageGranted && !snapshot.allFilesGranted)) {
        await requestRuntimePermissions();
      }

      final bool asked = PreferenceService.instance.startupPermissionsAsked;
      if (!asked) {
        await PreferenceService.instance.setStartupPermissionsAsked(true);
        if (!snapshot.allFilesGranted) {
          await openAllFilesSettings();
        }
        if (!snapshot.batteryExempt) {
          await requestBatteryExemption();
        }
      }
    } on Object catch (error) {
      debugPrint('ensureStartup 失败：$error');
    }
  }
}
