import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/services/notification_service.dart';

/// 任务 8.1：通知抽象层与能力探测。
void main() {
  group('8.1 通知 ID 生成', () {
    test('同一个 key 永远得到同一个 ID（跨进程也稳定）', () {
      // 用**写死的期望值**而不是「两次调用相等」：后者发现不了
      // 「换成一个不稳定的哈希实现」这种回归，而哈希一变，
      // 用户已经注册在系统里的提醒就会全部变成孤儿通知。
      expect(notificationIdFor('task:abc'), 1994244102);
      expect(notificationIdFor('task:task_1'), 1554223123);
      expect(notificationIdFor('cycle:cycle_1:2026-09-12'), 293145707);
    });

    test('不同 key 得到不同 ID', () {
      final ids = <int>{
        notificationIdFor('task:a'),
        notificationIdFor('task:b'),
        notificationIdFor('cycle:c:2026-09-12'),
        notificationIdFor('cycle:c:2026-09-13'),
      };
      expect(ids, hasLength(4));
    });

    test('ID 落在 Android 允许的非负 31 位整数范围内', () {
      final keys = <String>[
        '',
        'task:',
        'task:1',
        'cycle:循环计划:2026-09-12',
        'x' * 400,
      ];
      for (final key in keys) {
        final id = notificationIdFor(key);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });

  group('8.1 通知 payload', () {
    test('普通任务 payload 往返一致', () {
      final raw = reminderPayload(type: ReminderPayloadType.task, id: 't1');
      final parsed = ReminderPayload.parse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.type, ReminderPayloadType.task);
      expect(parsed.id, 't1');
      expect(parsed.dayKey, isNull);
    });

    test('循环计划 payload 带上日期', () {
      final raw = reminderPayload(
        type: ReminderPayloadType.cycle,
        id: 'c1',
        dayKey: '2026-09-12',
      );
      final parsed = ReminderPayload.parse(raw);
      expect(parsed!.type, ReminderPayloadType.cycle);
      expect(parsed.id, 'c1');
      expect(parsed.dayKey, '2026-09-12');
    });

    test('无法解析的 payload 一律返回 null，绝不抛异常', () {
      // 任务 8.6 要求「payload 无法解析时进入今日页」，
      // 所以这里必须能容忍任何脏数据。
      for (final raw in const [
        null,
        '',
        'not json',
        '[]',
        '{}',
        '{"type":"task"}',
        '{"id":"t1"}',
        '{"type":"","id":"t1"}',
        '{"type":"task","id":123}',
        '{"type":"task","id":""}',
      ]) {
        expect(
          ReminderPayload.parse(raw),
          isNull,
          reason: 'payload=$raw 应当被判为不可解析',
        );
      }
    });

    test('多余的字段不影响解析', () {
      final parsed =
          ReminderPayload.parse('{"type":"task","id":"t1","extra":123}');
      expect(parsed!.id, 't1');
    });

    test('日期字段类型不对时忽略它而不是整条判废', () {
      // 宽松解析：宁可少一个日期，也不要因为一个字段类型不对
      // 就让用户点了通知却什么反应都没有。
      final parsed = ReminderPayload.parse('{"type":"cycle","id":"c1","day":7}');
      expect(parsed, isNotNull);
      expect(parsed!.id, 'c1');
      expect(parsed.dayKey, isNull);
    });

    test('相等性按值比较', () {
      expect(
        ReminderPayload.parse('{"type":"task","id":"t1"}'),
        const ReminderPayload(type: ReminderPayloadType.task, id: 't1'),
      );
    });
  });

  group('8.1 空实现', () {
    test('不支持的平台返回 no-op 实现且不抛异常', () async {
      const service = NoopNotificationService();
      expect(service.isSupported, isFalse);
      expect(service.isInitialized, isFalse);

      expect(await service.init(), isFalse);
      expect(await service.init(onTap: (_) {}), isFalse);
      expect(await service.requestPermission(), isFalse);

      await expectLater(
        service.scheduleOnce(
          id: 1,
          title: 't',
          body: 'b',
          at: DateTime(2026, 9, 12, 9),
        ),
        completes,
      );
      await expectLater(
        service.scheduleDaily(id: 1, title: 't', body: 'b', minuteOfDay: 540),
        completes,
      );
      await expectLater(service.cancel(1), completes);
      await expectLater(service.cancelAll(), completes);
    });

    test('空实现不接受点击回调也不会崩', () async {
      const service = NoopNotificationService();
      await service.init(onTap: (payload) {
        fail('空实现不应该回调：$payload');
      });
    });
  });
}
