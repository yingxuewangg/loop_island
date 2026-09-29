import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 循环计划卡片（对应任务 3.9）。
///
/// 一张卡片回答四个问题：叫什么、多长周期、现在跑到第几天、什么时候结束。
class CycleCard extends StatelessWidget {
  const CycleCard({
    super.key,
    required this.cycle,
    required this.today,
    required this.onTap,
    this.taskCount,
  });

  final Cycle cycle;
  final DateTime today;
  final VoidCallback onTap;

  /// 计划内任务模板总数（可选，用于「每天任务 N 个」摘要）。
  final int? taskCount;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final status = effectiveStatus(cycle, today: today);
    final dayIndex = cycleDayIndexAt(cycle, today);
    final remaining = remainingCycles(cycle, today);
    final endLabel = endDateLabel(cycle);

    return IslandCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cycle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle(
                    size: 16,
                    color: status == CycleStatus.ended
                        ? theme.disabledTextColor
                        : theme.textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IslandTag(
                colors: _statusColor(status),
                child: Text(status.cycleStatusLabel),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              IslandTag(
                colors: IslandTagColors.pending,
                child: Text(CycleStrings.periodDaysValue(cycle.periodDays)),
              ),
              if (status != CycleStatus.ended && dayIndex != null)
                IslandTag(
                  colors: IslandTagColors.plan,
                  child: Text(
                    CycleStrings.currentDay(dayIndex, cycle.periodDays),
                  ),
                ),
              if (status != CycleStatus.ended && dayIndex == null)
                const IslandTag(
                  colors: IslandTagColors.pending,
                  child: Text(CycleStrings.notStarted),
                ),
              IslandTag(
                colors: endLabel == CycleStrings.neverEnds
                    ? IslandTagColors.pending
                    : IslandTagColors.skipped,
                child: Text(
                  endLabel == CycleStrings.neverEnds
                      ? endLabel
                      : CycleStrings.endDateValue(endLabel),
                ),
              ),
              if (remaining != null)
                IslandTag(
                  colors: remaining == 0
                      ? IslandTagColors.pending
                      : IslandTagColors.done,
                  child: Text(CycleStrings.remainingCycles(remaining)),
                ),
              if (cycle.remindMinuteOfDay != null)
                IslandTag(
                  colors: IslandTagColors.remind,
                  child: Text(
                    CycleStrings.remindAt(
                      formatMinuteOfDay(cycle.remindMinuteOfDay!),
                    ),
                  ),
                ),
            ],
          ),
          if (status != CycleStatus.ended && dayIndex != null) ...[
            const SizedBox(height: 10),
            AnimalProgress(value: dayIndex / cycle.periodDays),
          ],
        ],
      ),
    );
  }

  /// 计划状态 → 标签配色；映射收在 [CycleStatusLabel.cycleStatusColors]。
  TagColors _statusColor(CycleStatus status) => status.cycleStatusColors;
}
