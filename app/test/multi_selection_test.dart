import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/multi_selection.dart';

void main() {
  group('multi-selection input edits', () {
    test('distributes clipboard lines across primary and secondary selections',
        () {
      const oldValue = TextEditingValue(
        text: '🙂 x 🙂',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      );
      final result = applyDistributedMultiSelectionPaste(
        oldValue: oldValue,
        selections: const [
          TextSelection(baseOffset: 0, extentOffset: 2),
          TextSelection(baseOffset: 5, extentOffset: 7),
        ],
        clipboardText: 'left\r\nright',
      );

      expect(result.value.text, 'left x right');
      expect(result.value.selection, const TextSelection.collapsed(offset: 4));
      expect(result.selections, const [TextSelection.collapsed(offset: 12)]);
      expect(result.changed, isTrue);
    });

    test('repeats the full clipboard when line count differs from cursor count',
        () {
      const oldValue = TextEditingValue(
        text: 'a b c',
        selection: TextSelection.collapsed(offset: 1),
      );
      final result = applyDistributedMultiSelectionPaste(
        oldValue: oldValue,
        selections: const [
          TextSelection.collapsed(offset: 1),
          TextSelection.collapsed(offset: 3),
          TextSelection.collapsed(offset: 5),
        ],
        clipboardText: 'x\ny',
      );

      expect(result.value.text, 'ax\ny bx\ny cx\ny');
      expect(result.value.selection.extentOffset, 4);
      expect(result.selections, const [
        TextSelection.collapsed(offset: 9),
        TextSelection.collapsed(offset: 14),
      ]);
    });

    test('inserts at primary and secondary carets in one transformed value',
        () {
      const oldValue = TextEditingValue(
        text: 'abc def',
        selection: TextSelection.collapsed(offset: 3),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: oldValue.copyWith(
          text: 'abcX def',
          selection: const TextSelection.collapsed(offset: 4),
        ),
        additionalSelections: const [TextSelection.collapsed(offset: 7)],
      );

      expect(result.value.text, 'abcX defX');
      expect(result.value.selection.extentOffset, 4);
      expect(result.selections, const [TextSelection.collapsed(offset: 9)]);
      expect(result.changed, isTrue);
    });

    test('replaces selected matches and keeps Rust-facing UTF-16 positions',
        () {
      const oldValue = TextEditingValue(
        text: 'red green red',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: oldValue.copyWith(
          text: 'blue green red',
          selection: const TextSelection.collapsed(offset: 4),
        ),
        additionalSelections: const [
          TextSelection(baseOffset: 10, extentOffset: 13),
        ],
      );

      expect(result.value.text, 'blue green blue');
      expect(result.value.selection.extentOffset, 4);
      expect(result.selections, const [TextSelection.collapsed(offset: 15)]);
    });

    test('typing over a primary selection inserts at secondary carets', () {
      const oldValue = TextEditingValue(
        text: 'alpha beta',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: oldValue.copyWith(
          text: 'X beta',
          selection: const TextSelection.collapsed(offset: 1),
        ),
        additionalSelections: const [TextSelection.collapsed(offset: 10)],
      );

      expect(result.value.text, 'X betaX');
      expect(result.value.selection.extentOffset, 1);
      expect(result.selections, const [TextSelection.collapsed(offset: 7)]);
    });

    test(
        'deletes a full grapheme at each cursor even when UTF-16 widths differ',
        () {
      const text = 'a🙂b / c🙂d';
      const oldValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 3),
      );
      final updated = text.replaceRange(1, 3, '');
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: TextEditingValue(
          text: updated,
          selection: const TextSelection.collapsed(offset: 1),
        ),
        additionalSelections: const [TextSelection.collapsed(offset: 11)],
      );

      expect(result.value.text, 'ab / c🙂');
      expect(result.value.selection.extentOffset, 1);
      expect(result.selections, const [TextSelection.collapsed(offset: 8)]);
    });

    test('backspace at a secondary caret removes a combining grapheme', () {
      const text = 'a\u0301 x e\u0301';
      const oldValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: TextEditingValue(
          text: text.replaceRange(0, 2, ''),
          selection: const TextSelection.collapsed(offset: 0),
        ),
        additionalSelections: const [TextSelection.collapsed(offset: 7)],
      );

      expect(result.value.text, ' x ');
      expect(result.selections, const [TextSelection.collapsed(offset: 3)]);
    });

    test('delete at secondary carets removes the next whole grapheme', () {
      const text = '🙂a e\u0301';
      const oldValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 0),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: TextEditingValue(
          text: text.replaceRange(0, 2, ''),
          selection: const TextSelection.collapsed(offset: 0),
        ),
        additionalSelections: const [TextSelection.collapsed(offset: 4)],
      );

      expect(result.value.text, 'a ');
      expect(result.selections, const [TextSelection.collapsed(offset: 2)]);
    });

    test('does not rewrite active IME composition', () {
      const oldValue = TextEditingValue(
        text: 'a b',
        selection: TextSelection.collapsed(offset: 1),
      );
      final composing = oldValue.copyWith(
        text: 'あa b',
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      final result = applyMultiSelectionEdit(
        oldValue: oldValue,
        newValue: composing,
        additionalSelections: const [TextSelection.collapsed(offset: 3)],
      );

      expect(result.value, composing);
      expect(result.changed, isFalse);
    });
  });

  test('normalization merges overlaps and keeps primary selection first', () {
    final normalized = normalizeSelectionSet(const [
      TextSelection(baseOffset: 4, extentOffset: 7),
      TextSelection(baseOffset: 2, extentOffset: 5),
      TextSelection.collapsed(offset: 11),
      TextSelection.collapsed(offset: 11),
    ]);

    expect(normalized, const [
      TextSelection(baseOffset: 2, extentOffset: 7),
      TextSelection.collapsed(offset: 11),
    ]);
  });

  test('column selection maps CRLF rows and snaps away from emoji interiors',
      () {
    const text = 'one\r\ntwo\r\n🙂x';
    const column = ColumnSelectionState(
      anchorLine: 0,
      anchorColumn: 1,
      activeLine: 2,
      activeColumn: 2,
    );

    expect(columnSelectionsForText(text, column), const [
      TextSelection(baseOffset: 10, extentOffset: 12),
      TextSelection(baseOffset: 1, extentOffset: 2),
      TextSelection(baseOffset: 6, extentOffset: 7),
    ]);
    expect(lineAndColumnAt(text, 7), (1, 2));
  });

  test('cursor undo and redo are independent bounded selection history', () {
    final history = SelectionHistory(capacity: 2);
    const first = [TextSelection.collapsed(offset: 1)];
    const second = [
      TextSelection.collapsed(offset: 1),
      TextSelection.collapsed(offset: 4),
    ];
    const third = [TextSelection.collapsed(offset: 8)];

    history.record(first);
    history.record(second);
    expect(history.undo(third), second);
    expect(history.redo(first), third);
  });

  test('secondary offsets follow an IME overlay before text is committed', () {
    expect(mapOffsetThroughTextChange('ni ni', 'bei ni', 3), 4);
    expect(mapOffsetThroughTextChange('ni ni', 'bei ni', 5), 6);
  });

  test('column edges snap around combining marks as one grapheme', () {
    const text = 'e\u0301x\ny';
    expect(lineOffsetAtColumn(text, 0, 1), 0);
    const column = ColumnSelectionState(
      anchorLine: 0,
      anchorColumn: 1,
      activeLine: 1,
      activeColumn: 2,
    );
    expect(columnSelectionsForText(text, column), const [
      TextSelection(baseOffset: 5, extentOffset: 5),
      TextSelection(baseOffset: 0, extentOffset: 2),
    ]);
  });

  test('insertion offsets preserve emoji, combining marks, and CRLF', () {
    const text = '🙂\r\ne\u0301 x';
    const oldValue = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: 2),
    );
    final result = applyMultiSelectionEdit(
      oldValue: oldValue,
      newValue: oldValue.copyWith(
        text: '🙂Z\r\ne\u0301 x',
        selection: const TextSelection.collapsed(offset: 3),
      ),
      additionalSelections: const [TextSelection.collapsed(offset: 8)],
    );

    expect(result.value.text, '🙂Z\r\ne\u0301 xZ');
    expect(result.value.selection.extentOffset, 3);
    expect(result.selections, const [TextSelection.collapsed(offset: 10)]);
  });
}
