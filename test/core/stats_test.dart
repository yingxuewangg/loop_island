import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/stats.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';

/// 统计计算层验收（任务 5.1~5.5）。
void main() {
  final today = DateTime(2026, 9, 12);

  /// 造一条落在 [date] 的任务。
  Task taskOn(
    String id,
    DateTime date, {
    TaskStatus status = TaskStatus.pending,
    String? title,
  }) {
    return makeTask(
      id: id,
      title: title ?? id,
      dateType: TaskDateType.custom,
      date: date,
      status: status,
      completedAt: status == TaskStatus.completed ? date : null,
    );
  }

  /// 8 天计划，每天 1 个任务，指定某些天为休息日。
  Cycle cycle({
    String id = 'cycle_1',
    String name = '8 天跑步训练',
    int periodDays = 8,
    DateTime? startDate,
    CycleStatus status = CycleStatus.active,
    Map<int, bool> restDays = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: periodDays,
      startDate: startDate ?? today,
      status: status,
      days: [
        for (var i = 1; i <= periodDays; i++)
          makeCycleDay(
            dayIndex: i,
            isRestDay: restDays[i] ?? false,
            templates: restDays[i] == true
                ? const []
                : [makeCycleTemplate(id: 'ctask_${id}_$i', title: '第 $i 天')],
          ),
      ],
    );
  }

  /// 给某个循环实例造一条已完成的记录。
  AppData withCycleDone(AppData data, String cycleId, int dayIndex, DateTime date) {
    return data.copyWith(
      records: List.unmodifiable([
        ...data.records,
        makeRecord(
          id: 'r_${cycleId}_$dayIndex',
          taskId: 'ctask_${cycleId}_$dayIndex',
          cycleId: cycleId,
          cycleDayIndex: dayIndex,
          date: date,
          status: TaskStatus.completed,
          completedAt: date,
        ),
      ]),
    );
  }

  group('5.1 今日完成进度', () {
    test('没有任务时进度为 null 而不是 0%', () {
      final stat = todayProgress(const AppData(), today);
      expect(stat.total, 0);
      expect(stat.completed, 0);
      expect(stat.rate, isNull);
      expect(stat.percent, isNull);
      expect(stat.hasTask, isFalse);
      expect(stat.isAllDone, isFalse);
    });

    test('完成率与百分比', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
          taskOn('b', today),
          taskOn('c', today),
        ]),
      );
      final stat = todayProgress(data, today);
      expect(stat.total, 3);
      expect(stat.completed, 1);
      expect(stat.remaining, 2);
      expect(stat.percent, 33);
    });

    test('只把 completed 算作完成（未完成 / 跳过都不算）', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.missed),
          taskOn('c', today, status: TaskStatus.skipped),
          taskOn('d', today, status: TaskStatus.pending),
        ]),
      );
      final stat = todayProgress(data, today);
      expect(stat.total, 4);
      expect(stat.completed, 1);
    });

    test('全部完成', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.completed),
        ]),
      );
      final stat = todayProgress(data, today);
      expect(stat.percent, 100);
      expect(stat.isAllDone, isTrue);
    });

    test('普通任务与循环任务一起统计', () {
      var data = AppData(
        tasks: List.unmodifiable([taskOn('plain', today)]),
        cycles: List.unmodifiable([cycle()]),
      );
      data = withCycleDone(data, 'cycle_1', 1, today);

      final stat = todayProgress(data, today);
      expect(stat.total, 2);
      expect(stat.completed, 1);
    });

    test('昨天与明天的任务不计入今天', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('yesterday', addDays(today, -1)),
          taskOn('tomorrow', addDays(today, 1)),
          taskOn('today', today),
        ]),
      );
      expect(todayProgress(data, today).total, 1);
    });
  });

  group('5.2 当前周期进度', () {
    test('尚未开始返回空进度', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle(startDate: addDays(today, 5))]),
      );
      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.hasStarted, isFalse);
      expect(stat.dayIndex, isNull);
      expect(stat.progress.total, 0);
      expect(stat.progress.rate, isNull);
    });

    test('第 1 天：只算到今天为止，未到的日子不拉低完成率', () {
      var data = AppData(cycles: List.unmodifiable([cycle()]));
      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.dayIndex, 1);
      expect(stat.progress.total, 1, reason: '只应统计第 1 天');
      expect(stat.progress.completed, 0);

      data = withCycleDone(data, 'cycle_1', 1, today);
      final done = cycleProgress(data, data.cycles.single, today);
      expect(done.progress.percent, 100);
    });

    test('第 3 天：统计第 1~3 天', () {
      final start = addDays(today, -2);
      var data = AppData(cycles: List.unmodifiable([cycle(startDate: start)]));
      data = withCycleDone(data, 'cycle_1', 1, start);
      data = withCycleDone(data, 'cycle_1', 2, addDays(start, 1));

      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.dayIndex, 3);
      expect(stat.progress.total, 3);
      expect(stat.progress.completed, 2);
      expect(stat.progress.percent, 67);
    });

    test('只统计当前这一轮，不带上一轮', () {
      // 起始日在 9 天前：第 1 轮占 start..start+7，第 2 轮从 start+8（= 昨天）开始
      // 所以今天是第 2 轮第 2 天
      final start = addDays(today, -9);
      var data = AppData(cycles: List.unmodifiable([cycle(startDate: start)]));
      // 第 1 轮第 1 天的完成记录（9 天前）
      data = withCycleDone(data, 'cycle_1', 1, start);
      // 第 2 轮第 1 天（1 天前）
      data = withCycleDone(data, 'cycle_1', 1, addDays(today, -1));

      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.dayIndex, 2);
      expect(stat.progress.total, 2, reason: '第 2 轮的第 1~2 天');
      expect(stat.progress.completed, 1, reason: '上一轮的完成不该算进来');
    });

    test('休息日不计入应完成数', () {
      final start = addDays(today, -2);
      final data = AppData(
        cycles: List.unmodifiable([
          cycle(startDate: start, restDays: const {2: true}),
        ]),
      );
      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.progress.total, 2, reason: '第 2 天是休息日');
    });

    test('只统计本计划的实例，不混入别的计划', () {
      final start = addDays(today, -1);
      var data = AppData(
        cycles: List.unmodifiable([
          cycle(id: 'c1', name: 'A', startDate: start),
          cycle(id: 'c2', name: 'B', startDate: start),
        ]),
      );
      data = withCycleDone(data, 'c2', 1, start);

      final stat = cycleProgress(data, data.cycles.first, today);
      expect(stat.progress.total, 2);
      expect(stat.progress.completed, 0, reason: 'c2 的完成不算 c1 的');
    });

    test('暂停中的计划仍可算进度（今天起不再产生实例，历史仍计入）', () {
      final start = addDays(today, -2);
      final data = AppData(
        cycles: List.unmodifiable([cycle(startDate: start, status: CycleStatus.paused)]),
      );
      final stat = cycleProgress(data, data.cycles.single, today);
      expect(stat.hasStarted, isTrue);
      expect(
        stat.progress.total,
        2,
        reason: '今天-2 与今天-1 仍有实例；暂停后今天不再产生',
      );
    });

    test('allCycleProgress 跳过已结束与未开始的计划', () {
      final data = AppData(
        cycles: List.unmodifiable([
          cycle(id: 'c_run', name: '进行中'),
          cycle(id: 'c_future', name: '未开始', startDate: addDays(today, 3)),
          makeCycle(
            id: 'c_ended',
            name: '已结束',
            periodDays: 2,
            startDate: addDays(today, -10),
            endType: CycleEndType.untilDate,
            endDate: addDays(today, -1),
            days: [
              for (var i = 1; i <= 2; i++)
                makeCycleDay(
                  dayIndex: i,
                  templates: [makeCycleTemplate(id: 't$i')],
                ),
            ],
          ),
        ]),
      );

      final list = allCycleProgress(data, today);
      expect(list.map((e) => e.cycleName).toList(), ['进行中']);
    });

    test('返回的列表不可变', () {
      final data = AppData(cycles: List.unmodifiable([cycle()]));
      expect(
        () => allCycleProgress(data, today).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('5.3 连续打卡', () {
    test('没有任何任务 → 0 / 0', () {
      expect(streaks(const AppData(), today), StreakStat.empty);
    });

    test('只有今天且全部完成 → 当前 1、最长 1', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 1, longest: 1));
    });

    test('连续三天全部完成 → 3', () {
      final data = AppData(
        tasks: List.unmodifiable([
          for (var i = 0; i < 3; i++)
            taskOn('d$i', addDays(today, -i), status: TaskStatus.completed),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 3, longest: 3));
    });

    test('PRD 规则：无任务日跳过，不计入也不打断', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -3), status: TaskStatus.completed),
          // 第 -2 天没有任何任务
          taskOn('c', addDays(today, -1), status: TaskStatus.completed),
          taskOn('d', today, status: TaskStatus.completed),
        ]),
      );
      // 有效日子是 -3、-1、今天，中间的空档透明 → 连续 3
      expect(streaks(data, today), const StreakStat(current: 3, longest: 3));
    });

    test('未完成会打断连续', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -2), status: TaskStatus.completed),
          taskOn('b', addDays(today, -1), status: TaskStatus.missed),
          taskOn('c', today, status: TaskStatus.completed),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 1, longest: 1));
    });

    test('跳过不算打卡', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -1), status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.skipped),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 0, longest: 1));
    });

    test('一天里只要有一个没完成，这天就不算打卡', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.pending),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 0, longest: 0));
    });

    test('今天还没做完不算断（否则用户一整天都看到 0）', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -2), status: TaskStatus.completed),
          taskOn('b', addDays(today, -1), status: TaskStatus.completed),
          taskOn('c', today, status: TaskStatus.pending),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 2, longest: 2));
    });

    test('今天已明确标记未完成 → 算断点', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('b', addDays(today, -1), status: TaskStatus.completed),
          taskOn('c', today, status: TaskStatus.missed),
        ]),
      );
      // PRD：未完成不算打卡。用户已经把今天了结了，不能算「还没结束」。
      expect(streaks(data, today), const StreakStat(current: 0, longest: 1));
    });

    test('今天部分完成、部分还挂着待办 → 不算断', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -1), status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.completed),
          taskOn('c', today),
        ]),
      );
      expect(streaks(data, today).current, 1);
    });

    test('今天全部跳过 → 算断点', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -1), status: TaskStatus.completed),
          taskOn('b', today, status: TaskStatus.skipped),
          taskOn('c', today, status: TaskStatus.skipped),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 0, longest: 1));
    });

    test('今天没有任务时，昨天的未完成仍然算断', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -2), status: TaskStatus.completed),
          taskOn('b', addDays(today, -1), status: TaskStatus.missed),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 0, longest: 1));
    });

    test('最长连续可以大于当前连续', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', addDays(today, -5), status: TaskStatus.completed),
          taskOn('b', addDays(today, -4), status: TaskStatus.completed),
          taskOn('c', addDays(today, -3), status: TaskStatus.completed),
          taskOn('d', addDays(today, -2), status: TaskStatus.missed),
          taskOn('e', addDays(today, -1), status: TaskStatus.completed),
          taskOn('f', today, status: TaskStatus.completed),
        ]),
      );
      expect(streaks(data, today), const StreakStat(current: 2, longest: 3));
    });

    test('循环任务的完成也算打卡', () {
      var data = AppData(cycles: List.unmodifiable([cycle()]));
      data = withCycleDone(data, 'cycle_1', 1, today);
      expect(streaks(data, today).current, 1);
    });

    test('回溯范围可配置（避免长期使用后全量遍历）', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('old', addDays(today, -10), status: TaskStatus.completed),
          taskOn('new', today, status: TaskStatus.completed),
        ]),
      );
      expect(streaks(data, today, maxLookbackDays: 3).current, 1);
      expect(streaks(data, today, maxLookbackDays: 30).current, 2);
    });
  });

  group('5.4 热力图数据', () {
    test('长度与顺序：含结束日、升序、补齐无任务日', () {
      final cells = heatmapData(const AppData(), endDate: today, today: today);
      expect(cells, hasLength(90));
      expect(dayKey(cells.first.date), dayKey(addDays(today, -89)));
      expect(dayKey(cells.last.date), dayKey(today));
      for (var i = 1; i < cells.length; i++) {
        expect(daysBetween(cells[i - 1].date, cells[i].date), 1);
      }
      expect(cells.every((e) => e.hasTask), isFalse);
      expect(cells.every((e) => e.level == 0), isTrue);
    });

    test('有任务但一个没完成 → level 0 且 hasTask 为 true', () {
      final data = AppData(
        tasks: List.unmodifiable([taskOn('a', today)]),
      );
      final cell = heatmapData(data, endDate: today, today: today).last;
      expect(cell.total, 1);
      expect(cell.completed, 0);
      expect(cell.level, 0);
      expect(cell.hasTask, isTrue, reason: '要能区分「0%」与「无任务」');
    });

    test('全部完成 → level 4', () {
      final data = AppData(
        tasks: List.unmodifiable([
          taskOn('a', today, status: TaskStatus.completed),
        ]),
      );
      final cell = heatmapData(data, endDate: today, today: today).last;
      expect(cell.level, 4);
      expect(cell.isAllDone, isTrue);
      expect(cell.rate, 1.0);
    });

    test('分档：25% / 50% / 75% 的边界', () {
      AppData withRatio(int total, int completed) {
        return AppData(
          tasks: List.unmodifiable([
            for (var i = 0; i < total; i++)
              taskOn(
                't$i',
                today,
                status: i < completed
                    ? TaskStatus.completed
                    : TaskStatus.pending,
              ),
          ]),
        );
      }

      expect(heatmapData(withRatio(4, 0), endDate: today, today: today).last.level, 0);
      expect(heatmapData(withRatio(4, 1), endDate: today, today: today).last.level, 1);
      expect(heatmapData(withRatio(4, 2), endDate: today, today: today).last.level, 2);
      expect(heatmapData(withRatio(4, 3), endDate: today, today: today).last.level, 3);
      expect(heatmapData(withRatio(4, 4), endDate: today, today: today).last.level, 4);
    });

    test('可自定义天数', () {
      final cells = heatmapData(
        const AppData(),
        endDate: today,
        today: today,
        days: 7,
      );
      expect(cells, hasLength(7));
      expect(dayKey(cells.first.date), dayKey(addDays(today, -6)));
    });

    test('返回的列表不可变', () {
      final cells = heatmapData(const AppData(), endDate: today, today: today);
      expect(() => cells.clear(), throwsUnsupportedError);
    });
  });

  group('5.5 heatmapLevel 直接分档', () {
    test('无任务与零完成都是 0', () {
      expect(heatmapLevel(0, 0), 0);
      expect(heatmapLevel(3, 0), 0);
    });

    test('按完成率分档', () {
      expect(heatmapLevel(100, 1), 1, reason: '1%');
      expect(heatmapLevel(4, 1), 1, reason: '25%');
      expect(heatmapLevel(4, 2), 2, reason: '50%');
      expect(heatmapLevel(4, 3), 3, reason: '75%');
      expect(heatmapLevel(4, 4), 4, reason: '100%');
      expect(heatmapLevel(3, 1), 2, reason: '33%');
      expect(heatmapLevel(3, 2), 3, reason: '67%');
    });

    test('负数与异常输入不崩', () {
      expect(heatmapLevel(-1, 0), 0);
      expect(heatmapLevel(0, 5), 0);
    });
  });

  group('ProgressStat 值语义', () {
    test('相等与哈希', () {
      expect(const ProgressStat(total: 3, completed: 1),
          const ProgressStat(total: 3, completed: 1));
      expect(const ProgressStat(total: 3, completed: 1).hashCode,
          const ProgressStat(total: 3, completed: 1).hashCode);
      expect(const ProgressStat(total: 3, completed: 1),
          isNot(const ProgressStat(total: 3, completed: 2)));
    });
  });
}
