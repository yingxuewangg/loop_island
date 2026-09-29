import 'package:loop_island/models/backup.dart';

/// 本地存储抽象。
///
/// 只做一件事：把整份 [AppBackup] 原子地存下来、再原样读回来。
/// 故意**不提供**按 id 增删改的细粒度接口 —— 仓库层每次提交的都是完整快照，
/// 细粒度接口只会制造「内存与磁盘不一致」的机会。
///
/// 实现约束：
/// - `save` 必须是**全量替换**语义，不能与旧数据混合。
/// - `load` 在读不到或数据损坏时必须返回空备份，**不得抛异常**
///   （否则应用启动即白屏，用户没有任何恢复入口）。
abstract class LocalStore {
  /// 读取整份数据。首次启动或数据损坏时返回空备份。
  Future<AppBackup> load();

  /// 全量写入（替换）。
  Future<void> save(AppBackup backup);

  /// 清空全部数据。
  Future<void> clear();

  /// 释放资源（如关闭数据库文件）。默认无需处理。
  Future<void> close() async {}
}
