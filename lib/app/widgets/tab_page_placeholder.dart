import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';

/// Tab 页占位骨架：标题 + 空态。
///
/// 仅用于阶段 0 的 Tab 外壳（任务 0.5），后续各 Tab 任务会用真实页面替换。
class TabPagePlaceholder extends StatelessWidget {
  const TabPagePlaceholder({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: theme.textStyle(size: 20)),
            ),
          ),
          Expanded(
            child: Center(child: AnimalEmpty(description: description)),
          ),
        ],
      ),
    );
  }
}
