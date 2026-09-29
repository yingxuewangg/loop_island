import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/backup_codec.dart';
import 'package:loop_island/core/backup_merge.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/services/backup_io.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 导入方式。
enum ImportMode {
  /// 合并到现有数据。
  merge,

  /// 覆盖现有数据。
  overwrite,
}

/// 导入页内可被测试稳定定位的控件键。
abstract final class ImportKeys {
  static const pick = Key('import-pick-file');
  static const preview = Key('import-preview');
  static const error = Key('import-error');
  static const modeOverwrite = Key('import-mode-overwrite');
  static const modeMerge = Key('import-mode-merge');
  static const confirm = Key('import-confirm');
  static const result = Key('import-result');
  static const emptyWarning = Key('import-empty-warning');
}

/// 导入恢复页（任务 7.6）。
///
/// 流程：选择文件 → 预览（多少任务/计划/记录）→ 选覆盖或合并 → 确认恢复 → 结果。
/// **非法文件在预览阶段就给出错误，绝不改动现有数据。**
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  PickedBackup? _picked;
  BackupDecodeResult? _decoded;
  ImportMode _mode = ImportMode.merge;
  bool _busy = false;
  MergeStats? _stats;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(DataStrings.importTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(DataStrings.importHint, style: theme.textStyle(size: 13)),
          const SizedBox(height: 16),
          AnimalButton(
            key: ImportKeys.pick,
            block: true,
            loading: _busy,
            icon: const Icon(Icons.folder_open),
            onPressed: _busy ? null : _pick,
            child: const Text(DataStrings.importAction),
          ),

          if (_decoded != null) ...[
            const SizedBox(height: 18),
            if (_decoded!.isFailure)
              AnimalAlert(
                key: ImportKeys.error,
                type: AnimalAlertType.error,
                title: const Text(DataStrings.importFailed),
                child: Text(
                  '${DataStrings.backupErrorMessage(_decoded!.error!)}'
                  '${_decoded!.detail == null ? '' : '\n${_decoded!.detail}'}',
                  style: theme.textStyle(size: 12),
                ),
              )
            else
              _buildPreview(_decoded!.backup!),
          ],

          if (_stats != null) ...[
            const SizedBox(height: 18),
            AnimalAlert(
              key: ImportKeys.result,
              type: AnimalAlertType.success,
              title: const Text(DataStrings.importResultTitle),
              child: Text(
                DataStrings.importDone(
                  DataStrings.previewSummary(
                    _stats!.added,
                    _stats!.updated,
                    _stats!.total,
                  ),
                ),
                style: theme.textStyle(size: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview(AppBackup backup) {
    final theme = AnimalTheme.of(context);
    final data = backup.data;
    final isEmpty = data.tasks.isEmpty &&
        data.cycles.isEmpty &&
        data.records.isEmpty;

    return IslandCard(
      key: ImportKeys.preview,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DataStrings.importPreviewTitle, style: theme.textStyle(size: 15)),
          const SizedBox(height: 10),
          Text(
            DataStrings.previewSummary(
              data.tasks.length,
              data.cycles.length,
              data.records.length,
            ),
            style: theme.textStyle(size: 13),
          ),
          const SizedBox(height: 4),
          Text(
            DataStrings.exportedAt(
              '${formatFullDate(backup.exportedAt)} '
              '${formatHm(backup.exportedAt)}',
            ),
            style: theme.textStyle(
              size: 12,
              color: theme.secondaryTextColor,
            ),
          ),
          if (_picked != null) ...[
            const SizedBox(height: 4),
            Text(
              _picked!.name,
              style: theme.textStyle(
                size: 12,
                color: theme.secondaryTextColor,
              ),
            ),
          ],

          if (isEmpty) ...[
            const SizedBox(height: 12),
            AnimalAlert(
              key: ImportKeys.emptyWarning,
              type: AnimalAlertType.warning,
              child: Text(
                DataStrings.emptyBackupWarning,
                style: theme.textStyle(size: 12),
              ),
            ),
          ],

          const SizedBox(height: 18),
          Text(DataStrings.importModeTitle, style: theme.textStyle(size: 15)),
          const SizedBox(height: 10),
          AnimalRadio<ImportMode>(
            value: _mode,
            direction: AnimalRadioDirection.vertical,
            options: [
              AnimalRadioOption<ImportMode>(
                value: ImportMode.merge,
                label: Text(DataStrings.importModeMerge),
              ),
              AnimalRadioOption<ImportMode>(
                value: ImportMode.overwrite,
                label: Text(DataStrings.importModeOverwrite),
              ),
            ],
            onChanged: (value) => setState(() => _mode = value),
          ),
          const SizedBox(height: 6),
          Text(
            _mode == ImportMode.merge
                ? DataStrings.importModeMergeHint
                : DataStrings.importModeOverwriteHint,
            style: theme.textStyle(size: 12, color: theme.secondaryTextColor),
          ),
          if (_mode == ImportMode.overwrite) ...[
            const SizedBox(height: 10),
            AnimalAlert(
              type: AnimalAlertType.warning,
              child: Text(
                DataStrings.overwriteWarning,
                style: theme.textStyle(size: 12),
              ),
            ),
          ],

          const SizedBox(height: 18),
          AnimalButton(
            key: ImportKeys.confirm,
            block: true,
            danger: _mode == ImportMode.overwrite,
            onPressed: _busy ? null : _restore,
            child: const Text(DataStrings.importConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _stats = null;
    });

    try {
      final picked = await ref.read(backupIoProvider).pickBackup();
      if (!mounted) {
        return;
      }
      if (picked == null) {
        return; // 用户取消
      }
      setState(() {
        _picked = picked;
        _decoded = decodeBackup(picked.content);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _picked = null;
          _decoded = BackupDecodeResult.failure(
            BackupError.invalidJson,
            detail: '$error',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    final backup = _decoded?.backup;
    if (backup == null || _busy) {
      return;
    }
    setState(() => _busy = true);

    try {
      // 必须 await：provider 可能尚未加载完成，用 `read` 会拿到空的 AppData，
      // 那样「合并」就会连本地设置一起当成空的处理。
      final current = await ref.read(appDataProvider.future);
      final MergeResult result = switch (_mode) {
        ImportMode.merge => mergeData(current, backup.data),
        ImportMode.overwrite => MergeResult(
            data: replaceData(backup.data),
            stats: MergeStats(
              addedTasks: backup.data.tasks.length,
              updatedTasks: 0,
              addedCycles: backup.data.cycles.length,
              updatedCycles: 0,
              addedRecords: backup.data.records.length,
              updatedRecords: 0,
            ),
          ),
      };

      await ref.read(appDataProvider.notifier).commit(result.data);
      if (mounted) {
        setState(() => _stats = result.stats);
      }
    } catch (error) {
      if (mounted) {
        AnimalMessage.error(
          context,
          Text('${DataStrings.importFailed}：$error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
