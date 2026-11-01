import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native macOS drag drops local text into the same editor region',
    (tester) async {
      final directoryPath = Platform.environment['ALULA_MACOS_DND_DIR'];
      expect(directoryPath, isNotNull);
      final directory = Directory(directoryPath!);
      directory.createSync(recursive: true);
      final semanticsHandle = tester.ensureSemantics();
      addTearDown(semanticsHandle.dispose);

      const payload = EditorTextDragPayload(
        selection: EditorTextDragSelection(
          documentId: 7001,
          documentVersion: 3,
          startUtf16: 0,
          endUtf16: 5,
        ),
        selectedText: 'alpha',
        token: 41,
      );
      final dropReceived = Completer<EditorTextDragDropRequest>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EditorNativeTextDragDrop(
                enabled: true,
                payloadAt: (_) => payload,
                buildDropRequest: (candidate, _, operation) =>
                    EditorTextDragDropRequest(
                  payload: candidate,
                  targetDocumentId: candidate.selection.documentId,
                  targetDocumentVersion: candidate.selection.documentVersion,
                  targetOffsetUtf16: 11,
                  operation: operation,
                ),
                onDrop: (request) {
                  if (!dropReceived.isCompleted) {
                    dropReceived.complete(request);
                  }
                  File('${directory.path}/drop.json').writeAsStringSync(
                    jsonEncode({
                      'selectedText': request.payload.selectedText,
                      'operation': request.operation.name,
                      'targetOffsetUtf16': request.targetOffsetUtf16,
                    }),
                  );
                },
                onDragCompleted: (_, __) {},
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      container: true,
                      identifier: 'alula-dnd-source',
                      label: 'ALULA DND SOURCE',
                      child: const SizedBox(
                        width: 240,
                        height: 90,
                        child: Center(child: Text('Drag source')),
                      ),
                    ),
                    const SizedBox(height: 120),
                    Semantics(
                      container: true,
                      identifier: 'alula-dnd-target',
                      label: 'ALULA DND TARGET',
                      child: const SizedBox(
                        width: 240,
                        height: 90,
                        child: Center(child: Text('Drop target')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      File('${directory.path}/ready').writeAsStringSync('ready');

      final request = await tester.runAsync(
        () => dropReceived.future.timeout(const Duration(seconds: 40)),
      );
      await tester.pump();

      expect(request, isNotNull);
      final result = jsonDecode(
        File('${directory.path}/drop.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(result['selectedText'], 'alpha');
      expect(result['operation'], EditorTextDropOperation.move.name);
      expect(result['targetOffsetUtf16'], 11);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
