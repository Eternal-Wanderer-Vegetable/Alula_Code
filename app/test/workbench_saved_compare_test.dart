import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
// Test fixtures need the package's native-channel override, which is test-only.
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

Future<(Directory, File)> _openFixture(
  WidgetTester tester, {
  String initialText = 'saved line\ncommon',
  bool withSecondFile = false,
  Future<FileStat> Function(String path)? savedCompareFileStat,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  final temp = Directory.systemTemp.createTempSync('alula-saved-compare');
  addTearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/sample.rs')
    ..writeAsStringSync(initialText);
  if (withSecondFile) {
    File('${workspace.path}/other.rs').writeAsStringSync('other document');
  }
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    savedCompareFileStat: savedCompareFileStat,
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.rs').first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.showKeyboard(
    find.byKey(const ValueKey('rust-bounded-text-input')),
  );
  await tester.pump();
  return (temp, file);
}

Future<void> _replaceText(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _pressSavedChord(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _finishSavedCompare(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    final mockContext = MockMessageChannelContext();
    for (final channel in ['DragManager', 'DropManager']) {
      mockContext.registerMockChannelHandler(
        channel,
        (_) async => ['ok', null],
      );
    }
    setContextOverride(mockContext);
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.irondash.engine_context'),
          (call) async => call.method == 'getEngineHandle' ? 1 : null,
        );
  });

  testWidgets(
      'Ctrl+K D compares Rust text with current disk contents without mutation',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (temp, file) = await _openFixture(tester);
      await _replaceText(tester, 'active draft\ncommon!');
      file.writeAsStringSync('external saved\ncommon');

      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      final field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final textBefore = controller.text;
      final selectionBefore = controller.selection;
      final versionBefore = field.inputWindow.document.version;
      final dirtyBefore = field.inputWindow.document.isDirty;
      final diskBefore = file.readAsStringSync();

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      expect(find.text('已保存版本 ↔ sample.rs'), findsOneWidget);
      expect(find.text('external saved'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('saved-compare-modified-editor')),
        findsOneWidget,
      );
      expect(
        field.inputWindow.document.resync().content,
        'active draft\ncommon!',
      );
      expect(
          find.byKey(const ValueKey('saved-compare-preview')), findsOneWidget);
      expect(controller.text, textBefore);
      expect(controller.selection, selectionBefore);
      expect(field.inputWindow.document.version, versionBefore);
      expect(field.inputWindow.document.isDirty, dirtyBefore);
      expect(dirtyBefore, isTrue);
      expect(file.readAsStringSync(), diskBefore);
      final sessionFile = File('${temp.path}/session.json');
      if (sessionFile.existsSync()) {
        expect(
            sessionFile.readAsStringSync(), isNot(contains('external saved')));
      }

      await tester.tap(find.byKey(const ValueKey('saved-compare-close')));
      await tester.pumpAndSettle();
      await tester.showKeyboard(editor);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(controller.text, 'saved line\ncommon');
      expect(file.readAsStringSync(), diskBefore);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'saved comparison edits the Rust document, syncs its sibling, and saves',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(
        tester,
        initialText: '\uFEFFsaved 😀\r\nline',
      );
      await _replaceText(tester, 'draft 😀\nline');
      final diskOriginal = file.readAsBytesSync();
      final mainFieldFinder = find.byType(RustTextInputField).first;
      final document = tester
          .widget<RustTextInputField>(mainFieldFinder)
          .inputWindow
          .document;

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      final comparePane = find.byKey(
        const ValueKey('saved-compare-modified-pane'),
      );
      final compareInput = find.descendant(
        of: comparePane,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      expect(compareInput, findsOneWidget);
      final compareField = tester.widget<RustTextInputField>(
        find.descendant(
          of: comparePane,
          matching: find.byType(RustTextInputField),
        ),
      );
      expect(identical(compareField.inputWindow.document, document), isTrue);

      await tester.showKeyboard(compareInput);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'edited 🐈\nline!',
        selection: TextSelection.collapsed(offset: 15),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();

      expect(document.resync().content, 'edited 🐈\nline!');
      expect(document.isDirty, isTrue);
      expect(file.readAsBytesSync(), orderedEquals(diskOriginal));
      expect(
        tester.widget<RustTextInputField>(mainFieldFinder).inputWindow.version,
        document.version,
      );
      expect(
        find.byKey(const ValueKey('saved-compare-diff-status')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('saved-compare-close')));
      await tester.pumpAndSettle();
      await tester.showKeyboard(
        find.descendant(
          of: mainFieldFinder,
          matching: find.byType(TextField),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(document.resync().content, 'draft 😀\nline');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(document.resync().content, 'edited 🐈\nline!');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        file.readAsBytesSync(),
        orderedEquals([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('edited 🐈\r\nline!'),
        ]),
      );
      expect(document.isDirty, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'compare modified pane applies insert, delete, and replace in Rust',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester, initialText: 'base\nline');
      final document = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField).first)
          .inputWindow
          .document;
      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      final comparePane = find.byKey(
        const ValueKey('saved-compare-modified-pane'),
      );
      final compareInput = find.descendant(
        of: comparePane,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      await tester.showKeyboard(compareInput);

      Future<void> editCompareText(String text) async {
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ));
        await tester.pump();
        await tester.pump();
      }

      await editCompareText('base!\nline');
      expect(document.resync().content, 'base!\nline');
      expect(document.isDirty, isTrue);

      await editCompareText('base\nline');
      expect(document.resync().content, 'base\nline');
      expect(document.isDirty, isFalse);

      const replaced = 'new 🐈\nline';
      await editCompareText(replaced);
      expect(document.resync().content, replaced);
      expect(document.isDirty, isTrue);
      expect(file.readAsStringSync(), 'base\nline');

      await tester.pump(const Duration(milliseconds: 140));
      expect(
        find.byKey(const ValueKey('saved-compare-diff-status')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('saved-compare-close')));
      await tester.pumpAndSettle();
      expect(document.resync().content, replaced);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'compare modified pane keeps IME preedit out of Rust until commit',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester, initialText: 'base\nline');
      final compareSource = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField).first)
          .inputWindow
          .document;
      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      final comparePane = find.byKey(
        const ValueKey('saved-compare-modified-pane'),
      );
      final compareFieldFinder = find.descendant(
        of: comparePane,
        matching: find.byType(RustTextInputField),
      );
      final compareField =
          tester.widget<RustTextInputField>(compareFieldFinder);
      final compareInput = find.descendant(
        of: comparePane,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      await tester.showKeyboard(compareInput);

      final controller = tester.widget<TextField>(compareInput).controller!;
      final initialValue = controller.value;
      final initialVersion = compareSource.version;
      expect(initialValue.text, 'base\nline');
      final caret = initialValue.selection.extentOffset;
      expect(caret, greaterThanOrEqualTo(0));

      const preedit = 'ni';
      final preeditText = initialValue.text.replaceRange(caret, caret, preedit);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: preeditText,
        selection: TextSelection.collapsed(offset: caret + preedit.length),
        composing: TextRange(start: caret, end: caret + preedit.length),
      ));
      await tester.pump();

      expect(compareField.inputWindow.hasComposition, isTrue);
      expect(compareSource.resync().content, initialValue.text);
      expect(compareSource.version, initialVersion);

      const committed = '你好';
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: preeditText.replaceRange(
          caret,
          caret + preedit.length,
          committed,
        ),
        selection: TextSelection.collapsed(offset: caret + committed.length),
        composing: TextRange.empty,
      ));
      await tester.pump();
      await tester.pump();

      final expected = initialValue.text.replaceRange(caret, caret, committed);
      expect(compareField.inputWindow.hasComposition, isFalse);
      expect(compareSource.resync().content, expected);
      expect(compareSource.version, greaterThan(initialVersion));
      expect(compareSource.isDirty, isTrue);
      expect(file.readAsStringSync(), initialValue.text);

      await tester.tap(find.byKey(const ValueKey('saved-compare-close')));
      await tester.pumpAndSettle();
      expect(compareSource.resync().content, expected);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('compares a BOM/CRLF disk snapshot as normalized text',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (temp, file) =
          await _openFixture(tester, initialText: 'old 😀\nnext');
      file.writeAsBytesSync(
        [0xef, 0xbb, 0xbf, ...utf8.encode('saved 😀\r\nnext')],
      );
      // The editor buffer is intentionally unchanged while the saved file
      // differs; the disk snapshot must decode and normalize before diffing.
      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      expect(
          find.byKey(const ValueKey('saved-compare-preview')), findsOneWidget);
      expect(find.text('saved 😀'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('saved-compare-modified-editor')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField).first)
            .inputWindow
            .document
            .resync()
            .content,
        'old 😀\nnext',
      );
      final sessionFile = File('${temp.path}/session.json');
      if (sessionFile.existsSync()) {
        expect(sessionFile.readAsStringSync(), isNot(contains('saved 😀')));
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('diff budget fallback keeps accepted compare edits in Rust',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await _openFixture(tester, initialText: 'base');
      final document = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField).first)
          .inputWindow
          .document;
      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      final compareInput = find.descendant(
        of: find.byKey(const ValueKey('saved-compare-modified-pane')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      await tester.showKeyboard(compareInput);
      final oversizedDiff = String.fromCharCodes(List<int>.filled(8192, 0x0A));
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: oversizedDiff,
        selection: TextSelection.collapsed(offset: oversizedDiff.length),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();

      expect(document.resync().content, oversizedDiff);
      expect(document.isDirty, isTrue);
      expect(find.textContaining('差异预算已达到'), findsOneWidget);
      expect(find.text('base'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('closing compared document dismisses its editor before switching',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, sampleFile) = await _openFixture(
        tester,
        withSecondFile: true,
      );
      final oldDocument = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField).first)
          .inputWindow
          .document;
      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      final comparePane = find.byKey(
        const ValueKey('saved-compare-modified-pane'),
      );
      await tester.showKeyboard(find.descendant(
        of: comparePane,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      ));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'compare edit',
        selection: TextSelection.collapsed(offset: 12),
      ));
      await tester.pump();
      await tester.pump();
      expect(oldDocument.resync().content, 'compare edit');

      tester
          .widget<InkWell>(
            find.byKey(
              ValueKey('close-tab-editor-${oldDocument.id}'),
            ),
          )
          .onTap!
          .call();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.byKey(const ValueKey('saved-compare-modified-editor')),
          findsNothing);
      await tester.tap(find.text('other.rs').first);
      await tester.pump(const Duration(milliseconds: 300));

      final activeFieldFinder = find.byType(RustTextInputField).first;
      final newDocument = tester
          .widget<RustTextInputField>(activeFieldFinder)
          .inputWindow
          .document;
      expect(newDocument.id, isNot(oldDocument.id));
      await tester.showKeyboard(find.descendant(
        of: activeFieldFinder,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      ));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'other edit',
        selection: TextSelection.collapsed(offset: 10),
      ));
      await tester.pump();
      await tester.pump();

      expect(newDocument.resync().content, 'other edit');
      expect(sampleFile.readAsStringSync(), 'saved line\ncommon');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('opens an identical snapshot for a clean active file',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester, initialText: 'same\ntext');
      final mainFieldFinder = find.byType(RustTextInputField).first;
      final field = tester.widget<RustTextInputField>(mainFieldFinder);
      final editor = find.descendant(
        of: mainFieldFinder,
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      final textBefore = tester.widget<TextField>(editor).controller!.text;
      final versionBefore = field.inputWindow.document.version;
      final diskBefore = file.readAsStringSync();

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      expect(
          find.byKey(const ValueKey('saved-compare-preview')), findsOneWidget);
      expect(field.inputWindow.document.isDirty, isFalse);
      expect(field.inputWindow.document.version, versionBefore);
      expect(tester.widget<TextField>(editor).controller!.text, textBefore);
      expect(file.readAsStringSync(), diskBefore);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('rejects an oversized disk snapshot before text decoding',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester);
      await _replaceText(tester, 'unsaved draft');
      file.writeAsStringSync('x' * 6000017);

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);
      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：已保存文件超过 6,000,016 字节上限'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('rust-bounded-text-input')),
            )
            .controller!
            .text,
        'unsaved draft',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reports a missing on-disk version without opening a diff',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester);
      await _replaceText(tester, 'unsaved draft');
      file.deleteSync();

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);
      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：已保存磁盘版本不存在或不可读取'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('rejects a binary disk snapshot without changing editor text',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final (_, file) = await _openFixture(tester);
      await _replaceText(tester, 'unsaved draft');
      file.writeAsBytesSync([0x00, 0x01, 0x02]);

      await _pressSavedChord(tester);
      await _finishSavedCompare(tester);

      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：磁盘版本是二进制文件'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('rust-bounded-text-input')),
            )
            .controller!
            .text,
        'unsaved draft',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancels if the active view changes while stat is pending',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final statResult = Completer<FileStat>();

    try {
      final (_, file) = await _openFixture(
        tester,
        withSecondFile: true,
        savedCompareFileStat: (_) => statResult.future,
      );
      await _replaceText(tester, 'unsaved draft');
      await _pressSavedChord(tester);

      await tester.tap(find.text('other.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        statResult.complete(await file.stat());
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：读取磁盘期间活动文件已变化'), findsOneWidget);
    } finally {
      if (!statResult.isCompleted) {
        statResult.complete(FileStat.statSync(Directory.systemTemp.path));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancels if the Rust version changes while stat is pending',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final statResult = Completer<FileStat>();

    try {
      final (_, file) = await _openFixture(
        tester,
        savedCompareFileStat: (_) => statResult.future,
      );
      await _replaceText(tester, 'draft at invocation');
      await _pressSavedChord(tester);
      await _replaceText(tester, 'draft changed during stat');
      await tester.runAsync(() async {
        statResult.complete(await file.stat());
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：读取磁盘期间活动文件已变化'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('rust-bounded-text-input')),
            )
            .controller!
            .text,
        'draft changed during stat',
      );
    } finally {
      if (!statResult.isCompleted) {
        statResult.complete(FileStat.statSync(Directory.systemTemp.path));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancels if the compared tab closes while stat is pending',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final statResult = Completer<FileStat>();

    try {
      final (_, file) = await _openFixture(
        tester,
        savedCompareFileStat: (_) => statResult.future,
      );
      await _replaceText(tester, 'unsaved draft');
      final field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final documentId = field.inputWindow.document.id;

      await _pressSavedChord(tester);
      await tester.tap(find.byKey(ValueKey('close-tab-editor-$documentId')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        statResult.complete(await file.stat());
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('saved-compare-preview')), findsNothing);
      expect(find.text('比较已取消：读取磁盘期间活动文件已变化'), findsOneWidget);
    } finally {
      if (!statResult.isCompleted) {
        statResult.complete(FileStat.statSync(Directory.systemTemp.path));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
