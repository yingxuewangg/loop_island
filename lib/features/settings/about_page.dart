import 'package:animal_island_flutter/animal_island_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_island/app/l10n_strings.dart';
import 'package:loop_island/services/app_paths.dart';
import 'package:loop_island/app/design_tokens.dart';
import 'package:loop_island/app/widgets/island_widgets.dart';

/// 关于页内可被测试稳定定位的控件键。
abstract final class AboutKeys {
  static const appInfo = Key('about-app-info');
  static const storage = Key('about-storage');
  static const privacy = Key('about-privacy');
}

/// 关于 / 隐私说明页（任务 8.10）。
///
/// PRD 的定位是「本地优先、无账号」，所以这一页要回答用户最关心的三件事：
/// 这是什么应用、我的数据放在哪、会不会被传走。三块依次排开，
/// **不藏二级入口** —— 隐私说明需要点两次才能看到，就等于没有说明。
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String? _directory;
  bool _loadingPath = true;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final directory =
        await ref.read(appPathsProvider).storageDirectory();
    if (mounted) {
      setState(() {
        _directory = directory;
        _loadingPath = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AboutStrings.title),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ---- 应用信息 ----
          IslandCard(
            key: AboutKeys.appInfo,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppInfo.appName,
                  style: theme.textStyle(size: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  AppInfo.appNameEn,
                  style: theme.textStyle(
                    size: 13,
                    color: theme.secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AboutStrings.positioning,
                  style: theme.textStyle(size: 14),
                ),
                const SizedBox(height: 10),
                IslandTag(
                  colors: IslandTagColors.plan,
                  child: Text(AboutStrings.version(AppInfo.version)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 数据存储位置 ----
          IslandCard(
            key: AboutKeys.storage,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AboutStrings.storageTitle,
                  style: theme.textStyle(size: 15),
                ),
                const SizedBox(height: 8),
                _PathRow(
                  label: AboutStrings.storageDirectoryLabel,
                  value: _loadingPath
                      ? CommonStrings.loading
                      : (_directory ?? AboutStrings.storageUnknown),
                ),
                const SizedBox(height: 6),
                _PathRow(
                  label: AboutStrings.storageFileLabel,
                  value: kStorageFileName,
                ),
                const SizedBox(height: 10),
                Text(
                  AboutStrings.storageHint,
                  style: theme.textStyle(
                    size: 12,
                    color: theme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 隐私说明 ----
          IslandCard(
            key: AboutKeys.privacy,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AboutStrings.privacyTitle,
                  style: theme.textStyle(size: 15),
                ),
                const SizedBox(height: 8),
                for (final point in AboutStrings.privacyPoints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 6),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: theme.primaryColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            point,
                            style: theme.textStyle(size: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「目录 / 文件」一行：标签固定宽度，路径可以换行。
class _PathRow extends StatelessWidget {
  const _PathRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = AnimalTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: theme.textStyle(
              size: 13,
              color: theme.secondaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textStyle(size: 13),
          ),
        ),
      ],
    );
  }
}
