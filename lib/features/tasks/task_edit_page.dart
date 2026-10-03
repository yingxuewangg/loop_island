import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/data/record_commands.dart';
import 'package:loop_island/data/task_commands.dart';
import 'package:loop_island/features/reason/reason_sheet.dart';
import 'package:loop_island/features/reason/reason_view.dart';
import 'package:loop_island/features/tasks/widgets/date_type_picker.dart';
import 'package:loop_island/features/tasks/widgets/remind_time_picker.dart';
import 'package:loop_island/features/tasks/widgets/task_history_list.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/enums.dart';
// 注意：Dart 3 内置了 `Record` 类型，与本项目的 `Record` 模型同名。
// 凡是用到该模型的文件都必须显式导入本文件，否则 `Record` 会被解析成内置类型。
import 'package:loop_island/models/record.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/models/task.dart';
import 'package:loop_island/services/local_notification_service.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 任务编辑页（对应任务 2.9）。
///
/// [taskId] 为空表示新建。
///
/// 编辑期间所有字段都存在本页 state 里，**只有点保存才落库**；
/// 因此中途退出不会留下改了一半的任务。
class TaskEditPage extends ConsumerStatefulWidget {
  const TaskEditPage({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<TaskEditPage> createState() => _TaskEditPageState();
}

/// 任务编辑页内可被测试稳定定位的控件键。
abstract final class TaskEditKeys {
  /// 「精确闹钟未授权」提示旁的授权按钮。
  static const grantExactAlarm = Key('task-edit-grant-exact-alarm');
}

class _TaskEditPageState extends ConsumerState<TaskEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;

  TaskDateType _dateType = TaskDateType.none;
  DateTime? _date;
  List<DateTime> _remindAts = const [];
  TaskStatus _status = TaskStatus.pending;

  Task? _original;
  bool _loaded = false;
  bool _titleError = false;

  /// 精确闹钟权限；`null` 表示还没查到或平台不适用。
  ///
  /// 未授权时系统会把提醒降级为非精确闹钟（允许合并推迟），
  /// 用户会看到「提醒晚了几分钟」——必须在设提醒的地方就说清楚。
  bool? _exactAlarms;

  /// 本次进入本页是否已经为「设了提醒但缺精确闹钟权限」跳转过系统授权页。
  /// 只跳一次，避免反复保存时反复被拽出应用。
  bool _exactAlarmRequested = false;

  bool get _isNew => widget.taskId == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _noteController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExactAlarms());
  }

  /// 查一次精确闹钟权限（不弹系统框，只读状态）。
  Future<void> _loadExactAlarms() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    try {
      final granted = await service.exactAlarmsEnabled();
      if (mounted) {
        setState(() => _exactAlarms = granted);
      }
    } catch (_) {
      // 查询失败就不显示提示，不影响编辑
    }
  }

  /// 申请精确闹钟权限（已授权时插件会直接返回、不弹系统页）。
  Future<void> _requestExactAlarm() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.isSupported) {
      return;
    }
    await service.requestPermission();
    if (mounted) {
      await _loadExactAlarms();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 首次拿到数据后填充表单。放在 build 之前统一处理，
  /// 避免在 `initState` 里读 provider（那时还没有可用数据）。
  void _hydrate(AppData data, DateTime today) {
    if (_loaded) {
      return;
    }
    _loaded = true;

    final task = _isNew ? null : data.taskById(widget.taskId!);
    _original = task;

    if (task == null) {
      // 新建：默认安排在今天，比「无日期」更符合直觉。
      // 状态在这里**显式**钉回待办：新建页没有任何理由带着别的状态，
      // 显式赋值让「默认值被任何路径污染」在代码层面不可能成立。
      _dateType = TaskDateType.today;
      _date = dateOnly(today);
      _status = TaskStatus.pending;
      return;
    }

    _titleController.text = task.title;
    _noteController.text = task.note;
    _dateType = task.dateType;
    _date = task.resolvedDate(today) ?? task.date;
    _remindAts = task.remindAts;
    _status = task.status;
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final asyncData = ref.watch(appDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? TaskStrings.editTitleNew : TaskStrings.editTitleExisting),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Center(child: AnimalLoading()),
        error: (error, _) => Center(
          child: AnimalEmpty(description: '${CommonStrings.retry}：$error'),
        ),
        data: (data) {
          _hydrate(data, today);
          if (!_isNew && _original == null) {
            return const Center(
              child: AnimalEmpty(description: TaskStrings.listTitle),
            );
          }
          return _buildForm(data, today);
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildForm(AppData data, DateTime today) {
    final theme = AnimalTheme.of(context);
    final hasDate = _dateType != TaskDateType.none;
    final history = _isNew ? const <Record>[] : data.recordsForTask(widget.taskId!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _FieldLabel(TaskStrings.fieldTitle),
        AnimalInput(
          controller: _titleController,
          hintText: TaskStrings.fieldTitleHint,
          allowClear: true,
          status: _titleError ? AnimalInputStatus.error : null,
        ),
        if (_titleError) ...[
          const SizedBox(height: 6),
          Text(
            TaskStrings.titleRequired,
            style: theme.textStyle(size: 12, color: theme.errorColor),
          ),
        ],
        const SizedBox(height: 18),

        _FieldLabel(TaskStrings.fieldNote),
        AnimalTextarea(
          controller: _noteController,
          hintText: TaskStrings.fieldNoteHint,
          rows: 3,
        ),
        const SizedBox(height: 18),

        _FieldLabel(TaskStrings.fieldDate),
        DateTypePicker(
          dateType: _dateType,
          date: _date,
          today: today,
          onChanged: (dateType, date) => setState(() {
            _dateType = dateType;
            _date = date;
            if (dateType == TaskDateType.none) {
              _remindAts = const []; // 无日期不允许带提醒
            } else if (_remindAts.isNotEmpty && date != null) {
              // 换了日期就把提醒时段整体挪到新日期上，否则会出现
              // 「任务在下周、提醒还留在今天」这种自相矛盾的状态。
              _remindAts = normalizeInstantSlots(
                _remindAts.map(
                  (at) => atMinuteOfDay(date, minuteOfDay(at)),
                ),
              );
            }
          }),
        ),
        const SizedBox(height: 18),

        _FieldLabel(TaskStrings.fieldRemind),
        RemindTimePicker(
          remindAts: _remindAts,
          day: _date,
          enabled: hasDate,
          // 「现在」由调度器的同一个来源（nowProvider）提供：
          // 选择器据此提示「已经过去的时段到点不会再提醒」。
          now: ref.read(nowProvider)(),
          defaultMinuteOfDay: ref
              .watch(appDataProvider)
              .asData
              ?.value
              .settings
              .defaultRemindMinuteOfDay ??
              AppSettings.defaultRemindMinute,
          onChanged: (value) => setState(() => _remindAts = value),
        ),
        // 设了提醒、但精确闹钟权限没授 → 提醒会被系统合并推迟。
        // 这里行内提示 + 一键授权，用户不必自己去「设置 → 提醒设置」翻。
        if (hasDate && _remindAts.isNotEmpty && _exactAlarms == false) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  SettingsStrings.reminderExactAlarmMissing,
                  style: theme.textStyle(size: 12, color: theme.warningColor),
                ),
              ),
              const SizedBox(width: 8),
              AnimalButton(
                key: TaskEditKeys.grantExactAlarm,
                onPressed: _requestExactAlarm,
                child: const Text(SettingsStrings.reRequestPermission),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),

        _FieldLabel(TaskStrings.fieldStatus),
        AnimalRadio<TaskStatus>(
          value: _status,
          direction: AnimalRadioDirection.vertical,
          options: [
            for (final status in TaskStatus.values)
              AnimalRadioOption<TaskStatus>(
                value: status,
                label: Text(status.statusLabel),
              ),
          ],
          onChanged: (value) => setState(() => _status = value),
        ),

        if (_original != null && _original!.status != TaskStatus.completed) ...[
          const SizedBox(height: 18),
          _FieldLabel(TaskStrings.fieldReason),
          ReasonView(
            reason: _currentReasonOf(data, today),
            reasonUpdatedAt: _currentReasonUpdatedAtOf(data, today),
            onEdit: _editReason,
          ),
        ],

        const SizedBox(height: 22),
        _FieldLabel(TaskStrings.history),
        TaskHistoryList(
          records: history,
          emptyDescription: TaskStrings.noHistory,
        ),
      ],
    );
  }

  /// 当前生效的原因：优先取「任务归属那一天」的记录，其次取最近一次填过的。
  ///
  /// 之所以要回退：编辑页可能是在任务还没标记未完成、也没有当天记录时打开的，
  /// 此时用户仍应看到历史上填过的最近一条原因，而不是一片空白。
  String? _currentReasonOf(AppData data, DateTime today) {
    final task = _original;
    if (task == null) {
      return null;
    }
    final day = task.resolvedDate(today) ?? dateOnly(today);
    return entryReason(data, taskId: task.id, date: day) ??
        _latestReason(data.recordsForTask(task.id));
  }

  DateTime? _currentReasonUpdatedAtOf(AppData data, DateTime today) {
    final task = _original;
    if (task == null) {
      return null;
    }
    final day = task.resolvedDate(today) ?? dateOnly(today);
    final record = findEntryRecord(data, taskId: task.id, date: day);
    if (record != null && record.hasReason) {
      return record.reasonUpdatedAt;
    }
    for (final item in data.recordsForTask(task.id)) {
      if (item.hasReason) {
        return item.reasonUpdatedAt;
      }
    }
    return null;
  }

  /// 最近一次填写过的未完成原因（历史已按日期倒序）。
  String? _latestReason(List<Record> history) {
    for (final record in history) {
      if (record.hasReason) {
        return record.reason;
      }
    }
    return null;
  }

  Future<void> _editReason() async {
    final data = ref.appDataOrEmpty;
    final today = ref.read(todayProvider);
    final result = await showReasonSheet(
      context,
      initial: _currentReasonOf(data, today),
    );
    // null 表示取消：不要动数据
    if (result == null || !mounted) {
      return;
    }

    final task = _original!;
    final day = task.resolvedDate(today) ?? dateOnly(today);
    await ref.read(appDataProvider.notifier).commit(
          setEntryReason(
            data,
            taskId: task.id,
            date: day,
            reason: result,
            now: DateTime.now(),
          ),
        );
  }

  Widget _buildBottomBar() {
    final theme = AnimalTheme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      decoration: BoxDecoration(
        color: theme.elevatedBackgroundColor,
        border: Border(top: BorderSide(color: theme.controlBorderColor, width: 2)),
      ),
      child: Row(
        children: [
          if (!_isNew)
            Expanded(
              child: AnimalButton(
                danger: true,
                block: true,
                onPressed: _confirmDelete,
                child: const Text(CommonStrings.delete),
              ),
            ),
          if (!_isNew) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: IslandPrimaryButton(
              
              block: true,
              onPressed: _save,
              child: const Text(CommonStrings.save),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (!isValidTaskTitle(title)) {
      setState(() => _titleError = true);
      return;
    }
    setState(() => _titleError = false);

    final notifier = ref.read(appDataProvider.notifier);
    final current = ref.appDataOrEmpty;
    // 用注入的时钟（与 todayProvider 同源），不要直接 DateTime.now()：
    // 否则「界面按注入的今天算出明天」与「保存时按真实时钟固化」可能
    // 指向不同日期（跨零点时差一天，测试里也完全不可控）。
    final now = ref.read(nowProvider)();

    try {
      if (_isNew) {
        await notifier.commit(
          addTask(
            current,
            title: title,
            note: _noteController.text,
            dateType: _dateType,
            date: _date,
            remindAts: _remindAts,
            status: _status,
            now: now,
          ),
        );
      } else {
        final updated = _original!.copyWith(
          title: title,
          note: _noteController.text,
          dateType: _dateType,
          date: _dateType == TaskDateType.custom ? _date : null,
          remindAts: _remindAts,
          status: _status,
        );
        // 编辑页保存时把「今天 / 明天」固化成具体日期，
        // 否则明天再看这条任务会跟着漂移。
        await notifier.commit(
          updateTask(current, updated, now: now),
        );
        if (_dateType != TaskDateType.custom) {
          await notifier.commit(
            materializeTaskDate(
              ref.appDataOrEmpty,
              _original!.id,
              now: now,
            ),
          );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
      // 提醒只有在「精确闹钟」模式下才准时：非精确闹钟会被系统在批处理
      // 窗口内提前 / 推后几分钟触发（用户实测 9:00 的提醒 8:58 就响了）。
      // 保存的是带提醒的任务而权限又缺失时，主动带用户去开一次；
      // 已授权 / 平台不适用 / 本次已跳转过则不打扰。
      if (_remindAts.isNotEmpty &&
          _exactAlarms == false &&
          !_exactAlarmRequested) {
        _exactAlarmRequested = true;
        await _requestExactAlarm();
      }
    } catch (error) {
      if (mounted) {
        AnimalMessage.error(
          context,
          Text('${TaskStrings.saveFailed}：$error'),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final task = _original;
    if (task == null) {
      return;
    }

    final confirmed = await AnimalConfirmDialog.show(
      context: context,
      title: const Text(TaskStrings.deleteConfirmTitle),
      content: const Text(TaskStrings.deleteConfirmBody),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final notifier = ref.read(appDataProvider.notifier);
    final current = ref.appDataOrEmpty;
    await notifier.commit(deleteTask(current, task.id));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// 表单字段标题。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textStyle(size: 13, color: theme.secondaryTextColor),
      ),
    );
  }
}

/// 未完成原因现在的实现见 `lib/features/reason/reason_view.dart`（任务 6.4）：
/// 只读占位已替换为可编辑的 `ReasonView`，三处复用同一组件。

