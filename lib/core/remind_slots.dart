/// 多时段提醒的公共规则（纯 Dart，不依赖 Flutter）。
///
/// 「一天提醒 N 次」是本应用的提醒主形态：用户可以在一个计划或一个任务上
/// 设最多 [kMaxRemindSlots] 个时段（例如 10:30、15:30）。
///
/// 把「夹取 + 去重 + 升序 + 截断」收在一个地方，是因为它同时被三处需要：
/// 模型反序列化（老备份兼容）、命令层（写库）、界面（编辑时实时规范化）。
/// 各写一份的话，「加了第 6 个会怎样」这种边界行为很快就会不一致。
library;

import 'package:loop_island/core/date_x.dart';

/// 一个对象（普通任务 / 循环计划）最多能设几个提醒时段。
///
/// 上限不是随便定的：iOS 只允许 64 条待发送通知，而循环提醒是按
/// 「天数 × 时段数」展开的，时段越多，滚动窗口就越短。
const int kMaxRemindSlots = 5;

/// 规范化「一天内时刻」列表：夹到 `0..1439`、去重、升序、最多 [kMaxRemindSlots] 个。
List<int> normalizeMinuteSlots(Iterable<int> values) {
  final unique = <int>{};
  for (final value in values) {
    unique.add(value.clamp(0, minutesPerDay - 1));
  }
  final sorted = unique.toList()..sort();
  return List.unmodifiable(sorted.take(kMaxRemindSlots));
}

/// 规范化绝对时刻列表（普通任务提醒）：按时刻去重、升序、最多 [kMaxRemindSlots] 个。
List<DateTime> normalizeInstantSlots(Iterable<DateTime> values) {
  final unique = <int, DateTime>{};
  for (final value in values) {
    unique[value.millisecondsSinceEpoch] = value;
  }
  final sorted = unique.values.toList()..sort((a, b) => a.compareTo(b));
  return List.unmodifiable(sorted.take(kMaxRemindSlots));
}

/// 还能不能再加一个时段。
bool canAddRemindSlot(int currentCount) => currentCount < kMaxRemindSlots;

/// 「一天内时刻」列表 → `HH:mm` 列表（用于拼展示文案）。
List<String> formatMinuteSlots(Iterable<int> minutes) =>
    minutes.map(formatMinuteOfDay).toList(growable: false);
