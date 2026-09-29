/// 应用设置的命令层（任务 8.5）。
///
/// 和 `task_commands.dart` / `cycle_commands.dart` 一样是**纯函数**：
/// 输入旧 [AppData]，返回新 [AppData]，不碰磁盘、不碰时钟。
///
/// 单独成文件而不是并进任务/记录命令：设置是**应用级配置**，
/// 与业务数据无关，混在一起会让「清空数据保留设置」这条规则难以维护。
library;

import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/settings.dart';

/// 打开 / 关闭提醒总开关。
AppData setRemindersEnabled(AppData data, bool enabled) {
  return _withSettings(data, data.settings.copyWith(remindersEnabled: enabled));
}

/// 修改默认提醒时段（一天内分钟数列表，会去重、升序、截断到上限）。
AppData setDefaultRemindMinutesOfDay(AppData data, List<int> minutesOfDay) {
  return _withSettings(
    data,
    data.settings.copyWith(defaultRemindMinutesOfDay: minutesOfDay),
  );
}

/// 修改默认提醒时段（只设一个时刻的便捷写法）。
AppData setDefaultRemindMinuteOfDay(AppData data, int minuteOfDay) {
  return setDefaultRemindMinutesOfDay(data, [minuteOfDay]);
}

/// 打开 / 关闭循环计划每日提醒。
AppData setCycleRemindersEnabled(AppData data, bool enabled) {
  return _withSettings(
    data,
    data.settings.copyWith(cycleRemindersEnabled: enabled),
  );
}

AppData _withSettings(AppData data, AppSettings settings) {
  if (settings == data.settings) {
    return data;
  }
  return data.copyWith(settings: settings);
}
