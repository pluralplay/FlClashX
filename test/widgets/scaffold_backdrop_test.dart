import 'dart:typed_data';

import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x00, //
  0x00, 0x00, 0x04, 0x00, 0x01, 0x27, 0x34, 0x27, 0x0A, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

Future<void> _pump(WidgetTester tester, {ImageProvider? image}) async {
  await tester.pumpWidget(
    TestApp(
      wrapInProviderScope: true,
      child: PageBackdropScope(
        image: image,
        visibility: 30,
        child: const CommonScaffold(
          title: 'Page',
          backgroundColor: Colors.red,
          body: SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a page without a backdrop keeps its own colour', (tester) async {
    await _pump(tester);

    expect(find.byType(PageBackdrop), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.red,
    );
  });

  testWidgets('a backdrop goes under a page made see-through', (tester) async {
    await _pump(tester, image: MemoryImage(_pixel));

    expect(find.byType(PageBackdrop), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.transparent,
    );
    final scope = PageBackdropScope.of(tester.element(find.byType(Scaffold)));
    expect(scope?.scrimAlpha, closeTo(0.7, 0.001));
    expect(tester.takeException(), isNull);
  });
}
