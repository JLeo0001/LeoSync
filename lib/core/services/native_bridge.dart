import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 与原生宿主 `MainActivity.kt` 的通道。
///
/// 只做 Dart 做不到的两件事：
/// 1. 拿到 `nativeLibraryDir`（engine 可执行文件的真实位置）；
/// 2. 接收系统分享进来的文件（`ACTION_SEND`）。
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('com.jleoz.sync/native');

  static final StreamController<List<String>> _shareController =
      StreamController<List<String>>.broadcast();

  /// 系统分享进来的文件路径流（每次分享推送一次）。
  static Stream<List<String>> get sharedFiles => _shareController.stream;

  static bool _listening = false;

  /// 在 `main()` 里调用一次。
  static void initialize() {
    if (!Platform.isAndroid || _listening) return;
    _listening = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onShared') {
        final List<String>? paths = _stringList(call.arguments);
        if (paths != null && paths.isNotEmpty && !_shareController.isClosed) {
          _shareController.add(paths);
        }
      }
      return null;
    });
  }

  /// engine 可执行文件所在目录。
  ///
  /// 对应原生 `context.getApplicationInfo().nativeLibraryDir`，
  /// 比解析 `Platform.resolvedExecutable` 更可靠。
  static Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('nativeLibraryDir');
    } on PlatformException catch (error) {
      debugPrint('读取 nativeLibraryDir 失败：$error');
      return null;
    } on MissingPluginException {
      // 单元测试 / 桌面环境没有原生宿主，静默降级。
      return null;
    }
  }

  /// 冷启动时随启动 Intent 带进来的分享内容（取一次并清空）。
  static Future<List<String>?> takeInitialShare() async {
    if (!Platform.isAndroid) return null;
    try {
      return _stringList(
        await _channel.invokeMethod<List<Object?>>('takeInitialShare'),
      );
    } on PlatformException catch (error) {
      debugPrint('读取初始分享失败：$error');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// OAuth 授权期间启动保活前台服务。
  ///
  /// 应用切到浏览器后进入缓存态，Android 12+ 会杀掉 app exec 出来的
  /// 引擎子进程，授权回调就此断线。前台服务把进程顶在缓存态之上。
  /// 失败（通知权限未给、厂商阉割等）只影响成功率，不抛错。
  static Future<void> startOauthKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('oauthKeepAliveStart');
    } on PlatformException catch (error) {
      debugPrint('启动 OAuth 保活失败：$error');
    } on MissingPluginException {
      // 单元测试 / 无原生宿主环境，忽略。
    }
  }

  /// 停掉 OAuth 保活前台服务。授权结束（成功 / 失败 / 取消）都要调用。
  static Future<void> stopOauthKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('oauthKeepAliveStop');
    } on PlatformException catch (error) {
      debugPrint('停止 OAuth 保活失败：$error');
    } on MissingPluginException {
      // 同上。
    }
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List<dynamic>) return null;
    return raw.whereType<String>().toList(growable: false);
  }
}
