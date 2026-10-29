import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const EditorImeProbeApp());

class EditorImeProbeApp extends StatelessWidget {
  const EditorImeProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Alula P00.4 editor probe',
    theme: ThemeData.dark(useMaterial3: true),
    home: const EditorImeProbePage(),
  );
}

class EditorImeProbePage extends StatefulWidget {
  const EditorImeProbePage({super.key});

  @override
  State<EditorImeProbePage> createState() => _EditorImeProbePageState();
}

class _EditorImeProbePageState extends State<EditorImeProbePage> {
  static const _sampleLineCount = 10000;
  static const _estimatedLineHeight = 22.0;

  final _controller = CodeForgeController();
  final _focusNode = FocusNode(debugLabel: 'P00.4 editor probe');
  final _verticalScrollController = ScrollController();
  final _elapsed = Stopwatch()..start();
  Timer? _metricsTimer;

  int _controllerNotifications = 0;
  int _frameCount = 0;
  int _slowFrames = 0;
  int _maxFrameMicros = 0;
  int _maxKeyToEditMicros = 0;
  int? _lastKeyDownMicros;
  String _lastEvent = 'ready';

  @override
  void initState() {
    super.initState();
    _controller.text = _makeDocument(_sampleLineCount);
    _controller.addListener(_onControllerChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _metricsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _verticalScrollController.dispose();
    _focusNode.dispose();
    _elapsed.stop();
    super.dispose();
  }

  static String _makeDocument(int lineCount) => List<String>.generate(
    lineCount,
    (index) {
      final padded = index.toString().padLeft(5, '0');
      return 'line $padded  int value$index = calculate($index); '
          '// incremental input and viewport probe';
    },
  ).join('\n');

  void _onControllerChanged() {
    _controllerNotifications++;
    final now = _elapsed.elapsedMicroseconds;
    final keyDown = _lastKeyDownMicros;
    if (keyDown != null && now - keyDown < 2000000) {
      final latency = now - keyDown;
      if (latency > _maxKeyToEditMicros) _maxKeyToEditMicros = latency;
      _lastKeyDownMicros = null;
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _lastKeyDownMicros = _elapsed.elapsedMicroseconds;
      final keyLabel = event.logicalKey.keyLabel;
      _lastEvent = 'key $keyLabel';
    }
    return false;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final micros = timing.totalSpan.inMicroseconds;
      _frameCount++;
      if (micros > 16000) _slowFrames++;
      if (micros > _maxFrameMicros) _maxFrameMicros = micros;
    }
  }

  void _resetDocument() {
    _controller.clearMultiCursors();
    _controller.text = _makeDocument(_sampleLineCount);
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _focusNode.requestFocus();
    _lastEvent = 'reset $_sampleLineCount lines';
    setState(() {});
  }

  void _addThreeCursors() {
    _controller.clearMultiCursors();
    _controller.addMultiCursor(1, 5);
    _controller.addMultiCursor(3, 5);
    _controller.addMultiCursor(5, 5);
    _focusNode.requestFocus();
    _lastEvent = 'seeded 3 secondary cursors';
    setState(() {});
  }

  void _scrollToMiddle() {
    if (!_verticalScrollController.hasClients) return;
    final position = _verticalScrollController.position;
    _verticalScrollController.jumpTo(position.maxScrollExtent / 2);
    _lastEvent = 'scroll to middle';
    setState(() {});
  }

  Map<String, Object?> _snapshot() {
    final composition = _controller.imeComposition;
    final scroll = _verticalScrollController.hasClients
        ? _verticalScrollController.position
        : null;
    return {
      'probe': 'P00.4-editor-ime',
      'os': Platform.operatingSystem,
      'elapsedMs': _elapsed.elapsedMilliseconds,
      'lineCount': _controller.lineCount,
      'textLength': _controller.length,
      'controllerNotifications': _controllerNotifications,
      'imeCompositionActive': _controller.isComposingActive,
      'imeComposition': composition == null
          ? null
          : {
              'anchor': composition.anchor,
              'displayText': composition.displayText,
              'displayCaret': composition.displayCaret,
              'commitText': composition.commitText,
            },
      'selection': {
        'base': _controller.selection.baseOffset,
        'extent': _controller.selection.extentOffset,
      },
      'secondaryCursorCount': _controller.multiCursors.length,
      'secondaryCursors': _controller.multiCursors
          .map((cursor) => {'line': cursor.line, 'character': cursor.character})
          .toList(),
      'scrollPixels': scroll?.pixels,
      'maxScrollPixels': scroll?.maxScrollExtent,
      'estimatedFirstVisibleLine': scroll == null
          ? null
          : (scroll.pixels / _estimatedLineHeight).floor(),
      'frameCount': _frameCount,
      'framesOver16ms': _slowFrames,
      'maxFrameMs': _maxFrameMicros / 1000,
      'maxKeyToEditMs': _maxKeyToEditMicros / 1000,
      'lastEvent': _lastEvent,
    };
  }

  void _captureSnapshot() {
    debugPrint('P00.4_EDITOR ' + jsonEncode(_snapshot()));
    _lastEvent = 'snapshot written to app log';
    setState(() {});
  }

  String _imeStatus(ImeComposition? composition) {
    if (composition == null) return 'idle';
    return 'active display=' +
        jsonEncode(composition.displayText) +
        ' commit=' +
        jsonEncode(composition.commitText) +
        ' caret=' +
        composition.displayCaret.toString();
  }

  @override
  Widget build(BuildContext context) {
    final composition = _controller.imeComposition;
    final scroll = _verticalScrollController.hasClients
        ? _verticalScrollController.position
        : null;
    final estimatedLine = scroll == null
        ? 0
        : (scroll.pixels / _estimatedLineHeight).floor();
    final lineCount = _controller.lineCount;
    final cursorCount = _controller.multiCursors.length;
    final charCount = _controller.length;
    final frameMs = (_maxFrameMicros / 1000).toStringAsFixed(1);
    final keyEditMs = (_maxKeyToEditMicros / 1000).toStringAsFixed(1);
    final imeText = _imeStatus(composition);

    return Scaffold(
      appBar: AppBar(
        title: const Text('P00.4 editor / IME / viewport probe'),
        actions: [
          IconButton(
            tooltip: 'Print JSON snapshot to app log',
            onPressed: _captureSnapshot,
            icon: const Icon(Icons.assessment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    onPressed: _resetDocument,
                    child: const Text('Reset 10k lines'),
                  ),
                  FilledButton.tonal(
                    onPressed: _addThreeCursors,
                    child: const Text('Seed 3 cursors'),
                  ),
                  FilledButton.tonal(
                    onPressed: _controller.clearMultiCursors,
                    child: const Text('Clear cursors'),
                  ),
                  FilledButton.tonal(
                    onPressed: _scrollToMiddle,
                    child: const Text('Scroll middle'),
                  ),
                  FilledButton(
                    onPressed: _captureSnapshot,
                    child: const Text('Capture metrics'),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodySmall!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Click the editor. Type ordinary text, then use Microsoft '
                    'Pinyin: type nihao, Enter to commit, Esc to cancel.',
                  ),
                  const Text(
                    'Seed cursors, type one character, then Ctrl+Z to inspect '
                    'multi-cursor edits and undo grouping.',
                  ),
                  Text(
                    'IME: $imeText   Cursors: $cursorCount   '
                    'Lines: $lineCount   Chars: $charCount',
                  ),
                  Text(
                    'Viewport: ~line $estimatedLine / $lineCount   '
                    'Frames: $_frameCount ($_slowFrames >16ms, '
                    'max $frameMs ms)   Key→edit max: $keyEditMs ms   '
                    'Last: $_lastEvent',
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: CodeForge(
              controller: _controller,
              focusNode: _focusNode,
              verticalScrollController: _verticalScrollController,
              lineWrap: false,
              enableFolding: false,
              textStyle: const TextStyle(fontSize: 14, height: 1.45),
              innerPadding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }
}
