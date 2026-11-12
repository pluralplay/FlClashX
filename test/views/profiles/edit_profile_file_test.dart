import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/edit.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../helpers/app_paths.dart';
import '../../plugins/code_forge/support.dart' show initEditorNative;
import '../../widgets/edit_profile_focus_test.dart';

final class _UploadedFile extends PlatformFile {
  _UploadedFile(this.bytes);

  final Uint8List bytes;

  @override
  String get name => 'uploaded.yaml';

  @override
  Uri get uri => Uri.file('/picked/$name');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _PickedFile extends FilePickerPlatform {
  _PickedFile(this.file);

  final PlatformFile file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => file;
}

class _PendingCheck extends ProfilesAction {
  _PendingCheck(this.result);

  final Future<String> result;

  @override
  Future<String> validateConfigWithData(List<int> data) => result;
}

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _RecordingPut extends ProfilesAction {
  final put = <Profile>[];

  @override
  void putProfile(Profile profile) => put.add(profile);
}

class _PendingValidation extends CoreController {
  _PendingValidation() : super.scoped(_MockCoreHandlerInterface());

  int calls = 0;
  final result = Completer<String>();

  @override
  Future<String> validateProfile(String path, [String ageSecretKey = '']) {
    calls++;
    return result.future;
  }
}

// Each file call of the page finishes outside the fake clock.
Future<void> settleIo(WidgetTester tester) async {
  for (var step = 0; step < 10; step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Escape, the system back and a tap outside all close an alert with null.
Future<void> dismissAlert(WidgetTester tester, String message) async {
  Navigator.of(tester.element(find.text(message))).pop();
  await settleIo(tester);
}

Future<void> uploadFile(WidgetTester tester, String content) async {
  FilePickerPlatform.instance = _PickedFile(
    _UploadedFile(Uint8List.fromList(utf8.encode(content))),
  );
  await tester.longPress(find.text(currentAppLocalizations.profile));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text(currentAppLocalizations.upload));
  await settleIo(tester);
}

void main() {
  late Directory tempDir;
  late FilePickerPlatform platformPicker;

  setUpAll(() async {
    await initEditorNative();
    tempDir = Directory.systemTemp.createTempSync('edit_profile_file');
    await useAppPaths(tempDir);
  });

  setUp(() => platformPicker = FilePickerPlatform.instance);

  tearDown(() => FilePickerPlatform.instance = platformPicker);

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('the editor opens on the file just uploaded', (tester) async {
    final profile = Profile.normal(label: 'local');
    await tester.runAsync(
      () async => (await profile.file).writeAsString('saved: a\n'),
    );
    final uploaded = Uint8List.fromList(utf8.encode('uploaded: b\n'));
    FilePickerPlatform.instance = _PickedFile(_UploadedFile(uploaded));
    await pumpEditProfile(tester, profile: profile);

    await settleIo(tester);
    final row = find.text(currentAppLocalizations.profile);
    await tester.longPress(row);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(currentAppLocalizations.upload));
    await settleIo(tester);
    await tester.tap(row);
    await tester.pump();
    String? text;
    for (var attempt = 0; attempt < 50 && text == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final editors = find.byType(EditorView);
      if (editors.evaluate().isNotEmpty) {
        text = tester.state<EditorViewState>(editors).controller?.text;
      }
    }

    expect(text, 'uploaded: b\n');
  });

  testWidgets('a check that lands under another route leaves it open', (
    tester,
  ) async {
    final profile = Profile.normal(label: 'covered');
    await tester.runAsync(
      () async => (await profile.file).writeAsString('saved: a\n'),
    );
    final checked = Completer<String>();
    await pumpEditProfile(
      tester,
      profile: profile,
      overrides: [
        profilesActionProvider.overrideWith(
          () => _PendingCheck(checked.future),
        ),
      ],
    );
    await settleIo(tester);
    await tester.tap(find.text(currentAppLocalizations.profile));
    await settleIo(tester);
    final editorContext = tester.element(find.byType(EditorPage));
    final editor = tester.widget<EditorPage>(find.byType(EditorPage));
    final above = MaterialPageRoute<void>(builder: (_) => const Text('above'));
    unawaited(Navigator.of(editorContext).push(above));
    await settleIo(tester);

    unawaited(
      Future.value(
        editor.onSave!(
          editorContext,
          '',
          const EditorContent.text('saved: b\n'),
        ),
      ),
    );
    checked.complete('');
    await settleIo(tester);

    expect(above.isCurrent, isTrue);
    expect(find.byType(EditorPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('a dismissed prompt leaves the editor open with its edits', (
    tester,
  ) async {
    final profile = Profile.normal(label: 'dismissed');
    await tester.runAsync(
      () async => (await profile.file).writeAsString('saved: a\n'),
    );
    await pumpEditProfile(tester, profile: profile);
    await settleIo(tester);
    await tester.tap(find.text(currentAppLocalizations.profile));
    await settleIo(tester);
    final editorContext = tester.element(find.byType(EditorPage));
    final editor = tester.widget<EditorPage>(find.byType(EditorPage));
    const edited = EditorContent.text('saved: b\n');

    final dismissed = editor.onPop!(editorContext, '', edited);
    await settleIo(tester);
    await dismissAlert(tester, currentAppLocalizations.hasCacheChange);
    expect(await dismissed, isFalse);

    final declined = editor.onPop!(editorContext, '', edited);
    await settleIo(tester);
    await tester.tap(find.text(currentAppLocalizations.cancel));
    await settleIo(tester);
    expect(await declined, isTrue);
  });

  testWidgets('a dismissed prompt on leaving keeps the staged file', (
    tester,
  ) async {
    final profile = Profile.normal(label: 'staged');
    await tester.runAsync(
      () async => (await profile.file).writeAsString('saved: a\n'),
    );
    await pumpEditProfile(tester, profile: profile);
    await settleIo(tester);
    await uploadFile(tester, 'uploaded: b\n');

    final page = tester.element(find.byType(EditProfileView));
    final route = ModalRoute.of(page)!;
    unawaited(Navigator.of(page).maybePop());
    await settleIo(tester);
    await dismissAlert(tester, currentAppLocalizations.fileIsUpdate);

    expect(route.isActive, isTrue);
  });

  Future<_PendingValidation> pumpSaving(
    WidgetTester tester, {
    List<Override> overrides = const [],
    SheetType? sheetType,
  }) async {
    final profile = Profile.normal(label: 'saving');
    await tester.runAsync(
      () async => (await profile.file).writeAsString('saved: a\n'),
    );
    final validation = _PendingValidation();
    await pumpEditProfile(
      tester,
      profile: profile,
      sheetType: sheetType,
      overrides: [
        coreHandlerProvider.overrideWithValue(validation),
        ...overrides,
      ],
    );
    await settleIo(tester);
    await uploadFile(tester, 'uploaded: b\n');
    return validation;
  }

  testWidgets('a second save waits for the first one', (tester) async {
    final profiles = _RecordingPut();
    final validation = await pumpSaving(
      tester,
      overrides: [profilesActionProvider.overrideWith(() => profiles)],
    );
    final route = ModalRoute.of(tester.element(find.byType(EditProfileView)))!;

    final save = find.byTooltip(currentAppLocalizations.save);
    await tester.tap(save);
    await settleIo(tester);
    await tester.tap(save);
    await settleIo(tester);
    expect(validation.calls, 1);

    validation.result.complete('');
    await settleIo(tester);
    expect(profiles.put, hasLength(1));
    expect(route.isActive, isFalse);
  });

  testWidgets('the form takes no edits while a save runs', (tester) async {
    final profiles = _RecordingPut();
    final validation = await pumpSaving(
      tester,
      overrides: [profilesActionProvider.overrideWith(() => profiles)],
    );
    final name = find.byType(TextField).first;
    await tester.enterText(name, 'Before save');

    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await settleIo(tester);
    await tester.tap(name, warnIfMissed: false);
    await tester.pump();
    final editable = find.descendant(
      of: name,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);

    validation.result.complete('');
    await settleIo(tester);
    expect(profiles.put.single.label, 'Before save');
  });

  testWidgets('a failed save lets the next one run', (tester) async {
    final validation = await pumpSaving(tester);

    final save = find.byTooltip(currentAppLocalizations.save);
    await tester.tap(save);
    await settleIo(tester);
    validation.result.complete('broken: config');
    await settleIo(tester);
    await tester.tap(save);
    await settleIo(tester);

    expect(validation.calls, 2);
  });

  testWidgets('the side sheet close waits for a save in flight', (
    tester,
  ) async {
    await pumpSaving(tester, sheetType: SheetType.sideSheet);
    final route = ModalRoute.of(tester.element(find.byType(EditProfileView)))!;

    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await settleIo(tester);
    await tester.tap(find.byTooltip(currentAppLocalizations.close));
    await settleIo(tester);

    expect(route.isActive, isTrue);
  });
}
