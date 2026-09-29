// 通知能力探针：在真实设备运行时里，用与应用生产代码完全相同的
// 初始化参数与调度参数，验证「init → 连续调度两条 → 待发送列表 → 取消」。
//
// 运行方式：
//   flutter test integration_test/notification_probe_test.dart -d windows
//   flutter test integration_test/notification_probe_test.dart -d <手机/模拟器>
//
// 这是排查「提醒静默不响」的诊断工具：如果探针调度成功（pending 列表
// 里有这两条）、约 2~3 分钟后系统也真的弹了通知，说明插件层没问题，
// 应用不响的原因在权限 / ROM 省电策略；如果 pending 里都没有，才是调度层问题。
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _probeFirst = 990001;
const _probeSecond = 990002;

Future<FlutterLocalNotificationsPlugin> _initLikeProduction() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(resolveLocalLocation(DateTime.now()));

  final plugin = FlutterLocalNotificationsPlugin();
  // 与 local_notification_service.dart 的 _initializationSettings 保持一致。
  const darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  final settings = const InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_stat_loop'),
    iOS: darwin,
    macOS: darwin,
    windows: WindowsInitializationSettings(
      appName: ReminderStrings.appName,
      appUserModelId: 'LoopIsland.LoopIsland.App.1',
      guid: 'd7f5c0a1-3b64-4c8e-9a02-6f1b2c3d4e50',
    ),
  );
  final ok = await plugin.initialize(settings);
  // ignore: avoid_print
  print('PROBE initialize() = $ok');
  return plugin;
}

Future<List<int>> _pendingIds(FlutterLocalNotificationsPlugin plugin) async {
  final requests = await plugin.pendingNotificationRequests();
  return requests.map((r) => r.id).toList();
}

Future<void> _scheduleLikeProduction(
  FlutterLocalNotificationsPlugin plugin, {
  required int id,
  required String title,
  required DateTime at,
}) {
  // 与 _zonedSchedule / _details 保持一致。
  final details = const NotificationDetails(
    android: AndroidNotificationDetails(
      ReminderStrings.channelId,
      ReminderStrings.channelName,
      channelDescription: ReminderStrings.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );
  return plugin.zonedSchedule(
    id,
    title,
    title,
    tz.TZDateTime.from(at, tz.local),
    details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('通知探针：初始化 + 连续调度两条 + 查询/取消', (tester) async {
    final plugin = await _initLikeProduction();

    final now = DateTime.now();
    await _scheduleLikeProduction(
      plugin,
      id: _probeFirst,
      title: '探针-第一条',
      at: now.add(const Duration(minutes: 2)),
    );
    await _scheduleLikeProduction(
      plugin,
      id: _probeSecond,
      title: '探针-第二条',
      at: now.add(const Duration(minutes: 3)),
    );

    final pending = await _pendingIds(plugin);
    // ignore: avoid_print
    print('PROBE pending = $pending');
    expect(pending, containsAll(<int>[_probeFirst, _probeSecond]),
        reason: '连续调度两条都必须进入系统待发送列表');

    await plugin.cancel(_probeFirst);
    final afterCancel = await _pendingIds(plugin);
    // ignore: avoid_print
    print('PROBE pending after cancel = $afterCancel');
    expect(afterCancel, isNot(contains(_probeFirst)));
    expect(afterCancel, contains(_probeSecond), reason: 'cancel 不得误伤其它提醒');

    await plugin.cancelAll();
    final afterCancelAll = await _pendingIds(plugin);
    // ignore: avoid_print
    print('PROBE pending after cancelAll = $afterCancelAll');
    expect(afterCancelAll, isNot(contains(_probeSecond)));
  });
}
