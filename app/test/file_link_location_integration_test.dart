import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Open Link resolves local file line and range fragments in UTF-16',
    (tester) async {
      final profile = Directory.systemTemp.createTempSync(
        'alula-link-location',
      );
      final target = File('${profile.path}/target # 🐙.txt');
      const text = 'first\tAlpha\n\tA🦊Z\n末Tail\n';
      final targetBytes = utf8.encode('\uFEFF${text.replaceAll('\n', '\r\n')}');
      target.writeAsBytesSync(targetBytes);
      final far = File('${profile.path}/far target.txt');
      final farText = List.filled(700, 'repeat 🐙 row' * 9).join('\r\n');
      far.writeAsStringSync(farText);
      final targetUri = target.uri.toString();
      expect(targetUri, contains('%23'));
      final links = [
        '$targetUri#L2,4',
        '$targetUri#L3,2-L2%2C3',
        '$targetUri#900',
        '$targetUri#heading',
        '$targetUri#L2,2-L2,4',
        '${far.uri}#L2,3-L690,5',
        '${far.uri}#L2,3-900000000000000000000',
      ];
      final original = utf8.encode('\uFEFF说明 🦊\r\n${links.join('\r\n')}\r\n');
      final source = File('${profile.path}/source.md')
        ..writeAsBytesSync(original);
      final session = SessionStore(path: '${profile.path}/session.json')
        ..save({
          'v': 1,
          'workspace': profile.path,
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
        await tester.runAsync(() => profile.delete(recursive: true));
      });
      late CommandService commands;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkbenchPage(
            autoFolder: profile.path,
            layoutStore: LayoutStore(path: '${profile.path}/layout.json'),
            sessionStore: session,
            keybindingsStore: KeybindingsStore(
              path: '${profile.path}/keys.json',
            ),
            onCommandServiceReady: (value) => commands = value,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 650));
      final editor = find.byType(RustTextInputField);
      final input = find.descendant(
        of: editor,
        matching: find.byType(EditableText),
      );
      RustTextInputField currentEditor() =>
          tester.widget<RustTextInputField>(editor);
      EditableText editable() => tester.widget<EditableText>(input);
      TextSelection absoluteSelection() {
        final active = currentEditor();
        final local = editable().controller.selection;
        return TextSelection(
          baseOffset: active.inputWindow.startUtf16 + local.baseOffset,
          extentOffset: active.inputWindow.startUtf16 + local.extentOffset,
        );
      }

      Future<void> follow(String uri) async {
        final offset = editable().controller.text.indexOf(uri);
        expect(offset, greaterThanOrEqualTo(0));
        editable().controller.selection = TextSelection.collapsed(
          offset: offset + 12,
        );
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(
            () => commands.execute('editor.action.openLink'),
          ),
          CommandExecutionStatus.executed,
        );
        await tester.pumpAndSettle();
      }

      Future<void> returnToSource() async {
        expect(
          await tester.runAsync(
            () => commands.execute('workbench.action.closeActiveEditor'),
          ),
          CommandExecutionStatus.executed,
        );
        await tester.pumpAndSettle();
        expect(currentEditor().inputWindow.text, contains(links.last));
      }

      final start = text.indexOf('🦊');
      final end = text.indexOf('末') + 1;

      await follow(links[0]);
      expect(currentEditor().inputWindow.text, text);
      expect(absoluteSelection(), TextSelection.collapsed(offset: start));
      expect(currentEditor().focusNode!.hasPrimaryFocus, isTrue);
      await returnToSource();
      await follow(links[1]);
      expect(
        absoluteSelection(),
        TextSelection(baseOffset: start, extentOffset: end),
      );
      expect(currentEditor().inputWindow.text.substring(start, end), '🦊Z\n末');
      await returnToSource();
      await follow(links[2]);
      expect(absoluteSelection(),
          const TextSelection.collapsed(offset: text.length));
      await returnToSource();
      await follow(links[3]);
      expect(currentEditor().inputWindow.text, text);
      expect(absoluteSelection(), const TextSelection.collapsed(offset: 0));
      await returnToSource();
      await follow(links[4]);
      expect(
        absoluteSelection(),
        TextSelection(baseOffset: start - 1, extentOffset: start + 2),
      );
      expect(currentEditor().inputWindow.text.substring(start - 1, start + 2),
          'A🦊');
      await returnToSource();
      await follow(links[5]);
      final farLf = farText.replaceAll('\r\n', '\n').split('\n');
      final farStart = farLf.take(1).join('\n').length + 1 + 2;
      final farEnd = farLf.take(689).join('\n').length + 1 + 4;
      final field = currentEditor();
      expect(
        field.inputWindow.totalUtf16Length,
        farText.replaceAll('\r\n', '\n').length,
      );
      final selected = field.rangeDecorations.singleWhere(
        (r) => r.startUtf16 == farStart && r.endUtf16 == farEnd,
      );
      expect(selected.documentVersion, field.inputWindow.document.version);
      expect(absoluteSelection(), TextSelection.collapsed(offset: farEnd));
      await returnToSource();
      await follow(links[6]);
      final eof = currentEditor().inputWindow.totalUtf16Length;
      expect(
        currentEditor().rangeDecorations.any(
              (range) => range.startUtf16 == farStart && range.endUtf16 == eof,
            ),
        isTrue,
      );
      expect(absoluteSelection(), TextSelection.collapsed(offset: eof));
      expect(source.readAsBytesSync(), original);
      expect(target.readAsBytesSync(), targetBytes);
    },
  );
}
