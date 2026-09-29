import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/quick_reasons.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 原因弹窗内可被测试稳定定位的控件键。
abstract final class ReasonKeys {
  static const sheet = Key('reason-sheet');
  static const textField = Key('reason-text-field');
  static const confirm = Key('reason-confirm');
  static const cancel = Key('reason-cancel');
  static const clear = Key('reason-clear');
}

/// 单个快捷原因选项的 key。
Key reasonChipKey(String label) => Key('reason-chip-$label');

/// 弹出未完成原因填写弹窗（任务 6.2）。
///
/// 返回值语义（调用方需要区分三种情况，所以不能只返回 `String?`）：
/// - `null`：用户取消，**不要改动数据**
/// - `''`：用户清空了原因
/// - 其它：新的原因文本（已去除首尾空白）
Future<String?> showReasonSheet(
  BuildContext context, {
  String? initial,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ReasonSheet(initial: initial),
  );
}

/// 原因弹窗本体（公开出来便于测试直接挂载）。
///
/// PRD 要求：快捷原因可点选、支持自由文本、**不强制填写**。
/// 因此「确定」在输入为空时也可提交，其含义是「清空原因」。
class ReasonSheet extends StatefulWidget {
  const ReasonSheet({super.key, this.initial});

  final String? initial;

  @override
  State<ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<ReasonSheet> {
  late final TextEditingController _controller;

  /// 当前选中的快捷原因（非「其他」）。空表示未选。
  String? _selectedQuick;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial?.trim() ?? '';
    _controller = TextEditingController(text: initial);

    // 已有原因正好是某个非「其他」的快捷项时，回显选中态；
    // 否则（自定义文本或「其他」）保持输入框内容可见。
    _selectedQuick =
        isQuickReason(initial) && !isCustomReason(initial) ? initial : null;
  }

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
          key: ReasonKeys.sheet,
          color: IslandCardColor.warm,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ReasonStrings.sheetTitle, style: theme.textStyle(size: 16)),
              const SizedBox(height: 4),
              Text(
                ReasonStrings.hint,
                style: theme.textStyle(
                  size: 12,
                  color: theme.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 14),

              // ---- 快捷原因 ----
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in quickReasons)
                    _ReasonChip(
                      reason: reason,
                      selected: _selectedQuick == reason.label ||
                          (reason.isOther &&
                              isCustomReason(_controller.text) &&
                              _selectedQuick == null),
                      onTap: () => _selectQuick(reason),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // ---- 自由文本 ----
              AnimalInput(
                key: ReasonKeys.textField,
                controller: _controller,
                hintText: ReasonStrings.customLabel,
                allowClear: true,
                onChanged: (value) => setState(() {
                  // 手动改了文本就不再算选中快捷项
                  if (value != _selectedQuick) {
                    _selectedQuick = null;
                  }
                }),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: AnimalButton(
                      key: ReasonKeys.cancel,
                      block: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(CommonStrings.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IslandPrimaryButton(
                      key: ReasonKeys.confirm,
                      block: true,
                      onPressed: () => Navigator.of(context).pop(
                        _controller.text.trim(),
                      ),
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

  void _selectQuick(QuickReason reason) {
    setState(() {
      if (reason.isOther) {
        // 选中「其他」：清掉预设文本，提示用户自己写
        _selectedQuick = null;
        if (isQuickReason(_controller.text)) {
          _controller.text = '';
        }
        return;
      }
      _selectedQuick = reason.label;
      _controller.text = reason.label;
    });
  }
}

/// 一个可选中的快捷原因气泡。
class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final QuickReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return GestureDetector(
      key: reasonChipKey(reason.label),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.primaryBackgroundColor
              : theme.subtleBackgroundColor,
          borderRadius: BorderRadius.circular(theme.radiusSmall),
          border: Border.all(
            color: selected ? theme.primaryColor : theme.lightBorderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          reason.label,
          style: theme.textStyle(
            size: 13,
            color: selected ? theme.primaryColor : theme.textColor,
          ),
        ),
      ),
    );
  }
}
