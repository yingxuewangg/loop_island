import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/features/today/widgets/quick_add_field.dart';
import 'package:loop_island/features/today/widgets/today_progress.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';
import 'package:loop_island/features/today/widgets/tomorrow_preview_card.dart';
import 'package:loop_island/models/enums.dart';

/// 今日页内可被测试稳定定位的控件键。
abstract final class TodayKeys {
  static const list = Key('today-list');
}

/// Tab 1「今日」（对应任务 4.3~4.8）。
///
/// 内容顺序：日期与进度 → 快速添加 → 今日任务（循环任务在前）→ 明日预览。
///
/// 「归档到期计划 + 物化今天的循环实例」这类**每日维护由 `AppShell` 统一负责**
/// （它是唯一 owner），本页只负责展示与交互。
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final today = ref.watch(todayProvider);

    final asyncData = ref.watch(appDataProvider);
    final view = ref.watch(todayViewProvider).asData?.value ??
        DayView(date: dateOnly(today));
    final tomorrow = ref.watch(tomorrowViewProvider).asData?.value;

    return SafeArea(
      child: asyncData.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AnimalSkeleton(active: true, rows: 5),
        ),
        error: (error, _) => Center(
          child: AnimalEmpty(description: '$error'),
        ),
        data: (_) => ListView(
          key: TodayKeys.list,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // ---- 4.3 头部：日期 + 品牌渐变进度圆环 ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    formatFullDate(today),
                    style: theme.textStyle(size: 20),
                  ),
                ),
                if (view.progress != null)
                  IslandProgressRing(
                    value: view.progress!,
                    size: 52,
                    strokeWidth: 6,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TodayProgress(view: view),
            const SizedBox(height: 18),

            // ---- 4.6 快速添加 ----
            QuickAddField(onSubmit: _quickAdd),
            const SizedBox(height: 18),

            // ---- 4.4 今日任务 ----
            if (view.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: AnimalEmpty(description: TodayStrings.noTaskToday),
              )
            else
              for (final entry in view.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TodayTaskTile(
                    entry: entry,
                    onToggle: (completed) => _setStatus(
                      entry,
                      completed ? TaskStatus.completed : TaskStatus.pending,
                    ),
                    onMarkMissed: () => _setStatus(entry, TaskStatus.missed),
                    onMarkSkipped: () => _setStatus(entry, TaskStatus.skipped),
                    onOpen: () => _open(entry),
                  ),
                ),

            // ---- 4.5 明日预览 ----
            if (tomorrow != null) ...[
              const SizedBox(height: 10),
              TomorrowPreviewCard(view: tomorrow),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _quickAdd(String title) async {
    final notifier = ref.read(appDataProvider.notifier);
    final today = ref.read(todayProvider);
    await notifier.commit(
      addTask(
        ref.appDataOrEmpty,
        title: title,
        dateType: TaskDateType.custom,
        date: dateOnly(today),
        now: DateTime.now(),
      ),
    );
  }

  /// 改状态。
  ///
  /// 普通任务走 `setTaskStatus`；循环实例走 `editCycleInstance(scope: once)` ——
  /// 这正是 PRD 的关键规则：**勾选完成只影响当天实例，不修改模板**。
  Future<void> _setStatus(DayEntry entry, TaskStatus status) async {
    final notifier = ref.read(appDataProvider.notifier);
    final data = ref.appDataOrEmpty;
    final now = DateTime.now();

    if (!entry.isCycle) {
      await notifier.commit(setTaskStatus(data, entry.key, status, now: now));
      return;
    }

    await notifier.commit(
      editCycleInstance(
        data,
        cycleId: entry.cycleId!,
        templateId: entry.templateId!,
        date: ref.read(todayProvider),
        scope: EditScope.once,
        status: status,
        now: now,
      ),
    );
  }

  /// 4.7：循环任务跳到所属计划详情；普通任务进任务编辑页。
  void _open(DayEntry entry) {
    if (entry.isCycle) {
      context.pushRoute<void>(
        AppRoutes.cycleDetail,
        arguments: entry.cycleId,
      );
      return;
    }
    context.pushRoute<void>(AppRoutes.taskEdit, arguments: entry.key);
  }
}
