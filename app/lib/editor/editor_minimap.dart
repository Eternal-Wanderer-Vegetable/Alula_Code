import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';
import 'editor_folding.dart';
import 'editor_minimap_markers.dart';
import 'editor_minimap_syntax.dart';
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
  List<EditorDocumentLineRange> foldedLineRanges = const [],
  double lineHeight = editorMinimapLineHeight,
}) {
  if (documentLineCount < 1 || inputWindowLineCount < 1 || lineHeight <= 0) {
    throw ArgumentError('minimap line counts and line height must be positive');
  }
  final projection = EditorDocumentLineProjection(
    documentLineCount: documentLineCount,
    hiddenRanges: foldedLineRanges,
  );
  final windowVisibleLineCount = projection.visibleLineCountInRange(
    startLine: inputWindowFirstLine,
    endLineExclusive: inputWindowFirstLine + inputWindowLineCount,
  );
  final projectedWindowLineCount = math.max(1, windowVisibleLineCount).toInt();
  final visible = viewportHeight <= 0
      ? math.min(projectedWindowLineCount, 20)
      : (viewportHeight / lineHeight)
          .ceil()
          .clamp(1, projectedWindowLineCount)
          .toInt();
  final travel = math.max(0, projectedWindowLineCount - visible).toInt();
  final fraction = maxScrollExtent <= 0
      ? 0.0
      : (scrollOffset / maxScrollExtent).clamp(0.0, 1.0).toDouble();
  final firstVisibleLine =
      (projection.documentLineToVisibleLine(inputWindowFirstLine) +
              (travel * fraction).round())
          .clamp(0, projection.visibleLineCount - 1)
          .toInt();
  final first = projection.visibleLineToDocumentLine(firstVisibleLine);
  return EditorMinimapViewport(
    first,
    math.min(visible, projection.visibleLineCount - firstVisibleLine).toInt(),
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
    this.syntaxDocumentId = -1,
    this.syntaxTokens = const [],
    this.syntaxVersion = -1,
    this.syntaxEnabled = false,
    this.syntaxTokenColor,
    this.overviewMarkers = const [],
    this.foldedLineRanges = const [],
    this.width = editorMinimapWidth,
    this.lineHeight = editorMinimapLineHeight,
  });

  final RustTextInputWindow inputWindow;
  final ScrollController scrollController;
  final ValueChanged<int> onNavigateToLine;
  final int syntaxDocumentId;
  final List<Map<String, Object?>> syntaxTokens;
  final int syntaxVersion;
  final bool syntaxEnabled;
  final Color Function(String kind)? syntaxTokenColor;
  final List<EditorMinimapMarker> overviewMarkers;
  final List<EditorDocumentLineRange> foldedLineRanges;
  final double width;
  final double lineHeight;

  @override
  State<EditorMinimap> createState() => _EditorMinimapState();
}

class _EditorMinimapState extends State<EditorMinimap> {
  Timer? _timer;
  DocumentMinimapSample? _sample;
  DocumentMinimapSample? _syntaxSample;
  List<Map<String, Object?>> _syntaxTokens = const [];
  List<EditorMinimapSyntaxSegment> _syntaxSegments = const [];
  int _syntaxDocumentId = -1;
  int _syntaxVersion = -1;
  bool _syntaxEnabled = false;
  Color Function(String kind)? _syntaxTokenColor;
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
    _updateSyntaxSegments();
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
    _syntaxSample = null;
    _syntaxSegments = const [];
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
          _updateSyntaxSegments();
        });
      } catch (error) {
        _pendingDocId = -1;
        _pendingVersion = -1;
        debugPrint('读取 Rust minimap 概览失败：$error');
      }
    });
  }

  void _updateSyntaxSegments() {
    final sample = _sample;
    final tokens = widget.syntaxTokens;
    final colorForKind = widget.syntaxTokenColor;
    final documentId = widget.syntaxDocumentId;
    final version = widget.syntaxVersion;
    final enabled = widget.syntaxEnabled;
    if (identical(sample, _syntaxSample) &&
        identical(tokens, _syntaxTokens) &&
        documentId == _syntaxDocumentId &&
        version == _syntaxVersion &&
        enabled == _syntaxEnabled &&
        identical(colorForKind, _syntaxTokenColor)) {
      return;
    }
    _syntaxSample = sample;
    _syntaxTokens = tokens;
    _syntaxDocumentId = documentId;
    _syntaxVersion = version;
    _syntaxEnabled = enabled;
    _syntaxTokenColor = colorForKind;
    if (sample == null ||
        documentId != _sampleDocId ||
        colorForKind == null ||
        !enabled) {
      _syntaxSegments = const [];
      return;
    }
    _syntaxSegments = buildEditorMinimapSyntaxSegments(
      sample: sample,
      tokens: tokens,
      tokenVersion: version,
      colorForKind: colorForKind,
    );
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
                foldedLineRanges: widget.foldedLineRanges,
                overviewMarkers: widget.overviewMarkers,
                syntaxSegments: _syntaxSegments,
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
    required this.foldedLineRanges,
    required this.overviewMarkers,
    required this.syntaxSegments,
    required this.lineHeight,
  }) : super(repaint: scrollController);

  final DocumentMinimapSample? sample;
  final int sampleDocId;
  final ScrollController scrollController;
  final int docLineCount;
  final int windowFirstLine;
  final int windowLineCount;
  final List<EditorDocumentLineRange> foldedLineRanges;
  final List<EditorMinimapMarker> overviewMarkers;
  final List<EditorMinimapSyntaxSegment> syntaxSegments;
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
    var syntaxIndex = 0;
    for (final line in current.lines) {
      while (syntaxIndex < syntaxSegments.length &&
          syntaxSegments[syntaxIndex].line < line.line) {
        syntaxIndex++;
      }
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
      final rowTop =
          (y - rowHeight / 2).clamp(0.0, size.height - rowHeight).toDouble();
      canvas.drawRect(
        Rect.fromLTWH(drawX, rowTop, drawWidth, rowHeight),
        linePaint,
      );
      while (syntaxIndex < syntaxSegments.length &&
          syntaxSegments[syntaxIndex].line == line.line) {
        final segment = syntaxSegments[syntaxIndex++];
        final segmentX = (left + segment.startUtf16 * unitWidth)
            .clamp(left, size.width - right)
            .toDouble();
        final segmentWidth =
            (segment.endUtf16 - segment.startUtf16) * unitWidth;
        final clippedWidth =
            math.min(segmentWidth, size.width - right - segmentX).toDouble();
        if (clippedWidth <= 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(segmentX, rowTop, clippedWidth, rowHeight),
          Paint()..color = segment.color,
        );
      }
    }

    final position = editorPrimaryScrollPosition(scrollController);
    final viewport = projectEditorMinimapViewport(
      documentLineCount: docLineCount,
      inputWindowFirstLine: windowFirstLine,
      inputWindowLineCount: windowLineCount,
      scrollOffset: position?.pixels ?? 0,
      maxScrollExtent: position?.maxScrollExtent ?? 0,
      viewportHeight: position?.viewportDimension ?? 0,
      foldedLineRanges: foldedLineRanges,
      lineHeight: lineHeight,
    );
    final projection = EditorDocumentLineProjection(
      documentLineCount: docLineCount,
      hiddenRanges: foldedLineRanges,
    );
    final visibleFirst =
        projection.documentLineToVisibleLine(viewport.firstLine);
    final endDocumentLine = projection.visibleLineToDocumentBoundary(
      visibleFirst + viewport.lineCount,
    );
    final top = viewport.firstLine / current.lineCount * size.height;
    final bottom = endDocumentLine / current.lineCount * size.height;
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
      !listEquals(oldDelegate.foldedLineRanges, foldedLineRanges) ||
      !listEquals(oldDelegate.overviewMarkers, overviewMarkers) ||
      !listEquals(oldDelegate.syntaxSegments, syntaxSegments) ||
      oldDelegate.lineHeight != lineHeight;
}
