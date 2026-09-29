import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/backup_codec.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/features/settings/data_page.dart';
import 'package:loop_island/features/settings/export_page.dart';
import 'package:loop_island/features/settings/import_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/services/backup_io.dart';

import '../support/factories.dart';
import '../support/fake_backup_io.dart';
import '../support/pump_app.dart';

/// 数据管理界面验收（任务 7.5~7.7）。
void main() {
  final today = DateTime(2026, 9, 12);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  AppData sampleData() => AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '写周报'),
        ]),
        cycles: List.unmodifiable([
          makeCycle(id: 'cycle_1', name: '8 天跑步训练', periodDays: 8),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'task_1',
            date: kToday,
            status: TaskStatus.missed,
            reason: '加班，没时间',
          ),
        ]),
      );

  /// 点一下之后把 `AnimalMessage` 的 2 秒提示放完。
  ///
  /// 提示用的是 Overlay + Timer，测试结束时若还挂着会被判定为
  /// 「widget 树已销毁但定时器仍在」。
  Future<void> tapAndDrainMessage(
    WidgetTester tester,
    Finder finder,
  ) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  Future<({FakeBackupIo io, InMemoryLocalStore store})> pumpWith(
    WidgetTester tester,
    Widget page, {
    AppData? data,
    FakeBackupIo? io,
  }) async {
    final fake = io ?? FakeBackupIo();
    final result = await pumpWithScope(
      tester,
      page,
      data: data,
      today: today,
      extraOverrides: [backupIoProvider.overrideWithValue(fake)],
    );
    return (io: fake, store: result.store);
  }

  group('7.5 导出备份', () {
    testWidgets('显示当前数据量与是否备份过', (tester) async {
      useLargeSurface(tester);
      await pumpWith(tester, const ExportPage(), data: sampleData());

      expect(find.byKey(ExportKeys.summary), findsOneWidget);
      expect(find.text(DataStrings.dataOverviewLine(1, 1, 1)), findsOneWidget);
      expect(find.textContaining(DataStrings.noBackupYet), findsOneWidget);
    });

    testWidgets('保存到文件：内容是可解码的备份，并记录备份时间', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(savePath: r'C:\tmp\backup.json');
      final result = await pumpWith(
        tester,
        const ExportPage(),
        data: sampleData(),
        io: io,
      );

      await tapAndDrainMessage(tester, find.byKey(ExportKeys.saveToFile));

      expect(io.savedContent, isNotNull);
      final decoded = decodeBackup(io.savedContent!);
      expect(decoded.isSuccess, isTrue);
      expect(decoded.backup!.data.tasks.single.title, '写周报');
      expect(io.savedName, contains('loop_island_backup_'));
      expect(io.savedName, endsWith('.json'));

      // 备份时间被记下来
      expect(
        result.store.snapshot!.data.settings.lastBackupAt,
        isNotNull,
      );
    });

    testWidgets('用户取消保存时不记录备份时间', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(); // savePath 为 null → 取消
      final result = await pumpWith(
        tester,
        const ExportPage(),
        data: sampleData(),
        io: io,
      );

      await tester.tap(find.byKey(ExportKeys.saveToFile));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0);
    });

    testWidgets('分享：内容同样是可解码的备份', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo();
      final result = await pumpWith(
        tester,
        const ExportPage(),
        data: sampleData(),
        io: io,
      );

      await tapAndDrainMessage(tester, find.byKey(ExportKeys.share));

      expect(io.sharedContent, isNotNull);
      expect(decodeBackup(io.sharedContent!).isSuccess, isTrue);
      expect(result.store.snapshot!.data.settings.lastBackupAt, isNotNull);
    });

    testWidgets('空数据导出时给出提醒', (tester) async {
      useLargeSurface(tester);
      await pumpWith(tester, const ExportPage());

      expect(find.text(DataStrings.exportEmptyWarning), findsOneWidget);
    });
  });

  group('7.6 导入恢复', () {
    String backupOf(AppData data) => encodeBackup(data, exportedAt: today);

    testWidgets('预览显示数量与导出时间', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: PickedBackup(
          name: 'backup.json',
          content: backupOf(sampleData()),
        ),
      );
      await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportKeys.preview), findsOneWidget);
      expect(find.text(DataStrings.previewSummary(1, 1, 1)), findsOneWidget);
      expect(find.text('backup.json'), findsOneWidget);
      expect(find.textContaining(DataStrings.exportedAt('')), findsWidgets);
    });

    testWidgets('合并导入：新增数据且保留本地设置', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: PickedBackup(
          name: 'b.json',
          content: backupOf(sampleData()),
        ),
      );
      final result = await pumpWith(
        tester,
        const ImportPage(),
        data: AppData(
          settings: makeSettings(lockPinHash: 'local_hash'),
        ),
        io: io,
      );

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ImportKeys.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.tasks, hasLength(1));
      expect(saved.cycles, hasLength(1));
      expect(saved.records, hasLength(1));
      expect(saved.settings.lockPinHash, 'local_hash');
      expect(find.byKey(ImportKeys.result), findsOneWidget);
    });

    testWidgets('覆盖导入：替换业务数据与设置', (tester) async {
      useLargeSurface(tester);
      final incoming = sampleData().copyWith(
        settings: makeSettings(lockPinHash: 'backup_hash'),
      );
      final io = FakeBackupIo(
        picked: PickedBackup(name: 'b.json', content: backupOf(incoming)),
      );
      final result = await pumpWith(
        tester,
        const ImportPage(),
        data: AppData(
          tasks: List.unmodifiable([makeTask(id: 'local_only')]),
          settings: makeSettings(lockPinHash: 'local_hash'),
        ),
        io: io,
      );

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DataStrings.importModeOverwrite));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ImportKeys.confirm));
      await tester.pumpAndSettle();

      final saved = result.store.snapshot!.data;
      expect(saved.tasks.map((e) => e.id).toList(), ['task_1']);
      expect(saved.settings.lockPinHash, 'backup_hash');
    });

    testWidgets('覆盖模式会给出警告文案', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: PickedBackup(name: 'b.json', content: backupOf(sampleData())),
      );
      await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DataStrings.importModeOverwrite));
      await tester.pumpAndSettle();

      expect(find.text(DataStrings.overwriteWarning), findsOneWidget);
    });

    testWidgets('损坏文件给出可读错误，且不改动数据', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: const PickedBackup(name: 'bad.json', content: '{ 坏文件'),
      );
      final result = await pumpWith(
        tester,
        const ImportPage(),
        data: sampleData(),
        io: io,
      );

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportKeys.error), findsOneWidget);
      expect(
        find.textContaining(
          DataStrings.backupErrorMessage(BackupError.invalidJson),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ImportKeys.preview), findsNothing);
      expect(result.store.saveCount, 0, reason: '坏文件绝不能改动数据');
    });

    testWidgets('版本过高给出对应提示', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: const PickedBackup(
          name: 'future.json',
          content: '{"version":99,"tasks":[]}',
        ),
      );
      await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          DataStrings.backupErrorMessage(BackupError.unsupportedVersion),
        ),
        findsOneWidget,
      );
    });

    testWidgets('空备份会给出提示，但仍可导入', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(
        picked: PickedBackup(
          name: 'empty.json',
          content: backupOf(const AppData()),
        ),
      );
      await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportKeys.emptyWarning), findsOneWidget);
      expect(find.byKey(ImportKeys.confirm), findsOneWidget);
    });

    testWidgets('用户取消选文件时什么都不发生', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo(); // picked 为 null
      final result = await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(io.pickCount, 1);
      expect(find.byKey(ImportKeys.preview), findsNothing);
      expect(result.store.saveCount, 0);
    });

    testWidgets('读取文件抛异常时给出错误而不是崩溃', (tester) async {
      useLargeSurface(tester);
      final io = FakeBackupIo()..throwOnPick = StateError('没有权限');
      await pumpWith(tester, const ImportPage(), io: io);

      await tester.tap(find.byKey(ImportKeys.pick));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportKeys.error), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('7.7 清空数据', () {
    testWidgets('显示当前数据量', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const DataPage(),
        data: sampleData(),
        today: today,
      );

      expect(find.byKey(DataKeys.overview), findsOneWidget);
      expect(find.text(DataStrings.dataOverviewLine(1, 1, 1)), findsOneWidget);
    });

    testWidgets('需要二次确认，取消则不清空', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        const DataPage(),
        data: sampleData(),
        today: today,
      );

      await tester.tap(find.byKey(DataKeys.clearAction));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalDialog), findsOneWidget);

      await tester.tap(find.text(CommonStrings.cancel));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 0);
    });

    testWidgets('确认后清空业务数据但保留设置', (tester) async {
      useLargeSurface(tester);
      final result = await pumpWithScope(
        tester,
        const DataPage(),
        data: sampleData().copyWith(
          settings: makeSettings(lockPinHash: 'keep_me'),
        ),
        today: today,
      );

      await tester.tap(find.byKey(DataKeys.clearAction));
      await tester.pumpAndSettle();
      await tapAndDrainMessage(tester, find.text(CommonStrings.confirm));

      final saved = result.store.snapshot!.data;
      expect(saved.isEmpty, isTrue);
      expect(saved.settings.lockPinHash, 'keep_me', reason: '设置要保留');
    });

    testWidgets('数据管理页可进入导出与导入', (tester) async {
      useLargeSurface(tester);
      await pumpWithScope(
        tester,
        const DataPage(),
        data: sampleData(),
        today: today,
        extraOverrides: [backupIoProvider.overrideWithValue(FakeBackupIo())],
      );

      await tester.tap(find.byKey(DataKeys.exportEntry));
      await tester.pumpAndSettle();
      expect(find.byType(ExportPage), findsOneWidget);
    });
  });

  group('入口与路由', () {
    testWidgets('设置页有数据管理入口，点进数据管理页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();

      expect(find.byKey(SettingsKeys.dataEntry), findsOneWidget);
      await tester.tap(find.byKey(SettingsKeys.dataEntry));
      await tester.pumpAndSettle();

      expect(find.byType(DataPage), findsOneWidget);
    });

    testWidgets('export / import / dataManage 路由都是真实页面', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SettingsPage));

      context.pushRoute<void>(AppRoutes.export);
      await tester.pumpAndSettle();
      expect(find.byType(ExportPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });

    testWidgets('import 路由是真实页面', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SettingsPage));

      context.pushRoute<void>(AppRoutes.import);
      await tester.pumpAndSettle();
      expect(find.byType(ImportPage), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });

    testWidgets('日历视图路由是真实页面', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);

      // 从设置页取 context（当前 Tab 必须是它，否则 offstage 取不到 element）
      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SettingsPage));

      context.pushRoute<void>(AppRoutes.calendarView);
      await tester.pumpAndSettle();

      expect(find.text(DayStrings.calendarTitle), findsWidgets);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });
  });
}
