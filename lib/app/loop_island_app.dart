import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:loop_island/app/app_shell.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/island_theme_data.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';

/// 应用根 Widget：负责主题（「循环小岛」色彩系统）、中文本地化与首页装配。
///
/// 主题通过 [MaterialApp.builder] 注入，使**所有路由与浮层**
/// （Dialog / BottomSheet / SnackBar）都能拿到 `AnimalThemeData`，
/// 而不是只有首页生效。
class LoopIslandApp extends StatelessWidget {
  const LoopIslandApp({super.key, this.home});

  /// 首页。默认是四 Tab 外壳；widget 测试传入单个页面即可复用
  /// 同一套主题与本地化配置。
  final Widget? home;

  /// 应用主题：「循环小岛」色彩系统 v1.0（见 `app/design_tokens.dart`）。
  ///
  /// 中性色用冷调的青灰（页面 `#F0F6F7`、文字 `#16323A`…），品牌色取
  /// `#17B5CE`，辅助色为薄荷绿 / 沙洲金 / 珊瑚橙。圆角、字号、字重、
  /// 间距全部沿用组件库默认 —— 本次只替换颜色。
  ///
  /// 外面套一层 [IslandThemeData]：组件库的若干「派生色」是由背景色按
  /// **暖色偏移**插值算出的，冷色基准下会算出刺眼青色（详见该文件注释），
  /// 必须由子类覆写纠正。
  ///
  /// 另注意：组件库还有一部分颜色**不跟随主题**（`AnimalTagColor` 的语义色、
  /// `AnimalCard` 的底色），那些位置由 `app/widgets/island_widgets.dart`
  /// 里的 `IslandCard` / `IslandTag` 渲染，颜色同样取自 design_tokens。
  static final IslandThemeData themeData = IslandThemeData(
    AnimalThemeData.fallback().copyWith(
      // ---- 品牌色 ----
      primaryColor: IslandColors.brand,
      primaryHoverColor: IslandColors.brandLight,
      primaryActiveColor: IslandColors.brandDarker,
      primaryBackgroundColor: IslandColors.brandFaint,
      // ---- 辅助色 ----
      successColor: IslandColors.mint,
      warningColor: IslandColors.sand,
      errorColor: IslandColors.coral,
      // ---- 文字层级 ----
      textColor: IslandColors.ink900,
      secondaryTextColor: IslandColors.ink500,
      disabledTextColor: IslandColors.ink300,
      // ---- 线条 ----
      borderColor: IslandColors.line,
      borderHoverColor: IslandColors.brand,
      lightBorderColor: IslandColors.lineSoft,
      // ---- 面 ----
      backgroundColor: IslandColors.bg,
      secondaryBackgroundColor: IslandColors.neutralFill,
      disabledBackgroundColor: IslandColors.lineSoft,
      // 阴影用主文字色（深青灰）而非纯黑，避免冷色背景上发灰。
      shadowColor: IslandColors.ink900,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,

      // ---- 主题 ----
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeData.primaryColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: themeData.fontFamily,
        fontFamilyFallback: themeData.fontFamilyFallback,
      ),
      builder: (context, child) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: IslandColors.pageBackgroundGradient,
        ),
        child: AnimalTheme(
          data: themeData,
          child: child ?? const SizedBox.shrink(),
        ),
      ),

      // ---- 中文本地化 ----
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: home ?? const AppShell(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
