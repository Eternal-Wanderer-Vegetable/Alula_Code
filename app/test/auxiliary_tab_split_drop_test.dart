import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/auxiliary_tab_drop_target.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/auxiliary_window_transfer.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart' show Diagnosticable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'helpers/native_drag_drop.dart';

class _AuxiliaryReturnItem extends Fake
    with Diagnosticable
    implements DropItem {
  _AuxiliaryReturnItem(this.localData);

  @override
  final Object localData;
}

class _AuxiliaryReturnSession extends Fake
    with Diagnosticable
    implements DropSession {
  @override
  final List<DropItem> items = [
    _AuxiliaryReturnItem(
      const AuxiliaryTabDragTicket('aux-1', 1).toLocalData(),
    ),
  ];

  @override
  final allowedOperations = const {DropOperation.move};
}

void main() {
  setUpAll(mockNativeDragDrop);

  testWidgets(
    'native auxiliary edge preview uses the body, and rejection leaves the layout intact',
    (tester) async {
      const windowChannel = MethodChannel('mixin.one/desktop_multi_window');
      const peerChannel =
          MethodChannel('mixin.one/desktop_multi_window/channels');
      const windowManager = MethodChannel('window_manager');
      const dragInput = MethodChannel('alula/drag_input');
      final messenger = tester.binding.defaultBinaryMessenger;
      final directory = Directory.systemTemp.createTempSync('alula-aux-split');
      final workspace = Directory('${directory.path}/workspace')..createSync();
      final sample = File('${workspace.path}/sample.txt');
      final original = [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('Line 😀\r\nTail\r\n')
      ];
      sample.writeAsBytesSync(original);
      final layout = LayoutStore(path: '${directory.path}/layout.json');
      final session = SessionStore(path: '${directory.path}/session.json');
      const edited = 'Line 😀RETURN\nTail\n';
      const selection = TextSelection(baseOffset: 13, extentOffset: 7);
      final receipts = <bool>[];
      var reject = true;
      var disableSplit = false;
      CommandService? commands;

      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        for (final channel in [
          windowChannel,
          peerChannel,
          windowManager,
          dragInput
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        await tester.runAsync(() => directory.delete(recursive: true));
      });

      messenger.setMockMethodCallHandler(windowChannel, (call) async {
        return switch (call.method) {
          'createWindow' => 'aux-1',
          'getWindowDefinition' => {'windowId': 'main', 'windowArgument': ''},
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(dragInput, (call) async {
        expect(call.method, 'splitTogglePressed');
        return disableSplit;
      });
      messenger.setMockMethodCallHandler(windowManager, (call) async {
        return call.method == 'isFocused' ? true : null;
      });
      messenger.setMockMethodCallHandler(peerChannel, (call) async {
        if (call.method != 'invokeMethod') return null;
        final request = call.arguments as Map;
        switch (request['method']) {
          case auxiliaryTabReturnPrepareMethod:
            return {
              'businessId': AuxiliaryWindowPayload.businessId,
              'path': sample.path,
              'name': 'sample.txt',
              'text': edited,
              'dirty': true,
              'selectionBase': reject ? -1 : selection.baseOffset,
              'selectionExtent': selection.extentOffset,
            };
          case auxiliaryTabReturnFinishMethod:
            final receipt = request['arguments'] as Map;
            receipts.add(receipt['accepted'] as bool);
            return true;
        }
        return null;
      });
      File('${directory.path}/session.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'editorTabMode': 'multiple',
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'docs': [
              {'id': 10, 'path': sample.path}
            ],
            'active': 10,
          },
        ],
      }));
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: layout,
          sessionStore: session,
          keybindingsStore: KeybindingsStore(
            path: '${directory.path}/keybindings.json',
          ),
          onCommandServiceReady: (service) => commands = service,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
      await commands!.execute('workbench.action.moveEditorToNewWindow');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tab-10')), findsNothing);

      final source = _AuxiliaryReturnSession();
      final owner = find.byWidgetPredicate(
        (widget) =>
            widget is AuxiliaryTabDropTarget &&
            widget.keyPrefix == 'auxiliary-return-body-editor',
      );
      DropRegion target() => tester.widget<DropRegion>(
            find.descendant(of: owner, matching: find.byType(DropRegion)).first,
          );
      final originalBody =
          find.byKey(const ValueKey('editor-body-drop-editor'));
      final newBody = find.byKey(const ValueKey('editor-body-drop-editor-2'));
      DropPosition bodyPosition(double x, double y) {
        final rect = tester.getRect(originalBody);
        final local = Offset(rect.width * x, rect.height * y);
        return DropPosition(local: local, global: rect.topLeft + local);
      }

      Future<void> hover(String mode, double x, double y) async {
        expect(
          await target().onDropOver(
            DropOverEvent(session: source, position: bodyPosition(x, y)),
          ),
          DropOperation.move,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('auxiliary-return-body-editor-overlay-$mode')),
          findsOneWidget,
        );
        expect(newBody, findsNothing);
      }

      Future<void> dropDown() async {
        await target().onPerformDrop(PerformDropEvent(
          session: source,
          position: bodyPosition(.5, .95),
          acceptedOperation: DropOperation.move,
        ));
        await tester.pumpAndSettle();
      }

      await hover('splitLeft', .05, .5);
      await hover('splitRight', .95, .5);
      await hover('splitUp', .5, .05);
      await hover('center', .5, .5);
      disableSplit = true;
      await hover('center', .5, .95);
      disableSplit = false;
      await hover('splitDown', .5, .95);
      await dropDown();
      expect(receipts, [false]);
      expect(newBody, findsNothing);

      reject = false;
      await hover('splitDown', .5, .95);
      await dropDown();
      expect(receipts, [false, true]);
      expect(newBody, findsOneWidget);
      expect(tester.getRect(newBody).top,
          greaterThan(tester.getRect(originalBody).bottom));
      final input = tester.widget<RustTextInputField>(
        find.descendant(of: newBody, matching: find.byType(RustTextInputField)),
      );
      expect(input.inputWindow.document.resync().content, edited);
      final field = tester.widget<TextField>(
        find.descendant(of: newBody, matching: find.byType(TextField)).first,
      );
      expect(field.controller!.selection, selection);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(sample.readAsBytesSync(), original);
    },
  );
}
