import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/record_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 原因写入服务验收（任务 6.3）。
void main() {
  final today = DateTime(2026, 9, 12, 21, 0);
  final day = dateOnly(today);

  AppData withPlainTask() => AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_1', title: '跑步')]),
      );

  AppData withCycleInstance({bool materialized = true}) => AppData(
        tasks: const [],
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            name: '8 天跑步训练',
            periodDays: 8,
            startDate: day,
            days: [
              for (var i = 1; i <= 8; i++)
                makeCycleDay(
                  dayIndex: i,
                  templates: [makeCycleTemplate(id: 'ctask_$i')],
                ),
            ],
          ),
        ]),
        records: materialized
            ? List.unmodifiable([
                makeRecord(
                  id: 'r1',
                  taskId: 'ctask_1',
                  cycleId: 'cycle_1',
                  cycleDayIndex: 1,
                  date: day,
                ),
              ])
            : const [],
      );

  group('setEntryReason', () {
    test('给普通任务写原因：写入文本与更新时间', () {
      final next = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '加班，没时间',
        now: today,
      );

      expect(next.records, hasLength(1));
      final record = next.records.single;
      expect(record.reason, '加班，没时间');
      expect(record.reasonUpdatedAt, today);
      expect(record.taskId, 'task_1');
      expect(dayKey(record.date), dayKey(day));
    });

    test('记录不存在时补建，避免「填了原因却看不到」', () {
      final next = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: today,
      );
      expect(next.records, hasLength(1));
      expect(next.records.single.status, TaskStatus.pending);
    });

    test('只动原因，不改状态', () {
      var data = withCycleInstance();
      data = data.copyWith(records: List.unmodifiable([
        data.records.single.withStatus(TaskStatus.missed, at: today),
      ]));

      final next = setEntryReason(
        data,
        taskId: 'ctask_1',
        date: day,
        cycleId: 'cycle_1',
        reason: '身体不适',
        now: today,
      );

      expect(next.records.single.reason, '身体不适');
      expect(next.records.single.status, TaskStatus.missed, reason: '状态保持');
    });

    test('空白原因按清空处理，并清掉更新时间', () {
      var data = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: today,
      );
      expect(data.records.single.hasReason, isTrue);

      data = setEntryReason(
        data,
        taskId: 'task_1',
        date: day,
        reason: '   ',
        now: today,
      );
      expect(data.records.single.reason, isNull);
      expect(data.records.single.reasonUpdatedAt, isNull);
    });

    test('传 null 也是清空', () {
      var data = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: today,
      );
      data = setEntryReason(data, taskId: 'task_1', date: day, reason: null);
      expect(data.records.single.reason, isNull);
    });

    test('修剪首尾空白', () {
      final next = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '  在开会  ',
        now: today,
      );
      expect(next.records.single.reason, '在开会');
    });

    test('循环实例：按 cycleId 定位，不会误伤同类模板的另一天', () {
      var data = AppData(
        cycles: List.unmodifiable([
          makeCycle(
            id: 'cycle_1',
            periodDays: 8,
            startDate: day,
            days: [
              for (var i = 1; i <= 8; i++)
                makeCycleDay(
                  dayIndex: i,
                  templates: [makeCycleTemplate(id: 'ctask_1')],
                ),
            ],
          ),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r_day1',
            taskId: 'ctask_1',
            cycleId: 'cycle_1',
            cycleDayIndex: 1,
            date: day,
          ),
          makeRecord(
            id: 'r_day2',
            taskId: 'ctask_1',
            cycleId: 'cycle_1',
            cycleDayIndex: 2,
            date: addDays(day, 1),
          ),
        ]),
      );

      data = setEntryReason(
        data,
        taskId: 'ctask_1',
        date: addDays(day, 1),
        cycleId: 'cycle_1',
        reason: '天气原因',
        now: today,
      );

      expect(data.recordById('r_day2')!.reason, '天气原因');
      expect(data.recordById('r_day1')!.reason, isNull);
    });

    test('幂等：写同样的原因不产生新记录', () {
      var data = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: today,
      );
      final before = data;
      data = setEntryReason(
        data,
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: addDays(today, 1),
      );
      expect(data.records, hasLength(1));
      expect(before.records.single.reason, data.records.single.reason);
    });

    test('入参不被修改', () {
      final data = withPlainTask();
      setEntryReason(
        data,
        taskId: 'task_1',
        date: day,
        reason: '忘记',
        now: today,
      );
      expect(data.records, isEmpty);
    });
  });

  group('setRecordReason（按记录 id）', () {
    test('写入与清空', () {
      var data = withCycleInstance();
      data = setRecordReason(data, 'r1', '临时有事', now: today);
      expect(data.records.single.reason, '临时有事');
      expect(data.records.single.reasonUpdatedAt, today);

      data = setRecordReason(data, 'r1', null, now: today);
      expect(data.records.single.reason, isNull);
    });

    test('记录不存在时原样返回', () {
      final data = withCycleInstance();
      expect(setRecordReason(data, 'r_nope', 'x', now: today), data);
    });
  });

  group('markRecordMissed（按记录 id）', () {
    test('标记未完成并同时写原因', () {
      final data = markRecordMissed(
        withCycleInstance(),
        'r1',
        reason: '任务太难',
        now: today,
      );
      expect(data.records.single.status, TaskStatus.missed);
      expect(data.records.single.reason, '任务太难');
      expect(data.records.single.completedAt, isNull);
    });

    test('不传原因时只改状态', () {
      final data = markRecordMissed(withCycleInstance(), 'r1', now: today);
      expect(data.records.single.status, TaskStatus.missed);
      expect(data.records.single.reason, isNull);
    });

    test('记录不存在时原样返回', () {
      final data = withCycleInstance();
      expect(markRecordMissed(data, 'r_nope', now: today), data);
    });
  });

  group('ensureEntryRecord / entryReason', () {
    test('已存在时原样返回', () {
      final data = withCycleInstance();
      final result = ensureEntryRecord(
        data,
        taskId: 'ctask_1',
        date: day,
        cycleId: 'cycle_1',
      );
      expect(identical(result.data, data), isTrue);
      expect(result.record.id, 'r1');
    });

    test('不存在时补建并带上 cycleDayIndex', () {
      final result = ensureEntryRecord(
        withCycleInstance(materialized: false),
        taskId: 'ctask_3',
        date: day,
        cycleId: 'cycle_1',
        cycleDayIndex: 3,
      );
      expect(result.data.records, hasLength(1));
      expect(result.record.cycleDayIndex, 3);
      expect(result.record.status, TaskStatus.pending);
    });

    test('entryReason 读回原因', () {
      final data = setEntryReason(
        withPlainTask(),
        taskId: 'task_1',
        date: day,
        reason: '没时间',
        now: today,
      );
      expect(entryReason(data, taskId: 'task_1', date: day), '没时间');
      expect(
        entryReason(data, taskId: 'task_1', date: addDays(day, 1)),
        isNull,
      );
    });
  });
}
