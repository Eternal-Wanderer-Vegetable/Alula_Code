import 'dart:async';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openWorkspace(
  WidgetTester tester,
  Directory temp,
  Directory workspace, {
  Future<DefinitionResult?> Function(int, int, int)? definitionRequest,
  String openFileName = 'main.rs',
}) async {
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    definitionRequest: definitionRequest,
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text(openFileName).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(TextField).last);
  await tester.pump();
}

Finder _activeTextField() => find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );

TextEditingController _activeController(WidgetTester tester) =>
    tester.widget<TextField>(_activeTextField()).controller!;

Future<void> _closeNamedTab(WidgetTester tester, String name) async {
  final tab = find.ancestor(
    of: find.text(name).last,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is Container &&
          key is ValueKey<String> &&
          key.value.startsWith('tab-');
    }),
  );
  final close = find.descendant(
    of: tab.first,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is InkWell &&
          key is ValueKey<String> &&
          key.value.startsWith('close-tab-');
    }),
  );
  await tester.tap(close);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _runPaletteCommand(WidgetTester tester, String query) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 200));
  final quickInput = find.byKey(const ValueKey('quick-input'));
  await tester.enterText(
    find.descendant(of: quickInput, matching: find.byType(TextField)),
    query,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
      'LSP definition opens a cross-file target and back/forward restore it',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-cross-file-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = '\uFEFF// 🦊 target\nfn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);

    await _openWorkspace(
      tester,
      temp,
      workspace,
      definitionRequest: (id, offset, version) async => DefinitionResult(
        version: version,
        uri: Uri.file(targetPath).toString(),
        line: 1,
        character: 3,
      ),
    );
    final callOffset = source.indexOf('target()');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: callOffset);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('跳转到 target.rs'), findsOneWidget);
    expect(
        _activeController(tester).text, targetText.replaceFirst('\uFEFF', ''));
    expect(
      _activeController(tester).selection.extentOffset,
      targetText.replaceFirst('\uFEFF', '').indexOf('target()'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, callOffset);

    await _closeNamedTab(tester, 'target.rs');
    expect(_activeController(tester).text, source);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        _activeController(tester).text, targetText.replaceFirst('\uFEFF', ''));
    expect(
      _activeController(tester).selection.extentOffset,
      targetText.replaceFirst('\uFEFF', '').indexOf('target()'),
    );
  });

  testWidgets('definition response is ignored after its source version changes',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-stale-definition');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = 'fn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);
    final response = Completer<DefinitionResult?>();
    var requestVersion = -1;

    await _openWorkspace(
      tester,
      temp,
      workspace,
      definitionRequest: (id, offset, version) {
        requestVersion = version;
        return response.future;
      },
    );
    _activeController(tester).selection = TextSelection.collapsed(
      offset: source.indexOf('target()'),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(requestVersion, greaterThan(0));

    await tester.enterText(_activeTextField(), '$source// changed\n');
    await tester.pump(const Duration(milliseconds: 100));
    response.complete(DefinitionResult(
      version: requestVersion,
      uri: Uri.file(targetPath).toString(),
      line: 0,
      character: 3,
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('文档已更改，已取消跳转'), findsOneWidget);
    expect(_activeController(tester).text, '$source// changed\n');
  });

  testWidgets(
      'definition opens an already open file in the source editor group',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-group-definition');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = 'fn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);

    await _openWorkspace(
      tester,
      temp,
      workspace,
      openFileName: 'target.rs',
      definitionRequest: (id, offset, version) async => DefinitionResult(
        version: version,
        uri: Uri.file(targetPath).toString(),
        line: 0,
        character: 3,
      ),
    );
    await _runPaletteCommand(tester, '拆分编辑器');
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(RustTextInputField), findsNWidgets(2));

    final sourceField = find.byType(RustTextInputField).last;
    final sourceTextField = find.descendant(
      of: sourceField,
      matching: find.byType(TextField),
    );
    await tester.tap(sourceTextField);
    await tester.pump();
    final sourceOffset = source.indexOf('target()');
    tester.widget<TextField>(sourceTextField).controller!.selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RustTextInputField), findsNWidgets(2));
    final firstField = find.byType(RustTextInputField).first;
    final lastField = find.byType(RustTextInputField).last;
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: firstField,
            matching: find.byType(TextField),
          ))
          .controller!
          .text,
      targetText,
    );
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: lastField,
            matching: find.byType(TextField),
          ))
          .controller!
          .selection
          .extentOffset,
      targetText.indexOf('target()'),
    );
  });

  testWidgets('last edit location restores the UTF-16 caret position',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-last-edit-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { let value = 1; }\n';
    const edited = 'fn main() { let answer = 1; }\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);

    await _openWorkspace(tester, temp, workspace);
    final editOffset = source.indexOf('value');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: editOffset);
    await tester.pump();
    await tester.enterText(_activeTextField(), edited);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_activeController(tester).text, edited);

    _activeController(tester).selection =
        const TextSelection.collapsed(offset: edited.length);
    await tester.pump();
    await _runPaletteCommand(tester, '转到上次编辑位置');
    expect(_activeController(tester).selection.extentOffset, editOffset);
  });
}
