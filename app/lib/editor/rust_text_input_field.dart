import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'rust_text_input_window.dart';

/// A multiline Flutter input client whose document mirror is a bounded Rust
/// text window. Flutter's EditableText owns native IME and candidate geometry.
class RustTextInputField extends StatefulWidget {
  const RustTextInputField({
    super.key,
    required this.inputWindow,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.style,
    this.decoration,
    this.semanticsLabel,
    this.onTap,
    this.onDelta,
    this.onError,
  });

  final RustTextInputWindow inputWindow;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final TextStyle? style;
  final InputDecoration? decoration;
  final String? semanticsLabel;
  final VoidCallback? onTap;
  final ValueChanged<RustTextInputDelta>? onDelta;
  final ValueChanged<Object>? onError;

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

  TextEditingValue get editingValue => _controller.value;

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
    try {
      widget.inputWindow.enqueue(value);
      _lastAcceptedValue = value;
      _scheduleFlush();
    } on TextInputWindowLimitException catch (error) {
      if (value.text.length > widget.inputWindow.maxWindowUtf16) {
        try {
          final delta = widget.inputWindow.applyOversized(value);
          _restoreValue(
              delta.replacementValue ?? widget.inputWindow.initialValue);
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
      final delta = widget.inputWindow.flushPending();
      if (delta != null) {
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
      final delta = widget.inputWindow.commitComposition();
      if (delta != null) {
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
      final delta = widget.inputWindow.cancelComposition();
      if (delta != null) {
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
      final delta = widget.inputWindow.recoverPending();
      if (delta == null) {
        _clearError();
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: const ValueKey<String>('rust-bounded-text-input'),
      controller: _controller,
      focusNode: _focusNode,
      scrollController: widget.scrollController,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      expands: true,
      style: widget.style ?? const TextStyle(fontFamily: 'monospace'),
      decoration: widget.decoration ??
          const InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
          ),
    );
    return Semantics(
      label: widget.semanticsLabel,
      textField: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: field),
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
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
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
      ),
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
