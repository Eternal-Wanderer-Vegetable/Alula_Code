import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'diff_view_model.dart';
import 'diff_revert_plan.dart';

class SnapshotComparePresentation {
  const SnapshotComparePresentation({
    this.diff,
    this.isUpdating = false,
    this.fallbackMessage,
    this.actionMessage,
  });

  final DiffViewModelResult? diff;
  final bool isUpdating;
  final String? fallbackMessage;
  final String? actionMessage;
}

/// Side-by-side comparison with an optional Rust-backed modified editor.
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
    this.presentation,
    this.originalText,
    this.modifiedEditorBuilder,
    this.onRevertBlock,
    this.onRevertSelection,
  });

  final String title;
  final String originalLabel;
  final String modifiedLabel;
  final DiffViewModelResult diff;
  final VoidCallback onClose;
  final String keyPrefix;
  final String closeTooltip;
  final ValueListenable<SnapshotComparePresentation>? presentation;
  final String? originalText;
  final Widget Function(
    BuildContext context,
    SnapshotComparePresentation presentation,
  )? modifiedEditorBuilder;
  final ValueChanged<int>? onRevertBlock;
  final VoidCallback? onRevertSelection;

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
              if (presentation != null &&
                  originalText != null &&
                  modifiedEditorBuilder != null)
                ValueListenableBuilder<SnapshotComparePresentation>(
                  valueListenable: presentation!,
                  builder: (context, state, _) => _editableComparison(
                    context,
                    state,
                    originalText!,
                    modifiedEditorBuilder!,
                  ),
                )
              else ...[
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _editableComparison(
    BuildContext context,
    SnapshotComparePresentation state,
    String original,
    Widget Function(BuildContext, SnapshotComparePresentation) editorBuilder,
  ) {
    final style = Theme.of(context).textTheme.labelLarge;
    final exactDiff = state.diff != null && !state.isUpdating;
    final changedRows = exactDiff
        ? state.diff!.rows
            .where((row) => row.kind != DiffViewRowKind.unchanged)
            .length
        : 0;
    final revertHunkRows = exactDiff && onRevertBlock != null
        ? diffRevertToolbarRows(state.diff!)
        : const <int, int>{};
    final status = state.isUpdating
        ? '正在更新差异…'
        : state.actionMessage ??
            state.fallbackMessage ??
            (exactDiff ? '差异行：$changedRows' : '');
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _headerCell(originalLabel, style),
              const VerticalDivider(width: 1),
              _headerCell('$modifiedLabel（可编辑）', style),
            ],
          ),
          if (status.isNotEmpty || (exactDiff && onRevertSelection != null))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      key: ValueKey('$keyPrefix-diff-status'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (exactDiff && onRevertSelection != null)
                    TextButton.icon(
                      key: ValueKey('$keyPrefix-revert-selection'),
                      onPressed: onRevertSelection,
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Revert Selection'),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    key: ValueKey('$keyPrefix-original-pane'),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.18),
                    child: exactDiff
                        ? ListView.builder(
                            key: ValueKey('$keyPrefix-original-text'),
                            itemCount: state.diff!.rows.length,
                            itemBuilder: (context, index) {
                              final row = state.diff!.rows[index];
                              return _editableOriginalRow(
                                keyPrefix: keyPrefix,
                                row: row,
                                hunkIndex: revertHunkRows[row.rowIndex],
                                onRevertBlock: onRevertBlock,
                              );
                            },
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(10),
                            child: SelectableText(
                              original,
                              key: ValueKey('$keyPrefix-original-text'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('$keyPrefix-modified-pane'),
                    child: editorBuilder(context, state),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableOriginalRow({
    required String keyPrefix,
    required DiffViewRow row,
    required int? hunkIndex,
    required ValueChanged<int>? onRevertBlock,
  }) {
    final background = switch (row.kind) {
      DiffViewRowKind.modified ||
      DiffViewRowKind.deleted =>
        const Color(0x553F1D20),
      _ => Colors.transparent,
    };
    return SizedBox(
      height: 26,
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      row.originalLineNumber?.toString() ?? '',
                      key: ValueKey('$keyPrefix-original-line-${row.rowIndex}'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF9299A5),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (hunkIndex != null && onRevertBlock != null)
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: IconButton(
                        key: ValueKey('$keyPrefix-revert-block-$hunkIndex'),
                        tooltip: 'Revert Block',
                        onPressed: () => onRevertBlock(hunkIndex),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                            width: 26, height: 26),
                        icon: const Icon(Icons.arrow_forward, size: 14),
                      ),
                    )
                  else
                    const SizedBox(width: 26),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  row.originalText ?? '',
                  key: ValueKey('$keyPrefix-original-text-${row.rowIndex}'),
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
