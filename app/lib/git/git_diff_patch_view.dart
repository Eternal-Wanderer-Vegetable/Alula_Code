import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'git_diff_navigation.dart';
import 'git_diff_patch.dart';
import 'git_diff_side_by_side.dart';
import 'git_diff_word_highlights.dart';

enum GitDiffPatchPresentation { inline, sideBySide }

const BoxDecoration _currentChangeDecoration = BoxDecoration(
  border: Border(
    left: BorderSide(
      color: Color(0xFF75BEFF),
      width: 3,
    ),
  ),
);

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
  static const double _diffRowHeight = 20;

  late GitDiffPatchResult _result;
  late GitDiffPatchWordResult _wordChanges;
  late List<GitDiffPatchChange> _changeTargets;
  GitDiffSideBySideResult? _sideBySideRows;
  GitDiffPatchPresentation _presentation = GitDiffPatchPresentation.inline;
  int _currentChangeIndex = -1;
  final ScrollController _inlineScrollController = ScrollController();
  final ScrollController _sideBySideScrollController = ScrollController();

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
      _resetScrollPositions();
    }
  }

  @override
  void dispose() {
    _inlineScrollController.dispose();
    _sideBySideScrollController.dispose();
    super.dispose();
  }

  void _parsePatch() {
    _result = parseGitDiffPatch(widget.patch);
    _wordChanges = computeGitDiffPatchWordChanges(_result);
    _changeTargets = computeGitDiffPatchChanges(_result);
    _currentChangeIndex = -1;
    _sideBySideRows = _presentation == GitDiffPatchPresentation.sideBySide &&
            _result.canRender
        ? computeGitDiffSideBySideRows(_result)
        : null;
  }

  void _resetScrollPositions() {
    for (final controller in [
      _inlineScrollController,
      _sideBySideScrollController,
    ]) {
      if (controller.hasClients) controller.jumpTo(0);
    }
  }

  KeyEventResult _handleNavigationKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.f7 ||
        _changeTargets.isEmpty) {
      return KeyEventResult.ignored;
    }
    _navigateToChange(
      HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
    );
    return KeyEventResult.handled;
  }

  void _navigateToChange(int direction) {
    final count = _changeTargets.length;
    if (count == 0) return;

    final current = _currentChangeIndex;
    final next = current < 0
        ? (direction > 0 ? 0 : count - 1)
        : (current + direction + count) % count;
    setState(() => _currentChangeIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealCurrentChange();
    });
  }

  void _revealCurrentChange() {
    if (_currentChangeIndex < 0 ||
        _currentChangeIndex >= _changeTargets.length) {
      return;
    }

    final useSideBySide = _sideBySideScrollController.hasClients;
    final controller =
        useSideBySide ? _sideBySideScrollController : _inlineScrollController;
    if (!controller.hasClients) return;

    final target = _changeTargets[_currentChangeIndex];
    var rowIndex = target.firstRowIndex;
    if (useSideBySide) {
      final rows = _sideBySideRows?.rows ?? const <GitDiffSideBySideRow>[];
      final projectedIndex = rows.indexWhere(
        (row) =>
            row.originalLine?.rowIndex == target.firstRowIndex ||
            row.modifiedLine?.rowIndex == target.firstRowIndex,
      );
      if (projectedIndex >= 0) rowIndex = projectedIndex;
    }

    final position = controller.position;
    final rowTop = 4 + rowIndex * _diffRowHeight;
    final desiredOffset =
        rowTop - (position.viewportDimension - _diffRowHeight) / 2;
    final offset = desiredOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    unawaited(controller.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    ));
  }

  int? _currentSideBySideRowIndex(List<GitDiffSideBySideRow> rows) {
    if (_currentChangeIndex < 0 ||
        _currentChangeIndex >= _changeTargets.length) {
      return null;
    }
    final sourceRowIndex = _changeTargets[_currentChangeIndex].firstRowIndex;
    final index = rows.indexWhere(
      (row) =>
          row.originalLine?.rowIndex == sourceRowIndex ||
          row.modifiedLine?.rowIndex == sourceRowIndex,
    );
    return index < 0 ? null : index;
  }

  String _changeAnnouncement() {
    if (_changeTargets.isEmpty) return '无差异';
    if (_currentChangeIndex < 0) {
      return '尚未选择差异，共 ${_changeTargets.length} 处';
    }

    final target = _changeTargets[_currentChangeIndex];
    final lines = <String>[];
    if (target.originalLineNumber != null) {
      lines.add('原文第 ${target.originalLineNumber} 行');
    }
    if (target.modifiedLineNumber != null) {
      lines.add('修改后第 ${target.modifiedLineNumber} 行');
    }
    final location = lines.isEmpty ? '' : '，${lines.join('，')}';
    return '差异 ${_currentChangeIndex + 1} / ${_changeTargets.length}$location';
  }

  Widget _buildNavigationToolbar({
    required bool sideBySideAvailable,
    required bool useSideBySide,
  }) {
    final displayedChange =
        _currentChangeIndex < 0 ? 0 : _currentChangeIndex + 1;
    final countText = '$displayedChange / ${_changeTargets.length}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('git-diff-previous-change'),
          tooltip: '上一处差异 (Shift+F7)',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed:
              _changeTargets.isEmpty ? null : () => _navigateToChange(-1),
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
        ),
        IconButton(
          key: const ValueKey('git-diff-next-change'),
          tooltip: '下一处差异 (F7)',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed: _changeTargets.isEmpty ? null : () => _navigateToChange(1),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
        ),
        Semantics(
          key: const ValueKey('git-diff-change-count'),
          liveRegion: true,
          label: _changeAnnouncement(),
          child: SizedBox(
            width: 54,
            child: Text(
              countText,
              key: const ValueKey('git-diff-change-count-text'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SegmentedButton<GitDiffPatchPresentation>(
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
              tooltip: sideBySideAvailable ? '并排差异' : '并排差异需要至少 640 逻辑像素宽度',
              enabled:
                  sideBySideAvailable && (_sideBySideRows?.canRender ?? true),
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
            if (_currentChangeIndex >= 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _revealCurrentChange();
              });
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sideBySideFallback =
        _presentation == GitDiffPatchPresentation.sideBySide &&
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

    return Focus(
      autofocus: true,
      onKeyEvent: _handleNavigationKey,
      child: LayoutBuilder(
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
                  child: _buildNavigationToolbar(
                    sideBySideAvailable: sideBySideAvailable,
                    useSideBySide: useSideBySide,
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
      ),
    );
  }

  Widget _buildInlineList() => ListView.builder(
        key: const ValueKey('git-diff-patch-rows'),
        controller: _inlineScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemExtent: _diffRowHeight,
        itemCount: _result.lines.length,
        itemBuilder: (context, index) {
          final line = _result.lines[index];
          final isCurrentChangeTarget = _currentChangeIndex >= 0 &&
              _changeTargets[_currentChangeIndex].firstRowIndex ==
                  line.rowIndex;
          return _GitDiffPatchRow(
            line: line,
            wordChanges: _wordChanges.changesForRow(index),
            isCurrentChangeTarget: isCurrentChangeTarget,
          );
        },
      );

  Widget _buildSideBySideList() {
    final rows = _sideBySideRows?.rows ?? const <GitDiffSideBySideRow>[];
    final currentRowIndex = _currentSideBySideRowIndex(rows);
    return ListView.builder(
      key: const ValueKey('git-diff-side-by-side-rows'),
      controller: _sideBySideScrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: _diffRowHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildSideBySideRow(
        rows[index],
        isCurrentChangeTarget: index == currentRowIndex,
      ),
    );
  }

  Widget _buildSideBySideRow(
    GitDiffSideBySideRow row, {
    required bool isCurrentChangeTarget,
  }) {
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
        foregroundDecoration:
            isCurrentChangeTarget ? _currentChangeDecoration : null,
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
      foregroundDecoration:
          isCurrentChangeTarget ? _currentChangeDecoration : null,
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
    required this.isCurrentChangeTarget,
  });

  final GitDiffPatchLine line;
  final GitDiffPatchWordLineChanges? wordChanges;
  final bool isCurrentChangeTarget;

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
      foregroundDecoration:
          isCurrentChangeTarget ? _currentChangeDecoration : null,
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
