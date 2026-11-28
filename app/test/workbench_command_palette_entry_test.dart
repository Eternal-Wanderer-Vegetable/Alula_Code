import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/command_history_store.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('F1 opens the main command palette through its canonical action',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-palette-');
    addTearDown(() => temp.deleteSync(recursive: true));

    final history =
        CommandHistoryStore(path: '${temp.path}/command-history.json');
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: SessionStore(path: '${temp.path}/session.json'),
        keybindingsStore:
            KeybindingsStore(path: '${temp.path}/keybindings.json'),
        commandHistoryStore: history,
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pumpAndSettle();

    const canonical = 'workbench.action.showCommands';
    final palette = find.byKey(const ValueKey('quick-input'));
    final input = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField).first,
    );
    input.focusNode!.requestFocus();
    await tester.pump();
    expect(input.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(palette, findsOneWidget);
    final filter =
        find.descendant(of: palette, matching: find.byType(TextField));
    await tester.enterText(filter, '命令面板');
    await tester.pumpAndSettle();
    expect(find.text('查看: 命令面板'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(palette, findsNothing);
    expect(input.focusNode!.hasFocus, isTrue);

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
    expect(palette, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(input.focusNode!.hasFocus, isTrue);

    final action = commands.byId(canonical);
    expect(action, isNotNull);
    for (final id in ['view.commandPalette', 'view.quickInput']) {
      expect(commands.byId(id), same(action));
      expect(await commands.execute(id), CommandExecutionStatus.executed);
      await tester.pumpAndSettle();
      expect(palette, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input.focusNode!.hasFocus, isTrue);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await tester.enterText(filter, '诊断面板');
    await tester.pumpAndSettle();
    expect(find.text('查看: 诊断面板'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(palette, findsNothing);
    expect(history.load().commandIds.first, 'view.panelDiagnostics');
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }));
}
