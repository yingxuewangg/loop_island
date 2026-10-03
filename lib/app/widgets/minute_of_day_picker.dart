import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 「一天内时刻」选择器：小时 + 分钟两个下拉。
///
/// 普通任务用绝对时间点（`DateTime`），循环计划用「一天内分钟数」
/// （因为模板没有具体日期）。两者的**选择交互完全一样**，
/// 所以抽到这里，避免两处各写一份、改一处忘一处。
class MinuteOfDayPicker extends StatelessWidget {
  const MinuteOfDayPicker({
    super.key,
    required this.minuteOfDay,
    required this.onChanged,
    this.enabled = true,
    this.minWidth = 88,
    this.minuteStep = 1,
  });

  /// 当前时刻（0..1439）。
  final int minuteOfDay;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final double minWidth;

  /// 分钟粒度（默认 1：0~59 每一分钟都可以选）。
  final int minuteStep;

  @override
  Widget build(BuildContext context) {
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;

    return Row(
      children: [
        AnimalSelect<int>(
          value: hour,
          minWidth: minWidth,
          disabled: !enabled,
          options: [
            for (var h = 0; h < 24; h++)
              AnimalSelectOption<int>(
                key: h,
                label: _hourLabel(h),
              ),
          ],
          onChanged: (value) => onChanged(value * 60 + minute),
        ),
        const SizedBox(width: 10),
        AnimalSelect<int>(
          value: _snap(minute),
          minWidth: minWidth,
          disabled: !enabled,
          options: [
            for (var m = 0; m < 60; m += minuteStep)
              AnimalSelectOption<int>(
                key: m,
                label: '${m.toString().padLeft(2, '0')} 分',
              ),
          ],
          onChanged: (value) => onChanged(hour * 60 + value),
        ),
      ],
    );
  }

  /// 小时下拉的标签：带「凌晨 / 早上 / 中午 / 下午 / 晚上」段位。
  ///
  /// 只写「09 时」在 12 小时制手机上会被当成晚上 9 点（用户真实踩过坑：
  /// 选了 09:35 以为设的是晚上，实际存的是早上，到点自然不响）。
  /// 段位前缀让 09 与 21 一眼可辨；数字部分保留 24 小时制，
  /// 与存储值（0..23）和列表上的展示格式（HH:mm）一致。
  String _hourLabel(int hour) {
    final hh = hour.toString().padLeft(2, '0');
    if (hour < 6) {
      return '凌晨 $hh 时';
    }
    if (hour < 12) {
      return '早上 $hh 时';
    }
    if (hour == 12) {
      return '中午 12 时';
    }
    if (hour < 18) {
      return '下午 $hh 时';
    }
    return '晚上 $hh 时';
  }

  /// 把分钟对齐到粒度上，避免出现下拉里没有的选中值。
  int _snap(int minute) {
    final snapped = (minute / minuteStep).round() * minuteStep;
    return snapped >= 60 ? 60 - minuteStep : snapped;
  }
}

/// 弹出日历选择日期；用户取消时返回 `null`。
///
/// 抽成公共函数的原因：任务的「自定义日期」和循环计划的「起始日 / 结束日」
/// 都要用同一个日历弹层，样式与交互必须一致。
Future<DateTime?> showCalendarSheet(
  BuildContext context, {
  required DateTime initial,
  String? title,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => CalendarSheet(
      initial: initial,
      title: title,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

/// 日历弹层本体（公开出来便于测试直接挂载）。
class CalendarSheet extends StatefulWidget {
  const CalendarSheet({
    super.key,
    required this.initial,
    this.title,
    this.firstDate,
    this.lastDate,
  });

  final DateTime initial;
  final String? title;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<CalendarSheet> {
  late DateTime _selected = dateOnly(widget.initial);

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
              if (widget.title != null) ...[
                Text(widget.title!, style: theme.textStyle(size: 16)),
                const SizedBox(height: 10),
              ],
              AnimalCalendar(
                value: _selected,
                month: _selected,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onChanged: (value) =>
                    setState(() => _selected = dateOnly(value)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AnimalButton(
                      block: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IslandPrimaryButton(
                      
                      block: true,
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('确定'),
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
