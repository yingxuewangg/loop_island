package com.example.loop_island

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 提供通知提醒依赖的系统级查询与引导：
 *
 * - isIgnoringBatteryOptimizations：是否在电池优化白名单里。国产 ROM 与
 *   原生 Doze 都会清理/限制后台应用，未加白名单时定时通知**时有时无、
 *   时而延迟** —— 这是真机与模拟器行为差异的最大来源（模拟器默认不管控）。
 * - requestIgnoreBatteryOptimizations：拉起系统的「忽略电池优化」授权框，
 *   用户同意后进白名单。
 *
 * 仅 Android 有实现；其它平台走 Dart 侧的 MissingPluginException 兜底。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager =
                        getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(
                        powerManager.isIgnoringBatteryOptimizations(packageName),
                    )
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        // 个别 ROM 不支持该 action；让用户去系统设置手动处理
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val CHANNEL = "loop_island/system"
    }
}
