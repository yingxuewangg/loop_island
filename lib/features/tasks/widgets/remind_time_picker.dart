import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/models/settings.dart';

/// 提醒时段选择器（对应任务 2.8；多时段为后续追加需求）。
///
/// PRD 约定：提醒必须依附某一天，所以「无日期任务」时整体禁用并给出说明。
///
/// 受控组件：对外抛出的永远是**完整时间点**列表（所在日期 + 时分），
/// 因为任务提醒最终要落到确定时刻去调度通知。内部只处理「一天内分钟数」，
/// 日期由 [day] 统一提供 —— 这样多时段编辑不必反复问用户「哪一天」。
class RemindTimePicker extends StatelessWidget {
  const RemindTimePicker({
    super.key,
    required this.remindAts,
    required this.day,
    required this.enabled,
    required this.onChanged,
    this.defaultMinuteOfDay = AppSettings.defaultRemindMinute,
    this.now,
  });

  /// 当前提醒时间点列表；空表示不提醒。
  final List<DateTime> remindAts;

  /// 提醒依附的日期；[enabled] 为 false 时可为 null。
  final DateTime? day;

  /// 是否可设置（任务有日期时为 true）。
  final bool enabled;

  final ValueChanged<List<DateTime>> onChanged;

  /// 打开开关时的初始时刻（来自设置里的「默认提醒时段」首个时段）。
  final int defaultMinuteOfDay;

  /// 「当前时刻」，用来识别已经过去的提醒时段。
  ///
  /// 调度器对过去时刻**不会注册通知**（一次性通知在过去只会立刻弹出，
  /// 见 `reminder_scheduler.dart` 的 buildReminders），如果不在界面上把
  /// 这件事讲清楚，就会出现「界面写着提醒、系统里一条通知都没排」的
  /// 静默失效。传 null 则不做该检查。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final baseDay = day ?? dateOnly(DateTime.now());
    final minutes = remindAts.map(minuteOfDay).toList(growable: false);
    final current = now;
    final passedLabels = current == null
        ? const <String>[]
        : remindAts
            .where((at) => !at.isAfter(current))
            .map((at) => formatMinuteOfDay(minuteOfDay(at)))
            .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimalSwitch(
              value: remindAts.isNotEmpty,
              disabled: !enabled,
              onChanged: (on) => onChanged(
                on ? [atMinuteOfDay(baseDay, defaultMinuteOfDay)] : const [],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                remindAts.isEmpty
                    ? TaskStrings.noRemind
                    : TaskStrings.remindTimes(
                        formatMinuteSlots(minutes),
                      ),
                style: theme.textStyle(size: 14),
              ),
            ),
          ],
        ),
        if (!enabled) ...[
          const SizedBox(height: 6),
          Text(
            TaskStrings.remindNeedsDate,
            style: theme.textStyle(
              size: 12,
              color: theme.secondaryTextColor,
            ),
          ),
        ] else if (remindAts.isNotEmpty) ...[
          if (passedLabels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              TaskStrings.remindSlotsPassed(passedLabels),
              style: theme.textStyle(size: 12, color: theme.errorColor),
            ),
          ],
          const SizedBox(height: 12),
          MinuteOfDayListEditor(
            values: minutes,
            onChanged: (next) => onChanged(
              normalizeInstantSlots(
                next.map((minute) => atMinuteOfDay(baseDay, minute)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
