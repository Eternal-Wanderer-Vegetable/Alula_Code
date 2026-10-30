import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';
import 'editor_folding.dart';
import 'editor_minimap.dart' show projectEditorMinimapViewport;
import 'editor_rendering.dart'
    show
        editorLogicalLines,
        editorPrimaryScrollPosition,
        resolveEditorDocumentLinePosition;
import 'rust_text_input_window.dart';

const int maxEditorStickyScrollScopes = 5;
const double editorStickyScrollLineHeight = 21;

@immutable
class EditorStickySymbol {
  const EditorStickySymbol({
    required this.kind,
    required this.name,
    required this.startUtf16,
    required this.line,
    required this.endLine,
  });

  final String kind;
  final String name;
  final int startUtf16;
  final int line;
  final int endLine;

  @override
  bool operator ==(Object other) =>
      other is EditorStickySymbol &&
      kind == other.kind &&
      name == other.name &&
      startUtf16 == other.startUtf16 &&
      line == other.line &&
      endLine == other.endLine;

  @override
  int get hashCode => Object.hash(kind, name, startUtf16, line, endLine);

  static EditorStickySymbol? fromMap(Map<String, Object?> value) {
    final kind = value['kind'];
    final name = value['name'];
    final startUtf16 = value['start_utf16'];
    final line = value['line'];
    final endLine = value['end_line'];
    if (kind is! String ||
        name is! String ||
        startUtf16 is! num ||
        line is! num ||
        endLine is! num) {
      return null;
    }
    final parsedLine = line.toInt();
    final parsedEndLine = endLine.toInt();
    final parsedStart = startUtf16.toInt();
    if (parsedStart < 0 || parsedLine < 1 || parsedEndLine < parsedLine) {
      return null;
    }
    return EditorStickySymbol(
      kind: kind,
      name: name,
      startUtf16: parsedStart,
      line: parsedLine,
      endLine: parsedEndLine,
    );
  }
}

/// Returns enclosing Rust scopes for a zero-based first visible line.
List<EditorStickySymbol> buildEditorStickyScrollScopes({
  required List<EditorStickySymbol> symbols,
  required int firstVisibleLine,
  int maxScopes = maxEditorStickyScrollScopes,
}) {
  final limit = maxScopes.clamp(0, maxEditorStickyScrollScopes).toInt();
  if (limit == 0 || firstVisibleLine < 0) return const [];
  final visibleLine = firstVisibleLine + 1;
  const scopeKinds = {
    'function',
    'struct',
    'enum',
    'trait',
    'impl',
    'mod',
    'macro',
  };
  final active = symbols
      .where((symbol) =>
          scopeKinds.contains(symbol.kind) &&
          symbol.line < visibleLine &&
          symbol.endLine >= visibleLine)
      .toList()
    ..sort((a, b) {
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.startUtf16.compareTo(b.startUtf16);
    });
  return List.unmodifiable(
    active.length <= limit ? active : active.sublist(active.length - limit),
  );
}

/// Sticky Rust scope headers over the bounded text input viewport.
///
/// The Tree-sitter symbol list is fetched only after a document version settles.
/// Scrolling reuses that versioned list and never calls the Rust bridge.
class EditorStickyScroll extends StatefulWidget {
  const EditorStickyScroll({
    super.key,
    required this.document,
    required this.inputWindow,
    required this.scrollController,
    required this.onSelectSymbol,
    required this.child,
    this.foldedLineRanges = const [],
    this.enabled = true,
    this.lineHeight = editorStickyScrollLineHeight,
  });

  final AlulaDoc document;
  final RustTextInputWindow inputWindow;
  final ScrollController scrollController;
  final ValueChanged<int> onSelectSymbol;
  final Widget child;
  final List<EditorDocumentLineRange> foldedLineRanges;
  final bool enabled;
  final double lineHeight;

  @override
  State<EditorStickyScroll> createState() => _EditorStickyScrollState();
}

class _EditorStickyScrollState extends State<EditorStickyScroll> {
  Timer? _symbolsTimer;
  int _scheduledDocId = -1;
  int _scheduledVersion = -1;
  int _symbolsDocId = -1;
  int _symbolsVersion = -1;
  List<EditorStickySymbol> _symbols = const [];
  int _metadataDocId = -1;
  int _metadataVersion = -1;
  int _metadataStart = -1;
  String _metadataText = '';
  int _documentLineCount = 1;
  int _windowFirstLine = 0;
  int _windowLineCount = 1;
  int _firstVisibleLine = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateViewport);
    _syncDocumentState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateViewport();
    });
  }

  @override
  void didUpdateWidget(covariant EditorStickyScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateViewport);
      widget.scrollController.addListener(_updateViewport);
    }
    _syncDocumentState();
    _updateViewport(notify: false);
  }

  void _syncDocumentState() {
    final document = widget.document;
    final window = widget.inputWindow;
    final text = window.text;
    if (_metadataDocId != document.id ||
        _metadataVersion != window.version ||
        _metadataStart != window.startUtf16 ||
        _metadataText != text) {
      final position = resolveEditorDocumentLinePosition(
        document,
        window.startUtf16,
      );
      _metadataDocId = document.id;
      _metadataVersion = window.version;
      _metadataStart = window.startUtf16;
      _metadataText = text;
      _documentLineCount = position.lineCount;
      _windowFirstLine = position.firstLineNumber;
      _windowLineCount = editorLogicalLines(text).length;
      _firstVisibleLine = _windowFirstLine;
    }

    if (_isCurrentDocument &&
        (_symbolsDocId != document.id || _symbolsVersion != document.version)) {
      _scheduleSymbolsRead(document.id, document.version);
    }
  }

  bool get _isCurrentDocument =>
      widget.enabled &&
      widget.inputWindow.pendingText == null &&
      widget.inputWindow.document.id == widget.document.id &&
      widget.inputWindow.version == widget.document.version;

  void _scheduleSymbolsRead(int documentId, int version) {
    if ((_symbolsDocId == documentId && _symbolsVersion == version) ||
        (_scheduledDocId == documentId && _scheduledVersion == version)) {
      return;
    }
    _symbolsTimer?.cancel();
    _scheduledDocId = documentId;
    _scheduledVersion = version;
    _symbolsTimer = Timer(const Duration(milliseconds: 350), () {
      _symbolsTimer = null;
      _scheduledDocId = -1;
      _scheduledVersion = -1;
      if (!mounted ||
          !_isCurrentDocument ||
          widget.document.id != documentId ||
          widget.document.version != version) {
        return;
      }
      final result = widget.document.core.lsp.symbols(documentId);
      if (!mounted ||
          result == null ||
          result.version != version ||
          !_isCurrentDocument ||
          widget.document.version != version) {
        return;
      }
      final symbols = <EditorStickySymbol>[
        for (final value in result.symbols)
          if (EditorStickySymbol.fromMap(value) case final symbol?) symbol,
      ];
      setState(() {
        _symbols = List.unmodifiable(symbols);
        _symbolsDocId = documentId;
        _symbolsVersion = version;
      });
    });
  }

  void _updateViewport({bool notify = true}) {
    final controller = widget.scrollController;
    final position = editorPrimaryScrollPosition(controller);
    if (position == null) return;
    final viewport = projectEditorMinimapViewport(
      documentLineCount: _documentLineCount,
      inputWindowFirstLine: _windowFirstLine,
      inputWindowLineCount: _windowLineCount,
      scrollOffset: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      viewportHeight: position.viewportDimension,
      foldedLineRanges: widget.foldedLineRanges,
      lineHeight: widget.lineHeight,
    );
    if (viewport.firstLine == _firstVisibleLine) return;
    _firstVisibleLine = viewport.firstLine;
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    _symbolsTimer?.cancel();
    widget.scrollController.removeListener(_updateViewport);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _isCurrentDocument &&
        _symbolsDocId == widget.document.id &&
        _symbolsVersion == widget.document.version;
    final scopes = current
        ? buildEditorStickyScrollScopes(
            symbols: _symbols,
            firstVisibleLine: _firstVisibleLine,
          )
        : const <EditorStickySymbol>[];
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _updateViewport();
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (scopes.isNotEmpty)
            Positioned(
              top: 13,
              left: 13,
              right: 13,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final scope in scopes)
                      SizedBox(
                        height: widget.lineHeight,
                        child: InkWell(
                          key: ValueKey(
                            'sticky-scroll-${scope.startUtf16}-${scope.line}',
                          ),
                          onTap: () => widget.onSelectSymbol(scope.startUtf16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    scope.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  scope.kind,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
