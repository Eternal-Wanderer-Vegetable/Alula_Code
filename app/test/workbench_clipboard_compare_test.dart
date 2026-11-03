import 'dart:async';
import 'dart:io';

import 'package:alula_app/editor/editor_clipboard.dart';
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
  String initialText = 'file line\nshared',
  bool withSecondFile = false,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  final temp = Directory.systemTemp.createTempSync('alula-clipboard-compare');
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

Future<void> _pressCompareChord(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.pump(const Duration(milliseconds: 100));
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

  late bool previousClipboardFallback;
  setUp(() {
    previousClipboardFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
  });
  tearDown(() {
    EditorClipboard.forceFlutterClipboardFallbackForTesting =
        previousClipboardFallback;
  });

  testWidgets('Ctrl+K C opens readonly comparison without editing or saving',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? const {'text': 'clipboard line\nshared'}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    try {
      final (temp, file) = await _openFixture(tester);
      final fieldFinder = find.byType(RustTextInputField);
      final field = tester.widget<RustTextInputField>(fieldFinder);
      final controller = tester
          .widget<TextField>(
              find.byKey(const ValueKey('rust-bounded-text-input')))
          .controller!;
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'file line\nshared!',
        selection: TextSelection.collapsed(offset: 17),
      ));
      await tester.pump();
      final textBefore = controller.text;
      final selectionBefore = controller.selection;
      final versionBefore = field.inputWindow.document.version;
      final dirtyBefore = field.inputWindow.document.isDirty;
      final diskBefore = file.readAsStringSync();

      await _pressCompareChord(tester);
      await tester.pumpAndSettle();

      expect(find.text('剪贴板 ↔ sample.rs'), findsOneWidget);
      expect(find.text('clipboard line'), findsOneWidget);
      expect(find.text('file line'), findsOneWidget);
      expect(controller.text, textBefore);
      expect(controller.selection, selectionBefore);
      expect(field.inputWindow.document.version, versionBefore);
      expect(field.inputWindow.document.isDirty, dirtyBefore);
      expect(file.readAsStringSync(), diskBefore);
      final sessionFile = File('${temp.path}/session.json');
      if (sessionFile.existsSync()) {
        expect(
            sessionFile.readAsStringSync(), isNot(contains('clipboard line')));
      }

      await tester.tap(find.byKey(const ValueKey('clipboard-compare-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      await tester
          .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(controller.text, 'file line\nshared');
      expect(field.inputWindow.document.isDirty, isFalse);
      expect(file.readAsStringSync(), diskBefore);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'cancels when the active Rust document changes during clipboard read',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardStarted = Completer<void>();
    final clipboardResult = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        if (call.method == 'Clipboard.getData') {
          if (!clipboardStarted.isCompleted) clipboardStarted.complete();
          return clipboardResult.future;
        }
        return Future<Object?>.value(null);
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    try {
      await _openFixture(tester);
      await _pressCompareChord(tester);
      await tester.pump();
      await clipboardStarted.future;

      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'changed while clipboard waits',
        selection: TextSelection.collapsed(offset: 29),
      ));
      await tester.pump();
      clipboardResult.complete(const {'text': 'stale clipboard snapshot'});
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      expect(find.text('比较已取消：读取剪贴板期间活动文件已变化'), findsOneWidget);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        'changed while clipboard waits',
      );
    } finally {
      if (!clipboardResult.isCompleted) {
        clipboardResult.complete(const {'text': 'unused'});
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('compares empty clipboard text as a valid snapshot',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? const {'text': ''} : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      await _openFixture(tester);

      await _pressCompareChord(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsOneWidget);
      expect(find.text('剪贴板 ↔ sample.rs'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancels when the active file is switched during clipboard read',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardStarted = Completer<void>();
    final clipboardResult = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        if (call.method == 'Clipboard.getData') {
          if (!clipboardStarted.isCompleted) clipboardStarted.complete();
          return clipboardResult.future;
        }
        return Future<Object?>.value(null);
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    try {
      await _openFixture(tester, withSecondFile: true);
      await _pressCompareChord(tester);
      await tester.pump();
      await clipboardStarted.future;

      await tester.tap(find.text('other.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      clipboardResult.complete(const {'text': 'stale clipboard snapshot'});
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      expect(find.text('比较已取消：读取剪贴板期间活动文件已变化'), findsOneWidget);
      expect(find.text('other document'), findsOneWidget);
    } finally {
      if (!clipboardResult.isCompleted) {
        clipboardResult.complete(const {'text': 'unused'});
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'cancels when the compared document is closed during clipboard read',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardStarted = Completer<void>();
    final clipboardResult = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        if (call.method == 'Clipboard.getData') {
          if (!clipboardStarted.isCompleted) clipboardStarted.complete();
          return clipboardResult.future;
        }
        return Future<Object?>.value(null);
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    try {
      await _openFixture(tester);
      await _pressCompareChord(tester);
      await tester.pump();
      await clipboardStarted.future;

      final field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final documentId = field.inputWindow.document.id;
      await tester.tap(find.byKey(ValueKey('close-tab-editor-$documentId')));
      await tester.pump(const Duration(milliseconds: 100));
      clipboardResult.complete(const {'text': 'stale clipboard snapshot'});
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      expect(find.text('比较已取消：读取剪贴板期间活动文件已变化'), findsOneWidget);
      final replacementField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(replacementField.inputWindow.document.id, isNot(documentId));
    } finally {
      if (!clipboardResult.isCompleted) {
        clipboardResult.complete(const {'text': 'unused'});
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('rejects clipboard inputs beyond the line budget without rows',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': List<String>.filled(8193, 'line').join('\n')}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      await _openFixture(tester);

      await _pressCompareChord(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      expect(find.text('比较已取消：差异超过当前预览预算，未显示部分结果'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reports a clipboard without plain text and opens no preview',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      await _openFixture(tester);

      await _pressCompareChord(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clipboard-compare-preview')),
          findsNothing);
      expect(find.text('比较已取消：剪贴板没有纯文本内容'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
