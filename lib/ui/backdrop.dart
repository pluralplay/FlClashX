import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// How much of a page backdrop shows through when the panel does not say.
const defaultBackdropVisibility = 8;

/// A picture behind every full page, dimmed by the page colour down to
/// [visibility] percent of it.
class PageBackdropScope extends InheritedWidget {
  const PageBackdropScope({
    super.key,
    required this.image,
    this.visibility = defaultBackdropVisibility,
    required super.child,
  });

  final ImageProvider? image;
  final int visibility;

  static PageBackdropScope? of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PageBackdropScope>();
    return scope?.image == null ? null : scope;
  }

  double get scrimAlpha => (1 - visibility.clamp(1, 100) / 100).toDouble();

  Color scrimOf(Color page) => page.withValues(alpha: scrimAlpha);

  @override
  bool updateShouldNotify(PageBackdropScope oldWidget) =>
      image != oldWidget.image || visibility != oldWidget.visibility;
}

class PageBackdrop extends StatelessWidget {
  const PageBackdrop({super.key, required this.scope, required this.page});

  final PageBackdropScope scope;
  final Color page;

  @override
  Widget build(BuildContext context) {
    final alpha = scope.scrimAlpha;
    return Positioned.fill(
      child: IgnorePointer(
        // An animated picture repaints on every frame; a layer of its own
        // keeps that from repainting the page above it.
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: scope.image!,
                fit: BoxFit.cover,
                onError: (_, _) {},
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    page.withValues(alpha: alpha),
                    page.withValues(alpha: (alpha - 0.04).clamp(0.0, 1.0)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [image] held on its first frame, for an animated backdrop that has to keep
/// still.
class FirstFrameImage extends ImageProvider<FirstFrameImage> {
  const FirstFrameImage(this.image);

  final ImageProvider image;

  @override
  Future<FirstFrameImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    FirstFrameImage key,
    ImageDecoderCallback decode,
  ) => _FirstFrameCompleter(image.resolve(ImageConfiguration.empty));

  @override
  bool operator ==(Object other) =>
      other is FirstFrameImage && other.image == image;

  @override
  int get hashCode => image.hashCode;
}

class _FirstFrameCompleter extends ImageStreamCompleter {
  _FirstFrameCompleter(this._source) {
    _listener = ImageStreamListener(_onFrame, onError: _onError);
    _source.addListener(_listener);
  }

  final ImageStream _source;
  late final ImageStreamListener _listener;
  var _held = false;

  void _onFrame(ImageInfo frame, bool _) {
    if (_held) {
      frame.dispose();
      return;
    }
    _held = true;
    _source.removeListener(_listener);
    setImage(frame);
  }

  void _onError(Object error, StackTrace? stack) {
    _source.removeListener(_listener);
    reportError(exception: error, stack: stack);
  }
}
