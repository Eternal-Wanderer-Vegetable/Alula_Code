import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bulk_edit_multidiff_projection.dart';
import 'diff_view_model.dart';
import 'word_diff.dart';

/// Opens a transient, read-only Multi Diff surface for a frozen projection.
Future<void> showBulkEditMultiDiffPreview({
  required BuildContext context,
  required BulkEditMultiDiffProjection projection,
  String title = '重构预览',
  String keyPrefix = 'bulk-multidiff',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BulkEditMultiDiffPreview(
      projection: projection,
      title: title,
      keyPrefix: keyPrefix,
      onClose: () => Navigator.of(dialogContext).maybePop(),
    ),
  );
}

/// A resource navigator paired with the selected resource's frozen diff.
///
/// The widget never creates or edits a workbench document. Its rows and source
/// text come directly from [BulkEditMultiDiffProjection].
class BulkEditMultiDiffPreview extends StatefulWidget {
  const BulkEditMultiDiffPreview({
    super.key,
    required this.projection,
    required this.onClose,
    this.title = '重构预览',
    this.keyPrefix = 'bulk-multidiff',
  });

  final BulkEditMultiDiffProjection projection;
  final VoidCallback onClose;
  final String title;
  final String keyPrefix;

  @override
  State<BulkEditMultiDiffPreview> createState() =>
      _BulkEditMultiDiffPreviewState();
}

class _BulkEditMultiDiffPreviewState extends State<BulkEditMultiDiffPreview> {
  int _selectedResource = 0;
  late final FocusNode _resourceFocusNode;

  @override
  void initState() {
    super.initState();
    _resourceFocusNode = FocusNode(debugLabel: 'bulk-multidiff-resource-list');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resourceFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _resourceFocusNode.dispose();
    super.dispose();
  }

  List<BulkEditMultiDiffResource> get _resources => widget.projection.resources;

  void _selectResource(int index) {
    if (index < 0 || index >= _resources.length || index == _selectedResource) {
      return;
    }
    setState(() => _selectedResource = index);
  }

  void _selectPrevious() => _selectResource(_selectedResource - 1);

  void _selectNext() => _selectResource(_selectedResource + 1);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 32).clamp(320.0, 1200.0).toDouble();
    final height = (screen.height - 32).clamp(320.0, 760.0).toDouble();
    final keyPrefix = widget.keyPrefix;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Dialog(
        key: ValueKey('$keyPrefix-dialog'),
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        key: ValueKey('$keyPrefix-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('$keyPrefix-close'),
                      tooltip: '关闭批量差异预览',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 760;
                    if (isNarrow) {
                      return Column(
                        children: [
                          SizedBox(
                            height: 150,
                            child: _buildResourceNavigator(context),
                          ),
                          const Divider(height: 1),
                          Expanded(child: _buildSelectedDiff(context)),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 248,
                          child: _buildResourceNavigator(context),
                        ),
                        const VerticalDivider(width: 1, thickness: 1),
                        Expanded(child: _buildSelectedDiff(context)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResourceNavigator(BuildContext context) {
    final keyPrefix = widget.keyPrefix;
    final resources = _resources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            '更改的文件（${resources.length}）',
            key: ValueKey('$keyPrefix-resource-heading'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Focus(
            focusNode: _resourceFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _selectPrevious();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _selectNext();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ListView.builder(
              key: ValueKey('$keyPrefix-resource-list'),
              itemCount: resources.length,
              itemBuilder: (context, index) {
                final resource = resources[index];
                final isSelected = index == _selectedResource;
                final label = _resourceName(resource.uri);
                final semanticLabel =
                    '$label, ${resource.edits.length} selected text edits';
                final metadata =
                    '${resource.uri}\nDocument ${resource.documentId} · v${resource.baseVersion}';
                return Semantics(
                  key: ValueKey('$keyPrefix-resource-semantics-$index'),
                  label: semanticLabel,
                  selected: isSelected,
                  button: true,
                  child: ExcludeSemantics(
                    child: Tooltip(
                      message: metadata,
                      child: ListTile(
                        key: ValueKey('$keyPrefix-resource-$index'),
                        dense: true,
                        selected: isSelected,
                        onTap: () {
                          _selectResource(index);
                          _resourceFocusNode.requestFocus();
                        },
                        leading: Icon(
                          isSelected
                              ? Icons.insert_drive_file
                              : Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        title: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${resource.edits.length} 项文本更改',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDiff(BuildContext context) {
    final resource = _resources[_selectedResource];
    final keyPrefix = widget.keyPrefix;
    final metadata =
        '${resource.uri}\nDocument ${resource.documentId} · v${resource.baseVersion}';
    final label = _resourceName(resource.uri);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: metadata,
                  child: Text(
                    label,
                    key: ValueKey('$keyPrefix-selected-resource'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${resource.edits.length} 项更改 · v${resource.baseVersion}',
                key: ValueKey('$keyPrefix-selected-resource-count'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _diffHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: ValueKey('$keyPrefix-diff-rows'),
            itemCount: resource.diff.rows.length,
            itemBuilder: (context, index) => _diffRow(
              context,
              resource.diff.rows[index],
              keyPrefix: keyPrefix,
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Row(
      children: [
        _headerCell(context, '原始', style),
        const VerticalDivider(width: 1, thickness: 1),
        _headerCell(context, '预览', style),
      ],
    );
  }

  Widget _headerCell(BuildContext context, String label, TextStyle? style) =>
      Expanded(
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      );

  Widget _diffRow(
    BuildContext context,
    DiffViewRow row, {
    required String keyPrefix,
  }) {
    final colors = Theme.of(context).colorScheme;
    final originalBackground = switch (row.kind) {
      DiffViewRowKind.unchanged ||
      DiffViewRowKind.inserted =>
        Colors.transparent,
      DiffViewRowKind.modified ||
      DiffViewRowKind.deleted =>
        colors.errorContainer.withValues(alpha: 0.38),
    };
    final modifiedBackground = switch (row.kind) {
      DiffViewRowKind.unchanged ||
      DiffViewRowKind.deleted =>
        Colors.transparent,
      DiffViewRowKind.modified ||
      DiffViewRowKind.inserted =>
        colors.tertiaryContainer.withValues(alpha: 0.42),
    };
    return Semantics(
      key: ValueKey('$keyPrefix-row-semantics-${row.rowIndex}'),
      container: true,
      label:
          '${_rowKindLabel(row.kind)}，原始行 ${row.originalLineNumber ?? '无'}，预览行 ${row.modifiedLineNumber ?? '无'}',
      child: SizedBox(
        key: ValueKey('$keyPrefix-row-${row.rowIndex}'),
        height: 26,
        child: Row(
          children: [
            _sourceCell(
              context,
              lineNumber: row.originalLineNumber,
              text: row.originalText,
              wordChanges: row.wordChanges,
              isOriginal: true,
              background: originalBackground,
              side: 'original',
              rowIndex: row.rowIndex,
              keyPrefix: keyPrefix,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            _sourceCell(
              context,
              lineNumber: row.modifiedLineNumber,
              text: row.modifiedText,
              wordChanges: row.wordChanges,
              isOriginal: false,
              background: modifiedBackground,
              side: 'modified',
              rowIndex: row.rowIndex,
              keyPrefix: keyPrefix,
            ),
          ],
        ),
      ),
    );
  }

  String _rowKindLabel(DiffViewRowKind kind) => switch (kind) {
        DiffViewRowKind.unchanged => '未修改',
        DiffViewRowKind.modified => '已修改',
        DiffViewRowKind.inserted => '新增',
        DiffViewRowKind.deleted => '删除',
      };

  Widget _sourceCell(
    BuildContext context, {
    required int? lineNumber,
    required String? text,
    required List<WordDiffHunk> wordChanges,
    required bool isOriginal,
    required Color background,
    required String side,
    required int rowIndex,
    required String keyPrefix,
  }) {
    final colors = Theme.of(context).colorScheme;
    final content = text ?? '';
    return Expanded(
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(
                lineNumber?.toString() ?? '',
                key: ValueKey('$keyPrefix-$side-line-$rowIndex'),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText.rich(
                  TextSpan(
                    style: TextStyle(
                      color: colors.onSurface,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    children: _wordSpans(
                      content,
                      wordChanges,
                      isOriginal: isOriginal,
                      highlight: isOriginal
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                    ),
                  ),
                  key: ValueKey('$keyPrefix-$side-text-$rowIndex'),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _wordSpans(
    String text,
    List<WordDiffHunk> changes, {
    required bool isOriginal,
    required Color highlight,
  }) {
    if (text.isEmpty || changes.isEmpty) return [TextSpan(text: text)];
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final change in changes) {
      final start =
          (isOriginal ? change.originalStartUtf16 : change.modifiedStartUtf16)
              .clamp(0, text.length)
              .toInt();
      final end =
          (isOriginal ? change.originalEndUtf16 : change.modifiedEndUtf16)
              .clamp(start, text.length)
              .toInt();
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      if (end > start) {
        spans.add(TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            backgroundColor: highlight.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
          ),
        ));
      }
      cursor = end > cursor ? end : cursor;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  String _resourceName(String uri) {
    final parsed = Uri.tryParse(uri);
    final segments = parsed?.pathSegments.where((part) => part.isNotEmpty);
    if (segments != null && segments.isNotEmpty) return segments.last;
    return uri;
  }
}
