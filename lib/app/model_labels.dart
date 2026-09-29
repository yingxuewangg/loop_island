/// 模型枚举 → 中文文案的映射。
///
/// 单独成文件的原因：`lib/models/` 必须保持零 UI 依赖（否则 models 层会被
/// 文案绑死、也无法脱离 Flutter 单测），但界面又需要「pending → 待办」这种映射。
/// 把扩展放在 app 层，`features → app → models` 的依赖方向就干净了。
library;

import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/design_tokens.dart';

/// 任务状态文案。
extension TaskStatusLabel on TaskStatus {
  String get statusLabel => switch (this) {
        TaskStatus.pending => StatusLabels.pending,
        TaskStatus.completed => StatusLabels.completed,
        TaskStatus.skipped => StatusLabels.skipped,
        TaskStatus.missed => StatusLabels.missed,
      };

  /// 状态对应的标签配色（「循环小岛」色彩系统 semantic 段）。
  ///
  /// 收在这里而不是散在各界面的原因：同一个状态在任务列表、某天详情、
  /// 历史记录、日历视图等**五处**都要显示，各写一份必然出现
  /// 「同一状态两处颜色不一样」。
  TagColors get statusColors => switch (this) {
        TaskStatus.pending => IslandTagColors.pending,
        TaskStatus.completed => IslandTagColors.done,
        TaskStatus.skipped => IslandTagColors.skipped,
        TaskStatus.missed => IslandTagColors.missed,
      };
}

/// 任务日期类型文案。
extension TaskDateTypeLabel on TaskDateType {
  String get dateTypeLabel => switch (this) {
        TaskDateType.today => DateTypeLabels.today,
        TaskDateType.tomorrow => DateTypeLabels.tomorrow,
        TaskDateType.custom => DateTypeLabels.custom,
        TaskDateType.none => DateTypeLabels.none,
      };
}

/// 循环计划状态文案。
extension CycleStatusLabel on CycleStatus {
  String get cycleStatusLabel => switch (this) {
        CycleStatus.active => CycleStrings.statusActive,
        CycleStatus.paused => CycleStrings.statusPaused,
        CycleStatus.ended => CycleStrings.statusEnded,
      };

  /// 计划状态配色：进行中=品牌色，已暂停=沙洲金，已归档=中性。
  TagColors get cycleStatusColors => switch (this) {
        CycleStatus.active => IslandTagColors.plan,
        CycleStatus.paused => IslandTagColors.skipped,
        CycleStatus.ended => IslandTagColors.archived,
      };
}

/// 循环计划结束方式文案。
extension CycleEndTypeLabel on CycleEndType {
  String get endTypeLabel => switch (this) {
        CycleEndType.never => CycleStrings.endTypeNever,
        CycleEndType.afterCount => CycleStrings.endTypeAfterCount,
        CycleEndType.untilDate => CycleStrings.endTypeUntilDate,
      };
}

/// 修改作用域文案。
extension EditScopeLabel on EditScope {
  String get editScopeLabel => switch (this) {
        EditScope.once => CycleStrings.scopeOnce,
        EditScope.fromNowAll => CycleStrings.scopeFromNowAll,
      };
}
