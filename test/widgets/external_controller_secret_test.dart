import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _secretLabel = 'External controller secret';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpGeneralView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 3000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: GeneralView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapControllerSwitch(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'External controller'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  PatchClashConfig config() => container.read(patchClashConfigProvider);

  testWidgets('opening the controller uses the default address and no secret', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    expect(find.text(_secretLabel), findsNothing);
    expect(find.textContaining(defaultExternalController), findsOneWidget);

    await tapControllerSwitch(tester);

    expect(config().externalController, defaultExternalController);
    expect(config().secret, isEmpty);
    expect(find.text(_secretLabel), findsOneWidget);
  });

  testWidgets('androidsecure hides the port row', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        androidSecureProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 3000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: GeneralView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PortItem), findsNothing);
  });

  testWidgets('the footer shows the address the subscription gave', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(externalController: '0.0.0.0:9091'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.0.0.0:9091'), findsOneWidget);
    expect(find.textContaining(defaultExternalController), findsNothing);
  });

  testWidgets('a secret typed into the row is kept, and may be cleared', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    await tapControllerSwitch(tester);

    await tester.tap(find.text(_secretLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  my-own-secret ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(config().secret, 'my-own-secret');

    await tester.tap(find.text(_secretLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(config().secret, isEmpty);
  });

  testWidgets('closing the controller hides the row and keeps the secret', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    await tapControllerSwitch(tester);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(secret: 'mine'));
    await tester.pumpAndSettle();

    await tapControllerSwitch(tester);

    expect(config().externalController, isEmpty);
    expect(config().secret, 'mine');
    expect(find.text(_secretLabel), findsNothing);
  });
}
