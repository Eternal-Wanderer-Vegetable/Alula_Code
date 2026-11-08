import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'editor tabs wrap responsively in every group and preserve session state',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      void disposeSemantics() {
        if (semanticsDisposed) return;
        semanticsDisposed = true;
        semantics.dispose();
      }

      addTearDown(disposeSemantics);
      final temp = Directory.systemTemp.createTempSync('alula_tab_wrap');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final root = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$root/layout.json');
      final sessionStore = SessionStore(path: '$root/session.json');

      Future<void> settle(String reason) async {
        await tester.pumpAndSettle().timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw StateError('pumpAndSettle timed out: $reason'),
            );
      }

      Future<void> mountApp() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> openCommand(String query) async {
        await tester.tap(find.byKey(const ValueKey('command-center-control')));
        await settle('command center open');
        final input = find.descendant(
          of: find.byKey(const ValueKey('quick-input')),
          matching: find.byType(TextField),
        );
        await tester.enterText(input, query);
        await settle('command query');
        final command = find.byKey(const ValueKey('qi-文件: 新建文本文件'));
        expect(command, findsOneWidget);
        await tester.tap(command);
        await settle('create text file');
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<Finder> openWrapMenu() async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        return find.text('标签自动换行');
      }

      Future<void> selectTabMode(String label) async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        await tester.tap(find.text(label));
        await settle('select $label');
      }

      Future<void> setWrap(bool enabled) async {
        final item = await openWrapMenu();
        expect(item, findsOneWidget);
        final selected = tester
            .getSemantics(item)
            .getSemanticsData()
            .flagsCollection
            .isChecked;
        expect(
          selected,
          enabled ? CheckedState.isFalse : CheckedState.isTrue,
          reason: 'the menu reports the previous wrap state accessibly',
        );
        await tester.tap(item);
        await settle('toggle tab wrapping');
      }

      Finder tab(int id) => find.byKey(ValueKey('tab-$id'));

      Finder inGroup(String region, Finder child) => find.descendant(
            of: find.byKey(ValueKey('editor-tab-strip-$region')),
            matching: child,
          );

      Finder visibleTabs(String region) => inGroup(
            region,
            find.byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> && key.value.startsWith('tab-');
            }),
          );

      double tabY(String region, int id) =>
          tester.getTopLeft(inGroup(region, tab(id))).dy;

      Set<double> tabRows(String region, Iterable<int> ids) => {
            for (final id in ids) tabY(region, id),
          };

      await mountApp();
      expect(tab(1), findsOneWidget,
          reason: 'legacy sessions default to non-wrapping tabs');

      // Fill the first group while the default horizontal scrolling mode is on.
      for (var i = 0; i < 8; i++) {
        await openCommand('新建文本文件');
      }
      expect(tabRows('editor', List.generate(9, (i) => i + 1)), hasLength(1));

      // The preference is global. Split, focus the new group, and fill it too.
      await tester.tap(find.byTooltip('拆分编辑器').first);
      await settle('split editor group');
      final secondGroup =
          find.byKey(const ValueKey('editor-tab-strip-editor-2'));
      expect(secondGroup, findsOneWidget);
      await tester.tap(inGroup('editor-2', tab(9)));
      await settle('focus second editor group');
      for (var i = 0; i < 7; i++) {
        await openCommand('新建文本文件');
      }
      expect(tab(16), findsOneWidget);

      // Keep an editor's state, focus, selection, and scroll controller stable
      // while only its tab header changes height.
      final editorFinder = find.byType(RustTextInputField).first;
      final editorState = tester.state<RustTextInputFieldState>(editorFinder);
      final editorWidget = tester.widget<RustTextInputField>(editorFinder);
      final inputWindow = editorWidget.inputWindow;
      final focusNode = editorWidget.focusNode!;
      final scrollController = editorWidget.scrollController!;
      final editable = find.descendant(
        of: editorFinder,
        matching: find.byType(EditableText),
      );
      final textController = tester.widget<EditableText>(editable).controller;
      const selection = TextSelection.collapsed(offset: 0);
      textController.selection = selection;
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await setWrap(true);
      final firstRows = tabRows('editor', List.generate(8, (i) => i + 1));
      final secondRows = tabRows('editor-2', List.generate(7, (i) => i + 10));
      expect(visibleTabs('editor'), findsNWidgets(9));
      expect(visibleTabs('editor-2'), findsNWidgets(8));
      expect(firstRows.length, greaterThan(1),
          reason: 'a narrow first editor group lays tabs out on multiple rows');
      expect(secondRows.length, greaterThan(1),
          reason: 'the shared setting applies to the second editor group');

      final draggedTab = inGroup('editor-2', tab(15));
      final firstRowTarget = inGroup('editor-2', tab(10));
      expect(tester.getTopLeft(draggedTab).dy,
          greaterThan(tester.getTopLeft(firstRowTarget).dy));
      await tester.drag(
        draggedTab,
        tester.getCenter(firstRowTarget) - tester.getCenter(draggedTab),
      );
      await settle('reorder a wrapped lower-row tab');
      expect(tabY('editor-2', 15), lessThan(tabY('editor-2', 10)),
          reason: 'the lower-row drag target receives the tab reorder');

      final firstStrip = find.byKey(const ValueKey('editor-tab-strip-editor'));
      final firstHeight = tester.getSize(firstStrip).height;
      expect(firstHeight, greaterThan(36));
      final secondRowTab = inGroup('editor-2', tab(16));
      final secondRowRect = tester.getRect(secondRowTab);
      final splitAction = inGroup(
        'editor-2',
        find.byTooltip('拆分编辑器'),
      );
      expect(secondRowRect.right,
          lessThanOrEqualTo(tester.getRect(splitAction).left));

      expect(tester.state<RustTextInputFieldState>(editorFinder),
          same(editorState));
      expect(tester.widget<RustTextInputField>(editorFinder).inputWindow,
          same(inputWindow));
      expect(tester.widget<EditableText>(editable).controller,
          same(textController));
      expect(textController.selection, selection);
      expect(tester.widget<RustTextInputField>(editorFinder).focusNode,
          same(focusNode));
      expect(focusNode.hasFocus, isTrue);
      expect(tester.widget<RustTextInputField>(editorFinder).scrollController,
          same(scrollController));
      expect(scrollController.offset, 0);

      await selectTabMode('单标签');
      expect(visibleTabs('editor'), findsOneWidget);
      expect(visibleTabs('editor-2'), findsOneWidget);
      await selectTabMode('不显示标签');
      expect(visibleTabs('editor'), findsNothing);
      expect(visibleTabs('editor-2'), findsNothing);
      await selectTabMode('多标签');
      expect(tabRows('editor', List.generate(8, (i) => i + 1)).length,
          greaterThan(1));
      expect(tabRows('editor-2', List.generate(6, (i) => i + 10)).length,
          greaterThan(1));

      // A tab on a lower row remains a real target, including its close action.
      expect(tabY('editor-2', 16), greaterThan(tabY('editor-2', 10)));
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-2-16')));
      await tester.pump();
      expect(tab(16), findsNothing);
      expect(visibleTabs('editor-2'), findsNWidgets(7));

      // Widening and narrowing the window recomputes wrapping without duplicates.
      tester.view.physicalSize = const Size(4000, 900);
      await tester.pump();
      await settle('widen workbench');
      expect(tabRows('editor', List.generate(8, (i) => i + 1)), hasLength(1));
      expect(
          tabRows('editor-2', List.generate(6, (i) => i + 10)), hasLength(1));
      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      await settle('narrow workbench');
      expect(tabRows('editor', List.generate(8, (i) => i + 1)).length,
          greaterThan(1));
      expect(tabRows('editor-2', List.generate(6, (i) => i + 10)).length,
          greaterThan(1));

      await setWrap(false);
      expect(tabRows('editor', List.generate(8, (i) => i + 1)), hasLength(1));
      expect(
          tabRows('editor-2', List.generate(6, (i) => i + 10)), hasLength(1));
      expect(tester.getSize(firstStrip).height, lessThanOrEqualTo(firstHeight));

      await setWrap(true);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sessionStore.tryLoad()?['editorWrapTabs'], isTrue);
      expect(
        File('$root/layout.json').readAsStringSync(),
        isNot(contains('editorWrapTabs')),
        reason: 'tab wrapping preference is separate from editor layout JSON',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      expect(tabRows('editor', List.generate(8, (i) => i + 1)).length,
          greaterThan(1),
          reason: 'session restore reapplies tab wrapping');
      final restoredItem = await openWrapMenu();
      expect(
        tester
            .getSemantics(restoredItem)
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      disposeSemantics();
    },
  );

  testWidgets(
    'pinned tabs use a separate session-backed row only in multiple mode',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula_pinned_rows');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final root = temp.path.replaceAll(r'\', '/');
      final sessionStore = SessionStore(path: '$root/session.json');
      final layoutStore = LayoutStore(path: '$root/layout.json');
      File('$root/session.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'editorTabMode': 'multiple',
        'groups': <Object?>[],
      }));

      Future<void> settle(String reason) async {
        await tester.pumpAndSettle().timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw StateError('pumpAndSettle timed out: $reason'),
            );
      }

      Future<void> mountApp() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> openCommand(String query) async {
        await tester.tap(find.byKey(const ValueKey('command-center-control')));
        await settle('command center open');
        final input = find.descendant(
          of: find.byKey(const ValueKey('quick-input')),
          matching: find.byType(TextField),
        );
        await tester.enterText(input, query);
        await settle('command query');
        final command = find.byKey(const ValueKey('qi-文件: 新建文本文件'));
        expect(command, findsOneWidget);
        await tester.tap(command);
        await settle('create text file');
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<Finder> openTabOptions() async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        return find.text('固定标签单独成行');
      }

      Future<void> setSeparateRows(bool enabled) async {
        final item = await openTabOptions();
        expect(item, findsOneWidget);
        final selected = tester
            .getSemantics(item)
            .getSemanticsData()
            .flagsCollection
            .isChecked;
        expect(
          selected,
          enabled ? CheckedState.isFalse : CheckedState.isTrue,
        );
        await tester.tap(item);
        await settle('toggle pinned tab row');
      }

      Future<void> setWrap(bool enabled) async {
        await openTabOptions();
        final wrapItem = find.text('标签自动换行');
        final selected = tester
            .getSemantics(wrapItem)
            .getSemanticsData()
            .flagsCollection
            .isChecked;
        expect(selected, enabled ? CheckedState.isFalse : CheckedState.isTrue);
        await tester.tap(wrapItem);
        await settle('toggle tab wrapping');
      }

      Future<void> setTabSizing(String label) async {
        await openTabOptions();
        await tester.tap(find.text('标签尺寸'));
        await settle('Editor tab sizing submenu');
        await tester.tap(find.text(label));
        await settle('select tab sizing: $label');
      }

      Future<void> setSticky(int id, bool sticky) async {
        final target = find.byKey(ValueKey('tab-$id'));
        await tester.tapAt(tester.getCenter(target), buttons: kSecondaryButton);
        await settle('open tab context menu');
        await tester.tap(find.text(sticky ? '固定编辑器' : '取消固定编辑器'));
        await settle(sticky ? 'pin tab $id' : 'unpin tab $id');
      }

      Future<void> selectTabMode(String label) async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
        await tester.tap(find.text(label));
        await settle('select $label');
      }

      Finder tab(int id) => find.byKey(ValueKey('tab-$id'));
      double tabY(int id) => tester.getTopLeft(tab(id)).dy;
      Set<double> tabRows(Iterable<int> ids) =>
          {for (final id in ids) tabY(id)};

      await mountApp();
      expect(sessionStore.tryLoad()?['pinnedTabsOnSeparateRow'], isNull,
          reason: 'an absent field has the default shared-row behavior');
      expect(sessionStore.lastLoadStatus, SessionLoadStatus.legacy);
      for (var i = 0; i < 5; i++) {
        await openCommand('新建文本文件');
      }
      expect(tabRows(List.generate(6, (i) => i + 1)), hasLength(1));

      // Make the active buffer dirty and retain view objects across row moves.
      final editorFinder = find.byType(RustTextInputField).first;
      final editorState = tester.state<RustTextInputFieldState>(editorFinder);
      final editorWidget = tester.widget<RustTextInputField>(editorFinder);
      final inputWindow = editorWidget.inputWindow;
      final focusNode = editorWidget.focusNode!;
      final scrollController = editorWidget.scrollController!;
      final editable = find.descendant(
        of: editorFinder,
        matching: find.byType(EditableText),
      );
      final textController = tester.widget<EditableText>(editable).controller;
      await tester.tap(editorFinder);
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'pinned-row-state',
        selection: TextSelection.collapsed(offset: 7),
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await setSticky(2, true);
      await setSticky(3, true);
      expect(tabRows([1, 2, 3, 4, 5, 6]), hasLength(1),
          reason: 'the option defaults off');
      await setSeparateRows(true);

      final pinnedRow =
          find.byKey(const ValueKey('editor-tab-row-editor-pinned'));
      final ordinaryRow =
          find.byKey(const ValueKey('editor-tab-row-editor-ordinary'));
      expect(pinnedRow, findsOneWidget);
      expect(ordinaryRow, findsOneWidget);
      expect(tabRows([2, 3]), hasLength(1));
      expect(tabRows([1, 4, 5, 6]), hasLength(1));
      expect(tabY(2), lessThan(tabY(1)));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('editor-tab-strip-editor')),
          matching: find.byTooltip('拆分编辑器'),
        ),
        findsOneWidget,
        reason: 'the separate rows share the existing editor toolbar',
      );

      // A narrow wrapped layout computes each row independently.
      tester.view.physicalSize = const Size(700, 900);
      await tester.pump();
      await settle('narrow editor group');
      await setWrap(true);
      expect(
          find
              .byKey(const ValueKey('editor-tab-row-editor-pinned'))
              .evaluate()
              .single
              .widget,
          isA<Wrap>());
      expect(
          find
              .byKey(const ValueKey('editor-tab-row-editor-ordinary'))
              .evaluate()
              .single
              .widget,
          isA<Wrap>());
      expect(tabRows([1, 4, 5, 6]).length, greaterThan(1));
      await setTabSizing('固定宽度');
      expect(tabRows([1, 4, 5, 6]).length, greaterThan(1),
          reason: 'fixed sizing keeps wrapping within the ordinary row');
      await setTabSizing('按内容适配');

      // Pinning the active tab transfers it without replacing its editor view.
      await setWrap(false);
      final pinnedScrollable = find.descendant(
        of: pinnedRow,
        matching: find.byType(Scrollable),
      );
      final ordinaryScrollable = find.descendant(
        of: ordinaryRow,
        matching: find.byType(Scrollable),
      );
      expect(pinnedScrollable, findsOneWidget);
      expect(ordinaryScrollable, findsOneWidget);
      final pinnedPosition =
          tester.state<ScrollableState>(pinnedScrollable).position;
      final ordinaryPosition =
          tester.state<ScrollableState>(ordinaryScrollable).position;
      expect(ordinaryPosition.maxScrollExtent, greaterThan(0));
      final pinnedTabX = tester.getTopLeft(tab(2)).dx;
      ordinaryPosition.jumpTo(0);
      await tester.pump();
      expect(pinnedPosition.pixels, 0);
      expect(tester.getTopLeft(tab(2)).dx, pinnedTabX,
          reason: 'ordinary-row scrolling does not move the pinned row');
      ordinaryPosition.jumpTo(ordinaryPosition.maxScrollExtent);
      await settle('reveal active ordinary tab');
      expect(
        tester.getRect(ordinaryRow).contains(tester.getRect(tab(6)).center),
        isTrue,
        reason: 'the active tab is revealed in its row',
      );
      await setSticky(6, true);
      expect(tabY(6), lessThan(tabY(1)));
      final editorAfterPin = find.byType(RustTextInputField).first;
      expect(tester.state<RustTextInputFieldState>(editorAfterPin),
          same(editorState));
      expect(tester.widget<RustTextInputField>(editorAfterPin).inputWindow,
          same(inputWindow));
      expect(tester.widget<RustTextInputField>(editorAfterPin).focusNode,
          same(focusNode));
      expect(tester.widget<RustTextInputField>(editorAfterPin).scrollController,
          same(scrollController));
      expect(
          tester
              .widget<EditableText>(find.descendant(
                of: editorAfterPin,
                matching: find.byType(EditableText),
              ))
              .controller,
          same(textController));
      expect(textController.text, 'pinned-row-state');
      expect(
          textController.selection, const TextSelection.collapsed(offset: 7));
      expect(focusNode.hasFocus, isTrue,
          reason: 'Pin/Unpin leaves the text editor focused');
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('editor-tab-label-editor-6')))
            .data,
        contains('•'),
        reason: 'Pin/Unpin preserves the dirty marker',
      );

      await setSticky(6, false);
      expect(tabY(6), greaterThan(tabY(2)));
      await setSeparateRows(false);
      expect(tabRows([1, 2, 3, 4, 5, 6]), hasLength(1));
      await setSeparateRows(true);

      await selectTabMode('单标签');
      expect(find.byKey(const ValueKey('editor-tab-row-editor-shared')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('editor-tab-row-editor-pinned')),
          findsNothing);
      await selectTabMode('不显示标签');
      expect(tab(6), findsNothing);
      await selectTabMode('多标签');
      expect(find.byKey(const ValueKey('editor-tab-row-editor-pinned')),
          findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      expect(sessionStore.tryLoad()?['pinnedTabsOnSeparateRow'], isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      expect(find.byKey(const ValueKey('editor-tab-row-editor-pinned')),
          findsOneWidget,
          reason: 'session restore reapplies the pinned row preference');

      // All sticky and no sticky groups both collapse back to one tab row.
      tester.view.physicalSize = const Size(1600, 900);
      await tester.pump();
      await settle('widen editor group');
      for (final id in [1, 4, 5, 6]) {
        await setSticky(id, true);
      }
      expect(find.byKey(const ValueKey('editor-tab-row-editor-pinned')),
          findsNothing);
      expect(tabRows([1, 2, 3, 4, 5, 6]), hasLength(1));
      for (final id in [1, 2, 3, 4, 5, 6]) {
        await setSticky(id, false);
      }
      expect(find.byKey(const ValueKey('editor-tab-row-editor-ordinary')),
          findsNothing);
      expect(tabRows([1, 2, 3, 4, 5, 6]), hasLength(1));
    },
  );
}
