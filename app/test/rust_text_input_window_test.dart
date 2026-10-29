import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _CoreBootstrap();

void main() {
  test('composition updates and candidate commit write UTF-16 deltas to Rust',
      () {
    final doc = _bootstrap.core!.openDoc(9710, '\u{FEFF}prefix|A🦊B|suffix');
    try {
      const origin = '\u{FEFF}prefix|'.length;
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: origin,
        maxWindowUtf16: 32,
      );
      expect(window.text, 'A🦊B|suffix');
      expect(window.initialValue.selection.baseOffset, window.text.length);

      final composing = window.applyImmediate(
        const TextEditingValue(
          text: 'AnihaoB|suffix',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 1, end: 6),
        ),
      );
      expect(composing.operations, isEmpty);
      expect(composing.version, 1);
      expect(composing.selection, isNull);
      expect(composing.selectionWindow!.baseOffset, 6);
      expect(composing.composingWindow, const TextRange(start: 1, end: 6));
      expect(
        composing.replacedDocumentRange,
        const TextRange(start: origin + 1, end: origin + 3),
      );
      expect(window.text, 'A🦊B|suffix');
      expect(window.presentedText, 'AnihaoB|suffix');
      expect(doc.resync().content, '\u{FEFF}prefix|A🦊B|suffix');

      final committed = window.applyImmediate(
        const TextEditingValue(
          text: 'A你好B|suffix',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange.empty,
        ),
      );
      expect(committed.composingWindow, isNull);
      expect(
        committed.operations
            .map((op) => (op.type, op.offsetUtf16, op.lenUtf16, op.text))
            .toList(),
        [
          (OpType.delete, origin + 1, 2, null),
          (OpType.insert, origin + 1, null, '你好'),
        ],
      );
      expect(committed.selection!.baseOffset, origin + 3);
      expect(doc.resync().content, '\u{FEFF}prefix|A你好B|suffix');
      expect(committed.version, doc.version);
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('cancelled composition restores the committed Rust text', () {
    final doc = _bootstrap.core!.openDoc(9711, 'before|ok|after');
    try {
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 7,
        maxWindowUtf16: 16,
      );
      window.applyImmediate(
        const TextEditingValue(
          text: 'ni|after',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      expect(doc.resync().content, 'before|ok|after');
      expect(window.presentedText, 'ni|after');
      final cancelled = window.cancelComposition()!;
      expect(cancelled.operations, isEmpty);
      expect(cancelled.replacementValue!.text, 'ok|after');
      expect(window.presentedText, 'ok|after');
      expect(doc.resync().content, 'before|ok|after');

      // A cancellation delivered by the platform as a restored non-composing
      // value is also a no-op at the Rust boundary.
      final restored = window.applyImmediate(
        const TextEditingValue(
          text: 'ok|after',
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      );
      expect(restored.operations, isEmpty);
      expect(restored.composingWindow, isNull);
      expect(doc.resync().content, 'before|ok|after');
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test(
      'one-slot writeback coalesces input bursts and preserves the latest IME state',
      () {
    final doc = _bootstrap.core!.openDoc(9712, 'x');
    try {
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 128,
      );
      for (var count = 1; count <= 100; count++) {
        window.enqueue(
          TextEditingValue(
            text: 'x${'a' * count}',
            selection: TextSelection.collapsed(offset: count + 1),
          ),
        );
      }

      expect(window.pendingCount, 1);
      expect(window.coalescedInputCount, 99);
      final applied = window.flushPending()!;
      expect(
        applied.operations.map((op) => (op.type, op.offsetUtf16, op.text)),
        [(OpType.insert, 1, 'a' * 100)],
      );
      expect(applied.composingWindow, isNull);
      expect(window.pendingCount, 0);
      expect(doc.version, 2);
      expect(doc.resync().content, 'x${'a' * 100}');
      expect(window.flushPending(), isNull);
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('selection and composing coordinates map to Rust and never split emoji',
      () {
    final doc = _bootstrap.core!.openDoc(9713, 'a🦊z');
    try {
      final window =
          RustTextInputWindow.open(doc, startUtf16: 1, maxWindowUtf16: 4);
      expect(window.startUtf16, 1);
      expect(window.text, '🦊z');

      final result = window.applyImmediate(
        const TextEditingValue(
          text: '🦊z',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      expect(result.operations, isEmpty);
      expect(result.selection, isNull);
      expect(result.selectionWindow!.baseOffset, 0);
      expect(result.composingWindow, const TextRange(start: 0, end: 2));
      expect(result.replacedDocumentRange, const TextRange(start: 1, end: 3));
      expect(doc.resync().content, 'a🦊z');

      final committedSelection = window.applyImmediate(
        const TextEditingValue(
          text: '🦊z',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange.empty,
        ),
      );
      expect(committedSelection.selection!.baseOffset, 1);
      expect(committedSelection.composingWindow, isNull);
      expect(doc.resync().content, 'a🦊z');
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('queued IME preedit can be committed before a save or focus transfer',
      () {
    final doc = _bootstrap.core!.openDoc(9716, 'x');
    try {
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 16,
      );
      window.enqueue(
        const TextEditingValue(
          text: 'xni',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 1, end: 3),
        ),
      );
      expect(window.flushPending()!.operations, isEmpty);
      expect(doc.resync().content, 'x');

      final committed = window.commitComposition()!;
      expect(
        committed.operations.map((op) => (op.type, op.offsetUtf16, op.text)),
        [(OpType.insert, 1, 'ni')],
      );
      expect(committed.composingWindow, isNull);
      expect(doc.resync().content, 'xni');
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test(
      'window limit rejects an oversized paste without advancing Rust or session',
      () {
    final doc = _bootstrap.core!.openDoc(9714, 'abc');
    try {
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 4,
      );
      const tooLarge = TextEditingValue(
        text: 'abcde',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(
        () => window.enqueue(tooLarge),
        throwsA(isA<TextInputWindowLimitException>()),
      );
      expect(
        () => window.applyImmediate(tooLarge),
        throwsA(isA<TextInputWindowLimitException>()),
      );
      expect(window.text, 'abc');
      expect(window.pendingCount, 0);
      expect(doc.resync().content, 'abc');
      expect(doc.version, 1);
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('version mismatch keeps the failed input pending for explicit recovery',
      () {
    final doc = _bootstrap.core!.openDoc(9715, 'abc');
    try {
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 8,
      );
      doc.apply([const TextOp.insert(0, 'x')]);
      window.enqueue(
        const TextEditingValue(
          text: 'abc!',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );

      expect(window.flushPending, throwsA(isA<SyncMismatchException>()));
      expect(window.pendingCount, 1);
      expect(window.text, 'abc');
      expect(doc.resync().content, 'xabc');
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);
}
