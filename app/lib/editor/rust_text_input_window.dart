import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'text_diff.dart';

/// A hard upper bound on the text Flutter may mirror while editing one window.
const int maxRustTextInputWindowUtf16 = maxDocReadRangeUtf16;

/// A bounded Flutter-side input mirror backed by the Rust-authoritative doc.
///
/// Flutter owns the current selection and IME composing range. Each accepted
/// value is diffed only against this bounded window and committed values are
/// sent to Rust as UTF-16 [TextOp]s. Active IME preedit text stays as a Flutter
/// overlay until commit. [enqueue] provides a one-slot writeback queue: newer complete
/// editing values replace a pending value, so input bursts cannot grow an
/// unbounded queue. The host widget must schedule [flushPending] and flush
/// before save/close.
class RustTextInputWindow {
  RustTextInputWindow._({
    required this.document,
    required this.maxWindowUtf16,
    required this.compositionReserveUtf16,
    required TextRangeRead initialRange,
    required TextSelection initialSelection,
  })  : _startUtf16 = initialRange.startUtf16,
        _totalUtf16Length = initialRange.totalUtf16Length,
        _version = initialRange.version,
        _text = initialRange.text,
        _presentedText = initialRange.text,
        _committedSelectionWindow = TextSelection(
          baseOffset: (initialSelection.baseOffset - initialRange.startUtf16)
              .clamp(0, initialRange.text.length)
              .toInt(),
          extentOffset:
              (initialSelection.extentOffset - initialRange.startUtf16)
                  .clamp(0, initialRange.text.length)
                  .toInt(),
          affinity: initialSelection.affinity,
          isDirectional: initialSelection.isDirectional,
        );

  /// Reads at most [maxWindowUtf16] UTF-16 units from Rust.
  ///
  /// The range request reserves one unit for a surrogate-pair boundary. This
  /// keeps the returned mirror within the requested hard limit even when Rust
  /// expands a range by one unit to avoid splitting a scalar value.
  factory RustTextInputWindow.open(
    AlulaDoc document, {
    required int startUtf16,
    int maxWindowUtf16 = 8192,
    int compositionReserveUtf16 = 0,
    int? selectionUtf16,
    TextSelection? selection,
  }) {
    if (maxWindowUtf16 < 2 || maxWindowUtf16 > maxRustTextInputWindowUtf16) {
      throw ArgumentError.value(
        maxWindowUtf16,
        'maxWindowUtf16',
        'must be between 2 and $maxRustTextInputWindowUtf16',
      );
    }
    if (compositionReserveUtf16 < 0 ||
        compositionReserveUtf16 >= maxWindowUtf16 - 1) {
      throw ArgumentError.value(
        compositionReserveUtf16,
        'compositionReserveUtf16',
        'must leave at least one UTF-16 unit for the initial range',
      );
    }
    final range = document.readRange(
      startUtf16,
      maxLenUtf16: maxWindowUtf16 - compositionReserveUtf16 - 1,
    );
    if (range.text.length > maxWindowUtf16) {
      throw StateError('Rust returned a text window beyond its requested cap');
    }
    return RustTextInputWindow._(
      document: document,
      maxWindowUtf16: maxWindowUtf16,
      compositionReserveUtf16: compositionReserveUtf16,
      initialRange: range,
      initialSelection: selection ??
          TextSelection.collapsed(
            offset: selectionUtf16 ?? (range.startUtf16 + range.text.length),
          ),
    );
  }

  /// Opens a bounded window centered on an absolute caret or selection extent.
  factory RustTextInputWindow.openAround(
    AlulaDoc document, {
    required int selectionUtf16,
    int maxWindowUtf16 = 8192,
    int compositionReserveUtf16 = 0,
    TextSelection? selection,
  }) {
    final caret = selectionUtf16 < 0 ? 0 : selectionUtf16;
    final startUtf16 =
        caret > maxWindowUtf16 ~/ 2 ? caret - (maxWindowUtf16 ~/ 2) : 0;
    return RustTextInputWindow.open(
      document,
      startUtf16: startUtf16,
      maxWindowUtf16: maxWindowUtf16,
      compositionReserveUtf16: compositionReserveUtf16,
      selectionUtf16: caret,
      selection: selection,
    );
  }

  final AlulaDoc document;
  final int maxWindowUtf16;
  final int compositionReserveUtf16;
  int _startUtf16;
  int _totalUtf16Length;
  int _version;
  String _text;
  String _presentedText;
  TextSelection _committedSelectionWindow;
  TextEditingValue? _composingValue;
  TextEditingValue? _pending;
  List<TextOp> _pendingAdditionalOperations = const [];
  int _coalescedInputCount = 0;

  int get startUtf16 => _startUtf16;
  int get endUtf16 => _startUtf16 + _text.length;
  int get totalUtf16Length => _totalUtf16Length;
  int get version => _version;

  /// Last Flutter-visible text, including an uncommitted IME composition.
  String get presentedText => _presentedText;

  /// Rust-committed text in this input window.
  String get text => _text;
  int get pendingCount => _pending == null ? 0 : 1;
  int get coalescedInputCount => _coalescedInputCount;
  String? get pendingText => _pending?.text ?? _composingValue?.text;
  bool get hasComposition =>
      _composingValue != null ||
      (_pending != null && _hasComposition(_pending!.composing));

  /// Initial editable value with the caret at the end of this window.
  TextEditingValue get initialValue => TextEditingValue(
        text: _text,
        selection: _committedSelectionWindow,
      );

  /// Reuses this mirror object after a host edit replaces a document range.
  ///
  /// Text input formatters and the platform text-input client can still hold a
  /// reference to this window until the next widget build, so updating it in
  /// place lets that same input transaction observe the new bounded snapshot.
  /// Only an active composition overlay may be discarded; committed pending
  /// edits must be flushed before the host calls this method.
  void refreshAround(int selectionUtf16, {TextSelection? selection}) {
    final pending = _pending;
    if (pending != null && !_hasComposition(pending.composing)) {
      throw StateError(
          'Flush committed input before refreshing the input window');
    }
    final refreshed = RustTextInputWindow.openAround(
      document,
      selectionUtf16: selectionUtf16,
      maxWindowUtf16: maxWindowUtf16,
      compositionReserveUtf16: compositionReserveUtf16,
      selection: selection ?? TextSelection.collapsed(offset: selectionUtf16),
    );
    _startUtf16 = refreshed._startUtf16;
    _totalUtf16Length = refreshed._totalUtf16Length;
    _version = refreshed._version;
    _text = refreshed._text;
    _presentedText = refreshed._presentedText;
    _committedSelectionWindow = refreshed._committedSelectionWindow;
    _composingValue = null;
    _pending = null;
    _pendingAdditionalOperations = const [];
    _coalescedInputCount = 0;
  }

  /// Immediately writes one complete Flutter value to Rust.
  RustTextInputDelta applyImmediate(TextEditingValue value) {
    if (_pending != null) {
      throw StateError(
          'Flush the pending input value before applying directly');
    }
    return _apply(value);
  }

  /// Retains only the newest complete editing value until [flushPending].
  ///
  /// This coalesces Rust writeback, not Flutter's platform text-input state:
  /// the EditableText/IME connection still receives each native update.
  void enqueue(
    TextEditingValue value, {
    List<TextOp> additionalOperations = const [],
  }) {
    _validateWindowLength(value.text);
    if (_pending != null) _coalescedInputCount++;
    _pending = value;
    if (additionalOperations.isNotEmpty ||
        _pendingAdditionalOperations.isEmpty) {
      _pendingAdditionalOperations = List.unmodifiable(additionalOperations);
    }
  }

  /// Applies the newest queued value, or returns null when the slot is empty.
  /// Failed writes stay pending so the caller can recover or retry explicitly.
  RustTextInputDelta? flushPending() {
    final pending = _pending;
    if (pending == null) return null;
    final delta = _apply(
      pending,
      additionalOperations: _pendingAdditionalOperations,
    );
    _pending = null;
    _pendingAdditionalOperations = const [];
    return delta;
  }

  /// Commits a platform paste that is larger than the editable mirror.
  ///
  /// The platform may briefly present a value larger than this window. Rust
  /// receives the resulting bounded-window diff immediately, then the caller
  /// replaces the platform value with the refreshed bounded window. Failed
  /// writes retain the one pending draft so the user can retry or copy it.
  RustTextInputDelta applyOversized(
    TextEditingValue value, {
    List<TextOp> additionalOperations = const [],
  }) {
    if (value.text.length <= maxWindowUtf16) {
      throw ArgumentError.value(value.text.length, 'value.text.length',
          'must exceed the input window limit');
    }
    try {
      if (_hasComposition(value.composing)) {
        _pending = value;
        _presentedText = value.text;
        throw TextInputWindowLimitException(
          maxUtf16: maxWindowUtf16,
          receivedUtf16: value.text.length,
        );
      }
      final delta = _apply(
        value,
        allowOversized: true,
        additionalOperations: additionalOperations,
      );
      _pending = null;
      _pendingAdditionalOperations = const [];
      return delta;
    } catch (_) {
      _pending = value;
      _pendingAdditionalOperations = List.unmodifiable(additionalOperations);
      _presentedText = value.text;
      rethrow;
    }
  }

  /// Replays pending input after a version conflict only when the authoritative
  /// Rust text in this exact window still matches the acknowledged base text.
  /// Edits elsewhere can then advance the version without risking an overlap.
  RustTextInputDelta? recoverPending() {
    final pending = _pending;
    if (pending == null) return null;
    final value = _hasComposition(pending.composing)
        ? pending.copyWith(composing: TextRange.empty)
        : pending;
    final latest = document.readRange(
      _startUtf16,
      maxLenUtf16: maxWindowUtf16 - 1,
    );
    final coordinatesStable =
        _startUtf16 == 0 || latest.totalUtf16Length == _totalUtf16Length;
    if (!coordinatesStable ||
        latest.startUtf16 != _startUtf16 ||
        latest.text != _text) {
      throw const InputWindowRecoveryConflictException(
        'Rust text in the pending edit window has changed; the local draft '
        'was kept for copying.',
      );
    }

    _version = latest.version;
    _totalUtf16Length = latest.totalUtf16Length;
    final delta = _apply(
      value,
      allowOversized: value.text.length > maxWindowUtf16,
      additionalOperations: _pendingAdditionalOperations,
    );
    _pending = null;
    _pendingAdditionalOperations = const [];
    return delta;
  }

  /// Commits the current preedit text before save or focus transfer.
  ///
  /// A queued non-composing value is already the platform's commit event and
  /// is applied as-is. Otherwise the most recent composing snapshot is sent to
  /// Rust with an empty composing range.
  RustTextInputDelta? commitComposition() {
    final pending = _pending;
    if (pending != null && !_hasComposition(pending.composing)) {
      return flushPending();
    }
    final composingValue = pending ?? _composingValue;
    if (composingValue == null) return null;
    _pending = null;
    try {
      return _apply(composingValue.copyWith(composing: TextRange.empty));
    } catch (_) {
      _pending = composingValue;
      rethrow;
    }
  }

  /// Drops the preedit overlay and returns the committed Flutter value.
  RustTextInputDelta? cancelComposition() {
    final pending = _pending;
    if (pending != null && !_hasComposition(pending.composing)) {
      return flushPending();
    }
    if (_composingValue == null && pending == null) return null;
    _pending = null;
    _pendingAdditionalOperations = const [];
    _composingValue = null;
    _presentedText = _text;
    final selection = _mapSelection(_committedSelectionWindow, _text);
    return RustTextInputDelta(
      operations: const [],
      version: _version,
      documentLengthUtf16: _totalUtf16Length,
      selection: selection,
      selectionWindow: _committedSelectionWindow,
      composingWindow: null,
      replacedDocumentRange: null,
      replacementValue: TextEditingValue(
        text: _text,
        selection: _committedSelectionWindow,
      ),
    );
  }

  RustTextInputDelta _apply(
    TextEditingValue value, {
    bool allowOversized = false,
    List<TextOp> additionalOperations = const [],
  }) {
    if (!allowOversized) _validateWindowLength(value.text);
    final previousSelection = _mapSelection(_committedSelectionWindow, _text);
    final localOps = diffToOps(_text, value.text);
    final selectionWindow = _mapWindowSelection(value.selection, value.text);
    final composingWindow = _mapComposingWindow(value.composing, value.text);

    if (_hasComposition(value.composing)) {
      if (additionalOperations.isNotEmpty) {
        throw StateError('Multi-selection edits cannot commit during preedit');
      }
      final replacedRange =
          _compositionReplacementRange(localOps, composingWindow!);
      _presentedText = value.text;
      _composingValue = value;
      return RustTextInputDelta(
        operations: const [],
        version: _version,
        documentLengthUtf16: _totalUtf16Length,
        selection: null,
        selectionWindow: selectionWindow,
        composingWindow: composingWindow,
        replacedDocumentRange: replacedRange,
      );
    }

    final ops = [
      ..._toDocumentOps(localOps),
      ...additionalOperations,
    ]..sort(_compareDocumentOpsDescending);
    final editGroups = <int, _MutableTextEditGroup>{};
    for (final op in ops) {
      final group = editGroups.putIfAbsent(
        op.offsetUtf16,
        _MutableTextEditGroup.new,
      );
      switch (op.type) {
        case OpType.delete:
          group.deletedLength += op.lenUtf16!;
          break;
        case OpType.insert:
          group.insertedText += op.text!;
          break;
      }
    }
    final editOffsets = editGroups.keys.toList()..sort();
    final edits = <_TextEditGroup>[];
    for (final offset in editOffsets) {
      final group = editGroups[offset]!;
      final deletedText = group.deletedLength == 0
          ? ''
          : document.readRange(offset, maxLenUtf16: group.deletedLength).text;
      if (deletedText.length != group.deletedLength) {
        throw StateError('A multi-selection edit split a UTF-16 scalar');
      }
      edits.add(_TextEditGroup(offset, deletedText, group.insertedText));
    }
    final inverseOps = <TextOp>[];
    var nextLength = _totalUtf16Length;
    var inputWindowShift = 0;
    for (final edit in edits) {
      final lengthDelta = edit.insertedText.length - edit.deletedText.length;
      nextLength += lengthDelta;
      if (edit.offsetUtf16 < _startUtf16) inputWindowShift += lengthDelta;
      if (edit.insertedText.isNotEmpty) {
        inverseOps
            .add(TextOp.delete(edit.offsetUtf16, edit.insertedText.length));
      }
      if (edit.deletedText.isNotEmpty) {
        inverseOps.add(TextOp.insert(edit.offsetUtf16, edit.deletedText));
      }
    }
    if (nextLength < 0) {
      throw StateError(
          'Input window edit would produce a negative document length');
    }

    // Keep the snapshot unchanged if FFI rejects a stale version or invalid op.
    final nextVersion =
        ops.isEmpty ? _version : document.applyWith(_version, ops);

    _composingValue = null;
    _version = nextVersion;
    _totalUtf16Length = nextLength;
    _startUtf16 = (_startUtf16 + inputWindowShift).clamp(0, nextLength).toInt();
    final oversized = value.text.length > maxWindowUtf16;
    final mappedSelection = _mapSelection(value.selection, value.text);
    final absoluteSelection = mappedSelection == null
        ? null
        : TextSelection(
            baseOffset: (mappedSelection.baseOffset + inputWindowShift)
                .clamp(0, nextLength)
                .toInt(),
            extentOffset: (mappedSelection.extentOffset + inputWindowShift)
                .clamp(0, nextLength)
                .toInt(),
            affinity: mappedSelection.affinity,
            isDirectional: mappedSelection.isDirectional,
          );
    if (oversized) {
      _refreshWindowAround(absoluteSelection?.extentOffset ?? _startUtf16,
          absoluteSelection: absoluteSelection);
    } else {
      _text = value.text;
      _presentedText = value.text;
      if (selectionWindow != null) {
        _committedSelectionWindow = selectionWindow;
      }
    }
    final resultSelectionWindow =
        oversized ? _committedSelectionWindow : selectionWindow;
    return RustTextInputDelta(
      operations: List<TextOp>.unmodifiable(ops),
      version: nextVersion,
      documentLengthUtf16: nextLength,
      selection: absoluteSelection,
      selectionWindow: resultSelectionWindow,
      composingWindow: null,
      replacedDocumentRange: null,
      inverseOperations: List<TextOp>.unmodifiable(inverseOps),
      previousSelection: previousSelection,
      replacementValue: oversized
          ? TextEditingValue(
              text: _text,
              selection: _committedSelectionWindow,
            )
          : null,
    );
  }

  void _refreshWindowAround(
    int selectionUtf16, {
    required TextSelection? absoluteSelection,
  }) {
    final caret = selectionUtf16.clamp(0, _totalUtf16Length).toInt();
    final start = caret > maxWindowUtf16 ~/ 2 ? caret - maxWindowUtf16 ~/ 2 : 0;
    final range = document.readRange(
      start,
      maxLenUtf16: maxWindowUtf16 - compositionReserveUtf16 - 1,
    );
    _startUtf16 = range.startUtf16;
    _totalUtf16Length = range.totalUtf16Length;
    _version = range.version;
    _text = range.text;
    _presentedText = range.text;
    final selection =
        absoluteSelection ?? TextSelection.collapsed(offset: caret);
    _committedSelectionWindow = TextSelection(
      baseOffset: _snapOffsetBeforeSurrogate(
        range.text,
        selection.baseOffset - range.startUtf16,
      ),
      extentOffset: _snapOffsetBeforeSurrogate(
        range.text,
        selection.extentOffset - range.startUtf16,
      ),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  List<TextOp> _toDocumentOps(List<TextOp> localOps) => localOps.map((op) {
        final absoluteOffset = _startUtf16 + op.offsetUtf16;
        return switch (op.type) {
          OpType.insert => TextOp.insert(absoluteOffset, op.text!),
          OpType.delete => TextOp.delete(absoluteOffset, op.lenUtf16!),
        };
      }).toList(growable: false);

  TextRange _compositionReplacementRange(
    List<TextOp> localOps,
    TextRange composingWindow,
  ) {
    if (localOps.isEmpty) {
      return TextRange(
        start: _startUtf16 + composingWindow.start,
        end: _startUtf16 + composingWindow.end,
      );
    }
    final offset = localOps.first.offsetUtf16;
    final deletedLength = localOps
        .where((op) => op.type == OpType.delete)
        .fold<int>(0, (length, op) => length + op.lenUtf16!);
    return TextRange(
      start: _startUtf16 + offset,
      end: _startUtf16 + offset + deletedLength,
    );
  }

  void _validateWindowLength(String value) {
    if (value.length > maxWindowUtf16) {
      throw TextInputWindowLimitException(
        maxUtf16: maxWindowUtf16,
        receivedUtf16: value.length,
      );
    }
  }

  TextSelection? _mapSelection(TextSelection selection, String text) {
    if (!selection.isValid) return null;
    final local = _mapWindowSelection(selection, text);
    if (local == null) return null;
    return TextSelection(
      baseOffset: _startUtf16 + local.baseOffset,
      extentOffset: _startUtf16 + local.extentOffset,
      affinity: local.affinity,
      isDirectional: local.isDirectional,
    );
  }

  TextSelection? _mapWindowSelection(TextSelection selection, String text) {
    if (!selection.isValid) return null;
    final base = _snapOffsetBeforeSurrogate(text, selection.baseOffset);
    final extent = _snapOffsetBeforeSurrogate(text, selection.extentOffset);
    return TextSelection(
      baseOffset: base,
      extentOffset: extent,
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  TextRange? _mapComposingWindow(TextRange range, String text) {
    if (!range.isValid || range.start > range.end) return null;
    var start = range.start.clamp(0, text.length).toInt();
    var end = range.end.clamp(0, text.length).toInt();
    if (_splitsSurrogatePair(text, start)) start--;
    if (_splitsSurrogatePair(text, end)) end++;
    return TextRange(start: start, end: end);
  }

  static bool _hasComposition(TextRange range) =>
      range.isValid && !range.isCollapsed;

  static int _snapOffsetBeforeSurrogate(String text, int offset) {
    final bounded = offset.clamp(0, text.length).toInt();
    return _splitsSurrogatePair(text, bounded) ? bounded - 1 : bounded;
  }

  static bool _splitsSurrogatePair(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return false;
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF;
  }
}

int _compareDocumentOpsDescending(TextOp a, TextOp b) {
  final byOffset = b.offsetUtf16.compareTo(a.offsetUtf16);
  if (byOffset != 0) return byOffset;
  if (a.type == b.type) return 0;
  return a.type == OpType.delete ? -1 : 1;
}

class _MutableTextEditGroup {
  int deletedLength = 0;
  String insertedText = '';
}

class _TextEditGroup {
  const _TextEditGroup(this.offsetUtf16, this.deletedText, this.insertedText);

  final int offsetUtf16;
  final String deletedText;
  final String insertedText;
}

/// Rust's acknowledged result plus document-coordinate input metadata.
class RustTextInputDelta {
  const RustTextInputDelta({
    required this.operations,
    required this.version,
    required this.documentLengthUtf16,
    required this.selection,
    required this.selectionWindow,
    required this.composingWindow,
    required this.replacedDocumentRange,
    this.replacementValue,
    this.inverseOperations = const [],
    this.previousSelection,
  });

  final List<TextOp> operations;

  /// Operations that restore the committed text before [operations].
  final List<TextOp> inverseOperations;
  final int version;
  final int documentLengthUtf16;

  /// Absolute UTF-16 selection when the value is committed to Rust.
  /// Null while selection lies in an uncommitted composition overlay.
  final TextSelection? selection;

  /// Absolute selection that was committed before this delta.
  final TextSelection? previousSelection;

  /// Flutter-local selection, suitable for restoring the bounded input field.
  final TextSelection? selectionWindow;

  /// Flutter-local preedit range, kept out of Rust until commit.
  final TextRange? composingWindow;

  /// Absolute Rust range that the current preedit will replace on commit.
  final TextRange? replacedDocumentRange;

  /// Value to write back to Flutter after cancelling composition.
  final TextEditingValue? replacementValue;
}

class TextInputWindowLimitException implements Exception {
  const TextInputWindowLimitException({
    required this.maxUtf16,
    required this.receivedUtf16,
  });

  final int maxUtf16;
  final int receivedUtf16;

  @override
  String toString() =>
      'TextInputWindowLimitException($receivedUtf16 > $maxUtf16 UTF-16 units)';
}

class InputWindowRecoveryConflictException implements Exception {
  const InputWindowRecoveryConflictException(this.message);

  final String message;

  @override
  String toString() => 'InputWindowRecoveryConflictException: $message';
}
