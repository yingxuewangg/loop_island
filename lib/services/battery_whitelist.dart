/// 电池优化白名单（真机通知可靠性的关键开关）。
///
/// 背景：模拟器/电脑上定时通知几乎总是准时，真机上却「时有时无、时而
/// 延迟」—— 差异来自系统的后台管控：原生 Doze 会合并/推迟未加白名单
/// 应用的闹钟广播，国产 ROM（MIUI、ColorOS、HarmonyOS 等）更会直接清理
/// 后台进程，把已排好的闹钟一并丢掉。
///
/// 这里只做**查询与用户主动申请**（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
/// 会弹系统授权框），绝不静默加白 —— 那属于滥用，商店审核也会拦。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 电池优化白名单能力。
abstract class BatteryWhitelist {
  /// 是否已在电池优化白名单里。
  ///
  /// `null` 表示平台不适用（非 Android）或查询失败 —— 调用方据此隐藏入口。
  Future<bool?> isIgnoringOptimizations();

  /// 拉起系统授权框，请用户把应用加入白名单。
  ///
  /// 返回系统框是否成功拉起（用户同意与否要靠 [isIgnoringOptimizations] 复查）。
  Future<bool> requestIgnoreOptimizations();
}

/// 真实实现：走 [MainActivity] 注册的 `loop_island/system` 通道。
class MethodChannelBatteryWhitelist implements BatteryWhitelist {
  static const MethodChannel _channel = MethodChannel('loop_island/system');

  @override
  Future<bool?> isIgnoringOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
    } on MissingPluginException {
      // 非 Android 平台没有这个通道
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestIgnoreOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// 生产环境使用的电池白名单服务；测试覆写成假实现。
final batteryWhitelistProvider = Provider<BatteryWhitelist>(
  (ref) => MethodChannelBatteryWhitelist(),
);
