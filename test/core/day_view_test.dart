import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 今日/明日视图的纯计算验收（任务 4.1 / 4.2）。
void main() {
  final today = DateTime(2026, 9, 12);
  final tomorrow = addDays(today, 1);

  Cycle cycle({
    String id = 'cycle_1',
    String name = '8 天跑步训练',
    int periodDays = 8,
    DateTime? startDate,
    CycleStatus status = CycleStatus.active,
    CycleEndType endType = CycleEndType.never,
    DateTime? endDate,
    Map<int, bool> restDays = const {},
    Map<int, List<String>> titles = const {},
  }) {
    return makeCycle(
      id: id,
      name: name,
      periodDays: periodDays,
      startDate: startDate ?? today,
      status: status,
      endType: endType,
      endDate: endDate,
      days: [
        for (var i = 1; i <= periodDays; i++)
          makeCycleDay(
            dayIndex: i,
            isRestDay: restDays[i] ?? false,
            templates: restDays[i] == true
                ? const []
                : [
                    makeCycleTemplate(
                      id: 'ctask_${id}_$i',
                      title: titles[i]?.first ?? '第 $i 天任务',
                    ),
                  ],
          ),
      ],
    );
  }

  group('4.1 今日视图：聚合普通任务与循环任务', () {
    test('普通任务只取归属今天的', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_today',
            title: '今天做',
            dateType: TaskDateType.custom,
            date: today,
          ),
          makeTask(
            id: 'task_tomorrow',
            title: '明天做',
            dateType: TaskDateType.custom,
            date: tomorrow,
          ),
          makeTask(
            id: 'task_relative',
            title: '相对今天',
            dateType: TaskDateType.today,
            date: null,
          ),
          makeTask(id: 'task_none', title: '无日期', hasDate: false),
        ]),
      );

      final view = buildTodayView(data, today);
      expect(
        view.plainEntries.map((e) => e.key).toSet(),
        {'task_today', 'task_relative'},
      );
    });

    test('循环任务取今天对应的第几天', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle(startDate: addDays(today, -2))]),
      );

      final view = buildTodayView(data, today);
      expect(view.cycleEntries, hasLength(1));
      final entry = view.cycleEntries.single;
      expect(entry.title, '第 3 天任务');
      expect(entry.cycleDayIndex, 3);
      expect(entry.cyclePeriodDays, 8);
      expect(entry.cycleName, '8 天跑步训练');
      expect(entry.cycleLabel, '8 天跑步训练 · 第 3/8 天');
      expect(entry.isCycle, isTrue);
      expect(entry.status, TaskStatus.pending);
      expect(entry.recordId, isNull, reason: '尚未物化');
    });

    test('已物化的实例使用记录里的状态', () {
      final c = cycle();
      final data = AppData(
        cycles: List.unmodifiable([c]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'ctask_cycle_1_1',
            cycleId: 'cycle_1',
            cycleDayIndex: 1,
            date: today,
            status: TaskStatus.completed,
            completedAt: today,
          ),
        ]),
      );

      final view = buildTodayView(data, today);
      final entry = view.cycleEntries.single;
      expect(entry.status, TaskStatus.completed);
      expect(entry.isCompleted, isTrue);
      expect(entry.recordId, 'r1');
    });

    test('「仅本次」改的标题优先于模板标题', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle()]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'ctask_cycle_1_1',
            cycleId: 'cycle_1',
            cycleDayIndex: 1,
            date: today,
          ).withTitleOverride('今天改成慢跑'),
        ]),
      );

      final view = buildTodayView(data, today);
      expect(view.cycleEntries.single.title, '今天改成慢跑');
      expect(
        data.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
        reason: '模板不能被改动',
      );
    });

    test('暂停、已结束、休息日、未开始都不出现', () {
      final data = AppData(
        cycles: List.unmodifiable([
          cycle(id: 'c_paused', status: CycleStatus.paused),
          cycle(
            id: 'c_ended',
            startDate: addDays(today, -10),
            endType: CycleEndType.untilDate,
            endDate: addDays(today, -1),
          ),
          cycle(id: 'c_rest', restDays: const {1: true}),
          cycle(id: 'c_future', startDate: addDays(today, 3)),
        ]),
      );

      expect(buildTodayView(data, today).cycleEntries, isEmpty);
    });

    test('全部列表：循环任务在前，普通任务在后', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_1',
            title: '普通任务',
            dateType: TaskDateType.custom,
            date: today,
          ),
        ]),
        cycles: List.unmodifiable([cycle()]),
      );

      final view = buildTodayView(data, today);
      expect(view.all.map((e) => e.isCycle).toList(), [true, false]);
    });

    test('普通任务按提醒时间排序，无提醒的靠后', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 't_none',
            title: '没提醒',
            dateType: TaskDateType.custom,
            date: today,
          ),
          makeTask(
            id: 't_late',
            title: '晚上',
            dateType: TaskDateType.custom,
            date: today,
            remindAt: atMinuteOfDay(today, 20 * 60),
          ),
          makeTask(
            id: 't_early',
            title: '早上',
            dateType: TaskDateType.custom,
            date: today,
            remindAt: atMinuteOfDay(today, 7 * 60),
          ),
        ]),
      );

      expect(
        buildTodayView(data, today).plainEntries.map((e) => e.title).toList(),
        ['早上', '晚上', '没提醒'],
      );
    });
  });

  group('4.1 进度计算', () {
    test('没有任务时进度为 null（UI 不该显示 0%）', () {
      final view = buildTodayView(const AppData(), today);
      expect(view.isEmpty, isTrue);
      expect(view.total, 0);
      expect(view.progress, isNull);
      expect(view.progressPercent, isNull);
    });

    test('完成率与百分比', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'a',
            title: 'A',
            dateType: TaskDateType.custom,
            date: today,
            status: TaskStatus.completed,
            completedAt: today,
          ),
          makeTask(
            id: 'b',
            title: 'B',
            dateType: TaskDateType.custom,
            date: today,
          ),
          makeTask(
            id: 'c',
            title: 'C',
            dateType: TaskDateType.custom,
            date: today,
          ),
        ]),
      );

      final view = buildTodayView(data, today);
      expect(view.total, 3);
      expect(view.completedCount, 1);
      expect(view.progress, closeTo(1 / 3, 1e-9));
      expect(view.progressPercent, 33);
    });

    test('全部完成时 100%', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'a',
            title: 'A',
            dateType: TaskDateType.custom,
            date: today,
            status: TaskStatus.completed,
            completedAt: today,
          ),
        ]),
      );
      expect(buildTodayView(data, today).progressPercent, 100);
    });
  });

  group('4.2 明日视图：纯计算不落库', () {
    test('返回明天该出现的普通任务与循环任务', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_tomorrow',
            title: '明天做',
            dateType: TaskDateType.custom,
            date: tomorrow,
          ),
          makeTask(
            id: 'task_today',
            title: '今天做',
            dateType: TaskDateType.custom,
            date: today,
          ),
        ]),
        cycles: List.unmodifiable([cycle()]),
      );

      final view = buildTomorrowView(data, today);
      expect(view.date, tomorrow);
      expect(view.plainEntries.single.title, '明天做');
      expect(view.cycleEntries.single.cycleDayIndex, 2);
      expect(view.cycleEntries.single.cycleLabel, '8 天跑步训练 · 第 2/8 天');
    });

    test('不会写入任何记录', () {
      final data = AppData(cycles: List.unmodifiable([cycle()]));
      buildTomorrowView(data, today);
      expect(data.records, isEmpty, reason: '预览必须是纯计算');
    });

    test('今天没有的任务不会带过来', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_today',
            title: '今天做',
            dateType: TaskDateType.custom,
            date: today,
          ),
        ]),
      );
      expect(buildTomorrowView(data, today).plainEntries, isEmpty);
    });

    test('明日正好是周期最后一天与下一轮第一天都算得对', () {
      // 起始日 = 今天 - 6，则明天是第 8 天（周期末日）
      expect(
        buildTomorrowView(
          AppData(cycles: List.unmodifiable([cycle(startDate: addDays(today, -6))])),
          today,
        ).cycleEntries.single.cycleDayIndex,
        8,
      );

      // 起始日 = 今天 - 7，则今天是第 8 天、明天回到第 1 天
      expect(
        buildTomorrowView(
          AppData(cycles: List.unmodifiable([cycle(startDate: addDays(today, -7))])),
          today,
        ).cycleEntries.single.cycleDayIndex,
        1,
      );
    });

    test('明日是休息日则没有循环任务', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle(restDays: const {2: true})]),
      );
      expect(buildTomorrowView(data, today).cycleEntries, isEmpty);
    });

    test('计划在明日之前结束则不出现', () {
      final data = AppData(
        cycles: List.unmodifiable([
          cycle(
            endType: CycleEndType.untilDate,
            endDate: today,
          ),
        ]),
      );
      expect(buildTomorrowView(data, today).cycleEntries, isEmpty,
          reason: '结束日次日不再生成新任务实例');
    });
  });

  group('辅助输出', () {
    test('cycleDayLabels 去重后给出计划进度文案', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle()]),
      );
      final view = buildTodayView(data, today);
      expect(view.cycleDayLabels, ['8 天跑步训练 · 第 1/8 天']);
    });

    test('返回的列表不可变', () {
      final view = buildTodayView(const AppData(), today);
      expect(() => view.cycleEntries.clear(), throwsUnsupportedError);
      expect(() => view.all.clear(), throwsUnsupportedError);
    });
  });
}
