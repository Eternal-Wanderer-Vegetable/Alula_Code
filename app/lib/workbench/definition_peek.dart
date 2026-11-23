import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../bridge/alula_core.dart';

typedef DefinitionPeekEntry = ({String path, DefinitionTarget target});
typedef DefinitionPeekLine = ({
  int number,
  String text,
  int highlightStart,
  int highlightEnd,
});

const _contextBefore = 3;
const _previewLines = 9;
const _lineWidth = 512;
const _maxPreviewFileBytes = 4 * 1024 * 1024;

int _firstPreviewLine(DefinitionTarget target) =>
    math.max(0, target.line - _contextBefore);

int _firstPreviewColumn(DefinitionTarget target) =>
    target.character < _lineWidth ? 0 : target.character - _lineWidth ~/ 3;

DefinitionPeekLine _previewLine(int number, String text, int start, int end) {
  final low = _scalarBoundary(text, start.clamp(0, text.length));
  final high = _scalarBoundary(text, end.clamp(low, text.length));
  return (number: number, text: text, highlightStart: low, highlightEnd: high);
}

/// Open targets use the live Rust buffer, including unsaved edits.
List<DefinitionPeekLine> definitionPeekOpenDocument(
  AlulaDoc document,
  DefinitionTarget target,
) {
  final low = document.positionOffset(target.line, target.character);
  final high = document.positionOffset(
    target.endLine ?? target.line,
    target.endCharacter ?? target.character,
  );
  final lines = document.readLines(
    firstLine: _firstPreviewLine(target),
    maxLines: _previewLines,
    horizontalStartUtf16: _firstPreviewColumn(target),
    maxLineUtf16: _lineWidth,
  );
  return [
    for (final line in lines.lines)
      _previewLine(line.line + 1, line.text, low.offsetUtf16 - line.startUtf16,
          high.offsetUtf16 - line.startUtf16),
  ];
}

/// Run off the UI isolate and retain just the visible excerpt.
List<DefinitionPeekLine> definitionPeekFile(DefinitionPeekEntry entry) {
  final stat = File(entry.path).statSync();
  if (stat.type != FileSystemEntityType.file ||
      stat.size > _maxPreviewFileBytes) {
    return const [];
  }
  final text = AlulaCore.load().workspace.readFileDocument(entry.path).content;
  final target = entry.target;
  final first = _firstPreviewLine(target);
  final endLine = target.endLine ?? target.line;
  final endCharacter = target.endCharacter ?? target.character;
  final horizontalStart = _firstPreviewColumn(target);
  var offset = 0;
  final lines = <DefinitionPeekLine>[];
  for (var line = 0; line < first + _previewLines; line++) {
    final newline = text.indexOf('\n', offset);
    final end = newline < 0 ? text.length : newline;
    if (line >= first) {
      var from = math.min(end, offset + horizontalStart);
      if (from < end && _isLowSurrogate(text.codeUnitAt(from))) from--;
      var until = math.min(end, from + _lineWidth);
      if (until < end && _isLowSurrogate(text.codeUnitAt(until))) until--;
      final column = from - offset;
      final start = line < target.line
          ? until - from
          : line == target.line
              ? target.character - column
              : 0;
      final finish = line > endLine
          ? 0
          : line == endLine
              ? endCharacter - column
              : until - from;
      lines.add(
          _previewLine(line + 1, text.substring(from, until), start, finish));
    }
    if (newline < 0) break;
    offset = newline + 1;
  }
  return lines;
}

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

int _scalarBoundary(String text, int offset) => offset > 0 &&
        offset < text.length &&
        _isLowSurrogate(text.codeUnitAt(offset))
    ? offset - 1
    : offset;

class DefinitionPeek extends StatefulWidget {
  const DefinitionPeek({
    super.key,
    required this.entries,
    required this.loadPreview,
    required this.onOpen,
    required this.onClose,
    required this.onRemoved,
  });

  final List<DefinitionPeekEntry> entries;
  final Future<List<DefinitionPeekLine>> Function(DefinitionPeekEntry)
      loadPreview;
  final ValueChanged<DefinitionPeekEntry> onOpen;
  final VoidCallback onClose;
  final VoidCallback onRemoved;

  @override
  State<DefinitionPeek> createState() => _DefinitionPeekState();
}

class _DefinitionPeekState extends State<DefinitionPeek> {
  static const _rowHeight = 32.0;
  final _listFocus = FocusNode(debugLabel: 'definition-peek-list');
  final _resultsScroll = ScrollController();
  var _selected = 0;
  late Future<List<DefinitionPeekLine>> _preview;
  bool _readingPreview = false;
  ({
    DefinitionPeekEntry entry,
    Completer<List<DefinitionPeekLine>> result,
  })? _pendingPreview;

  @override
  void initState() {
    super.initState();
    _preview = _requestPreview(widget.entries.first);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pendingPreview?.result.complete(const []);
    _pendingPreview = null;
    _resultsScroll.dispose();
    _listFocus.dispose();
    widget.onRemoved();
    super.dispose();
  }

  Future<List<DefinitionPeekLine>> _requestPreview(DefinitionPeekEntry entry) {
    _pendingPreview?.result.complete(const []);
    final result = Completer<List<DefinitionPeekLine>>();
    _pendingPreview = (entry: entry, result: result);
    if (!_readingPreview) unawaited(_readPreviews());
    return result.future;
  }

  Future<void> _readPreviews() async {
    _readingPreview = true;
    try {
      while (mounted && _pendingPreview != null) {
        final request = _pendingPreview!;
        _pendingPreview = null;
        try {
          request.result.complete(await widget.loadPreview(request.entry));
        } catch (_) {
          request.result.complete(const []);
        }
      }
    } finally {
      _readingPreview = false;
    }
  }

  void _select(int next) {
    if (next == _selected) return;
    setState(() {
      _selected = next;
      _preview = _requestPreview(widget.entries[next]);
    });
    if (!_resultsScroll.hasClients) return;
    final position = _resultsScroll.position;
    final top = next * _rowHeight;
    final bottom = top + _rowHeight;
    final offset = top < position.pixels
        ? top
        : math.max(position.pixels, bottom - position.viewportDimension);
    _resultsScroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (!_listFocus.hasFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      _select((_selected + delta).clamp(0, widget.entries.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && event is KeyDownEvent) {
      widget.onOpen(widget.entries[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: _handleKey,
      child: Material(
        elevation: 6,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          height: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Expanded(child: Text('定义 (${widget.entries.length})')),
                    IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: '关闭定义预览',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _buildPreview(context)),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 2,
                      child: Focus(
                        focusNode: _listFocus,
                        child: ListView.builder(
                          controller: _resultsScroll,
                          itemExtent: _rowHeight,
                          itemCount: widget.entries.length,
                          itemBuilder: (context, index) {
                            final entry = widget.entries[index];
                            final target = entry.target;
                            return Semantics(
                              selected: index == _selected,
                              label: '${entry.path}:${target.line + 1}',
                              child: InkWell(
                                canRequestFocus: false,
                                onTap: () {
                                  _listFocus.requestFocus();
                                  _select(index);
                                },
                                onDoubleTap: () => widget.onOpen(entry),
                                child: ColoredBox(
                                  color: index == _selected
                                      ? colors.primaryContainer
                                      : Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.basename(entry.path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                            '${target.line + 1}:${target.character + 1}'),
                                      ],
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<DefinitionPeekLine>>(
      key: const ValueKey('definition-peek-preview'),
      future: _preview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: Text('正在读取定义…'));
        }
        final lines = snapshot.data;
        if (lines == null || lines.isEmpty) {
          return const Center(child: Text('无法预览定义'));
        }
        return SingleChildScrollView(
          key: ValueKey(_selected),
          padding: const EdgeInsets.all(8),
          child: SelectionArea(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                children: [
                  for (final line in lines) ...[
                    TextSpan(
                      text: '${line.number.toString().padLeft(4)}  ',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    TextSpan(text: line.text.substring(0, line.highlightStart)),
                    TextSpan(
                      text: line.text
                          .substring(line.highlightStart, line.highlightEnd),
                      style:
                          TextStyle(backgroundColor: colors.tertiaryContainer),
                    ),
                    TextSpan(
                        text: '${line.text.substring(line.highlightEnd)}\n'),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
