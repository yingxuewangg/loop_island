/// 未完成记录的读取与标题解析（纯计算）。
///
/// 单独抽出来的原因：`Record` 只存 `taskId`（普通任务 id 或循环模板 id），
/// 而列表要显示**任务标题**。标题可能来自三处 ——
/// 循环模板、实例级标题覆盖、普通任务 —— 且**模板可能已被删除**。
/// 把这套解析收在一处，统计页 / 某天详情 / 任务详情三处才不会各写一份。
library;

import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';
import 'package:meta/meta.dart';

/// 一条未完成记录，已解析好可展示的标题。
@immutable
class MissedRecordEntry {
  const MissedRecordEntry({
    required this.record,
    required this.title,
    required this.reason,
  });

  final Record record;

  /// 已解析的展示标题（模板可能已被删除，此时为「已删除的任务」）。
  final String title;

  /// 未完成原因；未填写时为 null。
  final String? reason;

  DateTime get date => record.date;

  bool get hasReason => (reason ?? '').trim().isNotEmpty;

  @override
  String toString() => 'MissedRecordEntry(${dayKey(date)}, $title)';
}

/// 解析一条记录对应的展示标题。
///
/// 优先级：实例级标题覆盖 → 循环模板标题 → 普通任务标题 → 占位文案。
String recordDisplayTitle(AppData data, Record record, {String fallback = ''}) {
  final override = record.titleOverride;
  if (override != null && override.trim().isNotEmpty) {
    return override;
  }

  final cycleId = record.cycleId;
  if (cycleId != null) {
    final cycle = data.cycleById(cycleId);
    if (cycle != null) {
      final dayIndex = record.cycleDayIndex;
      if (dayIndex != null) {
        for (final template in cycle.dayAt(dayIndex).templates) {
          if (template.id == record.taskId) {
            return template.title;
          }
        }
      }
    }
    return fallback;
  }

  return data.taskById(record.taskId)?.title ?? fallback;
}

/// 取出所有未完成（`missed`）记录，按日期倒序（最近的在前）。
///
/// [maxItems] 限制条数；传 null 表示不限制。
List<MissedRecordEntry> missedEntries(
  AppData data, {
  int? maxItems,
  String fallbackTitle = '',
}) {
  final entries = <MissedRecordEntry>[];

  for (final record in data.records) {
    if (record.status != TaskStatus.missed) {
      continue;
    }
    entries.add(
      MissedRecordEntry(
        record: record,
        title: recordDisplayTitle(data, record, fallback: fallbackTitle),
        reason: record.hasReason ? record.reason : null,
      ),
    );
  }

  entries.sort((a, b) {
    final byDate = dayNumber(b.date).compareTo(dayNumber(a.date));
    if (byDate != 0) {
      return byDate;
    }
    // 同一天内保持稳定顺序，避免每次重建都跳来跳去
    return a.record.id.compareTo(b.record.id);
  });

  if (maxItems != null && entries.length > maxItems) {
    return List.unmodifiable(entries.take(maxItems));
  }
  return List.unmodifiable(entries);
}
