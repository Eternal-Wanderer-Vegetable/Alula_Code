import 'package:flutter/foundation.dart';

import '../bridge/alula_core.dart';

const int maxEditorTextDragUtf16 = 65536;

enum EditorTextDropOperation { move, copy }

@immutable
class EditorTextDragSelection {
  const EditorTextDragSelection({
    required this.documentId,
    required this.documentVersion,
    required this.startUtf16,
    required this.endUtf16,
  });

  static const String localDataKind = 'alula.editorTextSelection.v1';

  final int documentId;
  final int documentVersion;
  final int startUtf16;
  final int endUtf16;

  int get lengthUtf16 => endUtf16 - startUtf16;

  @override
  bool operator ==(Object other) =>
      other is EditorTextDragSelection &&
      other.documentId == documentId &&
      other.documentVersion == documentVersion &&
      other.startUtf16 == startUtf16 &&
      other.endUtf16 == endUtf16;

  @override
  int get hashCode => Object.hash(
        documentId,
        documentVersion,
        startUtf16,
        endUtf16,
      );

  Map<String, Object?> toLocalData() => {
        'kind': localDataKind,
        'documentId': documentId,
        'documentVersion': documentVersion,
        'startUtf16': startUtf16,
        'endUtf16': endUtf16,
      };

  static EditorTextDragSelection? tryParseLocalData(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'];
    final documentId = value['documentId'];
    final documentVersion = value['documentVersion'];
    final startUtf16 = value['startUtf16'];
    final endUtf16 = value['endUtf16'];
    if (kind != localDataKind ||
        documentId is! int ||
        documentVersion is! int ||
        startUtf16 is! int ||
        endUtf16 is! int ||
        documentVersion <= 0 ||
        startUtf16 < 0 ||
        endUtf16 <= startUtf16 ||
        endUtf16 - startUtf16 > maxEditorTextDragUtf16) {
      return null;
    }
    return EditorTextDragSelection(
      documentId: documentId,
      documentVersion: documentVersion,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
    );
  }
}

@immutable
class EditorTextDragPayload {
  const EditorTextDragPayload({
    required this.selection,
    required this.selectedText,
    required this.token,
  });

  static const String selectedTextKey = 'selectedText';
  static const String tokenKey = 'token';

  final EditorTextDragSelection selection;
  final String selectedText;
  final int token;

  Map<String, Object?> toLocalData() => {
        ...selection.toLocalData(),
        selectedTextKey: selectedText,
        tokenKey: token,
      };

  static EditorTextDragPayload? tryParseLocalData(Object? value) {
    if (value is! Map) return null;
    final selection = EditorTextDragSelection.tryParseLocalData(value);
    final selectedText = value[selectedTextKey];
    final token = value[tokenKey];
    if (selection == null ||
        selectedText is! String ||
        selectedText.length != selection.lengthUtf16 ||
        token is! int ||
        token <= 0) {
      return null;
    }
    return EditorTextDragPayload(
      selection: selection,
      selectedText: selectedText,
      token: token,
    );
  }
}

@immutable
class EditorTextDragDropRequest {
  const EditorTextDragDropRequest({
    required this.payload,
    required this.targetDocumentId,
    required this.targetDocumentVersion,
    required this.targetOffsetUtf16,
    required this.operation,
  });

  final EditorTextDragPayload payload;
  final int targetDocumentId;
  final int targetDocumentVersion;
  final int targetOffsetUtf16;
  final EditorTextDropOperation operation;
}

@immutable
class EditorTextDragEditPlan {
  const EditorTextDragEditPlan({
    required this.forward,
    required this.inverse,
    required this.insertOffsetUtf16,
    required this.afterCaretUtf16,
    required this.resultLengthUtf16,
  });

  final List<TextOp> forward;
  final List<TextOp> inverse;
  final int insertOffsetUtf16;
  final int afterCaretUtf16;
  final int resultLengthUtf16;
}

/// Plans a bounded, single-document drag edit. All offsets are UTF-16 units.
/// The returned operation lists are sequential: each operation uses offsets in
/// the text produced by the preceding operation.
EditorTextDragEditPlan? planSameDocumentTextDrag({
  required EditorTextDragSelection source,
  required int targetDocumentId,
  required int targetDocumentVersion,
  required int targetDocumentLengthUtf16,
  required int targetOffsetUtf16,
  required String selectedText,
  required EditorTextDropOperation operation,
}) {
  final sourceLength = source.lengthUtf16;
  if (source.documentId != targetDocumentId ||
      source.documentVersion != targetDocumentVersion ||
      targetDocumentVersion <= 0 ||
      source.startUtf16 < 0 ||
      source.endUtf16 > targetDocumentLengthUtf16 ||
      targetOffsetUtf16 < 0 ||
      targetOffsetUtf16 > targetDocumentLengthUtf16 ||
      sourceLength <= 0 ||
      sourceLength > maxEditorTextDragUtf16 ||
      selectedText.length != sourceLength) {
    return null;
  }

  final targetInsideSource = targetOffsetUtf16 > source.startUtf16 &&
      targetOffsetUtf16 < source.endUtf16;
  if (targetInsideSource) return null;

  if (operation == EditorTextDropOperation.copy) {
    return EditorTextDragEditPlan(
      forward: [TextOp.insert(targetOffsetUtf16, selectedText)],
      inverse: [TextOp.delete(targetOffsetUtf16, sourceLength)],
      insertOffsetUtf16: targetOffsetUtf16,
      afterCaretUtf16: targetOffsetUtf16 + sourceLength,
      resultLengthUtf16: targetDocumentLengthUtf16 + sourceLength,
    );
  }

  if (targetOffsetUtf16 == source.startUtf16 ||
      targetOffsetUtf16 == source.endUtf16) {
    return null;
  }

  final insertOffset = targetOffsetUtf16 < source.startUtf16
      ? targetOffsetUtf16
      : targetOffsetUtf16 - sourceLength;
  final forward = targetOffsetUtf16 < source.startUtf16
      ? <TextOp>[
          TextOp.insert(insertOffset, selectedText),
          TextOp.delete(source.startUtf16 + sourceLength, sourceLength),
        ]
      : <TextOp>[
          TextOp.delete(source.startUtf16, sourceLength),
          TextOp.insert(insertOffset, selectedText),
        ];
  return EditorTextDragEditPlan(
    forward: forward,
    inverse: [
      TextOp.delete(insertOffset, sourceLength),
      TextOp.insert(source.startUtf16, selectedText),
    ],
    insertOffsetUtf16: insertOffset,
    afterCaretUtf16: insertOffset + sourceLength,
    resultLengthUtf16: targetDocumentLengthUtf16,
  );
}
