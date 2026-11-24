import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryButton, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../bridge/alula_core.dart';

typedef DefinitionPeekEntry = ({
  String path,
  DefinitionTarget target,
  String? referenceSymbol,
});
typedef DefinitionPeekLine = ({
  int number,
  int startCharacter,
  String text,
  int highlightStart,
  int highlightEnd,
  int? targetCharacter,
});

typedef _ReferenceRange = ({
  int line,
  int character,
  int endLine,
  int endCharacter,
});

typedef _PeekResultRow = ({String? file, int? entryIndex});

String _referenceFileKey(String path) {
  final normalized = p.normalize(path);
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

_ReferenceRange _referenceRange(DefinitionTarget target) => (
      line: target.line,
      character: target.character,
      endLine: target.endLine ?? target.line,
      endCharacter: target.endCharacter ?? target.character,
    );

List<DefinitionPeekEntry> distinctPeekReferences(
  Iterable<DefinitionPeekEntry> entries,
) {
  final seen = <(String, _ReferenceRange)>{};
  return [
    for (final entry in entries)
      if (seen
          .add((_referenceFileKey(entry.path), _referenceRange(entry.target))))
        entry,
  ];
}

Map<String, List<int>> groupPeekReferences(List<DefinitionPeekEntry> entries) {
  final byFile = <String, List<int>>{};
  for (var i = 0; i < entries.length; i++) {
    final key = _referenceFileKey(entries[i].path);
    byFile.putIfAbsent(key, () => []).add(i);
  }
  final groups = <String, List<int>>{};
  for (final key in byFile.keys.toList()..sort()) {
    final indices = byFile[key]!;
    final path = entries[indices.first].path;
    indices.sort((left, right) => _compareReferenceRanges(
          _referenceRange(entries[left].target),
          _referenceRange(entries[right].target),
        ));
    groups[path] = indices;
  }
  return groups;
}

int _compareReferenceRanges(_ReferenceRange left, _ReferenceRange right) {
  final line = left.line.compareTo(right.line);
  if (line != 0) return line;
  final character = left.character.compareTo(right.character);
  if (character != 0) return character;
  final endLine = left.endLine.compareTo(right.endLine);
  if (endLine != 0) return endLine;
  return left.endCharacter.compareTo(right.endCharacter);
}

const _contextBefore = 3;
const _previewLines = 9;
const _lineWidth = 512;
const maxReferenceSymbolUtf16 = _lineWidth - 2;
const _maxPreviewFileBytes = 4 * 1024 * 1024;

int _firstPreviewLine(DefinitionTarget target) =>
    math.max(0, target.line - _contextBefore);

int _firstPreviewColumn(DefinitionTarget target) =>
    target.character < _lineWidth ? 0 : target.character - _lineWidth ~/ 3;

DefinitionPeekLine _previewLine(
  int number,
  String text,
  int start,
  int end, {
  int startCharacter = 0,
  int? targetCharacter,
}) {
  final low = _scalarBoundary(text, start.clamp(0, text.length));
  final high = _scalarBoundary(text, end.clamp(low, text.length));
  return (
    number: number,
    startCharacter: startCharacter,
    text: text,
    highlightStart: low,
    highlightEnd: high,
    targetCharacter: targetCharacter,
  );
}

DefinitionTarget _referenceTargetWithoutBom(
  DefinitionTarget target,
  String? symbol,
  bool hasBom,
  ({String text, int startUtf16})? Function() read,
) {
  if (!hasBom ||
      symbol == null ||
      symbol.isEmpty ||
      target.line != 0 ||
      target.endLine != 0 ||
      target.character < 1 ||
      target.endCharacter != target.character + symbol.length) {
    return target;
  }

  // Providers can resolve an unopened file against its disk text, where the
  // leading BOM occupies a column. An open editor uses decoded text.
  final excerpt = read();
  if (excerpt == null) return target;
  final previous = target.character - 1 - excerpt.startUtf16;
  if (previous < 0 ||
      previous + symbol.length > excerpt.text.length ||
      !excerpt.text.startsWith(symbol, previous) ||
      excerpt.text.startsWith(symbol, previous + 1)) {
    return target;
  }
  return DefinitionTarget(
    uri: target.uri,
    line: 0,
    character: target.character - 1,
    endLine: 0,
    endCharacter: target.character + symbol.length - 1,
  );
}

DefinitionTarget referenceTargetInDocument(
  AlulaDoc document,
  DefinitionTarget target,
  String? symbol, {
  required bool hasBom,
}) =>
    _referenceTargetWithoutBom(target, symbol, hasBom, () {
      final line = document
          .readLines(
            firstLine: 0,
            maxLines: 1,
            horizontalStartUtf16: target.character - 1,
            maxLineUtf16: _lineWidth,
          )
          .lines
          .firstOrNull;
      if (line == null) return null;
      return (text: line.text, startUtf16: line.startUtf16);
    });

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
  final horizontalStart = _firstPreviewColumn(target);
  final lines = document.readLines(
    firstLine: _firstPreviewLine(target),
    maxLines: _previewLines,
    horizontalStartUtf16: horizontalStart,
    maxLineUtf16: _lineWidth,
  );
  return [
    for (final line in lines.lines)
      _previewLine(
        line.line + 1,
        line.text,
        low.offsetUtf16 - line.startUtf16,
        high.offsetUtf16 - line.startUtf16,
        startCharacter: horizontalStart == 0
            ? 0
            : document.positionAt(line.startUtf16).character,
        targetCharacter: line.line == target.line ? low.character : null,
      ),
  ];
}

/// Run off the UI isolate and retain just the visible excerpt.
List<DefinitionPeekLine> definitionPeekFile(DefinitionPeekEntry entry) {
  final stat = File(entry.path).statSync();
  if (stat.type != FileSystemEntityType.file ||
      stat.size > _maxPreviewFileBytes) {
    return const [];
  }
  final file = AlulaCore.load().workspace.readFileDocument(entry.path);
  final text = file.content;
  final target = _referenceTargetWithoutBom(
    entry.target,
    entry.referenceSymbol,
    file.options.bom,
    () => (text: text, startUtf16: 0),
  );
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
      lines.add(_previewLine(
        line + 1,
        text.substring(from, until),
        start,
        finish,
        startCharacter: column,
        targetCharacter: line == target.line
            ? target.character.clamp(0, end - offset)
            : null,
      ));
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

enum LocationPeekKind {
  definition('定义'),
  references('引用');

  const LocationPeekKind(this.label);

  final String label;
}

enum LocationPeekFocusTarget { results, preview, source }

/// The owning workbench can return focus to either pane after changing files.
class LocationPeekFocus {
  LocationPeekFocus({bool manageWindowInput = false})
      : _manageWindowInput = manageWindowInput &&
            defaultTargetPlatform == TargetPlatform.windows {
    if (_manageWindowInput) {
      results.addListener(_syncWindowsInput);
      preview.addListener(_syncWindowsInput);
    }
  }

  static const _windowsInput = MethodChannel('alula/peek_input');
  final results = FocusNode(debugLabel: 'definition-peek-list');
  final preview = FocusNode(debugLabel: 'definition-peek-preview');
  final bool _manageWindowInput;
  bool _visible = false;
  bool _readOnlyFocused = false;

  void toggle() {
    (preview.hasFocus ? results : preview).requestFocus();
  }

  void setVisible(bool visible) {
    if (!_manageWindowInput || _visible == visible) return;
    _visible = visible;
    _syncWindowsInput();
  }

  void _syncWindowsInput() {
    _setReadOnlyFocus(_visible && (results.hasFocus || preview.hasFocus));
  }

  void _setReadOnlyFocus(bool focused) {
    if (_readOnlyFocused == focused) return;
    _readOnlyFocused = focused;
    unawaited(_sendReadOnlyFocus(focused));
  }

  Future<void> _sendReadOnlyFocus(bool focused) async {
    try {
      await _windowsInput.invokeMethod<void>('setReadOnlyFocus', focused);
    } on MissingPluginException {
      // Some workbench embedders run without the Windows runner.
    }
  }

  void dispose() {
    preview.removeListener(_syncWindowsInput);
    results.removeListener(_syncWindowsInput);
    _setReadOnlyFocus(false);
    preview.dispose();
    results.dispose();
  }
}

class DefinitionPeek extends StatefulWidget {
  const DefinitionPeek({
    super.key,
    required this.entries,
    required this.loadPreview,
    required this.onOpen,
    required this.onClose,
    required this.onRemoved,
    this.onFocusedResultChanged,
    this.onOpenToSide,
    this.onOpenPreview,
    this.onResultKey,
    this.onFocusChange,
    this.kind = LocationPeekKind.definition,
    this.workspace,
    this.referenceGroups,
    this.expandedReferenceFiles,
    this.initialReference = 0,
    this.navigatedReference,
    this.focusController,
    this.focusTarget = LocationPeekFocusTarget.results,
  });

  final List<DefinitionPeekEntry> entries;
  final Future<List<DefinitionPeekLine>> Function(DefinitionPeekEntry)
      loadPreview;
  final ValueChanged<DefinitionPeekEntry> onOpen;
  final ValueChanged<DefinitionPeekEntry>? onOpenToSide;
  final ValueChanged<DefinitionPeekEntry>? onOpenPreview;
  final ValueChanged<DefinitionPeekEntry?>? onFocusedResultChanged;
  final KeyEventResult Function(KeyEvent)? onResultKey;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback onClose;
  final VoidCallback onRemoved;
  final LocationPeekKind kind;
  final String? workspace;
  final Map<String, List<int>>? referenceGroups;
  final Set<String>? expandedReferenceFiles;
  final int initialReference;
  final int? navigatedReference;
  final LocationPeekFocus? focusController;
  final LocationPeekFocusTarget focusTarget;

  @override
  State<DefinitionPeek> createState() => _DefinitionPeekState();
}

class _DefinitionPeekState extends State<DefinitionPeek> {
  static const _rowHeight = 32.0;
  LocationPeekFocus? _localFocus;
  LocationPeekFocus get _focus =>
      widget.focusController ?? (_localFocus ??= LocationPeekFocus());
  FocusNode get _listFocus => _focus.results;
  final _resultsScroll = ScrollController();
  final _previewText = GlobalKey();
  var _selected = 0;
  String? _focusedFile;
  ({int pointer, int entry, Offset position})? _sideClick;
  late final Map<String, List<int>> _fileGroups;
  late final Set<String> _expandedFiles;
  late List<_PeekResultRow> _rows;
  late Future<List<DefinitionPeekLine>> _preview;
  bool _readingPreview = false;
  ({
    DefinitionPeekEntry entry,
    Completer<List<DefinitionPeekLine>> result,
  })? _pendingPreview;

  @override
  void initState() {
    super.initState();
    _fileGroups = widget.referenceGroups ?? groupPeekReferences(widget.entries);
    _expandedFiles = widget.expandedReferenceFiles ?? <String>{};
    _showEntry(widget.navigatedReference ?? widget.initialReference);
  }

  @override
  void didUpdateWidget(DefinitionPeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reference = widget.navigatedReference;
    if (reference != null && reference != oldWidget.navigatedReference) {
      _showEntry(reference);
    }
  }

  void _showEntry(int index) {
    _selected = index;
    _focusedFile = null;
    if (_fileGroups.length > 1) {
      _expandedFiles.add(_fileGroups.entries
          .firstWhere((group) => group.value.contains(index))
          .key);
    }
    _rows = _visibleRows();
    _preview = _requestPreview(widget.entries[index]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusTarget) {
        case LocationPeekFocusTarget.results:
          _listFocus.requestFocus();
        case LocationPeekFocusTarget.preview:
          _focus.preview.requestFocus();
        case LocationPeekFocusTarget.source:
          break;
      }
      _publishFocusedResult();
      _revealRow(_focusedRowIndex);
    });
  }

  @override
  void dispose() {
    _pendingPreview?.result.complete(const []);
    _pendingPreview = null;
    _resultsScroll.dispose();
    _localFocus?.dispose();
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

  List<_PeekResultRow> _visibleRows() {
    if (_fileGroups.length <= 1) {
      final indices = _fileGroups.values.firstOrNull ??
          List.generate(widget.entries.length, (index) => index);
      return [for (final index in indices) (file: null, entryIndex: index)];
    }
    return [
      for (final group in _fileGroups.entries) ...[
        (file: group.key, entryIndex: null),
        if (_expandedFiles.contains(group.key))
          for (final index in group.value) (file: group.key, entryIndex: index),
      ],
    ];
  }

  int get _focusedRowIndex => _rows.indexWhere((row) => _focusedFile == null
      ? row.entryIndex == _selected
      : row.entryIndex == null && row.file == _focusedFile);

  void _select(int next) {
    if (next < 0 || next >= _rows.length || next == _focusedRowIndex) return;
    final row = _rows[next];
    final entryIndex = row.entryIndex;
    setState(() {
      _focusedFile = entryIndex == null ? row.file : null;
      if (entryIndex != null && entryIndex != _selected) {
        _selected = entryIndex;
        _preview = _requestPreview(widget.entries[entryIndex]);
      }
    });
    _publishFocusedResult();
    _revealRow(next);
  }

  void _toggleFile(String file) {
    setState(() {
      _focusedFile = file;
      if (!_expandedFiles.remove(file)) _expandedFiles.add(file);
      _rows = _visibleRows();
    });
    _publishFocusedResult();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealRow(_focusedRowIndex);
    });
  }

  void _revealRow(int row) {
    if (row < 0 || !_resultsScroll.hasClients) return;
    final position = _resultsScroll.position;
    final top = row * _rowHeight;
    final bottom = top + _rowHeight;
    final offset = top < position.pixels
        ? top
        : math.max(position.pixels, bottom - position.viewportDimension);
    _resultsScroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
  }

  void _publishFocusedResult() {
    final index = _focusedRowIndex;
    final entryIndex =
        _listFocus.hasFocus && index >= 0 ? _rows[index].entryIndex : null;
    widget.onFocusedResultChanged?.call(
      entryIndex == null ? null : widget.entries[entryIndex],
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (!_listFocus.hasFocus) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      final handled = widget.onResultKey?.call(event) ?? KeyEventResult.ignored;
      if (handled != KeyEventResult.ignored) return handled;
    }
    final index = _focusedRowIndex;
    if (index < 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      _select((index + delta).clamp(0, _rows.length - 1));
      return KeyEventResult.handled;
    }
    final row = _rows[index];
    final entryIndex = row.entryIndex;
    final file = row.file;
    final keyboard = HardwareKeyboard.instance;
    final modified = keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed;
    if (key == LogicalKeyboardKey.enter) {
      if (event is KeyRepeatEvent || modified) return KeyEventResult.handled;
      if (entryIndex != null) {
        widget.onOpen(widget.entries[entryIndex]);
      } else if (file != null) {
        _toggleFile(file);
      }
      return KeyEventResult.handled;
    }
    if (file == null || modified) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (entryIndex != null) {
        _select(_rows
            .indexWhere((row) => row.file == file && row.entryIndex == null));
      } else if (_expandedFiles.contains(file)) {
        _toggleFile(file);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && entryIndex == null) {
      if (_expandedFiles.contains(file)) {
        _select(index + 1);
      } else {
        _toggleFile(file);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: _handleKey,
      onFocusChange: widget.onFocusChange,
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
                    Expanded(
                        child: Text(
                            '${widget.kind.label} (${widget.entries.length})')),
                    IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: '关闭${widget.kind.label}预览',
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
                    Expanded(flex: 2, child: _buildResults(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (widget.kind == LocationPeekKind.definition) return _resultList(context);
    return FutureBuilder<List<DefinitionPeekLine>>(
      future: _preview,
      builder: (context, snapshot) {
        final column = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
                ?.where((line) => line.targetCharacter != null)
                .firstOrNull
                ?.targetCharacter
            : null;
        return _resultList(context, previewCharacter: column);
      },
    );
  }

  void _recordResultPress(PointerDownEvent event, int entry) {
    final keyboard = HardwareKeyboard.instance;
    final modified = keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
    _sideClick = event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryButton &&
            modified &&
            widget.onOpenToSide != null
        ? (pointer: event.pointer, entry: entry, position: event.position)
        : null;
  }

  void _cancelMovedResultPress(PointerMoveEvent event) {
    final pressed = _sideClick;
    if (pressed != null &&
        pressed.pointer == event.pointer &&
        (event.position - pressed.position).distance > kTouchSlop) {
      _sideClick = null;
    }
  }

  void _activateResult(int entryIndex, {required bool confirm}) {
    final openToSide = widget.onOpenToSide;
    final side = _sideClick?.entry == entryIndex && openToSide != null;
    _sideClick = null;
    final rowIndex = _rows.indexWhere((row) => row.entryIndex == entryIndex);
    if (rowIndex < 0) return;
    final entry = widget.entries[entryIndex];
    if (side) {
      _select(rowIndex);
      openToSide(entry);
    } else if (confirm) {
      widget.onOpen(entry);
    } else {
      _listFocus.requestFocus();
      _select(rowIndex);
    }
  }

  Widget _resultList(BuildContext context, {int? previewCharacter}) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _listFocus,
      onFocusChange: (_) => _publishFocusedResult(),
      child: ListView.builder(
        controller: _resultsScroll,
        itemExtent: _rowHeight,
        itemCount: _rows.length,
        itemBuilder: (context, index) {
          final row = _rows[index];
          final entryIndex = row.entryIndex;
          if (entryIndex == null) return _buildFileRow(row.file!, colors);
          final entry = widget.entries[entryIndex];
          final target = entry.target;
          final selected = _focusedFile == null && entryIndex == _selected;
          final character = entryIndex == _selected
              ? previewCharacter ?? target.character
              : target.character;
          final position = '${target.line + 1}:${character + 1}';
          return Semantics(
            key: ValueKey('peek-result:$entryIndex'),
            selected: selected,
            label: '${entry.path}:${target.line + 1}',
            child: Listener(
              onPointerDown: (event) => _recordResultPress(event, entryIndex),
              onPointerMove: _cancelMovedResultPress,
              onPointerCancel: (event) {
                if (_sideClick?.pointer == event.pointer) _sideClick = null;
              },
              child: InkWell(
                canRequestFocus: false,
                onTap: () => _activateResult(entryIndex, confirm: false),
                onDoubleTap: () => _activateResult(entryIndex, confirm: true),
                child: ColoredBox(
                  color:
                      selected ? colors.primaryContainer : Colors.transparent,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: row.file == null ? 8 : 28,
                      right: 8,
                    ),
                    child: Row(
                      children: [
                        if (row.file == null)
                          Expanded(
                            child: Text(
                              p.basename(entry.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        Text(position),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileRow(String path, ColorScheme colors) {
    final expanded = _expandedFiles.contains(path);
    final selected = path == _focusedFile;
    final count = _fileGroups[path]!.length;
    final directory = p.dirname(path);
    final workspace = widget.workspace;
    final parent =
        workspace == null ? directory : p.relative(directory, from: workspace);
    return Semantics(
      key: ValueKey('references-file:$path'),
      label: '$path，$count 个${widget.kind.label}',
      expanded: expanded,
      selected: selected,
      child: InkWell(
        canRequestFocus: false,
        onTap: () {
          _listFocus.requestFocus();
          _toggleFile(path);
        },
        child: ExcludeSemantics(
          child: ColoredBox(
            color: selected ? colors.primaryContainer : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      parent == '.'
                          ? p.basename(path)
                          : '${p.basename(path)}  $parent',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('$count'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _previewLinePrefix(int line) => '${line.toString().padLeft(4)}  ';

  void _openPreviewAt(Offset globalPosition, List<DefinitionPeekLine> lines) {
    var paragraph = _previewText.currentContext?.findRenderObject();
    while (paragraph is RenderProxyBox) {
      paragraph = paragraph.child;
    }
    if (paragraph is! RenderParagraph || !paragraph.hasSize) return;
    final point = paragraph.globalToLocal(globalPosition);
    if (!paragraph.size.contains(point)) return;
    var offset = paragraph.getPositionForOffset(point).offset;
    for (final line in lines) {
      final prefixLength = _previewLinePrefix(line.number).length;
      final end = prefixLength + line.text.length;
      if (offset > end) {
        offset -= end + 1;
        continue;
      }
      if (offset < prefixLength || line.text.isEmpty) return;
      final selected = widget.entries[_selected];
      final keyboard = HardwareKeyboard.instance;
      final open = keyboard.isControlPressed ||
              keyboard.isMetaPressed ||
              keyboard.isAltPressed
          ? widget.onOpenToSide
          : widget.onOpenPreview;
      if (open == null) return;
      final entry = (
        path: selected.path,
        target: DefinitionTarget(
          uri: selected.target.uri,
          line: line.number - 1,
          character: line.startCharacter + offset - prefixLength,
        ),
        referenceSymbol: null,
      );
      final preview = _preview;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_preview, preview)) open(entry);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
  }

  Widget _buildPreview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = FutureBuilder<List<DefinitionPeekLine>>(
      key: const ValueKey('definition-peek-preview'),
      future: _preview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: Text('正在读取${widget.kind.label}…'));
        }
        final lines = snapshot.data;
        if (lines == null || lines.isEmpty) {
          return Center(child: Text('无法预览${widget.kind.label}'));
        }
        final text = Text.rich(
          TextSpan(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            children: [
              for (final line in lines) ...[
                TextSpan(
                  text: _previewLinePrefix(line.number),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                TextSpan(text: line.text.substring(0, line.highlightStart)),
                TextSpan(
                  text: line.text
                      .substring(line.highlightStart, line.highlightEnd),
                  style: TextStyle(backgroundColor: colors.tertiaryContainer),
                ),
                TextSpan(text: '${line.text.substring(line.highlightEnd)}\n'),
              ],
            ],
          ),
          key: _previewText,
        );
        return SingleChildScrollView(
          key: ValueKey(_selected),
          padding: const EdgeInsets.all(8),
          child: widget.onOpenPreview == null
              ? text
              : GestureDetector(
                  supportedDevices: const {PointerDeviceKind.mouse},
                  // SelectionArea still handles text selection.
                  onDoubleTapDown: (details) =>
                      _openPreviewAt(details.globalPosition, lines),
                  child: text,
                ),
        );
      },
    );
    return ListenableBuilder(
      listenable: _focus.preview,
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color:
                _focus.preview.hasFocus ? colors.primary : Colors.transparent,
          ),
        ),
        child: child,
      ),
      child: SelectionArea(
        key: const ValueKey('definition-peek-preview-focus'),
        focusNode: _focus.preview,
        child: content,
      ),
    );
  }
}
