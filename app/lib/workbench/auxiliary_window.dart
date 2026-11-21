/// 浮动辅助窗口（LAY-12a）。
///
/// desktop_multi_window 为新窗口再跑一次 main()：入口按
/// `WindowController.fromCurrentEngine()` 的载荷分流到本文件的精简编辑器。
/// Alula 的 Rust FFI core 为每进程一份，辅助窗口按 path 从磁盘重开文档；
/// 未命名/脏文本经启动载荷传递（savepoint/撤销历史不跨进程，差异已登记）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsRole;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge/alula_core.dart';
import '../editor/rust_text_input_field.dart';
import '../editor/rust_text_input_window.dart';
import 'auxiliary_focus_context.dart';
import 'auxiliary_window_transfer.dart';
import 'editor_tab_close_action.dart';
import 'editor_tab_file_icon.dart';

/// 辅助窗口启动载荷。businessId 标记区分辅助引擎与主引擎。
class AuxiliaryWindowPayload {
  const AuxiliaryWindowPayload({
    required this.isAuxiliary,
    this.path,
    this.mainWindowId,
    this.documentId,
    this.name = '未命名',
    this.text = '',
    this.dirty = false,
  });

  static const businessId = 'alula-auxiliary-editor';

  final bool isAuxiliary;
  final String? path;
  final String? mainWindowId;

  /// Reserved by the main workbench for a new document in the shared core.
  final int? documentId;
  final String name;
  final String text;
  final bool dirty;

  factory AuxiliaryWindowPayload.mainWindow() =>
      const AuxiliaryWindowPayload(isAuxiliary: false);

  factory AuxiliaryWindowPayload.forDocument({
    String? path,
    String? mainWindowId,
    int? documentId,
    required String name,
    required String text,
    required bool dirty,
  }) {
    return AuxiliaryWindowPayload(
      isAuxiliary: true,
      path: path,
      mainWindowId: mainWindowId,
      documentId: documentId,
      name: name,
      text: text,
      dirty: dirty,
    );
  }

  factory AuxiliaryWindowPayload.fromArguments(String arguments) {
    if (arguments.isEmpty) {
      return AuxiliaryWindowPayload.mainWindow();
    }
    try {
      final map = jsonDecode(arguments) as Map<dynamic, dynamic>;
      if (map['businessId'] != businessId) {
        return AuxiliaryWindowPayload.mainWindow();
      }
      final pathValue = map['path'] as String?;
      final mainWindowIdValue = map['mainWindowId'] as String?;
      final documentId = map['documentId'];
      return AuxiliaryWindowPayload(
        isAuxiliary: true,
        path: pathValue == null || pathValue.isEmpty ? null : pathValue,
        mainWindowId: mainWindowIdValue == null || mainWindowIdValue.isEmpty
            ? null
            : mainWindowIdValue,
        documentId: documentId is int && documentId > 0 ? documentId : null,
        name: map['name'] as String? ?? '未命名',
        text: map['text'] as String? ?? '',
        dirty: map['dirty'] == true,
      );
    } on Object {
      return AuxiliaryWindowPayload.mainWindow();
    }
  }

  Map<String, Object?> toMap() => {
        'businessId': businessId,
        'path': path ?? '',
        'mainWindowId': mainWindowId ?? '',
        if (documentId != null) 'documentId': documentId,
        'name': name,
        'text': text,
        'dirty': dirty,
      };

  String toArguments() => jsonEncode(toMap());
}

/// 辅助窗口引擎入口：按载荷渲染精简编辑器页。
Future<void> runAlulaAuxiliaryEngine(String arguments) async {
  final payload = AuxiliaryWindowPayload.fromArguments(arguments);
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    title: payload.name,
    minimumSize: const Size(420, 320),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(AuxiliaryEditorApp(payload: payload));
}

/// 精简辅助编辑器页：单个 Rust 文档视图 + 标题行（名称/脏标/关闭）。
class AuxiliaryEditorApp extends StatefulWidget {
  const AuxiliaryEditorApp({super.key, required this.payload});

  final AuxiliaryWindowPayload payload;

  @override
  State<AuxiliaryEditorApp> createState() => _AuxiliaryEditorAppState();
}

class _PreparedAuxiliaryDocumentTransfer {
  const _PreparedAuxiliaryDocumentTransfer({
    required this.requestId,
    required this.payload,
    required this.document,
    required this.inputWindow,
    required this.previousDocument,
  });

  final String requestId;
  final AuxiliaryWindowPayload payload;
  final AlulaDoc document;
  final RustTextInputWindow inputWindow;
  final Map<String, Object?> previousDocument;
}

class _AuxiliaryEditorAppState extends State<AuxiliaryEditorApp>
    with WindowListener {
  AlulaDoc? _doc;
  RustTextInputWindow? _inputWindow;
  String? _path;
  String _name = '未命名';
  bool _dirty = false;
  bool _closing = false;
  bool? _alwaysOnTop;
  bool _changingAlwaysOnTop = false;
  bool _compactMode = false;
  String? _windowStateError;
  late final ScrollController _scrollController;
  final FocusNode _editorFocus = FocusNode(debugLabel: 'auxiliary editor');
  WindowController? _windowController;
  WindowController? _mainWindowController;
  Future<void> _focusEventQueue = Future<void>.value();
  int _focusEventSequence = 0;
  int _nativeFocusGeneration = 0;
  int _latestGlobalFocusRevision = -1;
  int _boundsReportSequence = 0;
  bool? _nativeWindowFocused;
  bool _focusContextConnected = false;
  bool _boundsReportRunning = false;
  bool _boundsReportRequested = false;
  String? _lastCommittedTransferId;
  _PreparedAuxiliaryDocumentTransfer? _pendingTransfer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    windowManager.addListener(this);
    unawaited(_preventNativeClose());
    unawaited(_connectFocusContext());
    _loadAlwaysOnTop();
    _openDocument();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _releaseDocuments();
    final windowController = _windowController;
    if (windowController != null) {
      unawaited(windowController
          .setWindowMethodHandler(null)
          .catchError((Object _) {}));
    }
    _scrollController.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _preventNativeClose() async {
    try {
      await windowManager.setPreventClose(true);
    } on Object {
      // The widget can be mounted without a native desktop window.
    }
  }

  String _focusGroupIdentity(String windowId) => '$windowId:editor';

  void _acceptGlobalFocusSnapshot(Object? value) {
    final snapshot = AuxiliaryFocusContextSnapshot.tryParse(value);
    if (snapshot == null || snapshot.revision <= _latestGlobalFocusRevision) {
      return;
    }
    _latestGlobalFocusRevision = snapshot.revision;
  }

  Future<void> _connectFocusContext() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      if (!mounted) return;
      _windowController = controller;
      await controller.setWindowMethodHandler((call) async {
        if (call.method == auxiliaryFocusContextMethod) {
          _acceptGlobalFocusSnapshot(call.arguments);
          return null;
        }
        return _handleDocumentTransferMethod(call.method, call.arguments);
      });

      WindowController? mainController;
      final mainWindowId = widget.payload.mainWindowId;
      if (mainWindowId != null && mainWindowId != controller.windowId) {
        mainController = WindowController.fromWindowId(mainWindowId);
      } else {
        final controllers = await WindowController.getAll();
        for (final candidate in controllers) {
          if (candidate.windowId == controller.windowId) continue;
          if (!AuxiliaryWindowPayload.fromArguments(candidate.arguments)
              .isAuxiliary) {
            mainController = candidate;
            break;
          }
        }
      }
      if (!mounted || mainController == null) return;
      _mainWindowController = mainController;
      final registration = AuxiliaryFocusContextEvent(
        kind: AuxiliaryFocusEventKind.register,
        windowId: controller.windowId,
        sequence: ++_focusEventSequence,
        groupId: _focusGroupIdentity(controller.windowId),
        focused: false,
      );
      final initialSnapshot = await mainController.invokeMethod<Object?>(
        auxiliaryFocusContextMethod,
        registration.toMap(),
      );
      _acceptGlobalFocusSnapshot(initialSnapshot);
      if (!mounted) return;
      _focusContextConnected = true;
      _requestBoundsReport();
      final observedFocus = _nativeWindowFocused;
      if (observedFocus != null) {
        _publishAuxiliaryFocusContext(focused: observedFocus);
      }

      final focusGeneration = _nativeFocusGeneration;
      try {
        final focused = await windowManager.isFocused();
        if (mounted && focusGeneration == _nativeFocusGeneration) {
          _nativeWindowFocused = focused;
          _publishAuxiliaryFocusContext(focused: focused);
        }
      } on Object {
        // A failed platform focus query does not block metadata registration.
      }
    } on Object {
      // Main-window focus context is optional on platforms without the channel.
    }
  }

  void _requestBoundsReport() {
    if (!_focusContextConnected || _mainWindowController == null || !mounted) {
      return;
    }
    _boundsReportRequested = true;
    if (_boundsReportRunning) return;
    _boundsReportRunning = true;
    unawaited(_drainBoundsReports());
  }

  Future<void> _drainBoundsReports() async {
    try {
      while (_boundsReportRequested && mounted) {
        _boundsReportRequested = false;
        final mainController = _mainWindowController;
        final windowController = _windowController;
        if (!_focusContextConnected ||
            mainController == null ||
            windowController == null) {
          return;
        }
        try {
          final snapshot = await _readWindowBounds();
          if (snapshot == null) return;
          await mainController.invokeMethod<void>(
            auxiliaryWindowBoundsMethod,
            snapshot.toMap(),
          );
        } on Object {
          // Bounds are optional when the native window API is unavailable.
        }
      }
    } finally {
      _boundsReportRunning = false;
      if (_boundsReportRequested && mounted) _requestBoundsReport();
    }
  }

  Future<AuxiliaryWindowBounds?> _readWindowBounds() async {
    final controller = _windowController;
    if (controller == null || _closing) return null;
    final bounds = await windowManager.getBounds();
    if (!mounted || _closing) return null;
    return AuxiliaryWindowBounds(
      windowId: controller.windowId,
      sequence: ++_boundsReportSequence,
      bounds: bounds,
    );
  }

  Map<String, Object?> _transferResponse(String requestId, String status) =>
      {'requestId': requestId, 'status': status};

  Future<Map<String, Object?>> _prepareDocumentTransfer(
    Object? arguments,
  ) async {
    if (arguments is! Map) return _transferResponse('', 'rejected');
    final requestId = arguments['requestId'];
    if (requestId is! String || requestId.isEmpty) {
      return _transferResponse('', 'rejected');
    }
    if (_lastCommittedTransferId == requestId) {
      return _transferResponse(requestId, 'committed');
    }
    final pending = _pendingTransfer;
    if (pending != null) {
      if (pending.requestId == requestId) {
        return {
          ..._transferResponse(requestId, 'prepared'),
          'previousDocument': pending.previousDocument,
        };
      }
      return _transferResponse(requestId, 'busy');
    }
    final currentDocument = _doc;
    final currentInputWindow = _inputWindow;
    if (_closing ||
        currentDocument == null ||
        currentInputWindow == null ||
        currentInputWindow.hasComposition ||
        currentInputWindow.pendingCount != 0 ||
        currentInputWindow.version != currentDocument.version) {
      return _transferResponse(requestId, 'rejected');
    }
    final sourceMap = arguments['document'];
    final incomingPayload = sourceMap is Map
        ? AuxiliaryWindowPayload.fromArguments(jsonEncode(sourceMap))
        : AuxiliaryWindowPayload.mainWindow();
    final documentId = incomingPayload.documentId;
    if (!incomingPayload.isAuxiliary ||
        documentId == null ||
        documentId == currentDocument.id) {
      return _transferResponse(requestId, 'rejected');
    }

    AlulaDoc? preparedDocument;
    try {
      final previousPayload = AuxiliaryWindowPayload.forDocument(
        path: _path,
        mainWindowId: widget.payload.mainWindowId,
        name: _name,
        text: currentDocument.resync().content,
        dirty: _dirty || currentDocument.isDirty,
      ).toMap();
      final core = currentDocument.core;
      preparedDocument = core.openDoc(documentId, incomingPayload.text);
      final decoded = incomingPayload.path == null
          ? null
          : core.workspace.readFileDocument(incomingPayload.path!);
      preparedDocument.setSavepoint(
        decoded?.content ?? (incomingPayload.dirty ? '' : incomingPayload.text),
      );
      final preparedInputWindow = RustTextInputWindow.openAround(
        preparedDocument,
        selectionUtf16: 0,
        maxWindowUtf16: 16384,
        compositionReserveUtf16: 256,
      );
      final nextTransfer = _PreparedAuxiliaryDocumentTransfer(
        requestId: requestId,
        payload: incomingPayload,
        document: preparedDocument,
        inputWindow: preparedInputWindow,
        previousDocument: previousPayload,
      );
      if (!mounted || _closing) {
        preparedDocument.close();
        return _transferResponse(requestId, 'rejected');
      }
      setState(() {
        _pendingTransfer = nextTransfer;
        _statusMessage = '正在交换文档…';
      });
      FocusManager.instance.primaryFocus?.unfocus();
      return {
        ..._transferResponse(requestId, 'prepared'),
        'previousDocument': previousPayload,
      };
    } on Object {
      preparedDocument?.close();
      return _transferResponse(requestId, 'rejected');
    }
  }

  Future<Map<String, Object?>> _commitDocumentTransfer(
    Object? arguments,
  ) async {
    final requestId = arguments is Map ? arguments['requestId'] : null;
    if (requestId is! String || requestId.isEmpty) {
      return _transferResponse('', 'rejected');
    }
    if (_lastCommittedTransferId == requestId) {
      return _transferResponse(requestId, 'committed');
    }
    final pending = _pendingTransfer;
    if (pending == null || pending.requestId != requestId || _closing) {
      return _transferResponse(requestId, 'rejected');
    }
    final previousDocument = _doc;
    setState(() {
      _doc = pending.document;
      _inputWindow = pending.inputWindow;
      _path = pending.payload.path;
      _name = pending.payload.name;
      _dirty = pending.payload.dirty || pending.document.isDirty;
      _pendingTransfer = null;
      _lastCommittedTransferId = requestId;
      _statusMessage = '';
    });
    unawaited(_updateNativeWindowTitle(pending.payload.name));
    if (previousDocument != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!identical(previousDocument, _doc)) previousDocument.close();
      });
    }
    return _transferResponse(requestId, 'committed');
  }

  Future<void> _updateNativeWindowTitle(String title) async {
    try {
      await windowManager.setTitle(title);
    } on Object {
      // The in-window document title remains available without native chrome.
    }
  }

  Future<Map<String, Object?>> _abortDocumentTransfer(
    Object? arguments,
  ) async {
    final requestId = arguments is Map ? arguments['requestId'] : null;
    if (requestId is! String || requestId.isEmpty) {
      return _transferResponse('', 'rejected');
    }
    if (_lastCommittedTransferId == requestId) {
      return _transferResponse(requestId, 'committed');
    }
    final pending = _pendingTransfer;
    if (pending == null || pending.requestId != requestId) {
      return _transferResponse(requestId, 'unknown');
    }
    pending.document.close();
    if (mounted) {
      setState(() {
        _pendingTransfer = null;
        _statusMessage = '';
      });
    } else {
      _pendingTransfer = null;
    }
    return _transferResponse(requestId, 'aborted');
  }

  Future<Map<String, Object?>> _documentTransferStatus(
    Object? arguments,
  ) async {
    final requestId = arguments is Map ? arguments['requestId'] : null;
    if (requestId is! String || requestId.isEmpty) {
      return _transferResponse('', 'unknown');
    }
    if (_lastCommittedTransferId == requestId) {
      return _transferResponse(requestId, 'committed');
    }
    if (_pendingTransfer?.requestId == requestId) {
      return _transferResponse(requestId, 'prepared');
    }
    return _transferResponse(requestId, 'unknown');
  }

  Future<Object?> _handleDocumentTransferMethod(
    String method,
    Object? arguments,
  ) async {
    switch (method) {
      case auxiliaryWindowBoundsQueryMethod:
        return (await _readWindowBounds())?.toMap();
      case auxiliaryDocumentTransferPrepareMethod:
        return _prepareDocumentTransfer(arguments);
      case auxiliaryDocumentTransferCommitMethod:
        return _commitDocumentTransfer(arguments);
      case auxiliaryDocumentTransferAbortMethod:
        return _abortDocumentTransfer(arguments);
      case auxiliaryDocumentTransferStatusMethod:
        return _documentTransferStatus(arguments);
      default:
        return null;
    }
  }

  void _publishAuxiliaryFocusContext({bool? focused}) {
    final controller = _windowController;
    final mainController = _mainWindowController;
    if (!_focusContextConnected ||
        controller == null ||
        mainController == null ||
        _closing) {
      return;
    }
    final event = AuxiliaryFocusContextEvent(
      kind: AuxiliaryFocusEventKind.update,
      windowId: controller.windowId,
      sequence: ++_focusEventSequence,
      groupId: _focusGroupIdentity(controller.windowId),
      focused: focused ?? _nativeWindowFocused == true,
    );
    _focusEventQueue = _focusEventQueue.then((_) async {
      try {
        final snapshot = await mainController.invokeMethod<Object?>(
          auxiliaryFocusContextMethod,
          event.toMap(),
        );
        _acceptGlobalFocusSnapshot(snapshot);
      } on Object {
        // A closed main window no longer owns auxiliary focus context.
      }
    });
  }

  @override
  void onWindowFocus() {
    _nativeFocusGeneration++;
    _nativeWindowFocused = true;
    _publishAuxiliaryFocusContext(focused: true);
  }

  @override
  void onWindowBlur() {
    _nativeFocusGeneration++;
    _nativeWindowFocused = false;
    _publishAuxiliaryFocusContext(focused: false);
  }

  @override
  void onWindowMove() => _requestBoundsReport();

  @override
  void onWindowMoved() => _requestBoundsReport();

  @override
  void onWindowResize() => _requestBoundsReport();

  @override
  void onWindowResized() => _requestBoundsReport();

  @override
  void onWindowMaximize() => _requestBoundsReport();

  @override
  void onWindowUnmaximize() => _requestBoundsReport();

  @override
  void onWindowRestore() => _requestBoundsReport();

  @override
  void onWindowClose() {
    unawaited(_sendClosedAndDestroy());
  }

  Future<void> _loadAlwaysOnTop() async {
    try {
      final alwaysOnTop = await windowManager.isAlwaysOnTop();
      if (!mounted) return;
      setState(() {
        _alwaysOnTop = alwaysOnTop;
        _windowStateError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _alwaysOnTop = null;
        _windowStateError = '读取置顶状态失败：$error';
      });
    }
  }

  Future<void> _toggleAlwaysOnTop() async {
    final current = _alwaysOnTop;
    if (current == null || _changingAlwaysOnTop) return;

    final requested = !current;
    setState(() => _changingAlwaysOnTop = true);
    try {
      await windowManager.setAlwaysOnTop(requested);
      if (!mounted) return;
      setState(() {
        _alwaysOnTop = requested;
        _changingAlwaysOnTop = false;
        _windowStateError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _changingAlwaysOnTop = false;
        _windowStateError = '置顶切换失败：$error';
      });
    }
  }

  void _toggleCompactMode() {
    setState(() => _compactMode = !_compactMode);
  }

  Future<void> _openDocument() async {
    final payload = widget.payload;
    AlulaDoc? openedDocument;
    try {
      final documentId = payload.documentId;
      if (documentId == null || documentId <= 0) {
        throw StateError('缺少为辅助窗口分配的文档 ID');
      }
      final core = AlulaCore.load();
      final decoded = payload.path != null
          ? core.workspace.readFileDocument(payload.path!)
          : null;
      final content = payload.path != null && !payload.dirty
          ? decoded?.content ?? payload.text
          : payload.text;
      final doc = openedDocument = core.openDoc(documentId, content);
      final inputWindow = RustTextInputWindow.openAround(
        doc,
        selectionUtf16: 0,
        maxWindowUtf16: 16384,
        compositionReserveUtf16: 256,
      );
      // 干净磁盘文件以磁盘内容为 savepoint；未命名/脏文本以空 savepoint 呈现脏标。
      doc.setSavepoint(
        decoded?.content ?? (payload.dirty ? '' : content),
      );
      if (!mounted) {
        doc.close();
        return;
      }
      setState(() {
        _doc = doc;
        _inputWindow = inputWindow;
        _path = payload.path;
        _name = payload.name;
        _dirty = payload.dirty || doc.isDirty;
      });
    } on Object catch (error) {
      openedDocument?.close();
      if (!mounted) return;
      setState(() {
        _name = payload.name;
        _dirty = false;
        _doc = null;
        _statusMessage = '辅助窗口打开失败：$error';
      });
    }
  }

  String _statusMessage = '';

  Future<void> _sendClosedAndDestroy() async {
    if (_closing) return;
    _closing = true;
    try {
      await _focusEventQueue;
      final mainController = await _findMainWindowController();
      if (mainController != null) {
        final doc = _doc;
        final text = doc?.resync().content ?? widget.payload.text;
        final closePayload = AuxiliaryWindowPayload.forDocument(
          path: _path,
          name: _name,
          text: text,
          dirty: _dirty || doc?.isDirty == true,
        ).toMap()
          ..['windowId'] = _windowController?.windowId ?? '';
        await mainController.invokeMethod<void>(
          'alula_auxiliary_closed',
          closePayload,
        );
      }
    } on Object {
      // 主窗口不可达：仅关闭本窗口（文档状态以磁盘/主窗会话为准）。
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Unmap the GTK window while its rendering context is still alive.
      try {
        await windowManager.hide();
      } on Exception {
        // The native close still finishes if hiding is unavailable.
      }
    }
    await windowManager.setPreventClose(false);
    if (mounted) setState(_releaseDocuments);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // destroy() posts WM_QUIT to the message loop shared with the main window.
      await windowManager.close();
    } else {
      await windowManager.destroy();
    }
  }

  void _releaseDocuments() {
    final document = _doc;
    final prepared = _pendingTransfer?.document;
    _doc = null;
    _inputWindow = null;
    _pendingTransfer = null;
    document?.close();
    prepared?.close();
  }

  Future<WindowController?> _findMainWindowController() async {
    final knownMainController = _mainWindowController;
    if (knownMainController != null) return knownMainController;
    final mainWindowId = widget.payload.mainWindowId;
    if (mainWindowId != null) {
      return WindowController.fromWindowId(mainWindowId);
    }
    final controllers = await WindowController.getAll();
    for (final controller in controllers) {
      final payload =
          AuxiliaryWindowPayload.fromArguments(controller.arguments);
      if (!payload.isAuxiliary) return controller;
    }
    return null;
  }

  Widget _buildActiveEditorTab() {
    final enabled = !_closing && _pendingTransfer == null;
    final activate = enabled ? _editorFocus.requestFocus : null;
    return Semantics(
      container: true,
      role: SemanticsRole.tabBar,
      child: Container(
        key: const ValueKey('auxiliary-editor-tab-strip'),
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFF181B20),
          border: Border(bottom: BorderSide(color: Color(0xFF343945))),
        ),
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 31, maxWidth: 320),
          child: Semantics(
            key: const ValueKey('auxiliary-editor-active-tab'),
            container: true,
            explicitChildNodes: true,
            role: SemanticsRole.tab,
            selected: true,
            label: _dirty ? '$_name，未保存' : _name,
            onTap: activate,
            child: Material(
              color: const Color(0xFF14161A),
              child: InkWell(
                onTap: activate,
                excludeFromSemantics: true,
                child: Container(
                  foregroundDecoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Colors.blueAccent, width: 2)),
                  ),
                  padding: const EdgeInsetsDirectional.only(start: 6, end: 6.5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EditorTabFileIcon(fileName: _name),
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            _name,
                            key: const ValueKey('auxiliary-editor-tab-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      EditorTabCloseAction(
                        actionKey: const ValueKey('auxiliary-editor-tab-close'),
                        enabled: enabled,
                        emphasized: true,
                        dirty: _dirty,
                        width: 20,
                        onPressed: () => unawaited(_sendClosedAndDestroy()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final inputWindow = _inputWindow;
    final titleHeight = _compactMode ? 30.0 : 35.0;
    final titleActionConstraints = BoxConstraints.tightFor(
      width: 30,
      height: titleHeight,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: false),
      home: Scaffold(
        backgroundColor: const Color(0xFF14161A),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('auxiliary-title-row'),
              color: const Color(0xFF181B20),
              height: titleHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Spacer(),
                  Semantics(
                    key: const ValueKey('auxiliary-compact-mode-semantics'),
                    container: true,
                    excludeSemantics: true,
                    label: '紧凑模式',
                    button: true,
                    toggled: _compactMode,
                    onTap: _toggleCompactMode,
                    child: IconButton(
                      key: const ValueKey('auxiliary-compact-mode-button'),
                      tooltip: _compactMode ? '退出紧凑模式' : '启用紧凑模式',
                      onPressed: _toggleCompactMode,
                      icon: Icon(
                        _compactMode ? Icons.fullscreen_exit : Icons.fullscreen,
                        size: 14,
                      ),
                      constraints: titleActionConstraints,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.standard,
                    ),
                  ),
                  Semantics(
                    key: const ValueKey('auxiliary-always-on-top-semantics'),
                    container: true,
                    excludeSemantics: true,
                    label: '始终置顶',
                    button: true,
                    toggled: _alwaysOnTop,
                    enabled: _alwaysOnTop != null && !_changingAlwaysOnTop,
                    onTap: _alwaysOnTop != null && !_changingAlwaysOnTop
                        ? _toggleAlwaysOnTop
                        : null,
                    child: IconButton(
                      key: const ValueKey('auxiliary-always-on-top-button'),
                      tooltip: _changingAlwaysOnTop
                          ? '正在切换置顶状态'
                          : _alwaysOnTop == null
                              ? '置顶状态不可用'
                              : _alwaysOnTop!
                                  ? '取消始终置顶'
                                  : '始终置顶',
                      onPressed: _alwaysOnTop != null && !_changingAlwaysOnTop
                          ? _toggleAlwaysOnTop
                          : null,
                      icon: const Icon(Icons.push_pin_outlined, size: 14),
                      selectedIcon: const Icon(Icons.push_pin, size: 14),
                      isSelected: _alwaysOnTop ?? false,
                      constraints: titleActionConstraints,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.standard,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('auxiliary-close-button'),
                    tooltip: '移回主窗口并关闭',
                    onPressed: doc == null || _pendingTransfer != null
                        ? null
                        : () {
                            _sendClosedAndDestroy();
                          },
                    icon: const Icon(Icons.close, size: 14),
                    constraints: titleActionConstraints,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.standard,
                  ),
                ],
              ),
            ),
            if (!_compactMode && doc != null) _buildActiveEditorTab(),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_statusMessage,
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade300)),
              ),
            if (_windowStateError != null)
              Semantics(
                key: const ValueKey('auxiliary-window-state-error'),
                container: true,
                liveRegion: true,
                label: _windowStateError!,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ExcludeSemantics(
                    child: Text(
                      _windowStateError!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade300,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: doc == null || inputWindow == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: _compactMode
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(4),
                      child: Focus(
                        canRequestFocus: _pendingTransfer == null,
                        descendantsAreFocusable: _pendingTransfer == null,
                        child: AbsorbPointer(
                          absorbing: _pendingTransfer != null,
                          child: RustTextInputField(
                            key: const ValueKey('auxiliary-editor-input'),
                            inputWindow: inputWindow,
                            focusNode: _editorFocus,
                            scrollController: _scrollController,
                            tabSize: 4,
                            semanticsLabel: '$_name 辅助窗口编辑器',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                            onDelta: (delta) {
                              if (!mounted ||
                                  delta.operations.isEmpty ||
                                  _pendingTransfer != null ||
                                  !identical(_doc, doc)) {
                                return;
                              }
                              // The input window has already committed the delta.
                              final dirty = doc.isDirty;
                              if (_dirty != dirty) {
                                setState(() => _dirty = dirty);
                              }
                            },
                            onError: (error) {
                              if (mounted) {
                                setState(() => _statusMessage = '编辑错误：$error');
                              }
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
