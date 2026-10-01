/// 单条过滤规则 —— 由原生 `Items/FilterEntry.java` + `Items/Filter.kt` 移植。
///
/// 存储格式与 engine 的 `--filter` 完全一致：`+ pattern` / `- pattern`。
class FilterEntry {
  const FilterEntry({required this.isInclude, required this.pattern});

  /// `true` = `+`（包含），`false` = `-`（排除）。
  final bool isInclude;

  final String pattern;

  /// 拼成 engine 参数值，注意 `+`/`-` 后面**有一个空格**。
  String toEngineValue() => '${isInclude ? '+' : '-'} $pattern';

  FilterEntry toggle() => FilterEntry(isInclude: !isInclude, pattern: pattern);

  @override
  String toString() => toEngineValue();

  @override
  bool operator ==(Object other) =>
      other is FilterEntry &&
      other.isInclude == isInclude &&
      other.pattern == pattern;

  @override
  int get hashCode => Object.hash(isInclude, pattern);
}

/// 一组过滤规则 —— 对应原生 `filter_table` 里的一行。
///
/// 原生把多条规则用 `System.lineSeparator()` 拼成一个字符串存进
/// `filter_filters` 列，这里保持同样的序列化格式。
class SyncFilter {
  const SyncFilter({
    required this.id,
    this.title = '',
    this.entries = const <FilterEntry>[],
  });

  final int id;
  final String title;
  final List<FilterEntry> entries;

  static const String tableName = 'filter_table';
  static const String columnId = 'filter_id';
  static const String columnTitle = 'filter_title';
  static const String columnFilters = 'filter_filters';

  SyncFilter copyWith({String? title, List<FilterEntry>? entries}) =>
      SyncFilter(
        id: id,
        title: title ?? this.title,
        entries: entries ?? this.entries,
      );

  /// 解析 `filter_filters` 列的原始文本。
  ///
  /// 原生按行切分，每行首字符决定包含 / 排除，空行会被跳过。
  static List<FilterEntry> parseRaw(String raw) {
    final List<FilterEntry> out = <FilterEntry>[];
    for (final String line in raw.split(RegExp(r'\r?\n'))) {
      if (line.isEmpty) continue;
      final String head = line.substring(0, 1);
      if (head != '+' && head != '-') continue;
      out.add(FilterEntry(isInclude: head == '+', pattern: line.substring(1)));
    }
    return out;
  }

  /// 序列化回 `filter_filters` 列的格式（与原生一致：每行末尾带换行）。
  static String serialize(List<FilterEntry> entries) {
    final StringBuffer buffer = StringBuffer();
    for (final FilterEntry entry in entries) {
      buffer
        ..write(entry.isInclude ? '+' : '-')
        ..write(entry.pattern)
        ..writeln();
    }
    return buffer.toString();
  }

  /// 从 DB 行构造。
  static SyncFilter fromRow(Map<String, Object?> row) => SyncFilter(
        id: (row[columnId] as int?) ?? 0,
        title: (row[columnTitle] as String?) ?? '',
        entries: parseRaw((row[columnFilters] as String?) ?? ''),
      );

  Map<String, Object?> toRow() => <String, Object?>{
        columnId: id,
        columnTitle: title,
        columnFilters: serialize(entries),
      };

  @override
  String toString() => 'SyncFilter($id, $title, ${entries.length} 条规则)';
}
