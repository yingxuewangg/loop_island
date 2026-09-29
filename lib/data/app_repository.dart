import 'dart:async';

import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';

/// 应用数据仓库：唯一的内存状态持有者与唯一写入口。
///
/// 数据流：
/// ```
/// 命令层 → commit(next)  → 立即更新内存并广播（UI 立刻响应）
///                        → 异步落盘
///                        → 落盘失败则回滚内存并把异常抛给调用方
/// ```
/// 「乐观更新 + 失败回滚」而不是「先落盘再更新」，是为了两件事同时成立：
/// UI 不需要等磁盘 IO，且永远不会停在一个「看着成功、其实没存下来」的状态。
class AppRepository {
  AppRepository(this._store);

  final LocalStore _store;
  final StreamController<AppData> _changes =
      StreamController<AppData>.broadcast();

  AppData _data = AppData.empty;
  bool _isLoaded = false;
  bool _isDisposed = false;

  /// 当前快照。
  AppData get data => _data;

  /// 是否已完成首次加载。
  bool get isLoaded => _isLoaded;

  /// 数据变化广播。首次 [init] **不会**广播（调用方直接拿返回值）。
  Stream<AppData> get changes => _changes.stream;

  /// 首次加载。重复调用只加载一次。
  ///
  /// 注意：这里刻意不广播 —— 否则 Riverpod 的 `build()` 阶段会被
  /// 「构建中更新 state」打断。
  Future<AppData> init() async {
    if (_isLoaded) {
      return _data;
    }
    final backup = await _store.load();
    _data = backup.data;
    _isLoaded = true;
    return _data;
  }

  /// 提交新快照：内存立即生效并广播，随后落盘；落盘失败则回滚。
  ///
  /// 与当前数据完全相同时直接返回（不广播、不落盘），
  /// 避免「点一下没改动的保存」也写一次磁盘。
  Future<void> commit(AppData next) async {
    _ensureUsable();
    if (next == _data) {
      return;
    }

    final previous = _data;
    _data = next;
    _isLoaded = true;
    _changes.add(next);

    try {
      await _store.save(AppBackup.of(next));
    } catch (error) {
      // 回滚到落盘前状态，并把失败暴露给调用方展示错误提示
      _data = previous;
      _changes.add(previous);
      rethrow;
    }
  }

  /// 清空全部业务数据，**保留设置**（应用锁、提醒开关等）。
  ///
  /// PRD §七 的「清空数据」只针对任务与记录，设置属于应用配置，不应被一并清掉。
  Future<void> clearBusinessData() {
    return commit(AppData(settings: _data.settings));
  }

  /// 直接读取存储（导入前的备份、调试用）。
  Future<AppBackup> readStore() => _store.load();

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _changes.close();
  }

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError('AppRepository 已释放，不能继续提交数据');
    }
  }
}
