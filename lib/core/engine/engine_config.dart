/// `engine.conf` 的 INI 解析 / 序列化。
///
/// 原生版只通过 `engine config dump`（JSON）读取配置，写回则交给
/// `engine config create/update/delete`。这里额外提供一个纯 Dart 的解析器：
/// 便于做「从原生版平滑迁移」（直接读取旧 `engine.conf`）、导入导出与备份。
///
/// 文件格式（无值可跨行，`key = value` 取第一个 `=` 切分）：
///
/// ```ini
/// [mydrive]
/// type = drive
/// scope = drive
/// token = {"access_token":"ya29...."}
/// ```
class EngineConf {
  EngineConf([Map<String, Map<String, String>>? sections])
      : _sections = sections ?? <String, Map<String, String>>{};

  final Map<String, Map<String, String>> _sections;

  /// 节名 → 键值对。返回的是**只读视图**，改动请走 [setValue] 等方法。
  Map<String, Map<String, String>> get sections =>
      Map<String, Map<String, String>>.unmodifiable(
        _sections.map(
          (String k, Map<String, String> v) =>
              MapEntry<String, Map<String, String>>(
            k,
            Map<String, String>.unmodifiable(v),
          ),
        ),
      );

  List<String> get names => _sections.keys.toList(growable: false);

  bool get isEmpty => _sections.isEmpty;

  Map<String, String>? operator [](String name) => _sections[name];

  bool has(String name) => _sections.containsKey(name);

  /// 追加一个远端节。类型会被写成 `type` 键（engine 的约定）。
  void add(String name, String type, [Map<String, String>? values]) {
    final Map<String, String> section = <String, String>{'type': type};
    if (values != null) section.addAll(values);
    _sections[name] = section;
  }

  void remove(String name) => _sections.remove(name);

  void rename(String from, String to) {
    final Map<String, String>? section = _sections.remove(from);
    if (section != null) _sections[to] = section;
  }

  void setValue(String name, String key, String? value) {
    final Map<String, String>? section = _sections[name];
    if (section == null) return;
    if (value == null || value.isEmpty) {
      section.remove(key);
    } else {
      section[key] = value;
    }
  }

  /// 解析 `engine.conf` 文本。无法识别的行会被忽略（与 engine 一致地宽容）。
  static EngineConf parse(String text) {
    final EngineConf conf = EngineConf();
    Map<String, String>? current;

    for (final String rawLine in text.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        final String name = line.substring(1, line.length - 1).trim();
        if (name.isEmpty) continue;
        current = <String, String>{};
        conf._sections[name] = current;
        continue;
      }
      final int eq = line.indexOf('=');
      if (eq <= 0 || current == null) continue;
      final String key = line.substring(0, eq).trim();
      final String value = line.substring(eq + 1).trim();
      if (key.isNotEmpty) current[key] = value;
    }
    return conf;
  }

  /// 序列化回 `engine.conf` 文本，节之间空一行。
  String serialize() {
    final StringBuffer buffer = StringBuffer();
    var first = true;
    for (final MapEntry<String, Map<String, String>> section in _sections.entries) {
      if (!first) buffer.writeln();
      first = false;
      buffer.writeln('[${section.key}]');
      for (final MapEntry<String, String> kv in section.value.entries) {
        buffer.writeln('${kv.key} = ${kv.value}');
      }
    }
    return buffer.toString();
  }

  @override
  String toString() => 'EngineConf(${names.join(', ')})';
}
