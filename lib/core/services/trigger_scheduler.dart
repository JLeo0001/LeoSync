import '../models/trigger.dart';

/// 触发器的时间换算 —— 由原生 `Services/TriggerService.java` 移植。
///
/// 原生用 `AlarmManager` 的精确闹钟；Flutter 侧改用 WorkManager（最小粒度
/// 15 分钟，且系统可能延迟），所以这里只负责算出**"下次该在什么时候跑"**，
/// 调度交给 [SyncScheduler]。
class TriggerScheduler {
  const TriggerScheduler._();

  /// WorkManager 的周期任务下限。
  static const Duration minimumInterval = Duration(minutes: 15);

  /// 计算「按时刻」触发器距下一次触发的时长。
  ///
  /// 逐行对照原生 `queueSingleScheduleTrigger()`：
  /// * 今天的 `HH:mm` 已过 → 顺延 24 小时；
  /// * **当前分钟数恰好等于目标分钟** → 直接顺延 24 小时。
  ///   这是原生的防死循环保护：触发后立刻重新排期时，避免又排到"就在此刻"。
  static Duration nextScheduleDelay(Trigger trigger, DateTime now) {
    final int targetHour = trigger.scheduleHour;
    final int targetMinute = trigger.scheduleMinute;

    final DateTime today = DateTime(
      now.year,
      now.month,
      now.day,
      targetHour,
      targetMinute,
    );
    var difference = today.difference(now);

    if (difference.isNegative) {
      difference += const Duration(days: 1);
    }
    if (now.minute == targetMinute) {
      difference = const Duration(days: 1);
    }
    return difference.isNegative ? const Duration(days: 1) : difference;
  }

  /// 触发器在 [now] 这一刻应该跳过吗（当天不在掩码里）。
  ///
  /// 对应原生 `startTask()` 里的 `skipBecauseOfWeekday` 判断 ——
  /// 星期过滤发生在**触发时**，而不是排期时。
  static bool shouldSkipNow(Trigger trigger, DateTime now) =>
      !trigger.isEnabledOn(now);

  /// 周期任务的间隔；低于 WorkManager 下限时会被夹到 15 分钟。
  static Duration effectiveInterval(Trigger trigger) {
    final Duration requested = Duration(minutes: trigger.intervalMinutes);
    return requested < minimumInterval ? minimumInterval : requested;
  }

  /// WorkManager 要求唯一的任务名，这里用触发器 id 派生。
  static String uniqueNameFor(Trigger trigger) => 'leosync.trigger.${trigger.id}';

  static String uniqueNameForTask(int taskId) => 'leosync.task.$taskId';

  /// 触发器的人类可读摘要，用于列表副标题。
  static String describe(Trigger trigger) {
    if (trigger.type == TriggerType.interval) {
      return '每 ${trigger.humanReadableInterval}';
    }
    return '${trigger.weekdaySummary} ${trigger.humanReadableTime}';
  }
}
