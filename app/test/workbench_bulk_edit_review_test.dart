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

const _cargoBefore = 'alpha\nbeta\n';
const _rustBefore = 'gamma\ndelta\n';

class _WorkbenchFixture {
  const _WorkbenchFixture({
    required this.cargo,
    required this.rust,
    required this.state,
  });

  final File cargo;
  final File rust;
  final dynamic state;

  String get cargoUri => 'file:///${cargo.absolute.path.replaceAll(r'\', '/')}';
  String get rustUri => 'file:///${rust.absolute.path.replaceAll(r'\', '/')}';
}

Future<_WorkbenchFixture> _startWorkbench(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final temp = Directory.systemTemp.createTempSync('alula_bulk_edit_review_');
  final workspace = Directory('${temp.path}/workspace')..createSync();
  Directory('${workspace.path}/src').createSync();
  final cargo = File('${workspace.path}/Cargo.toml')
    ..writeAsStringSync(_cargoBefore);
  final rust = File('${workspace.path}/src/main.rs')
    ..writeAsStringSync(_rustBefore);
  final base = temp.path.replaceAll(r'\', '/');

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('Cargo.toml').first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text('src').first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('main.rs').first);
  await tester.pump(const Duration(milliseconds: 200));

  return _WorkbenchFixture(
    cargo: cargo,
    rust: rust,
    state: tester.state(find.byType(WorkbenchPage)),
  );
}

WorkspaceEdit _edit(_WorkbenchFixture fixture,
        {String transactionId = 'review'}) =>
    WorkspaceEdit(
      [
        WorkspaceDocumentEdit(
          uri: fixture.cargoUri,
          edits: const [
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(0, 0),
                end: WorkspaceTextPosition(0, 0),
              ),
              newText: '# selected cargo\n',
            ),
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(1, 0),
                end: WorkspaceTextPosition(1, 0),
              ),
              newText: '# skipped cargo\n',
            ),
          ],
        ),
        WorkspaceDocumentEdit(
          uri: fixture.rustUri,
          edits: const [
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(0, 0),
                end: WorkspaceTextPosition(0, 0),
              ),
              newText: '// rust one\n',
            ),
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(1, 0),
                end: WorkspaceTextPosition(1, 0),
              ),
              newText: '// rust two\n',
            ),
          ],
        ),
      ],
      transactionId: transactionId,
    );

String _editorText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

Future<void> _activateTab(WidgetTester tester, String label) async {
  final hasSuffix = label.contains(' •');
  final exact = find.text(label);
  final target = hasSuffix && exact.evaluate().isNotEmpty
      ? exact
      : find.text(label.replaceFirst(' •', '')).last;
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _history(WidgetTester tester, {required bool redo}) async {
  await tester.tap(find.byType(TextField).first);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
      'Workbench review applies selected edits atomically with per-document undo and save',
      (tester) async {
    final fixture = await _startWorkbench(tester);
    final Future<bool> review = fixture.state.reviewWorkspaceEdit(
      _edit(fixture),
    ) as Future<bool>;
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('workbench-bulk-edit-preview-edit-checkbox-0-1'),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-apply')),
    );
    await tester.pumpAndSettle();
    expect(await review, isTrue);

    const cargoAfter = '# selected cargo\n$_cargoBefore';
    const rustAfter = '// rust one\ngamma\n// rust two\ndelta\n';
    expect(find.text('Cargo.toml •'), findsOneWidget);
    expect(find.text('main.rs •'), findsOneWidget);
    expect(_editorText(tester), rustAfter);

    await _history(tester, redo: false);
    expect(_editorText(tester), _rustBefore);
    await _history(tester, redo: true);
    expect(_editorText(tester), rustAfter);

    await _activateTab(tester, 'Cargo.toml •');
    expect(_editorText(tester), cargoAfter);
    await _history(tester, redo: false);
    expect(_editorText(tester), _cargoBefore);
    await _activateTab(tester, 'main.rs •');
    expect(_editorText(tester), rustAfter);
    await _activateTab(tester, 'Cargo.toml •');
    await _history(tester, redo: true);
    expect(_editorText(tester), cargoAfter);

    await _save(tester);
    expect(fixture.cargo.readAsStringSync(), cargoAfter);
    await _activateTab(tester, 'main.rs •');
    await _save(tester);
    expect(fixture.rust.readAsStringSync(), rustAfter);
    expect(find.text('Cargo.toml •'), findsNothing);
    expect(find.text('main.rs •'), findsNothing);
  });

  testWidgets('Workbench review pins source versions and rejects stale batches',
      (tester) async {
    final fixture = await _startWorkbench(tester);
    final Future<bool> review = fixture.state.reviewWorkspaceEdit(
      _edit(fixture, transactionId: 'stale-review'),
    ) as Future<bool>;
    await tester.pumpAndSettle();

    final intervening = fixture.state.applyWorkspaceEdit(WorkspaceEdit([
      WorkspaceDocumentEdit(
        uri: fixture.rustUri,
        edits: const [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 0),
            ),
            newText: '// intervening edit\n',
          ),
        ],
      ),
    ])) as bool;
    expect(
      intervening,
      isTrue,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-apply')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-error')),
      findsOneWidget,
    );
    expect(_editorText(tester), '// intervening edit\n$_rustBefore');

    await tester.tap(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-discard')),
    );
    await tester.pumpAndSettle();
    expect(await review, isFalse);
    await _activateTab(tester, 'Cargo.toml');
    expect(_editorText(tester), _cargoBefore);
    expect(find.text('Cargo.toml •'), findsNothing);
  });

  testWidgets('Workbench review Escape and Discard leave documents unchanged',
      (tester) async {
    final fixture = await _startWorkbench(tester);

    final Future<bool> escaped = fixture.state.reviewWorkspaceEdit(
      _edit(fixture, transactionId: 'escape-review'),
    ) as Future<bool>;
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await escaped, isFalse);

    final Future<bool> discarded = fixture.state.reviewWorkspaceEdit(
      _edit(fixture, transactionId: 'discard-review'),
    ) as Future<bool>;
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('workbench-bulk-edit-preview-discard')),
    );
    await tester.pumpAndSettle();
    expect(await discarded, isFalse);

    expect(fixture.cargo.readAsStringSync(), _cargoBefore);
    expect(fixture.rust.readAsStringSync(), _rustBefore);
    expect(find.text('Cargo.toml •'), findsNothing);
    expect(find.text('main.rs •'), findsNothing);
  });
}
