/// 未完成原因的快捷选项（任务 6.1）。
///
/// 为什么放在 `app/` 而不是 `core/`：这七个选项是**界面文案**，
/// 而 `core/` 不允许依赖 `app/l10n_strings.dart`（会破坏分层）。
/// 存储在 `Record.reason` 里的仍然是自由文本，因此**增删快捷项不影响已有数据**。
library;

import 'package:loop_island/app/l10n_strings.dart';
import 'package:meta/meta.dart';

/// 一个快捷原因选项。
@immutable
class QuickReason {
  const QuickReason({required this.label, this.isOther = false});

  /// 展示文案，同时也是写入 `Record.reason` 的文本。
  final String label;

  /// 是否是「其他」——选中后应展开自由输入框。
  final bool isOther;

  @override
  String toString() => 'QuickReason($label${isOther ? ', other' : ''})';
}

/// 各项之间用 `+` 而不是三引号拼接，避免误带换行或缩进。
const String _other = ReasonStrings.quickOther;

/// PRD §六 规定的七个快捷原因，顺序即展示顺序。
final List<QuickReason> quickReasons = List.unmodifiable([
  const QuickReason(label: ReasonStrings.quickNoTime),
  const QuickReason(label: ReasonStrings.quickUnwell),
  const QuickReason(label: ReasonStrings.quickSomethingCameUp),
  const QuickReason(label: ReasonStrings.quickForgot),
  const QuickReason(label: ReasonStrings.quickTooHard),
  const QuickReason(label: ReasonStrings.quickWeather),
  const QuickReason(label: _other, isOther: true),
]);

/// 「其他」选项的文案。
String get otherReasonLabel => _other;

/// 判断一段文本是否正好是某个快捷原因（用于回显选中态）。
bool isQuickReason(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return false;
  }
  return quickReasons.any((reason) => reason.label == trimmed);
}

/// 该文本是否命中了非「其他」的快捷原因。
///
/// 用于决定弹窗打开时是否需要展开自由输入框：
/// 已有原因是「其他」或完全自定义的文本时，都要把它显示在输入框里。
bool isCustomReason(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return false;
  }
  return !quickReasons
      .any((reason) => !reason.isOther && reason.label == trimmed);
}
