import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/models/enums.dart';

void main() {
  group('wireName 与 name 一致（JSON 兼容性契约）', () {
    test('TaskStatus', () {
      expect(
        TaskStatus.values.map((e) => e.wireName).toList(),
        ['pending', 'completed', 'skipped', 'missed'],
      );
    });

    test('TaskDateType', () {
      expect(
        TaskDateType.values.map((e) => e.wireName).toList(),
        ['today', 'tomorrow', 'custom', 'none'],
      );
    });

    test('CycleEndType', () {
      expect(
        CycleEndType.values.map((e) => e.wireName).toList(),
        ['never', 'afterCount', 'untilDate'],
      );
    });

    test('CycleStatus', () {
      expect(
        CycleStatus.values.map((e) => e.wireName).toList(),
        ['active', 'paused', 'ended'],
      );
    });

    test('EditScope', () {
      expect(
        EditScope.values.map((e) => e.wireName).toList(),
        ['once', 'fromNowAll'],
      );
    });
  });

  group('parse：合法值往返', () {
    test('所有枚举的所有取值都能解析回自身', () {
      for (final value in TaskStatus.values) {
        expect(TaskStatus.parse(value.wireName), value);
      }
      for (final value in TaskDateType.values) {
        expect(TaskDateType.parse(value.wireName), value);
      }
      for (final value in CycleEndType.values) {
        expect(CycleEndType.parse(value.wireName), value);
      }
      for (final value in CycleStatus.values) {
        expect(CycleStatus.parse(value.wireName), value);
      }
      for (final value in EditScope.values) {
        expect(EditScope.parse(value.wireName), value);
      }
    });
  });

  group('parse：脏数据不抛异常', () {
    test('null 走默认值', () {
      expect(TaskStatus.parse(null), TaskStatus.pending);
      expect(TaskDateType.parse(null), TaskDateType.none);
      expect(CycleEndType.parse(null), CycleEndType.never);
      expect(CycleStatus.parse(null), CycleStatus.active);
      expect(EditScope.parse(null), EditScope.once);
    });

    test('未知字符串走默认值', () {
      expect(TaskStatus.parse('unknown'), TaskStatus.pending);
      expect(TaskDateType.parse('2026-09-12'), TaskDateType.none);
      expect(CycleEndType.parse(''), CycleEndType.never);
      expect(CycleStatus.parse('ACTIVE'), CycleStatus.active, reason: '大小写敏感');
      expect(EditScope.parse('fromNowUntil'), EditScope.once, reason: '第二版才支持');
    });

    test('可指定 fallback', () {
      expect(
        TaskStatus.parse('bad', fallback: TaskStatus.completed),
        TaskStatus.completed,
      );
      expect(
        CycleStatus.parse(null, fallback: CycleStatus.ended),
        CycleStatus.ended,
      );
    });
  });

  group('语义辅助属性', () {
    test('TaskStatus.isSettled', () {
      expect(TaskStatus.pending.isSettled, isFalse);
      expect(TaskStatus.completed.isSettled, isTrue);
      expect(TaskStatus.skipped.isSettled, isTrue);
      expect(TaskStatus.missed.isSettled, isTrue);
    });

    test('TaskDateType.hasDate', () {
      expect(TaskDateType.today.hasDate, isTrue);
      expect(TaskDateType.tomorrow.hasDate, isTrue);
      expect(TaskDateType.custom.hasDate, isTrue);
      expect(TaskDateType.none.hasDate, isFalse);
    });

    test('CycleStatus.isRunning', () {
      expect(CycleStatus.active.isRunning, isTrue);
      expect(CycleStatus.paused.isRunning, isFalse);
      expect(CycleStatus.ended.isRunning, isFalse);
    });
  });
}
