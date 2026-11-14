import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, PointerDeviceKind;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tab close action visibility defaults, follows hover/focus, persists, and disables hit targets',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      final temp =
          Directory.systemTemp.createTempSync('alula_tab_close_visibility');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final root = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$root/layout.json');
      final sessionStore = SessionStore(path: '$root/session.json');
      final dirtyPath = '$root/dirty.rs';
      final firstPath = '$root/first.rs';
      final activePath = '$root/active.rs';
      File(dirtyPath).writeAsStringSync('fn disk_version() {}\n');
      File(firstPath).writeAsStringSync('fn first() {}\n');
      File(activePath).writeAsStringSync('fn active() {}\n');

      final legacySession = <String, Object?>{
        'v': 1,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 11,
            'docs': [
              {
                'id': 10,
                'path': dirtyPath,
                'text': 'fn unsaved_version() {}\n',
              },
              {'id': 12, 'path': firstPath},
              {'id': 11, 'path': activePath},
            ],
          }
        ],
      };
      sessionStore.save({
        ...legacySession,
        'editorTabCloseActionVisibility': 'invalid',
      });

      Future<void> mountApp() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> settle(String reason) async {
        await tester.pumpAndSettle().timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw StateError('pumpAndSettle timed out: $reason'),
            );
      }

      Future<void> openVisibilityMenu() async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
      }

      Future<void> expectCheckedAndCloseMenu(bool value) async {
        await openVisibilityMenu();
        final item = find.text('显示关闭操作');
        expect(item, findsOneWidget);
        expect(
          tester
              .getSemantics(item)
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          value ? CheckedState.isTrue : CheckedState.isFalse,
          reason: 'the visibility menu exposes its checked state accessibly',
        );
        await tester.tapAt(const Offset(1100, 850));
        await tester.pump();
      }

      Future<void> toggleVisibility(bool fromValue) async {
        await openVisibilityMenu();
        final item = find.text('显示关闭操作');
        expect(
          tester
              .getSemantics(item)
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          fromValue ? CheckedState.isTrue : CheckedState.isFalse,
        );
        await tester.tap(find.text('显示关闭操作'));
        await settle('toggle close action visibility');
        await tester.tapAt(const Offset(1100, 850));
        await tester.pump();
      }

      Finder tab(int id) => find.byKey(ValueKey('tab-$id'));
      Finder closeAction(String region, int id) =>
          find.byKey(ValueKey('close-tab-$region-$id'));

      double opacityOf(Finder action) => tester
          .widget<Opacity>(
            find.ancestor(of: action, matching: find.byType(Opacity)).first,
          )
          .opacity;

      bool ignoresPointers(Finder action) => tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: action, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring;

      bool excludesSemantics(Finder action) => tester
          .widget<ExcludeSemantics>(
            find
                .ancestor(of: action, matching: find.byType(ExcludeSemantics))
                .first,
          )
          .excluding;

      await mountApp();
      await expectCheckedAndCloseMenu(true);
      final dirtyAction = closeAction('editor', 10);
      final idleAction = closeAction('editor', 12);
      final activeAction = closeAction('editor', 11);
      expect(dirtyAction, findsOneWidget);
      expect(idleAction, findsOneWidget);
      expect(activeAction, findsOneWidget);
      expect(find.text('dirty.rs •'), findsOneWidget,
          reason: 'the restored dirty document keeps its tab marker');
      expect(opacityOf(dirtyAction), 1,
          reason: 'dirty tabs retain the upstream visible close glyph');
      expect(opacityOf(activeAction), 1,
          reason: 'the active tab shows its close glyph');
      expect(opacityOf(idleAction), 0,
          reason: 'an idle clean tab keeps a transparent, reserved action');
      expect(ignoresPointers(idleAction), isFalse,
          reason:
              'the enabled transparent action retains its default hit target');
      expect(excludesSemantics(idleAction), isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(tab(12)));
      await tester.pump();
      expect(opacityOf(idleAction), 1,
          reason: 'hover reveals the clean inactive tab action');
      await mouse.moveTo(const Offset(1100, 850));
      await tester.pump();
      final idleInkWell = tester.widget<InkWell>(idleAction);
      idleInkWell.focusNode!.requestFocus();
      await tester.pump();
      expect(opacityOf(idleAction), 1,
          reason: 'keyboard focus reveals the clean inactive tab action');
      idleInkWell.focusNode!.unfocus();
      await tester.pump();
      expect(opacityOf(idleAction), 0);

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

      await tester.tap(find.byTooltip('拆分编辑器').first);
      await settle('split editor group');
      final secondGroupAction = closeAction('editor-2', 11);
      expect(secondGroupAction, findsOneWidget);
      await toggleVisibility(true);
      expect(ignoresPointers(activeAction), isTrue);
      expect(ignoresPointers(secondGroupAction), isTrue,
          reason: 'the global setting immediately reaches every editor group');
      expect(excludesSemantics(activeAction), isTrue,
          reason: 'disabled close actions are removed from screen-reader semantics');
      expect(tester.widget<InkWell>(activeAction).onTap, isNull);
      expect(opacityOf(dirtyAction), 0,
          reason: 'turning actions off hides even a dirty tab close glyph');
      expect(find.text('dirty.rs •'), findsOneWidget,
          reason: 'hiding the close action retains the dirty marker');
      await tester.tap(activeAction, warnIfMissed: false);
      await tester.pump();
      expect(tab(11), findsNWidgets(2),
          reason: 'a disabled close action cannot close either group view');

      expect(
        tester.state<RustTextInputFieldState>(editorFinder),
        same(editorState),
      );
      expect(tester.widget<RustTextInputField>(editorFinder).inputWindow,
          same(inputWindow));
      expect(
        tester.widget<EditableText>(editable).controller,
        same(textController),
      );
      expect(textController.selection, selection);
      expect(tester.widget<RustTextInputField>(editorFinder).focusNode,
          same(focusNode));
      expect(tester.widget<RustTextInputField>(editorFinder).scrollController,
          same(scrollController));
      expect(scrollController.offset, 0);

      await tester.pump(const Duration(milliseconds: 700));
      expect(
          sessionStore.tryLoad()?['editorTabCloseActionVisibility'], isFalse);
      expect(
        jsonEncode(layoutStore.tryLoad()!.toJson()),
        isNot(contains('editorTabCloseActionVisibility')),
        reason:
            'the workbench preference is stored in the session journal only',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      await expectCheckedAndCloseMenu(false);
      expect(ignoresPointers(closeAction('editor', 11)), isTrue,
          reason: 'the disabled preference restores from the journal');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sessionStore.save(legacySession);
      await mountApp();
      await expectCheckedAndCloseMenu(true);
      expect(ignoresPointers(closeAction('editor', 11)), isFalse,
          reason: 'a legacy session with no visibility field defaults to true');
      semantics.dispose();
    },
  );
}
