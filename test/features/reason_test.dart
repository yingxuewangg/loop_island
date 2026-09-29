import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/quick_reasons.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/reason/reason_sheet.dart';
import 'package:loop_island/features/reason/reason_view.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

/// 未完成原因弹窗与展示组件验收（任务 6.2 / 6.4 / 6.5）。
void main() {
  final today = DateTime(2026, 9, 12);
  final day = dateOnly(today);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2800);
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

  group('6.2 原因弹窗', () {
    testWidgets('展示 7 个快捷原因与自由输入框', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(tester, const ReasonSheet(), today: today);

      expect(find.byKey(ReasonKeys.sheet), findsOneWidget);
      expect(find.text(ReasonStrings.sheetTitle), findsOneWidget);
      expect(find.text(ReasonStrings.hint), findsOneWidget);
      expect(find.byKey(ReasonKeys.textField), findsOneWidget);

      for (final reason in quickReasons) {
        expect(
          find.byKey(reasonChipKey(reason.label)),
          findsOneWidget,
          reason: '缺少快捷原因：${reason.label}',
        );
      }
    });

    testWidgets('点快捷原因会填入输入框', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(tester, const ReasonSheet(), today: today);

      await tester.tap(find.byKey(reasonChipKey(ReasonStrings.quickForgot)));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, ReasonStrings.quickForgot);
    });

    testWidgets('已有快捷原因时回显选中，并预填输入框', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const ReasonSheet(initial: '忘记'),
        today: today,
      );

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, ReasonStrings.quickForgot);
    });

    testWidgets('已有自定义文本时预填输入框', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const ReasonSheet(initial: '在开会'),
        today: today,
      );

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '在开会');
    });

    testWidgets('点「其他」会清掉预设的快捷文本，让用户自己写', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const ReasonSheet(initial: '忘记'),
        today: today,
      );

      await tester.tap(find.byKey(reasonChipKey(ReasonStrings.quickOther)));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '');
    });

    testWidgets('确定按钮返回当前文本（已去空白）', (tester) async {
      useLargeSurface(tester);
      String? captured;

      await pumpWithScope(
        tester,
        Builder(
          builder: (context) => AnimalButton(
            onPressed: () async {
              captured = await showReasonSheet(context, initial: ' 在开会 ');
            },
            child: const Text('打开'),
          ),
        ),
        today: today,
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      expect(captured, '在开会');
    });

    testWidgets('留空提交返回空串（表示清空原因，而不是取消）', (tester) async {
      useLargeSurface(tester);
      String? captured;
      var called = false;

      await pumpWithScope(
        tester,
        Builder(
          builder: (context) => AnimalButton(
            onPressed: () async {
              called = true;
              captured = await showReasonSheet(context);
            },
            child: const Text('打开'),
          ),
        ),
        today: today,
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(captured, '', reason: '空串 = 清空；null 才是取消');
    });

    testWidgets('取消返回 null', (tester) async {
      useLargeSurface(tester);
      String? captured = 'sentinel';

      await pumpWithScope(
        tester,
        Builder(
          builder: (context) => AnimalButton(
            onPressed: () async {
              captured = await showReasonSheet(context, initial: '忘记');
            },
            child: const Text('打开'),
          ),
        ),
        today: today,
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.cancel));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });
  });

  group('6.4 ReasonView 展示', () {
    testWidgets('没有原因时显示「未填写原因」与补充入口', (tester) async {
      await pumpWithScope(
        tester,
        ReasonView(reason: null, onEdit: () {}),
        today: today,
      );

      expect(find.text(ReasonStrings.noReason), findsOneWidget);
      expect(find.text(ReasonStrings.addReason), findsOneWidget);
      expect(find.text(ReasonStrings.editReason), findsNothing);
    });

    testWidgets('有原因时显示文本、更新时间与修改入口', (tester) async {
      await pumpWithScope(
        tester,
        ReasonView(
          reason: '加班，没时间',
          reasonUpdatedAt: DateTime(2026, 9, 12, 22, 30),
          onEdit: () {},
        ),
        today: today,
      );

      expect(find.text('加班，没时间'), findsOneWidget);
      expect(
        find.text(ReasonStrings.updatedAt('22:30')),
        findsOneWidget,
      );
      expect(find.text(ReasonStrings.editReason), findsOneWidget);
    });

    testWidgets('只读模式（onEdit 为空）不显示入口', (tester) async {
      await pumpWithScope(
        tester,
        const ReasonView(reason: '天气原因'),
        today: today,
      );

      expect(find.text('天气原因'), findsOneWidget);
      expect(find.text(ReasonStrings.editReason), findsNothing);
      expect(find.text(ReasonStrings.addReason), findsNothing);
    });

    testWidgets('点补充入口触发回调', (tester) async {
      var tapped = false;
      await pumpWithScope(
        tester,
        ReasonView(reason: null, onEdit: () => tapped = true),
        today: today,
      );

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('纯空白原因按「未填写」处理', (tester) async {
      await pumpWithScope(
        tester,
        const ReasonView(reason: '   '),
        today: today,
      );

      expect(find.text(ReasonStrings.noReason), findsOneWidget);
    });
  });

  group('6.5 任务编辑页的原因入口', () {
    Future<void> openTask(WidgetTester tester, String title) async {
      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('未完成的任务显示原因入口，填写后落库', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', day, title: '跑步', status: TaskStatus.missed),
          ]),
        ),
      );
      await openTask(tester, '跑步');

      expect(find.byType(TaskEditPage), findsOneWidget);
      expect(find.byType(ReasonView), findsOneWidget);
      expect(find.text(ReasonStrings.addReason), findsOneWidget);

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(reasonChipKey(ReasonStrings.quickNoTime)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      final record = saved.records.singleWhere((e) => e.taskId == 'task_1');
      expect(record.reason, ReasonStrings.quickNoTime);
      expect(record.reasonUpdatedAt, isNotNull);
    });

    testWidgets('已完成的任务不显示原因入口', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', day,
                title: '跑步',
                status: TaskStatus.completed),
          ]),
        ),
      );
      await openTask(tester, '跑步');

      expect(find.byType(ReasonView), findsNothing);
    });

    testWidgets('取消弹窗不改动数据', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', day, title: '跑步', status: TaskStatus.missed),
          ]),
        ),
      );
      await openTask(tester, '跑步');

      await tester.tap(find.text(ReasonStrings.addReason));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReasonKeys.cancel));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0, reason: '取消不该落盘');
    });

    testWidgets('再打开时回显已填的原因', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', day, title: '跑步', status: TaskStatus.missed),
          ]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 'task_1',
              date: day,
              status: TaskStatus.missed,
              reason: '天气原因',
              reasonUpdatedAt: DateTime(2026, 9, 12, 20, 0),
            ),
          ]),
        ),
      );
      await openTask(tester, '跑步');

      expect(find.text(ReasonStrings.editReason), findsOneWidget);
      expect(find.text('天气原因'), findsWidgets);
      expect(
        find.text(ReasonStrings.updatedAt('20:00')),
        findsOneWidget,
      );
    });

    testWidgets('清空原因（留空提交）会把原因与更新时间一起清掉', (tester) async {
      useLargeSurface(tester);
      final result = await pumpLoopIslandApp(
        tester,
        today: today,
        data: AppData(
          tasks: List.unmodifiable([
            taskOn('task_1', day, title: '跑步', status: TaskStatus.missed),
          ]),
          records: List.unmodifiable([
            makeRecord(
              id: 'r1',
              taskId: 'task_1',
              date: day,
              status: TaskStatus.missed,
              reason: '天气原因',
              reasonUpdatedAt: DateTime(2026, 9, 12, 20, 0),
            ),
          ]),
        ),
      );
      await openTask(tester, '跑步');

      await tester.tap(find.text(ReasonStrings.editReason));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ReasonKeys.textField), '');
      await tester.tap(find.byKey(ReasonKeys.confirm));
      await tester.pumpAndSettle();

      final record = result.store.snapshot!.data.records
          .singleWhere((e) => e.id == 'r1');
      expect(record.reason, isNull);
      expect(record.reasonUpdatedAt, isNull);
    });
  });
}
