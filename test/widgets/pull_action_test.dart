import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  late int pulls;

  Future<void> pump(WidgetTester tester) async {
    pulls = 0;
    await tester.pumpWidget(
      TestApp(
        child: Scaffold(
          body: PullAction(
            labels: (
              pull: 'Pull to test',
              release: 'Release to test',
              running: null,
              done: null,
            ),
            onPull: () async {
              pulls++;
              return true;
            },
            child: ListView(
              children: [
                for (var index = 0; index < 30; index++)
                  SizedBox(height: 80, child: Text('row $index')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> drag(WidgetTester tester, double dy, {int steps = 20}) async {
    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var step = 0; step < steps; step++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a touch or a scroll from the top shows no pill', (tester) async {
    await pump(tester);

    final gesture = await tester.startGesture(const Offset(200, 200));
    await gesture.moveBy(const Offset(0, 6));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Pull to test'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();

    await drag(tester, -400);
    await tester.pumpAndSettle();
    expect(find.text('Pull to test'), findsNothing);
    expect(find.text('Release to test'), findsNothing);
    expect(pulls, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a long pull says what it does and runs it', (tester) async {
    await pump(tester);

    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var step = 0; step < 30; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Release to test'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pulls, 1);
    expect(find.text('Release to test'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
