import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/models/json_x.dart';

void main() {
  group('readStr', () {
    test('正常读取', () {
      expect(readStr({'a': 'x'}, 'a'), 'x');
    });

    test('缺失 / null / 类型不符回落默认值', () {
      expect(readStr({}, 'a'), '');
      expect(readStr({'a': null}, 'a'), '');
      expect(readStr({'a': null}, 'a', fallback: 'd'), 'd');
      expect(readStr({'a': 123}, 'a'), '123');
      expect(readStr({'a': true}, 'a'), 'true');
      expect(readStr({'a': <String>[]}, 'a'), '[]');
    });
  });

  group('readStrOrNull', () {
    test('空串按 null 处理（统一「未设置」语义）', () {
      expect(readStrOrNull({'a': ''}, 'a'), isNull);
      expect(readStrOrNull({'a': '  '}, 'a'), '  ', reason: '空白串不是空串');
      expect(readStrOrNull({'a': 'x'}, 'a'), 'x');
      expect(readStrOrNull({}, 'a'), isNull);
      expect(readStrOrNull({'a': null}, 'a'), isNull);
    });

    test('数字与布尔转为字符串', () {
      expect(readStrOrNull({'a': 5}, 'a'), '5');
      expect(readStrOrNull({'a': true}, 'a'), 'true');
      expect(readStrOrNull({'a': <String>[]}, 'a'), isNull);
    });
  });

  group('readInt / readIntOrNull', () {
    test('正常与兼容类型', () {
      expect(readInt({'a': 7}, 'a'), 7);
      expect(readInt({'a': 7.9}, 'a'), 7, reason: 'double 截断');
      expect(readInt({'a': '42'}, 'a'), 42, reason: '字符串解析');
      expect(readInt({'a': ' 42 '}, 'a'), 42, reason: '容忍空白');
    });

    test('非法输入回落', () {
      expect(readInt({}, 'a'), 0);
      expect(readInt({'a': null}, 'a'), 0);
      expect(readInt({'a': 'abc'}, 'a'), 0, reason: '默认 fallback 为 0');
      expect(readInt({'a': 'abc'}, 'a', fallback: -1), -1);
      expect(readInt({'a': true}, 'a'), 0);
    });

    test('readIntOrNull 无默认值', () {
      expect(readIntOrNull({'a': 3}, 'a'), 3);
      expect(readIntOrNull({'a': '3'}, 'a'), 3);
      expect(readIntOrNull({}, 'a'), isNull);
      expect(readIntOrNull({'a': 'abc'}, 'a'), isNull);
    });
  });

  group('readBool', () {
    test('原生布尔', () {
      expect(readBool({'a': true}, 'a'), isTrue);
      expect(readBool({'a': false}, 'a'), isFalse);
    });

    test('数字与字符串兼容写法', () {
      expect(readBool({'a': 1}, 'a'), isTrue);
      expect(readBool({'a': 0}, 'a'), isFalse);
      expect(readBool({'a': 'true'}, 'a'), isTrue);
      expect(readBool({'a': 'TRUE'}, 'a'), isTrue);
      expect(readBool({'a': '1'}, 'a'), isTrue);
      expect(readBool({'a': 'false'}, 'a'), isFalse);
      expect(readBool({'a': '0'}, 'a'), isFalse);
    });

    test('无法识别时回落', () {
      expect(readBool({'a': 'yes'}, 'a'), isFalse);
      expect(readBool({'a': 'yes'}, 'a', fallback: true), isTrue);
      expect(readBool({}, 'a'), isFalse);
      expect(readBool({'a': null}, 'a'), isFalse);
      expect(readBool({'a': <String>[]}, 'a'), isFalse);
    });
  });

  group('readDay / writeDay', () {
    test('读取合法日期键', () {
      expect(dayKey(readDay({'d': '2026-09-12'}, 'd')!), '2026-09-12');
    });

    test('非法日期键返回 null', () {
      expect(readDay({'d': '2026-02-30'}, 'd'), isNull);
      expect(readDay({'d': 'oops'}, 'd'), isNull);
      expect(readDay({'d': 20260912}, 'd'), isNull, reason: '只接受字符串');
      expect(readDay({}, 'd'), isNull);
    });

    test('writeDay 输出 yyyy-MM-dd，null 原样', () {
      expect(writeDay(DateTime(2026, 9, 12, 20, 30)), '2026-09-12');
      expect(writeDay(null), isNull);
    });
  });

  group('readInstant / writeInstant', () {
    test('写入 UTC ISO 串以便跨时区还原同一时刻', () {
      final local = DateTime(2026, 9, 12, 20, 30, 15);
      final written = writeInstant(local)!;
      expect(written.endsWith('Z'), isTrue);
      expect(writeInstant(null), isNull);
    });

    test('往返保持同一时刻', () {
      final local = DateTime(2026, 9, 12, 20, 30, 15, 123);
      final restored = readInstant({'t': writeInstant(local)}, 't')!;
      expect(restored.isAtSameMomentAs(local), isTrue);
      expect(restored.isUtc, isFalse, reason: '读回来应是本地时间');
    });

    test('非法输入返回 null', () {
      expect(readInstant({'t': 'nope'}, 't'), isNull);
      expect(readInstant({'t': ''}, 't'), isNull);
      expect(readInstant({'t': 123}, 't'), isNull);
      expect(readInstant({}, 't'), isNull);
    });
  });

  group('readMapList / readMap', () {
    test('读取对象列表', () {
      final result = readMapList({
        'items': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      }, 'items');
      expect(result.length, 2);
      expect(result.first['id'], 'a');
    });

    test('跳过非对象元素，非列表返回空', () {
      final result = readMapList({
        'items': [
          {'id': 'a'},
          'oops',
          42,
          null,
          {'id': 'b'},
        ],
      }, 'items');
      expect(result.length, 2);
      expect(result.map((e) => e['id']).toList(), ['a', 'b']);

      expect(readMapList({'items': 'nope'}, 'items'), isEmpty);
      expect(readMapList({}, 'items'), isEmpty);
      expect(readMapList({'items': null}, 'items'), isEmpty);
    });

    test('键统一转字符串', () {
      final result = readMapList({
        'items': [
          {1: 'a'},
        ],
      }, 'items');
      expect(result.single['1'], 'a');
    });

    test('readMap', () {
      expect(readMap({'o': {'k': 1}}, 'o')['k'], 1);
      expect(readMap({'o': 'nope'}, 'o'), isEmpty);
      expect(readMap({}, 'o'), isEmpty);
    });
  });

  group('kUnset 哨兵', () {
    test('是唯一的常量对象，可用于 copyWith 区分「未传」与「显式 null」', () {
      const a = kUnset;
      const b = kUnset;
      expect(identical(a, b), isTrue);
      expect(identical(a, Object()), isFalse);
    });
  });
}
