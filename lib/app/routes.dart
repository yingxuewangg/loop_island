import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/features/cycle/cycle_day_edit_page.dart';
import 'package:loop_island/features/cycle/cycle_detail_page.dart';
import 'package:loop_island/features/cycle/cycle_edit_page.dart';
import 'package:loop_island/features/day/calendar_view_page.dart';
import 'package:loop_island/features/day/day_detail_page.dart';
import 'package:loop_island/features/settings/about_page.dart';
import 'package:loop_island/features/settings/data_page.dart';
import 'package:loop_island/features/settings/export_page.dart';
import 'package:loop_island/features/settings/import_page.dart';
import 'package:loop_island/features/settings/reminder_page.dart';
import 'package:loop_island/features/stats/stats_page.dart';
import 'package:loop_island/features/tasks/task_edit_page.dart';

/// 全部命名路由。
///
/// 阶段 2~8 会把 [AppRouter.onGenerateRoute] 中的占位页替换为真实页面，
/// 路由名保持不变，调用方无需改动。
abstract final class AppRoutes {
  /// 任务编辑（新建 / 编辑普通任务）：参数 `taskId`（新建时为 null）。
  static const taskEdit = '/task-edit';

  /// 计划详情：参数 `cycleId`。
  static const cycleDetail = '/cycle-detail';

  /// 计划编辑（新建 / 编辑循环计划）：参数 `cycleId`（新建时为 null）。
  static const cycleEdit = '/cycle-edit';

  /// 某一天编辑：参数 `CycleDayEditArgs`。
  static const cycleDayEdit = '/cycle-day-edit';

  /// 统计页。
  static const stats = '/stats';

  /// 某天详情：参数为 `dayKey` 字符串（`yyyy-MM-dd`）。
  static const dayDetail = '/day-detail';

  /// 日历视图：参数为可选的 `dayKey` 字符串（初始选中日期）。
  static const calendarView = '/calendar-view';

  /// 导出备份。
  static const export = '/export';

  /// 导入恢复。
  static const import = '/import';

  /// 数据管理（导出 / 导入 / 清空）。
  static const dataManage = '/data-manage';

  /// 提醒设置。
  static const reminder = '/reminder';

  /// 关于与隐私说明。
  static const about = '/about';
}

/// 「某一天编辑」页参数。
@immutable
class CycleDayEditArgs {
  const CycleDayEditArgs({required this.cycleId, required this.dayIndex});

  final String cycleId;

  /// 周期内第几天，从 1 开始。
  final int dayIndex;

  @override
  String toString() =>
      'CycleDayEditArgs(cycleId: $cycleId, dayIndex: $dayIndex)';
}

/// 路由生成器。
///
/// 已实现的页面直接返回真实页面；其余仍是占位页，
/// 各自任务完成时替换即可，路由名与调用方无需改动。
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    if (name == AppRoutes.taskEdit) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => TaskEditPage(taskId: settings.arguments as String?),
      );
    }

    if (name == AppRoutes.export) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ExportPage(),
      );
    }

    if (name == AppRoutes.import) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ImportPage(),
      );
    }

    if (name == AppRoutes.dataManage) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const DataPage(),
      );
    }

    if (name == AppRoutes.reminder) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ReminderPage(),
      );
    }

    if (name == AppRoutes.about) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AboutPage(),
      );
    }

    if (name == AppRoutes.calendarView) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CalendarViewPage(
          initialDate: parseDayKey(settings.arguments as String?),
        ),
      );
    }

    if (name == AppRoutes.dayDetail) {
      final key = settings.arguments;
      if (key is String && parseDayKey(key) != null) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => DayDetailPage(dayKey: key),
        );
      }
      return _notFoundRoute(settings);
    }

    if (name == AppRoutes.stats) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const StatsPage(),
      );
    }

    if (name == AppRoutes.cycleEdit) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CycleEditPage(cycleId: settings.arguments as String?),
      );
    }

    if (name == AppRoutes.cycleDayEdit) {
      final args = settings.arguments;
      if (args is CycleDayEditArgs) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => CycleDayEditPage(
            cycleId: args.cycleId,
            dayIndex: args.dayIndex,
          ),
        );
      }
      return _notFoundRoute(settings);
    }

    if (name == AppRoutes.cycleDetail) {
      final cycleId = settings.arguments;
      if (cycleId is String && cycleId.isNotEmpty) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => CycleDetailPage(cycleId: cycleId),
        );
      }
      // 缺计划 id：不落到「计划详情·开发中」那种误导性提示，直接报找不到
      return _notFoundRoute(settings);
    }

    if (name == null || !_routeTitles.containsKey(name)) {
      return _notFoundRoute(settings);
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => _RoutePlaceholder(
        title: _routeTitles[name]!,
        arguments: settings.arguments,
      ),
    );
  }

  static Route<dynamic> _notFoundRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const _RoutePlaceholder(title: RouteStrings.notFound),
    );
  }

  static const _routeTitles = <String, String>{
    AppRoutes.taskEdit: TaskStrings.editTitleExisting,
    AppRoutes.cycleDetail: CycleStrings.detailTitle,
    AppRoutes.cycleEdit: CycleStrings.editTitle,
    AppRoutes.cycleDayEdit: CycleStrings.dayEditTitle,
    AppRoutes.stats: StatsStrings.title,
    AppRoutes.dayDetail: DayStrings.detailTitle,
    AppRoutes.export: DataStrings.exportTitle,
    AppRoutes.import: DataStrings.importTitle,
  };
}

/// 导航扩展：统一从 [BuildContext] 发起命名路由跳转。
extension AppNavigator on BuildContext {
  /// 压入命名路由并等待返回结果。
  Future<T?> pushRoute<T>(String route, {Object? arguments}) {
    return Navigator.of(this).pushNamed<T>(route, arguments: arguments);
  }

  /// 压入「某一天编辑」页。
  Future<void> pushCycleDayEdit({
    required String cycleId,
    required int dayIndex,
  }) {
    return pushRoute<void>(
      AppRoutes.cycleDayEdit,
      arguments: CycleDayEditArgs(cycleId: cycleId, dayIndex: dayIndex),
    );
  }

  /// 压入「某天详情」页。
  Future<void> pushDayDetail(String dayKey) {
    return pushRoute<void>(AppRoutes.dayDetail, arguments: dayKey);
  }
}

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.title, this.arguments});

  final String title;
  final Object? arguments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimalEmpty(description: RouteStrings.underConstruction),
            if (arguments != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('参数：$arguments'),
              ),
          ],
        ),
      ),
    );
  }
}
