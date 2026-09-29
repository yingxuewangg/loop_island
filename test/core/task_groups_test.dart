import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/task_groups.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';

void main() {
  final today = DateTime(2026, 9, 12);
  final yesterday = addDays(today, -1);
  final tomorrow = addDays(today, 1);
  final nextWeek = addDays(today, 7);

  Task taskAt(
    String id,
    DateTime? date, {
    TaskStatus status = TaskStatus.pending,
    DateTime? remindAt,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return makeTask(
      id: id,
      title: id,
      dateType: date == null ? TaskDateType.none : TaskDateType.custom,
      date: date,
      hasDate: date != null,
      status: status,
      remindAt: remindAt,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      updatedAt: createdAt ?? DateTime(2026, 1, 1),
      completedAt: completedAt,
    );
  }

  AppData dataWith(List<Task> tasks) => AppData(tasks: List.unmodifiable(tasks));

  group('2.2 分组：基本归属', () {
    test('今天 / 明天 / 未安排 / 已完成 四组按 PRD 切分', () {
      final data = dataWith([
        taskAt('今天未做', today),
        taskAt('明天做', tomorrow),
        taskAt('没安排', null),
        taskAt('已完成', today, status: TaskStatus.completed),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.today.map((e) => e.id), ['今天未做']);
      expect(groups.tomorrow.map((e) => e.id), ['明天做']);
      expect(groups.unscheduled.map((e) => e.id), ['没安排']);
      expect(groups.completed.map((e) => e.id), ['已完成']);
    });

    test('「今天 / 明天」相对日期按传入的 today 换算，而不是按系统时间', () {
      final data = dataWith([
        makeTask(id: 'rel_today', dateType: TaskDateType.today, date: null),
        makeTask(id: 'rel_tomorrow', dateType: TaskDateType.tomorrow, date: null),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.today.map((e) => e.id), ['rel_today']);
      expect(groups.tomorrow.map((e) => e.id), ['rel_tomorrow']);

      // 换一个「今天」，相对日期任务**依然**落在今天/明天组 ——
      // 这正是「相对日期」该有的语义：它跟着你走，不会变成逾期。
      final shifted = groupTasks(data, tomorrow);
      expect(shifted.today.map((e) => e.id), ['rel_today']);
      expect(shifted.tomorrow.map((e) => e.id), ['rel_tomorrow']);
      expect(shifted.overdue, isEmpty);
      expect(shifted.upcoming, isEmpty);
    });

    test('固定日期任务才随「今天」变化而改变归属', () {
      final data = dataWith([
        taskAt('固定昨天', yesterday),
        taskAt('固定今天', today),
      ]);

      expect(groupTasks(data, today).today.map((e) => e.id), ['固定今天']);
      expect(groupTasks(data, today).overdue.map((e) => e.id), ['固定昨天']);

      // 到了明天，原本「今天」的那条变成逾期
      final shifted = groupTasks(data, tomorrow);
      expect(shifted.overdue.map((e) => e.id).toSet(), {'固定昨天', '固定今天'});
      expect(shifted.today, isEmpty);
    });

    test('已完成的 task 只看状态，不看日期', () {
      final data = dataWith([
        taskAt('今天完成', today, status: TaskStatus.completed),
        taskAt('昨天完成', yesterday, status: TaskStatus.completed),
        taskAt('无日期完成', null, status: TaskStatus.completed),
        taskAt('明年完成', nextWeek, status: TaskStatus.completed),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.completed, hasLength(4));
      expect(groups.today, isEmpty);
      expect(groups.unscheduled, isEmpty);
      expect(groups.upcoming, isEmpty);
    });
  });

  group('2.2 分组：PRD 四组之外的补充组', () {
    test('逾期未完成进入 overdue，而不是凭空消失', () {
      final data = dataWith([
        taskAt('昨天没做', yesterday),
        taskAt('上周没做', addDays(today, -7)),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.overdue.map((e) => e.id).toSet(), {'昨天没做', '上周没做'});
      expect(groups.today, isEmpty);
    });

    test('后天及以后进入 upcoming', () {
      final data = dataWith([
        taskAt('后天', addDays(today, 2)),
        taskAt('下周', nextWeek),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.upcoming.map((e) => e.id).toSet(), {'后天', '下周'});
    });

    test('未完成 / 跳过的任务仍留在自己的日期组，不进已完成组', () {
      final data = dataWith([
        taskAt('今天未完成', today, status: TaskStatus.missed),
        taskAt('今天跳过', today, status: TaskStatus.skipped),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.today.map((e) => e.id).toSet(), {'今天未完成', '今天跳过'});
      expect(groups.completed, isEmpty);
    });

    test('任何任务都不会凭空消失：六组之和等于全部任务数', () {
      final data = dataWith([
        taskAt('今天', today),
        taskAt('明天', tomorrow),
        taskAt('无日期', null),
        taskAt('已完成', today, status: TaskStatus.completed),
        taskAt('逾期', yesterday),
        taskAt('以后', nextWeek),
        taskAt('今天跳过', today, status: TaskStatus.skipped),
      ]);

      final groups = groupTasks(data, today);
      final total = groups.today.length +
          groups.tomorrow.length +
          groups.unscheduled.length +
          groups.completed.length +
          groups.overdue.length +
          groups.upcoming.length;

      expect(total, data.tasks.length);
    });
  });

  group('2.2 分组：排序稳定', () {
    test('今天组按提醒时间升序，无提醒的排最后', () {
      final data = dataWith([
        taskAt('没提醒', today),
        taskAt('晚上8点', today,
            remindAt: DateTime(2026, 9, 12, 20), createdAt: DateTime(2026, 1, 1)),
        taskAt('早上7点', today,
            remindAt: DateTime(2026, 9, 12, 7), createdAt: DateTime(2026, 1, 2)),
      ]);

      final groups = groupTasks(data, today);
      expect(
        groups.today.map((e) => e.id),
        ['早上7点', '晚上8点', '没提醒'],
      );
    });

    test('提醒时间相同时按创建时间升序', () {
      final data = dataWith([
        taskAt('后创建', today,
            remindAt: DateTime(2026, 9, 12, 8),
            createdAt: DateTime(2026, 5, 1)),
        taskAt('先创建', today,
            remindAt: DateTime(2026, 9, 12, 8),
            createdAt: DateTime(2026, 1, 1)),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.today.map((e) => e.id), ['先创建', '后创建']);
    });

    test('其余分组按创建时间升序', () {
      final data = dataWith([
        taskAt('明日后建', tomorrow, createdAt: DateTime(2026, 5, 1)),
        taskAt('明日前建', tomorrow, createdAt: DateTime(2026, 1, 1)),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.tomorrow.map((e) => e.id), ['明日前建', '明日后建']);
    });

    test('已完成组按完成时间倒序（最近完成在最上）', () {
      final data = dataWith([
        taskAt('早完成', today,
            status: TaskStatus.completed,
            completedAt: DateTime(2026, 9, 10, 9)),
        taskAt('晚完成', today,
            status: TaskStatus.completed,
            completedAt: DateTime(2026, 9, 12, 9)),
      ]);

      final groups = groupTasks(data, today);
      expect(groups.completed.map((e) => e.id), ['晚完成', '早完成']);
    });

    test('排序结果稳定：同一输入多次分组顺序一致', () {
      final data = dataWith([
        taskAt('c', today, createdAt: DateTime(2026, 3, 1)),
        taskAt('a', today, createdAt: DateTime(2026, 1, 1)),
        taskAt('b', today, createdAt: DateTime(2026, 2, 1)),
      ]);

      final first = groupTasks(data, today).today.map((e) => e.id).toList();
      final second = groupTasks(data, today).today.map((e) => e.id).toList();
      expect(first, ['a', 'b', 'c']);
      expect(first, second);
    });
  });

  group('2.2 分组：边界与辅助', () {
    test('空数据返回全空分组', () {
      final groups = groupTasks(const AppData(), today);
      expect(groups.isEmpty, isTrue);
      expect(groups.today, isEmpty);
      expect(groups.completed, isEmpty);
    });

    test('传入的时刻会被归一到当天（不会因时分秒导致漏分组）', () {
      final data = dataWith([taskAt('今天', today)]);
      final groups = groupTasks(data, DateTime(2026, 9, 12, 23, 59, 59));
      expect(groups.today, hasLength(1));
    });

    test('返回的列表不可变', () {
      final groups = groupTasks(dataWith([taskAt('今天', today)]), today);
      expect(() => groups.today.clear(), throwsUnsupportedError);
    });

    test('prdGroups 按 PRD 顺序给出四组', () {
      final data = dataWith([
        taskAt('今天', today),
        taskAt('明天', tomorrow),
        taskAt('无日期', null),
        taskAt('已完成', today, status: TaskStatus.completed),
      ]);

      final groups = groupTasks(data, today).prdGroups;
      expect(groups.keys.toList(), ['today', 'tomorrow', 'unscheduled', 'completed']);
      expect(groups['today']!.single.id, '今天');
    });

    test('todayTaskCounts 只统计归属今天的任务（含今天已完成的）', () {
      final data = dataWith([
        taskAt('今天未做', today),
        taskAt('今天已完成', today, status: TaskStatus.completed),
        taskAt('昨天已完成', yesterday, status: TaskStatus.completed),
        taskAt('明天做', tomorrow),
      ]);

      final counts = todayTaskCounts(data, today);
      expect(counts.total, 2, reason: '昨天完成的不算今天的进度');
      expect(counts.completed, 1);
    });

    test('todayTaskCounts 对空数据返回 0/0', () {
      final counts = todayTaskCounts(const AppData(), today);
      expect(counts.total, 0);
      expect(counts.completed, 0);
    });
  });
}
