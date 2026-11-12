import 'package:fl_clash/pages/stable_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<List<bool>> pumpPrompt(WidgetTester tester) async {
    final choices = <bool>[];
    await tester.pumpWidget(StableImportApp(onChoice: choices.add));
    await tester.pumpAndSettle();
    return choices;
  }

  test('the pre-init hold lasts exactly until a choice is made', () async {
    late ValueChanged<bool> choose;
    var released = 0;

    final answer = holdUntilChosen(
      show: (onChoice) => choose = onChoice,
      hold: () async =>
          () => released++,
    );
    await Future<void>.delayed(Duration.zero);
    expect(released, 0);

    choose(false);
    expect(await answer, isFalse);
    expect(released, 1);
  });

  testWidgets('retry asks to take the stable data again', (tester) async {
    final choices = await pumpPrompt(tester);

    expect(find.text('Bring over your FlClashX profiles'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(choices, [true]);
  });

  testWidgets('continue goes on without the stable data', (tester) async {
    final choices = await pumpPrompt(tester);

    await tester.tap(find.text('Continue without them'));
    await tester.pump();

    expect(choices, [false]);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Retry'))
          .onPressed,
      isNull,
    );
  });
}
