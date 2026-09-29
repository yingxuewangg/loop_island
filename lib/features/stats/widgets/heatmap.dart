import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/stats.dart';

/// 热力图里可被测试定位的控件键。
abstract final class HeatmapKeys {
  static const grid = Key('stats-heatmap-grid');
  static const legend = Key('stats-heatmap-legend');
}

/// 单个格子的 key（按日期）。
Key heatmapCellKey(DateTime date) => Key('heatmap-cell-${dayKey(date)}');

/// 最近 N 天热力图（对应任务 5.7）。
///
/// 布局为 **7 行 × 若干列**（一行是周一~周日，一列是一周），
/// 与 GitHub 贡献图一致；第一列前会用空位补齐，保证星期几不会错位。
///
/// 颜色：档位越深颜色越重；[HeatmapCell.hasTask] 为 false 的日期用浅灰空格，
/// 与「有任务但一个没做」区分开。
class HeatmapGrid extends StatelessWidget {
  const HeatmapGrid({
    super.key,
    required this.cells,
    this.onDayTap,
    this.cellSize = 13,
    this.gap = 3,
  });

  /// 升序的格子数据（见 `heatmapData`）。
  final List<HeatmapCell> cells;

  /// 点击某天。
  final ValueChanged<DateTime>? onDayTap;

  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    if (cells.isEmpty) {
      return const AnimalEmpty(description: StatsStrings.noMissedRecord);
    }

    // 首列从「第一格所在周的周一」开始，前面的日子留空位
    final firstWeekStart = weekStart(cells.first.date);
    final leadingBlanks = daysBetween(firstWeekStart, cells.first.date);
    final totalSlots = leadingBlanks + cells.length;
    final columnCount = (totalSlots + 6) ~/ 7;

    return Column(
      key: HeatmapKeys.grid,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columnCount; column++)
                Padding(
                  padding: EdgeInsets.only(right: gap),
                  child: Column(
                    children: [
                      for (var row = 0; row < 7; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: gap),
                          child: _buildSlot(
                            theme,
                            context,
                            column * 7 + row - leadingBlanks,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Legend(theme: theme),
      ],
    );
  }

  Widget _buildSlot(AnimalThemeData theme, BuildContext context, int index) {
    if (index < 0 || index >= cells.length) {
      return SizedBox(width: cellSize, height: cellSize);
    }

    final cell = cells[index];
    final color = heatmapColor(theme, cell);
    final tooltip = _tooltipFor(cell);

    return AnimalTooltip(
      message: tooltip,
      child: GestureDetector(
        // 每格一个稳定 key：测试可以精确点某一天，
        // 不必依赖「点击整个网格的中心」这种会落在格子间隙上的做法。
        key: heatmapCellKey(cell.date),
        behavior: HitTestBehavior.opaque,
        onTap: onDayTap == null ? null : () => onDayTap!(cell.date),
        child: Semantics(
          label: tooltip,
          button: onDayTap != null,
          child: Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  String _tooltipFor(HeatmapCell cell) {
    final date = dayKey(cell.date);
    if (!cell.hasTask) {
      return '$date · 无任务';
    }
    return '$date · 完成 ${cell.completed}/${cell.total}';
  }
}

/// 档位 → 颜色。
///
/// 暴露成顶层函数是为了让「无任务」与「0%」的取色差异只有一处定义。
Color heatmapColor(AnimalThemeData theme, HeatmapCell cell) {
  if (!cell.hasTask) {
    return theme.disabledBackgroundColor;
  }
  switch (cell.level) {
    case 0:
      // 有任务但一个没做：比「无任务」略深一点，能看出「这天有安排」
      return theme.lightBorderColor;
    case 1:
      return theme.primaryColor.withValues(alpha: 0.30);
    case 2:
      return theme.primaryColor.withValues(alpha: 0.55);
    case 3:
      return theme.primaryColor.withValues(alpha: 0.78);
    default:
      return theme.primaryColor;
  }
}

/// 图例：少 → 多。
class _Legend extends StatelessWidget {
  const _Legend({required this.theme});

  final AnimalThemeData theme;

  @override
  Widget build(BuildContext context) {
    final sample = HeatmapCell(
      date: DateTime(2026),
      total: 1,
      completed: 1,
      level: 1,
    );

    return Row(
      key: HeatmapKeys.legend,
      children: [
        Text(
          StatsStrings.heatmapLess,
          style: theme.textStyle(size: 11, color: theme.secondaryTextColor),
        ),
        const SizedBox(width: 6),
        for (var level = 0; level <= 4; level++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: heatmapColor(
                  theme,
                  HeatmapCell(
                    date: sample.date,
                    total: level == 0 ? 0 : 1,
                    completed: level == 0 ? 0 : 1,
                    level: level,
                  ),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        const SizedBox(width: 3),
        Text(
          StatsStrings.heatmapMore,
          style: theme.textStyle(size: 11, color: theme.secondaryTextColor),
        ),
      ],
    );
  }
}
