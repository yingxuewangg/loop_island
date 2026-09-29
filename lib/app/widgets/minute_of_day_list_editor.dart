import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_picker.dart';
import 'package:loop_island/core/remind_slots.dart';

/// 多时段编辑里可被测试稳定定位的控件键。
abstract final class RemindSlotKeys {
  static const add = Key('remind-slot-add');
  static const limitHint = Key('remind-slot-limit-hint');

  static Key row(int index) => ValueKey('remind-slot-row-$index');
  static Key remove(int index) => ValueKey('remind-slot-remove-$index');
}

/// 「一天内时刻」列表编辑器：一天可以提醒多次。
///
/// 受控组件：对外抛出的永远是**规范化之后**的列表（夹取、去重、升序、
/// 截断到 [kMaxRemindSlots] 个）。三个使用方（任务编辑、计划编辑、提醒设置）
/// 因此不需要各自再算一遍边界，也就不会出现「某处允许加第 6 个」这种不一致。
///
/// 去重是**即时**生效的：把第 2 个时段调成和第 1 个一样时，两行会合并成一行。
/// 这是有意为之 —— 同一个时刻提醒两次没有任何意义，与其等到保存时静默丢一个，
/// 不如当场把结果摆在用户面前。
class MinuteOfDayListEditor extends StatelessWidget {
  const MinuteOfDayListEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  /// 当前时段（一天内分钟数），已规范化。
  final List<int> values;

  final ValueChanged<List<int>> onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final canAdd = enabled && canAddRemindSlot(values.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            key: RemindSlotKeys.row(i),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: MinuteOfDayPicker(
                    minuteOfDay: values[i],
                    enabled: enabled,
                    onChanged: (next) => _replaceAt(i, next),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: RemindSlotKeys.remove(i),
                  // 只剩一个时段时不给删：要「不提醒」请关掉上面的开关，
                  // 留一个空列表在界面上反而让人不知道该点哪里。
                  onPressed:
                      (enabled && values.length > 1) ? () => _removeAt(i) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: TaskStrings.removeRemindTime,
                ),
              ],
            ),
          ),
        const SizedBox(height: 2),
        AnimalButton(
          key: RemindSlotKeys.add,
          icon: const Icon(Icons.add, size: 18),
          onPressed: canAdd ? _append : null,
          child: const Text(TaskStrings.addRemindTime),
        ),
        if (!canAdd && enabled && values.length >= kMaxRemindSlots) ...[
          const SizedBox(height: 6),
          Text(
            TaskStrings.remindSlotLimit,
            key: RemindSlotKeys.limitHint,
            style: theme.textStyle(size: 12, color: theme.secondaryTextColor),
          ),
        ],
      ],
    );
  }

  void _replaceAt(int index, int next) {
    final draft = [...values];
    if (index < 0 || index >= draft.length) {
      return;
    }
    draft[index] = next;
    onChanged(normalizeMinuteSlots(draft));
  }

  void _removeAt(int index) {
    final draft = [...values];
    if (index < 0 || index >= draft.length) {
      return;
    }
    draft.removeAt(index);
    onChanged(normalizeMinuteSlots(draft));
  }

  /// 新时段的默认值：在最后一个时段之后一小时，越界则压到当天最后一个可选项。
  void _append() {
    final base = values.isEmpty ? 9 * 60 : values.last + 60;
    final next = base.clamp(0, 24 * 60 - 1);
    onChanged(normalizeMinuteSlots([...values, next]));
  }
}
