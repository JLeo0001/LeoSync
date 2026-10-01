import 'dart:io';
import 'dart:math' as math;

import 'remote.dart';

/// 远端上的一个文件/目录条目 —— 由原生 `Items/FileItem.java` 移植。
class FileItem {
  FileItem({
    required this.remote,
    required this.path,
    required this.name,
    required this.size,
    required this.modTime,
    required this.mimeType,
    required this.isDir,
    this.startAtRoot = false,
  })  : humanReadableSize = sizeToHumanReadable(size),
        humanReadableModTime = modTimeToHumanReadable(modTime),
        formattedModTime = modTimeToFormattedTime(modTime);

  final Remote remote;
  final String path;
  final String name;
  final int size;

  /// 毫秒时间戳；解析失败时为 `-1`（原实现的约定）。
  final int modTime;

  final String mimeType;
  final bool isDir;
  final bool startAtRoot;

  final String humanReadableSize;
  final String humanReadableModTime;
  final String formattedModTime;

  /// 移植自 `FileItem.getPath()`：`startAtRoot` 时补上前导 `/`。
  String get normalizedPath {
    if (startAtRoot && !path.startsWith('/')) return '/$path';
    return path;
  }

  /// `engine lsjson` 的单项 → [FileItem]。
  ///
  /// 对应原生 `Engine.getDirectoryContent()` 里逐个字段的解码逻辑。
  static FileItem fromLsJson(
    Remote remote,
    Map<String, dynamic> json, {
    required String parentPath,
    required bool startAtRoot,
  }) {
    final name = json['Name'] as String? ?? '';
    final isDir = json['IsDir'] as bool? ?? false;
    final path = parentPath.isEmpty ? name : '$parentPath/$name';
    var mimeType = json['MimeType'] as String? ?? '';

    // crypt 远端上报的是加密后文件名，需要按**明文**扩展名重新推断 MIME。
    if (remote.isCrypt) {
      mimeType = mimeTypeFromPath(name) ?? mimeType;
    }

    return FileItem(
      remote: remote,
      path: path,
      name: name,
      size: _asInt(json['Size']),
      modTime: _parseRfc3339(json['ModTime'] as String?),
      mimeType: mimeType,
      isDir: isDir,
      startAtRoot: startAtRoot,
    );
  }

  @override
  String toString() => 'FileItem($path${isDir ? '/' : ''})';

  @override
  bool operator ==(Object other) =>
      other is FileItem &&
      other.remote == remote &&
      other.normalizedPath == normalizedPath &&
      other.name == name;

  @override
  int get hashCode => Object.hash(remote, normalizedPath, name);

  // ── 工具方法（移植自 FileItem 的私有 helper） ─────────────────────────

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 解析 engine 的 RFC3339 时间戳（可带纳秒），失败返回 `-1`。
  ///
  /// Dart 的 [DateTime.parse] 只接受最多 6 位小数秒，engine 会输出 9 位，
  /// 所以这里先把小数秒裁剪到 6 位。
  static int _parseRfc3339(String? raw) {
    if (raw == null || raw.isEmpty) return -1;
    var value = raw.trim();
    final dot = value.indexOf('.');
    if (dot != -1) {
      final int stop = _fractionEnd(value, dot + 1);
      final String fraction = value.substring(dot + 1, stop);
      if (fraction.length > 6) {
        value = value.replaceRange(dot + 1, stop, fraction.substring(0, 6));
      }
    }
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? -1;
  }

  /// 找出小数秒的结束位置（时区标记 `Z` / `+` / `-` 或字符串结尾）。
  static int _fractionEnd(String value, int from) {
    for (var i = from; i < value.length; i++) {
      final int c = value.codeUnitAt(i);
      if (c == 0x5A || c == 0x2B || c == 0x2D) return i;
    }
    return value.length;
  }

  /// 移植自 `FileItem.sizeToHumanReadable()`，同样以 1000 为进制。
  static String sizeToHumanReadable(int size) {
    const int unit = 1000;
    if (size < unit) return '$size B';
    final int exponent = (math.log(size) / math.log(unit)).floor();
    if (exponent < 1) return '$size B';
    const String prefixes = 'kMGTPE';
    final String prefix = exponent - 1 < prefixes.length
        ? prefixes[exponent - 1]
        : prefixes[prefixes.length - 1];
    final double scaled = size / math.pow(unit, exponent);
    return '${scaled.toStringAsFixed(1)} ${prefix}B';
  }

  /// 移植自 `FileItem.modTimeToHumanReadable()`：近 1 分钟内显示为“刚刚”。
  static String modTimeToHumanReadable(int modTime) {
    if (modTime < 1) return '';
    final DateTime then = DateTime.fromMillisecondsSinceEpoch(modTime);
    final Duration delta = DateTime.now().difference(then);
    if (delta.isNegative || delta.inMinutes < 1) return '刚刚';
    if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
    if (delta.inHours < 24) return '${delta.inHours} 小时前';
    if (delta.inDays < 30) return '${delta.inDays} 天前';
    return modTimeToFormattedTime(modTime);
  }

  /// 移植自 `FileItem.modTimeToFormattedTime()`。
  static String modTimeToFormattedTime(int modTime) {
    if (modTime < 1) return '';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(modTime);
    return '${t.year}-${_pad(t.month)}-${_pad(t.day)} '
        '${_pad(t.hour)}:${_pad(t.minute)}';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');

  /// 移植自 `FileItem.getMimeType()`：`application/octet-stream` 时按扩展名兜底。
  static String? mimeTypeFromPath(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return null;
    final String ext = path.substring(dot + 1).toLowerCase();
    return _mimeByExtension[ext];
  }

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'flac': 'audio/flac',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'htm': 'text/html',
    'csv': 'text/csv',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/vnd.rar',
    'apk': 'application/vnd.android.package-archive',
    'epub': 'application/epub+zip',
    'mobi': 'application/x-mobipocket-ebook',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
}

/// 判断给定路径是否是文件系统可直接访问的本地路径。
bool isLocalPath(String value) =>
    value.startsWith('/') || (Platform.isWindows && value.contains(':\\'));
