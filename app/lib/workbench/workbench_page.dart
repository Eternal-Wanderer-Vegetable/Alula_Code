/// Alula Code — W1 工作台页面（docs/09）。
///
/// 布局骨架：标题栏 + 分割树网格（活动栏/侧栏/编辑器/面板）+ 状态栏。
/// 编辑同步/LSP/保存的闭环逻辑自 Phase 1 增量 1 原样迁移（docs/03）：
/// 1. 打开文件夹 → 文件树（懒加载）→ 打开文件 → 多标签编辑；
/// 2. 编辑 → diff 增量 op → FFI → Rust（Ropey）→ 版本回执；
/// 3. Ctrl+S → Rust 侧原子保存（临时文件 + fsync + rename）；
/// 4. LSP（rust-analyzer，按工作区共享）：诊断实时推送 + 补全 + didSave 触发 flycheck；
/// 5. Tree-sitter：语法 token 着色预览。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import '../editor/text_diff.dart';
import 'activity_bar.dart';
import 'layout_controller.dart';
import 'layout_grid.dart';
import 'status_bar.dart';
import 'title_bar.dart';

/// 语法 token 颜色（VS Code Dark+ 风格）。
const Map<String, Color> _tokenColors = {
  'keyword': Color(0xFFC586C0),
  'keyword.function': Color(0xFFDCDCAA),
  'keyword.conditional': Color(0xFFC586C0),
  'keyword.repeat': Color(0xFFC586C0),
  'keyword.modifier': Color(0xFF569CD6),
  'function': Color(0xFFDCDCAA),
  'function.call': Color(0xFFDCDCAA),
  'method': Color(0xFFDCDCAA),
  'string': Color(0xFFCE9178),
  'comment': Color(0xFF6A9955),
  'type': Color(0xFF4EC9B0),
  'constant': Color(0xFF4FC1FF),
  'number': Color(0xFFB5CEA8),
  'property': Color(0xFF9CDCFE),
  'variable': Color(0xFF9CDCFE),
};

Color _tokenColor(String kind) {
  for (final e in _tokenColors.entries) {
    if (kind.startsWith(e.key)) return e.value;
  }
  return const Color(0xFFD4D4D4);
}

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, this.autoLsp = false, this.autoFolder});

  /// 启动即自动拉起 rust-analyzer（演示/自动化验证用）。
  final bool autoLsp;

  /// 随 autoLsp 一起自动打开的文件夹。
  final String? autoFolder;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  static const _untitledId = 1;

  AlulaCore? _core;
  String _loadError = '';
  int _nextDocId = 2;

  /// 工作台布局（分割树；W1-4 接持久化）。
  late final WorkbenchLayout _layout = WorkbenchLayout();

  String? _workspaceRoot;
  final List<TreeNode> _treeRoots = [];
  final List<OpenDoc> _openDocs = [];
  int? _activeDocId;
  int _syncCount = 0;
  int _lastLatencyUs = 0;
  int _abiVersion = 0;

  WbSyncState _state = WbSyncState.idle;
  String _statusDetail = '初始化…';

  // LSP / 语法
  bool _lspStarting = false;
  bool _lspReady = false;
  String _lspStatus = 'LSP 未启动';
  final List<Map<String, Object?>> _diagnostics = [];
  Map<int, List<Map<String, Object?>>> _syntaxByDoc = {};
  Timer? _pollTimer;
  bool _polling = false;
  List<String> _completionItems = const [];

  late final TabController _panelTab =
      TabController(length: 3, vsync: this, initialIndex: 0);

  final _editorFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _initCore();
  }

  void _initCore() {
    try {
      final core = AlulaCore.load();
      _core = core;
      _abiVersion = core.abiVersion;
      const welcome =
          '// Alula Code\n// 打开一个文件夹开始工作，或在此处体验编辑同步。\n';
      final doc = core.openDoc(_untitledId, welcome);
      final controller = TextEditingController(text: welcome);
      final untitled = OpenDoc(
        id: _untitledId,
        name: '未命名',
        doc: doc,
        controller: controller,
        savedText: welcome,
      );
      _openDocs.add(untitled);
      _activeDocId = _untitledId;
      controller.addListener(() => _onDocChanged(_untitledId));
      _state = WbSyncState.idle;
      _statusDetail = '已连接 Rust 核心 v$_abiVersion';
      if (widget.autoFolder != null &&
          Directory(widget.autoFolder!).existsSync()) {
        _openFolder(widget.autoFolder!);
        if (widget.autoLsp) {
          Future<void>.delayed(
              const Duration(milliseconds: 50), _startLsp);
        }
      }
    } catch (e) {
      _loadError = e.toString();
      _state = WbSyncState.error;
      _statusDetail = '核心加载失败';
    }
  }

  OpenDoc? get _active {
    for (final d in _openDocs) {
      if (d.id == _activeDocId) return d;
    }
    return null;
  }

  // ---------- 编辑同步 ----------

  void _onDocChanged(int docId) {
    final doc = _openDocs.where((d) => d.id == docId).firstOrNull;
    if (doc == null) return;
    final newText = doc.controller.text;
    final ops = diffToOps(doc.savedText, newText);
    if (ops.isEmpty) return;
    doc.savedText = newText; // 同步基准前移（失败时由失配分支恢复）

    final sw = Stopwatch()..start();
    try {
      final version = doc.doc.apply(ops);
      sw.stop();
      if (docId == _activeDocId) {
        setState(() {
          _state = WbSyncState.synced;
          _syncCount++;
          _lastLatencyUs = sw.elapsedMicroseconds;
          _statusDetail = '已同步 v$version（${ops.length} op，$_lastLatencyUs µs）';
        });
      }
    } on SyncMismatchException catch (e) {
      final r = doc.doc.resync();
      doc.controller.value = TextEditingValue(
        text: r.content,
        selection: TextSelection.collapsed(offset: r.content.length),
      );
      doc.savedText = r.content;
      if (docId == _activeDocId) {
        setState(() {
          _state = WbSyncState.mismatch;
          _statusDetail = '版本失配（Rust 已到 v${e.current}），已重同步至 v${r.version}';
        });
      }
    } catch (e) {
      if (docId == _activeDocId) {
        setState(() {
          _state = WbSyncState.error;
          _statusDetail = '同步失败：$e';
        });
      }
    }
  }

  // ---------- 文件夹 / 文件树 ----------

  void _openFolder(String path) {
    final core = _core;
    if (core == null) return;
    try {
      final entries = core.workspace.listDir(path);
      setState(() {
        _workspaceRoot = path;
        _treeRoots.clear();
        _treeRoots.addAll(entries
            .map((e) => TreeNode(
                  name: e['name'] as String,
                  path: e['path'] as String,
                  isDir: (e['is_dir'] as bool?) ?? false,
                ))
            .toList());
        _statusDetail = '工作区：$path（${entries.length} 项）';
        _layout.showRegion('sidebar');
      });
    } on AlulaException catch (e) {
      setState(() {
        _statusDetail = '打开文件夹失败：${e.code}';
        _state = WbSyncState.error;
      });
    }
  }

  Future<void> _showOpenFolderDialog() async {
    final controller = TextEditingController(
        text: _workspaceRoot ??
            (Directory(r'E:\Alula_Code\tests\fixtures\rust-mini').existsSync()
                ? r'E:\Alula_Code\tests\fixtures\rust-mini'
                : Directory.current.path));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '文件夹路径'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('打开')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _openFolder(result);
      if (widget.autoLsp || _lspReady) _startLsp();
    }
  }

  Future<void> _toggleDir(TreeNode node) async {
    final core = _core;
    if (core == null) return;
    if (node.expanded) {
      setState(() => node.expanded = false);
      return;
    }
    if (node.children == null) {
      try {
        final entries = core.workspace.listDir(node.path);
        node.children = entries
            .map((e) => TreeNode(
                  name: e['name'] as String,
                  path: e['path'] as String,
                  isDir: (e['is_dir'] as bool?) ?? false,
                ))
            .toList();
      } on AlulaException catch (e) {
        node.children = [
          TreeNode(name: '（无法读取: ${e.code}）', path: '', isDir: false)
        ];
      }
    }
    setState(() => node.expanded = true);
  }

  void _openTreeFile(TreeNode node) => _openFileByPath(node.path);

  Future<void> _openFileByPath(String path) async {
    final core = _core;
    if (core == null) return;
    for (final d in _openDocs) {
      if (d.path == path) {
        setState(() => _activeDocId = d.id);
        return;
      }
    }
    try {
      final content = core.workspace.readFile(path);
      final id = _nextDocId++;
      final doc = core.openDoc(id, content);
      final name = path.replaceAll('\\', '/').split('/').last;
      final controller = TextEditingController(text: content);
      final open = OpenDoc(
        id: id,
        path: path,
        uri: _pathToUri(path),
        name: name,
        doc: doc,
        controller: controller,
        savedText: content,
      );
      setState(() {
        _openDocs.add(open);
        _activeDocId = id;
      });
      controller.addListener(() => _onDocChanged(id));
      if (_lspReady) {
        try {
          core.lsp.setUri(id, open.uri!);
          core.lsp.didOpen(id, languageId: _languageIdOf(path));
          open.lspAttached = true;
        } catch (_) {}
      }
    } on AlulaException catch (e) {
      setState(() {
        _statusDetail =
            e.code == 'BinaryFile' ? '二进制文件，MVP 暂不支持打开' : '打开失败：${e.code}';
      });
    }
  }

  String _languageIdOf(String path) {
    if (path.endsWith('.rs')) return 'rust';
    if (path.endsWith('.py')) return 'python';
    if (path.endsWith('.ts') || path.endsWith('.js')) return 'typescript';
    return 'plaintext';
  }

  String _pathToUri(String path) {
    final p = path.replaceAll('\\', '/');
    return p.startsWith(RegExp(r'[A-Za-z]:/'))
        ? 'file:///${p[0].toLowerCase()}${p.substring(1)}'
        : 'file:///$p';
  }

  void _closeDoc(int id) {
    final doc = _openDocs.where((d) => d.id == id).firstOrNull;
    if (doc == null) return;
    final wasActive = _activeDocId == id;
    doc.doc.close();
    doc.controller.dispose();
    setState(() {
      _openDocs.remove(doc);
      if (wasActive) {
        _activeDocId = _openDocs.isEmpty ? null : _openDocs.last.id;
      }
    });
  }

  // ---------- LSP ----------

  Future<void> _startLsp() async {
    final core = _core;
    final root = _workspaceRoot;
    if (core == null || root == null || _lspStarting || _lspReady) return;
    setState(() {
      _lspStarting = true;
      _lspStatus = '正在启动 rust-analyzer…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      // Rust 侧按工作区复用服务器进程；挂接用任一已打开文档 id 均可
      core.lsp.start(_untitledId, root, ['rust-analyzer']);
      setState(() {
        _lspReady = true;
        _lspStarting = false;
        _lspStatus = 'rust-analyzer 运行中';
      });
      for (final d in _openDocs) {
        if (!d.isUntitled && !d.lspAttached) {
          try {
            core.lsp.setUri(d.id, d.uri!);
            core.lsp.didOpen(d.id, languageId: _languageIdOf(d.path!));
            d.lspAttached = true;
          } catch (_) {}
        }
      }
      _pollTimer ??= Timer.periodic(const Duration(milliseconds: 800), (_) {
        _pollLanguageServices();
      });
    } catch (e) {
      setState(() {
        _lspStarting = false;
        _lspStatus = '启动失败：$e';
      });
    }
  }

  void _pollLanguageServices() {
    final core = _core;
    if (core == null || _polling || !_lspReady) return;
    _polling = true;
    try {
      final diags = <Map<String, Object?>>[];
      final syntax = <int, List<Map<String, Object?>>>{};
      for (final d in _openDocs) {
        if (d.isUntitled || !d.lspAttached) continue;
        try {
          diags.addAll(
              core.lsp.diagnostics(d.id).map((m) => {...m, 'file': d.name}));
        } catch (_) {}
        final s = core.lsp.syntax(d.id);
        if (s != null) syntax[d.id] = s.tokens;
      }
      if (!mounted) return;
      setState(() {
        _diagnostics
          ..clear()
          ..addAll(diags);
        _syntaxByDoc = syntax;
      });
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  // ---------- 补全 / 保存 ----------

  Future<void> _requestCompletion() async {
    final active = _active;
    if (active == null || !_lspReady) {
      setState(() => _statusDetail = '补全需要先打开文件夹并启动 LSP');
      return;
    }
    final offset = active.controller.selection.baseOffset >= 0
        ? active.controller.selection.baseOffset
        : active.controller.text.length;
    setState(() => _statusDetail = '补全请求中…（阻塞式 FFI，MVP 过渡）');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final items =
          active.doc.core.lsp.completion(active.id, offset, timeoutMs: 10000);
      if (!mounted) return;
      setState(() {
        _completionItems = items.take(50).toList();
        _panelTab.index = 1;
        _statusDetail = '补全返回 ${items.length} 项';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusDetail = '补全失败：$e');
    }
  }

  void _insertCompletion(String text) {
    final active = _active;
    if (active == null) return;
    final sel = active.controller.selection;
    final pos = sel.baseOffset >= 0 ? sel.baseOffset : active.controller.text.length;
    final t = active.controller.text;
    var start = pos;
    while (start > 0) {
      final cu = t.codeUnitAt(start - 1);
      final isIdent = (cu >= 0x61 && cu <= 0x7A) ||
          (cu >= 0x41 && cu <= 0x5A) ||
          (cu >= 0x30 && cu <= 0x39) ||
          cu == 0x5F;
      if (!isIdent) break;
      start--;
    }
    active.controller.value = TextEditingValue(
      text: t.replaceRange(start, pos, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _saveActive() async {
    final active = _active;
    if (active == null) return;
    if (active.isUntitled) {
      setState(() => _statusDetail = '未命名文档不支持保存（请从文件树打开文件）');
      return;
    }
    try {
      active.doc.saveFile(active.path!);
      active.savedText = active.controller.text;
      setState(() {
        _statusDetail = '已原子保存 ${active.name}（v${active.doc.version}）';
      });
      if (active.lspAttached && _lspReady) {
        try {
          active.doc.core.lsp.didSave(active.id);
        } catch (_) {}
      }
    } on AlulaException catch (e) {
      setState(() {
        _state = WbSyncState.error;
        _statusDetail = '保存失败：${e.code} ${e.detail}';
      });
    }
  }

  void _verifyIntegrity() {
    final active = _active;
    if (active == null) return;
    final r = active.doc.resync();
    final matches = r.content == active.controller.text;
    setState(() {
      _state = matches ? WbSyncState.synced : WbSyncState.mismatch;
      _statusDetail = matches
          ? '一致性校验通过：本地与 Rust v${r.version} 完全一致'
          : '不一致！Rust v${r.version} 的内容与本地不同（见日志）';
    });
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alula Code'),
        content: const Text(
          '低内存代码编辑器原型（Flutter 工作台 + Rust 核心）\n'
          'W1 布局骨架 · docs/09\n\n'
          'Phase 1 增量 1 闭环：编辑 → 增量同步 → Rust 应用 → 版本回执；\n'
          'rust-analyzer 诊断/补全；Tree-sitter 语法预览。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final d in _openDocs) {
      d.controller.dispose();
    }
    _editorFocus.dispose();
    _panelTab.dispose();
    _layout.dispose();
    super.dispose();
  }

  // ---------- UI：五大区组装 ----------

  @override
  Widget build(BuildContext context) {
    if (_loadError.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('无法加载 Alula 核心',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(_loadError,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          AlulaTitleBar(menus: [
            (
              '文件',
              [
                TitleMenuItem('打开文件夹', _showOpenFolderDialog),
                TitleMenuItem('保存    Ctrl+S', _saveActive),
              ],
            ),
            (
              '查看',
              [
                TitleMenuItem(
                    '切换侧栏', () => _layout.toggleRegion('sidebar')),
                TitleMenuItem('切换面板', () => _layout.toggleRegion('panel')),
              ],
            ),
            (
              '帮助',
              [
                TitleMenuItem('关于 Alula Code', _showAbout),
              ],
            ),
          ]),
          Expanded(
            child: ListenableBuilder(
              listenable: _layout,
              builder: (context, _) => WorkbenchGrid(
                layout: _layout,
                builders: {
                  'activity': (_) => ActivityBar(
                        sidebarCollapsed: _layout.isCollapsed('sidebar'),
                        onToggleSidebar: () => _layout.toggleRegion('sidebar'),
                      ),
                  'sidebar': (_) => _buildSidebar(),
                  'editor': (_) => _buildEditorArea(),
                  'panel': (_) => _buildPanel(),
                },
              ),
            ),
          ),
          AlulaStatusBar(
            state: _state,
            detail: _statusDetail,
            lspStatus: _lspStatus,
            diagnosticsCount: _diagnostics.length,
            tabCount: _openDocs.length,
            abiVersion: _abiVersion,
            syncCount: _syncCount,
            panelCollapsed: _layout.isCollapsed('panel'),
            onTogglePanel: () => _layout.toggleRegion('panel'),
          ),
        ],
      ),
    );
  }

  // ---------- 侧栏：资源管理器 ----------

  Widget _buildSidebar() {
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _workspaceRoot == null
                        ? '资源管理器'
                        : _workspaceRoot!
                            .split(Platform.pathSeparator)
                            .last,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '打开文件夹',
                  onPressed: _showOpenFolderDialog,
                  icon: const Icon(Icons.folder_open, size: 15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _workspaceRoot == null
                ? Center(
                    child: Text('点击右上角图标打开文件夹',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)))
                : ListView.builder(
                    itemCount: _treeRoots.length,
                    itemBuilder: (context, i) => _buildNode(_treeRoots[i], 0),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode(TreeNode node, int depth) {
    final activePaths = _openDocs.map((d) => d.path).toSet();
    return Column(children: [
      InkWell(
        onTap: () {
          if (node.isDir) {
            _toggleDir(node);
          } else {
            _openTreeFile(node);
          }
        },
        child: Container(
          padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 3, bottom: 3),
          color: activePaths.contains(node.path)
              ? const Color(0xFF20252E)
              : null,
          child: Row(
            children: [
              Icon(
                node.isDir
                    ? (node.expanded ? Icons.folder_open : Icons.folder)
                    : Icons.description_outlined,
                size: 14,
                color: node.isDir ? Colors.amber.shade200 : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(node.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
      if (node.isDir && node.expanded && node.children != null)
        ...node.children!.map((c) => _buildNode(c, depth + 1)),
    ]);
  }

  // ---------- 编辑器区：标签条 + 编辑器 ----------

  Widget _buildEditorArea() {
    return Container(
      color: const Color(0xFF14161A),
      child: Column(
        children: [
          _buildTabStrip(),
          const Divider(height: 1),
          Expanded(child: _buildEditor()),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    return Container(
      height: 36,
      color: const Color(0xFF181B20),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                for (final d in _openDocs)
                  InkWell(
                    onTap: () => setState(() => _activeDocId = d.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: d.id == _activeDocId
                            ? const Color(0xFF14161A)
                            : Colors.transparent,
                        border: d.id == _activeDocId
                            ? const Border(
                                top: BorderSide(
                                    color: Colors.blueAccent, width: 2))
                            : const Border(
                                top: BorderSide(
                                    color: Colors.transparent, width: 2)),
                      ),
                      child: Row(
                        children: [
                          Text(
                              '${d.name}${d.isDirty ? " •" : ""}',
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _closeDoc(d.id),
                            child: Icon(Icons.close,
                                size: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 编辑器动作区（原工具栏按钮迁入，对标 VS Code 编辑器右上角动作）
          IconButton(
            tooltip: _lspReady
                ? 'LSP 运行中'
                : (_workspaceRoot == null ? '启动 LSP（需先打开文件夹）' : '启动 LSP'),
            onPressed: (_lspReady || _workspaceRoot == null) ? null : _startLsp,
            icon: Icon(_lspReady ? Icons.check_circle : Icons.play_arrow,
                size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '补全    Ctrl+Space',
            onPressed: _requestCompletion,
            icon: const Icon(Icons.autorenew, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '校验一致性',
            onPressed: _verifyIntegrity,
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final active = _active;
    if (active == null) {
      return Center(
        child: Text('打开文件夹后，从文件树选择文件',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveActive,
          const SingleActivator(LogicalKeyboardKey.space, control: true):
              _requestCompletion,
          const SingleActivator(LogicalKeyboardKey.f8): _requestCompletion,
          const SingleActivator(LogicalKeyboardKey.f1): () =>
              _panelTab.animateTo(0),
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              _panelTab.animateTo(1),
          const SingleActivator(LogicalKeyboardKey.f3): () =>
              _panelTab.animateTo(2),
        },
        child: Focus(
          focusNode: _editorFocus,
          child: TextField(
            controller: active.controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 面板：诊断 / 补全 / 语法 ----------

  Widget _buildPanel() {
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        children: [
          TabBar(
            controller: _panelTab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '诊断'),
              Tab(text: '补全'),
              Tab(text: '语法 (Tree-sitter)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _panelTab,
              children: [
                _buildDiagnosticsPanel(),
                _buildCompletionPanel(),
                _buildSyntaxPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    if (!_lspReady && _diagnostics.isEmpty) {
      return Center(
        child: Text('LSP 未启动\n打开文件夹后从编辑器右上角启动',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    if (_diagnostics.isEmpty) {
      return Center(
        child: Text('无诊断（代码干净）',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    return ListView.builder(
      itemCount: _diagnostics.length,
      itemBuilder: (context, i) {
        final d = _diagnostics[i];
        final severity = (d['severity'] as num?)?.toInt() ?? 3;
        final (icon, color) = switch (severity) {
          1 => (Icons.error, Colors.redAccent),
          2 => (Icons.warning_amber_rounded, Colors.orangeAccent),
          _ => (Icons.info_outline, Colors.lightBlueAccent),
        };
        return ListTile(
          dense: true,
          leading: Icon(icon, size: 16, color: color),
          title: Text(
            '${d['message'] ?? ''}',
            style: const TextStyle(fontSize: 12),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${d['file'] ?? ''} · L${d['line']} C${d['character']}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        );
      },
    );
  }

  Widget _buildCompletionPanel() {
    if (_completionItems.isEmpty) {
      return Center(
        child: Text('无补全结果\n点击编辑器右上角「补全」或 Ctrl+Space / F8',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    return ListView.builder(
      itemCount: _completionItems.length,
      itemBuilder: (context, i) {
        final item = _completionItems[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.text_snippet, size: 14),
          title: Text(item, style: const TextStyle(fontSize: 12)),
          onTap: () => _insertCompletion(item),
        );
      },
    );
  }

  Widget _buildSyntaxPanel() {
    final active = _active;
    if (active == null) {
      return Center(
        child: Text('无打开文档',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    final tokens = _syntaxByDoc[active.id] ?? const [];
    if (tokens.isEmpty) {
      return Center(
        child: Text('暂无语法数据\n等待轮询（800ms）或启动 LSP',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    const maxPreviewChars = 20000;
    final full = active.controller.text;
    final previewText =
        full.length > maxPreviewChars ? full.substring(0, maxPreviewChars) : full;
    final u16Units = previewText.length;

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final t in tokens) {
      final start = (t['start_utf16'] as num).toInt();
      final end = (t['end_utf16'] as num).toInt();
      if (start >= u16Units) break;
      final clampedEnd = end.clamp(0, u16Units);
      if (clampedEnd <= start) continue;
      if (start > cursor) {
        spans.add(TextSpan(
            text: previewText.substring(cursor, start),
            style: const TextStyle(color: Color(0xFFD4D4D4))));
      }
      final kind = (t['kind'] as String?) ?? '';
      spans.add(TextSpan(
        text: previewText.substring(start, clampedEnd),
        style: TextStyle(color: _tokenColor(kind)),
      ));
      cursor = clampedEnd;
    }
    if (cursor < u16Units) {
      spans.add(TextSpan(
          text: previewText.substring(cursor),
          style: const TextStyle(color: Color(0xFFD4D4D4))));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: SelectableText.rich(
        TextSpan(
          children: spans,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 12, height: 1.4),
        ),
      ),
    );
  }
}

/// 打开的文档（有路径的文件，或未命名草稿）。
class OpenDoc {
  OpenDoc({
    required this.id,
    required this.name,
    required this.doc,
    required this.controller,
    this.path,
    this.uri,
    required this.savedText,
  })  : lspAttached = false;

  final int id;
  final String? path;
  final String? uri;
  final String name;
  final AlulaDoc doc;
  final TextEditingController controller;

  /// 上次保存时的全文（脏标记基准）。
  String savedText;
  bool lspAttached = false;

  bool get isDirty => savedText != controller.text;
  bool get isUntitled => path == null;
}

/// 文件树节点。
class TreeNode {
  TreeNode({required this.name, required this.path, required this.isDir});

  final String name;
  final String path;
  final bool isDir;
  bool expanded = false;
  List<TreeNode>? children;
}
