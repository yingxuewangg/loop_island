import 'dart:convert';

import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';

/// 内存存储实现，供单元测试与 widget 测试使用。
///
/// 行为与 [HiveLocalStore] 完全一致（同一套契约测试同时覆盖两者）；
/// 另外提供计数与故障注入，方便断言「有没有真的落盘」与「落盘失败时的回滚」。
class InMemoryLocalStore extends LocalStore {
  InMemoryLocalStore([AppBackup? initial])
      : _snapshot = initial == null ? null : _copy(initial);

  AppBackup? _snapshot;

  /// `load` 被调用的次数。
  int loadCount = 0;

  /// 实际写入的次数（数据无变化时仓库层会跳过，因此可用于断言）。
  int saveCount = 0;

  /// `clear` 被调用的次数。
  int clearCount = 0;

  /// 置为 true 后 `save` 抛出异常，用于测试回滚路径。
  bool failSave = false;

  /// 置为非 null 后 `save` 抛出该异常。
  Object? saveError;

  /// 模拟磁盘上的原始数据损坏（仅 Hive 实现有这个真实场景）。
  bool corruptOnLoad = false;

  /// 当前快照（测试断言用）。
  AppBackup? get snapshot => _snapshot;

  @override
  Future<AppBackup> load() async {
    loadCount++;
    if (corruptOnLoad) {
      _snapshot = null;
      return AppBackup.of(AppData.empty);
    }
    final current = _snapshot;
    // 深拷贝：与真实存储一致，避免测试里因共享引用而掩盖别名 bug
    return current == null ? AppBackup.of(AppData.empty) : _copy(current);
  }

  @override
  Future<void> save(AppBackup backup) async {
    if (failSave) {
      throw saveError ?? StateError('InMemoryLocalStore.save 注入的故障');
    }
    saveCount++;
    _snapshot = _copy(backup);
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _snapshot = null;
  }

  /// 经 JSON 往返做深拷贝。
  static AppBackup _copy(AppBackup backup) {
    return AppBackup.fromJson(
      jsonDecode(jsonEncode(backup.toJson())) as Map<String, dynamic>,
    );
  }
}
