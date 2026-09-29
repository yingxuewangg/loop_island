import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';

void main() {
  group('dayKey / parseDayKey', () {
    test('格式化补零', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('丢弃时间部分（不是时区偏移）', () {
      expect(dayKey(DateTime(2026, 9, 12, 23, 59, 59)), '2026-09-12');
      expect(dayKey(DateTime(2026, 9, 12, 0, 0, 1)), '2026-09-12');
    });

    test('UTC 输入归一到本地日历日', () {
      final utc = DateTime.utc(2026, 9, 12, 23, 30);
      final local = utc.toLocal();

      expect(dayKey(utc), dayKey(local));
      expect(
        dateOnly(utc),
        DateTime(local.year, local.month, local.day),
      );
    });

    test('往返一致', () {
      for (final key in ['2026-01-01', '2024-02-29', '2026-12-31']) {
        expect(dayKey(parseDayKey(key)!), key);
      }
    });

    test('非法输入返回 null 而不抛异常', () {
      expect(parseDayKey(null), isNull);
      expect(parseDayKey(''), isNull);
      expect(parseDayKey('2026-9-1'), isNull, reason: '必须补零');
      expect(parseDayKey('2026/09/01'), isNull);
      expect(parseDayKey('2026-13-01'), isNull, reason: '月份越界');
      expect(parseDayKey('2026-02-30'), isNull, reason: '该日期不存在');
      expect(parseDayKey('2025-02-29'), isNull, reason: '平年没有 2/29');
      expect(parseDayKey('2026-00-10'), isNull);
      expect(parseDayKey('2026-01-00'), isNull);
      expect(parseDayKey('abc'), isNull);
      // 前后空白容忍
      expect(dayKey(parseDayKey('  2026-09-12 ')!), '2026-09-12');
    });
  });

  group('addDays 跨月跨年', () {
    test('月末 +1 天进位', () {
      expect(dayKey(addDays(DateTime(2026, 1, 31), 1)), '2026-02-01');
      expect(dayKey(addDays(DateTime(2026, 4, 30), 1)), '2026-05-01');
    });

    test('年末 +1 天进位', () {
      expect(dayKey(addDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
    });

    test('闰日', () {
      expect(dayKey(addDays(DateTime(2024, 2, 28), 1)), '2024-02-29');
      expect(dayKey(addDays(DateTime(2024, 2, 29), 1)), '2024-03-01');
      expect(dayKey(addDays(DateTime(2025, 2, 28), 1)), '2025-03-01');
    });

    test('负数回退', () {
      expect(dayKey(addDays(DateTime(2026, 1, 1), -1)), '2025-12-31');
      expect(dayKey(addDays(DateTime(2026, 3, 1), -1)), '2026-02-28');
    });

    test('结果时间部分归零', () {
      final result = addDays(DateTime(2026, 9, 12, 15, 30), 1);
      expect(result.hour, 0);
      expect(result.minute, 0);
    });
  });

  group('daysBetween / 比较函数', () {
    test('同月与跨月', () {
      expect(daysBetween(DateTime(2026, 9, 1), DateTime(2026, 9, 12)), 11);
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 1)), 1);
    });

    test('跨年与闰年', () {
      expect(daysBetween(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 1);
      expect(daysBetween(DateTime(2024, 1, 1), DateTime(2025, 1, 1)), 366);
      expect(daysBetween(DateTime(2025, 1, 1), DateTime(2026, 1, 1)), 365);
    });

    test('方向为 b - a', () {
      expect(daysBetween(DateTime(2026, 9, 12), DateTime(2026, 9, 1)), -11);
    });

    test('忽略时间部分', () {
      expect(
        daysBetween(
          DateTime(2026, 9, 1, 23, 59),
          DateTime(2026, 9, 2, 0, 1),
        ),
        1,
      );
    });

    test('闭区间天数', () {
      expect(daysInclusive(DateTime(2026, 9, 1), DateTime(2026, 9, 1)), 1);
      expect(daysInclusive(DateTime(2026, 9, 1), DateTime(2026, 9, 8)), 8);
    });

    test('比较函数', () {
      final a = DateTime(2026, 9, 12, 8);
      final sameA = DateTime(2026, 9, 12, 22);
      final b = DateTime(2026, 9, 13);

      expect(isSameDay(a, sameA), isTrue);
      expect(isSameDay(a, b), isFalse);
      expect(isBeforeDay(a, b), isTrue);
      expect(isAfterDay(b, a), isTrue);
      expect(isSameOrBeforeDay(a, sameA), isTrue);
      expect(isSameOrAfterDay(a, sameA), isTrue);
      expect(isBetweenDaysInclusive(sameA, a, b), isTrue);
      expect(isBetweenDaysInclusive(DateTime(2026, 9, 14), a, b), isFalse);
    });
  });

  group('周与月边界', () {
    test('weekStart 返回周一', () {
      // 2026-09-12 是周六
      final saturday = DateTime(2026, 9, 12);
      expect(saturday.weekday, DateTime.saturday);
      expect(dayKey(weekStart(saturday)), '2026-09-07');

      // 周一自身
      final monday = DateTime(2026, 9, 7);
      expect(dayKey(weekStart(monday)), '2026-09-07');

      // 周日属于上一周
      final sunday = DateTime(2026, 9, 13);
      expect(sunday.weekday, DateTime.sunday);
      expect(dayKey(weekStart(sunday)), '2026-09-07');
    });

    test('跨月的周', () {
      // 2026-03-01 是周日，本周一在 2 月
      expect(dayKey(weekStart(DateTime(2026, 3, 1))), '2026-02-23');
    });

    test('monthStart / addMonths', () {
      expect(dayKey(monthStart(DateTime(2026, 9, 12))), '2026-09-01');
      expect(dayKey(addMonths(DateTime(2026, 12, 15), 1)), '2027-01-01');
      expect(dayKey(addMonths(DateTime(2026, 1, 15), -1)), '2025-12-01');
    });

    test('daysInMonth 含闰年', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2000, 2), 29, reason: '400 年闰');
      expect(daysInMonth(1900, 2), 28, reason: '100 年不闰');
    });
  });

  group('lastNDates', () {
    test('升序且以 end 结尾', () {
      final dates = lastNDates(5, end: DateTime(2026, 9, 12));
      expect(dates.length, 5);
      expect(dayKey(dates.first), '2026-09-08');
      expect(dayKey(dates.last), '2026-09-12');
      for (var i = 1; i < dates.length; i++) {
        expect(daysBetween(dates[i - 1], dates[i]), 1);
      }
    });

    test('90 天跨月', () {
      final dates = lastNDates(90, end: DateTime(2026, 9, 12));
      expect(dates.length, 90);
      expect(dayKey(dates.first), '2026-06-15');
      expect(dates.toSet().map(dayKey).length, 90, reason: '不应有重复日期');
    });

    test('边界：count <= 0 返回空', () {
      expect(lastNDates(0, end: DateTime(2026, 9, 12)), isEmpty);
      expect(lastNDates(-3, end: DateTime(2026, 9, 12)), isEmpty);
    });

    test('count = 1 只有当天', () {
      final dates = lastNDates(1, end: DateTime(2026, 9, 12, 20));
      expect(dates.length, 1);
      expect(dayKey(dates.single), '2026-09-12');
    });
  });

  group('展示格式化', () {
    test('weekdayLabel', () {
      expect(weekdayLabel(DateTime(2026, 9, 7)), '周一');
      expect(weekdayLabel(DateTime(2026, 9, 12)), '周六');
      expect(weekdayLabel(DateTime(2026, 9, 13)), '周日');
    });

    test('isWeekend', () {
      expect(isWeekend(DateTime(2026, 9, 12)), isTrue);
      expect(isWeekend(DateTime(2026, 9, 13)), isTrue);
      expect(isWeekend(DateTime(2026, 9, 11)), isFalse);
    });

    test('formatMonthDay / formatFullDate', () {
      expect(formatMonthDay(DateTime(2026, 9, 5)), '9月5日');
      expect(formatFullDate(DateTime(2026, 9, 12)), '2026-09-12 周六');
    });

    test('formatHm 补零', () {
      expect(formatHm(DateTime(2026, 9, 12, 7, 5)), '07:05');
      expect(formatHm(DateTime(2026, 9, 12, 23, 59)), '23:59');
      expect(formatHm(DateTime(2026, 9, 12, 0, 0)), '00:00');
    });
  });

  group('一天内分钟数', () {
    test('minuteOfDay', () {
      expect(minuteOfDay(DateTime(2026, 9, 12, 0, 0)), 0);
      expect(minuteOfDay(DateTime(2026, 9, 12, 7, 5)), 425);
      expect(minuteOfDay(DateTime(2026, 9, 12, 23, 59)), 1439);
    });

    test('atMinuteOfDay 落到指定日期', () {
      final value = atMinuteOfDay(DateTime(2026, 9, 12, 20), 425);
      expect(dayKey(value), '2026-09-12');
      expect(value.hour, 7);
      expect(value.minute, 5);
    });

    test('atMinuteOfDay 夹住越界值，不溢出到相邻日期', () {
      final tooBig = atMinuteOfDay(DateTime(2026, 9, 12), 5000);
      expect(dayKey(tooBig), '2026-09-12');
      expect(tooBig.hour, 23);
      expect(tooBig.minute, 59);

      final negative = atMinuteOfDay(DateTime(2026, 9, 12), -10);
      expect(dayKey(negative), '2026-09-12');
      expect(negative.hour, 0);
      expect(negative.minute, 0);
    });

    test('parseHm 合法输入', () {
      expect(parseHm('07:05'), 425);
      expect(parseHm('7:05'), 425, reason: '小时允许一位');
      expect(parseHm('00:00'), 0);
      expect(parseHm('23:59'), 1439);
      expect(parseHm('  08:30  '), 510, reason: '容忍空白');
    });

    test('parseHm 非法输入返回 null', () {
      expect(parseHm(null), isNull);
      expect(parseHm(''), isNull);
      expect(parseHm('24:00'), isNull);
      expect(parseHm('12:60'), isNull);
      expect(parseHm('12:5'), isNull, reason: '分钟必须两位');
      expect(parseHm('abc'), isNull);
      expect(parseHm('12-30'), isNull);
    });

    test('formatMinuteOfDay 与 parseHm 往返一致', () {
      for (final minute in [0, 1, 59, 60, 425, 1439]) {
        expect(parseHm(formatMinuteOfDay(minute)), minute);
        expect(formatMinuteOfDay(minute), formatHm(atMinuteOfDay(DateTime(2026, 1, 1), minute)));
      }
    });

    test('formatMinuteOfDay 夹住越界值', () {
      expect(formatMinuteOfDay(-1), '00:00');
      expect(formatMinuteOfDay(5000), '23:59');
    });
  });
}
