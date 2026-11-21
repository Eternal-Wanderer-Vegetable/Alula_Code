import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/modal_editor.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

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
        keybindingsStore: KeybindingsStore(path: '${baseOf()}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> prepareWorkspace(
    WidgetTester tester, {
    ModalEditorUseMode useModal = ModalEditorUseMode.some,
  }) async {
    temp = Directory.systemTemp.createTempSync('alula-modal-editor');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final base = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$base/layout.json');
    sessionStore = SessionStore(path: '$base/session.json');
    // useModal 偏好经会话 journal 承载（P07 settings UI 接管前）。
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'workbench.editor.useModal': useModal.value,
      'groups': <Object?>[],
    }));
    File('${workspace.path}/settings.json')
        .writeAsStringSync('{"editor.fontSize": 14}\n');
    File('${workspace.path}/main.rs').writeAsStringSync('fn main() {}\n');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!temp.existsSync()) return;
        try {
          await temp.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    await mountPage(tester);
  }

  /// 打开 settings.json：Explorer 双击（预览 + 固定）。节点键保留原生
  /// 分隔符（P05.48 已知），用后缀匹配。
  Future<void> openSettingsByExplorer(WidgetTester tester) async {
    Finder explorerNode() => find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('explorer-node:') &&
              key.value.endsWith('settings.json');
        });
    // useModal=some 下单击即以模态打开（第二次点击会落在模态屏障外）。
    await tester.tap(explorerNode());
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('ModalEditorPreferences', () {
    test('json round-trips and defaults to some', () {
      expect(
        ModalEditorPreferences.fromJson(
          jsonDecode(jsonEncode(const ModalEditorPreferences().toJson())),
        ).useModal,
        ModalEditorUseMode.some,
      );
      final all = const ModalEditorPreferences()
          .withUseModal(ModalEditorUseMode.all);
      final parsed = ModalEditorPreferences.fromJson(
        jsonDecode(jsonEncode(all.toJson())),
      );
      expect(parsed.useModal, ModalEditorUseMode.all);
      expect(parsed.opensAutomatically('anything.txt'), isTrue);
    });

    test('configuration path detection is case-insensitive', () {
      expect(
        isConfigurationEditorPath('C:/ws/Settings.JSON'),
        isTrue,
      );
      expect(isConfigurationEditorPath('C:/ws/keybindings.json'), isTrue);
      expect(isConfigurationEditorPath('C:/ws/main.rs'), isFalse);
      expect(isConfigurationEditorPath(null), isFalse);
    });

    test('store saves and loads atomically', () {
      final store = ModalEditorStore(
        path: '${Directory.systemTemp
                .createTempSync('alula-modal-store')
                .path}/modal_editor.json',
      );
      store.save(
        const ModalEditorPreferences(useModal: ModalEditorUseMode.off),
      );
      expect(store.load().useModal, ModalEditorUseMode.off);
      store.save(
        const ModalEditorPreferences(useModal: ModalEditorUseMode.all),
      );
      expect(store.load().useModal, ModalEditorUseMode.all);
    });
  });

  testWidgets(
    'useModal=some opens settings.json as a modal dialog instead of a tab',
    (tester) async {
      await prepareWorkspace(tester);
      await openSettingsByExplorer(tester);
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsOneWidget,
          reason: 'the configuration editor opens as a modal dialog');
      expect(find.byKey(const ValueKey('modal-editor-titlebar')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('editor-tab-strip-editor')),
          matching: find.text('settings.json'),
        ),
        findsNothing,
        reason: 'no tab is created for the modal editor',
      );
      expect(find.text('settings.json'), findsWidgets);
    },
  );

  testWidgets(
    'move-back-to-tab closes the dialog and opens the document as a tab',
    (tester) async {
      await prepareWorkspace(tester);
      await openSettingsByExplorer(tester);
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('modal-editor-move-to-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('tab-1')), findsOneWidget,
          reason: 'the document opens as a regular tab after move-back');
      expect(find.text('settings.json'), findsWidgets);
    },
  );

  testWidgets(
    'escape closes the modal and the document is discarded',
    (tester) async {
      await prepareWorkspace(tester);
      await openSettingsByExplorer(tester);
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('editor-tab-strip-editor')),
          matching: find.text('settings.json'),
        ),
        findsNothing,
        reason: 'the detached modal document is discarded on close',
      );
    },
  );

  testWidgets(
    'the maximize toggle expands the dialog to the full workbench',
    (tester) async {
      await prepareWorkspace(tester);
      await openSettingsByExplorer(tester);
      final titleBar = find.byKey(const ValueKey('modal-editor-titlebar'));
      final before = tester.getSize(titleBar).width;
      await tester.tap(find.byKey(const ValueKey('modal-editor-maximize')));
      await tester.pumpAndSettle();
      final after = tester.getSize(titleBar).width;
      expect(after, greaterThan(before),
          reason: 'maximize expands the dialog content width');
    },
  );

  testWidgets(
    'useModal=off opens settings.json as a regular tab',
    (tester) async {
      await prepareWorkspace(
        tester,
        useModal: ModalEditorUseMode.off,
      );
      await openSettingsByExplorer(tester);
      expect(find.byKey(const ValueKey('modal-editor-dialog')), findsNothing,
          reason: 'useModal=off never opens modals');
      expect(find.byKey(const ValueKey('tab-1')), findsOneWidget,
          reason: 'the document opens as a regular tab');
    },
  );

  testWidgets(
    'the focus trap keeps Tab traversal inside the dialog',
    (tester) async {
      await prepareWorkspace(tester);
      await openSettingsByExplorer(tester);
      // 焦点陷阱：对话框内 Tab 循环，焦点不落到对话框外的编辑器。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      var insideDialog = false;
      final focusContext = FocusManager.instance.primaryFocus!.context;
      focusContext!.visitAncestorElements((element) {
        if (element.widget.key == const ValueKey('modal-editor-dialog')) {
          insideDialog = true;
          return false;
        }
        return true;
      });
      expect(insideDialog, isTrue,
          reason: 'focus stays inside the modal dialog');
    },
  );
}
