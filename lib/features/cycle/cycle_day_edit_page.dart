import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/minute_of_day_picker.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/ids.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 某一天编辑页内可被测试稳定定位的控件键。
abstract final class CycleDayEditKeys {
  static const addTaskButton = Key('cycle-day-add-task');
  static const restDaySwitch = Key('cycle-day-rest-switch');
  static const titleField = Key('cycle-day-title-field');
  static const remindSwitch = Key('cycle-day-remind-switch');
  static const confirmAdd = Key('cycle-day-confirm-add');
  static const moveUp = Key('cycle-day-move-up');
  static const moveDown = Key('cycle-day-move-down');
  static const remove = Key('cycle-day-remove');
}

/// 某一天编辑页（对应任务 3.12）。
///
/// 只编辑**周期模板**里第 [dayIndex] 天的任务定义，不碰任何具体日期的实例；
/// 保存后由 `updateCycleDay` 重算今天起的未来实例，历史记录保持不变。
class CycleDayEditPage extends ConsumerStatefulWidget {
  const CycleDayEditPage({
    super.key,
    required this.cycleId,
    required this.dayIndex,
  });

  final String cycleId;
  final int dayIndex;

  @override
  ConsumerState<CycleDayEditPage> createState() => _CycleDayEditPageState();
}

class _CycleDayEditPageState extends ConsumerState<CycleDayEditPage> {
  /// 编辑中的副本；点保存才写回。
  CycleDay? _draft;
  bool _loaded = false;
  String? _error;

  void _hydrate(AppData data) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _draft = data.cycleById(widget.cycleId)?.dayAt(widget.dayIndex) ??
        CycleDay.empty(widget.dayIndex);
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(appDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${CycleStrings.dayEditTitle} · ${CycleStrings.dayLabel(widget.dayIndex)}',
        ),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Center(child: AnimalLoading()),
        error: (error, _) => Center(child: AnimalEmpty(description: '$error')),
        data: (data) {
          _hydrate(data);
          final draft = _draft!;
          return _buildBody(draft);
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody(CycleDay draft) {
    final theme = AnimalTheme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ---- 休息日 ----
        Row(
          children: [
            AnimalSwitch(
              key: CycleDayEditKeys.restDaySwitch,
              value: draft.isRestDay,
              onChanged: (on) => setState(() {
                // 切到休息日会清空任务：留着「休息日 + 有任务」的矛盾状态没有意义
                _draft = draft.copyWith(
                  isRestDay: on,
                  templates: on ? const [] : draft.templates,
                );
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                CycleStrings.actionSetRestDay,
                style: theme.textStyle(size: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Text(
              CycleStrings.dayListTitle,
              style: theme.textStyle(size: 15),
            ),
            const Spacer(),
            Text(
              CycleStrings.dayTaskCount(draft.taskCount),
              style: theme.textStyle(
                size: 12,
                color: theme.secondaryTextColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (draft.isRestDay)
          IslandCard(
            type: IslandCardType.dashed,
            padding: const EdgeInsets.all(14),
            child: Text(
              '休息日不安排任务',
              style: theme.textStyle(
                size: 13,
                color: theme.secondaryTextColor,
              ),
            ),
          )
        else ...[
          if (draft.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                TaskStrings.emptyList,
                style: theme.textStyle(
                  size: 13,
                  color: theme.disabledTextColor,
                ),
              ),
            ),
          for (var i = 0; i < draft.sortedTemplates.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TemplateRow(
                template: draft.sortedTemplates[i],
                isFirst: i == 0,
                isLast: i == draft.sortedTemplates.length - 1,
                onMoveUp: () => setState(
                  () => _draft = draft.moveTemplate(i, i - 1),
                ),
                onMoveDown: () => setState(
                  () => _draft = draft.moveTemplate(i, i + 1),
                ),
                onRemove: () => setState(
                  () => _draft = draft.removeTemplate(
                    draft.sortedTemplates[i].id,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          IslandPrimaryButton(
            key: CycleDayEditKeys.addTaskButton,
            block: true,
            icon: const Icon(Icons.add),
            // 休息日下不可添加
            disabled: draft.isRestDay,
            onPressed: () => _addTemplate(draft),
            child: const Text(TaskStrings.addTask),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: theme.textStyle(size: 12, color: theme.errorColor),
          ),
        ],
      ],
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
        border:
            Border(top: BorderSide(color: theme.controlBorderColor, width: 2)),
      ),
      child: IslandPrimaryButton(
        
        block: true,
        onPressed: _save,
        child: const Text(CommonStrings.save),
      ),
    );
  }

  /// 弹出新增任务弹窗；返回填好的模板。
  Future<void> _addTemplate(CycleDay draft) async {
    // 提醒开关打开时用设置里的「默认提醒时间」作初始值，
    // 否则这个设置就只是个摆设。
    final defaultMinute =
        ref.read(appDataProvider).asData?.value.settings.defaultRemindMinuteOfDay ??
            AppSettings.defaultRemindMinute;
    final created = await showModalBottomSheet<CycleTaskTemplate>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddTemplateSheet(defaultMinuteOfDay: defaultMinute),
    );
    if (created == null || !mounted) {
      return;
    }
    setState(() => _draft = draft.addTemplate(created));
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }

    final notifier = ref.read(appDataProvider.notifier);
    try {
      await notifier.commit(
        updateCycleDay(
          ref.appDataOrEmpty,
          widget.cycleId,
          draft,
          now: DateTime.now(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '${CycleStrings.saveFailed}：$error');
      }
    }
  }
}

/// 单个模板行：标题 + 提醒 + 上移/下移/删除。
class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final CycleTaskTemplate template;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return IslandCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.title, style: theme.textStyle(size: 14)),
                if (template.remindLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IslandTag(
                      colors: IslandTagColors.remind,
                      child: Text(
                        TaskStrings.remindAt(template.remindLabel!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: CycleDayEditKeys.moveUp,
            onPressed: isFirst ? null : onMoveUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: '上移',
          ),
          IconButton(
            key: CycleDayEditKeys.moveDown,
            onPressed: isLast ? null : onMoveDown,
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: '下移',
          ),
          IconButton(
            key: CycleDayEditKeys.remove,
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline, size: 18, color: theme.errorColor),
            tooltip: CommonStrings.delete,
          ),
        ],
      ),
    );
  }
}

/// 新增任务弹窗：标题 + 可选提醒时间。
class _AddTemplateSheet extends StatefulWidget {
  const _AddTemplateSheet({required this.defaultMinuteOfDay});

  /// 打开提醒开关时使用的初始时刻（来自设置里的「默认提醒时间」）。
  final int defaultMinuteOfDay;

  @override
  State<_AddTemplateSheet> createState() => _AddTemplateSheetState();
}

class _AddTemplateSheetState extends State<_AddTemplateSheet> {
  final TextEditingController _controller = TextEditingController();
  int? _remindMinuteOfDay;
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: IslandCard(
          color: IslandCardColor.warm,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(TaskStrings.editTitleNew, style: theme.textStyle(size: 16)),
              const SizedBox(height: 12),
              AnimalInput(
                key: CycleDayEditKeys.titleField,
                controller: _controller,
                hintText: TaskStrings.fieldTitleHint,
                allowClear: true,
                status: _showError ? AnimalInputStatus.error : null,
              ),
              if (_showError) ...[
                const SizedBox(height: 6),
                Text(
                  TaskStrings.titleRequired,
                  style: theme.textStyle(size: 12, color: theme.errorColor),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  AnimalSwitch(
                    key: CycleDayEditKeys.remindSwitch,
                    value: _remindMinuteOfDay != null,
                    onChanged: (on) => setState(
                      () => _remindMinuteOfDay =
                          on ? widget.defaultMinuteOfDay : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _remindMinuteOfDay == null
                          ? CycleStrings.noRemind
                          : CycleStrings.remindAt(
                              formatMinuteOfDay(_remindMinuteOfDay!),
                            ),
                      style: theme.textStyle(size: 13),
                    ),
                  ),
                ],
              ),
              if (_remindMinuteOfDay != null) ...[
                const SizedBox(height: 10),
                MinuteOfDayPicker(
                  minuteOfDay: _remindMinuteOfDay!,
                  onChanged: (value) =>
                      setState(() => _remindMinuteOfDay = value),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: IslandPrimaryButton(
                      block: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(CommonStrings.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IslandPrimaryButton(
                      key: CycleDayEditKeys.confirmAdd,
                      block: true,
                      onPressed: _submit,
                      child: const Text(CommonStrings.confirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _showError = true);
      return;
    }

    Navigator.of(context).pop(
      CycleTaskTemplate(
        id: newCycleTaskId(),
        title: title,
        remindMinuteOfDay: _remindMinuteOfDay,
        updatedAt: DateTime.now(),
      ),
    );
  }
}
