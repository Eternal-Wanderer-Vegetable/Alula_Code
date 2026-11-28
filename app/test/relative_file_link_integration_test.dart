import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('relative file URI targets follow the current file directory',
      (tester) async {
    final workspace = Directory.systemTemp.createTempSync(
      'alula-relative-file-link',
    );
    final nested = Directory('${workspace.path}/nested')..createSync();
    Directory('${nested.path}/directory').createSync();
    const nearName = 'target # 🐙.txt';
    const parentName = 'outer # 🦊.txt';
    const nearContents = 'right sibling\nsecond line\n';
    const parentContents = 'one directory above\nsecond line\n';
    final near = File('${nested.path}/$nearName')
      ..writeAsStringSync(nearContents);
    final parent = File('${workspace.path}/$parentName')
      ..writeAsStringSync(parentContents);
    File('${workspace.path}/$nearName').writeAsStringSync('root decoy\n');
    final nearUri = Uri.encodeComponent(nearName);
    final parentUri = Uri.encodeComponent(parentName);
    final links = [
      'file://./$nearUri',
      'file:///./../$parentUri#L2,2',
      'file://%2e/$nearUri?query=1',
      'file:///%2E/../$parentUri#L2%2C2',
      'file:///./directory',
      'file://localhost/$nearUri',
      'file://./bad%00.txt',
    ];
    final sourceContents = '说明 🦊\n${links.join('\n')}\n';
    final source = File('${nested.path}/source.md')
      ..writeAsStringSync(sourceContents);
    final session = SessionStore(path: '${workspace.path}/session.json')
      ..save({
        'v': 1,
        'workspace': workspace.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 3,
            'docs': [
              {'id': 3, 'path': source.path},
            ],
          },
        ],
      });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => workspace.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '${workspace.path}/layout.json'),
          sessionStore: session,
          onCommandServiceReady: (value) => commands = value,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 650));

    final field = find.byType(RustTextInputField);
    final input =
        find.descendant(of: field, matching: find.byType(EditableText));
    RustTextInputField editor() => tester.widget<RustTextInputField>(field);
    EditableText editable() => tester.widget<EditableText>(input);
    Future<void> command(String name) async {
      expect(await tester.runAsync(() => commands.execute(name)),
          CommandExecutionStatus.executed);
      await tester.pumpAndSettle();
    }

    Future<void> follow(String uri) async {
      final prefix = editable().controller.text.indexOf(uri);
      expect(prefix, greaterThanOrEqualTo(0));
      editable().controller.selection =
          TextSelection.collapsed(offset: prefix + 11);
      await tester.pumpAndSettle();
      await command('editor.action.openLink');
    }

    for (final (index, expected) in [
      (0, nearContents),
      (1, parentContents),
      (2, nearContents),
      (3, parentContents),
    ]) {
      await follow(links[index]);
      expect(editor().inputWindow.text, expected);
      expect(editor().focusNode!.hasPrimaryFocus, isTrue);
      expect(editable().controller.selection,
          const TextSelection.collapsed(offset: 0));
      await command('workbench.action.closeActiveEditor');
      expect(editor().inputWindow.text, sourceContents);
    }

    for (final uri in links.skip(4)) {
      await follow(uri);
      expect(editor().inputWindow.text, sourceContents);
    }

    await command('workbench.action.files.newUntitledFile');
    await tester.enterText(input, links[0]);
    await tester.pumpAndSettle();
    final untitled = editor().inputWindow.document.id;
    await follow(links[0]);
    expect(editor().inputWindow.document.id, untitled);
    expect(editor().inputWindow.text, links[0]);
    expect(source.readAsStringSync(), sourceContents);
    expect(near.readAsStringSync(), nearContents);
    expect(parent.readAsStringSync(), parentContents);
  });
}
