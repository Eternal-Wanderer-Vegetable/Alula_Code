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
    'the local link hover offers a clickable action after the dwell',
    (tester) async {
      final profile = Directory.systemTemp.createTempSync('alula-link-pointer');
      final target = File('${profile.path}/target file 🐙.txt')
        ..writeAsStringSync('destination 中😀\r\n');
      final uri = target.uri.toString();
      final extra = List.filled(55, '滚动检查').join('\r\n');
      final original =
          utf8.encode('\uFEFF普通文字 🦊\r\n($uri).\r\n尾部\r\n$extra\r\n');
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
      RustTextInputField currentEditor() =>
          tester.widget<RustTextInputField>(field);
      final start = currentEditor().inputWindow.text.indexOf(uri);
      expect(start, greaterThanOrEqualTo(0));
      final render = tester.state<EditableTextState>(input).renderEditable;
      Offset pointAt(int offset) => render.localToGlobal(
            render.getLocalRectForCaret(TextPosition(offset: offset)).center,
          );
      final plain = pointAt(2);
      final below = pointAt(currentEditor().inputWindow.text.indexOf('尾部'));
      final link = pointAt(start + 12);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final action = find.byKey(const ValueKey('editor-file-link-hint-action'));
      await mouse.addPointer(location: plain);
      try {
        await mouse.moveTo(link);
        await tester.pump(const Duration(milliseconds: 180));
        expect(action, findsNothing);
        await mouse.moveTo(plain);
        await tester.pump(const Duration(milliseconds: 350));
        expect(action, findsNothing);

        await mouse.moveTo(link);
        await tester.pump(const Duration(milliseconds: 299));
        expect(action, findsNothing);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);
        final mac = defaultTargetPlatform == TargetPlatform.macOS;
        expect(find.text(mac ? '（Cmd+单击）' : '（Ctrl+单击）'), findsOneWidget);
        expect(
          find.descendant(of: action, matching: find.text('打开链接')),
          findsOneWidget,
        );

        final scroll = currentEditor().scrollController!;
        expect(scroll.position.maxScrollExtent, greaterThan(100));
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        expect(action, findsNothing);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await mouse.moveTo(link + const Offset(1, 0));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);

        await mouse.moveTo(below);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(action, findsNothing);

        await mouse.moveTo(link);
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(action, findsNothing);

        await mouse.moveTo(link + const Offset(1, 0));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);
        final actionPoint = tester.getCenter(action);
        await mouse.moveTo(actionPoint);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(action, findsOneWidget);
        await mouse.down(actionPoint);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(action, findsNothing);
        expect(currentEditor().inputWindow.text, contains('destination 中😀'));
        expect(currentEditor().focusNode?.hasPrimaryFocus, isTrue);
      } finally {
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
