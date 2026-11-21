import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/editor_tab_mode.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor tab mode accepts the three values and defaults invalid data',
      () {
    expect(EditorTabMode.fromSessionValue('multiple'), EditorTabMode.multiple);
    expect(EditorTabMode.fromSessionValue('single'), EditorTabMode.single);
    expect(EditorTabMode.fromSessionValue('none'), EditorTabMode.none);
    expect(EditorTabMode.fromSessionValue(null), EditorTabMode.multiple);
    expect(EditorTabMode.fromSessionValue('unknown'), EditorTabMode.multiple);
  });

  testWidgets(
      'tab visibility modes update every group and restore from session',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final temp = Directory.systemTemp.createTempSync('alula_tab_modes');
    addTearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final root = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$root/layout.json');
    final sessionStore = SessionStore(path: '$root/session.json');

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(String label) async {
      await tester.pumpAndSettle().timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw StateError('pumpAndSettle timed out: $label'),
          );
    }

    Future<void> openCommand(String query, String commandKey) async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await settle('command center open');
      final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, query);
      await settle('command query');
      final command = find.byKey(ValueKey(commandKey));
      expect(command, findsOneWidget);
      await tester.tap(command);
      await settle('command execution');
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> openTabModeMenu() async {
      await tester.tap(find.text('查看(V)'));
      await settle('View menu');
      await tester.tap(find.text('外观(A)'));
      await settle('Appearance menu');
      await tester.tap(find.text('编辑器标签'));
      await settle('Editor tabs submenu');
    }

    Future<void> chooseTabMode(String label,
        {required String currentMode}) async {
      await openTabModeMenu();
      for (final mode in ['多标签', '单标签', '不显示标签']) {
        final item = find
            .ancestor(
                of: find.text(mode), matching: find.byType(MenuItemButton))
            .first;
        final selected = mode == currentMode;
        expect(
          tester.widget<MenuItemButton>(item).leadingIcon,
          selected ? isA<Icon>() : isA<SizedBox>(),
          reason: '$mode should report the current mode $currentMode',
        );
        expect(
          tester
              .getSemantics(find.text(mode))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          selected ? CheckedState.isTrue : CheckedState.isFalse,
          reason: '$mode exposes its checked state to assistive technology',
        );
      }
      await tester.tap(find.text(label));
      await settle('select $label');
    }

    Finder tab(int id) => find.byKey(ValueKey('tab-$id'));
    Finder tabIcon(String region, int id) =>
        find.byKey(ValueKey('editor-tab-file-icon-$region-$id'));

    await mountApp();
    expect(tab(1), findsOneWidget,
        reason: 'legacy/new sessions default to multiple');
    expect(tabIcon('editor', 1), findsOneWidget);
    await chooseTabMode('多标签', currentMode: '多标签');
    await chooseTabMode('单标签', currentMode: '多标签');
    expect(tab(1), findsOneWidget,
        reason: 'single mode shows the only active document');
    await tester.tap(find.byKey(const ValueKey('close-tab-editor-1')));
    await tester.pump();
    expect(tab(1), findsNothing,
        reason: 'single mode remains empty after its last document closes');
    expect(find.byTooltip('拆分编辑器'), findsOneWidget,
        reason: 'empty editor group actions remain available');

    await openCommand('新建文本文件', 'qi-文件: 新建文本文件');
    expect(tab(2), findsOneWidget);
    expect(tabIcon('editor', 2), findsOneWidget);
    await openCommand('新建文本文件', 'qi-文件: 新建文本文件');
    expect(tab(2), findsNothing,
        reason: 'single mode hides inactive documents');
    expect(tabIcon('editor', 2), findsNothing);
    expect(tab(3), findsOneWidget);
    expect(tabIcon('editor', 3), findsOneWidget);

    await chooseTabMode('多标签', currentMode: '单标签');
    expect(tab(2), findsOneWidget);
    expect(tab(3), findsOneWidget);
    expect(tabIcon('editor', 2), findsOneWidget);
    expect(tabIcon('editor', 3), findsOneWidget);

    await tester.tap(find.byTooltip('拆分编辑器').first);
    await settle('split editor');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab(3), findsNWidgets(2), reason: 'both groups show the active tab');
    expect(tabIcon('editor', 3), findsOneWidget);
    expect(tabIcon('editor-2', 3), findsOneWidget);

    final editorFinder = find.byType(RustTextInputField).first;
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    final editorWidget = tester.widget<RustTextInputField>(editorFinder);
    final inputWindow = editorWidget.inputWindow;
    final focusNode = editorWidget.focusNode!;
    final scrollController = editorWidget.scrollController!;
    final editableText = find.descendant(
      of: editorFinder,
      matching: find.byType(EditableText),
    );
    final textController = tester.widget<EditableText>(editableText).controller;
    const selection = TextSelection.collapsed(offset: 0);
    textController.selection = selection;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await chooseTabMode('单标签', currentMode: '多标签');
    expect(tab(2), findsNothing);
    expect(tab(3), findsNWidgets(2),
        reason: 'single mode keeps one active tab in each editor group');
    expect(
        tester.state<RustTextInputFieldState>(editorFinder), same(editorState));
    expect(tester.widget<RustTextInputField>(editorFinder).inputWindow,
        same(inputWindow));
    expect(tester.widget<EditableText>(editableText).controller,
        same(textController));
    expect(textController.selection, selection);
    expect(tester.widget<RustTextInputField>(editorFinder).focusNode,
        same(focusNode));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.widget<RustTextInputField>(editorFinder).scrollController,
        same(scrollController));
    expect(scrollController.offset, 0);

    await chooseTabMode('不显示标签', currentMode: '单标签');
    expect(find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('tab-');
    }), findsNothing);
    expect(find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('editor-tab-file-icon-');
    }), findsNothing);
    expect(find.byTooltip('拆分编辑器'), findsNWidgets(2),
        reason: 'editor group actions remain available without tabs');
    expect(
        tester.state<RustTextInputFieldState>(editorFinder), same(editorState));
    expect(textController.selection, selection);
    expect(focusNode.hasFocus, isTrue);
    expect(scrollController.offset, 0);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(sessionStore.tryLoad()?['editorTabMode'], 'none');
    expect(
      File('$root/layout.json').readAsStringSync(),
      isNot(contains('editorTabMode')),
      reason: 'tab display preference is separate from editor layout JSON',
    );

    await mountApp();
    expect(find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('tab-');
    }), findsNothing);
    expect(find.byTooltip('拆分编辑器'), findsNWidgets(2));

    await chooseTabMode('多标签', currentMode: '不显示标签');
    expect(tab(2), findsOneWidget);
    expect(tab(3), findsNWidgets(2));
    expect(tabIcon('editor', 2), findsOneWidget);
    expect(tabIcon('editor', 3), findsOneWidget);
    expect(tabIcon('editor-2', 3), findsOneWidget);

    final closeButtons = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('close-tab-');
    });
    while (closeButtons.evaluate().isNotEmpty) {
      final closeButton = closeButtons.first;
      await tester.ensureVisible(closeButton);
      await settle('reveal next tab close action');
      await tester.tap(closeButton);
      await tester.pump();
    }
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('tab-');
      }),
      findsNothing,
      reason: 'multiple mode supports an editor group with no open documents',
    );
    await chooseTabMode('不显示标签', currentMode: '多标签');
    expect(find.byTooltip('拆分编辑器'), findsOneWidget,
        reason: 'empty editor groups keep their actions in no-tabs mode');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    semantics.dispose();
  });
}
