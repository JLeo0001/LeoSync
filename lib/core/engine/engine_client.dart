import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/file_item.dart';
import '../models/engine_provider.dart';
import '../models/remote.dart';
import '../models/sync_direction.dart';
import '../models/sync_filter.dart';
import '../models/sync_task.dart';
import 'engine_paths.dart';
import 'transfer_progress.dart';

/// 运行期可调的 engine 偏好，对应原生 `Engine.getEngineEnv()` 读取的那些
/// SharedPreferences 项。
class EngineSettings {
  EngineSettings({
    this.loggingEnabled = false,
    this.proxyEnabled = false,
    this.proxyProtocol = 'http',
    this.proxyHost = 'localhost',
    this.proxyPort = '8080',
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.noProxyHosts = 'localhost',
  });

  /// 打开后会追加 `-vvv`，与原生行为一致。
  bool loggingEnabled;

  bool proxyEnabled;
  String proxyProtocol;
  String proxyHost;
  String proxyPort;
  String proxyUsername;
  String proxyPassword;
  String noProxyHosts;
}

/// 一次 engine 调用的结果。
class EngineResult {
  const EngineResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get isSuccess => exitCode == 0;

  /// 尝试把 stdout 解析成 JSON；失败返回 `null`。
  Object? get jsonOrNull {
    final String text = stdout.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// engine 调用失败。
class EngineException implements Exception {
  EngineException(this.message, {this.exitCode, this.stderr});

  final String message;
  final int? exitCode;
  final String? stderr;

  @override
  String toString() =>
      'EngineException($message${exitCode == null ? '' : ', exit=$exitCode'})';
}

/// 解析 `engine config providers` 的 JSON 输出。
///
/// rclone 1.71 的实现是 `json.MarshalIndent(fs.Registry, "", " ")`，因此：
/// * **顶层是数组**，并不是 `{"providers": [...]}` 包一层的对象；
/// * 所有键都是 Go 字段名原样输出（首字母大写：`Name` / `Options` /
///   `IsPassword` / `DefaultStr` …），见 `fs/registry.go` 的 `RegInfo` 与
///   `Option`（无小写 json tag）。
/// 解析按不区分大小写匹配键名；若顶层是对象，则兜底取 `providers` 键，
/// 兼容其它引擎实现。解析不到数组时抛 [EngineException]。
List<EngineProvider> parseProvidersJson(String stdout, {String? stderr}) {
  final String text = stdout.trim();
  Object? decoded;
  if (text.isNotEmpty) {
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
  }

  Object? rawList = decoded;
  if (decoded is Map<String, dynamic>) rawList = decoded['providers'];
  if (rawList is! List<dynamic>) {
    throw EngineException('读取后端列表失败', stderr: stderr);
  }

  final List<EngineProvider> list = <EngineProvider>[];
  for (final Object? item in rawList) {
    if (item is Map<String, dynamic>) {
      list.add(EngineProvider.fromJson(item));
    }
  }
  list.sort((EngineProvider a, EngineProvider b) => a.name.compareTo(b.name));
  return list;
}

/// engine 引擎客户端 —— 由原生 `Engine.java` 移植。
///
/// 与原生最大的不同：原生通过 JNI 风格的 `Runtime.exec` 拉起进程，
/// 这里用 `dart:io` 的 [Process]；两者对 engine 而言完全等价，
/// 因此**不需要 FFI 或平台通道**。
class EngineClient {
  EngineClient({
    required this.paths,
    EngineSettings? settings,
  }) : settings = settings ?? EngineSettings();

  final EnginePaths paths;
  final EngineSettings settings;

  /// 最近一次调用的 stderr，便于在「日志」页展示。
  String lastErrorOutput = '';

  // ── 命令构造 ────────────────────────────────────────────────────────

  /// 翻译自 `Engine.createCommand(String...)`。
  List<String> buildCommand(List<String> args) => <String>[
        paths.binary,
        '--config',
        paths.config,
        if (settings.loggingEnabled) '-vvv',
        ...args,
      ];

  /// 翻译自 `Engine.createCommandWithOptions(String...)`：额外带上 cache 目录。
  List<String> buildCommandWithOptions(List<String> args) => <String>[
        paths.binary,
        '--cache-chunk-path',
        paths.cache,
        '--cache-db-path',
        paths.cache,
        '--config',
        paths.config,
        if (settings.loggingEnabled) '-vvv',
        ...args,
      ];

  /// 翻译自 `Engine.getEngineEnv(String... overwriteOptions)`。
  ///
  /// 返回 `KEY=VALUE` 列表；[overwriteOptions] 里同名的项会覆盖默认值。
  List<String> buildEnvironment({List<String> overwriteOptions = const []}) {
    final Map<String, String> env = <String, String>{};

    if (settings.proxyEnabled) {
      final String auth = (settings.proxyUsername + settings.proxyPassword)
              .isEmpty
          ? ''
          : '${settings.proxyUsername}:${settings.proxyPassword}@';
      final String url =
          '${settings.proxyProtocol}://$auth${settings.proxyHost}:${settings.proxyPort}';
      // 与 Go 的 net/http ProxyFromEnvironment 约定保持一致。
      env['http_proxy'] = url;
      env['https_proxy'] = url;
      env['no_proxy'] = settings.noProxyHosts;
    }

    // 不设置 TMPDIR 时 Go 会退到 /data/local/tmp（仅 shell 用户可访问）。
    env['TMPDIR'] = paths.cache;

    // 忽略 chtimes 报错，见 engine#2446。
    env['ENGINE_LOCAL_NO_SET_MODTIME'] = 'true';

    for (final String raw in overwriteOptions) {
      final int eq = raw.indexOf('=');
      if (eq <= 0) continue;
      env[raw.substring(0, eq)] = raw.substring(eq + 1);
    }

    return env.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .toList(growable: false);
  }

  Map<String, String> _effectiveEnvironment({List<String> overrides = const []}) {
    final Map<String, String> env = Map<String, String>.from(Platform.environment);
    for (final String pair in buildEnvironment(overwriteOptions: overrides)) {
      final int eq = pair.indexOf('=');
      env[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return env;
  }

  // ── 执行 ────────────────────────────────────────────────────────────

  /// 运行 engine 并等待结束。
  Future<EngineResult> run(
    List<String> args, {
    bool withCacheOptions = false,
    List<String> envOverrides = const [],
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!File(paths.binary).existsSync()) {
      throw EngineException('找不到 engine 可执行文件：${paths.binary}');
    }

    final List<String> command =
        withCacheOptions ? buildCommandWithOptions(args) : buildCommand(args);

    final Process process = await Process.start(
      command.first,
      command.sublist(1),
      environment: _effectiveEnvironment(overrides: envOverrides),
      workingDirectory: paths.cache,
    );

    final Future<String> out =
        process.stdout.transform(utf8.decoder).join();
    final Future<String> err =
        process.stderr.transform(utf8.decoder).join();

    final int exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw EngineException('engine 执行超时：${args.join(' ')}');
      },
    );

    final EngineResult result = EngineResult(
      exitCode: exitCode,
      stdout: await out,
      stderr: await err,
    );
    lastErrorOutput = result.stderr;
    return result;
  }

  /// 启动一个长期运行的 engine 子进程（`serve`、`mount`、`rcd` 等）。
  Future<Process> start(
    List<String> args, {
    bool withCacheOptions = true,
    List<String> envOverrides = const [],
  }) async {
    final List<String> command =
        withCacheOptions ? buildCommandWithOptions(args) : buildCommand(args);
    return Process.start(
      command.first,
      command.sublist(1),
      environment: _effectiveEnvironment(overrides: envOverrides),
      workingDirectory: paths.cache,
    );
  }

  // ── 业务封装 ────────────────────────────────────────────────────────

  /// 读取 engine 版本号，例如 `1.71.0-extract`。
  ///
  /// rclone 的 `version` 输出首行形如 `rclone v1.71.0-extract`，
  /// 这里只留版本号本身，避免把上游品牌名透给界面。
  Future<String> version() async {
    final EngineResult result = await run(<String>['version']);
    final String first = result.stdout.split('\n').first.trim();
    final RegExpMatch? match =
        RegExp(r'v?(\d[^ ,]*(-\S+)?)').firstMatch(first);
    return match?.group(1) ?? first;
  }

  /// `engine config dump` → [Remote] 列表。
  ///
  /// 翻译自 `Engine.getRemotes()`。
  Future<List<Remote>> getRemotes() async {
    final EngineResult result = await run(<String>['config', 'dump']);
    final Object? decoded = result.jsonOrNull;
    if (decoded is! Map<String, dynamic>) {
      throw EngineException(
        '读取远端失败',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final List<Remote> remotes = <Remote>[];
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Object? value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      final String type = (value['type'] as String? ?? '').trim();
      if (type.isEmpty) continue; // 与原生一致：跳过没写 type 的节
      remotes.add(Remote.fromConfigDump(entry.key, value));
    }
    remotes.sort(
      (Remote a, Remote b) => a.label.toLowerCase().compareTo(
            b.label.toLowerCase(),
          ),
    );
    return remotes;
  }

  /// 列出目录内容。
  ///
  /// 翻译自 `Engine.getDirectoryContent()`：
  /// * local / alias 远端加 `--ignore-errors`（engine#3179）；
  /// * local / alias 远端的退出码 6 视为非致命。
  Future<List<FileItem>> listDirectory(
    Remote remote,
    String path, {
    bool startAtRoot = false,
  }) async {
    final String remoteAndPath = _joinRemotePath(remote, path, startAtRoot);

    final bool lenient = remote.isLocal || remote.isPathAlias;
    final List<String> args = <String>[
      if (lenient) '--ignore-errors',
      'lsjson',
      remoteAndPath,
    ];

    final EngineResult result =
        await run(args, withCacheOptions: true, envOverrides: const []);

    final bool tolerableExit =
        result.exitCode == 0 || (lenient && result.exitCode == 6);
    if (!tolerableExit) {
      throw EngineException(
        '读取目录失败：$remoteAndPath',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final Object? decoded = result.jsonOrNull;
    if (decoded is! List<dynamic>) {
      throw EngineException(
        '无法解析 lsjson 输出',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final String parentPath =
        _isRemoteRoot(path, remote) ? '' : _normalize(path);

    final List<FileItem> items = <FileItem>[];
    for (final Object? raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      items.add(
        FileItem.fromLsJson(
          remote,
          raw,
          parentPath: parentPath,
          startAtRoot: startAtRoot,
        ),
      );
    }

    items.sort((FileItem a, FileItem b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// `engine config dump` 的原始结果：节名 → 键值对。
  Future<Map<String, Map<String, String>>> configDump() async {
    final EngineResult result = await run(<String>['config', 'dump']);
    final Object? decoded = result.jsonOrNull;
    if (decoded is! Map<String, dynamic>) {
      throw EngineException(
        '读取配置失败',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final Map<String, Map<String, String>> out =
        <String, Map<String, String>>{};
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Object? value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      out[entry.key] = value.map(
        (String k, Object? v) => MapEntry<String, String>(k, v?.toString() ?? ''),
      );
    }
    return out;
  }

  /// 读取单个远端的完整配置 —— 翻译自 `Engine.getConfig(name)`。
  Future<Map<String, String>> configFor(String name) async {
    final Map<String, Map<String, String>> all = await configDump();
    return all[name] ?? <String, String>{};
  }

  /// `engine config providers` → 可选后端类型列表。
  Future<List<EngineProvider>> providers() async {
    final EngineResult result =
        await run(<String>['config', 'providers'], withCacheOptions: false);
    return parseProvidersJson(result.stdout, stderr: result.stderr);
  }

  /// 新建 / 更新远端。
  ///
  /// 翻译自 `Engine.configCreate()`：**末尾追加 `--obscure`**，否则 engine 会把
  /// 长密码当成明文写进配置（上游刻意保留的行为，注释里说明了原因）。
  Future<EngineResult> createRemote({
    required String name,
    required String type,
    Map<String, String> params = const <String, String>{},
  }) {
    final List<String> args = <String>['config', 'create', name, type];
    params.forEach((String key, String value) {
      if (value.isEmpty) return;
      args..add(key)..add(value);
    });
    args.add('--obscure');
    return run(args);
  }

  /// 翻译自 `Engine.deleteRemote()`。
  Future<EngineResult> deleteRemote(String name) =>
      run(<String>['config', 'delete', name], withCacheOptions: true);

  /// 对字符串做 engine 的可逆混淆（密码字段）。
  ///
  /// 翻译自 `Engine.obscure()`；失败返回 `null`。
  Future<String?> obscure(String password) async {
    final EngineResult result = await run(<String>['obscure', password]);
    if (!result.isSuccess) return null;
    final String value = result.stdout.trim();
    return value.isEmpty ? null : value;
  }

  /// 复制 / 同步 / 移动等一次性任务；调用方可订阅 [Process.stdout] 看进度。
  /// 通用的 engine 子命令启动器（`copy` / `sync` / `moveto` / `serve`…）。
  Future<Process> startOperation(
    String operation,
    List<String> args, {
    bool withCacheOptions = true,
  }) {
    return start(
      <String>[operation, ...args],
      withCacheOptions: withCacheOptions,
    );
  }

  // ── 文件操作（翻译自 Engine.java 的对应方法） ─────────────────────────

  /// 某个远端在设备本地的基准前缀。
  ///
  /// `local` 类型（且不是 alias / crypt / cache）需要拼上
  /// [EnginePaths.localBase]，与 `Engine.getLocalRemotePathPrefix()` 一致。
  String localPrefix(Remote remote) {
    if (remote.isLocal && !remote.isAlias && !remote.isCrypt && !remote.isCache) {
      return '${paths.localBase}/';
    }
    return '';
  }

  /// `name:` + 本地前缀 —— 文件操作里反复用到。
  String remotePrefix(Remote remote) => '${remote.name}:${localPrefix(remote)}';

  /// 把文件名里的 `\u0000` 编码成 `\u2400`。
  ///
  /// 翻译自 `Engine.encodePath()`：命令行参数无法携带 NUL 字节，
  /// engine 用 U+2400 表示它（上游 issue：Appcenter #22305285）。
  static String encodePath(String value) {
    if (!value.contains('\u0000')) return value;
    final StringBuffer buffer = StringBuffer();
    for (final int unit in value.codeUnits) {
      buffer.writeCharCode(unit == 0 ? 0x2400 : unit);
    }
    return buffer.toString();
  }

  /// 下载 —— 翻译自 `Engine.downloadFile()`。
  ///
  /// [item] 是目录时会在 [localPath] 下建同名子目录，与原生一致。
  List<String> downloadArgs(Remote remote, FileItem item, String localPath) {
    final String source = remotePrefix(remote) + item.path;
    final String target = encodePath(
      item.isDir ? '$localPath/${item.name}' : localPath,
    );
    return _transferArgs('copy', source, target);
  }

  Future<Process> download(Remote remote, FileItem item, String localPath) =>
      start(downloadArgs(remote, item, localPath));

  /// 上传 —— 翻译自 `Engine.uploadFile()`。
  Future<Process> upload(
    Remote remote,
    String remoteDir,
    String localFile,
  ) =>
      start(uploadArgs(remote, remoteDir, localFile));

  List<String> uploadArgs(
    Remote remote,
    String remoteDir,
    String localFile,
  ) {
    final String prefix = remotePrefix(remote);
    final bool atRoot = remoteDir == '//${remote.name}';
    String destination;

    if (Directory(localFile).existsSync()) {
      final int slash = localFile.lastIndexOf('/');
      final String dirName =
          slash == -1 ? localFile : localFile.substring(slash + 1);
      destination = atRoot
          ? '$prefix$dirName'
          : '$prefix$remoteDir/$dirName';
    } else {
      destination = atRoot ? prefix : '$prefix$remoteDir';
    }

    return _transferArgs('copy', localFile, destination);
  }

  /// 删除 —— 翻译自 `Engine.deleteItems()`：目录走 `purge`，文件走 `deletefile`。
  Future<EngineResult> deleteItem(Remote remote, FileItem item) {
    final String target = remotePrefix(remote) + item.path;
    return run(
      <String>[item.isDir ? 'purge' : 'deletefile', target],
      withCacheOptions: true,
    );
  }

  /// 生成一个临时直链 —— 翻译自 `Engine.link()`。
  ///
  /// 只对支持直链的远端有效（`Remote.hasLinkSupport`）；
  /// 失败或后端不支持时返回 `null`。
  Future<String?> link(Remote remote, String path) async {
    final String prefix = remotePrefix(remote);
    final String target = path == '//${remote.name}' ? prefix : '$prefix$path';
    final EngineResult result =
        await run(<String>['link', target], withCacheOptions: true);
    if (!result.isSuccess) return null;
    final String url = result.stdout.trim();
    return url.isEmpty ? null : url;
  }

  /// 新建文件夹 —— 翻译自 `Engine.makeDirectory()`。
  Future<bool> makeDirectory(Remote remote, String path) async {
    final String target = remotePrefix(remote) + path;
    final EngineResult result =
        await run(<String>['mkdir', target], withCacheOptions: true);
    return result.isSuccess;
  }

  /// 移动的参数 —— 翻译自 `Engine.moveTo()`。
  List<String> moveArgs(Remote remote, FileItem item, String newLocation) {
    final String prefix = remotePrefix(remote);
    final String name = item.name;
    final String source = prefix + item.path;
    final String destination = newLocation == '//${remote.name}'
        ? '$prefix$name'
        : '$prefix$newLocation/$name';
    return <String>['moveto', source, destination];
  }

  Future<Process> moveItem(
    Remote remote,
    FileItem item,
    String newLocation,
  ) =>
      start(moveArgs(remote, item, newLocation), withCacheOptions: true);

  /// 跨远端（或同远端）复制的参数。
  ///
  /// 原生只有同远端内的 `moveto`；`engine copy` 本身支持 `源远端:路径 目标远端:路径`，
  /// 这里直接利用，作为「跨远端复制」的实现。
  List<String> copyArgs({
    required Remote fromRemote,
    required String fromPath,
    required Remote toRemote,
    required String toPath,
  }) {
    final String source = remotePrefix(fromRemote) + fromPath;
    final String destination = toPath == '//${toRemote.name}'
        ? remotePrefix(toRemote)
        : remotePrefix(toRemote) + toPath;
    return _transferArgs('copy', source, destination);
  }

  /// 移动并等待结束，返回是否成功。
  Future<bool> moveItemAndWait(
    Remote remote,
    FileItem item,
    String newLocation,
  ) async {
    final EngineResult result = await run(
      moveArgs(remote, item, newLocation),
      withCacheOptions: true,
    );
    return result.isSuccess;
  }

  /// 重命名（同目录内 moveto）。
  Future<EngineResult> renameItem(
    Remote remote,
    FileItem item,
    String newName,
  ) {
    final String prefix = remotePrefix(remote);
    final String parent = _parentOf(item.path);
    final String source = prefix + item.path;
    final String destination =
        parent.isEmpty ? '$prefix$newName' : '$prefix$parent/$newName';
    return run(
      <String>['moveto', source, destination],
      withCacheOptions: true,
    );
  }

  // ── 同步任务 ────────────────────────────────────────────────────────

  /// 把任务的定义翻译成 engine 参数 —— 逐行对应 `Engine.sync()`。
  ///
  /// * 方向 1/2 用 `sync`（镜像，会删多余文件），3/4 用 `copy`（只增不删）；
  /// * 双向同步（5/6）在原实现里**未启用**（`Engine.sync()` 直接返回 null），
  ///   这里也返回空列表，调用方据此提示"暂不支持"。
  List<String> syncArgs({
    required Remote remote,
    required SyncTask task,
    List<FilterEntry> filters = const <FilterEntry>[],
  }) {
    if (!task.direction.isSupported) return const <String>[];

    final String prefix = remotePrefix(remote);
    final String remoteSection = task.remotePath == '//${remote.name}'
        ? prefix
        : '$prefix${task.remotePath}';
    final String localSection = task.localPath;

    final List<String> options = <String>[
      '--transfers',
      '1',
      '--stats=1s',
      '--stats-log-level',
      'NOTICE',
      '--use-json-log',
      if (task.useMd5Sum) '--checksum',
      if (task.deleteExcluded) '--delete-excluded',
    ];
    for (final FilterEntry filter in filters) {
      options
        ..add('--filter')
        ..add(filter.toEngineValue());
    }

    final bool localFirst = task.direction == SyncDirection.syncLocalToRemote ||
        task.direction == SyncDirection.copyLocalToRemote;
    final String from = localFirst ? localSection : remoteSection;
    final String to = localFirst ? remoteSection : localSection;

    return <String>[task.direction.operation, from, to, ...options];
  }

  /// 执行一条同步任务，带进度回调。
  Future<TransferProgress> runSync(
    List<String> args, {
    void Function(TransferProgress progress)? onProgress,
    void Function(Process process)? onProcess,
  }) {
    return runTransfer(
      args,
      withCacheOptions: true,
      onProgress: onProgress,
      onProcess: onProcess,
    );
  }

  /// 传输类命令的公共参数：让 engine 输出**每秒一条 JSON 统计**。
  ///
  /// 原生用的是不带 `--use-json-log` 的人类可读统计行再正则解析；
  /// 这里改用 JSON，[TransferProgress.tryParse] 两种都兼容。
  List<String> _transferArgs(String operation, String from, String to) =>
      <String>[
        operation,
        from,
        to,
        '--transfers',
        '1',
        '--stats=1s',
        '--stats-log-level',
        'NOTICE',
        '--use-json-log',
      ];

  /// 运行一条传输命令，边跑边推送 [TransferProgress]。
  ///
  /// 流正常结束时 `Process` 已退出；退出码非 0 且没有上报 errors 时会
  /// 通过 [EngineException] 通知订阅方。
  Stream<TransferProgress> transfer(
    List<String> args, {
    bool withCacheOptions = true,
    void Function(Process process)? onProcess,
  }) {
    final StreamController<TransferProgress> controller =
        StreamController<TransferProgress>();

    Future<void> pump() async {
      final Process process;
      try {
        process = await start(args, withCacheOptions: withCacheOptions);
        onProcess?.call(process);
      } on Object catch (error, stack) {
        controller.addError(error, stack);
        await controller.close();
        return;
      }

      TransferProgress last = const TransferProgress();
      void handle(String line) {
        final TransferProgress? progress = TransferProgress.tryParse(line);
        if (progress == null) return;
        last = progress;
        if (!controller.isClosed) controller.add(progress);
      }

      Future<void> drain(Stream<List<int>> stream) async {
        try {
          await for (final String line
              in stream.transform(utf8.decoder).transform(const LineSplitter())) {
            handle(line);
          }
        } on Object {
          // engine 偶尔会输出非 UTF-8 字节，忽略该行即可。
        }
      }

      await Future.wait<void>(<Future<void>>[
        drain(process.stdout),
        drain(process.stderr),
      ]);

      final int exitCode = await process.exitCode;
      if (exitCode != 0 && last.errors == 0) {
        controller.addError(
          EngineException('传输失败：${args.join(' ')}', exitCode: exitCode),
        );
      }
      await controller.close();
    }

    unawaited(pump());
    return controller.stream;
  }

  /// 跑一条传输命令直到结束，仅返回最后一次进度快照。
  Future<TransferProgress> runTransfer(
    List<String> args, {
    bool withCacheOptions = true,
    void Function(TransferProgress progress)? onProgress,
    void Function(Process process)? onProcess,
  }) async {
    TransferProgress last = const TransferProgress();
    await for (final TransferProgress progress in transfer(
      args,
      withCacheOptions: withCacheOptions,
      onProcess: onProcess,
    )) {
      last = progress;
      onProgress?.call(progress);
    }
    return last;
  }

  static String _parentOf(String path) {
    final int slash = path.lastIndexOf('/');
    return slash <= 0 ? '' : path.substring(0, slash);
  }

  // ── 内部工具 ────────────────────────────────────────────────────────

  static bool _isRemoteRoot(String path, Remote remote) =>
      path == '//${remote.name}' || path.isEmpty || path == '/';

  static String _normalize(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  /// 翻译自 `getDirectoryContent()` 开头拼 `remoteAndPath` 的那段逻辑。
  static String _joinRemotePath(
    Remote remote,
    String path,
    bool startAtRoot,
  ) {
    final StringBuffer buffer = StringBuffer('${remote.name}:');
    if (startAtRoot) buffer.write('/');
    if (remote.isLocal && !remote.isCrypt && !remote.isAlias && !remote.isCache) {
      buffer.write('/');
    }
    if (path != '//${remote.name}') {
      buffer.write(path);
    }
    return buffer.toString();
  }
}
