/// 应用自己的卡片与标签组件（「循环小岛」色彩系统的落地载体）。
///
/// ## 为什么不用组件库的 `AnimalCard` / `AnimalTag`
///
/// `animal_island_flutter` 里这两者的颜色是**硬编码常量**，不跟随
/// `AnimalThemeData`：
/// - `AnimalCard` 的默认底色写死暖米色 `#F7F3DF`；
/// - `AnimalTag` 除 `primary` 外，`success` / `warning` / `danger` /
///   `blue` 等全部写死。
///
/// 也无法通过继承 `AnimalThemeData` 覆写派生色：`ThemeExtension` 的
/// `copyWith` / `lerp` 会返回基类实例，主题插值时子类会丢失。
///
/// 因此这里按「**只换颜色、其余逐字段对齐**」的原则复刻两者的视觉规格：
/// 内边距、圆角、字号、字重、边框宽度、图标尺寸、虚线与交互动效全部与
/// 原组件一致，仅把颜色换成本项目的色彩系统（见 `design_tokens.dart`）。
library;

import 'dart:math' as math;

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loop_island/app/design_tokens.dart';

/// 卡片配色（对应色彩系统的中性色与浅底色）。
enum IslandCardColor {
  /// 白卡片（默认）：内容区、设置项、列表项。
  surface,

  /// 暖背景卡片：底部弹层（与 `bgWarm` 呼应）。
  warm,

  /// 品牌极浅底：提示条、强调块。
  brandFaint,

  /// 薄荷浅底：成功 / 正向提示。
  mintFaint,

  /// 薄荷白面：循环任务卡片（与普通任务的纯白区分开）。
  mintSurface,

  /// 沙洲浅底：提醒 / 暂停提示。
  sandFaint,

  /// 珊瑚浅底：错误 / 危险提示。
  coralFaint,
}

/// 卡片类型（与 `AnimalCardType` 同名同义）。
enum IslandCardType { defaultType, title, dashed }

_IslandCardPalette _paletteOf(IslandCardColor color) {
  return switch (color) {
    IslandCardColor.surface => const _IslandCardPalette(
        IslandColors.surface,
        IslandColors.ink900,
      ),
    IslandCardColor.warm => const _IslandCardPalette(
        IslandColors.bgWarm,
        IslandColors.ink900,
      ),
    IslandCardColor.brandFaint => const _IslandCardPalette(
        IslandColors.brandFaint,
        IslandColors.brandDarker,
      ),
    IslandCardColor.mintFaint => const _IslandCardPalette(
        IslandColors.mintFaint,
        IslandColors.mintInk,
      ),
    IslandCardColor.mintSurface => const _IslandCardPalette(
        IslandColors.mintSurface,
        IslandColors.ink900,
      ),
    IslandCardColor.sandFaint => const _IslandCardPalette(
        IslandColors.sandFaint,
        IslandColors.sandInk,
      ),
    IslandCardColor.coralFaint => const _IslandCardPalette(
        IslandColors.coralFaint,
        IslandColors.coralInk,
      ),
  };
}

class _IslandCardPalette {
  const _IslandCardPalette(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// 卡片：圆角、内边距、悬浮/按下动效与 `AnimalCard` 一致，颜色按色彩系统。
///
/// v1.1 的三点变化：
/// - 圆角统一到规范值（大卡 20，标题卡保留有机形状）；
/// - 加 **1px 实线边框**（`#E3EFF2`）—— 浅青底上仅靠阴影区分卡片不够清晰；
/// - 阴影换成规范的双层轻阴影（`IslandShadows.card`）。
class IslandCard extends StatefulWidget {
  const IslandCard({
    super.key,
    required this.child,
    this.type = IslandCardType.defaultType,
    this.color = IslandCardColor.surface,
    this.padding,
    this.onTap,
    this.accent,
    this.accentWidth = 3,
  });

  final Widget child;
  final IslandCardType type;
  final IslandCardColor color;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 左侧强调边框色；null 表示不画。
  ///
  /// 用于「循环任务卡」—— 色彩系统要求左侧保留 3px 薄荷绿边框，
  /// 与普通任务卡明显区分。
  final Color? accent;

  /// 左侧强调边框宽度（默认 3px）。
  final double accentWidth;

  @override
  State<IslandCard> createState() => _IslandCardState();
}

class _IslandCardState extends State<IslandCard> {
  final _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final palette = _paletteOf(widget.color);
    final isDashed = widget.type == IslandCardType.dashed;
    final isTitle = widget.type == IslandCardType.title;
    final highlighted = _interactive && (_hovered || _focused);
    final yOffset = _interactive
        ? (_pressed
            ? 1.0
            : highlighted && !isDashed
                ? -2.0
                : 0.0)
        : 0.0;

    final borderRadius = isTitle
        ? const BorderRadius.only(
            topLeft: Radius.circular(IslandRadii.xlarge + 14),
            topRight: Radius.circular(IslandRadii.xlarge + 9),
            bottomRight: Radius.circular(IslandRadii.xlarge + 19),
            bottomLeft: Radius.circular(IslandRadii.xlarge + 12),
          )
        : BorderRadius.circular(IslandRadii.large);

    final hasAccent = widget.accent != null && !isDashed;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, yOffset, 0),
      padding: widget.padding ??
          (isTitle
              ? const EdgeInsets.symmetric(horizontal: 32, vertical: 12)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
      decoration: BoxDecoration(
        // 虚线卡片底色比白稍暖一档，与原组件保持一致的黑白对比关系。
        color: isDashed ? IslandColors.lineSoft : palette.background,
        borderRadius: borderRadius,
        // 1px 实线边框：浅青底上仅靠阴影区分卡片不够清晰。
        // 带强调条时左边缘由 accent 负责，这里用透明避免盖住它。
        border: isDashed
            ? null
            : Border.all(
                color: hasAccent ? Colors.transparent : IslandColors.line,
                width: 1,
              ),
        boxShadow: IslandShadows.card,
      ),
      foregroundDecoration: isDashed
          ? ShapeDecoration(
              shape: _DashedRoundedBorder(
                color: highlighted ? IslandColors.brand : IslandColors.line,
                width: 2,
                radius: IslandRadii.large,
              ),
            )
          : null,
      child: DefaultTextStyle.merge(
        style: theme.textStyle(
          size: 14,
          weight: isTitle ? FontWeight.w600 : FontWeight.w500,
          color: palette.foreground,
        ),
        child: widget.child,
      ),
    );

    if (hasAccent) {
      // 左侧 3px 强调条：用 ClipRRect + 细条，保证与卡片圆角贴合。
      card = ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            card,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: widget.accentWidth,
              child: ColoredBox(color: widget.accent!),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: _interactive,
      enabled: _interactive,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        enabled: _interactive,
        mouseCursor:
            _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) {
          if (mounted) {
            setState(() => _focused = value);
          }
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: _interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: _interactive ? (_) => _setHovered(true) : null,
          onExit: _interactive
              ? (_) {
                  _setHovered(false);
                  _setPressed(false);
                }
              : null,
          child: GestureDetector(
            onTapDown: _interactive ? (_) => _setPressed(true) : null,
            onTapUp: _interactive ? (_) => _setPressed(false) : null,
            onTapCancel: _interactive ? () => _setPressed(false) : null,
            onTap: _interactive
                ? () {
                    _focusNode.requestFocus();
                    widget.onTap?.call();
                  }
                : null,
            child: card,
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (mounted && _hovered != value) {
      setState(() => _hovered = value);
    }
  }

  void _setPressed(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }
}

/// 虚线圆角边框（与组件库同名实现一致：实线宽 2、虚线段 6、间隔 12）。
class _DashedRoundedBorder extends ShapeBorder {
  const _DashedRoundedBorder({
    required this.color,
    required this.width,
    required this.radius,
  });

  final Color color;
  final double width;
  final double radius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect.deflate(width),
        Radius.circular(radius),
      ));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect.deflate(width / 2),
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 12;
      }
    }
  }

  @override
  ShapeBorder scale(double t) {
    return _DashedRoundedBorder(
      color: color,
      width: width * t,
      radius: radius * t,
    );
  }
}

/// 标签：内边距、圆角、字号、图标尺寸与 `AnimalTag` 完全一致。
class IslandTag extends StatelessWidget {
  const IslandTag({
    super.key,
    required this.child,
    required this.colors,
    this.size = AnimalTagSize.middle,
    this.icon,
  });

  final Widget child;

  /// 取自 [IslandTagColors] 的语义配色。
  final TagColors colors;

  final AnimalTagSize size;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final metrics = _metricsOf(size);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(metrics.radius),
        border: Border.all(
          // 显式给了边框色就用它（如「进行中」用品牌色，更明显）；
          // 否则按底色与文字色插值，得到柔和的同色系描边。
          color: colors.border ??
              Color.lerp(colors.background, colors.foreground, 0.22)!,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: metrics.padding,
        child: DefaultTextStyle.merge(
          style: theme.textStyle(
            size: metrics.fontSize,
            weight: FontWeight.w700,
            color: colors.foreground,
          ),
          child: IconTheme.merge(
            data:
                IconThemeData(color: colors.foreground, size: metrics.iconSize),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 5),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IslandTagMetrics {
  const _IslandTagMetrics({
    required this.padding,
    required this.radius,
    required this.fontSize,
    required this.iconSize,
  });

  final EdgeInsetsGeometry padding;
  final double radius;
  final double fontSize;
  final double iconSize;
}

_IslandTagMetrics _metricsOf(AnimalTagSize size) {
  return switch (size) {
    AnimalTagSize.small => const _IslandTagMetrics(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        radius: 12,
        fontSize: 11,
        iconSize: 13,
      ),
    AnimalTagSize.middle => const _IslandTagMetrics(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        radius: 16,
        fontSize: 12,
        iconSize: 15,
      ),
    AnimalTagSize.large => const _IslandTagMetrics(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        radius: 18,
        fontSize: 14,
        iconSize: 17,
      ),
  };
}

/// 品牌渐变主按钮。
///
/// 组件库的 `AnimalButton` 装饰是纯色（`_buttonDecoration` 用 `colors.background`），
/// 没有渐变参数，所以渐变必须由应用层组件提供。这里只覆盖**主按钮**这一种
/// 形态：尺寸、内边距、圆角、字号、字重、按下位移与阴影都对齐组件库的
/// `AnimalButtonType.primary`，只把底色换成品牌渐变。
class IslandPrimaryButton extends StatefulWidget {
  const IslandPrimaryButton({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
    this.block = false,
    this.loading = false,
    this.disabled = false,
    this.size = AnimalButtonSize.middle,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool block;
  final bool loading;
  final bool disabled;
  final AnimalButtonSize size;

  @override
  State<IslandPrimaryButton> createState() => _IslandPrimaryButtonState();
}

class _IslandPrimaryButtonState extends State<IslandPrimaryButton> {
  bool _pressed = false;

  bool get _enabled => !widget.disabled && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final metrics = _metricsFor(theme, widget.size);
    // 按下时下沉 2px、阴影收紧；与组件库 primary 的位移一致。
    final yOffset = _enabled && _pressed ? 2.0 : 0.0;

    final labelStyle = theme.textStyle(
      size: metrics.fontSize,
      weight: FontWeight.w600,
      color: Colors.white,
    ).copyWith(overflow: TextOverflow.ellipsis);

    final content = DefaultTextStyle.merge(
      style: labelStyle,
      child: IconTheme.merge(
        data: IconThemeData(color: Colors.white, size: metrics.fontSize + 2),
        child: Row(
          mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!widget.loading && widget.icon != null) ...[
              widget.icon!,
              const SizedBox(width: 8),
            ],
            if (widget.block)
              Flexible(child: widget.child)
            else
              Flexible(
                fit: FlexFit.loose,
                child: DefaultTextStyle.merge(
                  style: labelStyle,
                  maxLines: 1,
                  child: widget.child,
                ),
              ),
          ],
        ),
      ),
    );

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: metrics.height,
      width: widget.block ? double.infinity : null,
      transform: Matrix4.translationValues(0, yOffset, 0),
      padding: metrics.padding,
      decoration: BoxDecoration(
        gradient: IslandColors.brandGradient,
        borderRadius: BorderRadius.circular(metrics.radius),
        boxShadow: _enabled ? IslandShadows.brand : null,
      ),
      child: content,
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: _enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      child: Opacity(opacity: widget.disabled ? 0.5 : 1, child: button),
    );

    if (widget.block) {
      return SizedBox(width: double.infinity, child: interactive);
    }
    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      constrainedAxis: Axis.vertical,
      child: interactive,
    );
  }
}

_IslandButtonMetrics _metricsFor(AnimalThemeData theme, AnimalButtonSize size) {
  return switch (size) {
    AnimalButtonSize.small => _IslandButtonMetrics(
        height: theme.heightSmall,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        radius: IslandRadii.small,
        fontSize: 12,
      ),
    AnimalButtonSize.middle => const _IslandButtonMetrics(
        height: 45,
        padding: EdgeInsets.symmetric(horizontal: 20),
        // 组件库中号按钮用胶囊形（radius 50）；这里改用规范的中圆角，
        // 与全站 10/14/20/26 的圆角语言统一。
        radius: IslandRadii.medium,
        fontSize: 14,
      ),
    AnimalButtonSize.large => _IslandButtonMetrics(
        height: theme.heightLarge,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        radius: IslandRadii.large,
        fontSize: 16,
      ),
  };
}

class _IslandButtonMetrics {
  const _IslandButtonMetrics({
    required this.height,
    required this.padding,
    required this.radius,
    required this.fontSize,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double fontSize;
}

/// 品牌渐变进度条。
///
/// 组件库的 `AnimalProgress` 只接受单个 `Color`，无法渐变；这里按同样的
/// 布局（轨道 + 填充 + 右侧百分比标签）复刻，填充换成品牌渐变。
class IslandProgress extends StatelessWidget {
  const IslandProgress({
    super.key,
    required this.value,
    this.height = 16,
    this.showLabel = true,
  });

  final double value;
  final double height;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final percent = value.clamp(0, 1).toDouble();
    final label = '${(percent * 100).round()}%';

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
              decoration: BoxDecoration(
              color: IslandColors.progressTrack,
              borderRadius: BorderRadius.circular(height),
              border: Border.all(color: IslandColors.line, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: IslandColors.brandGradient,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textStyle(
              size: 13,
              weight: FontWeight.w600,
              color: IslandColors.ink900,
            ),
          ),
        ],
      ],
    );
  }
}

/// 品牌渐变进度圆环（首页顶部）。
///
/// 组件库没有圆环组件，这里用 `CustomPaint` 画：底环 + 品牌渐变进度弧，
/// 中间显示百分比。
class IslandProgressRing extends StatelessWidget {
  const IslandProgressRing({
    super.key,
    required this.value,
    this.size = 76,
    this.strokeWidth = 9,
    this.center,
  });

  final double value;
  final double size;
  final double strokeWidth;

  /// 圆心内容；为 null 时显示百分比。
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final percent = value.clamp(0, 1).toDouble();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          percent: percent,
          strokeWidth: strokeWidth,
          trackColor: IslandColors.neutralFill,
          gradient: IslandColors.brandGradient,
        ),
        child: Center(
          child: center ??
              Text(
                '${(percent * 100).round()}%',
                style: theme.textStyle(
                  size: 15,
                  weight: FontWeight.w700,
                  color: IslandColors.ink900,
                ),
              ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.percent,
    required this.strokeWidth,
    required this.trackColor,
    required this.gradient,
  });

  final double percent;
  final double strokeWidth;
  final Color trackColor;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // 轨道
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (percent <= 0) {
      return;
    }

    // 进度弧：从 12 点方向顺时针
    final sweep = math.pi * 2 * percent;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor;
}
