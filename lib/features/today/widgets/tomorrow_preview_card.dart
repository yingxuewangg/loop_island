import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 明日预览卡片（对应任务 4.5）。
///
/// 只做「明天会有什么」的只读展示：明日日期、明日是某些计划的第几天、
/// 任务标题列表（最多 [maxItems] 条 + 「还有 N 项」）。
class TomorrowPreviewCard extends StatelessWidget {
  const TomorrowPreviewCard({
    super.key,
    required this.view,
    this.maxItems = 5,
    this.onTap,
  });

  final DayView view;

  /// 最多展示几条任务标题。
  final int maxItems;

  /// 点击卡片（例如跳到明日详情）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final entries = view.all;
    final shown = entries.take(maxItems).toList();
    final rest = entries.length - shown.length;
    final labels = view.cycleDayLabels.toSet().toList();

    return IslandCard(
      color: IslandCardColor.warm,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_twilight, size: 18),
              const SizedBox(width: 6),
              Text(
                TodayStrings.tomorrowPreview,
                style: theme.textStyle(size: 15),
              ),
              const Spacer(),
              Text(
                formatFullDate(view.date),
                style: theme.textStyle(
                  size: 12,
                  color: theme.secondaryTextColor,
                ),
              ),
            ],
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final label in labels)
                  IslandTag(
                    colors: IslandTagColors.plan,
                    child: Text(label),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              TodayStrings.noTaskTomorrow,
              style: theme.textStyle(
                size: 13,
                color: theme.secondaryTextColor,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 6),
                          child: Icon(
                            entry.isCycle
                                ? Icons.autorenew
                                : Icons.check_circle_outline,
                            size: 12,
                            color: theme.mutedIconColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyle(size: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (rest > 0)
                  Text(
                    TodayStrings.moreItems(rest),
                    style: theme.textStyle(
                      size: 12,
                      color: theme.secondaryTextColor,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
