import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _RecordingProfilesAction extends ProfilesAction {
  final singles = <String>[];
  final deviceHeaderChoices = <bool>[];
  final pageChoices = <bool>[];

  @override
  Future<Profile?> addProfileFromLink(
    String link, {
    String? label,
    String ageSecretKey = '',
    bool sendDeviceHeaders = true,
    bool showProfiles = true,
  }) async {
    singles.add(link);
    deviceHeaderChoices.add(sendDeviceHeaders);
    pageChoices.add(showProfiles);
    return null;
  }
}

ProviderContainer _containerFor(
  WidgetTester tester, {
  ProfilesAction? profilesAction,
  List<Profile> profiles = const [],
}) {
  const size = Size(1400, 1000);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(() => TestProfiles(profiles)),
      if (profilesAction != null)
        profilesActionProvider.overrideWith(() => profilesAction),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

Future<void> _openMenu(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        child: Scaffold(
          body: Center(
            child: AddProfileMenu(
              builder: (open) =>
                  FilledButton(onPressed: open, child: const Text('add')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('add'));
  await tester.pumpAndSettle();
}

Future<void> _openLinkDialog(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        child: Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => addProfileByLink(context, ref),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('add'));
  await tester.pumpAndSettle();
}

void _mockClipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData' ? {'text': text} : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

TextButton _button(WidgetTester tester, String label) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, label));

void main() {
  testWidgets('offers the QR code, file, link, and custom entries', (
    tester,
  ) async {
    final container = _containerFor(tester);

    await _openMenu(tester, container);

    final l10n = currentAppLocalizations;
    expect(find.text(l10n.qrcode), findsOne);
    expect(find.text(l10n.file), findsOne);
    expect(find.text(l10n.link), findsOne);
    expect(find.text(l10n.customProfile), findsOne);
    expect(tester.takeException(), null);
  });

  testWidgets('the menu link entry asks for the link alone', (tester) async {
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openMenu(tester, container);
    final l10n = currentAppLocalizations;
    await tester.tap(find.text(l10n.link));
    await tester.pumpAndSettle();

    expect(find.byType(AddProfileLinkDialog), findsOne);
    expect(find.byType(TextField), findsOne);
    expect(find.text(l10n.sendDeviceHeaders), findsNothing);
  });

  testWidgets('adds only once a link is typed, with the HWID sent', (
    tester,
  ) async {
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    final l10n = currentAppLocalizations;
    expect(_button(tester, l10n.add).onPressed, isNull);

    await tester.enterText(find.byType(TextField), ' https://example.com/sub ');
    await tester.pump();
    expect(_button(tester, l10n.add).onPressed, isNotNull);
    await tester.tap(find.text(l10n.add));
    await tester.pumpAndSettle();

    expect(action.singles, ['https://example.com/sub']);
    expect(action.deviceHeaderChoices, [true]);
    expect(action.pageChoices, [false]);
    expect(find.byType(AddProfileLinkDialog), findsNothing);
  });

  testWidgets('takes a proxy share link', (tester) async {
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    await tester.enterText(
      find.byType(TextField),
      'trojan://pass@example.com:443#HK',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(action.singles, ['trojan://pass@example.com:443#HK']);
  });

  testWidgets('rejects what is neither kind of link and stays open', (
    tester,
  ) async {
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    final l10n = currentAppLocalizations;
    await tester.enterText(
      find.byType(TextField),
      'wireguard://key@example.com:51820',
    );
    await tester.pump();
    await tester.tap(find.text(l10n.add));
    await tester.pumpAndSettle();

    expect(find.text(l10n.invalidLinkTip), findsOne);
    expect(find.byType(AddProfileLinkDialog), findsOne);
    expect(action.singles, isEmpty);
  });

  testWidgets('adds the link on the clipboard in one tap', (tester) async {
    _mockClipboard(tester, ' https://example.com/sub ');
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    await tester.tap(find.text(currentAppLocalizations.addFromClipboard));
    await tester.pumpAndSettle();

    expect(action.singles, ['https://example.com/sub']);
    expect(action.deviceHeaderChoices, [true]);
  });

  testWidgets('a clipboard without a link says so and stays open', (
    tester,
  ) async {
    _mockClipboard(tester, 'not a link');
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    final l10n = currentAppLocalizations;
    await tester.tap(find.text(l10n.addFromClipboard));
    await tester.pumpAndSettle();

    expect(find.text(l10n.invalidLinkTip), findsOne);
    expect(find.byType(AddProfileLinkDialog), findsOne);
    expect(action.singles, isEmpty);
  });

  testWidgets('cancel closes without adding', (tester) async {
    final action = _RecordingProfilesAction();
    final container = _containerFor(tester, profilesAction: action);

    await _openLinkDialog(tester, container);
    await tester.enterText(find.byType(TextField), 'https://example.com/sub');
    await tester.tap(find.text(currentAppLocalizations.cancel));
    await tester.pumpAndSettle();

    expect(find.byType(AddProfileLinkDialog), findsNothing);
    expect(action.singles, isEmpty);
  });
}
