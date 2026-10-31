import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/home.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

class _BackSystemAction extends SystemAction {
  final List<bool> closeRequests;

  _BackSystemAction(this.closeRequests);

  @override
  void build() {}

  @override
  Future<void> handleClose([bool exit = true]) async {
    closeRequests.add(exit);
  }
}

void main() {
  Future<ProviderContainer> pumpHomeBack(
    WidgetTester tester, {
    required bool isTV,
    required List<bool> closeRequests,
    PageLabel page = PageLabel.dashboard,
  }) async {
    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                glyph: AppGlyphs.dashboard,
                label: PageLabel.dashboard,
                builder: (_) => const SizedBox.shrink(),
              ),
              NavigationItem(
                glyph: AppGlyphs.settings,
                label: PageLabel.tools,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        systemActionProvider.overrideWith(
          () => _BackSystemAction(closeRequests),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(currentPageLabelProvider.notifier).toPage(page);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: HomeBackScopeContainer(
            isTV: isTV,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('TV Back at the dashboard minimizes without requesting exit', (
    tester,
  ) async {
    final closeRequests = <bool>[];
    final container = await pumpHomeBack(
      tester,
      isTV: true,
      closeRequests: closeRequests,
    );
    expect(container.read(appSettingProvider).minimizeOnExit, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(closeRequests, [false]);
  });

  testWidgets('TV Back from another page returns to the dashboard first', (
    tester,
  ) async {
    final closeRequests = <bool>[];
    final container = await pumpHomeBack(
      tester,
      isTV: true,
      closeRequests: closeRequests,
      page: PageLabel.tools,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
    expect(closeRequests, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(closeRequests, [false]);
  });

  testWidgets('Back on other devices keeps the configured close behavior', (
    tester,
  ) async {
    final closeRequests = <bool>[];
    await pumpHomeBack(tester, isTV: false, closeRequests: closeRequests);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(closeRequests, [true]);
  });

  testWidgets('TV Back dismisses an open route before minimizing', (
    tester,
  ) async {
    final closeRequests = <bool>[];
    await pumpHomeBack(tester, isTV: true, closeRequests: closeRequests);
    final context = tester.element(find.text('Home'));
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Details'))),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(closeRequests, isEmpty);
  });
}
