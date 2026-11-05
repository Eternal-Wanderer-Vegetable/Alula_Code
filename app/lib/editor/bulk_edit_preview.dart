/// Bounded, GUI-free selection state for a text-only WorkspaceEdit preview.
library;

import 'workspace_edit.dart';

enum BulkEditPreviewSelectionState { none, some, all }

class BulkEditPreviewException implements Exception {
  const BulkEditPreviewException(this.message);

  final String message;

  @override
  String toString() => 'BulkEditPreviewException: $message';
}

class BulkEditPreviewEditState {
  const BulkEditPreviewEditState({
    required this.documentIndex,
    required this.editIndex,
    required this.edit,
    required this.isSelected,
  });

  final int documentIndex;
  final int editIndex;
  final WorkspaceTextEdit edit;
  final bool isSelected;
}

class BulkEditPreviewDocumentState {
  const BulkEditPreviewDocumentState({
    required this.documentIndex,
    required this.uri,
    required this.version,
    required this.selectedEditCount,
    required this.selectionState,
    required this.edits,
  });

  final int documentIndex;
  final String uri;
  final int? version;
  final int selectedEditCount;
  final BulkEditPreviewSelectionState selectionState;
  final List<BulkEditPreviewEditState> edits;
}

/// A temporary selection snapshot. It owns a deep immutable copy of the input
/// edit lists and does not retain document text or register a listener.
class BulkEditPreviewSession {
  BulkEditPreviewSession(WorkspaceEdit source) {
    if (source.documents.isEmpty) {
      throw const BulkEditPreviewException(
        'The preview has no text documents.',
      );
    }
    if (source.documents.length > maxDocuments) {
      throw const BulkEditPreviewException(
        'The preview exceeds the document limit.',
      );
    }

    var editCount = 0;
    var byteCount = source.transactionId == null
        ? 0
        : _boundedUtf8Length(source.transactionId!, maxInputUtf8Bytes);
    if (byteCount > maxInputUtf8Bytes) {
      throw const BulkEditPreviewException(
        'The preview exceeds the UTF-8 input byte limit.',
      );
    }
    final seenUris = <String>{};
    final frozenDocuments = <_PreviewDocument>[];
    final selected = <List<bool>>[];

    for (final document in source.documents) {
      if (!seenUris.add(document.uri)) {
        throw BulkEditPreviewException(
          'The preview contains a duplicate URI: ${document.uri}',
        );
      }
      byteCount += _boundedUtf8Length(document.uri, maxInputUtf8Bytes);
      if (byteCount > maxInputUtf8Bytes) {
        throw const BulkEditPreviewException(
          'The preview exceeds the UTF-8 input byte limit.',
        );
      }

      editCount += document.edits.length;
      if (editCount > maxEdits) {
        throw const BulkEditPreviewException(
          'The preview exceeds the text edit limit.',
        );
      }

      final frozenEdits = <WorkspaceTextEdit>[];
      for (final edit in document.edits) {
        byteCount += _boundedUtf8Length(
          edit.newText,
          maxInputUtf8Bytes - byteCount,
        );
        if (byteCount > maxInputUtf8Bytes) {
          throw const BulkEditPreviewException(
            'The preview exceeds the UTF-8 input byte limit.',
          );
        }
        frozenEdits.add(_freezeTextEdit(edit));
      }
      frozenDocuments.add(
        _PreviewDocument(
          uri: document.uri,
          version: document.version,
          edits: List.unmodifiable(frozenEdits),
        ),
      );
      selected.add(List<bool>.filled(frozenEdits.length, true));
    }

    _documents = List.unmodifiable(frozenDocuments);
    _selected = selected;
    transactionId = source.transactionId;
    _selectedEditCount = editCount;
  }

  static const int maxDocuments = 2048;
  static const int maxEdits = 32768;
  static const int maxInputUtf8Bytes = 8 * 1024 * 1024;

  late final List<_PreviewDocument> _documents;
  late final List<List<bool>> _selected;
  late final String? transactionId;
  int _selectedEditCount = 0;
  int _revision = 0;

  int get revision => _revision;
  int get selectedEditCount => _selectedEditCount;
  int get editCount =>
      _selected.fold<int>(0, (sum, edits) => sum + edits.length);
  bool get hasSelection => _selectedEditCount > 0;

  BulkEditPreviewSelectionState get selectionState =>
      _selectionState(_selectedEditCount, editCount);

  List<BulkEditPreviewDocumentState> get documents => List.unmodifiable([
        for (var documentIndex = 0;
            documentIndex < _documents.length;
            documentIndex++)
          _documentState(documentIndex),
      ]);

  BulkEditPreviewSelectionState selectionStateForDocument(int documentIndex) {
    _checkDocumentIndex(documentIndex);
    return _selectionState(
      _selected[documentIndex].where((selected) => selected).length,
      _selected[documentIndex].length,
    );
  }

  bool isEditSelected(int documentIndex, int editIndex) {
    _checkEditIndex(documentIndex, editIndex);
    return _selected[documentIndex][editIndex];
  }

  /// Sets one edit's selection. Returns false when the state was unchanged.
  bool setEditSelected(int documentIndex, int editIndex, bool isSelected) {
    _checkEditIndex(documentIndex, editIndex);
    final previous = _selected[documentIndex][editIndex];
    if (previous == isSelected) return false;

    _selected[documentIndex][editIndex] = isSelected;
    _selectedEditCount += isSelected ? 1 : -1;
    _revision++;
    return true;
  }

  /// Applies one selection value to every edit in a document.
  bool setDocumentSelected(int documentIndex, bool isSelected) {
    _checkDocumentIndex(documentIndex);
    var changed = false;
    for (var editIndex = 0;
        editIndex < _selected[documentIndex].length;
        editIndex++) {
      if (_selected[documentIndex][editIndex] == isSelected) continue;
      _selected[documentIndex][editIndex] = isSelected;
      _selectedEditCount += isSelected ? 1 : -1;
      changed = true;
    }
    if (changed) _revision++;
    return changed;
  }

  /// Inverts every edit in one document as a single selection revision.
  bool invertDocumentSelection(int documentIndex) {
    _checkDocumentIndex(documentIndex);
    final edits = _selected[documentIndex];
    if (edits.isEmpty) return false;
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      edits[editIndex] = !edits[editIndex];
      _selectedEditCount += edits[editIndex] ? 1 : -1;
    }
    _revision++;
    return true;
  }

  bool selectAll() => _setAllSelected(true);

  bool clearAll() => _setAllSelected(false);

  /// Returns a filtered immutable edit while preserving input order and
  /// document metadata. An empty selection is not an applicable edit.
  WorkspaceEdit toWorkspaceEdit() {
    if (!hasSelection) {
      throw const BulkEditPreviewException(
        'Select at least one text edit before applying the preview.',
      );
    }

    final documents = <WorkspaceDocumentEdit>[];
    for (var documentIndex = 0;
        documentIndex < _documents.length;
        documentIndex++) {
      final source = _documents[documentIndex];
      final edits = <WorkspaceTextEdit>[];
      for (var editIndex = 0; editIndex < source.edits.length; editIndex++) {
        if (_selected[documentIndex][editIndex]) {
          edits.add(source.edits[editIndex]);
        }
      }
      if (edits.isEmpty) continue;
      documents.add(
        WorkspaceDocumentEdit(
          uri: source.uri,
          version: source.version,
          edits: List.unmodifiable(edits),
        ),
      );
    }
    return WorkspaceEdit(
      List.unmodifiable(documents),
      transactionId: transactionId,
    );
  }

  bool _setAllSelected(bool isSelected) {
    var changed = false;
    for (var documentIndex = 0;
        documentIndex < _selected.length;
        documentIndex++) {
      for (var editIndex = 0;
          editIndex < _selected[documentIndex].length;
          editIndex++) {
        if (_selected[documentIndex][editIndex] == isSelected) continue;
        _selected[documentIndex][editIndex] = isSelected;
        _selectedEditCount += isSelected ? 1 : -1;
        changed = true;
      }
    }
    if (changed) _revision++;
    return changed;
  }

  BulkEditPreviewDocumentState _documentState(int documentIndex) {
    final document = _documents[documentIndex];
    final selected = _selected[documentIndex];
    final selectedCount = selected.where((value) => value).length;
    return BulkEditPreviewDocumentState(
      documentIndex: documentIndex,
      uri: document.uri,
      version: document.version,
      selectedEditCount: selectedCount,
      selectionState: _selectionState(selectedCount, selected.length),
      edits: List.unmodifiable([
        for (var editIndex = 0; editIndex < document.edits.length; editIndex++)
          BulkEditPreviewEditState(
            documentIndex: documentIndex,
            editIndex: editIndex,
            edit: document.edits[editIndex],
            isSelected: selected[editIndex],
          ),
      ]),
    );
  }

  void _checkDocumentIndex(int documentIndex) {
    RangeError.checkValidIndex(documentIndex, _documents, 'documentIndex');
  }

  void _checkEditIndex(int documentIndex, int editIndex) {
    _checkDocumentIndex(documentIndex);
    RangeError.checkValidIndex(
      editIndex,
      _documents[documentIndex].edits,
      'editIndex',
    );
  }

  static BulkEditPreviewSelectionState _selectionState(
    int selectedCount,
    int totalCount,
  ) {
    if (selectedCount == 0 || totalCount == 0) {
      return BulkEditPreviewSelectionState.none;
    }
    if (selectedCount == totalCount) {
      return BulkEditPreviewSelectionState.all;
    }
    return BulkEditPreviewSelectionState.some;
  }

  static WorkspaceTextEdit _freezeTextEdit(WorkspaceTextEdit edit) =>
      WorkspaceTextEdit(
        range: WorkspaceTextRange(
          start: WorkspaceTextPosition(
            edit.range.start.line,
            edit.range.start.character,
          ),
          end: WorkspaceTextPosition(
            edit.range.end.line,
            edit.range.end.character,
          ),
        ),
        newText: edit.newText,
      );

  static int _boundedUtf8Length(String value, int limit) {
    var bytes = 0;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit <= 0x7F) {
        bytes++;
      } else if (unit <= 0x7FF) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= value.length) {
          throw const BulkEditPreviewException(
            'The preview contains malformed UTF-16 text.',
          );
        }
        final low = value.codeUnitAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
          throw const BulkEditPreviewException(
            'The preview contains malformed UTF-16 text.',
          );
        }
        bytes += 4;
        index++;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw const BulkEditPreviewException(
          'The preview contains malformed UTF-16 text.',
        );
      } else {
        bytes += 3;
      }
      if (bytes > limit) return bytes;
    }
    return bytes;
  }
}

class _PreviewDocument {
  const _PreviewDocument({
    required this.uri,
    required this.version,
    required this.edits,
  });

  final String uri;
  final int? version;
  final List<WorkspaceTextEdit> edits;
}
