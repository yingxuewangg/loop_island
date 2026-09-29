import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/remind_slots.dart';

/// 多时段提醒的公共规则（一天提醒 N 次）。
void main() {
  group('一天内时刻列表规范化', () {
    test('升序排列', () {
      expect(normalizeMinuteSlots([900, 630, 540]), [540, 630, 900]);
    });

    test('去重：同一个时刻提醒两次没有意义', () {
      expect(normalizeMinuteSlots([540, 630, 540]), [540, 630]);
    });

    test('夹到 0..1439，脏数据不会溢到相邻日期', () {
      expect(normalizeMinuteSlots([-100, 5000]), [0, 1439]);
    });

    test('截断到上限', () {
      final many = List<int>.generate(9, (i) => i * 60);
      final normalized = normalizeMinuteSlots(many);
      expect(normalized, hasLength(kMaxRemindSlots));
      // 截断的是「排完序之后的末尾」，保留最早的那几个
      expect(normalized.first, 0);
      expect(normalized.last, (kMaxRemindSlots - 1) * 60);
    });

    test('空输入得到空列表', () {
      expect(normalizeMinuteSlots(const []), isEmpty);
    });

    test('返回不可变列表，防止调用方就地改坏模型', () {
      final normalized = normalizeMinuteSlots([540]);
      expect(() => normalized.add(600), throwsUnsupportedError);
    });
  });

  group('绝对时刻列表规范化', () {
    test('按时间升序并去重', () {
      final a = DateTime(2026, 9, 12, 15, 30);
      final b = DateTime(2026, 9, 12, 10, 30);
      expect(normalizeInstantSlots([a, b, a]), [b, a]);
    });

    test('同一时刻的不同 DateTime 实例视为重复', () {
      expect(
        normalizeInstantSlots([
          DateTime(2026, 9, 12, 10, 30),
          DateTime(2026, 9, 12, 10, 30),
        ]),
        hasLength(1),
      );
    });

    test('截断到上限', () {
      final many = List<DateTime>.generate(
        8,
        (i) => DateTime(2026, 9, 12, i),
      );
      expect(normalizeInstantSlots(many), hasLength(kMaxRemindSlots));
    });
  });

  group('上限判断与展示', () {
    test('还能不能加', () {
      expect(canAddRemindSlot(0), isTrue);
      expect(canAddRemindSlot(kMaxRemindSlots - 1), isTrue);
      expect(canAddRemindSlot(kMaxRemindSlots), isFalse);
      expect(canAddRemindSlot(kMaxRemindSlots + 3), isFalse);
    });

    test('格式化成一串 HH:mm', () {
      expect(formatMinuteSlots([630, 930]), ['10:30', '15:30']);
      expect(formatMinuteSlots(const []), isEmpty);
    });
  });
}
