import 'dart:math' as math;

import '../bridge/alula_core.dart';
import 'package:flutter/material.dart';

enum MergeEditorLayout { mixed, columns }

/// Presents frozen merge inputs beside or above the existing result editor.
/// The result widget remains owned by the Workbench's Rust document path.
class MergeEditorSurface extends StatefulWidget {
  const MergeEditorSurface({
    super.key,
    required this.base,
    required this.input1,
    required this.input2,
    required this.resultEditor,
    this.conflicts = const [],
    this.resolutions = const {},
    this.unresolvedConflictCount = 0,
    this.activeConflict,
    this.conflictRangesCurrent = true,
    this.onNavigatePrevious,
    this.onNavigateNext,
    this.onAcceptInput1,
    this.onAcceptInput2,
    this.onAcceptAllInput1,
    this.onAcceptAllInput2,
  });

  final String base;
  final String input1;
  final String input2;
  final Widget resultEditor;
  final List<AlulaMergeConflict> conflicts;
  final Map<int, AlulaMergeSide> resolutions;
  final int unresolvedConflictCount;
  final AlulaMergeConflict? activeConflict;
  final bool conflictRangesCurrent;
  final VoidCallback? onNavigatePrevious;
  final VoidCallback? onNavigateNext;
  final VoidCallback? onAcceptInput1;
  final VoidCallback? onAcceptInput2;
  final VoidCallback? onAcceptAllInput1;
  final VoidCallback? onAcceptAllInput2;

  @override
  State<MergeEditorSurface> createState() => _MergeEditorSurfaceState();
}

class _MergeEditorSurfaceState extends State<MergeEditorSurface> {
  static const double _columnLayoutMinWidth = 960;
  static const double _sourcePaneMinWidth = 220;

  MergeEditorLayout _layout = MergeEditorLayout.mixed;
  bool _showBase = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowColumnsFallback = _layout == MergeEditorLayout.columns &&
            constraints.maxWidth < _columnLayoutMinWidth;
        return Column(
          children: [
            _buildToolbar(narrowColumnsFallback),
            Expanded(
              child: narrowColumnsFallback
                  ? _buildMixedLayout()
                  : _layout == MergeEditorLayout.columns
                      ? _buildColumnsLayout()
                      : _buildMixedLayout(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(bool narrowColumnsFallback) {
    final activeConflict = widget.activeConflict;
    final activeConflictIndex = activeConflict == null
        ? -1
        : widget.conflicts
            .indexWhere((conflict) => conflict.id == activeConflict.id);
    final canNavigate =
        widget.conflictRangesCurrent && widget.unresolvedConflictCount > 0;
    final canAccept = widget.conflictRangesCurrent && activeConflict != null;
    final unresolvedSummary = widget.unresolvedConflictCount == 1
        ? '1 unresolved conflict'
        : '${widget.unresolvedConflictCount} unresolved conflicts';
    final conflictStatus = widget.conflicts.isEmpty
        ? 'No conflicts'
        : !widget.conflictRangesCurrent
            ? 'Conflict locations are out of date'
            : widget.unresolvedConflictCount == 0
                ? 'All ${widget.conflicts.length} '
                    'conflict${widget.conflicts.length == 1 ? '' : 's'} handled'
                : activeConflictIndex >= 0
                    ? 'Conflict ${activeConflictIndex + 1} of '
                        '${widget.conflicts.length} · '
                        '${widget.unresolvedConflictCount} unresolved'
                    : unresolvedSummary;
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Text('Merge Editor',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(width: 12),
            IconButton(
              key: const ValueKey('merge-editor-previous-unhandled-conflict'),
              tooltip: 'Go to Previous Unhandled Conflict',
              onPressed: canNavigate ? widget.onNavigatePrevious : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            ),
            IconButton(
              key: const ValueKey('merge-editor-next-unhandled-conflict'),
              tooltip: 'Go to Next Unhandled Conflict',
              onPressed: canNavigate ? widget.onNavigateNext : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            ),
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  conflictStatus,
                  key: const ValueKey('merge-editor-conflict-status'),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('merge-editor-accept-input1'),
              onPressed: canAccept &&
                      widget.resolutions[activeConflict.id] !=
                          AlulaMergeSide.input1
                  ? widget.onAcceptInput1
                  : null,
              child: const Text('Accept Input 1'),
            ),
            TextButton(
              key: const ValueKey('merge-editor-accept-input2'),
              onPressed: canAccept &&
                      widget.resolutions[activeConflict.id] !=
                          AlulaMergeSide.input2
                  ? widget.onAcceptInput2
                  : null,
              child: const Text('Accept Input 2'),
            ),
            TextButton(
              key: const ValueKey('merge-editor-layout-mixed'),
              onPressed: () => setState(
                () => _layout = MergeEditorLayout.mixed,
              ),
              child: Text(
                _layout == MergeEditorLayout.mixed ? '✓ Mixed' : 'Mixed',
              ),
            ),
            TextButton(
              key: const ValueKey('merge-editor-layout-columns'),
              onPressed: () => setState(
                () => _layout = MergeEditorLayout.columns,
              ),
              child: Text(
                _layout == MergeEditorLayout.columns ? '✓ Columns' : 'Columns',
              ),
            ),
            if (narrowColumnsFallback)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Columns uses Mixed at this width',
                  key: ValueKey('merge-editor-narrow-layout-hint'),
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            TextButton.icon(
              key: const ValueKey('merge-editor-toggle-base'),
              onPressed: () => setState(() => _showBase = !_showBase),
              icon: Icon(_showBase ? Icons.visibility_off : Icons.visibility,
                  size: 16),
              label: Text(_showBase ? 'Hide Base' : 'Show Base'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMixedLayout() {
    final sourcePanes = _buildSourcePanes();
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                constraints.maxWidth,
                sourcePanes.length * _sourcePaneMinWidth,
              );
              return SingleChildScrollView(
                key: const ValueKey('merge-editor-mixed-source-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final pane in sourcePanes) Expanded(child: pane),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(flex: 3, child: _buildResultPane()),
      ],
    );
  }

  Widget _buildColumnsLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pane in [..._buildSourcePanes(), _buildResultPane()])
          Expanded(child: pane),
      ],
    );
  }

  List<Widget> _buildSourcePanes() => [
        _MergeSourcePane(
          key: const ValueKey('merge-editor-pane-input1'),
          title: 'Input 1',
          text: widget.input1,
          headerAction: _bulkAcceptButton(
            key: const ValueKey('merge-editor-accept-all-input1'),
            tooltip: 'Accept All Incoming Changes from Left',
            onPressed: widget.onAcceptAllInput1,
          ),
        ),
        if (_showBase)
          _MergeSourcePane(
            key: const ValueKey('merge-editor-pane-base'),
            title: 'Base',
            text: widget.base,
          ),
        _MergeSourcePane(
          key: const ValueKey('merge-editor-pane-input2'),
          title: 'Input 2',
          text: widget.input2,
          headerAction: _bulkAcceptButton(
            key: const ValueKey('merge-editor-accept-all-input2'),
            tooltip: 'Accept All Current Changes from Right',
            onPressed: widget.onAcceptAllInput2,
          ),
        ),
      ];

  IconButton _bulkAcceptButton({
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final canAcceptAll =
        widget.conflictRangesCurrent && widget.conflicts.isNotEmpty;
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: canAcceptAll ? onPressed : null,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.done_all, size: 16),
    );
  }

  Widget _buildResultPane() => _MergeResultPane(
        resultEditor: widget.resultEditor,
      );
}

class _MergeSourcePane extends StatelessWidget {
  const _MergeSourcePane({
    super.key,
    required this.title,
    required this.text,
    this.headerAction,
  });

  final String title;
  final String text;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$title source, read-only',
      child: _MergePaneFrame(
        title: title,
        headerAction: headerAction,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: SelectableText(
            text,
            key: ValueKey('merge-editor-source-text-${title.toLowerCase()}'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ),
      ),
    );
  }
}

class _MergeResultPane extends StatelessWidget {
  const _MergeResultPane({required this.resultEditor});

  final Widget resultEditor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Editable merge result',
      child: _MergePaneFrame(
        title: 'Result',
        child: resultEditor,
      ),
    );
  }
}

class _MergePaneFrame extends StatelessWidget {
  const _MergePaneFrame({
    required this.title,
    required this.child,
    this.headerAction,
  });

  final String title;
  final Widget child;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('merge-editor-pane-${title.toLowerCase()}-frame'),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF181A1F),
        border: Border.all(color: const Color(0xFF343840)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.centerLeft,
            color: const Color(0xFF22252B),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
                if (headerAction != null) headerAction!,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
