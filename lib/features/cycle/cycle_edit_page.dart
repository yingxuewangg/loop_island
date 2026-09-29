import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/model_labels.dart';
import 'package:loop_island/app/routes.dart';
import 'package:loop_island/app/widgets/minute_of_day_list_editor.dart';
import 'package:loop_island/app/widgets/minute_of_day_picker.dart';
import 'package:loop_island/core/date_x.dart';
import 'package:loop_island/core/remind_slots.dart';
import 'package:loop_island/data/cycle_commands.dart';
import 'package:loop_island/data/providers.dart';
import 'package:loop_island/models/app_data.dart';
import 'package:loop_island/models/cycle.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/models/settings.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 计划编辑页（对应任务 3.10）。
///
/// [cycleId] 为空表示新建。
///
/// 与任务编辑页一致：所有字段先存在本页 state，**只有点保存才落库**，
/// 中途退出不会留下改了一半的计划。
class CycleEditPage extends ConsumerStatefulWidget {
  const CycleEditPage({super.key, this.cycleId});

  final String? cycleId;

  @override
  ConsumerState<CycleEditPage> createState() => _CycleEditPageState();
}

class _CycleEditPageState extends ConsumerState<CycleEditPage> {
  late final TextEditingController _nameController;

  int _periodDays = 8;
  DateTime? _startDate;
  List<int> _remindMinutesOfDay = const [];
  CycleEndType _endType = CycleEndType.never;
  int _endCount = 3;
  DateTime? _endDate;
  bool _completeCyclesOnly = false;

  Cycle? _original;
  bool _loaded = false;
  String? _error;

  /// 打开提醒开关时使用的初始时刻（来自设置里的「默认提醒时间」）。
  int _defaultRemindMinute = AppSettings.defaultRemindMinute;

  bool get _isNew => widget.cycleId == null;

  static const int _minPeriodDays = 1;
  static const int _maxPeriodDays = 60;
  static const int _maxEndCount = 52;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _hydrate(AppData data, DateTime today) {
    // 每次 build 都更新默认提醒时刻：用户在设置页改完再回到本页要立刻生效。
    _defaultRemindMinute = data.settings.defaultRemindMinuteOfDay;

    if (_loaded) {
      return;
    }
    _loaded = true;

    _startDate ??= dateOnly(today);
    final cycle = _isNew ? null : data.cycleById(widget.cycleId!);
    _original = cycle;
    if (cycle == null) {
      return;
    }

    _nameController.text = cycle.name;
    _periodDays = cycle.periodDays;
    _startDate = cycle.startDate;
    _remindMinutesOfDay = cycle.remindMinutesOfDay;
    _endType = cycle.endType;
    _endCount = cycle.endCount ?? 3;
    _endDate = cycle.endDate;
    _completeCyclesOnly = cycle.completeCyclesOnly;
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final asyncData = ref.watch(appDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? CycleStrings.createTitle : CycleStrings.editTitle),
        backgroundColor: Colors.transparent,
      ),
      body: asyncData.when(
        loading: () => const Center(child: AnimalLoading()),
        error: (error, _) => Center(
          child: AnimalEmpty(description: '$error'),
        ),
        data: (data) {
          _hydrate(data, today);
          return _buildForm();
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildForm() {
    final theme = AnimalTheme.of(context);
    final start = _startDate ?? dateOnly(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _FieldLabel(CycleStrings.fieldName),
        AnimalInput(
          controller: _nameController,
          hintText: CycleStrings.fieldNameHint,
          allowClear: true,
        ),
        const SizedBox(height: 18),

        _FieldLabel(CycleStrings.fieldPeriodDays),
        AnimalSelect<int>(
          value: _periodDays,
          minWidth: 120,
          options: [
            for (var n = _minPeriodDays; n <= _maxPeriodDays; n++)
              AnimalSelectOption<int>(
                key: n,
                label: CycleStrings.periodDaysValue(n),
              ),
          ],
          onChanged: (value) => setState(() => _periodDays = value),
        ),
        const SizedBox(height: 18),

        _FieldLabel(CycleStrings.fieldStartDate),
        _DateRow(
          date: start,
          buttonText: CycleStrings.startDateLabel,
          onPick: (picked) => setState(() {
            _startDate = picked;
            // 起始日推后时，原来的结束日可能就不合法了
            if (_endDate != null && !isAfterDay(_endDate!, picked)) {
              _endDate = null;
            }
          }),
        ),
        const SizedBox(height: 18),

        _FieldLabel(CycleStrings.fieldRemindTime),
        Row(
          children: [
            AnimalSwitch(
              value: _remindMinutesOfDay.isNotEmpty,
              onChanged: (on) => setState(
                () => _remindMinutesOfDay =
                    on ? [_defaultRemindMinute] : const [],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _remindMinutesOfDay.isEmpty
                    ? CycleStrings.noRemind
                    : CycleStrings.remindTimes(
                        formatMinuteSlots(_remindMinutesOfDay),
                      ),
                style: theme.textStyle(size: 14),
              ),
            ),
          ],
        ),
        if (_remindMinutesOfDay.isNotEmpty) ...[
          const SizedBox(height: 12),
          MinuteOfDayListEditor(
            values: _remindMinutesOfDay,
            onChanged: (value) => setState(() => _remindMinutesOfDay = value),
          ),
        ],
        const SizedBox(height: 18),

        _FieldLabel(CycleStrings.fieldEndType),
        AnimalRadio<CycleEndType>(
          value: _endType,
          direction: AnimalRadioDirection.vertical,
          options: [
            for (final type in CycleEndType.values)
              AnimalRadioOption<CycleEndType>(
                value: type,
                label: Text(type.endTypeLabel),
              ),
          ],
          onChanged: (value) => setState(() => _endType = value),
        ),

        if (_endType == CycleEndType.afterCount) ...[
          const SizedBox(height: 14),
          _FieldLabel(CycleStrings.fieldEndCount),
          AnimalSelect<int>(
            value: _endCount,
            minWidth: 120,
            options: [
              for (var n = 1; n <= _maxEndCount; n++)
                AnimalSelectOption<int>(
                  key: n,
                  label: CycleStrings.endCountValue(n),
                ),
            ],
            onChanged: (value) => setState(() => _endCount = value),
          ),
        ],

        if (_endType == CycleEndType.untilDate) ...[
          const SizedBox(height: 14),
          _FieldLabel(CycleStrings.fieldEndDate),
          _DateRow(
            date: _endDate,
            buttonText: TaskStrings.customDate,
            placeholder: CommonStrings.notFilled,
            onPick: (picked) => setState(() => _endDate = picked),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AnimalSwitch(
                value: _completeCyclesOnly,
                onChanged: (on) => setState(() => _completeCyclesOnly = on),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  CycleStrings.fieldCompleteCyclesOnly,
                  style: theme.textStyle(size: 14),
                ),
              ),
            ],
          ),
        ],

        if (!_isNew) ...[
          const SizedBox(height: 22),
          _FieldLabel(CycleStrings.dayListTitle),
          AnimalButton(
            block: true,
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => context.pushRoute<void>(
              AppRoutes.cycleDetail,
              arguments: widget.cycleId,
            ),
            child: const Text(CycleStrings.dayListTitle),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
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

  /// 校验并返回错误文案；合法时返回 null。
  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return CycleStrings.nameRequired;
    }
    if (_periodDays < _minPeriodDays || _periodDays > _maxPeriodDays) {
      return CycleStrings.periodInvalid;
    }
    if (_endType == CycleEndType.afterCount && _endCount < 1) {
      return CycleStrings.endCountInvalid;
    }
    if (_endType == CycleEndType.untilDate) {
      final end = _endDate;
      if (end == null) {
        return CycleStrings.endDateTooEarly;
      }
      final start = _startDate ?? dateOnly(DateTime.now());
      // PRD：结束日必须晚于起始日（同日会让周期只剩一天，没有意义）
      if (!isAfterDay(end, start)) {
        return CycleStrings.endDateTooEarly;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);

    final notifier = ref.read(appDataProvider.notifier);
    final current = ref.appDataOrEmpty;
    // 「今天」必须取注入值，与列表页/详情页保持同一口径
    final today = ref.read(todayProvider);
    final now = DateTime.now();
    final start = _startDate ?? dateOnly(today);

    final name = _nameController.text.trim();
    final endDate = _endType == CycleEndType.untilDate ? _endDate : null;
    final endCount = _endType == CycleEndType.afterCount ? _endCount : null;

    final cycle = _original == null
        ? Cycle.create(
            name: name,
            periodDays: _periodDays,
            startDate: start,
            endType: _endType,
            endDate: endDate,
            endCount: endCount,
            completeCyclesOnly:
                _endType == CycleEndType.untilDate && _completeCyclesOnly,
            remindMinutesOfDay: _remindMinutesOfDay,
            now: now,
          )
        : _original!.copyWith(
            name: name,
            periodDays: _periodDays,
            startDate: start,
            endType: _endType,
            endDate: endDate,
            endCount: endCount,
            completeCyclesOnly:
                _endType == CycleEndType.untilDate && _completeCyclesOnly,
            remindMinutesOfDay: _remindMinutesOfDay,
          );

    try {
      await notifier.commit(
        upsertCycle(current, cycle, now: now, today: dateOnly(today)),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        AnimalMessage.error(
          context,
          Text('${CycleStrings.saveFailed}：$error'),
        );
      }
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

/// 一行日期：显示当前值 + 打开日历。
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.date,
    required this.buttonText,
    required this.onPick,
    this.placeholder = '',
  });

  final DateTime? date;
  final String buttonText;
  final String placeholder;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final current = date;

    return Row(
      children: [
        IslandTag(
          colors: current == null
              ? IslandTagColors.pending
              : IslandTagColors.plan,
          child: Text(
            current == null ? placeholder : formatFullDate(current),
          ),
        ),
        const SizedBox(width: 10),
        AnimalButton(
          size: AnimalButtonSize.small,
          onPressed: () async {
            final picked = await showCalendarSheet(
              context,
              initial: current ?? dateOnly(DateTime.now()),
              title: buttonText,
              firstDate: DateTime(DateTime.now().year - 5),
              lastDate: DateTime(DateTime.now().year + 10, 12, 31),
            );
            if (picked != null) {
              onPick(picked);
            }
          },
          child: Text(buttonText),
        ),
        const Spacer(),
        if (current != null)
          Text(
            weekdayLabel(current),
            style: theme.textStyle(
              size: 12,
              color: theme.secondaryTextColor,
            ),
          ),
      ],
    );
  }
}
