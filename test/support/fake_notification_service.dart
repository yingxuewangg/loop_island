/// 记录调用过程的假通知服务（任务 8.12 要求的测试替身）。
///
/// 与 `FakeBackupIo` 同一套思路：真实的 `LocalNotificationService` 会用
/// `flutter_local_notifications` 打平台通道，单测里跑不起来；界面与调度器
/// 都只依赖 `NotificationService` 抽象，所以注入这个假实现就能覆盖
/// 「新增 / 修改 / 删除 → 调度与取消序列」的完整链路。
library;

import 'package:loop_island/services/notification_service.dart';

/// 一次 `scheduleOnce` 调用的参数快照。
class FakeOnceCall {
  const FakeOnceCall({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;

  @override
  String toString() => 'FakeOnceCall($id, $title, $body, $at)';
}

/// 一次 `scheduleDaily` 调用的参数快照。
class FakeDailyCall {
  const FakeDailyCall({
    required this.id,
    required this.title,
    required this.body,
    required this.minuteOfDay,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final int minuteOfDay;
  final String? payload;

  @override
  String toString() => 'FakeDailyCall($id, $title, $body, $minuteOfDay)';
}

/// 假通知服务。
class FakeNotificationService implements NotificationService {
  FakeNotificationService({
    this.supported = true,
    this.permissionGranted = true,
    this.initResult = true,
    this.launchPayload,
  });

  /// 模拟平台是否支持本地通知。
  final bool supported;

  /// 模拟权限申请结果。可变：测试「重新申请权限」流程时中途翻转。
  bool permissionGranted;

  /// 模拟初始化结果。
  final bool initResult;

  /// 模拟「应用是被点这条通知启动的」（冷启动）。
  final String? launchPayload;

  final List<FakeOnceCall> onceCalls = <FakeOnceCall>[];
  final List<FakeDailyCall> dailyCalls = <FakeDailyCall>[];
  final List<int> cancelled = <int>[];

  int initCount = 0;
  int permissionCount = 0;
  int cancelAllCount = 0;

  /// 模拟「查询系统待发送提醒失败」。
  bool pendingQueryFails = false;

  /// 最近一次注册进来的点击回调。
  NotificationTapCallback? tapHandler;

  /// 当前仍然注册着的通知 id（调度加、取消减、cancelAll 清空）。
  final Set<int> liveIds = <int>{};

  /// 已注册通知的标题/正文，供 [pendingNotifications] 如实回报
  /// （调度器的冷启动差分要靠它比对文案）。
  final Map<int, FakeOnceCall> _onceById = <int, FakeOnceCall>{};
  final Map<int, FakeDailyCall> _dailyById = <int, FakeDailyCall>{};

  /// 所有一次性提醒的 id。
  List<int> get onceIds => onceCalls.map((e) => e.id).toList();

  /// 触发一次「用户点了通知」。
  void tap(String? payload) => tapHandler?.call(payload);

  @override
  bool get isSupported => supported;

  @override
  bool get isInitialized => initCount > 0;

  @override
  Future<bool> init({NotificationTapCallback? onTap}) async {
    initCount++;
    tapHandler = onTap;
    return supported && initResult;
  }

  @override
  Future<bool> requestPermission() async {
    permissionCount++;
    return supported && permissionGranted;
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    final call =
        FakeOnceCall(id: id, title: title, body: body, at: at, payload: payload);
    onceCalls.add(call);
    _onceById[id] = call;
    _dailyById.remove(id);
    liveIds.add(id);
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  }) async {
    final call = FakeDailyCall(
      id: id,
      title: title,
      body: body,
      minuteOfDay: minuteOfDay,
      payload: payload,
    );
    dailyCalls.add(call);
    _dailyById[id] = call;
    _onceById.remove(id);
    liveIds.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    liveIds.remove(id);
    _onceById.remove(id);
    _dailyById.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    liveIds.clear();
    _onceById.clear();
    _dailyById.clear();
  }

  @override
  Future<List<PendingNotificationSummary>> pendingNotifications() async {
    pendingQueries++;
    if (pendingQueryFails) {
      throw StateError('模拟查询系统待发送提醒失败');
    }
    // 如实回报已注册通知的标题与正文：调度器冷启动差分要靠它比对文案，
    // 返回假的文案会导致「系统里其实有、却被判定要重排」。
    return [
      for (final id in liveIds)
        PendingNotificationSummary(
          id: id,
          title: _onceById[id]?.title ?? _dailyById[id]?.title,
          body: _onceById[id]?.body ?? _dailyById[id]?.body,
        ),
    ];
  }

  int pendingQueries = 0;

  /// 模拟精确闹钟权限状态；`null` 表示平台不适用。
  bool? exactAlarmsEnabledResult;

  @override
  Future<bool?> exactAlarmsEnabled() async => exactAlarmsEnabledResult;

  @override
  Future<String?> initialPayload() async => launchPayload;
}
