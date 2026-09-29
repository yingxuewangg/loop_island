import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/stats.dart';
import 'package:loop_island/features/day/day_detail_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/features/stats/stats_page.dart';
import 'package:loop_island/features/stats/widgets/heatmap.dart';
import 'package:loop_island/features/stats/widgets/missed_records_list.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

/// 统计页与组件验收（任务 5.6 / 5.7 / 5.9 / 5.10）。
void main() {
  final today = DateTime(2026, 9, 12);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Task taskOn(
    String id,
    DateTime date, {
    TaskStatus status = TaskStatus.pending,
    String? title,
  }) {
    return makeTask(
      id: id,
      title: title ?? id,
      dateType: TaskDateType.custom,
      date: date,
      status: status,
      completedAt: status == TaskStatus.completed ? date : null,
    );
  }

  Cycle cycle({
    String id = 'cycle_1',
    String name = '8 天跑步训练',
    DateTime? startDate,
    Map<int, String> titles = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: 8,
      startDate: startDate ?? today,
      days: [
        for (var i = 1; i <= 8; i++)
          makeCycleDay(
            dayIndex: i,
            templates: [
              makeCycleTemplate(
                id: 'ctask_$i',
                title: titles[i] ?? '第 $i 天任务',
              ),
            ],
          ),
      ],
    );
  }

  /// 直接挂载统计页（不经设置页）。
  Future<void> pumpStats(
    WidgetTester tester, {
    AppData? data,
  }) async {
    await pumpWithScope(
      tester,
      const StatsPage(),
      data: data,
      today: today,
    );
  }

  group('5.6 统计页：五段布局', () {
    testWidgets('按 PRD §九 顺序渲染五个小节', (tester) async {
      useLargeSurface(tester);
      await pumpStats(tester);

      for (final section in [
        StatsStrings.sectionToday,
        StatsStrings.sectionStreak,
        StatsStrings.sectionCycles,
        StatsStrings.sectionHeatmap,
        StatsStrings.sectionMissed,
      ]) {
        expect(find.text(section), findsOneWidget, reason: '缺少小节：$section');
      }
    });

    testWidgets('今日小节显示任务数、已完成数与完成率', (tester) async {
      useLargeSurface(tester);
      await pumpStats(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('a', today, status: TaskStatus.completed),
            taskOn('b', today),
            taskOn('c', today),
          ]),
        ),
      );

      expect(find.text(StatsStrings.todaySummary(1, 3, 33)), findsOneWidget);
      expect(find.text('33%'), findsWidgets);
    });

    testWidgets('今天没有任务时给空态文案而不是 0%', (tester) async {
      useLargeSurface(tester);
      await pumpStats(tester);

      expect(find.text(StatsStrings.todayNoTask), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('连续打卡小节显示当前与最长', (tester) async {
      useLargeSurface(tester);
      await pumpStats(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('a', addDays(today, -1),
                status: TaskStatus.completed),
            taskOn('b', today, status: TaskStatus.completed),
          ]),
        ),
      );

      expect(find.text(StatsStrings.currentStreak), findsOneWidget);
      expect(find.text(StatsStrings.longestStreak), findsOneWidget);
      // 两个统计各自显示「2」与后缀「天」
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('天'), findsNWidgets(2));
    });

    testWidgets('循环计划小节显示第几天与本周期完成率', (tester) async {
      useLargeSurface(tester);
      final start = addDays(today, -2);
      await pumpStats(
        tester,
        data: AppData(
          cycles: List.unmodifiable([cycle(startDate: start)]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 'ctask_1',
              cycleId: 'cycle_1',
              cycleDayIndex: 1,
              date: start,
              status: TaskStatus.completed,
              completedAt: start,
            ),
          ]),
        ),
      );

      // 第 1 天完成、第 2、3 天未完成 → 1/3 = 33%
      expect(
        find.textContaining(StatsStrings.sectionCycles),
        findsWidgets,
      );
      expect(find.textContaining('8 天跑步训练：'), findsOneWidget);
      expect(find.textContaining('第 3/8 天'), findsOneWidget);
    });

    testWidgets('没有进行中的计划时给说明文案', (tester) async {
      useLargeSurface(tester);
      await pumpStats(tester);

      expect(find.text(StatsStrings.noRunningCycle), findsOneWidget);
    });

    testWidgets('未完成记录为空时显示空态', (tester) async {
      useLargeSurface(tester);
      await pumpStats(tester);

      expect(find.text(StatsStrings.noMissedRecord), findsWidgets);
    });
  });

  group('5.7 热力图', () {
    testWidgets('渲染 90 天格子与图例', (tester) async {
      useLargeSurface(tester);
      await pumpStats(tester);

      expect(find.byType(HeatmapGrid), findsOneWidget);
      expect(find.byKey(HeatmapKeys.grid), findsOneWidget);
      expect(find.byKey(HeatmapKeys.legend), findsOneWidget);
      expect(find.text(StatsStrings.heatmapLess), findsOneWidget);
      expect(find.text(StatsStrings.heatmapMore), findsOneWidget);
    });

    testWidgets('点击某天进入某天详情页', (tester) async {
      useLargeSurface(tester);
      await pumpStats(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('a', today, status: TaskStatus.completed),
          ]),
        ),
      );

      // 点今天那一格（按日期 key 精确定位，避免落在格子间隙上）
      await tester.tap(find.byKey(heatmapCellKey(today)));
      await tester.pumpAndSettle();

      expect(find.byType(DayDetailPage), findsOneWidget);
      expect(find.text(formatFullDate(today)), findsWidgets);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });

    test('档位取色：无任务与 0% 是不同的颜色来源', () {
      final theme = AnimalThemeData.fallback();
      final noTask = HeatmapCell(
        date: today,
        total: 0,
        completed: 0,
        level: 0,
      );
      final zeroPercent = HeatmapCell(
        date: today,
        total: 3,
        completed: 0,
        level: 0,
      );

      expect(heatmapColor(theme, noTask), theme.disabledBackgroundColor);
      expect(heatmapColor(theme, zeroPercent), isNot(theme.disabledBackgroundColor));
    });

    test('档位越高颜色越接近主色', () {
      final theme = AnimalThemeData.fallback();
      Color at(int level) => heatmapColor(
            theme,
            HeatmapCell(date: today, total: 4, completed: level, level: level),
          );

      expect(at(4), theme.primaryColor);
      expect(at(3).a, lessThan(at(4).a));
      expect(at(2).a, lessThan(at(3).a));
      expect(at(1).a, lessThan(at(2).a));
    });
  });

  group('5.9 未完成记录列表', () {
    testWidgets('按 PRD 格式展示「日期 标题：原因」', (tester) async {
      await pumpWithScope(
        tester,
        MissedRecordsList(
          data: AppData(
            tasks: List.unmodifiable([
              makeTask(id: 'task_1', title: '跑步'),
            ]),
            records: List.unmodifiable([
              makeRecord(
                id: 'r1',
                taskId: 'task_1',
                date: DateTime(2026, 9, 10),
                status: TaskStatus.missed,
                reason: '加班，没时间',
              ),
            ]),
          ),
        ),
        today: today,
      );

      expect(
        find.text('2026-09-10 跑步：加班，没时间'),
        findsOneWidget,
      );
    });

    testWidgets('没填原因时显示「未填写原因」', (tester) async {
      await pumpWithScope(
        tester,
        MissedRecordsList(
          data: AppData(
            tasks: List.unmodifiable([
              makeTask(id: 'task_1', title: '阅读'),
            ]),
            records: List.unmodifiable([
              makeRecord(
                id: 'r1',
                taskId: 'task_1',
                date: DateTime(2026, 9, 8),
                status: TaskStatus.missed,
              ),
            ]),
          ),
        ),
        today: today,
      );

      expect(find.textContaining('2026-09-08 阅读：未填写原因'), findsOneWidget);
    });

    testWidgets('按日期倒序', (tester) async {
      await pumpWithScope(
        tester,
        MissedRecordsList(
          data: AppData(
            tasks: List.unmodifiable([makeTask(id: 'task_1', title: 'A')]),
            records: List.unmodifiable([
              makeRecord(
                id: 'r_old',
                taskId: 'task_1',
                date: DateTime(2026, 9, 1),
                status: TaskStatus.missed,
              ),
              makeRecord(
                id: 'r_new',
                taskId: 'task_1',
                date: DateTime(2026, 9, 9),
                status: TaskStatus.missed,
              ),
            ]),
          ),
        ),
        today: today,
      );

      final newer = tester.getTopLeft(find.textContaining('2026-09-09')).dy;
      final older = tester.getTopLeft(find.textContaining('2026-09-01')).dy;
      expect(newer, lessThan(older));
    });

    testWidgets('无记录时显示空态', (tester) async {
      await pumpWithScope(
        tester,
        const MissedRecordsList(data: AppData()),
        today: today,
      );

      expect(find.byType(AnimalEmpty), findsOneWidget);
      expect(find.text(StatsStrings.noMissedRecord), findsOneWidget);
    });
  });

  group('入口与路由', () {
    testWidgets('设置页有统计入口，点击进入统计页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();

      expect(find.byKey(SettingsKeys.statsEntry), findsOneWidget);
      await tester.tap(find.byKey(SettingsKeys.statsEntry));
      await tester.pumpAndSettle();

      expect(find.byType(StatsPage), findsOneWidget);
      expect(find.text(StatsStrings.title), findsWidgets);
    });

    testWidgets('stats 路由已换成真实页面（不再是占位页）', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      // 非当前 Tab 是 offstage，finder 默认跳过，必须先切过去才能取到它的 element
      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SettingsPage));
      context.pushRoute<void>(AppRoutes.stats);
      await tester.pumpAndSettle();

      expect(find.byType(StatsPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });
  });
}
