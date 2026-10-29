import 'dart:io';

import 'package:alula_app/editor/workspace_edit.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final String _fixtureRoot =
    '${Directory.current.parent.path}/tests/fixtures/rust-mini';

String _uriFor(String path) => 'file:///${path.replaceAll(r'\', '/')}';

String _uri(String fileName) => _uriFor('$_fixtureRoot/$fileName');

void main() {
  late Directory temp;
  late LayoutStore layout;
  late SessionStore session;
  late KeybindingsStore keybindings;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_workspace_edit_');
    final base = temp.path.replaceAll(r'\', '/');
    layout = LayoutStore(path: '$base/layout.json');
    session = SessionStore(path: '$base/session.json');
    keybindings = KeybindingsStore(path: '$base/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  String editorText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  Future<void> startWorkbench(WidgetTester tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: _fixtureRoot,
      layoutStore: layout,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Cargo.toml').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('src').first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> undo(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).first);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets(
      'cross-document edit validates, commits, and keeps per-document undo',
      (tester) async {
    await startWorkbench(tester);
    final cargoBefore = File('$_fixtureRoot/Cargo.toml').readAsStringSync();
    final rustBefore = File('$_fixtureRoot/src/main.rs').readAsStringSync();
    expect(editorText(tester), rustBefore);

    final dynamic state = tester.state(find.byType(WorkbenchPage));
    final rejected = state.applyWorkspaceEdit(WorkspaceEdit([
      WorkspaceDocumentEdit(
        uri: _uri('Cargo.toml'),
        edits: const [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 0),
            ),
            newText: '# stale\n',
          ),
        ],
      ),
      WorkspaceDocumentEdit(
        uri: _uri('src/main.rs'),
        version: 999,
        edits: const [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 0),
            ),
            newText: '// stale\n',
          ),
        ],
      ),
    ])) as bool;
    expect(rejected, isFalse);
    await tester.pump();
    expect(editorText(tester), rustBefore);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(editorText(tester), cargoBefore);

    final committed = state.applyWorkspaceEdit(WorkspaceEdit([
      WorkspaceDocumentEdit(
        uri: _uri('Cargo.toml'),
        edits: const [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 0),
            ),
            newText: '# workspace A\n',
          ),
        ],
      ),
      WorkspaceDocumentEdit(
        uri: _uri('src/main.rs'),
        edits: const [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 0),
            ),
            newText: '// workspace B\n',
          ),
        ],
      ),
    ])) as bool;
    expect(committed, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(editorText(tester), '# workspace A\n$cargoBefore');

    await undo(tester);
    expect(editorText(tester), cargoBefore);

    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(editorText(tester), '// workspace B\n$rustBefore');
    await undo(tester);
    expect(editorText(tester), rustBefore);
  });
}
