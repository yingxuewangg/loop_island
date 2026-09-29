import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/app_shell.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/loop_island_app.dart';
import 'package:loop_island/app/routes.dart';

import '../support/pump_app.dart';
import 'package:loop_island/app/widgets/island_bottom_bar.dart';

/// 应用外壳级测试：四 Tab、主题注入、中文本地化、路由表。
///
/// 一律走 `pumpLoopIslandApp` 挂载 —— 直接 `pumpWidget(const LoopIslandApp())`
/// 会缺少 `ProviderScope`，而各 Tab 页面是会读 provider 的真实页面。
void main() {
  group('LoopIslandApp 外壳', () {
    testWidgets('可以正常构建并渲染四 Tab 外壳', (tester) async {
      await pumpLoopIslandApp(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(IslandBottomBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AnimalThemeData 已注入到 Theme 扩展中', (tester) async {
      await pumpLoopIslandApp(tester);

      final context = tester.element(find.byType(AppShell));

      // AnimalTheme.of 在未注入时会静默回落到 fallback，
      // 因此这里断言注入的值就是应用声明的主题（而非 fallback 默认值）。
      expect(Theme.of(context).extension<AnimalThemeData>(), isNotNull);
      expect(
        AnimalTheme.of(context).primaryColor,
        LoopIslandApp.themeData.primaryColor,
      );
      // 「循环小岛」色彩系统：主色为品牌青蓝
      expect(
        AnimalTheme.of(context).primaryColor,
        isNot(const Color(0xFF19C8B9)),
      );
      expect(AnimalTheme.of(context).primaryColor, const Color(0xFF17B5CE));
    });

    testWidgets('默认语言为简体中文', (tester) async {
      await pumpLoopIslandApp(tester);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('zh', 'CN'));
      expect(app.supportedLocales, contains(const Locale('zh', 'CN')));
    });
  });

  group('AppShell 底部 4 Tab', () {
    testWidgets('四个 Tab 标签齐全', (tester) async {
      await pumpLoopIslandApp(tester);

      for (final label in [
        TabLabels.today,
        TabLabels.tasks,
        TabLabels.cycles,
        TabLabels.settings,
      ]) {
        expect(find.text(label), findsWidgets, reason: '缺少 Tab：$label');
      }
    });

    testWidgets('切换 Tab 会切换当前页并保留其余页面状态', (tester) async {
      await pumpLoopIslandApp(tester);

      IndexedStack stack() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack));

      expect(stack().index, 0);

      await tester.tap(find.text(TabLabels.settings).last);
      await tester.pumpAndSettle();
      expect(stack().index, 3);

      await tester.tap(find.text(TabLabels.tasks).last);
      await tester.pumpAndSettle();
      expect(stack().index, 1);

      // IndexedStack 会保留全部子页面，因此不会丢失状态
      expect(stack().children.length, 4);
    });
  });

  group('路由表', () {
    test('8 个二级页路由名齐全且互不重复', () {
      const routes = <String>[
        AppRoutes.taskEdit,
        AppRoutes.cycleDetail,
        AppRoutes.cycleEdit,
        AppRoutes.cycleDayEdit,
        AppRoutes.stats,
        AppRoutes.dayDetail,
        AppRoutes.export,
        AppRoutes.import,
      ];

      expect(routes.length, 8);
      expect(routes.toSet().length, 8, reason: '路由名不可重复');
    });

    testWidgets('未知路由回落到「页面不存在」占位页', (tester) async {
      await pumpLoopIslandApp(tester);

      final context = tester.element(find.byType(AppShell));
      context.pushRoute<void>('/this-route-does-not-exist');
      await tester.pumpAndSettle();

      expect(find.text(RouteStrings.notFound), findsOneWidget);
    });

    testWidgets('已实现的二级页不再走占位页', (tester) async {
      await pumpLoopIslandApp(tester);

      final context = tester.element(find.byType(AppShell));
      context.pushRoute<void>(AppRoutes.taskEdit, arguments: 'task_missing');
      await tester.pumpAndSettle();

      expect(find.text(TaskStrings.editTitleExisting), findsOneWidget);
      expect(find.text(RouteStrings.underConstruction), findsNothing);
    });
  });
}
