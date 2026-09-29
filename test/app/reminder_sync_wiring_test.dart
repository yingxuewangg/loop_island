/// 回归测试：AppShell 的提醒同步接线。
///
/// 背景（用户反馈）：「只有第一次设置提醒会弹通知，之后新建的任务
/// 设了提醒都不弹」。调度器本身的差分逻辑在 `reminder_scheduler_test.dart`
/// 已覆盖；本文件验证的是**真实接线**——
/// AppShell 挂载 → 冷启动同步 → 运行中通过 `commit` 新建任务（与
/// 任务编辑页保存同一条路径）→ `ref.listen` 触发再次同步 →
/// 新任务的提醒真的被调度出去。
///
/// 用 [FakeNotificationService] 观察对服务层的调用序列。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:loop_island/services/reminder_scheduler.dart';
import '../support/factories.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';

void main() {
  final now = kBaseNow;
  final remindAt1 = DateTime(2026, 9, 12, 18);
  final remindAt2 = DateTime(2026, 9, 12, 19);

  testWidgets('运行中新建任务：新任务的提醒被追加调度，且不 cancelAll', (tester) async {
    final service = FakeNotificationService();
    final task1 = makeTask(
      id: 'task_1',
      title: '第一条',
      dateType: TaskDateType.custom,
      date: dateOnly(now),
      remindAt: remindAt1,
    );

    final result = await pumpLoopIslandApp(
      tester,
      data: AppData(tasks: [task1]),
      today: now,
      now: now,
      notificationService: service,
    );
    final container = result.container;

    // 冷启动同步：对齐系统状态（不再 cancelAll）+ 全量重排 task_1 的提醒。
    expect(service.cancelAllCount, 0, reason: '冷启动已改为差分，不做全量清空');
    expect(
      service.onceIds,
      [taskReminderId('task_1', remindAt1)],
    );

    // 与 TaskEditPage._save 相同的提交路径：新建第二条任务。
    final before = await container.read(appDataProvider.future);
    await container.read(appDataProvider.notifier).commit(
          addTask(
            before,
            title: '第二条',
            dateType: TaskDateType.custom,
            date: dateOnly(now),
            remindAt: remindAt2,
            now: now,
          ),
        );
    await tester.pumpAndSettle();

    // 新任务的提醒必须真的被调度出去 —— 这就是用户反馈缺失的那条。
    // （新建任务的 id 是随机 UUID，所以断言「时刻 + payload 指向」而不是具体 id。）
    final addedTask = (await container.read(appDataProvider.future))
        .tasks
        .firstWhere((t) => t.title == '第二条');
    final addedCalls = service.onceCalls
        .where((call) => call.at == remindAt2)
        .toList(growable: false);
    expect(addedCalls, hasLength(1), reason: '新任务的提醒时刻应当被调度一次');
    final payload = ReminderPayload.parse(addedCalls.single.payload);
    expect(payload!.type, ReminderPayloadType.task);
    expect(payload.id, addedTask.id);
    expect(service.cancelAllCount, 0, reason: '增量同步也不该 cancelAll');

    // 第一条任务的提醒不受影响。
    expect(
      service.liveIds,
      contains(taskReminderId('task_1', remindAt1)),
    );
  });

  testWidgets('连续新建多条任务：每一条都被调度', (tester) async {
    final service = FakeNotificationService();
    final today = dateOnly(now);

    final result = await pumpLoopIslandApp(
      tester,
      data: AppData.empty,
      today: now,
      now: now,
      notificationService: service,
    );
    final container = result.container;

    for (var i = 1; i <= 3; i++) {
      final before = await container.read(appDataProvider.future);
      await container.read(appDataProvider.notifier).commit(
            addTask(
              before,
              title: '任务$i',
              dateType: TaskDateType.custom,
              date: today,
              remindAt: DateTime(2026, 9, 12, 12 + i),
              now: now,
            ),
          );
      await tester.pumpAndSettle();
    }

    // 每新建一条任务，就多出一条对应的提醒（id 是随机 UUID，看时刻即可）。
    expect(
      service.onceCalls.map((call) => call.at).toSet(),
      {
        DateTime(2026, 9, 12, 13),
        DateTime(2026, 9, 12, 14),
        DateTime(2026, 9, 12, 15),
      },
      reason: '连续新建的每一条任务的提醒都要被调度',
    );
    expect(service.cancelAllCount, 0, reason: '冷启动改为差分后不再全量清空');
  });

  group('精确闹钟授权后的重排', () {
    testWidgets('从「未授权」翻转为「已授权」→ 全部提醒重新注册', (tester) async {
      final service = FakeNotificationService()..exactAlarmsEnabledResult = false;
      final task = makeTask(
        id: 'task_1',
        title: '写周报',
        dateType: TaskDateType.custom,
        date: dateOnly(now),
        remindAt: remindAt1,
      );

      await pumpLoopIslandApp(
        tester,
        data: AppData(tasks: [task]),
        today: now,
        now: now,
        notificationService: service,
      );

      final scheduledAfterBoot = service.onceCalls.length;
      expect(scheduledAfterBoot, 1);

      // 用户去系统设置里授权后回到应用
      service.exactAlarmsEnabledResult = true;
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        service.onceCalls.length,
        greaterThan(scheduledAfterBoot),
        reason: '授权后必须重排 —— 否则系统里仍是会被推迟的非精确闹钟',
      );
    });

    testWidgets('状态没变化时不做无谓重排', (tester) async {
      final service = FakeNotificationService()..exactAlarmsEnabledResult = false;
      final task = makeTask(
        id: 'task_1',
        title: '写周报',
        dateType: TaskDateType.custom,
        date: dateOnly(now),
        remindAt: remindAt1,
      );

      await pumpLoopIslandApp(
        tester,
        data: AppData(tasks: [task]),
        today: now,
        now: now,
        notificationService: service,
      );
      final scheduledAfterBoot = service.onceCalls.length;

      // 反复 resumed，但授权状态一直是 false
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(service.onceCalls, hasLength(scheduledAfterBoot));
    });
  });
}
