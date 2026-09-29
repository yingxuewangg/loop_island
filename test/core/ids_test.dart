import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/core/ids.dart';

void main() {
  group('newId', () {
    test('带前缀，格式为 <prefix>_<uuid>', () {
      final id = newId('task');
      expect(id.startsWith('task_'), isTrue);
      expect(id.length, greaterThan('task_'.length + 30));
    });

    test('1000 次生成无重复', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(newId('task'));
      }
      expect(ids.length, 1000);
    });

    test('不同前缀互不干扰', () {
      expect(newId('task').startsWith('task_'), isTrue);
      expect(newId('cycle').startsWith('cycle_'), isTrue);
    });

    test('空前缀也合法（退化为纯 uuid）', () {
      final id = newId('');
      expect(id.startsWith('_'), isTrue);
    });
  });

  group('便捷方法与前缀常量', () {
    test('各便捷方法使用对应前缀', () {
      expect(idPrefixOf(newTaskId()), IdPrefix.task);
      expect(idPrefixOf(newCycleId()), IdPrefix.cycle);
      expect(idPrefixOf(newCycleTaskId()), IdPrefix.cycleTask);
      expect(idPrefixOf(newRecordId()), IdPrefix.record);
    });

    test('idPrefixOf 容错', () {
      expect(idPrefixOf('no-underscore'), 'no-underscore');
      expect(idPrefixOf('_leading'), '_leading');
      expect(idPrefixOf('task_abc'), 'task');
    });
  });
}
