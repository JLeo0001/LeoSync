import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/models/trigger.dart';
import 'package:leosync/core/services/trigger_scheduler.dart';

void main() {
  group('Trigger.time 的真实单位是「分钟」', () {
    test('TriggerActivity 存的是 hourOfDay * 60 + minute', () {
      // 原生 Activities/TriggerActivity.kt:179
      expect(Trigger.timeFromClock(9, 30), 570);
      expect(Trigger.timeFromClock(0, 0), 0);
      expect(Trigger.timeFromClock(23, 59), 1439);
    });

    test('humanReadableTime 按分钟解析（不是注释里写的秒）', () {
      expect(const Trigger(time: 570).humanReadableTime, '09:30');
      expect(const Trigger(time: 0).humanReadableTime, '00:00');
      expect(const Trigger(time: 1439).humanReadableTime, '23:59');
      expect(const Trigger(time: 3 * 60).humanReadableTime, '03:00');
    });

    test('scheduleHour / scheduleMinute 拆分正确', () {
      const Trigger trigger = Trigger(time: 570);
      expect(trigger.scheduleHour, 9);
      expect(trigger.scheduleMinute, 30);
    });

    test('间隔类型的 time 同样是分钟（15/30/60/120）', () {
      expect(const Trigger(time: 15).intervalMinutes, 15);
      expect(const Trigger(time: 60).humanReadableInterval, '1 小时');
      expect(const Trigger(time: 120).humanReadableInterval, '2 小时');
      expect(const Trigger(time: 90).humanReadableInterval, '1 小时 30 分钟');
      expect(const Trigger(time: 0).humanReadableInterval, '未设置');
    });
  });

  group('TriggerScheduler.nextScheduleDelay —— 对照 queueSingleScheduleTrigger()', () {
    test('目标时刻在今天就返回今天的延迟', () {
      final DateTime now = DateTime(2026, 1, 1, 8, 0);
      final Duration delay = TriggerScheduler.nextScheduleDelay(
        const Trigger(time: 9 * 60 + 30),
        now,
      );
      expect(delay, const Duration(hours: 1, minutes: 30));
    });

    test('目标时刻已过则顺延 24 小时', () {
      final DateTime now = DateTime(2026, 1, 1, 10, 0);
      final Duration delay = TriggerScheduler.nextScheduleDelay(
        const Trigger(time: 9 * 60 + 30),
        now,
      );
      expect(delay, const Duration(hours: 23, minutes: 30));
    });

    test('当前分钟恰好等于目标分钟 → 强制 24 小时（原生的防死循环）', () {
      final DateTime now = DateTime(2026, 1, 1, 9, 30, 45);
      final Duration delay = TriggerScheduler.nextScheduleDelay(
        const Trigger(time: 9 * 60 + 30),
        now,
      );
      expect(delay, const Duration(days: 1));
    });

    test('恰好整点边界', () {
      final DateTime now = DateTime(2026, 1, 1, 0, 0);
      final Duration delay = TriggerScheduler.nextScheduleDelay(
        const Trigger(time: 0),
        now,
      );
      // now.minute == 0 == 目标分钟，同样触发防死循环保护
      expect(delay, const Duration(days: 1));
    });
  });

  group('TriggerScheduler.shouldSkipNow —— 星期过滤在触发时做', () {
    test('周一 0x01 掩码：周一不跳过，周二跳过', () {
      const Trigger mondayOnly = Trigger(weekdayMask: 0x01);
      // 2026-01-05 是周一，2026-01-06 是周二
      expect(
        TriggerScheduler.shouldSkipNow(mondayOnly, DateTime(2026, 1, 5, 9)),
        isFalse,
      );
      expect(
        TriggerScheduler.shouldSkipNow(mondayOnly, DateTime(2026, 1, 6, 9)),
        isTrue,
      );
    });

    test('周末掩码 0x60：周六周日不跳过', () {
      const Trigger weekend = Trigger(weekdayMask: 0x60);
      expect(
        TriggerScheduler.shouldSkipNow(weekend, DateTime(2026, 1, 3, 9)),
        isFalse, // 周六
      );
      expect(
        TriggerScheduler.shouldSkipNow(weekend, DateTime(2026, 1, 4, 9)),
        isFalse, // 周日
      );
      expect(
        TriggerScheduler.shouldSkipNow(weekend, DateTime(2026, 1, 5, 9)),
        isTrue, // 周一
      );
    });
  });

  group('TriggerScheduler 其它', () {
    test('周期任务低于 15 分钟时被夹到下限', () {
      expect(
        TriggerScheduler.effectiveInterval(const Trigger(time: 5)),
        const Duration(minutes: 15),
      );
      expect(
        TriggerScheduler.effectiveInterval(const Trigger(time: 60)),
        const Duration(hours: 1),
      );
    });

    test('唯一任务名由 id 派生', () {
      expect(TriggerScheduler.uniqueNameFor(const Trigger(id: 7)),
          'leosync.trigger.7');
      expect(TriggerScheduler.uniqueNameForTask(9), 'leosync.task.9');
    });

    test('列表摘要', () {
      expect(
        TriggerScheduler.describe(
          const Trigger(weekdayMask: 0x7F, time: 3 * 60 + 15),
        ),
        '每天 03:15',
      );
      expect(
        TriggerScheduler.describe(
          const Trigger(type: TriggerType.interval, time: 30),
        ),
        '每 30 分钟',
      );
    });
  });
}
