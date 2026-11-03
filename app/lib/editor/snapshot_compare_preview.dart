import 'package:flutter/material.dart';

import 'diff_view_model.dart';

/// Read-only, side-by-side comparison of two bounded text snapshots.
/// Source text is already bounded and projected by DiffViewModel.
class SnapshotComparePreview extends StatelessWidget {
  const SnapshotComparePreview({
    super.key,
    required this.title,
    required this.originalLabel,
    required this.modifiedLabel,
    required this.diff,
    required this.onClose,
    required this.keyPrefix,
    this.closeTooltip = '关闭比较预览',
  });

  final String title;
  final String originalLabel;
  final String modifiedLabel;
  final DiffViewModelResult diff;
  final VoidCallback onClose;
  final String keyPrefix;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: ValueKey('$keyPrefix-preview'),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: SizedBox(
          width: 1000,
          height: 680,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        key: ValueKey('$keyPrefix-title'),
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('$keyPrefix-close'),
                      tooltip: closeTooltip,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _headerRow(context),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  key: ValueKey('$keyPrefix-rows'),
                  itemCount: diff.rows.length,
                  itemBuilder: (context, index) => _diffRow(diff.rows[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Row(
      children: [
        _headerCell(originalLabel, style),
        const VerticalDivider(width: 1),
        _headerCell(modifiedLabel, style),
      ],
    );
  }

  Widget _headerCell(String label, TextStyle? style) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      );

  Widget _diffRow(DiffViewRow row) {
    final (originalColor, modifiedColor) = switch (row.kind) {
      DiffViewRowKind.unchanged => (Colors.transparent, Colors.transparent),
      DiffViewRowKind.modified => (
          const Color(0x553F1D20),
          const Color(0x55303F2E)
        ),
      DiffViewRowKind.deleted => (const Color(0x553F1D20), Colors.transparent),
      DiffViewRowKind.inserted => (Colors.transparent, const Color(0x55303F2E)),
    };
    return SizedBox(
      key: ValueKey('$keyPrefix-row-${row.rowIndex}'),
      height: 26,
      child: Row(
        children: [
          _sourceCell(
            lineNumber: row.originalLineNumber,
            text: row.originalText,
            background: originalColor,
            side: 'original',
            rowIndex: row.rowIndex,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          _sourceCell(
            lineNumber: row.modifiedLineNumber,
            text: row.modifiedText,
            background: modifiedColor,
            side: 'modified',
            rowIndex: row.rowIndex,
          ),
        ],
      ),
    );
  }

  Widget _sourceCell({
    required int? lineNumber,
    required String? text,
    required Color background,
    required String side,
    required int rowIndex,
  }) {
    return Expanded(
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                lineNumber?.toString() ?? '',
                key: ValueKey('$keyPrefix-$side-line-$rowIndex'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF9299A5),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  text ?? '',
                  key: ValueKey('$keyPrefix-$side-text-$rowIndex'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFFD4D8DE),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
