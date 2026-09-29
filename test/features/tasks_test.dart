import 'dart:async';

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/loop_island_app.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/app/widgets/minute_of_day_picker.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';
import 'package:loop_island/features/tasks/task_list_page.dart';
import 'package:loop_island/features/tasks/widgets/date_type_picker.dart';
import 'package:loop_island/features/tasks/widgets/remind_time_picker.dart';
import 'package:loop_island/features/tasks/widgets/task_history_list.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';

import '../support/factories.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';

/// 任务 2.5~2.13 的界面验收。
void main() {
  final today = DateTime(2026, 9, 12);

  /// 把测试视口调大。
  ///
  /// 任务列表与编辑页都是长列表，默认 800×600 视口下后半部分
  /// **根本不会被构建**，`find.text` 自然找不到 —— 这不是页面 bug，
  /// 是测试视口太小。凡是要断言靠下内容的用例都要先调大视口。
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 切到「任务」Tab。
  ///
  /// **必须先切过去再断言**：`AppShell` 用 `IndexedStack` + `Visibility.maintain`
  /// 承载四个 Tab，非当前 Tab 处于 offstage，而 finder 默认
  /// `skipOffstage: true` 会把它们全部跳过。
  Future<void> openTasksTab(WidgetTester tester) async {
    await tester.tap(find.text(TabLabels.tasks).last);
    await tester.pumpAndSettle();
  }

  /// 在历史记录组件内部查找文本，避免与编辑页其它位置的相同日期文案撞车。
  Finder inHistory(String text) => find.descendant(
        of: find.byType(TaskHistoryList),
        matching: find.text(text),
      );

  Task task(
    String id,
    String title, {
    TaskDateType dateType = TaskDateType.custom,
    DateTime? date,
    bool hasDate = true,
    TaskStatus status = TaskStatus.pending,
    DateTime? remindAt,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return makeTask(
      id: id,
      title: title,
      dateType: dateType,
      date: date,
      hasDate: hasDate,
      status: status,
      remindAt: remindAt,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      updatedAt: createdAt ?? DateTime(2026, 1, 1),
      completedAt: completedAt,
    );
  }

  group('2.5 任务列表页：分组渲染', () {
    testWidgets('按 逾期/今天/明天/未安排/以后/已完成 分节', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t_overdue', '昨天没做', date: addDays(today, -1)),
            task('t_today', '今天做', date: today),
            task('t_tomorrow', '明天做', date: addDays(today, 1)),
            task('t_none', '没安排', hasDate: false),
            task('t_future', '下周做', date: addDays(today, 7)),
            task('t_done', '已完成',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupOverdue, 1)),
          findsOneWidget);
      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupToday, 1)),
          findsOneWidget);
      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupTomorrow, 1)),
          findsOneWidget);
      expect(
          find.text(TaskStrings.sectionTitle(TaskStrings.groupUnscheduled, 1)),
          findsOneWidget);
      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupUpcoming, 1)),
          findsOneWidget);
      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupCompleted, 1)),
          findsOneWidget);

      for (final title in ['昨天没做', '今天做', '明天做', '没安排', '下周做', '已完成']) {
        expect(find.text(title), findsOneWidget, reason: '缺少任务：$title');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('空分节不渲染（没有逾期就不显示逾期标题）', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '今天做', date: today)]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupToday, 1)),
          findsOneWidget);
      expect(find.textContaining(TaskStrings.groupOverdue), findsNothing);
      expect(find.textContaining(TaskStrings.groupCompleted), findsNothing);
    });

    testWidgets('完全没有任务时显示空态', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      expect(find.byType(AnimalEmpty), findsOneWidget);
    });

    testWidgets('逾期任务的日期标签标注具体日期', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t_overdue', '逾期任务', date: addDays(today, -2)),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.textContaining('逾期（'), findsOneWidget);
    });
  });

  group('2.6 任务列表项：勾选与跳转', () {
    testWidgets('点勾选框只切换完成状态，不打开编辑页', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '写周报', date: today)]),
        ),
      );
      await openTasksTab(tester);

      await tester.tap(find.byType(AnimalCheckbox<bool>));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsNothing, reason: '不该跳进编辑页');

      final saved = result.store.snapshot!.data;
      expect(saved.tasks.single.status, TaskStatus.completed);
      expect(saved.records, hasLength(1), reason: '完成要落一条实例记录');
      expect(saved.records.single.status, TaskStatus.completed);
    });

    testWidgets('再点一次可取消完成', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '写周报',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
        ),
      );
      await openTasksTab(tester);

      await tester.tap(find.byType(AnimalCheckbox<bool>));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.tasks.single.status, TaskStatus.pending);
      expect(saved.tasks.single.completedAt, isNull);
    });

    testWidgets('点任务本体进入编辑页', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '写周报', date: today)]),
        ),
      );
      await openTasksTab(tester);

      await tester.tap(find.text('写周报'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsOneWidget);
      expect(find.text(TaskStrings.editTitleExisting), findsOneWidget);
    });

    testWidgets('已完成任务标题带删除线', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '做完了',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
        ),
      );
      await openTasksTab(tester);

      final title = tester.widget<Text>(find.text('做完了'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('提醒时间显示为徽标', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '带提醒',
                date: today, remindAt: DateTime(2026, 9, 12, 7, 30)),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(TaskStrings.remindAt('07:30')), findsOneWidget);
    });
  });

  group('2.5 新建按钮', () {
    testWidgets('点右下角新建按钮进入新建任务页', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsOneWidget);
      expect(find.text(TaskStrings.editTitleNew), findsOneWidget);
    });
  });

  group('2.9 任务编辑页：新建', () {
    testWidgets('填标题保存后任务出现在今天的分组里', (tester) async {
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '买牛奶');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsNothing, reason: '保存后应返回列表');
      final saved = result.store.snapshot!.data;
      expect(saved.tasks.single.title, '买牛奶');
      // 默认日期「今天」保存时固化为具体日期（不存相对类型）
      expect(saved.tasks.single.dateType, TaskDateType.custom);
      expect(dayKey(saved.tasks.single.date!), dayKey(today));
      expect(find.text('买牛奶'), findsOneWidget);
    });

    testWidgets('标题为空时禁止保存并给出错误', (tester) async {
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.titleRequired), findsOneWidget);
      expect(find.byType(TaskEditPage), findsOneWidget, reason: '不该返回');
      expect(result.store.saveCount, 0, reason: '不该产生任何落盘');
    });

    testWidgets('只有空格的标题同样被拒绝', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '    ');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.titleRequired), findsOneWidget);
    });

    testWidgets('新建页默认日期是今天', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      expect(find.byType(DateTypePicker), findsOneWidget);
      expect(find.textContaining(formatFullDate(today)), findsWidgets);
    });
  });

  group('2.9 任务编辑页：编辑与删除', () {
    testWidgets('改名保存后列表同步更新', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '旧标题', date: today)]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('旧标题'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '新标题');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      expect(result.store.snapshot!.data.tasks.single.title, '新标题');
      expect(find.text('新标题'), findsOneWidget);
      expect(find.text('旧标题'), findsNothing);
    });

    testWidgets('删除需要二次确认，取消则不删', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '要删的', date: today)]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('要删的'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.delete));
      await tester.pumpAndSettle();
      expect(find.text(TaskStrings.deleteConfirmTitle), findsOneWidget);

      await tester.tap(find.text(CommonStrings.cancel));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0, reason: '取消不该落盘');
      expect(find.byType(TaskEditPage), findsOneWidget);
    });

    testWidgets('确认删除后任务与记录一起消失', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '要删的',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
          records: List.unmodifiable([makeRecord(taskId: 't1', date: today)]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('要删的'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CommonStrings.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.tasks, isEmpty);
      expect(saved.records, isEmpty, reason: '记录必须级联删除');
      expect(find.byType(TaskEditPage), findsNothing);
    });

    testWidgets('编辑页展示历史记录', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '有历史的', date: today)]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 't1',
              date: addDays(today, -1),
              status: TaskStatus.missed,
              reason: '加班，没时间',
            ),
          ]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('有历史的'));
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.history), findsOneWidget);
      // 原因文本同时出现在「原因区」与「历史时间线」里，断言限定在历史组件内
      expect(inHistory('加班，没时间'), findsOneWidget);
      expect(inHistory(formatFullDate(addDays(today, -1))), findsOneWidget);
    });

    testWidgets('没有历史时给出空态说明', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '没历史的', date: today)]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('没历史的'));
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.noHistory), findsOneWidget);
    });
  });

  group('2.7 日期类型选择器', () {
    testWidgets('切到「无日期」后提醒被禁用并给出说明', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      // 新建默认是「今天」，此时提醒可用
      expect(find.text(TaskStrings.remindNeedsDate), findsNothing);

      await tester.tap(find.text(DateTypeLabels.none));
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.remindNeedsDate), findsOneWidget);
      final sw = tester.widget<AnimalSwitch>(find.byType(AnimalSwitch));
      expect(sw.disabled, isTrue);

      await tester.enterText(find.byType(AnimalInput).first, '无日期任务');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.tasks.single;
      expect(saved.dateType, TaskDateType.none);
      expect(saved.remindAt, isNull);
    });

    testWidgets('选择明天后写入明天日期（固化为具体日期，不存相对类型）', (tester) async {
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.tap(find.text(DateTypeLabels.tomorrow));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AnimalInput).first, '明天的事');
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.tasks.single;
      expect(
        saved.dateType,
        TaskDateType.custom,
        reason: '相对日期必须固化：否则明天再看这条会漂到后天，提醒时刻对不上',
      );
      expect(dayKey(saved.date!), dayKey(addDays(today, 1)));
    });
  });

  group('2.8 提醒时间选择器', () {
    testWidgets('有日期时可以打开提醒并选择时分', (tester) async {
      await pumpWithScope(
        tester,
        const _RemindHarness(),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.byType(RemindTimePicker), findsOneWidget);
      expect(find.text(TaskStrings.noRemind), findsOneWidget);

      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();

      expect(find.byType(AnimalSelect<int>), findsNWidgets(2));
      expect(find.textContaining('09 时'), findsWidgets);
    });

    testWidgets('无日期时提醒被禁用并提示原因', (tester) async {
      await pumpWithScope(
        tester,
        RemindTimePicker(
          remindAts: const [],
          day: null,
          enabled: false,
          onChanged: (_) {},
        ),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.remindNeedsDate), findsOneWidget);
      final sw = tester.widget<AnimalSwitch>(find.byType(AnimalSwitch));
      expect(sw.disabled, isTrue);
    });

    testWidgets('提醒时刻已过去时提示「到点不会再提醒」', (tester) async {
      // 用户的实际场景：任务落在今天、用默认时段 09:00，
      // 但创建时已经是下午 —— 这个时刻调度器不会注册，必须让用户看见。
      final now = DateTime(2026, 9, 12, 14);
      await pumpWithScope(
        tester,
        RemindTimePicker(
          remindAts: [atMinuteOfDay(today, 9 * 60)],
          day: today,
          enabled: true,
          now: now,
          onChanged: (_) {},
        ),
        today: today,
        now: now,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已经过去'), findsOneWidget);
      expect(find.textContaining('09:00'), findsWidgets);
    });

    testWidgets('提醒时刻仍在将来时不提示', (tester) async {
      final now = DateTime(2026, 9, 12, 8);
      await pumpWithScope(
        tester,
        RemindTimePicker(
          remindAts: [atMinuteOfDay(today, 9 * 60)],
          day: today,
          enabled: true,
          now: now,
          onChanged: (_) {},
        ),
        today: today,
        now: now,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已经过去'), findsNothing);
    });

    testWidgets('下午新建任务打开提醒开关（默认 09:00）会立刻看到已过去提示',
        (tester) async {
      useLargeSurface(tester);
      final now = DateTime(2026, 9, 12, 14);
      await pumpLoopIslandApp(tester, today: today, now: now);
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '下午建的');
      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('09:00'),
        findsWidgets,
        reason: '界面显示 09:00 提醒',
      );
      expect(
        find.textContaining('已经过去'),
        findsOneWidget,
        reason: '默认时段已过，必须立刻提示，而不是等用户发现通知没响',
      );
    });

    testWidgets('小时下拉带「早上 / 晚上」段位：09 与 21 一眼可辨', (tester) async {
      // 12 小时制手机上，裸的「09 时」会被读成晚上 9 点 ——
      // 用户实际踩坑：选了 09:35 以为设的是晚上，到点自然不响。
      await pumpWithScope(
        tester,
        MinuteOfDayPicker(minuteOfDay: 9 * 60 + 35, onChanged: (_) {}),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('早上 09 时'), findsOneWidget);
      expect(find.textContaining('晚上'), findsNothing);

      await pumpWithScope(
        tester,
        MinuteOfDayPicker(minuteOfDay: 21 * 60 + 35, onChanged: (_) {}),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('晚上 21 时'), findsOneWidget);
      expect(find.textContaining('早上'), findsNothing);
    });

    testWidgets('精确闹钟未授权且设了提醒 → 编辑页行内提示可一键授权', (tester) async {
      useLargeSurface(tester);
      final service = FakeNotificationService()..exactAlarmsEnabledResult = false;
      await pumpLoopIslandApp(
        tester,
        today: today,
        now: today,
        notificationService: service,
      );
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      // 还没设提醒时不打扰用户
      expect(find.byKey(TaskEditKeys.grantExactAlarm), findsNothing);

      await tester.enterText(find.byType(AnimalInput).first, '带提醒的');
      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();

      expect(
        find.byKey(TaskEditKeys.grantExactAlarm),
        findsOneWidget,
        reason: '设了提醒就要提示「不授权会延迟」，否则用户永远不知道',
      );

      final permissionBefore = service.permissionCount;
      await tester.tap(find.byKey(TaskEditKeys.grantExactAlarm));
      await tester.pumpAndSettle();
      expect(
        service.permissionCount,
        greaterThan(permissionBefore),
        reason: '点按钮要真的去申请权限',
      );
    });

    testWidgets('精确闹钟已授权时不显示提示', (tester) async {
      useLargeSurface(tester);
      final service = FakeNotificationService()..exactAlarmsEnabledResult = true;
      await pumpLoopIslandApp(
        tester,
        today: today,
        now: today,
        notificationService: service,
      );
      await openTasksTab(tester);
      await tester.tap(find.byKey(TaskListKeys.addFab));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '带提醒的');
      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();

      expect(find.byKey(TaskEditKeys.grantExactAlarm), findsNothing);
    });

    testWidgets('任务可以设「一天提醒两次」并保存', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      await tester.tap(find.byKey(TaskListKeys.emptyAddButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '一天两次');
      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();
      // 打开后只有一个时段，再加一个 → 一天两次
      await tester.tap(find.byKey(RemindSlotKeys.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.tasks.single;
      expect(saved.remindAts, hasLength(2));
      expect(saved.remindAts.first, atMinuteOfDay(today, 9 * 60));
      expect(saved.remindAts.last, atMinuteOfDay(today, 10 * 60));
    });

    testWidgets('改任务日期时提醒时段跟着挪到新日期', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      await tester.tap(find.byKey(TaskListKeys.emptyAddButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AnimalInput).first, '挪日期');
      await tester.tap(find.byType(AnimalSwitch));
      await tester.pumpAndSettle();

      // 切成「明天」：提醒时段必须整体挪到明天，否则会出现
      // 「任务在明天、提醒还留在今天」这种自相矛盾的状态
      await tester.tap(find.text(DateTypeLabels.tomorrow));
      await tester.pumpAndSettle();

      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data.tasks.single;
      expect(saved.resolvedDate(today), addDays(today, 1));
      expect(saved.remindAts, hasLength(1));
      expect(
        dayKey(saved.remindAts.single),
        dayKey(addDays(today, 1)),
        reason: '提醒要跟着任务日期走',
      );
      expect(minuteOfDay(saved.remindAts.single), 9 * 60);
    });
  });

  group('2.11 任务历史记录组件', () {
    testWidgets('用时间线展示日期、状态、完成时间与原因，按日期倒序', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '有历史的', date: today)]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r_recent',
              taskId: 't1',
              date: today,
              status: TaskStatus.completed,
              completedAt: DateTime(2026, 9, 12, 21, 5),
            ),
            makeRecord(
              id: 'r_older',
              taskId: 't1',
              date: addDays(today, -1),
              status: TaskStatus.missed,
              reason: '加班，没时间',
            ),
            makeRecord(
              id: 'r_oldest',
              taskId: 't1',
              date: addDays(today, -2),
              status: TaskStatus.skipped,
            ),
          ]),
        ),
      );
      await openTasksTab(tester);
      await tester.tap(find.text('有历史的'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskHistoryList), findsOneWidget);
      expect(find.byType(AnimalTimeline), findsOneWidget);

      expect(inHistory(formatFullDate(today)), findsOneWidget);
      expect(inHistory(formatFullDate(addDays(today, -1))), findsOneWidget);
      expect(inHistory(formatFullDate(addDays(today, -2))), findsOneWidget);

      expect(find.text(StatusLabels.completed), findsWidgets);
      expect(find.text(StatusLabels.missed), findsWidgets);
      expect(find.text(StatusLabels.skipped), findsWidgets);

      expect(find.textContaining('21:05'), findsOneWidget);
      // 同上：限定在历史组件内，避免与「原因区」的同一段文本撞车
      expect(inHistory('加班，没时间'), findsOneWidget);

      final recentY = tester.getTopLeft(inHistory(formatFullDate(today))).dy;
      final oldestY =
          tester.getTopLeft(inHistory(formatFullDate(addDays(today, -2)))).dy;
      expect(recentY, lessThan(oldestY), reason: '最近的记录应排在最上面');
    });

    test('状态映射到不同的时间线节点与标签颜色', () {
      expect(
        timelineStatusOf(makeRecord(status: TaskStatus.completed)),
        AnimalTimelineItemStatus.success,
      );
      expect(
        timelineStatusOf(makeRecord(status: TaskStatus.missed)),
        AnimalTimelineItemStatus.danger,
      );
      expect(
        timelineStatusOf(makeRecord(status: TaskStatus.skipped)),
        AnimalTimelineItemStatus.warning,
      );
      expect(
        timelineStatusOf(makeRecord(status: TaskStatus.pending)),
        AnimalTimelineItemStatus.defaultStatus,
      );

      expect(
        tagColorOf(makeRecord(status: TaskStatus.completed)),
        IslandTagColors.done,
      );
      expect(
        tagColorOf(makeRecord(status: TaskStatus.missed)),
        IslandTagColors.missed,
      );
      expect(
        tagColorOf(makeRecord(status: TaskStatus.skipped)),
        IslandTagColors.skipped,
      );
    });

    testWidgets('无记录时显示空态', (tester) async {
      await pumpWithScope(
        tester,
        const TaskHistoryList(records: []),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimalEmpty), findsOneWidget);
      expect(find.byType(AnimalTimeline), findsNothing);
    });

    testWidgets('空态文案可自定义', (tester) async {
      await pumpWithScope(
        tester,
        const TaskHistoryList(records: [], emptyDescription: '这里啥也没有'),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(find.text('这里啥也没有'), findsOneWidget);
    });

    testWidgets('顺延来的记录会标注来源日期', (tester) async {
      await pumpWithScope(
        tester,
        TaskHistoryList(
          records: [
            makeRecord(
              taskId: 't1',
              date: today,
              status: TaskStatus.pending,
              rescheduledFrom: addDays(today, -3),
            ),
          ],
        ),
        today: today,
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('顺延自 ${formatMonthDay(addDays(today, -3))}'),
        findsOneWidget,
      );
    });
  });

  group('2.12 空态与加载态', () {
    testWidgets('完全没任务时给出引导文案与新建按钮', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      expect(find.byType(AnimalEmpty), findsOneWidget);
      expect(find.text(TaskStrings.emptyList), findsOneWidget);

      await tester.tap(find.byKey(TaskListKeys.emptyAddButton));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditPage), findsOneWidget);
    });

    testWidgets('加载中显示骨架屏而不是空态', (tester) async {
      final store = _PendingLoadStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            notificationServiceProvider
                .overrideWithValue(const NoopNotificationService()),
          ],
          child: const LoopIslandApp(),
        ),
      );
      // 刻意不 settle：让 provider 停在 loading，验证骨架屏
      await tester.pump();
      // 任务页所在 Tab 是 offstage，finder 默认会跳过，必须切过去
      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pump();

      expect(find.byType(AnimalSkeleton), findsOneWidget);
      expect(
        find.text(TaskStrings.emptyList),
        findsNothing,
        reason: '还没读完就说「没有任务」会误导用户',
      );

      store.completer.complete(AppBackup.of(AppData.empty));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalSkeleton), findsNothing);
    });

    testWidgets('读取失败时给出错误提示与重试，而不是假装没任务', (tester) async {
      final store = _FailingLoadStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            notificationServiceProvider
                .overrideWithValue(const NoopNotificationService()),
          ],
          child: const LoopIslandApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openTasksTab(tester);

      expect(find.text(TaskStrings.loadFailed), findsOneWidget);
      expect(find.text(CommonStrings.retry), findsOneWidget);
      expect(
        find.text(TaskStrings.emptyList),
        findsNothing,
        reason: '读取失败不能显示成「没有任务」',
      );
      expect(tester.takeException(), isNull, reason: '不能让异常冒到框架层');
    });
  });

  group('2.13 分组边界补充', () {
    testWidgets('只有已完成任务时，只渲染「已完成」一节', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '做完了',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupCompleted, 1)),
          findsOneWidget);
      expect(find.textContaining(TaskStrings.groupToday), findsNothing);
      expect(find.textContaining(TaskStrings.groupOverdue), findsNothing);
    });

    testWidgets('分节标题带数量', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', 'A', date: today),
            task('t2', 'B', date: today),
            task('t3', 'C', date: addDays(today, 1)),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupToday, 2)),
          findsOneWidget);
      expect(find.text(TaskStrings.sectionTitle(TaskStrings.groupTomorrow, 1)),
          findsOneWidget);
    });

    testWidgets('未完成与跳过状态在列表项上有标签', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '没做的', date: today, status: TaskStatus.missed),
            task('t2', '跳过的', date: today, status: TaskStatus.skipped),
          ]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(StatusLabels.missed), findsWidgets);
      expect(find.text(StatusLabels.skipped), findsWidgets);
    });

    testWidgets('无日期任务显示「未安排」标签', (tester) async {
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([task('t1', '没安排', hasDate: false)]),
        ),
      );
      await openTasksTab(tester);

      expect(find.text(DateTypeLabels.unscheduled), findsWidgets);
    });

    testWidgets('六个分节覆盖全部任务，不会丢任务', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            task('t1', '逾期', date: addDays(today, -1)),
            task('t2', '今天', date: today),
            task('t3', '明天', date: addDays(today, 1)),
            task('t4', '没安排', hasDate: false),
            task('t5', '以后', date: addDays(today, 5)),
            task('t6', '已完成',
                date: today,
                status: TaskStatus.completed,
                completedAt: today),
          ]),
        ),
      );
      await openTasksTab(tester);

      for (final title in ['逾期', '今天', '明天', '没安排', '以后', '已完成']) {
        expect(find.text(title), findsOneWidget, reason: '任务「$title」不该消失');
      }
    });
  });

  group('路由接线', () {
    testWidgets('taskEdit 路由已从占位页换成真实编辑页', (tester) async {
      await pumpLoopIslandApp(tester, today: today);
      await openTasksTab(tester);

      final context = tester.element(find.byType(TaskListPage));
      context.pushRoute<void>(AppRoutes.taskEdit, arguments: 'task_missing');
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });
  });
}

/// 提醒选择的受控宿主。
class _RemindHarness extends StatefulWidget {
  const _RemindHarness();

  @override
  State<_RemindHarness> createState() => _RemindHarnessState();
}

class _RemindHarnessState extends State<_RemindHarness> {
  List<DateTime> _remindAts = const [];

  @override
  Widget build(BuildContext context) {
    return RemindTimePicker(
      remindAts: _remindAts,
      day: DateTime(2026, 9, 12),
      enabled: true,
      onChanged: (value) => setState(() => _remindAts = value),
    );
  }
}

/// `load` 一直挂起的存储，用于验证加载态。
class _PendingLoadStore extends LocalStore {
  final Completer<AppBackup> completer = Completer<AppBackup>();

  @override
  Future<AppBackup> load() => completer.future;

  @override
  Future<void> save(AppBackup backup) async {}

  @override
  Future<void> clear() async {}
}

/// `load` 直接失败的存储，用于验证错误态。
class _FailingLoadStore extends LocalStore {
  @override
  Future<AppBackup> load() async => throw StateError('磁盘读取失败');

  @override
  Future<void> save(AppBackup backup) async {}

  @override
  Future<void> clear() async {}
}
