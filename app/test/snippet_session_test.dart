import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/snippet_session.dart';
import 'package:alula_app/editor/snippet_template.dart';

void main() {
  group('SnippetSession', () {
    test('visits numeric tabstops in order and leaves the final stop last',
        () async {
      final expansion = await expandSnippetTemplate(r'${2:second} ${1:first}');
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

    test('preserves active choice metadata while linked ranges are edited',
        () async {
      final expansion =
          await expandSnippetTemplate(r'${1|blue,green|} / $1 ${2:done}$0');
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

    test('only exposes choice metadata from the first active occurrence',
        () async {
      final session = SnippetSession(
        await expandSnippetTemplate(r'$1 ${1|one,two|}'),
        documentOffsetUtf16: 0,
        version: 1,
      );

      expect(session.currentRanges, hasLength(2));
      expect(session.currentRanges.first.choice, isNull);
      expect(session.currentRanges.last.choice?.options, ['one', 'two']);
      expect(session.activeChoiceRange, isNull);
    });

    test('maps manual selection positions across linked placeholders',
        () async {
      final expansion = await expandSnippetTemplate(r'${1:name}-$1-${2:value}');
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

    test('tracks a mirrored edit and shifts later tabstops', () async {
      final expansion = await expandSnippetTemplate(r'${1:name} $1');
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

    test('tracks an independently transformed placeholder mirror', () async {
      final expansion = await expandSnippetTemplate(
        r'${1:name}-${1/(.*)/${1:/upcase} suffix/}$0',
      );
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 5,
        version: 8,
      );
      final transformed = session.currentRanges.last;
      expect(transformed.transform, isNotNull);

      expect(
        session.applyOperations(
          [
            TextOp.delete(transformed.startUtf16, transformed.lengthUtf16),
            TextOp.insert(transformed.startUtf16, 'NAME suffix'),
          ],
          nextVersion: 9,
          allowPartialActiveGroup: true,
        ),
        isTrue,
      );
      expect(session.currentRanges.first.transform, isNull);
      expect(session.currentRanges.last.transform, isNotNull);
      expect(session.currentRanges.last.startUtf16, 10);
      expect(session.currentRanges.last.endUtf16, 21);
      expect(session.moveNext(), isTrue);
      expect(session.currentSelections.single,
          const TextSelection.collapsed(offset: 21));
    });

    test('nested child edits update both child and enclosing ranges', () async {
      final expansion = await expandSnippetTemplate(r'${1:pre ${2:🙂x}}$0');
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: 10,
        version: 1,
      );

      expect(session.currentSelections.single,
          const TextSelection(baseOffset: 10, extentOffset: 17));
      expect(session.moveNext(), isTrue);
      expect(session.currentSelections.single,
          const TextSelection(baseOffset: 14, extentOffset: 17));
      final operations = session.operationsForMirroredEdit(
        primarySelection: const TextSelection(baseOffset: 14, extentOffset: 17),
        editStartUtf16: 14,
        deletedUtf16: 3,
        insertedText: 'ok',
      );

      expect(operations, isNotNull);
      expect(session.applyOperations(operations!, nextVersion: 2), isTrue);
      expect(session.currentRanges.single.startUtf16, 14);
      expect(session.currentRanges.single.endUtf16, 16);
      expect(session.movePrevious(), isTrue);
      expect(session.currentRanges.single.startUtf16, 10);
      expect(session.currentRanges.single.endUtf16, 16);
      expect(session.moveNext(), isTrue);
      expect(session.moveNext(), isTrue);
      expect(session.currentRanges.single.startUtf16, 16);
    });

    test('nested empty child remains inside its parent when edited', () async {
      final session = SnippetSession(
        await expandSnippetTemplate(r'${1:pre ${2:x}}$0'),
        documentOffsetUtf16: 10,
        version: 3,
      );

      final replaceParent = session.operationsForMirroredEdit(
        primarySelection: const TextSelection(baseOffset: 10, extentOffset: 15),
        editStartUtf16: 10,
        deletedUtf16: 5,
        insertedText: 'done',
      );
      expect(replaceParent, isNotNull);
      expect(session.applyOperations(replaceParent!, nextVersion: 4), isTrue);

      final extendParent = session.operationsForMirroredEdit(
        primarySelection: const TextSelection.collapsed(offset: 14),
        editStartUtf16: 14,
        deletedUtf16: 0,
        insertedText: '!',
      );
      expect(extendParent, isNotNull);
      expect(session.applyOperations(extendParent!, nextVersion: 5), isTrue);
      expect(session.currentRanges.single.endUtf16, 15);

      expect(session.moveNext(), isTrue);
      expect(session.currentSelections.single,
          const TextSelection.collapsed(offset: 15));

      final typeInChild = session.operationsForMirroredEdit(
        primarySelection: const TextSelection.collapsed(offset: 15),
        editStartUtf16: 15,
        deletedUtf16: 0,
        insertedText: 'Y',
      );
      expect(typeInChild, isNotNull);
      expect(session.applyOperations(typeInChild!, nextVersion: 6), isTrue);
      expect(session.currentRanges.single.startUtf16, 15);
      expect(session.currentRanges.single.endUtf16, 16);
      expect(session.movePrevious(), isTrue);
      expect(session.currentRanges.single.startUtf16, 10);
      expect(session.currentRanges.single.endUtf16, 16);
    });

    test('plans mirrored edits without collapsing across intervening text',
        () async {
      final expansion =
          await expandSnippetTemplate(r'${1:name} = $1; ${2:value}$0');
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
        () async {
      final expansion = await expandSnippetTemplate(r'${1:name} $1');
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

    test('combines cursor expansions with unique ranges and per-cursor indent',
        () async {
      final firstExpansion = await expandSnippetTemplate(r'${1:x}-$1-$0');
      final secondExpansion = await expandSnippetTemplate(r'${1:x}-$1-$0');
      final session = SnippetSession.fromInsertions(
        insertions: [
          (
            expansion: firstExpansion,
            documentOffsetUtf16: 10,
            lineLeadingWhitespace: '  ',
          ),
          (
            expansion: secondExpansion,
            documentOffsetUtf16: 30,
            lineLeadingWhitespace: '    ',
          ),
        ],
        version: 9,
      );

      final firstTabstopRanges = session.currentRanges;
      expect(firstTabstopRanges, hasLength(4));
      expect(
        firstTabstopRanges.map((range) => range.occurrenceId).toSet(),
        hasLength(4),
      );
      expect(
        firstTabstopRanges
            .map(session.lineLeadingWhitespaceFor)
            .toList(growable: false),
        ['  ', '  ', '    ', '    '],
      );

      expect(session.moveNext(), isTrue);
      expect(
        session.currentRanges
            .map((range) => [range.startUtf16, range.endUtf16]),
        [
          [14, 14],
          [34, 34],
        ],
      );
    });
  });
}
