/// 任务编辑页「状态」单选组的行为复现测试。
///
/// 用户反馈：新建任务时状态有时默认成「未完成」，且点「待办」会瞬间
/// 跳回「未完成」。本文件把新建 / 编辑两条路径的状态交互钉死。
library;

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';
import 'package:loop_island/features/tasks/task_list_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

void main() {
  final today = DateTime(2026, 9, 12);

  Future<void> openTasksTab(WidgetTester tester) async {
    await tester.tap(find.text(TabLabels.tasks).last);
    await tester.pumpAndSettle();
  }

  AnimalRadio<TaskStatus> statusRadio(WidgetTester tester) =>
      tester.widget<AnimalRadio<TaskStatus>>(
        find.byType(AnimalRadio<TaskStatus>),
      );

  testWidgets('新建页：状态默认是待办', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpLoopIslandApp(tester, today: today);
    await openTasksTab(tester);
    await tester.tap(find.byKey(TaskListKeys.addFab));
    await tester.pumpAndSettle();

    expect(statusRadio(tester).value, TaskStatus.pending,
        reason: '新建任务状态默认应为待办');
  });

  testWidgets('新建页：点「待办」后仍是待办，保存落盘待办', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final result = await pumpLoopIslandApp(tester, today: today);
    await openTasksTab(tester);
    await tester.tap(find.byKey(TaskListKeys.addFab));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(AnimalInput).first, '点待办');
    await tester.tap(find.text(StatusLabels.pending));
    await tester.pumpAndSettle();

    expect(statusRadio(tester).value, TaskStatus.pending,
        reason: '点击待办后不应跳到其它状态');

    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();

    final saved = result.store.snapshot!.data;
    expect(saved.tasks.single.status, TaskStatus.pending);
  });

  testWidgets('编辑页：未完成任务点「待办」保存后落盘待办', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final result = await pumpLoopIslandApp(
      tester,
      today: today,
      data: AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 't1',
            title: '没做完的',
            date: today,
            status: TaskStatus.missed,
          ),
        ]),
      ),
    );
    await openTasksTab(tester);
    await tester.tap(find.text('没做完的'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskEditPage), findsOneWidget);
    expect(statusRadio(tester).value, TaskStatus.missed,
        reason: '编辑未完成任务时单选组应显示未完成');

    await tester.tap(find.text(StatusLabels.pending));
    await tester.pumpAndSettle();

    expect(statusRadio(tester).value, TaskStatus.pending,
        reason: '点击待办后不应跳回未完成');

    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();

    final saved = result.store.snapshot!.data;
    expect(saved.tasks.single.status, TaskStatus.pending);
  });
}
