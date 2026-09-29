import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/missed_records.dart';
import 'package:loop_island/models/app_data.dart';

/// 未完成记录列表（对应任务 5.9）。
///
/// 按日期倒序列出 `missed` 记录，格式：
/// `2026-09-10 跑步：加班，没时间`；原因缺失时显示「未填写原因」。
class MissedRecordsList extends StatelessWidget {
  const MissedRecordsList({
    super.key,
    required this.data,
    this.maxItems = 20,
    this.onTapEntry,
  });

  final AppData data;

  /// 最多展示条数。
  final int maxItems;

  /// 点击某条记录（例如跳到某天详情）。
  final ValueChanged<MissedRecordEntry>? onTapEntry;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final entries = missedEntries(
      data,
      maxItems: maxItems,
      fallbackTitle: StatsStrings.unknownTask,
    );

    if (entries.isEmpty) {
      return const AnimalEmpty(description: StatsStrings.noMissedRecord);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: onTapEntry == null ? null : () => onTapEntry!(entry),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                child: Text(
                  StatsStrings.missedLine(
                    dayKey(entry.date),
                    entry.title,
                    entry.reason,
                  ),
                  style: theme.textStyle(size: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
