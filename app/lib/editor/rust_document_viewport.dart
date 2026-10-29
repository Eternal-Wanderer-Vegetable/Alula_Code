import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../bridge/alula_core.dart';

const int rustViewportLinesPerPage = 32;
const int rustViewportLineWindowUtf16 = 2048;
const int rustViewportPageUtf16 =
    rustViewportLinesPerPage * rustViewportLineWindowUtf16;
const int rustViewportCachedPages = 3;
const double rustViewportRowHeight = 22;

/// Read-only P03.3 prototype: Rust owns document text; Flutter keeps only a
/// small LRU of bounded line windows and independent per-view scroll state.
class RustDocumentViewport extends StatefulWidget {
  const RustDocumentViewport({
    super.key,
    required this.document,
    required this.viewId,
    this.scrollController,
    this.horizontalStartUtf16 = 0,
    this.onPageRead,
    this.onSelectionChanged,
  });

  final AlulaDoc document;
  final String viewId;
  final ScrollController? scrollController;

  /// Horizontal window origin for the prototype. P03.4 will connect native
  /// pointer/IME movement to this document-coordinate value.
  final int horizontalStartUtf16;
  final ValueChanged<DocumentLinesRead>? onPageRead;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<RustDocumentViewport> createState() => _RustDocumentViewportState();
}

class _RustDocumentViewportState extends State<RustDocumentViewport> {
  final LinkedHashMap<int, DocumentLinesRead> _pages =
      LinkedHashMap<int, DocumentLinesRead>();
  late ScrollController _scrollController;
  late int _lineCount;
  late int _observedVersion;
  bool _ownsScrollController = false;

  @override
  void initState() {
    super.initState();
    _setScrollController(widget.scrollController);
    _readDocumentMetadata();
  }

  @override
  void didUpdateWidget(covariant RustDocumentViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _disposeOwnedScrollController();
      _setScrollController(widget.scrollController);
    }
    if (oldWidget.document != widget.document ||
        oldWidget.horizontalStartUtf16 != widget.horizontalStartUtf16) {
      _pages.clear();
      _readDocumentMetadata();
    }
  }

  void _setScrollController(ScrollController? external) {
    _ownsScrollController = external == null;
    _scrollController = external ?? ScrollController();
  }

  void _disposeOwnedScrollController() {
    if (_ownsScrollController) _scrollController.dispose();
  }

  void _readDocumentMetadata() {
    final metadata = widget.document.lineOffset(0);
    _lineCount = metadata.lineCount;
    _observedVersion = metadata.version;
  }

  DocumentLinesRead _readPage(int pageIndex) {
    final cached = _pages.remove(pageIndex);
    if (cached != null) {
      _pages[pageIndex] = cached;
      return cached;
    }

    final page = widget.document.readLines(
      firstLine: pageIndex * rustViewportLinesPerPage,
      maxLines: rustViewportLinesPerPage,
      horizontalStartUtf16: widget.horizontalStartUtf16,
      maxLineUtf16: rustViewportLineWindowUtf16,
      maxTotalUtf16: rustViewportPageUtf16,
    );
    if (page.version != _observedVersion) {
      _pages.clear();
      _observedVersion = page.version;
      _lineCount = page.lineCount;
    }
    _pages[pageIndex] = page;
    while (_pages.length > rustViewportCachedPages) {
      _pages.remove(_pages.keys.first);
    }
    widget.onPageRead?.call(page);
    return page;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.document.version != _observedVersion) {
      _pages.clear();
      _readDocumentMetadata();
    }
    final pageCount =
        (_lineCount + rustViewportLinesPerPage - 1) ~/ rustViewportLinesPerPage;

    return SelectionArea(
      onSelectionChanged: widget.onSelectionChanged,
      child: ListView.builder(
        key: ValueKey<String>('rust-viewport-${widget.viewId}'),
        controller: _scrollController,
        itemCount: pageCount,
        itemExtent: rustViewportLinesPerPage * rustViewportRowHeight,
        itemBuilder: (context, pageIndex) {
          final page = _readPage(pageIndex);
          return SizedBox(
            key: ValueKey<String>(
                'rust-viewport-${widget.viewId}-page-${page.firstLine}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in page.lines)
                  SizedBox(
                    height: rustViewportRowHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(
                              '${line.line + 1}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Color(0xFF858585),
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                line.text,
                                key: ValueKey<String>(
                                  'rust-viewport-${widget.viewId}-line-${line.line}',
                                ),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFFD4D4D4),
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _disposeOwnedScrollController();
    super.dispose();
  }
}
