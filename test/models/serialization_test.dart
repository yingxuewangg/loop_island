import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/record.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/models/task.dart';

import '../support/factories.dart';

/// 经过真实 JSON 编解码的往返，能暴露「只比较 Dart 对象」发现不了的
/// 类型丢失问题（例如 DateTime 被写成不可解析的字符串）。
Map<String, dynamic> reencode(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  group('1.9 模型序列化往返', () {
    test('Task：字段齐全时往返一致', () {
      final task = makeTask(
        note: '记得附上截图',
        dateType: TaskDateType.custom,
        date: DateTime(2026, 9, 20),
        remindAt: DateTime(2026, 9, 20, 8, 30),
        status: TaskStatus.missed,
        completedAt: DateTime(2026, 9, 20, 9, 0),
      );

      final restored = Task.fromJson(reencode(task.toJson()));
      expect(restored, task);
      expect(restored.note, '记得附上截图');
      expect(restored.remindAt!.hour, 8);
      expect(restored.remindAt!.minute, 30);
    });

    test('Task：最小字段往返一致', () {
      final task = makeTask(hasDate: false);
      expect(Task.fromJson(reencode(task.toJson())), task);
    });

    test('Task：多时段提醒往返一致', () {
      final task = makeTask(
        remindAts: [
          DateTime(2026, 9, 20, 10, 30),
          DateTime(2026, 9, 20, 15, 30),
        ],
      );
      final restored = Task.fromJson(reencode(task.toJson()));
      expect(restored, task);
      expect(restored.remindAts, hasLength(2));
      expect(restored.remindAt!.hour, 10, reason: 'remindAt 取最早的时段');
    });

    test('Task：老备份的单个 remindAt 能无缝升级成多时段', () {
      // 老版本写的是 `remindAt` 字符串；新版本要能读出来并当成唯一的时段
      final legacy = {
        'id': 'task_old',
        'title': '老任务',
        'note': '',
        'dateType': 'custom',
        'date': '2026-09-20',
        'remindAt': DateTime(2026, 9, 20, 8, 30).toUtc().toIso8601String(),
        'status': 'pending',
        'createdAt': DateTime(2026, 9, 1).toUtc().toIso8601String(),
        'updatedAt': DateTime(2026, 9, 1).toUtc().toIso8601String(),
      };

      final restored = Task.fromJson(legacy);
      expect(restored.remindAts, hasLength(1));
      expect(restored.remindAt, DateTime(2026, 9, 20, 8, 30));
    });

    test('CycleTaskTemplate：往返一致（提醒用分钟数）', () {
      final template = makeCycleTemplate(
        remindMinuteOfDay: 7 * 60 + 5,
        order: 2,
      );
      final restored =
          CycleTaskTemplate.fromJson(reencode(template.toJson()));
      expect(restored, template);
      expect(restored.remindLabel, '07:05');
    });

    test('CycleDay：含多个模板往返一致', () {
      final day = makeCycleDay(
        dayIndex: 3,
        templates: [
          makeCycleTemplate(id: 'ctask_a', title: '热身', order: 0),
          makeCycleTemplate(id: 'ctask_b', title: '慢跑', order: 1),
        ],
      );
      final restored = CycleDay.fromJson(reencode(day.toJson()));
      expect(restored, day);
      expect(restored.taskCount, 2);
    });

    test('Cycle：8 天计划含结束条件往返一致', () {
      final cycle = makeCycle(
        periodDays: 8,
        endType: CycleEndType.afterCount,
        endCount: 3,
        remindMinuteOfDay: 6 * 60 + 30,
        days: [
          for (var i = 1; i <= 8; i++)
            i == 4
                ? makeCycleDay(dayIndex: 4, isRestDay: true)
                : makeCycleDay(
                    dayIndex: i,
                    templates: [
                      makeCycleTemplate(id: 'ctask_$i', order: 0),
                    ],
                  ),
        ],
      );

      final restored = Cycle.fromJson(reencode(cycle.toJson()));
      expect(restored, cycle);
      expect(restored.days.length, 8);
      expect(restored.dayAt(4).isRestDay, isTrue);
      expect(restored.dayAt(1).taskCount, 1);
      expect(restored.remindLabel, '06:30');
    });

    test('Cycle：结束日期型往返一致', () {
      final cycle = makeCycle(
        endType: CycleEndType.untilDate,
        endDate: DateTime(2026, 10, 19),
        completeCyclesOnly: true,
        status: CycleStatus.ended,
        endedAt: DateTime(2026, 10, 20, 0, 0),
      );
      final restored = Cycle.fromJson(reencode(cycle.toJson()));
      expect(restored, cycle);
      expect(dayKey(restored.endDate!), '2026-10-19');
      expect(restored.completeCyclesOnly, isTrue);
    });

    test('Record：循环实例含未完成原因往返一致', () {
      final record = makeRecord(
        cycleId: 'cycle_1',
        cycleDayIndex: 3,
        status: TaskStatus.missed,
        reason: '加班，没时间',
        reasonUpdatedAt: DateTime(2026, 9, 12, 22, 30),
        rescheduledFrom: DateTime(2026, 9, 10),
      );

      final restored = Record.fromJson(reencode(record.toJson()));
      expect(restored, record);
      expect(restored.isCycleInstance, isTrue);
      expect(restored.cycleDayIndex, 3);
      expect(restored.reason, '加班，没时间');
      expect(dayKey(restored.rescheduledFrom!), '2026-09-10');
    });

    test('Record：普通任务记录往返一致', () {
      final record = makeRecord(
        status: TaskStatus.completed,
        completedAt: DateTime(2026, 9, 12, 21, 0),
      );
      final restored = Record.fromJson(reencode(record.toJson()));
      expect(restored, record);
      expect(restored.isCycleInstance, isFalse);
      expect(restored.cycleDayIndex, isNull);
    });

    test('Record：仅本次的标题覆盖往返一致', () {
      final record = makeRecord(
        cycleId: 'cycle_1',
        cycleDayIndex: 1,
      ).withTitleOverride('  今天改成慢跑  ');

      expect(record.titleOverride, '今天改成慢跑', reason: '写入时修剪空白');

      final restored = Record.fromJson(reencode(record.toJson()));
      expect(restored, record);
      expect(restored.titleOverride, '今天改成慢跑');
      expect(restored.isCycleInstance, isTrue);
    });

    test('Record：缺 titleOverride 字段的老数据读为 null', () {
      final restored = Record.fromJson(const {
        'id': 'r1',
        'taskId': 't1',
        'date': '2026-09-12',
      }, now: kBaseNow);

      expect(restored.titleOverride, isNull, reason: '向后兼容');
    });

    test('Record：withTitleOverride 空串按清空处理', () {
      final record = makeRecord().withTitleOverride('改了');
      expect(record.withTitleOverride('   ').titleOverride, isNull);
      expect(record.withTitleOverride(null).titleOverride, isNull);
    });

    test('AppSettings：往返一致', () {
      final settings = makeSettings(
        remindersEnabled: false,
        defaultRemindMinuteOfDay: 7 * 60 + 45,
        lockEnabled: true,
        lockPinHash: 'abc123',
        biometricEnabled: true,
        themeSeed: 42,
        lastBackupAt: DateTime(2026, 9, 11, 20, 0),
      );
      final restored = AppSettings.fromJson(reencode(settings.toJson()));
      expect(restored, settings);
      expect(restored.defaultRemindLabel, '07:45');
      expect(restored.isLockActive, isTrue);
    });

    test('AppSettings：默认提醒时段支持「一天两次」', () {
      final settings = makeSettings(
        defaultRemindMinutesOfDay: [10 * 60 + 30, 15 * 60 + 30],
      );
      final restored = AppSettings.fromJson(reencode(settings.toJson()));
      expect(restored, settings);
      expect(restored.defaultRemindMinutesOfDay, [630, 930]);
      expect(restored.defaultRemindLabel, '10:30、15:30');
      expect(
        restored.defaultRemindMinuteOfDay,
        630,
        reason: '单值 getter 取最早的时段',
      );
    });

    test('AppSettings：老备份的单个 defaultRemindMinuteOfDay 能升级', () {
      final restored = AppSettings.fromJson({'defaultRemindMinuteOfDay': 420});
      expect(restored.defaultRemindMinutesOfDay, [420]);
      expect(restored.defaultRemindLabel, '07:00');
    });

    test('AppData：往返一致', () {
      final data = makeAppData(
        tasks: [makeTask(), makeTask(id: 'task_2', title: '买牛奶')],
        cycles: [makeCycle()],
        records: [makeRecord(), makeRecord(id: 'record_2', taskId: 'task_2')],
      );
      final restored = AppData.fromJson(reencode(data.toJson()));
      expect(restored, data);
      expect(restored.taskCount, 2);
      expect(restored.recordCount, 2);
    });

    test('AppBackup：整体往返一致且顶层结构符合 PRD', () {
      final backup = makeBackup();
      final json = reencode(backup.toJson());

      expect(json.keys, containsAll(<String>[
        'version',
        'exportedAt',
        'tasks',
        'cycles',
        'records',
        'settings',
      ]));
      expect(json['version'], 1);
      expect(json['tasks'], isA<List<dynamic>>());

      final restored = AppBackup.fromJson(json);
      expect(restored, backup);
      expect(restored.version, AppBackup.currentVersion);
    });
  });

  group('1.9 容错：脏数据不抛异常', () {
    test('Task：字段缺失时用默认值', () {
      final task = Task.fromJson(const {}, now: kBaseNow);
      expect(task.id, '');
      expect(task.title, '');
      expect(task.note, '');
      expect(task.dateType, TaskDateType.none);
      expect(task.date, isNull);
      expect(task.remindAt, isNull);
      expect(task.status, TaskStatus.pending);
      expect(task.createdAt, kBaseNow);
      expect(task.updatedAt, kBaseNow);
    });

    test('Task：字段类型错误时不抛异常', () {
      final task = Task.fromJson(const {
        'id': 123,
        'title': true,
        'dateType': 5,
        'date': 20260912,
        'remindAt': [],
        'status': {'x': 1},
        'createdAt': 'not-a-date',
      }, now: kBaseNow);

      expect(task.id, '123');
      expect(task.title, 'true');
      expect(task.dateType, TaskDateType.none, reason: '非字符串走默认值');
      expect(task.date, isNull);
      expect(task.remindAt, isNull);
      expect(task.status, TaskStatus.pending);
      expect(task.createdAt, kBaseNow, reason: '解析失败回落 now');
    });

    test('Task：缺 dateType 但带 date 时推断为 custom', () {
      final task = Task.fromJson(const {'date': '2026-09-20'}, now: kBaseNow);
      expect(task.dateType, TaskDateType.custom);
      expect(dayKey(task.date!), '2026-09-20');
    });

    test('Record：日期非法时回落 now，原因字段保留原文', () {
      final record = Record.fromJson(const {
        'id': 'r1',
        'taskId': 't1',
        'date': '2026-02-30',
        'reason': '天气原因',
      }, now: kBaseNow);

      expect(dayKey(record.date), dayKey(kBaseNow));
      expect(record.reason, '天气原因');
      expect(record.reasonUpdatedAt, isNull);
    });

    test('未知枚举值一律回落默认值', () {
      expect(
        Task.fromJson(const {'status': 'done'}, now: kBaseNow).status,
        TaskStatus.pending,
      );
      expect(
        Cycle.fromJson(const {'status': 'archived'}, now: kBaseNow).status,
        CycleStatus.active,
      );
      expect(
        Cycle.fromJson(const {'endType': 'forever'}, now: kBaseNow).endType,
        CycleEndType.never,
      );
    });

    test('AppSettings：缺字段时保留默认值而非清零', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings, const AppSettings());
      expect(settings.remindersEnabled, isTrue);
      expect(settings.cycleRemindersEnabled, isTrue);
      expect(settings.defaultRemindMinuteOfDay, AppSettings.defaultRemindMinute);
      expect(settings.lockEnabled, isFalse);
    });

    test('AppSettings：越界提醒时间被夹住', () {
      final tooBig = AppSettings.fromJson(const {
        'defaultRemindMinuteOfDay': 9999,
      });
      expect(tooBig.defaultRemindMinuteOfDay, 1439);

      final negative =
          AppSettings.fromJson(const {'defaultRemindMinuteOfDay': -5});
      expect(negative.defaultRemindMinuteOfDay, 0);
    });

    test('AppData：集合字段类型错误时退化为空列表', () {
      final data = AppData.fromJson(const {
        'tasks': 'nope',
        'cycles': 42,
        'records': null,
        'settings': [],
      });
      expect(data.tasks, isEmpty);
      expect(data.cycles, isEmpty);
      expect(data.records, isEmpty);
      expect(data.settings, const AppSettings());
    });

    test('AppData：列表中的坏元素被跳过，好的仍保留', () {
      final data = AppData.fromJson({
        'tasks': [
          {'id': 'task_ok', 'title': '有效'},
          'garbage',
          null,
          42,
        ],
      }, now: kBaseNow);

      expect(data.tasks.length, 1);
      expect(data.tasks.single.id, 'task_ok');
    });
  });

  group('Cycle 结构不变量修复', () {
    test('days 少于 periodDays 时补空白天', () {
      final cycle = Cycle.fromJson(const {
        'id': 'c1',
        'name': '5 天计划',
        'periodDays': 5,
        'startDate': '2026-09-01',
        'days': [
          {'dayIndex': 1, 'templates': []},
        ],
      }, now: kBaseNow);

      expect(cycle.days.length, 5);
      expect(cycle.dayAt(5).isEmpty, isTrue);
    });

    test('days 多于 periodDays 时截断', () {
      final cycle = Cycle.fromJson({
        'id': 'c2',
        'periodDays': 3,
        'startDate': '2026-09-01',
        'days': [
          for (var i = 1; i <= 6; i++) {'dayIndex': i, 'templates': []},
        ],
      }, now: kBaseNow);

      expect(cycle.days.length, 3);
    });

    test('越界与重复 dayIndex 被修复', () {
      final cycle = Cycle.fromJson({
        'id': 'c3',
        'periodDays': 3,
        'startDate': '2026-09-01',
        'days': [
          {'dayIndex': 0, 'isRestDay': true},
          {'dayIndex': 9, 'isRestDay': true},
          {
            'dayIndex': 2,
            'templates': [
              {'id': 'a', 'title': '旧'},
            ],
          },
          {
            'dayIndex': 2,
            'templates': [
              {'id': 'b', 'title': '新'},
            ],
          },
        ],
      }, now: kBaseNow);

      expect(cycle.days.length, 3);
      expect(cycle.dayAt(1).isRestDay, isFalse);
      expect(cycle.dayAt(2).taskCount, 1);
      expect(cycle.dayAt(2).templates.single.id, 'b', reason: '后者覆盖前者');
    });

    test('periodDays 非法值被夹到合法区间', () {
      expect(
        Cycle.fromJson(const {'periodDays': 0}, now: kBaseNow).periodDays,
        1,
      );
      expect(
        Cycle.fromJson(const {'periodDays': -7}, now: kBaseNow).periodDays,
        1,
      );
      expect(
        Cycle.fromJson(const {'periodDays': 9999}, now: kBaseNow).periodDays,
        365,
      );
      expect(
        Cycle.fromJson(const {'periodDays': 'abc'}, now: kBaseNow).periodDays,
        1,
      );
    });

    test('模板按 order 排序载入，顺序稳定', () {
      final day = CycleDay.fromJson({
        'dayIndex': 1,
        'templates': [
          {'id': 'c', 'title': '第三', 'order': 2},
          {'id': 'a', 'title': '第一', 'order': 0},
          {'id': 'b', 'title': '第二', 'order': 1},
        ],
      }, now: kBaseNow);

      expect(day.templates.map((e) => e.id).toList(), ['a', 'b', 'c']);
    });
  });

  group('AppBackup 版本处理', () {
    test('缺少 version 时按当前版本处理', () {
      final backup = AppBackup.fromJson({
        'tasks': const [],
        'cycles': const [],
        'records': const [],
        'settings': const {},
      }, now: kBaseNow);

      expect(backup.version, AppBackup.currentVersion);
    });

    test('version 高于当前版本时抛出可读异常', () {
      expect(
        () => AppBackup.fromJson(const {'version': 99}, now: kBaseNow),
        throwsA(isA<BackupVersionException>()),
      );

      try {
        AppBackup.fromJson(const {'version': 99}, now: kBaseNow);
        fail('应当抛出异常');
      } on BackupVersionException catch (error) {
        expect(error.toString(), contains('v99'));
        expect(error.toString(), contains('v1'));
      }
    });

    test('version 低于当前版本时按旧数据宽松载入', () {
      final backup = AppBackup.fromJson(const {
        'version': 0,
        'tasks': [
          {'id': 'task_old', 'title': '老任务'},
        ],
      }, now: kBaseNow);

      expect(backup.version, 0);
      expect(backup.data.tasks.single.id, 'task_old');
      expect(backup.data.settings, const AppSettings());
    });

    test('summary 便于导入预览展示', () {
      final backup = makeBackup(
        data: makeAppData(
          tasks: [makeTask(), makeTask(id: 'task_2')],
          cycles: [makeCycle()],
          records: [makeRecord()],
        ),
      );
      expect(backup.summary, '2 个任务、1 个计划、1 条记录');
    });
  });

  group('模型行为（供后续命令层复用）', () {
    test('Task.materializeDate 把相对日期固化为具体日期', () {
      final todayTask = makeTask(dateType: TaskDateType.today, date: null);
      final materialized = todayTask.materializeDate(kToday);

      expect(materialized.dateType, TaskDateType.custom);
      expect(dayKey(materialized.date!), dayKey(kToday));
      expect(materialized.resolvedDayKey(kToday), dayKey(kToday));

      // 无日期任务不受影响
      final noDate = makeTask(hasDate: false);
      expect(noDate.materializeDate(kToday), noDate);
    });

    test('Task.resolvedDate 支持今天 / 明天 / 自定义 / 无日期', () {
      expect(
        dayKey(makeTask(dateType: TaskDateType.today, date: null)
            .resolvedDate(kToday)!),
        dayKey(kToday),
      );
      expect(
        dayKey(makeTask(dateType: TaskDateType.tomorrow, date: null)
            .resolvedDate(kToday)!),
        dayKey(addDays(kToday, 1)),
      );
      expect(
        makeTask(hasDate: false).resolvedDate(kToday),
        isNull,
      );
    });

    test('Record.withStatus 维护 completedAt', () {
      final pending = makeRecord();
      final done = pending.withStatus(
        TaskStatus.completed,
        at: DateTime(2026, 9, 12, 21, 30),
      );
      expect(done.status, TaskStatus.completed);
      expect(done.completedAt, DateTime(2026, 9, 12, 21, 30));

      final back = done.withStatus(TaskStatus.pending);
      expect(back.status, TaskStatus.pending);
      expect(back.completedAt, isNull, reason: '取消完成要清掉完成时间');
    });

    test('Record.withReason 修剪空白，空白视为清空', () {
      final record = makeRecord();
      final written = record.withReason(
        '  加班，没时间  ',
        at: DateTime(2026, 9, 12, 22, 0),
      );
      expect(written.reason, '加班，没时间');
      expect(written.reasonUpdatedAt, DateTime(2026, 9, 12, 22, 0));
      expect(written.hasReason, isTrue);

      final cleared = written.withReason('   ');
      expect(cleared.reason, isNull);
      expect(cleared.reasonUpdatedAt, isNull);
      expect(cleared.hasReason, isFalse);
    });

    test('Cycle.dayAt 越界返回空白天而不抛异常', () {
      final cycle = makeCycle(periodDays: 3);
      expect(cycle.dayAt(0).isEmpty, isTrue);
      expect(cycle.dayAt(99).isEmpty, isTrue);
      expect(cycle.dayAt(2).dayIndex, 2);
    });

    test('Cycle.withDay 可扩容周期', () {
      final cycle = makeCycle(periodDays: 3);
      final expanded = cycle.withDay(
        makeCycleDay(
          dayIndex: 5,
          templates: [makeCycleTemplate()],
        ),
      );

      expect(expanded.periodDays, 5);
      expect(expanded.days.length, 5);
      expect(expanded.dayAt(5).taskCount, 1);
      expect(expanded.dayAt(4).isEmpty, isTrue);
    });

    test('CycleDay.addTemplate / removeTemplate 维护 order 连续', () {
      var day = CycleDay.empty(1);
      day = day.addTemplate(makeCycleTemplate(id: 'a', order: 99));
      day = day.addTemplate(makeCycleTemplate(id: 'b', order: 99));

      expect(day.templates.map((e) => e.order).toList(), [0, 1]);

      day = day.removeTemplate('a');
      expect(day.templates.length, 1);
      expect(day.templates.single.id, 'b');
      expect(day.templates.single.order, 0, reason: '删除后 order 重排');
    });

    test('CycleDay.moveTemplate 调整顺序', () {
      final day = CycleDay(
        dayIndex: 1,
        templates: [
          makeCycleTemplate(id: 'a', order: 0),
          makeCycleTemplate(id: 'b', order: 1),
          makeCycleTemplate(id: 'c', order: 2),
        ],
      );

      final moved = day.moveTemplate(0, 2);
      expect(moved.templates.map((e) => e.id).toList(), ['b', 'c', 'a']);
      expect(moved.templates.map((e) => e.order).toList(), [0, 1, 2]);
    });

    test('AppData 查询按 id 与日期工作', () {
      final data = makeAppData(
        tasks: [makeTask(), makeTask(id: 'task_2')],
        records: [
          makeRecord(id: 'record_1', taskId: 'task_1'),
          makeRecord(
            id: 'record_2',
            taskId: 'task_2',
            date: DateTime(2026, 9, 10),
          ),
        ],
      );

      expect(data.taskById('task_1')!.id, 'task_1');
      expect(data.taskById('nope'), isNull);
      expect(data.recordsOn(kToday).length, 1);
      expect(data.recordsForTask('task_1').length, 1);
      expect(data.recordById('record_2')!.taskId, 'task_2');
    });

    test('AppData.findInstance 区分普通与循环实例', () {
      final data = makeAppData(
        records: [
          makeRecord(id: 'r_plain', taskId: 'task_1'),
          makeRecord(id: 'r_cycle', taskId: 'ctask_1', cycleId: 'cycle_1'),
        ],
      );

      expect(
        data.findInstance(taskId: 'task_1', day: kToday)!.id,
        'r_plain',
      );
      expect(
        data.findInstance(taskId: 'ctask_1', day: kToday, cycleId: 'cycle_1')!
            .id,
        'r_cycle',
      );
      expect(
        data.findInstance(taskId: 'ctask_1', day: kToday),
        isNull,
        reason: 'cycleId 不同不应匹配',
      );
    });
  });
}
