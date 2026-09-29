/// 全局中文文案常量。
///
/// 约定：
/// - 所有界面可见文案集中在此文件，feature 层不得散落裸中文字符串。
/// - 需要拼接变量的文案以函数形式提供，避免手写字符串模板出错。
library;

import 'package:loop_island/core/backup_codec.dart';
import 'package:loop_island/core/remind_slots.dart';

/// 应用级信息。
abstract final class AppInfo {
  static const appName = '循环小岛';
  static const appNameEn = 'Loop Island';
  static const tagline = '按周期循环执行你的计划';
  static const version = '1.0.3';
}

/// 底部 Tab 名称。
abstract final class TabLabels {
  static const today = '今日';
  static const tasks = '任务';
  static const cycles = '计划';
  static const settings = '设置';
}

/// 通用动作与状态词。
abstract final class CommonStrings {
  static const confirm = '确定';
  static const cancel = '取消';
  static const save = '保存';
  static const delete = '删除';
  static const edit = '编辑';
  static const add = '添加';
  static const done = '完成';
  static const close = '关闭';
  static const back = '返回';
  static const retry = '重试';
  static const loading = '加载中…';
  static const empty = '暂无数据';
  static const notFilled = '未填写';
  static const unlimited = '不限';
  static const required = '此项不能为空';
  static const todayTag = '今天';

  static String countItems(int n) => '$n 项';
}

/// 任务状态。
abstract final class StatusLabels {
  static const pending = '待办';
  static const completed = '完成';
  static const skipped = '跳过';
  static const missed = '未完成';
}

/// 日期类型。
abstract final class DateTypeLabels {
  static const today = '今天';
  static const tomorrow = '明天';
  static const custom = '自定义日期';
  static const none = '无日期';
  static const unscheduled = '未安排';
}

/// 今日 / 明日。
abstract final class TodayStrings {
  static const title = '今日';
  static const tomorrowPreview = '明日预览';
  static const noTaskToday = '今天没有安排';
  static const noTaskTomorrow = '明天没有安排';
  static const quickAddHint = '添加今天的任务，回车确认';
  static const markMissed = '标记未完成';
  static const markSkipped = '跳过';
  static const moreActions = '更多操作';
  static const undoComplete = '取消完成';
  static const complete = '完成';

  static String progress(int done, int total) => '已完成 $done / $total';

  static String moreItems(int n) => '还有 $n 项';

  static String cycleDayBadge(String cycleName, int day, int total) =>
      '$cycleName · 第 $day/$total 天';
}

/// 任务模块。
abstract final class TaskStrings {
  static const listTitle = '任务';
  static const groupToday = '今天';
  static const groupTomorrow = '明天';
  static const groupUnscheduled = '未安排';
  static const groupCompleted = '已完成';

  /// PRD 四组之外的补充分组：逾期未完成。
  static const groupOverdue = '逾期';

  /// PRD 四组之外的补充分组：后天及以后。
  static const groupUpcoming = '以后';

  static const editTitleNew = '新建任务';
  static const editTitleExisting = '编辑任务';
  static const fieldTitle = '标题';
  static const fieldTitleHint = '要做什么？';
  static const fieldNote = '备注';
  static const fieldNoteHint = '补充说明（可选）';
  static const fieldDate = '日期';
  static const fieldRemind = '提醒时段';
  static const fieldStatus = '状态';
  static const fieldReason = '未完成原因';
  static const history = '历史记录';
  static const noHistory = '还没有历史记录';

  static const titleRequired = '请输入任务标题';
  static const deleteConfirmTitle = '删除任务';
  static const deleteConfirmBody = '删除后该任务及其历史记录都会一并清除，且无法恢复。';
  static const remindNeedsDate = '无日期任务无法设置提醒时间';
  static const noRemind = '不提醒';
  static const addTask = '新建';
  static const customDate = '选择日期';
  static const saveFailed = '保存失败';

  /// 多时段提醒：一天可以提醒多次。
  static const addRemindTime = '添加提醒时段';
  static const removeRemindTime = '删除这个时段';
  static const remindSlotLimit = '最多 $kMaxRemindSlots 个提醒时段';

  /// 任务列表空态引导文案。
  static const emptyList = '还没有任务\n点右下角「新建」添加第一个';
  static const loadFailed = '数据加载失败';

  /// 分组标题上的数量，如「今天 · 3」。
  static String sectionTitle(String title, int count) => '$title · $count';

  static String remindAt(String hm) => '$hm 提醒';

  /// 多时段提醒的展示文本，如「10:30、15:30 提醒」。
  static String remindTimes(List<String> labels) => '${labels.join('、')} 提醒';

  /// 已经过去的提醒时段提示：调度器对过去时刻不会注册通知
  /// （见 reminder_scheduler.dart），必须让用户看见，否则会变成
  /// 「界面写着提醒、系统里一条通知都没排」的静默失效。
  static String remindSlotsPassed(List<String> labels) =>
      '${labels.join('、')} 已经过去，到点不会再提醒；改成还没到的时刻才会通知';

  static String overdueHint(String date) => '逾期（$date）';
}

/// 循环计划模块。
abstract final class CycleStrings {
  static const listTitle = '计划';
  static const createTitle = '新建计划';
  static const editTitle = '编辑计划';
  static const detailTitle = '计划详情';
  static const dayEditTitle = '编辑当天任务';
  static const archivedSection = '已归档';
  static const noCycle = '还没有循环计划';

  static const fieldName = '计划名称';
  static const fieldNameHint = '例如：8 天跑步训练';
  static const fieldPeriodDays = '周期天数';
  static const fieldStartDate = '起始日';
  static const fieldRemindTime = '每日提醒时段';
  static const fieldEndType = '结束方式';
  static const fieldEndCount = '循环次数';
  static const fieldEndDate = '结束日期';
  static const fieldCompleteCyclesOnly = '完整周期结束后停止';

  static const endTypeNever = '永不结束';
  static const endTypeAfterCount = '循环 X 次后结束';
  static const endTypeUntilDate = '到指定日期结束';

  static const statusActive = '进行中';
  static const statusPaused = '已暂停';
  static const statusEnded = '已结束';

  static const actionPause = '暂停';
  static const actionResume = '启用';
  static const actionDuplicate = '复制为新计划';
  static const actionSetRestDay = '设为休息日';
  static const actionCancelRestDay = '取消休息日';
  static const restDay = '休息日';

  static const nameRequired = '请输入计划名称';
  static const periodInvalid = '周期天数需在 1~60 之间';
  static const endDateTooEarly = '结束日期必须晚于起始日';
  static const endCountInvalid = '循环次数至少为 1';
  static const endedCannotResume = '已结束的计划不可继续，可复制成新计划';

  static const deleteConfirmTitle = '删除计划';
  static const deleteConfirmBody = '删除后该计划及其所有任务实例记录都会清除，且无法恢复。';
  static const duplicateSuffix = '（副本）';
  static const neverEnds = '永不结束';
  static const dayListTitle = '每天的任务';
  static const noRemind = '不提醒';
  static const startDateLabel = '起始日';
  static const saveFailed = '保存失败';
  static const remindEveryDay = '每日提醒';
  static const notStarted = '尚未开始';
  static const dailyTaskCount = '每天任务';

  static const scopeTitle = '修改范围';
  static const scopeOnce = '仅本次';
  static const scopeFromNowAll = '以后所有';
  static const scopeOnceHint = '只改今天的任务，不影响周期模板';
  static const scopeAllHint = '修改周期模板，并重算今天起的实例；历史记录不变';

  static String periodDaysValue(int n) => '$n 天周期';

  static String currentDay(int day, int total) => '第 $day / $total 天';

  static String remainingCycles(int n) => '剩余约 $n 轮';

  static String endDateValue(String date) => '$date 结束';

  static String dayLabel(int day) => '第 $day 天';

  static String dayTaskCount(int n) => n == 0 ? '无任务' : '$n 个任务';

  static String endCountValue(int n) => '循环 $n 次后结束';

  static String startDateValue(String date) => '$date 开始';

  static String remindAt(String hm) => '每天 $hm 提醒';

  /// 多时段：如「每天 10:30、15:30 提醒」。
  static String remindTimes(List<String> labels) =>
      '每天 ${labels.join('、')} 提醒';

  static String duplicateName(String name) => '$name$duplicateSuffix';

  static String progressDays(int day, int total) => '第 $day / $total 天';
}

/// 统计模块。
abstract final class StatsStrings {
  static const title = '统计';
  static const sectionToday = '今日';
  static const sectionStreak = '连续打卡';
  static const sectionCycles = '循环计划';
  static const sectionHeatmap = '最近 90 天';
  static const sectionMissed = '未完成记录';

  static const currentStreak = '当前连续';
  static const longestStreak = '最长连续';
  static const noMissedRecord = '还没有未完成记录';
  static const completionRate = '完成率';
  static const taskCountLabel = '任务数';
  static const completedLabel = '已完成';
  static const heatmapLess = '少';
  static const heatmapMore = '多';
  static const noRunningCycle = '还没有进行中的计划';
  static const unknownTask = '已删除的任务';

  static String streakDays(int n) => '$n 天';

  static String todaySummary(int done, int total, int rate) =>
      '任务 $total 个，已完成 $done 个，完成率 $rate%';

  static const todayNoTask = '今天没有任务';

  static String cycleSummary(int day, int total, int rate) =>
      '第 $day/$total 天，本周期完成率 $rate%';

  static String cycleNotStarted(int total) => '第 1/$total 天，本周期暂无记录';

  /// 未完成记录一行的文案：`2026-09-10 跑步：加班，没时间`。
  static String missedLine(String date, String title, String? reason) =>
      '$date $title：'
      '${reason == null || reason.isEmpty ? '未填写原因' : reason}';
}

/// 某天详情。
abstract final class DayStrings {
  static const detailTitle = '某天详情';
  static const noTask = '这天没有任务';
  static const unknownCycle = '不属于任何循环计划';
  static const notThisDay = '不是这一天';
  static const invalidDate = '日期无效';
  static const renameAction = '改名';
  static const renameSheetTitle = '修改任务名称';
  static const renameHint = '任务名称';
  static const scopeTitle = '这次修改的范围';
  static const calendarTitle = '日历视图';
  static const openDayDetail = '查看这天详情';
  static const calendarEntry = '按日历查看';
  static const calendarEntryHint = '在月历上挑一天，看当天安排';

  /// 某天详情里一行任务的来源说明。
  static String cycleOf(String cycleName, int dayIndex, int periodDays) =>
      '$cycleName · 第 $dayIndex/$periodDays 天';

  static String progress(int done, int total) => '已完成 $done / $total';
}

/// 未完成原因模块。
abstract final class ReasonStrings {
  static const sheetTitle = '补充未完成原因';
  static const hint = '可以留空，也可以写点别的';
  static const customLabel = '其他原因';
  static const addReason = '补充原因';
  static const editReason = '修改原因';
  static const noReason = '未填写原因';

  static const quickNoTime = '没时间';
  static const quickUnwell = '身体不适';
  static const quickSomethingCameUp = '临时有事';
  static const quickForgot = '忘记';
  static const quickTooHard = '任务太难';
  static const quickWeather = '天气原因';
  static const quickOther = '其他';

  static String updatedAt(String time) => '更新于 $time';
}

/// 数据管理模块。
abstract final class DataStrings {  static const sectionTitle = '数据管理';
  static const exportTitle = '导出备份';
  static const exportAction = '导出全部数据';
  static const exportHint = '生成 JSON 文件，可保存到本机或分享出去。';
  static const exportSuccess = '导出成功';
  static const exportFailed = '导出失败';
  static const lastBackup = '上次备份';

  static const importTitle = '导入恢复';
  static const importAction = '选择备份文件';
  static const importHint = '从 JSON 备份文件恢复数据。';
  static const importPreviewTitle = '备份内容预览';
  static const importModeTitle = '导入方式';
  static const importModeOverwrite = '覆盖现有数据';
  static const importModeOverwriteHint = '清空当前全部数据，完全按备份恢复';
  static const importModeMerge = '合并到现有数据';
  static const importModeMergeHint = '保留现有数据，同 ID 以更新时间较新的为准';
  static const importConfirm = '确认恢复';
  static const importSuccess = '恢复完成';
  static const importFailed = '恢复失败';

  static const clearTitle = '清空数据';
  static const clearAction = '清空全部数据';
  static const clearConfirmTitle = '清空数据';
  static const clearConfirmBody = '将删除全部任务、计划与历史记录，且无法恢复。建议先导出备份。';
  static const clearDone = '已清空';
  static const clearKeepsSettings = '提醒开关与应用锁等设置会保留。';

  static const saveToFile = '保存到文件';
  static const shareFile = '分享文件';
  static const pickFileFirst = '请先选择备份文件';
  static const chooseMode = '请选择导入方式';
  static const overwriteWarning = '覆盖会清空当前全部任务、计划与记录（设置也会一并替换）。';
  static const emptyBackupWarning = '这份备份里没有任何任务、计划或记录，导入不会带来内容。';
  static const importResultTitle = '导入结果';
  static const dataOverview = '当前数据';
  static const noBackupYet = '还没有备份过';
  static const exportEmptyWarning = '当前没有任何任务、计划或记录，导出的备份是空的。';

  static String dataOverviewLine(int tasks, int cycles, int records) =>
      '任务 $tasks 个 · 计划 $cycles 个 · 记录 $records 条';

  static String savedTo(String path) => '已保存到 $path';

  static String importDone(String summary) => '导入完成：$summary';

  /// 解码失败原因 → 用户可读的中文说明。
  ///
  /// 映射放在 app 层而不是 core：`core` 不该持有界面文案。
  static String backupErrorMessage(BackupError error) {
    switch (error) {
      case BackupError.emptyInput:
        return '文件是空的，请确认选对了备份文件。';
      case BackupError.invalidJson:
        return '文件内容不是合法的 JSON，可能已损坏。';
      case BackupError.notAnObject:
        return '文件格式不对：备份文件的最外层应该是一个对象。';
      case BackupError.unsupportedVersion:
        return '这份备份来自更新版本的应用，请先升级应用再导入。';
    }
  }

  static String previewSummary(int tasks, int cycles, int records) =>
      '包含 $tasks 个任务、$cycles 个计划、$records 条记录';

  static String exportedAt(String time) => '导出时间：$time';

  static String mergeResult(int added, int updated, int kept) =>
      '新增 $added 项，覆盖 $updated 项，保留 $kept 项';
}

/// 设置模块。
abstract final class SettingsStrings {
  static const title = '设置';
  static const sectionReminder = '提醒设置';
  static const sectionStats = '统计';
  static const sectionData = '数据管理';
  static const sectionAbout = '关于';

  static const reminderTitle = '提醒设置';
  static const reminderEntryHint = '总开关、默认提醒时间、循环计划提醒';
  static const reminderEnabled = '开启提醒';
  static const reminderEnabledHint = '关闭后将取消全部已注册的本地通知';
  static const defaultRemindTime = '默认提醒时段';
  static const defaultRemindTimeHint = '在计划里打开提醒时套用的初始时段，可以设多个';
  static const cycleReminderEnabled = '循环计划每日提醒';
  static const cycleReminderEnabledHint = '在计划设置的提醒时段，每天各提醒一次';
  static const reminderUnsupported = '当前平台不支持本地通知';
  static const reminderUnsupportedHint = '提醒功能在 Android 与 Windows 上可用。';
  static const permissionDenied = '通知权限未开启，提醒可能无法送达';
  static const permissionDeniedHint = '请在系统设置里允许本应用发送通知。';
  static const reminderPickTime = '选择默认提醒时段';
  static const reminderSaveFailed = '设置没能保存，请重试';

  /// 「系统调度状态」卡片：回答「提醒到底是没排进系统，还是排进了系统没弹」。
  /// 没有这张卡片时，权限被拒 / ROM 拦截造成的「静默不响」完全无法自查。
  static const reminderStatusTitle = '系统调度状态';
  static const reminderPermissionGranted = '通知权限：已授予';
  static const reminderPermissionMissing = '通知权限：未授予';
  static const reminderExactAlarmMissing = '精确闹钟：未授权，提醒可能延迟几分钟';
  static const reminderBatteryMissing = '省电限制：未加白名单，后台可能被系统清理，提醒会丢';
  static const requestWhitelist = '加入白名单';
  static const reRequestPermission = '重新申请权限';
  static const pendingZero =
      '已排进系统的提醒：0 条 —— 当前没有任何未来提醒，或调度失败了';
  static String pendingCount(int count) => '已排进系统的提醒：$count 条';
  static String pendingTitles(String titles) => '最近几条：$titles';
  static const pendingLoadFailed = '查询系统待发送提醒失败';
  static const refresh = '刷新';

  static const statsEntry = '查看统计';
  static const statsEntryHint = '今日进度、周期进度、连续打卡、热力图';

  static const aboutEntry = '关于与隐私';
  static const aboutEntryHint = '版本信息、数据存储位置与隐私说明';
}

/// 关于 / 隐私说明页（任务 8.10）。
abstract final class AboutStrings {
  static const title = '关于与隐私';

  /// 一句话定位。
  static const positioning = '无登录、无账号、本地优先的待办与循环计划应用';

  static String version(String value) => '版本 $value';

  static const storageTitle = '数据存储位置';
  static const storageHint = '任务、计划、记录与设置都只保存在这一个文件里。';
  static const storageUnknown = '暂时读不到路径（不影响正常使用）';
  static const storageDirectoryLabel = '目录';
  static const storageFileLabel = '文件';

  static const privacyTitle = '隐私说明';
  static const privacyPoints = [
    '没有登录、没有账号、没有服务器。',
    '所有数据只保存在本机，不会上传云端。',
    '没有统计上报，也不含任何第三方分析 SDK。',
    '导出的 JSON 备份包含未完成原因，请自行妥善保管。',
  ];
}

/// 本地通知文案（任务 8.1 ~ 8.5）。
///
/// 通知内容由 `services/reminder_scheduler.dart` 在调度时算好，
/// 文案集中放这里，理由和模型层一样：**模型/服务不写中文**。
abstract final class ReminderStrings {
  /// 通知里展示的应用名（Windows 的 Toast 需要）。
  static const appName = '循环小岛';

  /// Android 通知渠道。
  static const channelId = 'loop_island_reminders';
  static const channelName = '到点提醒';
  static const channelDescription = '普通任务与循环计划的本地提醒';

  /// 普通任务提醒的正文（标题用任务标题）。
  static const taskBody = '到点啦，该做这件事了';

  /// 循环计划每日提醒的正文。
  ///
  /// 多时段时补上「第 x/N 次提醒」，用户才分得清这条是今天的哪一次。
  static String cycleDayBody(
    int dayIndex,
    int periodDays, {
    int slotIndex = 1,
    int slotCount = 1,
  }) {
    final base = '今天是第 $dayIndex/$periodDays 天';
    if (slotCount <= 1) {
      return base;
    }
    return '$base（第 $slotIndex/$slotCount 次提醒）';
  }
}

/// 启动引导。
abstract final class BootStrings {
  static const storageErrorTitle = '无法打开本地数据';
  static const storageErrorBody = '应用的数据只保存在本机，需要能读写本地文件才能启动。\n'
      '请确认设备存储空间充足、且未限制本应用的存储权限，然后重试。';
  static const storageErrorDetail = '错误详情：';
  static const storageRetry = '重试';
}

/// 路由占位与错误文案。
abstract final class RouteStrings {
  static const notFound = '页面不存在';
  static const underConstruction = '该页面正在开发中';
}
