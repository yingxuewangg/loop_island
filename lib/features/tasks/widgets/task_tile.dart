import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 任务列表项（对应任务 2.6）。
///
/// 交互约定（PRD：「点击任务进入详情编辑」「勾选完成」）：
/// - 点勾选框 **只切换完成状态**，不进编辑页；
/// - 点其余区域进编辑页。
///
/// 实现上把点击事件分开挂在两个子树上，而不是整行一个 `onTap` ——
/// 否则容易出现「点勾选框顺手把编辑页也打开了」。
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.today,
    required this.onToggle,
    required this.onTap,
    this.onTapDate,
    this.isOverdue = false,
  });

  final Task task;
  final DateTime today;

  /// 勾选框回调：参数为「勾选后是否已完成」。
  final ValueChanged<bool> onToggle;

  /// 点击任务本体（进编辑页）。
  final VoidCallback onTap;

  /// 点击日期标签（进某天详情）；为空时标签不可点。
  final VoidCallback? onTapDate;

  /// 是否逾期（用于把日期标签标红）。
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final completed = task.isCompleted;

    return IslandCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 勾选框：AnimalCheckbox 是「多选组」组件，这里只放一个选项、
          // label 传空，把它当作单选勾选框使用。
          AnimalCheckbox<bool>(
            size: AnimalCheckboxSize.middle,
            options: const [
              AnimalCheckboxOption<bool>(label: SizedBox.shrink(), value: true),
            ],
            value: completed ? const [true] : const [],
            onChanged: (_) => onToggle(!completed),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyle(
                        size: 15,
                        color: completed
                            ? theme.disabledTextColor
                            : theme.textColor,
                      ).copyWith(
                        decoration:
                            completed ? TextDecoration.lineThrough : null,
                        decorationColor: theme.disabledTextColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _TaskMetaRow(
                      task: task,
                      today: today,
                      isOverdue: isOverdue,
                      onTapDate: onTapDate,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.mutedIconColor,
          ),
        ],
      ),
    );
  }
}

/// 任务项的第二行：日期标签 + 提醒 + 状态。
class _TaskMetaRow extends StatelessWidget {
  const _TaskMetaRow({
    required this.task,
    required this.today,
    required this.isOverdue,
    this.onTapDate,
  });

  final Task task;
  final DateTime today;
  final bool isOverdue;

  /// 点日期标签（进某天详情）。
  final VoidCallback? onTapDate;

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[];

    final resolved = task.resolvedDate(today);
    if (resolved != null) {
      final tag = IslandTag(
        colors: isOverdue
            ? IslandTagColors.missed
            : IslandTagColors.pending,
        child: Text(
          isOverdue
              ? TaskStrings.overdueHint(formatMonthDay(resolved))
              : formatMonthDay(resolved),
        ),
      );
      // 日期标签可点进「某天详情」（PRD §五：任务列表点击日期）
      tags.add(
        onTapDate == null
            ? tag
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapDate,
                child: tag,
              ),
      );
    } else {
      tags.add(
        const IslandTag(
          colors: IslandTagColors.pending,
          child: Text(DateTypeLabels.unscheduled),
        ),
      );
    }

    if (task.remindAts.isNotEmpty) {
      tags.add(
        IslandTag(
          colors: IslandTagColors.remind,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_none, size: 12),
              const SizedBox(width: 3),
              Text(
                TaskStrings.remindTimes(
                  task.remindAts.map(formatHm).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (task.status != TaskStatus.pending && !task.isCompleted) {
      tags.add(
        IslandTag(
          colors: task.status.statusColors,
          child: Text(task.status.statusLabel),
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 4, children: tags);
  }
}
