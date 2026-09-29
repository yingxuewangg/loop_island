/// 「循环小岛」色彩系统（v1.1）的应用侧单一来源。
///
/// 为什么需要这个文件，而不是只改 [AnimalThemeData]：
/// 组件库 `animal_island_flutter` 里有一部分颜色是**硬编码常量**，
/// 不跟随主题 —— 具体是 `AnimalTagColor`（除 `primary` 外全部写死）
/// 与 `AnimalCard` 的卡片底色（写死暖米色）。这些位置无法通过改主题
/// 换成新色彩系统，只能在应用层用自己的组件（`IslandTag` / `IslandCard`）
/// 渲染，颜色取自本文件。因此这里既是设计令牌，也是那两个组件的调色板。
///
/// v1.1 相对 v1.0 的变化：**整体提高对比度**（正文/说明文字加深、状态标签
/// 文字加深），并补齐圆角与阴影规范、品牌渐变。
///
/// 颜色只用于本地界面，不涉及任何上传。
library;

import 'package:flutter/material.dart';

/// 一组标签配色（底色 + 文字色）。
///
/// 色彩系统对状态标签只定义了「底色 + 文字」两项；[IslandTag] 为了让
/// 尺寸与组件库的 `AnimalTag` 完全一致（后者有 1.5px 边框），会把边框
/// 取为同底色 —— 视觉上等同于纯色块，但不改变任何尺寸。
@immutable
class TagColors {
  const TagColors(this.background, this.foreground, [this.border]);

  final Color background;
  final Color foreground;

  /// 显式边框色；null 时 [IslandTag] 用底色与文字色的插值（约 22% 强度）。
  ///
  /// 色彩系统 v1.1 要求「进行中 / 循环任务」的边框更明显，仅这一档
  /// 显式指定品牌色；其余标签维持柔和插值边框。
  final Color? border;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagColors &&
          other.background == background &&
          other.foreground == foreground &&
          other.border == border;

  @override
  int get hashCode => Object.hash(background, foreground, border);
}

/// 圆角规范：小卡 10 / 中卡 14 / 大卡 20 / 超大弹层 26。
abstract final class IslandRadii {
  /// 小卡、小控件（标签、小按钮）。
  static const small = 10.0;

  /// 中卡（列表项、输入框）。
  static const medium = 14.0;

  /// 大卡（内容卡片）。
  static const large = 20.0;

  /// 超大弹层（底部弹层、对话框）。
  static const xlarge = 26.0;
}

/// 阴影规范：轻盈、低对比，避免灰蒙蒙。
abstract final class IslandShadows {
  /// 卡片阴影。
  static const card = [
    BoxShadow(
      color: Color(0x0A16323A), // rgba(22,50,58,.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(
      color: Color(0x0E16323A), // rgba(22,50,58,.055)
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// 底部磨砂栏顶部的柔和高光边缘。
  static const bottomBar = [
    BoxShadow(
      color: Color(0x80FFFFFF), // rgba(255,255,255,.5)
      offset: Offset(0, -1),
      blurRadius: 0,
    ),
  ];

  /// 品牌阴影（主按钮等强调元素）。
  static const brand = [
    BoxShadow(
      color: Color(0x4217B5CE), // rgba(23,181,206,.26)
      offset: Offset(0, 8),
      blurRadius: 20,
    ),
  ];

  /// 输入框聚焦光晕：box-shadow: 0 0 0 4px rgba(23,181,206,.15)
  static const focusRing = [
    BoxShadow(
      color: Color(0x2617B5CE), // rgba(23,181,206,.15)
      blurRadius: 0,
      spreadRadius: 4,
    ),
  ];
}

/// 全站色彩令牌。
abstract final class IslandColors {
  // ---------------------------------------------------------------- 品牌色
  /// 主色：按钮、进度条、选中态。
  static const brand = Color(0xFF17B5CE);

  /// 深一档：按下 / 强调。
  static const brandDark = Color(0xFF0E9CB4);

  /// 最深：文字 / 图标。
  static const brandDarker = Color(0xFF0A7F94);

  /// 亮一档：高亮 / 聚焦。
  static const brandLight = Color(0xFF4FD3E4);

  /// 极浅：标签底色。
  static const brandFaint = Color(0xFFDCF6FA);

  // ------------------------------------------------------------------ 辅助色
  /// 薄荷绿：成功 / 循环任务。
  static const mint = Color(0xFF3FCF9E);
  static const mintDark = Color(0xFF2BB486);

  /// 薄荷绿（文字用，比 [mintDark] 更深，保证小字清晰）。
  static const mintInk = Color(0xFF1F9D72);
  static const mintFaint = Color(0xFFDDF7EC);

  /// 循环任务卡片底色（比纯白略偏薄荷，用于区分普通任务）。
  static const mintSurface = Color(0xFFF8FDFB);

  /// 沙洲金：提醒 / 暂停。
  static const sand = Color(0xFFF2C078);
  static const sandDark = Color(0xFFD9A255);

  /// 沙洲金（文字用，更深）。
  static const sandInk = Color(0xFFC0842A);
  static const sandFaint = Color(0xFFFDF2DF);

  /// 珊瑚橙：未完成 / 删除。
  static const coral = Color(0xFFF0816E);
  static const coralDark = Color(0xFFD9553D);

  /// 珊瑚橙（文字用，更深）。
  static const coralInk = Color(0xFFC9442C);
  static const coralFaint = Color(0xFFFDE8E3);

  // ------------------------------------------------------------------ 中性色
  /// 页面背景：冷调浅蓝，顶部半屏更亮、底部过渡为灰蓝。
  static const bg = Color(0xFFD5ECFC);

  /// 页面背景渐变：linear-gradient(180deg, #D5ECFC 50%, #B6CAD8 100%)。
  static const pageBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.5, 1.0],
    colors: [Color(0xFFD5ECFC), Color(0xFFD5ECFC), Color(0xFFB6CAD8)],
  );

  /// 暖背景（暖色区块 / 底部弹层卡片）。
  static const bgWarm = Color(0xFFFBF8F4);

  /// 卡片 / 弹窗。
  static const surface = Color(0xFFFFFFFF);

  /// 分割线（同时用作卡片 1px 描边）。
  static const line = Color(0xFFE3EFF2);

  /// 浅分割线。
  static const lineSoft = Color(0xFFEFF6F8);

  /// 输入框等控件描边（更贴合冷蓝调）。
  static const controlLine = Color(0xFFB0C8DC);

  /// 主文字 / 标题。
  static const ink900 = Color(0xFF16323A);

  /// 正文 / 任务标题（比 v1.0 加深，提高阅读对比度）。
  static const ink700 = Color(0xFF1E3E47);

  /// 说明文字 / 时间（比 v1.0 加深，保证小字可见）。
  static const ink500 = Color(0xFF5C7A82);

  /// 占位 / 禁用。
  static const ink300 = Color(0xFFA9BFC6);

  /// 中性填充（次级背景、骨架屏）。
  static const neutralFill = Color(0xFFEAF2F4);

  /// 进度条背景槽：与新冷蓝背景底部色相近，但稍浅。
  static const progressTrack = Color(0xFFB8D0E0);

  /// 中性标签文字（保留冷色倾向，不用纯灰）。
  static const neutralInk = Color(0xFF5F7F88);

  /// 归档态中性（与 [neutralFill] 同色，色彩系统把二者归为一档）。
  static const neutralArchived = Color(0xFFEAF2F4);

  /// 归档态文字。
  static const archivedInk = Color(0xFF5F7F88);

  // -------------------------------------------------------------------- 渐变
  /// 品牌渐变：薄荷绿 → 主色（120deg ≈ 左上到右下）。
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, brand],
  );

  /// 品牌浅渐变。
  static const brandSoftGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE4F9F1), brandFaint],
  );

  /// 沙洲金渐变。
  static const sandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sandFaint, Color(0xFFFBF0E2)],
  );
}

/// 状态标签配色（对应色彩系统 `semantic` 段）。
///
/// v1.1 把文字色整体加深一档：小字号 + 浅底色时，原值对比度不足、发糊。
abstract final class IslandTagColors {
  /// 已完成 / 打卡成功。
  static const done = TagColors(IslandColors.mintFaint, IslandColors.mintInk);

  /// 待办 / 中性（也在无明确语义的普通标签上复用）。
  static const pending =
      TagColors(IslandColors.neutralFill, IslandColors.neutralInk);

  /// 未完成。
  static const missed =
      TagColors(IslandColors.coralFaint, IslandColors.coralInk);

  /// 跳过 / 暂停（二者在色彩系统里同为沙洲金）。
  static const skipped =
      TagColors(IslandColors.sandFaint, IslandColors.sandInk);

  /// 循环任务 / 进行中（边框显式用品牌色，比插值更明显）。
  static const plan = TagColors(
    IslandColors.brandFaint,
    IslandColors.brandDarker,
    IslandColors.brand,
  );

  /// 已归档。
  static const archived =
      TagColors(IslandColors.neutralArchived, IslandColors.archivedInk);

  /// 提醒时间：色彩系统的 usage 指明沙洲金用于提醒（与 [skipped] 同色）。
  static const remind = skipped;
}
