import 'package:flutter/material.dart';
import 'package:loop_island/app/bootstrap.dart';

void main() {
  // Hive 与本地通知都需要平台通道，必须在 runApp 前初始化绑定。
  WidgetsFlutterBinding.ensureInitialized();

  // 打开存储、注入 provider、处理失败态都由 StorageBootstrapApp 负责。
  runApp(const StorageBootstrapApp());
}
