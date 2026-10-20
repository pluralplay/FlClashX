import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Explains the dimmed rows of a page, shown only while the subscription
/// speaks for at least one of [keys].
class ManagedSettingsHint extends ConsumerWidget {
  const ManagedSettingsHint({super.key, required this.keys});

  final Set<String> keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managed = ref.watch(
      managedSettingsProvider.select((managed) => managed.any(keys.contains)),
    );
    if (!managed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlyphIcon(
            AppGlyphs.info,
            size: 18,
            color: context.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.appLocalizations.managedSettingsHint,
              style: context.listCaptionStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row the subscription speaks for: dimmed and asking before the
/// user takes it over, then offering to hand it back from its context menu.
class ManagedSetting extends ConsumerWidget {
  const ManagedSetting({
    super.key,
    required this.settingKey,
    required this.child,
    this.onTakenOver,
  });

  final String settingKey;
  final Widget child;
  final VoidCallback? onTakenOver;

  Future<void> _takeOver(BuildContext context, WidgetRef ref) async {
    final appLocalizations = context.appLocalizations;
    final agreed = await dialogs.showMessage(
      title: appLocalizations.managedByProvider,
      message: TextSpan(text: appLocalizations.managedByProviderTip),
      confirmText: appLocalizations.takeOver,
    );
    if (agreed != true) {
      return;
    }
    ref.read(managedSettingsActionProvider.notifier).takeOver(settingKey);
    onTakenOver?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(settingLockedProvider(settingKey))) {
      return Semantics(
        button: true,
        label: context.appLocalizations.managedByProvider,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _takeOver(context, ref),
          child: Opacity(opacity: 0.5, child: IgnorePointer(child: child)),
        ),
      );
    }
    if (!ref.watch(settingReleasableProvider(settingKey))) {
      return child;
    }
    return ContextMenuRegion(
      menuItems: [
        CommonPopupMenuItem(
          glyph: AppGlyphs.lock,
          label: context.appLocalizations.returnToProvider,
          onPressed: () => ref
              .read(managedSettingsActionProvider.notifier)
              .release(settingKey),
        ),
      ],
      child: child,
    );
  }
}
