import 'package:fl_clash/widgets/rising_hold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _RecordingVibration implements RisingVibration {
  final events = <String>[];

  @override
  void rise(Duration duration) => events.add('rise ${duration.inMilliseconds}');

  @override
  void stop() => events.add('stop');
}

void main() {
  late int taps;
  late int holds;
  late _RecordingVibration vibration;

  setUp(() {
    taps = 0;
    holds = 0;
    vibration = _RecordingVibration();
  });

  Widget hold({bool enabled = true}) => MaterialApp(
    home: Center(
      child: Tooltip(
        message: 'Start',
        child: RisingHold(
          enabled: enabled,
          onHeld: () => holds++,
          vibration: vibration,
          child: FilledButton(
            onPressed: () => taps++,
            child: const Text('start'),
          ),
        ),
      ),
    ),
  );

  Future<TestGesture> press(WidgetTester tester) =>
      tester.startGesture(tester.getCenter(find.text('start')));

  testWidgets('a press held for five seconds runs the action once, under '
      'one vibration rising until then', (tester) async {
    await tester.pumpWidget(hold());
    final gesture = await press(tester);

    await tester.pump(const Duration(milliseconds: 4900));
    expect(holds, 0);
    expect(vibration.events, ['rise 4500']);
    await tester.pump(const Duration(milliseconds: 200));
    expect(holds, 1);

    await tester.pump(const Duration(seconds: 5));
    await gesture.up();
    await tester.pump();
    expect(holds, 1);
    expect(taps, 0);
    expect(vibration.events, ['rise 4500']);
  });

  testWidgets('letting go before then stops the vibration and does nothing', (
    tester,
  ) async {
    await tester.pumpWidget(hold());
    final gesture = await press(tester);

    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump(const Duration(seconds: 5));

    expect(holds, 0);
    expect(taps, 0);
    expect(vibration.events, ['rise 4500', 'stop']);
  });

  testWidgets('a hold switched off or taken away stops its vibration', (
    tester,
  ) async {
    await tester.pumpWidget(hold());
    await press(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(hold(enabled: false));
    expect(vibration.events, ['rise 4500', 'stop']);

    await tester.pumpWidget(hold());
    final gesture = await press(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    expect(vibration.events, ['rise 4500', 'stop', 'rise 4500', 'stop']);

    await tester.pump(const Duration(seconds: 5));
    await gesture.up();
    expect(holds, 0);
  });

  testWidgets('a tap still reaches the button without a vibration', (
    tester,
  ) async {
    await tester.pumpWidget(hold());

    await tester.tap(find.text('start'));
    await tester.pump(const Duration(seconds: 6));

    expect(taps, 1);
    expect(holds, 0);
    expect(vibration.events, isEmpty);
  });

  testWidgets('switched off, a long press runs nothing', (tester) async {
    await tester.pumpWidget(hold(enabled: false));
    final gesture = await press(tester);

    await tester.pump(const Duration(seconds: 6));
    await gesture.up();
    await tester.pump();

    expect(holds, 0);
    expect(vibration.events, isEmpty);
  });
}
