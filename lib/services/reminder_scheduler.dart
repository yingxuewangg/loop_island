/// 提醒调度（任务 8.3 / 8.4）。
///
/// 职责边界：
/// - [buildReminders] 是**纯函数**：给定数据快照 + 设置 + 「现在」，
///   算出「此刻应当存在哪些提醒」。不发通知、不读时钟、不碰磁盘。
/// - [ReminderScheduler] 只做一件事：把期望集合和上次的调度结果做差分，
///   补上新增的、取消多余的。所有平台调用都走 [NotificationService] 抽象。
///
/// ## 为什么循环计划用的是「逐日一次性通知」而不是「每日重复通知」
///
/// 8.4 的验收要求通知正文包含「今天是第 x/N 天」，且**结束日次日不再提醒**。
/// 平台的「每日重复」通知（`matchDateTimeComponents: DateTimeComponents.time`）
/// 只保存一条固定文案与一个时刻，逐日变化的正文表达不了，也没法在某个
/// 日期之后自动停掉。所以这里按天展开成一次性通知，滚动维护一个窗口：
///
/// - 窗口长度 [kCycleReminderHorizonDays] 天；
/// - 同时运行的计划分走 [kCycleReminderBudget] 条预算（iOS 只允许 64 条
///   待发送通知，必须留余量给普通任务提醒），计划多了窗口自动缩短；
/// - 每次应用启动、以及任何数据变化（每日维护、勾选、编辑）都会重新
///   同步一次，窗口因此始终是「从今天起的 N 天」。
///
/// **已知限制**：连续超过窗口天数不打开应用，循环提醒会停。这与「每日维护
/// 也需要打开应用才会物化今天的实例」是同一个前提，不是本模块独有的退化。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:meta/meta.dart';

/// 循环提醒最多提前注册多少天。
const int kCycleReminderHorizonDays = 30;

/// 循环提醒能占用的通知条数上限（iOS 待发送通知上限 64，留出余量）。
///
/// 注意：**这是「天 × 时段」展开后的总条数上限**，不是天数上限。
/// 一个计划设了 3 个时段，能铺的天数就相应变少（见 [cycleReminderHorizon]）。
const int kCycleReminderBudget = 50;

/// 在给定「每天要发多少条循环提醒」的前提下，滚动窗口最多能铺几天。
///
/// 抽成纯函数是为了让「时段变多 → 窗口变短」这条规则可以被单独断言：
/// 它是最容易写错、也最容易在加时段之后悄悄越界的地方。
int cycleReminderHorizon(int notificationsPerDay) {
  if (notificationsPerDay <= 0) {
    return kCycleReminderHorizonDays;
  }
  // 窗口含今天，所以可用天数是 budget / perDay 向下取整后减 1
  final maxDays = kCycleReminderBudget ~/ notificationsPerDay - 1;
  return maxDays.clamp(0, kCycleReminderHorizonDays);
}

/// 普通任务某一条提醒的通知 ID。
///
/// ID 里带上**具体时刻**，因为一个任务可以有多个时段（一天提醒 N 次）；
/// 时刻没变时 ID 就不变，改了时刻等于换一条通知（先 cancel 旧的再排新的）。
/// 把 ID 格式做成公开函数，是为了让调度与测试共用同一份定义 ——
/// 测试里手写字符串拼格式，改格式时必然漏改一处。
int taskReminderId(String taskId, DateTime at) =>
    notificationIdFor('task:$taskId:${at.millisecondsSinceEpoch}');

/// 循环计划某天某个时段的提醒 ID。
int cycleReminderId(String cycleId, DateTime date, int minuteOfDay) =>
    notificationIdFor('cycle:$cycleId:${dayKey(date)}:$minuteOfDay');

/// 循环计划某天某条**任务模板**的提醒 ID。
///
/// 与计划级时段（[cycleReminderId]）分属不同命名空间：同一天里
/// 「计划 09:00 提醒」和「当天某任务 09:00 提醒」是两条独立通知。
///
/// ID 里带上 [minuteOfDay]：改了任务的提醒时刻就换一条通知。否则一旦
/// 「改时刻后那次重排失败」，重启后会因为 ID 未变而被判定为「系统里已有」
/// 从而跳过重排，系统里就留着旧时刻的提醒。
int cycleTaskReminderId(
  String cycleId,
  DateTime date,
  String templateId,
  int minuteOfDay,
) =>
    notificationIdFor(
      'cycle-task:$cycleId:${dayKey(date)}:$templateId:$minuteOfDay',
    );

/// 一条待注册的提醒。
///
/// 做成值对象是为了让差分可以简单地用 `==` 判断「参数有没有变」——
/// 没变就不重新调度，避免每次数据变化都把全部通知删了重建。
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    this.at,
    this.minuteOfDay,
    this.payload,
  });

  /// 通知 ID（见 [notificationIdFor]）。
  final int id;

  final String title;
  final String body;

  /// 一次性提醒的时刻；每日重复提醒为 null。
  final DateTime? at;

  /// 每日重复提醒的「一天内分钟数」；一次性提醒为 null。
  final int? minuteOfDay;

  final String? payload;

  /// 是否是每日重复提醒。
  bool get isDaily => minuteOfDay != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledReminder &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.at == at &&
          other.minuteOfDay == minuteOfDay &&
          other.payload == payload;

  @override
  int get hashCode => Object.hash(id, title, body, at, minuteOfDay, payload);

  @override
  String toString() => 'ScheduledReminder($id, $title, '
      '${minuteOfDay == null ? at : '每日 $minuteOfDay 分'})';
}

/// 算出「此刻应当存在哪些提醒」，以通知 ID 为键。
///
/// 规则：
/// - 总开关关闭 → 空集合（调用方随后会 `cancelAll`）。
/// - 普通任务：未完成、有 `remindAt`、且时间点**还没过去**。
/// - 循环计划：启用中（未暂停 / 未结束 / 未到期）、在计划里设了提醒时刻、
///   且落在窗口内的每一天各一条。
Map<int, ScheduledReminder> buildReminders({
  required AppData data,
  required AppSettings settings,
  required DateTime now,
}) {
  final result = <int, ScheduledReminder>{};
  if (!settings.remindersEnabled) {
    return result;
  }

  for (final task in data.tasks) {
    // 「一天提醒 N 次」：每个时段一条通知，各自一个稳定 ID。
    for (final remindAt in task.remindAts) {
      // 已完成 / 已跳过 / 已判定未完成的任务不再提醒；过去的时间点也不再注册
      // （系统对过去时刻的一次性通知本来就只会立刻弹出，属于噪音）。
      if (task.status != TaskStatus.pending || !remindAt.isAfter(now)) {
        continue;
      }
      final id = taskReminderId(task.id, remindAt);
      result[id] = ScheduledReminder(
        id: id,
        title: task.title,
        body: ReminderStrings.taskBody,
        at: remindAt,
        payload: reminderPayload(
          type: ReminderPayloadType.task,
          id: task.id,
          at: remindAt,
        ),
      );
    }
  }

  if (settings.cycleRemindersEnabled) {
    _addCycleReminders(result, data: data, now: now);
  }

  return result;
}

void _addCycleReminders(
  Map<int, ScheduledReminder> result, {
  required AppData data,
  required DateTime now,
}) {
  final running = <Cycle>[];
  var notificationsPerDay = 0;
  for (final cycle in data.cycles) {
    // 空列表表示用户在计划里显式选了「不提醒」，此时**不能**套用设置里的
    // 默认提醒时段 —— 那会违背用户意图。但**任务模板自带**的提醒时间
    // 是用户逐条显式设置的，计划级「不提醒」拦不住它。
    final hasTemplateReminders = cycleHasTemplateReminders(cycle);
    if (cycle.remindMinutesOfDay.isEmpty && !hasTemplateReminders) {
      continue;
    }
    if (effectiveStatus(cycle, today: now) != CycleStatus.active) {
      continue;
    }
    running.add(cycle);
    // 窗口按「每天要发多少条」反推：任务模板的提醒逐日展开后同样占预算，
    // 这里取该计划在周期内任一天的最大条数（时段 + 当天带提醒的模板数）。
    var maxTemplateReminders = 0;
    for (final day in cycle.days) {
      if (day.isRestDay) {
        continue;
      }
      var count = 0;
      for (final template in day.templates) {
        if (template.remindMinuteOfDay != null) {
          count++;
        }
      }
      if (count > maxTemplateReminders) {
        maxTemplateReminders = count;
      }
    }
    notificationsPerDay +=
        cycle.remindMinutesOfDay.length + maxTemplateReminders;
  }
  if (running.isEmpty) {
    return;
  }

  // 窗口按「每天要发多少条」反推：时段越多，能铺的天数越少，
  // 这样总条数永远压在上限内，不会在多设几个时段后突然越界。
  final horizon = cycleReminderHorizon(notificationsPerDay);

  for (final cycle in running) {
    for (final minute in cycle.remindMinutesOfDay) {
      for (var offset = 0; offset <= horizon; offset++) {
        final date = addDays(now, offset);
        // 闭区间：结束日当天仍然提醒；结束日次日不再提醒。
        // 暂停 / 已结束的计划在这里也会被排除。
        if (!isDateWithinCycle(cycle, date, today: now)) {
          continue;
        }
        final at = atMinuteOfDay(date, minute);
        if (!at.isAfter(now)) {
          continue;
        }
        final dayIndex = cycleDayIndexAt(cycle, date) ?? 1;
        final id = cycleReminderId(cycle.id, date, minute);
        result[id] = ScheduledReminder(
          id: id,
          title: cycle.name,
          body: ReminderStrings.cycleDayBody(
            dayIndex,
            cycle.periodDays,
            slotIndex: cycle.remindMinutesOfDay.indexOf(minute) + 1,
            slotCount: cycle.remindMinutesOfDay.length,
          ),
          at: at,
          payload: reminderPayload(
            type: ReminderPayloadType.cycle,
            id: cycle.id,
            dayKey: dayKey(date),
            at: at,
          ),
        );
      }
    }

    // ---- 任务模板自带提醒：逐日展开，与计划级时段互相独立 ----
    // （此前只有计划级时段被注册，任务上设的提醒时间是摆设 —— 用户反馈
    // 「计划能提醒、计划里的任务不提醒」就是这个缺口。）
    for (var offset = 0; offset <= horizon; offset++) {
      final date = addDays(now, offset);
      if (!isDateWithinCycle(cycle, date, today: now)) {
        continue;
      }
      final dayIndex = cycleDayIndexAt(cycle, date);
      if (dayIndex == null) {
        continue;
      }
      final cycleDay = cycle.dayAt(dayIndex);
      if (cycleDay.isRestDay || cycleDay.isEmpty) {
        continue;
      }
      for (final template in cycleDay.sortedTemplates) {
        final minute = template.remindMinuteOfDay;
        if (minute == null) {
          continue;
        }
        final at = atMinuteOfDay(date, minute);
        if (!at.isAfter(now)) {
          continue;
        }
        final id = cycleTaskReminderId(cycle.id, date, template.id, minute);
        result[id] = ScheduledReminder(
          id: id,
          title: template.title,
          body: ReminderStrings.cycleDayBody(dayIndex, cycle.periodDays),
          at: at,
          payload: reminderPayload(
            type: ReminderPayloadType.cycle,
            id: cycle.id,
            dayKey: dayKey(date),
            at: at,
          ),
        );
      }
    }
  }
}

/// 计划里是否存在**任何**带提醒时间的任务模板（任意一天）。
bool cycleHasTemplateReminders(Cycle cycle) {
  for (final day in cycle.days) {
    for (final template in day.templates) {
      if (template.remindMinuteOfDay != null) {
        return true;
      }
    }
  }
  return false;
}

/// 把期望的提醒集合落到平台上。
///
/// 差分策略：
/// - 进程内的第一次同步（冷启动）**不再 `cancelAll` 全量重建**，而是拿
///   系统实际的待发送列表做基准：只取消「系统里有、这次不需要」的残留，
///   并把「系统里已有且文案一致」的记入基准、跳过重排。
///
///   为什么不再全量重建：逐条重排最多 50 条通知，这段窗口里应用被杀、
///   或某条重排失败，那条提醒就彻底丢了 —— 这是「偶尔收不到提醒」的
///   直接来源。而重建本身也没有必要：通知 ID 编码了提醒时刻
///   （`task:...:<毫秒>` / `cycle:...:<日期>:<分钟>`），ID 相同即代表
///   时刻相同，改了时间必然换 ID。
/// - 之后的每次同步只取消「这次不需要的」，并重新调度「新增或参数变了的」，
///   编辑一条任务不会把其它提醒删了重建。
class ReminderScheduler {
  ReminderScheduler(this._service);

  final NotificationService _service;

  /// 已注册提醒的基准（可变：冷启动对齐系统状态时逐条写入）。
  Map<int, ScheduledReminder> _scheduled = <int, ScheduledReminder>{};
  bool _didInitialSync = false;

  /// 最近一次同步后的提醒集合（供测试与调试查看）。
  Map<int, ScheduledReminder> get scheduled => _scheduled;

  /// 作废内存基准：下一次 [sync] 会把全部提醒重新注册。
  ///
  /// 用于「精确闹钟权限刚被授予」——系统里已排的是**非精确**闹钟，
  /// 不重排的话授权等于白授（非精确闹钟仍会被系统合并推迟）。
  void invalidate() {
    _scheduled = <int, ScheduledReminder>{};
    // 保持 true：下次走增量分支，避免又去做一次冷启动的系统状态查询。
    _didInitialSync = true;
  }

  /// 同步一次。**不抛异常**：提醒失败不该影响应用的其它部分。
  Future<void> sync({
    required AppData data,
    required AppSettings settings,
    required DateTime now,
  }) async {
    if (!_service.isSupported) {
      _scheduled = <int, ScheduledReminder>{};
      return;
    }

    // 总开关关闭：无条件清空。冷启动时 `_scheduled` 是空的，
    // 但仍然必须清 —— 上一次运行注册的通知还躺在系统里。
    if (!settings.remindersEnabled) {
      await _service.cancelAll();
      _scheduled = <int, ScheduledReminder>{};
      _didInitialSync = true;
      return;
    }

    final desired = buildReminders(data: data, settings: settings, now: now);

    if (!_didInitialSync) {
      await _adoptSystemState(desired);
      _didInitialSync = true;
    } else {
      for (final id in _scheduled.keys) {
        if (!desired.containsKey(id)) {
          await _service.cancel(id);
        }
      }
    }

    for (final reminder in desired.values) {
      if (_scheduled[reminder.id] == reminder) {
        continue;
      }
      await _schedule(reminder);
    }

    _scheduled = desired;
  }

  /// 冷启动：以系统实际的待发送列表为基准，对齐内存里的 [scheduled]。
  ///
  /// - 系统里有、但这次不需要的 → 取消（上次运行留下的残留，可能对应
  ///   已删除的任务；这类残留靠内存里的旧集合清不掉）。
  /// - 系统里有、这次也需要、且标题与正文一致的 → 记入基准，**不重排**。
  ///   这是本方法的核心价值：避免每次打开应用都把全部闹钟撤销重建。
  /// - 剩下的（系统里没有、或文案变了）留给调用方的调度循环重排。
  ///
  /// 查询失败时（返回空列表）**什么都不取消** —— 宁可留着残留（点开只会
  /// 落到今日页），也绝不冒「把好提醒误删」的风险。
  Future<void> _adoptSystemState(Map<int, ScheduledReminder> desired) async {
    final List<PendingNotificationSummary> pending;
    try {
      pending = await _service.pendingNotifications();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) {
      return;
    }

    final pendingById = <int, PendingNotificationSummary>{
      for (final item in pending) item.id: item,
    };

    for (final id in pendingById.keys) {
      if (!desired.containsKey(id)) {
        await _service.cancel(id);
      }
    }

    for (final entry in desired.entries) {
      final existing = pendingById[entry.key];
      if (existing == null) {
        continue;
      }
      // 文案一致 → 系统里这条就是我们要的，不必重排。
      if (existing.title == entry.value.title &&
          existing.body == entry.value.body) {
        _scheduled[entry.key] = entry.value;
      }
    }
  }

  Future<void> _schedule(ScheduledReminder reminder) {
    final minute = reminder.minuteOfDay;
    if (minute != null) {
      return _service.scheduleDaily(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        minuteOfDay: minute,
        payload: reminder.payload,
      );
    }
    final at = reminder.at;
    if (at == null) {
      return Future.value();
    }
    return _service.scheduleOnce(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      at: at,
      payload: reminder.payload,
    );
  }
}

/// 提醒调度器；全应用只有一个实例，`AppShell` 是唯一的调用方。
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(ref.watch(notificationServiceProvider)),
);
