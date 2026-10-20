import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  testWidgets('the Zashboard row follows the Resources entry once a '
      'controller address is set', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                glyph: AppGlyphs.resources,
                label: PageLabel.resources,
                modes: const [NavigationItemMode.more],
                builder: (_) => const SizedBox.shrink(),
              ),
              NavigationItem(
                glyph: AppGlyphs.logs,
                label: PageLabel.logs,
                modes: const [NavigationItemMode.more],
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1400, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ToolsView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zashboard'), findsNothing);

    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(externalController: '127.0.0.1:9091'),
        );
    await tester.pumpAndSettle();

    expect(find.text('Zashboard'), findsOneWidget);
    expect(find.text('127.0.0.1:9091'), findsOneWidget);
    expect(find.byGlyph(AppGlyphs.zashboard), findsOneWidget);
    final resources = tester.getTopLeft(find.text('Resources'));
    final dashboard = tester.getTopLeft(find.text('Zashboard'));
    final logs = tester.getTopLeft(find.text('Logs'));
    expect(dashboard.dy, greaterThan(resources.dy));
    expect(dashboard.dy, lessThan(logs.dy));
    expect(tester.takeException(), null);
  });
}
