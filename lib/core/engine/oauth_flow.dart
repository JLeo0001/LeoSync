import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/native_bridge.dart';
import 'engine_client.dart';

/// OAuth 授权流程 —— 由原生 `RemoteConfig/OauthHelper.java` + `ConfigCreate.kt` 移植。
///
/// 机制（注意：**不需要自定义 scheme，也不需要任何原生代码**）：
///
/// 1. 启动 `engine config create <name> <type> … --obscure`；
/// 2. engine 在 `localhost:53682` 起一个本地回调服务器，并把授权链接打印到
///    **stderr**：`go to the following link: https://…`；
/// 3. 我们把该链接丢给系统浏览器，用户在浏览器里完成授权；
/// 4. 授权服务器 302 回 `http://localhost:53682/…`，由 engine 自己接住；
/// 5. 子进程正常退出，`engine.conf` 写入完成。
class OauthFlow {
  OauthFlow({required this.client});

  final EngineClient client;

  /// 需要走 OAuth 的后端类型。
  ///
  /// 这是**硬编码白名单**，与 `Remote.isOAuth` 并不相同 —— 原生
  /// `DynamicRemoteConfigFragment` 只对这几个后端走浏览器授权流程，
  /// 其余（如 sftp、s3）都能在表单里填完直接创建。
  static const Set<String> browserAuthProviders = <String>{
    'box',
    'dropbox',
    'pcloud',
    'yandex',
    'drive',
    'google photos',
    'onedrive',
  };

  static bool requiresBrowserAuth(String type) =>
      browserAuthProviders.contains(type);

  /// engine 打印授权链接的格式。
  static final RegExp authUrlPattern =
      RegExp(r'go to the following link: (\S+)');

  Process? _active;

  bool get isRunning => _active != null;

  /// 最近一次失败时引擎的 stderr 摘要，供界面展示具体原因。
  String lastError = '';

  /// 执行一次授权；返回 `true` 表示 engine 退出码为 0。
  ///
  /// * [openUrl] 负责把授权链接交给系统浏览器（通常是 Custom Tab）。
  /// * 同一时刻只允许一个尝试 —— 旧的会被强制结束，因为 engine 固定占用
  ///   53682 端口（对应原生 `OauthProcessToken.forceRelease()`）。
  Future<bool> authorize({
    required String name,
    required String type,
    Map<String, String> params = const <String, String>{},
    required Future<void> Function(String url) openUrl,
  }) async {
    await abort();

    final List<String> args = <String>['config', 'create', name, type];
    params.forEach((String key, String value) {
      if (value.isEmpty) return;
      args..add(key)..add(value);
    });
    // 与原生一致：末尾追加 --obscure，避免长密码被当明文写盘。
    args.add('--obscure');

    lastError = '';
    // 保活必须赶在切去浏览器之前 —— 等应用已经被切到后台就晚了。
    await NativeBridge.startOauthKeepAlive();

    final Process process =
        await client.start(args, withCacheOptions: false);
    _active = process;

    var urlSent = false;
    final List<String> stderrTail = <String>[];

    Future<void> drain(Stream<List<int>> stream, {bool isStderr = false}) async {
      try {
        await for (final String line
            in stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (isStderr) {
            stderrTail.add(line);
            if (stderrTail.length > 12) stderrTail.removeAt(0);
          }
          if (urlSent) continue;
          final RegExpMatch? match = authUrlPattern.firstMatch(line);
          if (match == null) continue;
          final String? url = match.group(1);
          if (url == null || url.isEmpty) continue;
          urlSent = true;
          await openUrl(url);
          // ⚠️ 绝不 break：原生注释明确说明，提前跳出会关闭管道，
          // engine 后续写日志时收到 SIGPIPE，会莫名其妙地退出。
        }
      } on Object {
        // engine 偶尔输出非 UTF-8 字节；忽略该行即可，不能让循环中断。
      }
    }

    try {
      await Future.wait<void>(<Future<void>>[
        drain(process.stdout),
        drain(process.stderr, isStderr: true),
      ]);

      final int exitCode = await process.exitCode;
      if (exitCode != 0 && stderrTail.isNotEmpty) {
        lastError = stderrTail.join('\n');
      }
      return exitCode == 0;
    } finally {
      if (identical(_active, process)) _active = null;
      // 无论成败，授权流程都已结束，别把前台服务挂着占通知栏。
      await NativeBridge.stopOauthKeepAlive();
    }
  }

  /// 强制结束当前尝试（对应 `OauthProcessToken.forceRelease()`）。
  Future<void> abort() async {
    final Process? process = _active;
    _active = null;
    // 即使此刻没有进行中的授权，也把保活服务停掉，避免通知栏残留。
    await NativeBridge.stopOauthKeepAlive();
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode;
    } on Object {
      // 进程可能已经退出，忽略。
    }
  }
}
