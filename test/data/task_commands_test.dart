import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

void main() {
  /// 命令层时间全部走注入，测试完全确定。
  final t0 = DateTime(2026, 9, 12, 9, 0);
  final t1 = DateTime(2026, 9, 12, 10, 30);
  final t2 = DateTime(2026, 9, 12, 21, 0);

  const emptyData = AppData();

  group('2.1 addTask', () {
    test('生成 id、写入创建与更新时间、追加到列表末尾', () {
      final data = addTask(
        emptyData,
        title: '写周报',
        dateType: TaskDateType.today,
        now: t0,
      );

      expect(data.tasks, hasLength(1));
      final task = data.tasks.single;
      expect(task.id, isNotEmpty);
      expect(task.id.startsWith('task_'), isTrue);
      expect(task.title, '写周报');
      expect(task.createdAt, t0);
      expect(task.updatedAt, t0);
      expect(task.status, TaskStatus.pending);
      expect(task.completedAt, isNull);
    });

    test('标题去除首尾空白，空标题抛 ArgumentError', () {
      final data = addTask(emptyData, title: '  买牛奶  ', now: t0);
      expect(data.tasks.single.title, '买牛奶');

      expect(
        () => addTask(emptyData, title: '   ', now: t0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => addTask(emptyData, title: '', now: t0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('每次新建的 id 都不同', () {
      var data = emptyData;
      for (var i = 0; i < 20; i++) {
        data = addTask(data, title: '任务 $i', now: t0);
      }
      expect(data.tasks.map((e) => e.id).toSet(), hasLength(20));
    });

    test('custom 类型未给日期时落到今天', () {
      final data = addTask(
        emptyData,
        title: '没给日期',
        dateType: TaskDateType.custom,
        now: t0,
      );
      expect(dayKey(data.tasks.single.date!), dayKey(t0));
    });

    test('相对日期（今天 / 明天）在写入时就固化成具体日期', () {
      // 关键回归：相对日期**绝不能**落盘成 `today` / `tomorrow`。
      // 26 号存下的 `tomorrow` 到 27 号会算成 28 号，任务一直往后漂移，
      // 而提醒时刻仍停在原定那天 → 被判为已过去 → 通知不再注册。
      final todayTask = addTask(
        emptyData,
        title: '今天',
        dateType: TaskDateType.today,
        now: t0,
      ).tasks.single;
      expect(todayTask.dateType, TaskDateType.custom, reason: '相对类型必须固化');
      expect(dayKey(todayTask.date!), dayKey(t0));

      final tomorrowTask = addTask(
        emptyData,
        title: '明天',
        dateType: TaskDateType.tomorrow,
        now: t0,
      ).tasks.single;
      expect(tomorrowTask.dateType, TaskDateType.custom);
      expect(
        dayKey(tomorrowTask.date!),
        dayKey(addDays(t0, 1)),
        reason: '明天 = 创建日 + 1 天，且写死为具体日期',
      );
    });

    test('相对日期若同时给了具体日期，以具体日期为准', () {
      // 界面按某个日期展示过（例如「明天 → 9/13」），保存时就该落到那天。
      // 这样「界面显示哪天」与「落盘哪天」同源，不会因跨零点差一天。
      final task = addTask(
        emptyData,
        title: '明天',
        dateType: TaskDateType.tomorrow,
        date: DateTime(2026, 9, 13),
        now: t0,
      ).tasks.single;

      expect(task.dateType, TaskDateType.custom);
      expect(dayKey(task.date!), '2026-09-13');
    });

    test('固化后的任务隔天再算仍指向同一天（不漂移）', () {
      final task = addTask(
        emptyData,
        title: '明天要做的',
        dateType: TaskDateType.tomorrow,
        now: t0,
      ).tasks.single;

      // 跨到第二天：「今天」变了，但任务的归属日不能跟着变
      expect(dayKey(task.resolvedDate(addDays(t0, 1))!), dayKey(addDays(t0, 1)));
      // 再往后一天也必须仍是原定那天
      expect(dayKey(task.resolvedDate(addDays(t0, 2))!), dayKey(addDays(t0, 1)));
    });

    test('无日期任务仍然没有日期（不受固化影响）', () {
      final data = addTask(emptyData, title: '未安排', now: t0);
      expect(data.tasks.single.dateType, TaskDateType.none);
      expect(data.tasks.single.date, isNull);
      expect(data.tasks.single.resolvedDate(t0), isNull);
    });

    test('无日期任务不保留提醒时间', () {
      final data = addTask(
        emptyData,
        title: '无日期',
        dateType: TaskDateType.none,
        remindAt: DateTime(2026, 9, 12, 8),
        now: t0,
      );
      expect(data.tasks.single.remindAt, isNull);
    });

    test('可以直接建成已完成状态，completedAt 同步写入', () {
      final data = addTask(
        emptyData,
        title: '已经做完了',
        status: TaskStatus.completed,
        now: t0,
      );
      expect(data.tasks.single.status, TaskStatus.completed);
      expect(data.tasks.single.completedAt, t0);
    });

    test('可以指定 id（导入合并时使用）', () {
      final data = addTask(
        emptyData,
        title: '指定 id',
        id: 'task_fixed',
        now: t0,
      );
      expect(data.tasks.single.id, 'task_fixed');
    });
  });

  group('2.1 updateTask', () {
    test('按 id 替换并刷新 updatedAt', () {
      var data = addTask(emptyData, title: '原标题', now: t0);
      final original = data.tasks.single;

      data = updateTask(
        data,
        original.copyWith(title: '新标题', note: '备注'),
        now: t1,
      );

      expect(data.tasks, hasLength(1), reason: '不应新增');
      expect(data.tasks.single.id, original.id);
      expect(data.tasks.single.title, '新标题');
      expect(data.tasks.single.note, '备注');
      expect(data.tasks.single.updatedAt, t1);
      expect(data.tasks.single.createdAt, t0, reason: '创建时间不变');
    });

    test('空标题抛 ArgumentError', () {
      var data = addTask(emptyData, title: '标题', now: t0);
      expect(
        () => updateTask(data, data.tasks.single.copyWith(title: '  '), now: t1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('任务不存在抛 ArgumentError', () {
      expect(
        () => updateTask(emptyData, makeTask(id: 'task_nope'), now: t1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('改成已完成会补 completedAt；改回其它状态会清空', () {
      var data = addTask(emptyData, title: '标题', now: t0);
      final original = data.tasks.single;

      data = updateTask(
        data,
        original.copyWith(status: TaskStatus.completed),
        now: t1,
      );
      expect(data.tasks.single.completedAt, t1);

      data = updateTask(
        data,
        data.tasks.single.copyWith(status: TaskStatus.pending),
        now: t2,
      );
      expect(data.tasks.single.completedAt, isNull);
    });

    test('状态变化会同步实例记录，纯文本修改不会', () {
      var data = addTask(
        emptyData,
        title: '今天的事',
        dateType: TaskDateType.today,
        now: t0,
      );

      // 只改标题：不产生记录
      data = updateTask(
        data,
        data.tasks.single.copyWith(note: '加个备注'),
        now: t1,
      );
      expect(data.records, isEmpty, reason: '只改文本不该写记录');

      // 改状态：产生记录
      data = updateTask(
        data,
        data.tasks.single.copyWith(status: TaskStatus.completed),
        now: t2,
      );
      expect(data.records, hasLength(1));
      expect(data.records.single.status, TaskStatus.completed);
    });

    test('改任务日期不会改写已有历史记录', () {
      var data = addTask(emptyData, title: '任务', now: t0);
      data = setTaskStatus(data, data.tasks.single.id, TaskStatus.missed,
          now: t1);
      final recordBefore = data.records.single;

      // 把任务改到明天
      data = updateTask(
        data,
        data.tasks.single.copyWith(dateType: TaskDateType.tomorrow),
        now: t2,
      );

      expect(data.records, hasLength(1));
      expect(data.records.single.id, recordBefore.id);
      expect(data.records.single.date, recordBefore.date);
      expect(data.records.single.status, TaskStatus.missed, reason: '历史是既成事实');
    });
  });

  group('2.1 deleteTask', () {
    test('删除任务并级联清理它的全部记录', () {
      var data = addTask(
        emptyData,
        title: '要删的',
        dateType: TaskDateType.today,
        now: t0,
      );
      data = addTask(data, title: '保留的', now: t0);

      final doomedId = data.tasks.first.id;
      data = setTaskStatus(data, doomedId, TaskStatus.completed, now: t1);
      expect(data.records, hasLength(1));

      data = deleteTask(data, doomedId);

      expect(data.tasks, hasLength(1));
      expect(data.tasks.single.title, '保留的');
      expect(data.records, isEmpty, reason: '记录必须级联删除，否则成孤儿数据');
    });

    test('删除不存在的任务是幂等的', () {
      final data = addTask(emptyData, title: '任务', now: t0);
      expect(deleteTask(data, 'task_nope'), data);
      expect(deleteTask(emptyData, 'task_nope'), emptyData);
    });

    test('只删除目标任务，不误伤其它任务的记录', () {
      var data = addTask(
        emptyData,
        title: 'A',
        dateType: TaskDateType.today,
        now: t0,
      );
      data = addTask(
        data,
        title: 'B',
        dateType: TaskDateType.today,
        now: t0,
      );

      final idA = data.tasks[0].id;
      final idB = data.tasks[1].id;
      data = setTaskStatus(data, idA, TaskStatus.completed, now: t1);
      data = setTaskStatus(data, idB, TaskStatus.completed, now: t1);
      expect(data.records, hasLength(2));

      data = deleteTask(data, idA);
      expect(data.records, hasLength(1));
      expect(data.records.single.taskId, idB);
    });
  });

  group('2.3 setTaskStatus 与记录落库', () {
    late String taskId;

    AppData seed() {
      final data = addTask(
        emptyData,
        title: '今天的事',
        dateType: TaskDateType.today,
        now: t0,
      );
      taskId = data.tasks.single.id;
      return data;
    }

    test('完成：写入 completedAt 并 upsert 当天记录', () {
      var data = seed();
      data = setTaskStatus(data, taskId, TaskStatus.completed, now: t1);

      expect(data.tasks.single.status, TaskStatus.completed);
      expect(data.tasks.single.completedAt, t1);
      expect(data.records, hasLength(1));

      final record = data.records.single;
      expect(record.taskId, taskId);
      expect(record.status, TaskStatus.completed);
      expect(record.completedAt, t1);
      expect(dayKey(record.date), dayKey(t0));
      expect(record.cycleId, isNull, reason: '普通任务的记录不属于循环计划');
      expect(record.cycleDayIndex, isNull);
    });

    test('取消完成：回 pending 且清空 completedAt', () {
      var data = seed();
      data = setTaskStatus(data, taskId, TaskStatus.completed, now: t1);
      data = setTaskStatus(data, taskId, TaskStatus.pending, now: t2);

      expect(data.tasks.single.status, TaskStatus.pending);
      expect(data.tasks.single.completedAt, isNull);
      expect(data.records, hasLength(1), reason: '不新增记录');
      expect(data.records.single.status, TaskStatus.pending);
      expect(data.records.single.completedAt, isNull);
    });

    test('标记未完成 → missed，跳过 → skipped，都落记录', () {
      var missed = setTaskStatus(seed(), taskId, TaskStatus.missed, now: t1);
      expect(missed.records.single.status, TaskStatus.missed);
      expect(missed.tasks.single.completedAt, isNull);

      var skipped = setTaskStatus(seed(), taskId, TaskStatus.skipped, now: t1);
      expect(skipped.records.single.status, TaskStatus.skipped);
    });

    test('反复切换状态只维护一条记录（幂等 upsert）', () {
      var data = seed();
      data = setTaskStatus(data, taskId, TaskStatus.completed, now: t1);
      final recordId = data.records.single.id;

      data = setTaskStatus(data, taskId, TaskStatus.pending, now: t1);
      data = setTaskStatus(data, taskId, TaskStatus.missed, now: t2);
      data = setTaskStatus(data, taskId, TaskStatus.completed, now: t2);

      expect(data.records, hasLength(1), reason: '同一天同一任务只应有一条记录');
      expect(data.records.single.id, recordId);
      expect(data.records.single.status, TaskStatus.completed);
    });

    test('无日期任务完成时记录落到今天', () {
      final data = addTask(
        emptyData,
        title: '随手做的事',
        dateType: TaskDateType.none,
        now: t0,
      );
      final done = setTaskStatus(
        data,
        data.tasks.single.id,
        TaskStatus.completed,
        now: t1,
      );

      expect(done.records, hasLength(1));
      expect(dayKey(done.records.single.date), dayKey(t1));
    });

    test('明日任务完成时记录落到明天', () {
      final data = addTask(
        emptyData,
        title: '明天的事',
        dateType: TaskDateType.tomorrow,
        now: t0,
      );
      final done = setTaskStatus(
        data,
        data.tasks.single.id,
        TaskStatus.completed,
        now: t1,
      );

      expect(dayKey(done.records.single.date), dayKey(addDays(t0, 1)));
    });

    test('writeRecord=false 时只改任务状态', () {
      final data = setTaskStatus(
        seed(),
        taskId,
        TaskStatus.completed,
        now: t1,
        writeRecord: false,
      );
      expect(data.tasks.single.status, TaskStatus.completed);
      expect(data.records, isEmpty);
    });

    test('任务不存在抛 ArgumentError', () {
      expect(
        () => setTaskStatus(emptyData, 'task_nope', TaskStatus.completed),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('不改动其它任务与其记录', () {
      var data = addTask(
        emptyData,
        title: 'A',
        dateType: TaskDateType.today,
        now: t0,
      );
      data = addTask(
        data,
        title: 'B',
        dateType: TaskDateType.today,
        now: t0,
      );
      final idA = data.tasks[0].id;
      final idB = data.tasks[1].id;

      data = setTaskStatus(data, idA, TaskStatus.completed, now: t1);

      expect(data.tasks.firstWhere((e) => e.id == idB).status,
          TaskStatus.pending);
      expect(data.records, hasLength(1));
      expect(data.records.single.taskId, idA);
    });

    test('便捷方法语义正确', () {
      final base = seed();
      expect(completeTask(base, taskId, now: t1).tasks.single.status,
          TaskStatus.completed);
      expect(markTaskMissed(base, taskId, now: t1).tasks.single.status,
          TaskStatus.missed);
      expect(markTaskSkipped(base, taskId, now: t1).tasks.single.status,
          TaskStatus.skipped);

      final done = completeTask(base, taskId, now: t1);
      expect(uncompleteTask(done, taskId, now: t2).tasks.single.status,
          TaskStatus.pending);
    });
  });

  group('2.1 materializeTaskDate', () {
    test('把「今天」固化成具体日期', () {
      final data = addTask(
        emptyData,
        title: '今天的事',
        dateType: TaskDateType.today,
        now: t0,
      );
      final materialized =
          materializeTaskDate(data, data.tasks.single.id, now: t0);

      final task = materialized.tasks.single;
      expect(task.dateType, TaskDateType.custom);
      expect(dayKey(task.date!), dayKey(t0));
      expect(task.updatedAt, t0);
    });

    test('无日期任务不受影响', () {
      final data = addTask(
        emptyData,
        title: '无日期',
        dateType: TaskDateType.none,
        now: t0,
      );
      final result = materializeTaskDate(data, data.tasks.single.id, now: t1);
      expect(result.tasks.single.dateType, TaskDateType.none);
      expect(result.tasks.single.updatedAt, t0, reason: '不该刷新更新时间');
    });

    test('任务不存在时原样返回', () {
      final data = addTask(emptyData, title: '任务', now: t0);
      expect(materializeTaskDate(data, 'task_nope', now: t1), data);
    });
  });

  group('2.4 命令层不变量', () {
    test('所有命令都返回新对象，不改动入参（不可变快照）', () {
      final before = addTask(emptyData, title: '原标题', now: t0);
      final snapshot = before;

      final after = updateTask(
        before,
        before.tasks.single.copyWith(title: '新标题'),
        now: t1,
      );

      expect(before.tasks.single.title, '原标题', reason: '入参必须保持不变');
      expect(after.tasks.single.title, '新标题');
      expect(
        identical(before.tasks, after.tasks),
        isFalse,
        reason: 'tasks 列表应换成新实例',
      );
      expect(snapshot, before);
    });

    test('列表始终保持不可变，防止外部误改', () {
      final data = addTask(emptyData, title: '任务', now: t0);
      expect(() => data.tasks.clear(), throwsUnsupportedError);
    });

    test('命令可以串起来组合成一次提交', () {
      var data = addTask(
        emptyData,
        title: 'A',
        dateType: TaskDateType.today,
        now: t0,
      );
      data = addTask(
        data,
        title: 'B',
        dateType: TaskDateType.today,
        now: t0,
      );
      final idB = data.tasks[1].id;

      data = setTaskStatus(data, idB, TaskStatus.completed, now: t1);
      data = deleteTask(data, data.tasks.first.id);

      expect(data.tasks, hasLength(1));
      expect(data.tasks.single.title, 'B');
      expect(data.records.single.status, TaskStatus.completed);
    });

    test('isValidTaskTitle 与 addTask 的校验保持一致', () {
      expect(isValidTaskTitle('正常'), isTrue);
      expect(isValidTaskTitle('  正常  '), isTrue);
      expect(isValidTaskTitle(''), isFalse);
      expect(isValidTaskTitle('   '), isFalse);
    });
  });
}
