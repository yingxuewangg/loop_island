import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:meta/meta.dart';

import 'enums.dart';
import 'json_x.dart';

/// 普通任务（一次性任务）。
///
/// 与循环计划无关；`dateType` 决定它出现在哪一天。
/// [date] 仅在 [TaskDateType.custom] 时有意义，其余情况由
/// [resolvedDate] 依据「今天」推算。
@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    this.note = '',
    this.dateType = TaskDateType.none,
    this.date,
    this.remindAts = const [],
    this.status = TaskStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  /// 从 JSON 还原。
  ///
  /// [now] 仅在数据损坏（缺少 `createdAt`/`updatedAt`）时用作回落，
  /// 显式传入可让测试完全确定。
  factory Task.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final fallbackNow = now ?? DateTime.now();
    final rawDateType = readStrOrNull(json, 'dateType');
    final date = readDay(json, 'date');

    return Task(
      id: readStr(json, 'id'),
      title: readStr(json, 'title'),
      note: readStr(json, 'note'),
      // 缺少 dateType 时按有无 date 推断，避免老数据丢日期
      dateType: rawDateType != null
          ? TaskDateType.parse(rawDateType)
          : (date != null ? TaskDateType.custom : TaskDateType.none),
      date: date,
      remindAts: _readRemindAts(json),
      status: TaskStatus.parse(readStrOrNull(json, 'status')),
      createdAt: readInstant(json, 'createdAt') ?? fallbackNow,
      updatedAt: readInstant(json, 'updatedAt') ?? fallbackNow,
      completedAt: readInstant(json, 'completedAt'),
    );
  }

  final String id;
  final String title;
  final String note;
  final TaskDateType dateType;

  /// 自定义日期（本地日历日）；仅 [TaskDateType.custom] 时有值。
  final DateTime? date;

  /// 提醒时刻列表（升序、去重、最多 [kMaxRemindSlots] 个）；空表示不提醒。
  ///
  /// 「一天提醒 N 次」就靠它：例如 10:30 与 15:30 各提醒一次。
  final List<DateTime> remindAts;

  /// 最早的提醒时刻；没有提醒时为 null。
  ///
  /// 排序与单行展示只需要「第一个」，保留这个派生 getter 让调用方
  /// 不必到处写 `remindAts.isEmpty ? null : remindAts.first`。
  DateTime? get remindAt => remindAts.isEmpty ? null : remindAts.first;

  final TaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  /// 是否已完成。
  bool get isCompleted => status == TaskStatus.completed;

  /// 是否已了结（完成 / 跳过 / 未完成）。
  bool get isSettled => status.isSettled;

  /// 是否需要按「今天」推算日期（即今天 / 明天两种相对日期）。
  bool get isRelativeDate =>
      dateType == TaskDateType.today || dateType == TaskDateType.tomorrow;

  /// 依据「今天」算出该任务实际落在哪一天；无日期返回 null。
  DateTime? resolvedDate(DateTime today) {
    switch (dateType) {
      case TaskDateType.today:
        return dateOnly(today);
      case TaskDateType.tomorrow:
        return addDays(today, 1);
      case TaskDateType.custom:
        return date;
      case TaskDateType.none:
        return null;
    }
  }

  /// 依据「今天」算出的日期键，用于与 `Record.date` 比对。
  String? resolvedDayKey(DateTime today) {
    final resolved = resolvedDate(today);
    return resolved == null ? null : dayKey(resolved);
  }

  /// 把所有相对日期固化为具体日期（编辑页保存时使用）。
  ///
  /// 例如保存「今天」的任务时把 `dateType` 变成 `custom` + 具体 `date`，
  /// 这样明天再看它仍指向同一天。
  Task materializeDate(DateTime today) {
    if (!isRelativeDate) {
      return this;
    }
    return copyWith(
      dateType: TaskDateType.custom,
      date: resolvedDate(today),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'dateType': dateType.wireName,
        'date': writeDay(date),
        'remindAts': writeInstantList(remindAts),
        'status': status.wireName,
        'createdAt': writeInstant(createdAt),
        'updatedAt': writeInstant(updatedAt),
        'completedAt': writeInstant(completedAt),
      };

  Task copyWith({
    String? id,
    String? title,
    String? note,
    TaskDateType? dateType,
    Object? date = kUnset,
    Object? remindAts = kUnset,
    Object? remindAt = kUnset,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kUnset,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      dateType: dateType ?? this.dateType,
      date: identical(date, kUnset) ? this.date : date as DateTime?,
      remindAts: _resolveRemindAts(remindAts: remindAts, remindAt: remindAt),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, kUnset)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  /// 解析 [copyWith] 的两个提醒参数。
  ///
  /// [remindAts] 是正式接口；[remindAt] 是「只设 / 只清一个时段」的便捷写法，
  /// 两者都传时以 [remindAts] 为准（别让调用方猜优先级）。
  List<DateTime> _resolveRemindAts({
    required Object? remindAts,
    required Object? remindAt,
  }) {
    if (!identical(remindAts, kUnset)) {
      return remindAts == null
          ? const []
          : normalizeInstantSlots(remindAts as Iterable<DateTime>);
    }
    if (identical(remindAt, kUnset)) {
      return this.remindAts;
    }
    final single = remindAt as DateTime?;
    return single == null ? const [] : normalizeInstantSlots([single]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'Task($id, $title, ${dateType.wireName}, '
      '${status.wireName})';
}

/// 读取提醒时刻列表，并兼容「只有一个 `remindAt`」的老备份。
///
/// 老版本存的是单个 `remindAt`；新版本写 `remindAts`。这里优先读新键，
/// 新键缺失时才把老键包成单元素列表 —— 老备份因此可以无缝升级，
/// 不需要任何迁移脚本。
List<DateTime> _readRemindAts(Map<String, dynamic> json) {
  final list = readInstantList(json, 'remindAts');
  if (list.isNotEmpty) {
    return normalizeInstantSlots(list);
  }
  final legacy = readInstant(json, 'remindAt');
  return legacy == null ? const [] : normalizeInstantSlots([legacy]);
}
