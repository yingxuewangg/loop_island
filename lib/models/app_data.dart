import 'package:loop_island/core/date_x.dart';
import 'package:meta/meta.dart';

import 'cycle.dart';
import 'json_x.dart';
import 'record.dart';
import 'settings.dart';
import 'task.dart';

/// 应用全部数据的**不可变快照**。
///
/// 仓库层（`AppRepository`）只持有它，每次改动都生成新实例，
/// 这样 Riverpod 能靠 `==` 判断「是否真的变了」，测试里也能直接比较前后状态。
@immutable
class AppData {
  const AppData({
    this.tasks = const [],
    this.cycles = const [],
    this.records = const [],
    this.settings = const AppSettings(),
  });

  factory AppData.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    return AppData(
      tasks: List.unmodifiable(
        readMapList(json, 'tasks').map((e) => Task.fromJson(e, now: now)),
      ),
      cycles: List.unmodifiable(
        readMapList(json, 'cycles').map((e) => Cycle.fromJson(e, now: now)),
      ),
      records: List.unmodifiable(
        readMapList(json, 'records').map((e) => Record.fromJson(e, now: now)),
      ),
      settings: AppSettings.fromJson(readMap(json, 'settings')),
    );
  }

  /// 空数据（首次启动）。
  static const empty = AppData();

  final List<Task> tasks;
  final List<Cycle> cycles;
  final List<Record> records;
  final AppSettings settings;

  bool get isEmpty =>
      tasks.isEmpty && cycles.isEmpty && records.isEmpty;

  /// 是否有任何业务数据（不含设置）。
  bool get hasNoBusinessData => isEmpty;

  int get taskCount => tasks.length;
  int get cycleCount => cycles.length;
  int get recordCount => records.length;

  // ---------------------------------------------------------------- 查询

  /// 按 id 找普通任务。
  Task? taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  /// 按 id 找循环计划。
  Cycle? cycleById(String id) {
    for (final cycle in cycles) {
      if (cycle.id == id) {
        return cycle;
      }
    }
    return null;
  }

  /// 按 id 找记录。
  Record? recordById(String id) {
    for (final record in records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  /// 某一天的全部记录（按 id 稳定排序，保证 UI 顺序一致）。
  List<Record> recordsOn(DateTime day) {
    final key = dayKey(day);
    final result = records.where((e) => e.dayKeyValue == key).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }

  /// 某个任务的全部历史记录，按日期倒序（最新在前）。
  List<Record> recordsForTask(String taskId) {
    final result = records.where((e) => e.taskId == taskId).toList()
      ..sort((a, b) => dayNumber(b.date).compareTo(dayNumber(a.date)));
    return List.unmodifiable(result);
  }

  /// 某个循环计划的全部实例记录，按日期升序。
  List<Record> recordsForCycle(String cycleId) {
    final result = records.where((e) => e.cycleId == cycleId).toList()
      ..sort((a, b) => dayNumber(a.date).compareTo(dayNumber(b.date)));
    return List.unmodifiable(result);
  }

  /// 某一天某任务实例是否已存在（用于物化时的幂等判断）。
  Record? findInstance({
    required String taskId,
    required DateTime day,
    String? cycleId,
  }) {
    final key = dayKey(day);
    for (final record in records) {
      if (record.taskId == taskId &&
          record.dayKeyValue == key &&
          record.cycleId == cycleId) {
        return record;
      }
    }
    return null;
  }

  /// 仍会出现在今日/明日页的循环计划（按创建时间排序）。
  List<Cycle> get runningCycles {
    final result = cycles.where((e) => e.isRunning).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  /// 已结束（已归档）的循环计划。
  List<Cycle> get archivedCycles {
    final result = cycles.where((e) => e.isEnded).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  // ---------------------------------------------------------------- 序列化

  Map<String, dynamic> toJson() => {
        'tasks': List.unmodifiable(tasks.map((e) => e.toJson())),
        'cycles': List.unmodifiable(cycles.map((e) => e.toJson())),
        'records': List.unmodifiable(records.map((e) => e.toJson())),
        'settings': settings.toJson(),
      };

  AppData copyWith({
    List<Task>? tasks,
    List<Cycle>? cycles,
    List<Record>? records,
    AppSettings? settings,
  }) {
    return AppData(
      tasks: tasks ?? this.tasks,
      cycles: cycles ?? this.cycles,
      records: records ?? this.records,
      settings: settings ?? this.settings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppData && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'AppData(tasks=${tasks.length}, '
      'cycles=${cycles.length}, records=${records.length})';
}
