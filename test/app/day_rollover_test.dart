/// 跨天回归测试（用户报告的严重 bug）。
///
/// 用户场景：26 号新建任务、日期选「明天」 → 应在 27 号提醒。实际却是
/// 27 号不提醒，且重开应用后日期显示成「明天」= 28 号。
///
/// 两个独立成因，本文件各覆盖一组：
/// 1. **相对日期被落盘**：`addTask` 原样存下 `tomorrow`，隔天解析就往后
///    漂移一天，而提醒时刻仍停在原定那天 → 被判为已过去 → 不注册通知。
/// 2. **「今天」被永久缓存**：`todayProvider` 是普通 `Provider`，应用不被
///    杀就永远停在启动那天，回到前台也不重算。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/services/reminder_scheduler.dart';

import '../support/factories.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';

void main() {
  group('相对日期不落盘（成因 1）', () {
    test('26 号建「明天」的任务 → 27 号仍指向 27 号，提醒照常注册', () {
      final day26 = DateTime(2026, 9, 26);
      final day27 = addDays(day26, 1);

      // 26 号 09:00 建任务：日期「明天」(27 号)，提醒设 27 号 10:00
      final data = addTask(
        AppData.empty,
        title: '明天的事',
        dateType: TaskDateType.tomorrow,
        date: day27,
        remindAt: DateTime(2026, 9, 27, 10),
        now: DateTime(2026, 9, 26, 9),
      );
      final task = data.tasks.single;

      // 落盘必须是具体日期，不能是相对类型
      expect(task.dateType, TaskDateType.custom);
      expect(dayKey(task.date!), dayKey(day27));

      // 27 号（跨天后）再看：归属日不变，仍是 27 号
      expect(dayKey(task.resolvedDate(day27)!), dayKey(day27));
      // 到了 28 号也必须还是 27 号，绝不继续漂移
      expect(dayKey(task.resolvedDate(addDays(day26, 2))!), dayKey(day27));

      // 27 号当天早上调度：提醒时刻在未来 → 必须注册
      final reminders = buildReminders(
        data: data,
        settings: makeSettings(),
        now: DateTime(2026, 9, 27, 8),
      );
      expect(
        reminders.values.where((r) => r.title == '明天的事'),
        hasLength(1),
        reason: '跨天后提醒仍应被注册（这正是原来漏掉的那条）',
      );
    });

    test('26 号建「今天」的任务 → 不会在 27 号漂到 27 号', () {
      final day26 = DateTime(2026, 9, 26);
      final data = addTask(
        AppData.empty,
        title: '今天的事',
        dateType: TaskDateType.today,
        now: day26,
      );

      expect(data.tasks.single.dateType, TaskDateType.custom);
      expect(
        dayKey(data.tasks.single.resolvedDate(addDays(day26, 1))!),
        dayKey(day26),
        reason: '26 号建的任务永远是 26 号，不会跟着「今天」跑',
      );
    });
  });

  group('「今天」跨天刷新（成因 2）', () {
    /// 可变时钟：让测试能模拟「应用一直在跑，日期翻页了」。
    ///
    /// **只覆写 `nowProvider`**（真实时钟的单一来源），不覆写
    /// `todayProvider` —— 否则就把「todayProvider 会不会自己刷新」
    /// 都由 `nowProvider` 派生，这样测的才是生产路径。
    late DateTime clock;

    List<Override> clockOverrides() => [
          nowProvider.overrideWithValue(() => clock),
        ];

    setUp(() => clock = DateTime(2026, 9, 26, 22));

    testWidgets('应用挂到第二天：回到前台后「今天」翻页', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        extraOverrides: clockOverrides(),
      );
      final container = result.container;

      expect(dayKey(container.read(todayProvider)), '2026-09-26');

      // 时间推进到第二天，应用回到前台
      clock = DateTime(2026, 9, 27, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        dayKey(container.read(todayProvider)),
        '2026-09-27',
        reason: '跨天后「今天」必须刷新，否则今日页/维护/提醒全按昨天算',
      );
    });

    testWidgets('同一天内回到前台「今天」保持不变', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        extraOverrides: clockOverrides(),
      );
      final container = result.container;

      // 时间只走了几小时，仍是同一天
      clock = DateTime(2026, 9, 26, 23, 30);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(dayKey(container.read(todayProvider)), '2026-09-26');
    });

    testWidgets('跨天回前台后，派生视图也按新日期重建', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        extraOverrides: clockOverrides(),
      );
      final container = result.container;

      // 先确保数据加载完成，否则视图的 AsyncValue 还没解析
      await container.read(appDataProvider.future);
      await tester.pumpAndSettle();
      expect(
        dayKey(container.read(todayViewProvider).asData!.value.date),
        '2026-09-26',
      );

      clock = DateTime(2026, 9, 27, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // todayViewProvider 派生自 todayProvider，必须一起翻页
      // （否则今日页仍渲染昨天的任务列表）
      expect(
        dayKey(container.read(todayViewProvider).asData!.value.date),
        '2026-09-27',
        reason: '今日视图的日期也要跟着刷新',
      );
    });
  });

  group('端到端：26 号建的任务在 27 号准时提醒', () {
    testWidgets('跨天后提醒被重新注册（不再因日期漂移而丢失）', (tester) async {
      final day26 = DateTime(2026, 9, 26);
      final day27 = addDays(day26, 1);
      final service = FakeNotificationService();

      // 26 号：新建「明天 10:00」提醒的任务
      final data = addTask(
        AppData.empty,
        title: '明天的事',
        dateType: TaskDateType.tomorrow,
        date: day27,
        remindAt: DateTime(2026, 9, 27, 10),
        now: DateTime(2026, 9, 26, 9),
      );

      // 27 号早上打开应用：冷启动同步应按 27 号重排
      await pumpLoopIslandApp(
        tester,
        data: data,
        today: day27,
        now: DateTime(2026, 9, 27, 9),
        notificationService: service,
      );

      final scheduled = service.onceCalls
          .where((c) => c.title == '明天的事')
          .toList(growable: false);
      expect(scheduled, hasLength(1), reason: '这一条正是原来会丢的提醒');
      expect(
        dayKey(scheduled.single.at),
        dayKey(day27),
        reason: '提醒落在任务原定的那一天',
      );
    });
  });
}
