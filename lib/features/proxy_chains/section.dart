import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'chain.dart';
import 'editor.dart';
import 'outbounds.dart';
import 'store.dart';
import 'transform.dart';

String proxyChainIssueText(AppLocalizations l, ProxyChainIssue issue) =>
    switch (issue.kind) {
      ProxyChainIssueKind.missingHop => l.proxyChainMissingHop(issue.name),
      ProxyChainIssueKind.providerHop => l.proxyChainProviderHop(issue.name),
      ProxyChainIssueKind.unchainableHop => l.proxyChainUnchainableHop(
        issue.name,
      ),
      ProxyChainIssueKind.unreadableFilter => l.proxyChainUnreadableFilter(
        issue.name,
      ),
      ProxyChainIssueKind.repeatedHop => l.proxyChainRepeatedHop,
      ProxyChainIssueKind.nameTaken => l.proxyChainNameTaken(issue.name),
    };

/// A chain the profile's MATCH rule points at cannot go away under it.
bool _isMatchTarget(WidgetRef ref, int profileId, ProxyChain chain) {
  if (ref.read(profileProvider(profileId))?.matchTarget != chain.name) {
    return false;
  }
  dialogs.showAlert(
    message: TextSpan(
      text: currentAppLocalizations.proxyChainIsMatchTarget(chain.name),
    ),
  );
  return true;
}

/// The names the profile build will add as groups, for rule targets.
final proxyChainTargetsProvider = Provider.autoDispose.family<Set<String>, int>(
  (ref, profileId) {
    final chains = ref.watch(proxyChainsProvider(profileId)).value;
    final graph = ref.watch(proxyChainGraphProvider(profileId)).value;
    if (chains == null || graph == null) {
      return const {};
    }
    final issues = graph.issuesOf(chains);
    return {
      for (final chain in chains)
        if (chain.enabled && !issues.containsKey(chain.id)) chain.name,
    };
  },
);

Future<void> _saving(Future<void> Function() save) async {
  try {
    await save();
  } on ProxyChainsSaveException {
    dialogs.showNotifier(
      currentAppLocalizations.databaseWriteFailedTip,
      level: MessageLevel.error,
    );
  }
}

/// The extension page's chains, a beta that lives in this folder alone.
class ProxyChainsSection extends ConsumerWidget {
  const ProxyChainsSection({super.key, required this.profileId});

  final int profileId;

  void _add(BuildContext context) {
    showProxyChainEditor(context, profileId: profileId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final chains = ref.watch(proxyChainsProvider(profileId)).value ?? const [];
    final graph = ref.watch(proxyChainGraphProvider(profileId)).value;
    final issues = graph?.issuesOf(chains) ?? const {};
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListHeader(
              title: appLocalizations.proxyChainsTitle,
              trailing: const BetaPill(),
              actions: [
                IconButtonData(
                  glyph: AppGlyphs.addCircle,
                  tooltip: appLocalizations.addProxyChain,
                  onPressed: () => _add(context),
                ),
              ],
            ),
            generateSection(
              footer: appLocalizations.proxyChainsDesc,
              items: [
                if (chains.isEmpty)
                  DecorationListItem(
                    leading: const GlyphIcon(AppGlyphs.addCircle),
                    title: Text(appLocalizations.addProxyChain),
                    onPressed: () => _add(context),
                  )
                else
                  for (final chain in chains)
                    _ChainRow(
                      profileId: profileId,
                      chain: chain,
                      issue: issues[chain.id],
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainRow extends ConsumerWidget {
  const _ChainRow({
    required this.profileId,
    required this.chain,
    required this.issue,
  });

  final int profileId;
  final ProxyChain chain;
  final ProxyChainIssue? issue;

  void _edit(BuildContext context) {
    showProxyChainEditor(context, profileId: profileId, chain: chain);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (_isMatchTarget(ref, profileId, chain)) {
      return;
    }
    final appLocalizations = context.appLocalizations;
    final notifier = ref.read(proxyChainsProvider(profileId).notifier);
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteTip(appLocalizations.proxyChain),
      ),
      destructive: true,
      confirmText: appLocalizations.delete,
    );
    if (confirmed != true) {
      return;
    }
    await _saving(() => notifier.remove(chain.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final issue = this.issue;
    return ContextMenuRegion(
      menuItems: [
        CommonPopupMenuItem(
          glyph: AppGlyphs.edit,
          label: appLocalizations.edit,
          onPressed: () => _edit(context),
        ),
        CommonPopupMenuItem(
          glyph: AppGlyphs.delete,
          label: appLocalizations.delete,
          danger: true,
          onPressed: () => _delete(context, ref),
        ),
      ],
      child: DecorationListItem(
        invalid: issue != null,
        onPressed: () => _edit(context),
        leading: GlyphIcon(
          AppGlyphs.link,
          color: chain.enabled ? colorScheme.primary : colorScheme.outline,
        ),
        title: Text(chain.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: issue == null
            ? ProxyChainHops(hops: chain.hops)
            : Text(
                proxyChainIssueText(appLocalizations, issue),
                style: TextStyle(color: colorScheme.error),
              ),
        trailing: CommonSwitch(
          value: chain.enabled,
          semanticLabel: chain.name,
          onChanged: (enabled) {
            if (!enabled && _isMatchTarget(ref, profileId, chain)) {
              return;
            }
            _saving(
              () => ref
                  .read(proxyChainsProvider(profileId).notifier)
                  .put(chain.copyWith(enabled: enabled)),
            );
          },
        ),
      ),
    );
  }
}

class ProxyChainHops extends StatelessWidget {
  const ProxyChainHops({super.key, required this.hops});

  final List<String> hops;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.footnote.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (index, hop) in hops.indexed) ...[
            DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShape.sm,
                color: colorScheme.surfaceContainerHighest,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                child: Text(
                  hop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
            if (index < hops.length - 1)
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class BetaPill extends StatelessWidget {
  const BetaPill({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShape.full,
        color: colorScheme.tertiaryContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          context.appLocalizations.beta,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(color: colorScheme.onTertiaryContainer),
        ),
      ),
    );
  }
}
