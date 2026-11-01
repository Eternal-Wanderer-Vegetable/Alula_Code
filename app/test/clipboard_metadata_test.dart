import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/clipboard_metadata.dart';

void main() {
  group('editor clipboard metadata', () {
    late EditorClipboardMetadataStore store;

    setUp(() {
      store = EditorClipboardMetadataStore.shared;
      store.clear();
    });

    tearDown(() => store.clear());

    test('matches exact plain text and keeps copied cursor chunks immutable',
        () {
      final chunks = ['one\ntwo', 'three'];
      expect(
        store.record(
          'one\ntwo\nthree',
          EditorClipboardMetadata(multiCursorText: chunks),
        ),
        isTrue,
      );
      chunks.add('later mutation');

      final metadata = store.lookup('one\ntwo\nthree');
      expect(metadata?.version, EditorClipboardMetadata.currentVersion);
      expect(metadata?.multiCursorText, const ['one\ntwo', 'three']);
      expect(metadata?.isFromEmptySelection, isFalse);
      expect(store.lookup('one\ntwo\nthree')?.multiCursorText,
          const ['one\ntwo', 'three']);
    });

    test('returns single empty-selection metadata for the matching text', () {
      store.record(
        'line\n',
        const EditorClipboardMetadata(isFromEmptySelection: true),
      );

      expect(store.lookup('line\n')?.isFromEmptySelection, isTrue);
      expect(store.lookup('line\n')?.multiCursorText, isNull);
    });

    test('external clipboard text invalidates stale editor metadata', () {
      store.record(
        'left\nright',
        const EditorClipboardMetadata(multiCursorText: ['left', 'right']),
      );

      expect(store.lookup('external text'), isNull);
      expect(store.lookup('left\nright'), isNull);
    });

    test('drops oversized retained metadata but leaves plain text usable', () {
      final oversized =
          'x' * (EditorClipboardMetadataStore.maxRetainedTextUtf16 + 1);
      expect(
        store.record(
          oversized,
          const EditorClipboardMetadata(multiCursorText: ['x', 'x']),
        ),
        isFalse,
      );
      expect(store.lookup(oversized), isNull);
    });
  });
}
