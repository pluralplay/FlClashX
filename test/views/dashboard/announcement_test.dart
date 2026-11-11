import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

const _link = 'https://example.com/news';
const _text = 'Servers moved 🚀 see $_link.';

Profile _profile({String? announce}) => Profile(
  id: 1,
  label: 'Sub',
  type: ProfileType.url,
  url: 'https://sub.example.com/link',
  autoUpdateDuration: Duration.zero,
  providerHeaders: {'announce': ?announce},
);

void main() {
  late ProviderContainer container;

  void setUpProfiles(List<Profile> profiles) {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
    );
    globalState.container = container;
    container.listen(currentProfileIdProvider, (_, _) {});
    container.read(currentProfileIdProvider.notifier).value =
        profiles.firstOrNull?.id;
    addTearDown(container.dispose);
  }

  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size size = const Size(412, 1400),
    bool navigator = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: navigator,
          child: const DashboardView(platform: SupportPlatform.Android),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  TextSpan linkSpan(WidgetTester tester) {
    final rich = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(AnnouncementCard),
            matching: find.byType(Text),
          )
          .last,
    );
    TextSpan? found;
    (rich.textSpan! as TextSpan).visitChildren((span) {
      if (span is TextSpan && span.text == _link) {
        found = span;
        return false;
      }
      return true;
    });
    return found!;
  }

  testWidgets('shows the announcement first, above the status card', (
    tester,
  ) async {
    setUpProfiles([_profile(announce: _text)]);
    await pumpDashboard(tester);

    expect(find.text('Announcement'), findsOneWidget);
    expect(find.textContaining('Servers moved'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(AnnouncementCard)).dy,
      lessThan(tester.getTopLeft(find.byType(CurrentOutboundCard)).dy),
    );

    await teardown(tester);
  });

  testWidgets('is absent without a profile or without the header', (
    tester,
  ) async {
    setUpProfiles([]);
    await pumpDashboard(tester);
    expect(find.byType(AnnouncementCard), findsNothing);
    await teardown(tester);

    setUpProfiles([_profile()]);
    await pumpDashboard(tester);
    expect(find.byType(AnnouncementCard), findsNothing);
    await teardown(tester);
  });

  testWidgets('highlights its link and asks before opening it', (tester) async {
    setUpProfiles([_profile(announce: _text)]);
    await pumpDashboard(tester, navigator: true);

    final span = linkSpan(tester);
    expect(span.style?.decoration, TextDecoration.underline);
    expect(span.mouseCursor, SystemMouseCursors.click);
    (span.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('External link'), findsOneWidget);
    expect(find.text(_link), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    await teardown(tester);
  });

  void seed(List<DashboardWidget> widgets) {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(dashboardWidgets: widgets));
  }

  List<DashboardWidget> saved() =>
      container.read(appSettingProvider).dashboardWidgets;

  testWidgets('stays where the saved cards put it', (tester) async {
    setUpProfiles([_profile(announce: _text)]);
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.announcement,
    ]);
    await pumpDashboard(tester);

    double topOf(Finder finder) => tester.getTopLeft(finder).dy;
    expect(
      topOf(find.byType(NetworkSpeedCard)),
      lessThan(topOf(find.byType(AnnouncementCard))),
    );

    await teardown(tester);
  });

  testWidgets('cannot be removed while editing, nor can the status card, '
      'yet both drag to a new place', (tester) async {
    setUpProfiles([_profile(announce: _text)]);
    seed(const [DashboardWidget.currentOutbound, DashboardWidget.networkSpeed]);
    await pumpDashboard(tester);
    await tester.tap(find.byTooltip('Edit dashboard'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Remove Announcement'), findsNothing);
    expect(find.byTooltip('Remove Status'), findsNothing);
    expect(find.byTooltip('Remove Network speed'), findsOneWidget);
    expect(find.text('Announcement'), findsOneWidget);

    double topOf(Finder finder) => tester.getTopLeft(finder).dy;
    final announcement = find.byType(AnnouncementCard);
    final status = find.byType(CurrentOutboundCard);
    expect(topOf(announcement), lessThan(topOf(status)));
    final rise = topOf(status) - topOf(announcement) + 10;
    final gesture = await tester.startGesture(tester.getCenter(status));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(Offset(0, -rise / 4));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(topOf(status), lessThan(topOf(announcement)));
    expect(saved(), const [
      DashboardWidget.currentOutbound,
      DashboardWidget.announcement,
      DashboardWidget.networkSpeed,
    ]);

    await teardown(tester);
  });

  testWidgets('keeps its place through an edit made while it is away', (
    tester,
  ) async {
    setUpProfiles([_profile()]);
    seed(const [
      DashboardWidget.currentOutbound,
      DashboardWidget.announcement,
      DashboardWidget.networkSpeed,
      DashboardWidget.profiles,
    ]);
    await pumpDashboard(tester);
    await tester.tap(find.byTooltip('Edit dashboard'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AnnouncementCard), findsNothing);
    await tester.tap(find.byTooltip('Remove Network speed'));
    await tester.pump(const Duration(seconds: 2));

    expect(saved(), const [
      DashboardWidget.currentOutbound,
      DashboardWidget.announcement,
      DashboardWidget.profiles,
    ]);

    await teardown(tester);
  });
}
