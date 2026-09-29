import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/enums.dart';
// `Record` 与 Dart 3 内置类型同名，必须显式导入模型文件。
import 'package:loop_island/models/record.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 任务历史记录（对应任务 2.11）。
///
/// 输入已经按日期倒序排好的记录（见 `AppData.recordsForTask`），
/// 用 [AnimalTimeline] 呈现：日期 + 状态标签 + 完成时间 + 未完成原因。
///
/// 独立成组件的理由：任务编辑页、某天详情页、统计页都要展示记录，
/// 三处各写一遍很快就会出现「同一个状态三种颜色」的不一致。
class TaskHistoryList extends StatelessWidget {
  const TaskHistoryList({
    super.key,
    required this.records,
    this.emptyDescription,
  });

  /// 历史记录，**按日期倒序**（最近一次在最上面）。
  final List<Record> records;

  /// 空态文案；默认给出「还没有历史记录」。
  final String? emptyDescription;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: AnimalEmpty(
          description: emptyDescription ?? '还没有历史记录',
        ),
      );
    }

    return AnimalTimeline(
      items: [
        for (final record in records)
          AnimalTimelineItem(
            status: timelineStatusOf(record),
            title: Row(
              children: [
                Text(
                  formatFullDate(record.date),
                  style: AnimalTheme.of(context).textStyle(size: 14),
                ),
                const SizedBox(width: 8),
                IslandTag(
                  colors: tagColorOf(record),
                  child: Text(record.status.statusLabel),
                ),
                if (record.rescheduledFrom != null) ...[
                  const SizedBox(width: 6),
                  IslandTag(
                    colors: IslandTagColors.plan,
                    child: Text(
                      '顺延自 ${formatMonthDay(record.rescheduledFrom!)}',
                    ),
                  ),
                ],
              ],
            ),
            time: record.completedAt == null
                ? null
                : Text('${formatHm(record.completedAt!)} 完成'),
            description: record.hasReason
                ? Text(
                    record.reason!,
                    style: AnimalTheme.of(context).textStyle(size: 13),
                  )
                : null,
          ),
      ],
    );
  }
}

/// 记录状态 → 时间线节点状态。
AnimalTimelineItemStatus timelineStatusOf(Record record) {
  switch (record.status) {
    case TaskStatus.completed:
      return AnimalTimelineItemStatus.success;
    case TaskStatus.missed:
      return AnimalTimelineItemStatus.danger;
    case TaskStatus.skipped:
      return AnimalTimelineItemStatus.warning;
    case TaskStatus.pending:
      return AnimalTimelineItemStatus.defaultStatus;
  }
}

/// 记录状态 → 标签配色。
///
/// 直接复用 [TaskStatusLabel.statusColors]（任务列表、某天详情、日历视图
/// 等五处共用同一份映射），这里不再自己写一遍 switch。
TagColors tagColorOf(Record record) => record.status.statusColors;
