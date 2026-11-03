import 'package:flutter/material.dart';

import 'git_diff_patch.dart';
import 'git_diff_side_by_side.dart';
import 'git_diff_word_highlights.dart';

enum GitDiffPatchPresentation { inline, sideBySide }

/// Bounded inline and side-by-side renderer for a Git unified text patch.
class GitDiffPatchView extends StatefulWidget {
  const GitDiffPatchView({
    required this.patch,
    super.key,
  });

  final String patch;

  @override
  State<GitDiffPatchView> createState() => _GitDiffPatchViewState();
}

class _GitDiffPatchViewState extends State<GitDiffPatchView> {
  static const double _sideBySideMinimumWidth = 640;

  late GitDiffPatchResult _result;
  late GitDiffPatchWordResult _wordChanges;
  GitDiffSideBySideResult? _sideBySideRows;
  GitDiffPatchPresentation _presentation = GitDiffPatchPresentation.inline;

  @override
  void initState() {
    super.initState();
    _parsePatch();
  }

  @override
  void didUpdateWidget(covariant GitDiffPatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patch != widget.patch) {
      _parsePatch();
    }
  }

  void _parsePatch() {
    _result = parseGitDiffPatch(widget.patch);
    _wordChanges = computeGitDiffPatchWordChanges(_result);
    _sideBySideRows = _presentation == GitDiffPatchPresentation.sideBySide &&
            _result.canRender
        ? computeGitDiffSideBySideRows(_result)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final sideBySideFallback = _presentation ==
            GitDiffPatchPresentation.sideBySide &&
        _sideBySideRows != null &&
        !_sideBySideRows!.canRender;
    if (!_result.canRender || sideBySideFallback) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          widget.patch,
          key: const ValueKey('git-diff-raw-fallback'),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySideAvailable =
            constraints.maxWidth >= _sideBySideMinimumWidth;
        final useSideBySide = sideBySideAvailable &&
            _presentation == GitDiffPatchPresentation.sideBySide &&
            (_sideBySideRows?.canRender ?? false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                child: SegmentedButton<GitDiffPatchPresentation>(
                  key: const ValueKey('git-diff-presentation-toggle'),
                  segments: [
                    const ButtonSegment(
                      value: GitDiffPatchPresentation.inline,
                      icon: Icon(Icons.view_agenda_outlined, size: 14),
                      label: Text('内联'),
                      tooltip: '内联差异',
                    ),
                    ButtonSegment(
                      value: GitDiffPatchPresentation.sideBySide,
                      icon: const Icon(Icons.view_column_outlined, size: 14),
                      label: const Text('并排'),
                      tooltip:
                          sideBySideAvailable ? '并排差异' : '并排差异需要至少 640 逻辑像素宽度',
                      enabled: sideBySideAvailable &&
                          (_sideBySideRows?.canRender ?? true),
                    ),
                  ],
                  selected: {
                    useSideBySide
                        ? GitDiffPatchPresentation.sideBySide
                        : GitDiffPatchPresentation.inline,
                  },
                  onSelectionChanged: (selection) {
                    final presentation = selection.first;
                    setState(() {
                      _presentation = presentation;
                      if (presentation == GitDiffPatchPresentation.sideBySide &&
                          _sideBySideRows == null) {
                        _sideBySideRows = computeGitDiffSideBySideRows(_result);
                      }
                    });
                  },
                ),
              ),
            ),
            Expanded(
              child:
                  useSideBySide ? _buildSideBySideList() : _buildInlineList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInlineList() => ListView.builder(
        key: const ValueKey('git-diff-patch-rows'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _result.lines.length,
        itemBuilder: (context, index) => _GitDiffPatchRow(
          line: _result.lines[index],
          wordChanges: _wordChanges.changesForRow(index),
        ),
      );

  Widget _buildSideBySideList() {
    final rows = _sideBySideRows?.rows ?? const <GitDiffSideBySideRow>[];
    return ListView.builder(
      key: const ValueKey('git-diff-side-by-side-rows'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildSideBySideRow(rows[index]),
    );
  }

  Widget _buildSideBySideRow(GitDiffSideBySideRow row) {
    final fullWidthLine = row.fullWidthLine;
    if (fullWidthLine != null) {
      final color = switch (fullWidthLine.kind) {
        GitDiffPatchLineKind.hunk => const Color(0xFF9CDCFE),
        GitDiffPatchLineKind.marker ||
        GitDiffPatchLineKind.metadata =>
          const Color(0xFF9299A3),
        _ => const Color(0xFFD4D4D4),
      };
      final background = fullWidthLine.kind == GitDiffPatchLineKind.hunk
          ? const Color(0x33264F78)
          : Colors.transparent;
      return Container(
        key: ValueKey('git-diff-side-by-side-full-${row.rowIndex}'),
        height: 20,
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SelectableText(
          fullWidthLine.text,
          key: ValueKey('git-diff-side-by-side-full-text-${row.rowIndex}'),
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('git-diff-side-by-side-row-${row.rowIndex}'),
      height: 20,
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(child: _buildSideBySideCell(row.originalLine, 'old')),
          const SizedBox(
            width: 1,
            child: ColoredBox(color: Color(0xFF3C3C3C)),
          ),
          Expanded(child: _buildSideBySideCell(row.modifiedLine, 'new')),
        ],
      ),
    );
  }

  Widget _buildSideBySideCell(GitDiffPatchLine? line, String side) {
    if (line == null) {
      return Container(
        key: ValueKey('git-diff-side-by-side-$side-empty'),
        height: 20,
      );
    }

    final background = switch (line.kind) {
      GitDiffPatchLineKind.removed => const Color(0x33CF222E),
      GitDiffPatchLineKind.added => const Color(0x332DA44E),
      _ => Colors.transparent,
    };
    final textColor = switch (line.kind) {
      GitDiffPatchLineKind.added => const Color(0xFFC3E6CB),
      GitDiffPatchLineKind.removed => const Color(0xFFFFC9C9),
      _ => const Color(0xFFD4D4D4),
    };
    final marker = switch (line.kind) {
      GitDiffPatchLineKind.added => '+',
      GitDiffPatchLineKind.removed => '−',
      _ => '',
    };
    final highlightBackground = line.kind == GitDiffPatchLineKind.removed
        ? const Color(0xFF70272B)
        : const Color(0xFF285E37);
    final highlightForeground = line.kind == GitDiffPatchLineKind.removed
        ? const Color(0xFFFFE5E7)
        : const Color(0xFFE6FFE9);

    return Container(
      key: ValueKey('git-diff-side-by-side-$side-cell-${line.rowIndex}'),
      color: background,
      child: Row(
        children: [
          _buildLineNumber(
            side == 'old' ? line.originalLineNumber : line.modifiedLineNumber,
          ),
          SizedBox(
            width: 12,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: _buildSideBySideSelectableText(
              line.text,
              textColor,
              rowIndex: line.rowIndex,
              side: side,
              wordChanges: _wordChanges.changesForRow(line.rowIndex),
              highlightBackground: highlightBackground,
              highlightForeground: highlightForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumber(int? number) => SizedBox(
        width: 42,
        child: Text(
          number?.toString() ?? '',
          textAlign: TextAlign.right,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFF858B95),
            fontFamily: 'monospace',
            fontSize: 10,
            height: 1.4,
          ),
        ),
      );

  Widget _buildSideBySideSelectableText(
    String value,
    Color color, {
    required int rowIndex,
    required String side,
    required GitDiffPatchWordLineChanges? wordChanges,
    required Color highlightBackground,
    required Color highlightForeground,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    );
    final ranges = wordChanges?.ranges ?? const <GitDiffWordRange>[];
    final spans = _buildSideBySideWordSpans(
      value,
      ranges,
      highlightBackground,
      highlightForeground,
    );
    final key = ValueKey<String>('git-diff-side-by-side-$side-text-$rowIndex');
    final selectable = spans == null
        ? SelectableText(
            value,
            key: key,
            maxLines: 1,
            style: textStyle,
          )
        : SelectableText.rich(
            TextSpan(style: textStyle, children: spans),
            key: key,
            maxLines: 1,
          );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: selectable,
    );
  }

  List<TextSpan>? _buildSideBySideWordSpans(
    String value,
    List<GitDiffWordRange> ranges,
    Color background,
    Color foreground,
  ) {
    if (ranges.isEmpty) return null;
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.startUtf16 < cursor ||
          range.endUtf16 <= range.startUtf16 ||
          range.endUtf16 > value.length) {
        return null;
      }
      if (range.startUtf16 > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, range.startUtf16)));
      }
      spans.add(TextSpan(
        text: value.substring(range.startUtf16, range.endUtf16),
        style: TextStyle(backgroundColor: background, color: foreground),
      ));
      cursor = range.endUtf16;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }
}

class _GitDiffPatchRow extends StatelessWidget {
  const _GitDiffPatchRow({
    required this.line,
    required this.wordChanges,
  });

  final GitDiffPatchLine line;
  final GitDiffPatchWordLineChanges? wordChanges;

  @override
  Widget build(BuildContext context) {
    final background = switch (line.kind) {
      GitDiffPatchLineKind.added => const Color(0x332DA44E),
      GitDiffPatchLineKind.removed => const Color(0x33CF222E),
      GitDiffPatchLineKind.hunk => const Color(0x33264F78),
      _ => Colors.transparent,
    };
    final textColor = switch (line.kind) {
      GitDiffPatchLineKind.added => const Color(0xFFC3E6CB),
      GitDiffPatchLineKind.removed => const Color(0xFFFFC9C9),
      GitDiffPatchLineKind.hunk => const Color(0xFF9CDCFE),
      GitDiffPatchLineKind.metadata ||
      GitDiffPatchLineKind.marker =>
        const Color(0xFF9299A3),
      GitDiffPatchLineKind.context => const Color(0xFFD4D4D4),
    };

    return Container(
      key: ValueKey('git-diff-row-${line.rowIndex}'),
      height: 20,
      color: background,
      child: switch (line.kind) {
        GitDiffPatchLineKind.context ||
        GitDiffPatchLineKind.added ||
        GitDiffPatchLineKind.removed =>
          _buildSourceRow(textColor),
        _ => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildSelectableText(line.text, textColor),
          ),
      },
    );
  }

  Widget _buildSourceRow(Color textColor) {
    final prefix = switch (line.kind) {
      GitDiffPatchLineKind.added => '+',
      GitDiffPatchLineKind.removed => '-',
      _ => ' ',
    };
    const gutterColor = Color(0xFF858B95);
    return Row(
      children: [
        _lineNumber(line.originalLineNumber, gutterColor),
        _lineNumber(line.modifiedLineNumber, gutterColor),
        SizedBox(
          width: 14,
          child: Text(
            prefix,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
        Expanded(
          child: _buildSelectableText(
            line.text,
            textColor,
            rowIndex: line.rowIndex,
            wordChanges: wordChanges,
            highlightBackground: line.kind == GitDiffPatchLineKind.removed
                ? const Color(0xFF70272B)
                : const Color(0xFF285E37),
            highlightForeground: line.kind == GitDiffPatchLineKind.removed
                ? const Color(0xFFFFE5E7)
                : const Color(0xFFE6FFE9),
          ),
        ),
      ],
    );
  }

  Widget _lineNumber(int? number, Color color) => SizedBox(
        width: 42,
        child: Text(
          number?.toString() ?? '',
          textAlign: TextAlign.right,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 10,
            height: 1.4,
          ),
        ),
      );

  Widget _buildSelectableText(
    String value,
    Color color, {
    int? rowIndex,
    String? keyPrefix,
    GitDiffPatchWordLineChanges? wordChanges,
    Color? highlightBackground,
    Color? highlightForeground,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    );
    final ranges = wordChanges?.ranges ?? const <GitDiffWordRange>[];
    final spans = _buildWordSpans(
      value,
      ranges,
      highlightBackground,
      highlightForeground,
    );
    final key = rowIndex == null
        ? null
        : ValueKey<String>(keyPrefix == null
            ? 'git-diff-text-$rowIndex'
            : 'git-diff-$keyPrefix-text-$rowIndex');
    final selectable = spans == null
        ? SelectableText(
            value,
            key: key,
            maxLines: 1,
            style: textStyle,
          )
        : SelectableText.rich(
            TextSpan(style: textStyle, children: spans),
            key: key,
            maxLines: 1,
          );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: selectable,
    );
  }

  List<TextSpan>? _buildWordSpans(
    String value,
    List<GitDiffWordRange> ranges,
    Color? background,
    Color? foreground,
  ) {
    if (ranges.isEmpty || background == null || foreground == null) {
      return null;
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.startUtf16 < cursor ||
          range.endUtf16 <= range.startUtf16 ||
          range.endUtf16 > value.length) {
        return null;
      }
      if (range.startUtf16 > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, range.startUtf16)));
      }
      spans.add(TextSpan(
        text: value.substring(range.startUtf16, range.endUtf16),
        style: TextStyle(
          backgroundColor: background,
          color: foreground,
        ),
      ));
      cursor = range.endUtf16;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }
}
