import 'package:alula_app/editor/clipboard_compare_preview.dart';
import 'package:alula_app/editor/diff_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diff snapshot keeps BOM, emoji, and CRLF code units', () {
    final changed = computeDiffViewModel(
      '\uFEFFbefore🙂\r\nsame',
      '\uFEFFafter🙂\r\nsame',
    );
    expect(changed.isApproximate, isFalse);
    expect(changed.rows, hasLength(2));
    expect(changed.rows.first.originalText, '\uFEFFbefore🙂\r');
    expect(changed.rows.first.modifiedText, '\uFEFFafter🙂\r');

    final identical = computeDiffViewModel('same\r\ntext', 'same\r\ntext');
    expect(identical.isApproximate, isFalse);
    expect(identical.rows.map((row) => row.kind),
        everyElement(DiffViewRowKind.unchanged));
  });

  testWidgets('renders both readonly sides and closes the preview',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => ClipboardComparePreview(
                title: '剪贴板 ↔ sample.rs',
                originalLabel: '剪贴板',
                modifiedLabel: 'sample.rs',
                diff: computeDiffViewModel('before\nshared', 'after\nshared'),
                onClose: () {
                  closed = true;
                  Navigator.of(dialogContext).pop();
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('剪贴板 ↔ sample.rs'), findsOneWidget);
    expect(find.text('剪贴板'), findsOneWidget);
    expect(find.text('sample.rs'), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(4));
    expect(find.text('before'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('clipboard-compare-row-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clipboard-compare-close')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(
        find.byKey(const ValueKey('clipboard-compare-preview')), findsNothing);
  });
}
