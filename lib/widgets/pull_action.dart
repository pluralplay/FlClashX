import 'dart:async';

import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// What the pill says: while pulling, once far enough, while [PullAction.onPull]
/// runs and after it succeeded; a stage without words shows no pill.
typedef PullLabels = ({
  String pull,
  String release,
  String? running,
  String? done,
});

/// A long pull down [child] runs [onPull]; a pill under the bar says what the
/// pull will do, and the content steps down under it. Any vertical scroll in
/// [child] takes the pull, nested ones included, and scrolls even when its
/// content fits.
class PullAction extends StatefulWidget {
  const PullAction({
    super.key,
    required this.labels,
    required this.onPull,
    required this.child,
  });

  final PullLabels labels;

  /// Whether the action succeeded, which shows [PullLabels.done].
  final Future<bool> Function() onPull;
  final Widget child;

  @override
  State<PullAction> createState() => _PullActionState();
}

enum _PullStage { pulling, armed, updating, updated }

class _PullActionState extends State<PullAction> {
  static const _updatedHold = Duration(milliseconds: 1600);
  static const _pillRoom = 48.0;

  /// How far past the top a finger drags before the pill shows: a touch, or
  /// a scroll that starts at the top, is not yet a pull.
  static const _revealAfter = 16.0;

  _PullStage? _stage;
  double _pulled = 0;
  Timer? _updatedTimer;

  @override
  void dispose() {
    _updatedTimer?.cancel();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    final stage = switch (status) {
      RefreshIndicatorStatus.drag => _PullStage.pulling,
      RefreshIndicatorStatus.armed => _PullStage.armed,
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh => _PullStage.updating,
      _ => _stage == _PullStage.updated ? _PullStage.updated : null,
    };
    if (stage != _stage) {
      setState(() => _stage = stage);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    var pulled = _pulled;
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      pulled -= notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) > 0) {
      pulled = 0;
    } else if (notification is ScrollEndNotification) {
      pulled = 0;
    }
    final crossed = (pulled >= _revealAfter) != (_pulled >= _revealAfter);
    _pulled = pulled;
    if (crossed) {
      setState(() {});
    }
    return false;
  }

  Future<void> _run() async {
    final done = await widget.onPull();
    if (!mounted) {
      return;
    }
    _updatedTimer?.cancel();
    if (!done) {
      setState(() => _stage = null);
      return;
    }
    setState(() => _stage = _PullStage.updated);
    _updatedTimer = Timer(_updatedHold, () {
      if (mounted && _stage == _PullStage.updated) {
        setState(() => _stage = null);
      }
    });
  }

  String? _labelOf(_PullStage stage) => switch (stage) {
    _PullStage.pulling => widget.labels.pull,
    _PullStage.armed => widget.labels.release,
    _PullStage.updating => widget.labels.running,
    _PullStage.updated => widget.labels.done,
  };

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final shown = stage == _PullStage.pulling && _pulled < _revealAfter
        ? null
        : stage;
    final label = shown == null ? null : _labelOf(shown);
    final motion = context.motionDuration(const Duration(milliseconds: 220));
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: _run,
          onStatusChange: _onStatus,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical,
          // A translation moves the cards without laying the list out again.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: label == null ? 0 : _pillRoom),
            duration: motion,
            curve: Curves.easeOutCubic,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ScrollConfiguration(
                // The platform's own physics keep the list at its edge; the pill
                // and the step down answer the pull instead of Android's stretch.
                behavior: ScrollConfiguration.of(context).copyWith(
                  physics: AlwaysScrollableScrollPhysics(
                    parent: ScrollConfiguration.of(
                      context,
                    ).getScrollPhysics(context),
                  ),
                  overscroll: false,
                ),
                child: widget.child,
              ),
            ),
            // Clipped, so the cards slide under the start button below.
            builder: (_, shift, child) => ClipRect(
              child: Transform.translate(
                offset: Offset(0, shift),
                child: child,
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: motion,
                child: shown == null || label == null
                    ? const SizedBox.shrink()
                    : _PullPill(
                        key: ValueKey(shown),
                        stage: shown,
                        label: label,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PullPill extends StatelessWidget {
  const _PullPill({super.key, required this.stage, required this.label});

  final _PullStage stage;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.footnote
        .of(context, emphasized: true)
        .copyWith(color: colorScheme.onSurface);
    final Widget icon = switch (stage) {
      _PullStage.updating => const CommonCircleLoading(size: 16),
      _PullStage.updated => GlyphIcon(
        AppGlyphs.check,
        size: 18,
        color: colorScheme.success,
      ),
      _ => GlyphIcon(
        AppGlyphs.refresh,
        size: 18,
        color: stage == _PullStage.armed
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            SizedBox.square(dimension: 18, child: Center(child: icon)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
