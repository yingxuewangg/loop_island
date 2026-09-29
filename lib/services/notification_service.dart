/// 本地通知的服务抽象（任务 8.1）。
///
/// 为什么要有这一层：
/// - `flutter_local_notifications` 的构造函数是**私有的**（类里只有
///   `factory FlutterLocalNotificationsPlugin()` + 私有构造），因此测试里
///   既不能 `extends` 也不能 `implements` 掉它的一大堆成员；把它收拢到
///   [NotificationBackend] 这个小接口后面，测试注入假实现即可跑完整链路
///   （和 `services/backup_io.dart` 的 `BackupIo` 是同一套做法）。
/// - 平台能力探测必须显式：不支持的平台返回 [NoopNotificationService]，
///   **不抛异常、不静默失败**，界面据此显示「当前平台不支持提醒」。
///
/// 分层：本文件与 `local_notification_service.dart` 同层，只依赖 `models`
/// 与 `core`；界面文案在 `lib/app/l10n_strings.dart`（`ReminderStrings`）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:meta/meta.dart';

/// 通知 payload 的类型。
abstract final class ReminderPayloadType {
  /// 普通任务提醒。
  static const task = 'task';

  /// 循环计划每日提醒。
  static const cycle = 'cycle';
}

/// 产出一条通知的 payload（JSON 字符串）。
///
/// 通知被点击时，系统只会把 payload 原样还回来（任务 8.6），
/// 因此它必须自带「点开哪个页面、哪个对象」所需的全部信息。
///
/// [at] 是这条提醒的调度时刻（epoch 毫秒）。带上它是为了在处理
/// 「通知启动应用」时能识别**过期payload**：Android 插件靠 Activity 的
/// 当前 Intent 判断是否通知启动，这个 Intent 可能跨启动残留，把一次
/// 普通打开误判成「点了旧通知」，随后自动跳转会把用户正在编辑的页面
/// 整个弹掉。超过约一天的 payload 只可能是残留，不该再导航。
String reminderPayload({
  required String type,
  required String id,
  String? dayKey,
  DateTime? at,
}) {
  return jsonEncode({
    'type': type,
    'id': id,
    if (dayKey != null) 'day': dayKey,
    if (at != null) 'at': at.millisecondsSinceEpoch,
  });
}

/// 解析后的通知 payload。
@immutable
class ReminderPayload {
  const ReminderPayload({
    required this.type,
    required this.id,
    this.dayKey,
    this.scheduledAt,
  });

  /// [ReminderPayloadType] 之一。
  final String type;

  /// 任务 id 或计划 id。
  final String id;

  /// 计划提醒对应的日期键（`yyyy-MM-dd`），普通任务提醒为 null。
  final String? dayKey;

  /// 这条提醒的调度时刻；旧版本 payload 没有该字段时为 null。
  final DateTime? scheduledAt;

  /// payload 是否明显过期（调度时刻在 [maxAge] 之前）。
  ///
  /// 没有调度时刻的旧 payload 一律视为「不过期」——它们可能来自旧版本
  /// 写入的通知，宁可信一次也不能把真实点击丢掉。
  bool isStale({Duration maxAge = const Duration(hours: 24), DateTime? now}) {
    final at = scheduledAt;
    if (at == null) {
      return false;
    }
    final reference = now ?? DateTime.now();
    return reference.difference(at) > maxAge;
  }

  /// 解析 payload；**任何异常或字段缺失都返回 `null`**。
  ///
  /// 任务 8.6 要求「payload 无法解析时进入今日页」，所以这里绝不能抛异常：
  /// 通知是系统在应用可能已经升级过的前提下发回来的，格式对不上很正常。
  static ReminderPayload? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final type = decoded['type'];
      final id = decoded['id'];
      if (type is! String || id is! String || type.isEmpty || id.isEmpty) {
        return null;
      }
      final day = decoded['day'];
      final at = decoded['at'];
      return ReminderPayload(
        type: type,
        id: id,
        dayKey: (day is String && day.isNotEmpty) ? day : null,
        scheduledAt: at is int && at > 0
            ? DateTime.fromMillisecondsSinceEpoch(at)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderPayload &&
          other.type == type &&
          other.id == id &&
          other.dayKey == dayKey &&
          other.scheduledAt == scheduledAt;

  @override
  int get hashCode => Object.hash(type, id, dayKey, scheduledAt);

  @override
  String toString() => 'ReminderPayload($type/$id'
      '${dayKey == null ? '' : '@$dayKey'}'
      '${scheduledAt == null ? '' : ' @${scheduledAt!.toIso8601String()}'})';
}

/// 通知被点击时的回调，参数是原始 payload（可能为 null 或无法解析）。
typedef NotificationTapCallback = void Function(String? payload);

/// 系统里一条「待发送提醒」的摘要。
///
/// 只带 id、标题与正文，供两处使用：
/// - 提醒设置页展示「已经排进系统几条、都是什么」，回答「是没排上，
///   还是排上了系统没弹」这个排查问题；
/// - 调度器冷启动时与系统实际状态做差分，避免把已经排好的闹钟
///   全部撤销重建（重建期间应用被杀或某条失败就会丢提醒）。
@immutable
class PendingNotificationSummary {
  const PendingNotificationSummary({
    required this.id,
    this.title,
    this.body,
  });

  final int id;
  final String? title;
  final String? body;
}

/// 通知 ID 的生成规则。
///
/// **必须是稳定哈希**：同一个任务在重启应用、重装应用之后都要落到同一个
/// 通知 ID 上，否则「修改提醒」会变成「多出一条旧提醒」。
/// 因此不能用 `String.hashCode` —— Dart 的字符串哈希在不同进程间不稳定。
///
/// 这里用 FNV-1a 32 位再掩掉符号位，得到 `0..0x7FFFFFFF`。
int notificationIdFor(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    // 乘 16777619 后截回 32 位（Dart 的 int 在 VM 上是 64 位）
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// 本地通知服务。
///
/// 实现必须满足：**任何平台调用失败都不能把异常抛给界面**。
/// 通知是「锦上添花」的能力，系统拒绝授权、厂商 ROM 阉割了闹钟、
/// 桌面端没有通知中心 —— 这些都只应导致提醒静默失效，而不是应用崩溃。
abstract class NotificationService {
  /// 当前平台是否支持本地通知。
  bool get isSupported;

  /// 是否已经成功初始化（用于界面判断是否需要申请权限）。
  bool get isInitialized;

  /// 初始化底层插件与本地时区库；**重复调用幂等**。
  ///
  /// 返回是否可用。不支持的平台直接返回 `false`，不抛异常。
  /// [onTap] 会覆盖上一次注册的点击回调（插件只允许初始化一次，
  /// 因此回调由本层保存并转发）。
  Future<bool> init({NotificationTapCallback? onTap});

  /// 申请通知权限。不支持的平台返回 `false`，无需授权的平台返回 `true`。
  Future<bool> requestPermission();

  /// 注册一条**一次性**提醒。[at] 必须晚于当前时间，否则忽略。
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  });

  /// 注册一条「每天同一时刻」的重复提醒。
  ///
  /// 循环计划的每日提醒**不用**它 —— 见 `reminder_scheduler.dart` 的说明：
  /// 「今天是第 x/N 天」这种逐日变化的文案用重复通知无法表达。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  });

  /// 取消一条提醒；不存在时是空操作。
  Future<void> cancel(int id);

  /// 取消全部已显示与待发送的通知（关闭提醒总开关时调用）。
  Future<void> cancelAll();

  /// 系统当前待发送的提醒列表；查询失败返回空列表（不抛异常）。
  ///
  /// 提醒「静默不响」只有两种可能：没排进系统，或排进了系统但系统没弹
  /// （权限被拒 / ROM 拦截）。这个查询把两种情况区分开。
  Future<List<PendingNotificationSummary>> pendingNotifications();

  /// 精确闹钟权限是否已授予。
  ///
  /// 只有 Android 12+ 有这个概念：未授予时调度退回非精确模式，
  /// 提醒可能晚几十秒到几分钟。`null` 表示平台不适用或无法判断。
  Future<bool?> exactAlarmsEnabled();

  /// 应用是不是**被点通知启动**的？是的话返回那条通知的 payload。
  ///
  /// 热启动（应用已在运行）走 [init] 注册的 `onTap` 回调；
  /// 冷启动时那次点击发生在应用起来之前，只能在这里补回来。
  /// 必须在 [init] 之后调用，否则底层插件还没准备好。
  Future<String?> initialPayload();
}

/// 不支持的平台上的空实现：所有方法都成功返回、什么都不做。
///
/// 刻意**不抛 `UnsupportedError`**：调用方（每日同步、设置页）不应该
/// 为了「这个平台没有通知」而到处写 try/catch。
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  bool get isSupported => false;

  @override
  bool get isInitialized => false;

  @override
  Future<bool> init({NotificationTapCallback? onTap}) async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {}

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<PendingNotificationSummary>> pendingNotifications() async =>
      const [];

  @override
  Future<bool?> exactAlarmsEnabled() async => null;

  @override
  Future<String?> initialPayload() async => null;
}

/// 通知平台的底层调用面（真实实现在 `local_notification_service.dart`）。
///
/// 存在的两个理由，缺一不可：
/// 1. **可测试**：见文件头注释（插件的私有构造函数）。
/// 2. **依赖收口**：`flutter_local_notifications` 只出现在一个文件里，
///    将来换插件（或加 Web 推送）只改那一处。
abstract class NotificationBackend {
  /// 初始化插件与本地时区库；重复调用必须幂等。
  Future<bool> init({required NotificationTapCallback onTap});

  /// 申请通知权限（Android 13+ / iOS）与精确闹钟权限（Android 12+）。
  ///
  /// [platform] 由 [LocalNotificationService] 传入而不是实现自己探测，
  /// 这样「模拟在某个平台上运行」的测试才能覆盖到平台分派逻辑。
  Future<bool> requestPermission(TargetPlatform platform);

  /// 在本地时刻 [at] 提醒一次。
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  });

  /// 每天 [minuteOfDay] 提醒一次。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  });

  /// 取消一条通知。
  Future<void> cancel(int id);

  /// 取消全部已显示与待发送的通知。
  Future<void> cancelAll();

  /// 系统当前待发送的提醒列表（见 [NotificationService.pendingNotifications]）。
  Future<List<PendingNotificationSummary>> pendingNotifications();

  /// 精确闹钟权限是否已授予（见 [NotificationService.exactAlarmsEnabled]）。
  Future<bool?> exactAlarmsEnabled();

  /// 冷启动时那条通知的 payload（不是被通知启动则返回 null）。
  Future<String?> initialPayload();
}
