import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/backup_codec.dart';
import 'package:loop_island/core/backup_merge.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/settings.dart';

import '../support/factories.dart';

/// 备份编解码与合并验收（任务 7.1~7.4 / 7.8）。
void main() {
  final now = DateTime(2026, 9, 12, 10, 0);

  AppData richData() => AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '写周报'),
          makeTask(
            id: 'task_2',
            title: '买牛奶',
            status: TaskStatus.completed,
            completedAt: now,
          ),
        ]),
        cycles: List.unmodifiable([
          makeCycle(id: 'cycle_1', name: '8 天跑步训练', periodDays: 8),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            taskId: 'task_1',
            date: kToday,
            status: TaskStatus.missed,
            reason: '加班，没时间',
            reasonUpdatedAt: now,
          ),
        ]),
        settings: makeSettings(
          remindersEnabled: false,
          lockEnabled: true,
          lockPinHash: 'hash',
        ),
      );

  group('7.1 encodeBackup', () {
    test('输出符合 PRD §八.6 的顶层结构', () {
      final raw = encodeBackup(richData(), exportedAt: now);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      expect(
        json.keys.toSet(),
        {'version', 'exportedAt', 'tasks', 'cycles', 'records', 'settings'},
      );
      expect(json['version'], AppBackup.currentVersion);
      expect(json['tasks'], hasLength(2));
      expect(json['cycles'], hasLength(1));
      expect(json['records'], hasLength(1));
    });

    test('未完成原因随备份一起导出', () {
      final raw = encodeBackup(richData(), exportedAt: now);
      expect(raw, contains('加班，没时间'));
    });

    test('导出时间可注入（便于测试与展示）', () {
      final raw = encodeBackup(richData(), exportedAt: now);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        DateTime.parse(json['exportedAt'] as String).isAtSameMomentAs(now),
        isTrue,
      );
    });

    test('pretty 输出可读，compact 输出更短', () {
      final pretty = encodeBackup(richData(), exportedAt: now);
      final compact =
          encodeBackup(richData(), exportedAt: now, pretty: false);

      expect(pretty, contains('\n'));
      expect(compact, isNot(contains('\n')));
      expect(compact.length, lessThan(pretty.length));
    });

    test('空数据也能导出（不是错误路径）', () {
      final raw = encodeBackup(const AppData(), exportedAt: now);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['tasks'], isEmpty);
      expect(json['settings'], isNotEmpty);
    });
  });

  group('7.2 decodeBackup', () {
    test('往返等价', () {
      final data = richData();
      final result = decodeBackup(encodeBackup(data, exportedAt: now));

      expect(result.isSuccess, isTrue);
      expect(result.backup!.data, data, reason: '往返后业务数据必须完全一致');
    });

    test('空内容报 emptyInput', () {
      expect(decodeBackup('').error, BackupError.emptyInput);
      expect(decodeBackup('   ').error, BackupError.emptyInput);
    });

    test('非法 JSON 报 invalidJson', () {
      final result = decodeBackup('{ 这不是 JSON');
      expect(result.error, BackupError.invalidJson);
      expect(result.detail, isNotNull);
      expect(result.isFailure, isTrue);
    });

    test('顶层不是对象报 notAnObject', () {
      expect(decodeBackup('[1,2,3]').error, BackupError.notAnObject);
      expect(decodeBackup('"abc"').error, BackupError.notAnObject);
      expect(decodeBackup('123').error, BackupError.notAnObject);
    });

    test('版本过高报 unsupportedVersion 并带上版本号', () {
      final result = decodeBackup(
        '{"version":99,"tasks":[],"cycles":[],"records":[],"settings":{}}',
      );
      expect(result.error, BackupError.unsupportedVersion);
      expect(result.detail, contains('99'));
    });

    test('缺 version 时按当前版本处理（兼容最早的手工备份）', () {
      final result = decodeBackup(
        '{"tasks":[{"id":"t1","title":"老任务"}]}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.backup!.version, AppBackup.currentVersion);
      expect(result.backup!.data.tasks.single.id, 't1');
      expect(result.backup!.data.settings, const AppSettings());
    });

    test('字段类型错误不整体失败，能救回多少算多少', () {
      final result = decodeBackup(
        '{"version":1,"tasks":[{"id":"t1"}, "garbage", 42],'
        '"cycles":"nope","records":null,"settings":[]}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.backup!.data.tasks, hasLength(1));
      expect(result.backup!.data.cycles, isEmpty);
      expect(result.backup!.data.records, isEmpty);
    });

    test('未知字段被忽略', () {
      final result = decodeBackup(
        '{"version":1,"futureField":123,"tasks":[],"cycles":[],'
        '"records":[],"settings":{}}',
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('7.3 mergeData', () {
    test('备份独有的条目会被新增', () {
      final local = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_local', title: '本地')]),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_backup', title: '备份')]),
      );

      final result = mergeData(local, incoming);
      expect(result.data.tasks.map((e) => e.id).toSet(),
          {'task_local', 'task_backup'});
      expect(result.stats.addedTasks, 1);
      expect(result.stats.updatedTasks, 0);
    });

    test('同 id 取更新时间较新的', () {
      final local = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_1',
            title: '本地标题',
            updatedAt: DateTime(2026, 9, 10),
          ),
        ]),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_1',
            title: '备份标题',
            updatedAt: DateTime(2026, 9, 11),
          ),
        ]),
      );

      final result = mergeData(local, incoming);
      expect(result.data.tasks.single.title, '备份标题');
      expect(result.stats.updatedTasks, 1);
    });

    test('本地更新时不覆盖（保护用户刚做的事）', () {
      final local = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_1',
            title: '本地较新',
            updatedAt: DateTime(2026, 9, 12),
          ),
        ]),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([
          makeTask(
            id: 'task_1',
            title: '备份较旧',
            updatedAt: DateTime(2026, 9, 1),
          ),
        ]),
      );

      final result = mergeData(local, incoming);
      expect(result.data.tasks.single.title, '本地较新');
      expect(result.stats.updatedTasks, 0);
      expect(result.stats.addedTasks, 0);
    });

    test('时间相同时保留本地，避免反复导入来回抖动', () {
      final same = DateTime(2026, 9, 12);
      final local = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '本地', updatedAt: same),
        ]),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '备份', updatedAt: same),
        ]),
      );

      expect(mergeData(local, incoming).data.tasks.single.title, '本地');
      expect(mergeData(local, incoming).stats.updated, 0);
    });

    test('计划与记录同样按时间取新', () {
      final local = AppData(
        cycles: List.unmodifiable([
          makeCycle(id: 'c1', name: '本地计划',
              updatedAt: DateTime(2026, 9, 1)),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            status: TaskStatus.pending,
            updatedAt: DateTime(2026, 9, 1),
          ),
        ]),
      );
      final incoming = AppData(
        cycles: List.unmodifiable([
          makeCycle(id: 'c1', name: '备份计划',
              updatedAt: DateTime(2026, 9, 5)),
        ]),
        records: List.unmodifiable([
          makeRecord(
            id: 'r1',
            status: TaskStatus.completed,
            completedAt: DateTime(2026, 9, 5),
            updatedAt: DateTime(2026, 9, 5),
          ),
        ]),
      );

      final result = mergeData(local, incoming);
      expect(result.data.cycles.single.name, '备份计划');
      expect(result.data.records.single.status, TaskStatus.completed);
      expect(result.stats.updatedCycles, 1);
      expect(result.stats.updatedRecords, 1);
    });

    test('合并不会删除本地独有的数据', () {
      final local = AppData(
        tasks: List.unmodifiable([makeTask(id: 'keep_me')]),
      );
      final result = mergeData(local, const AppData());
      expect(result.data.tasks, hasLength(1));
      expect(result.stats.total, 0);
    });

    test('合并保留本地设置（应用锁不该被别人的备份改掉）', () {
      final local = AppData(
        settings: makeSettings(lockEnabled: true, lockPinHash: 'local_hash'),
      );
      final incoming = AppData(
        settings: makeSettings(lockEnabled: false),
      );

      final result = mergeData(local, incoming);
      expect(result.data.settings.lockPinHash, 'local_hash');
      expect(result.data.settings.lockEnabled, isTrue);
    });

    test('重复合并同一份备份是幂等的', () {
      final local = AppData(
        tasks: List.unmodifiable([makeTask(id: 'task_1')]),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_2', updatedAt: DateTime(2026, 9, 5)),
        ]),
      );

      final once = mergeData(local, incoming);
      final twice = mergeData(once.data, incoming);

      expect(twice.data, once.data);
      expect(twice.stats.total, 0);
    });
  });

  group('7.4 replaceData', () {
    test('完全替换，包括设置', () {
      final local = AppData(
        tasks: List.unmodifiable([makeTask(id: 'local_only')]),
        settings: makeSettings(lockPinHash: 'local_hash'),
      );
      final incoming = AppData(
        tasks: List.unmodifiable([makeTask(id: 'backup_only')]),
        settings: makeSettings(lockPinHash: 'backup_hash'),
      );

      final replaced = replaceData(incoming);
      expect(replaced.tasks.single.id, 'backup_only');
      expect(replaced.settings.lockPinHash, 'backup_hash');
      expect(replaced, incoming);
      expect(replaced, isNot(local));
    });

    test('用空备份覆盖会清空业务数据（导入 UI 必须就此二次确认）', () {
      final replaced = replaceData(const AppData());
      expect(replaced.isEmpty, isTrue);
    });
  });

  group('7.8 编解码 + 合并的组合场景', () {
    test('导出 → 合并回同一份数据 → 无变化', () {
      final data = richData();
      final result = decodeBackup(encodeBackup(data, exportedAt: now));
      final merged = mergeData(data, result.backup!.data);

      expect(merged.data, data);
      expect(merged.stats.total, 0);
    });

    test('导出 → 覆盖到空库 → 数据等价', () {
      final data = richData();
      final result = decodeBackup(encodeBackup(data, exportedAt: now));
      final replaced = replaceData(result.backup!.data);

      expect(replaced, data);
    });

    test('清空后从备份恢复，业务数据回来但本地设置保留', () {
      final data = richData();
      final backup = decodeBackup(encodeBackup(data, exportedAt: now))
          .backup!
          .data;

      // 用户清空业务数据（保留设置）
      final cleared = AppData(settings: data.settings);
      expect(cleared.isEmpty, isTrue);

      final merged = mergeData(cleared, backup);
      expect(merged.data.tasks, hasLength(2));
      expect(merged.data.cycles, hasLength(1));
      expect(merged.data.records, hasLength(1));
      expect(merged.data.settings, data.settings);
    });

    test('合并两份不同来源的数据，取各自较新的部分', () {
      final fromPhone = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '手机上改的',
              updatedAt: DateTime(2026, 9, 10)),
          makeTask(id: 'task_phone', updatedAt: DateTime(2026, 9, 9)),
        ]),
      );
      final fromDesktop = AppData(
        tasks: List.unmodifiable([
          makeTask(id: 'task_1', title: '电脑上改的',
              updatedAt: DateTime(2026, 9, 12)),
          makeTask(id: 'task_desktop', updatedAt: DateTime(2026, 9, 11)),
        ]),
      );

      final merged = mergeData(fromPhone, fromDesktop);
      expect(merged.data.tasks.map((e) => e.id).toSet(),
          {'task_1', 'task_phone', 'task_desktop'});
      expect(
        merged.data.tasks.firstWhere((e) => e.id == 'task_1').title,
        '电脑上改的',
      );
      expect(merged.stats.addedTasks, 1);
      expect(merged.stats.updatedTasks, 1);
    });
  });
}
