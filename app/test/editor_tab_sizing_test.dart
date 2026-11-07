import 'dart:io';
import 'dart:ui' show CheckedState, PointerDeviceKind;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/editor_tab_sizing.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorTabSizing', () {
    test('session values default to fit and accept the supported modes', () {
      expect(EditorTabSizing.fromSessionValue(null), EditorTabSizing.fit);
      expect(EditorTabSizing.fromSessionValue('unknown'), EditorTabSizing.fit);
      expect(EditorTabSizing.fromSessionValue('fit'), EditorTabSizing.fit);
      expect(
          EditorTabSizing.fromSessionValue('shrink'), EditorTabSizing.shrink);
      expect(EditorTabSizing.fromSessionValue('fixed'), EditorTabSizing.fixed);
    });

    test('fit keeps content width even when the strip is narrower', () {
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [300, 240],
          availableWidth: 100,
          sizing: EditorTabSizing.fit,
        ),
        const [300, 240],
      );
    });

    test('shrink distributes available width but keeps its floor', () {
      final widths = EditorTabWidthPolicy.layout(
        contentWidths: const [340, 260, 180],
        availableWidth: 400,
        sizing: EditorTabSizing.shrink,
      );
      expect(widths.reduce((a, b) => a + b), closeTo(400, 0.001));
      expect(widths.every((width) => width >= 80), isTrue);
      for (final width in widths) {
        expect(width, closeTo(400 / 3, 0.001),
            reason: 'shrink gives tabs an even width up to their content size');
      }

      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [340, 260, 180],
          availableWidth: 200,
          sizing: EditorTabSizing.shrink,
        ),
        const [80, 80, 80],
        reason: 'once all tabs hit 80px they overflow as a scrollable row',
      );
    });

    test('fixed tabs share a width between the configured defaults', () {
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [100, 200, 300],
          availableWidth: 300,
          sizing: EditorTabSizing.fixed,
        ),
        const [100, 100, 100],
      );
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [100, 200],
          availableWidth: 600,
          sizing: EditorTabSizing.fixed,
        ),
        const [160, 160],
      );
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [100, 200],
          availableWidth: 40,
          sizing: EditorTabSizing.fixed,
        ),
        const [50, 50],
      );
    });

    test('wrapping uses bounded widths without changing tab identity', () {
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [300, 80],
          availableWidth: 150,
          sizing: EditorTabSizing.shrink,
          wrapping: true,
        ),
        const [150, 80],
      );
      expect(
        EditorTabWidthPolicy.layout(
          contentWidths: const [300, 80],
          availableWidth: 220,
          sizing: EditorTabSizing.fixed,
          wrapping: true,
        ),
        const [160, 160],
      );
    });
  });

  testWidgets('tab sizing changes geometry, persists, and holds close widths',
      (tester) async {
    tester.view.physicalSize = const Size(650, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    final temp = Directory.systemTemp.createTempSync('alula_tab_sizing');
    addTearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final root = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$root/layout.json');
    final sessionStore = SessionStore(path: '$root/session.json');
    final filePaths = <String>[];
    for (var i = 0; i < 4; i++) {
      final file = File(
        '$root/very_long_editor_tab_sizing_fixture_document_number_$i.rs',
      )..writeAsStringSync('fn fixture_$i() {}\n');
      filePaths.add(file.path.replaceAll(r'\', '/'));
    }
    sessionStore.save({
      'v': 1,
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'active': 13,
          'docs': [
            for (var i = 0; i < filePaths.length; i++)
              {'id': 10 + i, 'path': filePaths[i]},
          ],
        }
      ],
    });

    Future<void> settle(String label) async {
      await tester.pumpAndSettle().timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw StateError('pumpAndSettle timed out: $label'),
          );
    }

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openSizingMenu() async {
      await tester.tap(find.text('查看(V)'));
      await settle('View menu');
      await tester.tap(find.text('外观(A)'));
      await settle('Appearance menu');
      await tester.tap(find.text('编辑器标签'));
      await settle('Editor tabs submenu');
      await tester.tap(find.text('标签尺寸'));
      await settle('Tab sizing submenu');
    }

    Future<void> openTabModeMenu() async {
      await tester.tap(find.text('查看(V)'));
      await settle('View menu');
      await tester.tap(find.text('外观(A)'));
      await settle('Appearance menu');
      await tester.tap(find.text('编辑器标签'));
      await settle('Editor tabs submenu');
    }

    Future<void> chooseSizing(String label, {required String current}) async {
      await openSizingMenu();
      for (final mode in ['按内容适配', '收缩', '固定宽度']) {
        final item = find
            .ancestor(
                of: find.text(mode), matching: find.byType(MenuItemButton))
            .first;
        expect(
          tester
              .getSemantics(find.text(mode))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          mode == current ? CheckedState.isTrue : CheckedState.isFalse,
          reason: '$mode exposes the checked tab sizing state',
        );
        expect(
          tester.widget<MenuItemButton>(item).leadingIcon,
          mode == current ? isA<Icon>() : isA<SizedBox>(),
        );
      }
      await tester.tap(find.text(label));
      await settle('select tab sizing $label');
    }

    double tabWidth(int id) =>
        tester.getSize(find.byKey(ValueKey('tab-$id'))).width;

    await mountApp();
    final activeEditor = find.byType(RustTextInputField).first;
    final editorState = tester.state<RustTextInputFieldState>(activeEditor);
    final editorWidget = tester.widget<RustTextInputField>(activeEditor);
    final inputWindow = editorWidget.inputWindow;
    final focusNode = editorWidget.focusNode!;
    final scrollController = editorWidget.scrollController!;
    final editable = find.descendant(
      of: activeEditor,
      matching: find.byType(EditableText),
    );
    final textController = tester.widget<EditableText>(editable).controller;
    const selection = TextSelection.collapsed(offset: 0);
    textController.selection = selection;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    final fitWidth = tabWidth(10);
    expect(fitWidth, greaterThan(160));
    await chooseSizing('收缩', current: '按内容适配');
    final shrinkWidth = tabWidth(10);
    expect(shrinkWidth, lessThan(fitWidth));
    expect(shrinkWidth, greaterThanOrEqualTo(80));
    await chooseSizing('固定宽度', current: '收缩');
    final fixedWidths = [for (var id = 10; id < 14; id++) tabWidth(id)];
    expect(fixedWidths.every((width) => width >= 50 && width <= 160), isTrue);
    for (final width in fixedWidths.skip(1)) {
      expect(width, closeTo(fixedWidths.first, 0.001));
    }

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pump();
    await settle('widen fixed tabs');
    expect(tabWidth(10), greaterThanOrEqualTo(fixedWidths.first));
    tester.view.physicalSize = const Size(650, 900);
    await tester.pump();
    await settle('narrow fixed tabs');

    expect(
        tester.state<RustTextInputFieldState>(activeEditor), same(editorState));
    expect(tester.widget<RustTextInputField>(activeEditor).inputWindow,
        same(inputWindow));
    expect(
        tester.widget<EditableText>(editable).controller, same(textController));
    expect(textController.selection, selection);
    expect(tester.widget<RustTextInputField>(activeEditor).focusNode,
        same(focusNode));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.widget<RustTextInputField>(activeEditor).scrollController,
        same(scrollController));
    expect(scrollController.offset, 0);

    final close10 = find.byKey(const ValueKey('close-tab-editor-10'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(close10));
    await tester.pump();
    final heldWidth = tabWidth(11);
    await tester.tap(close10);
    await tester.pump();
    expect(find.byKey(const ValueKey('tab-10')), findsNothing);
    expect(tabWidth(11), closeTo(heldWidth, 0.001),
        reason:
            'remaining fixed tabs keep their width while pointer stays in strip');
    await mouse.moveTo(const Offset(0, 0));
    await tester.pump();
    expect(tabWidth(11), greaterThan(heldWidth),
        reason: 'widths recalculate after the pointer leaves the strip');
    await mouse.removePointer();

    await tester.pump(const Duration(milliseconds: 700));
    expect(sessionStore.tryLoad()?['editorTabSizing'], 'fixed');
    expect(
      File('$root/layout.json').readAsStringSync(),
      isNot(contains('editorTabSizing')),
      reason: 'tab sizing remains in session preferences, outside layout JSON',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(tabWidth(11), inInclusiveRange(50, 160));
    await openSizingMenu();
    expect(
      tester
          .getSemantics(find.text('固定宽度'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
      reason: 'session restore reapplies the selected sizing mode',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle('close tab sizing submenu');
    await openTabModeMenu();
    await tester.tap(find.text('标签自动换行'));
    await settle('wrap fixed tabs');
    expect(
      tester
          .getSize(find.byKey(const ValueKey('editor-tab-strip-editor')))
          .height,
      greaterThan(36),
      reason: 'fixed sizing still wraps in a constrained group',
    );
    await openTabModeMenu();
    await tester.tap(find.text('不显示标签'));
    await settle('hide sized tabs');
    expect(find.byKey(const ValueKey('tab-11')), findsNothing);
    await openTabModeMenu();
    await tester.tap(find.text('多标签'));
    await settle('restore multiple sized tabs');
    expect(find.byKey(const ValueKey('tab-11')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    semantics.dispose();
  });
}
