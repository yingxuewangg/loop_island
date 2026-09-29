/// 日期工具库（纯 Dart，不依赖 Flutter）。
///
/// 全局约定：
/// - **一切按「本地日历日」计算**。传入 UTC 时间会先 `toLocal()` 再取日期部分，
///   避免跨时区出现「差一天」。
/// - 日期键统一为 `yyyy-MM-dd` 字符串（见 [dayKey]），存储与比较都用它。
/// - 天数差一律用 UTC 日序号计算（[dayNumber]），**不能用 `Duration.inDays`**，
///   否则夏令时切换日会算错一天。
library;

/// 一天的毫秒数，仅用于日序号换算。
const int _msPerDay = 24 * 60 * 60 * 1000;

final RegExp _dayKeyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

final RegExp _hmPattern = RegExp(r'^(\d{1,2}):(\d{2})$');

/// 一天的总分钟数。
const int minutesPerDay = 24 * 60;

/// 周几的中文短标签，索引与 [DateTime.weekday] 对齐（周一 = 1）。
const List<String> _weekdayLabels = [
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 取本地日历日（时间部分归零）。
DateTime dateOnly(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day);
}

/// 该时刻所属的本地日历日序号（自 1970-01-01 起的天数，可为负）。
///
/// 用 UTC 构造再取整，天然规避夏令时导致的 23/25 小时日问题。
int dayNumber(DateTime value) {
  final d = dateOnly(value);
  return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      _msPerDay;
}

/// 格式化日期键：`yyyy-MM-dd`。
String dayKey(DateTime value) {
  final d = dateOnly(value);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 解析日期键；非法输入返回 `null`（不抛异常）。
///
/// 会拒绝 `2026-02-30` 这类「格式合法但日期不存在」的输入。
DateTime? parseDayKey(String? key) {
  if (key == null) {
    return null;
  }
  final match = _dayKeyPattern.firstMatch(key.trim());
  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  final parsed = DateTime(year, month, day);
  // DateTime 会把 2026-02-30 规范化成 2026-03-02，用它反查可识别非法日期。
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// 日期加减天数。用「构造器进位」而非 `Duration`，跨月跨年跨夏令时都安全。
DateTime addDays(DateTime value, int days) {
  final d = dateOnly(value);
  return DateTime(d.year, d.month, d.day + days);
}

/// 日期加减月数，结果落在目标月的 1 号。
DateTime addMonths(DateTime value, int months) {
  final d = dateOnly(value);
  return DateTime(d.year, d.month + months, 1);
}

/// 是否同一天（忽略时间）。
bool isSameDay(DateTime a, DateTime b) => dayNumber(a) == dayNumber(b);

/// `b - a` 的天数差；b 晚于 a 时为正。
int daysBetween(DateTime a, DateTime b) => dayNumber(b) - dayNumber(a);

/// 闭区间 `[start, end]` 覆盖的天数。
int daysInclusive(DateTime start, DateTime end) =>
    daysBetween(start, end) + 1;

/// 严格早于（按天比较）。
bool isBeforeDay(DateTime a, DateTime b) => dayNumber(a) < dayNumber(b);

/// 严格晚于（按天比较）。
bool isAfterDay(DateTime a, DateTime b) => dayNumber(a) > dayNumber(b);

/// 早于或等于（按天比较）。
bool isSameOrBeforeDay(DateTime a, DateTime b) => dayNumber(a) <= dayNumber(b);

/// 晚于或等于（按天比较）。
bool isSameOrAfterDay(DateTime a, DateTime b) => dayNumber(a) >= dayNumber(b);

/// 闭区间判断（按天比较）。
bool isBetweenDaysInclusive(DateTime value, DateTime start, DateTime end) =>
    isSameOrAfterDay(value, start) && isSameOrBeforeDay(value, end);

/// 本周起始日（周一），时间归零。
DateTime weekStart(DateTime value) {
  final d = dateOnly(value);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// 当月 1 号。
DateTime monthStart(DateTime value) {
  final d = dateOnly(value);
  return DateTime(d.year, d.month, 1);
}

/// 当月天数（正确处理闰年 2 月）。
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 返回以 [end] 结尾、长度 [count] 的连续日期升序列表（含 [end]）。
///
/// 用于热力图等「最近 N 天」场景；[count] <= 0 时返回空列表。
List<DateTime> lastNDates(int count, {required DateTime end}) {
  if (count <= 0) {
    return const [];
  }
  final last = dateOnly(end);
  return List<DateTime>.generate(count, (i) => addDays(last, i - (count - 1)));
}

/// 周几中文短标签，如「周三」。
String weekdayLabel(DateTime value) => _weekdayLabels[dateOnly(value).weekday];

/// 是否周末。
bool isWeekend(DateTime value) {
  final w = dateOnly(value).weekday;
  return w == DateTime.saturday || w == DateTime.sunday;
}

/// 中文短日期，如「9月12日」。
String formatMonthDay(DateTime value) {
  final d = dateOnly(value);
  return '${d.month}月${d.day}日';
}

/// 中文完整日期，如「2026-09-12 周六」。
String formatFullDate(DateTime value) {
  final d = dateOnly(value);
  return '${dayKey(d)} ${weekdayLabel(d)}';
}

/// `HH:mm` 时间格式。
String formatHm(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// 一天内的分钟数（0..1439），用于「每日提醒时间」这类与日期无关的时刻。
int minuteOfDay(DateTime value) => value.hour * 60 + value.minute;

/// 把「一天内分钟数」还原为 [day] 当天的具体时间点。
///
/// [minuteOfDay] 会被夹到 `0..1439`，避免脏数据把时间点溢出到相邻日期。
DateTime atMinuteOfDay(DateTime day, int minuteOfDay) {
  final d = dateOnly(day);
  final clamped = minuteOfDay.clamp(0, minutesPerDay - 1);
  return DateTime(d.year, d.month, d.day, clamped ~/ 60, clamped % 60);
}

/// 解析 `HH:mm`；非法输入返回 `null`（不抛异常）。
///
/// 小时允许写一位（`7:05` 合法），分钟必须两位。
int? parseHm(String? value) {
  if (value == null) {
    return null;
  }
  final match = _hmPattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// 把「一天内分钟数」格式化为 `HH:mm`；越界值会被夹到合法区间。
String formatMinuteOfDay(int value) {
  final clamped = value.clamp(0, minutesPerDay - 1);
  final h = (clamped ~/ 60).toString().padLeft(2, '0');
  final m = (clamped % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
