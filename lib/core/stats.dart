/// 轻量统计的纯计算层（PRD §五：第一版只做四项）。
///
/// 四项指标：今日完成进度、当前周期进度、连续打卡天数、90 天热力图。
/// 全部是**纯函数**、时间由参数注入，因此可以用确定性单测把规则钉死。
///
/// 口径统一说明：所有「某天有多少任务、完成了多少」的判断都复用
/// [buildDayView]，保证统计页与今日页对「今天」的理解一致 ——
/// 两处各写一套是这类应用最常见的数据不一致来源。
library;

import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:meta/meta.dart';

/// 完成进度（今日 / 周期通用）。
@immutable
class ProgressStat {
  const ProgressStat({required this.total, required this.completed});

  /// 空进度。
  static const empty = ProgressStat(total: 0, completed: 0);

  final int total;
  final int completed;

  int get remaining => total - completed;

  /// 完成率 0..1；**没有任务时返回 null**（UI 不该显示 0%）。
  double? get rate {
    if (total == 0) {
      return null;
    }
    return completed / total;
  }

  int? get percent {
    final value = rate;
    return value == null ? null : (value * 100).round();
  }

  bool get hasTask => total > 0;
  bool get isAllDone => total > 0 && completed == total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressStat &&
          other.total == total &&
          other.completed == completed;

  @override
  int get hashCode => Object.hash(total, completed);

  @override
  String toString() => 'ProgressStat($completed/$total)';
}

/// 5.1 今日完成进度。
///
/// 统计口径与今日页完全一致（普通任务 + 启用中计划今天对应的循环任务），
/// 只把 `completed` 状态算作完成。
ProgressStat todayProgress(AppData data, DateTime today) {
  final view = buildTodayView(data, today);
  return ProgressStat(total: view.total, completed: view.completedCount);
}

/// 5.2 当前周期进度。
///
/// 只统计**当前这一轮**内的实例：从本轮第一天到今天为止。
/// 未开始（今天早于起始日）时返回空进度。
@immutable
class CycleProgressStat {
  const CycleProgressStat({
    required this.cycleId,
    required this.cycleName,
    required this.periodDays,
    required this.dayIndex,
    required this.progress,
  });

  final String cycleId;
  final String cycleName;
  final int periodDays;

  /// 今天处于第几天；未开始为 null。
  final int? dayIndex;

  /// 本轮已完成 / 应完成。
  final ProgressStat progress;

  bool get hasStarted => dayIndex != null;

  @override
  String toString() =>
      'CycleProgressStat($cycleName, 第 $dayIndex/$periodDays 天, $progress)';
}

/// 计算某个计划当前这一轮的进度。
///
/// **应完成数只算到今天为止**：本轮还没到的日子不该拉低完成率 ——
/// 第 2 天看到「完成率 25%」会让人以为自己落后了。
CycleProgressStat cycleProgress(
  AppData data,
  Cycle cycle,
  DateTime today,
) {
  final todayOnly = dateOnly(today);
  final dayIndex = cycleDayIndexAt(cycle, todayOnly);

  if (dayIndex == null) {
    return CycleProgressStat(
      cycleId: cycle.id,
      cycleName: cycle.name,
      periodDays: cycle.periodDays,
      dayIndex: null,
      progress: ProgressStat.empty,
    );
  }

  // 本轮第一天 = 起始日 + 已过整轮数 * N
  final roundStart = addDays(
    cycle.startDate,
    elapsedCycles(cycle, todayOnly) * cycle.periodDays,
  );

  var total = 0;
  var completed = 0;

  var cursor = roundStart;
  while (!isAfterDay(cursor, todayOnly)) {
    final view = buildDayView(data, cursor, today: todayOnly);
    // 只看这个计划的实例，避免把别的计划/普通任务算进来
    for (final entry in view.cycleEntries) {
      if (entry.cycleId != cycle.id) {
        continue;
      }
      total++;
      if (entry.isCompleted) {
        completed++;
      }
    }
    cursor = addDays(cursor, 1);
  }

  return CycleProgressStat(
    cycleId: cycle.id,
    cycleName: cycle.name,
    periodDays: cycle.periodDays,
    dayIndex: dayIndex,
    progress: ProgressStat(total: total, completed: completed),
  );
}

/// 某个计划在当前这一轮的进度（按 [AppData] 里所有未结束的计划批量计算）。
///
/// 已暂停的计划也算 —— 暂停只是不再产生新实例，已有的进度依然值得展示。
List<CycleProgressStat> allCycleProgress(AppData data, DateTime today) {
  final result = <CycleProgressStat>[];
  for (final cycle in data.cycles) {
    if (effectiveStatus(cycle, today: today) == CycleStatus.ended) {
      continue;
    }
    final stat = cycleProgress(data, cycle, today);
    if (!stat.hasStarted) {
      continue;
    }
    result.add(stat);
  }
  return List.unmodifiable(result);
}

/// 5.3 打卡统计。
@immutable
class StreakStat {
  const StreakStat({required this.current, required this.longest});

  static const empty = StreakStat(current: 0, longest: 0);

  /// 当前连续打卡天数。
  final int current;

  /// 历史最长连续打卡天数。
  final int longest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakStat && other.current == current && other.longest == longest;

  @override
  int get hashCode => Object.hash(current, longest);

  @override
  String toString() => 'StreakStat(current=$current, longest=$longest)';
}

/// 5.3 连续打卡天数。
///
/// PRD §七 的三条规则：
/// 1. 当天有任务且**全部完成**才算打卡 1 天；
/// 2. **无任务日跳过，不计入，也不打断** —— 所以在「有任务的日子」序列上连续即可，
///    中间的空档是透明的；
/// 3. 有未完成或跳过就不算打卡（视为断点）。
///
/// 额外处理「今天还没做完不算断」：判据是**今天还有未了结的待办**（`pending`），
/// 而不是「今天不是全完成」。两者差别很关键 ——
/// 今天的任务全被标记为未完成/跳过时，用户已经明确结束了这一天，
/// 应当按断点处理（PRD：未完成或跳过不算打卡）；只有还挂着待办时才算「这一天还没结束」。
///
/// [maxLookbackDays] 限制回溯范围，避免长期使用后每次统计都遍历全部历史。
StreakStat streaks(
  AppData data,
  DateTime today, {
  int maxLookbackDays = 730,
}) {
  final todayOnly = dateOnly(today);
  final from = addDays(todayOnly, -(maxLookbackDays - 1));

  // 只保留「有任务的日子」——无任务日自动透明
  final days = <_DayStat>[];
  var cursor = from;
  while (!isAfterDay(cursor, todayOnly)) {
    final view = buildDayView(data, cursor, today: todayOnly);
    if (view.total > 0) {
      days.add(
        _DayStat(
          date: cursor,
          total: view.total,
          completed: view.completedCount,
          hasPending: view.all.any((e) => e.isPending),
        ),
      );
    }
    cursor = addDays(cursor, 1);
  }

  if (days.isEmpty) {
    return StreakStat.empty;
  }

  bool isOpen(_DayStat day) =>
      isSameDay(day.date, todayOnly) && day.hasPending;

  // ---- 最长连续 ----
  var longest = 0;
  var run = 0;
  for (final day in days) {
    if (day.isHit) {
      run++;
      if (run > longest) {
        longest = run;
      }
    } else if (!isOpen(day)) {
      run = 0;
    }
  }

  // ---- 当前连续（从最近一天往回数）----
  var current = 0;
  for (var i = days.length - 1; i >= 0; i--) {
    final day = days[i];
    if (day.isHit) {
      current++;
    } else if (isOpen(day)) {
      continue; // 今天还挂着待办 → 不算断，也不计数
    } else {
      break;
    }
  }

  return StreakStat(current: current, longest: longest);
}

/// 一天的任务概况，仅用于打卡计算。
@immutable
class _DayStat {
  const _DayStat({
    required this.date,
    required this.total,
    required this.completed,
    required this.hasPending,
  });

  final DateTime date;
  final int total;
  final int completed;
  final bool hasPending;

  bool get isHit => total > 0 && completed == total;
}

/// 5.4 热力图的单日格子。
@immutable
class HeatmapCell {
  const HeatmapCell({
    required this.date,
    required this.total,
    required this.completed,
    required this.level,
  });

  final DateTime date;
  final int total;
  final int completed;

  /// 颜色档位 0..4，越大越深。
  ///
  /// - `total == 0`（无任务）→ 0，且 [hasTask] 为 false（UI 画浅灰空格）
  /// - 有任务但一个没完成 → 0（[hasTask] 为 true，UI 可区分「0%」与「无任务」）
  /// - 完成率 1%~25% → 1；26%~50% → 2；51%~75% → 3；76%~100% → 4
  final int level;

  bool get hasTask => total > 0;

  double? get rate {
    if (total == 0) {
      return null;
    }
    return completed / total;
  }

  bool get isAllDone => total > 0 && completed == total;

  @override
  String toString() =>
      'HeatmapCell(${dayKey(date)}, $completed/$total, level=$level)';
}

/// 5.4 最近 [days] 天的热力图数据（含 [endDate] 当天，升序）。
///
/// 缺数据的日期会被补齐为「无任务」格子，保证热力图布局稳定。
List<HeatmapCell> heatmapData(
  AppData data, {
  required DateTime endDate,
  required DateTime today,
  int days = 90,
}) {
  final dates = lastNDates(days, end: endDate);
  return List.unmodifiable([
    for (final date in dates)
      () {
        final view = buildDayView(data, date, today: today);
        return HeatmapCell(
          date: date,
          total: view.total,
          completed: view.completedCount,
          level: heatmapLevel(view.total, view.completedCount),
        );
      }(),
  ]);
}

/// 完成率 → 热力图档位（0..4）。
int heatmapLevel(int total, int completed) {
  if (total <= 0 || completed <= 0) {
    return 0;
  }
  final rate = completed / total;
  if (rate <= 0.25) {
    return 1;
  }
  if (rate <= 0.50) {
    return 2;
  }
  if (rate <= 0.75) {
    return 3;
  }
  return 4;
}
