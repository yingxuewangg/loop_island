/// 备份文件的导入导出 IO（任务 7.5 / 7.6 的平台能力层）。
///
/// 抽成接口是为了**可测试**：`file_picker` / `share_plus` 依赖平台通道，
/// 在单测里跑不起来；界面只依赖 [BackupIo]，测试注入假的实现即可覆盖
/// 「选文件 → 预览 → 覆盖/合并 → 结果」整条链路。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 用户选中的备份文件。
class PickedBackup {
  const PickedBackup({required this.name, required this.content});

  /// 文件名（用于界面展示）。
  final String name;

  /// 文件内容。
  final String content;

  @override
  String toString() => 'PickedBackup($name, ${content.length} 字符)';
}

/// 备份文件的读写与分享。
abstract class BackupIo {
  /// 让用户挑一个备份文件并读回内容；用户取消返回 `null`。
  Future<PickedBackup?> pickBackup();

  /// 让用户选保存位置并写入；取消返回 `null`，成功返回路径。
  Future<String?> saveBackup(
    String content, {
    required String suggestedName,
  });

  /// 走系统分享。
  Future<void> shareBackup(
    String content, {
    required String suggestedName,
  });
}

/// 真实实现：`file_picker` + `share_plus` + `path_provider`。
class FileBackupIo implements BackupIo {
  const FileBackupIo();

  @override
  Future<PickedBackup?> pickBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return null;
    }

    // 桌面/移动端 `bytes` 可能为空（withData 只在部分平台填充），
    // 因此优先用 bytes，其次按路径读取。
    final bytes = file.bytes;
    final content = bytes != null
        ? utf8.decode(bytes, allowMalformed: true)
        : await File(file.path!).readAsString();

    return PickedBackup(name: file.name, content: content);
  }

  @override
  Future<String?> saveBackup(
    String content, {
    required String suggestedName,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: suggestedName,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: utf8.encode(content),
    );
    if (path == null) {
      return null;
    }
    // 部分平台 saveFile 只返回路径、不写内容，这里再写一次保证落盘。
    final file = File(path);
    if (!await file.exists() || (await file.length()) == 0) {
      await file.writeAsString(content);
    }
    return path;
  }

  @override
  Future<void> shareBackup(
    String content, {
    required String suggestedName,
  }) async {
    // share_plus 需要真实文件路径，先写到临时目录
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$suggestedName');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: suggestedName,
    );
  }
}

/// 备份 IO 实现；测试里覆写成假的。
final backupIoProvider = Provider<BackupIo>((ref) => const FileBackupIo());
