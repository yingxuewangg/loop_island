import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/cycle_engine.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 阶段 3 引擎验收（任务 3.1~3.7）。
///
/// 全部时间由参数注入，不受运行时刻影响。
void main() {
  /// 计划起始日，固定为周六。
  final start = DateTime(2026, 9, 12);

  /// 8 天计划。
  Cycle eightDay({
    DateTime? startDate,
    CycleEndType endType = CycleEndType.never,
    DateTime? endDate,
    int? endCount,
    bool completeCyclesOnly = false,
    CycleStatus status = CycleStatus.active,
    DateTime? endedAt,
    List<CycleDay>? days,
  }) {
    return makeCycle(
      id: 'cycle_1',
      name: '8 天跑步训练',
      periodDays: 8,
      startDate: startDate ?? start,
      endType: endType,
      endDate: endDate,
      endCount: endCount,
      completeCyclesOnly: completeCyclesOnly,
      status: status,
      endedAt: endedAt,
      days: days,
    );
  }

  /// 造一个每天都有 1 个任务的计划。
  Cycle withDailyTask({
    CycleEndType endType = CycleEndType.never,
    DateTime? endDate,
    int? endCount,
    bool completeCyclesOnly = false,
    int periodDays = 8,
    Map<int, bool> restDays = const {},
  }) {
    return makeCycle(
      id: 'cycle_1',
      name: '训练计划',
      periodDays: periodDays,
      startDate: start,
      endType: endType,
      endDate: endDate,
      endCount: endCount,
      completeCyclesOnly: completeCyclesOnly,
      days: [
        for (var i = 1; i <= periodDays; i++)
          makeCycleDay(
            dayIndex: i,
            isRestDay: restDays[i] ?? false,
            templates: restDays[i] == true
                ? const []
                : [makeCycleTemplate(id: 'ctask_$i', title: '第 $i 天任务')],
          ),
      ],
    );
  }

  group('3.1 周期天数计算：按「第几天」而非星期几', () {
    test('起始日当天是第 1 天', () {
      final cycle = eightDay();
      expect(cycleDayIndexAt(cycle, start), 1);
      expect(cycleRoundAt(cycle, start), 1);
      expect(elapsedCycles(cycle, start), 0);
    });

    test('第 N 天是周期最后一天，第 N+1 天回到第 1 天', () {
      final cycle = eightDay();
      expect(cycleDayIndexAt(cycle, addDays(start, 7)), 8);
      expect(cycleDayIndexAt(cycle, addDays(start, 8)), 1);
      expect(cycleRoundAt(cycle, addDays(start, 8)), 2);
      expect(elapsedCycles(cycle, addDays(start, 8)), 1);
    });

    test('起始日之前返回 null', () {
      final cycle = eightDay();
      expect(cycleDayIndexAt(cycle, addDays(start, -1)), isNull);
      expect(cycleRoundAt(cycle, addDays(start, -1)), isNull);
      expect(elapsedCycles(cycle, addDays(start, -1)), 0);
    });

    test('与星期几无关：跨越多周仍按天数推进', () {
      // 起始日是周六，第 8 天仍是周六，但编号必须继续走
      expect(start.weekday, DateTime.saturday);
      final cycle = eightDay();
      expect(cycleDayIndexAt(cycle, addDays(start, 7)), 8);
      expect(addDays(start, 7).weekday, DateTime.saturday);
    });

    test('周期天数为 1 时每天都是第 1 天，轮数每天 +1', () {
      final cycle = withDailyTask(periodDays: 1);
      expect(cycleDayIndexAt(cycle, start), 1);
      expect(cycleDayIndexAt(cycle, addDays(start, 1)), 1);
      expect(cycleRoundAt(cycle, addDays(start, 1)), 2);
      expect(cycleRoundAt(cycle, addDays(start, 5)), 6);
    });

    test('时刻会被归一到当天，不影响编号', () {
      final cycle = eightDay();
      expect(cycleDayIndexAt(cycle, DateTime(2026, 9, 12, 23, 59)), 1);
      expect(cycleDayIndexAt(cycle, DateTime(2026, 9, 19, 0, 1)), 8);
    });
  });

  group('3.2 结束条件求值', () {
    test('永不结束返回 null', () {
      expect(resolveEndDate(eightDay()), isNull);
      expect(lastActiveDate(eightDay()), isNull);
      expect(endDateLabel(eightDay()), '永不结束');
    });

    test('循环 X 次：结束日 = 起始日 + X*N - 1', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 1);
      expect(dayKey(resolveEndDate(cycle)!), dayKey(addDays(start, 7)));

      final three = eightDay(endType: CycleEndType.afterCount, endCount: 3);
      expect(dayKey(resolveEndDate(three)!), dayKey(addDays(start, 23)));
    });

    test('循环次数非法时退回「永不结束」而不是崩', () {
      expect(
        resolveEndDate(eightDay(endType: CycleEndType.afterCount, endCount: 0)),
        isNull,
      );
      expect(
        resolveEndDate(eightDay(endType: CycleEndType.afterCount)),
        isNull,
      );
    });

    test('到指定日期结束', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: DateTime(2026, 10, 19),
      );
      expect(dayKey(resolveEndDate(cycle)!), '2026-10-19');
    });

    test('结束日早于起始日时收敛到起始日（只执行一天）', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, -5),
      );
      expect(dayKey(resolveEndDate(cycle)!), dayKey(start));
    });

    test('结束日恰好落在周期末日 → 不截断', () {
      // 8 天计划的第 8 天 = start + 7
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 7),
      );
      expect(isTruncated(cycle), isFalse);
    });

    test('结束日落在周期中间 → 最后一轮被截断（PRD 允许）', () {
      // start + 4 是第 5 天
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 4),
      );
      expect(isTruncated(cycle), isTrue);
      expect(cycleDayIndexAt(cycle, resolveEndDate(cycle)!), 5);
    });

    test('完整周期模式：取结束日之前最后一个完整周期的末日', () {
      // 起始 start，结束 = start + 19（第 20 天，处于第 3 轮的第 4 天）
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 19),
        completeCyclesOnly: true,
      );
      // 完整跑满 2 轮 = 16 天，末日 = start + 15
      expect(dayKey(resolveEndDate(cycle)!), dayKey(addDays(start, 15)));
      expect(isTruncated(cycle), isFalse, reason: '整轮结束不该算截断');
    });

    test('完整周期模式：恰好整轮时就是结束日', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 15),
        completeCyclesOnly: true,
      );
      expect(dayKey(resolveEndDate(cycle)!), dayKey(addDays(start, 15)));
    });

    test('完整周期模式：连一个完整周期都放不下 → 不执行', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 3),
        completeCyclesOnly: true,
      );
      expect(resolveEndDate(cycle), isNull);
    });
  });

  group('3.2 执行区间：结束日当天仍执行，次日不执行', () {
    test('闭区间', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 9),
      );

      expect(isDateWithinCycle(cycle, addDays(start, -1)), isFalse);
      expect(isDateWithinCycle(cycle, start), isTrue);
      expect(isDateWithinCycle(cycle, addDays(start, 9)), isTrue,
          reason: 'PRD：结束日期当天仍然执行');
      expect(isDateWithinCycle(cycle, addDays(start, 10)), isFalse,
          reason: 'PRD：结束日期次日不再生成新任务实例');
    });

    test('永不结束时起始日之后一直有效', () {
      final cycle = eightDay();
      expect(isDateWithinCycle(cycle, addDays(start, 3650)), isTrue);
    });

    test('暂停后当天及之后不再执行，暂停前的历史仍有效', () {
      final cycle = eightDay(status: CycleStatus.paused);
      final today = addDays(start, 3);

      expect(isDateWithinCycle(cycle, addDays(start, 2), today: today), isTrue);
      expect(isDateWithinCycle(cycle, today, today: today), isFalse);
      expect(isDateWithinCycle(cycle, addDays(start, 4), today: today), isFalse);
    });

    test('已结束的计划在 endedAt 当天及之后不执行', () {
      final cycle = eightDay(
        status: CycleStatus.ended,
        endedAt: addDays(start, 5),
      );
      expect(isDateWithinCycle(cycle, addDays(start, 4)), isTrue);
      expect(isDateWithinCycle(cycle, addDays(start, 5)), isFalse);
    });
  });

  group('3.3 状态机与自动归档', () {
    test('未到期时保持 active', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 7),
      );
      expect(effectiveStatus(cycle, today: addDays(start, 7)), CycleStatus.active,
          reason: '结束日当天仍是进行中');
      expect(effectiveStatus(cycle, today: addDays(start, 8)), CycleStatus.ended,
          reason: '结束日次日到期');
    });

    test('应自动归档的判定', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 7),
      );
      expect(shouldAutoArchive(cycle, addDays(start, 7)), isFalse);
      expect(shouldAutoArchive(cycle, addDays(start, 8)), isTrue);
    });

    test('已 ended 的计划永远返回 ended', () {
      final cycle = eightDay(
        status: CycleStatus.ended,
        endedAt: start,
      );
      expect(effectiveStatus(cycle, today: addDays(start, 100)),
          CycleStatus.ended);
    });

    test('暂停的计划过了结束日同样会被归档', () {
      final data = AppData(
        cycles: [
          eightDay(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 7),
            status: CycleStatus.paused,
          ),
        ],
      );
      final result = archiveFinishedCycles(data, addDays(start, 30));
      expect(result.archived, hasLength(1),
          reason: '暂停中但已过期，同样不可恢复，必须归档');
      expect(result.data.cycles.single.status, CycleStatus.ended);
    });

    test('暂停的计划不会因为到期被改成 ended', () {
      final cycle = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 7),
        status: CycleStatus.paused,
      );
      // 未到期：保持 paused
      expect(effectiveStatus(cycle, today: addDays(start, 3)),
          CycleStatus.paused);
      expect(shouldAutoArchive(cycle, addDays(start, 3)), isFalse);
      // 已过期：状态视为 ended（它确实结束了），且可恢复性为 false
      expect(effectiveStatus(cycle, today: addDays(start, 30)),
          CycleStatus.ended);
      expect(canResume(cycle, addDays(start, 30)), isFalse);
    });

    test('暂停可恢复，结束不可恢复', () {
      final paused = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 30),
        status: CycleStatus.paused,
      );
      expect(canResume(paused, addDays(start, 5)), isTrue);

      final ended = eightDay(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 7),
        status: CycleStatus.paused,
      );
      expect(canResume(ended, addDays(start, 30)), isFalse,
          reason: '已过结束日的暂停计划只能归档，不能恢复');
    });

    test('缓存用的 endedAt 写成当天零点', () {
      final data = AppData(
        cycles: [eightDay(
          endType: CycleEndType.untilDate,
          endDate: addDays(start, 7),
        )],
      );
      final result = archiveFinishedCycles(data, addDays(start, 8));

      expect(result.archived, hasLength(1));
      final archived = result.data.cycles.single;
      expect(archived.status, CycleStatus.ended);
      expect(dayKey(archived.endedAt!), dayKey(addDays(start, 8)));
      expect(archived.endedAt!.hour, 0);
    });

    test('没有需要归档的计划时原样返回', () {
      final data = AppData(cycles: [eightDay()]);
      final result = archiveFinishedCycles(data, addDays(start, 3));
      expect(result.archived, isEmpty);
      expect(identical(result.data, data), isTrue);
    });
  });

  group('3.6 剩余轮数与剩余天数', () {
    test('永不结束返回 null', () {
      expect(remainingCycles(eightDay(), start), isNull);
      expect(remainingDays(eightDay(), start), isNull);
    });

    test('循环 3 次：起始日剩余 3 轮 24 天', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 3);
      expect(remainingCycles(cycle, start), 3);
      expect(remainingDays(cycle, start), 24);
    });

    test('中途剩余轮数向上取整', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 3);
      // 第 2 轮第 1 天 = start + 8，剩余到 start+23 共 16 天 = 2 轮
      expect(remainingCycles(cycle, addDays(start, 8)), 2);
      // 第 2 轮第 7 天 = start + 14，剩余 10 天 → 需要 2 轮（含当前未跑完的）
      expect(remainingCycles(cycle, addDays(start, 14)), 2);
      expect(remainingDays(cycle, addDays(start, 14)), 10);
    });

    test('结束当天剩余 1 轮 1 天', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 1);
      expect(remainingCycles(cycle, addDays(start, 7)), 1);
      expect(remainingDays(cycle, addDays(start, 7)), 1);
    });

    test('已结束返回 0', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 1);
      expect(remainingCycles(cycle, addDays(start, 8)), 0);
      expect(remainingDays(cycle, addDays(start, 8)), 0);
      expect(isFinished(cycle, addDays(start, 8)), isTrue);
    });

    test('还没开始时的剩余量从起始日算', () {
      final cycle = eightDay(endType: CycleEndType.afterCount, endCount: 2);
      expect(remainingDays(cycle, addDays(start, -5)), 16);
      expect(remainingCycles(cycle, addDays(start, -5)), 2);
    });
  });

  group('3.5 某天实例预览（纯计算，不落库）', () {
    test('返回当天的任务模板与所属第几天', () {
      final data = AppData(cycles: [withDailyTask()]);
      final instances = instancesForDay(data, addDays(start, 2), today: start);

      expect(instances, hasLength(1));
      final instance = instances.single;
      expect(instance.cycleId, 'cycle_1');
      expect(instance.cycleDayIndex, 3);
      expect(instance.periodDays, 8);
      expect(instance.title, '第 3 天任务');
      expect(dayKey(instance.date), dayKey(addDays(start, 2)));
    });

    test('一天多个任务按 order 排序返回', () {
      final data = AppData(
        cycles: [
          makeCycle(
            id: 'cycle_1',
            periodDays: 2,
            startDate: start,
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [
                  makeCycleTemplate(id: 'b', title: '第二', order: 1),
                  makeCycleTemplate(id: 'a', title: '第一', order: 0),
                ],
              ),
              makeCycleDay(dayIndex: 2),
            ],
          ),
        ],
      );

      final instances = instancesForDay(data, start, today: start);
      expect(instances.map((e) => e.title).toList(), ['第一', '第二']);
    });

    test('休息日与空白白天不产生实例', () {
      final data = AppData(
        cycles: [withDailyTask(restDays: const {2: true})],
      );

      expect(instancesForDay(data, addDays(start, 1), today: start), isEmpty,
          reason: '第 2 天是休息日');
      expect(instancesForDay(data, addDays(start, 2), today: start), hasLength(1));
    });

    test('起始日之前、结束日之后都没有实例', () {
      final data = AppData(
        cycles: [
          withDailyTask(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 3),
          ),
        ],
      );

      expect(instancesForDay(data, addDays(start, -1), today: start), isEmpty);
      expect(instancesForDay(data, addDays(start, 3), today: start), hasLength(1),
          reason: '结束日当天仍执行');
      expect(instancesForDay(data, addDays(start, 4), today: start), isEmpty);
    });

    test('多个计划同时命中，按计划创建时间排序', () {
      final data = AppData(
        cycles: [
          makeCycle(
            id: 'cycle_late',
            name: '后建',
            periodDays: 1,
            startDate: start,
            createdAt: DateTime(2026, 5, 1),
            days: [makeCycleDay(dayIndex: 1, templates: [makeCycleTemplate(id: 't2')])],
          ),
          makeCycle(
            id: 'cycle_early',
            name: '先建',
            periodDays: 1,
            startDate: start,
            createdAt: DateTime(2026, 1, 1),
            days: [makeCycleDay(dayIndex: 1, templates: [makeCycleTemplate(id: 't1')])],
          ),
        ],
        settings: makeSettings(),
      );

      final instances = instancesForDay(data, start, today: start);
      expect(instances.map((e) => e.cycleId).toList(),
          ['cycle_late', 'cycle_early'],
          reason: '沿用 AppData.cycles 的原始顺序，不额外排序');
    });

    test('预览不会写入任何记录', () {
      final data = AppData(cycles: [withDailyTask()]);
      instancesForDay(data, start, today: start);
      expect(data.records, isEmpty, reason: '预览必须是纯计算');
    });

    test('模板提醒时间是当天内的时刻', () {
      final data = AppData(
        cycles: [
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: start,
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [
                  makeCycleTemplate(id: 't1', remindMinuteOfDay: 7 * 60 + 30),
                ],
              ),
            ],
          ),
        ],
      );

      final instance = instancesForDay(data, addDays(start, 3), today: start).single;
      expect(dayKey(instance.remindAt!), dayKey(addDays(start, 3)));
      expect(instance.remindAt!.hour, 7);
      expect(instance.remindAt!.minute, 30);
    });
  });

  group('3.4 实例物化：幂等', () {
    test('首次物化生成当天记录', () {
      final data = AppData(cycles: [withDailyTask()]);
      final next = materializeDay(data, start, now: start, today: start);

      expect(next.records, hasLength(1));
      final record = next.records.single;
      expect(record.cycleId, 'cycle_1');
      expect(record.cycleDayIndex, 1);
      expect(record.taskId, 'ctask_1');
      expect(record.status, TaskStatus.pending);
      expect(dayKey(record.date), dayKey(start));
    });

    test('重复调用不产生重复记录，且无新增时原样返回', () {
      final data = AppData(cycles: [withDailyTask()]);
      final once = materializeDay(data, start, now: start, today: start);
      final twice = materializeDay(once, start, now: start, today: start);

      expect(twice.records, hasLength(1));
      expect(identical(twice, once), isTrue, reason: '无新增应返回同一对象，避免无意义写盘');
    });

    test('不覆盖已有记录的状态与原因（勾选后不会被冲掉）', () {
      var data = AppData(cycles: [withDailyTask()]);
      data = materializeDay(data, start, now: start, today: start);

      final record = data.records.single;
      data = data.copyWith(
        records: List.unmodifiable([
          record
              .withStatus(TaskStatus.completed, at: start)
              .withReason('其实做了一半'),
        ]),
      );

      final again = materializeDay(data, start, now: start, today: start);
      expect(again.records, hasLength(1));
      expect(again.records.single.status, TaskStatus.completed);
      expect(again.records.single.reason, '其实做了一半');
    });

    test('休息日不生成；结束日当天生成、次日不生成', () {
      final data = AppData(
        cycles: [
          withDailyTask(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 2),
            restDays: const {2: true},
          ),
        ],
      );

      expect(materializeDay(data, start, now: start, today: start).records,
          hasLength(1));
      expect(
        materializeDay(data, addDays(start, 1), now: start, today: start).records,
        isEmpty,
        reason: '第 2 天是休息日',
      );
      expect(
        materializeDay(data, addDays(start, 2), now: start, today: start).records,
        hasLength(1),
        reason: '结束日当天仍生成',
      );
      expect(
        materializeDay(data, addDays(start, 3), now: start, today: start).records,
        isEmpty,
        reason: '结束日次日不再生成',
      );
    });

    test('暂停的计划不物化', () {
      final data = AppData(
        cycles: [withDailyTask()..copyWith(status: CycleStatus.paused)],
      );
      final paused = data.copyWith(
        cycles: List.unmodifiable([
          data.cycles.single.copyWith(status: CycleStatus.paused),
        ]),
      );
      expect(
        materializeDay(paused, start, now: start, today: start).records,
        isEmpty,
      );
    });

    test('已结束的计划在结束日之后不物化', () {
      final data = AppData(
        cycles: [
          withDailyTask(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 1),
          ),
        ],
      );
      final today = addDays(start, 10);
      expect(
        materializeDay(data, addDays(start, 2), now: today, today: today).records,
        isEmpty,
      );
    });

    test('两个计划各自生成自己的实例，互不干扰', () {
      final data = AppData(
        cycles: [
          makeCycle(
            id: 'c1',
            periodDays: 1,
            startDate: start,
            days: [makeCycleDay(dayIndex: 1, templates: [makeCycleTemplate(id: 't1')])],
          ),
          makeCycle(
            id: 'c2',
            periodDays: 1,
            startDate: start,
            days: [makeCycleDay(dayIndex: 1, templates: [makeCycleTemplate(id: 't2')])],
          ),
        ],
      );

      final next = materializeDay(data, start, now: start, today: start);
      expect(next.records, hasLength(2));
      expect(next.records.map((e) => e.cycleId).toSet(), {'c1', 'c2'});
    });
  });

  group('3.4 区间物化与未来实例重建', () {
    test('materializeRange 覆盖闭区间', () {
      final data = AppData(
        cycles: [withDailyTask(endType: CycleEndType.afterCount, endCount: 2)],
      );
      final next = materializeRange(
        data,
        'cycle_1',
        start,
        addDays(start, 4),
        now: start,
        today: start,
      );
      expect(next.records, hasLength(5));
    });

    test('缩短结束日期：删掉未来待办实例，历史与已了结的保留', () {
      var data = AppData(
        cycles: [withDailyTask(endType: CycleEndType.afterCount, endCount: 8)],
      );
      data = materializeRange(data, 'cycle_1', start, addDays(start, 9),
          now: start, today: start);
      expect(data.records, hasLength(10));

      // 把第 3 天标记完成、第 4 天标记未完成并写原因
      data = data.copyWith(records: List.unmodifiable([
        for (final record in data.records)
          if (isSameDay(record.date, addDays(start, 2)))
            record.withStatus(TaskStatus.completed, at: start)
          else if (isSameDay(record.date, addDays(start, 3)))
            record.withStatus(TaskStatus.missed, at: start).withReason('加班')
          else
            record,
      ]));

      // 结束日缩短到第 5 天（start + 4）；先写回数据再重建
      final shortened = data.cycles.single.copyWith(
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 4),
      );
      final withNewRule = data.copyWith(cycles: List.unmodifiable([shortened]));

      final rebuilt = rebuildFutureInstances(
        withNewRule,
        'cycle_1',
        start,
        now: start,
        today: start,
      );

      expect(rebuilt.records, hasLength(5), reason: '只剩第 1..5 天');
      final day3 = rebuilt.records.firstWhere(
        (e) => isSameDay(e.date, addDays(start, 2)),
      );
      expect(day3.status, TaskStatus.completed, reason: '已完成的历史不能丢');
      final day4 = rebuilt.records.firstWhere(
        (e) => isSameDay(e.date, addDays(start, 3)),
      );
      expect(day4.reason, '加班', reason: '已写原因的历史不能丢');
    });

    test('延长结束日期：补出新的未来实例', () {
      final data = AppData(
        cycles: [
          withDailyTask(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 1),
          ),
        ],
      );
      var next = materializeRange(data, 'cycle_1', start, addDays(start, 1),
          now: start, today: start);
      expect(next.records, hasLength(2));

      final extended = data.cycles.single.copyWith(
        endDate: addDays(start, 4),
      );
      next = next.copyWith(cycles: List.unmodifiable([extended]));
      next = rebuildFutureInstances(next, 'cycle_1', start,
          now: start, today: start);
      expect(next.records, hasLength(5));
    });

    test('永不结束的计划只补 horizonDays 天，不会一次性铺满', () {
      final data = AppData(cycles: [withDailyTask()]);
      final rebuilt = rebuildFutureInstances(
        data,
        'cycle_1',
        start,
        now: start,
        today: start,
        horizonDays: 10,
      );
      expect(rebuilt.records, hasLength(10));
    });

    test('已结束的计划不再补新实例', () {
      final data = AppData(
        cycles: [
          withDailyTask(
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 1),
          ),
        ],
      );
      final rebuilt = rebuildFutureInstances(
        data,
        'cycle_1',
        addDays(start, 10),
        now: addDays(start, 10),
        today: addDays(start, 10),
      );
      expect(rebuilt.records, isEmpty);
    });

    test('计划不存在时原样返回', () {
      final data = AppData(cycles: [withDailyTask()]);
      expect(
        rebuildFutureInstances(data, 'cycle_nope', start, now: start),
        data,
      );
    });
  });

  group('引擎不变量', () {
    test('所有引擎函数都是纯函数，不修改入参', () {
      final data = AppData(cycles: [withDailyTask()]);
      final before = data;

      materializeDay(data, start, now: start, today: start);
      archiveFinishedCycles(data, addDays(start, 100));
      instancesForDay(data, start, today: start);

      expect(data, before);
      expect(data.records, isEmpty);
    });

    test('返回的列表不可变', () {
      final instances = instancesForDay(
        AppData(cycles: [withDailyTask()]),
        start,
        today: start,
      );
      expect(() => instances.clear(), throwsUnsupportedError);
    });
  });
}
