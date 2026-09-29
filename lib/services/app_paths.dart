/// 应用数据位置的读取（任务 8.10 的「数据存储路径可见」）。
///
/// 抽成接口的理由和 `BackupIo` 一样：`path_provider` 依赖平台通道，
/// 单测里跑不起来；界面只依赖 [AppPaths]，测试注入固定路径即可确定断言。
///
/// 只暴露**目录**，不自己拼完整路径：拼路径就得判断 Windows / POSIX 的分隔符，
/// 而那需要 `dart:io`（Web 上不可用，本应用有 Web 冒烟测试）。
/// 界面把「目录」和「文件名」分两行显示，既避免了这个问题，信息也更清楚。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Hive 的 box 名（与 `HiveLocalStore.defaultBoxName` 保持一致）。
///
/// 这里重复一次字面量而不是 import `data/hive_local_store.dart`：
/// `services/` 不该依赖 `data/`。`test/features/about_test.dart` 里有一条
/// 断言盯着两者相等，改一处漏一处会立刻红。
const String kStorageFileName = 'loop_island_data.hive';

/// 应用数据位置。
abstract class AppPaths {
  /// 本地数据所在目录；读不到时返回 `null`（不抛异常）。
  ///
  /// 「读不到」不是故障：界面显示一句「暂时读不到路径（不影响正常使用）」
  /// 就够了，没必要因此让整页崩掉或弹错误。
  Future<String?> storageDirectory();
}

/// 真实实现：`path_provider` 的应用文档目录。
class PathProviderAppPaths implements AppPaths {
  const PathProviderAppPaths();

  @override
  Future<String?> storageDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (_) {
      return null;
    }
  }
}

/// 应用数据位置；测试里覆写成固定路径。
final appPathsProvider =
    Provider<AppPaths>((ref) => const PathProviderAppPaths());
