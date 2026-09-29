/// 备份文件的编解码（任务 7.1 / 7.2）。
///
/// 备份格式就是 `AppBackup.toJson()` 的形状（PRD §八.6），
/// **不额外包一层**：本地存储用的也是同一份结构，所以「导出」不需要任何转换。
///
/// 本文件是 `core` 中允许**不含界面文案**的纯逻辑：解码失败只返回
/// [BackupError] 枚举，中文提示由 `app/l10n_strings.dart` 映射，
/// 这样 core 不必依赖 app 层。
library;

import 'dart:convert';

import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:meta/meta.dart';

/// 解码失败的类别。
enum BackupError {
  /// 内容为空。
  emptyInput,

  /// 不是合法 JSON。
  invalidJson,

  /// 顶层不是对象。
  notAnObject,

  /// 版本号高于当前应用支持的版本。
  unsupportedVersion,
}

/// 解码结果。
@immutable
class BackupDecodeResult {
  const BackupDecodeResult._({this.backup, this.error, this.detail});

  factory BackupDecodeResult.success(AppBackup backup) =>
      BackupDecodeResult._(backup: backup);

  factory BackupDecodeResult.failure(BackupError error, {String? detail}) =>
      BackupDecodeResult._(error: error, detail: detail);

  /// 成功时的备份对象。
  final AppBackup? backup;

  /// 失败类别。
  final BackupError? error;

  /// 附加信息（例如版本号、解析器原始报错），供界面展示细节。
  final String? detail;

  bool get isSuccess => backup != null;
  bool get isFailure => !isSuccess;

  @override
  String toString() => isSuccess
      ? 'BackupDecodeResult.success(${backup!.summary})'
      : 'BackupDecodeResult.failure(${error!.name}${detail == null ? '' : ': $detail'})';
}

/// 7.1 把全部数据编码成备份 JSON 文本。
///
/// - [pretty] 为真时缩进输出，便于用户直接用编辑器查看；
/// - `exportedAt` 每次导出都取当前时间，便于用户判断备份新旧。
String encodeBackup(
  AppData data, {
  DateTime? exportedAt,
  bool pretty = true,
}) {
  final backup = AppBackup.of(data, exportedAt: exportedAt);
  final json = backup.toJson();
  return pretty
      ? const JsonEncoder.withIndent('  ').convert(json)
      : jsonEncode(json);
}

/// 7.2 解码并校验备份文本。
///
/// **宽松读取**：单个实体字段缺失/类型不对由各模型的 `fromJson` 兜底，
/// 不整体失败；只有「连文件都不是备份」这种情况才报错。
BackupDecodeResult decodeBackup(String raw, {DateTime? now}) {
  if (raw.trim().isEmpty) {
    return BackupDecodeResult.failure(BackupError.emptyInput);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    return BackupDecodeResult.failure(
      BackupError.invalidJson,
      detail: error.message,
    );
  }

  if (decoded is! Map) {
    return BackupDecodeResult.failure(BackupError.notAnObject);
  }

  final json = decoded.map((key, value) => MapEntry(key.toString(), value));

  try {
    return BackupDecodeResult.success(AppBackup.fromJson(json, now: now));
  } on BackupVersionException catch (error) {
    return BackupDecodeResult.failure(
      BackupError.unsupportedVersion,
      detail: error.toString(),
    );
  } catch (error) {
    // 理论上上面已经把可预期的失败都覆盖了；这里兜底避免「导入坏文件把应用搞崩」
    return BackupDecodeResult.failure(
      BackupError.invalidJson,
      detail: error.toString(),
    );
  }
}
