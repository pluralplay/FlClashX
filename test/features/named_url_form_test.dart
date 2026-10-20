import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

Future<void> _open(
  WidgetTester tester,
  NamedUrlForm form,
  ValueSetter<List<NamedUrl>?> onResult,
) async {
  const size = Size(1200, 1000);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TestApp(
      overrides: [viewSizeProvider.overrideWithBuild((_, _) => size)],
      child: Builder(
        builder: (context) => FilledButton(
          onPressed: () async => onResult(
            await showFormSheet<List<NamedUrl>>(
              context: context,
              builder: (_) => form,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _field(String title) => find.descendant(
  of: find.widgetWithText(FormRow, title),
  matching: find.byType(TextFormField),
);

bool _focused(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

void main() {
  clipboardImportTests();
  testWidgets('the optional name comes first and the url holds the focus', (
    tester,
  ) async {
    List<NamedUrl>? result;
    await _open(
      tester,
      const NamedUrlForm(title: 'Import'),
      (value) => result = value,
    );

    expect(
      tester.getTopLeft(_field('Name')).dy,
      lessThan(tester.getTopLeft(_field('URL')).dy),
    );
    expect(find.text('Optional'), findsOneWidget);
    expect(find.byTooltip('Batch import'), findsNothing);
    expect(_focused(tester, _field('URL')), isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('URL cannot be empty'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(_field('Name'), 'Home');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(_focused(tester, _field('URL')), isTrue);

    await tester.enterText(_field('URL'), 'https://example.com/sub');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, [
      (
        label: 'Home',
        url: 'https://example.com/sub',
        ageSecretKey: '',
        sendDeviceHeaders: true,
      ),
    ]);
  });

  testWidgets('the HWID switch starts on and its choice is returned', (
    tester,
  ) async {
    List<NamedUrl>? result;
    await _open(
      tester,
      const NamedUrlForm(title: 'Import', withDeviceHeaders: true),
      (value) => result = value,
    );
    final row = find.widgetWithText(FormRow, 'Send HWID');
    expect(row, findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: row, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );

    await tester.tap(row);
    await tester.pump();
    await tester.enterText(_field('URL'), 'https://example.com/sub');
    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(result, [
      (
        label: '',
        url: 'https://example.com/sub',
        ageSecretKey: '',
        sendDeviceHeaders: false,
      ),
    ]);
  });

  testWidgets('a batch previews, refuses invalid lines and returns every url', (
    tester,
  ) async {
    List<NamedUrl>? result;
    await _open(
      tester,
      const NamedUrlForm(
        title: 'Import',
        batch: true,
        existingUrls: {'https://example.com/old'},
      ),
      (value) => result = value,
    );
    final submit = find.widgetWithText(TextButton, 'Submit');

    await tester.enterText(_field('URL'), 'https://example.com/a');
    await tester.tap(find.byTooltip('Batch import'));
    await tester.pumpAndSettle();
    expect(find.text('Batch import'), findsOneWidget);
    expect(find.byTooltip('Single import'), findsOneWidget);
    expect(find.text('1 to add, 0 skipped as existing'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://example.com/a\nnot-a-url',
    );
    await tester.pumpAndSettle();
    expect(find.text('Line 2: URL must be a URL'), findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byType(NamedUrlForm), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://example.com/a\nhttps://example.com/old\n'
      'https://example.com/b',
    );
    await tester.pump();
    expect(find.text('2 to add, 1 skipped as existing'), findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result, [
      (
        label: '',
        url: 'https://example.com/a',
        ageSecretKey: '',
        sendDeviceHeaders: true,
      ),
      (
        label: '',
        url: 'https://example.com/b',
        ageSecretKey: '',
        sendDeviceHeaders: true,
      ),
    ]);
  });
}

void clipboardImportTests() {
  void mockClipboard(WidgetTester tester, String? text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': text} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  testWidgets('a link on the clipboard submits in one tap', (tester) async {
    mockClipboard(tester, ' https://example.com/sub ');
    List<NamedUrl>? result;
    await _open(
      tester,
      const NamedUrlForm(title: 'Import', batch: true, clipboardImport: true),
      (value) => result = value,
    );

    await tester.tap(find.text('Add profile from clipboard'));
    await tester.pumpAndSettle();

    expect(result, [
      (
        label: '',
        url: 'https://example.com/sub',
        ageSecretKey: '',
        sendDeviceHeaders: true,
      ),
    ]);
  });

  testWidgets('a clipboard without a link says so and keeps the form', (
    tester,
  ) async {
    mockClipboard(tester, 'not a link');
    List<NamedUrl>? result;
    var opened = false;
    await _open(
      tester,
      const NamedUrlForm(title: 'Import', batch: true, clipboardImport: true),
      (value) {
        opened = true;
        result = value;
      },
    );

    await tester.tap(find.text('Add profile from clipboard'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(opened, isFalse);
    expect(result, isNull);
    expect(find.byType(NamedUrlForm), findsOneWidget);
    expect(find.textContaining('URL'), findsWidgets);
  });
}
