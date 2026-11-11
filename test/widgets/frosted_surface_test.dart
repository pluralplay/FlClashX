import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const surface = Color(0xFF202020);
  const radius = BorderRadius.all(Radius.circular(24));

  test('frost lets 40% through, 55% in ultra, flat and without a rim', () {
    final standard = LiquidGlassStyle.frost(
      surface,
      LiquidGlassQuality.standard,
    );
    final ultra = LiquidGlassStyle.frost(surface, LiquidGlassQuality.ultra);

    expect(standard.tint.a, moreOrLessEquals(0.6));
    expect(ultra.tint.a, moreOrLessEquals(0.45));
    expect(standard.refraction, 0);
    expect(standard.bevel, 0);
    expect(standard.rim, 0);
    expect(standard.blur, greaterThan(0));
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool glass,
    LiquidGlassQuality quality = LiquidGlassQuality.ultra,
    Widget? child,
  }) => tester.pumpWidget(
    MaterialApp(
      home: LiquidGlassScope(
        enabled: glass,
        quality: quality,
        child: Center(
          child:
              child ??
              const FrostedSurface(
                color: surface,
                radius: radius,
                child: SizedBox.square(dimension: 80),
              ),
        ),
      ),
    ),
  );

  testWidgets('a surface stays solid while glass is off', (tester) async {
    await pump(tester, glass: false);

    expect(find.byType(LiquidGlass), findsNothing);
    final decoration =
        tester.widget<Container>(find.byType(Container)).decoration!
            as ShapeDecoration;
    expect(decoration.color, surface);
  });

  testWidgets('a surface stays solid on the standard tier', (tester) async {
    await pump(tester, glass: true, quality: LiquidGlassQuality.standard);

    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('a surface frosts in its corners once glass is on', (
    tester,
  ) async {
    await pump(tester, glass: true);

    final pane = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    expect(pane.borderRadius, radius);
    expect(pane.style.tint.a, moreOrLessEquals(0.45));
  });

  testWidgets('a frosted sheet clears the pages in it', (tester) async {
    late Color pageColor;
    FrostScope? frost;
    await pump(
      tester,
      glass: true,
      child: FrostedSheet(
        color: surface,
        child: Builder(
          builder: (context) {
            pageColor = Theme.of(context).scaffoldBackgroundColor;
            frost = FrostScope.maybeOf(context);
            return const SizedBox.square(dimension: 80);
          },
        ),
      ),
    );

    expect(find.byType(LiquidGlass), findsOneWidget);
    expect(pageColor, Colors.transparent);
    expect(frost?.surface, surface);
    expect(
      frost?.opacity,
      LiquidGlassStyle.frostOpacity(LiquidGlassQuality.ultra),
    );
  });

  testWidgets('a solid sheet offers no frost to fill over', (tester) async {
    FrostScope? frost;
    await pump(
      tester,
      glass: false,
      child: FrostedSheet(
        color: surface,
        child: Builder(
          builder: (context) {
            frost = FrostScope.maybeOf(context);
            return const SizedBox.square(dimension: 80);
          },
        ),
      ),
    );

    expect(frost, isNull);
  });

  testWidgets('a card frosts on its own and only fills over a frost', (
    tester,
  ) async {
    await pump(
      tester,
      glass: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonCard(
            onPressed: () {},
            child: const SizedBox(width: 80, height: 40),
          ),
          FrostedSurface(
            color: surface,
            radius: radius,
            child: CommonCard(
              onPressed: () {},
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ],
      ),
    );

    expect(find.byType(LiquidGlass), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(LiquidGlass),
        matching: find.byType(LiquidGlass),
      ),
      findsNothing,
    );
  });

  test('a frost leaves its own color clear and thins any other', () {
    const frost = FrostScope(
      surface: surface,
      opacity: 0.6,
      child: SizedBox.shrink(),
    );

    expect(frost.fillOf(surface), Colors.transparent);
    expect(frost.fillOf(Colors.white).a, moreOrLessEquals(0.6));
  });

  testWidgets('a group of rows shares one frost, not a pane a row', (
    tester,
  ) async {
    await pump(
      tester,
      glass: true,
      child: SizedBox(
        width: 300,
        child: generateSection(
          items: [
            ListItem(title: const Text('a'), onTap: () {}),
            ListItem(title: const Text('b'), onTap: () {}),
          ],
        ),
      ),
    );

    expect(find.byType(DecorationListItem), findsNWidgets(2));
    expect(find.byType(LiquidGlass), findsOneWidget);
  });

  testWidgets('a row outside a group thins its fill without a pane', (
    tester,
  ) async {
    await pump(
      tester,
      glass: true,
      child: SizedBox(
        width: 300,
        child: ItemPositionProvider(
          position: ItemPosition.startAndEnd,
          child: ListItem(title: const Text('a'), onTap: () {}),
        ),
      ),
    );

    expect(find.byType(DecorationListItem), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
  });
}
