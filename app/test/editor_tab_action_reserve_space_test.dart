import 'dart:io';
import 'dart:ui' show CheckedState, PointerDeviceKind;

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tab close-action reservation compacts clean tabs and persists accessibly',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      final temp =
          Directory.systemTemp.createTempSync('alula_tab_action_reservation');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });
      final root = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$root/layout.json');
      final sessionStore = SessionStore(path: '$root/session.json');
      final dirtyPath = '$root/dirty.rs';
      final activePath = '$root/active.rs';
      final idlePaths = <int, String>{
        for (var id = 12; id < 20; id++)
          id: '$root/clean-inactive-document-$id.rs',
      };
      for (final entry in {
        dirtyPath: 'fn disk_dirty() {}\n',
        activePath: 'fn active() {}\n',
      }.entries) {
        File(entry.key).writeAsStringSync(entry.value);
      }
      for (final path in idlePaths.values) {
        File(path).writeAsStringSync('fn idle() {}\n');
      }

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
                'text': 'fn unsaved_dirty() {}\n',
              },
              for (final entry in idlePaths.entries)
                {'id': entry.key, 'path': entry.value},
              {'id': 11, 'path': activePath},
            ],
          }
        ],
      };
      sessionStore.save(legacySession);

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

      Future<void> openEditorTabsMenu() async {
        await tester.tap(find.text('查看(V)'));
        await settle('View menu');
        await tester.tap(find.text('外观(A)'));
        await settle('Appearance menu');
        await tester.tap(find.text('编辑器标签'));
        await settle('Editor tabs submenu');
      }

      Future<void> closeMenu() async {
        await tester.tapAt(const Offset(1100, 850));
        await tester.pump();
      }

      Finder preference(String label) => find.text(label);
      bool checked(String label) =>
          tester
              .getSemantics(preference(label))
              .getSemanticsData()
              .flagsCollection
              .isChecked ==
          CheckedState.isTrue;

      Future<void> togglePreference(String label, bool expectedBefore) async {
        await openEditorTabsMenu();
        expect(preference(label), findsOneWidget);
        expect(checked(label), expectedBefore,
            reason: '$label exposes its current state to screen readers');
        await tester.tap(preference(label));
        await settle('$label toggle');
        await closeMenu();
      }

      Future<void> chooseActionLocation(String label) async {
        await openEditorTabsMenu();
        await tester.tap(find.text('关闭操作位置'));
        await settle('action-location submenu');
        await tester.tap(find.text(label));
        await settle('action location $label');
        await closeMenu();
      }

      Future<void> chooseTabSizing(String label) async {
        await openEditorTabsMenu();
        await tester.tap(find.text('标签尺寸'));
        await settle('tab-sizing submenu');
        await tester.tap(find.text(label));
        await settle('tab sizing $label');
        await closeMenu();
      }

      Finder tab(String region, int id) => find.descendant(
            of: find.byKey(ValueKey('editor-tab-strip-$region')),
            matching: find.byKey(ValueKey('tab-$id')),
          );

      Finder closeAction(String region, int id) => find.byKey(
            ValueKey('close-tab-$region-$id'),
          );

      double tabWidth(String region, int id) =>
          tester.getSize(tab(region, id)).width;

      double opacityOf(Finder action) => tester
          .widget<Opacity>(
            find.ancestor(of: action, matching: find.byType(Opacity)).first,
          )
          .opacity;

      await mountApp();
      await openEditorTabsMenu();
      expect(checked('为关闭操作保留空间'), isTrue,
          reason: 'a legacy session without the option defaults to true');
      await closeMenu();

      final originalIdleWidth = tabWidth('editor', 12);
      final originalActiveWidth = tabWidth('editor', 11);
      final originalDirtyWidth = tabWidth('editor', 10);
      expect(closeAction('editor', 12), findsOneWidget);
      await togglePreference('为关闭操作保留空间', true);

      final compactIdleWidth = tabWidth('editor', 12);
      expect(compactIdleWidth, closeTo(originalIdleWidth - 18, 0.1),
          reason: 'a clean inactive fit tab releases the action and its gap');
      expect(tabWidth('editor', 11), closeTo(originalActiveWidth, 0.1),
          reason: 'the active close action keeps its visible slot');
      expect(tabWidth('editor', 10), closeTo(originalDirtyWidth, 0.1),
          reason: 'the dirty close action keeps its visible slot');

      final idleAction = closeAction('editor', 12);
      expect(opacityOf(idleAction), 0);
      final idleTabRect = tester.getRect(tab('editor', 12));
      final idleActionRect = tester.getRect(idleAction);
      expect(idleTabRect.contains(idleActionRect.center), isTrue,
          reason: 'the unreserved action remains inside the tab hit area');

      await tester.ensureVisible(tab('editor', 12));
      await settle('reveal idle tab before hover');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(tab('editor', 12)));
      await tester.pump();
      expect(opacityOf(idleAction), 1,
          reason: 'the overlay close action appears on hover');
      expect(tabWidth('editor', 12), closeTo(compactIdleWidth, 0.1),
          reason: 'hover does not resize the unreserved tab');

      final idleInkWell = tester.widget<InkWell>(idleAction);
      await mouse.moveTo(const Offset(1100, 850));
      await tester.pump();
      idleInkWell.focusNode!.requestFocus();
      await tester.pump();
      expect(opacityOf(idleAction), 1,
          reason: 'keyboard focus reveals the overlay action');
      expect(tabWidth('editor', 12), closeTo(compactIdleWidth, 0.1));
      idleInkWell.focusNode!.unfocus();
      await tester.pump();

      await chooseActionLocation('左侧');
      final leftActionRect = tester.getRect(idleAction);
      final leftTabRect = tester.getRect(tab('editor', 12));
      expect(leftActionRect.left, greaterThanOrEqualTo(leftTabRect.left));
      expect(leftActionRect.right, lessThan(leftTabRect.right),
          reason: 'left-side actions overlay the leading edge');
      await chooseActionLocation('右侧');

      await togglePreference('标签自动换行', false);
      final wrappedRows = {
        for (var id = 12; id < 20; id++)
          tester.getTopLeft(tab('editor', id)).dy,
      };
      expect(wrappedRows.length, greaterThan(1),
          reason: 'unreserved fit tabs still form multiple rows');
      expect(
        tester.getRect(tab('editor', 12)).contains(
              tester.getRect(idleAction).center,
            ),
        isTrue,
        reason: 'the overlaid close action stays inside a wrapped tab',
      );

      for (final sizing in ['收缩', '固定宽度']) {
        await chooseTabSizing(sizing);
        expect(tabWidth('editor', 12), greaterThan(0));
        expect(
          tester.getRect(tab('editor', 12)).contains(
                tester.getRect(idleAction).center,
              ),
          isTrue,
          reason: 'the overlay remains inside a $sizing tab',
        );
      }
      await chooseTabSizing('按内容适配');
      await togglePreference('标签自动换行', true);

      await tester.ensureVisible(tab('editor', 12));
      await settle('reveal idle tab before the final hover');
      await mouse.moveTo(tester.getCenter(tab('editor', 12)));
      await tester.pump();
      await tester.tap(idleAction);
      await settle('close the intended overlaid tab');
      expect(tab('editor', 12), findsNothing,
          reason: 'the unreserved close hit target still closes its own tab');

      await tester.tap(find.byTooltip('拆分编辑器').first);
      await settle('split editor group');
      final secondGroupTab = tab('editor-2', 11);
      expect(secondGroupTab, findsOneWidget);
      final originalSecondGroupWidth = tabWidth('editor-2', 11);
      final originalFirstGroupActiveWidth = tabWidth('editor', 11);
      await togglePreference('显示关闭操作', true);
      expect(tester.widget<InkWell>(closeAction('editor', 11)).onTap, isNull);
      expect(
        tabWidth('editor', 11),
        closeTo(originalFirstGroupActiveWidth - 18, 0.1),
        reason: 'without Close actions, the active tab has no action slot',
      );
      expect(
        tabWidth('editor-2', 11),
        closeTo(originalSecondGroupWidth - 18, 0.1),
        reason: 'the global option updates every editor group',
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(sessionStore.tryLoad()?['editorTabActionReserveSpace'], isFalse);
      expect(
          sessionStore.tryLoad()?['editorTabCloseActionVisibility'], isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      await openEditorTabsMenu();
      expect(checked('为关闭操作保留空间'), isFalse,
          reason: 'the preference restores from the session journal');
      expect(checked('显示关闭操作'), isFalse);
      await closeMenu();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sessionStore.save(legacySession);
      await mountApp();
      await openEditorTabsMenu();
      expect(checked('为关闭操作保留空间'), isTrue,
          reason: 'legacy sessions retain the default reservation');
      await closeMenu();
      semantics.dispose();
    },
  );
}
