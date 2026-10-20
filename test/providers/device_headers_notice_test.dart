import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const _notice = 'Устройств больше, чем разрешает тариф.';

Profile _profile({
  bool limit = false,
  bool unsupported = false,
  bool sends = true,
  String? support,
}) => Profile(
  id: 1,
  autoUpdateDuration: Duration.zero,
  sendDeviceHeaders: sends,
  providerHeaders: {
    if (limit) 'x-hwid-max-devices-reached': 'true',
    if (limit) 'announce': 'base64:${base64.encode(utf8.encode(_notice))}',
    if (unsupported) 'x-hwid-not-supported': 'true',
    if (unsupported) 'announce': 'Welcome back!',
    'support-url': ?support,
  },
);

void main() {
  late ProviderContainer container;

  Future<void> pumpHost(WidgetTester tester) async {
    const size = Size(1000, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).update((_) => size);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pump();
  }

  void notice(Profile profile, {Profile? before, required bool manual}) {
    container
        .read(profilesActionProvider.notifier)
        .noticeDeviceHeaders(profile, before: before, manual: manual);
  }

  testWidgets('a full plan shows the panel notice with a way to support', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;

    notice(
      _profile(limit: true, support: 'https://help.example.com'),
      manual: true,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.deviceLimitReached), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.support), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.confirm), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.confirm));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('without a support link the notice only confirms', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;

    notice(_profile(limit: true), manual: true);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, l10n.support), findsNothing);
    expect(find.widgetWithText(TextButton, l10n.confirm), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, l10n.confirm));
    await tester.pumpAndSettle();
  });

  testWidgets('a background update repeats the notice only when it is new', (
    tester,
  ) async {
    await pumpHost(tester);

    notice(_profile(limit: true), before: _profile(limit: true), manual: false);
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsNothing);

    notice(_profile(limit: true), before: _profile(), manual: false);
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsOneWidget);
    await tester.tap(find.text(currentAppLocalizations.confirm));
    await tester.pumpAndSettle();
  });

  testWidgets('an unsupported id is told like a full plan, with support', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = currentAppLocalizations;

    notice(
      _profile(unsupported: true, support: 'https://help.example.com'),
      manual: true,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.deviceIdUnsupportedTitle), findsOneWidget);
    expect(find.text(l10n.deviceIdUnsupported), findsOneWidget);
    expect(find.text('Welcome back!'), findsNothing);
    expect(find.widgetWithText(TextButton, l10n.support), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, l10n.confirm));
    await tester.pumpAndSettle();

    notice(_profile(unsupported: true, sends: false), manual: true);
    await tester.pumpAndSettle();
    expect(find.text(l10n.deviceIdNotSent), findsOneWidget);
    await tester.tap(find.text(l10n.confirm));
    await tester.pumpAndSettle();

    notice(
      _profile(unsupported: true),
      before: _profile(unsupported: true),
      manual: false,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.deviceIdUnsupportedTitle), findsNothing);
  });
}
