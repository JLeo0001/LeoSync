import 'dart:convert';

/// 一次传输任务的实时进度。
///
/// 原生 `FileExplorerFragment` 通过解析 engine 的 stderr 文本来更新进度条；
/// 这里让 engine 带上 `--use-json-log --stats=1s --stats-log-level NOTICE`，
/// 直接读结构化 JSON，解析更稳。
class TransferProgress {
  const TransferProgress({
    this.bytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.etaSeconds = 0,
    this.transfers = 0,
    this.errors = 0,
    this.fileName = '',
    this.percentage,
  });

  final int bytes;
  final int totalBytes;
  final double speed;
  final int etaSeconds;
  final int transfers;
  final int errors;
  final String fileName;

  /// 0–100，未知时为 `null`。
  final double? percentage;

  bool get hasTotal => totalBytes > 0;

  double get ratio => hasTotal ? (bytes / totalBytes).clamp(0, 1) : 0;

  String get humanReadableBytes => _human(bytes);

  String get humanReadableTotal => hasTotal ? _human(totalBytes) : '未知';

  String get humanReadableSpeed => '${_human(speed.round())}/s';

  String get humanReadableEta {
    if (etaSeconds <= 0) return '—';
    final int minutes = etaSeconds ~/ 60;
    final int seconds = etaSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m${seconds}s';
  }

  /// 从一行 engine 日志解析进度；不认识的行走返回 `null`。
  ///
  /// 兼容两种形态：
  /// * `--use-json-log` 的 JSON 行（含 `stats` 对象）
  /// * 默认的人类可读统计行（正则兜底）
  static TransferProgress? tryParse(String line) {
    final String text = line.trim();
    if (text.isEmpty) return null;

    if (text.startsWith('{')) {
      final Object? decoded = _decode(text);
      if (decoded is Map<String, dynamic>) {
        final Object? stats = decoded['stats'];
        if (stats is Map<String, dynamic>) {
          return _fromStats(stats, decoded);
        }
        // 带 stats 的行之外，还有形如 `{"msg":"...","object":"file"}` 的传输事件
        final String msg = decoded['msg'] as String? ?? '';
        if (msg.contains('Transferred:') || msg.contains('Copied')) {
          return TransferProgress(fileName: decoded['object'] as String? ?? '');
        }
      }
      return null;
    }

    return _fromPlainText(text);
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static TransferProgress _fromStats(
    Map<String, dynamic> stats,
    Map<String, dynamic> outer,
  ) {
    final int total = _int(stats['totalBytes']);
    final int bytes = _int(stats['bytes']);
    return TransferProgress(
      bytes: bytes,
      totalBytes: total,
      speed: _double(stats['speed']),
      etaSeconds: _int(stats['eta']),
      transfers: _int(stats['transfers']),
      errors: _int(stats['errors']),
      fileName: outer['object'] as String? ??
          outer['source'] as String? ??
          '',
      percentage: total > 0 ? bytes / total * 100 : null,
    );
  }

  /// 兜底解析形如：
  /// `Transferred:   	   1.234 MiB / 5.678 MiB, 21%, 512 KiB/s, ETA 8s`
  static TransferProgress? _fromPlainText(String text) {
    if (!text.contains('Transferred:')) return null;

    final RegExp percent = RegExp(r'(\d+)%');
    final RegExpMatch? percentMatch = percent.firstMatch(text);
    final RegExpPair? bytes = _parseBytePair(text);
    final RegExp eta = RegExp(r'ETA\s+(\d+)([smh]?)');
    final RegExpMatch? etaMatch = eta.firstMatch(text);

    if (percentMatch == null && bytes == null) return null;

    int etaSeconds = 0;
    if (etaMatch != null) {
      final int value = int.tryParse(etaMatch.group(1) ?? '0') ?? 0;
      switch (etaMatch.group(2)) {
        case 'm':
          etaSeconds = value * 60;
        case 'h':
          etaSeconds = value * 3600;
        default:
          etaSeconds = value;
      }
    }

    return TransferProgress(
      bytes: bytes?.done ?? 0,
      totalBytes: bytes?.total ?? 0,
      etaSeconds: etaSeconds,
      percentage: percentMatch == null
          ? (bytes != null && bytes.total > 0
              ? bytes.done / bytes.total * 100
              : null)
          : double.tryParse(percentMatch.group(1) ?? ''),
    );
  }

  static final RegExp _bytePair = RegExp(
    r'([\d.]+)\s*([KMGTP]?i?B)\s*/\s*([\d.]+)\s*([KMGTP]?i?B)',
    caseSensitive: false,
  );

  static RegExpPair? _parseBytePair(String text) {
    final RegExpMatch? match = _bytePair.firstMatch(text);
    if (match == null) return null;
    return RegExpPair(
      _toBytes(double.tryParse(match.group(1) ?? '0') ?? 0, match.group(2) ?? 'B'),
      _toBytes(double.tryParse(match.group(3) ?? '0') ?? 0, match.group(4) ?? 'B'),
    );
  }

  static int _toBytes(double value, String unit) {
    const Map<String, double> factors = <String, double>{
      'b': 1,
      'kb': 1000,
      'kib': 1024,
      'mb': 1000 * 1000,
      'mib': 1024 * 1024,
      'gb': 1000 * 1000 * 1000,
      'gib': 1024 * 1024 * 1024,
      'tb': 1000 * 1000 * 1000 * 1000,
      'tib': 1024 * 1024 * 1024 * 1024,
      'pb': 1e15,
      'pib': 1024 * 1024 * 1024 * 1024 * 1024,
    };
    return (value * (factors[unit.toLowerCase()] ?? 1)).round();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String _human(int bytes) {
    if (bytes < 1000) return '$bytes B';
    const List<String> units = <String>['kB', 'MB', 'GB', 'TB', 'PB'];
    double value = bytes / 1000;
    var index = 0;
    while (value >= 1000 && index < units.length - 1) {
      value /= 1000;
      index++;
    }
    return '${value.toStringAsFixed(1)} ${units[index]}';
  }
}

class RegExpPair {
  const RegExpPair(this.done, this.total);

  final int done;
  final int total;
}
