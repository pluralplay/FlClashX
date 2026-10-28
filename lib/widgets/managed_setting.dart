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
    final managed = ref.watch(managedSettingsProvider).where(keys.contains);
    if (managed.isEmpty) {
      return const SizedBox.shrink();
    }
    final owned = ref.watch(
      appSettingProvider.select((state) => state.ownedSettings),
    );
    final appLocalizations = context.appLocalizations;
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
              managed.any(owned.contains)
                  ? '${appLocalizations.managedSettingsHint} '
                        '${appLocalizations.managedSettingsOwnedHint}'
                  : appLocalizations.managedSettingsHint,
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
    this.dimsWhenLocked = true,
    this.marksOwner = true,
  });

  final String settingKey;
  final Widget child;
  final VoidCallback? onTakenOver;

  /// False for a control that asks before its own change, so a tap both
  /// takes the setting over and makes the change.
  final bool dimsWhenLocked;

  /// False for a dashboard card, which has no row edge to carry the mark.
  final bool marksOwner;

  Future<void> _takeOver(WidgetRef ref) async {
    final taken = await ref
        .read(managedSettingsActionProvider.notifier)
        .confirmTakeOver(settingKey);
    if (taken) {
      onTakenOver?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(settingLockedProvider(settingKey));
    if (locked && !dimsWhenLocked) {
      return child;
    }
    if (locked) {
      return Semantics(
        button: true,
        label: context.appLocalizations.managedByProvider,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _takeOver(ref),
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
      child: marksOwner
          ? Semantics(
              hint: context.appLocalizations.managedByYou,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  child,
                  const PositionedDirectional(
                    start: 6,
                    top: 0,
                    bottom: 0,
                    child: Center(child: OwnedSettingMark()),
                  ),
                ],
              ),
            )
          : child,
    );
  }
}

/// The dot in the leading gutter of a row the user took over.
class OwnedSettingMark extends StatelessWidget {
  const OwnedSettingMark({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: 6,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: context.colorScheme.primary,
            shape: AppShape.circle,
          ),
        ),
      ),
    );
  }
}
