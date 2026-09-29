/// 导入恢复的合并策略（任务 7.3 / 7.4）。
///
/// 两种导入方式：
/// - **合并**：[mergeData] 把备份并进现有数据，同 id 取「较新者」；
/// - **覆盖**：[replaceData] 直接用备份替换现有数据。
///
/// 无论哪种方式都**不在这里落盘** —— 落盘由 `AppRepository.commit` 统一负责。
library;

import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/record.dart';
import 'package:loop_island/models/task.dart';
import 'package:meta/meta.dart';

/// 合并结果统计（导入完成后展示给用户）。
@immutable
class MergeStats {
  const MergeStats({
    required this.addedTasks,
    required this.updatedTasks,
    required this.addedCycles,
    required this.updatedCycles,
    required this.addedRecords,
    required this.updatedRecords,
  });

  static const empty = MergeStats(
    addedTasks: 0,
    updatedTasks: 0,
    addedCycles: 0,
    updatedCycles: 0,
    addedRecords: 0,
    updatedRecords: 0,
  );

  final int addedTasks;
  final int updatedTasks;
  final int addedCycles;
  final int updatedCycles;
  final int addedRecords;
  final int updatedRecords;

  int get added => addedTasks + addedCycles + addedRecords;
  int get updated => updatedTasks + updatedCycles + updatedRecords;

  /// 本地保留（备份里没有、或没本地新）的总数。
  int get total => added + updated;

  @override
  String toString() =>
      'MergeStats(新增 $added, 覆盖 $updated)';
}

/// 合并导入的结果。
@immutable
class MergeResult {
  const MergeResult({required this.data, required this.stats});

  final AppData data;
  final MergeStats stats;
}

/// 7.3 把 [incoming] 合并进 [local]。
///
/// 规则：
/// - 同 id 的**任务 / 计划 / 记录**：谁的更新时间更晚用谁；时间相同保留本地
///   （这样重复合并同一份备份不会来回抖动）。
/// - 备份里有、本地没有的：新增。
/// - 本地有、备份里没有的：保留（合并的语义就是「不删」）。
/// - **设置保留本地的**：应用锁、提醒开关属于本机配置，
///   不该因为导入一份别人的备份就被改掉；要替换设置请用「覆盖导入」。
MergeResult mergeData(AppData local, AppData incoming) {
  var addedTasks = 0;
  var updatedTasks = 0;
  var addedCycles = 0;
  var updatedCycles = 0;
  var addedRecords = 0;
  var updatedRecords = 0;

  // ---- 任务 ----
  final taskIndex = <String, Task>{
    for (final task in local.tasks) task.id: task,
  };
  for (final task in incoming.tasks) {
    final existing = taskIndex[task.id];
    if (existing == null) {
      taskIndex[task.id] = task;
      addedTasks++;
    } else if (task.updatedAt.isAfter(existing.updatedAt)) {
      taskIndex[task.id] = task;
      updatedTasks++;
    }
  }

  // ---- 计划 ----
  final cycleIndex = <String, Cycle>{
    for (final cycle in local.cycles) cycle.id: cycle,
  };
  for (final cycle in incoming.cycles) {
    final existing = cycleIndex[cycle.id];
    if (existing == null) {
      cycleIndex[cycle.id] = cycle;
      addedCycles++;
    } else if (cycle.updatedAt.isAfter(existing.updatedAt)) {
      cycleIndex[cycle.id] = cycle;
      updatedCycles++;
    }
  }

  // ---- 记录 ----
  final recordIndex = <String, Record>{
    for (final record in local.records) record.id: record,
  };
  for (final record in incoming.records) {
    final existing = recordIndex[record.id];
    if (existing == null) {
      recordIndex[record.id] = record;
      addedRecords++;
    } else if (record.modifiedAt.isAfter(existing.modifiedAt)) {
      recordIndex[record.id] = record;
      updatedRecords++;
    }
  }

  return MergeResult(
    data: AppData(
      tasks: List.unmodifiable(_tasksById(taskIndex.values)),
      cycles: List.unmodifiable(_cyclesByCreated(cycleIndex.values)),
      records: List.unmodifiable(_recordsById(recordIndex.values)),
      settings: local.settings,
    ),
    stats: MergeStats(
      addedTasks: addedTasks,
      updatedTasks: updatedTasks,
      addedCycles: addedCycles,
      updatedCycles: updatedCycles,
      addedRecords: addedRecords,
      updatedRecords: updatedRecords,
    ),
  );
}

/// 7.4 覆盖导入：直接用备份里的数据替换本地。
///
/// **连设置一起替换** —— 这是「覆盖」与「合并」的关键区别，
/// 也是用户明确选择「覆盖现有数据」时应有的语义。
AppData replaceData(AppData incoming) => incoming;

List<Task> _tasksById(Iterable<Task> items) {
  return [...items]..sort((a, b) => a.id.compareTo(b.id));
}

List<Cycle> _cyclesByCreated(Iterable<Cycle> items) {
  return [...items]
    ..sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
}

List<Record> _recordsById(Iterable<Record> items) {
  return [...items]..sort((a, b) => a.id.compareTo(b.id));
}
