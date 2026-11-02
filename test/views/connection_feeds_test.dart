import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/navigation.dart';
import 'package:fl_clash/views/views.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late int connectionReads;

  setUp(() {
    connectionReads = 0;
    final core = _MockCoreHandlerInterface();
    when(core.getConnections).thenAnswer((_) async {
      connectionReads++;
      return const <TrackerInfo>[];
    });
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('switches between the two feeds from the title menu and keeps '
      'the choice', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ConnectionFeedsView()),
      ),
    );
    await settle(tester);

    expect(find.byType(ConnectionsView), findsOneWidget);
    expect(find.byType(RequestsView), findsNothing);

    await tester.tap(find.text('Live connections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent requests'));
    await tester.pumpAndSettle();

    expect(find.byType(RequestsView), findsOneWidget);
    expect(find.byType(ConnectionsView), findsNothing);
    expect(container.read(appSettingProvider).requestFeed, RequestFeed.recent);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a hidden feed keeps its state and stops polling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ConnectionFeedsView()),
      ),
    );
    await settle(tester);
    Future<void> select(String shown, String next) async {
      await tester.tap(find.text(shown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(next));
      await tester.pumpAndSettle();
    }

    await select('Live connections', 'Recent requests');
    final recent = tester.state(find.byType(RequestsView));
    final readsWhileHidden = connectionReads;
    await tester.pump(const Duration(seconds: 3));
    expect(connectionReads, readsWhileHidden);

    await select('Recent requests', 'Live connections');
    await tester.pump(const Duration(seconds: 2));
    expect(connectionReads, greaterThan(readsWhileHidden));

    await select('Live connections', 'Recent requests');
    expect(tester.state(find.byType(RequestsView)), same(recent));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  test('navigation offers the two feeds as one connections page', () {
    final labels = navigation
        .getItems(hasProxies: true)
        .map((item) => item.label);

    expect(labels, contains(PageLabel.connections));
    expect(labels, isNot(contains(PageLabel.requests)));
  });
}
