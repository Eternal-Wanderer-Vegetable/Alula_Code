import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuxiliaryWindowPayload', () {
    test('document payload round-trips through arguments', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        path: 'C:/ws/src/main.rs',
        name: 'main.rs',
        text: 'fn main() {}',
        dirty: true,
      );
      final parsed = AuxiliaryWindowPayload.fromArguments(
        payload.toArguments(),
      );
      expect(parsed.isAuxiliary, isTrue);
      expect(parsed.path, 'C:/ws/src/main.rs');
      expect(parsed.name, 'main.rs');
      expect(parsed.text, 'fn main() {}');
      expect(parsed.dirty, isTrue);
    });

    test('untitled payloads keep a null path', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        name: '未命名',
        text: 'body',
        dirty: false,
      );
      final parsed = AuxiliaryWindowPayload.fromArguments(
        payload.toArguments(),
      );
      expect(parsed.path, isNull);
      expect(parsed.text, 'body');
      expect(parsed.dirty, isFalse);
    });

    test('main-window arguments parse as non-auxiliary', () {
      expect(
        AuxiliaryWindowPayload.fromArguments('--lsp-auto').isAuxiliary,
        isFalse,
      );
      expect(AuxiliaryWindowPayload.fromArguments('').isAuxiliary, isFalse);
    });
  });

  group('main-window move flow', () {
    late Directory temp;
    late LayoutStore layoutStore;
    late SessionStore sessionStore;
    final createdPayloads = <String>[];
    CommandService? commands;

    String baseOf() => temp.path.replaceAll(r'\', '/');

    setUp(() {
      temp = Directory.systemTemp.createTempSync('alula-aux-window');
      Directory('${temp.path}/workspace').createSync();
      layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
      sessionStore = SessionStore(path: '${baseOf()}/session.json');
      createdPayloads.clear();
    });

    Future<void> mountWorkbench(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final untitled = File('${temp.path}/journal-copy.txt')
        ..writeAsStringSync('moved body');
      File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'editorTabMode': 'multiple',
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'docs': [
              {
                'id': 10,
                'name': 'journal-copy.txt',
                'path': untitled.path,
                'text': 'moved body',
              },
            ],
            'active': 10,
          },
        ],
      }));
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: '${temp.path}/workspace',
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

    testWidgets(
      'the command captures the document payload and removes the source view',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mixin.one/desktop_multi_window'),
          (call) async {
            if (call.method == 'createWindow') {
              final config = call.arguments as Map<dynamic, dynamic>;
              createdPayloads.add(config['arguments'] as String);
              return 'aux-1';
            }
            if (call.method == 'getWindowDefinition') {
              return {'windowId': 'main', 'windowArgument': ''};
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('mixin.one/desktop_multi_window'),
            null,
          );
        });

        await mountWorkbench(tester);
        expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);

        await commands!.execute('workbench.action.moveEditorToNewWindow');
        await tester.pumpAndSettle();
        // 推进 500ms 会话保存防抖，使断言读到持久化状态。
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(createdPayloads, hasLength(1),
            reason: 'the move creates one auxiliary window');
        final parsed = AuxiliaryWindowPayload.fromArguments(
          createdPayloads.single,
        );
        expect(parsed.isAuxiliary, isTrue);
        expect(parsed.name, 'journal-copy.txt');
        expect(parsed.text, 'moved body',
            reason: 'the document text travels with the window');
        expect(find.byKey(const ValueKey('tab-10')), findsNothing,
            reason: 'the source group loses the moved view');
        final groups =
            (sessionStore.tryLoad()?['groups'] as List).cast<Map>();
        expect(groups, hasLength(1),
            reason: 'the focused group remains (welcome untitled)');
        final docs = (groups.single['docs'] as List).cast<Map>();
        expect(docs.where((doc) => doc['id'] == 10), isEmpty,
            reason: 'the moved document no longer belongs to any group');
      },
    );
  });
}
