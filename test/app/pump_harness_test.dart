import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/loop_island_app.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';
import 'package:loop_island/app/widgets/island_bottom_bar.dart';

/// 验证挂载工具本身可用 —— 否则后面二十多个 widget 测试都会基于一个
/// 有问题的脚手架写断言。
void main() {
  group('pumpLoopIslandApp', () {
    testWidgets('应用能正常渲染，且不会写真实磁盘', (tester) async {
      final result = await pumpLoopIslandApp(tester);

      expect(find.text(TabLabels.today), findsWidgets);
      expect(find.byType(IslandBottomBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(result.store.saveCount, 0, reason: '只挂载不该产生写盘');
    });

    testWidgets('挂载外壳即会加载数据（IndexedStack 会构建全部 Tab 页）', (tester) async {
      final result = await pumpLoopIslandApp(tester);

      // AppShell 的 IndexedStack 会构建四个 Tab 页，其中任务页 watch 了
      // appDataProvider，所以首次挂载就会触发 store.load()。
      expect(result.store.loadCount, 1);

      final data = await result.container.read(appDataProvider.future);
      expect(data.isEmpty, isTrue);
      expect(result.store.loadCount, 1, reason: '重复读取不应二次加载');
    });

    testWidgets('初始数据注入后可被 provider 读到', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: DateTime(2026, 9, 12),
        data: makeAppData(
          tasks: [
            makeTask(
              title: '来自注入数据的任务',
              dateType: TaskDateType.today,
              date: null,
            ),
          ],
        ),
      );

      final data = await result.container.read(appDataProvider.future);
      expect(data.tasks.single.title, '来自注入数据的任务');
    });

    testWidgets('today 会被归一到当天零点（传入带时刻的值也不会泄漏）', (tester) async {
      final result = await pumpLoopIslandApp(
        tester,
        today: DateTime(2026, 9, 12, 18, 30),
      );

      final resolved = result.container.read(todayProvider);
      expect(dayKey(resolved), '2026-09-12');
      expect(resolved.hour, 0);
      expect(resolved.minute, 0);
    });

    testWidgets('不传 today 时取系统当天（归零）', (tester) async {
      final result = await pumpLoopIslandApp(tester);

      final resolved = result.container.read(todayProvider);
      final now = DateTime.now();
      expect(dayKey(resolved), dayKey(now));
      expect(resolved.hour, 0);
    });
  });

  group('pumpWithScope', () {
    testWidgets('子页面也能拿到 AnimalThemeData（与线上同一套主题）', (tester) async {
      final result = await pumpWithScope(tester, const SizedBox.shrink());

      final context = tester.element(find.byType(SizedBox).first);
      expect(Theme.of(context).extension<AnimalThemeData>(), isNotNull);
      expect(
        AnimalTheme.of(context).primaryColor,
        LoopIslandApp.themeData.primaryColor,
      );
      expect(result.store, isNotNull);
    });

    testWidgets('子页面可以读写 provider，改动会落盘', (tester) async {
      final result = await pumpWithScope(
        tester,
        const SizedBox.shrink(),
        today: DateTime(2026, 9, 12),
      );

      await result.container
          .read(appDataProvider.notifier)
          .commit(makeAppData(tasks: [makeTask(title: '提交一条')]));
      await tester.pumpAndSettle();

      expect(result.store.saveCount, 1);
      expect(result.store.snapshot!.data.tasks.single.title, '提交一条');
    });

    testWidgets('默认语言为简体中文', (tester) async {
      await pumpWithScope(tester, const SizedBox.shrink());

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('zh', 'CN'));
    });

    testWidgets('传入的 child 被真实渲染', (tester) async {
      await pumpWithScope(tester, const Text('我是被测页面'));

      expect(find.text('我是被测页面'), findsOneWidget);
    });

    testWidgets('extraOverrides 生效', (tester) async {
      final custom = DateTime(2020, 1, 2);
      final result = await pumpWithScope(
        tester,
        const SizedBox.shrink(),
        today: DateTime(2026, 9, 12),
        extraOverrides: [todayProvider.overrideWithValue(custom)],
      );

      expect(
        result.container.read(todayProvider),
        custom,
        reason: '额外覆写应覆盖 harness 的默认覆写',
      );
    });
  });
}
