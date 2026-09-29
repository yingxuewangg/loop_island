import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/text_input_sheet.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/record_commands.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/features/cycle/widgets/edit_scope_dialog.dart';
import 'package:loop_island/features/reason/reason_sheet.dart';
import 'package:loop_island/features/reason/reason_view.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 某天详情页内可被测试稳定定位的控件键。
abstract final class DayDetailKeys {
  static const list = Key('day-detail-list');
  static const empty = Key('day-detail-empty');

  static Key rename(DateTime date, String entryKey) =>
      Key('day-detail-rename-$entryKey');
}

/// 某天详情页（对应任务 5.8）。
///
/// 三个入口都落到这里：统计页热力图、统计页未完成记录、任务列表的日期标签。
///
/// 能力：
/// - 展示当天所有任务、状态、未完成原因、属于哪个循环计划第几天
/// - 补充 / 修改未完成原因
/// - 改状态（完成 / 未完成 / 跳过）
/// - **循环实例可「仅本次」或「以后所有」改名**（PRD §七）
///
/// 注意：本页**不做每日维护**（那是 `AppShell` 的职责），
/// 只按传入日期读取既有数据 + 纯计算。
class DayDetailPage extends ConsumerWidget {
  const DayDetailPage({super.key, required this.dayKey});

  /// `yyyy-MM-dd`。
  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = parseDayKey(dayKey);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          date == null ? DayStrings.detailTitle : formatFullDate(date),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: date == null
          ? const Center(
              child: AnimalEmpty(description: DayStrings.invalidDate),
            )
          : _DayBody(date: date),
    );
  }
}

class _DayBody extends ConsumerWidget {
  const _DayBody({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);
    final today = ref.watch(todayProvider);
    final asyncData = ref.watch(appDataProvider);

    return asyncData.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: AnimalSkeleton(active: true, rows: 5),
      ),
      error: (error, _) => Center(child: AnimalEmpty(description: '$error')),
      data: (data) {
        final view = buildDayView(data, date, today: today);

        return ListView(
          key: DayDetailKeys.list,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // ---- 当天概况 ----
            if (view.total > 0) ...[
              Text(
                DayStrings.progress(view.completedCount, view.total),
                style: theme.textStyle(size: 13),
              ),
              const SizedBox(height: 10),
              AnimalProgress(value: view.progress ?? 0),
              const SizedBox(height: 20),
            ],

            if (view.isEmpty)
              const Padding(
                key: DayDetailKeys.empty,
                padding: EdgeInsets.symmetric(vertical: 24),
                child: AnimalEmpty(description: DayStrings.noTask),
              )
            else
              for (final entry in view.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EntryCard(entry: entry, date: date, today: today),
                ),
          ],
        );
      },
    );
  }
}

/// 一条任务的详情卡片。
class _EntryCard extends ConsumerWidget {
  const _EntryCard({
    required this.entry,
    required this.date,
    required this.today,
  });

  final DayEntry entry;
  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);
    final completed = entry.isCompleted;

    return IslandCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 标题行 ----
          Row(
            children: [
              AnimalCheckbox<bool>(
                size: AnimalCheckboxSize.middle,
                options: const [
                  AnimalCheckboxOption<bool>(
                    label: SizedBox.shrink(),
                    value: true,
                  ),
                ],
                value: completed ? const [true] : const [],
                onChanged: (_) => _setStatus(
                  ref,
                  completed ? TaskStatus.pending : TaskStatus.completed,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openSource(context, ref),
                  child: Text(
                    entry.title,
                    style: theme.textStyle(
                      size: 15,
                      color:
                          completed ? theme.disabledTextColor : theme.textColor,
                    ).copyWith(
                      decoration: completed ? TextDecoration.lineThrough : null,
                      decorationColor: theme.disabledTextColor,
                    ),
                  ),
                ),
              ),
              IslandTag(
                colors: entry.isCompleted
                    ? IslandTagColors.done
                    : entry.status == TaskStatus.missed
                        ? IslandTagColors.missed
                        : entry.status == TaskStatus.skipped
                            ? IslandTagColors.skipped
                            : IslandTagColors.pending,
                child: Text(entry.status.statusLabel),
              ),
            ],
          ),

          // ---- 来源与提醒 ----
          if (entry.cycleLabel != null ||
              entry.remindAt != null ||
              !entry.isCycle) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (entry.cycleLabel != null)
                  IslandTag(
                    colors: IslandTagColors.plan,
                    child: Text(entry.cycleLabel!),
                  )
                else if (!entry.isCycle)
                  const IslandTag(
                    colors: IslandTagColors.pending,
                    child: Text(DayStrings.unknownCycle),
                  ),
                if (entry.remindAts.isNotEmpty)
                  IslandTag(
                    colors: IslandTagColors.remind,
                    child: Text(
                      TaskStrings.remindTimes(
                        entry.remindAts.map(formatHm).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          // ---- 状态操作 ----
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (entry.status != TaskStatus.pending)
                _Action(
                  label: TodayStrings.complete,
                  onTap: () => _setStatus(ref, TaskStatus.completed),
                ),
              if (entry.status != TaskStatus.missed)
                _Action(
                  label: TodayStrings.markMissed,
                  color: theme.errorColor,
                  onTap: () => _setStatus(ref, TaskStatus.missed),
                ),
              if (entry.status != TaskStatus.skipped)
                _Action(
                  label: TodayStrings.markSkipped,
                  onTap: () => _setStatus(ref, TaskStatus.skipped),
                ),
              // 只有循环实例能就地改名；普通任务点标题进任务编辑页
              if (entry.isCycle)
                _Action(
                  key: DayDetailKeys.rename(date, entry.key),
                  label: DayStrings.renameAction,
                  onTap: () => _rename(context, ref),
                ),
            ],
          ),

          // ---- 未完成原因 ----
          const SizedBox(height: 12),
          ReasonView(
            reason: entry.reason,
            reasonUpdatedAt: _reasonUpdatedAt(ref),
            dense: true,
            onEdit: () => _editReason(context, ref),
          ),
        ],
      ),
    );
  }

  DateTime? _reasonUpdatedAt(WidgetRef ref) {
    final data = ref.appDataOrEmpty;
    final record = findEntryRecord(
      data,
      taskId: entry.templateId ?? entry.key,
      date: date,
      cycleId: entry.cycleId,
    );
    return record?.reasonUpdatedAt;
  }

  Future<void> _setStatus(WidgetRef ref, TaskStatus status) async {
    final notifier = ref.read(appDataProvider.notifier);
    final data = ref.appDataOrEmpty;
    final now = DateTime.now();

    if (!entry.isCycle) {
      await notifier.commit(setTaskStatus(data, entry.key, status, now: now));
      return;
    }

    // 循环实例：勾选只影响当天（PRD 关键规则）
    await notifier.commit(
      editCycleInstance(
        data,
        cycleId: entry.cycleId!,
        templateId: entry.templateId!,
        date: date,
        scope: EditScope.once,
        status: status,
        now: now,
      ),
    );
  }

  Future<void> _editReason(BuildContext context, WidgetRef ref) async {
    final data = ref.appDataOrEmpty;
    final result = await showReasonSheet(context, initial: entry.reason);
    if (result == null || !context.mounted) {
      return;
    }

    await ref.read(appDataProvider.notifier).commit(
          setEntryReason(
            data,
            taskId: entry.templateId ?? entry.key,
            date: date,
            cycleId: entry.cycleId,
            cycleDayIndex: entry.cycleDayIndex,
            reason: result,
            now: DateTime.now(),
          ),
        );
  }

  /// 修改循环实例的名称，范围由用户选择。
  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final data = ref.appDataOrEmpty;

    final scope = await showEditScopeDialog(context);
    if (scope == null || !context.mounted) {
      return;
    }

    final newTitle = await showTextInputSheet(
      context,
      title: DayStrings.renameSheetTitle,
      initial: entry.title,
      hint: DayStrings.renameHint,
    );
    if (newTitle == null || !context.mounted) {
      return;
    }

    await ref.read(appDataProvider.notifier).commit(
          editCycleInstance(
            data,
            cycleId: entry.cycleId!,
            templateId: entry.templateId!,
            date: date,
            scope: scope,
            title: newTitle,
            now: DateTime.now(),
          ),
        );
  }

  /// 点标题：循环实例跳到所属计划，普通任务进任务编辑页。
  void _openSource(BuildContext context, WidgetRef ref) {
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

/// 卡片里的一个小号文字动作。
class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(theme.radiusSmall),
          border: Border.all(color: theme.lightBorderColor),
        ),
        child: Text(
          label,
          style: theme.textStyle(size: 12, color: color ?? theme.textColor),
        ),
      ),
    );
  }
}
