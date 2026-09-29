import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/ids.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:meta/meta.dart';

import 'enums.dart';
import 'json_x.dart';

/// 把「一天内分钟数」夹到合法区间；null 原样返回。
int? _clampMinute(int? value) {
  if (value == null) {
    return null;
  }
  return value.clamp(0, minutesPerDay - 1);
}

/// 周期内某一天的一个任务模板。
///
/// 与 `Task` 的区别：模板**没有具体日期**，它靠「周期的第几天」定位。
/// 因此提醒时间是「一天内的时刻」而不是绝对时间点 —— 用 `DateTime`
/// 存会在下一轮循环时变成过去的时刻，必然失效。
@immutable
class CycleTaskTemplate {
  const CycleTaskTemplate({
    required this.id,
    required this.title,
    this.note = '',
    this.remindMinuteOfDay,
    this.order = 0,
    required this.updatedAt,
  });

  /// 新建模板。
  factory CycleTaskTemplate.create({
    required String title,
    String note = '',
    int? remindMinuteOfDay,
    int order = 0,
    DateTime? now,
  }) {
    return CycleTaskTemplate(
      id: newCycleTaskId(),
      title: title,
      note: note,
      remindMinuteOfDay: remindMinuteOfDay,
      order: order,
      updatedAt: now ?? DateTime.now(),
    );
  }

  factory CycleTaskTemplate.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    return CycleTaskTemplate(
      id: readStr(json, 'id'),
      title: readStr(json, 'title'),
      note: readStr(json, 'note'),
      remindMinuteOfDay: _clampMinute(readIntOrNull(json, 'remindMinuteOfDay')),
      order: readInt(json, 'order'),
      updatedAt: readInstant(json, 'updatedAt') ?? now ?? DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String note;

  /// 提醒时刻（一天内分钟数 0..1439），null 表示不提醒。
  final int? remindMinuteOfDay;

  /// 当天内的排序序号，越小越靠前。
  final int order;

  final DateTime updatedAt;

  /// 提醒时间的 `HH:mm` 展示文本；无提醒返回 null。
  String? get remindLabel {
    final minute = remindMinuteOfDay;
    return minute == null ? null : formatMinuteOfDay(minute);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'remindMinuteOfDay': remindMinuteOfDay,
        'order': order,
        'updatedAt': writeInstant(updatedAt),
      };

  CycleTaskTemplate copyWith({
    String? id,
    String? title,
    String? note,
    Object? remindMinuteOfDay = kUnset,
    int? order,
    DateTime? updatedAt,
  }) {
    return CycleTaskTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      remindMinuteOfDay: identical(remindMinuteOfDay, kUnset)
          ? this.remindMinuteOfDay
          : _clampMinute(remindMinuteOfDay as int?),
      order: order ?? this.order,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CycleTaskTemplate && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => 'CycleTaskTemplate($id, $title, order=$order)';
}

/// 周期内的第 [dayIndex] 天（从 1 开始）。
@immutable
class CycleDay {
  const CycleDay({
    required this.dayIndex,
    this.isRestDay = false,
    this.templates = const [],
  });

  factory CycleDay.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final templates = readMapList(json, 'templates')
        .map((item) => CycleTaskTemplate.fromJson(item, now: now))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return CycleDay(
      dayIndex: readInt(json, 'dayIndex', fallback: 1),
      isRestDay: readBool(json, 'isRestDay'),
      templates: List.unmodifiable(templates),
    );
  }

  /// 空白天（无任务、非休息日）。
  factory CycleDay.empty(int dayIndex) => CycleDay(dayIndex: dayIndex);

  final int dayIndex;
  final bool isRestDay;
  final List<CycleTaskTemplate> templates;

  /// 是否没有任何任务。
  bool get isEmpty => templates.isEmpty;

  /// 任务数量。
  int get taskCount => templates.length;

  /// 是否实际有内容（有任务，或显式标记为休息日）。
  bool get hasContent => isRestDay || templates.isNotEmpty;

  /// 按 [order] 排序后的模板（保证展示顺序稳定）。
  List<CycleTaskTemplate> get sortedTemplates {
    final sorted = [...templates]..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(sorted);
  }

  Map<String, dynamic> toJson() => {
        'dayIndex': dayIndex,
        'isRestDay': isRestDay,
        'templates': sortedTemplates.map((e) => e.toJson()).toList(),
      };

  CycleDay copyWith({
    int? dayIndex,
    bool? isRestDay,
    List<CycleTaskTemplate>? templates,
  }) {
    return CycleDay(
      dayIndex: dayIndex ?? this.dayIndex,
      isRestDay: isRestDay ?? this.isRestDay,
      templates: templates ?? this.templates,
    );
  }

  /// 追加一个任务模板，`order` 自动排到末尾。
  CycleDay addTemplate(CycleTaskTemplate template) {
    return copyWith(
      templates: List.unmodifiable([
        ...templates,
        template.copyWith(order: templates.length),
      ]),
    );
  }

  /// 移除指定 id 的任务模板，并重排 `order` 保持连续。
  CycleDay removeTemplate(String templateId) {
    final remaining = templates.where((e) => e.id != templateId).toList();
    return copyWith(templates: _reorder(remaining));
  }

  /// 更新指定 id 的任务模板。
  CycleDay updateTemplate(CycleTaskTemplate template) {
    final updated = templates
        .map((e) => e.id == template.id ? template : e)
        .toList(growable: false);
    return copyWith(templates: List.unmodifiable(updated));
  }

  /// 把任务从 [from] 位置移动到 [to] 位置。
  CycleDay moveTemplate(int from, int to) {
    final sorted = [...sortedTemplates];
    if (from < 0 || from >= sorted.length) {
      return this;
    }
    final target = to.clamp(0, sorted.length - 1);
    final item = sorted.removeAt(from);
    sorted.insert(target, item);
    return copyWith(templates: _reorder(sorted));
  }

  static List<CycleTaskTemplate> _reorder(List<CycleTaskTemplate> items) {
    return List.unmodifiable([
      for (var i = 0; i < items.length; i++) items[i].copyWith(order: i),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CycleDay && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() =>
      'CycleDay($dayIndex, rest=$isRestDay, tasks=${templates.length})';
}

/// 循环计划：以 [periodDays] 天为一个周期，第 1..N 天各有任务定义。
@immutable
class Cycle {
  const Cycle({
    required this.id,
    required this.name,
    required this.periodDays,
    required this.startDate,
    this.endType = CycleEndType.never,
    this.endDate,
    this.endCount,
    this.completeCyclesOnly = false,
    this.status = CycleStatus.active,
    this.endedAt,
    this.remindMinutesOfDay = const [],
    this.days = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 新建计划：自动铺满第 1..N 天的空白天。
  factory Cycle.create({
    required String name,
    required int periodDays,
    required DateTime startDate,
    CycleEndType endType = CycleEndType.never,
    DateTime? endDate,
    int? endCount,
    bool completeCyclesOnly = false,
    int? remindMinuteOfDay,
    List<int>? remindMinutesOfDay,
    DateTime? now,
  }) {
    final normalizedDays = periodDays.clamp(1, 365);
    final timestamp = now ?? DateTime.now();
    return Cycle(
      id: newCycleId(),
      name: name,
      periodDays: normalizedDays,
      startDate: dateOnly(startDate),
      endType: endType,
      endDate: endDate == null ? null : dateOnly(endDate),
      endCount: endCount,
      completeCyclesOnly: completeCyclesOnly,
      remindMinutesOfDay: normalizeMinuteSlots(
        remindMinutesOfDay ?? (remindMinuteOfDay == null ? const [] : [remindMinuteOfDay]),
      ),
      days: List.unmodifiable([
        for (var i = 1; i <= normalizedDays; i++) CycleDay.empty(i),
      ]),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// 从 JSON 还原，并**修复结构不变量**：`days` 一定补齐到 `periodDays` 天。
  factory Cycle.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final fallbackNow = now ?? DateTime.now();
    final periodDays = readInt(json, 'periodDays', fallback: 1).clamp(1, 365);

    // 按 dayIndex 建索引，顺带丢弃越界与重复项
    final byIndex = <int, CycleDay>{};
    for (final item in readMapList(json, 'days')) {
      final day = CycleDay.fromJson(item, now: fallbackNow);
      if (day.dayIndex >= 1 && day.dayIndex <= periodDays) {
        byIndex[day.dayIndex] = day;
      }
    }

    final startDate = readDay(json, 'startDate') ?? dateOnly(fallbackNow);

    return Cycle(
      id: readStr(json, 'id'),
      name: readStr(json, 'name'),
      periodDays: periodDays,
      startDate: startDate,
      endType: CycleEndType.parse(readStrOrNull(json, 'endType')),
      endDate: readDay(json, 'endDate'),
      endCount: readIntOrNull(json, 'endCount'),
      completeCyclesOnly: readBool(json, 'completeCyclesOnly'),
      status: CycleStatus.parse(readStrOrNull(json, 'status')),
      endedAt: readInstant(json, 'endedAt'),
      remindMinutesOfDay: _readRemindMinutes(json),
      days: List.unmodifiable([
        for (var i = 1; i <= periodDays; i++)
          byIndex[i] ?? CycleDay.empty(i),
      ]),
      createdAt: readInstant(json, 'createdAt') ?? fallbackNow,
      updatedAt: readInstant(json, 'updatedAt') ?? fallbackNow,
    );
  }

  final String id;
  final String name;

  /// 周期天数 N。
  final int periodDays;

  /// 起始日（本地日历日）。
  final DateTime startDate;

  final CycleEndType endType;

  /// 结束日期；仅 [CycleEndType.untilDate] 时有值。
  final DateTime? endDate;

  /// 循环次数；仅 [CycleEndType.afterCount] 时有值。
  final int? endCount;

  /// 是否「完整周期结束后停止」（PRD §七）。
  final bool completeCyclesOnly;

  final CycleStatus status;

  /// 实际结束时间（自动归档或手动结束时写入）。
  final DateTime? endedAt;

  /// 每日提醒时段（一天内分钟数，升序去重，最多 [kMaxRemindSlots] 个）；
  /// 空表示不提醒。
  final List<int> remindMinutesOfDay;

  /// 最早的每日提醒时刻；没有提醒时为 null。
  ///
  /// 与 `Task.remindAt` 同理：排序 / 单行展示只需要第一个。
  int? get remindMinuteOfDay =>
      remindMinutesOfDay.isEmpty ? null : remindMinutesOfDay.first;

  /// 第 1..[periodDays] 天的定义，长度恒等于 [periodDays]。
  final List<CycleDay> days;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 计划是否仍在产生任务实例。
  bool get isRunning => status == CycleStatus.active;

  /// 计划是否已结束（含「按结束条件判定已到期但尚未落库」的情况由引擎处理）。
  bool get isEnded => status == CycleStatus.ended;

  /// 取第 [dayIndex] 天；越界返回当天编号的空白天（不抛异常）。
  CycleDay dayAt(int dayIndex) {
    if (dayIndex < 1 || dayIndex > days.length) {
      return CycleDay.empty(dayIndex);
    }
    return days[dayIndex - 1];
  }

  /// 每日提醒的 `HH:mm` 展示文本（多个时段用「、」连接）；无提醒返回 null。
  String? get remindLabel {
    if (remindMinutesOfDay.isEmpty) {
      return null;
    }
    return formatMinuteSlots(remindMinutesOfDay).join('、');
  }

  /// 所有非空白天（有任务或休息日）。
  List<CycleDay> get contentDays =>
      days.where((e) => e.hasContent).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'periodDays': periodDays,
        'startDate': writeDay(startDate),
        'endType': endType.wireName,
        'endDate': writeDay(endDate),
        'endCount': endCount,
        'completeCyclesOnly': completeCyclesOnly,
        'status': status.wireName,
        'endedAt': writeInstant(endedAt),
        'remindMinutesOfDay': remindMinutesOfDay,
        'days': List.unmodifiable(
          [for (var i = 1; i <= periodDays; i++) dayAt(i).toJson()],
        ),
        'createdAt': writeInstant(createdAt),
        'updatedAt': writeInstant(updatedAt),
      };

  Cycle copyWith({
    String? id,
    String? name,
    int? periodDays,
    DateTime? startDate,
    CycleEndType? endType,
    Object? endDate = kUnset,
    Object? endCount = kUnset,
    bool? completeCyclesOnly,
    CycleStatus? status,
    Object? endedAt = kUnset,
    Object? remindMinutesOfDay = kUnset,
    Object? remindMinuteOfDay = kUnset,
    List<CycleDay>? days,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextPeriodDays = (periodDays ?? this.periodDays).clamp(1, 365);
    final nextDays = days ?? this.days;

    return Cycle(
      id: id ?? this.id,
      name: name ?? this.name,
      periodDays: nextPeriodDays,
      startDate: startDate == null ? this.startDate : dateOnly(startDate),
      endType: endType ?? this.endType,
      endDate: identical(endDate, kUnset)
          ? this.endDate
          : (endDate == null ? null : dateOnly(endDate as DateTime)),
      endCount:
          identical(endCount, kUnset) ? this.endCount : endCount as int?,
      completeCyclesOnly: completeCyclesOnly ?? this.completeCyclesOnly,
      status: status ?? this.status,
      endedAt:
          identical(endedAt, kUnset) ? this.endedAt : endedAt as DateTime?,
      remindMinutesOfDay: _resolveRemindMinutes(
        remindMinutesOfDay: remindMinutesOfDay,
        remindMinuteOfDay: remindMinuteOfDay,
      ),
      days: _normalizeDays(nextDays, nextPeriodDays),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 解析 [copyWith] 的两个提醒参数：正式接口是列表，单值是便捷写法。
  List<int> _resolveRemindMinutes({
    required Object? remindMinutesOfDay,
    required Object? remindMinuteOfDay,
  }) {
    if (!identical(remindMinutesOfDay, kUnset)) {
      return remindMinutesOfDay == null
          ? const []
          : normalizeMinuteSlots(remindMinutesOfDay as Iterable<int>);
    }
    if (identical(remindMinuteOfDay, kUnset)) {
      return this.remindMinutesOfDay;
    }
    final single = remindMinuteOfDay as int?;
    return single == null ? const [] : normalizeMinuteSlots([single]);
  }

  /// 替换第 [dayIndex] 天的定义（越界自动扩容到该天）。
  Cycle withDay(CycleDay day) {
    final needed = day.dayIndex > periodDays ? day.dayIndex : periodDays;
    final rebuilt = <CycleDay>[];
    for (var i = 1; i <= needed; i++) {
      if (i == day.dayIndex) {
        rebuilt.add(day.copyWith(dayIndex: i));
      } else {
        rebuilt.add(dayAt(i));
      }
    }
    return copyWith(periodDays: needed, days: rebuilt);
  }

  /// 保证 `days` 长度与 [periodDays] 一致：缺的补空白天，多的截断。
  static List<CycleDay> _normalizeDays(List<CycleDay> days, int periodDays) {
    return List.unmodifiable([
      for (var i = 1; i <= periodDays; i++)
        i <= days.length ? days[i - 1].copyWith(dayIndex: i) : CycleDay.empty(i),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cycle && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() =>
      'Cycle($id, $name, $periodDays天, ${status.wireName}, '
      '${endType.wireName})';
}

/// 读取每日提醒时段，并兼容「只有一个 `remindMinuteOfDay`」的老备份。
///
/// 与 `Task._readRemindAts` 同一套思路：优先新键，新键缺失才把老键包成
/// 单元素列表，老备份因此无需迁移脚本即可升级。
List<int> _readRemindMinutes(Map<String, dynamic> json) {
  final raw = json['remindMinutesOfDay'];
  if (raw is List && raw.isNotEmpty) {
    final minutes = <int>[];
    for (final item in raw) {
      if (item is int) {
        minutes.add(item);
      } else if (item is double) {
        minutes.add(item.toInt());
      } else if (item is String) {
        final parsed = int.tryParse(item.trim());
        if (parsed != null) {
          minutes.add(parsed);
        }
      }
    }
    if (minutes.isNotEmpty) {
      return normalizeMinuteSlots(minutes);
    }
  }
  final legacy = readIntOrNull(json, 'remindMinuteOfDay');
  return legacy == null ? const [] : normalizeMinuteSlots([legacy]);
}
