import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 文本输入弹层的控件键。
abstract final class TextInputSheetKeys {
  static const sheet = Key('text-input-sheet');
  static const field = Key('text-input-field');
  static const confirm = Key('text-input-confirm');
  static const cancel = Key('text-input-cancel');
}

/// 弹出一个只收一行文本的底部弹层。
///
/// 返回值：`null` 表示取消；否则是**已去除首尾空白且非空**的文本。
/// 空文本不允许提交（会就地报错），所以调用方拿到的要么是 null 要么是有效文本 ——
/// 「改成一个空名字」这种事应该在弹层里就被挡住，而不是留给调用方判断。
Future<String?> showTextInputSheet(
  BuildContext context, {
  required String title,
  String? initial,
  String hint = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => TextInputSheet(
      title: title,
      initial: initial,
      hint: hint,
    ),
  );
}

/// 单行文本输入弹层。
class TextInputSheet extends StatefulWidget {
  const TextInputSheet({
    super.key,
    required this.title,
    this.initial,
    this.hint = '',
  });

  final String title;
  final String? initial;
  final String hint;

  @override
  State<TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<TextInputSheet> {
  late final TextEditingController _controller;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(text);
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
          key: TextInputSheetKeys.sheet,
          color: IslandCardColor.warm,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textStyle(size: 16)),
              const SizedBox(height: 12),
              AnimalInput(
                key: TextInputSheetKeys.field,
                controller: _controller,
                hintText: widget.hint,
                allowClear: true,
                status: _showError ? AnimalInputStatus.error : null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_showError) {
                    setState(() => _showError = false);
                  }
                },
              ),
              if (_showError) ...[
                const SizedBox(height: 6),
                Text(
                  CommonStrings.required,
                  style: theme.textStyle(size: 12, color: theme.errorColor),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AnimalButton(
                      key: TextInputSheetKeys.cancel,
                      block: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(CommonStrings.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IslandPrimaryButton(
                      key: TextInputSheetKeys.confirm,
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
}
