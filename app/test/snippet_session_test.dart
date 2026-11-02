import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/snippet_session.dart';
import 'package:alula_app/editor/snippet_template.dart';

void main() {
  group('SnippetSession', () {
    test('visits numeric tabstops in order and leaves the final stop last', () {
      final expansion = expandSnippetTemplate(r'${2:second} ${1:first}');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 10,
        version: 4,
      );

      expect(session.currentTabstop, 1);
      expect(session.currentSelections.first.start, 17);
      expect(session.moveNext(), isTrue);
      expect(session.currentTabstop, 2);
      expect(session.moveNext(), isTrue);
      expect(session.currentTabstop, 0);
      expect(session.isAtFinalTabstop, isTrue);
      expect(session.canMoveNext, isFalse);
      expect(session.movePrevious(), isTrue);
      expect(session.currentTabstop, 2);
    });

    test('preserves active choice metadata while linked ranges are edited', () {
      final expansion =
          expandSnippetTemplate(r'${1|blue,green|} / $1 ${2:done}$0');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 20,
        version: 3,
      );

      expect(session.activeChoiceRange?.choice?.options, ['blue', 'green']);
      expect(
        session.applyOperations(
          const [
            TextOp.delete(20, 4),
            TextOp.insert(20, 'golden'),
            TextOp.delete(27, 4),
            TextOp.insert(27, 'golden'),
          ],
          nextVersion: 4,
        ),
        isTrue,
      );
      final activeChoice = session.activeChoiceRange;
      expect(activeChoice, isNotNull);
      expect(activeChoice!.startUtf16, 20);
      expect(activeChoice.endUtf16, 26);
      expect(activeChoice.choice?.options, ['blue', 'green']);
      expect(session.moveNext(), isTrue);
      expect(session.activeChoiceRange, isNull);
    });

    test('only exposes choice metadata from the first active occurrence', () {
      final session = SnippetSession(
        expandSnippetTemplate(r'$1 ${1|one,two|}'),
        documentOffsetUtf16: 0,
        version: 1,
      );

      expect(session.currentRanges, hasLength(2));
      expect(session.currentRanges.first.choice, isNull);
      expect(session.currentRanges.last.choice?.options, ['one', 'two']);
      expect(session.activeChoiceRange, isNull);
    });

    test('maps manual selection positions across linked placeholders', () {
      final expansion = expandSnippetTemplate(r'${1:name}-$1-${2:value}');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 20,
        version: 1,
      );

      expect(
        session.mirrorSelection(
          const TextSelection(baseOffset: 21, extentOffset: 23),
        ),
        [const TextSelection(baseOffset: 26, extentOffset: 28)],
      );
      expect(
        session.mirrorSelection(
          const TextSelection.collapsed(offset: 40),
        ),
        isNull,
      );
    });

    test('tracks a mirrored edit and shifts later tabstops', () {
      final expansion = expandSnippetTemplate(r'${1:name} $1');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 20,
        version: 2,
      );
      final operations = [
        const TextOp.delete(20, 4),
        const TextOp.insert(20, 'ab'),
        const TextOp.delete(25, 4),
        const TextOp.insert(25, 'ab'),
      ];

      expect(session.applyOperations(operations, nextVersion: 3), isTrue);
      expect(
        session.currentRanges
            .map((range) => [range.startUtf16, range.endUtf16]),
        [
          [20, 22],
          [23, 25],
        ],
      );
      expect(session.version, 3);
      expect(session.moveNext(), isTrue);
      expect(session.currentRanges.single.startUtf16, 25);
    });

    test('plans mirrored edits without collapsing across intervening text', () {
      final expansion = expandSnippetTemplate(r'${1:name} = $1; ${2:value}$0');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 1,
        version: 4,
      );
      final operations = session.operationsForMirroredEdit(
        primarySelection: const TextSelection(baseOffset: 1, extentOffset: 5),
        editStartUtf16: 1,
        deletedUtf16: 4,
        insertedText: 'foo',
      );

      expect(operations, isNotNull);
      expect(session.applyOperations(operations!, nextVersion: 6), isTrue);
      expect(
        session.currentRanges
            .map((range) => [range.startUtf16, range.endUtf16]),
        [
          [1, 4],
          [7, 10],
        ],
      );
      expect(session.moveNext(), isTrue);
      expect(session.currentRanges.single.startUtf16, 12);
      expect(session.currentRanges.single.endUtf16, 17);
    });

    test('rejects a missing mirror edit without publishing stale coordinates',
        () {
      final expansion = expandSnippetTemplate(r'${1:name} $1');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 20,
        version: 2,
      );

      expect(
        session.applyOperations(
          const [TextOp.insert(20, 'x')],
          nextVersion: 3,
        ),
        isFalse,
      );
      expect(session.version, 2);
      expect(session.currentRanges.first.startUtf16, 20);
    });
  });
}
