import 'dart:async';

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/app_shell.dart';
import 'package:loop_island/app/bootstrap.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/backup.dart';

import '../support/factories.dart';

void main() {
  group('openLocalStore', () {
    test('成功时返回存储实例，不返回错误', () async {
      final fake = InMemoryLocalStore(AppBackup.of(makeAppData()));
      final result = await openLocalStore(opener: () async => fake);

      expect(result.store, same(fake));
      expect(result.error, isNull);
    });

    test('失败时返回 null 且带上原始错误，而不是抛异常', () async {
      final result = await openLocalStore(
        opener: () async => throw const _FakeStorageError('磁盘只读'),
      );

      expect(result.store, isNull);
      expect(result.error, isA<_FakeStorageError>());
      expect(result.error.toString(), contains('磁盘只读'));
    });

    test('平台通道缺失（Web 无 path_provider）也走失败分支而非崩溃', () async {
      final result = await openLocalStore(
        opener: () async => throw UnimplementedError('MissingPluginException'),
      );

      expect(result.store, isNull);
      expect(result.error, isA<UnimplementedError>());
    });
  });

  group('StorageBootstrapApp', () {
    testWidgets('存储打开成功时进入四 Tab 外壳', (tester) async {
      final store = InMemoryLocalStore(AppBackup.of(makeAppData()));

      await tester.pumpWidget(
        StorageBootstrapApp(opener: () async => store),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text(TabLabels.today), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('注入的存储确实被接到 localStoreProvider 上', (tester) async {
      final store = InMemoryLocalStore(AppBackup.of(makeAppData()));

      await tester.pumpWidget(
        StorageBootstrapApp(opener: () async => store),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(AppShell));
      final container = ProviderScope.containerOf(context);
      expect(container.read(localStoreProvider), same(store));
    });

    testWidgets('打开失败时显示可读的错误页，而不是白屏', (tester) async {
      await tester.pumpWidget(
        StorageBootstrapApp(
          opener: () async => throw const _FakeStorageError('磁盘只读'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(BootStrings.storageErrorTitle), findsOneWidget);
      expect(find.text(BootStrings.storageRetry), findsOneWidget);
      expect(find.textContaining('磁盘只读'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('失败后点重试可以恢复正常启动', (tester) async {
      var attempt = 0;
      final store = InMemoryLocalStore(AppBackup.of(makeAppData()));

      await tester.pumpWidget(
        StorageBootstrapApp(
          opener: () async {
            attempt++;
            if (attempt == 1) {
              throw const _FakeStorageError('第一次失败');
            }
            return store;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(BootStrings.storageErrorTitle), findsOneWidget);

      await tester.tap(find.text(BootStrings.storageRetry));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text(BootStrings.storageErrorTitle), findsNothing);
    });

    testWidgets('加载中显示启动页（含应用名）', (tester) async {
      final completer = Completer<InMemoryLocalStore>();

      await tester.pumpWidget(
        StorageBootstrapApp(opener: () => completer.future),
      );
      await tester.pump();

      expect(find.text(AppInfo.appName), findsOneWidget);
      expect(find.byType(AnimalLoading), findsOneWidget);

      completer.complete(InMemoryLocalStore(AppBackup.of(AppData.empty)));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('失败页也带上了线上同一套 AnimalTheme', (tester) async {
      await tester.pumpWidget(
        StorageBootstrapApp(
          opener: () async => throw const _FakeStorageError('坏了'),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.text(BootStrings.storageErrorTitle));
      expect(Theme.of(context).extension<AnimalThemeData>(), isNotNull);
    });
  });
}

/// 测试用的假异常，带可读消息便于断言渲染内容。
class _FakeStorageError implements Exception {
  const _FakeStorageError(this.message);

  final String message;

  @override
  String toString() => 'FakeStorageError: $message';
}
