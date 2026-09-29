import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/cycle_day_edit_page.dart';
import 'package:loop_island/features/cycle/cycle_list_page.dart';
import 'package:loop_island/features/settings/data_page.dart';
import 'package:loop_island/features/settings/export_page.dart';
import 'package:loop_island/features/settings/import_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/features/tasks/task_list_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/services/backup_io.dart';
import 'package:loop_island/services/reminder_scheduler.dart';

import '../support/factories.dart';
import '../support/fake_backup_io.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';
import 'package:loop_island/app/widgets/island_bottom_bar.dart';

/// 任务 9.3：主流程端到端验收（把人工冒烟清单里**能自动化**的部分固化下来）。
///
/// 这里刻意**走真实界面**：点 Tab、点按钮、填表单、确认弹窗，
/// 只把三样东西换成假的 —— 内存存储、通知服务、文件 IO（都要打平台通道）。
/// 因此它验证的是「用户点下去真的有反应」，而不是「某个函数返回了什么」。
///
/// `docs/ACCEPTANCE.md` §9.3 的 21 步里，除「通知真的弹出来」「重启手机后提醒仍在」
/// 「Android 图标名」这类必须真机的项目外，其余都在本文件里跑一遍。
void main() {
  final today = DateTime(2026, 9, 12);
  final now = DateTime(2026, 9, 12, 10);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1300, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 切到某个 Tab（非当前 Tab 处于 offstage，finder 默认跳过）。
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// 点设置页的某个入口。
  Future<void> openSettingsEntry(WidgetTester tester, Key entry) async {
    await openTab(tester, TabLabels.settings);
    await tester.tap(find.byKey(entry));
    await tester.pumpAndSettle();
  }

  /// 返回上一页（不能用 `tester.pageBack()`：本应用是 zh_CN，tooltip 不是 `Back`）。
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
  }

  testWidgets('主流程：建任务 → 今日勾选 → 建 8 天计划 → 循环任务 → 到期归档 → 导出 → 清空 → 导入恢复',
      (tester) async {
    useLargeSurface(tester);

    // ---------------------------------------------------------- 1. 打开应用
    final service = FakeNotificationService();
    final booted = await pumpLoopIslandApp(
      tester,
      today: today,
      now: now,
      notificationService: service,
    );
    // 打开即用：没有登录页 / 引导页，直接是今日页
    expect(find.byType(IslandBottomBar), findsOneWidget);
    expect(find.text(TodayStrings.title), findsWidgets);

    // ---------------------------------------------------------- 2. 新建任务
    await openTab(tester, TabLabels.tasks);
    await tester.tap(find.byKey(TaskListKeys.emptyAddButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(AnimalInput).first, '写周报');
    // 打开提醒（默认日期就是今天），再补一个时段 → 一天提醒两次
    await tester.tap(find.byType(AnimalSwitch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RemindSlotKeys.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();

    var saved = booted.store.snapshot!.data;
    expect(saved.tasks.single.title, '写周报');
    expect(saved.tasks.single.remindAts, hasLength(2), reason: '一天可选多次提醒');

    // ---------------------------------------------------- 3. 今日页勾选完成
    await openTab(tester, TabLabels.today);
    expect(find.text('写周报'), findsOneWidget);

    await tester.tap(find.byType(AnimalCheckbox<bool>).first);
    await tester.pumpAndSettle();

    saved = booted.store.snapshot!.data;
    expect(saved.tasks.single.status, TaskStatus.completed);
    expect(
      saved.records.where((e) => e.taskId == saved.tasks.single.id),
      hasLength(1),
      reason: '勾选要落一条记录',
    );

    // ---------------------------------------------------- 4. 新建 8 天计划
    await openTab(tester, TabLabels.cycles);
    await tester.tap(find.byKey(CycleListKeys.addFab));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(AnimalInput).first, '8 天跑步训练');
    // 第一个下拉是周期天数，选 8
    await tester.tap(find.byType(AnimalSelect<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CycleStrings.periodDaysValue(8)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();

    saved = booted.store.snapshot!.data;
    expect(saved.cycles.single.name, '8 天跑步训练');
    expect(saved.cycles.single.periodDays, 8);

    // ------------------------------------ 5. 给第 1 天加任务 → 今日出现实例
    await tester.tap(find.text('8 天跑步训练'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CycleStrings.dayLabel(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CycleDayEditKeys.addTaskButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AnimalInput).first, '慢跑 3 公里');
    await tester.tap(find.byKey(CycleDayEditKeys.confirmAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();
    await goBack(tester); // 回计划列表

    await openTab(tester, TabLabels.today);
    expect(find.text('慢跑 3 公里'), findsOneWidget);
    expect(find.text('8 天跑步训练 · 第 1/8 天'), findsOneWidget);

    // ------------------------------------- 6. 勾选循环实例：不动模板标题
    final templateTitleBefore = booted.store
        .snapshot!.data.cycles.single
        .dayAt(1)
        .sortedTemplates
        .single
        .title;

    await tester.tap(find.byType(AnimalCheckbox<bool>).first);
    await tester.pumpAndSettle();

    saved = booted.store.snapshot!.data;
    expect(
      saved.cycles.single.dayAt(1).sortedTemplates.single.title,
      templateTitleBefore,
      reason: 'PRD 关键规则：勾选循环任务只改当天实例，不改模板',
    );
    expect(
      saved.records.where(
        (e) => e.cycleId != null && e.status == TaskStatus.completed,
      ),
      hasLength(1),
      reason: '勾选只让当天那一条实例变成已完成',
    );
    expect(
      saved.records.where((e) => e.cycleId != null && e.status == TaskStatus.pending),
      isNotEmpty,
      reason: '周期里其它天的实例仍是待办（未来实例会被提前物化）',
    );

    // ------------------------------------------ 7. 导出备份（真实界面）
    final io = FakeBackupIo(savePath: 'C:/tmp/loop_island_backup.json');
    // 重新挂载以获得注入了假 IO 的容器（同一份数据，等价于「应用重启」）
    final restarted = await pumpLoopIslandApp(
      tester,
      store: booted.store,
      today: today,
      now: now,
      notificationService: service,
      extraOverrides: [backupIoProvider.overrideWithValue(io)],
    );
    final beforeExport = restarted.store.snapshot!.data;

    await openSettingsEntry(tester, SettingsKeys.dataEntry);
    await tester.tap(find.byKey(DataKeys.exportEntry));
    await tester.pumpAndSettle();
    expect(find.byKey(ExportKeys.summary), findsOneWidget);

    await tester.tap(find.byKey(ExportKeys.saveToFile));
    await tester.pumpAndSettle();

    expect(io.savedContent, isNotNull, reason: '导出应当写出文件内容');
    expect(io.savedName, contains('loop_island'));
    await goBack(tester); // 回数据管理页
    await goBack(tester); // 回设置页

    // -------------------------------------------------- 8. 清空业务数据
    await openSettingsEntry(tester, SettingsKeys.dataEntry);
    await tester.tap(find.byKey(DataKeys.clearAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.confirm).last);
    await tester.pumpAndSettle();

    var cleared = restarted.store.snapshot!.data;
    expect(cleared.tasks, isEmpty, reason: '业务数据要被清空');
    expect(cleared.cycles, isEmpty);
    expect(cleared.records, isEmpty);
    expect(
      cleared.settings.remindersEnabled,
      beforeExport.settings.remindersEnabled,
      reason: '清空数据要保留设置',
    );
    expect(
      cleared.settings.defaultRemindMinutesOfDay,
      beforeExport.settings.defaultRemindMinutesOfDay,
    );
    await goBack(tester); // 回设置页

    // ---------------------------------------- 9. 导入恢复 → 数据一致
    io
      ..picked = PickedBackup(
        name: 'loop_island_backup.json',
        content: io.savedContent!,
      )
      ..savePath = null;

    await openSettingsEntry(tester, SettingsKeys.dataEntry);
    await tester.tap(find.byKey(DataKeys.importEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ImportKeys.pick));
    await tester.pumpAndSettle();
    expect(find.byKey(ImportKeys.preview), findsOneWidget, reason: '导入前要先预览');
    await tester.tap(find.byKey(ImportKeys.confirm));
    await tester.pumpAndSettle();

    expect(find.byKey(ImportKeys.result), findsOneWidget);

    final restored = restarted.store.snapshot!.data;
    expect(restored.tasks, hasLength(beforeExport.tasks.length));
    expect(restored.tasks.single.title, beforeExport.tasks.single.title);
    expect(restored.tasks.single.remindAts, beforeExport.tasks.single.remindAts);
    expect(restored.cycles.single.name, beforeExport.cycles.single.name);
    expect(restored.cycles.single.periodDays, beforeExport.cycles.single.periodDays);
    expect(restored.records, hasLength(beforeExport.records.length));
    expect(
      restored.settings.defaultRemindMinutesOfDay,
      beforeExport.settings.defaultRemindMinutesOfDay,
    );

    // 恢复后今日页应当又能看到这两条任务
    await goBack(tester);
    await goBack(tester);
    await openTab(tester, TabLabels.today);
    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('慢跑 3 公里'), findsOneWidget);
  });

  testWidgets('重复导入同一份备份是幂等的（合并模式）', (tester) async {
    useLargeSurface(tester);

    final io = FakeBackupIo();
    final booted = await pumpLoopIslandApp(
      tester,
      data: AppData(
        tasks: [makeTask(id: 'task_1', title: '写周报')],
        cycles: [makeCycle(id: 'cycle_1', name: '8 天跑步训练')],
      ),
      today: today,
      now: now,
      extraOverrides: [backupIoProvider.overrideWithValue(io)],
    );

    // 先导出得到一份备份内容
    await openSettingsEntry(tester, SettingsKeys.dataEntry);
    await tester.tap(find.byKey(DataKeys.exportEntry));
    await tester.pumpAndSettle();
    io.savePath = 'C:/tmp/b.json';
    await tester.tap(find.byKey(ExportKeys.saveToFile));
    await tester.pumpAndSettle();
    final content = io.savedContent!;
    await goBack(tester);
    await goBack(tester);

    io.picked = PickedBackup(name: 'b.json', content: content);

    Future<void> importOnce() async {
      await openSettingsEntry(tester, SettingsKeys.dataEntry);
      await tester.tap(find.byKey(DataKeys.importEntry));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ImportKeys.confirm));
      await tester.pumpAndSettle();
      await goBack(tester);
      await goBack(tester);
    }

    await importOnce();
    final afterFirst = booted.store.snapshot!.data;

    await importOnce();
    final afterSecond = booted.store.snapshot!.data;

    expect(afterSecond.tasks, hasLength(afterFirst.tasks.length));
    expect(afterSecond.cycles, hasLength(afterFirst.cycles.length));
    expect(afterSecond.records, hasLength(afterFirst.records.length));
    expect(
      afterSecond.records.map((r) => r.id).toSet(),
      afterFirst.records.map((r) => r.id).toSet(),
      reason: '重复合并同一份备份不该产生新记录',
    );
  });

  testWidgets('到期归档：把「今天」推到结束日之后，计划自动归档且不再提醒', (tester) async {
    useLargeSurface(tester);

    final service = FakeNotificationService();
    final start = DateTime(2026, 9, 12);
    final booted = await pumpLoopIslandApp(
      tester,
      data: AppData(
        cycles: [
          makeCycle(
            id: 'cycle_1',
            name: '短计划',
            periodDays: 2,
            startDate: start,
            endType: CycleEndType.afterCount,
            endCount: 1,
            remindMinuteOfDay: 9 * 60,
          ),
        ],
      ),
      today: start,
      now: DateTime(2026, 9, 12, 10),
      notificationService: service,
    );
    expect(booted.store.snapshot!.data.cycles.single.status, CycleStatus.active);

    // 「第二天」再打开应用：计划已过期 → 自动归档
    await pumpLoopIslandApp(
      tester,
      store: booted.store,
      today: addDays(start, 3),
      now: DateTime(2026, 9, 15, 10),
      notificationService: service,
    );

    final cycle = booted.store.snapshot!.data.cycles.single;
    expect(
      cycle.status,
      CycleStatus.ended,
      reason: '过了结束日应当自动归档（PRD 第 18 条）',
    );
    expect(cycle.endedAt, isNotNull);

    // 归档后再同步提醒：这个计划不该再注册任何通知
    final scheduler = ReminderScheduler(service);
    await scheduler.sync(
      data: booted.store.snapshot!.data,
      settings: booted.store.snapshot!.data.settings,
      now: DateTime(2026, 9, 15, 10),
    );
    expect(
      service.liveIds.where(
        (id) =>
            id == cycleReminderId('cycle_1', addDays(start, 3), 9 * 60),
      ),
      isEmpty,
    );
  });
}
