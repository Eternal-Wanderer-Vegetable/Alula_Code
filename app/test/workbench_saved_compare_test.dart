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
      expect(find.text('active draft'), findsOneWidget);
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
      expect(find.text('old 😀'), findsOneWidget);
      final sessionFile = File('${temp.path}/session.json');
      if (sessionFile.existsSync()) {
        expect(sessionFile.readAsStringSync(), isNot(contains('saved 😀')));
      }
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
      final field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
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
