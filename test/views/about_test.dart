import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/about.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

void main() {
  late ProviderContainer container;
  late _MockCore core;

  setUp(() {
    core = _MockCore();
    when(() => core.getCoreVersion()).thenAnswer((_) async => 'v1.19.32');
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      ],
    );
    globalState.container = container;
    globalState.packageInfo = PackageInfo(
      appName: appName,
      packageName: packageName,
      version: '1.2.3',
      buildNumber: '7',
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('en'), child: AboutView()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the app and core versions as badges', (tester) async {
    await pump(tester);

    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.text('core: v1.19.32'), findsOneWidget);
    expect(find.text('GPL-3.0'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('lists the links and the people behind the fork', (tester) async {
    await pump(tester);

    expect(find.text('Original repository'), findsOneWidget);
    expect(find.text('github.com/chen08209/FlClash'), findsOneWidget);
    expect(find.text('github.com/MetaCubeX/mihomo'), findsOneWidget);
    expect(find.text('t.me/flclashx'), findsOneWidget);
    expect(find.text('Thanks for contribution'), findsOneWidget);
    expect(find.text('Gratitude'), findsOneWidget);
    for (final name in ['pluralplay', 'kastov', 'x_kit_', 'legiz']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a core that does not answer leaves the core badge out', (
    tester,
  ) async {
    when(() => core.getCoreVersion()).thenThrow(StateError('not running'));
    await pump(tester);

    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.textContaining('core:'), findsNothing);
  });
}
