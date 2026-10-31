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

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/gestures.dart'
    show
        kMiddleMouseButton,
        kPrimaryButton,
        kTouchSlop,
        PointerCancelEvent,
        PointerDownEvent,
        PointerDeviceKind,
        PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import '../editor/editor_minimap.dart';
import '../editor/editor_minimap_markers.dart';
import '../editor/editor_sticky_scroll.dart';
import '../editor/editor_folding.dart';
import '../editor/editor_rendering.dart';
import '../editor/editor_highlight_tokens.dart';
import '../editor/indentation.dart';
import '../editor/find_replace.dart';
import '../editor/lsp_diagnostic_decorations.dart';
import '../editor/navigation_history.dart';
import '../editor/multi_selection.dart';
import '../editor/occurrence_search.dart';
import '../editor/rust_text_input_field.dart';
import '../editor/rust_string_context.dart';
import '../editor/rust_text_input_window.dart';
import '../editor/text_diff.dart';
import '../editor/undo_stack.dart';
import '../editor/workspace_edit.dart';
import '../editor/workspace_search_decorations.dart';
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
  'struct': Color(0xFF4EC9B0),
  'enum': Color(0xFF4EC9B0),
  'interface': Color(0xFF4EC9B0),
  'builtinType': Color(0xFF4EC9B0),
  'constant': Color(0xFF4FC1FF),
  'const': Color(0xFF4FC1FF),
  'boolean': Color(0xFF569CD6),
  'enumMember': Color(0xFF4FC1FF),
  'number': Color(0xFFB5CEA8),
  'property': Color(0xFF9CDCFE),
  'variable': Color(0xFF9CDCFE),
  'parameter': Color(0xFF9CDCFE),
  'attribute': Color(0xFF9CDCFE),
  'macro': Color(0xFF4EC9B0),
  'procMacro': Color(0xFF4EC9B0),
  'macroBang': Color(0xFF4EC9B0),
  'namespace': Color(0xFF4EC9B0),
  'typeParameter': Color(0xFF4EC9B0),
  'decorator': Color(0xFFDCDCAA),
  'operator': Color(0xFFD4D4D4),
  'lifetime': Color(0xFF569CD6),
  'selfKeyword': Color(0xFF569CD6),
  'selfTypeKeyword': Color(0xFF569CD6),
  'formatSpecifier': Color(0xFFCE9178),
  'character': Color(0xFFCE9178),
  'module': Color(0xFF4EC9B0),
  'union': Color(0xFF4EC9B0),
  'typeAlias': Color(0xFF4EC9B0),
  'field': Color(0xFF9CDCFE),
  'constParameter': Color(0xFF4FC1FF),
  'static': Color(0xFF4FC1FF),
  'label': Color(0xFF569CD6),
  'derive': Color(0xFFDCDCAA),
  'builtinAttribute': Color(0xFF9CDCFE),
  'deriveHelper': Color(0xFF9CDCFE),
};

const int _editorInputWindowUtf16 = 16384;
const int _editorCompositionReserveUtf16 = 256;

int _operationPayloadChars(List<List<TextOp>> batches) => batches.fold<int>(
      0,
      (sum, batch) =>
          sum + batch.fold<int>(0, (n, op) => n + (op.text?.length ?? 0)),
    );

bool _isPrintableOvertypeCharacter(String? character) =>
    character != null &&
    character.isNotEmpty &&
    character.runes
        .every((codePoint) => codePoint >= 0x20 && codePoint != 0x7f);

const Map<String, String> _rustAutoClosingBracketPairs = {
  '(': ')',
  '[': ']',
  '{': '}',
};
const Map<String, String> _rustAutoClosingQuotePairs = {'"': '"'};
const Map<String, String> _rustAutoClosingPairs = {
  ..._rustAutoClosingBracketPairs,
  ..._rustAutoClosingQuotePairs,
};
const Map<String, String> _rustSelectionSurroundingPairs = {'<': '>'};
final RegExp _rustOnEnterCommentBefore = RegExp(r'^\s*//\s*\S|\s//\s+\S');
final RegExp _rustOnEnterCommentAfter = RegExp(r'^(?!\s*$)');
const String _rustAutoCloseBefore = ';:.,=}])> \t\n\r';
const int _maxAutoClosedBracketMarkers = 10000;

class _AutoClosedBracketMarker {
  _AutoClosedBracketMarker({
    required this.openOffsetUtf16,
    required this.closeOffsetUtf16,
    required this.close,
  });

  int openOffsetUtf16;
  int closeOffsetUtf16;
  final String close;
}

typedef _RustBracketDeletePlan = ({
  int start,
  String removed,
  int selectionIndex,
  TextSelection selection,
});

typedef _RustBracketBackspace = ({
  int version,
  List<TextSelection> selections,
  List<_RustBracketDeletePlan> plans,
});

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
    this.definitionRequest,
    this.overtypeOnPaste = true,
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

  /// Optional override for deterministic definition-navigation tests.
  final Future<DefinitionResult?> Function(
    int documentId,
    int offsetUtf16,
    int version,
  )? definitionRequest;

  /// Mirrors VS Code's editor.overtypeOnPaste default. User settings will be
  /// wired into this editor option when P07 adds the settings store.
  final bool overtypeOnPaste;

  static final LayoutStore _defaultStore = LayoutStore();
  static final SessionStore _defaultSessionStore = SessionStore();
  static final KeybindingsStore _defaultKeybindingsStore = KeybindingsStore();

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

final RegExp _rustIdentifierPattern = RegExp(
  r'[_\p{XID_Start}][_\p{XID_Continue}]*',
  unicode: true,
);

class _WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  static const _untitledId = 1;

  AlulaCore? _core;
  String _loadError = '';
  int _nextDocId = 2;

  /// 工作台布局（分割树）。启动时尝试从磁盘恢复（W1-4）。
  WorkbenchLayout _layout = WorkbenchLayout();
  final CommandService _commands = CommandService();

  /// 键位集合（默认表 + 用户 keybindings.json 覆盖，docs/09 W3-2）。
  late final KeybindingSet _keybindings;
  List<String>? _fileIndexCache; // 快速打开的文件索引（打开文件夹时失效）
  Timer? _stateSaveTimer;
  Timer? _resourceTimer;
  AlulaResourceStatus? _resourceStatus;

  // ---------- 撤销/重做（每文档独立，共享有界历史预算） ----------
  final UndoHistoryBudget _undoHistoryBudget = UndoHistoryBudget();
  final NavigationHistory _navigationHistory = NavigationHistory();

  // ---------- 查找/替换 ----------
  bool _findVisible = false;
  bool _replaceVisible = false;

  // ---------- 搜索视图（feat-search） ----------
  final _searchQuery = TextEditingController();
  List<SearchHit> _searchHits = [];
  SearchHit? _selectedSearchHit;
  int _selectedSearchDocId = -1;
  int _selectedSearchDocVersion = -1;
  bool _searching = false;
  String? _searchBackendLabel;
  bool _searchCaseSensitive = false;
  StreamSubscription<SearchHit>? _searchSub;
  int _searchGen = 0;
  SearchService? _searchService;
  WorkspaceWatcher? _watcher;
  int _watcherGeneration = 0;
  Future<void> _watcherTransition = Future<void>.value();

  // ---------- 大纲视图（feat-outline） ----------
  final List<({String kind, String name, int startUtf16, int line})>
      _outlineSymbols = [];
  String _outlineDocKey = '';
  Timer? _outlineTimer;

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
  List<int> _findOverviewLines = const [];
  int _matchesDocId = -1;
  int _matchesDocVersion = -1;
  int _matchIndex = -1;
  bool _caseSensitive = false;

  String? _workspaceRoot;
  final List<TreeNode> _treeRoots = [];

  /// 编辑器组（W2-2）：region → 组；焦点组承载快捷键/保存/补全/新开文档。
  final Map<String, EditorGroup> _groups = {};
  final Map<
      int,
      ({EditorGroup group, OpenDoc view, int offset, Offset position})>
      _pendingDefinitionPointers = {};
  final Map<int, ({OpenDoc view, List<TextSelection> selections})>
      _pendingColumnSelectionStarts = {};
  String _focusedRegion = 'editor';
  int _syncCount = 0;
  int _abiVersion = 0;

  WbSyncState _state = WbSyncState.idle;
  bool _overtypeMode = false;
  bool _disposing = false;
  String _statusDetail = '初始化…';
  String? _journalRecoveryNotice;
  String? _journalSaveError;

  // LSP / 语法
  bool _lspStarting = false;
  bool _lspReady = false;
  String _lspStatus = 'LSP 未启动';
  final List<Map<String, Object?>> _diagnostics = [];
  Map<int, List<Map<String, Object?>>> _syntaxByDoc = {};
  Map<int, int> _syntaxVersionByDoc = {};
  Map<int, List<Map<String, Object?>>> _semanticTokensByDoc = {};
  Map<int, int> _semanticTokensVersionByDoc = {};
  final Map<int, Timer> _syntaxRefreshTimers = {};
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
    _keybindings =
        KeybindingSet.load(userJson: widget.keybindingsStore.tryLoadText());
    _registerCommands();
    _ensureGroupsFromLayout(); // 保存的布局可能含多个编辑器组
    if (!_groups.containsKey('editor')) {
      _groups['editor'] = EditorGroup('editor');
    }
    _initCore();
    _syncCommandContext();
    _commands.addListener(_onCommandServiceChanged);
  }

  /// 命令注册（W3-1）：菜单/键位/命令面板统一入口。
  void _registerCommands() {
    void reg(
        String id, String category, String title, Future<void> Function() run,
        {String? shortcut,
        String? when,
        String? enablement,
        Future<void> Function(Object? arguments)? runWithArguments}) {
      _commands.register(Command(
        id: id,
        category: category,
        title: title,
        run: run,
        shortcut: shortcut,
        when: when,
        enablement: enablement,
        runWithArguments: runWithArguments,
      ));
    }

    reg('file.openFolder', '文件', '打开文件夹…', _showOpenFolderDialog);
    reg('file.save', '文件', '保存', _saveActive,
        shortcut: 'Ctrl+S', enablement: 'editorActive');
    reg('file.saveAs', '文件', '另存为…', _saveAsActive,
        shortcut: 'Ctrl+Shift+S', enablement: 'editorActive');
    reg('file.revert', '文件', '从磁盘还原', _revertActive,
        enablement: 'editorActive');
    reg('file.saveWithEncoding', '文件', '使用编码保存…', _saveWithEncodingActive,
        enablement: 'editorActive');
    reg('file.reopenWithEncoding', '文件', '使用编码重新打开…', _reopenWithEncodingActive,
        enablement: 'editorActive');
    reg('file.selectEol', '文件', '选择行尾…', _selectLineEndingActive,
        enablement: 'editorActive');
    reg('view.commandPalette', '查看', '命令面板', () async => _showCommandPalette(),
        shortcut: 'Ctrl+Shift+P');
    reg('view.quickOpen', '查看', '快速打开文件…', () async => _showQuickOpen(),
        shortcut: 'Ctrl+P');
    reg('view.search', '查看', '全局搜索…', () async => _selectSidebarView('search'));
    reg('view.toggleSidebar', '查看', '切换侧栏',
        () async => _layout.toggleRegion('sidebar'),
        shortcut: 'Ctrl+B');
    reg('view.togglePanel', '查看', '切换面板',
        () async => _layout.toggleRegion('panel'),
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Cmd+J'
            : 'Ctrl+J');
    reg('view.quickInput', '查看', '命令面板', () async => _showCommandPalette());
    reg(
      'editor.action.toggleOvertypeInsertMode',
      '编辑器',
      '切换覆写/插入模式',
      () async => _toggleOvertypeInsertMode(),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Cmd+Alt+O'
          : 'Insert',
      enablement: 'editorTextFocus',
    );
    reg(
      'deleteWordLeft',
      '编辑器',
      '删除至词首',
      () => _deleteWord(left: true),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Alt+Backspace'
          : 'Ctrl+Backspace',
      enablement: 'editorTextFocus',
    );
    reg(
      'deleteWordRight',
      '编辑器',
      '删除至词尾',
      () => _deleteWord(left: false),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Alt+Delete'
          : 'Ctrl+Delete',
      enablement: 'editorTextFocus',
    );
    reg('editor.split', '编辑器', '拆分编辑器', () async => _splitFocusedGroup());
    reg(
      'deleteAllLeft',
      '编辑器',
      '删除至行首',
      () => _deleteAllToBoundary(left: true),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Cmd+Backspace'
          : null,
      enablement: 'editorTextFocus',
    );
    reg(
      'deleteAllRight',
      '编辑器',
      '删除至行尾',
      () => _deleteAllToBoundary(left: false),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Ctrl+K, Cmd+Delete'
          : null,
      enablement: 'editorTextFocus',
    );
    reg('editor.completion', '编辑器', '触发补全', _requestCompletion,
        shortcut: 'Ctrl+Space', enablement: 'editorActive && lspReady');
    reg('editor.verifyIntegrity', '编辑器', '校验一致性',
        () async => _verifyIntegrity(),
        enablement: 'editorActive');
    reg('editor.gotoDef', '编辑器', '跳转定义', () async => _gotoDefinition(),
        enablement: 'editorActive');
    reg('workbench.action.navigateBack', '导航', '后退', _navigateBack,
        shortcut: 'Alt+←');
    reg('workbench.action.navigateForward', '导航', '前进', _navigateForward,
        shortcut: 'Alt+→');
    reg('workbench.action.navigateToLastEditLocation', '导航', '转到上次编辑位置',
        _navigateToLastEdit);
    reg('view.outline', '查看', '大纲', () async => _selectSidebarView('outline'));
    reg('view.panelDiagnostics', '查看', '诊断面板',
        () async => _panelTab.animateTo(0));
    reg('view.panelCompletions', '查看', '补全面板',
        () async => _panelTab.animateTo(1));
    reg('view.panelSyntax', '查看', '语法面板', () async => _panelTab.animateTo(2));
    reg('editor.undo', '编辑器', '撤销', () async => _undo(),
        enablement: 'editorActive && editorCanUndo');
    reg('editor.redo', '编辑器', '重做', () async => _redo(),
        enablement: 'editorActive && editorCanRedo');
    reg('editor.find', '编辑器', '查找…', () async => _toggleFind(),
        enablement: 'editorActive');
    reg('editor.addCursorAbove', '编辑器', '向上添加光标',
        () async => _addCursorVertical(-1),
        shortcut: 'Ctrl+Alt+Up', enablement: 'editorTextFocus');
    reg('editor.addCursorBelow', '编辑器', '向下添加光标',
        () async => _addCursorVertical(1),
        shortcut: 'Ctrl+Alt+Down', enablement: 'editorTextFocus');
    reg('editor.selectNextOccurrence', '编辑器', '添加下一个匹配项',
        () async => _selectNextOccurrence(),
        shortcut:
            defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+D' : 'Ctrl+D',
        enablement: 'editorTextFocus');
    reg('editor.action.moveSelectionToNextFindMatch', '编辑器', '移动最后选区到下一个匹配项',
        () async => _moveLastSelectionToNextOccurrence(),
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Cmd+K Cmd+D'
            : 'Ctrl+K Ctrl+D',
        enablement: 'editorTextFocus');
    reg('editor.selectAllOccurrences', '编辑器', '选择所有匹配项',
        () async => _selectAllOccurrences(),
        shortcut: 'Ctrl+Shift+L', enablement: 'editorTextFocus');
    reg('editor.wordPartLeft', '编辑器', '向左移动子词',
        () async => _moveWordPart(left: true),
        enablement: 'editorTextFocus');
    reg('editor.wordPartLeftSelect', '编辑器', '向左扩展子词选择',
        () async => _moveWordPart(left: true, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.wordPartRight', '编辑器', '向右移动子词',
        () async => _moveWordPart(left: false),
        enablement: 'editorTextFocus');
    reg('editor.wordPartRightSelect', '编辑器', '向右扩展子词选择',
        () async => _moveWordPart(left: false, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorHome', '编辑器', '移至行首（缩进感知）',
        () async => _moveLineBoundary(toEnd: false),
        enablement: 'editorTextFocus');
    reg('editor.cursorHomeSelect', '编辑器', '选择至行首（缩进感知）',
        () async => _moveLineBoundary(toEnd: false, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorEnd', '编辑器', '移至行尾',
        () async => _moveLineBoundary(toEnd: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorEndSelect', '编辑器', '选择至行尾',
        () async => _moveLineBoundary(toEnd: true, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorTop', '编辑器', '移至文件开头',
        () async => _moveDocumentBoundary(toBottom: false),
        enablement: 'editorTextFocus');
    reg('editor.cursorTopSelect', '编辑器', '选择至文件开头',
        () async => _moveDocumentBoundary(toBottom: false, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorBottom', '编辑器', '移至文件末尾',
        () async => _moveDocumentBoundary(toBottom: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorBottomSelect', '编辑器', '选择至文件末尾',
        () async => _moveDocumentBoundary(toBottom: true, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorPageUp', '编辑器', '向上翻页',
        () async => _moveCursorPage(forward: false),
        shortcut: 'PageUp', enablement: 'editorTextFocus');
    reg('editor.cursorPageUpSelect', '编辑器', '向上翻页并扩展选择',
        () async => _moveCursorPage(forward: false, extendSelection: true),
        shortcut: 'Shift+PageUp', enablement: 'editorTextFocus');
    reg('editor.cursorPageDown', '编辑器', '向下翻页',
        () async => _moveCursorPage(forward: true),
        shortcut: 'PageDown', enablement: 'editorTextFocus');
    reg('editor.cursorPageDownSelect', '编辑器', '向下翻页并扩展选择',
        () async => _moveCursorPage(forward: true, extendSelection: true),
        shortcut: 'Shift+PageDown', enablement: 'editorTextFocus');
    reg('editor.mergeSelections', '编辑器', '合并重叠选区',
        () async => _mergeSelections(),
        enablement: 'editorTextFocus');
    reg('editor.columnSelectUp', '编辑器', '向上扩展列选择',
        () async => _moveColumnSelection(lines: -1),
        shortcut: defaultTargetPlatform == TargetPlatform.windows
            ? 'Ctrl+Alt+Shift+Up'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Alt+Shift+Up'
                : null,
        enablement: 'editorTextFocus');
    reg('editor.columnSelectDown', '编辑器', '向下扩展列选择',
        () async => _moveColumnSelection(lines: 1),
        shortcut: defaultTargetPlatform == TargetPlatform.windows
            ? 'Ctrl+Alt+Shift+Down'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Alt+Shift+Down'
                : null,
        enablement: 'editorTextFocus');
    reg('editor.columnSelectLeft', '编辑器', '向左扩展列选择',
        () async => _moveColumnSelection(columns: -1),
        shortcut: defaultTargetPlatform == TargetPlatform.windows
            ? 'Ctrl+Alt+Shift+Left'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Alt+Shift+Left'
                : null,
        enablement: 'editorTextFocus');
    reg('editor.columnSelectRight', '编辑器', '向右扩展列选择',
        () async => _moveColumnSelection(columns: 1),
        shortcut: defaultTargetPlatform == TargetPlatform.windows
            ? 'Ctrl+Alt+Shift+Right'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Alt+Shift+Right'
                : null,
        enablement: 'editorTextFocus');
    reg('editor.cursorUndo', '编辑器', '撤销光标移动', () async => _cursorUndo(),
        shortcut: 'Ctrl+U', enablement: 'editorTextFocus && cursorCanUndo');
    reg('editor.cursorRedo', '编辑器', '重做光标移动', () async => _cursorRedo(),
        shortcut: 'Ctrl+Shift+U',
        enablement: 'editorTextFocus && cursorCanRedo');
    reg(
      'editor.action.indentLines',
      '编辑器',
      '缩进选中行',
      () => _applyIndentation(tabOperation: false),
      shortcut:
          defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+]' : 'Ctrl+]',
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.outdentLines',
      '编辑器',
      '减少选中行缩进',
      () => _applyIndentation(outdent: true, tabOperation: false),
      shortcut:
          defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+[' : 'Ctrl+[',
      enablement: 'editorTextFocus',
    );
    reg('editor.action.insertLineBefore', '编辑器', '在上方插入行',
        () => _insertLine(before: true),
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Cmd+Shift+Enter'
            : 'Ctrl+Shift+Enter',
        enablement: 'editorTextFocus');
    reg('editor.action.insertLineAfter', '编辑器', '在下方插入行',
        () => _insertLine(before: false),
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Cmd+Enter'
            : 'Ctrl+Enter',
        enablement: 'editorTextFocus');
    reg('editor.action.deleteLines', '编辑器', '删除行', _deleteLines,
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Cmd+Shift+K'
            : 'Ctrl+Shift+K',
        enablement: 'editorTextFocus');
    reg('editor.action.copyLinesUpAction', '编辑器', '向上复制行',
        () => _copyLines(down: false),
        shortcut: defaultTargetPlatform == TargetPlatform.linux
            ? 'Ctrl+Alt+Shift+Up'
            : 'Alt+Shift+Up',
        enablement: 'editorTextFocus');
    reg('editor.action.copyLinesDownAction', '编辑器', '向下复制行',
        () => _copyLines(down: true),
        shortcut: defaultTargetPlatform == TargetPlatform.linux
            ? 'Ctrl+Alt+Shift+Down'
            : 'Alt+Shift+Down',
        enablement: 'editorTextFocus');
    reg('editor.action.moveLinesUpAction', '编辑器', '向上移动行',
        () => _moveLines(down: false),
        shortcut: 'Alt+Up', enablement: 'editorTextFocus');
    reg('editor.action.moveLinesDownAction', '编辑器', '向下移动行',
        () => _moveLines(down: true),
        shortcut: 'Alt+Down', enablement: 'editorTextFocus');
    reg('editor.action.sortLinesAscending', '编辑器', '按升序排序行',
        () => _sortLines(descending: false),
        enablement: 'editorTextFocus');
    reg('editor.action.sortLinesDescending', '编辑器', '按降序排序行',
        () => _sortLines(descending: true),
        enablement: 'editorTextFocus');
    reg('editor.action.removeDuplicateLines', '编辑器', '删除重复行',
        _removeDuplicateLines,
        enablement: 'editorTextFocus');
    reg('editor.action.transformToUppercase', '编辑器', '转换为大写',
        () => _transformCase(uppercase: true),
        enablement: 'editorTextFocus');
    reg('editor.action.transformToLowercase', '编辑器', '转换为小写',
        () => _transformCase(uppercase: false),
        enablement: 'editorTextFocus');
    reg('editor.action.transformToTitlecase', '编辑器', '转换为标题大小写',
        () => _transformCase(uppercase: false, titleCase: true),
        enablement: 'editorTextFocus');
    reg('editor.action.transformToCamelcase', '编辑器', '转换为驼峰命名',
        () => _transformCase(uppercase: false, camelCase: true),
        enablement: 'editorTextFocus');
    reg('editor.action.joinLines', '编辑器', '合并行', _joinLines,
        shortcut: defaultTargetPlatform == TargetPlatform.macOS ? 'Ctrl+J' : null,
        enablement: 'editorTextFocus');
    reg('editor.replace', '编辑器', '替换…', () async => _openReplace(),
        enablement: 'editorActive');
    reg('lsp.start', '语言服务', '启动 rust-analyzer', _startLsp,
        enablement: 'workspaceOpen && !lspStarting && !lspReady');
    reg('help.about', '帮助', '关于 Alula Code', () async => _showAbout());
  }

  /// 菜单项的键位提示后缀（用户 keybindings.json 重绑定后自动跟随）。
  String _sc(String commandId) {
    final sc = _keybindings.shortcutFor(commandId);
    return sc == null ? '' : '    $sc';
  }

  /// 执行命令（键位/菜单/面板统一出口）；未知 id（用户键位指向不存在的命令）
  /// 给状态栏提示而不是静默吞掉。
  void _runCommand(String id, {Object? arguments}) {
    unawaited(_commands.execute(id, arguments: arguments).then((status) {
      if (!mounted) return;
      if (status == CommandExecutionStatus.unknown) {
        setState(() => _statusDetail = '命令不存在：$id（检查 keybindings.json）');
      } else if (status == CommandExecutionStatus.disabled ||
          status == CommandExecutionStatus.hidden) {
        setState(() => _statusDetail = '命令当前不可用：$id');
      } else if (status == CommandExecutionStatus.unsupportedArguments) {
        setState(() => _statusDetail = '命令不接受参数：$id');
      }
    }));
  }

  Future<void> _deleteAllToBoundary({required bool left}) async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) {
        setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      }
      return;
    }

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '行边界删除已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentDeleteRanges queried;
    try {
      queried = doc.doc.lineDeleteRanges(
        selections
            .map((selection) => DocumentDeleteRange(
                  startUtf16: selection.start,
                  endUtf16: selection.end,
                ))
            .toList(growable: false),
        left: left,
      );
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '行边界删除失败：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion ||
        queried.ranges.length != selections.length) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) {
        setState(() => _statusDetail = '行边界删除未应用：文档同步版本已变化');
      }
      return;
    }

    final candidates = <({int start, int end})>[];
    for (final range in queried.ranges) {
      if (range.startUtf16 < range.endUtf16) {
        candidates.add((start: range.startUtf16, end: range.endUtf16));
      }
    }
    if (candidates.isEmpty) return;

    candidates.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end));
    final merged = <({int start, int end})>[];
    for (final range in candidates) {
      if (merged.isEmpty || range.start > merged.last.end) {
        merged.add(range);
      } else if (range.end > merged.last.end) {
        merged[merged.length - 1] = (start: merged.last.start, end: range.end);
      }
    }

    final deletedUtf16 = merged.fold<int>(
      0,
      (total, range) => total + range.end - range.start,
    );
    if (deletedUtf16 > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '行边界删除已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    final plans = <({int start, int end, String removed, int mappedStart})>[];
    var removedBefore = 0;
    try {
      for (final range in merged) {
        plans.add((
          start: range.start,
          end: range.end,
          removed: _readDocumentRange(doc, range.start, range.end),
          mappedStart: range.start - removedBefore,
        ));
        removedBefore += range.end - range.start;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '行边界删除未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '行边界删除未应用：文档版本已变化');
      return;
    }

    final forward = [
      for (final plan in plans.reversed)
        TextOp.delete(plan.start, plan.end - plan.start),
    ];
    final inverse = [
      for (final plan in plans.reversed)
        TextOp.insert(plan.mappedStart, plan.removed),
    ];
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '行边界删除未应用：${error.code} ${error.detail}');
      }
      return;
    }

    int mapOffset(int offset) {
      var removed = 0;
      for (final plan in plans) {
        if (offset < plan.start) break;
        if (offset <= plan.end) return plan.start - removed;
        removed += plan.end - plan.start;
      }
      return offset - removed;
    }

    final newLength = doc.inputWindow.totalUtf16Length - deletedUtf16;
    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection(
          baseOffset:
              mapOffset(selection.baseOffset).clamp(0, newLength).toInt(),
          extentOffset:
              mapOffset(selection.extentOffset).clamp(0, newLength).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    final beforeCaret = selections.first.extentOffset;
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: beforeCaret,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(() => _statusDetail = left ? '已删除至行首' : '已删除至行尾');
    }
  }


  void _syncCommandContext() {
    final active = _active;
    _commands.context.setValues({
      'editorActive': active != null,
      'editorDirty': active?.isDirty ?? false,
      'editorTextFocus': active != null && _isEditorRegion(_focusedRegion),
      'editorCanUndo': active?.undoStack.canUndo ?? false,
      'editorCanRedo': active?.undoStack.canRedo ?? false,
      'cursorCanUndo': active?.selectionHistory.canUndo ?? false,
      'cursorCanRedo': active?.selectionHistory.canRedo ?? false,
      'workspaceOpen': _workspaceRoot != null,
      'lspStarting': _lspStarting,
      'lspReady': _lspReady,
    });
  }

  void _onCommandServiceChanged() {
    if (mounted) setState(() {});
  }

  void _toggleOvertypeInsertMode() {
    final active = _active;
    if (active == null) return;
    active.clearPendingOvertypeInput();
    _flushInput(active, commitComposition: true);
    if (!mounted) return;
    setState(() {
      _overtypeMode = !_overtypeMode;
      _statusDetail = _overtypeMode ? '覆写模式' : '插入模式';
    });
  }

  Future<void> _deleteWord({required bool left}) async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) {
        setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      }
      return;
    }
    if (doc.crossWindowSelection != null) {
      _replaceCrossWindowSelection(doc, '');
      return;
    }

    _flushInput(doc);
    final selections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (selections.length > maxDocWordDeleteCarets) {
      if (mounted) {
        setState(
            () => _statusDetail = '单词删除已取消：光标数超过 $maxDocWordDeleteCarets 上限');
      }
      return;
    }

    final collapsed = selections.where((item) => item.isCollapsed).toList();
    final expectedVersion = doc.doc.version;
    late final DocumentDeleteRanges queried;
    try {
      queried = doc.doc.wordDeleteRanges(
        collapsed.map((item) => item.extentOffset).toList(growable: false),
        left: left,
      );
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '单词删除失败：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) {
        setState(() => _statusDetail = '单词删除未应用：文档同步版本已变化');
      }
      return;
    }

    var collapsedIndex = 0;
    final candidates = <({int start, int end})>[];
    for (final selection in selections) {
      if (selection.isCollapsed) {
        final range = queried.ranges[collapsedIndex++];
        if (range.startUtf16 < range.endUtf16) {
          candidates.add((start: range.startUtf16, end: range.endUtf16));
        }
      } else {
        candidates.add((start: selection.start, end: selection.end));
      }
    }
    if (candidates.isEmpty) return;

    candidates.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end));
    final merged = <({int start, int end})>[];
    for (final range in candidates) {
      if (merged.isEmpty || range.start > merged.last.end) {
        merged.add(range);
      } else if (range.end > merged.last.end) {
        merged[merged.length - 1] = (
          start: merged.last.start,
          end: range.end,
        );
      }
    }

    final deletedUtf16 = merged.fold<int>(
      0,
      (total, range) => total + range.end - range.start,
    );
    if (deletedUtf16 > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '单词删除已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    final plans = <({int start, int end, String removed, int mappedStart})>[];
    var removedBefore = 0;
    try {
      for (final range in merged) {
        plans.add((
          start: range.start,
          end: range.end,
          removed: _readDocumentRange(doc, range.start, range.end),
          mappedStart: range.start - removedBefore,
        ));
        removedBefore += range.end - range.start;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '单词删除未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '单词删除未应用：文档版本已变化');
      return;
    }

    final forward = [
      for (final plan in plans.reversed)
        TextOp.delete(plan.start, plan.end - plan.start),
    ];
    final inverse = [
      for (final plan in plans.reversed)
        TextOp.insert(plan.mappedStart, plan.removed),
    ];
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '单词删除未应用：${error.code} ${error.detail}');
      }
      return;
    }

    int mapOffset(int offset) {
      var removed = 0;
      for (final plan in plans) {
        if (offset < plan.start) break;
        if (offset <= plan.end) return plan.start - removed;
        removed += plan.end - plan.start;
      }
      return offset - removed;
    }

    final newLength = doc.inputWindow.totalUtf16Length - deletedUtf16;
    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection(
          baseOffset:
              mapOffset(selection.baseOffset).clamp(0, newLength).toInt(),
          extentOffset:
              mapOffset(selection.extentOffset).clamp(0, newLength).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    final beforeCaret = selections.first.extentOffset;
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: beforeCaret,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(() => _statusDetail = left ? '已删除至词首' : '已删除至词尾');
    }
  }

  void _showCommandPalette() {
    QuickInput.show(
      context,
      hint: '输入命令名（> 前缀可省）',
      items: [
        for (final c in _commands.all)
          QuickItem(label: c.label, detail: c.shortcut, commandId: c.id),
      ],
      commands: _commands,
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
      final saved = widget.sessionStore.save(_encodeSession());
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _journalSaveError = '会话 journal 写入失败；未保存编辑仍在内存中，请尽快保存文档。'
              '${widget.sessionStore.lastSaveError ?? ''}';
        });
      } else if (_journalSaveError != null) {
        setState(() => _journalSaveError = null);
      }
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
                    'fileOptions': d.fileOptions.toJson(),
                    'savedFileOptions': d.savedFileOptions.toJson(),
                    if (d.isUntitled || d.isDirty)
                      'text': d.doc.resync().content,
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
        const welcome = '// Alula Code\n// 打开一个文件夹开始工作，或在此处体验编辑同步。\n';
        final doc = core.openDoc(_untitledId, welcome);
        final untitled = OpenDoc(
          id: _untitledId,
          name: '未命名',
          doc: doc,
          undoBudget: _undoHistoryBudget,
        );
        g.docs.add(untitled);
        _scheduleStateSave();
      }
      if (g.activeDocId == null && g.docs.isNotEmpty) {
        g.activeDocId = g.docs.last.id;
      }
      for (final doc in _allDocs) {
        if (doc.path?.toLowerCase().endsWith('.rs') == true) {
          _scheduleSyntaxRefresh(doc.id);
        }
      }
      _state = WbSyncState.idle;
      _statusDetail = _journalRecoveryNotice ?? '已连接 Rust 核心 v$_abiVersion';
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
        Future<void>.delayed(const Duration(milliseconds: 50), _startLsp);
      }
      if (_workspaceRoot != null && _resourceTimer == null) {
        _startResourceMonitoring();
      }
    } catch (e) {
      _loadError = e.toString();
      _state = WbSyncState.error;
      _statusDetail = '核心加载失败';
    }
  }

  /// 恢复上次会话（W2-4）：组/标签/焦点/工作区 + 未保存文本。
  /// 带路径的 journal 文本与当前磁盘不同时保留两侧并要求显式处理；旧 journal
  /// 没有已保存基线时也采取保守冲突提示，避免首次 Ctrl+S 静默覆盖磁盘。
  /// journal 损坏一律按全新会话启动。
  void _restoreSession(AlulaCore core) {
    final data = widget.sessionStore.tryLoad();
    _journalRecoveryNotice = switch (widget.sessionStore.lastLoadStatus) {
      SessionLoadStatus.recoveredFromBackup =>
        '会话 journal 主文件不可用，已从上一个有效备份恢复；最近一次会话状态可能不完整。',
      SessionLoadStatus.recoveredFromTemporary =>
        '检测到上次保存被中断，已从校验通过的临时 journal 恢复。',
      SessionLoadStatus.invalid =>
        '会话 journal 和备份均无法校验；未保存文本可能无法恢复，现有文件已从磁盘打开。',
      SessionLoadStatus.unsupportedVersion => '会话 journal 版本不受支持，未载入其中的未保存文本。',
      SessionLoadStatus.notFound ||
      SessionLoadStatus.loaded ||
      SessionLoadStatus.legacy =>
        null,
    };
    if (data == null) return;
    try {
      final groupsRaw = data['groups'];
      if (groupsRaw is! List) return;
      var maxId = 1;
      final restoredDocuments = <int, OpenDoc>{};
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
          final existing = restoredDocuments[id];
          if (existing != null) {
            final optionsRaw = dr['fileOptions'];
            final duplicateOptions = optionsRaw is Map
                ? TextFileOptions.fromJson(
                    Map<String, Object?>.from(optionsRaw),
                  )
                : existing.fileOptions;
            if (existing.path != path ||
                (text != null && text != existing.text) ||
                duplicateOptions != existing.fileOptions) {
              var recoveryText = text;
              var recoveryOptions = duplicateOptions;
              if (recoveryText == null && path != null) {
                try {
                  final disk = _readDiskDocument(core, path);
                  recoveryText = disk.content;
                  recoveryOptions = disk.options;
                } on AlulaException {
                  // Fall back to the first same-id copy if this path vanished.
                }
              }
              recoveryText ??= existing.text;
              final recoveryId = ++maxId;
              final recoveryCoreDoc = core.openDoc(recoveryId, recoveryText);
              recoveryCoreDoc.setSavepoint('');
              final recovery = OpenDoc(
                id: recoveryId,
                name: '恢复副本（${path == null ? existing.name : _nameOf(path)}）',
                doc: recoveryCoreDoc,
                fileOptions: recoveryOptions,
                savedFileOptions: recoveryOptions,
                dirtyDisk: true,
                undoBudget: _undoHistoryBudget,
              );
              target.docs.add(recovery);
              _journalRecoveryNotice = '会话中的同文档副本内容或文件设置冲突；已将冲突内容保留为未命名恢复副本。';
              continue;
            }
            target.docs.add(OpenDoc.viewOf(existing));
            if (id > maxId) maxId = id;
            continue;
          }
          String? content;
          String savedText;
          var fileOptions = TextFileOptions.defaults;
          var savedFileOptions = TextFileOptions.defaults;
          var diskState = DiskDocumentState.current;
          var conflictBaselineKnown = true;
          DecodedTextFile? diskFile;
          Map<String, Object?>? journalOptions;
          Map<String, Object?>? journalSavedOptions;
          // journal 文本保留本地编辑；磁盘文本作为当前可验证的 savepoint。
          if (path != null) {
            final optionsRaw = dr['fileOptions'];
            journalOptions = optionsRaw is Map
                ? Map<String, Object?>.from(optionsRaw)
                : null;
            final savedOptionsRaw = dr['savedFileOptions'];
            journalSavedOptions = savedOptionsRaw is Map
                ? Map<String, Object?>.from(savedOptionsRaw)
                : null;
            try {
              final options = journalOptions == null
                  ? null
                  : TextFileOptions.fromJson(journalOptions);
              diskFile = _readDiskDocument(
                core,
                path,
                preferredEncoding: options?.encoding,
              );
            } on AlulaException catch (error) {
              diskFile = null;
              diskState = error.code == 'NotFound'
                  ? DiskDocumentState.missing
                  : DiskDocumentState.unavailable;
            }
            if (text != null) {
              content = text;
            } else if (diskFile != null) {
              content = diskFile.content;
            } else {
              continue;
            }
            final priorSavedFileOptions = journalSavedOptions == null
                ? diskFile?.options ?? TextFileOptions.defaults
                : TextFileOptions.fromJson(journalSavedOptions);
            savedFileOptions = diskFile?.options ?? priorSavedFileOptions;
            fileOptions = text != null && journalOptions != null
                ? TextFileOptions.fromJson(journalOptions)
                : diskFile?.options ?? savedFileOptions;
            final optionsDifferFromDisk = fileOptions != diskFile?.options;
            final savedOptionsDifferFromDisk = journalSavedOptions == null ||
                priorSavedFileOptions != diskFile?.options;
            if (diskFile != null &&
                (content != diskFile.content ||
                    optionsDifferFromDisk && savedOptionsDifferFromDisk)) {
              diskState = DiskDocumentState.conflict;
              conflictBaselineKnown = false;
            }
          } else {
            if (text == null) continue; // untitled 缺 journal 文本：跳过
            content = text;
            final optionsRaw = dr['fileOptions'];
            if (optionsRaw is Map) {
              fileOptions = TextFileOptions.fromJson(
                Map<String, Object?>.from(optionsRaw),
              );
            }
            savedFileOptions = fileOptions;
          }
          savedText = diskFile?.content ?? content;
          final doc = core.openDoc(id, content);
          if (savedText != content) doc.setSavepoint(savedText);
          final name = path != null ? _nameOf(path) : '未命名';
          final open = OpenDoc(
            id: id,
            path: path,
            uri: path != null ? _pathToUri(path) : null,
            name: name,
            doc: doc,
            fileOptions: fileOptions,
            savedFileOptions: savedFileOptions,
            dirtyDisk: path == null
                ? false
                : diskFile == null ||
                    content != diskFile.content ||
                    fileOptions != diskFile.options,
            diskState: diskState,
            conflictBaselineKnown: conflictBaselineKnown,
            undoBudget: _undoHistoryBudget,
          );
          target.docs.add(open);
          restoredDocuments[id] = open;
          if (id > maxId) maxId = id;
        }
        final active = (gr['active'] as num?)?.toInt();
        if (target.docs.isNotEmpty) {
          target.activeDocId = target.docs.any((d) => d.id == active)
              ? active
              : target.docs.last.id;
        }
      }
      final focused = data['focused'];
      if (focused is String && _groups.containsKey(focused)) {
        _focusedRegion = focused;
      }
      final workspace = data['workspace'];
      if (workspace is String && Directory(workspace).existsSync()) {
        _workspaceRoot = workspace;
        _git = GitCli(
          root: workspace,
          registerProcess: core.runtime.registerProcess,
          unregisterProcess: core.runtime.unregisterProcess,
        );
        _searchService = SearchService(
          root: workspace,
          registerProcess: core.runtime.registerProcess,
          unregisterProcess: core.runtime.unregisterProcess,
        );
        _attachWorkspaceWatcher();
      }
      _nextDocId = maxId + 1;
    } catch (_) {
      // journal 损坏：忽略（组状态保持空，按全新会话继续）
    }
  }

  String _nameOf(String path) => path.replaceAll('\\', '/').split('/').last;

  DecodedTextFile _readDiskDocument(
    AlulaCore core,
    String path, {
    TextEncoding? preferredEncoding,
  }) {
    if (preferredEncoding != TextEncoding.utf16Le &&
        preferredEncoding != TextEncoding.utf16Be) {
      return core.workspace.readFileDocument(path);
    }
    try {
      return core.workspace.readFileDocument(
        path,
        encoding: preferredEncoding,
      );
    } on AlulaException {
      return core.workspace.readFileDocument(path);
    }
  }

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
  EditorGroup get _focused => _groups[_focusedRegion] ?? _groups.values.first;

  OpenDoc? get _active => _focused.active;

  Iterable<OpenDoc> get _allDocViews sync* {
    for (final g in _groups.values) {
      yield* g.docs;
    }
  }

  /// One representative per Rust document, for document-scoped services.
  Iterable<OpenDoc> get _allDocs sync* {
    final seen = <Object>{};
    for (final view in _allDocViews) {
      if (seen.add(view._shared)) yield view;
    }
  }

  Iterable<OpenDoc> _viewsOf(OpenDoc document) sync* {
    for (final view in _allDocViews) {
      if (view.sameDocumentAs(document)) yield view;
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

  EditorGroup? _ownerOfView(OpenDoc view) {
    for (final g in _groups.values) {
      if (g.docs.any((candidate) => identical(candidate, view))) return g;
    }
    return null;
  }

  bool _isEditorRegion(String r) => r == 'editor' || r.startsWith('editor-');

  String _editorSemanticsLabel(EditorGroup group, OpenDoc doc) {
    if (group.region == 'editor') return '${doc.name} 主编辑器';
    final ordinal = group.region.startsWith('editor-')
        ? group.region.substring('editor-'.length)
        : group.region;
    return '${doc.name} 编辑器 $ordinal';
  }

  /// 布局树里的编辑器叶子 ↔ 组状态对齐（启动恢复/拆分后调用）。
  void _ensureGroupsFromLayout() {
    for (final l in _layout.root.leaves) {
      if (_isEditorRegion(l.region) && !_groups.containsKey(l.region)) {
        _groups[l.region] = EditorGroup(l.region);
      }
    }
  }

  // ---------- 编辑同步 ----------

  void _updateDirty(OpenDoc doc) {
    doc.dirtyDisk = doc.doc.isDirty ||
        doc.fileOptions != doc.savedFileOptions ||
        doc.path != null &&
            (doc.diskState == DiskDocumentState.missing ||
                doc.diskState == DiskDocumentState.unavailable);
  }

  void _flushInput(OpenDoc doc, {bool commitComposition = false}) {
    final field = doc.inputFieldKey.currentState;
    if (field != null) {
      if (commitComposition) {
        field.commitComposition();
      } else {
        field.flushPending();
      }
      return;
    }
    final delta = commitComposition
        ? doc.inputWindow.commitComposition()
        : doc.inputWindow.flushPending();
    if (delta != null) _onInputDelta(doc, delta);
  }

  void _recordDocumentOperations(
    OpenDoc doc, {
    required List<TextOp> forward,
    required List<TextOp> inverse,
    required int beforeCaret,
    required int afterCaret,
    required bool coalesce,
    String? beforeSnapshot,
    String? transactionId,
  }) {
    if (forward.isNotEmpty) doc.crossWindowSelection = null;
    if (forward.isNotEmpty) doc.remapAutoClosedBracketMarkers(forward);
    final retainedOperationChars = _operationPayloadChars([forward, inverse]);
    if (beforeSnapshot != null &&
        retainedOperationChars > _undoHistoryBudget.maxTotalChars) {
      // A whole-document replacement can need more memory as two directional
      // delta payloads than the existing history budget allows. Keep its
      // pre-edit state as the single bounded legacy frame instead.
      doc.undoStack.push(
        before: beforeSnapshot,
        caret: beforeCaret,
        coalesce: false,
        encoding: doc.fileOptions.encoding.id,
        bom: doc.fileOptions.bom,
        lineEnding: doc.fileOptions.lineEnding.id,
        transactionId: transactionId,
      );
    } else {
      doc.undoStack.pushOperations(
        forward: forward,
        inverse: inverse,
        caret: beforeCaret,
        redoCaret: afterCaret,
        coalesce: coalesce,
        encoding: doc.fileOptions.encoding.id,
        bom: doc.fileOptions.bom,
        lineEnding: doc.fileOptions.lineEnding.id,
        transactionId: transactionId,
      );
    }
    if (forward.isNotEmpty && !coalesce) {
      final owner = _ownerOfView(doc);
      if (owner != null) {
        try {
          final offset =
              beforeCaret.clamp(0, doc.inputWindow.totalUtf16Length).toInt();
          _navigationHistory.recordEdit(
            _navigationLocation(doc, offset, owner.region),
          );
        } on AlulaException {
          // A stale edit caret is not allowed to interrupt the edit path.
        }
      }
    }
    doc.lastEditAt = coalesce ? DateTime.now() : null;
    _updateDirty(doc);
    if (_disposing) return;
    if (_active?.id == doc.id) _syncCommandContext();
    if (forward.isNotEmpty) {
      _scheduleStateSave();
      _scheduleOutlineRefresh();
      _scheduleSyntaxRefresh(doc.id);
    }
  }

  void _setDocSelection(OpenDoc doc, TextSelection selection) =>
      _setDocSelections(doc, [selection]);

  void _setCrossWindowLineSelection(OpenDoc doc, TextSelection selection) {
    final window = doc.inputWindow;
    if (window.pendingText != null && window.pendingText != window.text ||
        window.version != doc.doc.version ||
        selection.start < 0 ||
        selection.end > window.totalUtf16Length ||
        selection.start == selection.end) {
      return;
    }
    doc.selectionHistory.record(doc.selectionSet);
    doc.crossWindowSelection = selection;
    doc.additionalSelections = const [];
    doc.columnSelection = null;
    // Keep a bounded caret well inside the selected line so the input window
    // has room for IME preedit text on either side. The pointer handler must
    // leave this new window's selection intact after this callback returns.
    final compositionCaret = (selection.start + window.maxWindowUtf16 ~/ 2 + 1)
        .clamp(0, window.totalUtf16Length)
        .toInt();
    doc.replaceInputWindow(
      compositionCaret,
      selection: TextSelection.collapsed(offset: compositionCaret),
    );
    if (mounted) setState(() {});
    _syncCommandContext();
  }

  void _setCrossWindowDragSelection(
    OpenDoc doc,
    TextSelection selection, {
    required bool started,
  }) {
    final window = doc.inputWindow;
    if (window.pendingText != null && window.pendingText != window.text ||
        window.version != doc.doc.version ||
        selection.start < 0 ||
        selection.end > window.totalUtf16Length ||
        selection.isCollapsed) {
      return;
    }
    if (started) {
      doc.selectionHistory.record(doc.selectionSet);
      doc.additionalSelections = const [];
      doc.columnSelection = null;
    }
    doc.crossWindowSelection = selection;
    const rewindowMarginUtf16 = 2048;
    final extent = selection.extentOffset;
    final hasDocumentTextBeyondExtent =
        extent > 0 && extent < window.totalUtf16Length;
    if (hasDocumentTextBeyondExtent &&
        (started ||
            extent <= window.startUtf16 + rewindowMarginUtf16 ||
            extent >= window.endUtf16 - rewindowMarginUtf16)) {
      _flushInput(doc);
      final currentWindow = doc.inputWindow;
      if (extent <= currentWindow.startUtf16 + rewindowMarginUtf16 ||
          extent >= currentWindow.endUtf16 - rewindowMarginUtf16) {
        doc.replaceInputWindow(
          extent,
          selection: TextSelection.collapsed(offset: extent),
        );
      }
    }
    if (mounted) setState(() {});
    _syncCommandContext();
  }

  void _moveWordPart({required bool left, bool extendSelection = false}) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final current = doc.selection;
    if (!extendSelection && !current.isCollapsed) {
      _setDocSelection(
        doc,
        TextSelection.collapsed(offset: left ? current.start : current.end),
      );
      return;
    }
    final destination = doc.doc.wordPartOffset(
      current.extentOffset,
      left: left,
    );
    final next = extendSelection
        ? TextSelection(
            baseOffset: current.baseOffset,
            extentOffset: destination,
            affinity: current.affinity,
            isDirectional: current.isDirectional,
          )
        : TextSelection.collapsed(offset: destination, affinity: current.affinity);
    if (next != current) _setDocSelection(doc, next);
  }

  void _moveLineBoundary({required bool toEnd, bool extendSelection = false}) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final current = doc.selection;
    final boundary = doc.doc.lineBoundary(current.extentOffset);
    final destination = toEnd
        ? boundary.endUtf16
        : boundary.firstNonWhitespaceUtf16 != boundary.startUtf16 &&
                current.extentOffset == boundary.firstNonWhitespaceUtf16
            ? boundary.startUtf16
            : boundary.firstNonWhitespaceUtf16;
    final next = extendSelection
        ? TextSelection(
            baseOffset: current.baseOffset,
            extentOffset: destination,
            affinity: current.affinity,
            isDirectional: current.isDirectional,
          )
        : TextSelection.collapsed(
            offset: destination,
            affinity: current.affinity,
          );
    if (next != current) _setDocSelection(doc, next);
  }

  void _moveDocumentBoundary({
    required bool toBottom,
    bool extendSelection = false,
  }) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final current = doc.selection;
    final destination = toBottom ? doc.inputWindow.totalUtf16Length : 0;
    final next = extendSelection
        ? TextSelection(
            baseOffset: current.baseOffset,
            extentOffset: destination,
            affinity: current.affinity,
            isDirectional: current.isDirectional,
          )
        : TextSelection.collapsed(
            offset: destination,
            affinity: current.affinity,
          );
    if (next != current) _setDocSelection(doc, next);
  }

  void _moveCursorPage({
    required bool forward,
    bool extendSelection = false,
  }) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final context = _focusNodeFor(_focused, doc).context;
    if (context == null) return;
    Actions.invoke(
      context,
      ExtendSelectionVerticallyToAdjacentPageIntent(
        forward: forward,
        collapseSelection: !extendSelection,
      ),
    );
  }

  void _setDocSelections(
    OpenDoc doc,
    List<TextSelection> selections, {
    ColumnSelectionState? columnSelection,
    bool recordHistory = true,
  }) {
    _flushInput(doc);
    final total = doc.inputWindow.totalUtf16Length;
    final clampedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection(
          baseOffset: selection.baseOffset.clamp(0, total).toInt(),
          extentOffset: selection.extentOffset.clamp(0, total).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    if (clampedSelections.isEmpty) return;
    final previousSet = doc.selectionSet;
    if (recordHistory) doc.selectionHistory.record(previousSet);
    doc.crossWindowSelection = null;
    final oldAdditional = doc.additionalSelections;
    doc.additionalSelections = List.unmodifiable(clampedSelections.skip(1));
    doc.columnSelection = columnSelection;
    final clamped = clampedSelections.first;
    final window = doc.inputWindow;
    final start = window.startUtf16;
    final end = window.endUtf16;
    final field = doc.inputFieldKey.currentState;
    if (clamped.baseOffset >= start &&
        clamped.baseOffset <= end &&
        clamped.extentOffset >= start &&
        clamped.extentOffset <= end &&
        field != null) {
      field.setSelection(TextSelection(
        baseOffset: clamped.baseOffset - start,
        extentOffset: clamped.extentOffset - start,
        affinity: clamped.affinity,
        isDirectional: clamped.isDirectional,
      ));
      if (mounted &&
          (!listEquals(oldAdditional, doc.additionalSelections) ||
              previousSet.first != clamped)) {
        setState(() {});
      }
      _syncCommandContext();
      return;
    }
    doc.replaceInputWindow(clamped.extentOffset, selection: clamped);
    doc.columnSelection = columnSelection;
    if (mounted) setState(() {});
    _syncCommandContext();
  }

  List<TextSelection> _localAdditionalSelections(OpenDoc doc) {
    final window = doc.inputWindow;
    final source = window.text;
    final candidates = doc.additionalSelections.where((selection) {
      final base = selection.baseOffset - window.startUtf16;
      final extent = selection.extentOffset - window.startUtf16;
      return base >= 0 &&
          extent >= 0 &&
          base <= source.length &&
          extent <= source.length;
    }).toList(growable: false);
    final mapped = mapOffsetsThroughTextChange(
      source,
      window.presentedText,
      candidates
          .expand((selection) => [
                selection.baseOffset - window.startUtf16,
                selection.extentOffset - window.startUtf16,
              ])
          .toList(growable: false),
    );
    return List.unmodifiable([
      for (var i = 0; i < candidates.length; i++)
        TextSelection(
          baseOffset: mapped[i * 2],
          extentOffset: mapped[i * 2 + 1],
          affinity: candidates[i].affinity,
          isDirectional: candidates[i].isDirectional,
        ),
    ]);
  }

  List<TextSelection> _absoluteSelections(
    OpenDoc doc,
    List<TextSelection> localSelections,
  ) =>
      localSelections
          .map((selection) => TextSelection(
                baseOffset: doc.inputWindow.startUtf16 + selection.baseOffset,
                extentOffset:
                    doc.inputWindow.startUtf16 + selection.extentOffset,
                affinity: selection.affinity,
                isDirectional: selection.isDirectional,
              ))
          .toList(growable: false);

  void _addCursorVertical(int lineDelta) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final currentSelections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (currentSelections.isEmpty) return;

    try {
      final caret = doc.selection.extentOffset;
      final currentLine = doc.doc.lineBoundary(caret);
      final firstLine = doc.doc.lineOffset(0);
      final targetLineNumber = (currentLine.line + lineDelta)
          .clamp(0, firstLine.lineCount - 1)
          .toInt();
      final targetLine = doc.doc.lineOffset(targetLineNumber);
      final targetBoundary = doc.doc.lineBoundary(targetLine.offsetUtf16);
      final column = (caret - currentLine.startUtf16)
          .clamp(0, currentLine.endUtf16 - currentLine.startUtf16)
          .toInt();
      final targetColumn = column
          .clamp(0, targetBoundary.endUtf16 - targetBoundary.startUtf16)
          .toInt();
      final desiredTarget = targetBoundary.startUtf16 + targetColumn;

      // Keep the target's grapheme context bounded even on a very long line.
      // For ordinary lines this reads from the line start; for long lines it
      // reads at most 64 Ki UTF-16 units around the desired column.
      final contextStart =
          desiredTarget - targetBoundary.startUtf16 > maxDocReadRangeUtf16
              ? desiredTarget - maxDocReadRangeUtf16 ~/ 2
              : targetBoundary.startUtf16;
      final available = doc.inputWindow.totalUtf16Length - contextStart;
      if (available <= 0) return;
      final range = doc.doc.readRange(
        contextStart,
        maxLenUtf16: available.clamp(1, maxDocReadRangeUtf16).toInt(),
      );
      final localTarget = desiredTarget - range.startUtf16;
      if (localTarget < 0 || localTarget > range.text.length) return;

      // Snap the candidate before asking Rust to validate it, because the
      // desired UTF-16 column can otherwise land inside a surrogate pair.
      final target = range.startUtf16 +
          lineOffsetAtColumn(
            range.text,
            0,
            localTarget,
          );
      // Rust rejects offsets inside surrogate pairs.
      doc.doc.lineBoundary(target);
      final next = TextSelection.collapsed(offset: target);
      final window = doc.inputWindow;
      if (target < window.startUtf16 || target > window.endUtf16) {
        // Moving the new caret opens the correct input window while retaining
        // previous cursors, including those that are remote from that window.
        _setDocSelections(doc, [next, ...currentSelections]);
      } else {
        _setDocSelections(doc, [...currentSelections, next]);
      }
    } on AlulaException {
      // A stale or invalid Rust position must not create a split-scalar caret.
    } on RangeError {
      // Keep the current selections if the document changed during lookup.
    }
  }

  String? _selectedOccurrenceNeedle(OpenDoc doc) {
    final selection = doc.selection;
    final start = selection.baseOffset < selection.extentOffset
        ? selection.baseOffset
        : selection.extentOffset;
    final end = selection.baseOffset < selection.extentOffset
        ? selection.extentOffset
        : selection.baseOffset;
    final window = doc.inputWindow;
    final localStart = start - window.startUtf16;
    final localEnd = end - window.startUtf16;
    final text = doc.editingValue.text;
    if (start == end ||
        localStart < 0 ||
        localEnd > text.length ||
        localStart >= localEnd ||
        !_isUtf16CodePointBoundary(text, localStart) ||
        !_isUtf16CodePointBoundary(text, localEnd)) {
      return null;
    }
    return text.substring(localStart, localEnd);
  }

  bool _isUtf16CodePointBoundary(String text, int offset) {
    if (offset < 0 || offset > text.length) return false;
    if (offset == 0 || offset == text.length) return true;
    final previous = text.codeUnitAt(offset - 1);
    final next = text.codeUnitAt(offset);
    return !(previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF);
  }

  bool _selectionOverlapsMatch(TextSelection selection, int start, int end) {
    final low = selection.baseOffset < selection.extentOffset
        ? selection.baseOffset
        : selection.extentOffset;
    final high = selection.baseOffset < selection.extentOffset
        ? selection.extentOffset
        : selection.baseOffset;
    if (low == high) return low >= start && low < end;
    return low < end && high > start;
  }

  int? _nextUnselectedOccurrence(
    OpenDoc doc, {
    required String needle,
    required int startAfterUtf16,
    required List<TextSelection> existingSelections,
  }) {
    final total = doc.inputWindow.totalUtf16Length;
    final startAfter = startAfterUtf16.clamp(0, total).toInt();
    int? found;

    void scanRange(int start, int end) {
      if (found != null) return;
      for (final offset in findTextOccurrenceOffsets(
        needle: needle,
        totalUtf16Length: total,
        startUtf16: start,
        endUtf16: end,
        readRange: doc.doc.readRange,
      )) {
        final matchEnd = offset + needle.length;
        if (existingSelections.any(
          (selection) => _selectionOverlapsMatch(selection, offset, matchEnd),
        )) {
          continue;
        }
        found = offset;
        return;
      }
    }

    scanRange(startAfter, total);
    scanRange(0, startAfter);
    return found;
  }

  (int, int)? _remoteCaretDeletionRange(
    OpenDoc doc,
    int caret, {
    required bool backwards,
  }) {
    final total = doc.inputWindow.totalUtf16Length;
    if (backwards) {
      var start = (caret - maxDocReadRangeUtf16 + 1).clamp(0, caret).toInt();
      TextRangeRead range;
      while (true) {
        try {
          range = doc.doc.readRange(
            start,
            maxLenUtf16: caret - start,
          );
          break;
        } on AlulaException catch (error) {
          if (error.code != 'InvalidUtf16Offset' || start == 0) rethrow;
          start--;
        }
      }
      final boundary = previousGraphemeBoundary(
        range.text,
        caret - range.startUtf16,
      );
      if (boundary == 0 && range.startUtf16 > 0) return null;
      return (range.startUtf16 + boundary, caret);
    }

    if (caret >= total) return null;
    final range = doc.doc.readRange(
      caret,
      maxLenUtf16: (total - caret).clamp(1, maxDocReadRangeUtf16).toInt(),
    );
    final boundary = nextGraphemeBoundary(range.text, 0);
    if (boundary == range.text.length && range.endUtf16 < total) return null;
    return (caret, caret + boundary);
  }

  void _prepareRemoteMultiSelectionEdits(
    OpenDoc doc,
    TextEditingValue oldValue,
    TextEditingValue newValue,
    TextEditingValue formattedValue,
  ) {
    final windowStart = doc.inputWindow.startUtf16;
    final windowEnd = windowStart + oldValue.text.length;
    final rawOps = diffToOps(oldValue.text, newValue.text);
    final rawDeletedLength = rawOps
        .where((operation) => operation.type == OpType.delete)
        .fold<int>(0, (sum, operation) => sum + operation.lenUtf16!);
    final insertedText = rawOps
        .where((operation) => operation.type == OpType.insert)
        .map((operation) => operation.text!)
        .join();
    final backwardsDelete = oldValue.selection.isCollapsed &&
        rawDeletedLength > 0 &&
        rawOps.first.offsetUtf16 < oldValue.selection.extentOffset;
    final localOps = diffToOps(oldValue.text, formattedValue.text);
    final localGroup = localOps.isEmpty
        ? null
        : _SelectionEditOffset(
            windowStart + localOps.first.offsetUtf16,
            localOps
                .where((operation) => operation.type == OpType.delete)
                .fold<int>(0, (sum, operation) => sum + operation.lenUtf16!),
            localOps
                .where((operation) => operation.type == OpType.insert)
                .fold<int>(0, (sum, operation) => sum + operation.text!.length),
          );
    final additionalOperations = <TextOp>[];
    final remoteGroups = <_SelectionEditOffset>[];
    final unchangedExternal = <TextSelection>[];

    for (final selection in doc.additionalSelections) {
      final low = selection.baseOffset < selection.extentOffset
          ? selection.baseOffset
          : selection.extentOffset;
      final high = selection.baseOffset < selection.extentOffset
          ? selection.extentOffset
          : selection.baseOffset;
      final insideWindow = low >= windowStart && high <= windowEnd;
      if (insideWindow) continue;
      final beforeWindow = high <= windowStart;
      final afterWindow = low >= windowEnd;
      if (!beforeWindow && !afterWindow) {
        unchangedExternal.add(selection);
        continue;
      }

      var editStart = low;
      var deletedLength = high - low;
      if (selection.isCollapsed &&
          rawDeletedLength > 0 &&
          oldValue.selection.isCollapsed) {
        final range = _remoteCaretDeletionRange(
          doc,
          low,
          backwards: backwardsDelete,
        );
        if (range == null) {
          unchangedExternal.add(selection);
          continue;
        }
        editStart = range.$1;
        deletedLength = range.$2 - range.$1;
      }
      if (deletedLength == 0 && insertedText.isEmpty) {
        unchangedExternal.add(selection);
        continue;
      }
      final editEnd = editStart + deletedLength;
      if (localGroup != null &&
          localGroup.deletedLength > 0 &&
          editStart < localGroup.start + localGroup.deletedLength &&
          localGroup.start < editEnd) {
        unchangedExternal.add(selection);
        continue;
      }

      if (deletedLength > 0) {
        additionalOperations.add(TextOp.delete(editStart, deletedLength));
      }
      if (insertedText.isNotEmpty) {
        additionalOperations.add(TextOp.insert(editStart, insertedText));
      }
      remoteGroups.add(
        _SelectionEditOffset(editStart, deletedLength, insertedText.length),
      );
    }

    final groups = [
      if (localGroup != null) localGroup,
      ...remoteGroups,
    ]..sort((a, b) => a.start.compareTo(b.start));
    int mapOffset(int offset) {
      var shift = 0;
      for (final group in groups) {
        if (offset < group.start) break;
        if (offset <= group.start + group.deletedLength) {
          return group.start + shift + group.insertedLength;
        }
        shift += group.insertedLength - group.deletedLength;
      }
      return offset + shift;
    }

    final remoteSelections = <TextSelection>[
      for (final group in remoteGroups)
        TextSelection.collapsed(offset: mapOffset(group.start)),
      for (final selection in unchangedExternal)
        TextSelection(
          baseOffset: mapOffset(selection.baseOffset),
          extentOffset: mapOffset(selection.extentOffset),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ];
    doc.pendingInputOperations = List.unmodifiable(additionalOperations);
    doc.pendingInputWindowShiftUtf16 =
        remoteGroups.where((group) => group.start < windowStart).fold<int>(
              0,
              (shift, group) =>
                  shift + group.insertedLength - group.deletedLength,
            );
    doc.additionalSelections = List.unmodifiable(remoteSelections);
  }

  void _selectNextOccurrence() {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final needle = _selectedOccurrenceNeedle(doc);
    if (needle == null) {
      setState(() => _statusDetail = '先选择要匹配的文本');
      return;
    }
    final primary = doc.selection;
    final selectionEnd = primary.baseOffset < primary.extentOffset
        ? primary.extentOffset
        : primary.baseOffset;
    final existing = normalizeSelectionSet([
      primary,
      ...doc.additionalSelections,
    ]);
    final foundOffset = _nextUnselectedOccurrence(
      doc,
      needle: needle,
      startAfterUtf16: selectionEnd,
      existingSelections: existing,
    );
    if (foundOffset == null) return;
    final match = TextSelection(
      baseOffset: foundOffset,
      extentOffset: foundOffset + needle.length,
    );
    final window = doc.inputWindow;
    final matchOutsideWindow = match.baseOffset < window.startUtf16 ||
        match.extentOffset > window.endUtf16;
    _setDocSelections(
      doc,
      matchOutsideWindow ? [match, ...existing] : [...existing, match],
    );
  }

  void _moveLastSelectionToNextOccurrence() {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final needle = _selectedOccurrenceNeedle(doc);
    if (needle == null) {
      setState(() => _statusDetail = '先选择要匹配的文本');
      return;
    }
    final selections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (selections.isEmpty) return;
    final movingIndex = selections.length - 1;
    final moving = selections[movingIndex];
    final startAfter = moving.baseOffset < moving.extentOffset
        ? moving.extentOffset
        : moving.baseOffset;
    final remaining = [...selections]..removeAt(movingIndex);
    final foundOffset = _nextUnselectedOccurrence(
      doc,
      needle: needle,
      startAfterUtf16: startAfter,
      existingSelections: remaining,
    );
    if (foundOffset == null) return;
    remaining.add(TextSelection(
      baseOffset: foundOffset,
      extentOffset: foundOffset + needle.length,
    ));
    _setDocSelections(doc, remaining);
  }

  void _selectAllOccurrences() {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final needle = _selectedOccurrenceNeedle(doc);
    if (needle == null) {
      setState(() => _statusDetail = '先选择要匹配的文本');
      return;
    }
    final primary = doc.selection;
    final total = doc.inputWindow.totalUtf16Length;
    final matches = <TextSelection>[primary];
    var truncated = false;
    for (final offset in findTextOccurrenceOffsets(
      needle: needle,
      totalUtf16Length: total,
      readRange: doc.doc.readRange,
    )) {
      final matchEnd = offset + needle.length;
      if (_selectionOverlapsMatch(primary, offset, matchEnd)) continue;
      if (matches.length >= defaultMultiCursorLimit) {
        truncated = true;
        break;
      }
      matches.add(TextSelection(baseOffset: offset, extentOffset: matchEnd));
    }
    _setDocSelections(doc, matches);
    if (truncated && mounted) {
      setState(() => _statusDetail =
          '已选择前 $defaultMultiCursorLimit 个匹配项（editor.multiCursorLimit）');
    }
  }

  void _mergeSelections() {
    final doc = _active;
    if (doc == null) return;
    final merged = normalizeSelectionSet(doc.selectionSet);
    _setDocSelections(doc, merged);
  }

  List<String> _copyableSelectionTexts(OpenDoc doc) {
    final text = doc.inputWindow.text;
    final start = doc.inputWindow.startUtf16;
    final lines = lineContentRangesForText(text);
    return doc.selectionSet.map((selection) {
      final base = selection.baseOffset - start;
      final extent = selection.extentOffset - start;
      final low = base < extent ? base : extent;
      final high = base < extent ? extent : base;
      if (low != high) return text.substring(low, high);
      var lower = 0;
      var upper = lines.length;
      while (lower < upper) {
        final middle = (lower + upper) ~/ 2;
        if (lines[middle].$1 <= low) {
          lower = middle + 1;
        } else {
          upper = middle;
        }
      }
      final row = (lower - 1).clamp(0, lines.length - 1).toInt();
      final range = lines[row];
      return text.substring(range.$1, range.$2);
    }).toList(growable: false);
  }

  String _readDocumentRange(OpenDoc doc, int startUtf16, int endUtf16) {
    if (startUtf16 < 0 || endUtf16 < startUtf16) {
      throw RangeError('Invalid document range $startUtf16..$endUtf16');
    }
    final expectedVersion = doc.doc.version;
    final text = StringBuffer();
    var cursor = startUtf16;
    while (cursor < endUtf16) {
      final range = doc.doc.readRange(
        cursor,
        maxLenUtf16:
            (endUtf16 - cursor).clamp(1, maxDocReadRangeUtf16 - 1).toInt(),
      );
      if (range.version != expectedVersion ||
          range.startUtf16 != cursor ||
          range.endUtf16 <= cursor ||
          range.endUtf16 > endUtf16) {
        throw StateError('Document changed while reading a selected range');
      }
      text.write(range.text);
      cursor = range.endUtf16;
    }
    return text.toString();
  }

  Future<void> _applyIndentation({
    bool outdent = false,
    required bool tabOperation,
  }) async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) {
        setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      }
      return;
    }

    final hadCrossWindowSelection = doc.crossWindowSelection != null;
    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(
            () => _statusDetail = '缩进已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final edits = <({
      int start,
      int end,
      String text,
      String removed,
      bool collapseSelection,
    })>[];
    final lineIntervals = <({int first, int last})>[];
    try {
      for (final selection in selections) {
        final startBoundary = doc.doc.lineBoundary(selection.start);
        final endBoundary = doc.doc.lineBoundary(selection.end);
        if (startBoundary.version != expectedVersion ||
            endBoundary.version != expectedVersion) {
          throw StateError('文档版本在解析缩进行时发生变化');
        }

        if (tabOperation && !outdent) {
          if (selection.isCollapsed) {
            if (selection.extentOffset - startBoundary.startUtf16 >
                _undoHistoryBudget.maxTotalChars) {
              throw StateError('Tab 光标行前缀超过单次操作上限');
            }
            final prefix = _readDocumentRange(
              doc,
              startBoundary.startUtf16,
              selection.extentOffset,
            );
            final inserted = indentationTabText(prefix);
            edits.add((
              start: selection.extentOffset,
              end: selection.extentOffset,
              text: inserted,
              removed: '',
              collapseSelection: false,
            ));
            continue;
          }

          final isWholeSingleLine = startBoundary.line == endBoundary.line &&
              selection.start == startBoundary.startUtf16 &&
              selection.end == endBoundary.endUtf16;
          if (startBoundary.line == endBoundary.line && !isWholeSingleLine) {
            if (selection.end - selection.start >
                _undoHistoryBudget.maxTotalChars) {
              throw StateError('Tab 选区超过单次操作上限');
            }
            final prefix = _readDocumentRange(
              doc,
              startBoundary.startUtf16,
              selection.start,
            );
            final inserted = indentationTabText(prefix);
            edits.add((
              start: selection.start,
              end: selection.end,
              text: inserted,
              removed: _readDocumentRange(doc, selection.start, selection.end),
              collapseSelection: true,
            ));
            continue;
          }
        }

        var lastLine = endBoundary.line;
        if (!selection.isCollapsed &&
            lastLine > startBoundary.line &&
            selection.end == endBoundary.startUtf16) {
          lastLine--;
        }
        if (lastLine < startBoundary.line) lastLine = startBoundary.line;
        lineIntervals.add((first: startBoundary.line, last: lastLine));
      }

      lineIntervals.sort((a, b) => a.first != b.first
          ? a.first.compareTo(b.first)
          : a.last.compareTo(b.last));
      final mergedIntervals = <({int first, int last})>[];
      for (final interval in lineIntervals) {
        if (mergedIntervals.isEmpty ||
            interval.first > mergedIntervals.last.last) {
          mergedIntervals.add(interval);
        } else if (interval.last > mergedIntervals.last.last) {
          mergedIntervals[mergedIntervals.length - 1] = (
            first: mergedIntervals.last.first,
            last: interval.last,
          );
        }
      }

      var affectedUtf16 = 0;
      var affectedLines = 0;
      for (final interval in mergedIntervals) {
        final first = doc.doc.lineOffset(interval.first);
        final lastStart = doc.doc.lineOffset(interval.last);
        final last = doc.doc.lineBoundary(lastStart.offsetUtf16);
        if (first.version != expectedVersion ||
            lastStart.version != expectedVersion ||
            last.version != expectedVersion) {
          throw StateError('文档版本在读取缩进行时发生变化');
        }
        final lineCount = interval.last - interval.first + 1;
        affectedLines += lineCount;
        final rangeLength = last.endUtf16 - first.offsetUtf16;
        affectedUtf16 += rangeLength;
        if (affectedLines > maxDocLineDeleteSelections ||
            affectedUtf16 > _undoHistoryBudget.maxTotalChars) {
          throw StateError('缩进范围超过单次操作上限');
        }

        final text = _readDocumentRange(doc, first.offsetUtf16, last.endUtf16);
        final lines = text.split('\n');
        if (lines.length != lineCount) {
          throw StateError('Rust 行边界与读取文本不一致');
        }
        var lineOffset = first.offsetUtf16;
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          final skipEmptySelectionLine =
              interval.first != interval.last && line.isEmpty && !outdent;
          if (!skipEmptySelectionLine) {
            final newIndent = shiftLineIndentation(line, outdent: outdent);
            if (newIndent != null) {
              final oldIndentLength = leadingIndentLength(line);
              final oldIndent = line.substring(0, oldIndentLength);
              if (oldIndent != newIndent) {
                edits.add((
                  start: lineOffset,
                  end: lineOffset + oldIndentLength,
                  text: newIndent,
                  removed: oldIndent,
                  collapseSelection: false,
                ));
              }
            }
          }
          lineOffset += line.length + (index + 1 < lines.length ? 1 : 0);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '缩进未应用：$error');
      }
      return;
    }

    if (edits.isEmpty) return;
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '缩进未应用：文档版本已变化');
      return;
    }

    edits.sort((a, b) => a.start.compareTo(b.start));
    var payloadChars = 0;
    for (var index = 0; index < edits.length; index++) {
      final edit = edits[index];
      if (index > 0 &&
          (edit.start < edits[index - 1].end ||
              edit.start == edits[index - 1].start)) {
        if (mounted) setState(() => _statusDetail = '缩进未应用：多光标编辑范围重叠');
        return;
      }
      payloadChars += edit.removed.length + edit.text.length;
    }
    if (payloadChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '缩进已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    var deltaBefore = 0;
    final mappedStarts = <int>[];
    for (final edit in edits) {
      mappedStarts.add(edit.start + deltaBefore);
      deltaBefore += edit.text.length - (edit.end - edit.start);
    }
    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final edit in edits.reversed) {
      if (edit.end > edit.start) {
        forward.add(TextOp.delete(edit.start, edit.end - edit.start));
      }
      if (edit.text.isNotEmpty) {
        forward.add(TextOp.insert(edit.start, edit.text));
      }
    }
    for (var index = edits.length - 1; index >= 0; index--) {
      final edit = edits[index];
      final mappedStart = mappedStarts[index];
      if (edit.text.isNotEmpty) {
        inverse.add(TextOp.delete(mappedStart, edit.text.length));
      }
      if (edit.removed.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, edit.removed));
      }
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '缩进未应用：${error.code} ${error.detail}');
      }
      return;
    }

    int mapOffset(int offset, {required bool preserveEditStart}) {
      var delta = 0;
      for (final edit in edits) {
        if (offset < edit.start) break;
        final mappedStart = edit.start + delta;
        if (offset == edit.start && preserveEditStart) return mappedStart;
        if (offset <= edit.end) return mappedStart + edit.text.length;
        delta += edit.text.length - (edit.end - edit.start);
      }
      return offset + delta;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        () {
          final replacement = edits.where((edit) =>
              edit.collapseSelection &&
              selection.start == edit.start &&
              selection.end == edit.end);
          if (replacement.isNotEmpty) {
            final edit = replacement.first;
            final offset = mapOffset(edit.end, preserveEditStart: false);
            final caret = offset.clamp(0, newLength).toInt();
            return TextSelection.collapsed(offset: caret);
          }
          return TextSelection(
            baseOffset: mapOffset(
              selection.baseOffset,
              preserveEditStart: !selection.isCollapsed,
            ).clamp(0, newLength).toInt(),
            extentOffset: mapOffset(
              selection.extentOffset,
              preserveEditStart: !selection.isCollapsed,
            ).clamp(0, newLength).toInt(),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          );
        }(),
    ]);
    if (mappedSelections.isEmpty) return;
    final beforeCaret = selections.first.extentOffset;
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: beforeCaret,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (hadCrossWindowSelection) {
      _setCrossWindowLineSelection(doc, mappedSelections.first);
    } else {
      _setDocSelections(doc, mappedSelections, recordHistory: false);
    }
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(() => _statusDetail = outdent ? '已减少行缩进' : '已缩进行');
    }
  }

  Future<void> _copyCrossWindowSelection(OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final selection = doc.crossWindowSelection;
    if (selection == null) return;
    final text = _readDocumentRange(doc, selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _deleteLines() async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final crossWindow = doc.crossWindowSelection;
    final selections = normalizeSelectionSet(
      crossWindow == null
          ? [doc.selection, ...doc.additionalSelections]
          : [crossWindow],
    );
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '删除行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentLineOffset documentStart;
    final lineSelections =
        <({int firstLine, int lastLine, int column, int order})>[];
    try {
      documentStart = doc.doc.lineOffset(0);
      if (documentStart.version != expectedVersion) {
        throw StateError('文档版本在读取行数时发生变化');
      }
      if (documentStart.lineCount == 1 && documentStart.totalUtf16Length == 0) {
        return;
      }

      for (var order = 0; order < selections.length; order++) {
        final selection = selections[order];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        final active = doc.doc.positionAt(selection.extentOffset);
        if (start.version != expectedVersion ||
            end.version != expectedVersion ||
            active.version != expectedVersion) {
          throw StateError('文档版本在解析删除行选区时发生变化');
        }
        var lastLine = end.line;
        if (start.line < lastLine && end.character == 0) lastLine--;
        lineSelections.add((
          firstLine: start.line,
          lastLine: lastLine < start.line ? start.line : lastLine,
          column: active.character + 1,
          order: order,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '删除行未应用：$error');
      return;
    }

    lineSelections.sort((a, b) {
      final byStart = a.firstLine.compareTo(b.firstLine);
      if (byStart != 0) return byStart;
      final byEnd = a.lastLine.compareTo(b.lastLine);
      return byEnd != 0 ? byEnd : a.order.compareTo(b.order);
    });
    final mergedLines =
        <({int firstLine, int lastLine, int column, int order})>[];
    for (final current in lineSelections) {
      if (mergedLines.isEmpty ||
          current.firstLine > mergedLines.last.lastLine + 1) {
        mergedLines.add(current);
        continue;
      }
      final previous = mergedLines.removeLast();
      mergedLines.add((
        firstLine: previous.firstLine,
        lastLine: current.lastLine > previous.lastLine
            ? current.lastLine
            : previous.lastLine,
        column: previous.column,
        order: previous.order,
      ));
    }

    final plans = <({
      int start,
      int end,
      String removed,
      int mappedStart,
      int mappedCursor,
    })>[];
    var deletedUtf16 = 0;
    try {
      for (final lines in mergedLines) {
        final first = doc.doc.lineOffset(lines.firstLine);
        if (first.version != expectedVersion) {
          throw StateError('文档版本在解析删除行范围时发生变化');
        }

        late final int start;
        late final int end;
        late final int targetStart;
        late final int targetEnd;
        if (lines.lastLine < documentStart.lineCount - 1) {
          final next = doc.doc.lineOffset(lines.lastLine + 1);
          if (next.version != expectedVersion) {
            throw StateError('文档版本在解析删除行范围时发生变化');
          }
          final target = doc.doc.lineBoundary(next.offsetUtf16);
          if (target.version != expectedVersion) {
            throw StateError('文档版本在读取删除后光标位置时发生变化');
          }
          start = first.offsetUtf16;
          end = next.offsetUtf16;
          targetStart = target.startUtf16;
          targetEnd = target.endUtf16;
        } else if (lines.firstLine > 0) {
          final previous = doc.doc.lineOffset(lines.firstLine - 1);
          if (previous.version != expectedVersion) {
            throw StateError('文档版本在解析删除行范围时发生变化');
          }
          final target = doc.doc.lineBoundary(previous.offsetUtf16);
          if (target.version != expectedVersion) {
            throw StateError('文档版本在读取删除后光标位置时发生变化');
          }
          start = target.endUtf16;
          end = documentStart.totalUtf16Length;
          targetStart = target.startUtf16;
          targetEnd = target.endUtf16;
        } else {
          start = 0;
          end = documentStart.totalUtf16Length;
          targetStart = 0;
          targetEnd = 0;
        }

        if (start < 0 || end < start || end > documentStart.totalUtf16Length) {
          throw StateError('Rust 返回了无效的整行删除范围');
        }
        final removedLength = end - start;
        if (removedLength == 0) continue;
        if (removedLength > _undoHistoryBudget.maxTotalChars - deletedUtf16) {
          throw StateError(
              '删除行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final removed = _readDocumentRange(doc, start, end);
        final localColumn =
            (lines.column - 1).clamp(0, targetEnd - targetStart).toInt();
        final cursorBeforeDeletion = targetStart + localColumn;
        plans.add((
          start: start,
          end: end,
          removed: removed,
          mappedStart: start - deletedUtf16,
          mappedCursor: cursorBeforeDeletion <= start
              ? cursorBeforeDeletion - deletedUtf16
              : cursorBeforeDeletion - deletedUtf16 - removedLength,
        ));
        deletedUtf16 += removedLength;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '删除行未应用：$error');
      return;
    }

    if (plans.isEmpty) return;
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '删除行未应用：文档版本已变化');
      return;
    }

    final forward = [
      for (final plan in plans.reversed)
        TextOp.delete(plan.start, plan.end - plan.start),
    ];
    final inverse = [
      for (final plan in plans.reversed)
        TextOp.insert(plan.mappedStart, plan.removed),
    ];
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '删除行未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final newLength = documentStart.totalUtf16Length - deletedUtf16;
    final mappedSelections = normalizeSelectionSet([
      for (final plan in plans)
        TextSelection.collapsed(
          offset: plan.mappedCursor.clamp(0, newLength).toInt(),
        ),
    ]);
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已删除行');
  }

  Future<void> _copyLines({required bool down}) async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final crossWindow = doc.crossWindowSelection;
    final selections = normalizeSelectionSet(
      crossWindow == null
          ? [doc.selection, ...doc.additionalSelections]
          : [crossWindow],
    );
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '复制行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentLineOffset documentStart;
    final lineSelections = <({
      TextSelection selection,
      int firstLine,
      int lastLine,
      int endLine,
      int endColumn,
      int order
    })>[];
    try {
      documentStart = doc.doc.lineOffset(0);
      if (documentStart.version != expectedVersion) {
        throw StateError('文档版本在读取行数时发生变化');
      }
      if (documentStart.lineCount < 1) return;

      for (var order = 0; order < selections.length; order++) {
        final selection = selections[order];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('文档版本在解析复制行选区时发生变化');
        }
        var lastLine = end.line;
        if (start.line < lastLine && end.character == 0) lastLine--;
        lineSelections.add((
          selection: selection,
          firstLine: start.line,
          lastLine: lastLine < start.line ? start.line : lastLine,
          endLine: end.line,
          endColumn: end.character,
          order: order,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '复制行未应用：$error');
      return;
    }

    final sortedSelections = [...lineSelections]..sort((a, b) {
        final byStart = a.selection.start.compareTo(b.selection.start);
        return byStart != 0 ? byStart : a.order.compareTo(b.order);
      });
    final ignoredOrders = <int>{};
    if (sortedSelections.isNotEmpty) {
      var previous = sortedSelections.first;
      for (var index = 1; index < sortedSelections.length; index++) {
        final current = sortedSelections[index];
        if (previous.endLine == current.firstLine) {
          if (previous.order < current.order) {
            ignoredOrders.add(current.order);
          } else {
            ignoredOrders.add(previous.order);
            previous = current;
          }
        } else {
          previous = current;
        }
      }
    }

    final plans = <({
      int order,
      int firstLine,
      int lastLine,
      int offset,
      String inserted,
    })>[];
    var insertedUtf16 = 0;
    try {
      for (final lines in sortedSelections) {
        if (ignoredOrders.contains(lines.order)) continue;
        if (lines.firstLine < 0 ||
            lines.lastLine < lines.firstLine ||
            lines.lastLine >= documentStart.lineCount) {
          throw StateError('Rust 返回了无效的行复制范围');
        }

        final remainingBudget =
            _undoHistoryBudget.maxTotalChars - insertedUtf16;
        if (remainingBudget < 1) {
          throw StateError(
              '复制行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final sourceBudget = remainingBudget - 1;
        final source = StringBuffer();
        var sourceUtf16 = 0;
        late final DocumentLineBoundary lastBoundary;
        for (var line = lines.firstLine; line <= lines.lastLine; line++) {
          final lineStart = doc.doc.lineOffset(line);
          if (lineStart.version != expectedVersion) {
            throw StateError('文档版本在解析复制行范围时发生变化');
          }
          final boundary = doc.doc.lineBoundary(lineStart.offsetUtf16);
          if (boundary.version != expectedVersion ||
              boundary.startUtf16 > boundary.endUtf16) {
            throw StateError('Rust 返回了无效的行复制边界');
          }
          if (line > lines.firstLine) {
            if (sourceUtf16 >= sourceBudget) {
              throw StateError(
                  '复制行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
            }
            source.write('\n');
            sourceUtf16++;
          }
          final lineLength = boundary.endUtf16 - boundary.startUtf16;
          if (lineLength > sourceBudget - sourceUtf16) {
            throw StateError(
                '复制行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
          }
          source.write(_readDocumentRange(
            doc,
            boundary.startUtf16,
            boundary.endUtf16,
          ));
          sourceUtf16 += lineLength;
          lastBoundary = boundary;
        }

        final sourceText = source.toString();
        final inserted = down ? '$sourceText\n' : '\n$sourceText';
        if (inserted.length > remainingBudget) {
          throw StateError(
              '复制行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final first = doc.doc.lineOffset(lines.firstLine);
        if (first.version != expectedVersion) {
          throw StateError('文档版本在读取复制行插入点时发生变化');
        }
        plans.add((
          order: lines.order,
          firstLine: lines.firstLine,
          lastLine: lines.lastLine,
          offset: down ? first.offsetUtf16 : lastBoundary.endUtf16,
          inserted: inserted,
        ));
        insertedUtf16 += inserted.length;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '复制行未应用：$error');
      return;
    }

    if (plans.isEmpty) return;
    plans.sort((a, b) {
      final byOffset = a.offset.compareTo(b.offset);
      return byOffset != 0 ? byOffset : a.order.compareTo(b.order);
    });
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '复制行未应用：文档版本已变化');
      return;
    }

    final forward = [
      for (final plan in plans.reversed)
        TextOp.insert(plan.offset, plan.inserted),
    ];
    final inverse = <TextOp>[];
    for (var index = plans.length - 1; index >= 0; index--) {
      final plan = plans[index];
      final insertedBefore = plans
          .take(index)
          .fold<int>(0, (sum, prior) => sum + prior.inserted.length);
      inverse.add(TextOp.delete(
        plan.offset + insertedBefore,
        plan.inserted.length,
      ));
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '复制行未应用：${error.code} ${error.detail}');
      }
      return;
    }

    int mapOffset(int offset) {
      var mapped = offset;
      for (final plan in plans) {
        if (offset > plan.offset || (down && offset == plan.offset)) {
          mapped += plan.inserted.length;
        }
      }
      return mapped;
    }

    final mappedSelections = normalizeSelectionSet([
      for (final lines in lineSelections)
        () {
          var base = mapOffset(lines.selection.baseOffset);
          var extent = mapOffset(lines.selection.extentOffset);
          if (!down &&
              lines.firstLine < lines.endLine &&
              lines.endColumn == 0) {
            for (final plan in plans) {
              if (plan.order != lines.order) continue;
              final insertedBefore = plans
                  .where((other) => other.offset < plan.offset)
                  .fold<int>(0, (sum, other) => sum + other.inserted.length);
              final trackedEnd = plan.offset + 1 + insertedBefore;
              if (lines.selection.baseOffset > lines.selection.extentOffset) {
                base = trackedEnd;
              } else {
                extent = trackedEnd;
              }
              break;
            }
          }
          return TextSelection(
            baseOffset: base,
            extentOffset: extent,
            affinity: lines.selection.affinity,
            isDirectional: lines.selection.isDirectional,
          );
        }(),
    ]);
    final newLength = documentStart.totalUtf16Length + insertedUtf16;
    final clampedSelections = normalizeSelectionSet([
      for (final selection in mappedSelections)
        TextSelection(
          baseOffset: selection.baseOffset.clamp(0, newLength).toInt(),
          extentOffset: selection.extentOffset.clamp(0, newLength).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: clampedSelections.first.extentOffset,
      coalesce: false,
    );
    // Record selections against the previous window first. If a copied range
    // moved its endpoint beyond that window, _setDocSelections recenters and
    // schedules the widget update before a local controller selection can be
    // assigned beyond the controller's current text length.
    _setDocSelections(doc, clampedSelections, recordHistory: false);
    doc.replaceInputWindow(
      clampedSelections.first.extentOffset,
      selection: clampedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = down ? '已向下复制行' : '已向上复制行');
  }

  Future<void> _moveLines({required bool down}) async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final crossWindow = doc.crossWindowSelection;
    final selections = normalizeSelectionSet(
      crossWindow == null
          ? [doc.selection, ...doc.additionalSelections]
          : [crossWindow],
    );
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '移动行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentLineOffset documentStart;
    final lineSelections = <({
      TextSelection selection,
      int firstLine,
      int lastLine,
      int rawEndLine,
      int rawEndColumn,
      int order,
    })>[];
    try {
      documentStart = doc.doc.lineOffset(0);
      if (documentStart.version != expectedVersion) {
        throw StateError('文档版本在读取行数时发生变化');
      }
      if (documentStart.lineCount < 2) return;

      for (var order = 0; order < selections.length; order++) {
        final selection = selections[order];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('文档版本在解析移动行选区时发生变化');
        }
        var lastLine = end.line;
        if (start.line < lastLine && end.character == 0) lastLine--;
        lineSelections.add((
          selection: selection,
          firstLine: start.line,
          lastLine: lastLine < start.line ? start.line : lastLine,
          rawEndLine: end.line,
          rawEndColumn: end.character,
          order: order,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '移动行未应用：$error');
      return;
    }

    // Code-OSS checks the ordered selection endpoints before shrinking an
    // exclusive next-line column-one endpoint. Keep that boundary behavior:
    // a range ending on the final row cannot move down, even when that row is
    // excluded from the selected line block.
    final movable = lineSelections
        .where((lines) => down
            ? lines.rawEndLine < documentStart.lineCount - 1
            : lines.firstLine > 0)
        .toList()
      ..sort((a, b) {
        final byStart = a.firstLine.compareTo(b.firstLine);
        if (byStart != 0) return byStart;
        final byEnd = a.lastLine.compareTo(b.lastLine);
        return byEnd != 0 ? byEnd : a.order.compareTo(b.order);
      });
    if (movable.isEmpty) return;

    final groups = <({int firstLine, int lastLine, List<int> orders})>[];
    for (final lines in movable) {
      if (groups.isEmpty || lines.firstLine > groups.last.lastLine + 1) {
        groups.add((
          firstLine: lines.firstLine,
          lastLine: lines.lastLine,
          orders: [lines.order],
        ));
      } else {
        final previous = groups.removeLast();
        groups.add((
          firstLine: previous.firstLine,
          lastLine: lines.lastLine > previous.lastLine
              ? lines.lastLine
              : previous.lastLine,
          orders: [...previous.orders, lines.order],
        ));
      }
    }

    final plans = <({
      int firstLine,
      int lastLine,
      int start,
      int end,
      int adjacentStart,
      int adjacentEnd,
      int selectedStart,
      int selectedEnd,
      int movedEndOffset,
      int selectionDelta,
      List<int> orders,
      String removed,
      String inserted,
    })>[];
    var payloadChars = 0;
    try {
      for (final group in groups) {
        if (down && group.lastLine >= documentStart.lineCount - 1) continue;
        if (!down && group.firstLine <= 0) continue;

        final first = doc.doc.lineOffset(group.firstLine);
        final last = doc.doc.lineOffset(group.lastLine);
        if (first.version != expectedVersion ||
            last.version != expectedVersion) {
          throw StateError('文档版本在读取移动行边界时发生变化');
        }
        final selectedEndBoundary = doc.doc.lineBoundary(last.offsetUtf16);
        if (selectedEndBoundary.version != expectedVersion) {
          throw StateError('文档版本在读取移动行末尾时发生变化');
        }

        late final int start;
        late final int end;
        late final int adjacentStart;
        late final int adjacentEnd;
        late final int selectedStart;
        late final int selectedEnd;
        late final int movedEndOffset;
        late final int selectionDelta;
        if (down) {
          final neighbor = doc.doc.lineOffset(group.lastLine + 1);
          final neighborBoundary = doc.doc.lineBoundary(neighbor.offsetUtf16);
          if (neighbor.version != expectedVersion ||
              neighborBoundary.version != expectedVersion) {
            throw StateError('文档版本在读取下方移动行时发生变化');
          }
          start = first.offsetUtf16;
          end = neighborBoundary.endUtf16;
          adjacentStart = neighbor.offsetUtf16;
          adjacentEnd = neighborBoundary.endUtf16;
          selectedStart = first.offsetUtf16;
          selectedEnd = selectedEndBoundary.endUtf16;
          if (end < neighbor.offsetUtf16 || selectedEnd < selectedStart) {
            throw StateError('Rust 返回了无效的向下移动行边界');
          }
          final rangeLength = end - start;
          if (rangeLength < 0 ||
              rangeLength >
                  (_undoHistoryBudget.maxTotalChars - payloadChars) ~/ 2) {
            throw StateError(
                '移动行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
          }
          final removed = _readDocumentRange(doc, start, end);
          final selectedText = removed.substring(0, selectedEnd - start);
          final neighborText = removed.substring(neighbor.offsetUtf16 - start);
          final inserted = '$neighborText\n$selectedText';
          if (inserted.length != rangeLength) {
            throw StateError('向下移动行未保持 UTF-16 范围长度');
          }
          final neighborLength =
              neighborBoundary.endUtf16 - neighbor.offsetUtf16;
          movedEndOffset = start + inserted.length + 1;
          selectionDelta = neighborLength + 1;
          final cost = removed.length + inserted.length;
          if (cost > _undoHistoryBudget.maxTotalChars - payloadChars) {
            throw StateError(
                '移动行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
          }
          payloadChars += cost;
          plans.add((
            firstLine: group.firstLine,
            lastLine: group.lastLine,
            start: start,
            end: end,
            adjacentStart: adjacentStart,
            adjacentEnd: adjacentEnd,
            selectedStart: selectedStart,
            selectedEnd: selectedEnd,
            movedEndOffset: movedEndOffset,
            selectionDelta: selectionDelta,
            orders: group.orders,
            removed: removed,
            inserted: inserted,
          ));
        } else {
          final previous = doc.doc.lineOffset(group.firstLine - 1);
          final previousBoundary = doc.doc.lineBoundary(previous.offsetUtf16);
          if (previous.version != expectedVersion ||
              previousBoundary.version != expectedVersion) {
            throw StateError('文档版本在读取上方移动行时发生变化');
          }
          start = previous.offsetUtf16;
          end = selectedEndBoundary.endUtf16;
          adjacentStart = previous.offsetUtf16;
          adjacentEnd = previousBoundary.endUtf16;
          selectedStart = first.offsetUtf16;
          selectedEnd = selectedEndBoundary.endUtf16;
          if (selectedStart < start || end < selectedEnd) {
            throw StateError('Rust 返回了无效的向上移动行边界');
          }
          final rangeLength = end - start;
          if (rangeLength < 0 ||
              rangeLength >
                  (_undoHistoryBudget.maxTotalChars - payloadChars) ~/ 2) {
            throw StateError(
                '移动行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
          }
          final removed = _readDocumentRange(doc, start, end);
          final previousEnd = previousBoundary.endUtf16;
          final previousText = removed.substring(0, previousEnd - start);
          final selectedText = removed.substring(
            selectedStart - start,
            selectedEnd - start,
          );
          final inserted = '$selectedText\n$previousText';
          if (inserted.length != rangeLength) {
            throw StateError('向上移动行未保持 UTF-16 范围长度');
          }
          final previousLength =
              previousBoundary.endUtf16 - previous.offsetUtf16;
          movedEndOffset = start + selectedText.length + 1;
          selectionDelta = -(previousLength + 1);
          final cost = removed.length + inserted.length;
          if (cost > _undoHistoryBudget.maxTotalChars - payloadChars) {
            throw StateError(
                '移动行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
          }
          payloadChars += cost;
          plans.add((
            firstLine: group.firstLine,
            lastLine: group.lastLine,
            start: start,
            end: end,
            adjacentStart: adjacentStart,
            adjacentEnd: adjacentEnd,
            selectedStart: selectedStart,
            selectedEnd: selectedEnd,
            movedEndOffset: movedEndOffset,
            selectionDelta: selectionDelta,
            orders: group.orders,
            removed: removed,
            inserted: inserted,
          ));
        }
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '移动行未应用：$error');
      return;
    }

    if (plans.isEmpty) return;
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '移动行未应用：文档版本已变化');
      return;
    }

    final changedPlans = plans.where((plan) => plan.removed != plan.inserted);
    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in changedPlans.toList()
      ..sort((a, b) => b.start.compareTo(a.start))) {
      forward
        ..add(TextOp.delete(plan.start, plan.end - plan.start))
        ..add(TextOp.insert(plan.start, plan.inserted));
      inverse
        ..add(TextOp.delete(plan.start, plan.inserted.length))
        ..add(TextOp.insert(plan.start, plan.removed));
    }

    if (forward.isNotEmpty) {
      try {
        doc.doc.applyWith(expectedVersion, forward);
      } on AlulaException catch (error) {
        if (mounted) {
          setState(
              () => _statusDetail = '移动行未应用：${error.code} ${error.detail}');
        }
        return;
      }
    }

    final mappedSelections = normalizeSelectionSet([
      for (final lines in lineSelections)
        () {
          ({
            int firstLine,
            int lastLine,
            int start,
            int end,
            int adjacentStart,
            int adjacentEnd,
            int selectedStart,
            int selectedEnd,
            int movedEndOffset,
            int selectionDelta,
            List<int> orders,
            String removed,
            String inserted,
          })? plan;
          for (final candidate in plans) {
            if (candidate.orders.contains(lines.order)) {
              plan = candidate;
              break;
            }
          }
          final currentPlan = plan;
          int mapOffset(int offset, {bool orderedEnd = false}) {
            final isExclusiveLineEnd = orderedEnd &&
                lines.rawEndLine > lines.firstLine &&
                lines.rawEndColumn == 0;
            if (isExclusiveLineEnd &&
                currentPlan != null &&
                lines.rawEndLine > currentPlan.lastLine) {
              return currentPlan.movedEndOffset;
            }
            for (final candidate in plans) {
              if (offset < candidate.start || offset > candidate.end) {
                continue;
              }
              if (down) {
                if (offset >= candidate.adjacentStart) {
                  return candidate.start + offset - candidate.adjacentStart;
                }
                final adjacentLength =
                    candidate.adjacentEnd - candidate.adjacentStart;
                return candidate.start +
                    adjacentLength +
                    1 +
                    offset -
                    candidate.selectedStart;
              }
              if (offset >= candidate.selectedStart) {
                return candidate.start + offset - candidate.selectedStart;
              }
              final selectedLength =
                  candidate.selectedEnd - candidate.selectedStart;
              return candidate.start +
                  selectedLength +
                  1 +
                  offset -
                  candidate.adjacentStart;
            }
            return offset;
          }

          final orderedEnd = lines.selection.end;
          final baseIsEnd = lines.selection.baseOffset == orderedEnd &&
              lines.selection.baseOffset != lines.selection.extentOffset;
          final extentIsEnd = lines.selection.extentOffset == orderedEnd &&
              lines.selection.baseOffset != lines.selection.extentOffset;
          return TextSelection(
            baseOffset: mapOffset(
              lines.selection.baseOffset,
              orderedEnd: baseIsEnd,
            ),
            extentOffset: mapOffset(
              lines.selection.extentOffset,
              orderedEnd: extentIsEnd,
            ),
            affinity: lines.selection.affinity,
            isDirectional: lines.selection.isDirectional,
          );
        }(),
    ]);
    final clampedSelections = normalizeSelectionSet([
      for (final selection in mappedSelections)
        TextSelection(
          baseOffset: selection.baseOffset
              .clamp(0, documentStart.totalUtf16Length)
              .toInt(),
          extentOffset: selection.extentOffset
              .clamp(0, documentStart.totalUtf16Length)
              .toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);

    if (forward.isNotEmpty) {
      _recordDocumentOperations(
        doc,
        forward: forward,
        inverse: inverse,
        beforeCaret: selections.first.extentOffset,
        afterCaret: clampedSelections.first.extentOffset,
        coalesce: false,
      );
      _setDocSelections(doc, clampedSelections, recordHistory: false);
      doc.replaceInputWindow(
        clampedSelections.first.extentOffset,
        selection: clampedSelections.first,
      );
      _refreshSiblingViews(doc, forward);
      _onFindTextChanged();
      _syncCommandContext();
    } else {
      _setDocSelections(doc, clampedSelections);
    }
    if (mounted) setState(() => _statusDetail = down ? '已向下移动行' : '已向上移动行');
  }

  Future<void> _sortLines({required bool descending}) async {
    const maxSortLines = 100000;
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    var selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted && selections.length > maxDocLineDeleteSelections) {
        setState(() =>
            _statusDetail = '行排序已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final documentStart = doc.doc.lineOffset(0);
    if (documentStart.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '行排序未应用：文档版本已变化');
      return;
    }

    if (selections.length == 1) {
      try {
        final selection = selections.single;
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('Rust 返回了过期的行排序选区');
        }
        if (start.line == end.line) {
          // Code-OSS sorts the complete document for a single-line selection.
          selections = [
            TextSelection(
              baseOffset: 0,
              extentOffset: documentStart.totalUtf16Length,
            ),
          ];
        }
      } on Object catch (error) {
        if (mounted) setState(() => _statusDetail = '行排序未应用：$error');
        return;
      }
    }

    final plans = <({
      TextSelection selection,
      bool primary,
      int start,
      int end,
      String removed,
      String inserted,
    })>[];
    var payloadChars = 0;
    try {
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('Rust 返回了过期的行排序范围');
        }

        var endLine = end.line;
        if (end.character == 0) endLine--;
        // A one-line range cannot be sorted. Code-OSS cancels the whole
        // command if any selection has no sortable line range.
        if (start.line >= endLine) return;
        final lineCount = endLine - start.line + 1;
        if (lineCount > maxSortLines) {
          throw StateError('排序范围超过 $maxSortLines 行上限');
        }

        final first = doc.doc.lineOffset(start.line);
        final last = doc.doc.lineOffset(endLine);
        if (first.version != expectedVersion ||
            last.version != expectedVersion) {
          throw StateError('Rust 返回了过期的行排序边界');
        }
        final boundary = doc.doc.lineBoundary(last.offsetUtf16);
        if (boundary.version != expectedVersion ||
            boundary.line != endLine ||
            boundary.endUtf16 < first.offsetUtf16) {
          throw StateError('Rust 返回了无效的行排序边界');
        }

        final rangeLength = boundary.endUtf16 - first.offsetUtf16;
        final remaining = _undoHistoryBudget.maxTotalChars - payloadChars;
        if (rangeLength < 0 || rangeLength > remaining ~/ 2) {
          throw StateError(
              '行排序撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final removed = _readDocumentRange(
          doc,
          first.offsetUtf16,
          boundary.endUtf16,
        );
        if (removed.length != rangeLength) {
          throw StateError('Rust 返回的行排序文本长度与 UTF-16 范围不符');
        }

        final lines = removed.split('\n');
        if (lines.length != lineCount) {
          throw StateError('Rust 返回的行排序内容与行数不符');
        }
        final sorted = List<String>.of(lines)..sort((a, b) => a.compareTo(b));
        final ordered = descending ? sorted.reversed.toList() : sorted;
        final inserted = ordered.join('\n');
        if (inserted == removed) return;
        if (inserted.length != removed.length) {
          throw StateError('行排序改变了文本长度');
        }
        payloadChars += removed.length + inserted.length;
        plans.add((
          selection: selection,
          primary: index == 0,
          start: first.offsetUtf16,
          end: boundary.endUtf16,
          removed: removed,
          inserted: inserted,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '行排序未应用：$error');
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '行排序未应用：文档版本已变化');
      return;
    }

    plans.sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < plans.length; index++) {
      if (plans[index].start < plans[index - 1].end) {
        if (mounted) {
          setState(() => _statusDetail = '行排序已取消：多个选区的行范围重叠');
        }
        return;
      }
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in plans.reversed) {
      forward
        ..add(TextOp.delete(plan.start, plan.end - plan.start))
        ..add(TextOp.insert(plan.start, plan.inserted));
      inverse
        ..add(TextOp.delete(plan.start, plan.inserted.length))
        ..add(TextOp.insert(plan.start, plan.removed));
    }

    TextSelection mapSelection(
      ({
        TextSelection selection,
        bool primary,
        int start,
        int end,
        String removed,
        String inserted,
      }) plan,
    ) {
      final forwardSelection =
          plan.selection.baseOffset <= plan.selection.extentOffset;
      final mappedStart = plan.start;
      final mappedEnd = plan.selection.end <= plan.end
          ? plan.start + plan.inserted.length
          : plan.selection.end;
      return TextSelection(
        baseOffset: forwardSelection ? mappedStart : mappedEnd,
        extentOffset: forwardSelection ? mappedEnd : mappedStart,
        affinity: plan.selection.affinity,
        isDirectional: plan.selection.isDirectional,
      );
    }

    final mappedSelections = normalizeSelectionSet([
      for (final plan in plans.where((plan) => plan.primary))
        mapSelection(plan),
      for (final plan in plans.where((plan) => !plan.primary))
        mapSelection(plan),
    ]);

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '行排序未应用：${error.code} ${error.detail}');
      }
      return;
    }
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(() => _statusDetail = descending ? '已按降序排序行' : '已按升序排序行');
    }
  }

  Future<void> _removeDuplicateLines() async {
    const maxDeduplicateLines = 100000;
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    var selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted && selections.length > maxDocLineDeleteSelections) {
        setState(() =>
            _statusDetail = '删除重复行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final documentStart = doc.doc.lineOffset(0);
    if (documentStart.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '删除重复行未应用：文档版本已变化');
      return;
    }
    if (documentStart.lineCount == 1 && documentStart.totalUtf16Length == 0) {
      return;
    }

    final originalSelections = List<TextSelection>.of(selections);
    var updateSelection = true;
    if (selections.length == 1) {
      try {
        final selection = selections.single;
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('Rust 返回了过期的重复行选区');
        }
        if (start.line == end.line) {
          // Code-OSS promotes a single-line selection or caret to the full file.
          selections = [
            TextSelection(
              baseOffset: 0,
              extentOffset: documentStart.totalUtf16Length,
            ),
          ];
          updateSelection = false;
        }
      } on Object catch (error) {
        if (mounted) setState(() => _statusDetail = '删除重复行未应用：$error');
        return;
      }
    }

    final plans = <({
      TextSelection selection,
      bool primary,
      int start,
      int end,
      int firstLine,
      String removed,
      String inserted,
      List<int> oldLineToNewLine,
      List<int> insertedLineStarts,
      List<int> insertedLineLengths,
    })>[];
    var payloadChars = 0;
    try {
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('Rust 返回了过期的重复行范围');
        }
        final lineCount = end.line - start.line + 1;
        if (lineCount < 1 || lineCount > maxDeduplicateLines) {
          throw StateError('重复行范围超过 $maxDeduplicateLines 行上限');
        }

        final first = doc.doc.lineOffset(start.line);
        final last = doc.doc.lineOffset(end.line);
        if (first.version != expectedVersion ||
            last.version != expectedVersion) {
          throw StateError('Rust 返回了过期的重复行边界');
        }
        final boundary = doc.doc.lineBoundary(last.offsetUtf16);
        if (boundary.version != expectedVersion ||
            boundary.line != end.line ||
            boundary.endUtf16 < first.offsetUtf16) {
          throw StateError('Rust 返回了无效的重复行边界');
        }

        final rangeLength = boundary.endUtf16 - first.offsetUtf16;
        final remaining = _undoHistoryBudget.maxTotalChars - payloadChars;
        if (rangeLength < 0 || rangeLength > remaining ~/ 2) {
          throw StateError(
              '删除重复行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final removed = _readDocumentRange(
          doc,
          first.offsetUtf16,
          boundary.endUtf16,
        );
        if (removed.length != rangeLength) {
          throw StateError('Rust 返回的重复行文本长度与 UTF-16 范围不符');
        }

        final sourceLines = removed.split('\n');
        if (sourceLines.length != lineCount) {
          throw StateError('Rust 返回的重复行内容与行数不符');
        }
        final uniqueLineIndexes = <String, int>{};
        final uniqueLines = <String>[];
        final oldLineToNewLine = <int>[];
        for (final line in sourceLines) {
          final existingIndex = uniqueLineIndexes[line];
          if (existingIndex != null) {
            oldLineToNewLine.add(existingIndex);
          } else {
            final newIndex = uniqueLines.length;
            uniqueLineIndexes[line] = newIndex;
            uniqueLines.add(line);
            oldLineToNewLine.add(newIndex);
          }
        }
        final insertedLineStarts = <int>[];
        var lineStart = 0;
        for (final line in uniqueLines) {
          insertedLineStarts.add(lineStart);
          lineStart += line.length + 1;
        }
        final inserted = uniqueLines.join('\n');
        payloadChars += removed.length + inserted.length;
        plans.add((
          selection: originalSelections[index],
          primary: index == 0,
          start: first.offsetUtf16,
          end: boundary.endUtf16,
          firstLine: start.line,
          removed: removed,
          inserted: inserted,
          oldLineToNewLine: oldLineToNewLine,
          insertedLineStarts: insertedLineStarts,
          insertedLineLengths: [for (final line in uniqueLines) line.length],
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '删除重复行未应用：$error');
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) {
        setState(() => _statusDetail = '删除重复行未应用：文档版本已变化');
      }
      return;
    }

    plans.sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < plans.length; index++) {
      if (plans[index].start < plans[index - 1].end) {
        if (mounted) {
          setState(() => _statusDetail = '删除重复行已取消：多个选区的行范围重叠');
        }
        return;
      }
    }

    final mappedPlans = <({
      TextSelection selection,
      bool primary,
      int start,
      int end,
      int firstLine,
      String removed,
      String inserted,
      List<int> oldLineToNewLine,
      List<int> insertedLineStarts,
      List<int> insertedLineLengths,
      int mappedStart,
    })>[];
    var cumulativeDelta = 0;
    for (final plan in plans) {
      final mappedStart = plan.start + cumulativeDelta;
      mappedPlans.add((
        selection: plan.selection,
        primary: plan.primary,
        start: plan.start,
        end: plan.end,
        firstLine: plan.firstLine,
        removed: plan.removed,
        inserted: plan.inserted,
        oldLineToNewLine: plan.oldLineToNewLine,
        insertedLineStarts: plan.insertedLineStarts,
        insertedLineLengths: plan.insertedLineLengths,
        mappedStart: mappedStart,
      ));
      cumulativeDelta += plan.inserted.length - plan.removed.length;
    }

    int mapOffsetThroughEdits(int offset) {
      var delta = 0;
      for (final plan in mappedPlans) {
        if (plan.removed == plan.inserted) continue;
        if (offset < plan.start) break;
        if (offset > plan.end) {
          delta += plan.inserted.length - plan.removed.length;
          continue;
        }
        final position = doc.doc.positionAt(offset);
        if (position.version != expectedVersion) {
          throw StateError('Rust 返回了过期的重复行光标位置');
        }
        final oldLineIndex = position.line - plan.firstLine;
        if (oldLineIndex < 0 || oldLineIndex >= plan.oldLineToNewLine.length) {
          throw StateError('Rust 返回了无效的重复行光标行');
        }
        final newLineIndex = plan.oldLineToNewLine[oldLineIndex];
        final column = position.character
            .clamp(0, plan.insertedLineLengths[newLineIndex])
            .toInt();
        return plan.mappedStart +
            plan.insertedLineStarts[newLineIndex] +
            column;
      }
      return offset + delta;
    }

    TextSelection mapWholeDocumentSelection(TextSelection selection) =>
        TextSelection(
          baseOffset: mapOffsetThroughEdits(selection.baseOffset),
          extentOffset: mapOffsetThroughEdits(selection.extentOffset),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        );

    final mappedSelections = normalizeSelectionSet([
      for (final plan in mappedPlans.where((plan) => plan.primary))
        updateSelection
            ? TextSelection(
                baseOffset: plan.mappedStart,
                extentOffset: plan.mappedStart + plan.inserted.length,
              )
            : mapWholeDocumentSelection(plan.selection),
      for (final plan in mappedPlans.where((plan) => !plan.primary))
        updateSelection
            ? TextSelection(
                baseOffset: plan.mappedStart,
                extentOffset: plan.mappedStart + plan.inserted.length,
              )
            : mapWholeDocumentSelection(plan.selection),
    ]);

    final changedPlans = mappedPlans
        .where((plan) => plan.removed != plan.inserted)
        .toList(growable: false);
    if (changedPlans.isEmpty) {
      if (updateSelection) _setDocSelections(doc, mappedSelections);
      if (mounted) setState(() => _statusDetail = '未发现重复行');
      return;
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in changedPlans.reversed) {
      forward
        ..add(TextOp.delete(plan.start, plan.end - plan.start))
        ..add(TextOp.insert(plan.start, plan.inserted));
      inverse
        ..add(TextOp.delete(plan.mappedStart, plan.inserted.length))
        ..add(TextOp.insert(plan.mappedStart, plan.removed));
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '删除重复行未应用：${error.code} ${error.detail}');
      }
      return;
    }
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: originalSelections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已删除重复行');
  }

  Future<void> _transformCase({
    required bool uppercase,
    bool titleCase = false,
    bool camelCase = false,
  }) async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted && selections.length > maxDocLineDeleteSelections) {
        setState(
          () =>
              _statusDetail = '文本大小写转换已取消：选区数超过 $maxDocLineDeleteSelections 上限',
        );
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final ranges =
        <(int, int), ({int start, int end, String removed, String inserted})>{};
    final selectionPlans =
        <({TextSelection selection, (int, int)? range, bool selectedText})>[];
    const wordSeparators = r"""`~!@#$%^&*()-=+[{]}\|;:'",.<>/?""";
    final whitespace = RegExp(r'\s');
    final decimalWord = RegExp(r'-?\d*\.\d[A-Za-z0-9_]*');

    bool isSeparator(String text, int offset) {
      final unit = text.substring(offset, offset + 1);
      return wordSeparators.contains(unit) || whitespace.hasMatch(unit);
    }

    (int, int)? findDefaultWord(String text, int caret) {
      var cursor = 0;
      while (cursor < text.length) {
        final decimal = decimalWord.matchAsPrefix(text, cursor);
        if (decimal != null) {
          final start = cursor;
          final end = decimal.end;
          cursor = end;
          if (start <= caret && caret <= end) return (start, end);
          continue;
        }
        if (isSeparator(text, cursor)) {
          cursor++;
          continue;
        }
        final start = cursor;
        var end = cursor + 1;
        while (end < text.length && !isSeparator(text, end)) {
          end++;
        }
        cursor = end;
        if (start <= caret && caret <= end) return (start, end);
      }
      return null;
    }

    var payloadChars = 0;
    try {
      for (final selection in selections) {
        final selectedText = !selection.isCollapsed;
        var editStart = selection.start;
        var editEnd = selection.end;

        if (!selectedText) {
          final position = doc.doc.positionAt(editStart);
          final boundary = doc.doc.lineBoundary(editStart);
          if (position.version != expectedVersion ||
              boundary.version != expectedVersion ||
              boundary.line != position.line ||
              editStart < boundary.startUtf16 ||
              editStart > boundary.endUtf16) {
            throw StateError('Rust 返回了过期或无效的大小写转换光标位置');
          }

          // Code-OSS limits configured-word lookup to a 1,000 UTF-16-unit
          // window centered on the caret on exceptionally long lines.
          const maxWordLookupUtf16 = 1000;
          final lineLength = boundary.endUtf16 - boundary.startUtf16;
          final column = editStart - boundary.startUtf16 + 1;
          var windowStart = 0;
          var windowEnd = lineLength;
          if (lineLength > maxWordLookupUtf16) {
            windowStart = (column - maxWordLookupUtf16 ~/ 2)
                .clamp(0, lineLength)
                .toInt();
            windowEnd = (column + maxWordLookupUtf16 ~/ 2)
                .clamp(windowStart, lineLength)
                .toInt();
          }
          final lineText = _readDocumentRange(
            doc,
            boundary.startUtf16 + windowStart,
            boundary.startUtf16 + windowEnd,
          );
          final word = findDefaultWord(lineText, column - 1 - windowStart);
          if (word == null) {
            selectionPlans.add((
              selection: selection,
              range: null,
              selectedText: false,
            ));
            continue;
          }
          editStart = boundary.startUtf16 + windowStart + word.$1;
          editEnd = boundary.startUtf16 + windowStart + word.$2;
        }

        final key = (editStart, editEnd);
        if (!ranges.containsKey(key)) {
          final rangeLength = editEnd - editStart;
          final remaining = _undoHistoryBudget.maxTotalChars - payloadChars;
          if (rangeLength < 0 || rangeLength > remaining ~/ 2) {
            throw StateError(
              '文本大小写转换撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限',
            );
          }
          final removed = _readDocumentRange(doc, editStart, editEnd);
          if (removed.length != rangeLength) {
            throw StateError('Rust 返回的大小写转换文本长度与 UTF-16 范围不符');
          }
          final core = _core ?? (throw StateError('Alula Rust 核心未初始化'));
          final inserted = camelCase
              ? core.transformCamelCaseText(removed)
              : titleCase
                  ? core.transformTitleCaseText(removed)
                  : core.transformCaseText(removed, uppercase: uppercase);
          final editPayloadChars = removed.length + inserted.length;
          if (editPayloadChars > remaining) {
            throw StateError(
              '文本大小写转换撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限',
            );
          }
          if (inserted != removed) payloadChars += editPayloadChars;
          ranges[key] = (
            start: editStart,
            end: editEnd,
            removed: removed,
            inserted: inserted,
          );
        }
        selectionPlans.add((
          selection: selection,
          range: key,
          selectedText: selectedText,
        ));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '文本大小写转换未应用：$error');
      }
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) {
        setState(() => _statusDetail = '文本大小写转换未应用：文档版本已变化');
      }
      return;
    }

    final orderedRanges = ranges.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < orderedRanges.length; index++) {
      if (orderedRanges[index].start < orderedRanges[index - 1].end) {
        if (mounted) {
          setState(() => _statusDetail = '文本大小写转换已取消：多个编辑范围重叠');
        }
        return;
      }
    }

    final mappedRanges =
        <
          ({
            int start,
            int end,
            String removed,
            String inserted,
            int mappedStart,
          })
        >[];
    var cumulativeDelta = 0;
    for (final range in orderedRanges) {
      final mappedStart = range.start + cumulativeDelta;
      mappedRanges.add((
        start: range.start,
        end: range.end,
        removed: range.removed,
        inserted: range.inserted,
        mappedStart: mappedStart,
      ));
      cumulativeDelta += range.inserted.length - range.removed.length;
    }

    int mapOffset(int offset) {
      var delta = 0;
      for (final range in mappedRanges) {
        if (offset < range.start) return offset + delta;
        if (offset <= range.end) {
          final relative = (offset - range.start)
              .clamp(0, range.inserted.length)
              .toInt();
          return range.mappedStart + relative;
        }
        delta += range.inserted.length - range.removed.length;
      }
      return offset + delta;
    }

    final mappedSelections = <TextSelection>[];
    for (final plan in selectionPlans) {
      final key = plan.range;
      if (key == null) {
        mappedSelections.add(plan.selection);
        continue;
      }
      final range = ranges[key]!;
      if (plan.selectedText) {
        final mappedStart = mapOffset(range.start);
        final mappedEnd = mappedStart + range.inserted.length;
        final forward =
            plan.selection.baseOffset <= plan.selection.extentOffset;
        mappedSelections.add(
          TextSelection(
            baseOffset: forward ? mappedStart : mappedEnd,
            extentOffset: forward ? mappedEnd : mappedStart,
            affinity: plan.selection.affinity,
            isDirectional: plan.selection.isDirectional,
          ),
        );
      } else {
        final offset = mapOffset(plan.selection.extentOffset);
        mappedSelections.add(
          TextSelection(
            baseOffset: offset,
            extentOffset: offset,
            affinity: plan.selection.affinity,
            isDirectional: plan.selection.isDirectional,
          ),
        );
      }
    }
    final normalizedMappedSelections = normalizeSelectionSet(mappedSelections);

    final changedRanges = mappedRanges
        .where((range) => range.removed != range.inserted)
        .toList(growable: false);
    if (changedRanges.isEmpty) return;

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final range in changedRanges.reversed) {
      forward
        ..add(TextOp.delete(range.start, range.end - range.start))
        ..add(TextOp.insert(range.start, range.inserted));
      inverse
        ..add(TextOp.delete(range.mappedStart, range.inserted.length))
        ..add(TextOp.insert(range.mappedStart, range.removed));
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
          () => _statusDetail = '文本大小写转换未应用：${error.code} ${error.detail}',
        );
      }
      return;
    }
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: normalizedMappedSelections.first.extentOffset,
      coalesce: false,
    );
    _setDocSelections(doc, normalizedMappedSelections, recordHistory: false);
    doc.replaceInputWindow(
      normalizedMappedSelections.first.extentOffset,
      selection: normalizedMappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(
        () => _statusDetail = titleCase
            ? '已转换为标题大小写'
            : uppercase
                ? '已转换为大写'
                : '已转换为小写',
      );
    }
  }

  Future<void> _joinLines() async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final crossWindow = doc.crossWindowSelection;
    final selections = normalizeSelectionSet(
      crossWindow == null
          ? [doc.selection, ...doc.additionalSelections]
          : [crossWindow],
    );
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '合并行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentLineOffset documentStart;
    final lineSelections = <({
      TextSelection selection,
      int order,
      int startLine,
      int endLine,
      bool primary,
    })>[];
    try {
      documentStart = doc.doc.lineOffset(0);
      if (documentStart.version != expectedVersion) {
        throw StateError('文档版本在读取行数时发生变化');
      }
      for (var order = 0; order < selections.length; order++) {
        final selection = selections[order];
        final start = doc.doc.positionAt(selection.start);
        final end = doc.doc.positionAt(selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('文档版本在解析合并行选区时发生变化');
        }
        lineSelections.add((
          selection: selection,
          order: order,
          startLine: start.line,
          endLine: end.line,
          primary: order == 0,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '合并行未应用：$error');
      return;
    }

    lineSelections.sort((a, b) {
      final byStart = a.selection.start.compareTo(b.selection.start);
      if (byStart != 0) return byStart;
      final byEnd = a.selection.end.compareTo(b.selection.end);
      return byEnd != 0 ? byEnd : a.order.compareTo(b.order);
    });
    final reducedSelections = <({
      TextSelection selection,
      int startLine,
      int endLine,
      bool primary,
    })>[];
    for (final current in lineSelections) {
      if (reducedSelections.isEmpty) {
        reducedSelections.add((
          selection: current.selection,
          startLine: current.startLine,
          endLine: current.endLine,
          primary: current.primary,
        ));
        continue;
      }

      final previous = reducedSelections.last;
      if (previous.selection.isCollapsed) {
        if (previous.endLine == current.startLine) {
          // Code-OSS keeps the later same-line selection and transfers the
          // primary cursor when the earlier one was primary.
          reducedSelections
            ..removeLast()
            ..add((
              selection: current.selection,
              startLine: current.startLine,
              endLine: current.endLine,
              primary: previous.primary || current.primary,
            ));
          continue;
        }
        if (current.startLine > previous.endLine + 1) {
          reducedSelections.add((
            selection: current.selection,
            startLine: current.startLine,
            endLine: current.endLine,
            primary: current.primary,
          ));
          continue;
        }
      } else if (current.startLine > previous.endLine) {
        reducedSelections.add((
          selection: current.selection,
          startLine: current.startLine,
          endLine: current.endLine,
          primary: current.primary,
        ));
        continue;
      }

      final mergedSelection = TextSelection(
        baseOffset: previous.selection.start,
        extentOffset: previous.selection.end > current.selection.end
            ? previous.selection.end
            : current.selection.end,
        affinity: previous.selection.affinity,
        isDirectional: false,
      );
      reducedSelections
        ..removeLast()
        ..add((
          selection: mergedSelection,
          startLine: previous.startLine,
          endLine: previous.endLine > current.endLine
              ? previous.endLine
              : current.endLine,
          primary: previous.primary || current.primary,
        ));
    }

    final plans = <({
      TextSelection selection,
      bool primary,
      bool collapsed,
      bool sameLine,
      int rangeStart,
      int rangeEnd,
      int startCharacter,
      int endCharacter,
      int selectionEndSuffix,
      String removed,
      String inserted,
      int columnDeltaOffset,
      bool join,
    })>[];
    var payloadChars = 0;
    try {
      for (final lines in reducedSelections) {
        final start = doc.doc.positionAt(lines.selection.start);
        final end = doc.doc.positionAt(lines.selection.end);
        if (start.version != expectedVersion ||
            end.version != expectedVersion) {
          throw StateError('文档版本在解析合并行范围时发生变化');
        }
        final endLine = lines.selection.isCollapsed || start.line == end.line
            ? (start.line < documentStart.lineCount - 1
                ? start.line + 1
                : start.line)
            : end.line;
        final first = doc.doc.lineOffset(start.line);
        final last = doc.doc.lineOffset(endLine);
        if (first.version != expectedVersion ||
            last.version != expectedVersion) {
          throw StateError('文档版本在读取合并行边界时发生变化');
        }
        final lastBoundary = doc.doc.lineBoundary(last.offsetUtf16);
        if (lastBoundary.version != expectedVersion ||
            lastBoundary.line != endLine ||
            lastBoundary.endUtf16 < first.offsetUtf16) {
          throw StateError('Rust 返回了无效的合并行边界');
        }
        final sameLine = start.line == end.line;
        if (endLine == start.line) {
          plans.add((
            selection: lines.selection,
            primary: lines.primary,
            collapsed: lines.selection.isCollapsed,
            sameLine: sameLine,
            rangeStart: first.offsetUtf16,
            rangeEnd: lastBoundary.endUtf16,
            startCharacter: start.character,
            endCharacter: end.character,
            selectionEndSuffix: 0,
            removed: '',
            inserted: '',
            columnDeltaOffset: 0,
            join: false,
          ));
          continue;
        }

        final rangeLength = lastBoundary.endUtf16 - first.offsetUtf16;
        final remaining = _undoHistoryBudget.maxTotalChars - payloadChars;
        if (rangeLength < 0 || rangeLength > remaining ~/ 2) {
          throw StateError(
              '合并行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        final removed = _readDocumentRange(
          doc,
          first.offsetUtf16,
          lastBoundary.endUtf16,
        );
        if (removed.length != rangeLength) {
          throw StateError('Rust 返回的合并行文本长度与 UTF-16 范围不符');
        }
        final joined = _joinLineContents(removed);
        final cost = removed.length + joined.text.length;
        if (cost > remaining) {
          throw StateError(
              '合并行撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        payloadChars += cost;
        final endLineLength = lastBoundary.endUtf16 - last.offsetUtf16;
        final suffix = endLineLength - end.character;
        if (suffix < 0) {
          throw StateError('Rust 返回了无效的合并行选区末尾');
        }
        plans.add((
          selection: lines.selection,
          primary: lines.primary,
          collapsed: lines.selection.isCollapsed,
          sameLine: sameLine,
          rangeStart: first.offsetUtf16,
          rangeEnd: lastBoundary.endUtf16,
          startCharacter: start.character,
          endCharacter: end.character,
          selectionEndSuffix: suffix,
          removed: removed,
          inserted: joined.text,
          columnDeltaOffset: joined.columnDeltaOffset,
          join: true,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '合并行未应用：$error');
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '合并行未应用：文档版本已变化');
      return;
    }

    final changedIndices = <int>[
      for (var index = 0; index < plans.length; index++)
        if (plans[index].join && plans[index].removed != plans[index].inserted)
          index,
    ];
    final planStartsAfterEdits = <int>[];
    var cumulativeDelta = 0;
    for (final plan in plans) {
      planStartsAfterEdits.add(plan.rangeStart + cumulativeDelta);
      if (plan.join && plan.removed != plan.inserted) {
        cumulativeDelta += plan.inserted.length - plan.removed.length;
      }
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final index in changedIndices.reversed) {
      final plan = plans[index];
      final mappedStart = planStartsAfterEdits[index];
      forward.add(TextOp.delete(
        plan.rangeStart,
        plan.rangeEnd - plan.rangeStart,
      ));
      if (plan.inserted.isNotEmpty) {
        forward.add(TextOp.insert(plan.rangeStart, plan.inserted));
        inverse.add(TextOp.delete(mappedStart, plan.inserted.length));
      }
      inverse.add(TextOp.insert(mappedStart, plan.removed));
    }

    final mappedByPlan = <TextSelection>[];
    TextSelection? mappedPrimary;
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      final mappedStart = planStartsAfterEdits[index];
      late final TextSelection mapped;
      if (!plan.join) {
        if (plan.collapsed) {
          mapped = TextSelection.collapsed(
            offset: mappedStart + plan.rangeEnd - plan.rangeStart,
            affinity: plan.selection.affinity,
          );
        } else {
          mapped = TextSelection(
            baseOffset: mappedStart + plan.startCharacter,
            extentOffset: mappedStart + plan.endCharacter,
            affinity: plan.selection.affinity,
            isDirectional: false,
          );
        }
      } else if (plan.collapsed) {
        mapped = TextSelection.collapsed(
          offset: mappedStart + plan.inserted.length - plan.columnDeltaOffset,
          affinity: plan.selection.affinity,
        );
      } else if (plan.sameLine) {
        mapped = TextSelection(
          baseOffset: mappedStart + plan.startCharacter,
          extentOffset: mappedStart + plan.endCharacter,
          affinity: plan.selection.affinity,
          isDirectional: false,
        );
      } else {
        mapped = TextSelection(
          baseOffset: mappedStart + plan.startCharacter,
          extentOffset:
              mappedStart + plan.inserted.length - plan.selectionEndSuffix - 1,
          affinity: plan.selection.affinity,
          isDirectional: false,
        );
      }
      if (plan.primary) {
        mappedPrimary = mapped;
      } else {
        mappedByPlan.add(mapped);
      }
    }
    final newLength = documentStart.totalUtf16Length + cumulativeDelta;
    final mappedSelections = normalizeSelectionSet([
      if (mappedPrimary != null)
        TextSelection(
          baseOffset: mappedPrimary.baseOffset.clamp(0, newLength).toInt(),
          extentOffset: mappedPrimary.extentOffset.clamp(0, newLength).toInt(),
          affinity: mappedPrimary.affinity,
          isDirectional: mappedPrimary.isDirectional,
        ),
      for (final selection in mappedByPlan)
        TextSelection(
          baseOffset: selection.baseOffset.clamp(0, newLength).toInt(),
          extentOffset: selection.extentOffset.clamp(0, newLength).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);

    if (forward.isNotEmpty) {
      try {
        doc.doc.applyWith(expectedVersion, forward);
      } on AlulaException catch (error) {
        if (mounted) {
          setState(
              () => _statusDetail = '合并行未应用：${error.code} ${error.detail}');
        }
        return;
      }
      _recordDocumentOperations(
        doc,
        forward: forward,
        inverse: inverse,
        beforeCaret: selections.first.extentOffset,
        afterCaret: mappedSelections.first.extentOffset,
        coalesce: false,
      );
      _setDocSelections(doc, mappedSelections, recordHistory: false);
      doc.replaceInputWindow(
        mappedSelections.first.extentOffset,
        selection: mappedSelections.first,
      );
      _refreshSiblingViews(doc, forward);
      _onFindTextChanged();
      _syncCommandContext();
    } else {
      _setDocSelections(doc, mappedSelections);
    }
    if (mounted) setState(() => _statusDetail = '已合并行');
  }

  ({String text, int columnDeltaOffset}) _joinLineContents(String source) {
    var firstLineEnd = source.indexOf('\n');
    if (firstLineEnd < 0) return (text: source, columnDeltaOffset: 0);

    final joined = StringBuffer();
    final trailingWhitespace = StringBuffer();
    var joinedLength = 0;
    var trailingLength = 0;
    var lastCodeUnit = -1;

    bool isWhitespace(int value) =>
        value == 0x0009 ||
        value == 0x000a ||
        value == 0x000b ||
        value == 0x000c ||
        value == 0x000d ||
        value == 0x0020 ||
        value == 0x00a0 ||
        value == 0x1680 ||
        (value >= 0x2000 && value <= 0x200a) ||
        value == 0x2028 ||
        value == 0x2029 ||
        value == 0x202f ||
        value == 0x205f ||
        value == 0x3000 ||
        value == 0xfeff;

    void appendInitialLine(String line) {
      var suffixStart = line.length;
      while (
          suffixStart > 0 && isWhitespace(line.codeUnitAt(suffixStart - 1))) {
        suffixStart--;
      }
      joined.write(line.substring(0, suffixStart));
      joinedLength += suffixStart;
      trailingWhitespace.write(line.substring(suffixStart));
      trailingLength = line.length - suffixStart;
      if (line.isNotEmpty) lastCodeUnit = line.codeUnitAt(line.length - 1);
    }

    void flushTrailingWhitespace() {
      if (trailingLength == 0) return;
      joined.write(trailingWhitespace.toString());
      joinedLength += trailingLength;
      trailingWhitespace.clear();
      trailingLength = 0;
    }

    void appendJoinedLine(String line) {
      flushTrailingWhitespace();
      var suffixStart = line.length;
      while (
          suffixStart > 0 && isWhitespace(line.codeUnitAt(suffixStart - 1))) {
        suffixStart--;
      }
      joined.write(line.substring(0, suffixStart));
      joinedLength += suffixStart;
      trailingWhitespace.write(line.substring(suffixStart));
      trailingLength = line.length - suffixStart;
      if (line.isNotEmpty) lastCodeUnit = line.codeUnitAt(line.length - 1);
    }

    appendInitialLine(source.substring(0, firstLineEnd));
    var cursor = firstLineEnd + 1;
    var columnDeltaOffset = 0;
    while (cursor <= source.length) {
      final nextNewline = source.indexOf('\n', cursor);
      final end = nextNewline < 0 ? source.length : nextNewline;
      final line = source.substring(cursor, end);
      var firstNonWhitespace = 0;
      while (firstNonWhitespace < line.length &&
          isWhitespace(line.codeUnitAt(firstNonWhitespace))) {
        firstNonWhitespace++;
      }
      if (firstNonWhitespace < line.length) {
        var insertSpace = true;
        if (joinedLength + trailingLength == 0) insertSpace = false;
        if (insertSpace && (lastCodeUnit == 0x0020 || lastCodeUnit == 0x0009)) {
          trailingWhitespace
            ..clear()
            ..write(' ');
          trailingLength = 1;
          lastCodeUnit = 0x0020;
          insertSpace = false;
        }
        if (insertSpace) {
          flushTrailingWhitespace();
          joined.write(' ');
          joinedLength++;
          lastCodeUnit = 0x0020;
        }
        final content = line.substring(firstNonWhitespace);
        appendJoinedLine(content);
        columnDeltaOffset = content.length + (insertSpace ? 1 : 0);
      } else {
        columnDeltaOffset = 0;
      }
      if (nextNewline < 0) break;
      cursor = nextNewline + 1;
    }

    final result = StringBuffer()
      ..write(joined.toString())
      ..write(trailingWhitespace.toString());
    return (text: result.toString(), columnDeltaOffset: columnDeltaOffset);
  }

  Future<void> _insertLine({required bool before}) async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '插入行已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final plans = <({
      int start,
      String text,
      bool preserveSelection,
      List<int> selectionIndices,
    })>[];
    final planByStart = <int, int>{};
    var inspectedUtf16 = 0;

    void addPlan({
      required int start,
      required String text,
      required bool preserveSelection,
      required int selectionIndex,
    }) {
      final existingIndex = planByStart[start];
      if (existingIndex == null) {
        planByStart[start] = plans.length;
        plans.add((
          start: start,
          text: text,
          preserveSelection: preserveSelection,
          selectionIndices: [selectionIndex],
        ));
        return;
      }
      final existing = plans[existingIndex];
      if (existing.text != text ||
          existing.preserveSelection != preserveSelection) {
        throw StateError('多个光标在同一行插入位置产生了冲突');
      }
      existing.selectionIndices.add(selectionIndex);
    }

    try {
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final position = doc.doc.positionAt(selection.extentOffset);
        if (position.version != expectedVersion) {
          throw StateError('文档版本在解析插入行位置时发生变化');
        }

        if (before && position.line == 0) {
          // VS Code keeps the original cursor/selection on the source line
          // when inserting the first line at the beginning of the document.
          addPlan(
            start: 0,
            text: '\n',
            preserveSelection: true,
            selectionIndex: index,
          );
          continue;
        }

        final targetLine = before ? position.line - 1 : position.line;
        final lineStart = doc.doc.lineOffset(targetLine);
        if (lineStart.version != expectedVersion) {
          throw StateError('文档版本在读取插入行边界时发生变化');
        }
        final boundary = doc.doc.lineBoundary(lineStart.offsetUtf16);
        if (boundary.version != expectedVersion) {
          throw StateError('文档版本在读取插入行边界时发生变化');
        }
        final indentLength =
            boundary.firstNonWhitespaceUtf16 - boundary.startUtf16;
        if (indentLength < 0 ||
            indentLength > _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
          throw StateError('插入行缩进超过单次读取上限');
        }
        inspectedUtf16 += indentLength;
        final indentation = _readDocumentRange(
          doc,
          boundary.startUtf16,
          boundary.firstNonWhitespaceUtf16,
        );
        final text = '\n$indentation';
        addPlan(
          start: boundary.endUtf16,
          text: text,
          preserveSelection: false,
          selectionIndex: index,
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '插入行未应用：$error');
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '插入行未应用：文档版本已变化');
      return;
    }
    plans.sort((a, b) => a.start.compareTo(b.start));
    final payloadChars =
        plans.fold<int>(0, (sum, plan) => sum + plan.text.length);
    if (payloadChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '插入行已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    var deltaBefore = 0;
    final mappedStarts = <int>[];
    for (final plan in plans) {
      mappedStarts.add(plan.start + deltaBefore);
      deltaBefore += plan.text.length;
    }
    final forward = <TextOp>[
      for (final plan in plans.reversed) TextOp.insert(plan.start, plan.text),
    ];
    final inverse = <TextOp>[
      for (var index = plans.length - 1; index >= 0; index--)
        TextOp.delete(mappedStarts[index], plans[index].text.length),
    ];

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '插入行未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
    final mappedBySelection =
        List<TextSelection?>.filled(selections.length, null);
    for (var planIndex = 0; planIndex < plans.length; planIndex++) {
      final plan = plans[planIndex];
      final mappedStart = mappedStarts[planIndex];
      for (final selectionIndex in plan.selectionIndices) {
        final selection = selections[selectionIndex];
        if (plan.preserveSelection) {
          int mapOffset(int offset) {
            var delta = 0;
            for (final prior in plans) {
              if (prior.start > offset) break;
              delta += prior.text.length;
            }
            return (offset + delta).clamp(0, newLength).toInt();
          }

          mappedBySelection[selectionIndex] = TextSelection(
            baseOffset: mapOffset(selection.baseOffset),
            extentOffset: mapOffset(selection.extentOffset),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          );
        } else {
          mappedBySelection[selectionIndex] =
              TextSelection.collapsed(offset: mappedStart + plan.text.length);
        }
      }
    }
    final mappedSelections = normalizeSelectionSet([
      for (final selection in mappedBySelection)
        if (selection != null)
          TextSelection(
            baseOffset: selection.baseOffset.clamp(0, newLength).toInt(),
            extentOffset: selection.extentOffset.clamp(0, newLength).toInt(),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          ),
    ]);
    if (mappedSelections.isEmpty) return;

    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = before ? '已在上方插入行' : '已在下方插入行');
  }

  Future<void> _insertNewlineWithIndent() async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(
          () =>
              _statusDetail = 'Enter 已取消：选区数超过 $maxDocLineDeleteSelections 上限',
        );
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final edits = <({
      int start,
      int end,
      String text,
      String removed,
      int selectionIndex,
      int caretOffset,
    })>[];
    var inspectedUtf16 = 0;
    final isRust = doc.path?.toLowerCase().endsWith('.rs') == true;
    final totalUtf16 = doc.inputWindow.totalUtf16Length;
    try {
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final line = doc.doc.lineBoundary(selection.start);
        if (line.version != expectedVersion) {
          throw StateError('文档版本在读取 Enter 缩进时发生变化');
        }

        final prefixLength = selection.start - line.startUtf16;
        final selectionLength = selection.end - selection.start;
        if (prefixLength < 0 ||
            prefixLength > _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
          throw StateError('Enter 缩进前缀超过单次操作上限');
        }
        inspectedUtf16 += prefixLength;
        if (selectionLength >
            _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
          throw StateError('Enter 选区超过单次操作上限');
        }
        inspectedUtf16 += selectionLength;

        final prefix = _readDocumentRange(
          doc,
          line.startUtf16,
          selection.start,
        );
        final indentation = prefix.substring(0, leadingIndentLength(prefix));
        final removed = selection.isCollapsed
            ? ''
            : _readDocumentRange(doc, selection.start, selection.end);
        var text = '\n$indentation';
        var caretOffset = text.length;
        var continuesRustLineComment = false;
        if (isRust &&
            selection.isCollapsed &&
            _rustOnEnterCommentBefore.hasMatch(prefix)) {
          final suffixLength = line.endUtf16 - selection.end;
          if (suffixLength >= 0 &&
              suffixLength <=
                  _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
            inspectedUtf16 += suffixLength;
            final afterText = _readDocumentRange(
              doc,
              selection.end,
              line.endUtf16,
            );
            continuesRustLineComment =
                _rustOnEnterCommentAfter.hasMatch(afterText);
          }
        }
        if (continuesRustLineComment) {
          text = '\n$indentation// ';
          caretOffset = text.length;
        }
        if (!continuesRustLineComment &&
            isRust &&
            selection.isCollapsed &&
            selection.start > 0 &&
            selection.end < totalUtf16 &&
            _rustAutoClosingBracketPairs.entries.any((pair) =>
                doc.hasAutoClosedBracketAt(selection.end, pair.value))) {
          if (2 > _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
            throw StateError('Rust 括号检查超过单次操作上限');
          }
          inspectedUtf16 += 2;
          final pair = _readDocumentRange(
            doc,
            selection.start - 1,
            selection.end + 1,
          );
          if (pair.length == 2 &&
              _rustAutoClosingBracketPairs[pair[0]] == pair[1]) {
            final innerIndentation = '$indentation    ';
            text = '\n$innerIndentation\n$indentation';
            caretOffset = 1 + innerIndentation.length;
          }
        }
        edits.add((
          start: selection.start,
          end: selection.end,
          text: text,
          removed: removed,
          selectionIndex: index,
          caretOffset: caretOffset,
        ));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusDetail = 'Enter 未应用：$error');
      }
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = 'Enter 未应用：文档版本已变化');
      return;
    }

    edits.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.selectionIndex.compareTo(b.selectionIndex));
    var payloadChars = 0;
    for (var index = 0; index < edits.length; index++) {
      final edit = edits[index];
      if (index > 0 &&
          (edit.start < edits[index - 1].end ||
              edit.start == edits[index - 1].start)) {
        if (mounted) {
          setState(() => _statusDetail = 'Enter 未应用：多光标编辑范围重叠');
        }
        return;
      }
      payloadChars += edit.removed.length + edit.text.length;
    }
    if (payloadChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            'Enter 已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    var deltaBefore = 0;
    final mappedStarts = <int>[];
    for (final edit in edits) {
      mappedStarts.add(edit.start + deltaBefore);
      deltaBefore += edit.text.length - (edit.end - edit.start);
    }
    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final edit in edits.reversed) {
      if (edit.end > edit.start) {
        forward.add(TextOp.delete(edit.start, edit.end - edit.start));
      }
      forward.add(TextOp.insert(edit.start, edit.text));
    }
    for (var index = edits.length - 1; index >= 0; index--) {
      final edit = edits[index];
      final mappedStart = mappedStarts[index];
      inverse.add(TextOp.delete(mappedStart, edit.text.length));
      if (edit.removed.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, edit.removed));
      }
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = 'Enter 未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
    final mappedBySelection =
        List<TextSelection?>.filled(selections.length, null);
    for (var index = 0; index < edits.length; index++) {
      final edit = edits[index];
      final caret = (mappedStarts[index] + edit.caretOffset)
          .clamp(0, newLength)
          .toInt();
      mappedBySelection[edit.selectionIndex] =
          TextSelection.collapsed(offset: caret);
    }
    final mappedSelections = normalizeSelectionSet([
      for (final selection in mappedBySelection)
        if (selection != null) selection,
    ]);
    if (mappedSelections.isEmpty) return;

    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) {
      setState(() => _statusDetail = '已继承当前行缩进');
    }
  }

  Future<void> _applyRustBracketInput(String character) async {
    final doc = _active;
    if (doc == null ||
        doc.inputWindow.hasComposition ||
        doc.path?.toLowerCase().endsWith('.rs') != true) {
      return;
    }

    final autoCloser = _rustAutoClosingPairs[character];
    final closer = autoCloser ?? _rustSelectionSurroundingPairs[character];
    final isOpening = closer != null;
    if (!isOpening && !_rustAutoClosingPairs.values.contains(character)) {
      return;
    }

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '括号输入已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final totalUtf16 = doc.inputWindow.totalUtf16Length;
    final plans = <({
      int start,
      int end,
      String replacement,
      String removed,
      int selectionIndex,
      int baseInReplacement,
      int extentInReplacement,
      TextSelection original,
      bool skipExistingCloser,
      bool addAutoClosedMarker,
      int closeInReplacement,
    })>[];
    var inspectedUtf16 = 0;
    try {
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final selectedLength = selection.end - selection.start;
        if (selectedLength >
            _undoHistoryBudget.maxTotalChars - inspectedUtf16) {
          throw StateError('选区超过单次操作上限');
        }
        inspectedUtf16 += selectedLength;

        final removed = selection.isCollapsed
            ? ''
            : _readDocumentRange(doc, selection.start, selection.end);
        final nextCharacter = selection.end < totalUtf16
            ? _readDocumentRange(doc, selection.end, selection.end + 1)
            : '';
        if (character == '"' &&
            selection.isCollapsed &&
            nextCharacter == character &&
            doc.hasAutoClosedBracketAt(selection.start, character)) {
          plans.add((
            start: selection.start,
            end: selection.end,
            replacement: '',
            removed: '',
            selectionIndex: index,
            baseInReplacement: 1,
            extentInReplacement: 1,
            original: selection,
            skipExistingCloser: true,
            addAutoClosedMarker: false,
            closeInReplacement: -1,
          ));
          continue;
        }
        if (isOpening) {
          final wrapSelection = !selection.isCollapsed;
          final mayAutoCloseInContext = autoCloser != null &&
              (character != '"' ||
                  _rustStringContextAt(doc, selection.start) ==
                      RustStringContext.outside);
          final canCloseBefore = nextCharacter.isEmpty ||
              _rustAutoCloseBefore.contains(nextCharacter);
          final alreadyHasCloser =
              selection.isCollapsed && nextCharacter == closer;
          final appendCloser = wrapSelection ||
              (autoCloser != null &&
                  mayAutoCloseInContext &&
                  canCloseBefore &&
                  !alreadyHasCloser);
          final replacement = wrapSelection
              ? '$character$removed$closer'
              : appendCloser
                  ? '$character$closer'
                  : character;
          plans.add((
            start: selection.start,
            end: selection.end,
            replacement: replacement,
            removed: removed,
            selectionIndex: index,
            baseInReplacement: wrapSelection
                ? 1 + selection.baseOffset - selection.start
                : character.length,
            extentInReplacement: wrapSelection
                ? 1 + selection.extentOffset - selection.start
                : character.length,
            original: selection,
            skipExistingCloser: false,
            addAutoClosedMarker: autoCloser != null && appendCloser,
            closeInReplacement: autoCloser != null && appendCloser
                ? replacement.length - 1
                : -1,
          ));
          continue;
        }

        final skipExistingCloser = selection.isCollapsed &&
            nextCharacter == character &&
            nextCharacter.isNotEmpty &&
            doc.hasAutoClosedBracketAt(selection.start, character);
        plans.add((
          start: selection.start,
          end: selection.end,
          replacement: skipExistingCloser ? '' : character,
          removed: removed,
          selectionIndex: index,
          baseInReplacement: skipExistingCloser ? 1 : character.length,
          extentInReplacement: skipExistingCloser ? 1 : character.length,
          original: selection,
          skipExistingCloser: skipExistingCloser,
          addAutoClosedMarker: false,
          closeInReplacement: -1,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '括号输入未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '括号输入未应用：文档版本已变化');
      return;
    }

    plans.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.selectionIndex.compareTo(b.selectionIndex));
    var payloadChars = 0;
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      if (index > 0 &&
          (plan.start < plans[index - 1].end ||
              plan.start == plans[index - 1].start)) {
        if (mounted) {
          setState(() => _statusDetail = '括号输入未应用：多光标编辑范围重叠');
        }
        return;
      }
      payloadChars += plan.removed.length + plan.replacement.length;
    }
    if (payloadChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '括号输入已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    var deltaBefore = 0;
    final mappedSelections =
        List<TextSelection?>.filled(selections.length, null);
    final mappedStarts = List<int>.filled(plans.length, 0);
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      final mappedStart = plan.start + deltaBefore;
      mappedStarts[index] = mappedStart;
      mappedSelections[plan.selectionIndex] = TextSelection(
        baseOffset: mappedStart + plan.baseInReplacement,
        extentOffset: mappedStart + plan.extentInReplacement,
        affinity: plan.original.affinity,
        isDirectional: plan.original.isDirectional,
      );
      deltaBefore += plan.replacement.length - (plan.end - plan.start);
    }
    final orderedSelections = normalizeSelectionSet([
      for (final selection in mappedSelections)
        if (selection != null) selection,
    ]);
    if (orderedSelections.isEmpty) return;

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in plans.reversed) {
      if (plan.skipExistingCloser) continue;
      if (plan.end > plan.start) {
        forward.add(TextOp.delete(plan.start, plan.end - plan.start));
      }
      forward.add(TextOp.insert(plan.start, plan.replacement));
    }
    for (var index = plans.length - 1; index >= 0; index--) {
      final plan = plans[index];
      if (plan.skipExistingCloser) continue;
      final mappedStart = mappedStarts[index];
      inverse.add(TextOp.delete(mappedStart, plan.replacement.length));
      if (plan.removed.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, plan.removed));
      }
    }
    if (forward.isEmpty) {
      for (var index = 0; index < plans.length; index++) {
        final plan = plans[index];
        if (plan.skipExistingCloser) {
          doc.consumeAutoClosedBracketAt(mappedStarts[index], character);
        }
      }
      _setDocSelections(doc, orderedSelections);
      if (mounted) setState(() => _statusDetail = '已跳过现有右括号');
      return;
    }
    if (_operationPayloadChars([forward, inverse]) >
        _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '括号输入已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '括号输入未应用：${error.code} ${error.detail}');
      }
      return;
    }

    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: orderedSelections.first.extentOffset,
      coalesce: false,
    );
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      if (plan.skipExistingCloser) {
        doc.consumeAutoClosedBracketAt(mappedStarts[index], character);
      } else if (plan.addAutoClosedMarker) {
        doc.addAutoClosedBracketMarker(
          openOffsetUtf16: mappedStarts[index],
          closeOffsetUtf16: mappedStarts[index] + plan.closeInReplacement,
          close: _rustAutoClosingPairs[character]!,
        );
      }
    }
    doc.replaceInputWindow(
      orderedSelections.first.extentOffset,
      selection: orderedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _setDocSelections(doc, orderedSelections, recordHistory: false);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已输入 Rust 括号');
  }

  _RustBracketBackspace? _rustBracketBackspacePlan(OpenDoc doc) {
    if (doc.path?.toLowerCase().endsWith('.rs') != true ||
        doc.inputWindow.hasComposition ||
        doc.crossWindowSelection != null) {
      return null;
    }

    try {
      _flushInput(doc);
      final selections = normalizeSelectionSet(doc.selectionSet);
      if (selections.isEmpty ||
          selections.length > maxDocLineDeleteSelections ||
          selections.any((selection) => !selection.isCollapsed)) {
        return null;
      }

      final version = doc.doc.version;
      final totalUtf16 = doc.inputWindow.totalUtf16Length;
      final plans = <_RustBracketDeletePlan>[];
      for (var index = 0; index < selections.length; index++) {
        final selection = selections[index];
        final caret = selection.extentOffset;
        if (caret <= 0 || caret >= totalUtf16) return null;

        final pair = _readDocumentRange(doc, caret - 1, caret + 1);
        if (pair.length != 2) return null;
        final open = pair[0];
        final close = pair[1];
        if (_rustAutoClosingPairs[open] != close ||
            !doc.hasAutoClosedBracketAt(caret, close)) {
          return null;
        }
        plans.add((
          start: caret - 1,
          removed: '$open$close',
          selectionIndex: index,
          selection: selection,
        ));
      }
      if (doc.doc.version != version) return null;

      plans.sort((a, b) => a.start.compareTo(b.start));
      for (var index = 1; index < plans.length; index++) {
        if (plans[index].start <
            plans[index - 1].start + plans[index - 1].removed.length) {
          return null;
        }
      }
      return (version: version, selections: selections, plans: plans);
    } on Object {
      return null;
    }
  }

  Future<void> _applyRustBracketBackspace(
    OpenDoc doc,
    _RustBracketBackspace backspace,
  ) async {
    if (doc.inputWindow.hasComposition ||
        doc.doc.version != backspace.version) {
      return;
    }
    final currentSelections = normalizeSelectionSet(doc.selectionSet);
    if (currentSelections.length != backspace.selections.length ||
        currentSelections
            .asMap()
            .entries
            .any((entry) => entry.value != backspace.selections[entry.key])) {
      return;
    }

    final deletedUtf16 = backspace.plans.fold<int>(
      0,
      (total, plan) => total + plan.removed.length,
    );
    if (deletedUtf16 > _undoHistoryBudget.maxTotalChars) return;

    final mappedStarts = List<int>.filled(backspace.selections.length, 0);
    var removedBefore = 0;
    for (final plan in backspace.plans) {
      mappedStarts[plan.selectionIndex] = plan.start - removedBefore;
      removedBefore += plan.removed.length;
    }

    final forward = [
      for (final plan in backspace.plans.reversed)
        TextOp.delete(plan.start, plan.removed.length),
    ];
    final inverse = [
      for (final plan in backspace.plans.reversed)
        TextOp.insert(mappedStarts[plan.selectionIndex], plan.removed),
    ];
    try {
      doc.doc.applyWith(backspace.version, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '自动配对删除未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final mappedSelections = normalizeSelectionSet([
      for (var index = 0; index < backspace.selections.length; index++)
        TextSelection.collapsed(
          offset: mappedStarts[index],
          affinity: backspace.selections[index].affinity,
        ),
    ]);
    if (mappedSelections.isEmpty) return;

    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: backspace.selections.first.extentOffset,
      afterCaret: mappedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已删除 Rust 自动配对括号');
  }

  Future<void> _cutCrossWindowSelection(OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final selection = doc.crossWindowSelection;
    if (selection == null || selection.isCollapsed) return;
    final version = doc.doc.version;
    final text = _readDocumentRange(doc, selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted ||
        doc.doc.version != version ||
        doc.crossWindowSelection != selection) {
      return;
    }
    _replaceCrossWindowSelection(doc, '', selectedText: text, version: version);
  }

  void _replaceCrossWindowSelection(
    OpenDoc doc,
    String replacement, {
    String? selectedText,
    int? version,
  }) {
    _flushInput(doc, commitComposition: true);
    _applyCrossWindowSelectionReplacement(
      doc,
      replacement,
      selectedText: selectedText,
      version: version,
    );
  }

  TextEditingValue? _handleCrossWindowTextInput(
    OpenDoc doc,
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (doc.crossWindowSelection == null) return null;
    final window = doc.inputWindow;
    final oldHadComposition =
        oldValue.composing.isValid && !oldValue.composing.isCollapsed;
    if (window.hasComposition &&
        oldHadComposition &&
        newValue.text == window.text) {
      window.cancelComposition();
      return window.initialValue.copyWith(
        selection: newValue.selection,
        composing: TextRange.empty,
      );
    }
    final operations = diffToOps(window.text, newValue.text);
    if (operations.isEmpty) return null;
    final replacement = StringBuffer();
    for (final operation in operations) {
      if (operation.type == OpType.insert) replacement.write(operation.text);
    }
    _applyCrossWindowSelectionReplacement(
      doc,
      replacement.toString(),
      refreshWindowInPlace: true,
    );
    return doc.inputWindow.initialValue;
  }

  void _applyCrossWindowSelectionReplacement(
    OpenDoc doc,
    String replacement, {
    String? selectedText,
    int? version,
    bool refreshWindowInPlace = false,
  }) {
    final selection = doc.crossWindowSelection;
    if (selection == null) return;
    final expectedVersion = version ?? doc.doc.version;
    if (doc.doc.version != expectedVersion) return;
    final removed =
        selectedText ?? _readDocumentRange(doc, selection.start, selection.end);
    final start = selection.start;
    final forward = <TextOp>[
      if (selection.start != selection.end)
        TextOp.delete(selection.start, selection.end - selection.start),
      if (replacement.isNotEmpty) TextOp.insert(start, replacement),
    ];
    if (forward.isEmpty) {
      doc.crossWindowSelection = null;
      if (refreshWindowInPlace) {
        doc.refreshInputWindowInPlace(start);
      } else {
        doc.replaceInputWindow(start);
      }
      if (mounted) setState(() {});
      return;
    }
    final inverse = <TextOp>[
      if (replacement.isNotEmpty) TextOp.delete(start, replacement.length),
      if (removed.isNotEmpty) TextOp.insert(start, removed),
    ];
    doc.doc.applyWith(expectedVersion, forward);
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selection.extentOffset,
      afterCaret: start + replacement.length,
      coalesce: false,
    );
    doc.crossWindowSelection = null;
    doc.additionalSelections = const [];
    doc.columnSelection = null;
    if (refreshWindowInPlace) {
      doc.refreshInputWindowInPlace(start + replacement.length);
    } else {
      doc.replaceInputWindow(start + replacement.length);
    }
    _refreshSiblingViews(doc, forward);
    if (mounted) setState(() {});
    _syncCommandContext();
  }

  Future<void> _pasteCrossWindowSelection(OpenDoc doc) async {
    final selection = doc.crossWindowSelection;
    if (selection == null) return;
    _flushInput(doc, commitComposition: true);
    final version = doc.doc.version;
    final clipboard = await Clipboard.getData('text/plain');
    if (!mounted ||
        clipboard == null ||
        doc.doc.version != version ||
        doc.crossWindowSelection != selection) {
      return;
    }
    _replaceCrossWindowSelection(
      doc,
      clipboard.text ?? '',
      version: version,
    );
  }

  Future<void> _copyMultiSelections(OpenDoc doc) async {
    await Clipboard.setData(
      ClipboardData(text: _copyableSelectionTexts(doc).join('\n')),
    );
  }

  Future<bool> _pasteMultiSelections(OpenDoc doc) async {
    if (doc.additionalSelections.isEmpty) return false;
    _flushInput(doc, commitComposition: true);
    final clipboard = await Clipboard.getData('text/plain');
    if (clipboard == null || !mounted || _active?.id != doc.id) return false;
    final field = doc.inputFieldKey.currentState;
    if (field == null) return false;
    _flushInput(doc, commitComposition: true);

    final windowStart = doc.inputWindow.startUtf16;
    final localSelections = doc.selectionSet
        .map((selection) => TextSelection(
              baseOffset: selection.baseOffset - windowStart,
              extentOffset: selection.extentOffset - windowStart,
              affinity: selection.affinity,
              isDirectional: selection.isDirectional,
            ))
        .toList(growable: false);
    final result = applyDistributedMultiSelectionPaste(
      oldValue: doc.editingValue,
      selections: localSelections,
      clipboardText: clipboard.text ?? '',
    );
    if (!result.changed) return true;

    doc.additionalSelections = List.unmodifiable(
      result.selections.map((selection) => TextSelection(
            baseOffset: selection.baseOffset + windowStart,
            extentOffset: selection.extentOffset + windowStart,
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          )),
    );
    doc.columnSelection = null;
    field.setEditingValue(result.value);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _pasteOvertype(OpenDoc doc) async {
    if (doc.inputWindow.hasComposition) return;
    _flushInput(doc, commitComposition: true);
    final expectedVersion = doc.doc.version;
    final selections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (selections.isEmpty) return;
    if (selections.length > maxDocOvertypePasteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '覆写粘贴已取消：选区数超过 $maxDocOvertypePasteSelections 上限');
      }
      return;
    }

    bool selectionSetUnchanged() {
      final current = normalizeSelectionSet([
        doc.selection,
        ...doc.additionalSelections,
      ]);
      if (current.length != selections.length) return false;
      for (var index = 0; index < current.length; index++) {
        if (current[index].baseOffset != selections[index].baseOffset ||
            current[index].extentOffset != selections[index].extentOffset) {
          return false;
        }
      }
      return true;
    }

    final clipboard = await Clipboard.getData('text/plain');
    if (!mounted ||
        clipboard == null ||
        _active?.id != doc.id ||
        doc.doc.version != expectedVersion ||
        !selectionSetUnchanged()) {
      return;
    }
    final clipboardText = clipboard.text ?? '';
    if (clipboardText.isEmpty) return;

    final pasteTexts = distributeClipboardPasteText(
      clipboardText: clipboardText,
      selectionCount: selections.length,
    );
    late final DocumentOvertypePasteRanges queried;
    try {
      queried = doc.doc.overtypePasteRanges([
        for (var index = 0; index < selections.length; index++)
          DocumentOvertypePasteSelection(
            startUtf16: selections[index].start,
            endUtf16: selections[index].end,
            insertedUtf16: pasteTexts[index].length,
          ),
      ]);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '覆写粘贴范围查询失败：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion ||
        queried.ranges.length != selections.length) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) {
        setState(() => _statusDetail = '覆写粘贴未应用：文档同步版本已变化');
      }
      return;
    }

    final candidates = <({
      int start,
      int end,
      String text,
      bool primary,
    })>[];
    for (var index = 0; index < queried.ranges.length; index++) {
      final range = queried.ranges[index];
      candidates.add((
        start: range.startUtf16,
        end: range.endUtf16,
        text: pasteTexts[index],
        primary: index == 0,
      ));
    }
    candidates.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end));
    final merged = <({
      int start,
      int end,
      String text,
      bool primary,
    })>[];
    for (final range in candidates) {
      if (merged.isEmpty || range.start >= merged.last.end) {
        merged.add(range);
        continue;
      }
      if (range.text != merged.last.text) {
        if (mounted) {
          setState(() => _statusDetail = '覆写粘贴已取消：多光标覆盖范围重叠且粘贴内容不同');
        }
        return;
      }
      final previous = merged.last;
      merged[merged.length - 1] = (
        start: previous.start,
        end: range.end > previous.end ? range.end : previous.end,
        text: previous.text,
        primary: previous.primary || range.primary,
      );
    }

    final operationChars = merged.fold<int>(
      0,
      (total, range) => total + (range.end - range.start) + range.text.length,
    );
    if (operationChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) {
        setState(() => _statusDetail =
            '覆写粘贴已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
      }
      return;
    }

    final plans = <({
      int start,
      int end,
      String text,
      bool primary,
      String removed,
      int mappedStart,
    })>[];
    var shift = 0;
    try {
      for (final range in merged) {
        final removed = _readDocumentRange(doc, range.start, range.end);
        final mappedStart = range.start + shift;
        plans.add((
          start: range.start,
          end: range.end,
          text: range.text,
          primary: range.primary,
          removed: removed,
          mappedStart: mappedStart,
        ));
        shift += range.text.length - (range.end - range.start);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '覆写粘贴未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '覆写粘贴未应用：文档版本已变化');
      return;
    }

    final forward = [
      for (final plan in plans.reversed) ...[
        if (plan.end > plan.start)
          TextOp.delete(plan.start, plan.end - plan.start),
        if (plan.text.isNotEmpty) TextOp.insert(plan.start, plan.text),
      ],
    ];
    if (forward.isEmpty) return;
    final inverse = [
      for (final plan in plans.reversed) ...[
        if (plan.text.isNotEmpty)
          TextOp.delete(plan.mappedStart, plan.text.length),
        if (plan.removed.isNotEmpty)
          TextOp.insert(plan.mappedStart, plan.removed),
      ],
    ];
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '覆写粘贴未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final afterByPlan = <({bool primary, TextSelection selection})>[
      for (final plan in plans)
        (
          primary: plan.primary,
          selection: TextSelection.collapsed(
            offset: plan.mappedStart + plan.text.length,
          ),
        ),
    ];
    final primaryIndex = afterByPlan.indexWhere((item) => item.primary);
    final afterSelections = [
      if (primaryIndex >= 0) afterByPlan[primaryIndex].selection,
      for (var index = 0; index < afterByPlan.length; index++)
        if (index != primaryIndex) afterByPlan[index].selection,
    ];
    final primarySelection = afterSelections.first;
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: primarySelection.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      primarySelection.extentOffset,
      selection: primarySelection,
    );
    _setDocSelections(doc, afterSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已覆写粘贴');
  }

  Future<bool> _cutMultiSelections(OpenDoc doc) async {
    final field = doc.inputFieldKey.currentState;
    if (field == null) return false;
    final selections = doc.selectionSet;
    if (selections.length < 2 ||
        selections.any((selection) => selection.isCollapsed)) {
      return false;
    }
    await Clipboard.setData(
      ClipboardData(text: _copyableSelectionTexts(doc).join('\n')),
    );
    final value = doc.editingValue;
    final selection = value.selection;
    final start = selection.baseOffset < selection.extentOffset
        ? selection.baseOffset
        : selection.extentOffset;
    final end = selection.baseOffset < selection.extentOffset
        ? selection.extentOffset
        : selection.baseOffset;
    if (start == end) return false;
    field.applyFormattedValue(TextEditingValue(
      text: value.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    ));
    return true;
  }

  void _moveColumnSelection({int lines = 0, int columns = 0}) {
    final doc = _active;
    if (doc == null) return;
    _flushInput(doc);
    final value = doc.editingValue;
    final text = value.text;
    final previous = doc.columnSelection;
    final state = previous ??
        () {
          final (line, column) = lineAndColumnAt(
            text,
            value.selection.extentOffset.clamp(0, text.length).toInt(),
          );
          return ColumnSelectionState(
            anchorLine: line,
            anchorColumn: column,
            activeLine: line,
            activeColumn: column,
          );
        }();
    final count = '\n'.allMatches(text).length + 1;
    final moved = state.move(lines: lines, columns: columns);
    final bounded = ColumnSelectionState(
      anchorLine: state.anchorLine.clamp(0, count - 1).toInt(),
      anchorColumn: state.anchorColumn,
      activeLine: moved.activeLine.clamp(0, count - 1).toInt(),
      activeColumn: moved.activeColumn,
    );
    final local = columnSelectionsForText(text, bounded);
    _setDocSelections(
      doc,
      _absoluteSelections(doc, local),
      columnSelection: bounded,
    );
  }

  void _cursorUndo() {
    final doc = _active;
    if (doc == null) return;
    final previous = doc.selectionHistory.undo(doc.selectionSet);
    if (previous != null) {
      _setDocSelections(doc, previous, recordHistory: false);
    }
    _syncCommandContext();
  }

  void _cursorRedo() {
    final doc = _active;
    if (doc == null) return;
    final next = doc.selectionHistory.redo(doc.selectionSet);
    if (next != null) {
      _setDocSelections(doc, next, recordHistory: false);
    }
    _syncCommandContext();
  }

  void _scheduleSelectionRefresh(OpenDoc doc) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _active?.id != doc.id || _disposing) return;
      setState(() {});
    });
  }

  void _applyProgrammaticEdit(
    OpenDoc doc,
    String newText, {
    required TextSelection selection,
    bool clearHistory = false,
    bool markSaved = false,
  }) {
    _flushInput(doc, commitComposition: true);
    doc.additionalSelections = const [];
    doc.columnSelection = null;
    final before = doc.doc.resync().content;
    final oldSelection = doc.selection;
    final ops = diffToOps(before, newText);
    if (ops.isNotEmpty) {
      final inverse = diffToOps(newText, before);
      doc.doc.apply(ops);
      _recordDocumentOperations(
        doc,
        forward: ops,
        inverse: inverse,
        beforeCaret: oldSelection.baseOffset,
        afterCaret: selection.extentOffset,
        coalesce: false,
        beforeSnapshot: before,
      );
    }
    if (markSaved) doc.doc.setSavepoint(newText);
    if (clearHistory) doc.undoStack.clear();
    doc.replaceInputWindow(selection.extentOffset, selection: selection);
    if (ops.isNotEmpty) _refreshSiblingViews(doc, ops);
    doc.lastEditAt = null;
    _updateDirty(doc);
    _syncCommandContext();
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    _scheduleSyntaxRefresh(doc.id);
    if (mounted) setState(() {});
  }

  void _onInputDelta(OpenDoc doc, RustTextInputDelta delta) {
    final owner = _ownerOfView(doc);
    if (owner == null) return;
    final isActiveOfFocused =
        owner.region == _focusedRegion && identical(owner.active, doc);
    final ops = delta.operations;
    if (ops.isNotEmpty) doc.crossWindowSelection = null;
    if (ops.isNotEmpty && !doc.undoRedoBusy) {
      final now = DateTime.now();
      final coalesce = doc.lastEditAt != null &&
          now.difference(doc.lastEditAt!) < const Duration(milliseconds: 400);
      final beforeSelection = delta.previousSelection;
      final afterSelection = delta.selection;
      final beforeCaret = beforeSelection?.baseOffset ??
          beforeSelection?.extentOffset ??
          afterSelection?.baseOffset ??
          0;
      _recordDocumentOperations(
        doc,
        forward: ops,
        inverse: delta.inverseOperations,
        coalesce: coalesce,
        beforeCaret: beforeCaret,
        afterCaret: afterSelection?.extentOffset ?? beforeCaret,
      );
    }
    _updateDirty(doc);
    final refreshedSiblingViews =
        ops.isEmpty ? 0 : _refreshSiblingViews(doc, ops);
    if (isActiveOfFocused && !_disposing) _syncCommandContext();
    if (ops.isNotEmpty) {
      if (_findVisible && !_disposing) _onFindTextChanged();
      if ((isActiveOfFocused || refreshedSiblingViews > 0) &&
          mounted &&
          !_disposing) {
        setState(() {
          if (isActiveOfFocused) {
            _state = WbSyncState.synced;
            _syncCount++;
            _statusDetail = '已同步 v${delta.version}（${ops.length} op）';
          }
        });
      }
    }

    final selection = delta.selection;
    if (!_disposing &&
        selection != null &&
        _shouldRecenterInputWindow(doc, selection)) {
      doc.replaceInputWindow(selection.extentOffset);
      if (mounted) setState(() {});
    }
  }

  int _refreshSiblingViews(OpenDoc source, List<TextOp> operations) {
    final siblings = _viewsOf(source)
        .where((view) => !identical(view, source))
        .toList(growable: false);
    if (siblings.isEmpty) return 0;
    final total = source.doc.readRange(0, maxLenUtf16: 2).totalUtf16Length;
    for (final view in siblings) {
      view.crossWindowSelection = null;
      if (view.inputWindow.pendingCount > 0 ||
          view.inputWindow.pendingText != null) {
        // Keep the local draft intact. This indicates a focus/flush ordering
        // defect and must never silently discard uncommitted text.
        _statusDetail = '同文档另一视图仍有未提交输入；已保留其本地草稿';
        continue;
      }
      TextSelection mapSelection(TextSelection selection) => TextSelection(
            baseOffset: mapWorkspaceEditOffset(
              selection.baseOffset,
              operations,
            ).clamp(0, total).toInt(),
            extentOffset: mapWorkspaceEditOffset(
              selection.extentOffset,
              operations,
            ).clamp(0, total).toInt(),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          );
      final mapped = mapSelection(view.selection);
      view.additionalSelections = List.unmodifiable(
        view.additionalSelections.map(mapSelection),
      );
      view.columnSelection = null;
      view.replaceInputWindow(mapped.extentOffset, selection: mapped);
    }
    return siblings.length;
  }

  bool _shouldRecenterInputWindow(OpenDoc doc, TextSelection selection) {
    final window = doc.inputWindow;
    if (window.startUtf16 == 0 && window.endUtf16 >= window.totalUtf16Length) {
      return false;
    }
    final local = selection.extentOffset - window.startUtf16;
    final margin = window.maxWindowUtf16 ~/ 8;
    return (window.startUtf16 > 0 && local < margin) ||
        (window.endUtf16 < window.totalUtf16Length &&
            local > window.text.length - margin);
  }

  @visibleForTesting
  bool applyWorkspaceEdit(WorkspaceEdit edit) {
    final core = _core;
    if (core == null) {
      _statusDetail = '工作区编辑失败：核心尚未就绪';
      return false;
    }
    try {
      for (final doc in _allDocViews) {
        _flushInput(doc, commitComposition: true);
      }
      final snapshots = _allDocs
          .where((doc) => doc.uri != null)
          .map((doc) => WorkspaceDocumentSnapshot(
                id: doc.id,
                uri: doc.uri!,
                version: doc.doc.version,
                text: doc.text,
                writable: doc.path != null &&
                    doc.diskState == DiskDocumentState.current,
              ));
      final plan = const WorkspaceEditPlanner().plan(edit, snapshots);
      final docsById = {for (final doc in _allDocs) doc.id: doc};
      final oldSelections = <int, TextSelection>{};
      for (final change in plan.documents) {
        final doc = docsById[change.id];
        if (doc == null || doc.text != change.before) {
          throw WorkspaceEditException(
            'Document changed while planning: ${change.uri}',
          );
        }
        oldSelections[change.id] = doc.selection;
      }

      final result = core.applyWorkspaceEdit([
        for (final change in plan.documents)
          AlulaWorkspaceEditDocument(
            id: change.id,
            baseVersion: change.baseVersion,
            ops: change.ops,
          ),
      ]);

      for (final change in plan.documents) {
        final doc = docsById[change.id]!;
        final oldSelection = oldSelections[change.id]!;
        final caret = oldSelection.baseOffset.clamp(0, change.before.length);
        final mappedSelection = TextSelection(
          baseOffset: mapWorkspaceEditOffset(
            oldSelection.baseOffset.clamp(0, change.before.length).toInt(),
            change.ops,
          ).clamp(0, change.after.length).toInt(),
          extentOffset: mapWorkspaceEditOffset(
            oldSelection.extentOffset.clamp(0, change.before.length).toInt(),
            change.ops,
          ).clamp(0, change.after.length).toInt(),
          affinity: oldSelection.affinity,
          isDirectional: oldSelection.isDirectional,
        );
        final inverse = diffToOps(change.after, change.before);
        if (_operationPayloadChars([change.ops, inverse]) >
            _undoHistoryBudget.maxTotalChars) {
          doc.undoStack.push(
            before: change.before,
            caret: caret,
            coalesce: false,
            encoding: doc.fileOptions.encoding.id,
            bom: doc.fileOptions.bom,
            lineEnding: doc.fileOptions.lineEnding.id,
            transactionId: plan.transactionId,
          );
        } else {
          doc.undoStack.pushOperations(
            forward: change.ops,
            inverse: inverse,
            caret: caret,
            redoCaret: mappedSelection.extentOffset,
            coalesce: false,
            encoding: doc.fileOptions.encoding.id,
            bom: doc.fileOptions.bom,
            lineEnding: doc.fileOptions.lineEnding.id,
            transactionId: plan.transactionId,
          );
        }
        doc.doc.version = result.versions[change.id]!;
        doc.replaceInputWindow(mappedSelection.extentOffset);
        if (change.ops.isNotEmpty) _refreshSiblingViews(doc, change.ops);
        doc.lastEditAt = null;
        _updateDirty(doc);
        _scheduleSyntaxRefresh(doc.id);
      }
      _scheduleStateSave();
      _scheduleOutlineRefresh();
      _syncCommandContext();
      _onFindTextChanged();
      setState(() => _statusDetail =
          '已应用跨文档编辑事务 ${plan.transactionId}（${plan.documents.length} 个文档）');
      return true;
    } on WorkspaceEditException catch (error) {
      setState(() => _statusDetail = '跨文档编辑未应用：${error.message}');
      return false;
    } on AlulaException catch (error) {
      setState(() => _statusDetail = '跨文档编辑已回滚：${error.code} ${error.detail}');
      return false;
    }
  }

  // ---------- 文件夹 / 文件树 ----------

  void _openFolder(String path) {
    final core = _core;
    if (core == null) return;
    try {
      final entries = core.workspace.listDir(path);
      if (_workspaceRoot != path) {
        _searchSub?.cancel();
        _searchSub = null;
        _searchGen++;
        _shutdownLspWorkspace();
        _lspReady = false;
        _lspStarting = false;
        _lspStatus = 'LSP 未启动';
        _diagnostics.clear();
        _syntaxByDoc.clear();
        _syntaxVersionByDoc.clear();
        _semanticTokensByDoc.clear();
        _semanticTokensVersionByDoc.clear();
        for (final timer in _syntaxRefreshTimers.values) {
          timer.cancel();
        }
        _syntaxRefreshTimers.clear();
        _pollTimer?.cancel();
        _pollTimer = null;
        for (final doc in _allDocs) {
          doc.lspAttached = false;
        }
      }
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
        _git = GitCli(
          root: path,
          registerProcess: core.runtime.registerProcess,
          unregisterProcess: core.runtime.unregisterProcess,
        );
        _refreshGit();
        _searchService = SearchService(
          root: path,
          registerProcess: core.runtime.registerProcess,
          unregisterProcess: core.runtime.unregisterProcess,
        );
        _layout.showRegion('sidebar');
        _scheduleStateSave();
      });
      _attachWorkspaceWatcher();
      _updateLanguageServicePolling();
      _startResourceMonitoring();
      _syncCommandContext();
    } on AlulaException catch (e) {
      setState(() {
        _statusDetail = '打开文件夹失败：${e.code}';
        _state = WbSyncState.error;
      });
    }
  }

  void _startResourceMonitoring() {
    _resourceTimer?.cancel();
    final core = _core;
    if (core == null || _workspaceRoot == null) return;

    void sample() {
      if (!mounted || _workspaceRoot == null) return;
      try {
        final status = core.runtime.sampleResourceStatus();
        if (!mounted) return;
        if (_resourceStatus?.pressure != status.pressure ||
            _resourceStatus?.availableBytes != status.availableBytes) {
          setState(() => _resourceStatus = status);
        } else {
          _resourceStatus = status;
        }
      } catch (error) {
        debugPrint('资源状态采样失败：$error');
      }
    }

    sample();
    _resourceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sample(),
    );
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
    final previous = _active;
    if (previous != null) _flushInput(previous, commitComposition: true);
    // 同一文件在不同组打开时共享 Rust 文档，但为组创建独立视图状态。
    for (final g in _groups.values) {
      final existing = g.docs.where((d) => d.path == path).firstOrNull;
      if (existing != null) {
        final target = _focused;
        final view = identical(g, target)
            ? existing
            : target.docs
                    .where((candidate) => candidate.sameDocumentAs(existing))
                    .firstOrNull ??
                OpenDoc.viewOf(existing);
        setState(() {
          if (!target.docs.contains(view)) target.docs.add(view);
          target.activeDocId = view.id;
          _focusedRegion = target.region;
        });
        _scheduleStateSave();
        _syncCommandContext();
        _scheduleSyntaxRefresh(view.id);
        return;
      }
    }
    DecodedTextFile file;
    try {
      file = core.workspace.readFileDocument(path);
    } on AlulaException catch (error) {
      if (error.code != 'BinaryFile' && error.code != 'UnsupportedEncoding') {
        setState(() => _statusDetail = '打开失败：${error.code}');
        return;
      }
      if (!mounted) return;
      final encoding = await _pickReopenEncoding(title: '选择文件编码');
      if (!mounted || encoding == null) return;
      try {
        file = core.workspace.readFileDocument(path, encoding: encoding);
      } on AlulaException catch (decodeError) {
        setState(
            () => _statusDetail = '按 ${encoding.id} 打开失败：${decodeError.code}');
        return;
      }
    }

    try {
      final content = file.content;
      final id = _nextDocId++;
      final doc = core.openDoc(id, content);
      final name = path.replaceAll('\\', '/').split('/').last;
      final open = OpenDoc(
        id: id,
        path: path,
        uri: _pathToUri(path),
        name: name,
        doc: doc,
        fileOptions: file.options,
        savedFileOptions: file.options,
        undoBudget: _undoHistoryBudget,
      );
      setState(() {
        final g = _focused;
        g.docs.add(open);
        g.activeDocId = id;
      });
      _scheduleSyntaxRefresh(id);
      _syncCommandContext();
      _scheduleStateSave();
      if (_lspReady) {
        try {
          core.lsp.setUri(id, open.uri!);
          core.lsp.didOpen(id, languageId: _languageIdOf(path));
          open.lspAttached = true;
        } catch (_) {}
      }
      _updateLanguageServicePolling();
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

  void _closeDoc(int id, {EditorGroup? group}) {
    final owner = group ??
        (_focused.docs.any((doc) => doc.id == id) ? _focused : _ownerOf(id));
    if (owner == null) return;
    final doc = owner.docs.where((d) => d.id == id).firstOrNull;
    if (doc == null) return;
    _flushInput(doc, commitComposition: true);
    final wasActive = owner.activeDocId == id;
    final focusKey = _focusKeyFor(owner, doc);
    _editorFocusNodes.remove(focusKey)?.dispose();
    final isLastView = doc.sharedViewCount == 1;
    if (isLastView) {
      _syntaxRefreshTimers.remove(id)?.cancel();
      if (doc.lspAttached && _lspReady) {
        try {
          doc.doc.core.lsp.didClose(id);
        } catch (_) {}
      }
    }
    final nextSyntax = Map<int, List<Map<String, Object?>>>.of(_syntaxByDoc);
    final nextSyntaxVersion = Map<int, int>.of(_syntaxVersionByDoc);
    final nextSemanticTokens =
        Map<int, List<Map<String, Object?>>>.of(_semanticTokensByDoc);
    final nextSemanticTokensVersion =
        Map<int, int>.of(_semanticTokensVersionByDoc);
    if (isLastView) {
      nextSyntax.remove(id);
      nextSyntaxVersion.remove(id);
      nextSemanticTokens.remove(id);
      nextSemanticTokensVersion.remove(id);
    }
    owner.docs.remove(doc);
    doc.disposeView();
    if (isLastView) _navigationHistory.closeDocument(id);
    setState(() {
      _syntaxByDoc = nextSyntax;
      _syntaxVersionByDoc = nextSyntaxVersion;
      _semanticTokensByDoc = nextSemanticTokens;
      _semanticTokensVersionByDoc = nextSemanticTokensVersion;
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
    _updateLanguageServicePolling();
    _syncCommandContext();
  }

  void _onEditorFoldRangesChanged(
    OpenDoc active,
    int documentId,
    int version,
    List<EditorDocumentLineRange> ranges,
  ) {
    final owner = _ownerOfView(active);
    if (!mounted ||
        active.id != documentId ||
        active.inputWindow.version != version ||
        owner == null ||
        !owner.docs.any((view) => identical(view, active))) {
      return;
    }
    if (ranges.isNotEmpty &&
        (active.inputWindow.pendingText != null ||
            active.doc.version != version)) {
      return;
    }
    if (listEquals(active.foldedLineRanges, ranges)) return;
    active.foldedLineRanges = List.unmodifiable(ranges);
    setState(() {});
  }

  /// 拆分焦点组（W2-2）：沿水平方向分出新组，新组获得焦点。
  void _splitFocusedGroup() {
    final active = _active;
    if (active != null) _flushInput(active, commitComposition: true);
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
    _syncCommandContext();
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
    _syncCommandContext();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      // Rust 侧按工作区复用服务器进程；挂接用任一已打开文档 id 均可
      core.lsp.start(_untitledId, root, ['rust-analyzer']);
      setState(() {
        _lspReady = true;
        _lspStarting = false;
        _lspStatus = 'rust-analyzer 运行中';
      });
      _syncCommandContext();
      for (final d in _allDocs) {
        if (!d.isUntitled && !d.lspAttached) {
          try {
            core.lsp.setUri(d.id, d.uri!);
            core.lsp.didOpen(d.id, languageId: _languageIdOf(d.path!));
            d.lspAttached = true;
            _scheduleSyntaxRefresh(d.id);
          } catch (_) {}
        }
      }
      _updateLanguageServicePolling();
    } catch (e) {
      setState(() {
        _lspStarting = false;
        _lspStatus = '启动失败：$e';
      });
      _syncCommandContext();
    }
  }

  void _pollLanguageServices() {
    final core = _core;
    if (core == null || _polling || !_lspReady) return;
    if (!_allDocs.any((doc) => doc.lspAttached && !doc.isUntitled)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _polling = true;
    try {
      final diags = <Map<String, Object?>>[];
      for (final d in _allDocs) {
        if (d.isUntitled || !d.lspAttached) continue;
        try {
          diags.addAll(core.lsp.diagnostics(d.id).map((diagnostic) => {
                ...diagnostic,
                'file': d.name,
                '_documentId': d.id,
              }));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _diagnostics
          ..clear()
          ..addAll(diags);
      });
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _updateLanguageServicePolling() {
    final shouldPoll =
        _lspReady && _allDocs.any((doc) => doc.lspAttached && !doc.isUntitled);
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollLanguageServices();
    });
  }

  void _scheduleSyntaxRefresh(int docId) {
    final doc = _allDocs.where((item) => item.id == docId).firstOrNull;
    if (doc == null || doc.path?.toLowerCase().endsWith('.rs') != true) return;
    _syntaxRefreshTimers.remove(docId)?.cancel();
    _syntaxRefreshTimers[docId] = Timer(const Duration(milliseconds: 80), () {
      _syntaxRefreshTimers.remove(docId);
      if (!mounted) return;
      final current = _allDocs.where((item) => item.id == docId).firstOrNull;
      if (current == null ||
          current.path?.toLowerCase().endsWith('.rs') != true) {
        return;
      }
      try {
        final syntax = _core?.lsp.syntax(docId);
        if (!mounted) return;
        if (syntax != null) {
          setState(() {
            _syntaxByDoc = {..._syntaxByDoc, docId: syntax.tokens};
            _syntaxVersionByDoc = {
              ..._syntaxVersionByDoc,
              docId: syntax.version,
            };
          });
        }
        if (current.lspAttached) unawaited(_refreshSemanticTokens(docId));
      } catch (error) {
        debugPrint('语法状态刷新失败（doc=$docId）：$error');
      }
    });
  }

  RustStringContext _rustStringContextAt(OpenDoc doc, int offsetUtf16) =>
      rustStringContextAt(
        tokens: _syntaxByDoc[doc.id] ?? const <Map<String, Object?>>[],
        tokenVersion: _syntaxVersionByDoc[doc.id] ?? -1,
        documentVersion: doc.doc.version,
        offsetUtf16: offsetUtf16,
      );

  Future<void> _refreshSemanticTokens(int docId) async {
    final doc = _allDocs.where((item) => item.id == docId).firstOrNull;
    if (doc == null || !doc.lspAttached) return;
    final requestedVersion = doc.doc.version;
    try {
      final result = await doc.doc.core.lsp.semanticTokens(
        docId,
        timeoutMs: 8000,
      );
      if (!mounted || result == null || result.version != requestedVersion) {
        return;
      }
      final current = _allDocs.where((item) => item.id == docId).firstOrNull;
      if (current == null ||
          !current.lspAttached ||
          current.doc.version != requestedVersion ||
          current.inputWindow.version != requestedVersion ||
          current.inputWindow.pendingText != null) {
        return;
      }
      setState(() {
        _semanticTokensByDoc = {
          ..._semanticTokensByDoc,
          docId: result.tokens,
        };
        _semanticTokensVersionByDoc = {
          ..._semanticTokensVersionByDoc,
          docId: result.version,
        };
      });
    } catch (error) {
      debugPrint('语义令牌刷新失败（doc=$docId）：$error');
    }
  }

  // ---------- 补全 / 保存 ----------

  Future<void> _requestCompletion() async {
    final active = _active;
    if (active == null || !_lspReady) {
      setState(() => _statusDetail = '补全需要先打开文件夹并启动 LSP');
      return;
    }
    _flushInput(active, commitComposition: true);
    final offset = active.selection.baseOffset >= 0
        ? active.selection.baseOffset
        : active.inputWindow.startUtf16 + active.editingValue.text.length;
    setState(() => _statusDetail = '补全请求中…');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final completed = await active.doc.core.lsp
          .completion(active.id, offset, timeoutMs: 10000);
      if (!mounted) return;
      if (completed == null) {
        if (_active?.id == active.id) {
          setState(() => _statusDetail = '补全已取消或结果已过期');
        }
        return;
      }
      if (_active?.id != active.id || active.doc.version != completed.version) {
        return;
      }
      final items = completed.items;
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
    final value = active.editingValue;
    final sel = value.selection;
    final pos = sel.baseOffset >= 0 ? sel.baseOffset : value.text.length;
    final t = value.text;
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
    active.inputFieldKey.currentState?.setEditingValue(TextEditingValue(
      text: t.replaceRange(start, pos, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    ));
  }

  Future<void> _saveActive() async {
    final active = _active;
    if (active == null) return;
    if (active.isUntitled) {
      await _saveAsActive();
      return;
    }
    await _saveDocToPath(active, active.path!);
  }

  Future<void> _saveAsActive() async {
    final active = _active;
    if (active == null) return;
    await _saveAsDoc(active);
  }

  Future<void> _saveAsDoc(OpenDoc doc) async {
    final path = await _showSaveAsDialog(doc);
    if (path == null) return;
    await _saveDocToPath(doc, path);
  }

  Future<void> _saveDocToPath(
    OpenDoc doc,
    String requestedPath, {
    TextFileOptions? options,
  }) async {
    _flushInput(doc, commitComposition: true);
    final targetOptions = options ?? doc.fileOptions;
    final targetPath = File(requestedPath).absolute.path;
    final oldPath = doc.path;
    final pathChanged = oldPath == null ||
        _canonicalPath(oldPath) != _canonicalPath(targetPath);

    if (!pathChanged && doc.diskState == DiskDocumentState.missing) {
      setState(() => _statusDetail = '${doc.name} 已不在原路径；缓冲区仍保留，请使用“另存为”保存');
      return;
    }
    if (!pathChanged && doc.diskState == DiskDocumentState.unavailable) {
      setState(() => _statusDetail = '无法核对 ${doc.name} 的磁盘版本；请重试读取或使用“另存为”');
      return;
    }
    if (!pathChanged && doc.diskState == DiskDocumentState.conflict) {
      final action = await showDialog<_ConflictSaveAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('external-conflict-dialog'),
          title: const Text('磁盘版本已变化'),
          content: Text(
            '“${doc.name}”在磁盘上的内容与本地缓冲区不同。选择覆盖磁盘、另存本地内容，或返回继续编辑。',
          ),
          actions: [
            TextButton(
              key: const ValueKey('external-conflict-cancel'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ConflictSaveAction.cancel),
              child: const Text('继续编辑'),
            ),
            TextButton(
              key: const ValueKey('external-conflict-save-as'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ConflictSaveAction.saveAs),
              child: const Text('另存为…'),
            ),
            FilledButton(
              key: const ValueKey('external-conflict-confirm-overwrite'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ConflictSaveAction.overwrite),
              child: const Text('覆盖磁盘文件'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == _ConflictSaveAction.saveAs) {
        await _saveAsDoc(doc);
        return;
      }
      if (action != _ConflictSaveAction.overwrite) return;
    }

    if (pathChanged &&
        _allDocs.any((other) =>
            !identical(other, doc) &&
            other.path != null &&
            _canonicalPath(other.path!) == _canonicalPath(targetPath))) {
      setState(() => _statusDetail = '该路径已在其他标签中打开');
      return;
    }

    if (pathChanged && File(targetPath).existsSync()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('覆盖文件？'),
          content: Text('目标文件已存在：\n$targetPath'),
          actions: [
            TextButton(
              key: const ValueKey('save-as-overwrite-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('save-as-overwrite-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    try {
      doc.doc.saveFile(targetPath, options: targetOptions);
      doc.doc.markSaved();
      var lspWarning = false;
      if (pathChanged) {
        if (doc.lspAttached && _lspReady) {
          try {
            doc.doc.core.lsp.didClose(doc.id);
          } catch (_) {}
        }
        doc.path = targetPath;
        doc.uri = _pathToUri(targetPath);
        doc.name = _nameOf(targetPath);
        if (_lspReady) {
          try {
            doc.doc.core.lsp.setUri(doc.id, doc.uri!);
            doc.doc.core.lsp.didOpen(
              doc.id,
              languageId: _languageIdOf(targetPath),
            );
            doc.lspAttached = true;
          } catch (_) {
            doc.lspAttached = false;
            lspWarning = true;
          }
        }
        if (_workspaceRoot != null) _refreshTree();
      }
      doc.fileOptions = targetOptions;
      doc.savedFileOptions = targetOptions;
      doc.diskState = DiskDocumentState.current;
      doc.conflictBaselineKnown = true;
      _updateDirty(doc);
      _syncCommandContext();
      setState(() {
        _statusDetail = lspWarning
            ? '已保存 ${doc.name}，语言服务未能重新打开文档'
            : '已原子保存 ${doc.name}（v${doc.doc.version}）';
      });
      _scheduleStateSave(); // 保存后 journal 里的 text 分支消失（转干净）
      if (doc.lspAttached && _lspReady) {
        try {
          doc.doc.core.lsp.didSave(doc.id);
        } catch (_) {}
      }
    } on AlulaException catch (e) {
      setState(() {
        _state = WbSyncState.error;
        _statusDetail = '保存失败：${e.code} ${e.detail}';
        if (e.code == 'ReadOnlyFile') {
          doc.diskState = DiskDocumentState.readOnly;
        }
      });
    }
  }

  Future<void> _revertActive() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.isUntitled) {
      setState(() => _statusDetail = '未命名文档没有磁盘版本可还原');
      return;
    }
    if (doc.dirtyDisk) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: Text('将从磁盘重新载入“${doc.name}”，未保存内容会丢失。'),
          actions: [
            TextButton(
              key: const ValueKey('revert-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('revert-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('还原'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }

    try {
      _flushInput(doc, commitComposition: true);
      final diskFile = _readDiskDocument(
        doc.doc.core,
        doc.path!,
        preferredEncoding: doc.savedFileOptions.encoding,
      );
      final diskText = diskFile.content;
      final currentText = doc.doc.resync().content;
      final ops = diffToOps(currentText, diskText);
      if (ops.isNotEmpty) doc.doc.apply(ops);

      final caret =
          doc.selection.extentOffset.clamp(0, diskText.length).toInt();
      doc.doc.setSavepoint(diskText);
      doc.fileOptions = diskFile.options;
      doc.savedFileOptions = diskFile.options;
      doc.diskState = DiskDocumentState.current;
      doc.conflictBaselineKnown = true;
      doc.replaceInputWindow(caret);
      if (ops.isNotEmpty) _refreshSiblingViews(doc, ops);
      _updateDirty(doc);
      doc.undoStack.clear();
      doc.lastEditAt = null;
      _scheduleSyntaxRefresh(doc.id);
      _scheduleOutlineRefresh();
      _scheduleStateSave();
      _syncCommandContext();
      setState(() => _statusDetail = '已从磁盘还原 ${doc.name}');
    } on AlulaException catch (e) {
      setState(() {
        _state = WbSyncState.error;
        _statusDetail = '还原失败：${e.code} ${e.detail}';
        if (e.code == 'NotFound') {
          doc.diskState = DiskDocumentState.missing;
        }
      });
    }
  }

  Future<String?> _showSaveAsDialog(OpenDoc doc) async {
    final root = _workspaceRoot ?? Directory.current.path;
    final defaultPath = doc.path ??
        '$root${Platform.pathSeparator}${doc.isUntitled ? 'untitled.txt' : doc.name}';
    var selectedPath = defaultPath;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('另存为'),
        content: TextFormField(
          key: const ValueKey('save-as-path'),
          initialValue: defaultPath,
          onChanged: (value) => selectedPath = value,
          decoration: const InputDecoration(labelText: '文件路径'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-as-confirm'),
            onPressed: () => Navigator.pop(dialogContext, selectedPath),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _saveWithEncodingActive() async {
    final doc = _active;
    if (doc == null) return;
    final options = await _pickSaveOptions(doc.fileOptions);
    if (options == null) return;
    final path = doc.path ?? await _showSaveAsDialog(doc);
    if (path == null) return;
    await _saveDocToPath(doc, path, options: options);
  }

  Future<void> _reopenWithEncodingActive() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.path == null) {
      setState(() => _statusDetail = '未命名文档没有磁盘编码可重新打开');
      return;
    }
    final encoding = await _pickReopenEncoding();
    if (!mounted || encoding == null) return;
    if (doc.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: Text('将按 ${encoding.id} 重新读取“${doc.name}”，未保存内容会丢失。'),
          actions: [
            TextButton(
              key: const ValueKey('encoding-reopen-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('encoding-reopen-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('重新打开'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    try {
      final disk = doc.doc.core.workspace.readFileDocument(
        doc.path!,
        encoding: encoding,
      );
      _replaceDocumentFromDisk(doc, disk, '已按 ${encoding.id} 重新打开 ${doc.name}');
    } on AlulaException catch (e) {
      setState(() => _statusDetail = '重新打开失败：${e.code} ${e.detail}');
    }
  }

  Future<void> _showEncodingActions(OpenDoc doc) async {
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('文件编码 · ${doc.fileOptions.label}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('使用编码重新打开…'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('使用编码保存…'),
          ),
        ],
      ),
    );
    if (save == true) {
      await _saveWithEncodingActive();
    } else if (save == false) {
      await _reopenWithEncodingActive();
    }
  }

  Future<TextFileOptions?> _pickSaveOptions(TextFileOptions current) {
    final options = [
      current.copyWith(encoding: TextEncoding.utf8, bom: false),
      current.copyWith(encoding: TextEncoding.utf8, bom: true),
      current.copyWith(encoding: TextEncoding.utf16Le, bom: true),
      current.copyWith(encoding: TextEncoding.utf16Le, bom: false),
      current.copyWith(encoding: TextEncoding.utf16Be, bom: true),
      current.copyWith(encoding: TextEncoding.utf16Be, bom: false),
      current.copyWith(encoding: TextEncoding.gbk, bom: false),
    ];
    return showDialog<TextFileOptions>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('使用编码保存'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              key:
                  ValueKey('save-encoding-${option.encoding.id}-${option.bom}'),
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Text(option.label),
            ),
        ],
      ),
    );
  }

  Future<TextEncoding?> _pickReopenEncoding({
    String title = '使用编码重新打开',
  }) {
    const encodings = [
      TextEncoding.utf8,
      TextEncoding.utf16Le,
      TextEncoding.utf16Be,
      TextEncoding.gbk,
    ];
    return showDialog<TextEncoding>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final encoding in encodings)
            SimpleDialogOption(
              key: ValueKey('reopen-encoding-${encoding.id}'),
              onPressed: () => Navigator.pop(dialogContext, encoding),
              child: Text(switch (encoding) {
                TextEncoding.utf8 => 'UTF-8',
                TextEncoding.utf16Le => 'UTF-16 LE',
                TextEncoding.utf16Be => 'UTF-16 BE',
                TextEncoding.gbk => 'GBK',
              }),
            ),
        ],
      ),
    );
  }

  Future<void> _selectLineEndingActive() async {
    final doc = _active;
    if (doc == null) return;
    final lineEnding = await showDialog<TextLineEnding>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择行尾'),
        children: [
          for (final value in TextLineEnding.values)
            SimpleDialogOption(
              key: ValueKey('line-ending-${value.id}'),
              onPressed: () => Navigator.pop(dialogContext, value),
              child: Text(value.label),
            ),
        ],
      ),
    );
    if (lineEnding != null) _setLineEnding(doc, lineEnding);
  }

  void _setLineEnding(OpenDoc doc, TextLineEnding lineEnding) {
    if (doc.fileOptions.lineEnding == lineEnding) return;
    _flushInput(doc, commitComposition: true);
    final selection = doc.selection;
    doc.undoStack.pushOperations(
      forward: const [],
      inverse: const [],
      caret: selection.baseOffset >= 0 ? selection.baseOffset : 0,
      redoCaret: selection.extentOffset,
      coalesce: false,
      encoding: doc.fileOptions.encoding.id,
      bom: doc.fileOptions.bom,
      lineEnding: doc.fileOptions.lineEnding.id,
    );
    doc.fileOptions = doc.fileOptions.copyWith(lineEnding: lineEnding);
    doc.lastEditAt = null;
    _updateDirty(doc);
    _scheduleStateSave();
    _syncCommandContext();
    setState(() => _statusDetail = '行尾已更改为 ${lineEnding.label}');
  }

  void _replaceDocumentFromDisk(
    OpenDoc doc,
    DecodedTextFile disk, [
    String? status,
  ]) {
    _flushInput(doc, commitComposition: true);
    final currentText = doc.doc.resync().content;
    final ops = diffToOps(currentText, disk.content);
    if (ops.isNotEmpty) doc.doc.apply(ops);
    final caret =
        doc.selection.extentOffset.clamp(0, disk.content.length).toInt();
    doc.doc.setSavepoint(disk.content);
    doc.fileOptions = disk.options;
    doc.savedFileOptions = disk.options;
    doc.diskState = DiskDocumentState.current;
    doc.conflictBaselineKnown = true;
    doc.replaceInputWindow(caret);
    if (ops.isNotEmpty) _refreshSiblingViews(doc, ops);
    _updateDirty(doc);
    doc.undoStack.clear();
    doc.lastEditAt = null;
    _scheduleSyntaxRefresh(doc.id);
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    _syncCommandContext();
    setState(() => _statusDetail = status ?? '已从磁盘重新载入 ${doc.name}');
  }

  void _verifyIntegrity() {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final r = active.doc.resync();
    final window = active.inputWindow;
    final validRange =
        window.startUtf16 >= 0 && window.endUtf16 <= r.content.length;
    final expected = validRange
        ? r.content.substring(window.startUtf16, window.endUtf16)
        : '';
    final matches = validRange &&
        r.version == window.version &&
        r.content.length == window.totalUtf16Length &&
        expected == window.text;
    setState(() {
      _state = matches ? WbSyncState.synced : WbSyncState.mismatch;
      _statusDetail = matches
          ? '一致性校验通过：输入窗与 Rust v${r.version} 完全一致'
          : '不一致！输入窗与 Rust v${r.version} 不一致（见日志）';
    });
  }

  /// 每文档一个带 onKeyEvent 的 FocusNode：在事件分发第一站拦截
  /// 撤销/重做/查找键位。必须在这里抢——TextField 内建 UndoHistory 在
  /// 焦点链更下方注册了 Ctrl+Z/Y，晚于焦点节点处理器，且会双栈打架
  /// （测试环境还会死锁）。
  final Map<String, FocusNode> _editorFocusNodes = {};
  Timer? _pendingMoveSelectionChordTimer;
  bool _awaitingMoveSelectionChord = false;

  String _focusKeyFor(EditorGroup group, OpenDoc doc) =>
      '${group.region}:${doc.id}';

  FocusNode _focusNodeFor(EditorGroup g, OpenDoc doc) {
    return _editorFocusNodes.putIfAbsent(_focusKeyFor(g, doc), () {
      return FocusNode(onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final meta = HardwareKeyboard.instance.isMetaPressed;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final alt = HardwareKeyboard.instance.isAltPressed;
        final key = event.logicalKey;
        final active = _active;
        final character = event.character;
        if (_overtypeMode &&
            !ctrl &&
            !alt &&
            !meta &&
            _isPrintableOvertypeCharacter(character)) {
          active?.expectOvertypeInput(character!);
        } else {
          active?.clearPendingOvertypeInput();
        }
        final commandModifier =
            defaultTargetPlatform == TargetPlatform.macOS ? meta : ctrl;
        final activeHasComposition =
            active?.inputWindow.hasComposition ?? false;
        if (active != null && !activeHasComposition) {
          if (!ctrl && !meta && !alt && key == LogicalKeyboardKey.tab) {
            unawaited(_applyIndentation(
              outdent: shift,
              tabOperation: true,
            ));
            return KeyEventResult.handled;
          }
        }
        if (active != null &&
            !activeHasComposition &&
            !ctrl &&
            !meta &&
            !alt &&
            !shift &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter)) {
          unawaited(_insertNewlineWithIndent());
          return KeyEventResult.handled;
        }
        if (active != null &&
            !activeHasComposition &&
            !ctrl &&
            !meta &&
            !alt &&
            !_overtypeMode &&
            active.path?.toLowerCase().endsWith('.rs') == true &&
            (_rustAutoClosingPairs.containsKey(character) ||
                _rustAutoClosingPairs.values.contains(character) ||
                character == '<')) {
          unawaited(_applyRustBracketInput(character!));
          return KeyEventResult.handled;
        }
        if (active != null &&
            !ctrl &&
            !meta &&
            !alt &&
            key == LogicalKeyboardKey.backspace) {
          final backspace = _rustBracketBackspacePlan(active);
          if (backspace != null) {
            unawaited(_applyRustBracketBackspace(active, backspace));
            return KeyEventResult.handled;
          }
        }
        if (_awaitingMoveSelectionChord) {
          if (key == LogicalKeyboardKey.controlLeft ||
              key == LogicalKeyboardKey.controlRight ||
              key == LogicalKeyboardKey.metaLeft ||
              key == LogicalKeyboardKey.metaRight ||
              key == LogicalKeyboardKey.shiftLeft ||
              key == LogicalKeyboardKey.shiftRight ||
              key == LogicalKeyboardKey.altLeft ||
              key == LogicalKeyboardKey.altRight) {
            return KeyEventResult.ignored;
          }
          _pendingMoveSelectionChordTimer?.cancel();
          _pendingMoveSelectionChordTimer = null;
          _awaitingMoveSelectionChord = false;
          if (commandModifier &&
              !shift &&
              !alt &&
              key == LogicalKeyboardKey.keyD) {
            _runCommand('editor.action.moveSelectionToNextFindMatch');
            return KeyEventResult.handled;
          }
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyK) {
          _awaitingMoveSelectionChord = true;
          _pendingMoveSelectionChordTimer = Timer(
            const Duration(seconds: 5),
            () => _awaitingMoveSelectionChord = false,
          );
          return KeyEventResult.handled;
        }
        if (commandModifier && !shift && key == LogicalKeyboardKey.keyD) {
          _runCommand('editor.selectNextOccurrence');
          return KeyEventResult.handled;
        }
        if (active?.crossWindowSelection != null && !activeHasComposition) {
          if (commandModifier && key == LogicalKeyboardKey.keyC) {
            unawaited(_copyCrossWindowSelection(active!));
            return KeyEventResult.handled;
          }
          if (commandModifier && key == LogicalKeyboardKey.keyX) {
            unawaited(_cutCrossWindowSelection(active!));
            return KeyEventResult.handled;
          }
          if (commandModifier && key == LogicalKeyboardKey.keyV) {
            unawaited(_overtypeMode && widget.overtypeOnPaste
                ? _pasteOvertype(active!)
                : _pasteCrossWindowSelection(active!));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.delete ||
              key == LogicalKeyboardKey.backspace) {
            _replaceCrossWindowSelection(active!, '');
            return KeyEventResult.handled;
          }
        }
        final activeCrossSelection = active?.crossWindowSelection;
        if (key == LogicalKeyboardKey.escape &&
            !activeHasComposition &&
            active != null &&
            activeCrossSelection != null) {
          _setDocSelection(
            active,
            TextSelection.collapsed(offset: activeCrossSelection.end),
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape &&
            active?.additionalSelections.isNotEmpty == true) {
          final active = _active!;
          _setDocSelection(active, active.selection);
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !alt &&
            key == LogicalKeyboardKey.keyV &&
            _overtypeMode &&
            widget.overtypeOnPaste &&
            !activeHasComposition &&
            active != null) {
          unawaited(_pasteOvertype(active));
          return KeyEventResult.handled;
        }
        if (commandModifier && !alt && key == LogicalKeyboardKey.keyZ) {
          _runCommand(shift ? 'editor.redo' : 'editor.undo');
          return KeyEventResult.handled;
        }
        if (commandModifier && !alt && key == LogicalKeyboardKey.keyY) {
          _runCommand('editor.redo');
          return KeyEventResult.handled;
        }
        if (ctrl) {
          if (key == LogicalKeyboardKey.keyZ) {
            _runCommand(shift ? 'editor.redo' : 'editor.undo');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyY) {
            _runCommand('editor.redo');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyF && !shift) {
            _runCommand('editor.find');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyH && !shift) {
            _runCommand('editor.replace');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyL && shift) {
            _runCommand('editor.selectAllOccurrences');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyU) {
            _runCommand(shift ? 'editor.cursorRedo' : 'editor.cursorUndo');
            return KeyEventResult.handled;
          }
          if (active != null && active.additionalSelections.isNotEmpty) {
            if (key == LogicalKeyboardKey.keyC) {
              unawaited(_copyMultiSelections(active));
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.keyV) {
              unawaited(_pasteMultiSelections(active));
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.keyX) {
              unawaited(_cutMultiSelections(active).then((handled) {
                if (!handled && mounted) {
                  setState(() => _statusDetail = '多选剪切需要每个光标都有非空选区');
                }
              }));
              return KeyEventResult.handled;
            }
          }
          if (alt && !shift && key == LogicalKeyboardKey.arrowUp) {
            _runCommand('editor.addCursorAbove');
            return KeyEventResult.handled;
          }
          if (alt && !shift && key == LogicalKeyboardKey.arrowDown) {
            _runCommand('editor.addCursorBelow');
            return KeyEventResult.handled;
          }
        }
        final columnSelectionModifierMatches = switch (defaultTargetPlatform) {
          TargetPlatform.windows => ctrl,
          TargetPlatform.linux => !ctrl,
          _ => false,
        };
        if (alt && shift && columnSelectionModifierMatches) {
          final command = switch (key) {
            LogicalKeyboardKey.arrowUp => 'editor.columnSelectUp',
            LogicalKeyboardKey.arrowDown => 'editor.columnSelectDown',
            LogicalKeyboardKey.arrowLeft => 'editor.columnSelectLeft',
            LogicalKeyboardKey.arrowRight => 'editor.columnSelectRight',
            _ => null,
          };
          if (command != null) {
            _runCommand(command);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      });
    });
  }

  /// Restore the file-format state retained by a history frame.
  void _restoreFileOptionsFromUndo(OpenDoc doc, UndoEntry entry) {
    final encoding = TextEncodingInfo.fromId(entry.encoding);
    final lineEnding = TextLineEndingInfo.fromId(entry.lineEnding);
    if (encoding == null || entry.bom == null || lineEnding == null) return;
    doc.fileOptions = TextFileOptions(
      encoding: encoding,
      bom: entry.bom!,
      lineEnding: lineEnding,
    );
  }

  void _restoreRedoFileOptions(OpenDoc doc, UndoEntry entry) {
    final encoding = TextEncodingInfo.fromId(entry.redoEncoding);
    final lineEnding = TextLineEndingInfo.fromId(entry.redoLineEnding);
    if (encoding == null || entry.redoBom == null || lineEnding == null) return;
    doc.fileOptions = TextFileOptions(
      encoding: encoding,
      bom: entry.redoBom!,
      lineEnding: lineEnding,
    );
  }

  List<TextOp> _applyHistoryBatches(
    OpenDoc doc,
    List<List<TextOp>>? batches,
  ) {
    if (batches == null) return const [];
    final operations = batches.expand((batch) => batch).toList(growable: false);
    if (operations.isNotEmpty) doc.doc.apply(operations);
    return operations;
  }

  void _finishHistoryChange(OpenDoc doc, String status) {
    doc.crossWindowSelection = null;
    _updateDirty(doc);
    _syncCommandContext();
    doc.lastEditAt = null;
    _onFindTextChanged();
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    _scheduleSyntaxRefresh(doc.id);
    if (mounted) setState(() => _statusDetail = status);
  }

  void _undo() {
    final active = _active;
    if (active == null) {
      setState(() => _statusDetail = '撤销需要打开的文档');
      return;
    }
    _flushInput(active, commitComposition: true);
    final operation = active.undoStack.peekOperationUndo();
    if (operation != null) {
      final operations = _applyHistoryBatches(active, operation.inverseBatches);
      operation.redoEncoding = active.fileOptions.encoding.id;
      operation.redoBom = active.fileOptions.bom;
      operation.redoLineEnding = active.fileOptions.lineEnding.id;
      active.undoStack.takeOperationUndo();
      _restoreFileOptionsFromUndo(active, operation);
      active.replaceInputWindow(operation.caret);
      if (operations.isNotEmpty) _refreshSiblingViews(active, operations);
      _finishHistoryChange(active, '已撤销');
      return;
    }
    final currentText = active.doc.resync().content;
    final entry = active.undoStack.undo(
      currentText,
      active.selection.baseOffset,
      encoding: active.fileOptions.encoding.id,
      bom: active.fileOptions.bom,
      lineEnding: active.fileOptions.lineEnding.id,
    );
    if (entry == null) {
      setState(() => _statusDetail = '无可撤销');
      return;
    }
    final ops = diffToOps(currentText, entry.text);
    if (ops.isNotEmpty) active.doc.apply(ops);
    _restoreFileOptionsFromUndo(active, entry);
    active.replaceInputWindow(entry.caret);
    if (ops.isNotEmpty) _refreshSiblingViews(active, ops);
    _finishHistoryChange(active, '已撤销');
  }

  void _redo() {
    final active = _active;
    if (active == null) {
      setState(() => _statusDetail = '重做需要打开的文档');
      return;
    }
    _flushInput(active, commitComposition: true);
    final operation = active.undoStack.peekOperationRedo();
    if (operation != null) {
      final operations = _applyHistoryBatches(active, operation.forwardBatches);
      active.undoStack.takeOperationRedo();
      _restoreRedoFileOptions(active, operation);
      active.replaceInputWindow(operation.redoCaret);
      if (operations.isNotEmpty) _refreshSiblingViews(active, operations);
      _finishHistoryChange(active, '已重做');
      return;
    }
    final currentText = active.doc.resync().content;
    final entry = active.undoStack.redo(
      currentText,
      active.selection.baseOffset,
      encoding: active.fileOptions.encoding.id,
      bom: active.fileOptions.bom,
      lineEnding: active.fileOptions.lineEnding.id,
    );
    if (entry == null) {
      setState(() => _statusDetail = '无可重做');
      return;
    }
    final ops = diffToOps(currentText, entry.text);
    if (ops.isNotEmpty) active.doc.apply(ops);
    _restoreFileOptionsFromUndo(active, entry);
    active.replaceInputWindow(entry.caret);
    if (ops.isNotEmpty) _refreshSiblingViews(active, ops);
    _finishHistoryChange(active, '已重做');
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
        _findOverviewLines = const [];
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
    final text = active?.text ?? '';
    _matchesDocId = active?.id ?? -1;
    _matchesDocVersion = active?.doc.version ?? -1;
    _matches = _findVisible
        ? findMatches(text, _findQuery.text, caseSensitive: _caseSensitive)
        : const [];
    _findOverviewLines =
        _findVisible ? buildEditorMinimapFindLines(text, _matches) : const [];
    if (_matchIndex >= _matches.length) {
      _matchIndex = _matches.isEmpty ? -1 : _matches.length - 1;
    }
    if (_matches.isEmpty) _matchIndex = -1;
  }

  List<EditorRangeDecoration> _findDecorationsFor(OpenDoc doc) {
    final window = doc.inputWindow;
    if (!_findVisible ||
        _matchesDocId != doc.id ||
        _matchesDocVersion != window.version ||
        doc.doc.version != window.version ||
        window.pendingText != null ||
        _matches.isEmpty) {
      return const [];
    }

    final windowStart = window.startUtf16;
    final windowEnd = window.endUtf16;
    final first = firstTextMatchEndingAfter(_matches, windowStart);
    final decorations = <EditorRangeDecoration>[];
    for (var index = first; index < _matches.length; index++) {
      final match = _matches[index];
      if (match.start >= windowEnd) break;
      if (match.end <= windowStart || match.end <= match.start) continue;
      final isCurrent = index == _matchIndex;
      decorations.add(
        EditorRangeDecoration(
          documentVersion: window.version,
          startUtf16: match.start,
          endUtf16: match.end,
          backgroundColor:
              isCurrent ? const Color(0x66FFB000) : const Color(0x33F0C674),
          borderColor: isCurrent ? const Color(0xFFFFB000) : null,
        ),
      );
    }
    return decorations;
  }

  List<EditorRangeDecoration> _diagnosticDecorationsFor(OpenDoc doc) {
    final window = doc.inputWindow;
    if (window.pendingText != null ||
        doc.doc.version != window.version ||
        _diagnostics.isEmpty) {
      return const [];
    }

    final diagnostics = _diagnostics
        .where((diagnostic) => diagnostic['_documentId'] == doc.id)
        .toList(growable: false);
    if (diagnostics.isEmpty) return const [];

    final firstVisible =
        resolveEditorDocumentLinePosition(doc.doc, window.startUtf16);
    final lastVisible =
        resolveEditorDocumentLinePosition(doc.doc, window.endUtf16);
    if (doc.doc.version != window.version) return const [];

    final lineOffsets = <int, DocumentLineOffset>{};
    DocumentLineOffset lineOffset(int line) =>
        lineOffsets.putIfAbsent(line, () => doc.doc.lineOffset(line));
    return buildLspDiagnosticDecorations(
      diagnostics: diagnostics,
      documentVersion: doc.doc.version,
      inputWindowVersion: window.version,
      windowStartUtf16: window.startUtf16,
      windowEndUtf16: window.endUtf16,
      totalUtf16Length: window.totalUtf16Length,
      documentLineCount: firstVisible.lineCount,
      firstVisibleLine: firstVisible.firstLineNumber,
      lastVisibleLine: lastVisible.firstLineNumber,
      lineOffset: lineOffset,
    );
  }

  List<EditorRangeDecoration> _workspaceSearchDecorationsFor(OpenDoc doc) {
    final window = doc.inputWindow;
    if (_selectedSearchDocId != doc.id ||
        _selectedSearchDocVersion != doc.doc.version ||
        window.pendingText != null ||
        doc.doc.version != window.version) {
      return const [];
    }

    final firstVisible =
        resolveEditorDocumentLinePosition(doc.doc, window.startUtf16);
    final lastVisible =
        resolveEditorDocumentLinePosition(doc.doc, window.endUtf16);
    if (doc.doc.version != window.version) return const [];

    final lineOffsets = <int, DocumentLineOffset>{};
    DocumentLineOffset lineOffset(int line) =>
        lineOffsets.putIfAbsent(line, () => doc.doc.lineOffset(line));
    return buildWorkspaceSearchDecorations(
      hit: _selectedSearchHit,
      documentVersion: doc.doc.version,
      inputWindowVersion: window.version,
      windowStartUtf16: window.startUtf16,
      windowEndUtf16: window.endUtf16,
      totalUtf16Length: window.totalUtf16Length,
      documentLineCount: firstVisible.lineCount,
      firstVisibleLine: firstVisible.firstLineNumber,
      lastVisibleLine: lastVisible.firstLineNumber,
      lineOffset: lineOffset,
    );
  }

  void _gotoMatch(int direction) {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    _refreshMatches();
    if (_matches.isEmpty) {
      setState(() => _matchIndex = -1);
      return;
    }
    final sel = active.selection;
    final from = sel.baseOffset >= 0 ? sel.baseOffset : 0;
    final m =
        direction > 0 ? findNext(_matches, from) : findPrevious(_matches, from);
    _matchIndex = _matches.indexOf(m!);
    _setDocSelection(
      active,
      TextSelection(baseOffset: m.start, extentOffset: m.end),
    );
    setState(() {});
  }

  void _replaceCurrent() {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    _refreshMatches();
    if (_matches.isEmpty) {
      setState(() => _statusDetail = '无匹配');
      return;
    }
    final sel = active.selection;
    final from = sel.baseOffset >= 0 ? sel.baseOffset : 0;
    var m = findNext(_matches, from)!;
    var isOnMatch = sel.baseOffset == m.start && sel.extentOffset == m.end;
    if (!isOnMatch) {
      // 先跳转到该匹配，再按一次才替换（与 VS Code 语义一致）
      _matchIndex = _matches.indexOf(m);
      _setDocSelection(
        active,
        TextSelection(baseOffset: m.start, extentOffset: m.end),
      );
      setState(() {});
      return;
    }
    final t = active.text;
    final replaced = t.replaceRange(m.start, m.end, _replaceInput.text);
    _applyProgrammaticEdit(
      active,
      replaced,
      selection: TextSelection.collapsed(
        offset: m.start + _replaceInput.text.length,
      ),
    );
    _refreshMatches();
    setState(() => _statusDetail = '已替换 1 处（剩余 ${_matches.length} 处）');
  }

  void _replaceAll() {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final r = replaceAllMatches(
        active.text, _findQuery.text, _replaceInput.text,
        caseSensitive: _caseSensitive);
    if (r.count == 0) {
      setState(() => _statusDetail = '无匹配');
      return;
    }
    _applyProgrammaticEdit(
      active,
      r.newText,
      selection: TextSelection.collapsed(offset: r.newText.length),
    );
    _refreshMatches();
    setState(() => _statusDetail = '已替换 ${r.count} 处');
    _scheduleStateSave();
  }

  // ---------- 大纲视图 ----------

  /// 刷新当前焦点文档的符号大纲（FFI；按版本去重）。
  void _refreshOutline() {
    final active = _active;
    if (active == null) {
      _outlineSymbols.clear();
      _outlineDocKey = '';
      return;
    }
    final r = active.doc.core.lsp.symbols(active.id);
    if (r == null) return;
    final key = '${active.name}#${r.version}';
    if (key == _outlineDocKey) return;
    _outlineDocKey = key;
    _outlineSymbols
      ..clear()
      ..addAll([
        for (final s in r.symbols)
          (
            kind: s['kind'] as String? ?? '',
            name: s['name'] as String? ?? '',
            startUtf16: (s['start_utf16'] as num?)?.toInt() ?? 0,
            line: (s['line'] as num?)?.toInt() ?? 0,
          )
      ]);
  }

  /// 编辑后防抖刷新大纲。
  void _scheduleOutlineRefresh() {
    _outlineTimer?.cancel();
    _outlineTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(_refreshOutline);
    });
  }

  void _jumpToSymbol(int startUtf16) {
    final active = _active;
    if (active == null) return;
    _setDocSelection(
      active,
      TextSelection.collapsed(offset: startUtf16),
    );
    setState(() {});
  }

  /// 光标处的 Rust 标识符词，支持 Unicode XID 字符与 UTF-16 偏移。
  String _wordAt(String text, int offset) {
    final pos = offset.clamp(0, text.length).toInt();
    for (final match in _rustIdentifierPattern.allMatches(text)) {
      if (pos >= match.start && pos <= match.end) return match.group(0)!;
    }
    return '';
  }

  /// Navigate with the language server when available, retaining the local
  /// Rust outline fallback for same-file definitions.
  Future<void> _gotoDefinition() async {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final sel = active.selection;
    final offset = sel.baseOffset >= 0 ? sel.baseOffset : 0;
    final word = _wordAt(active.text, offset);
    if (word.isEmpty) {
      setState(() => _statusDetail = '光标不在符号上');
      return;
    }
    final sourceVersion = active.doc.version;
    final provider = widget.definitionRequest;
    if (provider != null || active.lspAttached) {
      try {
        DefinitionResult? definition;
        if (provider != null) {
          definition = await provider(active.id, offset, sourceVersion);
        } else {
          final stopwatch = Stopwatch()..start();
          definition = await active.doc.core.lsp.definition(active.id, offset);
          if (definition == null && stopwatch.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (!mounted || !identical(_active, active)) return;
            if (active.doc.version != sourceVersion) {
              setState(() => _statusDetail = '文档已更改，已取消跳转');
              return;
            }
            definition = await active.doc.core.lsp.definition(
              active.id,
              offset,
              timeoutMs: 2500,
            );
          }
        }
        if (!mounted || !identical(_active, active)) return;
        if (active.doc.version != sourceVersion ||
            (definition != null && definition.version != sourceVersion)) {
          setState(() => _statusDetail = '文档已更改，已取消跳转');
          return;
        }
        if (definition != null) {
          final navigated = await _navigateToDefinition(
            active,
            offset,
            definition,
          );
          if (!navigated && mounted) {
            setState(() => _statusDetail = '无法打开定义位置');
          }
          return;
        }
      } catch (error) {
        if (!mounted || !identical(_active, active)) return;
        setState(() => _statusDetail = 'LSP 定义请求失败：$error');
      }
    }

    _gotoDefinitionInCurrentFile(active, word, offset);
  }

  void _gotoDefinitionInCurrentFile(OpenDoc active, String word, int offset) {
    final r = active.doc.core.lsp.symbols(active.id);
    final defs =
        (r?.symbols ?? const []).where((s) => s['name'] == word).map((s) {
      final start = (s['start_utf16'] as num?)?.toInt() ?? 0;
      final lineEnd = active.text.indexOf('\n', start);
      final declaration = active.text.substring(
        start,
        lineEnd < 0 ? active.text.length : lineEnd,
      );
      var nameOffset = -1;
      for (final match in _rustIdentifierPattern.allMatches(declaration)) {
        if (match.group(0) == word) {
          nameOffset = match.start;
          break;
        }
      }
      return nameOffset < 0 ? start : start + nameOffset;
    }).toList();
    if (defs.isEmpty) {
      setState(() => _statusDetail = '未找到「$word」的定义（当前文件）');
      return;
    }
    // 排除光标正踩着的定义本身；跳第一个真实定义
    final target = defs.where((d) => d != offset).isEmpty
        ? defs.first
        : defs.firstWhere((d) => d != offset);
    final owner = _ownerOfView(active);
    if (owner != null) {
      try {
        final from = _navigationLocation(active, offset, owner.region);
        final to = _navigationLocation(active, target, owner.region);
        _navigationHistory.recordNavigation(from, to);
      } on AlulaException {
        // The document may have changed while its local symbols were read.
      }
    }
    _jumpToSymbol(target);
    setState(() => _statusDetail = '跳转到 $word（定义）');
  }

  Future<bool> _navigateToDefinition(
    OpenDoc source,
    int sourceOffset,
    DefinitionResult definition,
  ) async {
    final path = _pathFromFileUri(definition.uri);
    if (path == null) return false;
    final sourceGroup = _ownerOfView(source);
    if (sourceGroup == null) return false;
    setState(() => _focusedRegion = sourceGroup.region);

    final sameFile = source.path != null && _pathsEqual(source.path!, path);
    if (!sameFile) await _openFileByPath(path);
    if (!mounted || (sameFile && !identical(_active, source))) return false;
    final target = sameFile ? source : _active;
    if (target == null ||
        target.path == null ||
        !_pathsEqual(target.path!, path)) {
      return false;
    }
    final targetPosition = target.doc.positionOffset(
      definition.line,
      definition.character,
    );
    final targetGroup = _ownerOfView(target);
    if (targetGroup == null) return false;
    final from = _navigationLocation(source, sourceOffset, sourceGroup.region);
    final to = NavigationLocation(
      uri: target.uri,
      path: target.path,
      documentId: target.id,
      groupRegion: targetGroup.region,
      line: targetPosition.line,
      character: targetPosition.character,
      version: targetPosition.version,
    );
    _navigationHistory.recordNavigation(from, to);
    _setDocSelection(
      target,
      TextSelection.collapsed(offset: targetPosition.offsetUtf16),
    );
    setState(() => _statusDetail = '跳转到 ${target.name}（定义）');
    return true;
  }

  NavigationLocation _navigationLocation(
    OpenDoc doc,
    int offsetUtf16,
    String groupRegion,
  ) {
    final position = doc.doc.positionAt(offsetUtf16);
    return NavigationLocation(
      uri: doc.uri,
      path: doc.path,
      documentId: doc.id,
      groupRegion: groupRegion,
      line: position.line,
      character: position.character,
      version: position.version,
    );
  }

  NavigationLocation? _currentNavigationLocation() {
    final active = _active;
    final group = active == null ? null : _ownerOfView(active);
    if (active == null || group == null) return null;
    try {
      return _navigationLocation(
        active,
        active.selection.extentOffset,
        group.region,
      );
    } on AlulaException {
      return null;
    }
  }

  Future<void> _navigateBack() async {
    final current = _currentNavigationLocation();
    if (current == null) return;
    final target = _navigationHistory.goBack(current);
    if (target == null) {
      setState(() => _statusDetail = '没有更早的导航位置');
      return;
    }
    if (!await _restoreNavigationLocation(target) && mounted) {
      setState(() => _statusDetail = '无法恢复导航位置');
    }
  }

  Future<void> _navigateForward() async {
    final current = _currentNavigationLocation();
    if (current == null) return;
    final target = _navigationHistory.goForward(current);
    if (target == null) {
      setState(() => _statusDetail = '没有更新的导航位置');
      return;
    }
    if (!await _restoreNavigationLocation(target) && mounted) {
      setState(() => _statusDetail = '无法恢复导航位置');
    }
  }

  Future<void> _navigateToLastEdit() async {
    final target = _navigationHistory.lastEdit;
    final current = _currentNavigationLocation();
    if (target == null || current == null) {
      setState(() => _statusDetail = '没有可用的上次编辑位置');
      return;
    }
    _navigationHistory.recordNavigation(current, target);
    if (!await _restoreNavigationLocation(target) && mounted) {
      setState(() => _statusDetail = '无法恢复上次编辑位置');
    }
  }

  Future<bool> _restoreNavigationLocation(NavigationLocation location) async {
    final targetGroup = _groups[location.groupRegion] ?? _focused;
    setState(() => _focusedRegion = targetGroup.region);
    if (location.path != null) {
      await _openFileByPath(location.path!);
      if (!mounted) return false;
      final active = _active;
      if (active == null ||
          active.path == null ||
          !_pathsEqual(active.path!, location.path!)) {
        return false;
      }
    } else {
      final existing = _allDocViews
          .where((view) => view.id == location.documentId)
          .firstOrNull;
      if (existing == null) return false;
      final view = targetGroup.docs
              .where((candidate) => candidate.sameDocumentAs(existing))
              .firstOrNull ??
          OpenDoc.viewOf(existing);
      setState(() {
        if (!targetGroup.docs.contains(view)) targetGroup.docs.add(view);
        targetGroup.activeDocId = view.id;
      });
    }

    final active = _active;
    if (active == null) return false;
    DocumentPosition position;
    try {
      position = active.doc.positionOffset(location.line, location.character);
    } on AlulaException catch (error) {
      if (error.code != 'InvalidLine') return false;
      final snapshot = active.doc.readRange(0, maxLenUtf16: 1);
      position = active.doc.positionOffset(snapshot.lineCount - 1, 0);
    }
    _setDocSelection(
      active,
      TextSelection.collapsed(offset: position.offsetUtf16),
    );
    return true;
  }

  String? _pathFromFileUri(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'file') return null;
      return uri.toFilePath(windows: Platform.isWindows);
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  bool _pathsEqual(String left, String right) {
    final a = left.replaceAll('\\', '/');
    final b = right.replaceAll('\\', '/');
    return Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;
  }

  /// Ctrl+Click 跳转定义：从点击的全局坐标求字符偏移。
  void _onEditorPointerDown(
    EditorGroup group,
    OpenDoc view,
    BuildContext editorContext,
    PointerDownEvent event,
  ) {
    view.clearPendingOvertypeInput();
    _pendingDefinitionPointers.remove(event.pointer);
    if (event.buttons != kPrimaryButton) return;
    final control = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final gotoModifier = control || meta;
    if (event.kind == PointerDeviceKind.mouse &&
        alt &&
        shift &&
        !gotoModifier) {
      _pendingColumnSelectionStarts[event.pointer] = (
        view: view,
        selections: view.selectionSet,
      );
      return;
    }
    if (!gotoModifier && !alt) {
      if (view.crossWindowSelection != null) {
        view.crossWindowSelection = null;
        if (mounted) setState(() {});
        _syncCommandContext();
      }
      if (view.additionalSelections.isNotEmpty) {
        final previous = view.selectionSet;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(_active, view)) return;
          view.selectionHistory.record(previous);
          view.additionalSelections = const [];
          view.columnSelection = null;
          setState(() {});
          _syncCommandContext();
        });
      }
      return;
    }
    if (!editorContext.mounted) return;
    final fieldContext = view.inputFieldKey.currentState?.context;
    if (fieldContext == null) return;
    final editable = _findRenderEditable(fieldContext);
    if (editable == null) return;
    final pos = editable.getPositionForPoint(event.position);
    final active = view;
    final localOffset =
        pos.offset.clamp(0, active.editingValue.text.length).toInt();
    final offset = active.inputWindow.startUtf16 + localOffset;
    if (alt && !gotoModifier) return;
    _pendingDefinitionPointers[event.pointer] = (
      group: group,
      view: active,
      offset: offset,
      position: event.position,
    );
  }

  /// Apply Ctrl/Cmd+Click after EditableText has processed pointer-up selection.
  void _onEditorPointerUp(PointerUpEvent event) {
    _pendingColumnSelectionStarts.remove(event.pointer);
    final pending = _pendingDefinitionPointers.remove(event.pointer);
    if (pending == null ||
        (event.position - pending.position).distance > kTouchSlop) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_active, pending.view)) return;
      _focusedRegion = pending.group.region;
      _setDocSelection(
        pending.view,
        TextSelection.collapsed(offset: pending.offset),
      );
      _runCommand('editor.gotoDef');
    });
  }

  void _onEditorPointerCancel(PointerCancelEvent event) {
    _pendingColumnSelectionStarts.remove(event.pointer);
    _pendingDefinitionPointers.remove(event.pointer);
  }

  void _applyColumnSelectionDrag(
    OpenDoc view,
    ColumnSelectionState selection, {
    required bool started,
    List<TextSelection>? selectionsBeforeDrag,
  }) {
    if (!mounted || !_allDocViews.contains(view)) return;
    _flushInput(view);
    final window = view.inputWindow;
    if (window.version != view.doc.version) return;
    final selectionCount =
        (selection.activeLine - selection.anchorLine).abs() + 1;
    if (selectionCount > defaultMultiCursorLimit) {
      return;
    }
    final resolved = view.doc.columnSelectionsUtf16(
      anchorLine: selection.anchorLine,
      anchorColumnUtf16: selection.anchorColumn,
      activeLine: selection.activeLine,
      activeColumnUtf16: selection.activeColumn,
      maxSelections: defaultMultiCursorLimit,
    );
    if (resolved.version != window.version) return;
    if (started && selectionsBeforeDrag != null) {
      view.selectionHistory.record(selectionsBeforeDrag);
    }
    final absoluteSelections = resolved.selections
        .map((item) => TextSelection(
              baseOffset: item.baseOffsetUtf16,
              extentOffset: item.extentOffsetUtf16,
            ))
        .toList(growable: false);
    final primary = absoluteSelections.first;
    const rewindowMarginUtf16 = 2048;
    final hasDocumentTextBefore = primary.extentOffset > 0;
    final hasDocumentTextAfter =
        primary.extentOffset < window.totalUtf16Length;
    final nearWindowEdge = hasDocumentTextBefore &&
            primary.extentOffset <= window.startUtf16 + rewindowMarginUtf16 ||
        hasDocumentTextAfter &&
            primary.extentOffset >= window.endUtf16 - rewindowMarginUtf16;
    if (nearWindowEdge) {
      view.replaceInputWindow(primary.extentOffset, selection: primary);
      view.crossWindowSelection = null;
      view.additionalSelections = List.unmodifiable(absoluteSelections.skip(1));
      view.columnSelection = selection;
      if (mounted) setState(() {});
      _syncCommandContext();
      return;
    }
    _setDocSelections(
      view,
      absoluteSelections,
      columnSelection: selection,
      recordHistory: false,
    );
  }

  static RenderEditable? _findRenderEditable(BuildContext ctx) {
    return _findRenderEditableOf(ctx.findRenderObject());
  }

  static RenderEditable? _findRenderEditableOf(RenderObject? obj) {
    if (obj is RenderEditable) return obj;
    RenderEditable? found;
    obj?.visitChildren((child) {
      found ??= _findRenderEditableOf(child);
    });
    return found;
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
      _selectedSearchHit = null;
      _selectedSearchDocId = -1;
      _selectedSearchDocVersion = -1;
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
    setState(() {
      _selectedSearchHit = null;
      _selectedSearchDocId = -1;
      _selectedSearchDocVersion = -1;
    });
    final sep = root.endsWith('/') || root.endsWith('\\') ? '' : '/';
    await _openFileByPath('$root$sep${hit.path}');
    if (!mounted) return;
    final active = _active;
    if (active == null) return;
    final lines = active.text.split('\n');
    final requestedLine = hit.line - 1;
    final line = requestedLine.clamp(0, lines.length - 1).toInt();
    final lineOffset = active.doc.lineOffset(line);
    _setDocSelection(
      active,
      TextSelection.collapsed(offset: lineOffset.offsetUtf16),
    );
    final hitStillMatchesDocument =
        line == requestedLine && lines[line] == hit.lineText;
    setState(() {
      _selectedSearchHit = hitStillMatchesDocument ? hit : null;
      _selectedSearchDocId = hitStillMatchesDocument ? active.id : -1;
      _selectedSearchDocVersion =
          hitStillMatchesDocument ? active.doc.version : -1;
    });
  }

  // ---------- 工作区文件监视（feat-filewatch） ----------

  void _attachWorkspaceWatcher() {
    final root = _workspaceRoot;
    final current = _watcher;
    if (root == null) {
      _stopWorkspaceWatcher();
      return;
    }
    if (current != null && current.root == root && current.isWatching) return;

    final generation = ++_watcherGeneration;
    _watcher = null;
    _watcherTransition =
        _watcherTransition.catchError((Object error, StackTrace stack) {
      debugPrint('工作区 watcher 上次切换失败：$error');
    }).then((_) async {
      await current?.stop();
      if (!mounted ||
          generation != _watcherGeneration ||
          _workspaceRoot != root) {
        return;
      }
      final watcher = WorkspaceWatcher(
        root: root,
        onChanged: () {
          if (mounted &&
              generation == _watcherGeneration &&
              _workspaceRoot == root) {
            unawaited(_onWorkspaceChanged(root));
          }
        },
      );
      _watcher = watcher;
      await watcher.start();
      if (generation != _watcherGeneration && identical(_watcher, watcher)) {
        _watcher = null;
        await watcher.stop();
      }
    }).catchError((Object error, StackTrace stack) {
      debugPrint('工作区 watcher 切换失败：$error');
    });
  }

  void _stopWorkspaceWatcher() {
    ++_watcherGeneration;
    final watcher = _watcher;
    _watcher = null;
    _watcherTransition =
        _watcherTransition.catchError((Object error, StackTrace stack) {
      debugPrint('工作区 watcher 切换失败：$error');
    }).then((_) async {
      await watcher?.stop();
    }).catchError((Object error, StackTrace stack) {
      debugPrint('工作区 watcher 停止失败：$error');
    });
  }

  /// 外部变更（防抖后）：刷新文件树 + Git 状态；打开文档若在磁盘上被外部
  /// 修改，干净文档自动重载、脏文档仅提示（不覆盖本地编辑）。
  Future<void> _onWorkspaceChanged(String root) async {
    if (!mounted || _workspaceRoot != root) return;
    _refreshTree();
    _refreshGit();
    await _checkExternalChanges();
  }

  /// 重载文件树：全量重建但**保留展开状态**（外部刷新不能抹掉用户的
  /// 展开层级——否则每次 git status 写 .git 都会把树折回去）。
  void _refreshTree() {
    final core = _core;
    if (core == null || _workspaceRoot == null) return;

    // 快照展开目录路径
    final expandedPaths = <String>{};
    void snapshot(List<TreeNode> nodes) {
      for (final n in nodes) {
        if (n.isDir && n.expanded) expandedPaths.add(n.path);
        if (n.children != null) snapshot(n.children!);
      }
    }

    snapshot(_treeRoots);
    _reloadTreeRoots();

    // 恢复展开态并重载对应子节点
    void restore(List<TreeNode> nodes) {
      for (final n in nodes) {
        if (!n.isDir || !expandedPaths.contains(n.path)) continue;
        n.expanded = true;
        try {
          final entries = core.workspace.listDir(n.path);
          n.children = entries
              .map((e) => TreeNode(
                    name: e['name'] as String,
                    path: e['path'] as String,
                    isDir: (e['is_dir'] as bool?) ?? false,
                  ))
              .toList();
          restore(n.children!);
        } on AlulaException {
          // 目录被外部删除：跳过该分支
        }
      }
    }

    restore(_treeRoots);
    if (mounted) setState(() {});
  }

  Future<void> _checkExternalChanges() async {
    final core = _core;
    if (core == null) return;
    for (final g in _groups.values) {
      for (final d in g.docs.where((d) => d.path != null)) {
        _flushInput(d, commitComposition: true);
        DecodedTextFile disk;
        try {
          disk = _readDiskDocument(
            core,
            d.path!,
            preferredEncoding: d.savedFileOptions.encoding,
          );
        } on AlulaException catch (error) {
          final nextState = error.code == 'NotFound'
              ? DiskDocumentState.missing
              : DiskDocumentState.unavailable;
          if (d.diskState != nextState) {
            d.diskState = nextState;
            _updateDirty(d);
            if (error.code == 'NotFound') {
              _statusDetail = '${d.name} 已从磁盘删除或移动；本地缓冲区仍可编辑';
            } else {
              _statusDetail = '读取 ${d.name} 的磁盘版本失败：${error.code}';
            }
          }
          continue;
        }
        final currentText = d.doc.resync().content;
        final diskMatchesBuffer =
            disk.content == currentText && disk.options == d.fileOptions;
        if (diskMatchesBuffer) {
          d.doc.markSaved();
          d.savedFileOptions = disk.options;
          d.dirtyDisk = false;
          if (d.diskState != DiskDocumentState.readOnly) {
            d.diskState = DiskDocumentState.current;
            d.conflictBaselineKnown = true;
          }
          continue;
        }
        if (d.dirtyDisk) {
          final diskMatchesSavepoint = d.doc.savepointMatches(disk.content) &&
              disk.options == d.savedFileOptions;
          if (d.diskState == DiskDocumentState.conflict &&
              !d.conflictBaselineKnown) {
            // 旧 session journal 没有原文快照；直到两侧收敛或用户显式处理，
            // 保持冲突状态，不能因为重新读取同一磁盘版本而解除提示。
            continue;
          }
          if (!diskMatchesSavepoint) {
            d.diskState = DiskDocumentState.conflict;
            d.conflictBaselineKnown = true;
            _statusDetail = '注意：${d.name} 在磁盘上被外部修改；本地编辑已保留';
          } else if (d.diskState != DiskDocumentState.readOnly) {
            d.diskState = DiskDocumentState.current;
            d.conflictBaselineKnown = true;
          }
        } else if (d.diskState == DiskDocumentState.conflict) {
          // 即使本地通过 undo 回到旧 savepoint，已发现的外部冲突也要显式处理；
          // watcher 的后续事件不能把任一侧静默替换掉。
          continue;
        } else if (disk.content != currentText ||
            disk.options != d.fileOptions) {
          // 干净文档自动重载时保留光标、选区与每文档滚动位置，不产生撤销历史。
          final oldSelection = d.selection;
          int clampOffset(int offset) =>
              offset.clamp(0, disk.content.length).toInt();
          final selection = TextSelection(
            baseOffset: clampOffset(oldSelection.baseOffset),
            extentOffset: clampOffset(oldSelection.extentOffset),
            affinity: oldSelection.affinity,
            isDirectional: oldSelection.isDirectional,
          );
          final oldScrollOffset =
              editorPrimaryScrollPosition(d.editorScrollController)?.pixels;
          final reloadOps = diffToOps(currentText, disk.content);
          if (reloadOps.isNotEmpty) d.doc.apply(reloadOps);
          d.doc.setSavepoint(disk.content);
          d.replaceInputWindow(selection.extentOffset, selection: selection);
          if (reloadOps.isNotEmpty) _refreshSiblingViews(d, reloadOps);
          d.fileOptions = disk.options;
          d.savedFileOptions = disk.options;
          d.dirtyDisk = false;
          d.undoStack.clear();
          d.lastEditAt = null;
          if (d.diskState != DiskDocumentState.readOnly) {
            d.diskState = DiskDocumentState.current;
          }
          d.conflictBaselineKnown = true;
          _statusDetail = '已自动重载外部修改的 ${d.name}';
          if (oldScrollOffset != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              for (final position in d.editorScrollController.positions
                  .toList(growable: false)) {
                position.jumpTo(
                  oldScrollOffset
                      .clamp(
                        position.minScrollExtent,
                        position.maxScrollExtent,
                      )
                      .toDouble(),
                );
              }
            });
          }
        } else if (d.diskState == DiskDocumentState.missing ||
            d.diskState == DiskDocumentState.unavailable) {
          d.diskState = DiskDocumentState.current;
          d.conflictBaselineKnown = true;
        }
      }
    }
    if (mounted) setState(() {});
    _syncCommandContext();
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
        _gitDiffPath =
            e.origPath == null ? e.path : '${e.origPath} → ${e.path}';
        _gitDiffStaged = staged;
      });
      _panelTab.animateTo(3);
    } catch (err) {
      if (mounted) setState(() => _gitError = '$err');
    }
  }

  /// 侧栏视图切换（W4）：重复点当前视图 = 折叠/展开侧栏。
  void _selectSidebarView(String view) {
    if (view == 'outline') _refreshOutline();
    if (_sidebarView == view && !_layout.isCollapsed('sidebar')) {
      _layout.toggleRegion('sidebar');
      return;
    }
    setState(() {
      _sidebarView = view;
      if (view == 'outline') _refreshOutline();
    });
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
    _disposing = true;
    _pendingDefinitionPointers.clear();
    _pendingColumnSelectionStarts.clear();
    _pendingMoveSelectionChordTimer?.cancel();
    _pollTimer?.cancel();
    _resourceTimer?.cancel();
    _stateSaveTimer?.cancel();
    for (final d in _allDocViews) {
      _flushInput(d, commitComposition: true);
    }
    _shutdownLspWorkspace();
    // 退出前把未落盘的布局与会话冲写
    widget.layoutStore.save(_layout.root);
    widget.sessionStore.save(_encodeSession());
    for (final d in _allDocViews.toList()) {
      d.disposeView();
    }
    for (final n in _editorFocusNodes.values) {
      n.dispose();
    }
    _searchSub?.cancel();
    _commands
      ..removeListener(_onCommandServiceChanged)
      ..dispose();
    _searchQuery.dispose();
    _outlineTimer?.cancel();
    _stopWorkspaceWatcher();
    for (final timer in _syntaxRefreshTimers.values) {
      timer.cancel();
    }
    _syntaxRefreshTimers.clear();
    _panelTab.dispose();
    _commitMessage.dispose();
    _layout.dispose();
    super.dispose();
  }

  void _shutdownLspWorkspace() {
    final core = _core;
    final root = _workspaceRoot;
    if (_lspReady && core != null && root != null) {
      try {
        core.lsp.shutdownWorkspace(root);
      } catch (e) {
        debugPrint('关闭工作区语言服务器失败：$e');
      }
    }
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
                const Icon(Icons.error_outline,
                    size: 40, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('无法加载 Alula 核心',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(_loadError,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          if (_commands.isEnabled('editor.cursorPageUp'))
            const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                _runCommand('editor.cursorPageUp'),
          if (_commands.isEnabled('editor.cursorPageUpSelect'))
            const SingleActivator(LogicalKeyboardKey.pageUp, shift: true): () =>
                _runCommand('editor.cursorPageUpSelect'),
          if (_commands.isEnabled('editor.cursorPageDown'))
            const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                _runCommand('editor.cursorPageDown'),
          if (_commands.isEnabled('editor.cursorPageDownSelect'))
            const SingleActivator(LogicalKeyboardKey.pageDown, shift: true):
                () => _runCommand('editor.cursorPageDownSelect'),
          for (final e in _keybindings
              .resolveBindings(matchesWhen: _commands.context.matches)
              .entries
              .where((entry) => _commands.isEnabled(entry.value.commandId)))
            e.key: () =>
                _runCommand(e.value.commandId, arguments: e.value.arguments),
        },
        child: Focus(
          autofocus: true, // 无处可聚焦时也保证全局键位可达（W3-1）
          child: Column(
            children: [
              AlulaTitleBar(
                  commands: _commands,
                  windowControls: widget.windowControls,
                  onCloseRequested: _shutdownLspWorkspace,
                  menus: [
                    (
                      '文件',
                      [
                        const TitleMenuItem('打开文件夹',
                            commandId: 'file.openFolder'),
                        TitleMenuItem('保存${_sc('file.save')}',
                            commandId: 'file.save'),
                        TitleMenuItem('另存为…${_sc('file.saveAs')}',
                            commandId: 'file.saveAs'),
                        const TitleMenuItem('从磁盘还原', commandId: 'file.revert'),
                        const TitleMenuItem('使用编码保存…',
                            commandId: 'file.saveWithEncoding'),
                        const TitleMenuItem('使用编码重新打开…',
                            commandId: 'file.reopenWithEncoding'),
                        const TitleMenuItem('选择行尾…',
                            commandId: 'file.selectEol'),
                      ],
                    ),
                    (
                      '编辑',
                      [
                        TitleMenuItem('撤销${_sc('editor.undo')}',
                            commandId: 'editor.undo'),
                        TitleMenuItem('重做${_sc('editor.redo')}',
                            commandId: 'editor.redo'),
                        TitleMenuItem('查找…${_sc('editor.find')}',
                            commandId: 'editor.find'),
                        TitleMenuItem('替换…${_sc('editor.replace')}',
                            commandId: 'editor.replace'),
                      ],
                    ),
                    (
                      '查看',
                      [
                        TitleMenuItem('命令面板${_sc('view.commandPalette')}',
                            commandId: 'view.commandPalette'),
                        TitleMenuItem('快速打开文件…${_sc('view.quickOpen')}',
                            commandId: 'view.quickOpen'),
                        TitleMenuItem('搜索…${_sc('view.search')}',
                            commandId: 'view.search'),
                        const TitleMenuItem('大纲', commandId: 'view.outline'),
                        const TitleMenuItem('切换侧栏',
                            commandId: 'view.toggleSidebar'),
                        const TitleMenuItem('切换面板',
                            commandId: 'view.togglePanel'),
                      ],
                    ),
                    (
                      '帮助',
                      [
                        const TitleMenuItem('关于 Alula Code',
                            commandId: 'help.about'),
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
                            'outline' => _buildOutlinePanel(),
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
                tabCount: _allDocViews.length,
                abiVersion: _abiVersion,
                resourcePressure: _resourceStatus?.pressure,
                availableBytes: _resourceStatus?.availableBytes,
                totalBytes: _resourceStatus?.totalBytes,
                resourceSource: _resourceStatus?.source,
                syncCount: _syncCount,
                panelCollapsed: _layout.isCollapsed('panel'),
                onTogglePanel: () => _layout.toggleRegion('panel'),
                encodingLabel: _active?.fileOptions.statusLabel,
                encodingTooltip: _active?.fileOptions.label,
                lineEndingLabel: _active?.fileOptions.lineEnding.label,
                overtypeMode: _overtypeMode && _active != null,
                onToggleOvertype: _toggleOvertypeInsertMode,
                onEncodingTap: _active == null
                    ? null
                    : () => _showEncodingActions(_active!),
                onLineEndingTap:
                    _active == null ? null : _selectLineEndingActive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 侧栏：大纲 ----------

  Widget _buildOutlinePanel() {
    final active = _active;
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Text(
              active == null ? '大纲' : '大纲 · ${active.name}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: active == null || _outlineSymbols.isEmpty
                ? Center(
                    child: Text(
                      active == null
                          ? '无打开文档'
                          : (_outlineSymbols.isEmpty ? '未发现符号（仅支持 Rust）' : ''),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _outlineSymbols.length,
                    itemBuilder: (context, i) {
                      final sym = _outlineSymbols[i];
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          key: ValueKey('outline-$i'),
                          dense: true,
                          leading: Container(
                            width: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2F3542),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              _outlineKindBadge(sym.kind),
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.lightBlueAccent
                                    .withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          title: Text(sym.name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text('行 ${sym.line}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                          onTap: () => _jumpToSymbol(sym.startUtf16),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _outlineKindBadge(String kind) => switch (kind) {
        'function' => 'fn',
        'struct' => 'st',
        'enum' => 'en',
        'trait' => 'tr',
        'impl' => 'im',
        'mod' => 'mo',
        'const' => 'co',
        'static' => 'st',
        'type' => 'ty',
        'macro' => 'ma',
        _ => kind.isEmpty ? '?' : kind.substring(0, 2),
      };

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
                    setState(
                        () => _searchCaseSensitive = !_searchCaseSensitive);
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
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 12),
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
                          subtitle: Text('${_nameOf(hit.path)} · 行 ${hit.line}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500),
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
    final staged = _gitEntries.where((e) => e.hasStagedChanges).toList();
    final changes = _gitEntries.where((e) => !e.hasStagedChanges).toList();
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
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 11)),
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
                    label: Text(
                        staged.isEmpty ? '没有暂存的更改' : '提交（${staged.length}）'),
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
                        for (final e in staged) _gitTile(e, stagedEntry: true),
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
                    : (stagedEntry
                        ? Colors.lightGreenAccent
                        : Colors.orangeAccent))),
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
                    _workspaceRoot == null ? '资源管理器' : _nameOf(_workspaceRoot!),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '打开文件夹',
                  onPressed: () => _runCommand('file.openFolder'),
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
          color:
              activePaths.contains(node.path) ? const Color(0xFF20252E) : null,
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
    final normRoot = _normPath(_workspaceRoot!).replaceAll(RegExp(r'/+$'), '');
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
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

  String _canonicalPath(String path) {
    final absolute = _normPath(File(path).absolute.path);
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

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
            onPressed: () => _runCommand('editor.split'),
            icon: const Icon(Icons.splitscreen, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: _lspReady
                ? 'LSP 运行中'
                : (_workspaceRoot == null ? '启动 LSP（需先打开文件夹）' : '启动 LSP'),
            onPressed: _commands.isEnabled('lsp.start')
                ? () => _runCommand('lsp.start')
                : null,
            icon: Icon(_lspReady ? Icons.check_circle : Icons.play_arrow,
                size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '补全    Ctrl+Space',
            onPressed: _commands.isEnabled('editor.completion')
                ? () => _runCommand('editor.completion')
                : null,
            icon: const Icon(Icons.autorenew, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '校验一致性',
            onPressed: _commands.isEnabled('editor.verifyIntegrity')
                ? () => _runCommand('editor.verifyIntegrity')
                : null,
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
      onTap: () {
        final current = _active;
        if (current != null && !identical(current, d)) {
          _flushInput(current, commitComposition: true);
        }
        setState(() {
          g.activeDocId = d.id;
          _focusedRegion = g.region;
        });
        _syncCommandContext();
      },
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
            if (d.diskState != DiskDocumentState.current) ...[
              const SizedBox(width: 4),
              Icon(
                switch (d.diskState) {
                  DiskDocumentState.current => Icons.check,
                  DiskDocumentState.conflict => Icons.sync_problem_outlined,
                  DiskDocumentState.missing => Icons.file_present_outlined,
                  DiskDocumentState.readOnly => Icons.lock_outline,
                  DiskDocumentState.unavailable => Icons.warning_amber_outlined,
                },
                key: ValueKey('tab-disk-state-${d.id}'),
                size: 13,
                color: d.diskState == DiskDocumentState.conflict
                    ? Colors.orangeAccent
                    : Colors.blueGrey.shade300,
              ),
            ],
            const SizedBox(width: 6),
            InkWell(
              key: ValueKey('close-tab-${g.region}-${d.id}'),
              onTap: () => _closeDoc(d.id, group: g),
              child: Icon(Icons.close, size: 12, color: Colors.grey.shade500),
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
            if (e.buttons == kMiddleMouseButton) _closeDoc(d.id, group: g);
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
    final moved = g.docs[from];
    _editorFocusNodes.remove(_focusKeyFor(g, moved))?.dispose();
    setState(() {
      final doc = g.docs.removeAt(from);
      g.docs.insert(to, doc);
    });
    _scheduleStateSave();
  }

  Widget _buildDiskStateBanner(OpenDoc doc) {
    final (icon, message, color) = switch (doc.diskState) {
      DiskDocumentState.current => (
          Icons.check_circle_outline,
          '',
          Colors.transparent
        ),
      DiskDocumentState.conflict => (
          Icons.sync_problem_outlined,
          '磁盘上的 ${doc.name} 已变化，本地缓冲区仍保留。',
          Colors.orange.shade900
        ),
      DiskDocumentState.missing => (
          Icons.file_present_outlined,
          '${doc.name} 已从磁盘删除或移动；缓冲区仍可编辑。',
          Colors.blueGrey.shade800
        ),
      DiskDocumentState.readOnly => (
          Icons.lock_outline,
          '${doc.name} 是只读文件，原文件未被覆盖。',
          Colors.blueGrey.shade800
        ),
      DiskDocumentState.unavailable => (
          Icons.warning_amber_outlined,
          '无法读取 ${doc.name} 的当前磁盘版本；本地缓冲区已保留。',
          Colors.red.shade900
        ),
    };
    final actions = switch (doc.diskState) {
      DiskDocumentState.current => const <Widget>[],
      DiskDocumentState.conflict => <Widget>[
          TextButton(
            key: const ValueKey('external-reload'),
            onPressed: _revertActive,
            child: const Text('从磁盘重载'),
          ),
          TextButton(
            key: const ValueKey('external-overwrite'),
            onPressed: () => _saveDocToPath(doc, doc.path!),
            child: const Text('覆盖磁盘…'),
          ),
          TextButton(
            key: const ValueKey('external-save-as'),
            onPressed: () => _saveAsDoc(doc),
            child: const Text('另存为…'),
          ),
        ],
      DiskDocumentState.missing => <Widget>[
          TextButton(
            key: const ValueKey('external-save-as'),
            onPressed: () => _saveAsDoc(doc),
            child: const Text('另存为…'),
          ),
        ],
      DiskDocumentState.readOnly => <Widget>[
          TextButton(
            key: const ValueKey('external-retry-save'),
            onPressed: () => _saveDocToPath(doc, doc.path!),
            child: const Text('重试保存'),
          ),
          TextButton(
            key: const ValueKey('external-save-as'),
            onPressed: () => _saveAsDoc(doc),
            child: const Text('另存为…'),
          ),
        ],
      DiskDocumentState.unavailable => <Widget>[
          TextButton(
            key: const ValueKey('external-retry-read'),
            onPressed: _checkExternalChanges,
            child: const Text('重试读取'),
          ),
          TextButton(
            key: const ValueKey('external-save-as'),
            onPressed: () => _saveAsDoc(doc),
            child: const Text('另存为…'),
          ),
        ],
    };
    return Container(
      key: ValueKey('disk-state-${doc.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child:
                    Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 4, runSpacing: 0, children: actions),
        ],
      ),
    );
  }

  Widget _buildJournalNoticeBanner({
    required String key,
    required String message,
    required VoidCallback onDismiss,
  }) {
    return Container(
      key: ValueKey(key),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      child: MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(onPressed: onDismiss, child: const Text('关闭提示')),
        ],
      ),
    );
  }

  Widget _buildEditor(EditorGroup g) {
    final active = g.active;
    if (active == null) {
      return Center(
        child: Text('打开文件夹后，从文件树选择文件',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    final usesRustSyntax = active.path?.toLowerCase().endsWith('.rs') == true;
    final treeSyntaxTokens = usesRustSyntax
        ? _syntaxByDoc[active.id] ?? const <Map<String, Object?>>[]
        : const <Map<String, Object?>>[];
    final treeSyntaxVersion =
        usesRustSyntax ? _syntaxVersionByDoc[active.id] ?? -1 : -1;
    final semanticTokens = _semanticTokensByDoc[active.id] ?? const [];
    final semanticVersion = _semanticTokensVersionByDoc[active.id] ?? -1;
    final highlight = active.lspAttached
        ? selectEditorHighlightTokens(
            semanticTokens: semanticTokens,
            semanticVersion: semanticVersion,
            documentVersion: active.doc.version,
            inputWindowVersion: active.inputWindow.version,
            hasPendingInput: active.inputWindow.pendingText != null,
            fallbackTokens: treeSyntaxTokens,
            fallbackVersion: treeSyntaxVersion,
          )
        : (tokens: treeSyntaxTokens, version: treeSyntaxVersion);
    final syntaxTokens = highlight.tokens;
    final syntaxVersion = highlight.version;
    final findDecorations = _findDecorationsFor(active);
    final diagnosticDecorations = _diagnosticDecorationsFor(active);
    final workspaceSearchDecorations = _workspaceSearchDecorationsFor(active);
    final rangeDecorations = [
      ...findDecorations,
      ...diagnosticDecorations,
      ...workspaceSearchDecorations,
    ];
    final crossWindowSelection = active.crossWindowSelection;
    if (crossWindowSelection != null) {
      rangeDecorations.add(
        EditorRangeDecoration(
          documentVersion: active.inputWindow.version,
          startUtf16: crossWindowSelection.start,
          endUtf16: crossWindowSelection.end,
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.34),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (_journalRecoveryNotice != null)
            _buildJournalNoticeBanner(
              key: 'journal-recovery-banner',
              message: _journalRecoveryNotice!,
              onDismiss: () => setState(() => _journalRecoveryNotice = null),
            ),
          if (_journalSaveError != null)
            _buildJournalNoticeBanner(
              key: 'journal-save-error-banner',
              message: _journalSaveError!,
              onDismiss: () => setState(() => _journalSaveError = null),
            ),
          if (active.diskState != DiskDocumentState.current)
            _buildDiskStateBanner(active),
          Expanded(
            child: Stack(
              children: [
                Builder(
                  builder: (editorContext) => Listener(
                    onPointerDown: (event) => _onEditorPointerDown(
                      g,
                      active,
                      editorContext,
                      event,
                    ),
                    onPointerUp: _onEditorPointerUp,
                    onPointerCancel: _onEditorPointerCancel,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: EditorStickyScroll(
                              document: active.doc,
                              inputWindow: active.inputWindow,
                              scrollController: active.editorScrollController,
                              foldedLineRanges: active.foldedLineRanges,
                              enabled: usesRustSyntax &&
                                  active.inputWindow.pendingText == null &&
                                  active.inputWindow.version ==
                                      active.doc.version,
                              onSelectSymbol: (offset) {
                                _flushInput(active, commitComposition: true);
                                _focusNodeFor(g, active).requestFocus();
                                _setDocSelection(
                                  active,
                                  TextSelection.collapsed(offset: offset),
                                );
                              },
                              child: RustTextInputField(
                                key: active.inputFieldKey,
                                inputWindow: active.inputWindow,
                                syntaxTokens: syntaxTokens,
                                syntaxVersion: syntaxVersion,
                                enableCodeFolding: usesRustSyntax,
                                semanticsLabel:
                                    _editorSemanticsLabel(g, active),
                                onFoldRangesChanged:
                                    (documentId, version, ranges) =>
                                        _onEditorFoldRangesChanged(
                                  active,
                                  documentId,
                                  version,
                                  ranges,
                                ),
                                syntaxTokenColor: _tokenColor,
                                rangeDecorations: rangeDecorations,
                                focusNode: _focusNodeFor(g, active),
                                scrollController: active.editorScrollController,
                                inputFormatter:
                                    MultiSelectionTextInputFormatter(
                                  additionalSelections: () =>
                                      _localAdditionalSelections(active),
                                  onSelectionsChanged: (localSelections) {
                                    final inputWindowShift =
                                        active.pendingInputWindowShiftUtf16;
                                    active.additionalSelections =
                                        List.unmodifiable([
                                      ...active.additionalSelections,
                                      for (final selection
                                          in _absoluteSelections(
                                              active, localSelections))
                                        TextSelection(
                                          baseOffset: selection.baseOffset +
                                              inputWindowShift,
                                          extentOffset: selection.extentOffset +
                                              inputWindowShift,
                                          affinity: selection.affinity,
                                          isDirectional:
                                              selection.isDirectional,
                                        ),
                                    ]);
                                    active.pendingInputWindowShiftUtf16 = 0;
                                    active.columnSelection = null;
                                  },
                                  onSelectionChanged: (oldValue, newValue) {
                                    if (!oldValue.selection.isValid ||
                                        oldValue.selection ==
                                            newValue.selection) {
                                      return;
                                    }
                                    active.crossWindowSelection = null;
                                    active.selectionHistory
                                        .record(active.selectionSet);
                                    active.additionalSelections = const [];
                                    active.columnSelection = null;
                                    _scheduleSelectionRefresh(active);
                                    _syncCommandContext();
                                  },
                                  onCrossWindowTextInput:
                                      (oldValue, newValue) =>
                                          _handleCrossWindowTextInput(
                                    active,
                                    oldValue,
                                    newValue,
                                  ),
                                  shouldOvertypeInput: (insertedText) =>
                                      active.consumeOvertypeInput(
                                    insertedText,
                                    enabled: _overtypeMode,
                                  ),
                                  onTextChanged:
                                      (oldValue, newValue, formattedValue) {
                                    active.columnSelection = null;
                                    _prepareRemoteMultiSelectionEdits(
                                      active,
                                      oldValue,
                                      newValue,
                                      formattedValue,
                                    );
                                  },
                                ),
                                additionalOperations: () {
                                  final operations =
                                      active.pendingInputOperations;
                                  active.pendingInputOperations = const [];
                                  return operations;
                                },
                                additionalSelections:
                                    _localAdditionalSelections(active),
                                onDelta: (delta) =>
                                    _onInputDelta(active, delta),
                                onPresentationChanged: () =>
                                    _scheduleSelectionRefresh(active),
                                onAltClick: (localOffset) {
                                  final previous = active.selectionSet;
                                  final offset = active.inputWindow.startUtf16 +
                                      localOffset
                                          .clamp(0,
                                              active.editingValue.text.length)
                                          .toInt();
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted ||
                                        !identical(_active, active)) {
                                      return;
                                    }
                                    _setDocSelections(active, [
                                      ...previous,
                                      TextSelection.collapsed(offset: offset),
                                    ]);
                                  });
                                },
                                onColumnSelectionDrag: (
                                  pointer,
                                  selection, {
                                  required started,
                                }) {
                                  final before =
                                      _pendingColumnSelectionStarts[pointer];
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _applyColumnSelectionDrag(
                                      active,
                                      selection,
                                      started: started,
                                      selectionsBeforeDrag:
                                          before?.view == active
                                              ? before?.selections
                                              : null,
                                    );
                                  });
                                },
                                onCrossWindowLineSelection: (selection) =>
                                    _setCrossWindowLineSelection(
                                  active,
                                  selection,
                                ),
                                onCrossWindowDragSelection: (
                                  selection, {
                                  required started,
                                }) =>
                                    _setCrossWindowDragSelection(
                                  active,
                                  selection,
                                  started: started,
                                ),
                                onError: (error) {
                                  if (!_disposing &&
                                      mounted &&
                                      identical(_active, active)) {
                                    setState(() {
                                      _state = WbSyncState.error;
                                      _statusDetail = '输入同步失败：$error';
                                    });
                                  }
                                },
                                onTap: () {
                                  // 点击编辑器把焦点切到所在组（快捷键/保存/补全路由依据）
                                  final previous = _active;
                                  if (previous != null &&
                                      !identical(previous, active)) {
                                    _flushInput(previous,
                                        commitComposition: true);
                                  }
                                  if (_focusedRegion != g.region) {
                                    setState(() => _focusedRegion = g.region);
                                    _syncCommandContext();
                                  }
                                },
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    height: 1.5),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.all(12),
                                ),
                              ),
                            ),
                          ),
                          if (constraints.maxWidth >= 720) ...[
                            const SizedBox(width: 6),
                            EditorMinimap(
                              inputWindow: active.inputWindow,
                              scrollController: active.editorScrollController,
                              syntaxDocumentId: active.id,
                              syntaxTokens: syntaxTokens,
                              syntaxVersion: syntaxVersion,
                              syntaxEnabled:
                                  active.inputWindow.pendingText == null &&
                                      active.inputWindow.version ==
                                          active.doc.version &&
                                      syntaxVersion == active.doc.version,
                              syntaxTokenColor: _tokenColor,
                              foldedLineRanges: active.foldedLineRanges,
                              overviewMarkers: buildEditorMinimapMarkers(
                                documentId: active.id,
                                documentVersion: active.doc.version,
                                diagnostics: _diagnostics,
                                selectedSearchDocumentId: _selectedSearchDocId,
                                selectedSearchDocumentVersion:
                                    _selectedSearchDocVersion,
                                selectedSearchHit: _selectedSearchHit,
                                findMatchLines: _findOverviewLines,
                                findMatchesDocumentId: _matchesDocId,
                                findMatchesDocumentVersion: _matchesDocVersion,
                                enabled:
                                    active.inputWindow.pendingText == null &&
                                        active.inputWindow.version ==
                                            active.doc.version,
                              ),
                              onNavigateToLine: (line) {
                                _flushInput(active, commitComposition: true);
                                _focusNodeFor(g, active).requestFocus();
                                final offset =
                                    active.doc.lineOffset(line).offsetUtf16;
                                _setDocSelection(
                                  active,
                                  TextSelection.collapsed(offset: offset),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_findVisible)
                  Positioned(top: 0, right: 12, child: _buildFindBar()),
              ],
            ),
          ),
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
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black45)],
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
                        hintText: '查找',
                        isDense: true,
                        border: InputBorder.none),
                    onChanged: (_) => _onFindTextChanged(),
                    onSubmitted: (_) => _gotoMatch(1),
                  ),
                ),
                Text(count,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 11)),
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
                  onPressed: () => _runCommand('editor.find'),
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
            onTap: (index) {
              const commandIds = [
                'view.panelDiagnostics',
                'view.panelCompletions',
                'view.panelSyntax',
              ];
              if (index < commandIds.length) _runCommand(commandIds[index]);
            },
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
    final previewText =
        active.doc.readRange(0, maxLenUtf16: maxPreviewChars).text;
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
class _SelectionEditOffset {
  const _SelectionEditOffset(
    this.start,
    this.deletedLength,
    this.insertedLength,
  );

  final int start;
  final int deletedLength;
  final int insertedLength;
}

class _SharedOpenDocState {
  _SharedOpenDocState({
    required this.id,
    required this.name,
    required this.doc,
    required this.undoStack,
    this.path,
    this.uri,
    this.fileOptions = TextFileOptions.defaults,
    this.savedFileOptions = TextFileOptions.defaults,
    this.dirtyDisk = false,
    this.diskState = DiskDocumentState.current,
    this.conflictBaselineKnown = true,
  }) : autoClosedBracketMarkerVersion = doc.version;

  final int id;
  String? path;
  String? uri;
  String name;
  final AlulaDoc doc;
  final UndoStack undoStack;
  TextFileOptions fileOptions;
  TextFileOptions savedFileOptions;
  bool lspAttached = false;
  bool dirtyDisk;
  DiskDocumentState diskState;
  bool conflictBaselineKnown;
  DateTime? lastEditAt;
  bool undoRedoBusy = false;
  int viewCount = 0;
  bool closed = false;
  final List<_AutoClosedBracketMarker> autoClosedBracketMarkers = [];
  int autoClosedBracketMarkerVersion;

  void remapAutoClosedBracketMarkers(List<TextOp> operations) {
    if (operations.isEmpty) return;
    if (autoClosedBracketMarkerVersion != doc.version - operations.length) {
      autoClosedBracketMarkers.clear();
      autoClosedBracketMarkerVersion = doc.version;
      return;
    }

    final edits = <({int start, int deletedLength, int insertedLength})>[];
    var previousOffset = 0x7fffffffffffffff;
    for (final operation in operations) {
      final start = operation.offsetUtf16;
      if (start > previousOffset) {
        // TextOps normally arrive in descending document order. If a caller
        // supplies a sequential batch instead, discard metadata rather than
        // risk a false overtype after applying an uncertain transform.
        autoClosedBracketMarkers.clear();
        autoClosedBracketMarkerVersion = doc.version;
        return;
      }
      previousOffset = start;
      if (edits.isEmpty || edits.last.start != start) {
        edits.add((start: start, deletedLength: 0, insertedLength: 0));
      }
      final edit = edits.last;
      edits[edits.length - 1] = operation.type == OpType.insert
          ? (
              start: start,
              deletedLength: edit.deletedLength,
              insertedLength:
                  edit.insertedLength + (operation.text?.length ?? 0),
            )
          : (
              start: start,
              deletedLength: edit.deletedLength + (operation.lenUtf16 ?? 0),
              insertedLength: edit.insertedLength,
            );
    }

    final ascendingEdits = edits.reversed.toList(growable: false);
    final deletedRanges = <({int start, int end})>[];
    final rawEvents = <({int threshold, int delta})>[];
    var previousEnd = -1;
    for (final edit in ascendingEdits) {
      if (edit.start < previousEnd) {
        autoClosedBracketMarkers.clear();
        autoClosedBracketMarkerVersion = doc.version;
        return;
      }
      final end = edit.start + edit.deletedLength;
      if (edit.deletedLength > 0) {
        deletedRanges.add((start: edit.start, end: end));
        rawEvents.add((
          threshold: end,
          delta: edit.insertedLength - edit.deletedLength,
        ));
        previousEnd = end;
      } else if (edit.insertedLength > 0) {
        rawEvents.add((threshold: edit.start, delta: edit.insertedLength));
        previousEnd = edit.start;
      }
    }
    rawEvents.sort((a, b) => a.threshold.compareTo(b.threshold));
    final thresholds = <int>[];
    final prefixDeltas = <int>[];
    var runningDelta = 0;
    for (var index = 0; index < rawEvents.length;) {
      final threshold = rawEvents[index].threshold;
      var delta = 0;
      while (
          index < rawEvents.length && rawEvents[index].threshold == threshold) {
        delta += rawEvents[index++].delta;
      }
      runningDelta += delta;
      thresholds.add(threshold);
      prefixDeltas.add(runningDelta);
    }

    int? mapOffset(int offsetUtf16) {
      var low = 0;
      var high = deletedRanges.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (deletedRanges[middle].start <= offsetUtf16) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      if (low > 0 && offsetUtf16 < deletedRanges[low - 1].end) return null;

      low = 0;
      high = thresholds.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (thresholds[middle] <= offsetUtf16) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      final delta = low == 0 ? 0 : prefixDeltas[low - 1];
      return offsetUtf16 + delta;
    }

    autoClosedBracketMarkers.removeWhere((marker) {
      final open = mapOffset(marker.openOffsetUtf16);
      final close = mapOffset(marker.closeOffsetUtf16);
      if (open == null || close == null) return true;
      marker.openOffsetUtf16 = open;
      marker.closeOffsetUtf16 = close;
      return false;
    });
    autoClosedBracketMarkerVersion = doc.version;
  }

  bool hasAutoClosedBracketAt(int offsetUtf16, String close) {
    if (autoClosedBracketMarkerVersion != doc.version) {
      autoClosedBracketMarkers.clear();
      autoClosedBracketMarkerVersion = doc.version;
      return false;
    }
    return autoClosedBracketMarkers.any((marker) =>
        marker.closeOffsetUtf16 == offsetUtf16 && marker.close == close);
  }

  void addAutoClosedBracketMarker({
    required int openOffsetUtf16,
    required int closeOffsetUtf16,
    required String close,
  }) {
    if (autoClosedBracketMarkerVersion != doc.version) {
      autoClosedBracketMarkers.clear();
      autoClosedBracketMarkerVersion = doc.version;
    }
    if (autoClosedBracketMarkers.length >= _maxAutoClosedBracketMarkers) {
      autoClosedBracketMarkers.removeAt(0);
    }
    autoClosedBracketMarkers.add(_AutoClosedBracketMarker(
      openOffsetUtf16: openOffsetUtf16,
      closeOffsetUtf16: closeOffsetUtf16,
      close: close,
    ));
  }

  void consumeAutoClosedBracketAt(int offsetUtf16, String close) {
    autoClosedBracketMarkers.removeWhere((marker) =>
        marker.closeOffsetUtf16 == offsetUtf16 && marker.close == close);
  }

  void retainView() {
    if (closed) throw StateError('Cannot add a view to a closed document');
    viewCount++;
  }

  void releaseView() {
    if (closed || viewCount <= 0) return;
    viewCount--;
    if (viewCount == 0) {
      closed = true;
      autoClosedBracketMarkers.clear();
      doc.close();
      undoStack.dispose();
    }
  }
}

class OpenDoc {
  OpenDoc({
    required int id,
    required String name,
    required AlulaDoc doc,
    String? path,
    String? uri,
    TextFileOptions fileOptions = TextFileOptions.defaults,
    TextFileOptions savedFileOptions = TextFileOptions.defaults,
    bool dirtyDisk = false,
    DiskDocumentState diskState = DiskDocumentState.current,
    bool conflictBaselineKnown = true,
    required UndoHistoryBudget undoBudget,
  })  : _shared = _SharedOpenDocState(
          id: id,
          name: name,
          path: path,
          uri: uri,
          doc: doc,
          fileOptions: fileOptions,
          savedFileOptions: savedFileOptions,
          dirtyDisk: dirtyDisk,
          diskState: diskState,
          conflictBaselineKnown: conflictBaselineKnown,
          undoStack: UndoStack(budget: undoBudget),
        ),
        inputWindow = RustTextInputWindow.openAround(
          doc,
          selectionUtf16: 0,
          maxWindowUtf16: _editorInputWindowUtf16,
          compositionReserveUtf16: _editorCompositionReserveUtf16,
        ),
        inputFieldKey = GlobalKey<RustTextInputFieldState>(),
        editorScrollController = ScrollController() {
    _shared.retainView();
  }

  OpenDoc._viewOf(OpenDoc source)
      : _shared = source._shared,
        inputWindow = RustTextInputWindow.openAround(
          source.doc,
          selectionUtf16: source.selection.extentOffset,
          maxWindowUtf16: _editorInputWindowUtf16,
          compositionReserveUtf16: _editorCompositionReserveUtf16,
          selection: source.selection,
        ),
        inputFieldKey = GlobalKey<RustTextInputFieldState>(),
        editorScrollController = ScrollController(),
        additionalSelections = List.unmodifiable(source.additionalSelections),
        foldedLineRanges = List.unmodifiable(source.foldedLineRanges) {
    _shared.retainView();
  }

  factory OpenDoc.viewOf(OpenDoc source) => OpenDoc._viewOf(source);

  final _SharedOpenDocState _shared;
  int get id => _shared.id;
  String? get path => _shared.path;
  set path(String? value) => _shared.path = value;
  String? get uri => _shared.uri;
  set uri(String? value) => _shared.uri = value;
  String get name => _shared.name;
  set name(String value) => _shared.name = value;
  AlulaDoc get doc => _shared.doc;
  TextFileOptions get fileOptions => _shared.fileOptions;
  set fileOptions(TextFileOptions value) => _shared.fileOptions = value;
  TextFileOptions get savedFileOptions => _shared.savedFileOptions;
  set savedFileOptions(TextFileOptions value) =>
      _shared.savedFileOptions = value;
  bool get lspAttached => _shared.lspAttached;
  set lspAttached(bool value) => _shared.lspAttached = value;
  bool get dirtyDisk => _shared.dirtyDisk;
  set dirtyDisk(bool value) => _shared.dirtyDisk = value;
  DiskDocumentState get diskState => _shared.diskState;
  set diskState(DiskDocumentState value) => _shared.diskState = value;
  bool get conflictBaselineKnown => _shared.conflictBaselineKnown;
  set conflictBaselineKnown(bool value) =>
      _shared.conflictBaselineKnown = value;
  DateTime? get lastEditAt => _shared.lastEditAt;
  set lastEditAt(DateTime? value) => _shared.lastEditAt = value;
  bool get undoRedoBusy => _shared.undoRedoBusy;
  set undoRedoBusy(bool value) => _shared.undoRedoBusy = value;
  UndoStack get undoStack => _shared.undoStack;
  int get sharedViewCount => _shared.viewCount;
  bool get sharesDocument => !_shared.closed;

  void remapAutoClosedBracketMarkers(List<TextOp> operations) =>
      _shared.remapAutoClosedBracketMarkers(operations);

  bool hasAutoClosedBracketAt(int offsetUtf16, String close) =>
      _shared.hasAutoClosedBracketAt(offsetUtf16, close);

  void addAutoClosedBracketMarker({
    required int openOffsetUtf16,
    required int closeOffsetUtf16,
    required String close,
  }) =>
      _shared.addAutoClosedBracketMarker(
        openOffsetUtf16: openOffsetUtf16,
        closeOffsetUtf16: closeOffsetUtf16,
        close: close,
      );

  void consumeAutoClosedBracketAt(int offsetUtf16, String close) =>
      _shared.consumeAutoClosedBracketAt(offsetUtf16, close);

  RustTextInputWindow inputWindow;
  List<EditorDocumentLineRange> foldedLineRanges = const [];
  final GlobalKey<RustTextInputFieldState> inputFieldKey;
  final ScrollController editorScrollController;
  final SelectionHistory selectionHistory = SelectionHistory();
  List<TextSelection> additionalSelections = const [];
  List<TextOp> pendingInputOperations = const [];
  int pendingInputWindowShiftUtf16 = 0;
  ColumnSelectionState? columnSelection;
  TextSelection? crossWindowSelection;
  String? _pendingOvertypeCharacter;
  DateTime? _pendingOvertypeAt;
  bool _viewDisposed = false;

  void expectOvertypeInput(String character) {
    _pendingOvertypeCharacter = character;
    _pendingOvertypeAt = DateTime.now();
  }

  void clearPendingOvertypeInput() {
    _pendingOvertypeCharacter = null;
    _pendingOvertypeAt = null;
  }

  bool consumeOvertypeInput(String insertedText, {required bool enabled}) {
    final pending = _pendingOvertypeCharacter;
    final recordedAt = _pendingOvertypeAt;
    clearPendingOvertypeInput();
    return enabled &&
        pending == insertedText &&
        recordedAt != null &&
        DateTime.now().difference(recordedAt) <= const Duration(seconds: 2);
  }

  /// Current Flutter value is bounded by [inputWindow.maxWindowUtf16].
  TextEditingValue get editingValue =>
      inputFieldKey.currentState?.editingValue ?? inputWindow.initialValue;

  /// Current selection converted from the input-window-local UTF-16 offsets.
  TextSelection get selection {
    final crossWindow = crossWindowSelection;
    if (crossWindow != null) return crossWindow;
    final local = editingValue.selection;
    if (!local.isValid) {
      return TextSelection.collapsed(offset: inputWindow.startUtf16);
    }
    return TextSelection(
      baseOffset: (inputWindow.startUtf16 + local.baseOffset)
          .clamp(0, inputWindow.totalUtf16Length)
          .toInt(),
      extentOffset: (inputWindow.startUtf16 + local.extentOffset)
          .clamp(0, inputWindow.totalUtf16Length)
          .toInt(),
      affinity: local.affinity,
      isDirectional: local.isDirectional,
    );
  }

  List<TextSelection> get selectionSet {
    final window = inputWindow;
    return normalizeSelectionSet([
      selection,
      ...additionalSelections.where((item) =>
          item.baseOffset >= window.startUtf16 &&
          item.baseOffset <= window.endUtf16 &&
          item.extentOffset >= window.startUtf16 &&
          item.extentOffset <= window.endUtf16),
    ]);
  }

  String get text => doc.resync().content;

  void replaceInputWindow(int selectionUtf16, {TextSelection? selection}) {
    final total = doc.readRange(0, maxLenUtf16: 2).totalUtf16Length;
    final clampedSelection = TextSelection(
      baseOffset:
          (selection?.baseOffset ?? selectionUtf16).clamp(0, total).toInt(),
      extentOffset:
          (selection?.extentOffset ?? selectionUtf16).clamp(0, total).toInt(),
      affinity: selection?.affinity ?? TextAffinity.downstream,
      isDirectional: selection?.isDirectional ?? false,
    );
    inputWindow = RustTextInputWindow.openAround(
      doc,
      selectionUtf16: clampedSelection.extentOffset,
      maxWindowUtf16: _editorInputWindowUtf16,
      compositionReserveUtf16: _editorCompositionReserveUtf16,
      selection: clampedSelection,
    );
  }

  void refreshInputWindowInPlace(int selectionUtf16) {
    inputWindow.refreshAround(
      selectionUtf16,
      selection: TextSelection.collapsed(offset: selectionUtf16),
    );
  }

  bool get isDirty => dirtyDisk;
  bool get isUntitled => path == null;

  bool sameDocumentAs(OpenDoc other) => identical(_shared, other._shared);

  void disposeView() {
    if (_viewDisposed) return;
    _viewDisposed = true;
    editorScrollController.dispose();
    _shared.releaseView();
  }
}

enum DiskDocumentState { current, conflict, missing, readOnly, unavailable }

enum _ConflictSaveAction { cancel, saveAs, overwrite }

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
