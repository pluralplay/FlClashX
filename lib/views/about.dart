import 'dart:async';
import 'dart:io';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';

@immutable
class Contributor {
  const Contributor({
    this.avatar,
    required this.name,
    required this.link,
    this.clickable = true,
  });
  final String? avatar;
  final String name;
  final String link;
  final bool clickable;
}

@immutable
class ThanksPerson {
  const ThanksPerson({
    this.avatar,
    required this.name,
  });
  final String? avatar;
  final String name;
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  Future<void> _checkUpdate(BuildContext context) async {
    final commonScaffoldState = context.commonScaffoldState;
    if (commonScaffoldState?.mounted != true) return;
    final data = await commonScaffoldState?.loadingRun<Map<String, dynamic>?>(
      request.checkForUpdate,
      title: appLocalizations.checkUpdate,
    );
    globalState.appController.checkUpdateResultHandle(
      data: data,
      handleError: true,
    );
  }

  List<Widget> _buildThanksForContributionSection(BuildContext context) {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/x_kit_.jpg",
        name: "x_kit_",
        link: "https://github.com/this-xkit",
      ),
      Contributor(
        avatar: "assets/images/avatars/katsukibtw.jpg",
        name: "katsukibtw",
        link: "https://github.com/katsukibtw",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.thanks,
      items: [
        ListItem(
          title: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final contributor in contributors)
                Avatar(
                  contributor: contributor,
                  size: 48.0,
                ),
            ],
          ),
        )
      ],
    );
  }

  List<Widget> _buildGratitudeSection(BuildContext context) {
    const gratitude = [
      ThanksPerson(
        name: "cool_coala",
        avatar: "assets/images/avatars/cool_coala.jpg",
      ),
      ThanksPerson(
        name: "arpic",
        avatar: "assets/images/avatars/arpic.jpg",
      ),
      ThanksPerson(
        name: "legiz",
        avatar: "assets/images/avatars/legiz.jpg",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.gratitude,
      items: [
        ListItem(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              for (final person in gratitude)
                SizedBox(
                  width: 70,
                  child: ThanksAvatar(
                    person: person,
                  ),
                ),
            ],
          ),
        )
      ],
    );
  }

  List<Widget> _buildMoreSection(BuildContext context) => generateSection(
        separated: false,
        title: appLocalizations.more,
        items: [
          ListItem(
            title: Text(appLocalizations.checkUpdate),
            onTap: () {
              _checkUpdate(context);
            },
            trailing: const Icon(Icons.update),
          ),
          if (system.isDesktop) const _CoreUpdateItem(),
          ListItem(
            title: Text(appLocalizations.project),
            onTap: () {
              globalState.openUrl(
                "https://github.com/$repository",
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
          ListItem(
            title: Text(appLocalizations.originalRepository),
            onTap: () {
              globalState.openUrl(
                "https://github.com/chen08209/FlClash",
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
          ListItem(
            title: Text(appLocalizations.core),
            onTap: () {
              globalState.openUrl(
                "https://github.com/MetaCubeX/mihomo",
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
        ],
      );

  List<Widget> _buildContributorsSection() {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/pluralplay.jpg",
        name: "pluralplay",
        link: "https://github.com/pluralplay",
      ),
      Contributor(
        avatar: "assets/images/avatars/kastov.jpg",
        name: "kastov",
        link: "https://github.com/kastov",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.otherContributors,
      items: [
        ListItem(
          title: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final contributor in contributors)
                Avatar(
                  contributor: contributor,
                ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EasterEggDetector(
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.asset(
                      'assets/images/icon.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        globalState.packageInfo.version,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      const _CoreVersionWidget(),
                    ],
                  )
                ],
              ),
              onEasterEgg: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text(
                      'REMNAFAMILY ONE LOVE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '❤️',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 48),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () {
                            globalState.openUrl('https://docs.rw');
                          },
                          child: const Text(
                            'TRY REMNAWAVE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.blue,
                              fontFamily: 'Unbounded',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    actionsAlignment: MainAxisAlignment.center,
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(
              height: 24,
            ),
            Text(
              appLocalizations.desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(
        height: 12,
      ),
      ..._buildContributorsSection(),
      ..._buildThanksForContributionSection(context),
      ..._buildGratitudeSection(context),
      ..._buildMoreSection(context),
    ];
    return Padding(
      padding: kMaterialListPadding.copyWith(
        top: 16,
        bottom: 16,
      ),
      child: generateListView(items),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.contributor,
    this.size = 56.0,
  });
  final Contributor contributor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarSize = size;
    final fontSize = size * 0.25; // 14.0 for 56px
    final avatarFontSize = size * 0.46; // 26.0 for 56px

    final avatarWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: CircleAvatar(
            foregroundImage: contributor.avatar != null
                ? AssetImage(contributor.avatar!) as ImageProvider
                : null,
            backgroundColor: contributor.avatar == null
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: contributor.avatar == null
                ? Text(
                    contributor.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Unbounded',
                      fontSize: avatarFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          contributor.name,
          style: TextStyle(
            fontFamily: 'Unbounded',
            fontSize: fontSize,
          ),
        )
      ],
    );

    if (contributor.clickable) {
      return GestureDetector(
        onTap: () {
          globalState.openUrl(contributor.link);
        },
        child: avatarWidget,
      );
    }

    return avatarWidget;
  }
}

class ThanksAvatar extends StatelessWidget {
  const ThanksAvatar({
    super.key,
    required this.person,
  });
  final ThanksPerson person;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 36.0;
    const fontSize = 9.0;
    const avatarFontSize = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: CircleAvatar(
            foregroundImage: person.avatar != null
                ? AssetImage(person.avatar!) as ImageProvider
                : null,
            backgroundColor: person.avatar == null
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: person.avatar == null
                ? Text(
                    person.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: 'Unbounded',
                      fontSize: avatarFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          person.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Unbounded',
            fontSize: fontSize,
          ),
        )
      ],
    );
  }
}

class _CoreVersionWidget extends StatelessWidget {
  const _CoreVersionWidget();

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        // Prefer the running instance — after a standalone core update it is
        // the only truthful source; the build-time constant covers a stopped
        // core.
        future: clashCore.getCoreVersion(),
        builder: (context, snapshot) {
          final live = snapshot.data;
          final coreVersion =
              live != null && live.isNotEmpty ? live : globalState.coreVersion;
          if (coreVersion == null || coreVersion.isEmpty) {
            return const SizedBox.shrink();
          }
          return Text(
            'Core: $coreVersion',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        },
      );
}

class _CoreUpdateItem extends StatefulWidget {
  const _CoreUpdateItem();

  @override
  State<_CoreUpdateItem> createState() => _CoreUpdateItemState();
}

class _CoreUpdateItemState extends State<_CoreUpdateItem> {
  Map<String, dynamic>? _release;
  bool _busy = false;
  bool _downloading = false;
  double _progress = 0;
  String _error = '';
  bool _initialCheckDone = false;

  String get _coreAssetName {
    final arch = Platform.version.contains('arm64') ||
            Platform.version.contains('aarch64')
        ? 'arm64'
        : 'amd64';
    final platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : 'linux';
    final ext = Platform.isWindows ? '.exe' : '';
    return 'FlClashCore-$platform-$arch$ext';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialCheckDone) {
      _initialCheckDone = true;
      _check();
    }
  }

  Future<void> _check() async {
    try {
      final coreVersion = await clashCore.getCoreVersion();
      final currentVersion =
          coreVersion.isNotEmpty ? coreVersion : globalState.coreVersion ?? '';
      if (currentVersion.isEmpty) {
        return;
      }
      final release = await request.checkForCoreUpdate(currentVersion);
      if (mounted && release != null) {
        setState(() => _release = release);
      }
    } catch (_) {
      // The item only appears when an update is found; stay hidden on errors.
    }
  }

  Future<void> _download() async {
    if (_busy || _release == null) {
      return;
    }
    final assets = _release!['assets'] as List<dynamic>? ?? [];
    final name = _coreAssetName;
    final asset = assets
        .cast<Map<String, dynamic>>()
        .where((a) => (a['name'] as String?) == name)
        .firstOrNull;
    if (asset == null) {
      setState(() => _error = '$name not found');
      return;
    }
    final url = asset['browser_download_url'] as String;
    setState(() {
      _busy = true;
      _downloading = true;
      _progress = 0;
      _error = '';
    });
    final error = await request.downloadCoreUpdate(
      url,
      await appPath.corePendingPath,
      onProgress: (received, total) {
        if (!mounted || total <= 0) return;
        setState(() => _progress = received / total);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _downloading = false;
      if (error != null) {
        _error = error;
      }
    });
    if (error == null) {
      _showRestartDialog();
    }
  }

  void _showRestartDialog() {
    globalState.showCommonDialog(
      dismissible: false,
      child: CommonDialog(
        title: appLocalizations.coreUpdateSuccess,
        actions: [
          TextButton(
            onPressed: () {
              // Restart only the core, not the whole app. reStart applies the
              // pending binary (helper swap on Windows) and re-inits in place, so
              // the Dart run-state stays in sync — a full app restart
              // (handleRestart) left the UI thinking the core was stopped while it
              // was actually up and proxying.
              // Close the dialog + the About sheet and jump to the dashboard so the
              // restart happens on the main screen, not buried in settings.
              globalState.navigatorKey.currentState
                  ?.popUntil((route) => route.isFirst);
              globalState.appController.toPage(PageLabel.dashboard);
              globalState.appController.restartCore();
            },
            child: Text(appLocalizations.restart),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    if (release == null) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.primary;
    final tag = (release['tag_name'] as String).replaceFirst('core-', '');
    final subtitle = _error.isNotEmpty
        ? '${appLocalizations.coreUpdateFailed}: $_error'
        : _downloading
            ? appLocalizations.coreUpdateDownloading
            : tag;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListItem(
          title: Text(
            appLocalizations.coreUpdateAvailable,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subtitle),
          onTap: _download,
          trailing: Icon(Icons.system_update, color: color),
        ),
        if (_downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
            ),
          ),
      ],
    );
  }
}

class _EasterEggDetector extends StatefulWidget {
  const _EasterEggDetector({
    required this.child,
    required this.onEasterEgg,
  });
  final Widget child;
  final VoidCallback onEasterEgg;

  @override
  State<_EasterEggDetector> createState() => _EasterEggDetectorState();
}

class _EasterEggDetectorState extends State<_EasterEggDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    if (_counter >= 10) {
      widget.onEasterEgg();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _handleTap,
        child: widget.child,
      );
}
