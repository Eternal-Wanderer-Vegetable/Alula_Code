import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/editor_tab_action_location.dart';
import 'package:alula_app/workbench/editor_tab_sizing.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('action location session values default to the right', () {
    expect(EditorTabActionLocation.fromSessionValue(null),
        EditorTabActionLocation.right);
    expect(EditorTabActionLocation.fromSessionValue('unknown'),
        EditorTabActionLocation.right);
    expect(EditorTabActionLocation.fromSessionValue('left'),
        EditorTabActionLocation.left);
    expect(EditorTabActionLocation.fromSessionValue('right'),
        EditorTabActionLocation.right);
  });

  test('left fixed actions retain Code-OSS minimum space', () {
    expect(
      EditorTabWidthPolicy.layout(
        contentWidths: const [200, 200, 200, 200],
        availableWidth: 160,
        sizing: EditorTabSizing.fixed,
        fixedMinWidthOverride: 80,
      ),
      const [80, 80, 80, 80],
    );
    expect(
      EditorTabWidthPolicy.layout(
        contentWidths: const [200, 200, 200, 200],
        availableWidth: 160,
        sizing: EditorTabSizing.fixed,
      ),
      const [50, 50, 50, 50],
    );
  });

  testWidgets(
      'close action moves left/right, persists, and preserves editor state',
      (tester) async {
    tester.view.physicalSize = const Size(850, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    final temp = Directory.systemTemp.createTempSync('alula_tab_action');
    addTearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final root = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$root/layout.json');
    final sessionStore = SessionStore(path: '$root/session.json');
    final names = <String>[];
    final paths = <String>[];
    for (var i = 0; i < 6; i++) {
      final name = 'tab_action_location_fixture_document_$i.rs';
      final path = '$root/$name';
      File(path).writeAsStringSync('fn fixture_$i() {}\n');
      names.add(name);
      paths.add(path.replaceAll(r'\', '/'));
    }
    sessionStore.save({
      'v': 1,
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'active': 12,
          'docs': [
            for (var i = 0; i < paths.length; i++)
              {'id': 10 + i, 'path': paths[i]},
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

    Future<void> openEditorTabsMenu() async {
      await tester.tap(find.text('查看(V)'));
      await settle('View menu');
      await tester.tap(find.text('外观(A)'));
      await settle('Appearance menu');
      await tester.tap(find.text('编辑器标签'));
      await settle('Editor tabs submenu');
    }

    Future<void> chooseLocation(String label, {required String current}) async {
      await openEditorTabsMenu();
      await tester.tap(find.text('关闭操作位置'));
      await settle('Close action position submenu');
      for (final location in ['左侧', '右侧']) {
        expect(
          tester
              .getSemantics(find.text(location))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          location == current ? CheckedState.isTrue : CheckedState.isFalse,
          reason: '$location exposes the checked close action position',
        );
      }
      await tester.tap(find.text(label));
      await settle('select close action $label');
    }

    Future<void> chooseSizing(String label) async {
      await openEditorTabsMenu();
      await tester.tap(find.text('标签尺寸'));
      await settle('Tab sizing submenu');
      await tester.tap(find.text(label));
      await settle('select tab sizing $label');
    }

    Future<void> toggleWrap() async {
      await openEditorTabsMenu();
      await tester.tap(find.text('标签自动换行'));
      await settle('toggle tab wrapping');
    }

    double closeX(int id) =>
        tester.getCenter(find.byKey(ValueKey('close-tab-editor-$id'))).dx;

    double labelX(int id, String name) => tester
        .getCenter(find.descendant(
          of: find.byKey(ValueKey('tab-$id')),
          matching: find.text(name),
        ))
        .dx;

    await mountApp();
    final editor = find.byType(RustTextInputField).first;
    final editorState = tester.state<RustTextInputFieldState>(editor);
    final editorWidget = tester.widget<RustTextInputField>(editor);
    final inputWindow = editorWidget.inputWindow;
    final focusNode = editorWidget.focusNode!;
    final scrollController = editorWidget.scrollController!;
    final editable = find.descendant(
      of: editor,
      matching: find.byType(EditableText),
    );
    final textController = tester.widget<EditableText>(editable).controller;
    const selection = TextSelection.collapsed(offset: 0);
    textController.selection = selection;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    expect(closeX(10), greaterThan(labelX(10, names.first)),
        reason: 'right is the default action location');
    await chooseLocation('左侧', current: '右侧');
    expect(closeX(10), lessThan(labelX(10, names.first)));
    expect(tester.state<RustTextInputFieldState>(editor), same(editorState));
    expect(tester.widget<RustTextInputField>(editor).inputWindow,
        same(inputWindow));
    expect(
        tester.widget<EditableText>(editable).controller, same(textController));
    expect(textController.selection, selection);
    expect(
        tester.widget<RustTextInputField>(editor).focusNode, same(focusNode));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.widget<RustTextInputField>(editor).scrollController,
        same(scrollController));
    expect(scrollController.offset, 0);

    await tester.pump(const Duration(milliseconds: 700));
    expect(sessionStore.tryLoad()?['editorTabActionLocation'], 'left');
    expect(File('$root/layout.json').readAsStringSync(),
        isNot(contains('editorTabActionLocation')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(closeX(10), lessThan(labelX(10, names.first)),
        reason: 'session restore reapplies the left action location');

    await chooseSizing('固定宽度');
    expect(
      tester.getSize(find.byKey(const ValueKey('tab-10'))).width,
      greaterThanOrEqualTo(80),
      reason: 'left-side close actions keep the pinned 80px fixed minimum',
    );
    await toggleWrap();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('editor-tab-strip-editor')))
          .height,
      greaterThan(36),
      reason: 'left action position remains usable while tabs wrap',
    );
    await chooseLocation('右侧', current: '左侧');
    expect(closeX(10), greaterThan(labelX(10, names.first)));
    await chooseSizing('收缩');
    expect(closeX(10), greaterThan(labelX(10, names.first)));
    await toggleWrap();
    await tester.pump(const Duration(milliseconds: 700));
    expect(sessionStore.tryLoad()?['editorTabActionLocation'], 'right');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(closeX(10), greaterThan(labelX(10, names.first)),
        reason: 'the right action location restores with the session');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    semantics.dispose();
  });
}
