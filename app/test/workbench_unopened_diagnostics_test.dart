import 'dart:convert';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/diagnostic_navigation_peek.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/status_bar.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/native_drag_drop.dart';

void main() {
  setUp(mockNativeDragDrop);

  testWidgets('F8 opens a cached URI without selecting an unversioned range',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-f8-unopened');
    final workspace = Directory(p.join(temp.path, 'workspace'))..createSync();
    final source = File(p.join(workspace.path, 'm_open.rs'))
      ..writeAsStringSync('fn source() {}\n');
    const newText = 'first\n😀 abcdefghi\n';
    const newBytes = '\ufefffirst\r\n😀 abcdefghi\r\n';
    final target = File(p.join(workspace.path, 'z_unopened.rs'))
      ..writeAsStringSync(newBytes);
    final core = AlulaCore.load();
    final probe = core.openDoc(984642, '');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      core.lsp.shutdownWorkspace(workspace.path);
      probe.close();
      temp.deleteSync(recursive: true);
    });
    final executable = p.join(
      Directory.current.parent.path,
      'target',
      'debug',
      Platform.isWindows
          ? 'async_completion_fake_lsp.exe'
          : 'async_completion_fake_lsp',
    );
    core.lsp.start(probe.id, workspace.path, [
      executable,
      p.join(temp.path, 'process.log'),
      '0',
      'unopened-diagnostics',
    ]);
    final session = SessionStore(path: p.join(temp.path, 'session.json'));
    expect(
      session.save({
        'v': 1,
        'focused': 'editor',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 3,
            'docs': [
              {'id': 3, 'path': source.path}
            ],
          },
        ],
      }),
      isTrue,
    );
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        onCommandServiceReady: (value) => commands = value,
        layoutStore: LayoutStore(path: p.join(temp.path, 'layout.json')),
        sessionStore: session,
        keybindingsStore:
            KeybindingsStore(path: p.join(temp.path, 'keys.json')),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final starting = commands.execute('lsp.start');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await starting;
    final cached = await tester.runAsync(() async {
      final timeout = Stopwatch()..start();
      do {
        final candidate = core.lsp.nextUnopenedDiagnostic(
          probe.id,
          cursorUri: source.uri.toString(),
          openUris: [source.uri.toString()],
        );
        if (candidate?.uri.endsWith('/z_unopened.rs') ?? false) {
          return candidate;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } while (timeout.elapsed < const Duration(seconds: 3));
      return null;
    });
    expect(cached, isNotNull);
    expect(cached!.diagnostic['documentVersion'], isNull);
    ProblemsStatusCounts statusCounts() =>
        tester.widget<AlulaStatusBar>(find.byType(AlulaStatusBar)).problems;
    await tester.pump(const Duration(milliseconds: 800));
    expect(statusCounts().errors, 3);
    expect(statusCounts().warnings, 1);
    expect(statusCounts().infos, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(statusCounts().total, 4);
    final input = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    expect(
        tester.widget<TextField>(input).controller!.text, 'fn source() {}\n');
    await tester.tap(input);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<TextField>(input).controller!.text, newText);
    expect(tester.widget<TextField>(input).controller!.selection,
        const TextSelection.collapsed(offset: 0));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byType(DiagnosticNavigationPeek), findsNothing);
    expect(tester.widget<TextField>(input).controller!.selection,
        const TextSelection.collapsed(offset: 0));
    expect(target.readAsBytesSync(), utf8.encode(newBytes));

    final newWorkspace = Directory(p.join(temp.path, 'empty'))..createSync();
    final switching = commands.execute('file.openFolder');
    await tester.pumpAndSettle();
    final folderPath = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '文件夹路径',
    );
    await tester.enterText(folderPath, newWorkspace.path);
    await tester.tap(find.widgetWithText(FilledButton, '打开'));
    await tester.pumpAndSettle();
    expect(await switching, CommandExecutionStatus.executed);
    expect(statusCounts().total, 0);
  });
}
