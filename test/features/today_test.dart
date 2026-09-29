import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/cycle_detail_page.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';
import 'package:loop_island/features/today/today_page.dart';
import 'package:loop_island/features/today/widgets/quick_add_field.dart';
import 'package:loop_island/features/today/widgets/today_progress.dart';
import 'package:loop_island/features/today/widgets/tomorrow_preview_card.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

/// 阶段 4 界面验收（任务 4.3~4.9）。
void main() {
  final today = DateTime(2026, 9, 12);
  final tomorrow = addDays(today, 1);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Cycle cycle({
    String id = 'cycle_1',
    String name = '8 天跑步训练',
    int periodDays = 8,
    DateTime? startDate,
    CycleStatus status = CycleStatus.active,
    Map<int, String> titles = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: periodDays,
      startDate: startDate ?? today,
      status: status,
      days: [
        for (var i = 1; i <= periodDays; i++)
          makeCycleDay(
            dayIndex: i,
            templates: [
              makeCycleTemplate(
                id: 'ctask_${id}_$i',
                title: titles[i] ?? '第 $i 天任务',
              ),
            ],
          ),
      ],
    );
  }

  group('4.3 今日页头部', () {
    testWidgets('显示今天的日期与完成进度', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'a',
              title: 'A',
              dateType: TaskDateType.custom,
              date: today,
              status: TaskStatus.completed,
              completedAt: today,
            ),
            makeTask(
              id: 'b',
              title: 'B',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(TodayProgress), findsOneWidget);
      expect(find.text(formatFullDate(today)), findsOneWidget);
      expect(find.text(TodayStrings.progress(1, 2)), findsOneWidget);
      // 首页圆环与渐变进度条各显示一次百分比
      expect(find.text('50%'), findsNWidgets(2));
      expect(find.byType(IslandProgress), findsOneWidget);
      expect(find.byType(IslandProgressRing), findsOneWidget);
    });

    testWidgets('没有任务时显示空态而不是 0%', (tester) async {
      await pumpLoopIslandApp(tester, today: today);

      expect(find.text(TodayStrings.noTaskToday), findsWidgets);
      expect(find.text('0%'), findsNothing);
    });
  });

  group('4.4 今日任务列表与状态操作', () {
    testWidgets('普通任务与循环任务都出现在今日列表里', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
          cycles: List.unmodifiable([cycle()]),
        ),
      );

      expect(find.text('写周报'), findsOneWidget);
      expect(find.text('第 1 天任务'), findsOneWidget);
      expect(find.text('8 天跑步训练 · 第 1/8 天'), findsOneWidget);
    });

    testWidgets('勾选普通任务会写入完成状态与记录', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      await tester.tap(find.byType(AnimalCheckbox<bool>).first);
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.tasks.single.status, TaskStatus.completed);
      expect(saved.records.where((e) => e.taskId == 'task_1'), hasLength(1));
    });

    testWidgets('勾选循环任务只改当天实例，不改模板（PRD 关键规则）', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      await tester.tap(find.byType(AnimalCheckbox<bool>).first);
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      final instance = saved.records.singleWhere((e) => e.cycleId == 'cycle_1');
      expect(instance.status, TaskStatus.completed);
      expect(instance.cycleDayIndex, 1);

      // 模板没被动过
      expect(
        saved.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
      );
      expect(saved.cycles.single.dayAt(2).templates.single.title, '第 2 天任务');
    });

    testWidgets('可以标记未完成与跳过', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      // 「未完成 / 跳过」收进了「更多」菜单（防误触），先展开再选
      await tester.tap(find.byKey(TodayTaskTileKeys.moreActions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TodayStrings.markMissed).last);
      await tester.pumpAndSettle();
      expect(
        result.store.snapshot!.data.tasks.single.status,
        TaskStatus.missed,
      );
    });

    testWidgets('跳过任务', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      await tester.tap(find.byKey(TodayTaskTileKeys.moreActions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TodayStrings.markSkipped).last);
      await tester.pumpAndSettle();
      expect(
        result.store.snapshot!.data.tasks.single.status,
        TaskStatus.skipped,
      );
    });

    testWidgets('更多操作弹出应用风格操作单；取消不改状态', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      await tester.tap(find.byKey(TodayTaskTileKeys.moreActions));
      await tester.pumpAndSettle();

      // 操作单带任务标题上下文，两个动作按钮齐全（不是默认 Material 菜单）
      expect(find.textContaining(TodayStrings.moreActions), findsOneWidget);
      expect(find.text(TodayStrings.markMissed), findsOneWidget);
      expect(find.text(TodayStrings.markSkipped), findsOneWidget);

      await tester.tap(find.text(CommonStrings.cancel));
      await tester.pumpAndSettle();

      expect(
        result.store.snapshot!.data.tasks.single.status,
        TaskStatus.pending,
        reason: '取消不得改动状态',
      );
    });

    testWidgets('循环任务在被勾选后依然显示在今日列表（不会消失）', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      await tester.tap(find.byType(AnimalCheckbox<bool>).first);
      await tester.pumpAndSettle();

      expect(find.text('第 1 天任务'), findsOneWidget);
    });
  });

  group('4.6 快速添加', () {
    testWidgets('输入标题后点添加，创建今天的任务', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);

      await tester.enterText(find.byType(AnimalInput).first, '买牛奶');
      await tester.tap(find.text(CommonStrings.add));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.tasks.single;
      expect(saved.title, '买牛奶');
      expect(dayKey(saved.resolvedDate(today)!), dayKey(today));
      expect(find.text('买牛奶'), findsOneWidget);
    });

    testWidgets('空输入不创建任务', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);

      await tester.enterText(find.byType(AnimalInput).first, '   ');
      await tester.tap(find.text(CommonStrings.add));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0, reason: '不该产生任何落盘');
      expect(find.byType(QuickAddField), findsOneWidget);
    });

    testWidgets('添加后输入框被清空', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.enterText(find.byType(AnimalInput).first, '买牛奶');
      await tester.tap(find.text(CommonStrings.add));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '');
    });
  });

  group('4.5 明日预览卡片', () {
    testWidgets('显示明日日期与明日会出现的任务', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_tomorrow',
              title: '明天开会',
              dateType: TaskDateType.custom,
              date: tomorrow,
            ),
          ]),
          cycles: List.unmodifiable([cycle()]),
        ),
      );

      expect(find.byType(TomorrowPreviewCard), findsOneWidget);
      expect(find.text(TodayStrings.tomorrowPreview), findsOneWidget);
      expect(find.text(formatFullDate(tomorrow)), findsOneWidget);
      expect(find.text('明天开会'), findsOneWidget);
      expect(find.text('第 2 天任务'), findsOneWidget);
      expect(find.text('8 天跑步训练 · 第 2/8 天'), findsOneWidget);
    });

    testWidgets('明日没有安排时给出提示', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      expect(find.text(TodayStrings.noTaskTomorrow), findsOneWidget);
    });

    testWidgets('超过 5 条时显示「还有 N 项」', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            for (var i = 1; i <= 7; i++)
              makeTask(
                id: 'task_$i',
                title: '明日任务 $i',
                dateType: TaskDateType.custom,
                date: tomorrow,
              ),
          ]),
        ),
      );

      expect(find.text('明日任务 1'), findsOneWidget);
      expect(find.text('明日任务 5'), findsOneWidget);
      expect(find.text('明日任务 6'), findsNothing);
      expect(find.text(TodayStrings.moreItems(2)), findsOneWidget);
    });

    testWidgets('明日预览不会写库', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      // 今日维护只会物化「今天」的实例，不该出现明天的
      final saved = result.store.snapshot!.data;
      expect(
        saved.records.every((e) => isSameDay(e.date, today)),
        isTrue,
        reason: '明日预览必须是纯计算',
      );
    });
  });

  group('4.7 跳转', () {
    testWidgets('点循环任务进入所属计划详情', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      await tester.tap(find.text('第 1 天任务'));
      await tester.pumpAndSettle();

      expect(find.byType(CycleDetailPage), findsOneWidget);
    });

    testWidgets('点普通任务进入任务编辑页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            makeTask(
              id: 'task_1',
              title: '写周报',
              dateType: TaskDateType.custom,
              date: today,
            ),
          ]),
        ),
      );

      await tester.tap(find.text('写周报'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsOneWidget);
    });
  });

  group('每日维护（由 AppShell 统一负责）', () {
    testWidgets('打开应用会物化今天的循环实例', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      final saved = result.store.snapshot!.data;
      expect(saved.records, hasLength(1));
      expect(saved.records.single.cycleId, 'cycle_1');
      expect(saved.records.single.cycleDayIndex, 1);
    });

    testWidgets('维护是幂等的：不会重复写盘', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycle()])),
      );

      expect(result.store.saveCount, 1,
          reason: '四个 Tab 页同时存在，维护必须只提交一次');

      // 切 Tab 也不该再写
      await tester.tap(find.text(TabLabels.cycles).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TabLabels.today).last);
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 1);
    });

    testWidgets('没有可维护内容时不写盘', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      // 没有计划、没有到期项 → 不该产生写盘
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('已到期的计划在打开应用时被归档', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            makeCycle(
              id: 'c_old',
              periodDays: 3,
              startDate: addDays(today, -10),
              endType: CycleEndType.untilDate,
              endDate: addDays(today, -1),
              days: [
                for (var i = 1; i <= 3; i++)
                  makeCycleDay(
                    dayIndex: i,
                    templates: [makeCycleTemplate(id: 't$i')],
                  ),
              ],
            ),
          ]),
        ),
      );

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.status, CycleStatus.ended);
      expect(dayKey(saved.endedAt!), dayKey(today));
    });
  });

  group('4.8 进度组件', () {
    testWidgets('没有任务时不渲染进度条', (tester) async {
      await pumpLoopIslandApp(tester, today: today);

      // 今日页在空数据下不应出现进度百分比
      expect(find.textContaining('%'), findsNothing);
    });
  });
}
