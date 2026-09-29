/// 电池优化白名单的测试替身。
library;

import 'package:loop_island/services/battery_whitelist.dart';

/// 假电池白名单：记录调用，状态可翻转。
class FakeBatteryWhitelist implements BatteryWhitelist {
  FakeBatteryWhitelist({this.ignored});

  /// `null` 模拟「平台不适用」（隐藏入口）；true/false 模拟授权状态。
  bool? ignored;

  int requestCount = 0;

  @override
  Future<bool?> isIgnoringOptimizations() async => ignored;

  @override
  Future<bool> requestIgnoreOptimizations() async {
    requestCount++;
    // 真机行为：授权框确认后即进白名单
    ignored = true;
    return true;
  }
}
