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
    required TextRangeRead initialRange,
  })  : _startUtf16 = initialRange.startUtf16,
        _totalUtf16Length = initialRange.totalUtf16Length,
        _version = initialRange.version,
        _text = initialRange.text,
        _presentedText = initialRange.text,
        _committedSelectionWindow =
            TextSelection.collapsed(offset: initialRange.text.length);

  /// Reads at most [maxWindowUtf16] UTF-16 units from Rust.
  ///
  /// The range request reserves one unit for a surrogate-pair boundary. This
  /// keeps the returned mirror within the requested hard limit even when Rust
  /// expands a range by one unit to avoid splitting a scalar value.
  factory RustTextInputWindow.open(
    AlulaDoc document, {
    required int startUtf16,
    int maxWindowUtf16 = 8192,
  }) {
    if (maxWindowUtf16 < 2 || maxWindowUtf16 > maxRustTextInputWindowUtf16) {
      throw ArgumentError.value(
        maxWindowUtf16,
        'maxWindowUtf16',
        'must be between 2 and $maxRustTextInputWindowUtf16',
      );
    }
    final range = document.readRange(
      startUtf16,
      maxLenUtf16: maxWindowUtf16 - 1,
    );
    if (range.text.length > maxWindowUtf16) {
      throw StateError('Rust returned a text window beyond its requested cap');
    }
    return RustTextInputWindow._(
      document: document,
      maxWindowUtf16: maxWindowUtf16,
      initialRange: range,
    );
  }

  final AlulaDoc document;
  final int maxWindowUtf16;
  int _startUtf16;
  int _totalUtf16Length;
  int _version;
  String _text;
  String _presentedText;
  TextSelection _committedSelectionWindow;
  TextEditingValue? _composingValue;
  TextEditingValue? _pending;
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

  /// Initial editable value with the caret at the end of this window.
  TextEditingValue get initialValue => TextEditingValue(
        text: _text,
        selection: TextSelection.collapsed(offset: _text.length),
      );

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
  void enqueue(TextEditingValue value) {
    _validateWindowLength(value.text);
    if (_pending != null) _coalescedInputCount++;
    _pending = value;
  }

  /// Applies the newest queued value, or returns null when the slot is empty.
  /// Failed writes stay pending so the caller can recover or retry explicitly.
  RustTextInputDelta? flushPending() {
    final pending = _pending;
    if (pending == null) return null;
    final delta = _apply(pending);
    _pending = null;
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

  RustTextInputDelta _apply(TextEditingValue value) {
    _validateWindowLength(value.text);
    final localOps = diffToOps(_text, value.text);
    final selectionWindow = _mapWindowSelection(value.selection, value.text);
    final composingWindow = _mapComposingWindow(value.composing, value.text);

    if (_hasComposition(value.composing)) {
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

    final ops = _toDocumentOps(localOps);
    final nextLength = _totalUtf16Length + value.text.length - _text.length;
    if (nextLength < 0) {
      throw StateError(
          'Input window edit would produce a negative document length');
    }

    // Keep the snapshot unchanged if FFI rejects a stale version or invalid op.
    final nextVersion =
        ops.isEmpty ? _version : document.applyWith(_version, ops);

    _text = value.text;
    _presentedText = value.text;
    _composingValue = null;
    _version = nextVersion;
    _totalUtf16Length = nextLength;
    if (selectionWindow != null) {
      _committedSelectionWindow = selectionWindow;
    }
    return RustTextInputDelta(
      operations: List<TextOp>.unmodifiable(ops),
      version: nextVersion,
      documentLengthUtf16: nextLength,
      selection: _mapSelection(value.selection, value.text),
      selectionWindow: selectionWindow,
      composingWindow: null,
      replacedDocumentRange: null,
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
  });

  final List<TextOp> operations;
  final int version;
  final int documentLengthUtf16;

  /// Absolute UTF-16 selection when the value is committed to Rust.
  /// Null while selection lies in an uncommitted composition overlay.
  final TextSelection? selection;

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
