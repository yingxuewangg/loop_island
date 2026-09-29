import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 日历视图页内可被测试稳定定位的控件键。
abstract final class CalendarViewKeys {
  static const calendar = Key('calendar-view-calendar');
  static const summary = Key('calendar-view-summary');
  static const openDay = Key('calendar-view-open-day');
}

/// 日历视图页（任务 5.11）。
///
/// PRD §四.6 把「日历视图点击某天」列为某天详情的入口之一，
/// 但页面清单里没有对应页面 —— 这一页就是补上它。
///
/// 上：月历；下：选中那天的概要（进度 + 任务清单 + 未完成原因），
/// 点「查看这天详情」进入某天详情页做进一步操作。
class CalendarViewPage extends ConsumerStatefulWidget {
  const CalendarViewPage({super.key, this.initialDate});

  /// 初始选中的日期；为空时取「今天」。
  final DateTime? initialDate;

  @override
  ConsumerState<CalendarViewPage> createState() => _CalendarViewPageState();
}

class _CalendarViewPageState extends ConsumerState<CalendarViewPage> {
  late DateTime _selected;
  late DateTime _month;
  bool _initialized = false;

  void _ensureInit(DateTime today) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _selected = dateOnly(widget.initialDate ?? today);
    _month = monthStart(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    _ensureInit(today);

    final asyncData = ref.watch(appDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(DayStrings.calendarTitle),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AnimalSkeleton(active: true, rows: 6),
        ),
        error: (error, _) => Center(child: AnimalEmpty(description: '$error')),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            IslandCard(
              key: CalendarViewKeys.calendar,
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: AnimalCalendar(
                value: _selected,
                month: _month,
                firstDate: DateTime(today.year - 5),
                lastDate: DateTime(today.year + 10, 12, 31),
                onChanged: (value) => setState(() {
                  _selected = dateOnly(value);
                  _month = monthStart(_selected);
                }),
                onMonthChanged: (value) =>
                    setState(() => _month = monthStart(value)),
              ),
            ),
            const SizedBox(height: 18),
            _DaySummary(
              key: CalendarViewKeys.summary,
              data: data,
              date: _selected,
              today: today,
            ),
            const SizedBox(height: 16),
            IslandPrimaryButton(
              key: CalendarViewKeys.openDay,
              block: true,
              icon: const Icon(Icons.event_note_outlined),
              onPressed: () => context.pushDayDetail(dayKey(_selected)),
              child: const Text(DayStrings.openDayDetail),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中那天的概要：进度 + 任务清单。
class _DaySummary extends StatelessWidget {
  const _DaySummary({
    super.key,
    required this.data,
    required this.date,
    required this.today,
  });

  final AppData data;
  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final view = buildDayView(data, date, today: today);
    final isToday = isSameDay(date, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(formatFullDate(date), style: theme.textStyle(size: 15)),
            if (isToday) ...[
              const SizedBox(width: 8),
              const IslandTag(
                colors: IslandTagColors.plan,
                child: Text(CommonStrings.todayTag),
              ),
            ],
            const Spacer(),
            if (view.total > 0)
              Text(
                DayStrings.progress(view.completedCount, view.total),
                style: theme.textStyle(
                  size: 12,
                  color: theme.secondaryTextColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (view.isEmpty)
          Text(
            DayStrings.noTask,
            style: theme.textStyle(
              size: 13,
              color: theme.disabledTextColor,
            ),
          )
        else
          IslandCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in view.all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 6),
                          child: Icon(
                            entry.isCompleted
                                ? Icons.check_circle
                                : entry.isCycle
                                    ? Icons.autorenew
                                    : Icons.circle_outlined,
                            size: 14,
                            color: entry.isCompleted
                                ? theme.successColor
                                : theme.mutedIconColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyle(
                              size: 13,
                              color: entry.isCompleted
                                  ? theme.disabledTextColor
                                  : theme.textColor,
                            ),
                          ),
                        ),
                        if (entry.status != TaskStatus.pending &&
                            !entry.isCompleted)
                          IslandTag(
                            colors: entry.status == TaskStatus.missed
                                ? IslandTagColors.missed
                                : IslandTagColors.skipped,
                            child: Text(entry.status.statusLabel),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
