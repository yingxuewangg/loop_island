/// 全实体共用的枚举与状态常量（纯 Dart，不含界面文案）。
///
/// 每个枚举都提供：
/// - `wireName`：写入 JSON 的稳定字符串，**不得随意改动**（备份兼容性）。
/// - `parse(String?)`：宽松解析，未知值回落默认值，**不抛异常**。
///
/// 界面文案统一在 `lib/app/l10n_strings.dart` 中映射，模型层不依赖 UI。
library;

/// 任务 / 任务实例的状态。
enum TaskStatus {
  /// 待办。
  pending,

  /// 已完成。
  completed,

  /// 主动跳过。
  skipped,

  /// 未完成（到期未做）。
  missed;

  String get wireName => name;

  /// 是否属于「已了结」状态（完成 / 跳过 / 未完成）。
  bool get isSettled => this != TaskStatus.pending;

  /// 宽松解析，未知值回落 [fallback]。
  static TaskStatus parse(String? value, {TaskStatus fallback = TaskStatus.pending}) {
    if (value == null) {
      return fallback;
    }
    for (final item in TaskStatus.values) {
      if (item.wireName == value) {
        return item;
      }
    }
    return fallback;
  }
}

/// 普通任务的日期类型。
enum TaskDateType {
  /// 今天。
  today,

  /// 明天。
  tomorrow,

  /// 自定义日期（具体日期见 `Task.date`）。
  custom,

  /// 无日期（未安排）。
  none;

  String get wireName => name;

  /// 是否带具体日期。
  bool get hasDate => this != TaskDateType.none;

  static TaskDateType parse(
    String? value, {
    TaskDateType fallback = TaskDateType.none,
  }) {
    if (value == null) {
      return fallback;
    }
    for (final item in TaskDateType.values) {
      if (item.wireName == value) {
        return item;
      }
    }
    return fallback;
  }
}

/// 循环计划的结束方式。
enum CycleEndType {
  /// 永不结束。
  never,

  /// 循环 X 次后结束。
  afterCount,

  /// 到指定日期结束。
  untilDate;

  String get wireName => name;

  static CycleEndType parse(
    String? value, {
    CycleEndType fallback = CycleEndType.never,
  }) {
    if (value == null) {
      return fallback;
    }
    for (final item in CycleEndType.values) {
      if (item.wireName == value) {
        return item;
      }
    }
    return fallback;
  }
}

/// 循环计划状态。
enum CycleStatus {
  /// 进行中。
  active,

  /// 已暂停（可恢复）。
  paused,

  /// 已结束（不可恢复，自动归档）。
  ended;

  String get wireName => name;

  /// 是否仍在产生任务实例。
  bool get isRunning => this == CycleStatus.active;

  static CycleStatus parse(
    String? value, {
    CycleStatus fallback = CycleStatus.active,
  }) {
    if (value == null) {
      return fallback;
    }
    for (final item in CycleStatus.values) {
      if (item.wireName == value) {
        return item;
      }
    }
    return fallback;
  }
}

/// 修改循环任务时的作用域。
///
/// PRD 明确只需两个选项：仅本次 / 以后所有。
/// `fromNowUntil`（到某日为止）留给第二版，见 PRD §八.5。
enum EditScope {
  /// 仅本次：只改当天的任务实例，不动周期模板。
  once,

  /// 以后所有：改周期模板，并重算今天起的未来实例。
  fromNowAll;

  String get wireName => name;

  static EditScope parse(String? value, {EditScope fallback = EditScope.once}) {
    if (value == null) {
      return fallback;
    }
    for (final item in EditScope.values) {
      if (item.wireName == value) {
        return item;
      }
    }
    return fallback;
  }
}
