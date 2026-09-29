import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/models/task.dart';

/// 测试用的固定时间基准，保证所有断言确定、不受运行时刻影响。
final DateTime kBaseNow = DateTime(2026, 9, 12, 10, 0, 0);

/// 测试用「今天」。
final DateTime kToday = dateOnly(kBaseNow);

/// 造一个普通任务。
///
/// [remindAt] 是「只设一个提醒时段」的便捷写法；多时段用 [remindAts]。
Task makeTask({
  String id = 'task_1',
  String title = '写周报',
  String note = '',
  TaskDateType dateType = TaskDateType.custom,
  DateTime? date,
  bool hasDate = true,
  DateTime? remindAt,
  List<DateTime>? remindAts,
  TaskStatus status = TaskStatus.pending,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? completedAt,
}) {
  final resolvedDate = hasDate ? (date ?? kToday) : null;
  final effectiveType = hasDate ? dateType : TaskDateType.none;
  return Task(
    id: id,
    title: title,
    note: note,
    dateType: effectiveType,
    date: effectiveType == TaskDateType.custom ? resolvedDate : null,
    remindAts: normalizeInstantSlots(
      remindAts ?? (remindAt == null ? const [] : [remindAt]),
    ),
    status: status,
    createdAt: createdAt ?? kBaseNow,
    updatedAt: updatedAt ?? kBaseNow,
    completedAt: completedAt,
  );
}

/// 造一个周期内任务模板。
CycleTaskTemplate makeCycleTemplate({
  String id = 'ctask_1',
  String title = '慢跑 3 公里',
  String note = '',
  int? remindMinuteOfDay,
  int order = 0,
  DateTime? updatedAt,
}) {
  return CycleTaskTemplate(
    id: id,
    title: title,
    note: note,
    remindMinuteOfDay: remindMinuteOfDay,
    order: order,
    updatedAt: updatedAt ?? kBaseNow,
  );
}

/// 造周期内的一天。
CycleDay makeCycleDay({
  int dayIndex = 1,
  bool isRestDay = false,
  List<CycleTaskTemplate>? templates,
}) {
  return CycleDay(
    dayIndex: dayIndex,
    isRestDay: isRestDay,
    templates: templates ?? const [],
  );
}

/// 造一个 N 天循环计划，默认 8 天、每天一个任务。
Cycle makeCycle({
  String id = 'cycle_1',
  String name = '8 天跑步训练',
  int periodDays = 8,
  DateTime? startDate,
  CycleEndType endType = CycleEndType.never,
  DateTime? endDate,
  int? endCount,
  bool completeCyclesOnly = false,
  CycleStatus status = CycleStatus.active,
  DateTime? endedAt,
  int? remindMinuteOfDay,
  List<int>? remindMinutesOfDay,
  List<CycleDay>? days,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return Cycle(
    id: id,
    name: name,
    periodDays: periodDays,
    startDate: startDate ?? kToday,
    endType: endType,
    endDate: endDate,
    endCount: endCount,
    completeCyclesOnly: completeCyclesOnly,
    status: status,
    endedAt: endedAt,
    remindMinutesOfDay: normalizeMinuteSlots(
      remindMinutesOfDay ??
          (remindMinuteOfDay == null ? const [] : [remindMinuteOfDay]),
    ),
    days: days ??
        List.unmodifiable([
          for (var i = 1; i <= periodDays; i++) CycleDay.empty(i),
        ]),
    createdAt: createdAt ?? kBaseNow,
    updatedAt: updatedAt ?? kBaseNow,
  );
}

/// 造一条任务实例记录。
Record makeRecord({
  String id = 'record_1',
  String taskId = 'task_1',
  String? cycleId,
  int? cycleDayIndex,
  DateTime? date,
  TaskStatus status = TaskStatus.pending,
  DateTime? completedAt,
  String? reason,
  DateTime? reasonUpdatedAt,
  DateTime? rescheduledFrom,
  String? titleOverride,
  DateTime? updatedAt,
}) {
  return Record(
    id: id,
    taskId: taskId,
    cycleId: cycleId,
    cycleDayIndex: cycleDayIndex,
    date: date ?? kToday,
    status: status,
    completedAt: completedAt,
    reason: reason,
    reasonUpdatedAt: reasonUpdatedAt,
    rescheduledFrom: rescheduledFrom,
    titleOverride: titleOverride,
    updatedAt: updatedAt ?? kBaseNow,
  );
}

/// 造一份设置。
AppSettings makeSettings({
  bool remindersEnabled = true,
  int? defaultRemindMinuteOfDay,
  List<int>? defaultRemindMinutesOfDay,
  bool cycleRemindersEnabled = true,
  bool lockEnabled = false,
  String? lockPinHash,
  bool biometricEnabled = false,
  int? themeSeed,
  DateTime? lastBackupAt,
}) {
  return AppSettings(
    remindersEnabled: remindersEnabled,
    defaultRemindMinutesOfDay: normalizeMinuteSlots(
      defaultRemindMinutesOfDay ??
          [defaultRemindMinuteOfDay ?? AppSettings.defaultRemindMinute],
    ),
    cycleRemindersEnabled: cycleRemindersEnabled,
    lockEnabled: lockEnabled,
    lockPinHash: lockPinHash,
    biometricEnabled: biometricEnabled,
    themeSeed: themeSeed,
    lastBackupAt: lastBackupAt,
  );
}

/// 造一份完整数据快照。
AppData makeAppData({
  List<Task>? tasks,
  List<Cycle>? cycles,
  List<Record>? records,
  AppSettings? settings,
}) {
  return AppData(
    tasks: tasks ?? [makeTask()],
    cycles: cycles ?? [makeCycle()],
    records: records ?? [makeRecord()],
    settings: settings ?? makeSettings(),
  );
}

/// 造一个备份信封。
AppBackup makeBackup({
  int version = AppBackup.currentVersion,
  DateTime? exportedAt,
  AppData? data,
}) {
  return AppBackup(
    version: version,
    exportedAt: exportedAt ?? kBaseNow,
    data: data ?? makeAppData(),
  );
}
