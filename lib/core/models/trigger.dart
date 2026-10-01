/// 触发器类型 —— 由原生 `Items/Trigger.kt` 移植。
enum TriggerType {
  schedule(0, '按时刻'),
  interval(1, '按间隔');

  const TriggerType(this.value, this.label);

  final int value;
  final String label;

  static TriggerType fromValue(int value) =>
      value == 1 ? TriggerType.interval : TriggerType.schedule;
}

/// 一个定时/间隔触发器 —— 由原生 `Items/Trigger.kt` 移植。
///
/// 星期用一个 7 位比特掩码表示，**bit 0 = 周一，bit 6 = 周日**
/// （与原生 `weekdays: Byte` 完全一致，默认 `0b01111111` 即每天）。
class Trigger {
  const Trigger({
    this.id = 0,
    this.title = '',
    this.isEnabled = true,
    this.weekdayMask = defaultWeekdayMask,
    this.time = 0,
    this.triggerTarget = 0,
    this.type = TriggerType.schedule,
  });

  static const int defaultWeekdayMask = 0x7F;

  static const int idDoesNotExist = -1;

  static const List<String> weekdayLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  final int id;
  final String title;
  final bool isEnabled;

  /// 7 位掩码：bit 0 周一 … bit 6 周日。
  final int weekdayMask;

  /// **距离 00:00 的分钟数**（`schedule` 类型），或**间隔分钟数**（`interval` 类型）。
  ///
  /// ⚠️ 原生 `Trigger.kt` 的注释写的是 `//in seconds since 00:00`，但那是
  /// **错的**：`TriggerActivity.kt` 存的是 `hourOfDay * 60 + minute`
  /// （即分钟），间隔类型存的是 15 / 30 / 60 / 120（同样是分钟）；
  /// `TriggerService` 也用 `time / 60` 当小时、`time % 60` 当分钟。
  /// 这里以**实际行为**为准，不要被上游注释带偏。
  final int time;

  /// 要触发的任务 id。
  final int triggerTarget;

  final TriggerType type;

  static const String tableName = 'trigger_table';
  static const String columnId = 'trigger_id';
  static const String columnTitle = 'trigger_title';
  static const String columnEnabled = 'trigger_enabled';
  static const String columnTime = 'trigger_time';
  static const String columnWeekday = 'trigger_weekday';
  static const String columnTarget = 'trigger_target';
  static const String columnType = 'trigger_type';

  /// 翻译自 `Trigger.isEnabledAtDay()`。`weekday` 从 0（周一）开始。
  bool isEnabledAtDay(int weekday) =>
      ((weekdayMask >> weekday) & 1) == 1;

  /// 翻译自 `Trigger.setEnabledAtDay()`。
  Trigger setEnabledAtDay(int weekday, bool enabled) {
    final int bit = 1 << weekday;
    final int next = enabled ? (weekdayMask | bit) : (weekdayMask & ~bit);
    return copyWith(weekdayMask: next & defaultWeekdayMask);
  }

  /// 按时刻类型：`time`（分钟）→ `HH:mm`。
  String get humanReadableTime {
    final int hours = (time ~/ 60) % 24;
    final int minutes = time % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// 按时刻类型：小时部分（0–23）。
  int get scheduleHour => (time ~/ 60) % 24;

  /// 按时刻类型：分钟部分（0–59）。
  int get scheduleMinute => time % 60;

  /// 间隔类型：间隔分钟数。
  int get intervalMinutes => time;

  /// 间隔类型：人类可读的间隔描述。
  String get humanReadableInterval {
    final int minutes = intervalMinutes;
    if (minutes <= 0) return '未设置';
    if (minutes < 60) return '$minutes 分钟';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }

  /// 用界面上的 `HH:mm` 构造 `time`（分钟）。
  static int timeFromClock(int hour, int minute) => hour * 60 + minute;

  /// 该触发器在 [when] 当天是否生效。
  ///
  /// Dart 的 [DateTime.weekday] 是 1=周一 … 7=周日，
  /// 位掩码是 0=周一 … 6=周日，所以减 1。
  bool isEnabledOn(DateTime when) => isEnabledAtDay(when.weekday - 1);

  /// 简短的星期摘要，例如「每天」「工作日」「周一、周三」。
  String get weekdaySummary {
    if (weekdayMask == defaultWeekdayMask) return '每天';
    if (weekdayMask == 0x1F) return '工作日';
    if (weekdayMask == 0x60) return '周末';
    final List<String> days = <String>[];
    for (var i = 0; i < 7; i++) {
      if (isEnabledAtDay(i)) days.add(weekdayLabels[i]);
    }
    return days.isEmpty ? '从不' : days.join('、');
  }

  Trigger copyWith({
    int? id,
    String? title,
    bool? isEnabled,
    int? weekdayMask,
    int? time,
    int? triggerTarget,
    TriggerType? type,
  }) {
    return Trigger(
      id: id ?? this.id,
      title: title ?? this.title,
      isEnabled: isEnabled ?? this.isEnabled,
      weekdayMask: weekdayMask ?? this.weekdayMask,
      time: time ?? this.time,
      triggerTarget: triggerTarget ?? this.triggerTarget,
      type: type ?? this.type,
    );
  }

  static Trigger fromRow(Map<String, Object?> row) => Trigger(
        id: (row[columnId] as int?) ?? 0,
        title: (row[columnTitle] as String?) ?? '',
        isEnabled: ((row[columnEnabled] as int?) ?? 1) != 0,
        weekdayMask: ((row[columnWeekday] as int?) ?? defaultWeekdayMask) &
            defaultWeekdayMask,
        time: (row[columnTime] as int?) ?? 0,
        triggerTarget: (row[columnTarget] as int?) ?? 0,
        type: TriggerType.fromValue((row[columnType] as int?) ?? 0),
      );

  Map<String, Object?> toRow({bool includeId = true}) => <String, Object?>{
        if (includeId) columnId: id,
        columnTitle: title,
        columnEnabled: isEnabled ? 1 : 0,
        columnWeekday: weekdayMask,
        columnTime: time,
        columnTarget: triggerTarget,
        columnType: type.value,
      };

  @override
  String toString() => 'Trigger($id, $title, $weekdaySummary $humanReadableTime)';
}
