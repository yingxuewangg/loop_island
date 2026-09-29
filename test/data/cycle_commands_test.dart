import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 阶段 3 命令层验收（3.12 / 3.13 / 3.14 / 3.15）。
void main() {
  final start = DateTime(2026, 9, 12);

  /// 8 天计划，每天 1 个任务；第 4 天为休息日。
  Cycle plan({CycleStatus status = CycleStatus.active}) {
    return makeCycle(
      id: 'cycle_1',
      name: '训练计划',
      periodDays: 8,
      startDate: start,
      status: status,
      days: [
        for (var i = 1; i <= 8; i++)
          makeCycleDay(
            dayIndex: i,
            isRestDay: i == 4,
            templates: i == 4
                ? const []
                : [makeCycleTemplate(id: 'ctask_$i', title: '第 $i 天任务')],
          ),
      ],
    );
  }

  AppData dataWith(Cycle cycle, {List<dynamic> records = const []}) {
    return AppData(
      cycles: List.unmodifiable([cycle]),
      records: List.unmodifiable(records.cast()),
    );
  }

  group('3.12 updateCycleDay：某天任务增删排序与休息日', () {
    test('新增任务后模板落库并保持 order 连续', () {
      final data = dataWith(plan());
      final day = data.cycles.single.dayAt(2).addTemplate(
            makeCycleTemplate(id: 'ctask_new', title: '拉伸'),
          );

      final next = updateCycleDay(data, 'cycle_1', day, now: start);
      final saved = next.cycles.single.dayAt(2);

      expect(saved.taskCount, 2);
      expect(saved.sortedTemplates.map((e) => e.id).toList(),
          ['ctask_2', 'ctask_new']);
      expect(saved.sortedTemplates.map((e) => e.order).toList(), [0, 1]);
    });

    test('删除任务后 order 重排', () {
      var data = dataWith(plan());
      var day = data.cycles.single.dayAt(2);
      day = day.addTemplate(makeCycleTemplate(id: 'ctask_extra', title: 'B'));
      data = updateCycleDay(data, 'cycle_1', day, now: start);

      final afterDelete = data.cycles.single
          .dayAt(2)
          .removeTemplate('ctask_2');
      final next = updateCycleDay(data, 'cycle_1', afterDelete, now: start);

      final saved = next.cycles.single.dayAt(2);
      expect(saved.taskCount, 1);
      expect(saved.sortedTemplates.single.id, 'ctask_extra');
      expect(saved.sortedTemplates.single.order, 0);
    });

    test('排序（上移）会持久化', () {
      var data = dataWith(plan());
      var day = data.cycles.single.dayAt(1);
      day = day.addTemplate(makeCycleTemplate(id: 'ctask_b', title: 'B'));

      final moved = day.moveTemplate(1, 0);
      final next = updateCycleDay(data, 'cycle_1', moved, now: start);

      expect(
        next.cycles.single.dayAt(1).sortedTemplates.map((e) => e.id).toList(),
        ['ctask_b', 'ctask_1'],
      );
    });

    test('设为休息日会清空任务', () {
      final data = dataWith(plan());
      final day = data.cycles.single
          .dayAt(2)
          .copyWith(isRestDay: true, templates: const []);

      final next = updateCycleDay(data, 'cycle_1', day, now: start);
      final saved = next.cycles.single.dayAt(2);
      expect(saved.isRestDay, isTrue);
      expect(saved.isEmpty, isTrue);
    });

    test('休息日不再产生新实例', () {
      var data = dataWith(plan());
      data = materializeDay(data, addDays(start, 3), now: start, today: start);
      expect(data.records, isEmpty, reason: '第 4 天是休息日');
    });

    test('计划不存在时原样返回', () {
      final data = dataWith(plan());
      expect(
        updateCycleDay(data, 'cycle_nope', CycleDay.empty(1), now: start),
        data,
      );
    });
  });

  group('3.14 修改作用域：仅本次 / 以后所有', () {
    test('仅本次：只改当天实例，不动模板', () {
      var data = dataWith(plan());
      data = materializeDay(data, start, now: start, today: start);
      expect(data.records, hasLength(1));

      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.once,
        status: TaskStatus.missed,
        reason: '加班，没时间',
        now: start,
      );

      final record = next.records.single;
      expect(record.status, TaskStatus.missed);
      expect(record.reason, '加班，没时间');
      expect(
        next.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
        reason: '模板不能被改动',
      );
    });

    test('仅本次：实例还不存在时会补建', () {
      final data = dataWith(plan());
      expect(data.records, isEmpty);

      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_3',
        date: addDays(start, 2),
        scope: EditScope.once,
        status: TaskStatus.skipped,
        now: start,
      );

      expect(next.records, hasLength(1));
      expect(next.records.single.cycleDayIndex, 3);
      expect(next.records.single.status, TaskStatus.skipped);
    });

    test('以后所有：改模板并重算未来实例，历史不变', () {
      var data = dataWith(plan());
      data = materializeRange(data, 'cycle_1', start, addDays(start, 3),
          now: start, today: start);
      expect(data.records, hasLength(3), reason: '第 4 天是休息日');

      // 把第 1 天的任务标记完成，作为「历史」
      data = data.copyWith(records: List.unmodifiable([
        for (final record in data.records)
          if (isSameDay(record.date, start))
            record.withStatus(TaskStatus.completed, at: start)
          else
            record,
      ]));

      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.fromNowAll,
        title: '改成慢跑',
        now: addDays(start, 5),
      );

      expect(
        next.cycles.single.dayAt(1).templates.single.title,
        '改成慢跑',
      );
      // 历史记录（第 1 天那条）保持完成状态
      final history = next.records
          .firstWhere((e) => isSameDay(e.date, start));
      expect(history.status, TaskStatus.completed);
    });

    test('以后所有：标题为空时不改', () {
      final data = dataWith(plan());
      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.fromNowAll,
        title: '   ',
        now: start,
      );
      expect(next, data);
    });

    test('仅本次：可以改这一天的标题，模板与其它天不受影响', () {
      var data = dataWith(plan());
      data = materializeDay(data, start, now: start, today: start);

      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.once,
        title: '今天改成慢跑',
        now: start,
      );

      expect(next.records.single.titleOverride, '今天改成慢跑');
      expect(
        next.cycles.single.dayAt(1).templates.single.title,
        '第 1 天任务',
        reason: '模板必须保持原样',
      );
    });

    test('仅本次：空标题按清空覆盖处理', () {
      var data = dataWith(plan());
      data = materializeDay(data, start, now: start, today: start);
      data = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.once,
        title: '改了',
        now: start,
      );
      expect(data.records.single.titleOverride, '改了');

      final cleared = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.once,
        title: '   ',
        now: start,
      );
      expect(cleared.records.single.titleOverride, isNull);
    });

    test('以后所有：改标题后重算实例，但不清除已有的实例级覆盖', () {
      var data = dataWith(plan());
      data = materializeDay(data, start, now: start, today: start);
      data = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.once,
        title: '今天专属',
        now: start,
      );

      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_1',
        date: start,
        scope: EditScope.fromNowAll,
        title: '模板新名字',
        now: start,
      );

      expect(
        next.cycles.single.dayAt(1).templates.single.title,
        '模板新名字',
      );
      // rebuildFutureInstances 会按 horizonDays 补出未来若干天的实例，
      // 所以这里只针对「今天那一条」断言，而不是 records.single。
      final todayRecord =
          next.records.firstWhere((e) => isSameDay(e.date, start));
      expect(
        todayRecord.titleOverride,
        '今天专属',
        reason: '实例级覆盖属于当天的事实，改模板不该抹掉它',
      );
    });

    test('找不到模板时原样返回', () {
      final data = dataWith(plan());
      final next = editCycleInstance(
        data,
        cycleId: 'cycle_1',
        templateId: 'ctask_nope',
        date: start,
        scope: EditScope.fromNowAll,
        title: 'X',
        now: start,
      );
      expect(next, data);
    });
  });

  group('3.15 结束日期变更后未来实例重算', () {
    test('缩短结束日：删掉越界的待办实例', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: start,
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 9),
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [makeCycleTemplate(id: 't1', title: '每天')],
              ),
            ],
          ),
        ]),
      );
      data = rebuildFutureInstances(data, 'cycle_1', start,
          now: start, today: start);
      expect(data.records, hasLength(10));

      final shortened = data.cycles.single.copyWith(endDate: addDays(start, 4));
      final next = rebuildFutureInstances(
        data.copyWith(cycles: List.unmodifiable([shortened])),
        'cycle_1',
        start,
        now: start,
        today: start,
      );

      expect(next.records, hasLength(5));
      expect(
        next.records.every((e) => isSameOrBeforeDay(e.date, addDays(start, 4))),
        isTrue,
      );
    });

    test('缩短结束日：今天之前的历史与已了结记录都保留', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: addDays(start, -5),
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 9),
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [makeCycleTemplate(id: 't1', title: '每天')],
              ),
            ],
          ),
        ]),
      );
      final today = start;
      data = rebuildFutureInstances(data, 'cycle_1', addDays(start, -5),
          now: today, today: today);
      expect(data.records, hasLength(15));

      // 昨天那条标记未完成并写原因
      data = data.copyWith(records: List.unmodifiable([
        for (final record in data.records)
          if (isSameDay(record.date, addDays(today, -1)))
            record.withStatus(TaskStatus.missed, at: today).withReason('身体不适')
          else
            record,
      ]));

      final shortened = data.cycles.single.copyWith(endDate: addDays(start, 1));
      final next = rebuildFutureInstances(
        data.copyWith(cycles: List.unmodifiable([shortened])),
        'cycle_1',
        today,
        now: today,
        today: today,
      );

      // 今天之前（start-5 .. start-1）全部保留
      final past = next.records
          .where((e) => isBeforeDay(e.date, today))
          .toList();
      expect(past, hasLength(5));
      final yesterday = past
          .firstWhere((e) => isSameDay(e.date, addDays(today, -1)));
      expect(yesterday.status, TaskStatus.missed);
      expect(yesterday.reason, '身体不适');

      // 今天起只剩 start..start+1
      final future =
          next.records.where((e) => isSameOrAfterDay(e.date, today)).toList();
      expect(future, hasLength(2));
    });

    test('延长结束日：补出新的未来实例', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: start,
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 1),
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [makeCycleTemplate(id: 't1', title: '每天')],
              ),
            ],
          ),
        ]),
      );
      data = rebuildFutureInstances(data, 'cycle_1', start,
          now: start, today: start);
      expect(data.records, hasLength(2));

      final extended = data.cycles.single.copyWith(endDate: addDays(start, 6));
      final next = rebuildFutureInstances(
        data.copyWith(cycles: List.unmodifiable([extended])),
        'cycle_1',
        start,
        now: start,
        today: start,
      );
      expect(next.records, hasLength(7));
    });

    test('改成「循环 1 次」后次日不再有实例', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 3,
            startDate: start,
            days: [
              for (var i = 1; i <= 3; i++)
                makeCycleDay(
                  dayIndex: i,
                  templates: [makeCycleTemplate(id: 't$i', title: '第 $i 天')],
                ),
            ],
          ),
        ]),
      );

      final oneRound = data.cycles.single.copyWith(
        endType: CycleEndType.afterCount,
        endCount: 1,
      );
      data = data.copyWith(cycles: List.unmodifiable([oneRound]));

      final next = rebuildFutureInstances(data, 'cycle_1', start,
          now: start, today: start);
      expect(next.records, hasLength(3), reason: '3 天计划只跑一轮');

      // 第 4 天（下一轮第 1 天）不应再有实例
      final day4 = materializeDay(next, addDays(start, 3),
          now: start, today: addDays(start, 3));
      expect(day4.records, hasLength(3), reason: '次日不再生成新实例');
    });

    test('计划的结束日已经早于重建起点时不再补实例', () {
      final data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: start,
            endType: CycleEndType.untilDate,
            endDate: addDays(start, 2),
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [makeCycleTemplate(id: 't1')],
              ),
            ],
          ),
        ]),
      );

      final next = rebuildFutureInstances(
        data,
        'cycle_1',
        addDays(start, 10),
        now: addDays(start, 10),
        today: addDays(start, 10),
      );
      expect(next.records, isEmpty);
    });
  });

  group('3.13 生命周期命令', () {
    test('pause / resume', () {
      var data = dataWith(plan());
      data = pauseCycle(data, 'cycle_1', now: start);
      expect(data.cycles.single.status, CycleStatus.paused);

      data = resumeCycle(data, 'cycle_1', now: addDays(start, 1));
      expect(data.cycles.single.status, CycleStatus.active);
    });

    test('已过期的暂停计划不可恢复（静默无操作）', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 1,
            startDate: addDays(start, -10),
            endType: CycleEndType.untilDate,
            endDate: addDays(start, -1),
            status: CycleStatus.paused,
            days: [
              makeCycleDay(
                dayIndex: 1,
                templates: [makeCycleTemplate(id: 't1')],
              ),
            ],
          ),
        ]),
      );

      final before = data;
      data = resumeCycle(data, 'cycle_1', now: start);
      expect(data, before, reason: '不可恢复时不应该有任何改动');
    });

    test('delete 级联删除该计划的全部记录，且不动普通任务的记录', () {
      var data = AppData(
        cycles: List.unmodifiable([plan()]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r_cycle',
            taskId: 'ctask_1',
            cycleId: 'cycle_1',
            cycleDayIndex: 1,
            date: start,
          ),
          makeRecord(id: 'r_plain', taskId: 'task_1', date: start),
        ]),
      );

      data = deleteCycle(data, 'cycle_1');
      expect(data.cycles, isEmpty);
      expect(data.records, hasLength(1));
      expect(data.records.single.id, 'r_plain');
    });

    test('copy 生成独立计划：新 id、名称后缀、起始日今天、模板 id 重生成', () {
      final data = dataWith(plan());
      final next = duplicateCycle(
        data,
        'cycle_1',
        today: start,
        now: start,
        suffix: '（副本）',
      );

      expect(next.cycles, hasLength(2));
      final copy = next.cycles.firstWhere((e) => e.id != 'cycle_1');
      expect(copy.name, '训练计划（副本）');
      expect(copy.startDate, start);
      expect(copy.status, CycleStatus.active);
      expect(copy.periodDays, 8);
      expect(copy.dayAt(4).isRestDay, isTrue, reason: '休息日也要复制');
      expect(copy.dayAt(1).templates.single.id, isNot('ctask_1'));
      expect(copy.days, hasLength(8));
    });

    test('upsert 新建计划时补齐未来实例', () {
      final data = AppData();
      final created = Cycle.create(
        name: '新计划',
        periodDays: 2,
        startDate: start,
        endType: CycleEndType.untilDate,
        endDate: addDays(start, 3),
        now: start,
      ).withDay(
        makeCycleDay(
          dayIndex: 1,
          templates: [makeCycleTemplate(id: 't1', title: 'A')],
        ),
      ).withDay(
        makeCycleDay(
          dayIndex: 2,
          templates: [makeCycleTemplate(id: 't2', title: 'B')],
        ),
      );

      final next = upsertCycle(data, created, now: start, today: start);
      expect(next.cycles, hasLength(1));
      expect(next.records, hasLength(4), reason: '4 天 = 2 轮 × 2 天');
    });

    test('upsert 更新计划时替换而不是追加', () {
      var data = dataWith(plan());
      final renamed = data.cycles.single.copyWith(name: '改过名');
      data = upsertCycle(data, renamed, now: start, today: start);

      expect(data.cycles, hasLength(1));
      expect(data.cycles.single.name, '改过名');
    });
  });
}
