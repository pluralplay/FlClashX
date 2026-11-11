import 'package:fl_clash/common/frame_load.dart';
import 'package:flutter_test/flutter_test.dart';

const _late = Duration(milliseconds: 18);
const _onTime = Duration(milliseconds: 12);

List<Duration> _window({required int late, int size = 10}) => [
  ...List.filled(late, _late),
  ...List.filled(size - late, _onTime),
];

void main() {
  test('reports overload after two late windows in a row', () {
    final watch = FrameLoadWatch(window: 10);

    expect(watch.overloadedAfter(_window(late: 8)), isFalse);
    expect(watch.overloadedAfter(_window(late: 8)), isTrue);
  });

  test('a window within budget breaks the run', () {
    final watch = FrameLoadWatch(window: 10);

    expect(watch.overloadedAfter(_window(late: 8)), isFalse);
    expect(watch.overloadedAfter(_window(late: 5)), isFalse);
    expect(watch.overloadedAfter(_window(late: 8)), isFalse);
    expect(watch.overloadedAfter(_window(late: 8)), isTrue);
  });

  test('needs more than the late share of a window', () {
    final watch = FrameLoadWatch(window: 10);

    expect(watch.overloadedAfter(_window(late: 7)), isFalse);
    expect(watch.overloadedAfter(_window(late: 7)), isFalse);
  });

  test('exactly the late share of a default window is not an overload', () {
    final watch = FrameLoadWatch();

    expect(watch.overloadedAfter(_window(late: 63, size: 90)), isFalse);
    expect(watch.overloadedAfter(_window(late: 63, size: 90)), isFalse);
    expect(watch.overloadedAfter(_window(late: 64, size: 90)), isFalse);
    expect(watch.overloadedAfter(_window(late: 64, size: 90)), isTrue);
  });

  test('counts frames across batches and starts over after a report', () {
    final watch = FrameLoadWatch(window: 10);
    final frames = [..._window(late: 9), ..._window(late: 9)];

    expect(watch.overloadedAfter(frames.take(15)), isFalse);
    expect(watch.overloadedAfter(frames.skip(15)), isTrue);
    expect(watch.overloadedAfter(_window(late: 9)), isFalse);
  });

  test('reset drops a late window already seen', () {
    final watch = FrameLoadWatch(window: 10);

    expect(watch.overloadedAfter(_window(late: 9)), isFalse);
    watch.reset();
    expect(watch.overloadedAfter(_window(late: 9)), isFalse);
  });
}
