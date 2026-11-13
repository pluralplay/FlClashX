import 'dart:io';

import 'package:fl_clash/features/update/update.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

class _Platform implements UpdatePlatform {
  @override
  final UpdateTarget target;

  _Platform(UpdateInstallKind kind) : target = UpdateTarget(kind, ['arm64']);

  @override
  Future<void> verify(File file) async {}

  @override
  Future<UpdateInstallResult> install(File file) async =>
      UpdateInstallResult.exiting;
}

class _Scripted extends UpdateController {
  final calls = <String>[];

  _Scripted(UpdateInstallKind kind)
    : super(
        release: const {'tag_name': 'v0.5.1'},
        platform: _Platform(kind),
        downloader: UpdateDownloader(root: () async => Directory.systemTemp),
        repository: 'pluralplay/FlClashX',
        pre: false,
        installBlocker: () => null,
      );

  @override
  Future<void> download() async => calls.add('download');

  @override
  Future<void> install() async => calls.add('install');

  @override
  void cancel() => calls.add('cancel');
}

void main() {
  late _Scripted controller;
  late int releasePageOpens;
  late int hides;

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    UpdateInstallKind kind = UpdateInstallKind.macos,
    bool reminder = false,
  }) async {
    controller = _Scripted(kind);
    releasePageOpens = 0;
    hides = 0;
    await tester.pumpWidget(
      TestApp(
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 800)),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFloatingDialog<void>(
                  context: context,
                  child: UpdateDialog(
                    createController: () => controller,
                    notes: const TextSpan(text: 'Release notes'),
                    onOpenReleasePage: () => releasePageOpens++,
                    onHide: reminder ? () => hides++ : null,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return AppLocalizations.current;
  }

  Future<void> show(WidgetTester tester, UpdateState state) async {
    controller.value = state;
    await tester.pump();
  }

  testWidgets('offers download, the release page and closing', (tester) async {
    final l10n = await pump(tester);
    expect(find.text('Release notes'), findsOneWidget);
    await tester.tap(find.text(l10n.goDownload));
    expect(controller.calls, ['download']);
    await tester.tap(find.text(l10n.updateViewOnGitHub));
    expect(releasePageOpens, 1);
    await tester.tap(find.text(l10n.close));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('a reminder hides its release from the dialog', (tester) async {
    final l10n = await pump(tester, reminder: true);
    expect(find.text(l10n.close), findsNothing);
    await tester.tap(find.text(l10n.updateHide));
    await tester.pumpAndSettle();
    expect(hides, 1);
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('a package-managed copy gets no download', (tester) async {
    final l10n = await pump(tester, kind: UpdateInstallKind.packageManager);
    expect(find.text(l10n.goDownload), findsNothing);
    expect(find.text(l10n.updatePackageManager), findsOneWidget);
    expect(find.text(l10n.updateViewOnGitHub), findsOneWidget);
  });

  testWidgets('shows progress in the download button and cancels', (
    tester,
  ) async {
    final l10n = await pump(tester);
    await show(
      tester,
      const UpdateState(UpdatePhase.downloading, received: 1024, total: 4096),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedFractionallySizedBox>(
            find.byType(AnimatedFractionallySizedBox),
          )
          .widthFactor,
      0.25,
    );
    await tester.tap(find.text(l10n.cancel));
    expect(controller.calls, ['cancel']);

    await show(tester, const UpdateState(UpdatePhase.verifying));
    expect(find.text(l10n.updateVerifying), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a failure explains itself and retries', (tester) async {
    final l10n = await pump(tester);
    await show(
      tester,
      const UpdateState(
        UpdatePhase.failed,
        error: UpdateException(UpdateErrorKind.checksumMismatch, 'x.dmg'),
      ),
    );
    expect(find.text(l10n.updateErrorChecksum), findsOneWidget);
    expect(find.text('x.dmg'), findsNothing);
    expect(find.text(l10n.updateViewOnGitHub), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    expect(controller.calls, ['download']);
  });

  testWidgets('ready offers Install and shows why it waits', (tester) async {
    final l10n = await pump(tester);
    await show(tester, const UpdateState(UpdatePhase.ready));
    expect(find.text(l10n.updateReady), findsOneWidget);
    await tester.tap(find.text(l10n.updateInstall));
    expect(controller.calls, ['install']);

    await show(
      tester,
      const UpdateState(
        UpdatePhase.ready,
        error: UpdateException(UpdateErrorKind.busy),
      ),
    );
    expect(find.text(l10n.updateErrorBusy), findsOneWidget);
    expect(find.text(l10n.updateInstall), findsOneWidget);
  });

  testWidgets('installing holds the dialog open', (tester) async {
    final l10n = await pump(tester);
    await show(tester, const UpdateState(UpdatePhase.installing));
    expect(find.text(l10n.updateInstalling), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UpdateDialog),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(UpdateDialog), findsOneWidget);

    await show(
      tester,
      const UpdateState(
        UpdatePhase.done,
        result: UpdateInstallResult.openedImage,
      ),
    );
    expect(find.text(l10n.updateOpenedImage), findsOneWidget);
    expect(find.text(l10n.close), findsOneWidget);
  });
}
