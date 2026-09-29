import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/data/app_repository.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

void main() {
  group('AppRepository（1.13）', () {
    late InMemoryLocalStore store;
    late AppRepository repository;

    setUp(() {
      store = InMemoryLocalStore();
      repository = AppRepository(store);
    });

    tearDown(() async {
      await repository.dispose();
    });

    test('init 从存储载入数据', () async {
      store = InMemoryLocalStore(
        AppBackup.of(
          makeAppData(tasks: [makeTask(title: '从磁盘来')]),
        ),
      );
      repository = AppRepository(store);

      final data = await repository.init();
      expect(data.tasks.single.title, '从磁盘来');
      expect(repository.isLoaded, isTrue);
    });

    test('init 幂等：重复调用只 load 一次', () async {
      await repository.init();
      await repository.init();
      await repository.init();
      expect(store.loadCount, 1);
    });

    test('init 不广播（否则 Riverpod 会在 build 阶段更新 state）', () async {
      final events = <AppData>[];
      final subscription = repository.changes.listen(events.add);

      await repository.init();
      await pumpEventQueue();

      expect(events, isEmpty);
      await subscription.cancel();
    });

    test('commit 同时更新内存、落盘并广播', () async {
      await repository.init();

      final events = <AppData>[];
      final subscription = repository.changes.listen(events.add);

      final next = makeAppData(tasks: [makeTask(title: '新任务')]);
      await repository.commit(next);
      await pumpEventQueue();

      expect(repository.data, next);
      expect(store.saveCount, 1);
      expect(store.snapshot!.data, next, reason: '落盘内容必须与内存一致');
      expect(events, hasLength(1));
      expect(events.single.tasks.single.title, '新任务');

      await subscription.cancel();
    });

    test('commit 相同数据时跳过：不落盘也不广播', () async {
      final data = makeAppData();
      await repository.init();
      await repository.commit(data);

      final events = <AppData>[];
      final subscription = repository.changes.listen(events.add);

      await repository.commit(data);
      await pumpEventQueue();

      expect(store.saveCount, 1, reason: '第二次不应再写磁盘');
      expect(events, isEmpty);
      await subscription.cancel();
    });

    test('落盘失败时回滚内存并抛出异常', () async {
      await repository.init();
      final before = repository.data;
      store.failSave = true;

      final events = <AppData>[];
      final subscription = repository.changes.listen(events.add);

      await expectLater(
        repository.commit(makeAppData(tasks: [makeTask(title: '存不下去')])),
        throwsA(isA<StateError>()),
      );
      await pumpEventQueue();

      expect(repository.data, before, reason: '失败后不能停在未落盘的状态');
      expect(events, hasLength(2), reason: '先乐观广播，再广播回滚');
      expect(events.last, before);
      await subscription.cancel();
    });

    test('新建仓库能读到上一次提交的数据（模拟重启）', () async {
      await repository.init();
      await repository.commit(
        makeAppData(tasks: [makeTask(title: '重启后还在')]),
      );

      final reopened = AppRepository(store);
      final data = await reopened.init();
      expect(data.tasks.single.title, '重启后还在');
      await reopened.dispose();
    });

    test('clearBusinessData 清空任务与记录但保留设置', () async {
      await repository.init();
      await repository.commit(
        makeAppData(
          settings: makeSettings(
            lockEnabled: true,
            lockPinHash: 'hash',
            remindersEnabled: false,
          ),
        ),
      );

      await repository.clearBusinessData();

      expect(repository.data.tasks, isEmpty);
      expect(repository.data.cycles, isEmpty);
      expect(repository.data.records, isEmpty);
      expect(repository.data.settings.lockPinHash, 'hash', reason: '应用锁配置要留下');
      expect(repository.data.settings.remindersEnabled, isFalse);
    });

    test('dispose 之后不能再 commit', () async {
      await repository.init();
      await repository.dispose();

      await expectLater(
        repository.commit(makeAppData()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('providers（1.14）', () {
    test('未覆写 localStoreProvider 时给出可读错误', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(localStoreProvider),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('localStoreProvider 未初始化'),
          ),
        ),
      );
    });

    test('覆写后可注入内存存储，appDataProvider 载入数据', () async {
      final store = InMemoryLocalStore(
        AppBackup.of(makeAppData(tasks: [makeTask(title: '注入来的')])),
      );
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final data = await container.read(appDataProvider.future);
      expect(data.tasks.single.title, '注入来的');
      expect(store.loadCount, 1);
    });

    test('通过 notifier commit 后 appDataProvider 推出新值', () async {
      final store = InMemoryLocalStore();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(appDataProvider.future);

      await container.read(appDataProvider.notifier).commit(
            makeAppData(
              tasks: [makeTask(title: '提交后可见')],
              cycles: const [],
              records: const [],
            ),
          );
      await pumpEventQueue();

      final current = container.read(appDataProvider).value!;
      expect(current.tasks.single.title, '提交后可见');
      expect(store.snapshot!.data, current);
    });

    test('todayProvider 可被覆写成固定日期，todayKeyProvider 跟随', () {
      final container = ProviderContainer(
        overrides: [
          todayProvider.overrideWithValue(DateTime(2026, 9, 12, 23, 30)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(todayKeyProvider), '2026-09-12');
    });

    test('未覆写时 todayProvider 取本地今天（时间归零）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final today = container.read(todayProvider);
      final now = DateTime.now();
      expect(today.year, now.year);
      expect(today.month, now.month);
      expect(today.day, now.day);
      expect(today.hour, 0);
      expect(today.minute, 0);
    });

    test('appRepositoryProvider 关闭容器时释放仓库', () async {
      final store = InMemoryLocalStore();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );

      await container.read(appDataProvider.future);
      final repository = container.read(appRepositoryProvider);
      container.dispose();
      await pumpEventQueue();

      expect(
        () => repository.commit(AppData(settings: makeSettings())),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('InMemoryLocalStore 测试工具（1.12）', () {
    test('每次 load 返回独立副本，避免别名污染', () async {
      final store = InMemoryLocalStore(
        AppBackup.of(makeAppData(tasks: [makeTask(title: '原值')])),
      );

      final first = await store.load();
      final second = await store.load();

      expect(identical(first, second), isFalse);
      expect(identical(first.data, second.data), isFalse);
      expect(identical(first.data.tasks, second.data.tasks), isFalse);
      expect(first, second, reason: '内容仍然相等');
    });

    test('写入是深拷贝：外部持有的旧快照不会跟着变', () async {
      final original = AppBackup.of(
        makeAppData(tasks: [makeTask(title: '原值')]),
      );
      final store = InMemoryLocalStore(original);

      await store.save(
        AppBackup.of(
          makeAppData(tasks: [makeTask(title: '新值')]),
        ),
      );

      expect(original.data.tasks.single.title, '原值', reason: '快照不可变');
      expect((await store.load()).data.tasks.single.title, '新值');
    });

    test('saveError 可注入自定义异常', () async {
      final store = InMemoryLocalStore()
        ..failSave = true
        ..saveError = ArgumentError('磁盘满了');

      await expectLater(
        store.save(AppBackup.of(AppData.empty)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('corruptOnLoad 模拟损坏数据', () async {
      final store = InMemoryLocalStore(AppBackup.of(makeAppData()))
        ..corruptOnLoad = true;

      expect((await store.load()).data.isEmpty, isTrue);
    });

    test('计数可断言是否真的落盘', () async {
      final store = InMemoryLocalStore();
      await store.load();
      await store.save(AppBackup.of(makeAppData()));
      await store.clear();

      expect(store.loadCount, 1);
      expect(store.saveCount, 1);
      expect(store.clearCount, 1);
    });

    test('状态枚举在存储往返后保持不变', () async {
      final store = InMemoryLocalStore();
      await store.save(
        AppBackup.of(
          makeAppData(
            records: [
              makeRecord(id: 'r1', status: TaskStatus.missed, reason: '忘记'),
              makeRecord(id: 'r2', status: TaskStatus.skipped),
              makeRecord(id: 'r3', status: TaskStatus.completed),
            ],
          ),
        ),
      );

      final restored = await store.load();
      expect(
        restored.data.records.map((e) => e.status).toList(),
        [TaskStatus.missed, TaskStatus.skipped, TaskStatus.completed],
      );
    });
  });
}
