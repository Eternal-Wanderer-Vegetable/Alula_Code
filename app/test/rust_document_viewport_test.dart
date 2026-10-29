import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_document_viewport.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

class _Bootstrap {
  final AlulaCore? core;
  final String? error;

  _Bootstrap._(this.core, this.error);

  factory _Bootstrap() {
    try {
      return _Bootstrap._(AlulaCore.load(), null);
    } catch (error) {
      return _Bootstrap._(null, 'alula_core 动态库未构建：$error');
    }
  }
}

final _Bootstrap _bootstrap = _Bootstrap();
final String? _skip = _bootstrap.error;

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const caret = Rect.fromLTWH(0, 0, 2, 20);
  final local = paragraph.getOffsetForCaret(
        TextPosition(offset: offset),
        caret,
      ) +
      Offset(0, paragraph.preferredLineHeight);
  return paragraph.localToGlobal(local) + const Offset(0, -2);
}

void main() {
  testWidgets(
    '50k-line Rust document pages, scrolls, selects and keeps views independent',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final core = _bootstrap.core!;
      var seed = List<String>.generate(
        50000,
        (line) => "L${line.toString().padLeft(5, '0')} 🦊",
      ).join('\r\n');
      final doc = core.openDoc(95001, seed);
      seed = '';
      addTearDown(doc.close);

      final leftScroll = ScrollController();
      final rightScroll = ScrollController();
      addTearDown(leftScroll.dispose);
      addTearDown(rightScroll.dispose);

      final leftPages = <int>{};
      final rightPages = <int>{};
      var leftSelection = '';
      var rightSelection = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: RustDocumentViewport(
                    document: doc,
                    viewId: 'left',
                    scrollController: leftScroll,
                    onPageRead: (page) => leftPages.add(page.firstLine),
                    onSelectionChanged: (selection) {
                      leftSelection = selection?.plainText ?? '';
                    },
                  ),
                ),
                Expanded(
                  child: RustDocumentViewport(
                    document: doc,
                    viewId: 'right',
                    scrollController: rightScroll,
                    onPageRead: (page) => rightPages.add(page.firstLine),
                    onSelectionChanged: (selection) {
                      rightSelection = selection?.plainText ?? '';
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(doc.lineOffset(0).lineCount, 50000);
      expect(leftPages, contains(0));
      expect(rightPages, contains(0));
      expect(find.byKey(const ValueKey('rust-viewport-left-line-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('rust-viewport-right-line-0')),
          findsOneWidget);

      final lineZero = find.byKey(const ValueKey('rust-viewport-left-line-0'));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: lineZero, matching: find.byType(RichText)),
      );
      final selectionGesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await selectionGesture.moveTo(_textOffsetToPosition(paragraph, 6));
      await tester.pumpAndSettle();
      await selectionGesture.up();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(leftSelection, contains('L00000'));
      expect(rightSelection, isEmpty);

      const pageExtent = rustViewportLinesPerPage * rustViewportRowHeight;
      leftScroll.jumpTo(pageExtent * 200);
      await tester.pumpAndSettle();
      expect(leftPages, contains(6400));
      expect(leftScroll.offset, greaterThan(0));
      expect(rightScroll.offset, 0);

      rightScroll.jumpTo(pageExtent * 1250);
      await tester.pumpAndSettle();
      expect(rightPages, contains(40000));
      expect(rightScroll.offset, greaterThan(leftScroll.offset));

      rightScroll.jumpTo(pageExtent * 1562);
      await tester.pumpAndSettle();
      expect(rightPages, contains(49984));
      expect(
        find.byKey(const ValueKey('rust-viewport-right-line-49999')),
        findsOneWidget,
      );

      for (final page in [...leftPages, ...rightPages]) {
        final read = doc.readLines(
          firstLine: page,
          maxLines: rustViewportLinesPerPage,
          maxLineUtf16: rustViewportLineWindowUtf16,
          maxTotalUtf16: rustViewportPageUtf16,
        );
        final units = read.lines.fold<int>(
          0,
          (sum, line) => sum + line.endUtf16 - line.startUtf16,
        );
        expect(units, lessThanOrEqualTo(rustViewportPageUtf16));
        expect(
          read.lines
              .every((line) => line.text.length <= rustViewportLineWindowUtf16),
          isTrue,
        );
      }
    },
    skip: _skip != null,
  );
}
