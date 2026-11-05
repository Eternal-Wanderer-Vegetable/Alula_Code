/// Validation and UTF-16 range planning for atomic multi-document edits.
library;

import '../bridge/alula_core.dart';

class WorkspaceTextPosition {
  const WorkspaceTextPosition(this.line, this.character);

  final int line;
  final int character;
}

class WorkspaceTextRange {
  const WorkspaceTextRange({required this.start, required this.end});

  final WorkspaceTextPosition start;
  final WorkspaceTextPosition end;
}

class WorkspaceTextEdit {
  const WorkspaceTextEdit({required this.range, required this.newText});

  final WorkspaceTextRange range;
  final String newText;
}

class WorkspaceDocumentEdit {
  const WorkspaceDocumentEdit({
    required this.uri,
    required this.edits,
    this.version,
  });

  final String uri;
  final int? version;
  final List<WorkspaceTextEdit> edits;
}

class WorkspaceEdit {
  const WorkspaceEdit(this.documents, {this.transactionId});

  final List<WorkspaceDocumentEdit> documents;
  final String? transactionId;
}

class WorkspaceDocumentSnapshot {
  const WorkspaceDocumentSnapshot({
    required this.id,
    required this.uri,
    required this.version,
    required this.text,
    this.writable = true,
  });

  final int id;
  final String uri;
  final int version;
  final String text;
  final bool writable;
}

class PlannedWorkspaceDocumentEdit {
  const PlannedWorkspaceDocumentEdit({
    required this.id,
    required this.uri,
    required this.baseVersion,
    required this.before,
    required this.after,
    required this.ops,
  });

  final int id;
  final String uri;
  final int baseVersion;
  final String before;
  final String after;
  final List<TextOp> ops;
}

class WorkspaceEditPlan {
  const WorkspaceEditPlan(
      {required this.transactionId, required this.documents});

  final String transactionId;
  final List<PlannedWorkspaceDocumentEdit> documents;
}

class WorkspaceEditException implements Exception {
  const WorkspaceEditException(this.message);

  final String message;

  @override
  String toString() => 'WorkspaceEditException: $message';
}

class _ResolvedEdit {
  const _ResolvedEdit(this.start, this.end, this.newText);

  final int start;
  final int end;
  final String newText;
}

class _TextIndex {
  _TextIndex(this.text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        contentEnds.add(i > 0 && text.codeUnitAt(i - 1) == 0x0D ? i - 1 : i);
        lineStarts.add(i + 1);
      }
    }
    contentEnds.add(text.length);
  }

  final String text;
  final List<int> lineStarts = [0];
  final List<int> contentEnds = [];

  int offset(WorkspaceTextPosition position) {
    if (position.line < 0 || position.line >= lineStarts.length) {
      throw WorkspaceEditException('Line is out of bounds: ${position.line}.');
    }
    if (position.character < 0) {
      throw WorkspaceEditException(
        'Character is out of bounds: ${position.character}.',
      );
    }
    final lineStart = lineStarts[position.line];
    final lineEnd = contentEnds[position.line];
    final result = lineStart + position.character;
    if (result > lineEnd || result > text.length) {
      throw WorkspaceEditException(
        'Character ${position.character} exceeds line ${position.line}.',
      );
    }
    return result;
  }
}

class WorkspaceEditPlanner {
  const WorkspaceEditPlanner();

  WorkspaceEditPlan plan(
    WorkspaceEdit edit,
    Iterable<WorkspaceDocumentSnapshot> snapshots,
  ) {
    if (edit.documents.isEmpty) {
      throw const WorkspaceEditException('The edit has no text documents.');
    }
    final byUri = <String, WorkspaceDocumentSnapshot>{};
    for (final snapshot in snapshots) {
      if (byUri.containsKey(snapshot.uri)) {
        throw WorkspaceEditException('Duplicate open URI: ${snapshot.uri}');
      }
      byUri[snapshot.uri] = snapshot;
    }

    final seenUris = <String>{};
    final planned = <PlannedWorkspaceDocumentEdit>[];
    for (final document in edit.documents) {
      if (!seenUris.add(document.uri)) {
        throw WorkspaceEditException('Duplicate edit URI: ${document.uri}');
      }
      final snapshot = byUri[document.uri];
      if (snapshot == null) {
        throw WorkspaceEditException('Document is not open: ${document.uri}');
      }
      if (!snapshot.writable) {
        throw WorkspaceEditException('Document is read-only: ${document.uri}');
      }
      if (document.version != null && document.version != snapshot.version) {
        throw WorkspaceEditException(
          'Version mismatch for ${document.uri}: '
          'edit v${document.version}, open v${snapshot.version}.',
        );
      }
      final index = _TextIndex(snapshot.text);
      final resolved = document.edits
          .map((textEdit) => _resolve(index, textEdit))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      _validateNonOverlapping(document.uri, resolved);
      if (resolved.isEmpty ||
          resolved.every(
              (item) => item.start == item.end && item.newText.isEmpty)) {
        continue;
      }
      planned.add(PlannedWorkspaceDocumentEdit(
        id: snapshot.id,
        uri: snapshot.uri,
        baseVersion: snapshot.version,
        before: snapshot.text,
        after: _applyResolved(snapshot.text, resolved),
        ops: _toOps(resolved),
      ));
    }
    if (planned.isEmpty) {
      throw const WorkspaceEditException('The edit contains no changes.');
    }
    return WorkspaceEditPlan(
      transactionId: edit.transactionId ?? _newTransactionId(),
      documents: List.unmodifiable(planned),
    );
  }

  _ResolvedEdit _resolve(_TextIndex index, WorkspaceTextEdit edit) {
    final start = index.offset(edit.range.start);
    final end = index.offset(edit.range.end);
    if (start > end) {
      throw const WorkspaceEditException(
          'Range start must not follow its end.');
    }
    if (!_isCodePointBoundary(index.text, start) ||
        !_isCodePointBoundary(index.text, end)) {
      throw const WorkspaceEditException(
        'Range splits a UTF-16 surrogate pair.',
      );
    }
    return _ResolvedEdit(start, end, edit.newText);
  }

  bool _isCodePointBoundary(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return true;
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return !(before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF);
  }

  void _validateNonOverlapping(String uri, List<_ResolvedEdit> edits) {
    for (var i = 1; i < edits.length; i++) {
      final previous = edits[i - 1];
      final current = edits[i];
      final overlap = current.start < previous.end ||
          (current.start == previous.start &&
              (current.start == current.end || previous.start == previous.end));
      if (overlap) {
        throw WorkspaceEditException('Overlapping edits for $uri.');
      }
    }
  }

  String _applyResolved(String text, List<_ResolvedEdit> edits) {
    final output = StringBuffer();
    var cursor = 0;
    for (final edit in edits) {
      output
        ..write(text.substring(cursor, edit.start))
        ..write(edit.newText);
      cursor = edit.end;
    }
    output.write(text.substring(cursor));
    return output.toString();
  }

  List<TextOp> _toOps(List<_ResolvedEdit> edits) {
    final descending = edits.reversed;
    final ops = <TextOp>[];
    for (final edit in descending) {
      final length = edit.end - edit.start;
      if (length > 0) ops.add(TextOp.delete(edit.start, length));
      if (edit.newText.isNotEmpty) {
        ops.add(TextOp.insert(edit.start, edit.newText));
      }
    }
    return List.unmodifiable(ops);
  }

  static String _newTransactionId() =>
      'workspace-${DateTime.now().microsecondsSinceEpoch}-${_transactionSequence++}';

  static int _transactionSequence = 0;
}

int mapWorkspaceEditOffset(int offset, List<TextOp> descendingOps) {
  // The plan's operations are descending, but selection mapping is easiest
  // when their original-document ranges are processed in ascending order.
  final edits = <({int start, int end, String inserted})>[];
  for (var i = 0; i < descendingOps.length;) {
    final op = descendingOps[i];
    if (op.type == OpType.delete) {
      final next = i + 1 < descendingOps.length ? descendingOps[i + 1] : null;
      final inserted = next != null &&
              next.type == OpType.insert &&
              next.offsetUtf16 == op.offsetUtf16
          ? (next.text ?? '')
          : '';
      edits.add((
        start: op.offsetUtf16,
        end: op.offsetUtf16 + (op.lenUtf16 ?? 0),
        inserted: inserted,
      ));
      i += inserted.isNotEmpty ? 2 : 1;
    } else {
      edits.add((
        start: op.offsetUtf16,
        end: op.offsetUtf16,
        inserted: op.text ?? '',
      ));
      i++;
    }
  }
  edits.sort((a, b) => a.start.compareTo(b.start));
  var delta = 0;
  for (final edit in edits) {
    if (offset < edit.start) break;
    final mappedStart = edit.start + delta;
    if (offset <= edit.end) return mappedStart + edit.inserted.length;
    delta += edit.inserted.length - (edit.end - edit.start);
  }
  return offset + delta;
}
