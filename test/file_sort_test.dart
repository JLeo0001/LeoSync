import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/models/file_item.dart';
import 'package:leosync/core/models/file_sort.dart';
import 'package:leosync/core/models/remote.dart';

final Remote _remote = Remote(name: 'r', type: 'drive');

FileItem _item(
  String name, {
  int size = 0,
  int modTime = 0,
  bool isDir = false,
}) {
  return FileItem(
    remote: _remote,
    path: name,
    name: name,
    size: size,
    modTime: modTime,
    mimeType: '',
    isDir: isDir,
  );
}

List<String> _names(List<FileItem> items) =>
    items.map((FileItem e) => e.name).toList();

void main() {
  final List<FileItem> sample = <FileItem>[
    _item('banana', size: 300, modTime: 3000),
    _item('apple', size: 100, modTime: 1000),
    _item('subdir', isDir: true),
    _item('cherry', size: 200, modTime: 2000),
    _item('adir', isDir: true),
  ];

  group('FileSort —— 移植自 FileComparators.java', () {
    test('目录永远排在文件前面，且目录之间按名称升序', () {
      final List<String> names = _names(FileSort.modTimeAscending.apply(sample));
      expect(names.sublist(0, 2), <String>['adir', 'subdir']);
    });

    test('名称升序 / 降序', () {
      expect(
        _names(FileSort.alphaAscending.apply(sample)),
        <String>['adir', 'subdir', 'apple', 'banana', 'cherry'],
      );
      // 降序时目录同样按名称降序 —— 与 Java 的 SortAlphaDescending 一致，
      // 只有主键相同的项才走确定性兜底。
      expect(
        _names(FileSort.alphaDescending.apply(sample)),
        <String>['subdir', 'adir', 'cherry', 'banana', 'apple'],
      );
    });

    test('大小升序 / 降序', () {
      expect(
        _names(FileSort.sizeAscending.apply(sample)),
        <String>['adir', 'subdir', 'apple', 'cherry', 'banana'],
      );
      expect(
        _names(FileSort.sizeDescending.apply(sample)),
        <String>['adir', 'subdir', 'banana', 'cherry', 'apple'],
      );
    });

    test('时间升序 / 降序', () {
      expect(
        _names(FileSort.modTimeAscending.apply(sample)),
        <String>['adir', 'subdir', 'apple', 'cherry', 'banana'],
      );
      expect(
        _names(FileSort.modTimeDescending.apply(sample)),
        <String>['adir', 'subdir', 'banana', 'cherry', 'apple'],
      );
    });

    test('大小排序时，两个目录之间按名称升序（原实现的特例）', () {
      final List<FileItem> dirs = <FileItem>[
        _item('zeta', isDir: true, size: 999),
        _item('alpha', isDir: true, size: 1),
      ];
      expect(
        _names(FileSort.sizeDescending.apply(dirs)),
        <String>['alpha', 'zeta'],
      );
    });

    test('不修改传入的列表', () {
      final List<FileItem> original = List<FileItem>.of(sample);
      FileSort.alphaDescending.apply(sample);
      expect(_names(sample), _names(original));
    });

    test('fromName 对未知值回落到名称升序', () {
      expect(FileSort.fromName('sizeDescending'), FileSort.sizeDescending);
      expect(FileSort.fromName('nope'), FileSort.alphaAscending);
      expect(FileSort.fromName(null), FileSort.alphaAscending);
    });
  });
}
