import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 日期类型选择器（对应任务 2.7）。
///
/// 四选一「今天 / 明天 / 自定义日期 / 无日期」；
/// 选「自定义日期」时展开日历，选中后回调具体日期。
///
/// 是**受控组件**：只通过 [onChanged] 向外抛出 `(dateType, date)`，
/// 自己不持有状态 —— 状态归编辑页统一管理，避免两处状态不一致。
class DateTypePicker extends StatelessWidget {
  const DateTypePicker({
    super.key,
    required this.dateType,
    required this.date,
    required this.today,
    required this.onChanged,
    this.enabled = true,
  });

  final TaskDateType dateType;

  /// 自定义日期；仅 [TaskDateType.custom] 时有意义。
  final DateTime? date;

  /// 「今天」的基准，用于把今天/明天显示成具体日期。
  final DateTime today;

  final void Function(TaskDateType dateType, DateTime? date) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimalSegmented<TaskDateType>(
          value: dateType,
          disabled: !enabled,
          options: const [
            AnimalSegmentedOption(
              value: TaskDateType.today,
              label: Text(DateTypeLabels.today),
            ),
            AnimalSegmentedOption(
              value: TaskDateType.tomorrow,
              label: Text(DateTypeLabels.tomorrow),
            ),
            AnimalSegmentedOption(
              value: TaskDateType.custom,
              label: Text(DateTypeLabels.custom),
            ),
            AnimalSegmentedOption(
              value: TaskDateType.none,
              label: Text(DateTypeLabels.none),
            ),
          ],
          onChanged: (value) {
            switch (value) {
              case TaskDateType.today:
                onChanged(TaskDateType.today, dateOnly(today));
              case TaskDateType.tomorrow:
                onChanged(TaskDateType.tomorrow, addDays(today, 1));
              case TaskDateType.none:
                onChanged(TaskDateType.none, null);
              case TaskDateType.custom:
                // 已有自定义日期就沿用，否则先给今天，用户可再点开日历改
                onChanged(TaskDateType.custom, date ?? dateOnly(today));
            }
          },
        ),
        const SizedBox(height: 10),
        if (dateType == TaskDateType.custom)
          _CustomDateRow(
            date: date ?? dateOnly(today),
            today: today,
            enabled: enabled,
            onPick: (picked) => onChanged(TaskDateType.custom, picked),
          )
        else
          Text(
            _resolvedLabel(),
            style: theme.textStyle(
              size: 13,
              color: theme.secondaryTextColor,
            ),
          ),
      ],
    );
  }

  /// 非自定义类型时给出「实际会落在哪天」的说明，减少用户误解。
  String _resolvedLabel() {
    switch (dateType) {
      case TaskDateType.today:
        return '${formatFullDate(today)} 执行';
      case TaskDateType.tomorrow:
        return '${formatFullDate(addDays(today, 1))} 执行';
      case TaskDateType.none:
        return DateTypeLabels.unscheduled;
      case TaskDateType.custom:
        return '';
    }
  }
}

/// 自定义日期一行：显示当前日期 + 打开日历。
class _CustomDateRow extends StatelessWidget {
  const _CustomDateRow({
    required this.date,
    required this.today,
    required this.enabled,
    required this.onPick,
  });

  final DateTime date;
  final DateTime today;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  Future<void> _openCalendar(BuildContext context) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CalendarSheet(
        initial: date,
        today: today,
      ),
    );
    if (picked != null) {
      onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Row(
      children: [
        IslandTag(
          colors: IslandTagColors.plan,
          child: Text(formatFullDate(date)),
        ),
        const SizedBox(width: 10),
        AnimalButton(
          size: AnimalButtonSize.small,
          disabled: !enabled,
          onPressed: () => _openCalendar(context),
          child: const Text(TaskStrings.customDate),
        ),
        const Spacer(),
        if (isBeforeDay(date, today))
          Text(
            TaskStrings.overdueHint(formatMonthDay(date)),
            style: theme.textStyle(
              size: 12,
              color: theme.errorColor,
            ),
          ),
      ],
    );
  }
}

/// 日历弹层。
class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet({required this.initial, required this.today});

  final DateTime initial;
  final DateTime today;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: IslandCard(
          color: IslandCardColor.warm,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                TaskStrings.customDate,
                style: theme.textStyle(size: 16),
              ),
              const SizedBox(height: 10),
              AnimalCalendar(
                value: _selected,
                month: _selected,
                firstDate: DateTime(widget.today.year - 5),
                lastDate: DateTime(widget.today.year + 10, 12, 31),
                onChanged: (value) => setState(() => _selected = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AnimalButton(
                      block: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(CommonStrings.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IslandPrimaryButton(
                      
                      block: true,
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text(CommonStrings.confirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
