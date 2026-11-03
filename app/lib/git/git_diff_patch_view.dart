import 'package:flutter/material.dart';

import 'git_diff_patch.dart';
import 'git_diff_word_highlights.dart';

/// Lazy inline renderer for a Git unified text patch.
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
  late GitDiffPatchResult _result;
  late GitDiffPatchWordResult _wordChanges;

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
  }

  @override
  Widget build(BuildContext context) {
    if (!_result.canRender) {
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

    return ListView.builder(
      key: const ValueKey('git-diff-patch-rows'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _result.lines.length,
      itemBuilder: (context, index) => _GitDiffPatchRow(
        line: _result.lines[index],
        wordChanges: _wordChanges.changesForRow(index),
      ),
    );
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
    final key =
        rowIndex == null ? null : ValueKey<String>('git-diff-text-$rowIndex');
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
