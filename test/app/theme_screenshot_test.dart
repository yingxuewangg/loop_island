// 「海岛蓝」主题视觉验收截图：离屏渲染四个 Tab，输出 PNG 到
// build/theme_shots/ 供人工查看。
//
// 运行方式（带环境开关，不随日常测试执行）：
//   THEME_SHOTS=1 flutter test test/app/theme_screenshot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';

import '../support/factories.dart';
import '../support/pump_app.dart';

void main() {
  // 仅在显式要求时生成截图；平时 `flutter test` 跳过。
  final enabled = Platform.environment['THEME_SHOTS'] == '1';

  testWidgets('生成「海岛蓝」主题的四 Tab 截图', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime(2026, 9, 26);
    final data = AppData(
      tasks: [
        makeTask(
          id: 'task_1',
          title: '写周报',
          dateType: TaskDateType.custom,
          date: today,
          remindAt: DateTime(2026, 9, 26, 18),
        ),
        makeTask(
          id: 'task_2',
          title: '晨跑 3 公里',
          dateType: TaskDateType.custom,
          date: today,
          status: TaskStatus.completed,
        ),
        makeTask(
          id: 'task_3',
          title: '整理房间',
          dateType: TaskDateType.custom,
          date: today,
          status: TaskStatus.missed,
        ),
        makeTask(
          id: 'task_4',
          title: '采购下周食材',
          dateType: TaskDateType.custom,
          date: today,
          status: TaskStatus.skipped,
        ),
        makeTask(
          id: 'task_5',
          title: '明天的读书会',
          dateType: TaskDateType.tomorrow,
          remindAt: DateTime(2026, 9, 27, 14),
        ),
      ],
      cycles: [
        makeCycle(
          id: 'cycle_1',
          name: '8 天跑步训练',
          periodDays: 8,
          startDate: today,
          remindMinutesOfDay: const [9 * 60],
          days: [
            makeCycleDay(
              dayIndex: 1,
              templates: [makeCycleTemplate(remindMinuteOfDay: 7 * 60 + 30)],
            ),
          ],
        ),
      ],
    );

    await pumpLoopIslandApp(
      tester,
      data: data,
      today: today,
      now: DateTime(2026, 9, 26, 10),
    );

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        final renderView = WidgetsBinding.instance.renderViews.first;
        final layer = renderView.debugLayer! as OffsetLayer;
        final image = await layer.toImage(
          Offset.zero & renderView.size,
          pixelRatio: 2.0,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/theme_shots');
        await dir.create(recursive: true);
        File('${dir.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        // ignore: avoid_print
        print('SCREENSHOT build/theme_shots/$name.png');
      });
    }

    await shot('01-today');
    await tester.tap(find.text(TabLabels.tasks).last);
    await tester.pumpAndSettle();
    await shot('02-tasks');
    await tester.tap(find.text(TabLabels.cycles).last);
    await tester.pumpAndSettle();
    await shot('03-cycles');
    await tester.tap(find.text(TabLabels.settings).last);
    await tester.pumpAndSettle();
    await shot('04-settings');
  }, skip: !enabled);
}
