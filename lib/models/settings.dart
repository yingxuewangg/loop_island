import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:meta/meta.dart';

import 'json_x.dart';

/// 应用设置。
///
/// 所有字段都有合理默认值，因此 `AppSettings()` 即为「默认设置」——
/// 这保证老备份缺少 `settings` 时也能正常导入。
@immutable
class AppSettings {
  const AppSettings({
    this.remindersEnabled = true,
    this.defaultRemindMinutesOfDay = const [defaultRemindMinute],
    this.cycleRemindersEnabled = true,
    this.lockEnabled = false,
    this.lockPinHash,
    this.biometricEnabled = false,
    this.themeSeed,
    this.lastBackupAt,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      remindersEnabled: readBool(json, 'remindersEnabled', fallback: true),
      defaultRemindMinutesOfDay: _readDefaultRemindMinutes(json),
      cycleRemindersEnabled:
          readBool(json, 'cycleRemindersEnabled', fallback: true),
      lockEnabled: readBool(json, 'lockEnabled'),
      lockPinHash: readStrOrNull(json, 'lockPinHash'),
      biometricEnabled: readBool(json, 'biometricEnabled'),
      themeSeed: readIntOrNull(json, 'themeSeed'),
      lastBackupAt: readInstant(json, 'lastBackupAt'),
    );
  }

  /// 默认提醒时间：早上 9:00（一天提醒一次）。
  static const int defaultRemindMinute = 9 * 60;

  /// 提醒总开关。
  final bool remindersEnabled;

  /// 默认提醒时段（一天内分钟数，升序去重，最多 [kMaxRemindSlots] 个）。
  ///
  /// 在计划里打开提醒时套用的初始值；用户可以改成「一天提醒 2 次」这种。
  final List<int> defaultRemindMinutesOfDay;

  /// 循环计划每日提醒开关。
  final bool cycleRemindersEnabled;

  /// 是否启用应用锁。
  ///
  /// **应用锁功能已取消（原任务 8.8 / 8.9 不做）**，这几个字段保留下来只为两件事：
  /// 1. 备份 JSON 的字段集合保持稳定 —— 老备份导入、新备份导出都还能原样往返；
  /// 2. 「清空数据 / 合并导入时要保留哪些设置」的测试拿它当见证字段。
  /// 新增功能时**不要**顺手删掉它们。
  final bool lockEnabled;

  /// PIN 的摘要（sha256 + 盐），**绝不存明文**；未设置时为 null。
  final String? lockPinHash;

  /// 是否启用生物识别解锁。
  final bool biometricEnabled;

  /// 主题色种子（预留，第一版不使用）。
  final int? themeSeed;

  /// 上次成功导出备份的时间。
  final DateTime? lastBackupAt;

  /// 是否已设置 PIN。
  ///
  /// 保留字段的派生 getter，见 [lockEnabled] 的说明。
  bool get hasPin => (lockPinHash ?? '').isNotEmpty;

  /// 应用锁是否实际生效（开关打开且至少有一种验证方式）。
  bool get isLockActive => lockEnabled && (hasPin || biometricEnabled);

  /// 默认提醒时间（最早的时段）；用于只需要一个时刻的旧调用点。
  int get defaultRemindMinuteOfDay => defaultRemindMinutesOfDay.isEmpty
      ? defaultRemindMinute
      : defaultRemindMinutesOfDay.first;

  /// 默认提醒时间的 `HH:mm` 展示文本（多个时段用「、」连接）。
  String get defaultRemindLabel =>
      formatMinuteSlots(defaultRemindMinutesOfDay).join('、');

  Map<String, dynamic> toJson() => {
        'remindersEnabled': remindersEnabled,
        'defaultRemindMinutesOfDay': defaultRemindMinutesOfDay,
        'cycleRemindersEnabled': cycleRemindersEnabled,
        'lockEnabled': lockEnabled,
        'lockPinHash': lockPinHash,
        'biometricEnabled': biometricEnabled,
        'themeSeed': themeSeed,
        'lastBackupAt': writeInstant(lastBackupAt),
      };

  AppSettings copyWith({
    bool? remindersEnabled,
    Object? defaultRemindMinutesOfDay = kUnset,
    Object? defaultRemindMinuteOfDay = kUnset,
    bool? cycleRemindersEnabled,
    bool? lockEnabled,
    Object? lockPinHash = kUnset,
    bool? biometricEnabled,
    Object? themeSeed = kUnset,
    Object? lastBackupAt = kUnset,
  }) {
    return AppSettings(
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      defaultRemindMinutesOfDay: _resolveDefaultRemindMinutes(
        list: defaultRemindMinutesOfDay,
        single: defaultRemindMinuteOfDay,
      ),
      cycleRemindersEnabled:
          cycleRemindersEnabled ?? this.cycleRemindersEnabled,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      lockPinHash: identical(lockPinHash, kUnset)
          ? this.lockPinHash
          : lockPinHash as String?,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      themeSeed: identical(themeSeed, kUnset)
          ? this.themeSeed
          : themeSeed as int?,
      lastBackupAt: identical(lastBackupAt, kUnset)
          ? this.lastBackupAt
          : lastBackupAt as DateTime?,
    );
  }

  /// 解析 [copyWith] 的两个默认提醒参数：正式接口是列表，单值是便捷写法。
  List<int> _resolveDefaultRemindMinutes({
    required Object? list,
    required Object? single,
  }) {
    if (!identical(list, kUnset)) {
      return list == null
          ? const [defaultRemindMinute]
          : normalizeMinuteSlots(list as Iterable<int>);
    }
    if (identical(single, kUnset)) {
      return defaultRemindMinutesOfDay;
    }
    final value = single as int?;
    return value == null
        ? const [defaultRemindMinute]
        : normalizeMinuteSlots([value]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'AppSettings(reminders=$remindersEnabled, '
      'lock=$lockEnabled, pin=$hasPin)';
}

int? _clampMinute(int? value) {
  if (value == null) {
    return null;
  }
  return value.clamp(0, minutesPerDay - 1);
}

/// 读取默认提醒时段，并兼容「只有一个 `defaultRemindMinuteOfDay`」的老备份。
List<int> _readDefaultRemindMinutes(Map<String, dynamic> json) {
  final raw = json['defaultRemindMinutesOfDay'];
  if (raw is List && raw.isNotEmpty) {
    final minutes = <int>[];
    for (final item in raw) {
      if (item is int) {
        minutes.add(item);
      } else if (item is double) {
        minutes.add(item.toInt());
      }
    }
    if (minutes.isNotEmpty) {
      return normalizeMinuteSlots(minutes);
    }
  }
  final legacy = _clampMinute(readIntOrNull(json, 'defaultRemindMinuteOfDay'));
  return normalizeMinuteSlots(
    legacy == null ? const [AppSettings.defaultRemindMinute] : [legacy],
  );
}
