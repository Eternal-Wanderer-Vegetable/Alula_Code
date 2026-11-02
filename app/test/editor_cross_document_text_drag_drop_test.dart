import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class _LocalDropItem extends DropItem {
  _LocalDropItem(this.localData);

  @override
  final Object? localData;

  @override
  bool canProvide(DataFormat format) => false;

  @override
  DataReader? get dataReader => null;

  @override
  List<PlatformFormat> get platformFormats => const [];
}

class _PayloadDropSession extends DropSession {
  _PayloadDropSession(EditorTextDragPayload payload)
      : items = [_LocalDropItem(payload.toLocalData())];

  final _disposed = ChangeNotifier();
  @override
  final List<DropItem> items;

  @override
  Listenable get onDisposed => _disposed;

  @override
  Set<DropOperation> get allowedOperations => const {
        DropOperation.copy,
        DropOperation.move,
      };
}

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } on Object catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _coreBootstrap = _CoreBootstrap();

void main() {
  testWidgets(
    'cross-document local drag routes explicit copy and default move',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final targetDocument =
            _coreBootstrap.core!.openDoc(97621, 'target text');
        final inputWindow = RustTextInputWindow.open(
          targetDocument,
          startUtf16: 0,
          maxWindowUtf16: 64,
        );
        final received = <EditorTextDragDropRequest>[];
        const payload = EditorTextDragPayload(
          selection: EditorTextDragSelection(
            documentId: 97620,
            documentVersion: 4,
            startUtf16: 2,
            endUtf16: 7,
          ),
          selectedText: 'alpha',
          token: 9,
        );

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          targetDocument.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 160,
                child: RustTextInputField(
                  inputWindow: inputWindow,
                  showLineNumbers: false,
                  showIndentGuides: false,
                  onTextDragDrop: (request) {
                    received.add(request);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final region = tester.widget<DropRegion>(find.byType(DropRegion));
        final point = tester.getCenter(find.byType(EditableText));
        final position = DropPosition(local: point, global: point);
        final session = _PayloadDropSession(payload);
        const copyModifier = LogicalKeyboardKey.controlLeft;

        await tester.sendKeyDownEvent(copyModifier);
        late final DropOperation copyOperation;
        try {
          copyOperation = await region.onDropOver(
            DropOverEvent(session: session, position: position),
          );
          expect(copyOperation, DropOperation.copy);
          await region.onPerformDrop(
            PerformDropEvent(
              session: session,
              position: position,
              acceptedOperation: copyOperation,
            ),
          );
          expect(received, hasLength(1));
          expect(
            received.single.payload.selection,
            payload.selection,
          );
          expect(received.single.payload.selectedText, payload.selectedText);
          expect(received.single.payload.token, payload.token);
          expect(received.single.operation, EditorTextDropOperation.copy);
          expect(received.single.targetDocumentId, targetDocument.id);
          expect(received.single.targetDocumentVersion, targetDocument.version);
        } finally {
          await tester.sendKeyUpEvent(copyModifier);
        }

        final moveOperation = await region.onDropOver(
          DropOverEvent(session: session, position: position),
        );
        expect(moveOperation, DropOperation.move);
        await region.onPerformDrop(
          PerformDropEvent(
            session: session,
            position: position,
            acceptedOperation: moveOperation,
          ),
        );
        expect(received, hasLength(2));
        expect(received.last.operation, EditorTextDropOperation.move);
        expect(received.last.targetDocumentId, targetDocument.id);
        expect(received.last.targetDocumentVersion, targetDocument.version);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
    skip: _coreBootstrap.skip != null,
  );
}
