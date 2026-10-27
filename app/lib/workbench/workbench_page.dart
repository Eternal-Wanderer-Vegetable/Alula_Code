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

import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import '../editor/find_replace.dart';
import '../editor/text_diff.dart';
import '../editor/undo_stack.dart';
import '../git/git_cli.dart';
import '../search/search_service.dart';
import '../workspace/workspace_watcher.dart';
import 'activity_bar.dart';
import 'commands.dart';
import 'layout_controller.dart';
import 'layout_grid.dart';
import 'keybindings.dart';
import 'layout_store.dart';
import 'quick_input.dart';
import 'session_store.dart';
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
  WorkbenchPage({
    super.key,
    this.autoLsp = false,
    this.autoFolder,
    LayoutStore? layoutStore,
    SessionStore? sessionStore,
    KeybindingsStore? keybindingsStore,
    this.windowControls = false,
  })  : layoutStore = layoutStore ?? _defaultStore,
        sessionStore = sessionStore ?? _defaultSessionStore,
        keybindingsStore = keybindingsStore ?? _defaultKeybindingsStore;

  /// 启动即自动拉起 rust-analyzer（演示/自动化验证用）。
  final bool autoLsp;

  /// 随 autoLsp 一起自动打开的文件夹。
  final String? autoFolder;

  /// 布局持久化（测试注入临时路径，避免读写真实 ~/.alula/layout.json）。
  final LayoutStore layoutStore;

  /// 会话 journal（测试注入临时路径）。
  final SessionStore sessionStore;

  /// 键位覆盖文件（测试注入临时路径）。
  final KeybindingsStore keybindingsStore;

  /// 自绘窗口控制按钮（真实窗口开启；测试关闭，避免触碰插件通道）。
  final bool windowControls;

  static final LayoutStore _defaultStore = LayoutStore();
  static final SessionStore _defaultSessionStore = SessionStore();
  static final KeybindingsStore _defaultKeybindingsStore = KeybindingsStore();

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  static const _untitledId = 1;

  AlulaCore? _core;
  String _loadError = '';
  int _nextDocId = 2;

  /// 工作台布局（分割树）。启动时尝试从磁盘恢复（W1-4）。
  WorkbenchLayout _layout = WorkbenchLayout();
  final CommandRegistry _commands = CommandRegistry();

  /// 键位集合（默认表 + 用户 keybindings.json 覆盖，docs/09 W3-2）。
  late final KeybindingSet _keybindings;
  List<String>? _fileIndexCache; // 快速打开的文件索引（打开文件夹时失效）
  Timer? _stateSaveTimer;

  // ---------- 撤销/重做（feat-010，自研栈：不依赖 TextField 内建 UndoHistory） ----------
  final UndoStack _undoStack = UndoStack();
  DateTime? _lastEditAt;
  bool _undoRedoBusy = false; // 撤销/重做程序化写回时不入栈

  // ---------- 查找/替换 ----------
  bool _findVisible = false;
  bool _replaceVisible = false;

  // ---------- 搜索视图（feat-search） ----------
  final _searchQuery = TextEditingController();
  List<SearchHit> _searchHits = [];
  bool _searching = false;
  String? _searchBackendLabel;
  bool _searchCaseSensitive = false;
  StreamSubscription<SearchHit>? _searchSub;
  int _searchGen = 0;
  SearchService? _searchService;
  WorkspaceWatcher? _watcher;

  // ---------- Git 面板（feat-git，CLI 封装） ----------
  String _sidebarView = 'explorer';
  GitCli? _git;
  bool _gitReady = false;
  String _gitBranch = '';
  List<GitStatusEntry> _gitEntries = [];
  String? _gitError;
  final _commitMessage = TextEditingController();
  String _gitDiff = '';
  String _gitDiffPath = '';
  bool _gitDiffStaged = false;
  final _findQuery = TextEditingController();
  final _replaceInput = TextEditingController();
  List<TextMatch> _matches = const [];
  int _matchIndex = -1;
  bool _caseSensitive = false;

  /// journal 单文档文本上限（字符）：超出不落 journal（内容只存在于内存，
  /// 崩溃后该文档回退为磁盘内容）。低内存纪律：journal 不做无界缓冲。
  static const _kMaxJournalTextChars = 2000000;

  String? _workspaceRoot;
  final List<TreeNode> _treeRoots = [];

  /// 编辑器组（W2-2）：region → 组；焦点组承载快捷键/保存/补全/新开文档。
  final Map<String, EditorGroup> _groups = {};
  String _focusedRegion = 'editor';
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
      TabController(length: 4, vsync: this, initialIndex: 0);

  @override
  void initState() {
    super.initState();
    final saved = widget.layoutStore.tryLoad();
    if (saved != null) {
      _layout = WorkbenchLayout(root: saved);
    }
    _layout.addListener(_scheduleStateSave);
    _keybindings = KeybindingSet.load(
        userJson: widget.keybindingsStore.tryLoadText());
    _registerCommands();
    _ensureGroupsFromLayout(); // 保存的布局可能含多个编辑器组
    if (!_groups.containsKey('editor')) {
      _groups['editor'] = EditorGroup('editor');
    }
    _initCore();
  }

  /// 命令注册（W3-1）：菜单/键位/命令面板统一入口。
  void _registerCommands() {
    void reg(String id, String category, String title,
        Future<void> Function() run, [String? shortcut]) {
      _commands.register(Command(
          id: id, category: category, title: title, run: run, shortcut: shortcut));
    }

    reg('file.openFolder', '文件', '打开文件夹…', _showOpenFolderDialog);
    reg('file.save', '文件', '保存', _saveActive, 'Ctrl+S');
    reg('view.commandPalette', '查看', '命令面板', () async => _showCommandPalette(),
        'Ctrl+Shift+P');
    reg('view.quickOpen', '查看', '快速打开文件…', () async => _showQuickOpen(),
        'Ctrl+P');
    reg('view.search', '查看', '全局搜索…', () async => _selectSidebarView('search'));
    reg('view.toggleSidebar', '查看', '切换侧栏',
        () async => _layout.toggleRegion('sidebar'), 'Ctrl+B');
    reg('view.togglePanel', '查看', '切换面板',
        () async => _layout.toggleRegion('panel'), 'Ctrl+J');
    reg('view.quickInput', '查看', '命令面板', () async => _showCommandPalette());
    reg('editor.split', '编辑器', '拆分编辑器', () async => _splitFocusedGroup());
    reg('editor.completion', '编辑器', '触发补全', _requestCompletion,
        'Ctrl+Space');
    reg('editor.verifyIntegrity', '编辑器', '校验一致性',
        () async => _verifyIntegrity());
    reg('view.panelDiagnostics', '查看', '诊断面板',
        () async => _panelTab.animateTo(0));
    reg('view.panelCompletions', '查看', '补全面板',
        () async => _panelTab.animateTo(1));
    reg('view.panelSyntax', '查看', '语法面板',
        () async => _panelTab.animateTo(2));
    reg('editor.undo', '编辑器', '撤销', () async => _undo());
    reg('editor.redo', '编辑器', '重做', () async => _redo());
    reg('editor.find', '编辑器', '查找…', () async => _toggleFind());
    reg('editor.replace', '编辑器', '替换…', () async => _openReplace());
    reg('lsp.start', '语言服务', '启动 rust-analyzer', _startLsp);
    reg('help.about', '帮助', '关于 Alula Code', () async => _showAbout());
  }

  /// 菜单项的键位提示后缀（用户 keybindings.json 重绑定后自动跟随）。
  String _sc(String commandId) {
    final sc = _keybindings.shortcutFor(commandId);
    return sc == null ? '' : '    $sc';
  }

  /// 执行命令（键位/菜单/面板统一出口）；未知 id（用户键位指向不存在的命令）
  /// 给状态栏提示而不是静默吞掉。
  void _runCommand(String id) {
    final c = _commands.byId(id);
    if (c == null) {
      setState(() => _statusDetail = '命令不存在：$id（检查 keybindings.json）');
      return;
    }
    c.run();
  }

  void _showCommandPalette() {
    QuickInput.show(
      context,
      hint: '输入命令名（> 前缀可省）',
      items: [
        for (final c in _commands.all)
          QuickItem(label: c.label, detail: c.shortcut, onRun: c.run),
      ],
    );
  }

  void _showQuickOpen() {
    QuickInput.show(
      context,
      hint: '按文件名筛选（工作区内，最多索引 2000 个文件）',
      items: [
        for (final path in _workspaceFileIndex())
          QuickItem(
              label: _nameOf(path),
              detail: path,
              onRun: () => _openFileByPath(path)),
      ],
    );
  }

  /// 工作区文件索引（快速打开用）：有界递归遍历，跳过常见重目录；
  /// 打开新文件夹时失效。同步 FFI 遍历在大仓库会卡 UI，Phase 1 后续改异步。
  List<String> _workspaceFileIndex() {
    final core = _core;
    final root = _workspaceRoot;
    if (core == null || root == null) return const [];
    final cached = _fileIndexCache;
    if (cached != null) return cached;
    const skipDirs = {'.git', 'target', 'node_modules', 'build', '.dart_tool'};
    const maxFiles = 2000;
    final out = <String>[];
    void walk(String dir) {
      if (out.length >= maxFiles) return;
      try {
        final entries = core.workspace.listDir(dir);
        for (final e in entries) {
          if (out.length >= maxFiles) return;
          final path = e['path'] as String;
          final name = e['name'] as String;
          if ((e['is_dir'] as bool?) ?? false) {
            if (!skipDirs.contains(name)) walk(path);
          } else {
            out.add(path);
          }
        }
      } on AlulaException {
        // 不可读目录：跳过
      }
    }

    walk(root);
    _fileIndexCache = out;
    return out;
  }

  /// 布局/会话变更防抖落盘（拖拽每帧都通知、编辑每键都触发，不能每帧写盘）。
  void _scheduleStateSave() {
    _stateSaveTimer?.cancel();
    _stateSaveTimer = Timer(const Duration(milliseconds: 500), () {
      widget.layoutStore.save(_layout.root);
      widget.sessionStore.save(_encodeSession());
    });
  }

  /// 会话 journal 序列化：文档文本只在 untitled 或已脏时落盘；
  /// 干净文件恢复时从磁盘重读（journal 保持小）。
  Map<String, Object?> _encodeSession() => {
        'v': 1,
        'focused': _focusedRegion,
        if (_workspaceRoot != null) 'workspace': _workspaceRoot,
        'groups': [
          for (final g in _groups.values)
            {
              'region': g.region,
              'active': g.activeDocId,
              'docs': [
                for (final d in g.docs)
                  {
                    'id': d.id,
                    if (d.path != null) 'path': d.path,
                    if ((d.isUntitled || d.isDirty) &&
                        d.controller.text.length <= _kMaxJournalTextChars)
                      'text': d.controller.text,
                  }
              ],
            }
        ],
      };

  void _initCore() {
    try {
      final core = AlulaCore.load();
      _core = core;
      _abiVersion = core.abiVersion;
      _restoreSession(core);
      // journal 没有未命名文档时才建欢迎页（避免恢复后出现重复未命名）
      final g = _focused;
      if (!g.docs.any((d) => d.isUntitled)) {
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
        g.docs.add(untitled);
        controller.addListener(() => _onDocChanged(_untitledId));
        _scheduleStateSave();
      }
      if (g.activeDocId == null && g.docs.isNotEmpty) {
        g.activeDocId = g.docs.last.id;
      }
      _state = WbSyncState.idle;
      _statusDetail = '已连接 Rust 核心 v$_abiVersion';
      var openedFolder = false;
      if (_workspaceRoot == null &&
          widget.autoFolder != null &&
          Directory(widget.autoFolder!).existsSync()) {
        _openFolder(widget.autoFolder!);
        openedFolder = true;
      } else if (_workspaceRoot != null) {
        _reloadTreeRoots();
      }
      if (openedFolder && widget.autoLsp) {
        Future<void>.delayed(
            const Duration(milliseconds: 50), _startLsp);
      }
    } catch (e) {
      _loadError = e.toString();
      _state = WbSyncState.error;
      _statusDetail = '核心加载失败';
    }
  }

  /// 恢复上次会话（W2-4）：组/标签/焦点/工作区 + 未保存文本。
  /// 脏文件的脏标记不跨重启保留（内容优先）：恢复后 savedText = 恢复文本，
  /// 首次编辑从恢复文本继续增量同步。journal 损坏一律按全新会话启动。
  void _restoreSession(AlulaCore core) {
    final data = widget.sessionStore.tryLoad();
    if (data == null) return;
    try {
      final groupsRaw = data['groups'];
      if (groupsRaw is! List) return;
      var maxId = 1;
      for (final gr in groupsRaw) {
        if (gr is! Map) continue;
        final region = gr['region'];
        if (region is! String || !_isEditorRegion(region)) continue;
        final target = _groups[region];
        if (target == null) continue; // 布局里已无此组：跳过
        final docsRaw = gr['docs'];
        if (docsRaw is! List) continue;
        for (final dr in docsRaw) {
          if (dr is! Map) continue;
          final id = (dr['id'] as num?)?.toInt();
          if (id == null) continue;
          final path = dr['path'] as String?;
          final text = dr['text'] as String?;
          String? content;
          String savedText;
          // 优先级：journal 文本（未保存内容）> 磁盘内容；脏标记不跨重启保留
          if (path != null) {
            String? disk;
            try {
              disk = core.workspace.readFile(path);
            } on AlulaException {
              disk = null; // 磁盘文件没了：只能靠 journal
            }
            if (text != null) {
              content = text;
            } else if (disk != null) {
              content = disk;
            } else {
              continue;
            }
          } else {
            if (text == null) continue; // untitled 缺 journal 文本：跳过
            content = text;
          }
          savedText = content;
          final doc = core.openDoc(id, content);
          final name =
              path != null ? _nameOf(path) : '未命名';
          final controller = TextEditingController(text: content);
          final open = OpenDoc(
            id: id,
            path: path,
            uri: path != null ? _pathToUri(path) : null,
            name: name,
            doc: doc,
            controller: controller,
            savedText: savedText,
          );
          target.docs.add(open);
          controller.addListener(() => _onDocChanged(id));
          if (id > maxId) maxId = id;
        }
        final active = (gr['active'] as num?)?.toInt();
        if (target.docs.isNotEmpty) {
          target.activeDocId =
              target.docs.any((d) => d.id == active) ? active : target.docs.last.id;
        }
      }
      final focused = data['focused'];
      if (focused is String && _groups.containsKey(focused)) {
        _focusedRegion = focused;
      }
      final workspace = data['workspace'];
      if (workspace is String && Directory(workspace).existsSync()) {
        _workspaceRoot = workspace;
        _git = GitCli(root: workspace);
        _searchService = SearchService(root: workspace);
        _attachWorkspaceWatcher();
      }
      _nextDocId = maxId + 1;
    } catch (_) {
      // journal 损坏：忽略（组状态保持空，按全新会话继续）
    }
  }

  String _nameOf(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  /// 重载文件树根（journal 恢复工作区后）。
  void _reloadTreeRoots() {
    final core = _core;
    final root = _workspaceRoot;
    if (core == null || root == null) return;
    try {
      final entries = core.workspace.listDir(root);
      _treeRoots
        ..clear()
        ..addAll(entries
            .map((e) => TreeNode(
                  name: e['name'] as String,
                  path: e['path'] as String,
                  isDir: (e['is_dir'] as bool?) ?? false,
                ))
            .toList());
    } on AlulaException catch (_) {
      // 工作区目录不可读：树保持空，用户可重新打开文件夹
    }
  }

  /// 焦点组（组被移除时回退到第一个组）。
  EditorGroup get _focused =>
      _groups[_focusedRegion] ?? _groups.values.first;

  OpenDoc? get _active => _focused.active;

  Iterable<OpenDoc> get _allDocs sync* {
    for (final g in _groups.values) {
      yield* g.docs;
    }
  }

  EditorGroup? _ownerOf(int docId) {
    for (final g in _groups.values) {
      for (final d in g.docs) {
        if (d.id == docId) return g;
      }
    }
    return null;
  }

  bool _isEditorRegion(String r) => r == 'editor' || r.startsWith('editor-');

  /// 布局树里的编辑器叶子 ↔ 组状态对齐（启动恢复/拆分后调用）。
  void _ensureGroupsFromLayout() {
    for (final l in _layout.root.leaves) {
      if (_isEditorRegion(l.region) && !_groups.containsKey(l.region)) {
        _groups[l.region] = EditorGroup(l.region);
      }
    }
  }

  // ---------- 编辑同步 ----------

  void _onDocChanged(int docId) {
    final owner = _ownerOf(docId);
    final doc = owner?.docs.where((d) => d.id == docId).firstOrNull;
    if (doc == null) return;
    final isActiveOfFocused =
        owner!.region == _focusedRegion && owner.activeDocId == docId;
    final newText = doc.controller.text;
    final beforeText = doc.savedText; // 撤销快照基线（必须在基准前移前捕获）
    final ops = diffToOps(beforeText, newText);
    if (ops.isEmpty) return;
    doc.savedText = newText; // 同步基准前移（失败时由失配分支恢复）

    // 撤销栈入帧
    if (!_undoRedoBusy) {
      final now = DateTime.now();
      final coalesce =
          _lastEditAt != null && now.difference(_lastEditAt!) < const Duration(milliseconds: 400);
      _undoStack.push(before: beforeText, caret: newText.length, coalesce: coalesce);
      _lastEditAt = now;
    }
    doc.dirtyDisk = true; // 有未保存的用户编辑（同步失配分支同样视为脏）
    _scheduleStateSave(); // 编辑内容变化 → journal 防抖更新
    final sw = Stopwatch()..start();
    try {
      final version = doc.doc.apply(ops);
      sw.stop();
      if (isActiveOfFocused) {
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
      if (isActiveOfFocused) {
        setState(() {
          _state = WbSyncState.mismatch;
          _statusDetail = '版本失配（Rust 已到 v${e.current}），已重同步至 v${r.version}';
        });
      }
    } catch (e) {
      if (isActiveOfFocused) {
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
        _fileIndexCache = null;
        _git = GitCli(root: path);
        _refreshGit();
        _searchService = SearchService(root: path);
        _attachWorkspaceWatcher();
        _layout.showRegion('sidebar');
        _scheduleStateSave();
      });
    } on AlulaException catch (e) {
      setState(() {
        _statusDetail = '打开文件夹失败：${e.code}';
        _state = WbSyncState.error;
      });
    }
  }

  /// fixture 工程的跨平台探测（演示/测试默认值）。
  static String _defaultFolderSuggestion() {
    final rel =
        Directory('${Directory.current.path}/../tests/fixtures/rust-mini');
    if (rel.existsSync()) return rel.path;
    return Directory.current.path;
  }

  Future<void> _showOpenFolderDialog() async {
    final controller = TextEditingController(
        text: _workspaceRoot ?? _defaultFolderSuggestion());
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
    // 已在任何组打开 → 跳转到所在组并激活（对标 VS Code 单实例语义）
    for (final g in _groups.values) {
      for (final d in g.docs) {
        if (d.path == path) {
          setState(() {
            g.activeDocId = d.id;
            _focusedRegion = g.region;
          });
          return;
        }
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
        final g = _focused;
        g.docs.add(open);
        g.activeDocId = id;
      });
      _scheduleStateSave();
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
    final owner = _ownerOf(id);
    if (owner == null) return;
    final doc = owner.docs.where((d) => d.id == id).firstOrNull;
    if (doc == null) return;
    final wasActive = owner.activeDocId == id;
    doc.doc.close();
    doc.controller.dispose();
    _editorFocusNodes.remove(id)?.dispose();
    setState(() {
      owner.docs.remove(doc);
      if (wasActive) {
        owner.activeDocId = owner.docs.isEmpty ? null : owner.docs.last.id;
      }
      // 组空且不是唯一的组 → 摘除该组（布局树自动折叠）
      if (owner.docs.isEmpty && _groups.length > 1) {
        _layout.removeRegion(owner.region);
        _groups.remove(owner.region);
        if (_focusedRegion == owner.region) {
          _focusedRegion = _groups.keys.first;
        }
      }
      _scheduleStateSave();
    });
  }

  /// 拆分焦点组（W2-2）：沿水平方向分出新组，新组获得焦点。
  void _splitFocusedGroup() {
    final region = _focusedRegion;
    var i = 2;
    while (_groups.containsKey('editor-$i')) {
      i++;
    }
    final fresh = 'editor-$i';
    if (!_layout.splitRegion(region, fresh, Axis.horizontal)) {
      setState(() => _statusDetail = '拆分失败：区域 $region 不可拆分');
      return;
    }
    setState(() {
      _ensureGroupsFromLayout();
      _focusedRegion = fresh; // 新组获焦（对标 VS Code 拆分行为）
      _statusDetail = '已拆分编辑器：$region → $fresh';
      _scheduleStateSave();
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
      for (final d in _allDocs) {
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
      for (final d in _allDocs) {
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
      active.dirtyDisk = false;
      setState(() {
        _statusDetail = '已原子保存 ${active.name}（v${active.doc.version}）';
      });
      _scheduleStateSave(); // 保存后 journal 里的 text 分支消失（转干净）
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

  /// 每文档一个带 onKeyEvent 的 FocusNode：在事件分发第一站拦截
  /// 撤销/重做/查找键位。必须在这里抢——TextField 内建 UndoHistory 在
  /// 焦点链更下方注册了 Ctrl+Z/Y，晚于焦点节点处理器，且会双栈打架
  /// （测试环境还会死锁）。
  final Map<int, FocusNode> _editorFocusNodes = {};

  FocusNode _focusNodeFor(EditorGroup g, OpenDoc doc) {
    return _editorFocusNodes.putIfAbsent(doc.id, () {
      return FocusNode(onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        if (!ctrl) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.keyZ) {
          shift ? _redo() : _undo();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyY) {
          _redo();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyF && !shift) {
          _toggleFind();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyH && !shift) {
          _openReplace();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      });
    });
  }

  /// 撤销：把快照写回 controller，经「diff → FFI」通路同步 Rust。
  void _undo() {
    final active = _active;
    if (active == null) {
      setState(() => _statusDetail = '撤销需要打开的文档');
      return;
    }
    final sel = active.controller.selection;
    final entry = _undoStack.undo(
        active.controller.text, sel.baseOffset >= 0 ? sel.baseOffset : 0);
    if (entry == null) {
      setState(() => _statusDetail = '无可撤销');
      return;
    }
    _undoRedoBusy = true;
    final caret = entry.caret.clamp(0, entry.text.length);
    active.controller.value = TextEditingValue(
      text: entry.text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _undoRedoBusy = false;
    _lastEditAt = null; // 撤销后不再与后续打字合并
    _onFindTextChanged();
    setState(() => _statusDetail = '已撤销');
    _scheduleStateSave();
  }

  void _redo() {
    final active = _active;
    if (active == null) {
      setState(() => _statusDetail = '重做需要打开的文档');
      return;
    }
    final sel = active.controller.selection;
    final entry = _undoStack.redo(
        active.controller.text, sel.baseOffset >= 0 ? sel.baseOffset : 0);
    if (entry == null) {
      setState(() => _statusDetail = '无可重做');
      return;
    }
    _undoRedoBusy = true;
    final caret = entry.caret.clamp(0, entry.text.length);
    active.controller.value = TextEditingValue(
      text: entry.text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _undoRedoBusy = false;
    _lastEditAt = null;
    _onFindTextChanged();
    setState(() => _statusDetail = '已重做');
    _scheduleStateSave();
  }

  // ---------- 查找/替换 ----------

  void _toggleFind() {
    setState(() {
      _findVisible = !_findVisible;
      if (_findVisible) {
        _replaceVisible = false;
        _refreshMatches();
      } else {
        _matches = const [];
        _matchIndex = -1;
      }
    });
  }

  void _openReplace() {
    setState(() {
      _findVisible = true;
      _replaceVisible = true;
      _refreshMatches();
    });
  }

  void _onFindTextChanged() {
    if (!_findVisible) return;
    _refreshMatches();
    setState(() {});
  }

  void _refreshMatches() {
    final active = _active;
    final text = active?.controller.text ?? '';
    _matches = _findVisible
        ? findMatches(text, _findQuery.text, caseSensitive: _caseSensitive)
        : const [];
    if (_matchIndex >= _matches.length) {
      _matchIndex = _matches.isEmpty ? -1 : _matches.length - 1;
    }
    if (_matches.isEmpty) _matchIndex = -1;
  }

  void _gotoMatch(int direction) {
    final active = _active;
    if (active == null) return;
    _refreshMatches();
    if (_matches.isEmpty) {
      setState(() => _matchIndex = -1);
      return;
    }
    final sel = active.controller.selection;
    final from = sel.baseOffset >= 0 ? sel.baseOffset : 0;
    final m = direction > 0
        ? findNext(_matches, from)
        : findPrevious(_matches, from);
    _matchIndex = _matches.indexOf(m!);
    active.controller.value = TextEditingValue(
      text: active.controller.text,
      selection: TextSelection(baseOffset: m.start, extentOffset: m.end),
    );
    setState(() {});
  }

  void _replaceCurrent() {
    final active = _active;
    if (active == null) return;
    _refreshMatches();
    if (_matches.isEmpty) {
      setState(() => _statusDetail = '无匹配');
      return;
    }
    final sel = active.controller.selection;
    final from = sel.baseOffset >= 0 ? sel.baseOffset : 0;
    var m = findNext(_matches, from)!;
    var isOnMatch = sel.baseOffset == m.start && sel.extentOffset == m.end;
    if (!isOnMatch) {
      // 先跳转到该匹配，再按一次才替换（与 VS Code 语义一致）
      _matchIndex = _matches.indexOf(m);
      active.controller.value = TextEditingValue(
        text: active.controller.text,
        selection: TextSelection(baseOffset: m.start, extentOffset: m.end),
      );
      setState(() {});
      return;
    }
    final t = active.controller.text;
    active.controller.value = TextEditingValue(
      text: t.replaceRange(m.start, m.end, _replaceInput.text),
      selection:
          TextSelection.collapsed(offset: m.start + _replaceInput.text.length),
    );
    _refreshMatches();
    setState(() => _statusDetail =
        '已替换 1 处（剩余 ${_matches.length} 处）');
  }

  void _replaceAll() {
    final active = _active;
    if (active == null) return;
    final r = replaceAllMatches(active.controller.text, _findQuery.text,
        _replaceInput.text,
        caseSensitive: _caseSensitive);
    if (r.count == 0) {
      setState(() => _statusDetail = '无匹配');
      return;
    }
    active.controller.value = TextEditingValue(
      text: r.newText,
      selection: TextSelection.collapsed(offset: r.newText.length),
    );
    _refreshMatches();
    setState(() => _statusDetail = '已替换 ${r.count} 处');
    _scheduleStateSave();
  }

  // ---------- 搜索视图 ----------

  Future<void> _runSearch() async {
    final svc = _searchService;
    final gen = ++_searchGen;
    await _searchSub?.cancel();
    final q = _searchQuery.text;
    if (!mounted) return;
    setState(() {
      _searching = true;
      _searchHits = [];
    });
    if (q.trim().isEmpty || svc == null) {
      if (mounted) setState(() => _searching = false);
      return;
    }
    final backend = await svc.detectBackend();
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _searchBackendLabel = switch (backend) {
        SearchBackend.ripgrep => 'ripgrep',
        SearchBackend.gitGrep => 'git grep',
        null => '不可用（需 ripgrep 或 git 仓库）',
      };
      _searching = backend == null;
    });
    if (backend == null) return;
    final caseSensitive = _searchCaseSensitive;
    _searchSub = svc
        .search(q, caseSensitive: caseSensitive, backend: backend)
        .listen((hit) {
      if (!mounted || gen != _searchGen) return;
      setState(() => _searchHits = [..._searchHits, hit]);
    }, onDone: () {
      if (mounted && gen == _searchGen) setState(() => _searching = false);
    }, onError: (Object e) {
      if (mounted && gen == _searchGen) {
        setState(() {
          _searching = false;
          _statusDetail = '搜索失败：$e';
        });
      }
    });
  }

  /// 打开命中的文件并跳转到对应行。
  Future<void> _openSearchHit(SearchHit hit) async {
    final root = _workspaceRoot;
    if (root == null) return;
    final sep = root.endsWith('/') || root.endsWith('\\') ? '' : '/';
    await _openFileByPath('$root$sep${hit.path}');
    final active = _active;
    if (active == null) return;
    final lines = active.controller.text.split('\n');
    var offset = 0;
    for (var i = 0; i < hit.line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    active.controller.value = TextEditingValue(
      text: active.controller.text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  // ---------- 工作区文件监视（feat-filewatch） ----------

  void _attachWorkspaceWatcher() {
    final root = _workspaceRoot;
    if (root == null) return;
    _watcher?.stop();
    _watcher = WorkspaceWatcher(root: root, onChanged: _onWorkspaceChanged)
      ..start();
  }

  /// 外部变更（防抖后）：刷新文件树 + Git 状态；打开文档若在磁盘上被外部
  /// 修改，干净文档自动重载、脏文档仅提示（不覆盖本地编辑）。
  Future<void> _onWorkspaceChanged() async {
    if (!mounted) return;
    _refreshTree();
    _refreshGit();
    await _checkExternalChanges();
  }

  /// 重载文件树：根 + 已展开目录（保留展开状态）。
  void _refreshTree() {
    final core = _core;
    if (core == null || _workspaceRoot == null) return;
    _reloadTreeRoots();

    void walk(List<TreeNode> nodes) {
      for (final n in nodes) {
        if (!n.isDir || !n.expanded || n.children == null) continue;
        try {
          final entries = core.workspace.listDir(n.path);
          n.children = entries
              .map((e) => TreeNode(
                    name: e['name'] as String,
                    path: e['path'] as String,
                    isDir: (e['is_dir'] as bool?) ?? false,
                  ))
              .toList();
          walk(n.children!);
        } on AlulaException {
          // 目录被外部删除等：保留旧子节点，不中断
        }
      }
    }

    walk(_treeRoots);
    if (mounted) setState(() {});
  }

  Future<void> _checkExternalChanges() async {
    final core = _core;
    if (core == null) return;
    for (final g in _groups.values) {
      for (final d in g.docs.where((d) => d.path != null)) {
        String? disk;
        try {
          disk = core.workspace.readFile(d.path!);
        } on AlulaException {
          continue; // 文件被外部删除：V1 不处理（保留内存缓冲）
        }
        if (d.dirtyDisk) {
          if (disk != d.savedText) {
            if (mounted) {
              setState(() =>
                  _statusDetail = '注意：${d.name} 在磁盘上被外部修改（本地有未保存编辑）');
            }
          }
        } else if (disk != d.controller.text) {
          // 干净文档自动重载（_undoRedoBusy 复用为「程序化更新」闸门）
          _undoRedoBusy = true;
          d.controller.value = TextEditingValue(
            text: disk,
            selection: const TextSelection.collapsed(offset: 0),
          );
          d.savedText = disk;
          d.dirtyDisk = false;
          _undoRedoBusy = false;
          if (mounted) {
            setState(() => _statusDetail = '已自动重载外部修改的 ${d.name}');
          }
        }
      }
    }
    _scheduleStateSave();
  }

  // ---------- Git 面板 ----------

  Future<void> _refreshGit() async {
    final git = _git;
    if (git == null) return;
    try {
      if (!await git.isRepo()) {
        if (!mounted) return;
        setState(() {
          _gitReady = false;
          _gitError = null;
          _gitEntries = [];
        });
        return;
      }
      final branch = await git.currentBranch();
      final entries = await git.status();
      if (!mounted) return;
      setState(() {
        _gitReady = true;
        _gitBranch = branch;
        _gitEntries = entries;
        _gitError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gitReady = false;
        _gitError = '$e';
      });
    }
  }

  Future<void> _gitStage(String path) async {
    try {
      await _git?.stage([path]);
      await _refreshGit();
    } catch (e) {
      if (mounted) setState(() => _gitError = '$e');
    }
  }

  Future<void> _gitUnstage(String path) async {
    try {
      await _git?.unstage([path]);
      await _refreshGit();
    } catch (e) {
      if (mounted) setState(() => _gitError = '$e');
    }
  }

  Future<void> _gitCommit() async {
    final msg = _commitMessage.text;
    if (msg.trim().isEmpty) {
      setState(() => _gitError = '提交信息不能为空');
      return;
    }
    try {
      final summary = await _git!.commit(msg);
      _commitMessage.clear();
      await _refreshGit();
      if (mounted) setState(() => _statusDetail = summary);
    } catch (e) {
      if (mounted) setState(() => _gitError = '$e');
    }
  }

  Future<void> _showGitDiff(GitStatusEntry e) async {
    final staged = !e.hasUnstagedChanges; // 纯暂存变更看 cached，否则看工作区
    try {
      final d = await _git?.diff(path: e.path, staged: staged) ?? '';
      if (!mounted) return;
      setState(() {
        _gitDiff = d.isEmpty ? '（无文本差异：可能是二进制文件或全新文件）' : d;
        _gitDiffPath = e.origPath == null ? e.path : '${e.origPath} → ${e.path}';
        _gitDiffStaged = staged;
      });
      _panelTab.animateTo(3);
    } catch (err) {
      if (mounted) setState(() => _gitError = '$err');
    }
  }

  /// 侧栏视图切换（W4）：重复点当前视图 = 折叠/展开侧栏。
  void _selectSidebarView(String view) {
    if (_sidebarView == view && !_layout.isCollapsed('sidebar')) {
      _layout.toggleRegion('sidebar');
      return;
    }
    setState(() => _sidebarView = view);
    _layout.showRegion('sidebar');
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
    _stateSaveTimer?.cancel();
    // 退出前把未落盘的布局与会话冲写
    widget.layoutStore.save(_layout.root);
    widget.sessionStore.save(_encodeSession());
    for (final d in _allDocs) {
      d.controller.dispose();
    }
    for (final n in _editorFocusNodes.values) {
      n.dispose();
    }
    _searchSub?.cancel();
    _searchQuery.dispose();
    _watcher?.stop();
    _panelTab.dispose();
    _commitMessage.dispose();
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
      body: CallbackShortcuts(
        bindings: {
          for (final e in _keybindings.resolve().entries)
            e.key: () => _runCommand(e.value),
        },
        child: Focus(
        autofocus: true, // 无处可聚焦时也保证全局键位可达（W3-1）
        child: Column(
        children: [
          AlulaTitleBar(
              windowControls: widget.windowControls,
              menus: [
            (
              '文件',
              [
                TitleMenuItem('打开文件夹', _showOpenFolderDialog),
                TitleMenuItem('保存${_sc('file.save')}', _saveActive),
              ],
            ),
            (
              '编辑',
              [
                TitleMenuItem('撤销${_sc('editor.undo')}', _undo),
                TitleMenuItem('重做${_sc('editor.redo')}', _redo),
                TitleMenuItem('查找…${_sc('editor.find')}', _toggleFind),
                TitleMenuItem('替换…${_sc('editor.replace')}', _openReplace),
              ],
            ),
            (
              '查看',
              [
                TitleMenuItem(
                    '命令面板${_sc('view.commandPalette')}', _showCommandPalette),
                TitleMenuItem(
                    '快速打开文件…${_sc('view.quickOpen')}', _showQuickOpen),
                TitleMenuItem('搜索…${_sc('view.search')}', () {
                  _selectSidebarView('search');
                }),
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
                        activeView: _sidebarView,
                        sidebarCollapsed: _layout.isCollapsed('sidebar'),
                        onSelectView: _selectSidebarView,
                      ),
                  'sidebar': (_) => switch (_sidebarView) {
                        'git' => _buildGitPanel(),
                        'search' => _buildSearchPanel(),
                        _ => _buildSidebar(),
                      },
                  'panel': (_) => _buildPanel(),
                  // 编辑器组通配（W2-2）：'editor'、'editor-2'…各对应一个组
                  for (final g in _groups.values)
                    g.region: (_) => _buildEditorArea(g),
                },
              ),
            ),
          ),
          AlulaStatusBar(
            state: _state,
            detail: _statusDetail,
            lspStatus: _lspStatus,
            diagnosticsCount: _diagnostics.length,
            tabCount: _allDocs.length,
            abiVersion: _abiVersion,
            syncCount: _syncCount,
            panelCollapsed: _layout.isCollapsed('panel'),
            onTogglePanel: () => _layout.toggleRegion('panel'),
          ),
        ],
        ),
        ),
      ),
    );
  }

  // ---------- 侧栏：搜索 ----------

  Widget _buildSearchPanel() {
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('search-input'),
                    controller: _searchQuery,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '搜索（Enter 执行）',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                IconButton(
                  tooltip: '区分大小写',
                  onPressed: () {
                    setState(() => _searchCaseSensitive = !_searchCaseSensitive);
                  },
                  icon: Text('Aa',
                      style: TextStyle(
                          fontSize: 11,
                          color: _searchCaseSensitive
                              ? Colors.lightBlueAccent
                              : Colors.grey.shade400)),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '搜索',
                  onPressed: _runSearch,
                  icon: const Icon(Icons.search, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Text(
              _searching
                  ? '搜索中…'
                  : '${_searchBackendLabel == null ? '' : '$_searchBackendLabel · '}${_searchHits.length} 个匹配（上限 500）',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _searchHits.isEmpty
                ? Center(
                    child: Text(
                      _searching ? '' : '输入关键词后回车搜索',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _searchHits.length,
                    itemBuilder: (context, i) {
                      final hit = _searchHits[i];
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                        key: ValueKey('search-hit-$i'),
                        dense: true,
                        title: Text(hit.lineText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                        subtitle: Text(
                            '${_nameOf(hit.path)} · 行 ${hit.line}',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis),
                        onTap: () => _openSearchHit(hit),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- 侧栏：源代码管理（Git） ----------

  Widget _buildGitPanel() {
    if (!_gitReady) {
      return Container(
        color: const Color(0xFF181B20),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.topLeft,
        child: Text(
          _gitError ?? '当前文件夹不是 Git 仓库',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }
    final staged =
        _gitEntries.where((e) => e.hasStagedChanges).toList();
    final changes =
        _gitEntries.where((e) => !e.hasStagedChanges).toList();
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                const Text('源代码管理',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.call_split, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(_gitBranch,
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 11)),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _refreshGit,
                  icon: const Icon(Icons.refresh, size: 15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('commit-input'),
                  controller: _commitMessage,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '提交信息（暂存的更改）',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('commit-button'),
                    onPressed: staged.isEmpty ? null : _gitCommit,
                    icon: const Icon(Icons.check, size: 14),
                    label: Text(staged.isEmpty
                        ? '没有暂存的更改'
                        : '提交（${staged.length}）'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (_gitError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _gitError!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _gitEntries.isEmpty
                ? Center(
                    child: Text('工作区干净',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)))
                : ListView(
                    children: [
                      if (staged.isNotEmpty) ...[
                        _gitSectionHeader('暂存的更改（${staged.length}）'),
                        for (final e in staged)
                          _gitTile(e, stagedEntry: true),
                      ],
                      if (changes.isNotEmpty) ...[
                        _gitSectionHeader('更改（${changes.length}）'),
                        for (final e in changes)
                          _gitTile(e, stagedEntry: false),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _gitSectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
        child: Text(text,
            style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );

  Widget _gitTile(GitStatusEntry e, {required bool stagedEntry}) {
    final name = _nameOf(e.path);
    // 面板容器有背景色，ListTile 需自备 Material 才能正常绘制 ink
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
      key: ValueKey('git-${stagedEntry ? 's' : 'w'}-${e.path}'),
      dense: true,
      leading: Text(e.code,
          style: TextStyle(
              fontSize: 11,
              color: e.isUntracked
                  ? Colors.greenAccent
                  : (stagedEntry ? Colors.lightGreenAccent : Colors.orangeAccent))),
      title: Text(name,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis),
      subtitle: e.origPath != null
          ? Text('${_nameOf(e.origPath!)} → $name',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => _showGitDiff(e),
      trailing: IconButton(
        tooltip: stagedEntry ? '取消暂存' : '暂存',
        onPressed: () =>
            stagedEntry ? _gitUnstage(e.path) : _gitStage(e.path),
        icon: Icon(
          stagedEntry ? Icons.remove : Icons.add,
          size: 15,
          color: Colors.grey.shade400,
        ),
      ),
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
                        : _nameOf(_workspaceRoot!),
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
    final activePaths = _allDocs.map((d) => d.path).toSet();
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

  Widget _buildEditorArea(EditorGroup g) {
    return Container(
      color: const Color(0xFF14161A),
      child: Column(
        children: [
          _buildTabStrip(g),
          const Divider(height: 1),
          _buildBreadcrumb(g),
          Expanded(child: _buildEditor(g)),
        ],
      ),
    );
  }

  /// 面包屑（W2-3）：工作区相对路径拆段；点文件夹段在文件树中展开该目录。
  Widget _buildBreadcrumb(EditorGroup g) {
    final active = g.active;
    if (active == null || active.path == null || _workspaceRoot == null) {
      return const SizedBox.shrink();
    }
    final normRoot =
        _normPath(_workspaceRoot!).replaceAll(RegExp(r'/+$'), '');
    final normPath = _normPath(active.path!);
    var rel = normPath.startsWith('$normRoot/')
        ? normPath.substring(normRoot.length + 1)
        : normPath;
    final segments = rel.split('/');
    return Container(
      key: ValueKey('breadcrumb-${g.region}'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              Text(' › ',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11)),
            GestureDetector(
              onTap: () => _revealInExplorer(segments, i),
              child: Text(
                segments[i],
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _normPath(String p) => p.replaceAll('\\', '/');

  /// 点面包屑文件夹段 → 侧栏唤起 + 文件树逐级展开到该目录。
  void _revealInExplorer(List<String> segments, int index) {
    if (_workspaceRoot == null || index >= segments.length - 1) {
      return; // 最后一段是文件名，无目录可展开
    }
    _layout.showRegion('sidebar');
    final target =
        '${_normPath(_workspaceRoot!).replaceAll(RegExp(r'/+$'), '')}/'
            '${segments.take(index + 1).join('/')}';
    void walk(List<TreeNode> nodes) {
      for (final n in nodes) {
        final np = _normPath(n.path);
        if (target == np || target.startsWith('$np/')) {
          if (n.isDir && !n.expanded) _toggleDir(n);
          if (n.children != null) walk(n.children!);
        }
      }
    }

    walk(_treeRoots);
    setState(() {});
  }

  Widget _buildTabStrip(EditorGroup g) {
    return Container(
      height: 36,
      color: const Color(0xFF181B20),
      child: Row(
        children: [
          Expanded(
            // W2-1：标签溢出横向滚动（对标 VS Code 滚动标签条）
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in g.docs) _buildTab(g, d),
                ],
              ),
            ),
          ),
          // 编辑器动作区（原工具栏按钮迁入，对标 VS Code 编辑器右上角动作）
          IconButton(
            tooltip: '拆分编辑器',
            onPressed: _splitFocusedGroup,
            icon: const Icon(Icons.splitscreen, size: 16),
            visualDensity: VisualDensity.compact,
          ),
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

  /// 单个标签（W2-1）：点击激活 / 中键关闭 / 拖动排序。
  Widget _buildTab(EditorGroup g, OpenDoc d) {
    final tab = InkWell(
      onTap: () => setState(() {
        g.activeDocId = d.id;
        _focusedRegion = g.region;
      }),
      child: Container(
        key: ValueKey('tab-${d.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: d.id == g.activeDocId
              ? const Color(0xFF14161A)
              : Colors.transparent,
          border: d.id == g.activeDocId
              ? const Border(
                  top: BorderSide(color: Colors.blueAccent, width: 2))
              : const Border(
                  top: BorderSide(color: Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Text('${d.name}${d.isDirty ? " •" : ""}',
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
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != d.id,
      onAcceptWithDetails: (details) => _moveDoc(g, details.data, d.id),
      builder: (context, _, __) => Draggable<int>(
        data: d.id,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF252932),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(d.name, style: const TextStyle(fontSize: 12)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tab),
        child: Listener(
          // 中键关闭（kMiddleMouseButton），不影响左键激活
          onPointerDown: (e) {
            if (e.buttons == kMiddleMouseButton) _closeDoc(d.id);
          },
          child: tab,
        ),
      ),
    );
  }

  /// 拖动排序：把被拖标签移到目标标签的位置。
  void _moveDoc(EditorGroup g, int draggedId, int targetId) {
    final from = g.docs.indexWhere((d) => d.id == draggedId);
    final to = g.docs.indexWhere((d) => d.id == targetId);
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      final doc = g.docs.removeAt(from);
      g.docs.insert(to, doc);
    });
    _scheduleStateSave();
  }

  Widget _buildEditor(EditorGroup g) {
    final active = g.active;
    if (active == null) {
      return Center(
        child: Text('打开文件夹后，从文件树选择文件',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          TextField(
            focusNode: _focusNodeFor(g, active),
            controller: active.controller,
            maxLines: null,
            expands: true,
            onTap: () {
              // 点击编辑器把焦点切到所在组（快捷键/保存/补全路由依据）
              if (_focusedRegion != g.region) {
                setState(() => _focusedRegion = g.region);
              }
            },
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
          if (_findVisible)
            Positioned(top: 0, right: 12, child: _buildFindBar()),
        ],
      ),
    );
  }

  /// 查找/替换栏（feat-010，对标 VS Code 编辑器右上角浮层）。
  Widget _buildFindBar() {
    final count = _matches.isEmpty
        ? (_findQuery.text.isEmpty ? '' : '无匹配')
        : '${_matchIndex < 0 ? '-' : _matchIndex + 1}/${_matches.length}';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _toggleFind,
      },
      child: Container(
        key: const ValueKey('find-bar'),
        width: 470,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF252932),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(blurRadius: 12, color: Colors.black45)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findQuery,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                        hintText: '查找', isDense: true, border: InputBorder.none),
                    onChanged: (_) => _onFindTextChanged(),
                    onSubmitted: (_) => _gotoMatch(1),
                  ),
                ),
                Text(count,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 11)),
                IconButton(
                  tooltip: '区分大小写',
                  onPressed: () {
                    setState(() {
                      _caseSensitive = !_caseSensitive;
                      _refreshMatches();
                    });
                  },
                  icon: Text('Aa',
                      style: TextStyle(
                          fontSize: 11,
                          color: _caseSensitive
                              ? Colors.lightBlueAccent
                              : Colors.grey.shade400)),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '上一个匹配',
                  onPressed: () => _gotoMatch(-1),
                  icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '下一个匹配',
                  onPressed: () => _gotoMatch(1),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: _toggleFind,
                  icon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_replaceVisible)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replaceInput,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                          hintText: '替换为',
                          isDense: true,
                          border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    tooltip: '替换',
                    onPressed: _replaceCurrent,
                    icon: const Icon(Icons.find_replace, size: 15),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: '全部替换',
                    onPressed: _replaceAll,
                    icon: const Icon(Icons.done_all, size: 15),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
          ],
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
              Tab(text: 'Git Diff'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _panelTab,
              children: [
                _buildDiagnosticsPanel(),
                _buildCompletionPanel(),
                _buildSyntaxPanel(),
                _buildGitDiffPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitDiffPanel() {
    if (_gitDiff.isEmpty) {
      return Center(
        child: Text('在源代码管理中点击更改文件查看差异',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_gitDiffPath（${_gitDiffStaged ? '暂存区' : '工作区'}）',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '清除',
                onPressed: () => setState(() => _gitDiff = ''),
                icon: const Icon(Icons.close, size: 14),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              _gitDiff,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, height: 1.4),
            ),
          ),
        ),
      ],
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

  /// 上次保存时的全文（FFI 增量同步基准；每次成功 apply 都会前移，
  /// 因此不能当「与磁盘不一致」的脏标记用）。
  String savedText;
  bool lspAttached = false;

  /// 与磁盘不一致（有未保存的用户编辑）：编辑置位、saveFile 复位。
  bool dirtyDisk = false;

  bool get isDirty => dirtyDisk;
  bool get isUntitled => path == null;
}

/// 一个编辑器组（W2-2）：一组标签 + 组内激活文档。
class EditorGroup {
  EditorGroup(this.region);

  /// 对应布局树里的叶子 region（'editor'、'editor-2'…）。
  final String region;
  final List<OpenDoc> docs = [];
  int? activeDocId;

  OpenDoc? get active {
    for (final d in docs) {
      if (d.id == activeDocId) return d;
    }
    return null;
  }
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
