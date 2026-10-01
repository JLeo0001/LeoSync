import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/models/remote.dart';
import 'package:leosync/core/models/sync_direction.dart';
import 'package:leosync/core/models/sync_filter.dart';
import 'package:leosync/core/models/sync_task.dart';
import 'package:leosync/core/models/trigger.dart';
import 'package:leosync/core/engine/engine_client.dart';
import 'package:leosync/core/engine/engine_paths.dart';

const EnginePaths _paths = EnginePaths(
  binary: '/nonexistent/engine.so',
  config: '/tmp/engine.conf',
  cache: '/tmp/cache',
  localBase: '/storage/emulated/0/Android/data/com.jleoz.sync/files',
  binaryExists: false,
);

void main() {
  group('SyncDirection —— 移植自 SyncDirectionObject.java', () {
    test('数值与原生一致（务必不要改动）', () {
      expect(SyncDirection.syncLocalToRemote.value, 1);
      expect(SyncDirection.syncRemoteToLocal.value, 2);
      expect(SyncDirection.copyLocalToRemote.value, 3);
      expect(SyncDirection.copyRemoteToLocal.value, 4);
      expect(SyncDirection.bisyncInitial.value, 5);
      expect(SyncDirection.bisync.value, 6);
    });

    test('sync 用 sync 子命令，copy 用 copy 子命令', () {
      expect(SyncDirection.syncLocalToRemote.operation, 'sync');
      expect(SyncDirection.copyRemoteToLocal.operation, 'copy');
    });

    test('bisync 未启用 —— 与原生 sync_direction_array.xml 保持一致', () {
      expect(SyncDirection.bisyncInitial.isSupported, isFalse);
      expect(SyncDirection.bisync.isSupported, isFalse);
      expect(SyncDirection.selectable, hasLength(4));
      expect(SyncDirection.bisyncInitial.needsResync, isTrue);
    });

    test('fromValue 对未知值回落到本地→远端', () {
      expect(SyncDirection.fromValue(3), SyncDirection.copyLocalToRemote);
      expect(SyncDirection.fromValue(99), SyncDirection.syncLocalToRemote);
    });
  });

  group('SyncFilter —— filter_filters 列的序列化', () {
    test('解析原生存储格式', () {
      // 每行形如 "+ *.png"，末尾带换行
      const String raw = '+ *.png\n- *.tmp\n+ *\n';
      final List<FilterEntry> entries = SyncFilter.parseRaw(raw);
      expect(entries, hasLength(3));
      expect(entries[0].isInclude, isTrue);
      expect(entries[0].pattern, ' *.png');
      expect(entries[1].isInclude, isFalse);
      expect(entries[1].pattern, ' *.tmp');
    });

    test('忽略空行与非法行', () {
      const String raw = '\n+ a\n\n? b\n';
      final List<FilterEntry> entries = SyncFilter.parseRaw(raw);
      expect(entries, hasLength(1));
      expect(entries.single.pattern, ' a');
    });

    test('序列化后能原样解析回来', () {
      final List<FilterEntry> original = <FilterEntry>[
        const FilterEntry(isInclude: true, pattern: ' *.mp4'),
        const FilterEntry(isInclude: false, pattern: '/.git/**'),
      ];
      final String raw = SyncFilter.serialize(original);
      expect(SyncFilter.parseRaw(raw), original);
    });

    test('toEngineValue 的格式与 engine --filter 一致（+/- 后有空格）', () {
      expect(
        const FilterEntry(isInclude: true, pattern: '*.png').toEngineValue(),
        '+ *.png',
      );
      expect(
        const FilterEntry(isInclude: false, pattern: '*.tmp').toEngineValue(),
        '- *.tmp',
      );
    });

    test('fromRow / toRow 往返', () {
      const SyncFilter filter = SyncFilter(
        id: 7,
        title: '图片',
        entries: <FilterEntry>[
          FilterEntry(isInclude: true, pattern: ' *.jpg'),
        ],
      );
      final Map<String, Object?> row = filter.toRow();
      final SyncFilter back = SyncFilter.fromRow(row);
      expect(back.id, 7);
      expect(back.title, '图片');
      expect(back.entries, filter.entries);
    });
  });

  group('Trigger —— 星期位掩码', () {
    test('默认每天（0b01111111）', () {
      const Trigger trigger = Trigger();
      expect(trigger.weekdayMask, 0x7F);
      expect(trigger.weekdaySummary, '每天');
      for (var day = 0; day < 7; day++) {
        expect(trigger.isEnabledAtDay(day), isTrue);
      }
    });

    test('bit 0 是周一 —— 与原生注释一致', () {
      const Trigger monday = Trigger(weekdayMask: 0x01);
      expect(monday.isEnabledAtDay(0), isTrue);
      expect(monday.isEnabledAtDay(1), isFalse);
      expect(monday.weekdaySummary, '周一');
    });

    test('setEnabledAtDay 增删位', () {
      const Trigger none = Trigger(weekdayMask: 0x00);
      final Trigger monday = none.setEnabledAtDay(0, true);
      expect(monday.weekdayMask, 0x01);

      final Trigger back = monday.setEnabledAtDay(0, false);
      expect(back.weekdayMask, 0x00);
      expect(back.weekdaySummary, '从不');
    });

    test('工作日 / 周末摘要', () {
      expect(const Trigger(weekdayMask: 0x1F).weekdaySummary, '工作日');
      expect(const Trigger(weekdayMask: 0x60).weekdaySummary, '周末');
    });

    test('时间格式化 —— time 的单位是分钟，不是 Trigger.kt 注释里的秒', () {
      expect(const Trigger(time: 0).humanReadableTime, '00:00');
      // 09:30 → 9 * 60 + 30 = 570 分钟（原生 TriggerActivity.kt:179）
      expect(const Trigger(time: 570).humanReadableTime, '09:30');
      expect(const Trigger(time: 23 * 60 + 59).humanReadableTime, '23:59');
    });

    test('fromRow / toRow 往返', () {
      const Trigger trigger = Trigger(
        id: 3,
        title: '夜间备份',
        isEnabled: false,
        weekdayMask: 0x1F,
        time: 7200,
        triggerTarget: 42,
        type: TriggerType.interval,
      );
      final Trigger back = Trigger.fromRow(trigger.toRow());
      expect(back.id, 3);
      expect(back.title, '夜间备份');
      expect(back.isEnabled, isFalse);
      expect(back.weekdayMask, 0x1F);
      expect(back.time, 7200);
      expect(back.triggerTarget, 42);
      expect(back.type, TriggerType.interval);
    });
  });

  group('SyncTask —— 表行列名与原生一致', () {
    test('列名不能改（老用户数据库靠它接管）', () {
      expect(SyncTask.tableName, 'task_table');
      expect(SyncTask.columnId, 'task_id');
      expect(SyncTask.columnMd5Sum, 'task_use_md5sum');
      expect(SyncTask.columnWifiOnly, 'task_use_only_wifi');
      expect(SyncTask.columnOnFail, 'task_onFailFollowupTask');
      expect(SyncTask.columnOnSuccess, 'task_onSuccessFollowupTask');
      expect(Trigger.columnWeekday, 'trigger_weekday');
      expect(SyncFilter.columnFilters, 'filter_filters');
    });

    test('fromRow / toRow 往返（布尔存 0/1）', () {
      const SyncTask task = SyncTask(
        id: 5,
        title: '照片备份',
        remoteId: 'mydrive',
        remotePath: '/photos',
        localPath: '/sdcard/DCIM',
        direction: SyncDirection.copyLocalToRemote,
        useMd5Sum: true,
        wifiOnly: true,
        filterId: 2,
        deleteExcluded: true,
      );
      final Map<String, Object?> row = task.toRow();
      expect(row[SyncTask.columnMd5Sum], 1);
      expect(row[SyncTask.columnWifiOnly], 1);

      final SyncTask back = SyncTask.fromRow(row);
      expect(back.id, 5);
      expect(back.direction, SyncDirection.copyLocalToRemote);
      expect(back.useMd5Sum, isTrue);
      expect(back.wifiOnly, isTrue);
      expect(back.filterId, 2);
      expect(back.deleteExcluded, isTrue);
    });

    test('INSERT 用的行不含 id', () {
      const SyncTask task = SyncTask(id: 9, title: 'x');
      expect(task.toRow(includeId: false).containsKey(SyncTask.columnId), isFalse);
      expect(task.toRow().containsKey(SyncTask.columnId), isTrue);
    });
  });

  group('EngineClient.syncArgs —— 逐行对照 Engine.sync()', () {
    final EngineClient client = EngineClient(paths: _paths);
    final Remote remote = Remote(name: 'myr', type: 's3');

    test('本地 → 远端：sync 子命令', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(
          remoteId: 'myr',
          remotePath: '/photos',
          localPath: '/local',
          direction: SyncDirection.syncLocalToRemote,
        ),
      );
      expect(args, <String>[
        'sync',
        '/local',
        'myr:/photos',
        '--transfers',
        '1',
        '--stats=1s',
        '--stats-log-level',
        'NOTICE',
        '--use-json-log',
      ]);
    });

    test('远端 → 本地：参数顺序反过来', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(
          remoteId: 'myr',
          remotePath: '/photos',
          localPath: '/local',
          direction: SyncDirection.copyRemoteToLocal,
        ),
      );
      expect(args.sublist(0, 3), <String>['copy', 'myr:/photos', '/local']);
    });

    test('远端根目录（//name）不拼路径', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(
          remoteId: 'myr',
          remotePath: '//myr',
          localPath: '/local',
          direction: SyncDirection.copyLocalToRemote,
        ),
      );
      expect(args[2], 'myr:');
    });

    test('--checksum / --delete-excluded 开关', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(
          remoteId: 'myr',
          localPath: '/local',
          useMd5Sum: true,
          deleteExcluded: true,
        ),
      );
      expect(args, contains('--checksum'));
      expect(args, contains('--delete-excluded'));
    });

    test('过滤规则展开成成对的 --filter', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(remoteId: 'myr', localPath: '/local'),
        filters: const <FilterEntry>[
          FilterEntry(isInclude: false, pattern: '*.tmp'),
          FilterEntry(isInclude: true, pattern: '*'),
        ],
      );
      final int first = args.indexOf('--filter');
      expect(args[first + 1], '- *.tmp');
      expect(args[first + 3], '+ *');
    });

    test('local 远端会带上基准目录前缀', () {
      final Remote local = Remote(name: 'sdcard', type: 'local');
      final List<String> args = client.syncArgs(
        remote: local,
        task: const SyncTask(
          remoteId: 'sdcard',
          remotePath: '/backup',
          localPath: '/local',
        ),
      );
      // 注意路径里的双斜杠：原生 `Engine.sync()` 里
      // `localRemotePath` 已经以 `/` 结尾，再拼 `remotePath` 就会出现 `//`。
      // engine 能容忍，这里刻意保留原行为，避免"顺手修正"引入差异。
      expect(
        args[2],
        'sdcard:/storage/emulated/0/Android/data/com.jleoz.sync/files//backup',
      );
    });

    test('bisync 未启用 —— 返回空参数列表', () {
      final List<String> args = client.syncArgs(
        remote: remote,
        task: const SyncTask(
          remoteId: 'myr',
          localPath: '/local',
          direction: SyncDirection.bisync,
        ),
      );
      expect(args, isEmpty);
    });
  });
}
