import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class Person {
  const Person({required this.avatar, required this.name, this.link});

  final String avatar;
  final String name;
  final String? link;
}

const _contributors = [
  Person(
    avatar: 'assets/images/avatar/pluralplay.jpg',
    name: 'pluralplay',
    link: 'https://github.com/pluralplay',
  ),
  Person(
    avatar: 'assets/images/avatar/kastov.jpg',
    name: 'kastov',
    link: 'https://github.com/kastov',
  ),
];

const _thanks = [
  Person(
    avatar: 'assets/images/avatar/x_kit_.jpg',
    name: 'x_kit_',
    link: 'https://github.com/this-xkit',
  ),
  Person(
    avatar: 'assets/images/avatar/katsukibtw.jpg',
    name: 'katsukibtw',
    link: 'https://github.com/katsukibtw',
  ),
];

const _gratitude = [
  Person(avatar: 'assets/images/avatar/cool_coala.jpg', name: 'cool_coala'),
  Person(avatar: 'assets/images/avatar/arpic.jpg', name: 'arpic'),
  Person(avatar: 'assets/images/avatar/legiz.jpg', name: 'legiz'),
];

const _upstreamRepository = 'chen08209/FlClash';
const _coreRepository = 'MetaCubeX/mihomo';
const _telegram = 'https://t.me/flclashx';

/// The running core's version when it answers, else the one this build was
/// made with, else nothing.
final coreVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  String live = '';
  if (ref.watch(coreStatusProvider) == CoreStatus.connected) {
    try {
      live = await ref.read(coreHandlerProvider).getCoreVersion();
    } catch (_) {}
  }
  final version = live.isNotEmpty ? live : coreVersionDefine;
  return version.isEmpty ? null : version;
});

class AboutView extends ConsumerWidget {
  const AboutView({super.key});

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    if (ref.read(loadingProvider(LoadingTag.checkUpdate))) return;
    final commonAction = ref.read(commonActionProvider.notifier);
    final result = await globalState.loadingRun(
      () async => (release: await request.checkForUpdate()),
      title: context.appLocalizations.checkUpdate,
      tag: LoadingTag.checkUpdate,
    );
    if (result == null) return;
    unawaited(
      commonAction.checkUpdateResultHandle(data: result.release, isUser: true),
    );
  }

  Widget _buildLinkItem({
    required Glyph glyph,
    required String title,
    required String url,
    required String label,
  }) {
    return ListItem(
      leading: _LinkBadge(glyph: glyph),
      title: Text(title),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const GlyphIcon(AppGlyphs.openExternal),
      onTap: () {
        dialogs.openUrl(url);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final isLoading = ref.watch(loadingProvider(LoadingTag.checkUpdate));
    return CommonScaffold(
      isLoading: isLoading,
      title: appLocalizations.about,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.contentTopPadding, bottom: 32),
        children: [
          _AboutHero(
            isCheckingUpdate: isLoading,
            onCheckUpdate: () {
              _checkUpdate(context, ref);
            },
            onEnterDeveloperMode: () {
              ref
                  .read(appSettingProvider.notifier)
                  .update((state) => state.copyWith(developerMode: true));
              context.showNotifier(
                appLocalizations.developerModeEnableTip,
                level: MessageLevel.success,
              );
            },
            onEasterEgg: () => _showEasterEgg(context),
          ),
          const SizedBox(height: 8),
          generateSection(
            title: appLocalizations.more,
            items: [
              _buildLinkItem(
                glyph: AppGlyphs.code,
                title: appLocalizations.project,
                url: 'https://github.com/$repository',
                label: 'github.com/$repository',
              ),
              _buildLinkItem(
                glyph: AppGlyphs.link,
                title: appLocalizations.originalRepository,
                url: 'https://github.com/$_upstreamRepository',
                label: 'github.com/$_upstreamRepository',
              ),
              _buildLinkItem(
                glyph: AppGlyphs.cpu,
                title: appLocalizations.core,
                url: 'https://github.com/$_coreRepository',
                label: 'github.com/$_coreRepository',
              ),
              _buildLinkItem(
                glyph: AppGlyphs.send,
                title: 'Telegram',
                url: _telegram,
                label: 't.me/flclashx',
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.otherContributors,
            items: const [_PeopleRow(people: _contributors)],
          ),
          generateSection(
            title: appLocalizations.thanks,
            items: const [_PeopleRow(people: _thanks)],
          ),
          generateSection(
            title: appLocalizations.gratitude,
            items: const [_PeopleRow(people: _gratitude, size: 44)],
          ),
        ],
      ),
    );
  }

  void _showEasterEgg(BuildContext context) {
    dialogs
        .showMessage(
          context: context,
          title: 'REMNAFAMILY ONE LOVE',
          message: const TextSpan(text: '❤️  TRY REMNAWAVE  ❤️'),
          confirmText: 'docs.rw',
          cancelable: true,
        )
        .then((open) {
          if (open == true) {
            dialogs.openUrl('https://docs.rw');
          }
        });
  }
}

class _AboutHero extends ConsumerWidget {
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdate;
  final VoidCallback onEnterDeveloperMode;
  final VoidCallback onEasterEgg;

  const _AboutHero({
    required this.isCheckingUpdate,
    required this.onCheckUpdate,
    required this.onEnterDeveloperMode,
    required this.onEasterEgg,
  });

  static const _logoSize = 96.0;
  static const _logoInset = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final coreVersion = ref.watch(coreVersionProvider).value;
    final raised = context.raisedSurfaceLevel.colorOf(colorScheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _TapCounter(
            onEnterDeveloperMode: onEnterDeveloperMode,
            onEasterEgg: onEasterEgg,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: raised,
                shape: AppShape.all(AppCorner.fit(_logoSize)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_logoInset),
                child: Image.asset(
                  'assets/images/icon.png',
                  width: _logoSize - _logoInset * 2,
                  height: _logoSize - _logoInset * 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            appName,
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Pill(
                label: 'v${globalState.packageInfo.displayVersion}',
                color: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              if (coreVersion != null)
                _Pill(
                  label: 'core: $coreVersion',
                  color: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
              _Pill(
                label: 'GPL-3.0',
                color: raised,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              appLocalizations.desc,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.sync,
            label: appLocalizations.checkUpdate,
            onPressed: isCheckingUpdate ? null : onCheckUpdate,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color foregroundColor;

  const _Pill({
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: color, shape: AppShape.full),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(color: foregroundColor),
        ),
      ),
    );
  }
}

class _LinkBadge extends StatelessWidget {
  final Glyph glyph;

  const _LinkBadge({required this.glyph});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.md,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: GlyphIcon(
            glyph,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A row of avatars with names under them; a person with a link opens it.
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.people, this.size = 56});

  final List<Person> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          for (final person in people) _Avatar(person: person, size: size),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.size});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final link = person.link;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: size / 2,
          foregroundImage: AssetImage(person.avatar),
        ),
        const SizedBox(height: 4),
        Text(
          person.name,
          style: AppTextStyle.caption1.of(context, emphasized: link != null),
        ),
      ],
    );
    if (link == null) {
      return column;
    }
    return Tooltip(
      message: link,
      child: FocusRing(
        shape: AppShape.md,
        standsOff: true,
        child: InkWell(
          mouseCursor: clickableCursor,
          customBorder: AppShape.md,
          onTap: () => dialogs.openUrl(link),
          child: Padding(padding: const EdgeInsets.all(4), child: column),
        ),
      ),
    );
  }
}

/// Five taps on the logo open developer mode; ten in a row find the egg.
class _TapCounter extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnterDeveloperMode;
  final VoidCallback onEasterEgg;

  const _TapCounter({
    required this.child,
    required this.onEnterDeveloperMode,
    required this.onEasterEgg,
  });

  @override
  State<_TapCounter> createState() => _TapCounterState();
}

class _TapCounterState extends State<_TapCounter> {
  static const _developerTaps = 5;
  static const _easterEggTaps = 10;

  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    _timer?.cancel();
    if (_counter == _developerTaps) {
      widget.onEnterDeveloperMode();
    }
    if (_counter >= _easterEggTaps) {
      widget.onEasterEgg();
      _resetCounter();
      return;
    }
    _timer = Timer(const Duration(seconds: 1), _resetCounter);
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
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: _handleTap, child: widget.child),
    );
  }
}
