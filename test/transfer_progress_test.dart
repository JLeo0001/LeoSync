import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/engine/transfer_progress.dart';

void main() {
  group('TransferProgress.tryParse —— JSON 日志', () {
    test('解析 --use-json-log 的统计行', () {
      const String line =
          '{"level":"notice","msg":"Transferred:   1 KiB / 4 KiB, 25%",'
          '"object":"file.bin","stats":{"bytes":1000,"totalBytes":4000,'
          '"speed":500.5,"eta":6,"transfers":1,"errors":0,"elapsedTime":2}}';

      final TransferProgress? progress = TransferProgress.tryParse(line);
      expect(progress, isNotNull);
      expect(progress!.bytes, 1000);
      expect(progress.totalBytes, 4000);
      expect(progress.speed, 500.5);
      expect(progress.etaSeconds, 6);
      expect(progress.fileName, 'file.bin');
      expect(progress.percentage, 25);
      expect(progress.ratio, closeTo(0.25, 1e-9));
    });

    test('没有 stats 的普通传输事件只带文件名', () {
      const String line =
          '{"level":"info","msg":"Copied (new)","object":"a/b.txt"}';
      final TransferProgress? progress = TransferProgress.tryParse(line);
      expect(progress, isNotNull);
      expect(progress!.fileName, 'a/b.txt');
      expect(progress.hasTotal, isFalse);
    });

    test('无法识别的 JSON 行返回 null', () {
      expect(TransferProgress.tryParse('{"level":"debug"}'), isNull);
      expect(TransferProgress.tryParse('{ not json'), isNull);
    });
  });

  group('TransferProgress.tryParse —— 纯文本统计行（兜底）', () {
    test('解析字节对 / 百分比 / ETA', () {
      const String line =
          'Transferred:   	   1.234 MiB / 5.678 MiB, 21%, 512 KiB/s, ETA 8s';
      final TransferProgress? progress = TransferProgress.tryParse(line);
      expect(progress, isNotNull);
      expect(progress!.totalBytes, (5.678 * 1024 * 1024).round());
      expect(progress.etaSeconds, 8);
      expect(progress.percentage, 21);
    });

    test('ETA 单位 m/h', () {
      final TransferProgress? minutes = TransferProgress.tryParse(
        'Transferred:   1 MiB / 100 MiB, 1%, 10 KiB/s, ETA 2m30s',
      );
      expect(minutes!.etaSeconds, 120);

      final TransferProgress? hours = TransferProgress.tryParse(
        'Transferred:   1 MiB / 100 MiB, 1%, 10 KiB/s, ETA 3h',
      );
      expect(hours!.etaSeconds, 3 * 3600);
    });

    test('不含 Transferred 前缀的行返回 null', () {
      expect(TransferProgress.tryParse('2024/01/01 ERROR : boom'), isNull);
      expect(TransferProgress.tryParse(''), isNull);
    });
  });

  group('格式化', () {
    test('人类可读的字节 / 速度 / 剩余时间', () {
      const TransferProgress progress = TransferProgress(
        bytes: 1500,
        totalBytes: 2500000,
        speed: 1024,
        etaSeconds: 125,
      );
      expect(progress.humanReadableBytes, '1.5 kB');
      expect(progress.humanReadableTotal, '2.5 MB');
      expect(progress.humanReadableSpeed, '1.0 kB/s');
      expect(progress.humanReadableEta, '2m5s');
    });

    test('总量未知时不显示百分比', () {
      const TransferProgress progress = TransferProgress(bytes: 10);
      expect(progress.hasTotal, isFalse);
      expect(progress.percentage, isNull);
      expect(progress.humanReadableTotal, '未知');
      expect(progress.humanReadableEta, '—');
    });
  });
}
