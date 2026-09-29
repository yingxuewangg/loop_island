/// 任务实例记录（`Record`）的命令层：写未完成原因、补建记录等。
///
/// 与 `task_commands.dart` / `cycle_commands.dart` 一样是**纯函数**。
///
/// 单独成文件的原因：写原因是**普通任务与循环实例共有的能力**，
/// 放在任何一个既有命令文件里都会让另一个产生奇怪的依赖。
library;

import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';

/// 找到「某天的某条任务」对应的记录；没有则返回 null。
///
/// [cycleId] 为空表示普通任务。
Record? findEntryRecord(
  AppData data, {
  required String taskId,
  required DateTime date,
  String? cycleId,
}) {
  return data.findInstance(taskId: taskId, day: date, cycleId: cycleId);
}

/// 确保「某天的某条任务」有对应记录，没有就补建一条。
///
/// 返回 `(新数据, 该记录)`。已存在时原样返回入参。
({AppData data, Record record}) ensureEntryRecord(
  AppData data, {
  required String taskId,
  required DateTime date,
  String? cycleId,
  int? cycleDayIndex,
  TaskStatus status = TaskStatus.pending,
}) {
  final existing = findEntryRecord(
    data,
    taskId: taskId,
    date: date,
    cycleId: cycleId,
  );
  if (existing != null) {
    return (data: data, record: existing);
  }

  final created = Record.create(
    taskId: taskId,
    date: date,
    cycleId: cycleId,
    cycleDayIndex: cycleDayIndex,
    status: status,
  );
  return (
    data: data.copyWith(
      records: List.unmodifiable([...data.records, created]),
    ),
    record: created,
  );
}

/// 给「某天的某条任务」写入 / 清空未完成原因（任务 6.3）。
///
/// - 记录不存在时会先补建，避免用户填了原因却因为没物化而看不到。
/// - [reason] 为 null 或纯空白表示**清空**原因，同时清掉 `reasonUpdatedAt`。
/// - 只动 `reason` 与 `reasonUpdatedAt`，**不改状态** ——
///   「标记未完成」与「写原因」是两件独立的事，用户可能先写原因后改状态，也可能反过来。
AppData setEntryReason(
  AppData data, {
  required String taskId,
  required DateTime date,
  String? cycleId,
  int? cycleDayIndex,
  String? reason,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  final ensured = ensureEntryRecord(
    data,
    taskId: taskId,
    date: date,
    cycleId: cycleId,
    cycleDayIndex: cycleDayIndex,
  );

  final updated = ensured.record.withReason(reason, at: timestamp);
  if (updated == ensured.record) {
    return ensured.data;
  }

  return ensured.data.copyWith(
    records: List.unmodifiable([
      for (final record in ensured.data.records)
        if (record.id == updated.id) updated else record,
    ]),
  );
}

/// 按记录 id 写原因；记录不存在时原样返回。
AppData setRecordReason(
  AppData data,
  String recordId,
  String? reason, {
  DateTime? now,
}) {
  final existing = data.recordById(recordId);
  if (existing == null) {
    return data;
  }

  final updated = existing.withReason(reason, at: now ?? DateTime.now());
  if (updated == existing) {
    return data;
  }

  return data.copyWith(
    records: List.unmodifiable([
      for (final record in data.records)
        if (record.id == recordId) updated else record,
    ]),
  );
}

/// 按记录 id 标记未完成（可同时写原因）。
///
/// 存在的意义：**给记录层一个不依赖任务模板的入口**。
/// 某天详情页只有 `Record`，不需要回头去查它属于哪个任务或哪个计划。
AppData markRecordMissed(
  AppData data,
  String recordId, {
  String? reason,
  DateTime? now,
}) {
  final existing = data.recordById(recordId);
  if (existing == null) {
    return data;
  }

  final timestamp = now ?? DateTime.now();
  var updated = existing.withStatus(TaskStatus.missed, at: timestamp);
  if (reason != null) {
    updated = updated.withReason(reason, at: timestamp);
  }
  if (updated == existing) {
    return data;
  }

  return data.copyWith(
    records: List.unmodifiable([
      for (final record in data.records)
        if (record.id == recordId) updated else record,
    ]),
  );
}

/// 取某条记录当前的原因（没有记录或没填时为 null）。
String? entryReason(
  AppData data, {
  required String taskId,
  required DateTime date,
  String? cycleId,
}) {
  return findEntryRecord(
    data,
    taskId: taskId,
    date: date,
    cycleId: cycleId,
  )?.reason;
}
