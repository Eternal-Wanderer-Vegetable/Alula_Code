import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
// Test fixtures need the package's native-channel override, which is test-only.
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

Future<(Directory, Directory)> _createWorkspace(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final temp = Directory.systemTemp.createTempSync('alula-explorer-compare');
  addTearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  return (temp, workspace);
}

Future<void> _mountWorkspace(
  WidgetTester tester,
  Directory temp,
  Directory workspace,
) async {
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _rightClickNode(WidgetTester tester, String path) async {
  await tester.tap(
    find.byKey(ValueKey('explorer-node:$path')),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Future<void> _finishAsyncIo(WidgetTester tester) async {
  // Each completed filesystem await resumes the handler inside FakeAsync and
  // can start the next real I/O operation; pump between wall-clock waits.
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _chooseContextAction(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(find.text(label).last);
  await _finishAsyncIo(tester);
}

Future<void> _replaceText(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _saveWithCtrlS(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _finishAsyncIo(tester);
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
      'disk original is frozen with decoded text and modified side saves the Rust document',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final original = File('${workspace.path}/original.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('original 😀\r\nshared'),
        ]);
      final modified = File('${workspace.path}/modified.rs')
        ..writeAsStringSync('modified source\nshared');
      await _mountWorkspace(tester, temp, workspace);

      await _rightClickNode(tester, original.path);
      expect(find.text('Select for Compare'), findsOneWidget);
      expect(find.text('Compare with Selected'), findsNothing);
      await _chooseContextAction(tester, 'Select for Compare');
      expect(find.textContaining('已选择 original.rs 用于比较'), findsOneWidget);

      original.writeAsStringSync('later on disk\nshared');
      await _rightClickNode(tester, original.path);
      expect(find.text('Compare with Selected'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await _rightClickNode(tester, modified.path);
      expect(find.text('Compare with Selected'), findsOneWidget);
      await _chooseContextAction(tester, 'Compare with Selected');

      final preview = find.byKey(const ValueKey('explorer-compare-preview'));
      expect(preview, findsOneWidget);
      expect(find.text('original.rs ↔ modified.rs'), findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.text('original 😀')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('later on disk')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('explorer-compare-modified-editor')),
        findsOneWidget,
      );

      final compareInput = find.descendant(
        of: find.byKey(const ValueKey('explorer-compare-modified-pane')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')),
      );
      final compareFieldFinder = find.descendant(
        of: find.byKey(const ValueKey('explorer-compare-modified-pane')),
        matching: find.byType(RustTextInputField),
      );
      await tester.showKeyboard(compareInput);
      await _replaceText(tester, 'edited through compare\nshared');
      final compareDoc = tester
          .widget<RustTextInputField>(compareFieldFinder)
          .inputWindow
          .document;
      expect(compareDoc.resync().content, 'edited through compare\nshared');
      expect(compareDoc.isDirty, isTrue);
      expect(modified.readAsStringSync(), 'modified source\nshared');
      await _saveWithCtrlS(tester);
      expect(modified.readAsStringSync(), 'edited through compare\nshared');
      expect(compareDoc.isDirty, isFalse);

      await tester.tap(find.byKey(const ValueKey('explorer-compare-close')));
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      final editor = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField).first,
      );
      expect(
        editor.inputWindow.document.resync().content,
        'edited through compare\nshared',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an open dirty original is captured once and stays frozen',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final original = File('${workspace.path}/original.rs')
        ..writeAsStringSync('disk original\nshared');
      final modified = File('${workspace.path}/modified.rs')
        ..writeAsStringSync('modified source\nshared');
      await _mountWorkspace(tester, temp, workspace);

      await tester.tap(find.byKey(ValueKey('explorer-node:${original.path}')));
      await tester.pump(const Duration(milliseconds: 250));
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      await tester.showKeyboard(editor);
      await _replaceText(tester, 'dirty original 😀\nshared');

      await _rightClickNode(tester, original.path);
      await _chooseContextAction(tester, 'Select for Compare');
      await tester.showKeyboard(editor);
      await _replaceText(tester, 'changed after selection\nshared');

      await _rightClickNode(tester, modified.path);
      await _chooseContextAction(tester, 'Compare with Selected');
      final preview = find.byKey(const ValueKey('explorer-compare-preview'));
      expect(
        find.descendant(
          of: preview,
          matching: find.textContaining('dirty original 😀'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.textContaining('changed after selection'),
        ),
        findsNothing,
      );
      expect(original.readAsStringSync(), 'disk original\nshared');
      await tester.tap(find.byKey(const ValueKey('explorer-compare-close')));
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('selection cancels if an open source document changes in flight',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final original = File('${workspace.path}/original.rs')
        ..writeAsStringSync('before\nshared');
      final modified = File('${workspace.path}/modified.rs')
        ..writeAsStringSync('modified\nshared');
      await _mountWorkspace(tester, temp, workspace);

      await tester.tap(find.byKey(ValueKey('explorer-node:${original.path}')));
      await tester.pump(const Duration(milliseconds: 250));
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      await tester.showKeyboard(editor);
      await _rightClickNode(tester, original.path);
      await tester.tap(find.text('Select for Compare'));

      await tester.showKeyboard(editor);
      await _replaceText(tester, 'changed during selection\nshared');
      await _finishAsyncIo(tester);

      expect(
        find.textContaining('活动文档在读取期间已变化'),
        findsOneWidget,
      );
      await _rightClickNode(tester, modified.path);
      expect(find.text('Compare with Selected'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'files only get compare actions; deleted originals and workspace switches are rejected',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final folder = Directory('${workspace.path}/folder')..createSync();
      final original = File('${workspace.path}/original.rs')
        ..writeAsStringSync('original\nshared');
      final modified = File('${workspace.path}/modified.rs')
        ..writeAsStringSync('modified\nshared');
      File('${workspace.path}/binary.bin').writeAsBytesSync([0, 1, 2]);
      final nextWorkspace = Directory('${temp.path}/next-workspace')
        ..createSync();
      final nextFile = File('${nextWorkspace.path}/next.rs')
        ..writeAsStringSync('next workspace');
      await _mountWorkspace(tester, temp, workspace);

      await _rightClickNode(tester, folder.path);
      expect(find.text('Select for Compare'), findsNothing);
      await tester.pumpAndSettle();

      final binary = File('${workspace.path}/binary.bin');
      await _rightClickNode(tester, binary.path);
      await _chooseContextAction(tester, 'Select for Compare');
      expect(find.textContaining('二进制文件'), findsOneWidget);
      await _rightClickNode(tester, modified.path);
      expect(find.text('Compare with Selected'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await _rightClickNode(tester, original.path);
      await _chooseContextAction(tester, 'Select for Compare');
      original.deleteSync();
      await _rightClickNode(tester, modified.path);
      await _chooseContextAction(tester, 'Compare with Selected');
      expect(find.textContaining('原始文件已删除'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('explorer-compare-preview')), findsNothing);

      await tester.tap(find.byTooltip('打开文件夹').first);
      await tester.pumpAndSettle();
      final folderPath = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '文件夹路径',
      );
      await tester.enterText(folderPath, nextWorkspace.path);
      await tester.tap(find.text('打开').last);
      await tester.pumpAndSettle();

      await _rightClickNode(tester, nextFile.path);
      expect(find.text('Select for Compare'), findsOneWidget);
      expect(find.text('Compare with Selected'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('oversized original is rejected before a compare preview opens',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final oversized = File('${workspace.path}/oversized.rs')
        ..writeAsStringSync(List<String>.filled(2000001, 'x').join());
      await _mountWorkspace(tester, temp, workspace);

      await _rightClickNode(tester, oversized.path);
      await _chooseContextAction(tester, 'Select for Compare');
      expect(find.textContaining('2,000,000 UTF-16 单元上限'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('explorer-compare-preview')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('diff row budget rejects the complete Explorer comparison',
      (tester) async {
    try {
      final (temp, workspace) = await _createWorkspace(tester);
      final lines = List<String>.filled(8193, 'same');
      final original = File('${workspace.path}/original.rs')
        ..writeAsStringSync(lines.join('\n'));
      lines[8192] = 'changed';
      final modified = File('${workspace.path}/modified.rs')
        ..writeAsStringSync(lines.join('\n'));
      await _mountWorkspace(tester, temp, workspace);

      await _rightClickNode(tester, original.path);
      await _chooseContextAction(tester, 'Select for Compare');
      await _rightClickNode(tester, modified.path);
      await _chooseContextAction(tester, 'Compare with Selected');

      expect(
        find.textContaining('差异超过当前预览预算'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('explorer-compare-preview')),
        findsNothing,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
