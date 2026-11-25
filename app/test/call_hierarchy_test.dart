import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart' show HierarchyDirection, HierarchyKind;
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/call_hierarchy.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/native_drag_drop.dart';

void main() {
  setUp(mockNativeDragDrop);

  testWidgets('call hierarchy selects the first child and navigates its rows',
      (tester) async {
    final opened = <int>[];
    final toggled = <int>[];
    var changedDirection = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CallHierarchyPeek(
          direction: HierarchyDirection.incoming,
          loading: false,
          message: null,
          rows: const [
            CallHierarchyRow(
                id: 'root',
                name: 'root',
                detail: 'lib.rs',
                depth: 0,
                expanded: true),
            CallHierarchyRow(
                id: 'caller',
                name: 'caller',
                detail: 'calls.rs',
                depth: 1,
                parentIndex: 0),
          ],
          loadPreview: (index) async => [
            (
              number: 1,
              startCharacter: 0,
              text:
                  index == 0 ? 'pub fn root()' : 'let _ = "🦊"; crate::root();',
              highlightStart: index == 0 ? 7 : 21,
              highlightEnd: index == 0 ? 11 : 25,
              targetCharacter: null,
            ),
          ],
          onDirection: () => changedDirection = true,
          onOpen: opened.add,
          onToggle: toggled.add,
          onClose: () {},
          onCommandKey: (_) => KeyEventResult.ignored,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    bool selected(int row) => tester
        .widget<Semantics>(find.byKey(ValueKey('call-hierarchy-row-$row')))
        .properties
        .selected!;
    expect(selected(1), isTrue);
    expect(
        find.byKey(const ValueKey('call-hierarchy-preview')), findsOneWidget);
    expect(find.textContaining('crate::root()', findRichText: true),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(selected(0), isTrue);
    expect(find.textContaining('pub fn root()', findRichText: true),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(toggled, [0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(selected(1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, [1]);
    await tester.tap(find.byKey(const ValueKey('call-hierarchy-direction')));
    expect(changedDirection, isTrue);
  });

  testWidgets('hierarchy pages and row insertions preserve visible tree focus',
      (tester) async {
    const root = CallHierarchyRow(
      id: 'root',
      name: 'root',
      detail: '',
      depth: 0,
      expanded: true,
    );
    const first = CallHierarchyRow(
      id: 'first',
      name: 'first',
      detail: '',
      depth: 1,
      parentIndex: 0,
    );
    const next = CallHierarchyRow(
      id: 'next',
      name: 'next',
      detail: '',
      depth: 1,
      parentIndex: 0,
    );
    const inserted = CallHierarchyRow(
      id: 'inserted',
      name: 'inserted',
      detail: '',
      depth: 1,
      parentIndex: 0,
    );
    const more = CallHierarchyRow(
      id: 'more',
      name: '显示更多',
      detail: '剩余 1 项',
      depth: 1,
      parentIndex: 0,
      more: true,
    );
    List<CallHierarchyRow> rows = const [root, first, more];
    Object? reportedSelection;
    Object? preferred;
    StateSetter? update;
    final opens = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return CallHierarchyPeek(
            rows: rows,
            preferredSelection: preferred,
            direction: HierarchyDirection.incoming,
            loading: false,
            message: null,
            onSelection: (index) =>
                reportedSelection = index == null ? null : rows[index].id,
            loadPreview: (index) async => [
              (
                number: 1,
                startCharacter: 0,
                text: 'preview for ${rows[index].name}',
                highlightStart: 0,
                highlightEnd: 0,
                targetCharacter: null,
              ),
            ],
            onDirection: null,
            onOpen: (index) {
              opens.add(index);
              if (rows[index].more) {
                setState(() {
                  rows = const [root, first, next];
                  preferred = next.id;
                });
              }
            },
            onToggle: (_) {},
            onClose: () {},
            onCommandKey: (_) => KeyEventResult.ignored,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    bool selected(int row) => tester
        .widget<Semantics>(find.byKey(ValueKey('call-hierarchy-row-$row')))
        .properties
        .selected!;

    expect(selected(1), isTrue);
    expect(reportedSelection, first.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(selected(2), isTrue);
    expect(reportedSelection, more.id);
    expect(find.textContaining('preview for first', findRichText: true),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opens, [2]);
    expect(find.textContaining('显示更多', findRichText: true), findsNothing);
    expect(selected(2), isTrue);
    expect(find.textContaining('preview for next', findRichText: true),
        findsOneWidget);

    update!(() {
      preferred = null;
      rows = const [root, inserted, first, next];
    });
    await tester.pumpAndSettle();
    expect(selected(3), isTrue);
    expect(reportedSelection, next.id);
    expect(find.textContaining('preview for next', findRichText: true),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selected(0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected(1), isTrue);

    update!(() => rows = const [root]);
    await tester.pumpAndSettle();
    expect(selected(0), isTrue);
    expect(reportedSelection, root.id);
    update!(() => rows = const []);
    await tester.pumpAndSettle();
    expect(reportedSelection, isNull);
  });

  testWidgets('hierarchy restores scroll and selection for a retained view',
      (tester) async {
    List<CallHierarchyRow> rowsFor(String direction, int count) => [
          for (var index = 0; index < count; index++)
            CallHierarchyRow(
              id: '$direction-$index',
              name: '$direction $index',
              detail: '',
              depth: index == 0 ? 0 : 1,
              parentIndex: index == 0 ? null : 0,
            ),
        ];

    final incoming = rowsFor('incoming', 40);
    final outgoing = rowsFor('outgoing', 38);
    final incomingView = Object();
    var outgoingView = Object();
    var showIncoming = true;
    var freshOutgoing = false;
    Object? selected;
    StateSetter? update;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          final rows = showIncoming ? incoming : outgoing;
          return CallHierarchyPeek(
            rows: rows,
            preferredSelection: showIncoming
                ? 'incoming-9'
                : freshOutgoing
                    ? null
                    : 'outgoing-3',
            viewIdentity: showIncoming ? incomingView : outgoingView,
            direction: showIncoming
                ? HierarchyDirection.incoming
                : HierarchyDirection.outgoing,
            loading: false,
            message: null,
            onSelection: (index) =>
                selected = index == null ? null : rows[index].id,
            loadPreview: (index) async => [
              (
                number: 1,
                startCharacter: 0,
                text: 'preview for ${rows[index].name}',
                highlightStart: 0,
                highlightEnd: 0,
                targetCharacter: null,
              ),
            ],
            onDirection: () => setState(() => showIncoming = !showIncoming),
            onOpen: (_) {},
            onToggle: (_) {},
            onClose: () {},
            onCommandKey: (_) => KeyEventResult.ignored,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    final results = find.byKey(const ValueKey('call-hierarchy-results'));
    final scroll = tester.widget<ListView>(results).controller!;
    final direction = find.byKey(const ValueKey('call-hierarchy-direction'));

    scroll.jumpTo(82);
    await tester.pumpAndSettle();
    expect(selected, 'incoming-9');
    await tester.tap(direction);
    await tester.pumpAndSettle();
    expect(selected, 'outgoing-3');
    expect(scroll.offset, 0);

    scroll.jumpTo(173);
    await tester.pumpAndSettle();
    await tester.tap(direction);
    await tester.pumpAndSettle();
    expect(scroll.offset, 82);
    expect(selected, 'incoming-9');
    expect(find.textContaining('preview for incoming 9', findRichText: true),
        findsOneWidget);

    await tester.tap(direction);
    await tester.pumpAndSettle();
    expect(scroll.offset, 173);
    expect(selected, 'outgoing-3');
    await tester.tap(direction);
    await tester.pumpAndSettle();

    update!(() {
      outgoingView = Object();
      freshOutgoing = true;
      showIncoming = false;
    });
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(selected, 'outgoing-1');
    expect(find.textContaining('preview for outgoing 1', findRichText: true),
        findsOneWidget);
  });

  for (final (kind, stablePeek) in [
    for (final kind in HierarchyKind.values)
      for (final stablePeek in [false, true]) (kind, stablePeek),
  ]) {
    testWidgets(
        'unavailable ${kind.name} hierarchy restores source focus (stable=$stablePeek)',
        (tester) async {
      final isType = kind == HierarchyKind.type;
      final hierarchyName = isType ? '类型层级' : '调用层级';
      final keyPrefix = isType ? 'type-hierarchy' : 'call-hierarchy';
      final temp = Directory.systemTemp.createTempSync('alula-call-hierarchy');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final base = temp.path.replaceAll(r'\', '/');
      final workspace = Directory('$base/workspace')..createSync();
      const source = '// 🦊 text\ncaller\n';
      File('${workspace.path}/plain.txt').writeAsStringSync(source);
      File('$base/settings.json').writeAsStringSync(
        '{"editor.stablePeek":$stablePeek}',
      );
      if (isType) {
        File('$base/keybindings.json').writeAsStringSync(
          '[{"key":"ctrl+shift+f9","command":"editor.showTypeHierarchy"}]',
        );
      }
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('plain.txt').first);
      await tester.pump(const Duration(milliseconds: 300));
      final editor = find.descendant(
        of: find.byType(RustTextInputField),
        matching: find.byType(TextField),
      );
      await tester.tap(editor);
      await tester.pump();
      final field = tester.widget<TextField>(editor);
      final caret = TextSelection.collapsed(offset: source.indexOf('caller'));
      field.controller!.selection = caret;
      await tester.pump();

      final modifier =
          isType ? LogicalKeyboardKey.controlLeft : LogicalKeyboardKey.altLeft;
      final key = isType ? LogicalKeyboardKey.f9 : LogicalKeyboardKey.keyH;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      final hierarchy = find.byType(CallHierarchyPeek);
      expect(hierarchy, findsOneWidget);
      expect(find.text('没有可用的$hierarchyName提供程序'), findsOneWidget);
      expect(
        tester.widget<CallHierarchyPeek>(hierarchy).direction,
        isType ? HierarchyDirection.subtypes : HierarchyDirection.incoming,
      );
      expect(field.controller!.selection, caret);
      expect(field.controller!.text, source);
      expect(field.focusNode!.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      if (stablePeek) {
        expect(hierarchy, findsOneWidget);
        await tester.tap(find.byKey(ValueKey('$keyPrefix-close')));
        await tester.pumpAndSettle();
      }
      expect(hierarchy, findsNothing);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller!.selection, caret);
    });
  }
}
