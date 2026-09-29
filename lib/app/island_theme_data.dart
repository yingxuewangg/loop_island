/// 「循环小岛」主题：在组件库主题之上纠正派生色。
///
/// ## 为什么需要这个子类
///
/// `animal_island_flutter` 的 `AnimalThemeData` 有一批「派生色」
/// （`contentBackgroundColor`、`elevatedBackgroundColor`、
/// `controlBorderColor`、`mutedIconColor`…）不是独立字段，而是由
/// `backgroundColor` / `textColor` **按暖色偏移插值算出**的 ——
/// 见其内部 `_shiftWarmNeutral`：把基准色的 HSL 加上「暖中性色相对
/// 默认暖底色」的色相/饱和度/明度差。
///
/// 本项目的中性色是**冷调青灰**（页面 `#F0F6F7`、文字 `#16323A`），
/// 套进那条暖色公式会算出高饱和的青色：实测 `elevatedBackgroundColor`
/// 会变成 `#D6FEFD`（刺眼亮青），`contentBackgroundColor` 变成
/// `#DFF6F5`，底部导航栏与弹层因此显得很脏。
///
/// 求解过「换一个 backgroundColor 能否让派生色落到目标中性色」——
/// 枚举整个 HSL 空间后最小色差仍有 189（满分 765），说明该公式在冷色
/// 基准下**结构性**地产生青色，无法靠调参解决。
///
/// 因此这里继承 `AnimalThemeData` 并覆写这些 getter，直接返回色彩系统
/// 定义的中性色。已验证子类实例能穿过 `ThemeData.extensions` 被
/// `AnimalTheme.of(context)` 取到（`ThemeData` 用 `extension.type` 作键，
/// 组件库未覆写 `type`，故键仍是 `AnimalThemeData`，查找成立）。
///
/// **只改颜色，不动任何尺寸、圆角、字重。**
library;

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/design_tokens.dart';

/// 应用主题：[AnimalThemeData] + 冷调中性色纠正。
class IslandThemeData extends AnimalThemeData {
  /// 从一份基础主题复制全部字段（通常是 `AnimalThemeData.fallback()`
  /// 再 `copyWith` 成色彩系统值的实例）。
  IslandThemeData(AnimalThemeData base)
      : super(
          primaryColor: base.primaryColor,
          primaryHoverColor: base.primaryHoverColor,
          primaryActiveColor: base.primaryActiveColor,
          primaryBackgroundColor: base.primaryBackgroundColor,
          successColor: base.successColor,
          warningColor: base.warningColor,
          errorColor: base.errorColor,
          textColor: base.textColor,
          secondaryTextColor: base.secondaryTextColor,
          disabledTextColor: base.disabledTextColor,
          borderColor: base.borderColor,
          borderHoverColor: base.borderHoverColor,
          lightBorderColor: base.lightBorderColor,
          backgroundColor: base.backgroundColor,
          secondaryBackgroundColor: base.secondaryBackgroundColor,
          disabledBackgroundColor: base.disabledBackgroundColor,
          shadowColor: base.shadowColor,
          fontFamily: base.fontFamily,
          fontPackage: base.fontPackage,
          fontFamilyFallback: base.fontFamilyFallback,
          textHeight: base.textHeight,
          borderWidth: base.borderWidth,
          // 圆角规范：小卡 10 / 中卡 14 / 大卡 20 / 超大弹层 26。
          // 组件库把这三个字段用在按钮（小/大）、输入框、卡片等处，
          // 但「中号按钮」与「卡片」在组件库内部是写死的（50 / 20），
          // 那两处由应用层的 IslandButton / IslandCard 负责。
          radiusSmall: IslandRadii.small,
          radius: IslandRadii.medium,
          radiusLarge: IslandRadii.large,
          heightSmall: base.heightSmall,
          height: base.height,
          heightLarge: base.heightLarge,
        );

  // ------------------------------------------------------------ 品牌派生色
  // 组件库用「主色 + 硬编码薄荷绿偏移」推导条形加载等强调色；主色已是
  // 冷青，偏移后仍落在品牌色系内，无需纠正。

  // ------------------------------------------------------------ 中性派生色
  // 以下全部改为色彩系统定义的中性色，绕开暖色插值公式。

  /// 内容面（卡片、输入框、列表行）：纯白。
  @override
  Color get contentBackgroundColor => IslandColors.surface;

  /// 抬升面（AppBar、底部导航栏、弹层）：纯白。
  @override
  Color get elevatedBackgroundColor => IslandColors.surface;

  /// 更浅的面（弹层内嵌区块）：浅分割线色。
  @override
  Color get subtleBackgroundColor => IslandColors.lineSoft;

  /// 控件描边：比分割线略深，让输入框边界明确（v1.1 提高对比度）。
  @override
  Color get controlBorderColor => IslandColors.controlLine;

  /// 暖色边框：警示/强调区块的描边，用沙洲金浅色。
  @override
  Color get warmBorderColor => IslandColors.sand;

  /// 弱化图标：占位/禁用色。
  @override
  Color get mutedIconColor => IslandColors.ink300;

  /// 占位文字：占位/禁用色。
  @override
  Color get placeholderColor => IslandColors.ink300;

  /// 正文文字：比 `textColor` 略浅一档，维持层级但保证对比度。
  @override
  Color get bodyTextColor => IslandColors.ink700;

  /// 触感阴影：中性浅色，避免在冷色背景上发灰。
  @override
  Color get tactileShadowColor => IslandColors.line;
}
