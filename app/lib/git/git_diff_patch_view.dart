import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'git_diff_navigation.dart';
import 'git_diff_moved_blocks.dart';
import 'git_diff_moved_blocks_projection.dart';
import 'git_diff_patch.dart';
import 'git_diff_whitespace_projection.dart';
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
    this.navigationController,
    this.onNavigationAvailabilityChanged,
    super.key,
  });

  final String patch;
  final GitDiffPatchNavigationController? navigationController;
  final ValueChanged<bool>? onNavigationAvailabilityChanged;

  @override
  State<GitDiffPatchView> createState() => _GitDiffPatchViewState();
}

class _GitDiffPatchViewState extends State<GitDiffPatchView> {
  static const double _sideBySideMinimumWidth = 640;
  static const double _diffRowHeight = 20;

  final Object _navigationOwner = Object();
  late GitDiffPatchResult _result;
  late GitDiffProjectionResult _projection;
  GitDiffPatchPresentation _presentation = GitDiffPatchPresentation.inline;
  bool _showMovedBlocks = false;
  GitDiffMovedBlocksProjectionResult? _movedBlocksProjection;
  final Map<int, _GitDiffMovedBlockLineMarker> _originalMovedLineMarkers = {};
  final Map<int, _GitDiffMovedBlockLineMarker> _modifiedMovedLineMarkers = {};
  int _currentChangeIndex = -1;
  bool? _reportedNavigationAvailability;
  final ScrollController _inlineScrollController = ScrollController();
  final ScrollController _sideBySideScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _parsePatch();
    _attachNavigationController();
    _notifyNavigationAvailability(force: true);
  }

  @override
  void didUpdateWidget(covariant GitDiffPatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patch != widget.patch) {
      _parsePatch();
      _resetScrollPositions();
    }
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?.detach(owner: _navigationOwner);
      _attachNavigationController();
    } else {
      widget.navigationController?.updateAvailability(
        owner: _navigationOwner,
        canNavigate: _projection.changes.isNotEmpty,
      );
    }
    _notifyNavigationAvailability(
      force: oldWidget.onNavigationAvailabilityChanged !=
          widget.onNavigationAvailabilityChanged,
    );
  }

  @override
  void dispose() {
    final callback = widget.onNavigationAvailabilityChanged;
    final wasAvailable = _reportedNavigationAvailability ?? false;
    widget.navigationController?.detach(owner: _navigationOwner);
    if (wasAvailable && callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback(false));
    }
    _inlineScrollController.dispose();
    _sideBySideScrollController.dispose();
    super.dispose();
  }

  void _attachNavigationController() {
    widget.navigationController?.attach(
      owner: _navigationOwner,
      navigateToChange: _navigateToChange,
      canNavigate: _projection.changes.isNotEmpty,
    );
  }

  void _notifyNavigationAvailability({bool force = false}) {
    final canNavigate = _projection.changes.isNotEmpty;
    widget.navigationController?.updateAvailability(
      owner: _navigationOwner,
      canNavigate: canNavigate,
    );
    final callback = widget.onNavigationAvailabilityChanged;
    if (callback == null ||
        (!force && _reportedNavigationAvailability == canNavigate)) {
      return;
    }
    _reportedNavigationAvailability = canNavigate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(canNavigate);
    });
  }

  void _parsePatch() {
    _result = parseGitDiffPatch(widget.patch);
    _projection = projectGitDiffPatchIgnoringTrimWhitespace(_result);
    _currentChangeIndex = -1;
    _updateMovedBlocksProjection();
  }

  void _toggleMovedBlocks() {
    setState(() {
      _showMovedBlocks = !_showMovedBlocks;
      _updateMovedBlocksProjection();
    });
  }

  void _updateMovedBlocksProjection() {
    _movedBlocksProjection = null;
    _originalMovedLineMarkers.clear();
    _modifiedMovedLineMarkers.clear();
    if (!_showMovedBlocks || !_result.canRender || !_projection.canRender) {
      return;
    }

    final movedBlocks = computeGitDiffMovedBlocks(widget.patch);
    final projected = projectGitDiffMovedBlocks(
      movedBlocks,
      _result,
      _projection,
    );
    if (!projected.canRender) return;
    _movedBlocksProjection = projected;

    for (final block in projected.blocks) {
      for (var offset = 0; offset < block.block.lineCount; offset++) {
        final isStart = offset == 0;
        final isEnd = offset + 1 == block.block.lineCount;
        _originalMovedLineMarkers[block.originalStartRowIndex + offset] =
            _GitDiffMovedBlockLineMarker(
          isStart: isStart,
          isEnd: isEnd,
        );
        _modifiedMovedLineMarkers[block.modifiedStartRowIndex + offset] =
            _GitDiffMovedBlockLineMarker(
          isStart: isStart,
          isEnd: isEnd,
        );
      }
    }
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
        _projection.changes.isEmpty) {
      return KeyEventResult.ignored;
    }
    _navigateToChange(
      HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
    );
    return KeyEventResult.handled;
  }

  void _navigateToChange(int direction) {
    final count = _projection.changes.length;
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
        _currentChangeIndex >= _projection.changes.length) {
      return;
    }

    final useSideBySide = _sideBySideScrollController.hasClients;
    final controller =
        useSideBySide ? _sideBySideScrollController : _inlineScrollController;
    if (!controller.hasClients) return;

    final target = _projection.changes[_currentChangeIndex];
    final rowIndex =
        useSideBySide ? target.sideBySideRowIndex : target.inlineRowIndex;

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

  int? _currentSideBySideRowIndex() {
    if (_currentChangeIndex < 0 ||
        _currentChangeIndex >= _projection.changes.length) {
      return null;
    }
    return _projection.changes[_currentChangeIndex].sideBySideRowIndex;
  }

  String _changeAnnouncement() {
    if (_projection.changes.isEmpty) return '无差异';
    if (_currentChangeIndex < 0) {
      return '尚未选择差异，共 ${_projection.changes.length} 处';
    }

    final target = _projection.changes[_currentChangeIndex];
    final lines = <String>[];
    if (target.originalLineNumber != null) {
      lines.add('原文第 ${target.originalLineNumber} 行');
    }
    if (target.modifiedLineNumber != null) {
      lines.add('修改后第 ${target.modifiedLineNumber} 行');
    }
    final location = lines.isEmpty ? '' : '，${lines.join('，')}';
    return '差异 ${_currentChangeIndex + 1} / ${_projection.changes.length}$location';
  }

  Widget _buildNavigationToolbar({
    required bool sideBySideAvailable,
    required bool useSideBySide,
  }) {
    final displayedChange =
        _currentChangeIndex < 0 ? 0 : _currentChangeIndex + 1;
    final countText = '$displayedChange / ${_projection.changes.length}';
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
              _projection.changes.isEmpty ? null : () => _navigateToChange(-1),
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
        ),
        IconButton(
          key: const ValueKey('git-diff-next-change'),
          tooltip: '下一处差异 (F7)',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed:
              _projection.changes.isEmpty ? null : () => _navigateToChange(1),
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
        if (sideBySideAvailable)
          IconButton(
            key: const ValueKey('git-diff-toggle-moved-blocks'),
            tooltip: '移动代码块标记（仅并排视图）',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            onPressed: _toggleMovedBlocks,
            style: _showMovedBlocks
                ? IconButton.styleFrom(
                    backgroundColor: const Color(0x332DA44E),
                    foregroundColor: const Color(0xFFC3E6CB),
                  )
                : null,
            icon: const Icon(Icons.compare_arrows, size: 16),
          ),
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
              enabled: sideBySideAvailable && _projection.canRender,
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
    if (!_result.canRender || !_projection.canRender) {
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
              _presentation == GitDiffPatchPresentation.sideBySide;
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
        itemCount: _projection.inlineRows.length,
        itemBuilder: (context, index) {
          final row = _projection.inlineRows[index];
          final line = row.line;
          final isCurrentChangeTarget = _currentChangeIndex >= 0 &&
              _projection.changes[_currentChangeIndex].inlineRowIndex == index;
          return _GitDiffPatchRow(
            line: line,
            wordChanges: row.wordChanges,
            isCurrentChangeTarget: isCurrentChangeTarget,
          );
        },
      );

  Widget _buildSideBySideList() {
    final rows = _projection.rows;
    final currentRowIndex = _currentSideBySideRowIndex();
    final list = ListView.builder(
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
    final movedBlocks = _movedBlocksProjection?.blocks ?? const [];
    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        if (_showMovedBlocks && movedBlocks.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sideBySideScrollController,
                builder: (context, _) => CustomPaint(
                  key: const ValueKey('git-diff-moved-block-connectors'),
                  painter: _GitDiffMovedBlocksConnectorPainter(
                    blocks: movedBlocks,
                    scrollOffset: _sideBySideScrollOffset,
                    rowHeight: _diffRowHeight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double get _sideBySideScrollOffset {
    final positions = _sideBySideScrollController.positions;
    return positions.length == 1 ? positions.single.pixels : 0;
  }

  Widget _buildSideBySideRow(
    GitDiffProjectionRow row, {
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
          Expanded(
            child: _buildSideBySideCell(
              row.originalLine,
              'old',
              wordChanges: row.originalWordChanges,
              movedMarker: _originalMovedLineMarkers[row.rowIndex],
            ),
          ),
          const SizedBox(
            width: 26,
            child: Center(
              child: SizedBox(
                width: 1,
                child: ColoredBox(color: Color(0xFF3C3C3C)),
              ),
            ),
          ),
          Expanded(
            child: _buildSideBySideCell(
              row.modifiedLine,
              'new',
              wordChanges: row.modifiedWordChanges,
              movedMarker: _modifiedMovedLineMarkers[row.rowIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBySideCell(
    GitDiffPatchLine? line,
    String side, {
    required List<GitDiffWordRange> wordChanges,
    _GitDiffMovedBlockLineMarker? movedMarker,
  }) {
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
      key: ValueKey(movedMarker == null
          ? 'git-diff-side-by-side-$side-cell-${line.rowIndex}'
          : 'git-diff-moved-$side-cell-${line.rowIndex}'),
      color: background,
      foregroundDecoration: movedMarker == null
          ? null
          : BoxDecoration(
              border: Border(
                top: movedMarker.isStart
                    ? const BorderSide(color: Color(0xFFB08D57), width: 1)
                    : BorderSide.none,
                bottom: movedMarker.isEnd
                    ? const BorderSide(color: Color(0xFFB08D57), width: 1)
                    : BorderSide.none,
                left: const BorderSide(color: Color(0xFFB08D57), width: 1),
                right: const BorderSide(color: Color(0xFFB08D57), width: 1),
              ),
            ),
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
              wordChanges: wordChanges,
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
    required List<GitDiffWordRange> wordChanges,
    required Color highlightBackground,
    required Color highlightForeground,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    );
    final spans = _buildSideBySideWordSpans(
      value,
      wordChanges,
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

class _GitDiffMovedBlockLineMarker {
  const _GitDiffMovedBlockLineMarker({
    required this.isStart,
    required this.isEnd,
  });

  final bool isStart;
  final bool isEnd;
}

class _GitDiffMovedBlocksConnectorPainter extends CustomPainter {
  const _GitDiffMovedBlocksConnectorPainter({
    required this.blocks,
    required this.scrollOffset,
    required this.rowHeight,
  });

  final List<GitDiffProjectedMovedBlock> blocks;
  final double scrollOffset;
  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (blocks.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final centerX = size.width / 2;
    final leftX = centerX - 12;
    final rightX = centerX + 12;
    final stroke = Paint()
      ..color = const Color(0xCCB08D57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final arrow = Paint()
      ..color = const Color(0xCCB08D57)
      ..style = PaintingStyle.fill;

    double centerOf(int start, int end) =>
        4 + ((start + end) / 2) * rowHeight - scrollOffset;

    for (final block in blocks) {
      final originalY = centerOf(
        block.originalStartRowIndex,
        block.originalEndRowIndexExclusive,
      );
      final modifiedY = centerOf(
        block.modifiedStartRowIndex,
        block.modifiedEndRowIndexExclusive,
      );
      if ((originalY < 0 && modifiedY < 0) ||
          (originalY > size.height && modifiedY > size.height)) {
        continue;
      }

      final path = Path()
        ..moveTo(leftX, originalY)
        ..cubicTo(
            centerX - 4, originalY, centerX + 4, modifiedY, rightX, modifiedY);
      canvas.drawPath(path, stroke);

      const arrowSize = 4.0;
      final arrowPath = Path()
        ..moveTo(rightX, modifiedY)
        ..lineTo(rightX - arrowSize, modifiedY - arrowSize / 2)
        ..lineTo(rightX - arrowSize, modifiedY + arrowSize / 2)
        ..close();
      canvas.drawPath(arrowPath, arrow);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
          covariant _GitDiffMovedBlocksConnectorPainter oldDelegate) =>
      oldDelegate.blocks != blocks ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.rowHeight != rowHeight;
}

class _GitDiffPatchRow extends StatelessWidget {
  const _GitDiffPatchRow({
    required this.line,
    required this.wordChanges,
    required this.isCurrentChangeTarget,
  });

  final GitDiffPatchLine line;
  final List<GitDiffWordRange> wordChanges;
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
    List<GitDiffWordRange>? wordChanges,
    Color? highlightBackground,
    Color? highlightForeground,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    );
    final ranges = wordChanges ?? const <GitDiffWordRange>[];
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
