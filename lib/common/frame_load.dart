/// Says when frames keep missing 60 fps on the raster thread, whatever the
/// display runs at: a faster one missed still scrolls smoothly.
class FrameLoadWatch {
  FrameLoadWatch({this.window = 90, this.windowsInARow = 2});

  static const budget = Duration(microseconds: 16667);

  static const latePercent = 70;

  final int window;
  final int windowsInARow;

  var _frames = 0;
  var _late = 0;
  var _overloaded = 0;

  bool overloadedAfter(Iterable<Duration> rasterDurations) {
    for (final duration in rasterDurations) {
      _frames++;
      if (duration > budget) {
        _late++;
      }
      if (_frames < window) {
        continue;
      }
      _overloaded = _late * 100 > window * latePercent ? _overloaded + 1 : 0;
      _frames = 0;
      _late = 0;
      if (_overloaded == windowsInARow) {
        _overloaded = 0;
        return true;
      }
    }
    return false;
  }

  void reset() {
    _frames = 0;
    _late = 0;
    _overloaded = 0;
  }
}
