import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/models/file_item.dart';
import 'package:leosync/core/models/remote.dart';
import 'package:leosync/core/engine/engine_client.dart';
import 'package:leosync/core/engine/engine_paths.dart';
import 'package:leosync/core/services/connectivity_service.dart';
import 'package:leosync/widgets/file_thumbnail.dart';

const EnginePaths _paths = EnginePaths(
  binary: '/nonexistent/engine.so',
  config: '/tmp/engine.conf',
  cache: '/tmp/cache',
  localBase: '/base',
  binaryExists: false,
);

FileItem _item(String name, String path, {bool isDir = false, String mime = ''}) {
  return FileItem(
    remote: Remote(name: 'r', type: 'drive'),
    path: path,
    name: name,
    size: 0,
    modTime: 0,
    mimeType: mime,
    isDir: isDir,
  );
}

void main() {
  group('EngineClient.moveArgs —— 对照 Engine.moveTo()', () {
    final EngineClient client = EngineClient(paths: _paths);
    final Remote remote = Remote(name: 'myr', type: 's3');

    test('移动到子目录：目标拼上原文件名', () {
      final List<String> args = client.moveArgs(
        remote,
        _item('a.txt', '/docs/a.txt'),
        '/archive',
      );
      expect(args, <String>['moveto', 'myr:/docs/a.txt', 'myr:/archive/a.txt']);
    });

    test('移动到根目录（//name）时不带中间路径', () {
      final List<String> args = client.moveArgs(
        remote,
        _item('a.txt', '/docs/a.txt'),
        '//myr',
      );
      expect(args, <String>['moveto', 'myr:/docs/a.txt', 'myr:a.txt']);
    });

    test('local 远端会带上基准目录前缀', () {
      final Remote local = Remote(name: 'sd', type: 'local');
      final List<String> args = client.moveArgs(
        local,
        _item('a.txt', '/a.txt'),
        '/dest',
      );
      expect(args[1], 'sd:/base//a.txt');
      expect(args[2], 'sd:/base//dest/a.txt');
    });
  });

  group('EngineClient.link', () {
    test('远端根目录用 `name:` 形式', () {
      // link() 内部会执行进程，这里只验证路径拼接逻辑不走偏：
      // 通过 syncArgs 的同类推导间接确认 remotePrefix 行为一致。
      final EngineClient client = EngineClient(paths: _paths);
      final Remote local = Remote(name: 'sd', type: 'local');
      expect(client.remotePrefix(local), 'sd:/base/');
      expect(client.localPrefix(local), '/base/');
    });

    test('非 local 远端没有本地前缀', () {
      final EngineClient client = EngineClient(paths: _paths);
      expect(client.remotePrefix(Remote(name: 'x', type: 's3')), 'x:');
      expect(client.localPrefix(Remote(name: 'x', type: 's3')), '');
    });
  });

  group('DataConnection —— 对照 WifiConnectivitiyUtil', () {
    test('只有 connected 允许跑「仅 Wi-Fi」任务', () {
      expect(DataConnection.connected.allowsUnmetered, isTrue);
      expect(DataConnection.metered.allowsUnmetered, isFalse);
      expect(DataConnection.notAvailable.allowsUnmetered, isFalse);
      expect(DataConnection.disconnected.allowsUnmetered, isFalse);
    });
  });

  group('FileThumbnail.iconFor', () {
    test('按 MIME 选图标', () {
      expect(FileThumbnail.iconFor(_item('d', '/d', isDir: true)),
          Icons.folder_outlined);
      expect(FileThumbnail.iconFor(_item('a', '/a', mime: 'image/png')),
          Icons.image_outlined);
      expect(FileThumbnail.iconFor(_item('a', '/a', mime: 'video/mp4')),
          Icons.movie_outlined);
      expect(FileThumbnail.iconFor(_item('a', '/a', mime: 'audio/mpeg')),
          Icons.music_note_outlined);
      expect(FileThumbnail.iconFor(_item('a', '/a', mime: 'application/pdf')),
          Icons.picture_as_pdf_outlined);
      expect(FileThumbnail.iconFor(_item('a', '/a', mime: 'application/zip')),
          Icons.folder_zip_outlined);
      expect(
        FileThumbnail.iconFor(
          _item('a', '/a', mime: 'application/octet-stream'),
        ),
        Icons.insert_drive_file_outlined,
      );
    });
  });
}
