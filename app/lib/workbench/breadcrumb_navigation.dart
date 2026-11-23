import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl4x/collation.dart';

final _breadcrumbPathNameCollation = Collation(
  numeric: true,
  sensitivity: Sensitivity.base,
);

/// Compares file and directory names with the fixed picker’s UTF-16 tie-break.
int compareBreadcrumbFileNames(String first, String second) {
  final result = _breadcrumbPathNameCollation.compare(first, second);
  return result == 0 ? first.compareTo(second) : result;
}

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

  Rect? focusedSegmentBounds(String region) =>
      _groups[region]?._focusedSegmentBounds();

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

class BreadcrumbSymbolMenuItem extends PopupMenuItem<String> {
  BreadcrumbSymbolMenuItem({
    super.key,
    required String value,
    required Widget child,
    required this.children,
    required String initialValue,
  })  : focusedOnOpen = value == initialValue,
        expandedOnOpen = children.any(
          (child) => child.focusedOnOpen || child.expandedOnOpen,
        ),
        super(value: value, child: child);

  final List<BreadcrumbSymbolMenuItem> children;
  final bool focusedOnOpen;
  final bool expandedOnOpen;
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
    this.loadFolder,
    this.focusParent,
    this.onItemFocus,
    this.expandedSymbols,
    this.depth = 0,
  });

  final PopupMenuItem<String> item;
  final bool first;
  final VoidCallback onEscape;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final ValueChanged<ModalRoute<dynamic>?> onRoute;
  final ValueChanged<String> onRevealAside;
  final List<PopupMenuItem<String>> Function(String path)? loadFolder;
  final VoidCallback? focusParent;
  final ValueChanged<String>? onItemFocus;
  final Set<String>? expandedSymbols;
  final int depth;

  @override
  double get height => item.height;

  @override
  bool represents(String? value) => item.represents(value);

  @override
  State<BreadcrumbMenuEntry> createState() => _BreadcrumbMenuEntryState();
}

class _BreadcrumbMenuEntryState extends State<BreadcrumbMenuEntry> {
  final _rowFocus = FocusNode();
  List<PopupMenuItem<String>>? _children;
  bool _initialFocusRevealed = false;

  BreadcrumbSymbolMenuItem? get _symbol =>
      widget.item is BreadcrumbSymbolMenuItem
          ? widget.item as BreadcrumbSymbolMenuItem
          : null;

  bool get _hasChildren =>
      _directory || (_symbol?.children.isNotEmpty ?? false);

  bool get _directory =>
      widget.loadFolder != null &&
      (widget.item.value?.startsWith('reveal:') ?? false);

  @override
  void initState() {
    super.initState();
    final symbol = _symbol;
    if (symbol != null &&
        (widget.expandedSymbols?.contains(symbol.value) ?? false)) {
      _children = symbol.children;
    }
  }

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  void _expand() {
    final children = _symbol?.children ??
        widget.loadFolder!(widget.item.value!.substring('reveal:'.length));
    if (_symbol != null) widget.expandedSymbols?.add(widget.item.value!);
    setState(() => _children = children);
  }

  void _collapse() {
    if (_symbol != null) widget.expandedSymbols?.remove(widget.item.value);
    setState(() => _children = null);
  }

  void _toggle() {
    _rowFocus.requestFocus();
    if (_children == null) {
      _expand();
    } else {
      _collapse();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      widget.onEscape();
      return KeyEventResult.handled;
    }
    final pickerResult = widget.onKeyEvent(event);
    if (pickerResult != KeyEventResult.ignored) return pickerResult;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (widget.loadFolder != null || _symbol != null) {
      final plain = !keyboard.isControlPressed &&
          !keyboard.isMetaPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isShiftPressed;
      if (plain && key == LogicalKeyboardKey.arrowLeft) {
        if (_children != null) {
          _collapse();
        } else {
          widget.focusParent?.call();
        }
        return KeyEventResult.handled;
      }
      if (plain && key == LogicalKeyboardKey.arrowRight) {
        if (_hasChildren && _children == null) {
          _expand();
        } else if (_children?.isNotEmpty ?? false) {
          FocusScope.of(context).nextFocus();
        }
        return KeyEventResult.handled;
      }
      if (_hasChildren && key == LogicalKeyboardKey.space) {
        if (plain && event is KeyDownEvent) _toggle();
        return KeyEventResult.handled;
      }
      if (_directory && key == LogicalKeyboardKey.enter) {
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.enter &&
        widget.item.enabled &&
        widget.item.value != null) {
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
  }

  @override
  Widget build(BuildContext context) {
    widget.onRoute(ModalRoute.of(context));
    Widget label = widget.item.child!;
    final symbol = _symbol;
    if ((widget.loadFolder != null || symbol != null) && widget.item.enabled) {
      Widget disclosure = const SizedBox(width: 18);
      if (_hasChildren) {
        disclosure = Icon(
          _children == null ? Icons.chevron_right : Icons.expand_more,
          size: 18,
        );
        if (symbol != null) {
          disclosure = InkResponse(
            canRequestFocus: false,
            radius: 12,
            onTap: _toggle,
            child: disclosure,
          );
        }
      }
      final indent = symbol == null ? widget.depth : widget.depth.clamp(0, 8);
      label = Padding(
        padding: EdgeInsets.only(left: indent * 12.0),
        child: Row(children: [disclosure, Expanded(child: label)]),
      );
      if (symbol != null && _hasChildren) {
        label = Semantics(expanded: _children != null, child: label);
      }
    }
    final content = Focus(
      focusNode: _rowFocus,
      autofocus: widget.first,
      skipTraversal: true,
      child: label,
    );
    final row = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      onFocusChange: widget.onItemFocus == null
          ? null
          : (focused) {
              final value = widget.item.value;
              if (focused && widget.item.enabled && value != null) {
                widget.onItemFocus!(value);
                if (widget.first && widget.depth > 0 && !_initialFocusRevealed) {
                  _initialFocusRevealed = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final rowContext = _rowFocus.context;
                    if (mounted && _rowFocus.hasFocus && rowContext != null) {
                      Scrollable.ensureVisible(rowContext, alignment: 0.5);
                    }
                  });
                  WidgetsBinding.instance.scheduleFrame();
                }
              }
            },
      child: _directory
          ? _BreadcrumbDirectoryMenuItem(
              value: widget.item.value,
              expanded: _children != null,
              onToggle: _toggle,
              child: content,
            )
          : PopupMenuItem<String>(
              value: widget.item.value,
              enabled: widget.item.enabled,
              child: content,
            ),
    );
    if (!_hasChildren) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final item in _children ?? const <PopupMenuItem<String>>[])
          BreadcrumbMenuEntry(
            key: ValueKey(item.value),
            item: item,
            onEscape: widget.onEscape,
            onKeyEvent: widget.onKeyEvent,
            onRoute: widget.onRoute,
            onRevealAside: widget.onRevealAside,
            first: item is BreadcrumbSymbolMenuItem && item.focusedOnOpen,
            loadFolder: widget.loadFolder,
            focusParent: _rowFocus.requestFocus,
            onItemFocus: widget.onItemFocus,
            expandedSymbols: widget.expandedSymbols,
            depth: widget.depth + 1,
          ),
      ],
    );
  }
}

class _BreadcrumbDirectoryMenuItem extends PopupMenuItem<String> {
  _BreadcrumbDirectoryMenuItem({
    required super.value,
    required Widget child,
    required bool expanded,
    required this.onToggle,
  }) : super(child: Semantics(expanded: expanded, child: child));

  final VoidCallback onToggle;

  @override
  PopupMenuItemState<String, _BreadcrumbDirectoryMenuItem> createState() =>
      _BreadcrumbDirectoryMenuItemState();
}

class _BreadcrumbDirectoryMenuItemState
    extends PopupMenuItemState<String, _BreadcrumbDirectoryMenuItem> {
  @override
  void handleTap() => widget.onToggle();
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
  final _segmentKeys = <GlobalKey>[];
  BoxConstraints? _viewportConstraints;
  int? _index;
  bool _opening = false;
  bool _replacePicker = false;
  bool _revealPending = false;

  RenderBox? get _focusedSegmentBox {
    final index = _index;
    if (index == null || index >= _segmentKeys.length) return null;
    final object = _segmentKeys[index].currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  double _revealOffset(RenderBox segment) {
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
    return target.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  Rect? _focusedSegmentBounds() {
    if (!mounted || !_scroll.hasClients) return null;
    final segment = _focusedSegmentBox;
    if (segment == null) return null;
    final RenderObject viewport = RenderAbstractViewport.of(segment);
    if (viewport is! RenderBox || !viewport.hasSize) return null;

    // Menu opening and focus are synchronous. Project the same scroll
    // adjustment that the reveal callback will apply after the frame.
    final position = _scroll.position;
    final delta = position.pixels - _revealOffset(segment);
    final horizontal = position.axisDirection == AxisDirection.left
        ? -delta
        : delta;
    final segmentBounds = MatrixUtils.transformRect(
      segment.getTransformTo(null),
      Offset(horizontal, 0) & segment.size,
    );
    final viewportBounds = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      Offset.zero & viewport.size,
    );
    final visibleBounds = segmentBounds.intersect(viewportBounds);
    return visibleBounds.isFinite && !visibleBounds.isEmpty
        ? visibleBounds
        : null;
  }

  void _scheduleReveal() {
    if (_revealPending || _index == null) return;
    _revealPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealPending = false;
      if (!mounted || (!_focus.hasFocus && !_opening) || !_scroll.hasClients) {
        return;
      }
      final segment = _focusedSegmentBox;
      if (segment == null) return;
      final offset = _revealOffset(segment);
      if (offset != _scroll.position.pixels) _scroll.jumpTo(offset);
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
      _replacePicker = false;
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
    final previous = _index;
    final next = ((previous ?? widget.segments.length - 1) + delta)
        .clamp(0, widget.segments.length - 1);
    setState(() => _index = next);
    _scheduleReveal();
    final cancelPicker = widget.controller.cancelPicker;
    if (_opening && next != previous && cancelPicker != null) {
      _replacePicker = true;
      cancelPicker();
    }
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
    await _openPicker(index, widget.onSelect);
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
    setState(() => _index = index + 1);
    _scheduleReveal();
    await _openPicker(index, widget.onRevealDirectory);
  }

  Future<void> _openPicker(
    int index,
    Future<void> Function(int index) open,
  ) async {
    _opening = true;
    final controller = widget.controller;
    final resource = widget.resource;
    controller._active = this;
    controller.setPickerShowing(true);
    try {
      await open(index);
      // Let the previous route clear its callbacks and focus context before
      // opening the picker for the newly focused segment.
      while (mounted && _replacePicker && widget.resource == resource) {
        _replacePicker = false;
        final next = _index;
        if (next == null || next >= widget.segments.length) break;
        await widget.onSelect(next);
      }
    } finally {
      _replacePicker = false;
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
          final length = widget.segments.length;
          if (_segmentKeys.length > length) {
            _segmentKeys.removeRange(length, _segmentKeys.length);
          }
          while (_segmentKeys.length < length) {
            _segmentKeys.add(GlobalKey());
          }
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
                        key: _segmentKeys[i],
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
