import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'chain.dart';
import 'outbounds.dart';
import 'section.dart';
import 'store.dart';
import 'transform.dart';

Future<void> showProxyChainEditor(
  BuildContext context, {
  required int profileId,
  ProxyChain? chain,
}) {
  return showFormSheet<void>(
    context: context,
    builder: (_) => ProxyChainForm(profileId: profileId, chain: chain),
  );
}

String _hopLabel(AppLocalizations l, int index, int count) {
  if (index == 0) {
    return l.proxyChainEntry;
  }
  return index == count - 1 ? l.proxyChainExit : l.proxyChainMiddle;
}

class ProxyChainForm extends ConsumerStatefulWidget {
  const ProxyChainForm({super.key, required this.profileId, this.chain});

  final int profileId;
  final ProxyChain? chain;

  @override
  ConsumerState<ProxyChainForm> createState() => _ProxyChainFormState();
}

class _ProxyChainFormState extends ConsumerState<ProxyChainForm> {
  late final _nameController = TextEditingController(text: widget.chain?.name);
  late List<String?> _hops = [...?widget.chain?.hops];
  String? _error;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    if (_hops.length < ProxyChain.minHops) {
      _hops = [null, null];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pick(int index) async {
    final picked = await showSheet<String>(
      context: context,
      builder: (_) => _HopPicker(
        profileId: widget.profileId,
        title: _hopLabel(context.appLocalizations, index, _hops.length),
        isEntry: index == 0,
        current: _hops[index],
        otherHops: {
          for (final (i, hop) in _hops.indexed)
            if (i != index && hop != null) hop,
        },
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _hops[index] = picked;
      _error = null;
    });
  }

  void _setMiddle({required bool present}) {
    setState(() {
      _hops = [_hops.first, if (present) null, _hops.last];
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final appLocalizations = context.appLocalizations;
    final name = _nameController.text.trim();
    final hops = [for (final hop in _hops) ?hop];
    if (name.isEmpty || hops.length != _hops.length) {
      setState(() => _error = appLocalizations.proxyChainIncomplete);
      return;
    }
    final chain = ProxyChain(
      id: widget.chain?.id ?? uniqueId,
      name: name,
      hops: hops,
      enabled: widget.chain?.enabled ?? true,
    );
    final chainsProvider = proxyChainsProvider(widget.profileId);
    final notifier = ref.read(chainsProvider.notifier);
    final profiles = ref.read(profilesProvider.notifier);
    final graphFuture = ref.read(
      proxyChainGraphProvider(widget.profileId).future,
    );
    setState(() => _saving = true);
    try {
      final chains = await ref.read(chainsProvider.future);
      final graph = await graphFuture;
      if (!mounted) {
        return;
      }
      final issue =
          graph?.issuesOf([chain])[chain.id] ??
          (chains.any((other) => other.id != chain.id && other.name == name)
              ? (kind: ProxyChainIssueKind.nameTaken, name: name)
              : null);
      if (issue != null) {
        setState(() => _error = proxyChainIssueText(appLocalizations, issue));
        return;
      }
      await notifier.put(chain);
      final previous = widget.chain?.name;
      if (previous != null && previous != name) {
        profiles.updateProfile(
          widget.profileId,
          (profile) => profile.matchTarget == previous
              ? profile.copyWith(matchTarget: name)
              : profile,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ProxyChainsSaveException {
      if (mounted) {
        setState(() => _error = appLocalizations.databaseWriteFailedTip);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error = error is MessageException ? error.message : '$error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final count = _hops.length;
    ref.watch(proxyChainGraphProvider(widget.profileId));
    return FormPage(
      title: widget.chain == null
          ? appLocalizations.newProxyChain
          : appLocalizations.proxyChain,
      onSave: _save,
      saving: _saving,
      error: _error,
      children: [
        generateSection(items: [_PathDiagram(hops: _hops)]),
        const ListSectionGap(),
        generateSection(
          items: [
            FormRow(
              title: appLocalizations.name,
              trailing: FormRowTextField(
                controller: _nameController,
                hintText: appLocalizations.proxyChain,
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
          ],
        ),
        const ListSectionGap(),
        generateSection(
          footer: appLocalizations.proxyChainHopsDesc,
          items: [
            for (final (index, hop) in _hops.indexed)
              FormRow(
                title: _hopLabel(appLocalizations, index, count),
                leading: index == 1 && count == ProxyChain.maxHops
                    ? EntryButton.remove(
                        onPressed: () => _setMiddle(present: false),
                      )
                    : null,
                onPressed: () => _pick(index),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Flexible(child: Text(hop ?? appLocalizations.select)),
                    const GlyphIcon(AppGlyphs.chevronForward),
                  ],
                ),
              ),
            if (count < ProxyChain.maxHops)
              FormRow(
                title: appLocalizations.addProxyChainHop,
                leading: EntryButton.add(
                  onPressed: () => _setMiddle(present: true),
                ),
                onPressed: () => _setMiddle(present: true),
              ),
          ],
        ),
      ],
    );
  }
}

class _PathDiagram extends StatelessWidget {
  const _PathDiagram({required this.hops});

  final List<String?> hops;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final connector = SizedBox(
      width: 10,
      child: Divider(thickness: 2, color: colorScheme.primary.opacity38),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Align(alignment: Alignment.centerRight, child: BetaPill()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PathEnd(
                glyph: AppGlyphs.devices,
                label: appLocalizations.proxyChainDevice,
              ),
              for (final (index, hop) in hops.indexed) ...[
                connector,
                Flexible(
                  child: _PathHop(
                    hop: hop,
                    label: _hopLabel(appLocalizations, index, hops.length),
                  ),
                ),
              ],
              connector,
              _PathEnd(
                glyph: AppGlyphs.globe,
                label: appLocalizations.proxyChainInternet,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PathEnd extends StatelessWidget {
  const _PathEnd({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      spacing: 6,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: AppShape.circle,
            color: colorScheme.surfaceContainerHighest,
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: GlyphIcon(glyph, size: 20),
          ),
        ),
        Text(
          label,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PathHop extends StatelessWidget {
  const _PathHop({required this.hop, required this.label});

  final String? hop;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final picked = hop != null;
    return Column(
      spacing: 6,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            shape: AppShape.full,
            color: picked
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
          ),
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  hop ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .copyWith(
                        color: picked
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption2
              .of(context, emphasized: true)
              .copyWith(color: colorScheme.primary),
        ),
      ],
    );
  }
}

class _HopPicker extends ConsumerWidget {
  const _HopPicker({
    required this.profileId,
    required this.title,
    required this.isEntry,
    required this.current,
    required this.otherHops,
  });

  final int profileId;
  final String title;
  final bool isEntry;
  final String? current;
  final Set<String> otherHops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final graph = ref.watch(proxyChainGraphProvider(profileId)).value;
    bool usable(String name) =>
        !otherHops.contains(name) &&
        (isEntry || (graph?.isChainable(name) ?? false));
    final groupTypes = {
      for (final MapEntry(:key, :value)
          in (graph?.groupTypes ?? const <String, String>{}).entries)
        if (usable(key)) key: value,
    };
    final proxyTypes = {
      for (final MapEntry(:key, :value)
          in (graph?.proxyTypes ?? const <String, String>{}).entries)
        if (usable(key)) key: value,
    };
    return SelectionSheet<String>(
      title: title,
      sections: [
        SelectionSection(
          label: appLocalizations.proxyGroup,
          items: groupTypes.keys.toList(),
          subtitleBuilder: (_, name) => groupTypes[name],
        ),
        SelectionSection(
          label: appLocalizations.proxies,
          items: proxyTypes.keys.toList(),
          subtitleBuilder: (_, name) => proxyTypes[name],
        ),
      ],
      labelBuilder: (item) => item,
      selectedOf: (_) => current,
      onSelected: (item) => Navigator.of(context).pop(item),
    );
  }
}
