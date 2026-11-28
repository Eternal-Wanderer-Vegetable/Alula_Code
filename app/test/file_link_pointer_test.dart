import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'modifier click follows the exact local file URI and opens beside',
    (tester) async {
      final profile = Directory.systemTemp.createTempSync('alula-link-pointer');
      final target = File('${profile.path}/target file 🐙.txt')
        ..writeAsStringSync('destination 中😀\r\n');
      final uri = target.uri.toString();
      final original = utf8.encode('\uFEFF普通文字 🦊\r\n($uri). 尾部\r\n');
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
      await tester.pumpWidget(
        MaterialApp(
          home: WorkbenchPage(
            autoFolder: profile.path,
            layoutStore: LayoutStore(path: '${profile.path}/layout.json'),
            sessionStore: session,
            keybindingsStore: KeybindingsStore(
              path: '${profile.path}/keys.json',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 650));
      final editors = find.byType(RustTextInputField);
      final input = find.descendant(
        of: editors,
        matching: find.byType(EditableText),
      );
      final primaryModifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;

      RustTextInputField onlyEditor() =>
          tester.widget<RustTextInputField>(editors);
      Offset pointAt(int offset) {
        final render = tester.state<EditableTextState>(input).renderEditable;
        return render.localToGlobal(
          render.getLocalRectForCaret(TextPosition(offset: offset)).center,
        );
      }

      Future<void> click(
        Offset position, {
        bool modified = false,
        bool side = false,
      }) async {
        if (modified) await tester.sendKeyDownEvent(primaryModifier);
        if (side) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        try {
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
        } finally {
          if (side) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          if (modified) await tester.sendKeyUpEvent(primaryModifier);
        }
      }

      final linkStart = onlyEditor().inputWindow.text.indexOf(uri);
      expect(linkStart, greaterThanOrEqualTo(0));
      final link = pointAt(linkStart + 12);
      await click(link);
      expect(onlyEditor().inputWindow.text, contains(uri));
      await click(pointAt(2), modified: true);
      expect(onlyEditor().inputWindow.text, contains(uri));

      await tester.sendKeyDownEvent(primaryModifier);
      final drag = await tester.startGesture(
        link,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(42, 0));
      await drag.up();
      await tester.sendKeyUpEvent(primaryModifier);
      await tester.pumpAndSettle();
      expect(onlyEditor().inputWindow.text, contains(uri));

      await click(link, modified: true);
      expect(editors, findsOneWidget);
      expect(onlyEditor().inputWindow.text, contains('destination 中😀'));
      expect(onlyEditor().focusNode?.hasPrimaryFocus, isTrue);

      await tester.sendKeyDownEvent(primaryModifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(primaryModifier);
      await tester.pumpAndSettle();
      expect(onlyEditor().inputWindow.text, contains(uri));

      await click(pointAt(linkStart + 12), modified: true, side: true);
      expect(editors, findsNWidgets(2));
      final fields = tester.widgetList<RustTextInputField>(editors).toList();
      expect(
        fields.any((field) => field.inputWindow.text.contains(uri)),
        isTrue,
      );
      expect(
        fields
            .singleWhere((field) => field.focusNode?.hasPrimaryFocus ?? false)
            .inputWindow
            .text,
        contains('destination 中😀'),
      );
      expect(source.readAsBytesSync(), original);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );
}
