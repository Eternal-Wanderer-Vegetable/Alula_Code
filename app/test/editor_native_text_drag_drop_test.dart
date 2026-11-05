import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:alula_app/editor/text_drag_drop.dart';

void main() {
  testWidgets('macOS native drag/drop waits for the engine context handshake',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: EditorNativeTextDragDrop(
            enabled: true,
            payloadAt: (_) => null,
            buildDropRequest: (_, __, ___) => null,
            onDrop: (_) {},
            onDragCompleted: (_, __) {},
            child: const Text('editor'),
          ),
        ),
      );

      expect(find.byType(DragItemWidget), findsNothing);
      expect(find.byType(DraggableWidget), findsNothing);
      expect(find.byType(DropRegion), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('external text drop advertises only plain text', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: EditorNativeTextDragDrop(
            enabled: true,
            payloadAt: (_) => null,
            buildDropRequest: (_, __, ___) => null,
            onDrop: (_) {},
            onDragCompleted: (_, __) {},
            editorExternalTextDropTargetAt: (_) =>
                const EditorExternalTextDropTarget(
              targetDocumentId: 7,
              targetDocumentVersion: 2,
              targetOffsetUtf16: 3,
            ),
            onExternalTextDrop: (_) {},
            child: const Text('editor'),
          ),
        ),
      );

      final region = tester.widget<DropRegion>(find.byType(DropRegion));
      expect(region.formats, [Formats.plainText]);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
