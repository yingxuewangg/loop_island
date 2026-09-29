import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/island_theme_data.dart';
import 'package:loop_island/app/loop_island_app.dart';

/// 「循环小岛」色彩系统 v1.0 的回归测试。
///
/// 钉住关键色值，防止后续有人改主题时把色彩系统带偏；也覆盖
/// [IslandThemeData] 对组件库「暖色偏移派生色」的纠正 ——
/// 那是冷色基准下最容易出问题的地方（不纠正会算出刺眼青色）。
void main() {
  final theme = LoopIslandApp.themeData;

  test('品牌色与辅助色取自色彩系统', () {
    expect(theme.primaryColor, IslandColors.brand);
    expect(theme.primaryHoverColor, IslandColors.brandLight);
    expect(theme.primaryActiveColor, IslandColors.brandDarker);
    expect(theme.primaryBackgroundColor, IslandColors.brandFaint);
    expect(theme.successColor, IslandColors.mint);
    expect(theme.warningColor, IslandColors.sand);
    expect(theme.errorColor, IslandColors.coral);
  });

  test('中性色取自色彩系统', () {
    expect(theme.backgroundColor, IslandColors.bg);
    expect(theme.primaryBackgroundColor, IslandColors.brandFaint);
    expect(theme.textColor, IslandColors.ink900);
    expect(theme.secondaryTextColor, IslandColors.ink500);
    expect(theme.disabledTextColor, IslandColors.ink300);
    expect(theme.borderColor, IslandColors.line);
    expect(theme.lightBorderColor, IslandColors.lineSoft);
    expect(theme.secondaryBackgroundColor, IslandColors.neutralFill);
  });

  test('派生色被纠正为冷调中性色（而非组件库算出的青色）', () {
    expect(theme, isA<IslandThemeData>());
    // 组件库默认公式在冷色背景下会给出 #DFF6F5 / #D6FEFD 这类高饱和青，
    // 这里必须是我们指定的中性色。
    expect(theme.contentBackgroundColor, const Color(0xFFFFFFFF));
    expect(theme.elevatedBackgroundColor, const Color(0xFFFFFFFF));
    expect(theme.controlBorderColor, IslandColors.controlLine);
    expect(theme.bodyTextColor, IslandColors.ink700);
    expect(theme.mutedIconColor, IslandColors.ink300);
    expect(theme.placeholderColor, IslandColors.ink300);
  });

  test('状态标签配色与 semantic 段一致', () {
    expect(IslandTagColors.done.background, const Color(0xFFDDF7EC));
    expect(IslandTagColors.done.foreground, const Color(0xFF1F9D72));
    expect(IslandTagColors.pending.background, const Color(0xFFEAF2F4));
    expect(IslandTagColors.pending.foreground, const Color(0xFF5F7F88));
    expect(IslandTagColors.missed.background, const Color(0xFFFDE8E3));
    expect(IslandTagColors.missed.foreground, const Color(0xFFC9442C));
    expect(IslandTagColors.skipped.background, const Color(0xFFFDF2DF));
    expect(IslandTagColors.skipped.foreground, const Color(0xFFC0842A));
    expect(IslandTagColors.plan.background, const Color(0xFFDCF6FA));
    expect(IslandTagColors.plan.foreground, const Color(0xFF0A7F94));
    expect(IslandTagColors.archived.background, const Color(0xFFEAF2F4));
    expect(IslandTagColors.archived.foreground, const Color(0xFF5F7F88));
  });

  test('只换颜色：尺寸规格遵循第二轮规范', () {
    final fallback = AnimalThemeData.fallback();
    expect(theme.radiusSmall, 10);
    expect(theme.radius, 14);
    expect(theme.radiusLarge, 20);
    expect(theme.borderWidth, fallback.borderWidth);
    expect(theme.heightSmall, fallback.heightSmall);
    expect(theme.height, fallback.height);
    expect(theme.heightLarge, fallback.heightLarge);
    expect(theme.textHeight, fallback.textHeight);
    expect(theme.fontFamily, fallback.fontFamily);
  });
}
