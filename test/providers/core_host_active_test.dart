import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _MockCore core;
  late ProviderContainer container;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('core_host_active');
    await useAppPaths(tempDir);
    registerFallbackValue(const InitParams(homeDir: '', version: 0));
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    core = _MockCore();
    when(() => core.isInit).thenAnswer((_) async => false);
    when(() => core.init(any())).thenAnswer((_) async => true);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([])),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    container.listen(appVisibleProvider, (_, _) {});
  });

  test('a core that starts behind a hidden app is told so', () async {
    container.read(appVisibleProvider.notifier).value = false;

    await container.read(coreActionProvider.notifier).initCore();

    verify(() => core.setHostActive(false)).called(1);
  });

  test('a core that starts in front is active', () async {
    await container.read(coreActionProvider.notifier).initCore();

    verify(() => core.setHostActive(true)).called(1);
  });
}
