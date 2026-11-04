import 'dart:math' as math;

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
  });

  final String base;
  final String input1;
  final String input2;
  final Widget resultEditor;

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
        ),
      ];

  Widget _buildResultPane() => _MergeResultPane(
        resultEditor: widget.resultEditor,
      );
}

class _MergeSourcePane extends StatelessWidget {
  const _MergeSourcePane({
    super.key,
    required this.title,
    required this.text,
  });

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$title source, read-only',
      child: _MergePaneFrame(
        title: title,
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
  const _MergePaneFrame({required this.title, required this.child});

  final String title;
  final Widget child;

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
            child: Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
