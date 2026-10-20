import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

Profile _profile({
  required Duration left,
  String? renew,
  String? service,
  int id = 1,
}) => Profile(
  id: id,
  label: 'Plan',
  type: ProfileType.url,
  url: 'https://sub.example/x',
  autoUpdateDuration: const Duration(hours: 24),
  subscriptionInfo: SubscriptionInfo(
    expire: DateTime.now().add(left).millisecondsSinceEpoch ~/ 1000,
  ),
  providerHeaders: {
    'flclashx-buyplan': ?renew,
    'flclashx-servicename': ?service,
  },
);

class _FakeNotifications implements NotificationPort {
  final shown = <({String title, String body, String? url})>[];
  bool available = true;

  @override
  Future<bool> show({
    required String title,
    required String body,
    required String channelName,
    String? url,
  }) async {
    if (!available) {
      return false;
    }
    shown.add((title: title, body: body, url: url));
    return true;
  }
}

void main() {
  late ProviderContainer container;
  late _FakeNotifications notifications;

  setUp(() {
    notifications = _FakeNotifications();
    notificationPort = notifications;
    addTearDown(() => notificationPort = null);
  });

  Future<void> pumpHost(WidgetTester tester) async {
    const size = Size(1000, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles([]))],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
    container.read(viewSizeProvider.notifier).update((_) => size);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pump();
  }

  ProfilesAction action() => container.read(profilesActionProvider.notifier);

  testWidgets('two days before the end the system is told, with the link', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;

    await action().noticeSubscriptionExpiry(
      _profile(
        left: const Duration(days: 2, hours: 3),
        renew: 'https://pay.example/renew',
        service: 'MyVPN',
      ),
    );
    await tester.pump();

    expect(notifications.shown, [
      (
        title: 'MyVPN',
        body: l10n.subscriptionExpiresInDays(2),
        url: 'https://pay.example/renew',
      ),
    ]);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('without system notifications a dialog offers to renew', (
    tester,
  ) async {
    await pumpHost(tester);
    notifications.available = false;
    final l10n = currentAppLocalizations;

    unawaited(
      action().noticeSubscriptionExpiry(
        _profile(
          left: const Duration(days: 2, hours: 3),
          renew: 'https://pay.example/renew',
          service: 'MyVPN',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MyVPN'), findsOneWidget);
    expect(find.text(l10n.subscriptionExpiresInDays(2)), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.renew), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.confirm));
    await tester.pumpAndSettle();
    expect(find.text('MyVPN'), findsNothing);
  });

  testWidgets('each step is said once; far-off or missing ends never', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;
    final soon = _profile(left: const Duration(hours: 5));

    await action().noticeSubscriptionExpiry(soon);
    await action().noticeSubscriptionExpiry(soon);
    await action().noticeSubscriptionExpiry(
      _profile(left: const Duration(days: 30), id: 2),
    );
    await action().noticeSubscriptionExpiry(
      const Profile(id: 3, autoUpdateDuration: Duration.zero),
    );

    expect(notifications.shown.map((n) => n.body), [
      l10n.subscriptionExpiresToday,
    ]);
  });

  testWidgets('an expired plan says so, without a link to renew', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;

    await action().noticeSubscriptionExpiry(
      _profile(left: const Duration(days: -2)),
    );

    expect(notifications.shown.single.body, l10n.subscriptionExpired);
    expect(notifications.shown.single.url, isNull);
  });
}
