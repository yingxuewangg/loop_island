import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/core/date_x.dart';

/// 原因展示组件（任务 6.4）。
///
/// 三处复用（任务详情、某天详情、统计页未完成记录），因此状态语义必须一致：
/// - 没有原因 → 「未填写原因」+ 补充入口
/// - 有原因 → 原因文本 + 更新时间 + 修改入口
///
/// [onEdit] 为空时只读展示（统计页那种场景不需要入口）。
class ReasonView extends StatelessWidget {
  const ReasonView({
    super.key,
    required this.reason,
    this.reasonUpdatedAt,
    this.onEdit,
    this.dense = false,
  });

  final String? reason;
  final DateTime? reasonUpdatedAt;

  /// 点击「补充原因 / 修改原因」的回调；为空时隐藏按钮。
  final VoidCallback? onEdit;

  /// 紧凑排版（用于列表行内）。
  final bool dense;

  bool get _hasReason => (reason ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);
    final bodyStyle = theme.textStyle(
      size: dense ? 12 : 13,
      color: _hasReason ? theme.textColor : theme.disabledTextColor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _hasReason ? reason!.trim() : ReasonStrings.noReason,
                style: bodyStyle,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 8),
              _EditAction(
                label: _hasReason
                    ? ReasonStrings.editReason
                    : ReasonStrings.addReason,
                onTap: onEdit!,
              ),
            ],
          ],
        ),
        if (_hasReason && reasonUpdatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              ReasonStrings.updatedAt(formatHm(reasonUpdatedAt!)),
              style: theme.textStyle(
                size: 11,
                color: theme.secondaryTextColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _EditAction extends StatelessWidget {
  const _EditAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: theme.textStyle(size: 12, color: theme.primaryColor),
        ),
      ),
    );
  }
}
