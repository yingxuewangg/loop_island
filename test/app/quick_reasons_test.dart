import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/quick_reasons.dart';

/// 快捷原因常量验收（任务 6.1）。
void main() {
  group('quickReasons 列表', () {
    test('PRD 要求的 7 项齐全且顺序固定', () {
      expect(
        quickReasons.map((e) => e.label).toList(),
        [
          ReasonStrings.quickNoTime,
          ReasonStrings.quickUnwell,
          ReasonStrings.quickSomethingCameUp,
          ReasonStrings.quickForgot,
          ReasonStrings.quickTooHard,
          ReasonStrings.quickWeather,
          ReasonStrings.quickOther,
        ],
      );
      expect(quickReasons, hasLength(7));
    });

    test('只有「其他」被标记为 isOther', () {
      final others = quickReasons.where((e) => e.isOther).toList();
      expect(others, hasLength(1));
      expect(others.single.label, ReasonStrings.quickOther);
      expect(otherReasonLabel, ReasonStrings.quickOther);
    });

    test('文案互不重复', () {
      expect(
        quickReasons.map((e) => e.label).toSet(),
        hasLength(quickReasons.length),
      );
    });

    test('列表不可变', () {
      expect(() => quickReasons.add(const QuickReason(label: 'x')),
          throwsUnsupportedError);
    });
  });

  group('isQuickReason', () {
    test('命中快捷项', () {
      for (final reason in quickReasons) {
        expect(isQuickReason(reason.label), isTrue);
      }
    });

    test('容忍首尾空白', () {
      expect(isQuickReason('  ${ReasonStrings.quickForgot}  '), isTrue);
    });

    test('空与自定义文本不算', () {
      expect(isQuickReason(null), isFalse);
      expect(isQuickReason(''), isFalse);
      expect(isQuickReason('   '), isFalse);
      expect(isQuickReason('在开会'), isFalse);
    });
  });

  group('isCustomReason', () {
    test('非「其他」的快捷项不算自定义', () {
      expect(isCustomReason(ReasonStrings.quickNoTime), isFalse);
      expect(isCustomReason(ReasonStrings.quickWeather), isFalse);
    });

    test('「其他」算自定义（需要展开输入框）', () {
      expect(isCustomReason(ReasonStrings.quickOther), isTrue);
    });

    test('自由文本算自定义', () {
      expect(isCustomReason('在开会'), isTrue);
      expect(isCustomReason(' 加班到十点 '), isTrue);
    });

    test('空文本不算自定义', () {
      expect(isCustomReason(null), isFalse);
      expect(isCustomReason('  '), isFalse);
    });
  });
}
