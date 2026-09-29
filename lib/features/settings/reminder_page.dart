import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/settings_commands.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/services/battery_whitelist.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/services/notification_service.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 提醒设置页内可被测试稳定定位的控件键。
abstract final class ReminderKeys {
  static const masterSwitch = Key('reminder-master-switch');
  static const defaultTimeTile = Key('reminder-default-time');
  static const cycleSwitch = Key('reminder-cycle-switch');
  static const permissionBanner = Key('reminder-permission-banner');
  static const unsupportedNotice = Key('reminder-unsupported');
  static const statusCard = Key('reminder-status-card');
  static const reRequestPermission = Key('reminder-re-request-permission');
  static const reRequestExactAlarm = Key('reminder-re-request-exact-alarm');
  static const requestWhitelist = Key('reminder-request-whitelist');
  static const refreshPending = Key('reminder-refresh-pending');
}

/// 提醒设置页（任务 8.5）。
///
/// 三件事：总开关、默认提醒时间、循环计划提醒开关。
/// - 状态全部持久化到 `AppSettings`（经由 `data/settings_commands.dart`）。
/// - 「关闭总开关后取消全部已注册提醒」由 `AppShell` 的同步逻辑完成
///   （它是提醒同步的唯一 owner，见 `services/reminder_scheduler.dart`）：
///   这里只负责把设置写下去，写下去之后同步自然会跑。
/// - 首次进入本页时申请一次通知权限，并把结果反馈在页面上（任务 8.2）。
class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key});

  @override
  ConsumerState<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends ConsumerState<ReminderPage> {
  /// 权限申请结果；`null` 表示还没问过（或该平台不需要授权）。
  bool? _permissionGranted;
  bool _askedPermission = false;

  /// 系统里待发送的提醒（「系统调度状态」卡片用）。
  List<PendingNotificationSummary> _pending = const [];
  bool _pendingLoaded = false;
  bool _pendingLoadFailed = false;

  /// 精确闹钟权限；`null` 表示平台不适用（非 Android 12+）。
  bool? _exactAlarms;

  /// 电池优化白名单；`null` 表示平台不适用或查询失败。
  bool? _batteryWhitelisted;

  @override
  void initState() {
    super.initState();
    // 首帧后再申请：申请失败时要弹提示，需要 context 已经可用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askPermission();
      _refreshStatus();
    });
  }

  Future<void> _askPermission() async {
    if (_askedPermission) {
      return;
    }
    _askedPermission = true;

    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    final granted = await service.requestPermission();
    if (mounted) {
      setState(() => _permissionGranted = granted);
    }
  }

  /// 重新向系统申请一次通知权限（用户拒绝过后仍可再问）。
  Future<void> _requestPermissionAgain() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    final granted = await service.requestPermission();
    if (mounted) {
      setState(() => _permissionGranted = granted);
    }
    await _refreshStatus();
  }

  /// 查询系统调度状态：待发送提醒 + 精确闹钟权限 + 电池白名单。
  Future<void> _refreshStatus() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    try {
      final pending = await service.pendingNotifications();
      final exactAlarms = await service.exactAlarmsEnabled();
      final battery = await ref.read(batteryWhitelistProvider)
          .isIgnoringOptimizations();
      if (mounted) {
        setState(() {
          _pending = pending;
          _pendingLoaded = true;
          _pendingLoadFailed = false;
          _exactAlarms = exactAlarms;
          _batteryWhitelisted = battery;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pendingLoaded = true;
          _pendingLoadFailed = true;
        });
      }
    }
  }

  /// 拉起系统的「忽略电池优化」授权框，成功后复查状态。
  Future<void> _requestBatteryWhitelist() async {
    await ref.read(batteryWhitelistProvider).requestIgnoreOptimizations();
    // 授权框是另一个界面，回来后状态可能已变化，复查一次。
    await _refreshStatus();
  }

  /// 「系统调度状态」卡片：权限状态 + 已排进系统的提醒条数。
  ///
  /// 「提醒静默不响」只有两种可能：**没排进系统**（应用侧调度失败），
  /// 或**排进了系统但系统没弹**（权限被拒 / ROM 省电拦截）。
  /// 这张卡片把两种情况区分开 —— 待发送为 0 说明应用侧就没排上，
  /// 大于 0 却不响则去查系统权限与省电设置。
  Widget _buildStatusCard(AnimalThemeData theme) {
    final permissionGranted = _permissionGranted != false;
    final titles = _pending
        .take(5)
        .map((item) => item.title ?? item.id.toString())
        .join('、');

    return IslandCard(
      key: ReminderKeys.statusCard,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SettingsStrings.reminderStatusTitle,
            style: theme.textStyle(size: 15),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  permissionGranted
                      ? SettingsStrings.reminderPermissionGranted
                      : SettingsStrings.reminderPermissionMissing,
                  style: theme.textStyle(
                    size: 13,
                    color: permissionGranted
                        ? theme.textColor
                        : theme.errorColor,
                  ),
                ),
              ),
              if (!permissionGranted)
                IslandPrimaryButton(
                  key: ReminderKeys.reRequestPermission,
                  onPressed: _requestPermissionAgain,
                  child: const Text(SettingsStrings.reRequestPermission),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 电池优化白名单：真机（尤其国产 ROM）后台清理是「提醒时有时无」
          // 的最大来源；只有「未加白」才显示，非 Android 平台查询返回
          // null，整行隐藏。
          if (_batteryWhitelisted == false) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    SettingsStrings.reminderBatteryMissing,
                    style: theme.textStyle(
                      size: 13,
                      color: theme.warningColor,
                    ),
                  ),
                ),
                AnimalButton(
                  key: ReminderKeys.requestWhitelist,
                  onPressed: _requestBatteryWhitelist,
                  child: const Text(SettingsStrings.requestWhitelist),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // 精确闹钟：只有「未授权」才显示 —— 这是提醒延迟几十秒到几分钟
          // 的直接原因，必须给出可操作的引导（重新申请会顺带打开系统页）。
          if (_exactAlarms == false) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    SettingsStrings.reminderExactAlarmMissing,
                    style: theme.textStyle(
                      size: 13,
                      color: theme.warningColor,
                    ),
                  ),
                ),
                AnimalButton(
                  key: ReminderKeys.reRequestExactAlarm,
                  onPressed: _requestPermissionAgain,
                  child: const Text(SettingsStrings.reRequestPermission),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_pendingLoadFailed)
                      Text(
                        SettingsStrings.pendingLoadFailed,
                        style: theme.textStyle(
                          size: 13,
                          color: theme.errorColor,
                        ),
                      )
                    else if (_pendingLoaded) ...[
                      Text(
                        _pending.isEmpty
                            ? SettingsStrings.pendingZero
                            : SettingsStrings.pendingCount(_pending.length),
                        style: theme.textStyle(size: 13),
                      ),
                      if (_pending.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          SettingsStrings.pendingTitles(titles),
                          style: theme.textStyle(
                            size: 12,
                            color: theme.secondaryTextColor,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              AnimalButton(
                key: ReminderKeys.refreshPending,
                onPressed: _refreshStatus,
                child: const Text(SettingsStrings.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 把一条纯函数命令落到仓库上。
  Future<void> _commit(AppData Function(AppData) command) async {
    try {
      // 先等首帧数据到位：否则可能拿着默认设置去覆盖用户的开关。
      final data = await ref.read(appDataProvider.future);
      await ref.read(appDataProvider.notifier).commit(command(data));
    } catch (_) {
      if (mounted) {
        AnimalMessage.error(
          context,
          const Text(SettingsStrings.reminderSaveFailed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final service = ref.read(notificationServiceProvider);
    final supported = service.isSupported;
    final data = ref.watch(appDataProvider).asData?.value ?? AppData.empty;
    final settings = data.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text(SettingsStrings.reminderTitle),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!supported) ...[
            IslandCard(
              key: ReminderKeys.unsupportedNotice,
              color: IslandCardColor.warm,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SettingsStrings.reminderUnsupported,
                    style: theme.textStyle(size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SettingsStrings.reminderUnsupportedHint,
                    style: theme.textStyle(
                      size: 12,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (_permissionGranted == false) ...[
            IslandCard(
              key: ReminderKeys.permissionBanner,
              color: IslandCardColor.warm,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SettingsStrings.permissionDenied,
                    style: theme.textStyle(size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SettingsStrings.permissionDeniedHint,
                    style: theme.textStyle(
                      size: 12,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (supported) ...[
            _buildStatusCard(theme),
            const SizedBox(height: 12),
          ],

          IslandCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SettingsStrings.reminderEnabled,
                        style: theme.textStyle(size: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        SettingsStrings.reminderEnabledHint,
                        style: theme.textStyle(
                          size: 12,
                          color: theme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimalSwitch(
                  key: ReminderKeys.masterSwitch,
                  value: settings.remindersEnabled,
                  disabled: !supported,
                  onChanged: (value) =>
                      _commit((data) => setRemindersEnabled(data, value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (settings.remindersEnabled) ...[
            IslandCard(
              key: ReminderKeys.defaultTimeTile,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SettingsStrings.defaultRemindTime,
                    style: theme.textStyle(size: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SettingsStrings.defaultRemindTimeHint,
                    style: theme.textStyle(
                      size: 12,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 一天可以提醒多次：这里编辑的就是「新计划打开提醒时
                  // 套用的那一串时段」，所以它和计划编辑页用的是同一个编辑器。
                  MinuteOfDayListEditor(
                    values: settings.defaultRemindMinutesOfDay,
                    enabled: supported,
                    onChanged: (value) => _commit(
                      (data) => setDefaultRemindMinutesOfDay(data, value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IslandCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          SettingsStrings.cycleReminderEnabled,
                          style: theme.textStyle(size: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SettingsStrings.cycleReminderEnabledHint,
                          style: theme.textStyle(
                            size: 12,
                            color: theme.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimalSwitch(
                    key: ReminderKeys.cycleSwitch,
                    value: settings.cycleRemindersEnabled,
                    disabled: !supported,
                    onChanged: (value) => _commit(
                      (data) => setCycleRemindersEnabled(data, value),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
