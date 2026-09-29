import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';

/// 基于 Hive 的本地存储实现。
///
/// ## 为什么是「一个 box + 一个快照键」而不是 4 个 box
///
/// 计划里原本写的是 tasks/cycles/records/settings 四个 box 按 id 存。
/// 实现时改成**单键快照**，原因是原子性：
/// 4 个 box 的全量替换必须 `clear()` 再 `putAll()`，中途崩溃会让数据处于
/// 「一半新一半旧」的状态；而单个 key 的 `put` 在 Hive 里是追加一帧、
/// 重开时以最后一帧为准，**天然原子**。
///
/// 本项目是纯本地、无服务器、无同步的应用 —— 崩溃丢数据是它最严重的故障，
/// 因此用原子性换掉了「按 id 分条存储」的便利。数据量很小（数千条），
/// 全量重写与全量解码的代价可以忽略。
///
/// 快照内容就是备份格式本身，因此「导出」= 直接读出这个字符串。
class HiveLocalStore extends LocalStore {
  HiveLocalStore._(this._box);

  /// 默认 box 名。
  static const String defaultBoxName = 'loop_island_data';

  /// 快照在 box 中的键。
  static const String snapshotKey = 'snapshot';

  /// 损坏数据暂存键前缀：读不出来时把原文挪到 `corrupt_<时间>` 下，
  /// 避免下一次保存把它彻底覆盖，给用户留一条手工恢复的路。
  static const String corruptKeyPrefix = 'corrupt_';

  /// 打开（或新建）本地存储。
  ///
  /// 重复调用幂等：Hive 会复用已打开的 box。
  /// - [directory] 为空时用 `Hive.initFlutter()`（走 path_provider 的应用文档目录）；
  /// - 单元测试请显式传临时目录，避免依赖平台通道。
  static Future<HiveLocalStore> open({
    String? directory,
    String boxName = defaultBoxName,
  }) async {
    if (directory != null) {
      Hive.init(directory);
    } else {
      await Hive.initFlutter();
    }
    final box = await Hive.openBox<dynamic>(boxName);
    return HiveLocalStore._(box);
  }

  final Box<dynamic> _box;

  /// 直接用一个已打开的 box 构造，供需要自行控制 box 生命周期的测试使用
  /// （例如浏览器端要先 `Hive.openBox` 再注入损坏数据）。
  factory HiveLocalStore.forTesting(Box<dynamic> box) = HiveLocalStore._;

  /// 快照原始 JSON（调试 / 导出用）。无数据时返回 null。
  String? get rawSnapshot {
    final raw = _box.get(snapshotKey);
    return raw is String ? raw : null;
  }

  @override
  Future<AppBackup> load() async {
    final raw = _box.get(snapshotKey);
    if (raw is! String || raw.trim().isEmpty) {
      return AppBackup.of(AppData.empty);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('快照根节点不是对象');
      }
      return AppBackup.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on BackupVersionException {
      // 版本过高说明用户装了旧版应用：必须让上层看到，不能静默清空。
      rethrow;
    } catch (_) {
      // 数据损坏：暂存原文后按空数据处理，保证应用仍能启动。
      await _preserveCorrupt(raw);
      return AppBackup.of(AppData.empty);
    }
  }

  @override
  Future<void> save(AppBackup backup) async {
    final raw = jsonEncode(backup.toJson());
    await _box.put(snapshotKey, raw);
    await _box.flush();
  }

  @override
  Future<void> clear() async {
    await _box.delete(snapshotKey);
    await _box.flush();
  }

  @override
  Future<void> close() async {
    await _box.close();
  }

  Future<void> _preserveCorrupt(String raw) async {
    final key = '$corruptKeyPrefix${dayKey(DateTime.now())}'
        '_${DateTime.now().millisecondsSinceEpoch}';
    await _box.put(key, raw);
    await _box.delete(snapshotKey);
    await _box.flush();
  }
}
