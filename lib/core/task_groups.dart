import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/task.dart';
import 'package:meta/meta.dart';

/// 普通任务按日期分组的结果（对应 PRD「Tab 2 任务」的分组列表）。
///
/// PRD 只要求四组：今天 / 明天 / 未安排 / 已完成。
/// 这里额外给出 [overdue]（逾期未完成）与 [upcoming]（后天及以后）两组，
/// 原因是**只按四组切分会让一部分任务从列表里彻底消失**：
/// 昨天没做完的任务、下个月才到期的任务既不属于今天/明天/未安排，
/// 也不是已完成。命令层保持完备，展示与否交给 UI 决定。
@immutable
class TaskGroups {
  const TaskGroups({
    this.today = const [],
    this.tomorrow = const [],
    this.unscheduled = const [],
    this.completed = const [],
    this.overdue = const [],
    this.upcoming = const [],
  });

  /// 今天到期且未完成。
  final List<Task> today;

  /// 明天到期且未完成。
  final List<Task> tomorrow;

  /// 无日期且未完成。
  final List<Task> unscheduled;

  /// 已完成（不论日期），按完成时间倒序。
  final List<Task> completed;

  /// 今天之前到期且未完成（PRD 四组之外的补充组）。
  final List<Task> overdue;

  /// 后天及以后到期且未完成（PRD 四组之外的补充组）。
  final List<Task> upcoming;

  /// 是否有任何任务。
  bool get isEmpty =>
      today.isEmpty &&
      tomorrow.isEmpty &&
      unscheduled.isEmpty &&
      completed.isEmpty &&
      overdue.isEmpty &&
      upcoming.isEmpty;

  /// 按 PRD 顺序返回「今天 / 明天 / 未安排 / 已完成」四组。
  Map<String, List<Task>> get prdGroups => {
        'today': today,
        'tomorrow': tomorrow,
        'unscheduled': unscheduled,
        'completed': completed,
      };

  @override
  String toString() => 'TaskGroups(今天=${today.length}, 明天=${tomorrow.length}, '
      '未安排=${unscheduled.length}, 已完成=${completed.length}, '
      '逾期=${overdue.length}, 以后=${upcoming.length})';
}

/// 把全部普通任务切分到各日期分组。纯函数，无副作用。
///
/// 分组依据是 [Task.resolvedDate]（会把「今天 / 明天」按 [today] 换算成具体日期）。
///
/// 排序规则（PRD：分组查看要有稳定顺序）：
/// - [today]：先按提醒时间升序，无提醒的排在最后；同一时刻再按创建时间升序。
/// - [tomorrow] / [unscheduled] / [overdue] / [upcoming]：按创建时间升序。
/// - [completed]：按完成时间倒序（最近完成的在最上面）。
TaskGroups groupTasks(AppData data, DateTime today) {
  final todayOnly = dateOnly(today);
  final tomorrowOnly = addDays(todayOnly, 1);
  final todayKeyValue = dayKey(todayOnly);

  final todayList = <Task>[];
  final tomorrowList = <Task>[];
  final unscheduledList = <Task>[];
  final completedList = <Task>[];
  final overdueList = <Task>[];
  final upcomingList = <Task>[];

  for (final task in data.tasks) {
    if (task.isCompleted) {
      completedList.add(task);
      continue;
    }

    final resolved = task.resolvedDate(todayOnly);
    if (resolved == null) {
      unscheduledList.add(task);
      continue;
    }

    final resolvedKey = dayKey(resolved);
    if (resolvedKey == todayKeyValue) {
      todayList.add(task);
    } else if (isSameDay(resolved, tomorrowOnly)) {
      tomorrowList.add(task);
    } else if (isBeforeDay(resolved, todayOnly)) {
      overdueList.add(task);
    } else {
      upcomingList.add(task);
    }
  }

  todayList.sort(_byRemindThenCreated);
  tomorrowList.sort(_byCreated);
  unscheduledList.sort(_byCreated);
  overdueList.sort(_byCreated);
  upcomingList.sort(_byCreated);
  completedList.sort(_byCompletedDesc);

  return TaskGroups(
    today: List.unmodifiable(todayList),
    tomorrow: List.unmodifiable(tomorrowList),
    unscheduled: List.unmodifiable(unscheduledList),
    completed: List.unmodifiable(completedList),
    overdue: List.unmodifiable(overdueList),
    upcoming: List.unmodifiable(upcomingList),
  );
}

/// 今天到期的普通任务总数与其中已完成数（供 Tab 2 的「今天」分节标题使用）。
///
/// 与 [TaskGroups.today] + [TaskGroups.completed] 不同：这里**按日期口径**统计，
/// 只算归属今天的任务（含今天已完成的那部分），
/// 不会把「昨天完成」的任务算进今天的进度里。
({int total, int completed}) todayTaskCounts(AppData data, DateTime today) {
  final todayKeyValue = dayKey(dateOnly(today));
  var total = 0;
  var completed = 0;

  for (final task in data.tasks) {
    if (task.resolvedDayKey(today) != todayKeyValue) {
      continue;
    }
    total++;
    if (task.isCompleted) {
      completed++;
    }
  }

  return (total: total, completed: completed);
}

int _byCreated(Task a, Task b) => a.createdAt.compareTo(b.createdAt);

/// 有提醒的排前面（按时刻升序），无提醒的排后面，持平再按创建时间。
int _byRemindThenCreated(Task a, Task b) {
  final aRemind = a.remindAt;
  final bRemind = b.remindAt;
  if (aRemind != null && bRemind != null) {
    final byRemind = aRemind.compareTo(bRemind);
    return byRemind != 0 ? byRemind : _byCreated(a, b);
  }
  if (aRemind != null) {
    return -1;
  }
  if (bRemind != null) {
    return 1;
  }
  return _byCreated(a, b);
}

/// 最近完成的排在前面；都没有完成时间时按创建时间倒序兜底。
int _byCompletedDesc(Task a, Task b) {
  final aAt = a.completedAt;
  final bAt = b.completedAt;
  if (aAt != null && bAt != null) {
    final byCompleted = bAt.compareTo(aAt);
    return byCompleted != 0 ? byCompleted : _byCreated(b, a);
  }
  if (aAt != null) {
    return -1;
  }
  if (bAt != null) {
    return 1;
  }
  return _byCreated(b, a);
}
