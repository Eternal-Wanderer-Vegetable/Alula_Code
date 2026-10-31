import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        kDoubleTapSlop,
        kDoubleTapTimeout,
        kPrimaryButton,
        PointerDeviceKind,
        PointerDownEvent;
import 'package:flutter/rendering.dart' show AxisDirection, RenderEditable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'editor_folding.dart';
import 'editor_rendering.dart';
import 'rust_text_input_window.dart';

/// Cross-platform monospace choices for code points absent from the primary
/// editor font. Flutter continues through this list to its platform fallback.
const List<String> editorFontFamilyFallbacks = [
  'Cascadia Code',
  'Consolas',
  'Menlo',
  'SF Mono',
  'Noto Sans Mono',
  'DejaVu Sans Mono',
  'monospace',
];

class _SyntaxTextEditingController extends TextEditingController {
  _SyntaxTextEditingController.fromValue(super.value) : super.fromValue();

  List<Map<String, Object?>> _tokens = const [];
  int _tokenVersion = -1;
  int _windowVersion = -2;
  int _windowStartUtf16 = 0;
  String _windowText = '';
  Color Function(String kind)? _colorForKind;
  List<EditorFoldRange> _foldedRanges = const [];

  void configureSyntax({
    required List<Map<String, Object?>> tokens,
    required int tokenVersion,
    required int windowVersion,
    required int windowStartUtf16,
    required String windowText,
    required Color Function(String kind)? colorForKind,
    required List<EditorFoldRange> foldedRanges,
  }) {
    _tokens = tokens;
    _tokenVersion = tokenVersion;
    _windowVersion = windowVersion;
    _windowStartUtf16 = windowStartUtf16;
    _windowText = windowText;
    _colorForKind = colorForKind;
    _foldedRanges = foldedRanges;
  }

  List<_ResolvedSyntaxToken> _visibleTokens() {
    final colorForKind = _colorForKind;
    if (colorForKind == null ||
        _tokenVersion != _windowVersion ||
        text != _windowText ||
        text.isEmpty ||
        _tokens.isEmpty) {
      return const [];
    }

    final windowEnd = _windowStartUtf16 + text.length;
    var low = 0;
    var high = _tokens.length;
    // Rust returns ordered, non-overlapping document-absolute UTF-16 tokens.
    // Skip preceding tokens without copying the complete document token list.
    while (low < high) {
      final middle = (low + high) >> 1;
      final end = (_tokens[middle]['end_utf16'] as num?)?.toInt() ?? 0;
      if (end <= _windowStartUtf16) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final visible = <_ResolvedSyntaxToken>[];
    for (var index = low; index < _tokens.length; index++) {
      final token = _tokens[index];
      final absoluteStart = (token['start_utf16'] as num?)?.toInt();
      final absoluteEnd = (token['end_utf16'] as num?)?.toInt();
      if (absoluteStart == null || absoluteEnd == null) continue;
      if (absoluteStart >= windowEnd) break;
      if (absoluteEnd <= _windowStartUtf16 || absoluteEnd <= absoluteStart) {
        continue;
      }
      final start =
          absoluteStart > _windowStartUtf16 ? absoluteStart : _windowStartUtf16;
      final end = absoluteEnd < windowEnd ? absoluteEnd : windowEnd;
      if (start >= end) continue;
      visible.add(
        _ResolvedSyntaxToken(
          start: start - _windowStartUtf16,
          end: end - _windowStartUtf16,
          color: colorForKind((token['kind'] as String?) ?? ''),
        ),
      );
    }
    return visible;
  }

  List<EditorFoldRange> _visibleFoldedRanges() {
    if (text != _windowText || _foldedRanges.isEmpty) return const [];
    final composing = value.composing;
    if (!composing.isValid || composing.isCollapsed) return _foldedRanges;
    return _foldedRanges
        .where((range) =>
            composing.end <= range.hiddenStartUtf16 ||
            composing.start >= range.hiddenEndUtf16)
        .toList(growable: false);
  }

  bool get hasVisibleFoldedRanges => _visibleFoldedRanges().isNotEmpty;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final visible = _visibleTokens();
    final foldedRanges = _visibleFoldedRanges();
    if (visible.isEmpty && foldedRanges.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final composing =
        withComposing && value.composing.isValid && value.isComposingRangeValid
            ? value.composing
            : null;
    final boundaries = <int>{0, text.length};
    for (final token in visible) {
      boundaries
        ..add(token.start)
        ..add(token.end);
    }
    for (final range in foldedRanges) {
      boundaries
        ..add(range.hiddenStartUtf16)
        ..add(range.hiddenEndUtf16);
    }
    if (composing != null) {
      boundaries
        ..add(composing.start)
        ..add(composing.end);
    }
    final sortedBoundaries = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    var tokenIndex = 0;
    var foldedIndex = 0;
    for (var index = 0; index + 1 < sortedBoundaries.length; index++) {
      final start = sortedBoundaries[index];
      final end = sortedBoundaries[index + 1];
      if (start >= end) continue;
      while (tokenIndex < visible.length && visible[tokenIndex].end <= start) {
        tokenIndex++;
      }
      while (foldedIndex < foldedRanges.length &&
          foldedRanges[foldedIndex].hiddenEndUtf16 <= start) {
        foldedIndex++;
      }
      final token = tokenIndex < visible.length &&
              visible[tokenIndex].start <= start &&
              visible[tokenIndex].end >= end
          ? visible[tokenIndex]
          : null;
      final isComposing =
          composing != null && composing.start <= start && composing.end >= end;
      final isFolded = foldedIndex < foldedRanges.length &&
          foldedRanges[foldedIndex].hiddenStartUtf16 <= start &&
          foldedRanges[foldedIndex].hiddenEndUtf16 >= end;
      final segmentStyle = isFolded
          ? const TextStyle(
              color: Color(0x00000000),
              fontSize: 0,
              height: 0,
              letterSpacing: 0,
            )
          : token == null && !isComposing
              ? null
              : TextStyle(
                  color: token?.color,
                  decoration: isComposing ? TextDecoration.underline : null,
                );
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: segmentStyle,
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }
}

class _ResolvedSyntaxToken {
  const _ResolvedSyntaxToken({
    required this.start,
    required this.end,
    required this.color,
  });

  final int start;
  final int end;
  final Color color;
}

/// A multiline Flutter input client whose document mirror is a bounded Rust
/// text window. Flutter's EditableText owns native IME and candidate geometry.
class RustTextInputField extends StatefulWidget {
  const RustTextInputField({
    super.key,
    required this.inputWindow,
    this.focusNode,
    this.scrollController,
    this.inputFormatter,
    this.additionalSelections = const [],
    this.additionalOperations,
    this.autofocus = false,
    this.style,
    this.fontFamilyFallback,
    this.decoration,
    this.showLineNumbers = true,
    this.showIndentGuides = true,
    this.wordWrap = false,
    this.horizontalScrollController,
    this.rangeDecorations = const [],
    this.syntaxTokens = const [],
    this.syntaxVersion = -1,
    this.syntaxTokenColor,
    this.whitespaceMode = EditorWhitespaceMode.none,
    this.tabSize = 4,
    this.enableCodeFolding = false,
    this.semanticsLabel,
    this.onTap,
    this.onAltClick,
    this.onCrossWindowLineSelection,
    this.onDelta,
    this.onError,
    this.onPresentationChanged,
    this.onFoldRangesChanged,
  }) : assert(tabSize > 0);

  final RustTextInputWindow inputWindow;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final TextInputFormatter? inputFormatter;
  final List<TextSelection> additionalSelections;
  final List<TextOp> Function()? additionalOperations;
  final bool autofocus;
  final TextStyle? style;
  final List<String>? fontFamilyFallback;
  final InputDecoration? decoration;
  final bool showLineNumbers;
  final bool showIndentGuides;
  final bool wordWrap;
  final ScrollController? horizontalScrollController;
  final List<EditorRangeDecoration> rangeDecorations;
  final List<Map<String, Object?>> syntaxTokens;
  final int syntaxVersion;
  final Color Function(String kind)? syntaxTokenColor;
  final EditorWhitespaceMode whitespaceMode;
  final int tabSize;
  final bool enableCodeFolding;
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final ValueChanged<int>? onAltClick;
  final ValueChanged<TextSelection>? onCrossWindowLineSelection;
  final ValueChanged<RustTextInputDelta>? onDelta;
  final ValueChanged<Object>? onError;
  final VoidCallback? onPresentationChanged;
  final EditorFoldRangesChanged? onFoldRangesChanged;

  @override
  RustTextInputFieldState createState() => RustTextInputFieldState();
}

class RustTextInputFieldState extends State<RustTextInputField> {
  late _SyntaxTextEditingController _controller;
  late TextEditingValue _lastAcceptedValue;
  late FocusNode _focusNode;
  late ScrollController _horizontalScrollController;
  bool _ownsFocusNode = false;
  bool _ownsHorizontalScrollController = false;
  bool _flushScheduled = false;
  bool _restoringValue = false;
  int _mouseClickCount = 0;
  Duration? _lastMouseClickTimeStamp;
  Offset? _lastMouseClickPosition;
  int? _lastMouseClickDevice;
  String? _errorMessage;
  int _lineMetadataVersion = -1;
  int _lineMetadataStartUtf16 = -1;
  int _firstLineNumber = 0;
  int _documentLineCount = 1;
  final GlobalKey _horizontalViewportKey = GlobalKey();
  Timer? _foldSymbolsTimer;
  int _scheduledFoldDocId = -1;
  int _scheduledFoldVersion = -1;
  int _foldSymbolsDocId = -1;
  int _foldSymbolsVersion = -1;
  List<EditorFoldSymbol> _foldSymbols = const [];
  final Set<String> _collapsedFoldKeys = {};
  EditorFoldLayout _lastFoldLayout = const EditorFoldLayout.empty();
  int _reportedFoldDocId = -1;
  int _reportedFoldVersion = -1;
  List<EditorDocumentLineRange> _reportedFoldRanges = const [];

  TextEditingValue get editingValue => _controller.value;

  /// Hit-tests a global pointer coordinate against this editor's text layout.
  int? _textOffsetAtGlobalPosition(Offset globalPosition) {
    final editable = _findEditableRenderObject(context);
    if (editable == null) return null;
    return editable.getPositionForPoint(globalPosition).offset;
  }

  void _handlePointerDown(PointerDownEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event.buttons == kPrimaryButton &&
        keyboard.isAltPressed &&
        !keyboard.isControlPressed) {
      final offset = _textOffsetAtGlobalPosition(event.position);
      if (offset != null) widget.onAltClick?.call(offset);
    }

    final supportsDesktopTripleClick =
        defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS;
    if (!supportsDesktopTripleClick ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryButton ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed) {
      _resetMouseClickSequence();
      return;
    }

    final previousTimeStamp = _lastMouseClickTimeStamp;
    final previousPosition = _lastMouseClickPosition;
    final elapsed =
        previousTimeStamp == null ? null : event.timeStamp - previousTimeStamp;
    final continuesSequence = elapsed != null &&
        elapsed >= Duration.zero &&
        elapsed <= kDoubleTapTimeout &&
        previousPosition != null &&
        (event.position - previousPosition).distance <= kDoubleTapSlop &&
        _lastMouseClickDevice == event.device;
    _mouseClickCount = continuesSequence ? _mouseClickCount + 1 : 1;
    _lastMouseClickTimeStamp = event.timeStamp;
    _lastMouseClickPosition = event.position;
    _lastMouseClickDevice = event.device;

    if (_mouseClickCount == 3) {
      _resetMouseClickSequence();
      final localOffset = _textOffsetAtGlobalPosition(event.position);
      if (localOffset != null) {
        final window = widget.inputWindow;
        _selectLogicalLineAt(window.startUtf16 + localOffset);
      }
    }
  }

  void _resetMouseClickSequence() {
    _mouseClickCount = 0;
    _lastMouseClickTimeStamp = null;
    _lastMouseClickPosition = null;
    _lastMouseClickDevice = null;
  }

  void _selectLogicalLineAt(int documentOffsetUtf16) {
    final initialWindow = widget.inputWindow;
    final document = initialWindow.document;
    final documentId = document.id;
    final version = initialWindow.version;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final window = widget.inputWindow;
      if (window.document.id != documentId ||
          window.version != version ||
          (window.pendingText != null && window.pendingText != window.text)) {
        return;
      }
      final requestedLocalOffset = documentOffsetUtf16 - window.startUtf16;
      final localOffset =
          requestedLocalOffset < 0 || requestedLocalOffset > window.text.length
              ? window.text.length ~/ 2
              : requestedLocalOffset;
      final boundary = document.lineBoundary(documentOffsetUtf16);
      if (boundary.version != version) return;

      var selectionEnd = boundary.endUtf16;
      final lineEnding = document.readRange(
        selectionEnd,
        maxLenUtf16: 2,
      );
      if (lineEnding.version != version ||
          lineEnding.startUtf16 != selectionEnd) {
        return;
      }
      if (lineEnding.text.startsWith('\r\n')) {
        selectionEnd += 2;
      } else if (lineEnding.text.startsWith('\n') ||
          lineEnding.text.startsWith('\r')) {
        selectionEnd++;
      }

      final localStart = boundary.startUtf16 - window.startUtf16;
      final localEnd = selectionEnd - window.startUtf16;
      final spansInputWindow = boundary.startUtf16 < window.startUtf16 ||
          selectionEnd > window.endUtf16;
      if (spansInputWindow) {
        final callback = widget.onCrossWindowLineSelection;
        if (callback == null) {
          setSelection(TextSelection(
            baseOffset: localStart.clamp(0, window.text.length).toInt(),
            extentOffset: localEnd.clamp(0, window.text.length).toInt(),
          ));
        } else {
          callback(TextSelection(
            baseOffset: boundary.startUtf16,
            extentOffset: selectionEnd,
          ));
          setSelection(TextSelection.collapsed(offset: localOffset));
        }
        return;
      }
      if (localStart < 0 ||
          localStart > window.text.length ||
          localEnd > window.text.length ||
          localStart > localEnd) {
        return;
      }
      setSelection(
          TextSelection(baseOffset: localStart, extentOffset: localEnd));
    });
  }

  RenderEditable? _findEditableRenderObject(BuildContext subtree) {
    if (subtree is StatefulElement && subtree.state is EditableTextState) {
      return (subtree.state as EditableTextState).renderEditable;
    }
    RenderEditable? found;
    subtree.visitChildElements((child) {
      found ??= _findEditableRenderObject(child);
    });
    return found;
  }

  /// Changes the local selection while keeping the input window's acknowledged
  /// selection in step with the Flutter text-input client.
  void setSelection(TextSelection selection) {
    _controller.value = _controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
  }

  /// Applies a local bounded value through the field's ordinary enqueue path.
  void setEditingValue(TextEditingValue value) {
    _controller.value = value;
  }

  /// Applies a host-generated edit through the same multi-selection formatter
  /// used by platform typing, then follows the ordinary bounded writeback path.
  void applyFormattedValue(TextEditingValue value) {
    final formatter = widget.inputFormatter;
    _controller.value =
        formatter?.formatEditUpdate(_controller.value, value) ?? value;
  }

  void requestFocus() => _focusNode.requestFocus();

  @override
  void initState() {
    super.initState();
    _controller = _SyntaxTextEditingController.fromValue(
      widget.inputWindow.initialValue,
    )
      ..addListener(_handleEditingValueChanged)
      ..addListener(_handleFoldSelectionChanged);
    _lastAcceptedValue = _controller.value;
    _setFocusNode(widget.focusNode);
    _setHorizontalScrollController(widget.horizontalScrollController);
    _syncFoldSymbols();
  }

  @override
  void didUpdateWidget(covariant RustTextInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _disposeOwnedFocusNode();
      _setFocusNode(widget.focusNode);
    }
    if (oldWidget.horizontalScrollController !=
        widget.horizontalScrollController) {
      _disposeOwnedHorizontalScrollController();
      _setHorizontalScrollController(widget.horizontalScrollController);
    }
    if (oldWidget.wordWrap && !widget.wordWrap) {
      _scheduleCaretReveal();
    }
    if (oldWidget.inputWindow != widget.inputWindow) {
      assert(
        oldWidget.inputWindow.pendingCount == 0,
        'Flush the old input window before replacing it.',
      );
      _restoreValue(widget.inputWindow.initialValue);
      _errorMessage = null;
    }
    _syncFoldSymbols();
  }

  void _syncFoldSymbols() {
    if (!widget.enableCodeFolding) {
      _foldSymbolsTimer?.cancel();
      _foldSymbolsTimer = null;
      _foldSymbols = const [];
      _foldSymbolsDocId = -1;
      _foldSymbolsVersion = -1;
      _collapsedFoldKeys.clear();
      return;
    }
    final document = widget.inputWindow.document;
    final version = widget.inputWindow.version;
    if (widget.inputWindow.pendingText != null || document.version != version) {
      _foldSymbolsTimer?.cancel();
      _foldSymbolsTimer = null;
      _scheduledFoldDocId = -1;
      _scheduledFoldVersion = -1;
      return;
    }
    if ((_foldSymbolsDocId == document.id && _foldSymbolsVersion == version) ||
        (_scheduledFoldDocId == document.id &&
            _scheduledFoldVersion == version)) {
      return;
    }
    _foldSymbolsTimer?.cancel();
    _scheduledFoldDocId = document.id;
    _scheduledFoldVersion = version;
    _foldSymbolsTimer = Timer(const Duration(milliseconds: 350), () {
      _foldSymbolsTimer = null;
      _scheduledFoldDocId = -1;
      _scheduledFoldVersion = -1;
      if (!mounted ||
          !widget.enableCodeFolding ||
          widget.inputWindow.document.id != document.id ||
          widget.inputWindow.version != version ||
          widget.inputWindow.pendingText != null ||
          document.version != version) {
        return;
      }
      final result = document.core.lsp.symbols(document.id);
      if (!mounted ||
          result == null ||
          result.version != version ||
          widget.inputWindow.document.id != document.id ||
          widget.inputWindow.version != version ||
          widget.inputWindow.pendingText != null ||
          document.version != version) {
        return;
      }
      final symbols = <EditorFoldSymbol>[
        for (final value in result.symbols)
          if (EditorFoldSymbol.fromMap(value) case final symbol?) symbol,
      ];
      final validKeys = symbols.map((symbol) => symbol.key).toSet();
      setState(() {
        _foldSymbols = List.unmodifiable(symbols);
        _foldSymbolsDocId = document.id;
        _foldSymbolsVersion = version;
        _collapsedFoldKeys.removeWhere((key) => !validKeys.contains(key));
      });
    });
  }

  EditorFoldLayout _buildFoldLayout(String text) {
    final window = widget.inputWindow;
    if (!widget.enableCodeFolding ||
        window.pendingText != null ||
        window.version != window.document.version ||
        text != window.text ||
        _foldSymbolsDocId != window.document.id ||
        _foldSymbolsVersion != window.version) {
      return const EditorFoldLayout.empty();
    }
    return buildEditorFoldLayout(
      text: text,
      firstDocumentLine: _firstLineNumber,
      symbols: _foldSymbols,
      collapsedKeys: _collapsedFoldKeys,
    );
  }

  void _reportFoldRanges() {
    final callback = widget.onFoldRangesChanged;
    if (callback == null) return;
    final window = widget.inputWindow;
    final document = window.document;
    final isCurrent = widget.enableCodeFolding &&
        window.pendingText == null &&
        window.version == document.version &&
        _foldSymbolsDocId == document.id &&
        _foldSymbolsVersion == window.version;
    final ranges = isCurrent
        ? normalizeEditorDocumentLineRanges(
            _foldSymbols
                .where((symbol) => _collapsedFoldKeys.contains(symbol.key))
                .map((symbol) => EditorDocumentLineRange(
                      startLine: symbol.line,
                      endLineExclusive: symbol.endLine,
                    )),
            documentLineCount: _documentLineCount,
          )
        : const <EditorDocumentLineRange>[];
    final documentId = document.id;
    final version = window.version;
    if (_reportedFoldDocId == documentId &&
        _reportedFoldVersion == version &&
        listEquals(_reportedFoldRanges, ranges)) {
      return;
    }
    _reportedFoldDocId = documentId;
    _reportedFoldVersion = version;
    _reportedFoldRanges = ranges;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.inputWindow.document.id != documentId ||
          widget.inputWindow.version != version) {
        return;
      }
      callback(documentId, version, ranges);
    });
  }

  bool _editingValueIntersectsFold(
    TextEditingValue value,
    EditorFoldRange range,
  ) {
    bool intersects(TextRange selection) {
      if (!selection.isValid) return false;
      if (selection.isCollapsed) {
        return selection.start >= range.hiddenStartUtf16 &&
            selection.start < range.hiddenEndUtf16;
      }
      return selection.start < range.hiddenEndUtf16 &&
          selection.end > range.hiddenStartUtf16;
    }

    return intersects(value.selection) || intersects(value.composing);
  }

  void _handleFoldSelectionChanged() {
    if (!widget.enableCodeFolding ||
        _collapsedFoldKeys.isEmpty ||
        _controller.text != widget.inputWindow.text) {
      return;
    }
    final value = _controller.value;
    final expanded = _lastFoldLayout.collapsedRanges
        .where((range) => _editingValueIntersectsFold(value, range))
        .map((range) => range.symbol.key)
        .toSet();
    if (!expanded.any(_collapsedFoldKeys.contains)) return;
    _collapsedFoldKeys.removeAll(expanded);
    setState(() {});
  }

  void _toggleFold(EditorFoldLayout layout, EditorFoldSymbol symbol) {
    if (_collapsedFoldKeys.remove(symbol.key)) {
      setState(() {});
      return;
    }
    final range = layout.foldRangesByLine.values
        .where((candidate) => candidate.symbol.key == symbol.key)
        .firstOrNull;
    if (range == null ||
        _editingValueIntersectsFold(_controller.value, range)) {
      return;
    }
    setState(() => _collapsedFoldKeys.add(symbol.key));
  }

  void _handleFoldGutterTap({
    required TapUpDetails details,
    required EditorFoldLayout layout,
    required TextSpan textSpan,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required EdgeInsets padding,
    required double textWidth,
  }) {
    if (details.localPosition.dx > 14 || layout.foldableByLine.isEmpty) return;
    final painter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (textWidth - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY = editorScrollOffset(widget.scrollController);
    final lineHeight = painter.preferredLineHeight;
    final lines = editorLogicalLines(_controller.text);
    EditorFoldSymbol? hit;
    for (final entry in layout.foldableByLine.entries) {
      final line = lines[entry.key];
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: line.startUtf16),
        Rect.fromLTWH(0, 0, 1.5, lineHeight),
      );
      final top = padding.top + caret.dy - scrollY;
      if (details.localPosition.dy >= top &&
          details.localPosition.dy <= top + lineHeight) {
        hit = entry.value;
        break;
      }
    }
    painter.dispose();
    if (hit != null) _toggleFold(layout, hit);
  }

  List<
      ({
        EditorFoldSymbol symbol,
        double top,
        double height,
        bool collapsed,
      })> _foldControlTargets({
    required EditorFoldLayout layout,
    required TextSpan textSpan,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required EdgeInsets padding,
    required double textWidth,
    required double viewportHeight,
  }) {
    if (layout.foldableByLine.isEmpty) return const [];
    final painter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (textWidth - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY = editorScrollOffset(widget.scrollController);
    final lineHeight = painter.preferredLineHeight;
    final lines = editorLogicalLines(_controller.text);
    final controls = <({
      EditorFoldSymbol symbol,
      double top,
      double height,
      bool collapsed,
    })>[];
    for (final entry in layout.foldableByLine.entries) {
      if (layout.hiddenLineIndices.contains(entry.key) ||
          entry.key < 0 ||
          entry.key >= lines.length) {
        continue;
      }
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: lines[entry.key].startUtf16),
        Rect.fromLTWH(0, 0, 1.5, lineHeight),
      );
      final top = padding.top + caret.dy - scrollY;
      if (top + lineHeight < 0 || top > viewportHeight) continue;
      controls.add((
        symbol: entry.value,
        top: top,
        height: lineHeight,
        collapsed: layout.collapsedRanges
            .any((range) => range.symbol.key == entry.value.key),
      ));
    }
    painter.dispose();
    return List.unmodifiable(controls);
  }

  void _setFocusNode(FocusNode? external) {
    _ownsFocusNode = external == null;
    _focusNode = external ?? FocusNode();
  }

  void _disposeOwnedFocusNode() {
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _setHorizontalScrollController(ScrollController? external) {
    _ownsHorizontalScrollController = external == null;
    _horizontalScrollController = external ?? ScrollController();
  }

  void _disposeOwnedHorizontalScrollController() {
    if (_ownsHorizontalScrollController) _horizontalScrollController.dispose();
  }

  void _scheduleCaretReveal() {
    if (widget.wordWrap) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) return;
      final selection = _controller.selection;
      if (!selection.isValid) return;
      final viewport =
          _horizontalViewportKey.currentContext?.findRenderObject();
      final editable = _findEditableRenderObject(context);
      if (viewport is! RenderBox || !viewport.hasSize || editable == null) {
        return;
      }
      final caret = editable.getLocalRectForCaret(selection.extent);
      final caretTopLeft = editable.localToGlobal(caret.topLeft);
      final caretBottomRight = editable.localToGlobal(caret.bottomRight);
      final caretRect = Rect.fromPoints(caretTopLeft, caretBottomRight);
      final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
      final position = _horizontalScrollController.position;
      var delta = 0.0;
      if (position.axisDirection == AxisDirection.right) {
        if (caretRect.right > viewportRect.right) {
          delta = caretRect.right - viewportRect.right + 8;
        } else if (caretRect.left < viewportRect.left) {
          delta = caretRect.left - viewportRect.left - 8;
        }
      } else if (position.axisDirection == AxisDirection.left) {
        if (caretRect.left < viewportRect.left) {
          delta = viewportRect.left - caretRect.left + 8;
        } else if (caretRect.right > viewportRect.right) {
          delta = viewportRect.right - caretRect.right - 8;
        }
      }
      if (delta == 0) return;
      position.jumpTo(
        (position.pixels + delta)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  void _handleEditingValueChanged() {
    if (_restoringValue) return;
    _scheduleCaretReveal();
    final value = _controller.value;
    final additionalOperations =
        widget.additionalOperations?.call() ?? const <TextOp>[];
    try {
      widget.inputWindow.enqueue(
        value,
        additionalOperations: additionalOperations,
      );
      if (additionalOperations.isEmpty) {
        _lastAcceptedValue = value;
        _scheduleFlush();
      } else {
        flushPending();
      }
    } on TextInputWindowLimitException catch (error) {
      if (value.text.length > widget.inputWindow.maxWindowUtf16) {
        try {
          final previousPresentation = widget.inputWindow.presentedText;
          final delta = widget.inputWindow.applyOversized(
            value,
            additionalOperations: additionalOperations,
          );
          _restoreValue(
              delta.replacementValue ?? widget.inputWindow.initialValue);
          _notifyPresentationChanged(previousPresentation);
          _clearError();
          widget.onDelta?.call(delta);
        } catch (oversizedError) {
          _restoreValue(_lastAcceptedValue);
          _reportError(oversizedError);
        }
      } else {
        _restoreValue(_lastAcceptedValue);
        _reportError(error);
      }
    } catch (error) {
      _reportError(error);
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushScheduled = false;
      if (!mounted) return;
      try {
        flushPending();
      } catch (_) {
        // The error is reported by flushPending and the Rust session retains
        // the unsynchronized value for an explicit recovery attempt.
      }
    });
  }

  /// Flushes the one-slot queue. Call before saving or switching documents.
  RustTextInputDelta? flushPending() {
    try {
      final previousPresentation = widget.inputWindow.presentedText;
      final delta = widget.inputWindow.flushPending();
      if (delta != null) {
        if (mounted) {
          setState(() => _lineMetadataVersion = -1);
        }
        _notifyPresentationChanged(previousPresentation);
        _lastAcceptedValue = _controller.value;
        _clearError();
        widget.onDelta?.call(delta);
      }
      return delta;
    } catch (error) {
      _reportError(error);
      rethrow;
    }
  }

  /// Commits the active preedit before a host save/focus operation.
  RustTextInputDelta? commitComposition() {
    try {
      final previousPresentation = widget.inputWindow.presentedText;
      final delta = widget.inputWindow.commitComposition();
      if (delta != null) {
        _notifyPresentationChanged(previousPresentation);
        _restoreValue(_valueForDelta(delta));
        _clearError();
        widget.onDelta?.call(delta);
      }
      return delta;
    } catch (error) {
      _reportError(error);
      rethrow;
    }
  }

  /// Cancels the active preedit and restores the text last committed to Rust.
  RustTextInputDelta? cancelComposition() {
    try {
      final previousPresentation = widget.inputWindow.presentedText;
      final delta = widget.inputWindow.cancelComposition();
      if (delta != null) {
        _notifyPresentationChanged(previousPresentation);
        _restoreValue(delta.replacementValue ?? _valueForDelta(delta));
        _clearError();
        widget.onDelta?.call(delta);
      }
      return delta;
    } catch (error) {
      _reportError(error);
      rethrow;
    }
  }

  void recoverPending() {
    try {
      final previousPresentation = widget.inputWindow.presentedText;
      final delta = widget.inputWindow.recoverPending();
      if (delta == null) {
        _notifyPresentationChanged(previousPresentation);
        _clearError();
        return;
      }
      _notifyPresentationChanged(previousPresentation);
      _restoreValue(_valueForDelta(delta));
      _clearError();
      widget.onDelta?.call(delta);
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> copyPendingDraft() async {
    final pending = widget.inputWindow.pendingText;
    if (pending == null) return;
    await Clipboard.setData(ClipboardData(text: pending));
  }

  TextEditingValue _valueForDelta(RustTextInputDelta delta) {
    final localSelection = delta.selectionWindow;
    return TextEditingValue(
      text: widget.inputWindow.text,
      selection: localSelection ??
          TextSelection.collapsed(offset: widget.inputWindow.text.length),
      composing: TextRange.empty,
    );
  }

  void _restoreValue(TextEditingValue value) {
    _restoringValue = true;
    try {
      _controller.value = value;
      _lastAcceptedValue = value;
    } finally {
      _restoringValue = false;
    }
  }

  void _notifyPresentationChanged(String previousPresentation) {
    if (previousPresentation != widget.inputWindow.presentedText) {
      widget.onPresentationChanged?.call();
    }
  }

  void _reportError(Object error) {
    if (mounted) {
      setState(() => _errorMessage = error.toString());
    }
    widget.onError?.call(error);
  }

  void _clearError() {
    if (_errorMessage == null || !mounted) return;
    setState(() => _errorMessage = null);
  }

  void _updateLineMetadata() {
    final window = widget.inputWindow;
    if (_lineMetadataVersion == window.version &&
        _lineMetadataStartUtf16 == window.startUtf16) {
      return;
    }
    final position =
        resolveEditorDocumentLinePosition(window.document, window.startUtf16);
    _lineMetadataVersion = window.version;
    _lineMetadataStartUtf16 = window.startUtf16;
    _firstLineNumber = position.firstLineNumber;
    _documentLineCount = position.lineCount;
  }

  @override
  Widget build(BuildContext context) {
    _updateLineMetadata();
    _syncFoldSymbols();
    final foldLayout = _buildFoldLayout(_controller.text);
    _lastFoldLayout = foldLayout;
    _reportFoldRanges();
    _controller.configureSyntax(
      tokens: widget.syntaxTokens,
      tokenVersion: widget.syntaxVersion,
      windowVersion: widget.inputWindow.version,
      windowStartUtf16: widget.inputWindow.startUtf16,
      windowText: widget.inputWindow.text,
      colorForKind: widget.syntaxTokenColor,
      foldedRanges: foldLayout.collapsedRanges,
    );
    final requestedStyle =
        widget.style ?? const TextStyle(fontFamily: 'monospace');
    final editorStyle = requestedStyle.copyWith(
      fontFamilyFallback: widget.fontFamilyFallback ??
          requestedStyle.fontFamilyFallback ??
          editorFontFamilyFallbacks,
    );
    final theme = Theme.of(context);
    final inputBaseStyle = theme.useMaterial3
        ? theme.textTheme.bodyLarge!
        : theme.textTheme.titleMedium!;
    final field = Listener(
      onPointerDown: _handlePointerDown,
      child: TextField(
        key: const ValueKey<String>('rust-bounded-text-input'),
        controller: _controller,
        focusNode: _focusNode,
        scrollController: widget.scrollController,
        inputFormatters:
            widget.inputFormatter == null ? null : [widget.inputFormatter!],
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        keyboardType: TextInputType.multiline,
        maxLines: null,
        expands: true,
        style: editorStyle,
        strutStyle:
            _controller.hasVisibleFoldedRanges ? StrutStyle.disabled : null,
        decoration: widget.decoration ??
            const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
            ),
      ),
    );
    final textStyle = inputBaseStyle.merge(editorStyle);
    final editorTextSpan = _controller.buildTextSpan(
      context: context,
      style: textStyle,
      withComposing: true,
    );
    final gutterStyle = textStyle.copyWith(fontSize: 11);
    final padding = (widget.decoration?.contentPadding ?? EdgeInsets.zero)
        .resolve(Directionality.of(context));
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final showGutter =
        widget.showLineNumbers || foldLayout.foldableByLine.isNotEmpty;
    final gutterWidth = widget.showLineNumbers
        ? editorGutterWidth(
            lineCount: _documentLineCount,
            style: gutterStyle,
            textScaler: textScaler,
            textDirection: textDirection,
          )
        : showGutter
            ? 18.0
            : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final editorWidth = (constraints.maxWidth - gutterWidth)
                  .clamp(1.0, double.infinity)
                  .toDouble();
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, editingValue, _) {
                  final contentWidth = widget.wordWrap
                      ? editorWidth
                      : editorUnwrappedTextWidth(
                          text: editingValue.text,
                          style: textStyle,
                          textScaler: textScaler,
                          textDirection: textDirection,
                          padding: padding,
                        ).clamp(editorWidth, double.infinity).toDouble();
                  final editorContent = Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.rangeDecorations.any(
                          (decoration) => decoration.backgroundColor != null))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: EditorRangeDecorationPainter(
                                text: editingValue.text,
                                textSpan: editorTextSpan,
                                windowVersion: widget.inputWindow.version,
                                windowStartUtf16: widget.inputWindow.startUtf16,
                                decorations: widget.rangeDecorations,
                                style: textStyle,
                                textDirection: textDirection,
                                textScaler: textScaler,
                                padding: padding,
                                scrollController: widget.scrollController,
                                paintBackgrounds: true,
                              ),
                            ),
                          ),
                        ),
                      Semantics(
                        label: widget.semanticsLabel,
                        textField: true,
                        child: field,
                      ),
                      if (widget.showIndentGuides ||
                          widget.whitespaceMode != EditorWhitespaceMode.none)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: EditorTextDecorationPainter(
                                text: editingValue.text,
                                textSpan: editorTextSpan,
                                style: textStyle,
                                textDirection: textDirection,
                                textScaler: textScaler,
                                padding: padding,
                                scrollController: widget.scrollController,
                                showIndentGuides: widget.showIndentGuides,
                                tabSize: widget.tabSize,
                                whitespaceMode: widget.whitespaceMode,
                                guideColor: const Color(0x557A8290),
                                whitespaceColor: const Color(0xFF727983),
                                hiddenLineIndices: foldLayout.hiddenLineIndices,
                              ),
                            ),
                          ),
                        ),
                      if (widget.additionalSelections.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _AdditionalSelectionsPainter(
                                text: editingValue.text,
                                textSpan: editorTextSpan,
                                selections: widget.additionalSelections,
                                style: textStyle,
                                textDirection: textDirection,
                                textScaler: textScaler,
                                padding: padding,
                                scrollController: widget.scrollController,
                                caretColor:
                                    Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      if (widget.rangeDecorations.any(
                        (decoration) =>
                            decoration.borderColor != null ||
                            decoration.underlineColor != null,
                      ))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: EditorRangeDecorationPainter(
                                text: editingValue.text,
                                textSpan: editorTextSpan,
                                windowVersion: widget.inputWindow.version,
                                windowStartUtf16: widget.inputWindow.startUtf16,
                                decorations: widget.rangeDecorations,
                                style: textStyle,
                                textDirection: textDirection,
                                textScaler: textScaler,
                                padding: padding,
                                scrollController: widget.scrollController,
                                paintBackgrounds: false,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                  final editorViewport = widget.wordWrap
                      ? editorContent
                      : SingleChildScrollView(
                          key: _horizontalViewportKey,
                          controller: _horizontalScrollController,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentWidth,
                            child: editorContent,
                          ),
                        );
                  Widget buildGutterContents() {
                    final controls = _foldControlTargets(
                      layout: foldLayout,
                      textSpan: editorTextSpan,
                      textDirection: textDirection,
                      textScaler: textScaler,
                      padding: padding,
                      textWidth: contentWidth,
                      viewportHeight: constraints.maxHeight,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: EditorGutterPainter(
                            text: editingValue.text,
                            textSpan: editorTextSpan,
                            firstLineNumber: _firstLineNumber,
                            style: textStyle,
                            textDirection: textDirection,
                            textScaler: textScaler,
                            padding: padding,
                            textWidth: contentWidth,
                            scrollController: widget.scrollController,
                            backgroundColor: const Color(0xFF191B20),
                            foregroundColor: const Color(0xFF858585),
                            dividerColor: const Color(0xFF2A2D33),
                            hiddenLineIndices: foldLayout.hiddenLineIndices,
                            foldableLineIndices: foldLayout.foldableLineIndices,
                            collapsedLineIndices:
                                foldLayout.collapsedLineIndices,
                            showLineNumbers: widget.showLineNumbers,
                          ),
                        ),
                        for (final control in controls)
                          Positioned(
                            left: 0,
                            top: control.top,
                            width: 14,
                            height: control.height,
                            child: Semantics(
                              key: ValueKey(
                                'editor-fold-${control.symbol.key}',
                              ),
                              button: true,
                              label: control.collapsed
                                  ? '展开 ${control.symbol.name} 区域'
                                  : '折叠 ${control.symbol.name} 区域',
                              value: control.collapsed ? '已折叠' : '已展开',
                              hint: '第 ${control.symbol.line} 行',
                              onTap: () => _toggleFold(
                                foldLayout,
                                control.symbol,
                              ),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                excludeFromSemantics: true,
                                onTap: () => _toggleFold(
                                  foldLayout,
                                  control.symbol,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                      ],
                    );
                  }

                  final scrollController = widget.scrollController;
                  final gutterContents = scrollController == null
                      ? buildGutterContents()
                      : AnimatedBuilder(
                          animation: scrollController,
                          builder: (context, _) => buildGutterContents(),
                        );
                  return Row(
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showGutter)
                        GestureDetector(
                          key: const ValueKey<String>('rust-editor-gutter'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: foldLayout.foldableByLine.isEmpty
                              ? null
                              : (details) => _handleFoldGutterTap(
                                    details: details,
                                    layout: foldLayout,
                                    textSpan: editorTextSpan,
                                    textDirection: textDirection,
                                    textScaler: textScaler,
                                    padding: padding,
                                    textWidth: contentWidth,
                                  ),
                          child: SizedBox(
                            width: gutterWidth,
                            child: gutterContents,
                          ),
                        ),
                      Expanded(child: editorViewport),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (_errorMessage case final message?)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const ValueKey<String>(
                            'rust-bounded-text-input-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: recoverPending,
                    child: const Text('重试同步'),
                  ),
                  TextButton(
                    onPressed: widget.inputWindow.pendingText == null
                        ? null
                        : copyPendingDraft,
                    child: const Text('复制草稿'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    assert(
      widget.inputWindow.pendingCount == 0,
      'Flush the bounded input window before removing this widget.',
    );
    _controller
      ..removeListener(_handleEditingValueChanged)
      ..removeListener(_handleFoldSelectionChanged)
      ..dispose();
    _foldSymbolsTimer?.cancel();
    _disposeOwnedFocusNode();
    _disposeOwnedHorizontalScrollController();
    super.dispose();
  }
}

class _AdditionalSelectionsPainter extends CustomPainter {
  _AdditionalSelectionsPainter({
    required this.text,
    required this.textSpan,
    required this.selections,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.padding,
    required this.scrollController,
    required this.caretColor,
  }) : super(repaint: scrollController);

  final String text;
  final TextSpan textSpan;
  final List<TextSelection> selections;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final EdgeInsets padding;
  final ScrollController? scrollController;
  final Color caretColor;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (size.width - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY = editorScrollOffset(scrollController);
    final origin = Offset(padding.left, padding.top - scrollY);
    final selectionPaint = Paint()..color = const Color(0x665B9BD5);
    final caretPaint = Paint()
      ..color = caretColor
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final selection in selections) {
      final base = selection.baseOffset.clamp(0, text.length).toInt();
      final extent = selection.extentOffset.clamp(0, text.length).toInt();
      final start = base < extent ? base : extent;
      final end = base < extent ? extent : base;
      if (start != end) {
        for (final box in painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )) {
          canvas.drawRect(box.toRect().shift(origin), selectionPaint);
        }
      } else {
        final caret = painter.getOffsetForCaret(
          TextPosition(offset: extent),
          Rect.fromLTWH(0, 0, 2, painter.preferredLineHeight),
        );
        canvas.drawLine(
          origin + caret,
          origin + caret + Offset(0, painter.preferredLineHeight),
          caretPaint,
        );
      }
    }
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _AdditionalSelectionsPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.textSpan != textSpan ||
      !listEquals(oldDelegate.selections, selections) ||
      oldDelegate.style != style ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.padding != padding ||
      oldDelegate.scrollController != scrollController ||
      oldDelegate.caretColor != caretColor;
}
