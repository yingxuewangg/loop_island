import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/features/cycle/widgets/cycle_card.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 计划列表页内可被测试稳定定位的控件键。
abstract final class CycleListKeys {
  static const addFab = Key('cycle-list-add-fab');
  static const emptyAddButton = Key('cycle-list-empty-add');
  static const archivedToggle = Key('cycle-list-archived-toggle');
}

/// Tab 3「计划」：循环计划列表（对应任务 3.8）。
///
/// 分两段：进行中/已暂停的计划，以及**已归档**（已结束）的计划 ——
/// 归档段默认折叠，避免长期使用后历史计划淹没当前计划。
///
/// 注意：**归档动作由 `AppShell` 统一负责**（它是每日维护的唯一 owner）。
/// 本页只按 `effectiveStatus` 决定把计划放进哪一段，不写数据。
class CycleListPage extends ConsumerStatefulWidget {
  const CycleListPage({super.key});

  @override
  ConsumerState<CycleListPage> createState() => _CycleListPageState();
}

class _CycleListPageState extends ConsumerState<CycleListPage> {
  bool _archivedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(appDataProvider);
    final today = ref.watch(todayProvider);

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: asyncData.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: AnimalSkeleton(active: true, rows: 4),
              ),
              error: (error, _) => Center(
                child: AnimalEmpty(description: '$error'),
              ),
              data: (data) => _CycleListBody(
                data: data,
                today: today,
                archivedExpanded: _archivedExpanded,
                onToggleArchived: () => setState(
                  () => _archivedExpanded = !_archivedExpanded,
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 20,
            child: IslandPrimaryButton(
              key: CycleListKeys.addFab,
              icon: const Icon(Icons.add),
              onPressed: () => context.pushRoute<void>(AppRoutes.cycleEdit),
              child: const Text(CycleStrings.createTitle),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleListBody extends StatelessWidget {
  const _CycleListBody({
    required this.data,
    required this.today,
    required this.archivedExpanded,
    required this.onToggleArchived,
  });

  final AppData data;
  final DateTime today;
  final bool archivedExpanded;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    final running = <Cycle>[];
    final archived = <Cycle>[];
    for (final cycle in data.cycles) {
      if (effectiveStatus(cycle, today: today) == CycleStatus.ended) {
        archived.add(cycle);
      } else {
        running.add(cycle);
      }
    }

    if (running.isEmpty && archived.isEmpty) {
      return Center(
        child: AnimalEmpty(
          description: CycleStrings.noCycle,
          action: IslandPrimaryButton(
            key: CycleListKeys.emptyAddButton,
            icon: const Icon(Icons.add),
            onPressed: () => context.pushRoute<void>(AppRoutes.cycleEdit),
            child: const Text(CycleStrings.createTitle),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(TabLabels.cycles, style: theme.textStyle(size: 20)),
        ),
        for (final cycle in running)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CycleCard(
              cycle: cycle,
              today: today,
              onTap: () => context.pushRoute<void>(
                AppRoutes.cycleDetail,
                arguments: cycle.id,
              ),
            ),
          ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ArchivedHeader(
            count: archived.length,
            expanded: archivedExpanded,
            onTap: onToggleArchived,
          ),
          if (archivedExpanded)
            for (final cycle in archived)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: CycleCard(
                  cycle: cycle,
                  today: today,
                  onTap: () => context.pushRoute<void>(
                    AppRoutes.cycleDetail,
                    arguments: cycle.id,
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _ArchivedHeader extends StatelessWidget {
  const _ArchivedHeader({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return InkWell(
      key: CycleListKeys.archivedToggle,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: theme.secondaryTextColor,
            ),
            const SizedBox(width: 6),
            Text(
              '${CycleStrings.archivedSection} · $count',
              style: theme.textStyle(
                size: 13,
                color: theme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
