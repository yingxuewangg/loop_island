import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 设置页内可被测试稳定定位的控件键。
abstract final class SettingsKeys {
  static const statsEntry = Key('settings-stats-entry');
  static const dataEntry = Key('settings-data-entry');
  static const reminderEntry = Key('settings-reminder-entry');
  static const aboutEntry = Key('settings-about-entry');
}

/// Tab 4「设置」（任务 8.7）。
///
/// 四个分组，与 PRD 的设置清单一一对应：
/// 提醒设置 / 统计 / 数据管理（导出·导入·清空）/ 关于与隐私。
///
/// 每组都是「一节标题 + 若干 `AnimalCard` 入口」，入口本身只负责跳转，
/// 具体操作留在各自的页面里 —— 设置页因此永远是一屏能看完的目录。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(TabLabels.settings, style: theme.textStyle(size: 20)),
          ),
          _SectionLabel(text: SettingsStrings.sectionReminder),
          _EntryCard(
            key: SettingsKeys.reminderEntry,
            title: SettingsStrings.reminderTitle,
            hint: SettingsStrings.reminderEntryHint,
            onTap: () => context.pushRoute<void>(AppRoutes.reminder),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: SettingsStrings.sectionStats),
          _EntryCard(
            key: SettingsKeys.statsEntry,
            title: SettingsStrings.statsEntry,
            hint: SettingsStrings.statsEntryHint,
            onTap: () => context.pushRoute<void>(AppRoutes.stats),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: SettingsStrings.sectionData),
          _EntryCard(
            key: SettingsKeys.dataEntry,
            title: DataStrings.sectionTitle,
            hint: DataStrings.exportHint,
            onTap: () => context.pushRoute<void>(AppRoutes.dataManage),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: SettingsStrings.sectionAbout),
          _EntryCard(
            key: SettingsKeys.aboutEntry,
            title: SettingsStrings.aboutEntry,
            hint: SettingsStrings.aboutEntryHint,
            onTap: () => context.pushRoute<void>(AppRoutes.about),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textStyle(size: 13, color: theme.secondaryTextColor),
      ),
    );
  }
}

/// 一个带箭头的入口卡片。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.title,
    required this.hint,
    required this.onTap,
  });

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textStyle(size: 15)),
                const SizedBox(height: 4),
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
