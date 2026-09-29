/// 本地通知的真实实现（任务 8.2）。
///
/// 本文件是**唯一**允许 import `flutter_local_notifications` 的地方：
/// 其它层只认 `notification_service.dart` 里的抽象，测试注入假实现。
///
/// 设计要点：
/// - **时区**：`zonedSchedule` 要求 `TZDateTime`，而 `timezone` 包初始化后
///   默认时区是 UTC，直接用会让「早上 9 点」变成「UTC 9 点」。
///   这里不引入 `flutter_timezone` 之类的额外依赖，而是按设备的当前 UTC
///   偏移在时区库里挑一个偏移一致的时区（见 [resolveLocalLocation]）——
///   本地通知只关心墙上时钟的偏移，同偏移的时区在调度上完全等价。
/// - **精确闹钟**：Android 12+ 需要额外权限才允许精确闹钟；拿不到时自动
///   退回非精确模式，而不是让提醒彻底失效。
/// - **异常**：所有平台调用都被吞掉。通知失败只应导致提醒不响，
///   绝不能把界面搞崩。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Windows 通知激活回调所需的 GUID；**一旦发布就不能改**，
/// 改了等于换了一个通知来源（旧的待发送通知会认不出来）。
const String _kWindowsNotificationGuid = 'd7f5c0a1-3b64-4c8e-9a02-6f1b2c3d4e50';

/// Windows 的 AppUserModelID，格式为
/// `CompanyName.ProductName.SubProduct.VersionInformation`。
const String _kWindowsAppUserModelId = 'LoopIsland.LoopIsland.App.1';

/// 依据设备当前的 UTC 偏移，在时区数据库里挑一个偏移一致的时区。
///
/// 优先挑**当前不处于夏令时**的时区，这样名字更稳定、也更不容易在
/// 切换夏令时的时候把提醒整体挪动一小时。
///
/// 必须先调用 `tzdata.initializeTimeZones()`，否则时区库是空的。
tz.Location resolveLocalLocation(DateTime now) {
  final targetOffset = now.timeZoneOffset.inMilliseconds;
  final epoch = now.millisecondsSinceEpoch;

  tz.Location? firstMatch;
  for (final location in tz.timeZoneDatabase.locations.values) {
    final zone = location.timeZone(epoch);
    if (zone.offset != targetOffset) {
      continue;
    }
    if (!zone.isDst) {
      return location;
    }
    firstMatch ??= location;
  }
  // 全部候选都在夏令时里（例如某些南半球时区）时退回第一个匹配；
  // 完全没有匹配（时区库缺失或设备用了奇怪的偏移）则退回 UTC。
  return firstMatch ?? tz.UTC;
}

/// `NotificationBackend` 的真实实现：`flutter_local_notifications` 适配层。
class FlutterNotificationBackend implements NotificationBackend {
  FlutterNotificationBackend();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<bool>? _initializing;
  NotificationTapCallback? _onTap;
  bool _timeZonesReady = false;

  @override
  Future<bool> init({required NotificationTapCallback onTap}) {
    // 允许后注册的回调覆盖先前的：插件只初始化一次，回调由本层保存转发。
    _onTap = onTap;
    return _initializing ??= _doInit();
  }

  Future<bool> _doInit() async {
    _ensureTimeZones();
    bool ok;
    try {
      ok = await _plugin.initialize(
            _initializationSettings(),
            onDidReceiveNotificationResponse: (response) =>
                _onTap?.call(response.payload),
          ) ??
          true;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // 失败不缓存：清掉 in-flight 标记，下一次 init / 调度会重新尝试。
      // 否则一次瞬时失败会让本进程内所有提醒静默失效且无法自愈。
      _initializing = null;
    }
    return ok;
  }

  void _ensureTimeZones() {
    if (_timeZonesReady) {
      return;
    }
    tzdata.initializeTimeZones();
    tz.setLocalLocation(resolveLocalLocation(DateTime.now()));
    _timeZonesReady = true;
  }

  InitializationSettings _initializationSettings() {
    // 通知栏小图标必须是「白色剪影 + 透明底」：系统只取它的 alpha 通道来着色，
    // 直接塞一张彩色 launcher 图标会被渲染成一个白色方块。
    // `ic_stat_loop` 是一枚手绘的白色环形箭头，五档密度都在 res/drawable-* 里。
    const android = AndroidInitializationSettings('@drawable/ic_stat_loop');
    // 三个 requestXxxPermission 一律关掉：权限统一由 requestPermission()
    // 在「首次进入提醒设置」时申请，避免开屏就弹系统弹窗。
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const windows = WindowsInitializationSettings(
      appName: ReminderStrings.appName,
      appUserModelId: _kWindowsAppUserModelId,
      guid: _kWindowsNotificationGuid,
    );
    return const InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: windows,
    );
  }

  @override
  Future<bool> requestPermission(TargetPlatform platform) async {
    try {
      switch (platform) {
        case TargetPlatform.android:
          final android = _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          final granted = await android?.requestNotificationsPermission();
          // 精确闹钟权限拿不到也不影响：调度时会自动退回非精确模式。
          try {
            await android?.requestExactAlarmsPermission();
          } catch (_) {
            // 忽略：非致命
          }
          return granted ?? true;

        case TargetPlatform.iOS:
          final ios = _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
          final granted =
              await ios?.requestPermissions(alert: true, badge: true, sound: true);
          return granted ?? true;

        case TargetPlatform.macOS:
          final mac = _plugin.resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>();
          final granted =
              await mac?.requestPermissions(alert: true, badge: true, sound: true);
          return granted ?? true;

        case TargetPlatform.windows:
          // Windows 的 Toast 通知不需要运行时授权。
          return true;

        case TargetPlatform.linux:
        case TargetPlatform.fuchsia:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) {
    return _zonedSchedule(
      id: id,
      title: title,
      body: body,
      when: tz.TZDateTime.from(at, tz.local),
      payload: payload,
    );
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  }) {
    return _zonedSchedule(
      id: id,
      title: title,
      body: body,
      when: _nextDailyOccurrence(minuteOfDay),
      payload: payload,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// [minuteOfDay] 在本地时区里的下一个发生时刻（严格晚于此刻）。
  tz.TZDateTime _nextDailyOccurrence(int minuteOfDay) {
    final clamped = minuteOfDay.clamp(0, 24 * 60 - 1);
    final hour = clamped ~/ 60;
    final minute = clamped % 60;
    final now = tz.TZDateTime.now(tz.local);

    final today = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (today.isAfter(now)) {
      return today;
    }
    // 用构造函数做「+1 天」而不是 `add(Duration(days: 1))`：
    // 后者加的是绝对时长，夏令时切换那天会把墙上时钟挪掉一小时。
    return tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, hour, minute);
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final details = _details();
    // 调度模式两级回退：
    // 1. exactAllowWhileIdle —— 首选；但 Android 12+ 默认没有
    //    SCHEDULE_EXACT_ALARM 权限，会抛异常；
    // 2. inexactAllowWhileIdle —— 兜底，不弹错但允许系统合并延迟
    //    （表现就是提醒晚几十秒到几分钟；根治要靠用户授权精确闹钟，
    //    提醒设置页的「系统调度状态」卡片负责引导）。
    //    注意插件的 alarmClock 模式也被同一权限检查拦住，无法绕过。
    const fallbackModes = [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ];
    for (final (index, mode) in fallbackModes.indexed) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: mode,
          payload: payload,
          matchDateTimeComponents: matchDateTimeComponents,
        );
        return;
      } catch (error) {
        // 本级失败（最常见：精确闹钟权限被拒）就试下一级；
        // 全部失败只能放弃这一条 —— 用户关掉通知权限属于正常情况。
        if (kDebugMode) {
          debugPrint('[notify] 调度失败（$mode），'
              '${index == fallbackModes.length - 1 ? '放弃本条' : '尝试下一级'}：$error');
        }
      }
    }
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        ReminderStrings.channelId,
        ReminderStrings.channelName,
        channelDescription: ReminderStrings.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> cancelAll() async {
    // `cancelAll` 清掉已弹出的与待发送的；`cancelAllPendingNotifications`
    // 再兜一层，避免某些平台实现只清其中一类。
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // 忽略：下面继续尝试另一种
    }
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      return;
    }
  }

  @override
  Future<List<PendingNotificationSummary>> pendingNotifications() async {
    try {
      final requests = await _plugin.pendingNotificationRequests();
      return [
        for (final request in requests)
          PendingNotificationSummary(
            id: request.id,
            title: request.title,
            body: request.body,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool?> exactAlarmsEnabled() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // 非 Android 平台拿不到 android 实例，返回 null 表示「不适用」。
      return await android?.canScheduleExactNotifications();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> initialPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) {
        return null;
      }
      return details.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }
}

/// 生产环境使用的通知服务。
class LocalNotificationService implements NotificationService {
  LocalNotificationService({
    NotificationBackend? backend,
    TargetPlatform? platform,
  })  : _backend = backend ?? FlutterNotificationBackend(),
        _platformOverride = platform;

  final NotificationBackend _backend;
  final TargetPlatform? _platformOverride;

  Future<bool>? _initializing;
  bool _initialized = false;

  /// 生效的点击回调；后注册的覆盖先前的（插件只允许初始化一次，
  /// 所以回调由本层保存、用一个稳定的闭包转发进去）。
  NotificationTapCallback? _onTap;

  /// 生效的平台（测试可覆写，模拟「在不支持的平台上运行」）。
  TargetPlatform get targetPlatform => _platformOverride ?? defaultTargetPlatform;

  @override
  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    switch (targetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<bool> init({NotificationTapCallback? onTap}) {
    if (onTap != null) {
      _onTap = onTap;
    }
    if (!isSupported) {
      _initialized = true;
      return Future.value(false);
    }
    return _initializing ??= _doInit();
  }

  Future<bool> _doInit() async {
    final ok = await _backend.init(
      onTap: (payload) => _onTap?.call(payload),
    );
    if (ok) {
      _initialized = true;
    } else {
      // 失败不缓存：下一次 init / 调度会重新尝试初始化，
      // 否则一次瞬时失败会让本进程内所有提醒静默失效（调度全部走
      // `if (!await init()) return`）且重启前无法自愈。
      if (kDebugMode) {
        debugPrint('[notify] 通知插件初始化失败，将在下次调度时重试');
      }
      _initializing = null;
    }
    return ok;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await init()) {
      return false;
    }
    return _backend.requestPermission(targetPlatform);
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    if (!await init()) {
      return;
    }
    return _backend.scheduleOnce(
      id: id,
      title: title,
      body: body,
      at: at,
      payload: payload,
    );
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  }) async {
    if (!await init()) {
      return;
    }
    return _backend.scheduleDaily(
      id: id,
      title: title,
      body: body,
      minuteOfDay: minuteOfDay,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!await init()) {
      return;
    }
    return _backend.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    if (!await init()) {
      return;
    }
    return _backend.cancelAll();
  }

  @override
  Future<List<PendingNotificationSummary>> pendingNotifications() async {
    if (!await init()) {
      return const [];
    }
    return _backend.pendingNotifications();
  }

  @override
  Future<bool?> exactAlarmsEnabled() async {
    if (!await init()) {
      return null;
    }
    return _backend.exactAlarmsEnabled();
  }

  @override
  Future<String?> initialPayload() async {
    if (!await init()) {
      return null;
    }
    return _backend.initialPayload();
  }
}

/// 通知服务；测试里覆写成 [NoopNotificationService] 或假实现。
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);
