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
    this.showsLock = true,
  });

  final String settingKey;
  final Widget child;
  final VoidCallback? onTakenOver;

  /// False for a control that asks before its own change, so a tap both
  /// takes the setting over and makes the change.
  final bool dimsWhenLocked;

  /// False for a dashboard card, which has no title to carry the lock.
  final bool showsLock;

  Future<void> _takeOver(WidgetRef ref) async {
    final taken = await ref
        .read(managedSettingsActionProvider.notifier)
        .confirmTakeOver(settingKey);
    if (taken) {
      onTakenOver?.call();
    }
  }

  Widget _withLock(Widget child, {required bool locked}) {
    if (!showsLock) {
      return child;
    }
    return TitleBadge(
      badge: SettingLock(locked: locked),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(settingLockedProvider(settingKey));
    if (locked && !dimsWhenLocked) {
      return child;
    }
    if (locked) {
      return _LockedSetting(
        onTakeOver: () => _takeOver(ref),
        child: _withLock(child, locked: true),
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
      child: Semantics(
        hint: context.appLocalizations.managedByYou,
        child: _withLock(child, locked: false),
      ),
    );
  }
}

/// Closed while the subscription speaks for a setting, open once it is the
/// user's.
class SettingLock extends StatelessWidget {
  const SettingLock({super.key, required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ExcludeSemantics(
      child: GlyphIcon(
        locked ? AppGlyphs.lock : AppGlyphs.lockOpen,
        size: 16,
        color: locked ? colorScheme.onSurfaceVariant : colorScheme.primary,
      ),
    );
  }
}

/// Keyboard and remote focus stop at the row itself, so Enter asks before a
/// takeover as a tap does rather than reaching the control under the dimming.
class _LockedSetting extends StatefulWidget {
  const _LockedSetting({required this.onTakeOver, required this.child});

  final VoidCallback onTakeOver;
  final Widget child;

  @override
  State<_LockedSetting> createState() => _LockedSettingState();
}

class _LockedSettingState extends State<_LockedSetting> {
  bool _focused = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTakeOver();
        return null;
      },
    ),
  };

  RoundedSuperellipseBorder _shape(BuildContext context) {
    final position = ItemPositionProvider.of(context)?.position;
    if (position == null) {
      return AppShape.xl;
    }
    final isStart =
        position == ItemPosition.start || position == ItemPosition.startAndEnd;
    final isEnd =
        position == ItemPosition.end || position == ItemPosition.startAndEnd;
    return AppShape.of(
      AppRadius.vertical(
        top: isStart ? AppCorner.xl : AppCorner.none,
        bottom: isEnd ? AppCorner.xl : AppCorner.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        button: true,
        label: context.appLocalizations.managedByProvider,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTakeOver,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: _shape(context).copyWith(
                side: _focused
                    ? focusRingSide(context.colorScheme)
                    : BorderSide.none,
              ),
            ),
            child: Opacity(
              opacity: 0.5,
              child: ExcludeFocus(child: IgnorePointer(child: widget.child)),
            ),
          ),
        ),
      ),
    );
  }
}
