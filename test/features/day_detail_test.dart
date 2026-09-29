import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';
import 'package:loop_island/app/widgets/text_input_sheet.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/widgets/edit_scope_dialog.dart';
import 'package:loop_island/features/day/day_detail_page.dart';
import 'package:loop_island/features/reason/reason_sheet.dart';
import 'package:loop_island/features/tasks/task_list_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

/// 某天详情页验收（任务 5.8）。
void main() {
  final today = DateTime(2026, 9, 12);
  final yesterday = addDays(today, -1);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
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
    int periodDays = 8,
    DateTime? startDate,
    Map<int, String> titles = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: periodDays,
      startDate: startDate ?? today,
      days: [
        for (var i = 1; i <= periodDays; i++)
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

  /// 直接挂载某天详情页。
  Future<void> pumpDay(
    WidgetTester tester, {
    AppData? data,
    DateTime? date,
  }) async {
    await pumpWithScope(
      tester,
      DayDetailPage(dayKey: dayKey(date ?? today)),
      data: data,
      today: today,
    );
  }

  group('日期与空态', () {
    testWidgets('标题显示完整日期', (tester) async {
      useLargeSurface(tester);
      await pumpDay(tester);

      expect(find.text(formatFullDate(today)), findsOneWidget);
    });

    testWidgets('日期非法时给出可读提示，不崩', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const DayDetailPage(dayKey: '2026-02-30'),
        today: today,
      );

      expect(find.text(DayStrings.invalidDate), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('当天没有任务时显示空态', (tester) async {
      useLargeSurface(tester);
      await pumpDay(tester);

      expect(find.byKey(DayDetailKeys.empty), findsOneWidget);
      expect(find.text(DayStrings.noTask), findsOneWidget);
    });
  });

  group('展示当天所有任务', () {
    testWidgets('普通任务与循环任务都在，并标出来源', (tester) async {
      useLargeSurface(tester);
      await pumpDay(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', today, title: '写周报'),
          ]),
          cycles: List.unmodifiable([cycle()]),
        ),
      );

      expect(find.text('写周报'), findsOneWidget);
      expect(find.text(DayStrings.unknownCycle), findsOneWidget);
      expect(find.text('第 1 天任务'), findsOneWidget);
      expect(find.text('8 天跑步训练 · 第 1/8 天'), findsOneWidget);
    });

    testWidgets('显示当天进度', (tester) async {
      useLargeSurface(tester);
      await pumpDay(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('a', today, status: TaskStatus.completed),
            taskOn('b', today),
          ]),
        ),
      );

      expect(find.text(DayStrings.progress(1, 2)), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('展示状态标签', (tester) async {
      useLargeSurface(tester);
      await pumpDay(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('a', today, status: TaskStatus.missed),
            taskOn('b', today, status: TaskStatus.skipped),
          ]),
        ),
      );

      // 「跳过」既是状态标签也是动作按钮文案，必须限定在标签内断言
      Finder tagWith(String text) => find.descendant(
            of: find.byType(IslandTag),
            matching: find.text(text),
          );

      expect(tagWith(StatusLabels.missed), findsOneWidget);
      expect(tagWith(StatusLabels.skipped), findsOneWidget);
    });

    testWidgets('展示已有的未完成原因', (tester) async {
      useLargeSurface(tester);
      await pumpDay(
        tester,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', today, title: '跑步', status: TaskStatus.missed),
          ]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 'task_1',
              date: today,
              status: TaskStatus.missed,
              reason: '加班，没时间',
              reasonUpdatedAt: DateTime(2026, 9, 12, 22, 30),
            ),
          ]),
        ),
      );

      expect(find.text('加班，没时间'), findsOneWidget);
      expect(find.text(ReasonStrings.updatedAt('22:30')), findsOneWidget);
    });
  });

  group('改状态', () {
    testWidgets('勾选普通任务完成', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(
          tasks: List.unmodifiable([taskOn('task_1', today, title: '跑步')]),
        ),
        today: today,
      );

      await tester.tap(find.byType(AnimalCheckbox<bool>).first);
      await tester.pumpAndSettle();

      expect(
        result.store.snapshot!.data.tasks.single.status,
        TaskStatus.completed,
      );
    });

    testWidgets('标记未完成 / 跳过', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(
          tasks: List.unmodifiable([taskOn('task_1', today, title: '跑步')]),
        ),
        today: today,
      );

      await tester.tap(find.text(TodayStrings.markSkipped));
      await tester.pumpAndSettle();
      expect(
        result.store.snapshot!.data.tasks.single.status,
        TaskStatus.skipped,
      );
    });

    testWidgets('勾选循环实例只改当天，不改模板', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.byType(AnimalCheckbox<bool>).first);
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.records.single.status, TaskStatus.completed);
      expect(
        saved.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
      );
    });
  });

  group('补充 / 修改原因', () {
    testWidgets('填写快捷原因后落库', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', today, title: '跑步', status: TaskStatus.missed),
          ]),
        ),
        today: today,
      );

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(reasonChipKey(ReasonStrings.quickUnwell)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      final record = result.store.snapshot!.data.records.single;
      expect(record.reason, ReasonStrings.quickUnwell);
      expect(record.reasonUpdatedAt, isNotNull);
    });

    testWidgets('循环实例的原因写到当天记录上', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(reasonChipKey(ReasonStrings.quickWeather)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      final record = result.store.snapshot!.data.records.single;
      expect(record.cycleId, 'cycle_1');
      expect(record.cycleDayIndex, 1);
      expect(record.reason, ReasonStrings.quickWeather);
    });

    testWidgets('取消弹窗不改数据', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(
          tasks: List.unmodifiable([taskOn('task_1', today, title: '跑步')]),
        ),
        today: today,
      );

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.cancel));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0);
    });
  });

  group('循环实例改名（仅本次 / 以后所有）', () {
    testWidgets('选「仅本次」：只改当天，模板不动', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.byKey(DayDetailKeys.rename(today, 'cycle_1#ctask_1')));
      await tester.pumpAndSettle();

      // 范围弹窗
      expect(find.byKey(EditScopeKeys.dialog), findsOneWidget);
      expect(find.text(CycleStrings.scopeOnceHint), findsOneWidget);
      await tester.tap(find.byKey(EditScopeKeys.confirm));
      await tester.pumpAndSettle();

      // 名称弹层
      expect(find.byKey(TextInputSheetKeys.sheet), findsOneWidget);
      await tester.enterText(find.byKey(TextInputSheetKeys.field), '今天改成慢跑');
      await tester.tap(find.byKey(TextInputSheetKeys.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.records.single.titleOverride, '今天改成慢跑');
      expect(
        saved.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
        reason: '模板不能被改动',
      );
    });

    testWidgets('选「以后所有」：改模板并重算未来实例', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.byKey(DayDetailKeys.rename(today, 'cycle_1#ctask_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CycleStrings.scopeFromNowAll));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditScopeKeys.confirm));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(TextInputSheetKeys.field), '改成慢跑');
      await tester.tap(find.byKey(TextInputSheetKeys.confirm));
      await tester.pumpAndSettle();

      expect(
        result.store.snapshot!.data.cycles.single.dayAt(1).templates.single
            .title,
        '改成慢跑',
      );
    });

    testWidgets('范围弹窗取消则什么都不做', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.byKey(DayDetailKeys.rename(today, 'cycle_1#ctask_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditScopeKeys.cancel));
      await tester.pumpAndSettle();

      expect(find.byKey(TextInputSheetKeys.sheet), findsNothing);
      expect(result.store.saveCount, 0);
    });

    testWidgets('名称留空不允许提交', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        DayDetailPage(dayKey: dayKey(today)),
        data: AppData(cycles: List.unmodifiable([cycle()])),
        today: today,
      );

      await tester.tap(find.byKey(DayDetailKeys.rename(today, 'cycle_1#ctask_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditScopeKeys.confirm));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(TextInputSheetKeys.field), '   ');
      await tester.tap(find.byKey(TextInputSheetKeys.confirm));
      await tester.pumpAndSettle();

      expect(find.text(CommonStrings.required), findsOneWidget);
      expect(
        find.byKey(TextInputSheetKeys.sheet),
        findsOneWidget,
        reason: '不该关闭弹层',
      );
    });

    testWidgets('普通任务没有就地改名按钮', (tester) async {
      useLargeSurface(tester);
      await pumpDay(
        tester,
        data: AppData(
          tasks: List.unmodifiable([taskOn('task_1', today, title: '跑步')]),
        ),
      );

      expect(find.text(DayStrings.renameAction), findsNothing);
    });
  });

  group('入口与路由', () {
    testWidgets('dayDetail 路由带合法日期可进入', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      // 必须先切到任务 Tab：非当前 Tab 是 offstage，取 element 会失败
      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TaskListPage));
      context.pushDayDetail(dayKey(yesterday));
      await tester.pumpAndSettle();

      expect(find.byType(DayDetailPage), findsOneWidget);
      expect(find.text(formatFullDate(yesterday)), findsOneWidget);
    });

    testWidgets('dayDetail 路由日期非法时回落「页面不存在」', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TaskListPage));
      context.pushRoute<void>(AppRoutes.dayDetail, arguments: 'not-a-date');
      await tester.pumpAndSettle();

      expect(find.byType(DayDetailPage), findsNothing);
      expect(find.text(RouteStrings.notFound), findsOneWidget);
    });

    testWidgets('任务列表点日期标签进某天详情', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([taskOn('task_1', today, title: '跑步')]),
        ),
      );

      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(formatMonthDay(today)));
      await tester.pumpAndSettle();

      expect(find.byType(DayDetailPage), findsOneWidget);
    });
  });
}
