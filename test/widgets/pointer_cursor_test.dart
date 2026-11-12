import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
).withAppShapes.withAppSurfaces.withPointerCursor;

const _device = 1;

MouseCursor? _cursor() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(_device);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: _device,
  );
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  return gesture;
}

/// Sweeps the pointer over [finder] from its edge through its center to the
/// far edge, checking the cursor at every stop.
Future<void> _expectHandAcross(
  WidgetTester tester,
  TestGesture gesture,
  Finder finder,
) async {
  final rect = tester.getRect(finder);
  for (final point in [
    rect.topLeft + const Offset(2, 2),
    rect.center,
    rect.centerRight - const Offset(2, 0),
    rect.bottomCenter - const Offset(0, 2),
  ]) {
    await gesture.moveTo(point);
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.click, reason: '$finder at $point');
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: _theme,
  home: Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 24,
        children: [child],
      ),
    ),
  ),
);

void main() {
  testWidgets('a filled button shows the hand across its label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(FilledButton(onPressed: () {}, child: const Text('Press this one'))),
    );
    final gesture = await _mouse(tester);
    await _expectHandAcross(tester, gesture, find.byType(FilledButton));
    await _expectHandAcross(tester, gesture, find.text('Press this one'));
  });

  testWidgets('an icon button and a switch show the hand', (tester) async {
    await tester.pumpWidget(
      _app(
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 24,
          children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ),
    );
    final gesture = await _mouse(tester);
    await _expectHandAcross(tester, gesture, find.byType(IconButton));
    await _expectHandAcross(tester, gesture, find.byType(Switch));
  });

  testWidgets('a disabled button keeps the arrow', (tester) async {
    await tester.pumpWidget(
      _app(const FilledButton(onPressed: null, child: Text('Nope'))),
    );
    final gesture = await _mouse(tester);
    await gesture.moveTo(tester.getCenter(find.byType(FilledButton)));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.basic);
  });

  testWidgets('an ink well with the clickable cursor keeps the hand over '
      'its text, ring and tooltip', (tester) async {
    await tester.pumpWidget(
      _app(
        Tooltip(
          message: 'Details',
          child: FocusRing(
            shape: AppShape.xs,
            standsOff: true,
            child: InkWell(
              mouseCursor: clickableCursor,
              onTap: () {},
              customBorder: AppShape.xs,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('203.0.113.9'),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await _mouse(tester);
    await _expectHandAcross(tester, gesture, find.byType(InkWell));
    await _expectHandAcross(tester, gesture, find.text('203.0.113.9'));
    await tester.pump(const Duration(seconds: 2));
    await _expectHandAcross(tester, gesture, find.text('203.0.113.9'));
  });
}
