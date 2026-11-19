import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Registrations live exactly as long as their mounted group breadcrumbs.
class BreadcrumbNavigationController extends ChangeNotifier {
  final Map<String, _BreadcrumbNavigationState> _groups = {};
  _BreadcrumbNavigationState? _active;
  bool _pickerShowing = false;
  bool _disposed = false;

  void focusChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    closePicker = null;
    cancelPicker = null;
    super.dispose();
  }

  VoidCallback? closePicker;
  VoidCallback? cancelPicker;

  bool get isActive => _pickerShowing || (_active?._focus.hasFocus ?? false);

  void focusLast(String region, {bool select = false}) {
    if (_pickerShowing) return;
    final group = _groups[region];
    if (group == null) return;
    _active = group;
    group.focusLast();
    if (select) group.selectFocused();
  }

  void move(int delta) => _active?.move(delta);
  void selectFocused() => _active?.selectFocused();
  void revealFocused() => _active?.revealFocused();

  void selectEditor() {
    final active = _active;
    closePicker?.call();
    active?.clearFocus();
    active?.widget.onSelectEditor();
  }

  void setPickerShowing(bool value) {
    _pickerShowing = value;
    focusChanged();
  }
}

class BreadcrumbMenuEntry extends PopupMenuEntry<String> {
  const BreadcrumbMenuEntry({
    super.key,
    required this.item,
    required this.onEscape,
    required this.onKeyEvent,
    required this.onRoute,
    required this.onRevealAside,
    required this.first,
  });

  final PopupMenuItem<String> item;
  final bool first;
  final VoidCallback onEscape;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final ValueChanged<ModalRoute<dynamic>?> onRoute;
  final ValueChanged<String> onRevealAside;

  @override
  double get height => item.height;

  @override
  bool represents(String? value) => item.represents(value);

  @override
  State<BreadcrumbMenuEntry> createState() => _BreadcrumbMenuEntryState();
}

class _BreadcrumbMenuEntryState extends State<BreadcrumbMenuEntry> {
  @override
  Widget build(BuildContext context) {
    widget.onRoute(ModalRoute.of(context));
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onEscape();
          return KeyEventResult.handled;
        }
        final pickerKeyResult = widget.onKeyEvent(event);
        if (pickerKeyResult != KeyEventResult.ignored) return pickerKeyResult;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            widget.item.enabled &&
            widget.item.value != null) {
          final keyboard = HardwareKeyboard.instance;
          final isMac = defaultTargetPlatform == TargetPlatform.macOS;
          final primaryModifier =
              isMac ? keyboard.isMetaPressed : keyboard.isControlPressed;
          final otherModifier = isMac
              ? keyboard.isControlPressed || keyboard.isAltPressed
              : keyboard.isMetaPressed || keyboard.isAltPressed;
          if (primaryModifier && !otherModifier && !keyboard.isShiftPressed) {
            widget.onRevealAside(widget.item.value!);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: PopupMenuItem<String>(
        value: widget.item.value,
        enabled: widget.item.enabled,
        child: Focus(
          autofocus: widget.first,
          skipTraversal: true,
          child: widget.item.child!,
        ),
      ),
    );
  }
}

class BreadcrumbNavigation extends StatefulWidget {
  const BreadcrumbNavigation({
    super.key,
    required this.region,
    required this.resource,
    required this.segments,
    this.editorSegmentIndex,
    required this.controller,
    required this.onSelect,
    required this.onRevealDirectory,
    required this.onSelectEditor,
  });

  final String region;
  final Object resource;
  final List<String> segments;

  /// A terminal path segment that returns focus to its owning editor even
  /// when symbol ancestry segments follow it.
  final int? editorSegmentIndex;
  final BreadcrumbNavigationController controller;
  final Future<void> Function(int index) onSelect;
  final Future<void> Function(int index) onRevealDirectory;
  final VoidCallback onSelectEditor;

  @override
  State<BreadcrumbNavigation> createState() => _BreadcrumbNavigationState();
}

class _BreadcrumbNavigationState extends State<BreadcrumbNavigation> {
  final FocusNode _focus = FocusNode(debugLabel: 'breadcrumb');
  final ScrollController _scroll = ScrollController();
  final GlobalKey _focusedSegment = GlobalKey();
  BoxConstraints? _viewportConstraints;
  int? _index;
  bool _opening = false;
  bool _revealPending = false;

  void _scheduleReveal() {
    if (_revealPending || _index == null) return;
    _revealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealPending = false;
      if (!mounted || (!_focus.hasFocus && !_opening) || !_scroll.hasClients) {
        return;
      }
      final segment = _focusedSegment.currentContext?.findRenderObject();
      if (segment is! RenderBox || !segment.hasSize) return;
      final viewport = RenderAbstractViewport.of(segment);
      final position = _scroll.position;
      final start = viewport.getOffsetToReveal(segment, 0).offset;
      final end = viewport.getOffsetToReveal(segment, 1).offset;
      // Reveal the leading edge of an oversized item; its remaining text stays
      // reachable by scrolling. Otherwise move only enough to show the item.
      final target = segment.size.width > position.viewportDimension ||
              start < position.pixels
          ? start
          : end > position.pixels
              ? end
              : position.pixels;
      final offset =
          target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (offset != position.pixels) _scroll.jumpTo(offset);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    widget.controller._groups[widget.region] = this;
  }

  @override
  void didUpdateWidget(BreadcrumbNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource != widget.resource) {
      if (_opening) {
        final close = widget.controller.cancelPicker;
        WidgetsBinding.instance.addPostFrameCallback((_) => close?.call());
        WidgetsBinding.instance.scheduleFrame();
      }
      _index = null;
      _focus.unfocus();
    } else if (!listEquals(oldWidget.segments, widget.segments)) {
      _index = _index == null || widget.segments.isEmpty
          ? null
          : _index!.clamp(0, widget.segments.length - 1);
      _scheduleReveal();
    }
  }

  void focusLast() {
    if (widget.segments.isEmpty) return;
    setState(() => _index = widget.segments.length - 1);
    _focus.requestFocus();
    _scheduleReveal();
  }

  void move(int delta) {
    if (widget.segments.isEmpty) return;
    setState(() => _index = ((_index ?? widget.segments.length - 1) + delta)
        .clamp(0, widget.segments.length - 1));
    _scheduleReveal();
  }

  Future<void> selectFocused() async {
    final index = _index;
    if (index == null ||
        index < 0 ||
        index >= widget.segments.length ||
        _opening ||
        widget.controller._pickerShowing) {
      return;
    }
    _opening = true;
    final controller = widget.controller;
    final select = widget.onSelect;
    controller._active = this;
    controller.setPickerShowing(true);
    try {
      await select(index);
    } finally {
      _opening = false;
      controller.setPickerShowing(false);
    }
  }

  Future<void> revealFocused() async {
    final index = _index;
    if (index == null ||
        index < 0 ||
        index >= widget.segments.length ||
        _opening ||
        widget.controller._pickerShowing) {
      return;
    }
    if (index == widget.editorSegmentIndex ||
        index == widget.segments.length - 1) {
      clearFocus();
      widget.onSelectEditor();
      return;
    }
    final controller = widget.controller;
    final reveal = widget.onRevealDirectory;
    setState(() => _index = index + 1);
    _scheduleReveal();
    _opening = true;
    controller._active = this;
    controller.setPickerShowing(true);
    try {
      await reveal(index);
    } finally {
      _opening = false;
      controller.setPickerShowing(false);
    }
  }

  void clearFocus() {
    if (!mounted) return;
    setState(() => _index = null);
    _focus.unfocus();
  }

  @override
  void dispose() {
    if (_opening) {
      final close = widget.controller.cancelPicker;
      WidgetsBinding.instance.addPostFrameCallback((_) => close?.call());
      WidgetsBinding.instance.scheduleFrame();
    }
    widget.controller._groups.remove(widget.region);
    if (identical(widget.controller._active, this)) {
      widget.controller._active = null;
    }
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        key: ValueKey('breadcrumbs-focus-${widget.region}'),
        focusNode: _focus,
        onFocusChange: (focused) {
          if (focused) {
            widget.controller._active = this;
            _scheduleReveal();
          }
          widget.controller.focusChanged();
          if (mounted) setState(() {});
        },
        child: LayoutBuilder(builder: (context, constraints) {
          if (_viewportConstraints != constraints) {
            _viewportConstraints = constraints;
            _scheduleReveal();
          }
          return SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.segments.length; i++) ...[
                  if (i > 0)
                    Text(' › ',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 11)),
                  Semantics(
                    key: ValueKey('breadcrumbs-segment-${widget.region}-$i'),
                    selected: _index == i && (_focus.hasFocus || _opening),
                    button: true,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _index = i);
                        _focus.requestFocus();
                        _scheduleReveal();
                        selectFocused();
                      },
                      child: DecoratedBox(
                        key: _index == i ? _focusedSegment : null,
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                            color: _index == i && (_focus.hasFocus || _opening)
                                ? Colors.lightBlue
                                : Colors.transparent,
                          )),
                        ),
                        child: Text(widget.segments[i],
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      );
}
