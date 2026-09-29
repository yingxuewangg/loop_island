import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/backup_codec.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/services/backup_io.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 导出页内可被测试稳定定位的控件键。
abstract final class ExportKeys {
  static const saveToFile = Key('export-save-to-file');
  static const share = Key('export-share');
  static const summary = Key('export-summary');
  static const lastBackup = Key('export-last-backup');
}

/// 导出备份页（任务 7.5）。
///
/// 导出内容就是 `encodeBackup(data)` 的文本，与本地存储用的是同一份结构，
/// 因此**不需要任何格式转换**。
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    // 必须 watch：用 read 的话数据加载完成后页面不会重建，
    // 会一直显示「空数据」并把空备份导出去。
    final data = ref.watch(appDataProvider).asData?.value ?? AppData.empty;
    final lastBackup = data.settings.lastBackupAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text(DataStrings.exportTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          IslandCard(
            key: ExportKeys.summary,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DataStrings.exportHint,
                  style: theme.textStyle(size: 13),
                ),
                const SizedBox(height: 10),
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
          if (data.isEmpty) ...[
            const SizedBox(height: 12),
            AnimalAlert(
              type: AnimalAlertType.warning,
              child: Text(
                DataStrings.exportEmptyWarning,
                style: theme.textStyle(size: 12),
              ),
            ),
          ],
          const SizedBox(height: 18),
          IslandPrimaryButton(
            key: ExportKeys.saveToFile,
            block: true,
            loading: _busy,
            icon: const Icon(Icons.save_alt),
            onPressed: _busy ? null : _saveToFile,
            child: const Text(DataStrings.saveToFile),
          ),
          const SizedBox(height: 10),
          AnimalButton(
            key: ExportKeys.share,
            block: true,
            icon: const Icon(Icons.ios_share),
            onPressed: _busy ? null : _share,
            child: const Text(DataStrings.shareFile),
          ),
          const SizedBox(height: 18),
          Text(
            key: ExportKeys.lastBackup,
            lastBackup == null
                ? '${DataStrings.lastBackup}：${DataStrings.noBackupYet}'
                : '${DataStrings.lastBackup}：'
                    '${formatFullDate(lastBackup)} ${formatHm(lastBackup)}',
            style: theme.textStyle(
              size: 12,
              color: theme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 建议文件名：带日期，便于用户区分多份备份。
  String _suggestedName() {
    final now = DateTime.now();
    final stamp = '${dayKey(now).replaceAll('-', '')}_'
        '${formatHm(now).replaceAll(':', '')}';
    return 'loop_island_backup_$stamp.json';
  }

  Future<void> _saveToFile() async {
    await _runExport((io, content, name) async {
      final path = await io.saveBackup(content, suggestedName: name);
      if (path == null || !mounted) {
        return false;
      }
      _toast(DataStrings.savedTo(path));
      return true;
    });
  }

  Future<void> _share() async {
    await _runExport((io, content, name) async {
      await io.shareBackup(content, suggestedName: name);
      return true;
    });
  }

  /// 导出公共流程：编码 → 交给 IO → 成功则记录备份时间。
  Future<void> _runExport(
    Future<bool> Function(BackupIo io, String content, String name) action,
  ) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);

    try {
      // 必须 await：provider 可能尚未加载完成，用 `read` 会拿到空的 AppData，
      // 结果就是「导出了一份空备份」。
      final data = await ref.read(appDataProvider.future);
      final content = encodeBackup(data);
      final name = _suggestedName();
      final done = await action(ref.read(backupIoProvider), content, name);

      if (done) {
        // 记录备份时间，让用户知道上次备份是多久之前
        await ref.read(appDataProvider.notifier).commit(
              data.copyWith(
                settings: data.settings.copyWith(
                  lastBackupAt: DateTime.now(),
                ),
              ),
            );
      }
    } catch (error) {
      if (mounted) {
        _toast('${DataStrings.exportFailed}：$error', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message, {bool error = false}) {
    if (error) {
      AnimalMessage.error(context, Text(message));
    } else {
      AnimalMessage.success(context, Text(message));
    }
  }
}
