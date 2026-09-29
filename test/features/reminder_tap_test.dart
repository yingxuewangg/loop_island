import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/cycle_detail_page.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/services/notification_service.dart';

import '../support/factories.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';
import 'package:loop_island/app/widgets/island_bottom_bar.dart';

/// 任务 8.6：点通知跳转（热启动 + 冷启动）。
///
/// 现行行为：**点通知一律回到今日页**。提醒只是「该做这件事了」的提示，
/// 不代表用户已经完成 —— 直接跳进任务编辑页会逼用户当场处理状态，
/// 而那是用户自己的判断。
void main() {
  final today = DateTime(2026, 9, 12);
  final now = DateTime(2026, 9, 12, 10);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 一份含一个普通任务与一个循环计划的数据。
  AppData dataWithTargets() {
    return AppData(
      tasks: [makeTask(id: 'task_1', title: '写周报')],
      cycles: [makeCycle(id: 'cycle_1', name: '8 天跑步训练')],
    );
  }

  /// 挂载应用并等所有首帧回调（维护 / 提醒同步 / 通知注册）跑完。
  Future<FakeNotificationService> pumpApp(
    WidgetTester tester, {
    AppData? data,
    String? launchPayload,
  }) async {
    final service = FakeNotificationService(launchPayload: launchPayload);
    await pumpLoopIslandApp(
      tester,
      data: data ?? dataWithTargets(),
      today: today,
      now: now,
      notificationService: service,
    );
    await tester.pumpAndSettle();
    return service;
  }

  /// 当前选中的 Tab 下标。
  ///
  /// 注意 `skipOffstage: false`：一旦有页面压在主壳之上，
  /// `AppShell` 就变成 offstage，默认 finder 会直接找不到它。
  int currentTab(WidgetTester tester) => tester
      .widget<IslandBottomBar>(find.byType(IslandBottomBar, skipOffstage: false))
      .currentIndex;

  group('8.6 热启动：应用运行中点通知', () {
    testWidgets('点任务提醒 → 今日页（不直接进编辑页）', (tester) async {
      useLargeSurface(tester);
      final service = await pumpApp(tester);

      service.tap(
        reminderPayload(type: ReminderPayloadType.task, id: 'task_1'),
      );
      await tester.pumpAndSettle();

      expect(currentTab(tester), 0, reason: '落点应当是今日页');
      expect(
        find.byType(TaskEditPage),
        findsNothing,
        reason: '提醒不代表已完成，不该把用户推进编辑页去选状态',
      );
      // 今日页能看到这条任务，用户可以自行勾选
      expect(find.text('写周报'), findsWidgets);
    });

    testWidgets('点计划提醒 → 今日页（不直接进计划详情）', (tester) async {
      useLargeSurface(tester);
      final service = await pumpApp(tester);

      service.tap(
        reminderPayload(
          type: ReminderPayloadType.cycle,
          id: 'cycle_1',
          dayKey: dayKey(today),
        ),
      );
      await tester.pumpAndSettle();

      expect(currentTab(tester), 0);
      expect(find.byType(CycleDetailPage), findsNothing);
    });

    testWidgets('从深层页面点通知：先清栈再回到今日页', (tester) async {
      useLargeSurface(tester);
      final service = await pumpApp(tester);

      // 手动进到计划详情页，制造一个「栈上已经有页面」的局面
      await tester.tap(find.text(TabLabels.cycles).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 天跑步训练'));
      await tester.pumpAndSettle();
      expect(find.byType(CycleDetailPage), findsOneWidget);

      service.tap(
        reminderPayload(type: ReminderPayloadType.task, id: 'task_1'),
      );
      await tester.pumpAndSettle();

      expect(currentTab(tester), 0);
      expect(find.byType(CycleDetailPage), findsNothing, reason: '栈要被清干净');
      expect(find.byType(TaskEditPage), findsNothing);
    });

    testWidgets('payload 真的解析不了 → 今日页', (tester) async {
      useLargeSurface(tester);
      final service = await pumpApp(tester);
      // 先离开今日页，确认这次是真的被「带回来」了
      await tester.tap(find.text(TabLabels.cycles).last);
      await tester.pumpAndSettle();
      expect(currentTab(tester), 2);

      service.tap('这不是 JSON');
      await tester.pumpAndSettle();

      expect(currentTab(tester), 0);
      expect(find.byType(TaskEditPage), findsNothing);
      expect(find.byType(CycleDetailPage), findsNothing);
    });

    testWidgets('payload 指向已被删除的任务 → 今日页', (tester) async {
      useLargeSurface(tester);
      final service = await pumpApp(tester);

      service.tap(
        reminderPayload(type: ReminderPayloadType.task, id: '已经不在了'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsNothing);
      expect(currentTab(tester), 0);
    });
  });

  group('8.6 冷启动：应用被点通知拉起', () {
    testWidgets('任务提醒启动 → 今日页', (tester) async {
      useLargeSurface(tester);
      await pumpApp(
        tester,
        launchPayload:
            reminderPayload(type: ReminderPayloadType.task, id: 'task_1'),
      );

      expect(currentTab(tester), 0);
      expect(find.byType(TaskEditPage), findsNothing);
    });

    testWidgets('计划提醒启动 → 今日页', (tester) async {
      useLargeSurface(tester);
      await pumpApp(
        tester,
        launchPayload:
            reminderPayload(type: ReminderPayloadType.cycle, id: 'cycle_1'),
      );

      expect(currentTab(tester), 0);
      expect(find.byType(CycleDetailPage), findsNothing);
    });

    testWidgets('冷启动 payload 无法解析 → 今日页', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester, launchPayload: '坏的 payload');

      expect(currentTab(tester), 0);
      expect(find.byType(TaskEditPage), findsNothing);
    });

    testWidgets('不是被通知拉起时留在今日页', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester);

      expect(currentTab(tester), 0);
      expect(find.byType(TaskEditPage), findsNothing);
    });
  });
}
