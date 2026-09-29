import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/cycle_day_edit_page.dart';
import 'package:loop_island/features/cycle/cycle_detail_page.dart';
import 'package:loop_island/features/cycle/cycle_edit_page.dart';
import 'package:loop_island/features/cycle/cycle_list_page.dart';
import 'package:loop_island/features/cycle/widgets/cycle_card.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

/// 阶段 3 界面验收（任务 3.8~3.11）。
void main() {
  final today = DateTime(2026, 9, 12);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 切到「计划」Tab。
  ///
  /// `IndexedStack` 下非当前 Tab 是 offstage，finder 默认会跳过，
  /// 必须先切过去。
  Future<void> openCycleTab(WidgetTester tester) async {
    await tester.tap(find.text(TabLabels.cycles).last);
    await tester.pumpAndSettle();
  }

  /// 一个 8 天计划，每天 1 个任务。
  Cycle cycleEightDay({
    String id = 'cycle_1',
    String name = '8 天跑步训练',
    DateTime? startDate,
    CycleEndType endType = CycleEndType.never,
    DateTime? endDate,
    int? endCount,
    CycleStatus status = CycleStatus.active,
    DateTime? endedAt,
    int? remindMinuteOfDay,
    Map<int, bool> restDays = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: 8,
      startDate: startDate ?? today,
      endType: endType,
      endDate: endDate,
      endCount: endCount,
      status: status,
      endedAt: endedAt,
      remindMinuteOfDay: remindMinuteOfDay,
      days: [
        for (var i = 1; i <= 8; i++)
          makeCycleDay(
            dayIndex: i,
            isRestDay: restDays[i] ?? false,
            templates: restDays[i] == true
                ? const []
                : [makeCycleTemplate(id: 'ctask_$i', title: '第 $i 天任务')],
          ),
      ],
    );
  }

  group('3.8 计划列表页 / 3.9 计划卡片', () {
    testWidgets('没有计划时显示空态与新建按钮', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openCycleTab(tester);

      expect(find.byType(AnimalEmpty), findsOneWidget);
      expect(find.text(CycleStrings.noCycle), findsOneWidget);

      await tester.tap(find.byKey(CycleListKeys.emptyAddButton));
      await tester.pumpAndSettle();
      expect(find.byType(CycleEditPage), findsOneWidget);
    });

    testWidgets('卡片展示名称、周期、第几天、状态、结束日期、剩余轮数', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(
              endType: CycleEndType.untilDate,
              endDate: addDays(today, 23),
              remindMinuteOfDay: 6 * 60 + 30,
            ),
          ]),
        ),
      );
      await openCycleTab(tester);

      expect(find.byType(CycleCard), findsOneWidget);
      expect(find.text('8 天跑步训练'), findsOneWidget);
      expect(find.text(CycleStrings.periodDaysValue(8)), findsOneWidget);
      expect(find.text(CycleStrings.currentDay(1, 8)), findsOneWidget);
      expect(find.text(CycleStrings.statusActive), findsOneWidget);
      expect(
        find.text(CycleStrings.endDateValue(dayKey(addDays(today, 23)))),
        findsOneWidget,
      );
      expect(find.text(CycleStrings.remainingCycles(3)), findsOneWidget);
      expect(find.text(CycleStrings.remindAt('06:30')), findsOneWidget);
    });

    testWidgets('永不结束的计划显示「永不结束」且不显示剩余轮数', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openCycleTab(tester);

      expect(find.text(CycleStrings.neverEnds), findsOneWidget);
      expect(find.textContaining('剩余约'), findsNothing);
    });

    testWidgets('未开始的计划显示「尚未开始」', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(startDate: addDays(today, 5)),
          ]),
        ),
      );
      await openCycleTab(tester);

      expect(find.text(CycleStrings.notStarted), findsOneWidget);
      expect(find.text(CycleStrings.currentDay(1, 8)), findsNothing);
    });

    testWidgets('暂停的计划显示暂停状态', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([cycleEightDay(status: CycleStatus.paused)]),
        ),
      );
      await openCycleTab(tester);

      expect(find.text(CycleStrings.statusPaused), findsOneWidget);
    });

    testWidgets('已结束计划进入「已归档」段，默认折叠', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(id: 'c_run', name: '进行中的'),
            cycleEightDay(
              id: 'c_done',
              name: '已归档的',
              // 起始日必须在结束日之前，否则引擎会把结束日收敛到起始日
              startDate: addDays(today, -10),
              endType: CycleEndType.untilDate,
              endDate: addDays(today, -1),
            ),
          ]),
        ),
      );
      await openCycleTab(tester);

      expect(find.text('进行中的'), findsOneWidget);
      expect(find.textContaining(CycleStrings.archivedSection), findsOneWidget);
      expect(find.text('已归档的'), findsNothing, reason: '默认折叠');

      await tester.tap(find.byKey(CycleListKeys.archivedToggle));
      await tester.pumpAndSettle();
      expect(find.text('已归档的'), findsOneWidget);
    });

    testWidgets('进页面会把到期计划自动归档', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(
              // 库里还是 active，但结束日已过（起始日必须早于结束日）
              startDate: addDays(today, -10),
              endType: CycleEndType.untilDate,
              endDate: addDays(today, -3),
            ),
          ]),
        ),
      );
      await openCycleTab(tester);

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.status, CycleStatus.ended);
      expect(dayKey(saved.endedAt!), dayKey(today));
      expect(result.store.saveCount, 1, reason: '归档应产生一次落盘');
    });

    testWidgets('点卡片进入计划详情', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openCycleTab(tester);

      await tester.tap(find.text('8 天跑步训练'));
      await tester.pumpAndSettle();

      expect(find.byType(CycleDetailPage), findsOneWidget);
    });

    testWidgets('右下角新建按钮进入计划编辑页', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openCycleTab(tester);

      await tester.tap(find.byKey(CycleListKeys.addFab));
      await tester.pumpAndSettle();

      expect(find.byType(CycleEditPage), findsOneWidget);
      expect(find.text(CycleStrings.createTitle), findsWidgets);
    });
  });

  group('3.10 计划编辑页：新建', () {
    Future<void> openNewCycle(WidgetTester tester) async {
      await openCycleTab(tester);
      await tester.tap(find.byKey(CycleListKeys.addFab));
      await tester.pumpAndSettle();
    }

    testWidgets('填名称保存后计划出现在列表里', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '7 天学习计划');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.byType(CycleEditPage), findsNothing, reason: '保存后应返回');
      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.name, '7 天学习计划');
      expect(saved.periodDays, 8, reason: '默认 8 天');
      expect(saved.startDate, today);
      expect(saved.endType, CycleEndType.never);
      expect(saved.status, CycleStatus.active);
      expect(saved.days, hasLength(8), reason: '新建时自动铺满 8 天空白天');
      expect(find.text('7 天学习计划'), findsOneWidget);
    });

    testWidgets('名称为空时拒绝保存并提示', (tester) async {
      // 错误提示渲染在表单底部，视口太小会落在可见区域之外
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.text(CycleStrings.nameRequired), findsOneWidget);
      expect(find.byType(CycleEditPage), findsOneWidget);
      expect(result.store.saveCount, 0);
    });

    testWidgets('可以改周期天数', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '5 天计划');
      // 第一个下拉是周期天数
      await tester.tap(find.byType(AnimalSelect<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(CycleStrings.periodDaysValue(5)).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.periodDays, 5);
      expect(saved.days, hasLength(5));
    });

    testWidgets('选「循环 X 次后结束」会出现次数选择并保存', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '循环三次');
      await tester.tap(find.text(CycleStrings.endTypeAfterCount));
      await tester.pumpAndSettle();

      expect(find.text(CycleStrings.fieldEndCount), findsOneWidget);

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.endType, CycleEndType.afterCount);
      expect(saved.endCount, 3, reason: '默认 3 次');
    });

    testWidgets('选「到指定日期结束」但没选日期时拒绝保存', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '到某日结束');
      await tester.tap(find.text(CycleStrings.endTypeUntilDate));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.text(CycleStrings.endDateTooEarly), findsOneWidget);
      expect(find.byType(CycleEditPage), findsOneWidget);
      expect(result.store.saveCount, 0);
    });

    testWidgets('开启每日提醒后保存 reminder', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '带提醒的计划');
      await tester.tap(find.byType(AnimalSwitch).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.remindMinuteOfDay, 9 * 60, reason: '默认 09:00');
      expect(saved.remindLabel, '09:00');
    });

    testWidgets('开启每日提醒时用的是设置里的「默认提醒时间」', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          settings: makeSettings(defaultRemindMinuteOfDay: 21 * 60),
        ),
      );
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '跟着设置走');
      await tester.tap(find.byType(AnimalSwitch).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.cycles.single;
      expect(
        saved.remindMinuteOfDay,
        21 * 60,
        reason: '设置里的默认提醒时间只是个摆设就说明 8.5 没接上',
      );
    });

    testWidgets('计划可以设「一天提醒两次」并保存', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openNewCycle(tester);

      await tester.enterText(find.byType(AnimalInput).first, '一天两次提醒');
      await tester.tap(find.byType(AnimalSwitch).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(RemindSlotKeys.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.cycles.single;
      expect(saved.remindMinutesOfDay, [9 * 60, 10 * 60]);
      expect(saved.remindLabel, '09:00、10:00');
      expect(saved.remindMinuteOfDay, 9 * 60, reason: '单值 getter 取最早时段');
    });
  });

  group('3.10 计划编辑页：编辑', () {
    testWidgets('改名与改周期后保存，计划同步更新', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openCycleTab(tester);
      await tester.tap(find.text('8 天跑步训练'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CycleStrings.editTitle));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '改过名的计划');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(result.store.snapshot!.data.cycles.single.name, '改过名的计划');
    });
  });

  group('3.11 计划详情页', () {
    Future<void> openDetail(
      WidgetTester tester,
      String name, {
      bool expandArchived = false,
    }) async {
      await openCycleTab(tester);
      if (expandArchived) {
        await tester.tap(find.byKey(CycleListKeys.archivedToggle));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('展示状态、第几天、起始日、结束日期与剩余轮数', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(
              endType: CycleEndType.untilDate,
              endDate: addDays(today, 23),
            ),
          ]),
        ),
      );
      await openDetail(tester, '8 天跑步训练');

      expect(find.byType(CycleDetailPage), findsOneWidget);
      expect(find.text(CycleStrings.statusActive), findsOneWidget);
      expect(find.text(CycleStrings.currentDay(1, 8)), findsOneWidget);
      expect(
        find.text(CycleStrings.startDateValue(dayKey(today))),
        findsOneWidget,
      );
      expect(
        find.text(CycleStrings.endDateValue(dayKey(addDays(today, 23)))),
        findsOneWidget,
      );
      expect(find.text(CycleStrings.remainingCycles(3)), findsOneWidget);
    });

    testWidgets('列出第 1~8 天并显示任务预览', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openDetail(tester, '8 天跑步训练');

      for (var i = 1; i <= 8; i++) {
        expect(find.text(CycleStrings.dayLabel(i)), findsOneWidget,
            reason: '缺少第 $i 天');
        expect(find.text('第 $i 天任务'), findsOneWidget);
      }
    });

    testWidgets('休息日显示休息日标签', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([cycleEightDay(restDays: const {4: true})]),
        ),
      );
      await openDetail(tester, '8 天跑步训练');

      expect(find.text(CycleStrings.restDay), findsOneWidget);
      expect(find.text('第 4 天任务'), findsNothing);
      expect(find.text(CycleStrings.dayTaskCount(0)), findsNWidgets(0));
    });

    testWidgets('点某一天进入某天编辑页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openDetail(tester, '8 天跑步训练');

      await tester.tap(find.text(CycleStrings.dayLabel(3)));
      await tester.pumpAndSettle();

      expect(find.byType(CycleDayEditPage), findsOneWidget);
      expect(
        find.textContaining(CycleStrings.dayLabel(3)),
        findsWidgets,
        reason: '标题里应带上第几天',
      );
      expect(find.text('第 3 天任务'), findsOneWidget);
    });

    testWidgets('暂停后状态变为已暂停，再启用可恢复', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openDetail(tester, '8 天跑步训练');

      await tester.tap(find.text(CycleStrings.actionPause));
      await tester.pumpAndSettle();
      expect(
        result.store.snapshot!.data.cycles.single.status,
        CycleStatus.paused,
      );
      expect(find.text(CycleStrings.statusPaused), findsOneWidget);

      await tester.tap(find.text(CycleStrings.actionResume));
      await tester.pumpAndSettle();
      expect(
        result.store.snapshot!.data.cycles.single.status,
        CycleStatus.active,
      );
    });

    testWidgets('已结束的计划：启用按钮禁用并提示不可继续', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([
            cycleEightDay(
              startDate: addDays(today, -10),
              endType: CycleEndType.untilDate,
              endDate: addDays(today, -1),
            ),
          ]),
        ),
      );
      await openDetail(tester, '8 天跑步训练', expandArchived: true);

      expect(find.text(CycleStrings.statusEnded), findsOneWidget);
      expect(find.text(CycleStrings.endedCannotResume), findsOneWidget);

      final button = tester.widget<AnimalButton>(
        find.ancestor(
          of: find.text(CycleStrings.actionResume),
          matching: find.byType(AnimalButton),
        ),
      );
      expect(button.disabled, isTrue);
    });

    testWidgets('复制为新计划：生成副本、名称带后缀、起始日为今天', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openDetail(tester, '8 天跑步训练');

      await tester.tap(find.text(CycleStrings.actionDuplicate));
      // 复制成功会弹一条 2 秒的提示；必须让它自然结束，
      // 否则测试结束时残留的 Timer 会被判定为「widget 树已销毁但定时器仍在」
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final cycles = result.store.snapshot!.data.cycles;
      expect(cycles, hasLength(2));
      final copy = cycles.firstWhere((e) => e.id != 'cycle_1');
      expect(copy.name, '8 天跑步训练${CycleStrings.duplicateSuffix}');
      expect(copy.startDate, today);
      expect(copy.status, CycleStatus.active);
      expect(
        copy.days.first.templates.single.id,
        isNot('ctask_1'),
        reason: '模板 id 必须重新生成',
      );
    });

    testWidgets('删除计划：二次确认后级联删除记录并返回列表', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          cycles: List.unmodifiable([cycleEightDay()]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 'ctask_1',
              cycleId: 'cycle_1',
              cycleDayIndex: 1,
              date: today,
            ),
          ]),
        ),
      );
      await openDetail(tester, '8 天跑步训练');

      await tester.tap(find.text(CycleStrings.deleteConfirmTitle));
      await tester.pumpAndSettle();
      // 只断言「二次确认弹窗确实弹出来了」，不依赖长文案的逐字渲染
      expect(find.byType(AnimalDialog), findsOneWidget);
      expect(find.text(CommonStrings.cancel), findsOneWidget);
      expect(find.text(CommonStrings.confirm), findsOneWidget);

      await tester.tap(find.text(CommonStrings.cancel));
      await tester.pumpAndSettle();
      expect(result.store.snapshot!.data.cycles, hasLength(1),
          reason: '取消不删');

      await tester.tap(find.text(CycleStrings.deleteConfirmTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CommonStrings.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.cycles, isEmpty);
      expect(saved.records, isEmpty, reason: '记录必须级联删除');
      expect(find.byType(CycleDetailPage), findsNothing);
    });

    testWidgets('编辑计划按钮进入计划编辑页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openDetail(tester, '8 天跑步训练');

      await tester.tap(find.text(CycleStrings.editTitle));
      await tester.pumpAndSettle();

      expect(find.byType(CycleEditPage), findsOneWidget);
    });
  });

  group('3.12 某天编辑页', () {
    testWidgets('新建当天任务：第一次保存就必须落盘并回显', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(cycles: List.unmodifiable([cycleEightDay()])),
      );
      await openCycleTab(tester);
      await tester.tap(find.text('8 天跑步训练'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CycleStrings.dayLabel(1)));
      await tester.pumpAndSettle();
      expect(find.byType(CycleDayEditPage), findsOneWidget);

      // 新增任务（与用户操作一致：弹窗填标题 → 确定 → 保存）
      await tester.tap(find.byKey(CycleDayEditKeys.addTaskButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(CycleDayEditKeys.titleField),
        '晨跑 3 公里',
      );
      await tester.tap(find.byKey(CycleDayEditKeys.confirmAdd));
      await tester.pumpAndSettle();

      // 页面内先回显
      expect(find.text('晨跑 3 公里'), findsOneWidget);

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      // 第一次保存就必须写进模板（用户反馈「有时第一次保存会丢」）
      final snapshot = result.store.snapshot!.data;
      final day1 = snapshot.cycleById('cycle_1')!.dayAt(1);
      expect(
        day1.templates.map((t) => t.title),
        contains('晨跑 3 公里'),
        reason: '第一次保存就应生效',
      );

      // 返回详情页后当天行要能看到新任务
      expect(find.byType(CycleDayEditPage), findsNothing);
      expect(find.textContaining('晨跑 3 公里'), findsOneWidget);
    });
  });

  group('路由接线', () {
    testWidgets('cycleDetail 已从占位页换成真实页面', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openCycleTab(tester);

      final context = tester.element(find.byType(CycleListPage));
      context.pushRoute<void>(AppRoutes.cycleDetail, arguments: 'cycle_none');
      await tester.pumpAndSettle();

      expect(find.byType(CycleDetailPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });

    testWidgets('cycleEdit 已从占位页换成真实页面', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openCycleTab(tester);

      final context = tester.element(find.byType(CycleListPage));
      context.pushRoute<void>(AppRoutes.cycleEdit, arguments: 'cycle_none');
      await tester.pumpAndSettle();

      expect(find.byType(CycleEditPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });

    testWidgets('cycleDetail 缺少 id 时不进详情页', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openCycleTab(tester);

      final context = tester.element(find.byType(CycleListPage));
      context.pushRoute<void>(AppRoutes.cycleDetail);
      await tester.pumpAndSettle();

      expect(find.byType(CycleDetailPage), findsNothing);
      expect(find.text(RouteStrings.notFound), findsOneWidget);
    });
  });
}
