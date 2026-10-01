import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 应用日志 —— 由原生 `Log2File.java` + `util/FLog.java` 移植。
///
/// 原生把 engine 的 stderr 落到 `files/logs/log.txt`；这里做同样的事，
/// 同时保留一份内存环形缓冲供「日志」页即时查看（不必反复读文件）。
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 内存里最多保留多少行。
  static const int maxLines = 2000;

  final List<String> _buffer = <String>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  File? _file;
  bool _enabled = false;

  bool get enabled => _enabled;

  /// 日志变化通知（供日志页刷新）。
  Stream<void> get changes => _changes.stream;

  List<String> get lines => List<String>.unmodifiable(_buffer);

  File? get file => _file;

  /// 初始化日志文件。对应原生 `Log2File` 的构造函数。
  static Future<AppLog> initialize({required String filesDir}) async {
    final AppLog log = instance;
    final Directory dir = Directory('$filesDir/logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    log._file = File('${dir.path}/log.txt');
    return log;
  }

  /// 是否把日志写盘。对应设置里的「记录详细日志」。
  void setEnabled(bool value) {
    _enabled = value;
    if (value) {
      info('日志记录已开启');
    } else {
      info('日志记录已关闭');
    }
  }

  void info(String message) => _write('INFO', message);

  void warn(String message) => _write('WARN', message);

  void error(String message) => _write('ERROR', message);

  /// engine 的原样输出（可能多行）。
  void engineOutput(String output) {
    for (final String line in output.split('\n')) {
      if (line.trim().isEmpty) continue;
      _write('ENGINE', line);
    }
  }

  void _write(String level, String message) {
    final String line = '${_timestamp()} [$level] $message';
    _buffer.add(line);
    if (_buffer.length > maxLines) {
      _buffer.removeRange(0, _buffer.length - maxLines);
    }

    if (_enabled) {
      try {
        _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } on Object catch (error) {
        debugPrint('写入日志失败：$error');
      }
    }

    if (!_changes.isClosed) _changes.add(null);
  }

  static String _timestamp() {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  /// 清空内存缓冲与日志文件。
  Future<void> clear() async {
    _buffer.clear();
    try {
      await _file?.writeAsString('');
    } on Object catch (error) {
      debugPrint('清空日志失败：$error');
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  /// 把整份日志读成字符串（用于复制 / 分享）。
  String export() => _buffer.join('\n');
}
