import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/models/task.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:loop_island/services/reminder_scheduler.dart';

import '../support/factories.dart';
import '../support/fake_notification_service.dart';

/// 任务 8.3 / 8.4 / 8.12：提醒调度。
void main() {
  // 固定「现在」：2026-09-12 10:00
  final now = kBaseNow;

  /// 造一份只有设置、没有循环计划的数据。
  AppData dataWith({
    List<Task> tasks = const [],
    List<Cycle> cycles = const [],
    AppSettings? settings,
  }) {
    return AppData(
      tasks: tasks,
      cycles: cycles,
      records: const [],
      settings: settings ?? makeSettings(),
    );
  }

  group('8.3 普通任务提醒', () {
    test('未完成 + 未来提醒 → 注册一条一次性通知', () {
      final task = makeTask(
        id: 'task_1',
        title: '写周报',
        remindAt: DateTime(2026, 9, 12, 18),
      );
      final reminders = buildReminders(
        data: dataWith(tasks: [task]),
        settings: makeSettings(),
        now: now,
      );

      expect(reminders, hasLength(1));
      final reminder = reminders.values.single;
      expect(reminder.id, taskReminderId('task_1', DateTime(2026, 9, 12, 18)));
      expect(reminder.title, '写周报');
      expect(reminder.body, ReminderStrings.taskBody);
      expect(reminder.at, DateTime(2026, 9, 12, 18));
      expect(reminder.isDaily, isFalse);

      final payload = ReminderPayload.parse(reminder.payload);
      expect(payload!.type, ReminderPayloadType.task);
      expect(payload.id, 'task_1');
    });

    test('已经过去的提醒时间不再注册', () {
      final task = makeTask(remindAt: DateTime(2026, 9, 12, 9));
      final reminders = buildReminders(
        data: dataWith(tasks: [task]),
        settings: makeSettings(),
        now: now,
      );
      expect(reminders, isEmpty);
    });

    test('没有提醒时间的任务不注册', () {
      final reminders = buildReminders(
        data: dataWith(tasks: [makeTask()]),
        settings: makeSettings(),
        now: now,
      );
      expect(reminders, isEmpty);
    });

    test('已完成 / 已跳过 / 未完成的任务都不再提醒', () {
      for (final status in const [
        TaskStatus.completed,
        TaskStatus.skipped,
        TaskStatus.missed,
      ]) {
        final reminders = buildReminders(
          data: dataWith(
            tasks: [
              makeTask(remindAt: DateTime(2026, 9, 12, 18), status: status),
            ],
          ),
          settings: makeSettings(),
          now: now,
        );
        expect(reminders, isEmpty, reason: '$status 的任务不该提醒');
      }
    });

    test('多条任务各自拿到稳定的独立 ID', () {
      final reminders = buildReminders(
        data: dataWith(
          tasks: [
            makeTask(id: 'a', remindAt: DateTime(2026, 9, 12, 18)),
            makeTask(id: 'b', remindAt: DateTime(2026, 9, 12, 19)),
          ],
        ),
        settings: makeSettings(),
        now: now,
      );
      expect(reminders.keys.toSet(), {
        taskReminderId('a', DateTime(2026, 9, 12, 18)),
        taskReminderId('b', DateTime(2026, 9, 12, 19)),
      });
    });
  });

  group('8.4 循环计划每日提醒', () {
    test('启用中的计划逐日展开，正文含「第 x/N 天」', () {
      final cycle = makeCycle(
        id: 'cycle_1',
        name: '8 天跑步训练',
        periodDays: 8,
        startDate: now,
        remindMinuteOfDay: 9 * 60,
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      // 今天 09:00 已经过去，所以从明天开始，共 30 天
      expect(reminders, hasLength(kCycleReminderHorizonDays));
      expect(
        reminders.values.every((r) => r.at!.isAfter(now)),
        isTrue,
        reason: '过去的时间点不该注册',
      );

      // 明天是周期第 2 天
      final tomorrow = addDays(now, 1);
      final tomorrowReminder =
          reminders[cycleReminderId('cycle_1', tomorrow, 9 * 60)];
      expect(tomorrowReminder, isNotNull);
      expect(tomorrowReminder!.title, '8 天跑步训练');
      expect(tomorrowReminder.body, ReminderStrings.cycleDayBody(2, 8));
      expect(tomorrowReminder.at, atMinuteOfDay(tomorrow, 9 * 60));

      // 第 8 天之后回到第 1 天
      final eighth = addDays(now, 8);
      expect(
        reminders[cycleReminderId('cycle_1', eighth, 9 * 60)]!.body,
        ReminderStrings.cycleDayBody(1, 8),
      );

      final payload = ReminderPayload.parse(tomorrowReminder.payload);
      expect(payload!.type, ReminderPayloadType.cycle);
      expect(payload.id, 'cycle_1');
      expect(payload.dayKey, dayKey(tomorrow));
    });

    test('提醒时刻还没到时今天也算一天', () {
      final cycle = makeCycle(
        startDate: now,
        remindMinuteOfDay: 20 * 60,
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      final todayReminder =
          reminders[cycleReminderId('cycle_1', now, 20 * 60)];
      expect(todayReminder, isNotNull);
      expect(todayReminder!.body, ReminderStrings.cycleDayBody(1, 8));
      expect(reminders, hasLength(kCycleReminderHorizonDays + 1));
    });

    test('结束日当天仍然提醒，结束日次日不再提醒', () {
      final cycle = makeCycle(
        startDate: now,
        remindMinuteOfDay: 9 * 60,
        endType: CycleEndType.untilDate,
        endDate: addDays(now, 2),
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      final dates = reminders.values.map((r) => dayKey(r.at!)).toSet();
      expect(dates, {dayKey(addDays(now, 1)), dayKey(addDays(now, 2))});
      expect(dates.contains(dayKey(addDays(now, 3))), isFalse);
    });

    test('已暂停 / 已结束 / 已到期的计划都不提醒', () {
      final cycles = [
        makeCycle(id: 'paused', status: CycleStatus.paused, remindMinuteOfDay: 540),
        makeCycle(
          id: 'ended',
          status: CycleStatus.ended,
          endedAt: addDays(now, -1),
          remindMinuteOfDay: 540,
        ),
        makeCycle(
          id: 'expired',
          startDate: addDays(now, -5),
          endType: CycleEndType.untilDate,
          endDate: addDays(now, -1),
          remindMinuteOfDay: 540,
        ),
      ];
      final reminders = buildReminders(
        data: dataWith(cycles: cycles),
        settings: makeSettings(),
        now: now,
      );
      expect(reminders, isEmpty);
    });

    test('计划里选了「不提醒」时不套用默认提醒时间', () {
      final cycle = makeCycle(remindMinuteOfDay: null);
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(defaultRemindMinuteOfDay: 20 * 60),
        now: now,
      );
      expect(reminders, isEmpty, reason: 'null 表示用户明确选了不提醒');
    });

    test('循环提醒开关关闭时不注册循环提醒', () {
      final reminders = buildReminders(
        data: dataWith(cycles: [makeCycle(remindMinuteOfDay: 540)]),
        settings: makeSettings(cycleRemindersEnabled: false),
        now: now,
      );
      expect(reminders, isEmpty);
    });

    test('计划很多时自动缩短窗口，避免超出系统的待发送通知上限', () {
      final cycles = [
        for (var i = 0; i < 5; i++)
          makeCycle(id: 'c$i', remindMinuteOfDay: 9 * 60),
      ];
      final reminders = buildReminders(
        data: dataWith(cycles: cycles),
        settings: makeSettings(),
        now: now,
      );
      final horizon = cycleReminderHorizon(5);
      expect(reminders, hasLength(5 * horizon));
      expect(reminders.length, lessThanOrEqualTo(kCycleReminderBudget));
    });

    test('时段越多窗口越短：2 个时段时仍不超预算', () {
      // 一个计划 + 每天 2 次提醒 → 每天 2 条，窗口必须比 1 个时段时更短
      final single = makeCycle(id: 'c1', remindMinuteOfDay: 9 * 60);
      final dual = makeCycle(
        id: 'c1',
        remindMinutesOfDay: [10 * 60 + 30, 15 * 60 + 30],
      );

      final singleReminders = buildReminders(
        data: dataWith(cycles: [single]),
        settings: makeSettings(),
        now: now,
      );
      final dualReminders = buildReminders(
        data: dataWith(cycles: [dual]),
        settings: makeSettings(),
        now: now,
      );

      expect(
        dualReminders.length,
        lessThanOrEqualTo(kCycleReminderBudget),
        reason: '多时段展开后总条数仍然要压在上限内',
      );
      expect(
        dualReminders.length,
        greaterThan(singleReminders.length),
        reason: '一天两次当然比一天一次条数多（窗口已相应缩短）',
      );
      expect(
        dualReminders.values.map((r) => r.at!.hour).toSet(),
        {10, 15},
        reason: '两个时段都要排到',
      );
    });

    test('未来的计划也会提醒，起始日之前不提醒', () {
      final cycle = makeCycle(
        startDate: addDays(now, 3),
        remindMinuteOfDay: 9 * 60,
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      final dates = reminders.values.map((r) => dayKey(r.at!)).toSet();
      expect(dates, isNotEmpty);
      expect(dates.every((d) => d.compareTo(dayKey(addDays(now, 3))) >= 0), isTrue);
    });

    test('计划级没设提醒、但任务模板带提醒时间 → 模板提醒照样注册', () {
      // 用户反馈：计划提醒正常、计划里的每日任务不提醒 ——
      // 根因是模板的 remindMinuteOfDay 从未被调度。计划级「不提醒」
      // 拦不住用户逐条显式设置的任务提醒。
      final cycle = makeCycle(
        id: 'cycle_1',
        name: '8 天训练',
        remindMinutesOfDay: const [],
        days: [
          makeCycleDay(
            dayIndex: 1,
            templates: [makeCycleTemplate(remindMinuteOfDay: 7 * 60 + 30)],
          ),
        ],
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      // 周期从今天（第 1 天）开始，明起是空白的第 2 天；
      // 第 1 天的模板下一次出现是 8 天后（第 9 天），07:30 在未来 → 注册。
      final expectedDay = addDays(now, 8);
      final matching = reminders.values.where(
        (r) => r.title == '慢跑 3 公里' && dayKey(r.at!) == dayKey(expectedDay),
      );
      expect(matching, hasLength(1), reason: '任务模板的提醒要逐日注册');
      expect(matching.single.at, atMinuteOfDay(expectedDay, 7 * 60 + 30));
      expect(matching.single.id, cycleTaskReminderId(
        'cycle_1',
        expectedDay,
        'ctask_1',
        7 * 60 + 30,
      ));
      final payload = ReminderPayload.parse(matching.single.payload);
      expect(payload!.type, ReminderPayloadType.cycle);
      expect(payload.id, 'cycle_1');
    });

    test('任务模板提醒：休息日与空白天不注册，正文含第 x/N 天', () {
      final cycle = makeCycle(
        id: 'cycle_1',
        remindMinutesOfDay: const [],
        days: [
          makeCycleDay(
            dayIndex: 1,
            templates: [makeCycleTemplate(remindMinuteOfDay: 8 * 60)],
          ),
          makeCycleDay(dayIndex: 2, isRestDay: true), // 休息日：清空了任务
          makeCycleDay(dayIndex: 3), // 空白天
        ],
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      for (final reminder in reminders.values) {
        final dayIndex = cycleDayIndexAt(
          cycle,
          DateTime(
            reminder.at!.year,
            reminder.at!.month,
            reminder.at!.day,
          ),
        );
        expect(dayIndex, isNotNull);
        expect(dayIndex, isNot(2), reason: '休息日不提醒');
        expect(dayIndex, isNot(3), reason: '空白天不提醒');
        expect(reminder.title, '慢跑 3 公里');
        expect(
          reminder.body,
          ReminderStrings.cycleDayBody(dayIndex!, cycle.periodDays),
        );
      }
      expect(reminders, isNotEmpty);
    });

    test('任务模板提醒计入每条预算：时段多时窗口相应缩短', () {
      // 每天最多 1 条计划时段 + 2 条模板提醒 = 3 条/天，
      // 窗口必须按 3 条/天反推，而不是只按计划时段的 1 条。
      final cycle = makeCycle(
        id: 'cycle_1',
        remindMinuteOfDay: 9 * 60,
        days: [
          makeCycleDay(
            dayIndex: 1,
            templates: [
              makeCycleTemplate(id: 'ctask_1', remindMinuteOfDay: 7 * 60),
              makeCycleTemplate(
                id: 'ctask_2',
                title: '拉伸',
                remindMinuteOfDay: 21 * 60,
              ),
            ],
          ),
        ],
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );

      // 每个窗口日最多 3 条（1 计划时段 + 2 模板）
      final perDay = <String, int>{};
      for (final reminder in reminders.values) {
        perDay[dayKey(reminder.at!)] =
            (perDay[dayKey(reminder.at!)] ?? 0) + 1;
      }
      expect(perDay.values.every((c) => c <= 3), isTrue);
      expect(reminders.length, lessThanOrEqualTo(kCycleReminderBudget));
    });

    test('已过去的模板提醒时刻不注册', () {
      final cycle = makeCycle(
        id: 'cycle_1',
        remindMinutesOfDay: const [],
        days: [
          makeCycleDay(
            dayIndex: 1,
            templates: [makeCycleTemplate(remindMinuteOfDay: 8 * 60)],
          ),
        ],
      );
      final reminders = buildReminders(
        data: dataWith(cycles: [cycle]),
        settings: makeSettings(),
        now: now,
      );
      // 今天是周期第 1 天，08:00 已过（now=10:00）→ 当天这条不注册；
      // 之后的周期轮次（第 9 天起）仍在窗口内且属于未来 → 会注册。
      expect(
        reminders.values
            .where((r) => dayKey(r.at!) == dayKey(now))
            .map((r) => r.title),
        isEmpty,
      );
      expect(reminders, isNotEmpty, reason: '下一轮的模板提醒仍然注册');
    });
  });

  group('8.3 / 8.4 同步与差分', () {
    test('冷启动先清空再全量重排', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final task = makeTask(remindAt: DateTime(2026, 9, 12, 18));

      await scheduler.sync(
        data: dataWith(tasks: [task]),
        settings: makeSettings(),
        now: now,
      );

      expect(
        service.cancelAllCount,
        0,
        reason: '冷启动不再全量撤销重建（重建期间失败会丢提醒）',
      );
      expect(service.pendingQueries, 1, reason: '改为查询系统实际状态做差分');
      expect(service.onceIds, [taskReminderId('task_1', DateTime(2026, 9, 12, 18))]);
      expect(service.liveIds, {taskReminderId('task_1', DateTime(2026, 9, 12, 18))});
    });

    test('修改提醒时间：取消旧时刻、排上新时刻，且不 cancelAll', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final settings = makeSettings();

      await scheduler.sync(
        data: dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))]),
        settings: settings,
        now: now,
      );
      await scheduler.sync(
        data: dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 20))]),
        settings: settings,
        now: now,
      );

      expect(service.cancelAllCount, 0, reason: '任何一次同步都不该 cancelAll');
      expect(service.onceCalls, hasLength(2));
      expect(
        service.cancelled,
        [taskReminderId('task_1', DateTime(2026, 9, 12, 18))],
        reason: 'ID 里带时刻，改时刻＝换一条通知，旧的必须取消',
      );
      expect(service.onceCalls.last.at, DateTime(2026, 9, 12, 20));
      expect(service.liveIds, hasLength(1));
    });

    test('一天两个时段：两条通知各自独立，改其中一个只影响那一条', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final settings = makeSettings();
      const morning = 10 * 60 + 30;
      const afternoon = 15 * 60 + 30;
      final day = DateTime(2026, 9, 12);

      await scheduler.sync(
        data: dataWith(
          tasks: [
            makeTask(
              remindAts: [
                atMinuteOfDay(day, morning),
                atMinuteOfDay(day, afternoon),
              ],
            ),
          ],
        ),
        settings: settings,
        now: now,
      );
      expect(service.onceCalls, hasLength(2));
      expect(
        service.onceCalls.map((c) => c.at).toSet(),
        {atMinuteOfDay(day, morning), atMinuteOfDay(day, afternoon)},
      );

      // 只把下午那次改到 17:00
      await scheduler.sync(
        data: dataWith(
          tasks: [
            makeTask(
              remindAts: [
                atMinuteOfDay(day, morning),
                atMinuteOfDay(day, 17 * 60),
              ],
            ),
          ],
        ),
        settings: settings,
        now: now,
      );

      expect(service.onceCalls, hasLength(3), reason: '只重排被改的那一条');
      expect(service.cancelled, [
        taskReminderId('task_1', atMinuteOfDay(day, afternoon)),
      ]);
      expect(
        service.liveIds,
        {
          taskReminderId('task_1', atMinuteOfDay(day, morning)),
          taskReminderId('task_1', atMinuteOfDay(day, 17 * 60)),
        },
      );
    });

    test('参数没变时不重复调度', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final data = dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))]);

      await scheduler.sync(data: data, settings: data.settings, now: now);
      await scheduler.sync(data: data, settings: data.settings, now: now);
      await scheduler.sync(data: data, settings: data.settings, now: now);

      expect(service.onceCalls, hasLength(1));
    });

    test('删除任务时取消对应的提醒', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final settings = makeSettings();

      await scheduler.sync(
        data: dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))]),
        settings: settings,
        now: now,
      );
      await scheduler.sync(data: dataWith(), settings: settings, now: now);

      expect(service.cancelled, [taskReminderId('task_1', DateTime(2026, 9, 12, 18))]);
      expect(service.liveIds, isEmpty);
    });

    test('时间往前走一天：昨天那次循环提醒被取消，窗口整体前移', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final cycle = makeCycle(startDate: now, remindMinuteOfDay: 540);
      final settings = makeSettings();

      await scheduler.sync(
        data: dataWith(cycles: [cycle]),
        settings: settings,
        now: now,
      );
      final firstBatch = service.onceIds.toSet();

      final tomorrow = addDays(now, 1);
      await scheduler.sync(
        data: dataWith(cycles: [cycle]),
        settings: settings,
        now: atMinuteOfDay(tomorrow, 10 * 60),
      );
      final newIds = service.onceIds.toSet().difference(firstBatch);

      // 窗口前移后，最早的那天（昨天 09:00 那条）不再需要
      expect(
        service.cancelled,
        contains(
          cycleReminderId('cycle_1', addDays(now, 1), 9 * 60),
        ),
      );
      expect(newIds, isNotEmpty, reason: '窗口前移后要补上新的一天');
    });

    test('暂停计划后取消它的全部提醒', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final settings = makeSettings();
      final active = makeCycle(id: 'c1', remindMinuteOfDay: 540);

      await scheduler.sync(
        data: dataWith(cycles: [active]),
        settings: settings,
        now: now,
      );
      final activeIds = service.onceIds.toSet();
      expect(activeIds, isNotEmpty);

      await scheduler.sync(
        data: dataWith(
          cycles: [
            makeCycle(
              id: 'c1',
              remindMinuteOfDay: 540,
              status: CycleStatus.paused,
            ),
          ],
        ),
        settings: settings,
        now: now,
      );

      expect(service.cancelled.toSet(), activeIds);
      expect(service.liveIds, isEmpty);
    });

    test('总开关关闭：cancelAll 被调用且清空内存里的调度结果', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);

      await scheduler.sync(
        data: dataWith(
          tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))],
          cycles: [makeCycle(remindMinuteOfDay: 540)],
        ),
        settings: makeSettings(),
        now: now,
      );
      expect(service.liveIds, isNotEmpty);

      await scheduler.sync(
        data: dataWith(
          tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))],
          cycles: [makeCycle(remindMinuteOfDay: 540)],
        ),
        settings: makeSettings(remindersEnabled: false),
        now: now,
      );

      expect(
        service.cancelAllCount,
        1,
        reason: '只有「关总开关」这一次需要 cancelAll（冷启动已改为差分）',
      );
      expect(service.liveIds, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    test('总开关一开始就是关闭的：冷启动也要清一次', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);

      await scheduler.sync(
        data: dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))]),
        settings: makeSettings(remindersEnabled: false),
        now: now,
      );

      expect(service.cancelAllCount, 1, reason: '上次运行注册的通知还躺在系统里');
      expect(service.onceCalls, isEmpty);
    });

    test('平台不支持时不做任何调度，也不抛异常', () async {
      final service = FakeNotificationService(supported: false);
      final scheduler = ReminderScheduler(service);

      await scheduler.sync(
        data: dataWith(tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))]),
        settings: makeSettings(),
        now: now,
      );

      expect(service.onceCalls, isEmpty);
      expect(service.cancelAllCount, 0);
      expect(scheduler.scheduled, isEmpty);    });

    test('关闭循环提醒后，普通任务提醒保持不变', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final data = dataWith(
        tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))],
        cycles: [makeCycle(remindMinuteOfDay: 540)],
      );

      await scheduler.sync(data: data, settings: makeSettings(), now: now);
      final taskId = taskReminderId('task_1', DateTime(2026, 9, 12, 18));
      expect(service.liveIds, contains(taskId));

      await scheduler.sync(
        data: data,
        settings: makeSettings(cycleRemindersEnabled: false),
        now: now,
      );

      expect(service.liveIds, {taskId});
      expect(service.cancelled, isNot(contains(taskId)));
    });
  });

  group('冷启动对齐系统状态（不再全量撤销重建）', () {
    test('系统里已有同一条提醒 → 不重排、不取消', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final task = makeTask(remindAt: DateTime(2026, 9, 12, 18));
      final data = dataWith(tasks: [task]);

      // 第一次同步把提醒排进系统
      await scheduler.sync(data: data, settings: data.settings, now: now);
      final scheduledCount = service.onceCalls.length;
      expect(scheduledCount, 1);

      // 模拟「重启应用」：新的调度器实例，但系统里的通知还在
      final restarted = ReminderScheduler(service);
      await restarted.sync(data: data, settings: data.settings, now: now);

      expect(
        service.onceCalls,
        hasLength(scheduledCount),
        reason: '系统里已有且文案一致的提醒不该被撤销重建',
      );
      expect(service.cancelAllCount, 0, reason: '绝不 cancelAll');
      expect(service.cancelled, isEmpty, reason: '没有多余残留要清');
      expect(service.liveIds, hasLength(1));
    });

    test('系统里有上次运行留下的残留（任务已删）→ 只取消那一条', () async {
      final service = FakeNotificationService();
      final staleTask = makeTask(id: 'gone', remindAt: DateTime(2026, 9, 12, 18));
      final first = ReminderScheduler(service);
      await first.sync(
        data: dataWith(tasks: [staleTask]),
        settings: makeSettings(),
        now: now,
      );
      final staleId = taskReminderId('gone', DateTime(2026, 9, 12, 18));
      expect(service.liveIds, {staleId});

      // 重启后任务已被删除：残留必须清掉，但走的是逐条 cancel
      final restarted = ReminderScheduler(service);
      await restarted.sync(data: dataWith(), settings: makeSettings(), now: now);

      expect(service.cancelled, [staleId]);
      expect(service.cancelAllCount, 0, reason: '用逐条 cancel 而不是全量清空');
      expect(service.liveIds, isEmpty);
    });

    test('查询系统状态失败 → 什么都不取消（宁可留残留也不误删）', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final task = makeTask(remindAt: DateTime(2026, 9, 12, 18));

      service.pendingQueryFails = true;
      await expectLater(
        scheduler.sync(
          data: dataWith(tasks: [task]),
          settings: makeSettings(),
          now: now,
        ),
        completes,
      );

      expect(service.cancelled, isEmpty);
      expect(service.cancelAllCount, 0);
      expect(
        service.onceCalls,
        hasLength(1),
        reason: '查询失败不影响正常调度',
      );
    });

    test('文案变了（同 ID）→ 重新排一次', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final at = DateTime(2026, 9, 12, 18);

      await scheduler.sync(
        data: dataWith(tasks: [makeTask(title: '旧标题', remindAt: at)]),
        settings: makeSettings(),
        now: now,
      );

      // 改标题：通知 ID 不变（ID 只含任务 id + 时刻），但文案变了
      final restarted = ReminderScheduler(service);
      await restarted.sync(
        data: dataWith(tasks: [makeTask(title: '新标题', remindAt: at)]),
        settings: makeSettings(),
        now: now,
      );

      expect(service.onceCalls, hasLength(2), reason: '文案不一致要重排');
      expect(service.onceCalls.last.title, '新标题');
    });

    test('invalidate() 后下次同步全量重排（精确闹钟授权后升级用）', () async {
      final service = FakeNotificationService();
      final scheduler = ReminderScheduler(service);
      final task = makeTask(remindAt: DateTime(2026, 9, 12, 18));
      final data = dataWith(tasks: [task]);

      await scheduler.sync(data: data, settings: data.settings, now: now);
      expect(service.onceCalls, hasLength(1));

      scheduler.invalidate();
      await scheduler.sync(data: data, settings: data.settings, now: now);

      expect(
        service.onceCalls,
        hasLength(2),
        reason: '作废基准后必须重新注册（否则授权精确闹钟后仍是非精确闹钟）',
      );
      expect(service.cancelAllCount, 0, reason: 'invalidate 也不走 cancelAll');
    });
  });
}
