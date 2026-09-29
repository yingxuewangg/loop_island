/// 循环计划的命令层（普通任务命令层见 `task_commands.dart`）。
///
/// 与 `task_commands.dart` 一样是**纯函数**：`AppData → AppData`，
/// 时间由参数注入，落盘与广播交给 `AppRepository.commit`。
library;

import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/ids.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';
import 'package:loop_island/data/record_commands.dart';

/// 新建或更新一个循环计划。
///
/// - 新建：追加到列表，并补齐从今天起的实例（受 [horizonDays] 限制）。
/// - 更新：替换原计划，并**重算今天及以后的未来实例**；历史记录不变。
///
/// 调用方应先通过 `cycle.copyWith(...)` 把规则改好再传进来。
AppData upsertCycle(
  AppData data,
  Cycle cycle, {
  DateTime? now,
  DateTime? today,
  int horizonDays = 60,
}) {
  final timestamp = now ?? DateTime.now();
  final referenceToday = dateOnly(today ?? timestamp);
  final exists = data.cycleById(cycle.id) != null;

  final saved = cycle.copyWith(updatedAt: timestamp);
  final cycles = exists
      ? [
          for (final item in data.cycles)
            if (item.id == saved.id) saved else item,
        ]
      : [...data.cycles, saved];

  final next = data.copyWith(cycles: List.unmodifiable(cycles));
  return rebuildFutureInstances(
    next,
    saved.id,
    referenceToday,
    now: timestamp,
    today: referenceToday,
    horizonDays: horizonDays,
  );
}

/// 暂停计划。已结束的计划不受影响（无操作）。
AppData pauseCycle(AppData data, String cycleId, {DateTime? now}) {
  return _patchCycle(data, cycleId, (cycle) {
    if (cycle.status == CycleStatus.ended) {
      return cycle;
    }
    return cycle.copyWith(
      status: CycleStatus.paused,
      updatedAt: now ?? DateTime.now(),
    );
  });
}

/// 恢复计划。
///
/// **已过结束日期的计划不会被恢复**（PRD：结束不可继续）——
/// 这里静默无操作而不是抛异常，因为界面上的按钮本来就该是禁用的，
/// 万一被触发也不该让应用崩掉。用 [canResume] 判断是否可恢复。
AppData resumeCycle(AppData data, String cycleId, {DateTime? now}) {
  final timestamp = now ?? DateTime.now();
  final cycle = data.cycleById(cycleId);
  if (cycle == null || !canResume(cycle, timestamp)) {
    return data;
  }

  final resumed = cycle.copyWith(
    status: CycleStatus.active,
    updatedAt: timestamp,
  );
  final next = _replaceCycle(data, resumed);
  // 恢复后把今天及以后的实例补回来
  return rebuildFutureInstances(
    next,
    cycleId,
    dateOnly(timestamp),
    now: timestamp,
    today: dateOnly(timestamp),
  );
}

/// 删除计划，**并级联删除它的全部实例记录**。
AppData deleteCycle(AppData data, String cycleId) {
  if (data.cycleById(cycleId) == null) {
    return data;
  }
  return data.copyWith(
    cycles: List.unmodifiable(data.cycles.where((e) => e.id != cycleId)),
    records: List.unmodifiable(data.records.where((e) => e.cycleId != cycleId)),
  );
}

/// 复制成新计划（PRD：结束不可继续，可复制成新计划）。
///
/// - 新 id、名称加「（副本）」、`status=active`、`endedAt=null`
/// - **起始日重置为今天**，让副本从头开始跑
/// - 任务模板的 id 全部重新生成，避免与原计划共用主键造成排查困难
AppData duplicateCycle(
  AppData data,
  String cycleId, {
  DateTime? today,
  DateTime? now,
  String suffix = '（副本）',
  int horizonDays = 60,
}) {
  final source = data.cycleById(cycleId);
  if (source == null) {
    return data;
  }

  final timestamp = now ?? DateTime.now();
  final startDay = dateOnly(today ?? timestamp);

  final copy = Cycle(
    id: newCycleId(),
    name: '${source.name}$suffix',
    periodDays: source.periodDays,
    startDate: startDay,
    endType: source.endType,
    endDate: source.endDate,
    endCount: source.endCount,
    completeCyclesOnly: source.completeCyclesOnly,
    status: CycleStatus.active,
    remindMinutesOfDay: source.remindMinutesOfDay,
    days: List.unmodifiable([
      for (final day in source.days)
        CycleDay(
          dayIndex: day.dayIndex,
          isRestDay: day.isRestDay,
          templates: List.unmodifiable([
            for (final template in day.sortedTemplates)
              template.copyWith(id: newCycleTaskId(), updatedAt: timestamp),
          ]),
        ),
    ]),
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  return upsertCycle(
    data,
    copy,
    now: timestamp,
    today: startDay,
    horizonDays: horizonDays,
  );
}

/// 单独更新周期内某一天的定义（某天编辑页用）。
AppData updateCycleDay(
  AppData data,
  String cycleId,
  CycleDay day, {
  DateTime? now,
}) {
  final cycle = data.cycleById(cycleId);
  if (cycle == null) {
    return data;
  }

  final timestamp = now ?? DateTime.now();
  final updated = cycle.withDay(day).copyWith(updatedAt: timestamp);
  var next = _replaceCycle(data, updated);

  // 今天及以后该天的待办实例要跟着模板走；已了结的记录保持原样
  next = rebuildFutureInstances(
    next,
    cycleId,
    dateOnly(timestamp),
    now: timestamp,
    today: dateOnly(timestamp),
  );
  return next;
}

AppData _replaceCycle(AppData data, Cycle cycle) {
  return data.copyWith(
    cycles: List.unmodifiable([
      for (final item in data.cycles)
        if (item.id == cycle.id) cycle else item,
    ]),
  );
}

/// 对单个计划做字段级修改的通用入口。
AppData _patchCycle(
  AppData data,
  String cycleId,
  Cycle Function(Cycle cycle) patch,
) {
  final cycle = data.cycleById(cycleId);
  if (cycle == null) {
    return data;
  }
  return _replaceCycle(data, patch(cycle));
}

// ---------------------------------------------------------------- 修改作用域

/// 修改**某一天的任务实例**，作用域由 [scope] 决定（PRD：仅本次 / 以后所有）。
///
/// - [EditScope.once]：只改这一天的实例（改名、改状态、改原因），
///   **不碰周期模板**。实例若不存在会先补建，`rescheduledFrom` 留空
///   （这里不是顺延，只是单次调整）。
/// - [EditScope.fromNowAll]：改周期模板里对应那一天的**同名任务模板**，
///   并重算今天起的未来实例；**历史记录一律不动**。
///
/// 返回新的 [AppData]；找不到计划 / 记录时原样返回。
AppData editCycleInstance(
  AppData data, {
  required String cycleId,
  required String templateId,
  required DateTime date,
  required EditScope scope,
  String? title,
  TaskStatus? status,
  String? reason,
  DateTime? now,
}) {
  final cycle = data.cycleById(cycleId);
  if (cycle == null) {
    return data;
  }
  final timestamp = now ?? DateTime.now();
  final day = dateOnly(date);

  switch (scope) {
    case EditScope.once:
      return _editInstanceOnly(
        data,
        cycle: cycle,
        templateId: templateId,
        day: day,
        title: title,
        status: status,
        reason: reason,
        now: timestamp,
      );

    case EditScope.fromNowAll:
      return _editTemplateFromNow(
        data,
        cycle: cycle,
        templateId: templateId,
        title: title,
        now: timestamp,
      );
  }
}

AppData _editInstanceOnly(
  AppData data, {
  required Cycle cycle,
  required String templateId,
  required DateTime day,
  String? title,
  TaskStatus? status,
  String? reason,
  required DateTime now,
}) {
  final dayIndex = cycleDayIndexAt(cycle, day);
  if (dayIndex == null) {
    return data;
  }

  // 先确保实例存在再改。走 ensureEntryRecord 而不是自己写一遍补建逻辑：
  // 早先的补建分支**忘了应用 title**，导致「在没物化过的那天改名」静默失效。
  final ensured = ensureEntryRecord(
    data,
    taskId: templateId,
    date: day,
    cycleId: cycle.id,
    cycleDayIndex: dayIndex,
  );

  var updated = ensured.record;
  if (status != null) {
    updated = updated.withStatus(status, at: now);
  }
  if (reason != null) {
    updated = updated.withReason(reason, at: now);
  }
  // 「仅本次」改标题写进实例自己的 titleOverride，**不动模板** ——
  // 这正是 PRD「修改循环任务时默认只改今天」的落地方式。
  if (title != null) {
    updated = updated.withTitleOverride(title);
  }

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

AppData _editTemplateFromNow(
  AppData data, {
  required Cycle cycle,
  required String templateId,
  String? title,
  required DateTime now,
}) {
  if (title == null) {
    return data;
  }

  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    return data;
  }

  var changed = false;
  final days = <CycleDay>[];
  for (final day in cycle.days) {
    final templates = [
      for (final template in day.templates)
        if (template.id == templateId)
          () {
            changed = true;
            return template.copyWith(title: trimmed, updatedAt: now);
          }()
        else
          template,
    ];
    days.add(day.copyWith(templates: List.unmodifiable(templates)));
  }

  if (!changed) {
    return data;
  }

  final updatedCycle = cycle
      .copyWith(days: List.unmodifiable(days))
      .copyWith(updatedAt: now);
  final next = _replaceCycle(data, updatedCycle);

  // 重算今天起的未来实例；历史记录不变
  return rebuildFutureInstances(
    next,
    cycle.id,
    dateOnly(now),
    now: now,
    today: dateOnly(now),
  );
}

/// 为 [date] 当天物化循环任务实例（PRD：「任务实例」）。
///
/// - **幂等**：同一 (plan, template, 日期) 已有记录时跳过，
///   重复调用不会产生重复任务；无新增时原样返回入参（不触发写盘）。
/// - 休息日不生成；结束日当天仍生成、次日不生成（由引擎判定）。
/// - 只生成 `pending` 状态的新记录，**绝不覆盖已有记录的状态或原因** ——
///   今天的任务勾完之后再打开今日页，不能把完成状态冲掉。
///
/// [today] 用于判定暂停/结束，便于在测试里固定时间。
AppData materializeDay(
  AppData data,
  DateTime date, {
  DateTime? now,
  DateTime? today,
}) {
  final timestamp = now ?? DateTime.now();
  final day = dateOnly(date);
  final instances = instancesForDay(data, day, today: today ?? timestamp);
  if (instances.isEmpty) {
    return data;
  }

  final additions = <Record>[];
  for (final instance in instances) {
    final existing = data.findInstance(
      taskId: instance.template.id,
      day: day,
      cycleId: instance.cycleId,
    );
    if (existing != null) {
      continue;
    }
    additions.add(
      Record.create(
        taskId: instance.template.id,
        date: day,
        cycleId: instance.cycleId,
        cycleDayIndex: instance.cycleDayIndex,
        status: TaskStatus.pending,
      ),
    );
  }

  if (additions.isEmpty) {
    return data;
  }
  return data.copyWith(
    records: List.unmodifiable([...data.records, ...additions]),
  );
}

/// 把已经到期但库里仍是 `active` 的计划落库为 `ended`（PRD：自动归档）。
///
/// 返回 `(新数据, 本次归档的计划列表)`；没有需要归档的则原样返回。
/// `endedAt` 写「今天零点」而不是「现在」——
/// 结束是**按天**发生的事实，写成当下时刻会让「结束日当天仍执行」的判定
/// 依赖用户什么时候打开应用。
({AppData data, List<Cycle> archived}) archiveFinishedCycles(
  AppData data,
  DateTime today, {
  DateTime? now,
}) {
  final day = dateOnly(today);
  final archived = <Cycle>[];

  final cycles = [
    for (final cycle in data.cycles)
      if (shouldAutoArchive(cycle, day))
        () {
          final ended = cycle.copyWith(
            status: CycleStatus.ended,
            endedAt: day,
            updatedAt: now ?? DateTime.now(),
          );
          archived.add(ended);
          return ended;
        }()
      else
        cycle,
  ];

  if (archived.isEmpty) {
    return (data: data, archived: const []);
  }
  return (
    data: data.copyWith(cycles: List.unmodifiable(cycles)),
    archived: List.unmodifiable(archived),
  );
}

/// 给某个计划补齐 [from]..[to] 区间的实例（含两端）。
///
/// 结束日期被改长时补生成、被改短时由 [pruneFutureInstances] 负责删除。
AppData materializeRange(
  AppData data,
  String cycleId,
  DateTime from,
  DateTime to, {
  DateTime? now,
  DateTime? today,
}) {
  var next = data;
  var cursor = dateOnly(from);
  final last = dateOnly(to);
  if (isAfterDay(cursor, last)) {
    return data;
  }

  while (!isAfterDay(cursor, last)) {
    next = materializeDay(next, cursor, now: now, today: today);
    cursor = addDays(cursor, 1);
  }
  return next;
}

/// 删除某个计划在 [from] 之后（含当天）**尚未了结、且未被单独定制**的实例。
///
/// 保留三类记录：
/// - 今天之前的（历史是既成事实）
/// - 已了结的（完成 / 未完成 / 跳过，或写了原因）
/// - **带实例级标题覆盖的**（用户明确改过这一天的标题，不能因为改了模板就悄悄丢掉）
///
/// [includePast] 为真时连过去一起清理，仅用于「删除计划」这类整段清理。
AppData pruneFutureInstances(
  AppData data,
  String cycleId,
  DateTime from, {
  bool includePast = false,
}) {
  final boundary = dateOnly(from);
  final removed = <String>[];

  for (final record in data.records) {
    if (record.cycleId != cycleId) {
      continue;
    }
    if (includePast) {
      removed.add(record.id);
      continue;
    }
    if (isBeforeDay(record.date, boundary)) {
      continue;
    }
    if (record.isPending && record.titleOverride == null) {
      removed.add(record.id);
    }
  }

  if (removed.isEmpty) {
    return data;
  }
  return data.copyWith(
    records: List.unmodifiable(
      data.records.where((e) => !removed.contains(e.id)),
    ),
  );
}

/// 重建某个计划的未来实例（PRD：修改结束日期后未来实例重新生成）。
///
/// 步骤：先删掉未来的 `pending` 实例，再按**当前库里**的规则补齐。
/// 已经了结的记录（完成/未完成/跳过，或写了原因）保持不变。
///
/// 注意参数是 [cycleId] 而不是 `Cycle` 对象：调用方应先把改好的计划写回
/// `data.cycles`，再调这里重建。传对象容易出现「引擎按新规则算、库里还是旧规则」
/// 的错配（这个坑我在写测试时踩过一次）。
///
/// [horizonDays] 限制一次补多少天，默认 60 天。
/// **不按结束日期一次性铺满**：一个「永远不结束」或「一年后结束」的计划
/// 若在这里全量物化，会凭空生成成百上千条记录；
/// 更远的日期交给今日页按天惰性物化（见 [materializeDay]）。
AppData rebuildFutureInstances(
  AppData data,
  String cycleId,
  DateTime from, {
  DateTime? now,
  DateTime? today,
  int horizonDays = 60,
}) {
  final cycle = data.cycleById(cycleId);
  if (cycle == null) {
    return data;
  }

  final start = dateOnly(from);
  final referenceToday = today ?? now ?? DateTime.now();

  var next = pruneFutureInstances(data, cycleId, start);

  final end = resolveEndDate(cycle);
  if (end != null && isBeforeDay(end, start)) {
    return next; // 结束日已经早于重建起点，不再补任何实例
  }

  final horizonEnd = addDays(start, horizonDays - 1);
  final last = end == null
      ? horizonEnd
      : (isBeforeDay(end, horizonEnd) ? end : horizonEnd);

  next = materializeRange(next, cycleId, start, last,
      now: now, today: referenceToday);
  return next;
}
