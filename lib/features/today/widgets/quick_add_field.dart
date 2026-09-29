import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 今日页的快速添加（对应任务 4.6）。
///
/// 输入标题后回车（或点「添加」）即创建一条**日期为今天**的普通任务。
/// 空输入不创建 —— 避免用户误按回车留下一条空任务。
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.onSubmit});

  /// 提交回调；参数已去除首尾空白，保证非空。
  final ValueChanged<String> onSubmit;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AnimalInput(
            controller: _controller,
            hintText: TodayStrings.quickAddHint,
            allowClear: true,
            textInputAction: TextInputAction.done,
            // 回车即创建（PRD：快速添加普通任务）
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 10),
        IslandPrimaryButton(
          
          onPressed: _submit,
          child: const Text(CommonStrings.add),
        ),
      ],
    );
  }
}
