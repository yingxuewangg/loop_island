import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_island/data/hive_local_store.dart';
import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 两个实现必须跑同一套契约测试，否则「内存测试通过、真机丢数据」会漏掉。
///
/// [reopen] 表示「重新打开同一份存储」（模拟重启应用）：
/// Hive 实现是重新 open 同一个目录下的同一个 box；
/// 内存实现没有真正的持久化，只能返回同一实例，这一点在测试名里注明。
void runLocalStoreContract({
  required String label,
  required Future<LocalStore> Function() create,
  required Future<LocalStore> Function(LocalStore current) reopen,
  required Future<void> Function(LocalStore store) dispose,
}) {
  group('LocalStore 契约：$label', () {
    late LocalStore store;

    setUp(() async {
      store = await create();
    });

    tearDown(() async {
      await dispose(store);
    });

    test('首次加载返回空数据而不是报错', () async {
      final backup = await store.load();
      expect(backup.data.isEmpty, isTrue);
      expect(backup.data.settings.remindersEnabled, isTrue, reason: '设置用默认值');
      expect(backup.version, AppBackup.currentVersion);
    });

    test('save 后 load 得到等价数据', () async {
      final original = makeAppData(
        tasks: [
          makeTask(),
          makeTask(id: 'task_2', title: '买牛奶', status: TaskStatus.completed),
        ],
        cycles: [
          makeCycle(
            periodDays: 3,
            endType: CycleEndType.untilDate,
            endDate: DateTime(2026, 12, 31),
          ),
        ],
        records: [
          makeRecord(status: TaskStatus.missed, reason: '加班，没时间'),
        ],
      );

      await store.save(AppBackup.of(original, exportedAt: kBaseNow));
      final restored = await store.load();

      expect(restored.data, original, reason: '往返后业务数据必须完全一致');
    });

    test('重复 save 是全量替换，不与旧数据混合', () async {
      await store.save(AppBackup.of(makeAppData()));
      await store.save(
        AppBackup.of(
          makeAppData(
            tasks: [makeTask(id: 'task_only', title: '只剩我')],
            cycles: const [],
            records: const [],
          ),
        ),
      );

      final restored = await store.load();
      expect(restored.data.tasks.length, 1);
      expect(restored.data.tasks.single.id, 'task_only');
      expect(restored.data.cycles, isEmpty);
      expect(restored.data.records, isEmpty);
    });

    test('clear 之后回到空数据', () async {
      await store.save(AppBackup.of(makeAppData()));
      await store.clear();

      final restored = await store.load();
      expect(restored.data.isEmpty, isTrue);
    });

    test('空数据也能正常保存（不是错误路径）', () async {
      await store.save(AppBackup.of(AppData.empty));
      final restored = await store.load();
      expect(restored.data.isEmpty, isTrue);
    });

    test('保存后重新打开仍能读到（模拟重启）', () async {
      await store.save(
        AppBackup.of(makeAppData(tasks: [makeTask(title: '重启后还要在')])),
      );

      final reopened = await reopen(store);
      final restored = await reopened.load();
      expect(restored.data.tasks.single.title, '重启后还要在');
    });
  });
}

void main() {
  // ------------------------------------------------------------ 内存实现
  runLocalStoreContract(
    label: 'InMemoryLocalStore',
    create: () async => InMemoryLocalStore(),
    // 内存实现没有真正的「重开」，返回同一实例即代表同一份「磁盘」
    reopen: (current) async => current,
    dispose: (store) async {},
  );

  // ------------------------------------------------------------ Hive 实现
  var contractCounter = 0;
  late Directory contractDir;
  late String contractBox;
  runLocalStoreContract(
    label: 'HiveLocalStore',
    create: () async {
      contractDir = await Directory.systemTemp.createTemp('loop_island_test_');
      // 每个用例用独立 box 名，避免 Hive 的全局 box 缓存互相串味
      contractBox = 'contract_${contractCounter++}';
      return HiveLocalStore.open(
        directory: contractDir.path,
        boxName: contractBox,
      );
    },
    reopen: (current) async {
      // 真正关闭后再打开同一个 box，等价于「杀掉应用再启动」
      await current.close();
      return HiveLocalStore.open(
        directory: contractDir.path,
        boxName: contractBox,
      );
    },
    dispose: (store) async {
      await store.close();
      await Hive.close();
    },
  );

  group('HiveLocalStore 专有行为', () {
    late Directory dir;
    late String boxName;
    late HiveLocalStore store;
    var counter = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('loop_island_hive_');
      boxName = 'hive_specific_${counter++}';
      store = await HiveLocalStore.open(
        directory: dir.path,
        boxName: boxName,
      );
    });

    tearDown(() async {
      await Hive.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('快照就是备份格式本身，导出可直接复用', () async {
      await store.save(AppBackup.of(makeAppData(), exportedAt: kBaseNow));

      final raw = store.rawSnapshot!;
      expect(raw, contains('"version":1'));
      expect(raw, contains('"tasks"'));
      expect(raw, contains('"cycles"'));
      expect(raw, contains('"records"'));
      expect(raw, contains('"settings"'));
      expect(raw, contains('"exportedAt"'));
    });

    test('无数据时 rawSnapshot 为 null', () {
      expect(store.rawSnapshot, isNull);
    });

    test('数据损坏时返回空数据而不是抛异常，并把原文挪到 corrupt_ 键下', () async {
      final box = await Hive.openBox<dynamic>(boxName);
      await box.put(HiveLocalStore.snapshotKey, '{ 这不是合法 JSON');
      await box.flush();

      final backup = await store.load();
      expect(backup.data.isEmpty, isTrue, reason: '损坏也必须能启动，否则用户无路可走');

      final preserved = box
          .toMap()
          .keys
          .map((key) => key.toString())
          .where((key) => key.startsWith(HiveLocalStore.corruptKeyPrefix))
          .toList();
      expect(preserved, hasLength(1), reason: '损坏原文要留一份，便于手工恢复');
      expect(box.get(preserved.single), '{ 这不是合法 JSON');
      expect(box.get(HiveLocalStore.snapshotKey), isNull, reason: '坏数据不再占着主键');
    });

    test('版本高于当前时抛 BackupVersionException，不静默清空', () async {
      final box = await Hive.openBox<dynamic>(boxName);
      await box.put(
        HiveLocalStore.snapshotKey,
        '{"version":99,"exportedAt":"2026-09-12T02:00:00.000Z",'
            '"tasks":[],"cycles":[],"records":[],"settings":{}}',
      );
      await box.flush();

      await expectLater(store.load(), throwsA(isA<BackupVersionException>()));
      expect(
        box.get(HiveLocalStore.snapshotKey),
        isNotNull,
        reason: '高版本数据不能被挪走或删除',
      );
    });

    test('重新 open 同一 box 幂等，不会丢数据', () async {
      await store.save(AppBackup.of(makeAppData()));
      final again = await HiveLocalStore.open(
        directory: dir.path,
        boxName: boxName,
      );
      expect((await again.load()).data.tasks.length, 1);
    });
  });
}
