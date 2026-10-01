import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/models/file_item.dart';
import 'package:leosync/core/models/remote.dart';

void main() {
  group('FileItem.sizeToHumanReadable（移植自 FileItem.java）', () {
    test('小于 1000 字节时显示为 B', () {
      expect(FileItem.sizeToHumanReadable(0), '0 B');
      expect(FileItem.sizeToHumanReadable(999), '999 B');
    });

    test('以 1000 为进制逐级进位', () {
      expect(FileItem.sizeToHumanReadable(1000), '1.0 kB');
      expect(FileItem.sizeToHumanReadable(1500), '1.5 kB');
      expect(FileItem.sizeToHumanReadable(1000000), '1.0 MB');
      expect(FileItem.sizeToHumanReadable(2500000000), '2.5 GB');
    });
  });

  group('FileItem.fromLsJson', () {
    final Remote remote = Remote(name: 'mydrive', type: 'drive');

    test('根目录下的条目路径就是文件名', () {
      final FileItem item = FileItem.fromLsJson(
        remote,
        <String, dynamic>{
          'Path': 'a.txt',
          'Name': 'a.txt',
          'Size': 12,
          'ModTime': '2024-01-02T03:04:05.123456789Z',
          'IsDir': false,
          'MimeType': 'text/plain',
        },
        parentPath: '',
        startAtRoot: true,
      );
      expect(item.path, 'a.txt');
      expect(item.name, 'a.txt');
      expect(item.humanReadableSize, '12 B');
      expect(item.isDir, isFalse);
    });

    test('子目录下的条目会拼上父路径', () {
      final FileItem item = FileItem.fromLsJson(
        remote,
        <String, dynamic>{
          'Path': 'b/c',
          'Name': 'c',
          'Size': 0,
          'ModTime': '2024-01-02T03:04:05Z',
          'IsDir': true,
          'MimeType': 'inode/directory',
        },
        parentPath: 'b',
        startAtRoot: true,
      );
      expect(item.path, 'b/c');
      expect(item.isDir, isTrue);
    });

    test('9 位纳秒能被正确解析（Dart 只吃 6 位）', () {
      final FileItem item = FileItem.fromLsJson(
        remote,
        <String, dynamic>{
          'Path': 'x',
          'Name': 'x',
          'Size': 0,
          'ModTime': '2024-01-02T03:04:05.123456789Z',
          'IsDir': false,
          'MimeType': '',
        },
        parentPath: '',
        startAtRoot: false,
      );
      expect(
        item.modTime,
        DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456).millisecondsSinceEpoch,
      );
    });

    test('时间戳非法时回落到 -1', () {
      final FileItem item = FileItem.fromLsJson(
        remote,
        <String, dynamic>{
          'Path': 'x',
          'Name': 'x',
          'Size': 0,
          'ModTime': 'not-a-date',
          'IsDir': false,
          'MimeType': '',
        },
        parentPath: '',
        startAtRoot: false,
      );
      expect(item.modTime, -1);
    });

    test('crypt 远端按明文扩展名重推 MIME', () {
      final Remote crypt = Remote(name: 'sec', type: 'drive', isCrypt: true);
      final FileItem item = FileItem.fromLsJson(
        crypt,
        <String, dynamic>{
          'Path': 'photo.jpg.abc123',
          'Name': 'photo.jpg.abc123',
          'Size': 1,
          'ModTime': '2024-01-02T03:04:05Z',
          'IsDir': false,
          'MimeType': 'application/octet-stream',
        },
        parentPath: '',
        startAtRoot: false,
      );
      // 扩展名 abc123 未知 → 保留原 MIME
      expect(item.mimeType, 'application/octet-stream');
    });
  });

  group('FileItem.mimeTypeFromPath', () {
    test('常见扩展名', () {
      expect(FileItem.mimeTypeFromPath('a.png'), 'image/png');
      expect(FileItem.mimeTypeFromPath('dir/b.MP4'), 'video/mp4');
      expect(FileItem.mimeTypeFromPath('noext'), isNull);
      expect(FileItem.mimeTypeFromPath('trailing.'), isNull);
    });
  });

  group('Remote', () {
    test('从 engine config dump 节点构造', () {
      final Remote remote = Remote.fromConfigDump('my', <String, dynamic>{
        'type': 's3',
        'provider': 'AWS',
      });
      expect(remote.name, 'my');
      expect(remote.type, 's3');
      expect(remote.isOAuth, isFalse);
      expect(remote.hasTrashCan, isFalse);
    });

    test('SAF 伪装成 webdav 时会被识别回 saf', () {
      final Remote remote = Remote.fromConfigDump('saf', <String, dynamic>{
        'type': 'webdav',
        'url': '${Remote.safRemoteUrlPrefix}device',
      });
      expect(remote.isSaf, isTrue);
      expect(remote.hasSyncSupport, isFalse);
    });

    test('能力判定与原生 RemoteItem 保持一致', () {
      expect(Remote(name: 'g', type: 'drive').hasTrashCan, isTrue);
      expect(Remote(name: 'd', type: 'dropbox').supportsDirectoryModifiedTime,
          isFalse);
      expect(Remote(name: 'l', type: 'local').hasLinkSupport, isFalse);
      expect(Remote(name: 'c', type: 'crypt').hasLinkSupport, isFalse);
      expect(Remote(name: 'w', type: 'webdav').hasLinkSupport, isTrue);
    });

    test('label 在未重命名时回落到 name', () {
      expect(Remote(name: 'a', type: 's3').label, 'a');
      expect(Remote(name: 'a', type: 's3', displayName: '别名').label, '别名');
    });
  });
}
