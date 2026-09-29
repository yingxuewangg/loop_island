import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/data/settings_commands.dart';
import 'package:loop_island/models/app_data.dart';

import '../support/factories.dart';

/// 任务 8.5：设置命令层（纯函数）。
void main() {
  group('8.5 提醒相关设置命令', () {
    test('开关总开关', () {
      final data = makeAppData();
      expect(data.settings.remindersEnabled, isTrue);

      final off = setRemindersEnabled(data, false);
      expect(off.settings.remindersEnabled, isFalse);
      // 其它字段不受影响
      expect(off.settings.defaultRemindMinuteOfDay,
          data.settings.defaultRemindMinuteOfDay);
      expect(off.settings.cycleRemindersEnabled,
          data.settings.cycleRemindersEnabled);
      expect(off.tasks, same(data.tasks));
    });
    test('修改默认提醒时间', () {
      final data = makeAppData();
      final updated = setDefaultRemindMinuteOfDay(data, 22 * 60 + 30);
      expect(updated.settings.defaultRemindMinuteOfDay, 22 * 60 + 30);
      expect(updated.settings.defaultRemindLabel, '22:30');
    });

    test('越界的分钟数被夹到合法区间，不会写出脏数据', () {
      final data = makeAppData();
      expect(
        setDefaultRemindMinuteOfDay(data, -5)
            .settings
            .defaultRemindMinuteOfDay,
        0,
      );
      expect(
        setDefaultRemindMinuteOfDay(data, 99 * 60)
            .settings
            .defaultRemindMinuteOfDay,
        24 * 60 - 1,
      );
    });

    test('开关循环计划提醒', () {
      final data = makeAppData();
      final off = setCycleRemindersEnabled(data, false);
      expect(off.settings.cycleRemindersEnabled, isFalse);
      expect(off.settings.remindersEnabled, isTrue);
    });

    test('设置没变化时返回同一个对象（不触发多余的写盘与广播）', () {
      final data = makeAppData();
      expect(identical(setRemindersEnabled(data, true), data), isTrue);
      expect(
        identical(
          setDefaultRemindMinuteOfDay(
            data,
            data.settings.defaultRemindMinuteOfDay,
          ),
          data,
        ),
        isTrue,
      );
    });

    test('清空业务数据后设置仍然保留', () {
      final data = makeAppData(
        settings: makeSettings(remindersEnabled: false, cycleRemindersEnabled: false),
      );
      final cleared = AppData(settings: data.settings);
      expect(cleared.settings.remindersEnabled, isFalse);
      expect(cleared.settings.cycleRemindersEnabled, isFalse);
      expect(cleared.tasks, isEmpty);
    });
  });
}
