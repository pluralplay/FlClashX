import 'dart:async';

import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../plugins/code_forge/support.dart' show initEditorNative;

final _viewSizeOverride = viewSizeProvider.overrideWithBuild(
  (_, _) => const Size(1200, 1000),
);

void main() {
  setUpAll(initEditorNative);

  testWidgets('shows the unavailable state without the native editor library', (
    tester,
  ) async {
    final ready = editorNativeReady;
    editorNativeReady = () => false;
    addTearDown(() => editorNativeReady = ready);
    await tester.pumpWidget(
      TestApp(
        overrides: [_viewSizeOverride],
        child: const EditorPage(
          title: 'Editor',
          content: 'mixed-port: 7890',
          onSave: _noopSave,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Editor unavailable'), findsOneWidget);
    for (final glyph in [AppGlyphs.search, AppGlyphs.check]) {
      expect(
        tester
            .widget<IconButton>(find.widgetWithGlyph(IconButton, glyph))
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('Ctrl+S saves a changed document off Apple platforms', (
    tester,
  ) async {
    final saved = <String>[];
    await tester.pumpWidget(
      TestApp(
        overrides: [_viewSizeOverride],
        child: EditorPage(
          title: 'Editor',
          content: '',
          titleEditable: true,
          onSave: (_, title, _) => saved.add(title),
        ),
      ),
    );
    await tester.pump();
    Future<void> pressSave() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await pressSave();
    expect(saved, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithGlyph(IconButton, AppGlyphs.check))
          .onPressed,
      isNotNull,
    );
    await pressSave();
    expect(saved, ['Renamed']);
  });

  Future<void> openDirtyEditor(WidgetTester tester, EditorPage page) async {
    await tester.pumpWidget(
      TestApp(
        overrides: [_viewSizeOverride],
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump();
  }

  VoidCallback? saveButton(WidgetTester tester) => tester
      .widget<IconButton>(find.widgetWithGlyph(IconButton, AppGlyphs.check))
      .onPressed;

  testWidgets('back is refused while a save is still running', (tester) async {
    final saving = Completer<void>();
    var asked = 0;
    await openDirtyEditor(
      tester,
      EditorPage(
        title: 'Editor',
        content: '',
        titleEditable: true,
        onSave: (_, _, _) => saving.future,
        onPop: (_, _, _) async {
          asked++;
          return true;
        },
      ),
    );
    await tester.tap(find.widgetWithGlyph(IconButton, AppGlyphs.check));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    final title = find.byType(TextField).first;
    await tester.tap(title);
    await tester.pump();
    tester.testTextInput.enterText('Changed');
    await tester.pump();

    expect(find.byType(EditorPage), findsOneWidget);
    expect(asked, 0);
    expect(tester.widget<TextField>(title).controller!.text, 'Renamed');
    expect(tester.widget<EditorView>(find.byType(EditorView)).readOnly, isTrue);
    saving.complete();
    await tester.pump();
    expect(tester.widget<TextField>(title).enabled, isTrue);
    expect(
      tester.widget<EditorView>(find.byType(EditorView)).readOnly,
      isFalse,
    );
  });

  testWidgets('a save picked on the way back holds the editor too', (
    tester,
  ) async {
    final saving = Completer<bool>();
    var asked = 0;
    await openDirtyEditor(
      tester,
      EditorPage(
        title: 'Editor',
        content: '',
        titleEditable: true,
        onSave: _noopSave,
        onPop: (_, _, _) {
          asked++;
          return saving.future;
        },
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(asked, 1);
    expect(saveButton(tester), isNull);
    saving.complete(false);
    await tester.pump();
    expect(find.byType(EditorPage), findsOneWidget);
    expect(saveButton(tester), isNotNull);
  });
}

void _noopSave(BuildContext context, String title, EditorContent content) {}
