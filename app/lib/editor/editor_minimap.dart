import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';
import 'editor_minimap_markers.dart';
import 'editor_rendering.dart';
import 'rust_text_input_window.dart';

const double editorMinimapWidth = 82;
const double editorMinimapLineHeight = 21;

@immutable
class EditorMinimapViewport {
  const EditorMinimapViewport(this.firstLine, this.lineCount);

  final int firstLine;
  final int lineCount;
}

/// Maps a bounded editor window's scroll position to absolute document lines.
EditorMinimapViewport projectEditorMinimapViewport({
  required int documentLineCount,
  required int inputWindowFirstLine,
  required int inputWindowLineCount,
  required double scrollOffset,
  required double maxScrollExtent,
  required double viewportHeight,
  double lineHeight = editorMinimapLineHeight,
}) {
  if (documentLineCount < 1 || inputWindowLineCount < 1 || lineHeight <= 0) {
    throw ArgumentError('minimap line counts and line height must be positive');
  }
  final visible = viewportHeight <= 0
      ? math.min(inputWindowLineCount, 20)
      : (viewportHeight / lineHeight)
          .ceil()
          .clamp(1, inputWindowLineCount)
          .toInt();
  final travel = math.max(0, inputWindowLineCount - visible).toInt();
  final fraction = maxScrollExtent <= 0
      ? 0.0
      : (scrollOffset / maxScrollExtent).clamp(0.0, 1.0).toDouble();
  final first = (inputWindowFirstLine + (travel * fraction).round())
      .clamp(0, documentLineCount - 1);
  return EditorMinimapViewport(
    first,
    math.min(visible, documentLineCount - first).toInt(),
  );
}

/// Bounded full-document overview with click/drag line navigation.
///
/// The Rust bridge returns at most 512 representative line prefixes and at
/// most 48 UTF-16 units per prefix; Flutter never mirrors the complete file.
class EditorMinimap extends StatefulWidget {
  const EditorMinimap({
    super.key,
    required this.inputWindow,
    required this.scrollController,
    required this.onNavigateToLine,
    this.overviewMarkers = const [],
    this.width = editorMinimapWidth,
    this.lineHeight = editorMinimapLineHeight,
  });

  final RustTextInputWindow inputWindow;
  final ScrollController scrollController;
  final ValueChanged<int> onNavigateToLine;
  final List<EditorMinimapMarker> overviewMarkers;
  final double width;
  final double lineHeight;

  @override
  State<EditorMinimap> createState() => _EditorMinimapState();
}

class _EditorMinimapState extends State<EditorMinimap> {
  Timer? _timer;
  DocumentMinimapSample? _sample;
  int _sampleDocId = -1;
  int _sampleVersion = -1;
  int _pendingDocId = -1;
  int _pendingVersion = -1;
  int _metaDocId = -1;
  int _metaVersion = -1;
  int _metaStart = -1;
  String _metaText = '';
  int _docLineCount = 1;
  int _windowFirstLine = 0;
  int _windowLineCount = 1;
  int _lastNavigatedLine = -1;

  @override
  void initState() {
    super.initState();
    _updateWindowMetadata();
    _scheduleSample(Duration.zero);
  }

  @override
  void didUpdateWidget(covariant EditorMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateWindowMetadata();
    final doc = widget.inputWindow.document;
    if (doc.id != _sampleDocId || doc.version != _sampleVersion) {
      _scheduleSample(const Duration(milliseconds: 120));
    }
  }

  void _updateWindowMetadata() {
    final window = widget.inputWindow;
    final doc = window.document;
    final text = window.presentedText;
    if (_metaDocId == doc.id &&
        _metaVersion == window.version &&
        _metaStart == window.startUtf16 &&
        _metaText == text) {
      return;
    }
    final position = resolveEditorDocumentLinePosition(doc, window.startUtf16);
    _metaDocId = doc.id;
    _metaVersion = window.version;
    _metaStart = window.startUtf16;
    _metaText = text;
    _docLineCount = position.lineCount;
    _windowFirstLine = position.firstLineNumber;
    _windowLineCount = editorLogicalLines(text).length;
  }

  void _scheduleSample(Duration delay) {
    final doc = widget.inputWindow.document;
    final version = doc.version;
    if ((_sampleDocId == doc.id && _sampleVersion == version) ||
        (_pendingDocId == doc.id && _pendingVersion == version)) {
      return;
    }
    _timer?.cancel();
    _sample = null;
    _pendingDocId = doc.id;
    _pendingVersion = version;
    _timer = Timer(delay, () {
      _timer = null;
      if (!mounted) return;
      try {
        final sample = doc.readMinimapSample();
        if (!mounted ||
            sample.version != doc.version ||
            doc.id != widget.inputWindow.document.id ||
            sample.version != widget.inputWindow.version) {
          _pendingDocId = -1;
          _pendingVersion = -1;
          return;
        }
        setState(() {
          _sample = sample;
          _sampleDocId = doc.id;
          _sampleVersion = sample.version;
          _pendingDocId = doc.id;
          _pendingVersion = sample.version;
        });
      } catch (error) {
        _pendingDocId = -1;
        _pendingVersion = -1;
        debugPrint('读取 Rust minimap 概览失败：$error');
      }
    });
  }

  void _navigateAt(Offset offset) {
    final box = context.findRenderObject();
    final sample = _sample;
    if (box is! RenderBox ||
        !box.hasSize ||
        sample == null ||
        sample.lineCount < 1 ||
        box.size.height <= 0) {
      return;
    }
    final fraction = (offset.dy / box.size.height).clamp(0.0, 1.0);
    final line =
        (fraction * sample.lineCount).floor().clamp(0, sample.lineCount - 1);
    if (line == _lastNavigatedLine) return;
    _lastNavigatedLine = line;
    widget.onNavigateToLine(line);
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    final lineCount = sample?.lineCount;
    return Semantics(
      label: sample == null ? '代码缩略图正在加载' : '代码缩略图，共 $lineCount 行，点击或拖动跳转',
      child: SizedBox(
        width: widget.width,
        child: GestureDetector(
          key: const ValueKey<String>('editor-minimap'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _navigateAt(details.localPosition),
          onVerticalDragStart: (details) => _navigateAt(details.localPosition),
          onVerticalDragUpdate: (details) => _navigateAt(details.localPosition),
          child: ClipRect(
            child: CustomPaint(
              painter: _EditorMinimapPainter(
                sample: sample,
                sampleDocId: _sampleDocId,
                scrollController: widget.scrollController,
                docLineCount: _docLineCount,
                windowFirstLine: _windowFirstLine,
                windowLineCount: _windowLineCount,
                overviewMarkers: widget.overviewMarkers,
                lineHeight: widget.lineHeight,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _EditorMinimapPainter extends CustomPainter {
  _EditorMinimapPainter({
    required this.sample,
    required this.sampleDocId,
    required this.scrollController,
    required this.docLineCount,
    required this.windowFirstLine,
    required this.windowLineCount,
    required this.overviewMarkers,
    required this.lineHeight,
  }) : super(repaint: scrollController);

  final DocumentMinimapSample? sample;
  final int sampleDocId;
  final ScrollController scrollController;
  final int docLineCount;
  final int windowFirstLine;
  final int windowLineCount;
  final List<EditorMinimapMarker> overviewMarkers;
  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF17191E),
    );
    final current = sample;
    if (current == null || current.lines.isEmpty || size.isEmpty) return;

    const left = 7.0;
    const right = 4.0;
    final contentWidth = math.max(1.0, size.width - left - right).toDouble();
    final unitWidth = contentWidth / maxDocMinimapLineSampleUtf16;
    final rowHeight =
        (size.height / current.lines.length).clamp(0.65, 1.5).toDouble();
    final linePaint = Paint()..color = const Color(0xFF858B95);
    for (final line in current.lines) {
      if (line.utf16Length == 0) continue;
      var indent = 0;
      for (final unit in line.text.codeUnits) {
        if (unit == 0x20) {
          indent++;
        } else if (unit == 0x09) {
          indent += 4 - indent % 4;
        } else {
          break;
        }
      }
      final sampled = math.min(maxDocMinimapLineSampleUtf16, line.utf16Length);
      final textWidth = math.max(1, sampled - indent);
      final x = left + math.min(indent, sampled) * unitWidth;
      final y = current.lineCount <= 1
          ? 0.0
          : line.line / (current.lineCount - 1) * size.height;
      final drawX = x.clamp(left, size.width - right).toDouble();
      final drawWidth = math
          .min(textWidth * unitWidth, size.width - right - drawX)
          .clamp(0.5, contentWidth)
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(
          drawX,
          (y - rowHeight / 2).clamp(0.0, size.height - rowHeight).toDouble(),
          drawWidth,
          rowHeight,
        ),
        linePaint,
      );
    }

    final position =
        scrollController.hasClients ? scrollController.position : null;
    final viewport = projectEditorMinimapViewport(
      documentLineCount: docLineCount,
      inputWindowFirstLine: windowFirstLine,
      inputWindowLineCount: windowLineCount,
      scrollOffset: position?.pixels ?? 0,
      maxScrollExtent: position?.maxScrollExtent ?? 0,
      viewportHeight: position?.viewportDimension ?? 0,
      lineHeight: lineHeight,
    );
    final top = viewport.firstLine / current.lineCount * size.height;
    final bottom = (viewport.firstLine + viewport.lineCount) /
        current.lineCount *
        size.height;
    final rect = Rect.fromLTRB(
      1,
      top.clamp(0.0, size.height).toDouble(),
      size.width - 1,
      math.max(top + 5, bottom).clamp(0.0, size.height).toDouble(),
    );
    canvas.drawRect(rect, Paint()..color = const Color(0x335B9BD5));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xAA75B7FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final markerHeight = math.min(
      size.height,
      math.max(1.0, size.height / current.lineCount),
    );
    for (final marker in overviewMarkers.take(maxEditorMinimapMarkers)) {
      if (marker.documentId != sampleDocId ||
          marker.documentVersion != current.version ||
          marker.line < 0 ||
          marker.line >= current.lineCount) {
        continue;
      }
      final centerY = projectEditorMinimapMarkerY(
        line: marker.line,
        lineCount: current.lineCount,
        height: size.height,
      );
      final top = (centerY - markerHeight / 2)
          .clamp(0.0, size.height - markerHeight)
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(size.width - 3, top, 3, markerHeight),
        Paint()..color = marker.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorMinimapPainter oldDelegate) =>
      oldDelegate.sample != sample ||
      oldDelegate.sampleDocId != sampleDocId ||
      oldDelegate.scrollController != scrollController ||
      oldDelegate.docLineCount != docLineCount ||
      oldDelegate.windowFirstLine != windowFirstLine ||
      oldDelegate.windowLineCount != windowLineCount ||
      !listEquals(oldDelegate.overviewMarkers, overviewMarkers) ||
      oldDelegate.lineHeight != lineHeight;
}
