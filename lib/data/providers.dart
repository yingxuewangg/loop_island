import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/day_view.dart';
import 'package:loop_island/data/app_repository.dart';
import 'package:loop_island/data/local_store.dart';
import 'package:loop_island/models/app_data.dart';

/// 本地存储实现。
///
/// **必须**在 `runApp` 之前用 `ProviderScope(overrides: [...])` 注入：
/// 生产环境注入 `HiveLocalStore`，测试注入 `InMemoryLocalStore`。
/// 故意不给默认实现 —— 静默退回某个实现会让「测试误写真实磁盘」这类
/// 事故变得难以发现。
final localStoreProvider = Provider<LocalStore>((ref) {
  throw StateError(
    'localStoreProvider 未初始化：请在 ProviderScope.overrides 中注入 LocalStore',
  );
});

/// 数据仓库。
final appRepositoryProvider = Provider<AppRepository>((ref) {
  final repository = AppRepository(ref.watch(localStoreProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

/// 应用数据快照。
///
/// UI 通过 `ref.watch(appDataProvider)` 拿到 `AsyncValue<AppData>`：
/// 首次加载显示骨架屏，之后仓库每次提交都会推来新值。
final appDataProvider =
    AsyncNotifierProvider<AppDataNotifier, AppData>(AppDataNotifier.new);

/// 数据快照的 Notifier，把仓库的 Stream 桥接成 Riverpod 状态。
class AppDataNotifier extends AsyncNotifier<AppData> {
  @override
  Future<AppData> build() async {
    final repository = ref.watch(appRepositoryProvider);
    final subscription =
        repository.changes.listen((data) => state = AsyncData(data));
    ref.onDispose(subscription.cancel);
    return repository.init();
  }

  /// 命令层通过它提交新快照。
  Future<void> commit(AppData next) {
    return ref.read(appRepositoryProvider).commit(next);
  }

  /// 清空全部业务数据，**保留设置**（应用锁、提醒开关等）。
  Future<void> clearBusinessData() {
    return ref.read(appRepositoryProvider).clearBusinessData();
  }
}

/// 「今天」。
///
/// 独立成 provider 是为了让测试能把它固定成任意日期 ——
/// 循环计划、连续打卡、热力图全都依赖「今天是哪天」，
/// 若到处直接调 `DateTime.now()` 就没法写确定性测试。
///
/// 走 [nowProvider] 取时刻（而不是直接 `DateTime.now()`），这样测试用
/// 一个可变时钟就能同时驱动「今天」与提醒调度，跨天场景才可测。
///
/// **必须处理跨天**：`Provider` 会永久缓存首次结果，应用若长时间不被
/// 杀掉，「今天」会一直停在启动那天 —— 今日页、每日维护、相对日期换算
/// 全部跟着错。刷新入口见 `AppShell._refreshDayIfChanged`：
/// 它把**本 provider 的缓存值**与当前真实日期比较（缓存值就是「上次算
/// 今天时是哪天」），不一致即作废重算。
///
/// 注意别另建一个「日期戳 provider」来记录这件事：`Provider` 是**惰性**
/// 求值的，若没有其它读取方，它会在跨天之后才第一次被读到，于是「记下的
/// 日期」永远等于当前日期，比较永远相等、跨天永远检测不到。
/// [todayProvider] 的缓存值本身才是那个可靠的「上次计算的日期」。
final todayProvider = Provider<DateTime>(
  (ref) => dateOnly(ref.watch(nowProvider)()),
);

/// 当前**时刻**（不是日期）。
///
/// 与 [todayProvider] 分开的原因：提醒调度需要「现在几点几分」才能判断
/// 一个时间点是否已经过去，而 [todayProvider] 刻意把时间部分抹平了。
/// 同样做成 provider 是为了测试能固定它。
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 「今天」的日期键（`yyyy-MM-dd`）。
final todayKeyProvider =
    Provider<String>((ref) => dayKey(ref.watch(todayProvider)));

/// 安全读取当前数据快照。
///
/// **必须用 [AsyncValue.asData] 而不是 `.value`**：在 Riverpod 2.x 中
/// `AsyncError.value` 会把原始异常**抛出来**，于是「读取失败」这种本该
/// 显示错误页的情况会直接变成一次崩溃。
/// 加载中与出错时统一返回 `null`，由调用方决定怎么处理。
extension AppDataRefX on WidgetRef {
  AppData? get appDataOrNull => read(appDataProvider).asData?.value;

  /// 读取数据，缺失时退化为空数据（用于「尽力而为」的写操作）。
  AppData get appDataOrEmpty => appDataOrNull ?? AppData.empty;
}

/// 今日视图：普通任务（今天）+ 所有启用中计划今天的任务。
///
/// 派生于 [appDataProvider] 与 [todayProvider]，测试里覆写这两者即可固定结果。
final todayViewProvider = Provider<AsyncValue<DayView>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(appDataProvider)
      .whenData((data) => buildTodayView(data, today));
});

/// 明日视图：**纯计算，不落库**。
final tomorrowViewProvider = Provider<AsyncValue<DayView>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(appDataProvider)
      .whenData((data) => buildTomorrowView(data, today));
});
