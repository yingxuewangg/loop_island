/// 循环计划引擎（纯 Dart，不依赖 Flutter）。
///
/// 这是整个应用最核心的规则层：PRD §七「关键规则」里关于循环计划的每一条
/// 都在这里落地。所有函数都是**纯函数** —— 不读时钟（`today` 由调用方传入）、
/// 不碰磁盘、不改入参。
///
/// ## PRD 规则的对应实现
///
/// | PRD 规则 | 实现 |
/// | --- | --- |
/// | 按「第几天」算，不按星期几算 | [cycleDayIndexAt] |
/// | 结束日期当天仍然执行 | [isDateWithinCycle] 用闭区间 |
/// | 结束日期次日不再生成新任务实例 | [isDateWithinCycle] |
/// | 结束日不是周期最后一天时允许最后一轮截断 | [resolveEndDate] + [isTruncated] |
/// | 可选「完整周期结束后停止」 | [completeCyclesOnly] → [resolveEndDate] |
/// | 已结束计划自动归档，不再提醒 | [effectiveStatus] |
/// | 暂停可恢复，结束不可继续 | [effectiveStatus] + [canResume] |
/// | 修改结束日期后未来实例重新生成，历史不变 | 由 `cycle_commands` 调用本引擎重算 |
library;

import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:meta/meta.dart';

/// 周期内第几天（1..periodDays）；[date] 早于起始日时返回 null。
///
/// 「第几天」是 `(date - startDate) % periodDays + 1`，
/// **与星期几无关** —— 这是 PRD 明确要求的。
int? cycleDayIndexAt(Cycle cycle, DateTime date) {
  final elapsed = daysBetween(cycle.startDate, date);
  if (elapsed < 0) {
    return null;
  }
  return elapsed % cycle.periodDays + 1;
}

/// 截至 [date] 已经过去的**完整轮数**（起始日当天为 0）。
int elapsedCycles(Cycle cycle, DateTime date) {
  final elapsed = daysBetween(cycle.startDate, date);
  if (elapsed < 0) {
    return 0;
  }
  return elapsed ~/ cycle.periodDays;
}

/// 当前处于第几轮（从 1 开始）；[date] 早于起始日时为 null。
int? cycleRoundAt(Cycle cycle, DateTime date) {
  final dayIndex = cycleDayIndexAt(cycle, date);
  if (dayIndex == null) {
    return null;
  }
  return elapsedCycles(cycle, date) + 1;
}

/// 计划的实际结束日期；`null` 表示永不结束。
///
/// - `never` → null
/// - `afterCount(X)` → `startDate + X * N - 1`（第 X 轮的最后一天）
/// - `untilDate(D)` → D
/// - `untilDate(D)` 且 [Cycle.completeCyclesOnly] 为真时 → D 之前**最后一个完整周期的末日**
///   （PRD：「可选完整周期结束后停止，系统自动找到该日期前最后一个完整周期」）
///
/// 若结束日期早于起始日，返回起始日之前的日期会失去意义，
/// 因此这种情况下返回 [Cycle.startDate]（当天执行一天后结束）。
DateTime? resolveEndDate(Cycle cycle) {
  switch (cycle.endType) {
    case CycleEndType.never:
      return null;

    case CycleEndType.afterCount:
      final count = cycle.endCount;
      if (count == null || count < 1) {
        return null;
      }
      return addDays(
        cycle.startDate,
        count * cycle.periodDays - 1,
      );

    case CycleEndType.untilDate:
      final raw = cycle.endDate;
      if (raw == null) {
        return null;
      }
      final end = dateOnly(raw);
      if (isBeforeDay(end, cycle.startDate)) {
        return dateOnly(cycle.startDate);
      }
      if (!cycle.completeCyclesOnly) {
        return end;
      }
      // 往前找最后一个完整周期的末日：完整跑满的轮数 * N 天 - 1
      final fullDays = daysBetween(cycle.startDate, end) + 1;
      final fullCycles = fullDays ~/ cycle.periodDays;
      if (fullCycles < 1) {
        return null; // 连一个完整周期都放不下 → 不执行
      }
      return addDays(cycle.startDate, fullCycles * cycle.periodDays - 1);
  }
}

/// 结束日是否落在周期中间（即最后一轮被截断）。
bool isTruncated(Cycle cycle) {
  final end = resolveEndDate(cycle);
  if (end == null) {
    return false;
  }
  final dayIndex = cycleDayIndexAt(cycle, end);
  return dayIndex != null && dayIndex != cycle.periodDays;
}

/// [date] 是否落在计划的执行区间内（**闭区间**：结束日当天仍然执行）。
bool isDateWithinCycle(Cycle cycle, DateTime date, {DateTime? today}) {
  final day = dateOnly(date);
  if (isBeforeDay(day, cycle.startDate)) {
    return false;
  }

  // 被暂停时，暂停日之后（含当天）不再产生实例；暂停日之前的历史不受影响。
  // 这里用「今天」判断，因为暂停是即时生效的：暂停后连今天也不执行。
  if (cycle.status == CycleStatus.paused && today != null) {
    if (!isBeforeDay(day, dateOnly(today))) {
      return false;
    }
  }
  if (cycle.status == CycleStatus.ended && cycle.endedAt != null) {
    if (!isBeforeDay(day, dateOnly(cycle.endedAt!))) {
      return false;
    }
  }

  final end = resolveEndDate(cycle);
  if (end == null) {
    return true;
  }
  return isSameOrBeforeDay(day, end);
}

/// 计划的**有效状态**。
///
/// 「按结束条件已到期」但库里还写着 `active` 时，这里会返回 [CycleStatus.ended]，
/// 由 `cycle_commands` 负责把这个判断落库（写 `endedAt`）以实现自动归档。
///
/// [today] 为空时只做静态判断（不看日期）。
CycleStatus effectiveStatus(Cycle cycle, {DateTime? today}) {
  if (cycle.status == CycleStatus.ended) {
    return CycleStatus.ended;
  }
  if (today == null) {
    return cycle.status;
  }
  final end = resolveEndDate(cycle);
  if (end != null && isAfterDay(dateOnly(today), end)) {
    return CycleStatus.ended;
  }
  return cycle.status;
}

/// 计划是否应该被自动归档（到期但库里还是 active / paused）。
///
/// 暂停中的计划一旦过了结束日期同样不可恢复，因此也要归档 ——
/// 否则它会永远挂在「已暂停」里，而用户点「启用」却发现什么都不会发生。
bool shouldAutoArchive(Cycle cycle, DateTime today) =>
    cycle.status != CycleStatus.ended &&
    effectiveStatus(cycle, today: today) == CycleStatus.ended;

/// 已结束的计划不可恢复（PRD：「暂停可恢复，结束不可继续」）。
bool canResume(Cycle cycle, DateTime today) =>
    cycle.status == CycleStatus.paused &&
    effectiveStatus(cycle, today: today) != CycleStatus.ended;

/// 计划最后一次会执行任务的日期；永不结束时为 null。
DateTime? lastActiveDate(Cycle cycle) => resolveEndDate(cycle);

/// 剩余**整轮**数（PRD：计划列表显示「剩余约几轮」）。
///
/// 已结束返回 0；永不结束返回 null。
/// 进行中且当前轮尚未跑完时，当前这一轮也算「剩余」。
int? remainingCycles(Cycle cycle, DateTime today) {
  final end = resolveEndDate(cycle);
  if (end == null) {
    return null;
  }
  final current = dateOnly(today);
  if (isAfterDay(current, end)) {
    return 0;
  }

  // 从今天（或起始日，取较晚者）到结束日还剩多少天
  final from = isAfterDay(current, cycle.startDate) ? current : cycle.startDate;
  final remainingDays = daysInclusive(from, end);
  // 向上取整：不足一轮也算一轮
  return (remainingDays + cycle.periodDays - 1) ~/ cycle.periodDays;
}

/// 剩余天数（含今天）；已结束返回 0，永不结束返回 null。
int? remainingDays(Cycle cycle, DateTime today) {
  final end = resolveEndDate(cycle);
  if (end == null) {
    return null;
  }
  final current = dateOnly(today);
  if (isAfterDay(current, end)) {
    return 0;
  }
  final from = isAfterDay(current, cycle.startDate) ? current : cycle.startDate;
  return daysInclusive(from, end);
}

/// 计划是否已跑完（按日期口径）。
bool isFinished(Cycle cycle, DateTime today) =>
    effectiveStatus(cycle, today: today) == CycleStatus.ended;

/// 结束日期的中文描述，供计划列表使用。
String endDateLabel(Cycle cycle) {
  final end = resolveEndDate(cycle);
  if (end == null) {
    return '永不结束';
  }
  return dayKey(end);
}

/// 某一天某个计划应当出现的任务实例（**尚未落库**）。
///
/// 只是「应该出现什么」的描述，不含状态；真正写库由
/// `cycle_commands.materializeDay` 负责 —— 预览明日任务时不能污染数据库。
@immutable
class CycleTaskInstance {
  const CycleTaskInstance({
    required this.cycleId,
    required this.cycleName,
    required this.cycleDayIndex,
    required this.periodDays,
    required this.template,
    required this.date,
  });

  final String cycleId;
  final String cycleName;

  /// 周期内第几天（1 起）。
  final int cycleDayIndex;

  /// 计划周期天数 N。
  final int periodDays;

  /// 对应的任务模板。
  final CycleTaskTemplate template;

  /// 归属日期。
  final DateTime date;

  String get title => template.title;

  DateTime? get remindAt {
    final minute = template.remindMinuteOfDay;
    return minute == null ? null : atMinuteOfDay(date, minute);
  }

  @override
  String toString() =>
      'CycleTaskInstance($cycleName#$cycleDayIndex, ${template.title}, '
      '${dayKey(date)})';
}

/// 计算 [date] 当天应当出现的**全部循环任务实例**（纯计算，不落库）。
///
/// 跳过：尚未开始、已暂停（暂停日及之后）、已结束、超出结束日、
/// 休息日、以及没有任务的空白白天。
///
/// 关于暂停的语义（PRD 未明确，这里取可预测的一种）：
/// **暂停不改变周期进度** —— 第几天永远只由 `startDate` 决定，
/// 暂停期间的日期只是不产生实例，恢复后仍按原日历继续。
/// 这样「8 天计划暂停 3 天再恢复」不会让用户重新数天数。
List<CycleTaskInstance> instancesForDay(
  AppData data,
  DateTime date, {
  required DateTime today,
}) {
  final day = dateOnly(date);
  final result = <CycleTaskInstance>[];

  for (final cycle in data.cycles) {
    if (!isDateWithinCycle(cycle, day, today: today)) {
      continue;
    }

    final dayIndex = cycleDayIndexAt(cycle, day);
    if (dayIndex == null) {
      continue;
    }

    final cycleDay = cycle.dayAt(dayIndex);
    if (cycleDay.isRestDay || cycleDay.isEmpty) {
      continue;
    }

    for (final template in cycleDay.sortedTemplates) {
      result.add(
        CycleTaskInstance(
          cycleId: cycle.id,
          cycleName: cycle.name,
          cycleDayIndex: dayIndex,
          periodDays: cycle.periodDays,
          template: template,
          date: day,
        ),
      );
    }
  }

  return List.unmodifiable(result);
}
