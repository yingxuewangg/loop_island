/// 带品牌渐变选中态的底部导航栏。
///
/// `AnimalBottomBar` 的选中图标与文字只能读单色 `theme.primaryColor`，
/// 无渐变参数；这里保持它的布局规格（padding、间距、底部安全区、
/// 图标尺寸、标签字号），只把选中内容包进 `ShaderMask` 使用品牌渐变。
library;

import 'dart:ui' as ui;

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/design_tokens.dart';

class IslandBottomBarItem {
  const IslandBottomBarItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  final Widget icon;
  final Widget label;
  final Widget? activeIcon;
}

class IslandBottomBar extends StatelessWidget {
  const IslandBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.safeAreaBottom = true,
  });

  final List<IslandBottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    final bottom = safeAreaBottom ? MediaQuery.paddingOf(context).bottom : 0.0;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(10, 8, 10, bottom + 8),
          decoration: BoxDecoration(
            // rgba(255,255,255,.78)：让冷蓝背景微微透出。
            color: const Color(0xC7FFFFFF),
            boxShadow: IslandShadows.bottomBar,
          ),
          child: Row(
            children: [
              for (final indexed in items.indexed)
                Expanded(
                  child: _IslandBottomBarButton(
                    item: indexed.$2,
                    selected: indexed.$1 == currentIndex,
                    onTap: () => onChanged(indexed.$1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IslandBottomBarButton extends StatefulWidget {
  const _IslandBottomBarButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final IslandBottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IslandBottomBarButton> createState() => _IslandBottomBarButtonState();
}

class _IslandBottomBarButtonState extends State<_IslandBottomBarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(
            color: widget.selected ? Colors.white : theme.secondaryTextColor,
            size: 23,
          ),
          child: widget.selected
              ? (widget.item.activeIcon ?? widget.item.icon)
              : widget.item.icon,
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textStyle(
            size: 12,
            weight: FontWeight.w600,
            color: widget.selected ? Colors.white : theme.secondaryTextColor,
          ),
          child: widget.item.label,
        ),
      ],
    );

    final selectedContent = widget.selected
        ? ShaderMask(
            shaderCallback: (bounds) => IslandColors.brandGradient.createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: content,
          )
        : content;

    return MouseRegion(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            // 选中项保留原有的淡品牌底色；图标/文字再用渐变高亮。
            color: widget.selected ? IslandColors.brandFaint : Colors.transparent,
            borderRadius: BorderRadius.circular(IslandRadii.small),
            border: Border.all(
              color: widget.selected ? IslandColors.brand : Colors.transparent,
              width: 1,
            ),
          ),
          child: selectedContent,
        ),
      ),
    );
  }
}
