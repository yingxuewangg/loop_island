/// 应用启动引导：打开本地存储 → 注入 provider → 挂载应用。
///
/// 单独抽出来的原因有两个：
/// 1. `main()` 里塞 try/catch 会让「存储打不开」变成一个没人处理的静默分支，
///    而这是本应用**最需要被看见**的故障（本地优先、无服务器、无云端备份）。
/// 2. 打开存储依赖平台通道（path_provider），在测试里无法直接跑；
///    抽成可注入 [StoreOpener] 的纯函数后，成功/失败两条路径都能被测试覆盖。
library;

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/loop_island_app.dart';
import 'package:loop_island/data/hive_local_store.dart';
import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 打开存储的方式。默认用 Hive；测试注入假的。
typedef StoreOpener = Future<LocalStore> Function();

/// 打开本地存储。
///
/// 不抛异常：失败时返回 `store == null` 与具体 [error]，
/// 让上层决定怎么告诉用户，而不是让异常冒到 `runApp` 外面变成白屏。
Future<({LocalStore? store, Object? error})> openLocalStore({
  StoreOpener? opener,
}) async {
  final open = opener ?? HiveLocalStore.open;
  try {
    final store = await open();
    return (store: store, error: null);
  } catch (error) {
    return (store: null, error: error);
  }
}

/// 启动引导 Widget：负责加载态、失败态与成功后的应用装配。
///
/// [opener] 仅测试使用；线上走默认的 Hive 实现。
class StorageBootstrapApp extends StatefulWidget {
  const StorageBootstrapApp({super.key, this.opener});

  final StoreOpener? opener;

  @override
  State<StorageBootstrapApp> createState() => _StorageBootstrapAppState();
}

class _StorageBootstrapAppState extends State<StorageBootstrapApp> {
  LocalStore? _store;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await openLocalStore(opener: widget.opener);
    if (!mounted) {
      return;
    }

    setState(() {
      _store = result.store;
      _error = result.error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoopIslandApp(home: _BootSplashPage());
    }

    final store = _store;
    if (store == null) {
      return LoopIslandApp(
        home: StorageFailurePage(
          error: _error,
          onRetry: _boot,
        ),
      );
    }

    // 只有拿到可用的存储实现，才把 provider 覆写上 ——
    // localStoreProvider 故意没有默认实现，缺了它读取会直接报错，
    // 这样「忘了注入」不会退化成「悄悄写进了别的地方」。
    return ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const LoopIslandApp(),
    );
  }
}

/// 启动加载页。
class _BootSplashPage extends StatelessWidget {
  const _BootSplashPage();

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimalLoading(style: AnimalLoadingStyle.island),
            const SizedBox(height: 20),
            Text(
              AppInfo.appName,
              style: theme.textStyle(size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              CommonStrings.loading,
              style: theme.textStyle(
                size: 13,
                color: theme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地存储打开失败页。
///
/// 这里刻意不做「静默降级到内存存储」：内存存储意味着用户以为数据存下来了、
/// 其实一关应用就没了 —— 对这个应用来说比直接报错糟糕得多。
class StorageFailurePage extends StatelessWidget {
  const StorageFailurePage({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimalAlert(
                  type: AnimalAlertType.error,
                  title: const Text(BootStrings.storageErrorTitle),
                  child: Text(
                    BootStrings.storageErrorBody,
                    style: theme.textStyle(size: 13),
                  ),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  IslandCard(
                    type: IslandCardType.dashed,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${BootStrings.storageErrorDetail}$error',
                      style: theme.textStyle(
                        size: 12,
                        color: theme.secondaryTextColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                IslandPrimaryButton(
                  
                  block: true,
                  onPressed: () => onRetry(),
                  child: const Text(BootStrings.storageRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
