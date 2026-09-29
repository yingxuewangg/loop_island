import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 今日完成进度（对应任务 4.8）。
///
/// 复用 `AnimalProgress`；**没有任务时不显示 0%**，而是给一句空态文案 ——
/// 「0%」会让用户以为自己没做完什么，其实今天根本没有安排。
class TodayProgress extends StatelessWidget {
  const TodayProgress({super.key, required this.view});

  final DayView view;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final percent = view.progressPercent;

    if (percent == null) {
      return Text(
        TodayStrings.noTaskToday,
        style: theme.textStyle(size: 13, color: theme.secondaryTextColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TodayStrings.progress(view.completedCount, view.total),
          style: theme.textStyle(size: 13),
        ),
        const SizedBox(height: 8),
        // 品牌渐变进度条：AnimalProgress 只支持单色，所以用应用层
        // IslandProgress 保持相同布局并换成 mint → cyan 渐变。
        IslandProgress(value: view.progress!),
      ],
    );
  }
}

/// 今日/明日列表项（对应任务 4.4 / 4.7）。
///
/// 与任务 Tab 的 `TaskTile` 分开的原因：这里要同时承载普通任务与循环实例，
/// 循环实例需要显示「计划名 · 第 x/N 天」并支持跳转到所属计划。
class TodayTaskTile extends StatelessWidget {
  const TodayTaskTile({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onMarkMissed,
    required this.onMarkSkipped,
    required this.onOpen,
  });

  final DayEntry entry;

  /// 勾选 / 取消完成；参数为「勾选后是否已完成」。
  final ValueChanged<bool> onToggle;

  /// 标记未完成。
  final VoidCallback onMarkMissed;

  /// 跳过。
  final VoidCallback onMarkSkipped;

  /// 点击任务本体（循环任务 → 所属计划；普通任务 → 任务编辑页）。
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final completed = entry.isCompleted;
    final label = entry.cycleLabel;

    return IslandCard(
      // 循环任务用淡薄荷面 + 3px 左侧薄荷绿强调条，与普通任务白卡区分。
      color: entry.isCycle
          ? IslandCardColor.mintSurface
          : IslandCardColor.surface,
      accent: entry.isCycle ? IslandColors.mint : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimalCheckbox<bool>(
            size: AnimalCheckboxSize.middle,
            options: const [
              AnimalCheckboxOption<bool>(
                label: SizedBox.shrink(),
                value: true,
              ),
            ],
            value: completed ? const [true] : const [],
            onChanged: (_) => onToggle(!completed),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (label != null)
                          IslandTag(
                            colors: IslandTagColors.plan,
                            child: Text(label),
                          ),
                        if (entry.remindAts.isNotEmpty)
                          IslandTag(
                            colors: IslandTagColors.remind,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.notifications_none, size: 12),
                                const SizedBox(width: 3),
                                Text(
                                  TaskStrings.remindTimes(
                                    entry.remindAts.map(formatHm).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!completed && entry.status != TaskStatus.pending)
                          IslandTag(
                            colors: entry.status == TaskStatus.missed
                                ? IslandTagColors.missed
                                : IslandTagColors.skipped,
                            child: Text(entry.status.statusLabel),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 「未完成 / 跳过」只在还没了结时出现，收进「更多」操作单：
          // 常驻两个按钮紧挨着卡片边缘，滑动列表或想点开任务时极容易
          // 误触，把好好的待办悄悄改成「未完成 / 跳过」—— 用户反馈过
          // 「到点任务自己变成跳过」，误触是最现实的来源；状态只能由
          // 用户**明确**更改。
          if (entry.status == TaskStatus.pending)
            IconButton(
              key: TodayTaskTileKeys.moreActions,
              tooltip: TodayStrings.moreActions,
              icon: Icon(
                Icons.more_horiz,
                size: 20,
                color: theme.secondaryTextColor,
              ),
              onPressed: () => _showActions(context),
            ),
        ],
      ),
    );
  }

  /// 弹出与应用风格一致的操作单（底部弹层 + AnimalCard + 按钮组，
  /// 与日历弹层 / 新增任务弹窗同一套视觉），返回用户选中的状态。
  Future<void> _showActions(BuildContext context) async {
    final status = await showModalBottomSheet<TaskStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskActionsSheet(title: entry.title),
    );
    if (status == TaskStatus.missed) {
      onMarkMissed();
    } else if (status == TaskStatus.skipped) {
      onMarkSkipped();
    }
  }
}

/// 今日任务的操作单：标记未完成 / 跳过。
class _TaskActionsSheet extends StatelessWidget {
  const _TaskActionsSheet({required this.title});

  /// 任务标题，作为操作单的上下文标题。
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: IslandCard(
          color: IslandCardColor.warm,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${TodayStrings.moreActions} · $title',
                style: theme.textStyle(size: 15),
              ),
              const SizedBox(height: 12),
              AnimalButton(
                danger: true,
                block: true,
                onPressed: () =>
                    Navigator.of(context).pop(TaskStatus.missed),
                child: const Text(TodayStrings.markMissed),
              ),
              const SizedBox(height: 10),
              AnimalButton(
                block: true,
                onPressed: () =>
                    Navigator.of(context).pop(TaskStatus.skipped),
                child: const Text(TodayStrings.markSkipped),
              ),
              const SizedBox(height: 10),
              AnimalButton(
                block: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(CommonStrings.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表项内可被测试稳定定位的控件键。
abstract final class TodayTaskTileKeys {
  /// 「更多操作」入口（标记未完成 / 跳过在弹出的操作单里）。
  static const moreActions = Key('today-task-more');
}
