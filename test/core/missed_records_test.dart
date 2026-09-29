import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/missed_records.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 未完成记录读取与标题解析（任务 5.9 的计算部分）。
void main() {
  final today = DateTime(2026, 9, 12);

  Cycle cycle({Map<int, String> titles = const {}}) {
    return makeCycle(
      id: 'cycle_1',
      name: '8 天跑步训练',
      periodDays: 8,
      startDate: today,
      days: [
        for (var i = 1; i <= 8; i++)
          makeCycleDay(
            dayIndex: i,
            templates: [
              makeCycleTemplate(
                id: 'ctask_$i',
                title: titles[i] ?? '第 $i 天任务',
              ),
            ],
          ),
      ],
    );
  }

  group('recordDisplayTitle', () {
    test('普通任务取任务标题', () {
      final data = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_1', title: '写周报')]),
      );
      final record = makeRecord(taskId: 'task_1', date: today);
      expect(recordDisplayTitle(data, record), '写周报');
    });

    test('循环实例取模板标题', () {
      final data = AppData(cycles: List.unmodifiable([cycle()]));
      final record = makeRecord(
        taskId: 'ctask_3',
        cycleId: 'cycle_1',
        cycleDayIndex: 3,
        date: today,
      );
      expect(recordDisplayTitle(data, record), '第 3 天任务');
    });

    test('实例级标题覆盖优先于模板标题', () {
      final data = AppData(cycles: List.unmodifiable([cycle()]));
      final record = makeRecord(
        taskId: 'ctask_3',
        cycleId: 'cycle_1',
        cycleDayIndex: 3,
        date: today,
      ).withTitleOverride('今天改成慢跑');
      expect(recordDisplayTitle(data, record), '今天改成慢跑');
    });

    test('任务已删除时返回占位文案', () {
      final data = const AppData();
      final record = makeRecord(taskId: 'task_gone', date: today);
      expect(
        recordDisplayTitle(data, record, fallback: '已删除的任务'),
        '已删除的任务',
      );
    });

    test('计划已删除时返回占位文案', () {
      final data = const AppData();
      final record = makeRecord(
        taskId: 'ctask_1',
        cycleId: 'cycle_gone',
        cycleDayIndex: 1,
        date: today,
      );
      expect(recordDisplayTitle(data, record, fallback: '已删除的任务'), '已删除的任务');
    });

    test('计划还在但模板被删掉时也返回占位文案', () {
      final data = AppData(cycles: List.unmodifiable([cycle()]));
      final record = makeRecord(
        taskId: 'ctask_99',
        cycleId: 'cycle_1',
        cycleDayIndex: 1,
        date: today,
      );
      expect(recordDisplayTitle(data, record, fallback: '已删除的任务'), '已删除的任务');
    });
  });

  group('missedEntries', () {
    test('只取 missed，按日期倒序', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_a', title: 'A'),
          makeTask(id: 'task_b', title: 'B'),
          makeTask(id: 'task_c', title: 'C'),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r_old',
            taskId: 'task_a',
            date: addDays(today, -5),
            status: TaskStatus.missed,
          ),
          makeRecord(
            id: 'r_new',
            taskId: 'task_b',
            date: addDays(today, -1),
            status: TaskStatus.missed,
          ),
          // 不是 missed，不该出现
          makeRecord(
            id: 'r_done',
            taskId: 'task_c',
            date: today,
            status: TaskStatus.completed,
            completedAt: today,
          ),
          makeRecord(
            id: 'r_skip',
            taskId: 'task_c',
            date: today,
            status: TaskStatus.skipped,
          ),
        ]),
      );

      final entries = missedEntries(data);
      expect(entries.map((e) => e.record.id).toList(), ['r_new', 'r_old']);
      expect(entries.first.title, 'B');
    });

    test('原因会带出来；没填原因时为 null', () {
      final data = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_a', title: 'A'),
          makeTask(id: 'task_b', title: 'B'),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'task_a',
            date: addDays(today, -2),
            status: TaskStatus.missed,
            reason: '加班，没时间',
          ),
          makeRecord(
            id: 'r2',
            taskId: 'task_b',
            date: addDays(today, -1),
            status: TaskStatus.missed,
          ),
        ]),
      );

      final entries = missedEntries(data);
      expect(entries.first.record.id, 'r2');
      expect(entries.first.reason, isNull);
      expect(entries.first.hasReason, isFalse);
      expect(entries.last.reason, '加班，没时间');
      expect(entries.last.hasReason, isTrue);
    });

    test('循环实例的标题可解析（用于「跑步：加班，没时间」这种行）', () {
      final data = AppData(
        cycles: List.unmodifiable([cycle(titles: const {3: '跑步'})]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'ctask_3',
            cycleId: 'cycle_1',
            cycleDayIndex: 3,
            date: today,
            status: TaskStatus.missed,
            reason: '加班，没时间',
          ),
        ]),
      );

      final entry = missedEntries(data).single;
      expect(entry.title, '跑步');
      expect(entry.reason, '加班，没时间');
    });

    test('maxItems 截断', () {
      final data = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_a', title: 'A')]),
        records: List.unmodifiable([
          for (var i = 0; i < 5; i++)
            makeRecord(
              id: 'r$i',
              taskId: 'task_a',
              date: addDays(today, -i),
              status: TaskStatus.missed,
            ),
        ]),
      );

      expect(missedEntries(data, maxItems: 3), hasLength(3));
      expect(missedEntries(data), hasLength(5));
    });

    test('同一天内顺序稳定（按 id）', () {
      final data = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_a', title: 'A')]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r_b',
            taskId: 'task_a',
            date: today,
            status: TaskStatus.missed,
          ),
          makeRecord(
            id: 'r_a',
            taskId: 'task_a',
            date: today,
            status: TaskStatus.missed,
          ),
        ]),
      );

      expect(
        missedEntries(data).map((e) => e.record.id).toList(),
        ['r_a', 'r_b'],
      );
    });

    test('没有未完成记录时返回空', () {
      expect(missedEntries(const AppData()), isEmpty);
    });

    test('返回的列表不可变', () {
      final data = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_a')]),
        records: List.unmodifiable([
          makeRecord(
            taskId: 'task_a',
            date: today,
            status: TaskStatus.missed,
          ),
        ]),
      );
      expect(() => missedEntries(data).clear(), throwsUnsupportedError);
    });
  });
}
