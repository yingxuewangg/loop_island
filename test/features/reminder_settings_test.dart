import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/data/memory_local_store.dart';
import 'package:loop_island/features/settings/reminder_page.dart';
import 'package:loop_island/features/settings/settings_page.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/services/battery_whitelist.dart';
import 'package:loop_island/services/reminder_scheduler.dart';

import '../support/factories.dart';
import '../support/fake_battery_whitelist.dart';
import '../support/fake_notification_service.dart';
import '../support/pump_app.dart';

/// 任务 8.5：提醒设置页。
void main() {
  final today = DateTime(2026, 9, 12);
  final now = DateTime(2026, 9, 12, 10);

  /// 长列表页面在默认 800×600 视口下靠下的内容不会被构建。
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 切到「设置」Tab。
  ///
  /// `IndexedStack` 会让非当前 Tab 处于 offstage，finder 默认跳过它们，
  /// 所以必须先切 Tab 再找内容；`.last` 取的是底部导航栏那一个。
  Future<void> openSettingsTab(WidgetTester tester) async {
    await tester.tap(find.text(TabLabels.settings).last);
    await tester.pumpAndSettle();
  }

  /// 挂载应用并进入提醒设置页。
  Future<
      ({
        InMemoryLocalStore store,
        FakeNotificationService service,
      })> openReminderPage(
    WidgetTester tester, {
    AppData? data,
    bool supported = true,
    bool permissionGranted = true,
    List<Override> extraOverrides = const [],
  }) async {
    final service = FakeNotificationService(
      supported: supported,
      permissionGranted: permissionGranted,
    );
    final result = await pumpLoopIslandApp(
      tester,
      data: data,
      today: today,
      now: now,
      notificationService: service,
      extraOverrides: extraOverrides,
    );

    await openSettingsTab(tester);
    await tester.tap(find.byKey(SettingsKeys.reminderEntry));
    await tester.pumpAndSettle();

    return (store: result.store, service: service);
  }

  group('8.5 入口与页面骨架', () {
    testWidgets('设置页有提醒入口，点进去是提醒设置页', (tester) async {
      useLargeSurface(tester);
      await pumpLoopIslandApp(tester, today: today, now: now);
      await openSettingsTab(tester);

      expect(find.byKey(SettingsKeys.reminderEntry), findsOneWidget);

      await tester.tap(find.byKey(SettingsKeys.reminderEntry));
      await tester.pumpAndSettle();

      expect(find.byType(ReminderPage), findsOneWidget);
      expect(find.text(SettingsStrings.reminderEnabled), findsOneWidget);
      expect(find.text(SettingsStrings.defaultRemindTime), findsOneWidget);
      expect(find.text(SettingsStrings.cycleReminderEnabled), findsOneWidget);
    });

    testWidgets('默认提醒时段显示的是设置里的值', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(
        tester,
        data: AppData(
          settings: makeSettings(defaultRemindMinuteOfDay: 21 * 60 + 30),
        ),
      );

      expect(find.textContaining('21 时'), findsWidgets);
      expect(find.textContaining('30 分'), findsWidgets);
    });
  });

  group('8.5 提醒总开关', () {
    testWidgets('关闭总开关会持久化，并取消全部已注册提醒', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(
        tester,
        data: AppData(
          tasks: [makeTask(remindAt: DateTime(2026, 9, 12, 18))],
        ),
      );

      // 冷启动同步阶段已经注册过一次任务提醒
      expect(ctx.service.liveIds, isNotEmpty);
      final cancelAllBefore = ctx.service.cancelAllCount;

      await tester.tap(find.byKey(ReminderKeys.masterSwitch));
      await tester.pumpAndSettle();

      expect(ctx.store.snapshot!.data.settings.remindersEnabled, isFalse);
      expect(
        ctx.service.cancelAllCount,
        greaterThan(cancelAllBefore),
        reason: '关掉总开关必须把系统里已注册的提醒清干净',
      );
      expect(ctx.service.liveIds, isEmpty);
    });

    testWidgets('关闭总开关后隐藏默认提醒时间与循环计划开关', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(tester);

      expect(find.byKey(ReminderKeys.defaultTimeTile), findsOneWidget);
      expect(find.byKey(ReminderKeys.cycleSwitch), findsOneWidget);

      await tester.tap(find.byKey(ReminderKeys.masterSwitch));
      await tester.pumpAndSettle();

      expect(find.byKey(ReminderKeys.defaultTimeTile), findsNothing);
      expect(find.byKey(ReminderKeys.cycleSwitch), findsNothing);
    });

    testWidgets('重新打开总开关会保存', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(
        tester,
        data: AppData(settings: makeSettings(remindersEnabled: false)),
      );

      await tester.tap(find.byKey(ReminderKeys.masterSwitch));
      await tester.pumpAndSettle();

      expect(ctx.store.snapshot!.data.settings.remindersEnabled, isTrue);
    });
  });

  group('8.5 默认提醒时段', () {
    testWidgets('可以改时刻并持久化', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester);

      // 默认只有一个时段 09:00
      expect(find.textContaining('09 时'), findsWidgets);

      // 第一个下拉是小时
      await tester.tap(find.byType(AnimalSelect<int>).first);
      await tester.pumpAndSettle();

      // 小时下拉最多滚 260 高，22 时不在可视范围内，先滚到它
      // （小时标签带「晚上」段位标注，见 MinuteOfDayPicker 的 _hourLabel）
      final option = find.textContaining('22 时').last;
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(
        ctx.store.snapshot!.data.settings.defaultRemindMinutesOfDay,
        [22 * 60],
        reason: '新设置必须落盘，否则重启就丢了',
      );
      expect(find.textContaining('22 时'), findsWidgets);
    });

    testWidgets('可以加第二个时段，形成「一天提醒两次」', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester);

      await tester.tap(find.byKey(RemindSlotKeys.add));
      await tester.pumpAndSettle();

      expect(
        ctx.store.snapshot!.data.settings.defaultRemindMinutesOfDay,
        [9 * 60, 10 * 60],
        reason: '新时段的默认值接在最后一个时段之后一小时',
      );
      expect(find.byKey(RemindSlotKeys.row(1)), findsOneWidget);
      expect(find.byKey(RemindSlotKeys.remove(1)), findsOneWidget);
    });

    testWidgets('可以删掉多出来的时段', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester);

      await tester.tap(find.byKey(RemindSlotKeys.add));
      await tester.pumpAndSettle();
      expect(ctx.store.snapshot!.data.settings.defaultRemindMinutesOfDay,
          hasLength(2));

      await tester.tap(find.byKey(RemindSlotKeys.remove(1)));
      await tester.pumpAndSettle();

      expect(
        ctx.store.snapshot!.data.settings.defaultRemindMinutesOfDay,
        [9 * 60],
      );
    });

    testWidgets('最后一个时段不给删：要「不提醒」请关总开关', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(tester);

      final remove = tester.widget<IconButton>(
        find.byKey(RemindSlotKeys.remove(0)),
      );
      expect(remove.onPressed, isNull);
    });

    testWidgets('最多 5 个时段，到上限后不能再加', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester);

      for (var i = 1; i < kMaxRemindSlots; i++) {
        await tester.tap(find.byKey(RemindSlotKeys.add));
        await tester.pumpAndSettle();
      }

      final saved = ctx.store.snapshot!.data.settings.defaultRemindMinutesOfDay;
      expect(saved, hasLength(kMaxRemindSlots));

      final addButton = tester.widget<AnimalButton>(
        find.byKey(RemindSlotKeys.add),
      );
      expect(addButton.onPressed, isNull, reason: '到上限后加号要禁用');
      expect(find.byKey(RemindSlotKeys.limitHint), findsOneWidget);
    });
  });

  group('8.5 循环计划提醒开关', () {
    testWidgets('关闭循环提醒会持久化，并取消循环提醒但保留任务提醒', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(
        tester,
        data: AppData(
          tasks: [makeTask(id: 'task_1', remindAt: DateTime(2026, 9, 12, 18))],
          cycles: [makeCycle(id: 'cycle_1', remindMinuteOfDay: 9 * 60)],
        ),
      );

      final taskId =
          taskReminderId('task_1', DateTime(2026, 9, 12, 18));
      expect(ctx.service.liveIds, contains(taskId));
      expect(ctx.service.liveIds.length, greaterThan(1));

      await tester.tap(find.byKey(ReminderKeys.cycleSwitch));
      await tester.pumpAndSettle();

      expect(ctx.store.snapshot!.data.settings.cycleRemindersEnabled, isFalse);
      expect(ctx.service.liveIds, {taskId});
      expect(ctx.service.cancelled, isNot(contains(taskId)));
    });
  });

  group('8.5 权限与平台能力', () {
    testWidgets('权限被拒时给出提示', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester, permissionGranted: false);

      expect(ctx.service.permissionCount, greaterThan(0));
      expect(find.byKey(ReminderKeys.permissionBanner), findsOneWidget);
      expect(find.text(SettingsStrings.permissionDenied), findsOneWidget);
    });

    testWidgets('权限通过时不显示提示', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(tester);

      expect(find.byKey(ReminderKeys.permissionBanner), findsNothing);
    });

    testWidgets('不支持的平台给出说明，开关禁用且不写设置', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester, supported: false);

      expect(find.byKey(ReminderKeys.unsupportedNotice), findsOneWidget);
      expect(ctx.service.permissionCount, 0, reason: '不支持的平台不该去要权限');

      final saveCountBefore = ctx.store.saveCount;
      await tester.tap(find.byKey(ReminderKeys.masterSwitch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<AnimalSwitch>(
        find.byKey(ReminderKeys.masterSwitch),
      );
      expect(switchWidget.disabled, isTrue);
      expect(ctx.store.saveCount, saveCountBefore);
      expect(ctx.store.snapshot!.data.settings.remindersEnabled, isTrue);
    });
  });

  group('8.5 系统调度状态卡片', () {
    testWidgets('权限已授予时显示已排进系统的提醒条数', (tester) async {
      useLargeSurface(tester);
      final task = makeTask(
        id: 'task_1',
        title: '有未来提醒的',
        remindAt: DateTime(2026, 9, 12, 18),
      );
      final ctx = await openReminderPage(
        tester,
        data: AppData(tasks: [task]),
      );

      // 冷启动同步会把这条未来提醒排进系统，卡片必须如实反映。
      expect(find.byKey(ReminderKeys.statusCard), findsOneWidget);
      expect(
        find.text(SettingsStrings.reminderPermissionGranted),
        findsOneWidget,
      );
      expect(find.text(SettingsStrings.pendingCount(1)), findsOneWidget);
      expect(ctx.service.pendingQueries, greaterThanOrEqualTo(1));
    });

    testWidgets('没有任何未来提醒时显示 0 条', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(tester);

      expect(find.text(SettingsStrings.pendingZero), findsOneWidget);
    });

    testWidgets('权限被拒时提示并支持重新申请，成功后状态更新', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester, permissionGranted: false);

      expect(
        find.text(SettingsStrings.reminderPermissionMissing),
        findsOneWidget,
      );
      expect(find.byKey(ReminderKeys.reRequestPermission), findsOneWidget);

      ctx.service.permissionGranted = true;
      await tester.tap(find.byKey(ReminderKeys.reRequestPermission));
      await tester.pumpAndSettle();

      expect(
        find.text(SettingsStrings.reminderPermissionGranted),
        findsOneWidget,
      );
      expect(
        find.byKey(ReminderKeys.reRequestPermission),
        findsNothing,
        reason: '拿到权限后按钮消失',
      );
    });

    testWidgets('精确闹钟未授权时提示并支持重新申请', (tester) async {
      useLargeSurface(tester);
      final ctx = await openReminderPage(tester);
      ctx.service.exactAlarmsEnabledResult = false;
      // 卡片数据是进页时查的，这里触发一次刷新再断言
      await tester.tap(find.byKey(ReminderKeys.refreshPending));
      await tester.pumpAndSettle();

      expect(
        find.text(SettingsStrings.reminderExactAlarmMissing),
        findsOneWidget,
      );

      ctx.service.exactAlarmsEnabledResult = true;
      await tester.tap(find.byKey(ReminderKeys.reRequestExactAlarm));
      await tester.pumpAndSettle();

      expect(
        find.text(SettingsStrings.reminderExactAlarmMissing),
        findsNothing,
        reason: '授权后提示消失',
      );
    });

    testWidgets('电池未加白名单时提示并可一键申请，授权后提示消失', (tester) async {
      useLargeSurface(tester);
      final battery = FakeBatteryWhitelist(ignored: false);
      await openReminderPage(
        tester,
        extraOverrides: [
          batteryWhitelistProvider.overrideWithValue(battery),
        ],
      );

      expect(
        find.text(SettingsStrings.reminderBatteryMissing),
        findsOneWidget,
      );
      expect(find.byKey(ReminderKeys.requestWhitelist), findsOneWidget);

      await tester.tap(find.byKey(ReminderKeys.requestWhitelist));
      await tester.pumpAndSettle();

      expect(battery.requestCount, 1);
      expect(
        find.text(SettingsStrings.reminderBatteryMissing),
        findsNothing,
        reason: '加入白名单后提示消失',
      );
    });

    testWidgets('平台不适用（查询返回 null）时不显示电池提示', (tester) async {
      useLargeSurface(tester);
      await openReminderPage(
        tester,
        extraOverrides: [
          batteryWhitelistProvider
              .overrideWithValue(FakeBatteryWhitelist(ignored: null)),
        ],
      );

      expect(
        find.text(SettingsStrings.reminderBatteryMissing),
        findsNothing,
      );
      expect(find.byKey(ReminderKeys.requestWhitelist), findsNothing);
    });
  });
}
