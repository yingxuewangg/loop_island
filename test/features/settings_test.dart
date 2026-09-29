import 'dart:io';

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/data/hive_local_store.dart';
import 'package:loop_island/features/settings/about_page.dart';
import 'package:loop_island/features/settings/data_page.dart';
import 'package:loop_island/features/settings/reminder_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/features/stats/stats_page.dart';
import 'package:loop_island/services/app_paths.dart';

import '../support/pump_app.dart';

/// 任务 8.7（设置页 Tab 4）与 8.10（关于 / 隐私说明页）。
void main() {
  final today = DateTime(2026, 9, 12);

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 切到「设置」Tab。
  Future<void> openSettingsTab(WidgetTester tester) async {
    // 非当前 Tab 处于 offstage，finder 默认跳过，必须先切过去
    await tester.tap(find.text(TabLabels.settings).last);
    await tester.pumpAndSettle();
  }

  /// 进设置页并点开某个入口。
  Future<void> openEntry(WidgetTester tester, Key entry) async {
    await openSettingsTab(tester);
    await tester.tap(find.byKey(entry));
    await tester.pumpAndSettle();
  }

  group('8.7 设置页四个分组', () {
    testWidgets('按 提醒 / 统计 / 数据管理 / 关于 的顺序分组列出', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);
      await openSettingsTab(tester);

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      final order = [
        SettingsStrings.sectionReminder,
        SettingsStrings.sectionStats,
        SettingsStrings.sectionData,
        SettingsStrings.sectionAbout,
      ];
      final positions = [for (final label in order) labels.indexOf(label)];

      expect(
        positions.every((p) => p >= 0),
        isTrue,
        reason: '四个分组标题都要出现：$positions',
      );
      expect(
        positions,
        List<int>.from(positions)..sort(),
        reason: '分组顺序必须是 提醒→统计→数据→关于',
      );
    });

    testWidgets('四个入口都能进对应页面，且能返回设置页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);
      await openSettingsTab(tester);

      for (final entry in const [
        SettingsKeys.reminderEntry,
        SettingsKeys.statsEntry,
        SettingsKeys.dataEntry,
        SettingsKeys.aboutEntry,
      ]) {
        expect(find.byKey(entry), findsOneWidget, reason: '$entry 入口要在');
      }

      Future<void> check(Key entry, Type page) async {
        await tester.tap(find.byKey(entry));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget, reason: '$entry 应当进入 $page');
        // 不能用 tester.pageBack()：它按 tooltip `Back` 找返回按钮，
        // 而本应用锁定了 zh_CN，Material 的返回按钮 tooltip 是「返回」。
        await tester.tap(find.byType(BackButton).last);
        await tester.pumpAndSettle();
        expect(find.byKey(SettingsKeys.aboutEntry), findsOneWidget);
      }

      await check(SettingsKeys.reminderEntry, ReminderPage);
      await check(SettingsKeys.statsEntry, StatsPage);
      await check(SettingsKeys.dataEntry, DataPage);
      await check(SettingsKeys.aboutEntry, AboutPage);
    });
  });

  group('8.10 关于 / 隐私说明页', () {
    testWidgets('显示应用名、一句话定位与版本号', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);
      await openEntry(tester, SettingsKeys.aboutEntry);

      expect(find.byKey(AboutKeys.appInfo), findsOneWidget);
      expect(find.text(AppInfo.appName), findsWidgets);
      expect(find.text(AppInfo.appNameEn), findsOneWidget);
      expect(find.text(AboutStrings.positioning), findsOneWidget);
      expect(find.text(AboutStrings.version(AppInfo.version)), findsOneWidget);
    });

    testWidgets('显示数据存储目录与文件名', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        appPaths: const FixedAppPaths('/data/app/loop_island'),
      );
      await openEntry(tester, SettingsKeys.aboutEntry);

      expect(find.byKey(AboutKeys.storage), findsOneWidget);
      expect(find.text(AboutStrings.storageTitle), findsOneWidget);
      expect(find.text('/data/app/loop_island'), findsOneWidget);
      expect(find.text(kStorageFileName), findsOneWidget);
      expect(find.text(AboutStrings.storageHint), findsOneWidget);
    });

    testWidgets('读不到路径时显示「不影响使用」，不弹错误', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(
        tester,
        today: today,
        appPaths: const UnknownAppPaths(),
      );
      await openEntry(tester, SettingsKeys.aboutEntry);

      expect(find.text(AboutStrings.storageUnknown), findsOneWidget);
      expect(find.byType(AnimalAlert), findsNothing);
    });

    testWidgets('隐私说明把四条要点都摆出来', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today);
      await openEntry(tester, SettingsKeys.aboutEntry);

      expect(find.byKey(AboutKeys.privacy), findsOneWidget);
      for (final point in AboutStrings.privacyPoints) {
        expect(find.text(point), findsOneWidget);
      }
      final joined = AboutStrings.privacyPoints.join();
      expect(joined, contains('没有登录'));
      expect(joined, contains('不会上传云端'));
    });

    test('存储文件名与 Hive 的 box 名一致', () {
      expect(kStorageFileName, '${HiveLocalStore.defaultBoxName}.hive');
    });

    test('版本常量与 pubspec.yaml 保持一致', () async {
      // 版本是写死在 AppInfo 里的常量，很容易改一处忘一处；
      // 这条断言把它钉在 pubspec.yaml 上（测试的工作目录是工程根目录）。
      final content = await File('pubspec.yaml').readAsString();
      final line = content
          .split('\n')
          .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
      expect(line, isNotEmpty, reason: 'pubspec.yaml 里应当有 version');
      final version = line.substring('version:'.length).trim().split('+').first;
      expect(AppInfo.version, version);
    });
  });
}
