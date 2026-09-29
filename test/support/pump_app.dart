/// widget 测试的挂载工具。
///
/// 阶段 2 起每个界面任务都要写 widget 测试，若各写各的挂载代码，
/// 很快就会各自踩坑：忘了覆写 `localStoreProvider`（于是误写真实磁盘）、
/// 忘了固定 `todayProvider`（于是断言随运行日期漂移）、
/// 忘了套 `ProviderScope`（于是 provider 读不到）。
/// 统一收在这里，测试只关心业务断言。
///
/// 两个函数都返回 `(store, container)`：
/// - `store` 用于断言落盘结果（`saveCount`、`snapshot`）
/// - `container` 用于直接读 provider 或再覆写
///
/// 约定：**所有 widget 测试都必须用这两个函数挂载**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/loop_island_app.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/services/app_paths.dart';
import 'package:loop_island/services/battery_whitelist.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';

/// 固定返回同一个目录的假数据路径，避免测试去打 `path_provider` 的平台通道。
class FixedAppPaths implements AppPaths {
  const FixedAppPaths([this.directory = '/test/loop_island']);

  final String directory;

  @override
  Future<String?> storageDirectory() async => directory;
}

/// 读不到路径的假实现（覆盖「显示未知」的分支）。
class UnknownAppPaths implements AppPaths {
  const UnknownAppPaths();

  @override
  Future<String?> storageDirectory() async => null;
}

/// 默认的电池白名单替身：模拟「平台不适用」，让状态卡片隐藏该行。
class _NullBatteryWhitelist implements BatteryWhitelist {
  const _NullBatteryWhitelist();

  @override
  Future<bool?> isIgnoringOptimizations() async => null;

  @override
  Future<bool> requestIgnoreOptimizations() async => false;
}

/// 挂载时使用的 provider 覆写集合。
///
/// [today] 会经 [dateOnly] 归一 —— 测试里随手传 `DateTime(2026, 9, 12, 18)`
/// 也不会让「今天」带上 18 点，避免出现只在下午跑测试才失败的诡异断言。
List<Override> _overrides({
  required InMemoryLocalStore store,
  DateTime? today,
  DateTime? now,
  NotificationService? notificationService,
  AppPaths? appPaths,
  required List<Override> extra,
}) {
  final fixedNow = now;
  return [
    localStoreProvider.overrideWithValue(store),
    if (today != null) todayProvider.overrideWithValue(dateOnly(today)),
    if (fixedNow != null) nowProvider.overrideWithValue(() => fixedNow),
    // 默认注入空实现：`AppShell` 会在每次数据变化后同步提醒，
    // 若走真实实现，每个 widget 测试都会去初始化时区库并打平台通道
    // （既慢又和被测逻辑无关）。需要断言调度行为时显式传 fake。
    notificationServiceProvider
        .overrideWithValue(notificationService ?? const NoopNotificationService()),
    // 同理：关于页要显示数据目录，但 `path_provider` 在单测里没有平台通道。
    appPathsProvider.overrideWithValue(appPaths ?? const FixedAppPaths()),
    // 电池白名单走真实 MethodChannel，在测试绑定里永远不会返回；
    // 默认注入「平台不适用」实现，需要断言该行为时显式传 Fake 覆写。
    batteryWhitelistProvider.overrideWithValue(_NullBatteryWhitelist()),
    ...extra,
  ];
}

/// 挂载整个应用（含底部 4 Tab 外壳），并注入内存存储。
///
/// - [data] 初始数据；为空表示全新用户。
/// - [store] 复用已有存储（模拟「重启应用」）；传了它时 [data] 被忽略。
/// - [today] 固定的「今天」，会自动归一到当天零点。
/// - [now] 固定的「当前时刻」（提醒调度用）；不传则用真实时间。
/// - [notificationService] 通知服务；不传则注入 [NoopNotificationService]。
/// - [appPaths] 数据目录来源；不传则注入固定路径。
///
/// 挂载后 `appDataProvider` **会立刻被加载**：`AppShell` 用 `IndexedStack`
/// 承载四个 Tab，四个页面都会被构建，而任务页会 `watch(appDataProvider)`。
/// 因此挂载完 `store.loadCount` 通常已是 1。
Future<({InMemoryLocalStore store, ProviderContainer container})>
    pumpLoopIslandApp(
  WidgetTester tester, {
  AppData? data,
  InMemoryLocalStore? store,
  DateTime? today,
  DateTime? now,
  NotificationService? notificationService,
  AppPaths? appPaths,
  List<Override> extraOverrides = const [],
  bool settle = true,
}) async {
  final localStore =
      store ?? InMemoryLocalStore(AppBackup.of(data ?? AppData.empty));
  final container = ProviderContainer(
    overrides: _overrides(
      store: localStore,
      today: today,
      now: now,
      notificationService: notificationService,
      appPaths: appPaths,
      extra: extraOverrides,
    ),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LoopIslandApp(),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  }
  return (store: localStore, container: container);
}

/// 只挂载某个子页面，但复用**真实的**主题、本地化与 `ProviderContainer`。
///
/// 适合测试单个页面/组件（例如任务编辑页），不必先点进导航。
/// 用 `LoopIslandApp(home: ...)` 而不是自己拼 `MaterialApp`，
/// 是为了让测试里的 `AnimalTheme` / `zh_CN` 与线上完全一致 ——
/// 否则「测试里按钮是灰的、真机是绿的」这类偏差查起来很痛苦。
Future<({InMemoryLocalStore store, ProviderContainer container})> pumpWithScope(
  WidgetTester tester,
  Widget child, {
  AppData? data,
  DateTime? today,
  DateTime? now,
  NotificationService? notificationService,
  AppPaths? appPaths,
  List<Override> extraOverrides = const [],
  bool settle = true,
}) async {
  final store = InMemoryLocalStore(AppBackup.of(data ?? AppData.empty));
  final container = ProviderContainer(
    overrides: _overrides(
      store: store,
      today: today,
      now: now,
      notificationService: notificationService,
      appPaths: appPaths,
      extra: extraOverrides,
    ),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LoopIslandApp(home: Scaffold(body: child)),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  }
  return (store: store, container: container);
}
