/// 假的备份 IO（任务 7.5 / 7.6 的测试替身）。
///
/// 与 `fake_notification_service.dart` 同一套做法：真实的 `FileBackupIo` 会调用
/// `file_picker` / `share_plus`（依赖平台通道，单测里跑不起来），
/// 界面只依赖 `BackupIo` 抽象，注入假实现就能覆盖「选文件 → 预览 → 覆盖/合并 → 结果」
/// 整条链路。
///
/// 放在 `test/support/` 而不是某个测试文件里：验收流程测试（`acceptance_flow_test.dart`）
/// 也要用它 —— 跨测试文件 import 另一个 `_test.dart` 很容易踩到重复声明与意外执行。
library;

import 'package:loop_island/services/backup_io.dart';

/// 记录「用户选了什么文件」「有没有保存/分享」。
class FakeBackupIo implements BackupIo {
  FakeBackupIo({this.picked, this.savePath});

  /// `pickBackup` 的返回值；null 表示用户取消。
  PickedBackup? picked;

  /// `saveBackup` 的返回值；null 表示用户取消保存。
  String? savePath;

  int pickCount = 0;
  String? savedContent;
  String? savedName;
  String? sharedContent;
  String? sharedName;

  /// 非 null 时 `pickBackup` 抛该异常（覆盖「选文件出错」）。
  Object? throwOnPick;

  @override
  Future<PickedBackup?> pickBackup() async {
    pickCount++;
    final error = throwOnPick;
    if (error != null) {
      throw error;
    }
    return picked;
  }

  @override
  Future<String?> saveBackup(
    String content, {
    required String suggestedName,
  }) async {
    savedContent = content;
    savedName = suggestedName;
    return savePath;
  }

  @override
  Future<void> shareBackup(
    String content, {
    required String suggestedName,
  }) async {
    sharedContent = content;
    sharedName = suggestedName;
  }
}
