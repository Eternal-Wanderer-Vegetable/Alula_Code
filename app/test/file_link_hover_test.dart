import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_rendering.dart';
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
    'modifier hover paints the precise file link and clears on release and exit',
    (tester) async {
      final profile = Directory.systemTemp.createTempSync('alula-link-pointer');
      final target = File('${profile.path}/target file 🐙.txt')
        ..writeAsStringSync('destination 中😀\r\n');
      final uri = target.uri.toString();
      final tail = List.filled(55, '其他行').join('\r\n');
      final original = utf8.encode('\uFEFF普通文字 🦊\r\n($uri). 尾部\r\n$tail\r\n');
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

      final field = find.byType(RustTextInputField);
      final input = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final textField = find.descendant(
        of: field,
        matching: find.byType(TextField),
      );
      final editor = tester.widget<RustTextInputField>(field);
      final start = editor.inputWindow.text.indexOf(uri);
      expect(start, greaterThanOrEqualTo(0));
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      Offset at(int offset) {
        final render = tester.state<EditableTextState>(input).renderEditable;
        return render.localToGlobal(
          render.getLocalRectForCaret(TextPosition(offset: offset)).center,
        );
      }

      Iterable<EditorRangeDecoration> underlines() => tester
          .widgetList<CustomPaint>(
            find.descendant(of: field, matching: find.byType(CustomPaint)),
          )
          .map((paint) => paint.painter)
          .whereType<EditorRangeDecorationPainter>()
          .expand((painter) => painter.decorations)
          .where((range) => range.underlineColor != null);

      void expectInactive() {
        expect(
          tester.widget<TextField>(textField).mouseCursor,
          isNot(SystemMouseCursors.click),
        );
        expect(underlines(), isEmpty);
      }

      void expectActive() {
        expect(
          tester.widget<TextField>(textField).mouseCursor,
          SystemMouseCursors.click,
        );
        expect(underlines().single.startUtf16, start);
        expect(underlines().single.endUtf16, start + uri.length);
        expect(
          underlines().single.documentVersion,
          editor.inputWindow.document.version,
        );
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final linkPoint = at(start + 12);
      final plain = at(2);
      await mouse.addPointer(location: plain);
      try {
        await mouse.moveTo(linkPoint);
        await tester.pumpAndSettle();
        expectInactive();

        await tester.sendKeyDownEvent(modifier);
        await tester.pumpAndSettle();
        expectActive();
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expectInactive();

        await tester.sendKeyDownEvent(modifier);
        await tester.pumpAndSettle();
        expectActive();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expectInactive();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expectActive();

        final scroll = editor.scrollController!;
        expect(scroll.position.maxScrollExtent, greaterThan(100));
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        expectInactive();
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await mouse.moveTo(at(start + 13));
        await tester.pumpAndSettle();
        expectActive();
        await mouse.moveTo(plain);
        await tester.pumpAndSettle();
        expectInactive();
        await mouse.moveTo(linkPoint);
        await tester.pumpAndSettle();
        expectActive();

        await mouse.moveTo(const Offset(2, 2));
        await tester.pumpAndSettle();
        expectInactive();
        await mouse.moveTo(linkPoint);
        await tester.pumpAndSettle();
        expectActive();

        await mouse.down(linkPoint);
        await tester.pumpAndSettle();
        expectInactive();
        await mouse.moveBy(const Offset(42, 0));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(
          tester.widget<RustTextInputField>(field).inputWindow.text,
          contains(uri),
        );

        await mouse.moveTo(linkPoint);
        await tester.pumpAndSettle();
        expectActive();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        await tester.sendKeyUpEvent(modifier);
        await mouse.removePointer();
      }
      expect(tester.takeException(), isNull);
      expect(source.readAsBytesSync(), original);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );
}
