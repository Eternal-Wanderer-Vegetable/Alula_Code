/// 浮动辅助窗口（LAY-12a）。
///
/// desktop_multi_window 为新窗口再跑一次 main()：入口按
/// `WindowController.fromCurrentEngine()` 的载荷分流到本文件的精简编辑器。
/// Alula 的 Rust FFI core 为每进程一份，辅助窗口按 path 从磁盘重开文档；
/// 未命名/脏文本经启动载荷传递（savepoint/撤销历史不跨进程，差异已登记）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge/alula_core.dart';
import '../editor/rust_text_input_field.dart';
import '../editor/rust_text_input_window.dart';

/// 辅助窗口启动载荷。businessId 标记区分辅助引擎与主引擎。
class AuxiliaryWindowPayload {
  const AuxiliaryWindowPayload({
    required this.isAuxiliary,
    this.path,
    this.name = '未命名',
    this.text = '',
    this.dirty = false,
  });

  static const businessId = 'alula-auxiliary-editor';

  final bool isAuxiliary;
  final String? path;
  final String name;
  final String text;
  final bool dirty;

  factory AuxiliaryWindowPayload.mainWindow() =>
      const AuxiliaryWindowPayload(isAuxiliary: false);

  factory AuxiliaryWindowPayload.forDocument({
    String? path,
    required String name,
    required String text,
    required bool dirty,
  }) {
    return AuxiliaryWindowPayload(
      isAuxiliary: true,
      path: path,
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
      return AuxiliaryWindowPayload(
        isAuxiliary: true,
        path: pathValue == null || pathValue.isEmpty ? null : pathValue,
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

class _AuxiliaryEditorAppState extends State<AuxiliaryEditorApp> {
  AlulaDoc? _doc;
  String _name = '未命名';
  bool _dirty = false;
  bool _closing = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _openDocument();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openDocument() async {
    final payload = widget.payload;
    try {
      final core = AlulaCore.load();
      final decoded =
          payload.path != null ? core.workspace.readFileDocument(payload.path!) : null;
      final content = payload.text.isNotEmpty ? payload.text : decoded?.content ?? '';
      final doc = core.openDoc(1, content);
      // 干净磁盘文件以磁盘内容为 savepoint；未命名/脏文本以空 savepoint 呈现脏标。
      doc.setSavepoint(decoded?.content ?? '');
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _name = payload.name;
        _dirty = doc.isDirty;
      });
    } on Object catch (error) {
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
      final mainController = await _findMainWindowController();
      if (mainController != null) {
        final doc = _doc;
        final text = doc?.resync().content ?? widget.payload.text;
        await mainController.invokeMethod(
          'alula_auxiliary_closed',
          AuxiliaryWindowPayload.forDocument(
            path: widget.payload.path,
            name: _name,
            text: text,
            dirty: _dirty || doc?.isDirty == true,
          ).toMap(),
        );
      }
    } on Object {
      // 主窗口不可达：仅关闭本窗口（文档状态以磁盘/主窗会话为准）。
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<WindowController?> _findMainWindowController() async {
    final controllers = await WindowController.getAll();
    for (final controller in controllers) {
      final payload = AuxiliaryWindowPayload.fromArguments(
          controller.arguments);
      if (!payload.isAuxiliary) return controller;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_name${_dirty ? " •" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('auxiliary-close-button'),
                    tooltip: '移回主窗口并关闭',
                    onPressed:
                        doc == null ? null : () { _sendClosedAndDestroy(); },
                    icon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_statusMessage,
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade300)),
              ),
            Expanded(
              child: doc == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(4),
                      child: RustTextInputField(
                        inputWindow: RustTextInputWindow.openAround(
                          doc,
                          selectionUtf16: 0,
                          maxWindowUtf16: 16384,
                          compositionReserveUtf16: 256,
                        ),
                        scrollController: _scrollController,
                        tabSize: 4,
                        semanticsLabel: '$_name 辅助窗口编辑器',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        onDelta: (delta) {
                          try {
                            _doc?.applyWith(delta.version, delta.operations);
                            if (mounted && !_dirty) {
                              setState(() => _dirty = true);
                            }
                          } on Object {
                            // 陈旧窗口引擎：忽略增量。
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
          ],
        ),
      ),
    );
  }
}
