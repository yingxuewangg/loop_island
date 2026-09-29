import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/stats.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/features/stats/widgets/heatmap.dart';
import 'package:loop_island/features/stats/widgets/missed_records_list.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 统计页内可被测试稳定定位的控件键。
abstract final class StatsKeys {
  static const list = Key('stats-list');
  static const calendarEntry = Key('stats-calendar-entry');
}

/// 统计页（对应任务 5.6）。
///
/// 布局按 PRD §九：今日 → 连续打卡 → 循环计划 → 最近 90 天热力图 → 未完成记录。
/// 入口在设置页；也直接注册成 `AppRoutes.stats`。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(appDataProvider);
    final today = ref.watch(todayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(StatsStrings.title),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AnimalSkeleton(active: true, rows: 6),
        ),
        error: (error, _) => Center(
          child: AnimalEmpty(description: '$error'),
        ),
        data: (data) => _StatsBody(data: data, today: today),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.data, required this.today});

  final AppData data;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final todayStat = todayProgress(data, today);
    final streak = streaks(data, today);
    final cycles = allCycleProgress(data, today);
    final heatmap = heatmapData(data, endDate: today, today: today, days: 90);

    return ListView(
      key: StatsKeys.list,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ---- 今日 ----
        _Section(
          title: StatsStrings.sectionToday,
          child: _TodaySection(stat: todayStat),
        ),

        // ---- 连续打卡 ----
        _Section(
          title: StatsStrings.sectionStreak,
          child: Row(
            children: [
              Expanded(
                child: AnimalStatistic(
                  title: const Text(StatsStrings.currentStreak),
                  value: streak.current,
                  suffix: const Text('天'),
                ),
              ),
              Expanded(
                child: AnimalStatistic(
                  title: const Text(StatsStrings.longestStreak),
                  value: streak.longest,
                  suffix: const Text('天'),
                ),
              ),
            ],
          ),
        ),

        // ---- 循环计划 ----
        _Section(
          title: StatsStrings.sectionCycles,
          child: cycles.isEmpty
              ? const _Muted(StatsStrings.noRunningCycle)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final stat in cycles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CycleRow(stat: stat),
                      ),
                  ],
                ),
        ),

        // ---- 最近 90 天 ----
        _Section(
          title: StatsStrings.sectionHeatmap,
          child: HeatmapGrid(
            cells: heatmap,
            onDayTap: (date) => context.pushDayDetail(dayKey(date)),
          ),
        ),

        // ---- 日历视图入口 ----
        _Section(
          title: DayStrings.calendarTitle,
          child: _EntryRow(
            key: StatsKeys.calendarEntry,
            title: DayStrings.calendarEntry,
            hint: DayStrings.calendarEntryHint,
            icon: Icons.calendar_month_outlined,
            onTap: () => context.pushRoute<void>(AppRoutes.calendarView),
          ),
        ),

        // ---- 未完成记录 ----
        _Section(
          title: StatsStrings.sectionMissed,
          child: MissedRecordsList(
            data: data,
            onTapEntry: (entry) =>
                context.pushDayDetail(dayKey(entry.date)),
          ),
        ),
      ],
    );
  }
}

/// 今日小节：没有任务时给空态文案，而不是 0%。
class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.stat});

  final ProgressStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    if (!stat.hasTask) {
      return const _Muted(StatsStrings.todayNoTask);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StatsStrings.todaySummary(
            stat.completed,
            stat.total,
            stat.percent ?? 0,
          ),
          style: theme.textStyle(size: 13),
        ),
        const SizedBox(height: 10),
        AnimalProgress(value: stat.rate ?? 0),
      ],
    );
  }
}

/// 一个计划一行：[名称] 第 x/N 天，本周期完成率 y%。
class _CycleRow extends StatelessWidget {
  const _CycleRow({required this.stat});

  final CycleProgressStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final dayIndex = stat.dayIndex ?? 1;
    final percent = stat.progress.percent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${stat.cycleName}：'
          '${percent == null ? StatsStrings.cycleNotStarted(stat.periodDays) : StatsStrings.cycleSummary(dayIndex, stat.periodDays, percent)}',
          style: theme.textStyle(size: 13),
        ),
        if (percent != null) ...[
          const SizedBox(height: 6),
          AnimalProgress(value: stat.progress.rate ?? 0),
        ],
      ],
    );
  }
}

/// 带标题的小节卡片。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textStyle(
                size: 13,
                color: theme.secondaryTextColor,
              ),
            ),
          ),
          IslandCard(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 次要说明文案。
class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    return Text(
      text,
      style: theme.textStyle(size: 13, color: theme.secondaryTextColor),
    );
  }
}

/// 一行可点击的入口（图标 + 标题 + 说明 + 箭头）。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.title,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textStyle(size: 14)),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textStyle(
                    size: 12,
                    color: theme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: theme.mutedIconColor),
        ],
      ),
    );
  }
}
