import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 数据管理页内可被测试稳定定位的控件键。
abstract final class DataKeys {
  static const overview = Key('data-overview');
  static const exportEntry = Key('data-export-entry');
  static const importEntry = Key('data-import-entry');
  static const clearAction = Key('data-clear-action');
}

/// 数据管理页（任务 7.7）。
///
/// 汇聚「导出备份 / 导入恢复 / 清空数据」三个入口，
/// 并显示当前数据量，让用户在清空之前先看清楚要删掉多少东西。
class DataPage extends ConsumerWidget {
  const DataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AnimalTheme.of(context);
    final data = ref.watch(appDataProvider).asData?.value ?? AppData.empty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(DataStrings.sectionTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          IslandCard(
            key: DataKeys.overview,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DataStrings.dataOverview, style: theme.textStyle(size: 15)),
                const SizedBox(height: 8),
                Text(
                  DataStrings.dataOverviewLine(
                    data.tasks.length,
                    data.cycles.length,
                    data.records.length,
                  ),
                  style: theme.textStyle(
                    size: 13,
                    color: theme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _DataEntry(
            key: DataKeys.exportEntry,
            icon: Icons.save_alt,
            title: DataStrings.exportTitle,
            hint: DataStrings.exportHint,
            onTap: () => context.pushRoute<void>(AppRoutes.export),
          ),
          const SizedBox(height: 10),
          _DataEntry(
            key: DataKeys.importEntry,
            icon: Icons.settings_backup_restore,
            title: DataStrings.importTitle,
            hint: DataStrings.importHint,
            onTap: () => context.pushRoute<void>(AppRoutes.import),
          ),
          const SizedBox(height: 22),
          AnimalButton(
            key: DataKeys.clearAction,
            danger: true,
            block: true,
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () => _confirmClear(context, ref),
            child: const Text(DataStrings.clearAction),
          ),
          const SizedBox(height: 8),
          Text(
            DataStrings.clearKeepsSettings,
            style: theme.textStyle(size: 12, color: theme.secondaryTextColor),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await AnimalConfirmDialog.show(
      context: context,
      title: const Text(DataStrings.clearConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(DataStrings.clearConfirmBody),
          const SizedBox(height: 8),
          Text(DataStrings.clearKeepsSettings),
        ],
      ),
      okText: CommonStrings.confirm,
      danger: true,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    // 先等数据加载完成再清空：否则可能拿着默认设置去覆盖，
    // 把用户的提醒开关与应用锁一起清掉。
    final data = await ref.read(appDataProvider.future);
    if (!context.mounted) {
      return;
    }
    await ref
        .read(appDataProvider.notifier)
        .commit(AppData(settings: data.settings));

    if (context.mounted) {
      AnimalMessage.success(context, const Text(DataStrings.clearDone));
    }
  }
}

/// 一个入口行。
class _DataEntry extends StatelessWidget {
  const _DataEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return IslandCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textStyle(size: 15)),
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
