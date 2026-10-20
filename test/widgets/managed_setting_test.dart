import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/proxies/setting.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:fl_clash/widgets/managed_setting.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  const profile = Profile(
    id: 1,
    label: 'Plan',
    type: ProfileType.url,
    autoUpdateDuration: Duration.zero,
    providerHeaders: {'flclashx-settings': 'minimize'},
  );

  Future<void> pumpGeneral(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
    container.listen(profileHeadersActionProvider, (_, _) {});
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

  AppSettingProps setting() => container.read(appSettingProvider);

  Finder row() => find.widgetWithText(ListTile, 'Minimize on exit');

  testWidgets('a managed row is dimmed and asks before it is taken over', (
    tester,
  ) async {
    await pumpGeneral(tester);
    expect(setting().minimizeOnExit, isTrue);
    expect(
      find.ancestor(of: row(), matching: find.byType(Opacity)),
      findsOneWidget,
    );

    await tester.tap(row());
    await tester.pumpAndSettle();
    expect(find.text('Managed by your provider'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(setting().minimizeOnExit, isTrue);
    expect(setting().ownedSettings, isEmpty);

    await tester.tap(row());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(setting().ownedSettings, {'app.minimizeOnExit'});
    expect(setting().minimizeOnExit, isFalse);
    expect(
      find.ancestor(of: row(), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('a taken-over row is handed back from its context menu', (
    tester,
  ) async {
    await pumpGeneral(tester);
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            ownedSettings: {'app.minimizeOnExit'},
            minimizeOnExit: false,
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(row(), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand back to provider'));
    await tester.pumpAndSettle();

    expect(setting().ownedSettings, isEmpty);
    expect(setting().minimizeOnExit, isTrue);
  });

  testWidgets('one row in diagnostics hands every setting back', (
    tester,
  ) async {
    await pumpGeneral(tester);
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            ownedSettings: {'app.minimizeOnExit', 'clash.allow-lan'},
            minimizeOnExit: false,
          ),
        );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Hand settings back to provider'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Hand settings back to provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(setting().ownedSettings, isEmpty);
    expect(setting().minimizeOnExit, isTrue);
  });

  testWidgets('a view key dims its block on the theme page', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const styled = Profile(
      id: 2,
      label: 'Plan',
      type: ProfileType.url,
      autoUpdateDuration: Duration.zero,
      providerHeaders: {'flclashx-view': 'app.board:extended'},
    );
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([styled])),
        currentProfileIdProvider.overrideWithBuild((_, _) => styled.id),
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
        child: const TestApp(child: ThemeView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('Theme mode'),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Pure black mode'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  testWidgets('the hint shows only on a page with a managed row', (
    tester,
  ) async {
    await pumpGeneral(tester);
    expect(
      find.text(
        'Dimmed settings are set by your subscription. '
        'Tap one to change it yourself.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesSetting()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ManagedSettingsHint), findsOneWidget);
    expect(find.textContaining('Dimmed settings'), findsNothing);
  });
}
