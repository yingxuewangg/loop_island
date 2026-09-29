import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/task_groups.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/features/tasks/widgets/task_tile.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 任务列表页内可被测试稳定定位的控件键。
///
/// 空态按钮与右下角 FAB 的文案相同（都是「新建」），
/// 只用 `find.text` 会命中两个；用 Key 定位才能明确点的是哪一个。
abstract final class TaskListKeys {
  static const addFab = Key('task-list-add-fab');
  static const emptyAddButton = Key('task-list-empty-add');
}

/// Tab 2「任务」：普通 TodoList（对应任务 2.5）。
///
/// 分节顺序：逾期 → 今天 → 明天 → 未安排 → 以后 → 已完成。
///
/// PRD 只要求四组（今天/明天/未安排/已完成）。多出的「逾期」与「以后」
/// 是**为了避免任务从列表里消失** —— 昨天没做完的、下个月才到期的任务，
/// 在四组方案里不属于任何一组。空分节不渲染。
class TaskListPage extends ConsumerWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(appDataProvider);
    final today = ref.watch(todayProvider);

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: asyncData.when(
              loading: () => const _TaskListLoading(),
              error: (error, _) => _TaskListError(error: error),
              data: (data) => _TaskListBody(data: data, today: today),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 20,
            child: IslandPrimaryButton(
              key: TaskListKeys.addFab,
              icon: const Icon(Icons.add),
              onPressed: () => context.pushRoute<void>(AppRoutes.taskEdit),
              child: const Text(TaskStrings.addTask),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskListBody extends StatelessWidget {
  const _TaskListBody({required this.data, required this.today});

  final AppData data;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final groups = groupTasks(data, today);

    final sections = <Widget>[
      if (groups.overdue.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupOverdue,
          tasks: groups.overdue,
          today: today,
          isOverdue: true,
        ),
      if (groups.today.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupToday,
          tasks: groups.today,
          today: today,
        ),
      if (groups.tomorrow.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupTomorrow,
          tasks: groups.tomorrow,
          today: today,
        ),
      if (groups.unscheduled.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupUnscheduled,
          tasks: groups.unscheduled,
          today: today,
        ),
      if (groups.upcoming.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupUpcoming,
          tasks: groups.upcoming,
          today: today,
        ),
      if (groups.completed.isNotEmpty)
        _TaskSection(
          title: TaskStrings.groupCompleted,
          tasks: groups.completed,
          today: today,
        ),
    ];

    if (sections.isEmpty) {
      return Center(
        child: AnimalEmpty(
          description: TaskStrings.emptyList,
          action: IslandPrimaryButton(
            key: TaskListKeys.emptyAddButton,
            icon: const Icon(Icons.add),
            onPressed: () => context.pushRoute<void>(AppRoutes.taskEdit),
            child: const Text(TaskStrings.addTask),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            TabLabels.tasks,
            style: theme.textStyle(size: 20),
          ),
        ),
        ...sections,
      ],
    );
  }
}

/// 一个分节：标题（带数量）+ 任务项。
class _TaskSection extends ConsumerWidget {
  const _TaskSection({
    required this.title,
    required this.tasks,
    required this.today,
    this.isOverdue = false,
  });

  final String title;
  final List<Task> tasks;
  final DateTime today;
  final bool isOverdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              TaskStrings.sectionTitle(title, tasks.length),
              style: theme.textStyle(
                size: 13,
                color: isOverdue ? theme.errorColor : theme.secondaryTextColor,
              ),
            ),
          ),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TaskTile(
                task: task,
                today: today,
                isOverdue: isOverdue,
                onToggle: (completed) => _setStatus(
                  ref,
                  task,
                  completed ? TaskStatus.completed : TaskStatus.pending,
                ),
                onTap: () => context.pushRoute<void>(
                  AppRoutes.taskEdit,
                  arguments: task.id,
                ),
                // 点日期标签进「某天详情」（PRD §五：任务列表点击日期）
                onTapDate: task.resolvedDate(today) == null
                    ? null
                    : () => context
                        .pushDayDetail(dayKey(task.resolvedDate(today)!)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setStatus(
    WidgetRef ref,
    Task task,
    TaskStatus status,
  ) async {
    final notifier = ref.read(appDataProvider.notifier);
    final current = ref.appDataOrEmpty;
    await notifier.commit(
      setTaskStatus(current, task.id, status, now: DateTime.now()),
    );
  }
}

/// 加载骨架。
class _TaskListLoading extends StatelessWidget {
  const _TaskListLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: AnimalSkeleton(active: true, rows: 5),
    );
  }
}

/// 加载失败。
///
/// 不做「静默显示空列表」：那会让用户以为任务丢了，
/// 而实际只是读取失败。这里明确给出错误内容与重试入口。
class _TaskListError extends ConsumerWidget {
  const _TaskListError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimalAlert(
              type: AnimalAlertType.error,
              title: const Text(TaskStrings.loadFailed),
              child: Text(
                '$error',
                style: theme.textStyle(size: 12),
              ),
            ),
            const SizedBox(height: 16),
            AnimalButton(
              onPressed: () => ref.invalidate(appDataProvider),
              child: const Text(CommonStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
