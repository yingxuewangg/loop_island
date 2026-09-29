/// 今日 / 明日视图的纯计算层。
///
/// 把「今天该做什么」汇成一份不含 UI 的结构：普通任务 + 各个启用中计划当天
/// 对应的循环任务。**纯函数、不落库** —— 明日预览尤其不能写数据。
library;

import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/task_groups.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';
import 'package:meta/meta.dart';

/// 今日/明日列表里的一条任务。
///
/// 普通任务与循环任务在这里被统一成同一种形状，UI 因此只需要一套渲染逻辑。
@immutable
class DayEntry {
  const DayEntry({
    required this.key,
    required this.title,
    required this.status,
    this.remindAts = const [],
    this.recordId,
    this.cycleId,
    this.cycleName,
    this.cycleDayIndex,
    this.cyclePeriodDays,
    this.templateId,
    this.reason,
    this.isOverdue = false,
  });

  /// 列表 key：普通任务用 `task.id`，循环实例用 `cycleId#templateId`。
  final String key;

  /// 展示标题（循环实例优先取当天覆盖的标题）。
  final String title;

  final TaskStatus status;

  /// 提醒时刻列表（升序）；空表示不提醒。
  final List<DateTime> remindAts;

  /// 最早的提醒时刻；排序用它。
  DateTime? get remindAt => remindAts.isEmpty ? null : remindAts.first;

  /// 已物化的记录 id；未物化时为 null（明日预览就是这种情况）。
  final String? recordId;

  final String? cycleId;
  final String? cycleName;
  final int? cycleDayIndex;
  final int? cyclePeriodDays;

  /// 循环模板 id；普通任务为 null。
  final String? templateId;

  final String? reason;

  /// 是否逾期（仅普通任务可能出现）。
  final bool isOverdue;

  bool get isCycle => cycleId != null;

  bool get isCompleted => status == TaskStatus.completed;

  bool get isPending => status == TaskStatus.pending;

  /// 「计划名 · 第 x/N 天」，仅循环任务有值。
  String? get cycleLabel {
    final name = cycleName;
    final day = cycleDayIndex;
    final total = cyclePeriodDays;
    if (name == null || day == null || total == null) {
      return null;
    }
    return '$name · 第 $day/$total 天';
  }

  @override
  String toString() => 'DayEntry($key, $title, ${status.wireName})';
}

/// 某一天的完整视图。
@immutable
class DayView {
  const DayView({
    required this.date,
    this.cycleEntries = const [],
    this.plainEntries = const [],
  });

  final DateTime date;

  /// 循环任务（按计划创建时间 → 模板 order）。
  final List<DayEntry> cycleEntries;

  /// 普通任务（按提醒时间 → 创建时间）。
  final List<DayEntry> plainEntries;

  /// 全部任务：循环任务在前，普通任务在后。
  List<DayEntry> get all => List.unmodifiable([...cycleEntries, ...plainEntries]);

  bool get isEmpty => cycleEntries.isEmpty && plainEntries.isEmpty;

  int get total => cycleEntries.length + plainEntries.length;

  int get completedCount =>
      all.where((e) => e.isCompleted).length;

  /// 完成率 0..1；没有任务时返回 null（UI 不该显示 0%）。
  double? get progress {
    final sum = total;
    if (sum == 0) {
      return null;
    }
    return completedCount / sum;
  }

  /// 完成率百分比（四舍五入）；没有任务时返回 null。
  int? get progressPercent {
    final value = progress;
    return value == null ? null : (value * 100).round();
  }

  /// 「明日是某计划第几天」之类的摘要，供明日预览卡片使用。
  List<String> get cycleDayLabels => List.unmodifiable([
        for (final entry in cycleEntries)
          if (entry.cycleLabel != null) entry.cycleLabel!,
      ]);

  @override
  String toString() =>
      'DayView(${dayKey(date)}, 循环=${cycleEntries.length}, '
      '普通=${plainEntries.length}, 完成=$completedCount)';
}

/// 计算某一天的视图。
///
/// [today] 用于判定暂停/结束与「逾期」；预览未来或过去日期时也要传当前今天。
///
/// - 循环任务来自 [instancesForDay]（纯计算），状态取**已有记录**的状态；
///   没物化过就显示为待办 —— 这正是明日预览需要的效果。
/// - 普通任务只取「归属日期等于 [date]」的那些；归属判定与任务 Tab 共用
///   [groupTasks] 的口径，避免两处对「今天」的理解不一致。
DayView buildDayView(
  AppData data,
  DateTime date, {
  required DateTime today,
}) {
  final day = dateOnly(date);
  final todayOnly = dateOnly(today);
  final key = dayKey(day);

  // ---- 循环任务 ----
  final cycleEntries = <DayEntry>[];
  for (final instance in instancesForDay(data, day, today: todayOnly)) {
    final record = data.findInstance(
      taskId: instance.template.id,
      day: day,
      cycleId: instance.cycleId,
    );
    cycleEntries.add(
      DayEntry(
        key: '${instance.cycleId}#${instance.template.id}',
        // 「仅本次」改名优先于模板标题
        title: record?.titleOverride ?? instance.template.title,
        status: record?.status ?? TaskStatus.pending,
        remindAts: [
          if (instance.remindAt != null) instance.remindAt!,
        ],
        recordId: record?.id,
        cycleId: instance.cycleId,
        cycleName: instance.cycleName,
        cycleDayIndex: instance.cycleDayIndex,
        cyclePeriodDays: instance.periodDays,
        templateId: instance.template.id,
        reason: record?.reason,
      ),
    );
  }

  // ---- 普通任务 ----
  final plainEntries = <DayEntry>[];
  for (final task in data.tasks) {
    final resolved = task.resolvedDate(todayOnly);
    if (resolved == null || dayKey(resolved) != key) {
      continue;
    }
    plainEntries.add(
      DayEntry(
        key: task.id,
        title: task.title,
        status: task.status,
        remindAts: task.remindAts,
        recordId: data.findInstance(taskId: task.id, day: day)?.id,
        reason: data.findInstance(taskId: task.id, day: day)?.reason,
        isOverdue: isBeforeDay(day, todayOnly) && !task.isCompleted,
      ),
    );
  }
  plainEntries.sort(_byRemindThenTitle);

  return DayView(
    date: day,
    cycleEntries: List.unmodifiable(cycleEntries),
    plainEntries: List.unmodifiable(plainEntries),
  );
}

/// 今日视图：普通任务日期为今天 + 所有启用中计划今天的任务。
DayView buildTodayView(AppData data, DateTime today) =>
    buildDayView(data, today, today: today);

/// 明日视图：**不落库**，只算「明天会出现什么」。
DayView buildTomorrowView(AppData data, DateTime today) =>
    buildDayView(data, addDays(today, 1), today: today);

int _byRemindThenTitle(DayEntry a, DayEntry b) {
  final aRemind = a.remindAt;
  final bRemind = b.remindAt;
  if (aRemind != null && bRemind != null) {
    final byRemind = aRemind.compareTo(bRemind);
    if (byRemind != 0) {
      return byRemind;
    }
  } else if (aRemind != null) {
    return -1;
  } else if (bRemind != null) {
    return 1;
  }
  return a.title.compareTo(b.title);
}

/// 供 Tab 2 复用的「今天到期的普通任务」计数（口径与 [Task] 分组一致）。
({int total, int completed}) todayPlainTaskCounts(AppData data, DateTime today) =>
    todayTaskCounts(data, today);
