import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../services/native_bridge.dart';

/// engine 引擎所需的三个关键路径。
///
/// 对应原生 `Engine.java` 构造函数里的：
/// ```java
/// this.engine     = context.getApplicationInfo().nativeLibraryDir + "/engine.so";
/// this.engineConf = context.getFilesDir().getPath() + "/engine.conf";
/// ```
/// Android 不允许执行 `assets/` 里的文件，所以原项目把 **engine 可执行文件
/// 改名成 `engine.so` 放进 `jniLibs/`**，安装时由系统解压到 native 库目录
/// （该目录带可执行权限）。Dart 侧沿用同一套约定，用 `Process` 直接拉起。
class EnginePaths {
  const EnginePaths({
    required this.binary,
    required this.config,
    required this.cache,
    required this.localBase,
    required this.binaryExists,
  });

  /// engine 可执行文件路径。
  final String binary;

  /// `engine.conf` 路径。
  final String config;

  /// 缓存目录，用作 `TMPDIR` / `--cache-*-path`。
  final String cache;

  /// `local` 类型远端在设备上的基准目录。
  ///
  /// 翻译自 `Engine.getLocalRemotePathPrefix()`：
  /// Android 11+ 用 `getExternalFilesDir(null)`（无需任何存储权限），
  /// 更老的系统用外部存储根目录，都拿不到时退到应用私有目录。
  final String localBase;

  /// 启动时是否真的找到了可执行文件（用于设置页给出明确提示）。
  final bool binaryExists;

  static const String _binaryName = 'engine.so';

  static EnginePaths? _cached;

  /// 解析并缓存路径。App 启动时调用一次即可。
  static Future<EnginePaths> resolve() async {
    final EnginePaths? cached = _cached;
    if (cached != null) return cached;

    final Directory support = await getApplicationSupportDirectory();
    final Directory cacheDir = await getApplicationCacheDirectory();

    final String binary = await _resolveBinary();
    final EnginePaths result = EnginePaths(
      binary: binary,
      config: '${support.path}/engine.conf',
      cache: cacheDir.path,
      localBase: await _resolveLocalBase(support),
      binaryExists: File(binary).existsSync(),
    );
    _cached = result;
    return result;
  }

  /// 解析 `local:` 远端的基准目录。
  static Future<String> _resolveLocalBase(Directory support) async {
    try {
      final Directory? external = await getExternalStorageDirectory();
      if (external != null) return external.path;
    } on Object {
      // 非 Android 平台或调用失败，走下面的回退。
    }
    final Directory fallback = Directory('${support.path}/fallback-local');
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    return fallback.path;
  }

  /// 定位 engine 可执行文件。
  ///
  /// 首选：`Platform.resolvedExecutable` 的所在目录 —— 在 Android 上它就是
  /// 应用的 native library 目录（`libapp.so` / `engine.so` 都在这里）。
  /// 其次回退到常见的开发机路径，方便桌面端调试。
  static Future<String> _resolveBinary() async {
    // 首选原生宿主给出的 nativeLibraryDir —— 与原生
    // `context.getApplicationInfo().nativeLibraryDir` 完全等价。
    final String? nativeDir = await NativeBridge.nativeLibraryDir();
    if (nativeDir != null) {
      final String candidate = '$nativeDir/$_binaryName';
      if (File(candidate).existsSync()) return candidate;
    }
    for (final String dir in _candidateDirs()) {
      final String candidate = '$dir/$_binaryName';
      if (File(candidate).existsSync()) return candidate;
    }
    final List<String> candidates = _candidateDirs();
    final String? first = candidates.firstOrNull;
    return '${first ?? '/data/local/tmp'}/$_binaryName';
  }

  static List<String> _candidateDirs() {
    final List<String> dirs = <String>[];
    try {
      dirs.add(File(Platform.resolvedExecutable).parent.path);
    } on Object {
      // 某些平台拿不到 resolvedExecutable，忽略。
    }
    dirs.add(Directory.current.path);
    dirs.add('${Directory.current.path}/android/app/lib/${_abiDirName()}');
    return dirs;
  }

  static String _abiDirName() {
    if (Platform.isAndroid) {
      // 仅在开发机上会走到这里；设备上 nativeLibraryDir 已经命中。
      return 'arm64-v8a';
    }
    return 'x86_64';
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
