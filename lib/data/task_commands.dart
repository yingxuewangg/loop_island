/// 普通任务的命令层。
///
/// **全部是纯函数**：输入旧 [AppData]，返回新 [AppData]，不碰磁盘、不碰
/// `DateTime.now()`（时间一律由 `now` 参数注入）。好处是命令层可以在纯 Dart
/// 测试里反复验证，落盘与广播交给 `AppRepository.commit` 统一处理。
///
/// 写入口只有这些函数 —— UI 不得直接改 `data.tasks`。
library;

import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/ids.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';
import 'package:loop_island/models/task.dart';
import 'package:meta/meta.dart';

/// 新建任务。
///
/// - [title] 会去除首尾空白；为空时抛 [ArgumentError]（PRD 要求标题必填）。
/// - [dateType] 为 `custom` 但未给 [date] 时落到「今天」。
/// - **相对日期（今天 / 明天）在写入时立即固化成具体日期**（见下方说明）。
/// - 无日期任务不允许带提醒时间（PRD：提醒必须依附某一天）。
/// - 提醒支持多时段：优先用 [remindAts]；只想要一个时段时可用 [remindAt]
///   这个便捷参数（两者都传时以 [remindAts] 为准）。
///
/// ## 为什么相对日期必须在这里固化
///
/// 「今天 / 明天」是**相对**概念，一旦落盘就固定了含义：26 号存的
/// `tomorrow` 到了 27 号会算成 28 号，任务会一直往后漂移，而它的提醒
/// 时刻仍停在原定那一天 —— 于是提醒时刻被判为「已过去」，通知不再注册。
///
/// 在命令层（而不是编辑页）固化，是因为这是**数据层的约束**：任何入口
/// 新建任务都必须遵守。之前只有编辑页的「编辑分支」记得补一次固化，
/// 新建分支与其它调用方漏了，就出现了上面这个 bug。
AppData addTask(
  AppData data, {
  required String title,
  String note = '',
  TaskDateType dateType = TaskDateType.none,
  DateTime? date,
  Iterable<DateTime>? remindAts,
  DateTime? remindAt,
  TaskStatus status = TaskStatus.pending,
  String? id,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(title, 'title', '任务标题不能为空');
  }

  final slots = remindAts ?? (remindAt == null ? const [] : [remindAt]);

  final task = _materializeRelative(
    _normalize(
      Task(
        id: id ?? newTaskId(),
        title: trimmed,
        note: note.trim(),
        dateType: dateType,
        date: date,
        remindAts: normalizeInstantSlots(slots),
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
        completedAt: status == TaskStatus.completed ? timestamp : null,
      ),
      today: timestamp,
    ),
    // 调用方若已给出具体日期（界面按它展示过），以它为准：这样「界面显示
    // 哪天」与「落盘哪天」用的是同一个来源，不会因跨零点而差一天。
    explicitDate: date,
    fallbackToday: timestamp,
  );

  return data.copyWith(
    tasks: List.unmodifiable([...data.tasks, task]),
  );
}

/// 把相对日期（今天 / 明天）固化成具体日期；已是具体日期 / 无日期则原样返回。
///
/// 优先用 [explicitDate]（调用方按它展示过），缺失时才用 [fallbackToday] 推算。
Task _materializeRelative(
  Task task, {
  required DateTime? explicitDate,
  required DateTime fallbackToday,
}) {
  if (!task.isRelativeDate) {
    return task;
  }
  final resolved = explicitDate == null
      ? task.resolvedDate(fallbackToday)
      : dateOnly(explicitDate);
  if (resolved == null) {
    return task;
  }
  return task.copyWith(dateType: TaskDateType.custom, date: resolved);
}

/// 更新任务（按 [task] 的 id 替换）。
///
/// - 自动刷新 `updatedAt` 为 [now]。
/// - 若状态发生变化，会同步写入当天的任务实例记录。
/// - **历史记录不会被改写**：即使改了任务日期，旧日期的 [Record] 仍保留，
///   因为它们是既成事实。
AppData updateTask(
  AppData data,
  Task task, {
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  final index = data.tasks.indexWhere((e) => e.id == task.id);
  if (index < 0) {
    throw ArgumentError.value(task.id, 'task.id', '要更新的任务不存在');
  }

  final previous = data.tasks[index];
  final trimmedTitle = task.title.trim();
  if (trimmedTitle.isEmpty) {
    throw ArgumentError.value(task.title, 'task.title', '任务标题不能为空');
  }

  final normalized = _normalize(
    task.copyWith(
      title: trimmedTitle,
      note: task.note.trim(),
      // 状态从「完成」改成别的时清掉完成时间
      completedAt: task.status == TaskStatus.completed
          ? (task.completedAt ?? timestamp)
          : null,
    ),
    today: timestamp,
  ).copyWith(updatedAt: timestamp);

  final tasks = [...data.tasks];
  tasks[index] = normalized;
  var next = data.copyWith(tasks: List.unmodifiable(tasks));

  if (previous.status != normalized.status) {
    next = _syncRecord(next, normalized, now: timestamp);
  }
  return next;
}

/// 删除任务，**并级联删除它的全部历史记录**。
///
/// 任务不存在时原样返回（幂等），避免重复点击删除报错。
AppData deleteTask(AppData data, String taskId) {
  final exists = data.tasks.any((e) => e.id == taskId);
  if (!exists) {
    return data;
  }

  return data.copyWith(
    tasks: List.unmodifiable(
      data.tasks.where((e) => e.id != taskId),
    ),
    records: List.unmodifiable(
      data.records.where((e) => e.taskId != taskId),
    ),
  );
}

/// 修改任务状态，并同步当天的任务实例记录。
///
/// 状态语义（PRD §八.3）：
/// - `completed`：写 `completedAt`
/// - `pending`：清 `completedAt`（取消完成）
/// - `missed` / `skipped`：清 `completedAt`
AppData setTaskStatus(
  AppData data,
  String taskId,
  TaskStatus status, {
  DateTime? now,
  bool writeRecord = true,
}) {
  final timestamp = now ?? DateTime.now();
  final index = data.tasks.indexWhere((e) => e.id == taskId);
  if (index < 0) {
    throw ArgumentError.value(taskId, 'taskId', '任务不存在');
  }

  final current = data.tasks[index];
  final updated = current.copyWith(
    status: status,
    updatedAt: timestamp,
    completedAt: status == TaskStatus.completed ? timestamp : null,
  );

  final tasks = [...data.tasks];
  tasks[index] = updated;
  final next = data.copyWith(tasks: List.unmodifiable(tasks));

  return writeRecord ? _syncRecord(next, updated, now: timestamp) : next;
}

/// 勾选完成。
AppData completeTask(AppData data, String taskId, {DateTime? now}) =>
    setTaskStatus(data, taskId, TaskStatus.completed, now: now);

/// 取消完成，回到待办。
AppData uncompleteTask(AppData data, String taskId, {DateTime? now}) =>
    setTaskStatus(data, taskId, TaskStatus.pending, now: now);

/// 标记未完成。
AppData markTaskMissed(AppData data, String taskId, {DateTime? now}) =>
    setTaskStatus(data, taskId, TaskStatus.missed, now: now);

/// 跳过任务。
AppData markTaskSkipped(AppData data, String taskId, {DateTime? now}) =>
    setTaskStatus(data, taskId, TaskStatus.skipped, now: now);

/// 把任务的相对日期（今天 / 明天）固化成具体日期。
///
/// 编辑页保存时调用：否则「今天」的任务明天会自动漂移到明天。
/// 任务本来就没有相对日期时**原样返回**，不刷新 `updatedAt` ——
/// 否则「重新保存一次没改的任务」也会把更新时间推到现在。
AppData materializeTaskDate(
  AppData data,
  String taskId, {
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  final index = data.tasks.indexWhere((e) => e.id == taskId);
  if (index < 0) {
    return data;
  }

  final current = data.tasks[index];
  final materialized = current.materializeDate(timestamp);
  if (materialized == current) {
    return data;
  }

  final tasks = [...data.tasks];
  tasks[index] = materialized.copyWith(updatedAt: timestamp);
  return data.copyWith(tasks: List.unmodifiable(tasks));
}

// ------------------------------------------------------------------ 内部

/// 修正字段间的一致性。
Task _normalize(Task task, {required DateTime today}) {
  var dateType = task.dateType;
  DateTime? date = task.date;

  if (dateType == TaskDateType.custom) {
    // 自定义日期缺省落到今天，避免出现「自定义但没日期」的空洞状态
    date = dateOnly(date ?? today);
  } else {
    date = null;
  }

  // 无日期任务不保留提醒时间
  final remindAts =
      dateType == TaskDateType.none ? const <DateTime>[] : task.remindAts;

  return task.copyWith(dateType: dateType, date: date, remindAts: remindAts);
}

/// 为任务在「它归属的那一天」写入 / 更新实例记录。
///
/// 归属日取 `resolvedDate`；无日期任务落到今天（完成当天即为记录日）。
AppData _syncRecord(AppData data, Task task, {required DateTime now}) {
  final day = task.resolvedDate(now) ?? dateOnly(now);
  final existing = data.findInstance(taskId: task.id, day: day);

  if (existing == null) {
    final created = Record.create(
      taskId: task.id,
      date: day,
      status: task.status,
      completedAt: task.completedAt,
    );
    return data.copyWith(
      records: List.unmodifiable([...data.records, created]),
    );
  }

  final updated = existing.withStatus(task.status, at: task.completedAt ?? now);
  return data.copyWith(
    records: List.unmodifiable([
      for (final record in data.records)
        if (record.id == existing.id) updated else record,
    ]),
  );
}

/// 供 UI 复用的校验：任务标题是否合法。
@useResult
bool isValidTaskTitle(String title) => title.trim().isNotEmpty;
