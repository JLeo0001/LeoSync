import 'file_item.dart';

/// 目录排序规则 —— 由原生 `FileComparators.java` 移植。
///
/// 原生用 6 个独立 Comparator 类表达，这里收敛成一个枚举。
/// 共同的约定：**目录永远排在文件前面**。
enum FileSort {
  alphaAscending('名称 ↑'),
  alphaDescending('名称 ↓'),
  sizeAscending('大小 ↑'),
  sizeDescending('大小 ↓'),
  modTimeAscending('时间 ↑'),
  modTimeDescending('时间 ↓');

  const FileSort(this.label);

  final String label;

  /// 原地排序，返回新列表。
  List<FileItem> apply(List<FileItem> items) {
    final List<FileItem> sorted = List<FileItem>.of(items);
    sorted.sort(_compare);
    return List<FileItem>.unmodifiable(sorted);
  }

  int _compare(FileItem a, FileItem b) {
    // 目录优先 —— 与 Java 实现里的 if/else 链完全一致。
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;

    final int primary = _comparePrimary(a, b);
    if (primary != 0) return primary;

    // 确定性兜底：Dart 的 List.sort **不保证稳定**（Java 的 Collections.sort
    // 是稳定的），若主键相同则再按名称升序，避免排序结果每次刷新都跳变。
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _comparePrimary(FileItem a, FileItem b) {
    switch (this) {
      case FileSort.alphaAscending:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case FileSort.alphaDescending:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case FileSort.sizeAscending:
        // 两边都是目录时，原实现退化按名称升序比较。
        if (a.isDir && b.isDir) return a.name.compareTo(b.name);
        return a.size.compareTo(b.size);
      case FileSort.sizeDescending:
        if (a.isDir && b.isDir) return a.name.compareTo(b.name);
        return b.size.compareTo(a.size);
      case FileSort.modTimeAscending:
        return a.modTime.compareTo(b.modTime);
      case FileSort.modTimeDescending:
        return b.modTime.compareTo(a.modTime);
    }
  }

  /// 持久化用的稳定标识（枚举名），避免依赖 index 顺序。
  static FileSort fromName(String? name) {
    for (final FileSort value in FileSort.values) {
      if (value.name == name) return value;
    }
    return FileSort.alphaAscending;
  }
}
