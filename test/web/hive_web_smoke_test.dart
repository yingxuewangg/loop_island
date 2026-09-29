@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:loop_island/data/hive_local_store.dart';
import 'package:loop_island/models/backup.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';

/// 浏览器专项冒烟测试。
///
/// 存在的理由：`Hive.initFlutter()` 在 Web 上会 `if (kIsWeb) return;`，
/// 不调用 `Hive.init(path)`，改走 IndexedDB。这条路径与移动端/桌面端完全不同，
/// 而 Chrome 是当前唯一可用的目视通道 —— 必须确认它真的能读写，
/// 而不是等到打开浏览器才发现停在「无法打开本地数据」页。
///
/// 只在浏览器跑：`flutter test --platform chrome test/web/hive_web_smoke_test.dart`
/// 默认的 `flutter test`（VM）会跳过本文件。
void main() {
  test('Hive 在浏览器上能打开存储并完成读写往返', () async {
    await Hive.initFlutter();

    final store = await HiveLocalStore.open(boxName: 'web_smoke_box');
    expect(await store.load(), isA<AppBackup>());

    final data = makeAppData(
      tasks: [makeTask(title: '浏览器里的任务')],
      records: [
        makeRecord(status: TaskStatus.missed, reason: '天气原因'),
      ],
    );
    await store.save(AppBackup.of(data, exportedAt: kBaseNow));

    final restored = await store.load();
    expect(restored.data, data, reason: 'IndexedDB 往返必须与原生一致');
    expect(restored.data.tasks.single.title, '浏览器里的任务');
    expect(restored.data.records.single.reason, '天气原因');

    await store.clear();
    expect((await store.load()).data.isEmpty, isTrue);

    await Hive.close();
  });

  test('损坏数据在浏览器上同样不抛异常', () async {
    await Hive.initFlutter();

    final box = await Hive.openBox<dynamic>('web_corrupt_box');
    await box.put(HiveLocalStore.snapshotKey, '{ 坏掉的 JSON');
    await box.flush();

    final store = HiveLocalStore.forTesting(box);
    expect((await store.load()).data.isEmpty, isTrue);

    await Hive.close();
  });
}
