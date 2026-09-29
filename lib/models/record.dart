import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/ids.dart';
import 'package:meta/meta.dart';

import 'enums.dart';
import 'json_x.dart';

/// 某一天的任务实例记录。
///
/// 这是**历史事实**，不是模板：
/// - 勾选完成只写 `Record.status`，绝不回写周期模板（PRD 关键规则）。
/// - `cycleId` / `cycleDayIndex` 为空表示它来自普通任务。
/// - 修改结束日期、编辑周期模板都会重算未来的 `Record`，
///   但**今天之前的 `Record` 保持不变**。
@immutable
class Record {
  const Record({
    required this.id,
    required this.taskId,
    this.cycleId,
    this.cycleDayIndex,
    required this.date,
    this.status = TaskStatus.pending,
    this.completedAt,
    this.reason,
    this.reasonUpdatedAt,
    this.rescheduledFrom,
    this.titleOverride,
    this.updatedAt,
  });

  /// 为某天的任务实例新建一条记录。
  factory Record.create({
    required String taskId,
    required DateTime date,
    String? cycleId,
    int? cycleDayIndex,
    TaskStatus status = TaskStatus.pending,
    DateTime? completedAt,
    DateTime? rescheduledFrom,
    String? titleOverride,
    DateTime? updatedAt,
  }) {
    return Record(
      id: newRecordId(),
      taskId: taskId,
      cycleId: cycleId,
      cycleDayIndex: cycleDayIndex,
      date: dateOnly(date),
      status: status,
      completedAt: completedAt,
      rescheduledFrom:
          rescheduledFrom == null ? null : dateOnly(rescheduledFrom),
      titleOverride: titleOverride,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory Record.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final date = readDay(json, 'date') ?? dateOnly(now ?? DateTime.now());
    return Record(
      id: readStr(json, 'id'),
      taskId: readStr(json, 'taskId'),
      cycleId: readStrOrNull(json, 'cycleId'),
      cycleDayIndex: readIntOrNull(json, 'cycleDayIndex'),
      date: date,
      status: TaskStatus.parse(readStrOrNull(json, 'status')),
      completedAt: readInstant(json, 'completedAt'),
      reason: readStrOrNull(json, 'reason'),
      reasonUpdatedAt: readInstant(json, 'reasonUpdatedAt'),
      rescheduledFrom: readDay(json, 'rescheduledFrom'),
      titleOverride: readStrOrNull(json, 'titleOverride'),
      // 老备份里可能没有 updatedAt，保持 null（由 `modifiedAt` 退化到归属日）。
      // **不要在这里回落到 date**：那会让「往返后对象 != 原对象」，
      // 序列化往返测试会直接抓到。
      updatedAt: readInstant(json, 'updatedAt'),
    );
  }

  final String id;

  /// 对应的任务模板 id（普通任务用 `Task.id`，循环任务用 `CycleTaskTemplate.id`）。
  final String taskId;

  /// 所属循环计划 id；普通任务为 null。
  final String? cycleId;

  /// 周期内第几天（1 起）；普通任务为 null。
  final int? cycleDayIndex;

  /// 归属日期（本地日历日）。
  final DateTime date;

  final TaskStatus status;

  /// 完成时间点。
  final DateTime? completedAt;

  /// 未完成原因（自由文本或快捷原因），可为空。
  final String? reason;

  /// 原因最后更新时间。
  final DateTime? reasonUpdatedAt;

  /// 从哪一天顺延而来（PRD §八.2）。
  final DateTime? rescheduledFrom;

  /// 仅这一天的标题覆盖（PRD §七：修改循环任务默认只改今天）。
  ///
  /// 为 null 时标题取模板的标题。**只对循环实例有意义**：
  /// 这样「仅本次改名」不用去动模板，历史与未来互不影响。
  final String? titleOverride;

  /// 这条记录最后一次被修改的时间。
  ///
  /// **存在的理由是「合并导入」**：同 id 的记录必须能判断谁更新，
  /// 否则「导入备份 + 合并」会随机地用旧数据覆盖用户刚做的事。
  /// `withStatus` / `withReason` / `withTitleOverride` 都会推进它。
  final DateTime? updatedAt;

  /// 是否来自循环计划。
  bool get isCycleInstance => cycleId != null;

  bool get isCompleted => status == TaskStatus.completed;
  bool get isMissed => status == TaskStatus.missed;
  bool get isSkipped => status == TaskStatus.skipped;
  bool get isPending => status == TaskStatus.pending;

  /// 是否填了非空原因。
  bool get hasReason => (reason ?? '').trim().isNotEmpty;

  /// 归属日期键（`yyyy-MM-dd`）。
  String get dayKeyValue => dayKey(date);

  /// 用于「较新者胜」比较的时间戳。
  DateTime get modifiedAt => updatedAt ?? date;

  /// 在这天更新状态，并自动维护 `completedAt` 与 `updatedAt`。
  ///
  /// - 置为 `completed` 时写入 [at]（默认现在）；
  /// - 置为其它状态时清空 `completedAt`，避免留下「未完成却有完成时间」的脏数据。
  Record withStatus(TaskStatus next, {DateTime? at}) {
    final moment = at ?? DateTime.now();
    if (next == TaskStatus.completed) {
      return copyWith(
        status: next,
        completedAt: moment,
        updatedAt: moment,
      );
    }
    return copyWith(status: next, completedAt: null, updatedAt: moment);
  }

  /// 写入 / 清空未完成原因，并刷新 `reasonUpdatedAt`。
  ///
  /// 空串与纯空白按「清空」处理，与 [hasReason] 语义一致。
  Record withReason(String? text, {DateTime? at}) {
    final moment = at ?? DateTime.now();
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return copyWith(
        reason: null,
        reasonUpdatedAt: null,
        updatedAt: moment,
      );
    }
    return copyWith(
      reason: trimmed,
      reasonUpdatedAt: moment,
      updatedAt: moment,
    );
  }

  /// 写入 / 清空这一天专属的标题覆盖。
  ///
  /// 空串与纯空白按「清空」处理（即恢复用模板标题）。
  Record withTitleOverride(String? text, {DateTime? at}) {
    final moment = at ?? DateTime.now();
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return copyWith(titleOverride: null, updatedAt: moment);
    }
    return copyWith(titleOverride: trimmed, updatedAt: moment);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'cycleId': cycleId,
        'cycleDayIndex': cycleDayIndex,
        'date': writeDay(date),
        'status': status.wireName,
        'completedAt': writeInstant(completedAt),
        'reason': reason,
        'reasonUpdatedAt': writeInstant(reasonUpdatedAt),
        'rescheduledFrom': writeDay(rescheduledFrom),
        'titleOverride': titleOverride,
        'updatedAt': writeInstant(updatedAt),
      };

  Record copyWith({
    String? id,
    String? taskId,
    Object? cycleId = kUnset,
    Object? cycleDayIndex = kUnset,
    DateTime? date,
    TaskStatus? status,
    Object? completedAt = kUnset,
    Object? reason = kUnset,
    Object? reasonUpdatedAt = kUnset,
    Object? rescheduledFrom = kUnset,
    Object? titleOverride = kUnset,
    Object? updatedAt = kUnset,
  }) {
    return Record(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      cycleId: identical(cycleId, kUnset) ? this.cycleId : cycleId as String?,
      cycleDayIndex: identical(cycleDayIndex, kUnset)
          ? this.cycleDayIndex
          : cycleDayIndex as int?,
      date: date == null ? this.date : dateOnly(date),
      status: status ?? this.status,
      completedAt: identical(completedAt, kUnset)
          ? this.completedAt
          : completedAt as DateTime?,
      reason: identical(reason, kUnset) ? this.reason : reason as String?,
      reasonUpdatedAt: identical(reasonUpdatedAt, kUnset)
          ? this.reasonUpdatedAt
          : reasonUpdatedAt as DateTime?,
      rescheduledFrom: identical(rescheduledFrom, kUnset)
          ? this.rescheduledFrom
          : (rescheduledFrom == null
              ? null
              : dateOnly(rescheduledFrom as DateTime)),
      titleOverride: identical(titleOverride, kUnset)
          ? this.titleOverride
          : titleOverride as String?,
      updatedAt: identical(updatedAt, kUnset)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Record && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'Record($id, task=$taskId, $dayKeyValue, '
      '${status.wireName}${cycleId == null ? '' : ', cycle=$cycleId#$cycleDayIndex'})';
}
