import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/models/enums.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 修改作用域弹窗的控件键。
abstract final class EditScopeKeys {
  static const dialog = Key('edit-scope-dialog');
  static const confirm = Key('edit-scope-confirm');
  static const cancel = Key('edit-scope-cancel');
}

/// 弹出「仅本次 / 以后所有」选择框（PRD §七）。
///
/// 返回 `null` 表示取消。
///
/// 只给两个选项是 PRD 明确要求（`fromNowUntil` 留到第二版，见 PRD §八.5）。
Future<EditScope?> showEditScopeDialog(BuildContext context) {
  return showDialog<EditScope>(
    context: context,
    builder: (_) => const _EditScopeDialog(),
  );
}

class _EditScopeDialog extends StatefulWidget {
  const _EditScopeDialog();

  @override
  State<_EditScopeDialog> createState() => _EditScopeDialogState();
}

class _EditScopeDialogState extends State<_EditScopeDialog> {
  EditScope _scope = EditScope.once;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return AnimalDialog(
      key: EditScopeKeys.dialog,
      title: const Text(CycleStrings.scopeTitle),
      showFooter: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimalRadio<EditScope>(
            value: _scope,
            direction: AnimalRadioDirection.vertical,
            options: const [
              AnimalRadioOption<EditScope>(
                value: EditScope.once,
                label: Text(CycleStrings.scopeOnce),
              ),
              AnimalRadioOption<EditScope>(
                value: EditScope.fromNowAll,
                label: Text(CycleStrings.scopeFromNowAll),
              ),
            ],
            onChanged: (value) => setState(() => _scope = value),
          ),
          const SizedBox(height: 8),
          Text(
            _scope == EditScope.once
                ? CycleStrings.scopeOnceHint
                : CycleStrings.scopeAllHint,
            style: theme.textStyle(size: 12, color: theme.secondaryTextColor),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: IslandPrimaryButton(
                  key: EditScopeKeys.cancel,
                  block: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(CommonStrings.cancel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IslandPrimaryButton(
                  key: EditScopeKeys.confirm,
                  block: true,
                  onPressed: () => Navigator.of(context).pop(_scope),
                  child: const Text(CommonStrings.confirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
