import 'package:uuid/uuid.dart';

/// 各类实体的 ID 前缀。
///
/// 前缀让 ID 自带类型信息，便于在导出 JSON 中肉眼排查、
/// 也方便从 `taskId` 直接判断该去哪个集合查找。
abstract final class IdPrefix {
  /// 普通任务。
  static const task = 'task';

  /// 循环计划。
  static const cycle = 'cycle';

  /// 周期内某天的任务模板。
  static const cycleTask = 'ctask';

  /// 某一天的任务实例记录。
  static const record = 'record';
}

const Uuid _uuid = Uuid();

/// 生成带前缀的唯一 ID，形如 `task_3f1c...`。
///
/// 用 v4 随机 UUID 而非自增，避免导入合并时主键冲突。
String newId(String prefix) => '${prefix}_${_uuid.v4()}';

/// 便捷方法：新建普通任务 ID。
String newTaskId() => newId(IdPrefix.task);

/// 便捷方法：新建循环计划 ID。
String newCycleId() => newId(IdPrefix.cycle);

/// 便捷方法：新建周期内任务模板 ID。
String newCycleTaskId() => newId(IdPrefix.cycleTask);

/// 便捷方法：新建任务实例记录 ID。
String newRecordId() => newId(IdPrefix.record);

/// 从 ID 中取出前缀（无下划线时返回整个字符串）。
String idPrefixOf(String id) {
  final index = id.indexOf('_');
  return index <= 0 ? id : id.substring(0, index);
}
