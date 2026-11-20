import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 49) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Finder _tabIn(String region, int id) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byKey(ValueKey('tab-$id')),
    );

Finder _strip(String region) =>
    find.byKey(ValueKey('editor-tab-strip-$region'));

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  CommandService? commands;

  String baseOf() => temp.path.replaceAll(r'\', '/');

  Future<void> mountPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands, isNotNull);
  }

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-group-mru-close');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  /// Seeds a three-group horizontal layout with one file document per group.
  Future<void> seedThreeGroups({required String focused}) async {
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync('fn alpha() {}\n');
    final beta = File('${workspace.path}/beta.rs')
      ..writeAsStringSync('fn beta() {}\n');
    final gamma = File('${workspace.path}/gamma.rs')
      ..writeAsStringSync('fn gamma() {}\n');
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    layout.splitLeaf('editor-2', 'editor-3', Axis.horizontal);
    layoutStore.save(layout);
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': focused,
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': alpha.path},
          ],
          'active': 10,
        },
        {
          'region': 'editor-2',
          'docs': [
            {'id': 11, 'path': beta.path},
          ],
          'active': 11,
        },
        {
          'region': 'editor-3',
          'docs': [
            {'id': 12, 'path': gamma.path},
          ],
          'active': 12,
        },
      ],
    }));
  }

  testWidgets(
    'closing the focused group focuses the most recently active group',
    (tester) async {
      await prepareWorkspace(tester);
      await seedThreeGroups(focused: 'editor-3');
      await mountPage(tester);
      expect(_strip('editor'), findsOneWidget);
      expect(_strip('editor-2'), findsOneWidget);
      expect(_strip('editor-3'), findsOneWidget);

      // Establish the activation order editor -> editor-2 (editor-3 stays
      // the focused group with the oldest restored activation).
      await tester.tap(_tabIn('editor', 10));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-2', 11));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-3', 12));
      await tester.pump(const Duration(milliseconds: 200));

      // Close the focused group's documents (the welcome untitled re-attaches
      // to the focused group at mount): once the group empties it is removed
      // and the most recently active remaining group (editor-2) gains focus,
      // not the insertion-first group (editor).
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-3-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-3-1')));
      await tester.pumpAndSettle();
      // 推进 500ms 会话保存防抖，使断言读到持久化状态。
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor-3'), findsNothing,
          reason: 'the emptied group is removed');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2',
          reason: 'the most recently active remaining group gains focus '
              '(upstream doRemoveEmptyGroup mostRecentlyActiveGroups[1])');
    },
  );

  testWidgets(
    'closing a non-focused middle group keeps focus and MRU continues',
    (tester) async {
      await prepareWorkspace(tester);
      await seedThreeGroups(focused: 'editor-3');
      await mountPage(tester);

      // Activation order: editor-3 (restored focus) -> editor -> editor-2.
      await tester.tap(_tabIn('editor', 10));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-2', 11));
      await tester.pump(const Duration(milliseconds: 200));

      // Close the non-focused first group: focus stays on editor-2.
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-10')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor'), findsNothing);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2',
          reason: 'closing a non-focused group does not move focus');

      // Closing the focused editor-2 group falls back to the most recently
      // active remaining group (editor-3, activated before editor-2).
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-2-11')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor-2'), findsNothing);
      expect(sessionStore.tryLoad()?['focused'], 'editor-3',
          reason: 'the MRU chain continues across consecutive group closes');
    },
  );

  Future<void> seedSelectionTabs() async {
    final files = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'other']
        .map((name) => File('${workspace.path}/$name.txt')
          ..writeAsStringSync('$name fixture\n'))
        .toList();
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    layoutStore.save(layout);
    sessionStore.save({
      'v': 1,
      'focused': 'editor',
      'editorTabSizing': 'shrink',
      'groups': [
        {
          'region': 'editor',
          'active': 14,
          'locked': true,
          'docs': [
            for (var index = 0; index < 5; index++)
              {'id': index + 10, 'path': files[index].path},
          ],
        },
        {
          'region': 'editor-2',
          'active': 15,
          'locked': true,
          'docs': [
            {'id': 15, 'path': files.last.path}
          ],
        },
      ],
    });
  }

  Future<void> clickTab(
    WidgetTester tester,
    int id, {
    LogicalKeyboardKey? modifier,
    String region = 'editor',
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.tap(
      find.byKey(ValueKey('editor-tab-label-$region-$id')),
      kind: PointerDeviceKind.mouse,
    );
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
  }

  void expectSelected(
    WidgetTester tester,
    Set<int> ids,
    int active, {
    String region = 'editor',
  }) {
    final selected = tester
        .widgetList<Semantics>(find.descendant(
          of: _strip(region),
          matching: find.byType(Semantics),
        ))
        .where((widget) => widget.properties.selected == true);
    expect(
      selected.map((widget) => (widget.key as ValueKey<String>).value).toSet(),
      {for (final id in ids) 'editor-tab-semantics-$region-$id'},
    );
    final groups = sessionStore.tryLoad()!['groups'] as List;
    final saved =
        groups.cast<Map>().singleWhere((group) => group['region'] == region);
    expect(saved['active'], active);
  }

  testWidgets(
    'modified editor-tab clicks keep a group selection and MRU fallback',
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
    (tester) async {
      await prepareWorkspace(tester);
      await seedSelectionTabs();
      await mountPage(tester);
      final toggle = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      expectSelected(tester, {14}, 14);
      await clickTab(tester, 11);
      await clickTab(tester, 13, modifier: toggle);
      expectSelected(tester, {11, 13}, 13);
      await clickTab(tester, 10, modifier: toggle);
      expectSelected(tester, {10, 11, 13}, 10);
      await clickTab(tester, 10, modifier: toggle);
      expectSelected(tester, {11, 13}, 13);
      await clickTab(tester, 11, modifier: toggle);
      await clickTab(tester, 13, modifier: toggle);
      expectSelected(tester, {13}, 13);

      await clickTab(tester, 11);
      await clickTab(tester, 13, modifier: LogicalKeyboardKey.shiftLeft);
      expectSelected(tester, {11, 12, 13}, 13);
      await clickTab(tester, 10, modifier: LogicalKeyboardKey.shiftLeft);
      expectSelected(tester, {10, 11}, 10);
      await clickTab(tester, 15, region: 'editor-2');
      expectSelected(tester, {15}, 15, region: 'editor-2');
      expectSelected(tester, {10, 11}, 10);
      await clickTab(tester, 11);
      expectSelected(tester, {11}, 11);
    },
  );

  testWidgets(
    'editor-tab batch close uses one dirty confirmation and respects its scope',
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
    (tester) async {
      await prepareWorkspace(tester);
      await seedSelectionTabs();
      await mountPage(tester);
      Future<void> contextClose(int id) async {
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('editor-tab-label-editor-$id'))),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PopupMenuItem<String>, '关闭'));
        await tester.pumpAndSettle();
      }

      final field = find.descendant(
        of: find.byKey(const ValueKey('wb-region-editor')),
        matching: find.byType(EditableText),
      );
      await clickTab(tester, 10);
      await tester.enterText(field, 'alpha changed');
      await tester.pump(const Duration(milliseconds: 600));
      expect(await commands!.execute('workbench.action.splitEditorInGroup'),
          CommandExecutionStatus.executed);
      await tester.pumpAndSettle();
      expect(field, findsNWidgets(2));
      await clickTab(tester, 11);
      await tester.enterText(field, 'bravo changed');
      await tester.pump(const Duration(milliseconds: 600));
      await clickTab(tester, 10, modifier: LogicalKeyboardKey.controlLeft);
      expectSelected(tester, {10, 11}, 10);
      await contextClose(14);
      expect(_tabIn('editor', 14), findsNothing);
      expectSelected(tester, {10, 11}, 10);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      for (final name in ['alpha.txt', 'bravo.txt']) {
        expect(find.descendant(of: dialog, matching: find.textContaining(name)),
            findsWidgets);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expectSelected(tester, {10, 11}, 10);
      expect(_tabIn('editor', 12), findsOneWidget);
      expect(_tabIn('editor-2', 15), findsOneWidget);

      await contextClose(11);
      expect(dialog, findsOneWidget);
      await tester.tap(find.text('不保存'));
      await tester.pumpAndSettle();
      expect(_tabIn('editor', 10), findsNothing);
      expect(_tabIn('editor', 11), findsNothing);
      expect(_tabIn('editor', 12), findsOneWidget);
      expect(_tabIn('editor', 13), findsOneWidget);
      expect(_tabIn('editor-2', 15), findsOneWidget);
      for (final name in ['alpha', 'bravo']) {
        expect(File('${workspace.path}/$name.txt').readAsStringSync(),
            '$name fixture\n');
      }

      await clickTab(tester, 12);
      expect(await commands!.execute('workbench.action.pinEditor'),
          CommandExecutionStatus.executed);
      await tester.pumpAndSettle();
      await clickTab(tester, 13, modifier: LogicalKeyboardKey.controlLeft);
      expectSelected(tester, {12, 13}, 13);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_tabIn('editor', 12), findsOneWidget);
      expect(_tabIn('editor', 13), findsNothing);
    },
  );

  testWidgets(
    'recent editor picker cycles while held and commits to the chosen group',
    (tester) async {
      await prepareWorkspace(tester);
      final files = ['alpha', 'bravo', 'charlie', 'delta']
          .map((name) => File('${workspace.path}/$name.txt')
            ..writeAsStringSync('$name sample\n'))
          .toList();
      final layout = defaultLayout();
      layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
      layoutStore.save(layout);
      sessionStore.save({
        'v': 1,
        'focused': 'editor',
        'editorTabSizing': 'shrink',
        'groups': [
          {
            'region': 'editor',
            'active': 12,
            'locked': true,
            'docs': [
              for (var index = 0; index < 3; index++)
                {'id': index + 10, 'path': files[index].path},
            ],
          },
          {
            'region': 'editor-2',
            'active': 13,
            'locked': true,
            'docs': [
              {'id': 11, 'path': files[1].path},
              {'id': 13, 'path': files[3].path},
            ],
          },
        ],
      });
      await mountPage(tester);
      final picker = find.byKey(const ValueKey('quick-input'));
      Finder row(String name) => find.byKey(ValueKey('qi-$name.txt'));
      void expectHighlighted(String name) {
        expect(picker, findsOneWidget);
        expect(
            tester.widget<Container>(row(name)).color, const Color(0xFF2F3542));
      }

      Future<void> confirmEditor(String region, int id) async {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();
        expect(picker, findsNothing);
        final session = sessionStore.tryLoad()!;
        expect(session['focused'], region);
        final groups = (session['groups'] as List).cast<Map>();
        expect(groups.singleWhere((g) => g['region'] == region)['active'], id);
      }

      await clickTab(tester, 10);
      await clickTab(tester, 11);
      await clickTab(tester, 12);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectHighlighted('bravo');
      expect(find.descendant(of: picker, matching: find.byType(TextField)),
          findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectHighlighted('alpha');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectHighlighted('charlie');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expectHighlighted('alpha');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await confirmEditor('editor', 10);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectHighlighted('bravo');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expectHighlighted('bravo');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await confirmEditor('editor', 11);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectHighlighted('alpha');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await confirmEditor('editor', 11);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await confirmEditor('editor', 10);

      await clickTab(tester, 11, region: 'editor-2');
      await clickTab(tester, 10);
      await clickTab(tester, 13, region: 'editor-2');
      expect(
        await commands!
            .execute('workbench.action.showAllEditorsByMostRecentlyUsed'),
        CommandExecutionStatus.executed,
      );
      await tester.pumpAndSettle();
      expectHighlighted('delta');
      expect(find.descendant(of: picker, matching: find.byType(TextField)),
          findsOneWidget);
      expect(row('bravo'), findsNWidgets(2));
      final duplicateInSecondGroup = find.ancestor(
        of: find.descendant(
          of: row('bravo'),
          matching: find.text('编辑器组 2'),
        ),
        matching: row('bravo'),
      );
      await tester.tap(duplicateInSecondGroup);
      await confirmEditor('editor-2', 11);
      await clickTab(tester, 10);
      await clickTab(tester, 13, region: 'editor-2');

      expect(
        await commands!
            .execute('workbench.action.quickOpenPreviousRecentlyUsedEditor'),
        CommandExecutionStatus.executed,
      );
      await tester.pumpAndSettle();
      expectHighlighted('alpha');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await confirmEditor('editor', 10);
    },
  );
}
