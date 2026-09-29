import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 假的底层后端：只记录调用，不碰平台通道。
class _FakeBackend implements NotificationBackend {
  _FakeBackend({this.initResult = true, this.launchPayload});

  /// 可变：测试「失败 → 重试成功」的序列时中途翻转。
  bool initResult;
  final String? launchPayload;

  int initCount = 0;
  int permissionCount = 0;
  final List<TargetPlatform> permissionPlatforms = <TargetPlatform>[];
  final List<Map<String, Object?>> onceCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> dailyCalls = <Map<String, Object?>>[];
  final List<int> cancelled = <int>[];
  int cancelAllCount = 0;
  NotificationTapCallback? onTap;

  @override
  Future<bool> init({required NotificationTapCallback onTap}) async {
    initCount++;
    this.onTap = onTap;
    return initResult;
  }

  @override
  Future<bool> requestPermission(TargetPlatform platform) async {
    permissionCount++;
    permissionPlatforms.add(platform);
    return true;
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    onceCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'at': at,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int minuteOfDay,
    String? payload,
  }) async {
    dailyCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'minuteOfDay': minuteOfDay,
      'payload': payload,
    });
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Future<List<PendingNotificationSummary>> pendingNotifications() async {
    pendingQueries++;
    return pending;
  }

  int pendingQueries = 0;
  List<PendingNotificationSummary> pending = const [];

  bool? exactAlarmsResult;

  @override
  Future<bool?> exactAlarmsEnabled() async => exactAlarmsResult;

  @override
  Future<String?> initialPayload() async => launchPayload;
}

/// 任务 8.2：本地通知初始化与权限申请。
void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('8.2 本地时区解析', () {
    test('解析出的时区与设备当前 UTC 偏移一致', () {
      final now = DateTime.now();
      final location = resolveLocalLocation(now);
      final zone = location.timeZone(now.millisecondsSinceEpoch);
      expect(
        zone.offset,
        now.timeZoneOffset.inMilliseconds,
        reason: '偏移不一致会让「早上 9 点」变成别的时刻',
      );
    });

    test('零偏移的设备落到 UTC 或同为 UTC 的时区', () {
      final utc = DateTime.utc(2026, 9, 12, 10);
      final location = resolveLocalLocation(utc);
      expect(location.timeZone(utc.millisecondsSinceEpoch).offset, 0);
    });

    test('优先挑非夏令时的时区，避免切换夏令时时整体挪一小时', () {
      final now = DateTime.now();
      final target = now.timeZoneOffset.inMilliseconds;
      final epoch = now.millisecondsSinceEpoch;
      // 只在「确实存在非夏令时候选」时才断言，因此不依赖跑测试的机器在哪个时区
      final hasNonDst = tz.timeZoneDatabase.locations.values.any((location) {
        final zone = location.timeZone(epoch);
        return zone.offset == target && !zone.isDst;
      });

      final resolved = resolveLocalLocation(now);
      expect(resolved.timeZone(epoch).offset, target);
      if (hasNonDst) {
        expect(resolved.timeZone(epoch).isDst, isFalse);
      }
    });
  });

  group('8.2 平台能力探测', () {
    test('Android / Windows 支持，Linux / Fuchsia / Web 不支持', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(
          LocalNotificationService(backend: _FakeBackend(), platform: platform)
              .isSupported,
          isTrue,
          reason: '$platform 应当被判定为支持',
        );
      }
      for (final platform in const [
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          LocalNotificationService(backend: _FakeBackend(), platform: platform)
              .isSupported,
          isFalse,
          reason: '$platform 应当被判定为不支持',
        );
      }
    });

    test('不支持的平台：init 返回 false 且完全不碰后端', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.linux,
      );

      expect(await service.init(), isFalse);
      expect(backend.initCount, 0, reason: '不支持的平台不该去初始化插件');
      expect(service.isInitialized, isTrue, reason: '问过了就该记住结论');

      await service.scheduleOnce(
        id: 1,
        title: 't',
        body: 'b',
        at: DateTime(2026, 9, 12, 9),
      );
      await service.scheduleDaily(id: 1, title: 't', body: 'b', minuteOfDay: 540);
      await service.cancel(1);
      await service.cancelAll();
      expect(backend.onceCalls, isEmpty);
      expect(backend.dailyCalls, isEmpty);
      expect(backend.cancelled, isEmpty);
      expect(backend.cancelAllCount, 0);
      expect(await service.requestPermission(), isFalse);
      expect(backend.permissionCount, 0);
    });
  });

  group('8.2 初始化幂等', () {
    test('重复 init 只真正初始化一次', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      expect(await service.init(), isTrue);
      expect(await service.init(), isTrue);
      expect(await service.init(onTap: (_) {}), isTrue);
      expect(backend.initCount, 1);
      expect(service.isInitialized, isTrue);
    });

    test('并发 init 也只初始化一次', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      final results = await Future.wait([
        service.init(),
        service.init(),
        service.init(),
      ]);
      expect(results, everyElement(isTrue));
      expect(backend.initCount, 1);
    });

    test('初始化失败时返回 false，并且不影响后续调用不抛异常', () async {
      final backend = _FakeBackend(initResult: false);
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      expect(await service.init(), isFalse);
      expect(await service.requestPermission(), isFalse);
      expect(backend.permissionCount, 0);
      await expectLater(
        service.scheduleOnce(
          id: 1,
          title: 't',
          body: 'b',
          at: DateTime(2026, 9, 12, 9),
        ),
        completes,
      );
      expect(backend.onceCalls, isEmpty);
    });

    test('初始化失败不缓存：下一次 init 会重新尝试并可能成功', () async {
      final backend = _FakeBackend(initResult: false);
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      expect(await service.init(), isFalse);
      expect(backend.initCount, 1);
      expect(
        service.isInitialized,
        isFalse,
        reason: '初始化没成功就不能谎报已初始化',
      );

      backend.initResult = true;
      expect(
        await service.init(),
        isTrue,
        reason: '失败必须允许重试 —— 否则一次瞬时失败会让本进程的提醒全部失声',
      );
      expect(backend.initCount, 2);
      expect(service.isInitialized, isTrue);
    });

    test('init 失败期间调度被跳过；重试成功后调度恢复正常', () async {
      final backend = _FakeBackend(initResult: false);
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );
      final at = DateTime(2026, 9, 12, 9);

      await service.scheduleOnce(id: 1, title: 't', body: 'b', at: at);
      expect(backend.onceCalls, isEmpty, reason: '没初始化成功前不能调度');

      backend.initResult = true;
      await service.scheduleOnce(id: 1, title: 't', body: 'b', at: at);
      expect(
        backend.onceCalls,
        hasLength(1),
        reason: '自愈之后调度必须恢复，而不是永远静默',
      );
    });

    test('并发 init 在失败后各自重试，不共享失败结果', () async {
      final backend = _FakeBackend(initResult: false);
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      expect(await Future.wait([service.init(), service.init()]),
          everyElement(isFalse));
      expect(backend.initCount, 1, reason: '同一次尝试内的并发调用共享同一个 Future');

      backend.initResult = true;
      expect(await service.init(), isTrue);
      expect(backend.initCount, 2);
    });
  });

  group('8.2 权限与调度转发', () {
    test('requestPermission 把生效平台传给后端', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.windows,
      );

      expect(await service.requestPermission(), isTrue);
      expect(backend.permissionCount, 1);
      expect(backend.permissionPlatforms, [TargetPlatform.windows]);
    });

    test('scheduleOnce 原样转发参数', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );
      final at = DateTime(2026, 9, 12, 9, 30);

      await service.scheduleOnce(
        id: 7,
        title: '写周报',
        body: '到点啦',
        at: at,
        payload: '{"type":"task","id":"t1"}',
      );

      expect(backend.onceCalls, hasLength(1));
      expect(backend.onceCalls.single['id'], 7);
      expect(backend.onceCalls.single['title'], '写周报');
      expect(backend.onceCalls.single['at'], at);
      expect(backend.onceCalls.single['payload'], '{"type":"task","id":"t1"}');
    });

    test('scheduleDaily 转发一天内分钟数', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.windows,
      );

      await service.scheduleDaily(
        id: 8,
        title: '8 天计划',
        body: '今天是第 1/8 天',
        minuteOfDay: 540,
      );

      expect(backend.dailyCalls, hasLength(1));
      expect(backend.dailyCalls.single['minuteOfDay'], 540);
    });

    test('cancel / cancelAll 转发到底层', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      await service.cancel(3);
      await service.cancelAll();

      expect(backend.cancelled, [3]);
      expect(backend.cancelAllCount, 1);
    });

    test('点击通知时把 payload 转给注册的回调', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      String? received;
      await service.init(onTap: (payload) => received = payload);
      backend.onTap?.call('{"type":"task","id":"t1"}');

      expect(received, '{"type":"task","id":"t1"}');
    });

    test('后注册的 onTap 覆盖先前的（插件只允许初始化一次）', () async {
      final backend = _FakeBackend();
      final service = LocalNotificationService(
        backend: backend,
        platform: TargetPlatform.android,
      );

      final received = <String?>[];
      await service.init(onTap: received.add);
      await service.init(onTap: (payload) => received.add('第二次:$payload'));
      backend.onTap?.call('p1');

      expect(received, ['第二次:p1']);
    });

    test('cold start 的 payload 透传，不支持的平台返回 null', () async {
      final service = LocalNotificationService(
        backend: _FakeBackend(launchPayload: '{"type":"cycle","id":"c1"}'),
        platform: TargetPlatform.android,
      );
      expect(await service.initialPayload(), '{"type":"cycle","id":"c1"}');

      final unsupported = LocalNotificationService(
        backend: _FakeBackend(launchPayload: '{"type":"cycle","id":"c1"}'),
        platform: TargetPlatform.linux,
      );
      expect(await unsupported.initialPayload(), isNull);
    });
  });
}
