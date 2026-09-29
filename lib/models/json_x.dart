/// JSON 读写工具（纯 Dart，不依赖 Flutter）。
///
/// 设计目标：**任何脏数据都不能让 `fromJson` 抛异常**。
/// 备份文件可能被手工编辑、被旧版本写入、或字段被删掉，
/// 因此所有读取都带默认值，类型不符即回落默认值。
library;

import 'package:collection/collection.dart';
import 'package:loop_island/core/date_x.dart';

/// `copyWith` 用的哨兵值：区分「不传该参数」与「显式传 null 以清空字段」。
///
/// 用法：`copyWith({Object? date = kUnset})`，内部判断
/// `identical(date, kUnset) ? this.date : date as DateTime?`。
const Object kUnset = Object();

const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

/// 基于 JSON 结构的值相等。
///
/// 所有模型统一用它实现 `operator ==`，好处是**相等性与序列化结果严格一致**：
/// 两个模型相等 ⇔ 它们写出的 JSON 相同，序列化往返测试因此才有意义。
bool jsonEquals(Object? a, Object? b) => _deepEquality.equals(a, b);

/// 与 [jsonEquals] 配套的哈希。
int jsonHash(Object? value) => _deepEquality.hash(value);

/// 读取字符串；缺失 / 类型不符 / null 都回落 [fallback]。
String readStr(Map<String, dynamic> json, String key, {String fallback = ''}) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

/// 读取可空字符串；空串也按 `null` 处理，避免「空字符串」与「未设置」两种状态。
String? readStrOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

/// 读取整数；类型不符时尝试从字符串解析，再回落 [fallback]。
int readInt(Map<String, dynamic> json, String key, {int fallback = 0}) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

/// 读取可空整数。
int? readIntOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

/// 读取布尔；兼容 `1/0`、`"true"/"false"` 等写法。
bool readBool(Map<String, dynamic> json, String key, {bool fallback = false}) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return fallback;
}

/// 读取 `yyyy-MM-dd` 日历日；非法或缺失返回 `null`。
DateTime? readDay(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    return parseDayKey(value);
  }
  return null;
}

/// 读取时间点（存的是 UTC ISO 串），返回本地时间。
DateTime? readInstant(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

/// 读取时间点列表（多时段提醒用）；非列表返回空列表，坏元素跳过。
List<DateTime> readInstantList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    return const [];
  }
  final result = <DateTime>[];
  for (final item in value) {
    if (item is! String || item.isEmpty) {
      continue;
    }
    final parsed = DateTime.tryParse(item);
    if (parsed != null) {
      result.add(parsed.toLocal());
    }
  }
  return result;
}

/// 读取对象列表；非列表或元素非对象时跳过该元素。
List<Map<String, dynamic>> readMapList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map>().map((e) {
    return e.map((k, v) => MapEntry(k.toString(), v));
  }).toList(growable: false);
}

/// 读取嵌套对象。
Map<String, dynamic> readMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const {};
}

/// 写入日历日：`yyyy-MM-dd`，null 原样写 null。
String? writeDay(DateTime? value) => value == null ? null : dayKey(value);

/// 写入时间点：UTC ISO 串（带 `Z`）。
///
/// 用 UTC 而非本地时间，保证备份文件跨时区导入后仍是同一时刻。
String? writeInstant(DateTime? value) => value?.toUtc().toIso8601String();

/// 写入时间点列表（`writeInstant` 的列表版本）。
List<String?> writeInstantList(List<DateTime> values) =>
    values.map(writeInstant).toList(growable: false);

