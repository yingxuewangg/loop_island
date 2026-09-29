import 'package:loop_island/core/date_x.dart';
import 'package:meta/meta.dart';

import 'app_data.dart';
import 'json_x.dart';

/// 备份文件里出现「未来版本号」时的处理策略说明：
/// 解码阶段应拒绝导入并提示用户升级应用，而不是猜测字段含义。
class BackupVersionException implements Exception {
  const BackupVersionException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      '备份版本不受支持：文件为 v$found，当前应用最高支持 v$supported';
}

/// 版本化备份信封。
///
/// JSON 结构严格对应 PRD §八.6：
/// `{ version, exportedAt, tasks, cycles, records, settings }`
/// —— [data] 在序列化时被**摊平**到顶层，不做嵌套，便于人工查看与手工编辑。
@immutable
class AppBackup {
  const AppBackup({
    required this.version,
    required this.exportedAt,
    required this.data,
  });

  /// 用当前版本号打包数据。
  factory AppBackup.of(AppData data, {DateTime? exportedAt}) {
    return AppBackup(
      version: currentVersion,
      exportedAt: exportedAt ?? DateTime.now(),
      data: data,
    );
  }

  /// 从 JSON 还原。
  ///
  /// - 缺少 `version` 时按 [currentVersion] 处理（兼容最初的手工备份）。
  /// - 版本高于 [currentVersion] 时抛 [BackupVersionException]。
  /// - 缺字段的单个实体由各模型的宽松 `fromJson` 兜底，不整体失败。
  factory AppBackup.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final version = readInt(json, 'version', fallback: currentVersion);
    if (version > currentVersion) {
      throw BackupVersionException(version, currentVersion);
    }

    return AppBackup(
      version: version,
      exportedAt: readInstant(json, 'exportedAt') ??
          readDay(json, 'exportedAt') ??
          (now ?? DateTime.now()),
      data: AppData.fromJson(json, now: now),
    );
  }

  /// 当前应用支持的备份版本。
  static const int currentVersion = 1;

  final int version;

  /// 导出时间。
  final DateTime exportedAt;

  /// 业务数据。
  final AppData data;

  /// 备份规模摘要（导入预览用）。
  String get summary =>
      '${data.tasks.length} 个任务、${data.cycles.length} 个计划、'
      '${data.records.length} 条记录';

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportedAt': writeInstant(exportedAt),
        ...data.toJson(),
      };

  AppBackup copyWith({
    int? version,
    DateTime? exportedAt,
    AppData? data,
  }) {
    return AppBackup(
      version: version ?? this.version,
      exportedAt: exportedAt ?? this.exportedAt,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBackup && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'AppBackup(v$version, ${dayKey(exportedAt)}, $summary)';
}
