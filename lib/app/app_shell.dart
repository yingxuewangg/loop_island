import 'dart:async';

import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/island_bottom_bar.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/data/maintenance.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/features/cycle/cycle_list_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/features/tasks/task_list_page.dart';
import 'package:loop_island/features/today/today_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:loop_island/services/reminder_scheduler.dart';

/// 应用主外壳：底部 4 个 Tab「今日 / 任务 / 计划 / 设置」。
///
/// 用 [IndexedStack] 承载页面，切换 Tab 时各页状态（滚动位置、输入内容、
/// 展开项）得以保留，避免每次切换都重建。
///
/// 注意：[AnimalBottomBar] 的 `_BottomBarButton` 会自行按选中态着色
/// （图标走 `IconTheme.merge`、文字走 `DefaultTextStyle.merge`），
/// 因此这里传入的 icon/label **不要**再带显式颜色，否则会盖掉选中效果。
///
/// 本组件同时是**每日维护的唯一 owner**（归档到期计划 + 物化今天的循环实例）。
/// 放在这里而不是各页面里的原因：`IndexedStack` 会把四个 Tab 页面**全部构建**，
/// 若多个页面各自监听数据并提交维护结果，同一次数据变化会被提交多次
/// （曾因此产生重复写盘，计划列表页与今日页各写一次）。
///
/// 同理，它也是**提醒同步的唯一 owner**：每次数据变化（每日维护、勾选任务、
/// 改计划、改设置）后重新算一次「该有哪些提醒」。这样「关闭提醒总开关后取消
/// 全部通知」不需要设置页自己去调调度器 —— 设置写下去，同步自然会跑。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _pages = <Widget>[
    TodayPage(),
    TaskListPage(),
    CycleListPage(),
    SettingsPage(),
  ];

  int _currentIndex = 0;
  bool _maintaining = false;
  bool _syncingReminders = false;

  /// 上一次观察到的精确闹钟授权状态。
  ///
  /// 用来识别「用户刚去系统设置里把精确闹钟授权打开了」这个翻转 ——
  /// 系统里已排的是**非精确**闹钟，不重排的话授权等于白授。
  /// `null` 表示还没查过（或平台不适用）。
  bool? _exactAlarmsGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 数据可能已经加载完毕（例如热重载），首帧后补一次检查
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = ref.appDataOrNull;
      if (data != null) {
        unawaited(_maintain(data));
        unawaited(_syncReminders(data));
      }
    });
    // 通知的初始化要等首帧之后：冷启动那次点击需要能 push 路由
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setupNotifications());
      unawaited(_refreshExactAlarmState(initial: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // 回到前台可能已经跨天了（挂了一整夜、或有天没打开）。
    // 必须先刷新「今天」，否则今日页、每日维护、提醒调度全都停在旧日期。
    unawaited(_refreshDayIfChanged());
    // 用户从系统设置页授权后回到应用 → 这里能观察到状态翻转。
    unawaited(_refreshExactAlarmState());
  }

  /// 若真实日期已翻页，则刷新「今天」并重跑每日维护与提醒同步。
  ///
  /// [todayProvider] 会缓存首次结果，应用不被杀就永远不会自己跨天 ——
  /// 这是「26 号建的任务到了 27 号还显示明天」的根源之一。
  ///
  /// 判据是「[todayProvider] 的**缓存值**」对比「当前真实日期」：
  /// 缓存值本身就代表「上次算今天时是哪天」，可靠且无额外状态。
  /// 不能另建日期戳 provider —— `Provider` 惰性求值，没有其它读取方时
  /// 它会在跨天之后才第一次被读到，于是永远"看起来没变"。
  Future<void> _refreshDayIfChanged() async {
    if (!mounted) {
      return;
    }
    final cachedToday = dayKey(ref.read(todayProvider));
    final actualToday = dayKey(ref.read(nowProvider)());
    if (cachedToday == actualToday) {
      return;
    }

    // 作废「今天」（以及所有由它派生的 provider，如今日视图），
    // 下次读取即按新日期重算。
    ref.invalidate(todayProvider);
    if (!mounted) {
      return;
    }

    final data = ref.appDataOrNull;
    if (data == null) {
      return;
    }
    // 维护（归档到期计划、物化今天实例）与提醒同步都必须按新的「今天」重跑。
    await _maintain(data);
    await _syncReminders(ref.appDataOrNull ?? data);
  }

  /// 复查精确闹钟授权状态；从「未授权」翻转为「已授权」时重排全部提醒。
  ///
  /// 插件的 `requestExactAlarmsPermission()` 已授权时会直接返回、不弹系统页，
  /// 所以这里的重复查询是安全的。重排用 [ReminderScheduler.invalidate] 作废
  /// 内存基准，下一次 sync 就会把每条提醒重新注册为精确闹钟。
  Future<void> _refreshExactAlarmState({bool initial = false}) async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    bool? granted;
    try {
      granted = await service.exactAlarmsEnabled();
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }

    final previous = _exactAlarmsGranted;
    _exactAlarmsGranted = granted;

    // 只在「上次明确未授权 → 现在已授权」时重排。
    // initial 那一次只记录基线，避免每次启动都无谓地全量重排。
    if (initial || previous != false || granted != true) {
      return;
    }

    final scheduler = ref.read(reminderSchedulerProvider);
    scheduler.invalidate();
    final data = ref.appDataOrNull;
    if (data != null) {
      await _syncReminders(data);
    }
  }

  /// 注册通知点击回调，并补上「应用是被点通知启动的」这种情况。
  ///
  /// 冷启动与热启动是两条不同的路径：热启动由插件的回调直接送到
  /// [_openReminderTarget]；冷启动那次点击发生在应用起来之前，只能靠
  /// [NotificationService.initialPayload] 在启动后补一次。
  Future<void> _setupNotifications() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    try {
      await service.init(onTap: (payload) {
        unawaited(_openReminderTarget(payload));
      });
      final initial = await service.initialPayload();
      if (initial != null) {
        await _openReminderTarget(initial);
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'loop_island',
          context: ErrorDescription('注册通知点击回调时出错（已忽略）'),
        ),
      );
    }
  }

  /// 把一次通知点击变成导航：**一律回到今日页**。
  ///
  /// 提醒只是「该做这件事了」的提示，不代表用户已经完成。若直接跳进任务
  /// 编辑页，会逼着用户当场处理状态（完成 / 未完成 / 跳过）——那是用户
  /// 自己的判断，不该由一次点击替他决定。落在今日页，用户能看到今天的
  /// 全部安排并自行勾选。
  ///
  /// **过期 payload 不导航**（直接忽略）：Android 插件靠 Activity 当前
  /// Intent 判断「是否通知启动」，这个 Intent 可能跨启动残留，把一次普通
  /// 打开误判成点了旧通知。此时导航会 `popUntil` 弹掉用户正在编辑的页面
  /// （草稿全丢）。调度时刻超过一天的 payload 只可能是残留。
  ///
  /// 先清掉栈上的旧页面再切 Tab：否则用户点通知后会落在一堆残留页面的
  /// 最上面，返回键的行为也变得难以预料。
  Future<void> _openReminderTarget(String? payload) async {
    final parsed = ReminderPayload.parse(payload);
    if (parsed != null && parsed.isStale()) {
      if (kDebugMode) {
        debugPrint('[notify] 忽略过期的通知启动 payload：$parsed');
      }
      return;
    }
    _goToTodayTab();
  }

  /// 回到今日页：先清掉栈上的页面，再切 Tab。
  void _goToTodayTab() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _switchTab(0);
  }

  void _switchTab(int index) {
    if (!mounted || index == _currentIndex) {
      return;
    }
    setState(() => _currentIndex = index);
  }

  /// 幂等维护：数据已经是对的就不写盘。
  Future<void> _maintain(AppData data) async {
    if (_maintaining || !mounted) {
      return;
    }
    final next = prepareForDay(data, ref.read(todayProvider));
    if (next == null) {
      return;
    }

    _maintaining = true;
    try {
      await ref.read(appDataProvider.notifier).commit(next);
    } finally {
      _maintaining = false;
    }
  }

  /// 把「该有哪些提醒」同步到系统。
  ///
  /// 刻意不抛异常：通知能力出问题（用户拒绝授权、厂商 ROM 限制）时，
  /// 应用照常可用，只是提醒不响。
  ///
  /// 循环收敛而不是「跑一次就完」：同步期间每日维护可能刚好提交了新快照
  /// （归档了到期计划），此时必须按新快照再算一次，否则会漏掉那次归档带来的
  /// 取消操作。`ReminderScheduler.sync` 是差分 + 幂等的，多跑一次没有副作用。
  Future<void> _syncReminders(AppData data) async {
    if (_syncingReminders || !mounted) {
      return;
    }
    _syncingReminders = true;
    try {
      var snapshot = data;
      while (mounted) {
        await ref.read(reminderSchedulerProvider).sync(
              data: snapshot,
              settings: snapshot.settings,
              now: ref.read(nowProvider)(),
            );
        final latest = ref.appDataOrNull;
        if (latest == null || latest == snapshot) {
          return;
        }
        snapshot = latest;
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'loop_island',
          context: ErrorDescription('同步本地提醒时出错（已忽略）'),
        ),
      );
    } finally {
      _syncingReminders = false;
    }
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) {
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppData>>(appDataProvider, (previous, next) {
      final data = next.asData?.value;
      if (data != null) {
        // 先维护再同步提醒：维护可能会归档到期计划、物化今天的实例，
        // 提醒应当基于维护后的快照算（多跑一次同步是幂等的）。
        unawaited(_maintain(data));
        unawaited(_syncReminders(data));
      }
    });

    return Scaffold(
      // 让页面内容延伸到底部导航栏后面：毛玻璃才有真实内容可模糊，
      // 否则底栏后面只有渐变背景，半透明白几乎等于纯白。
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: IslandBottomBar(
        currentIndex: _currentIndex,
        onChanged: _onTabChanged,
        items: const [
          IslandBottomBarItem(
            icon: Icon(Icons.wb_sunny_outlined),
            activeIcon: Icon(Icons.wb_sunny),
            label: Text(TabLabels.today),
          ),
          IslandBottomBarItem(
            icon: Icon(Icons.checklist_outlined),
            activeIcon: Icon(Icons.checklist_rtl),
            label: Text(TabLabels.tasks),
          ),
          IslandBottomBarItem(
            icon: Icon(Icons.autorenew_outlined),
            activeIcon: Icon(Icons.autorenew),
            label: Text(TabLabels.cycles),
          ),
          IslandBottomBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: Text(TabLabels.settings),
          ),
        ],
      ),
    );
  }
}
