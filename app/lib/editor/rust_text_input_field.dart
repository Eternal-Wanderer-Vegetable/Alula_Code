import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton, PointerDownEvent;
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'editor_rendering.dart';
import 'rust_text_input_window.dart';

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
    this.decoration,
    this.showLineNumbers = true,
    this.showIndentGuides = true,
    this.whitespaceMode = EditorWhitespaceMode.none,
    this.tabSize = 4,
    this.semanticsLabel,
    this.onTap,
    this.onAltClick,
    this.onDelta,
    this.onError,
    this.onPresentationChanged,
  }) : assert(tabSize > 0);

  final RustTextInputWindow inputWindow;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final TextInputFormatter? inputFormatter;
  final List<TextSelection> additionalSelections;
  final List<TextOp> Function()? additionalOperations;
  final bool autofocus;
  final TextStyle? style;
  final InputDecoration? decoration;
  final bool showLineNumbers;
  final bool showIndentGuides;
  final EditorWhitespaceMode whitespaceMode;
  final int tabSize;
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final ValueChanged<int>? onAltClick;
  final ValueChanged<RustTextInputDelta>? onDelta;
  final ValueChanged<Object>? onError;
  final VoidCallback? onPresentationChanged;

  @override
  RustTextInputFieldState createState() => RustTextInputFieldState();
}

class RustTextInputFieldState extends State<RustTextInputField> {
  late TextEditingController _controller;
  late TextEditingValue _lastAcceptedValue;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _flushScheduled = false;
  bool _restoringValue = false;
  String? _errorMessage;
  int _lineMetadataVersion = -1;
  int _lineMetadataStartUtf16 = -1;
  int _firstLineNumber = 0;
  int _documentLineCount = 1;

  TextEditingValue get editingValue => _controller.value;

  /// Hit-tests a global pointer coordinate against this editor's text layout.
  int? _textOffsetAtGlobalPosition(Offset globalPosition) {
    final editable = _findEditableRenderObject(context);
    if (editable == null) return null;
    return editable.getPositionForPoint(globalPosition).offset;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton ||
        !HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final offset = _textOffsetAtGlobalPosition(event.position);
    if (offset != null) widget.onAltClick?.call(offset);
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
    _controller =
        TextEditingController.fromValue(widget.inputWindow.initialValue)
          ..addListener(_handleEditingValueChanged);
    _lastAcceptedValue = _controller.value;
    _setFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant RustTextInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _disposeOwnedFocusNode();
      _setFocusNode(widget.focusNode);
    }
    if (oldWidget.inputWindow != widget.inputWindow) {
      assert(
        oldWidget.inputWindow.pendingCount == 0,
        'Flush the old input window before replacing it.',
      );
      _restoreValue(widget.inputWindow.initialValue);
      _errorMessage = null;
    }
  }

  void _setFocusNode(FocusNode? external) {
    _ownsFocusNode = external == null;
    _focusNode = external ?? FocusNode();
  }

  void _disposeOwnedFocusNode() {
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _handleEditingValueChanged() {
    if (_restoringValue) return;
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
    final editorStyle =
        widget.style ?? const TextStyle(fontFamily: 'monospace');
    final field = Listener(
      onPointerDown: widget.onAltClick == null ? null : _handlePointerDown,
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
        decoration: widget.decoration ??
            const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
            ),
      ),
    );
    final textStyle = DefaultTextStyle.of(context).style.merge(
          editorStyle,
        );
    final gutterStyle = textStyle.copyWith(fontSize: 11);
    final padding = (widget.decoration?.contentPadding ?? EdgeInsets.zero)
        .resolve(Directionality.of(context));
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final gutterWidth = widget.showLineNumbers
        ? editorGutterWidth(
            lineCount: _documentLineCount,
            style: gutterStyle,
            textScaler: textScaler,
            textDirection: textDirection,
          )
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
                builder: (context, editingValue, _) => Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.showLineNumbers)
                      SizedBox(
                        key: const ValueKey<String>('rust-editor-gutter'),
                        width: gutterWidth,
                        child: CustomPaint(
                          painter: EditorGutterPainter(
                            text: editingValue.text,
                            firstLineNumber: _firstLineNumber,
                            style: textStyle,
                            textDirection: textDirection,
                            textScaler: textScaler,
                            padding: padding,
                            textWidth: editorWidth,
                            scrollController: widget.scrollController,
                            backgroundColor: const Color(0xFF191B20),
                            foregroundColor: const Color(0xFF858585),
                            dividerColor: const Color(0xFF2A2D33),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Semantics(
                            label: widget.semanticsLabel,
                            textField: true,
                            child: field,
                          ),
                          if (widget.showIndentGuides ||
                              widget.whitespaceMode !=
                                  EditorWhitespaceMode.none)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: EditorTextDecorationPainter(
                                    text: editingValue.text,
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
                        ],
                      ),
                    ),
                  ],
                ),
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
      ..dispose();
    _disposeOwnedFocusNode();
    super.dispose();
  }
}

class _AdditionalSelectionsPainter extends CustomPainter {
  _AdditionalSelectionsPainter({
    required this.text,
    required this.selections,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.padding,
    required this.scrollController,
    required this.caretColor,
  }) : super(repaint: scrollController);

  final String text;
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
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (size.width - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY =
        scrollController?.hasClients == true ? scrollController!.offset : 0.0;
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
      !listEquals(oldDelegate.selections, selections) ||
      oldDelegate.style != style ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.padding != padding ||
      oldDelegate.scrollController != scrollController ||
      oldDelegate.caretColor != caretColor;
}
