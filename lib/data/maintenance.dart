import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/models/app_data.dart';

/// 每日维护：把「数据」调整成「今天该有的样子」。
///
/// 两个动作都是**幂等**的，因此可以在每次数据变化时放心调用：
/// 1. 归档已到期的计划（[archiveFinishedCycles]）
/// 2. 物化今天的循环任务实例（[materializeDay]）
///
/// 返回 `null` 表示无需改动 —— 调用方据此避免无意义的写盘与广播。
AppData? prepareForDay(
  AppData data,
  DateTime today, {
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  final day = dateOnly(today);

  var next = archiveFinishedCycles(data, day, now: timestamp).data;
  next = materializeDay(next, day, now: timestamp, today: day);

  if (next == data) {
    return null;
  }
  return next;
}
