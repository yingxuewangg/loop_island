import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 计划详情页（对应任务 3.11）。
///
/// 内容：状态与关键信息、第 1~N 天列表（点击进某天编辑）、
/// 以及启用/暂停、编辑、复制、删除四个操作。
class CycleDetailPage extends ConsumerWidget {
  const CycleDetailPage({super.key, required this.cycleId});

  final String cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final asyncData = ref.watch(appDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(CycleStrings.detailTitle),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Center(child: AnimalLoading()),
        error: (error, _) => Center(child: AnimalEmpty(description: '$error')),
        data: (data) {
          final cycle = data.cycleById(cycleId);
          if (cycle == null) {
            return const Center(
              child: AnimalEmpty(description: CycleStrings.noCycle),
            );
          }
          return _DetailBody(cycle: cycle, today: today);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.cycle, required this.today});

  final Cycle cycle;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);
    final status = effectiveStatus(cycle, today: today);
    final dayIndex = cycleDayIndexAt(cycle, today);
    final remaining = remainingCycles(cycle, today);
    final end = resolveEndDate(cycle);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ---- 概览 ----
        IslandCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cycle.name, style: theme.textStyle(size: 18)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  IslandTag(
                    colors: _statusColor(status),
                    child: Text(status.cycleStatusLabel),
                  ),
                  IslandTag(
                    colors: IslandTagColors.pending,
                    child: Text(CycleStrings.periodDaysValue(cycle.periodDays)),
                  ),
                  if (dayIndex != null && status != CycleStatus.ended)
                    IslandTag(
                      colors: IslandTagColors.plan,
                      child: Text(
                        CycleStrings.currentDay(dayIndex, cycle.periodDays),
                      ),
                    ),
                  IslandTag(
                    colors: IslandTagColors.pending,
                    child: Text(
                      CycleStrings.startDateValue(dayKey(cycle.startDate)),
                    ),
                  ),
                  IslandTag(
                    colors: IslandTagColors.skipped,
                    child: Text(
                      end == null
                          ? CycleStrings.neverEnds
                          : CycleStrings.endDateValue(dayKey(end)),
                    ),
                  ),
                  if (remaining != null)
                    IslandTag(
                      colors: remaining == 0
                          ? IslandTagColors.pending
                          : IslandTagColors.done,
                      child: Text(CycleStrings.remainingCycles(remaining)),
                    ),
                  if (isTruncated(cycle))
                    const IslandTag(
                      colors: IslandTagColors.skipped,
                      child: Text('最后一轮不完整'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${CycleStrings.fieldRemindTime}：'
                '${cycle.remindLabel ?? CycleStrings.noRemind}',
                style: theme.textStyle(
                  size: 13,
                  color: theme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ---- 第 1~N 天 ----
        Text(CycleStrings.dayListTitle, style: theme.textStyle(size: 15)),
        const SizedBox(height: 10),
        for (var i = 1; i <= cycle.periodDays; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DayRow(
              cycleId: cycle.id,
              day: cycle.dayAt(i),
              isCurrent:
                  status != CycleStatus.ended && dayIndex == i,
            ),
          ),
        const SizedBox(height: 20),

        // ---- 操作 ----
        Text(CommonStrings.edit, style: theme.textStyle(size: 15)),
        const SizedBox(height: 10),
        _Actions(cycle: cycle, today: today, status: status),
      ],
    );
  }

  /// 计划状态 → 标签配色；映射收在 [CycleStatusLabel.cycleStatusColors]。
  TagColors _statusColor(CycleStatus status) => status.cycleStatusColors;
}

/// 一天一行：编号 + 休息日/任务预览。
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.cycleId,
    required this.day,
    required this.isCurrent,
  });

  final String cycleId;
  final CycleDay day;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return IslandCard(
      onTap: () => context.pushCycleDayEdit(
        cycleId: cycleId,
        dayIndex: day.dayIndex,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              CycleStrings.dayLabel(day.dayIndex),
              style: theme.textStyle(
                size: 13,
                color: isCurrent ? theme.primaryColor : theme.textColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day.isRestDay)
                  const IslandTag(
                    colors: IslandTagColors.remind,
                    child: Text(CycleStrings.restDay),
                  )
                else if (day.isEmpty)
                  Text(
                    CycleStrings.dayTaskCount(0),
                    style: theme.textStyle(
                      size: 13,
                      color: theme.disabledTextColor,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final template in day.sortedTemplates)
                        IslandTag(
                          colors: IslandTagColors.pending,
                          child: Text(
                            template.remindLabel == null
                                ? template.title
                                : '${template.remindLabel} ${template.title}',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.mutedIconColor,
          ),
        ],
      ),
    );
  }
}

/// 操作区：启用/暂停、编辑、复制、删除。
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.cycle,
    required this.today,
    required this.status,
  });

  final Cycle cycle;
  final DateTime today;
  final CycleStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);
    final resumable = canResume(cycle, today);
    final isEnded = status == CycleStatus.ended;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == CycleStatus.active)
          AnimalButton(
            block: true,
            icon: const Icon(Icons.pause),
            onPressed: () => _commit(
              ref,
              pauseCycle(_data(ref), cycle.id, now: DateTime.now()),
            ),
            child: const Text(CycleStrings.actionPause),
          )
        else
          AnimalButton(
            block: true,
            // 已结束不可恢复：禁用按钮而不是让它点了没反应
            disabled: !resumable,
            icon: const Icon(Icons.play_arrow),
            onPressed: resumable
                ? () => _commit(
                      ref,
                      resumeCycle(_data(ref), cycle.id, now: DateTime.now()),
                    )
                : null,
            child: const Text(CycleStrings.actionResume),
          ),
        if (isEnded) ...[
          const SizedBox(height: 6),
          Text(
            CycleStrings.endedCannotResume,
            style: theme.textStyle(size: 12, color: theme.secondaryTextColor),
          ),
        ],
        const SizedBox(height: 10),
        AnimalButton(
          block: true,
          icon: const Icon(Icons.tune),
          onPressed: () => context.pushRoute<void>(
            AppRoutes.cycleEdit,
            arguments: cycle.id,
          ),
          child: const Text(CycleStrings.editTitle),
        ),
        const SizedBox(height: 10),
        AnimalButton(
          block: true,
          icon: const Icon(Icons.copy_all_outlined),
          onPressed: () async {
            // 起点日期必须用注入的「今天」，不能用 DateTime.now()：
            // 否则测试里无法固定时间，线上也会出现「详情页看到的今天」与
            // 「复制出来的起始日」不一致。
            await _commit(
              ref,
              duplicateCycle(
                _data(ref),
                cycle.id,
                today: today,
                now: DateTime.now(),
                suffix: CycleStrings.duplicateSuffix,
              ),
            );
            if (context.mounted) {
              AnimalMessage.success(
                context,
                const Text('已复制成新计划'),
              );
            }
          },
          child: const Text(CycleStrings.actionDuplicate),
        ),
        const SizedBox(height: 10),
        AnimalButton(
          block: true,
          danger: true,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(context, ref),
          child: const Text(CycleStrings.deleteConfirmTitle),
        ),
      ],
    );
  }

  AppData _data(WidgetRef ref) => ref.appDataOrEmpty;

  Future<void> _commit(WidgetRef ref, AppData next) {
    return ref.read(appDataProvider.notifier).commit(next);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AnimalConfirmDialog.show(
      context: context,
      title: const Text(CycleStrings.deleteConfirmTitle),
      content: const Text(CycleStrings.deleteConfirmBody),
      danger: true,
    );
    if (confirmed != true) {
      return;
    }

    await _commit(ref, deleteCycle(_data(ref), cycle.id));
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
