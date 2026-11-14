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
import 'package:flutter/rendering.dart' show RenderBox, RenderEditable;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../bridge/alula_core.dart';
import '../editor/bulk_edit_preview_surface.dart';
import '../editor/editor_minimap.dart';
import '../editor/snapshot_compare_preview.dart';
import '../editor/diff_view_model.dart';
import '../editor/diff_revert_plan.dart';
import '../editor/editor_minimap_markers.dart';
import '../editor/editor_sticky_scroll.dart';
import '../editor/editor_folding.dart';
import '../editor/editor_rendering.dart';
import '../editor/editor_highlight_tokens.dart';
import '../editor/indentation.dart';
import '../editor/find_replace.dart';
import '../editor/find_replace_history.dart';
import '../editor/merge_result_session.dart';
import '../editor/merge_editor_surface.dart';
import '../editor/merge_editor_open_request.dart';
import '../editor/clipboard_metadata.dart';
import '../editor/editor_clipboard.dart';
import '../editor/text_drag_drop.dart';
import '../editor/lsp_diagnostic_decorations.dart';
import '../editor/navigation_history.dart';
import '../editor/multi_selection.dart';
import '../editor/occurrence_search.dart';
import '../editor/paste_as.dart';
import '../editor/rich_text_clipboard.dart';
import '../editor/rust_text_input_field.dart';
import '../editor/rust_string_context.dart';
import '../editor/rust_text_input_window.dart';
import '../editor/snippet_session.dart';
import '../editor/snippet_choice_suggestion_list.dart';
import '../editor/snippet_template.dart';
import '../editor/snippet_variable_transform.dart';
import '../editor/text_diff.dart';
import '../editor/undo_stack.dart';
import '../editor/workspace_edit.dart';
import '../editor/workspace_search_decorations.dart';
import '../git/git_cli.dart';
import '../git/git_diff_commands.dart';
import '../git/git_diff_navigation.dart';
import '../git/git_diff_patch_view.dart';
import '../search/search_service.dart';
import '../workspace/workspace_watcher.dart';
import 'activity_bar.dart';
import 'activity_bar_badges.dart';
import 'activity_bar_global_actions.dart';
import 'activity_bar_order.dart';
import 'activity_bar_pins.dart';
import 'activity_bar_position.dart';
import 'activity_bar_size.dart';
import 'commands.dart';
import 'editor_tab_action_location.dart';
import 'editor_tab_close_policy.dart';
import 'editor_tab_close_action.dart';
import 'editor_tab_file_icon.dart';
import 'editor_tab_label.dart';
import 'editor_tab_mode.dart';
import 'editor_tab_sizing.dart';
import 'find_history_store.dart';
import 'layout_controller.dart';
import 'layout_grid.dart';
import 'keybindings.dart';
import 'layout_model.dart';
import 'layout_store.dart';
import 'panel_alignment.dart';
import 'panel_maximize.dart';
import 'panel_position.dart';
import 'quick_input.dart';
import 'secondary_sidebar_empty_state.dart';
import 'secondary_sidebar_layout.dart';
import 'sidebar_position.dart';
import 'sidebar_view_locations.dart';
import 'session_store.dart';
import 'status_bar.dart';
import 'title_bar.dart';
import 'workbench_window_title.dart';
import 'auxiliary_window.dart';
import 'modal_editor.dart';

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
const int _maxSnippetInsertionSelections = 64;
const int _maxSnippetInsertionPlaceholderOccurrences = 4096;
const Duration _snippetMultiCursorExpansionTimeout = Duration(seconds: 8);

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

class _SnippetInsertionPlan {
  _SnippetInsertionPlan({
    required this.startUtf16,
    required this.endUtf16,
    required this.removedText,
    required this.expansion,
    required this.lineLeadingWhitespace,
  });

  final int startUtf16;
  final int endUtf16;
  final String removedText;
  final SnippetExpansion expansion;
  final String lineLeadingWhitespace;
  late int mappedStartUtf16;
}

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

class _PasteAsSession {
  const _PasteAsSession({
    required this.documentId,
    required this.version,
    required this.payload,
    required this.beforeSelections,
    required this.afterSelections,
    required this.providerId,
    required this.wasCrossWindow,
  });

  final int documentId;
  final int version;
  final EditorPasteAsPayload payload;
  final List<TextSelection> beforeSelections;
  final List<TextSelection> afterSelections;
  final String providerId;
  final bool wasCrossWindow;
}

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
    this.savedCompareFileStat,
    this.overtypeOnPaste = true,
    this.pasteAsConfiguration = const PasteAsConfiguration(),
    this.findReplaceHistoryConfiguration =
        const FindReplaceHistoryConfiguration(),
    this.findReplaceHistoryStore,
    this.mergeResultSessionFactory,
    this.onCommandServiceReady,
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

  /// Optional file-stat provider for deterministic saved-compare fixtures.
  final Future<FileStat> Function(String path)? savedCompareFileStat;

  /// Mirrors VS Code's editor.overtypeOnPaste default. User settings will be
  /// wired into this editor option when P07 adds the settings store.
  final bool overtypeOnPaste;

  /// Editor Paste As behavior. The settings store can hydrate this value when
  /// the settings surface lands; command and keybinding behavior is available
  /// independently of that UI.
  final PasteAsConfiguration pasteAsConfiguration;

  /// Find/replace history options are hydrated by the settings store in P07.
  final FindReplaceHistoryConfiguration findReplaceHistoryConfiguration;

  /// Optional per-workspace history store (tests can use a temporary folder).
  final FindReplaceHistoryStore? findReplaceHistoryStore;

  /// Optional integration point for a merge-result owner. The workbench keeps
  /// the returned session with the shared Rust document and consumes its save
  /// and close decisions. Git conflict discovery and merge UI are separate.
  final MergeResultSession? Function(
    AlulaCore core,
    OpenDoc resultDocument,
    bool Function(MergeResultEditPlan plan) applyPlan,
  )? mergeResultSessionFactory;

  /// Host integration hook invoked after Workbench commands are registered.
  /// The service remains owned and disposed by this Workbench.
  final void Function(CommandService commands)? onCommandServiceReady;

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

enum _EditorGroupMoveDirection {
  left(Axis.horizontal, true),
  right(Axis.horizontal, false),
  up(Axis.vertical, true),
  down(Axis.vertical, false);

  const _EditorGroupMoveDirection(this.axis, this.insertBefore);

  final Axis axis;
  final bool insertBefore;
}

class _EditorGroupBounds {
  const _EditorGroupBounds(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

class _WorkbenchPageState extends State<WorkbenchPage>
    with SingleTickerProviderStateMixin {
  static const _untitledId = 1;
  static const _findBarInitialWidth = 419.0;
  static const _maxExplorerCompareUtf16 = 2000000;
  static const _maxExplorerCompareDiskBytes = 6000016;
  static const _selectForCompareCommandId = 'selectForCompare';
  static const _compareFilesCommandId = 'compareFiles';
  static const _compareSelectedExplorerFilesAction = 'explorer.compareSelected';
  static const _explorerDoubleClickTimeout = Duration(milliseconds: 500);

  AlulaCore? _core;
  String _loadError = '';
  int _nextDocId = 2;

  /// 工作台布局（分割树）。启动时尝试从磁盘恢复（W1-4）。
  WorkbenchLayout _layout = WorkbenchLayout();
  final CommandService _commands = CommandService();
  final ValueNotifier<EditorTabMode> _editorTabMode =
      ValueNotifier(EditorTabMode.multiple);
  final ValueNotifier<EditorTabSizing> _editorTabSizing =
      ValueNotifier(EditorTabSizing.fit);
  final ValueNotifier<EditorTabActionLocation> _editorTabActionLocation =
      ValueNotifier(EditorTabActionLocation.right);
  final ValueNotifier<bool> _editorTabCloseActionVisibility =
      ValueNotifier(true);
  final ValueNotifier<bool> _editorTabActionReserveSpace = ValueNotifier(true);
  final ValueNotifier<bool> _pinnedTabsOnSeparateRow = ValueNotifier(false);
  final ValueNotifier<({String region, int docId})?> _editorTabHoveredTarget =
      ValueNotifier(null);
  // 标签拖动开始时记录源组 region；文档 id 可被多组共享，无法在 drop 时消歧。
  String? _tabDragSourceRegion;
  final Set<String> _editorTabPointerInside = <String>{};
  final Map<String, Map<int, double>> _editorTabLastWidths = {};
  final Map<String, Map<int, double>> _editorTabHeldWidths = {};
  final ValueNotifier<bool> _editorTabWrap = ValueNotifier(false);
  final GitDiffPatchNavigationController _gitDiffNavigation =
      GitDiffPatchNavigationController();

  /// 键位集合（默认表 + 用户 keybindings.json 覆盖，docs/09 W3-2）。
  late final KeybindingSet _keybindings;
  List<String>? _fileIndexCache; // 快速打开的文件索引（打开文件夹时失效）
  Timer? _stateSaveTimer;
  Timer? _findHistoryTimer;
  Timer? _resourceTimer;
  String? _lastExplorerClickPath;
  Stopwatch? _lastExplorerClickClock;
  String? _pendingExplorerPreviewPinPath;
  final Map<String, int> _explorerPreviewOpenCounts = <String, int>{};
  AlulaResourceStatus? _resourceStatus;

  // ---------- 撤销/重做（每文档独立，共享有界历史预算） ----------
  final UndoHistoryBudget _undoHistoryBudget = UndoHistoryBudget();
  final NavigationHistory _navigationHistory = NavigationHistory();
  final Set<int> _appliedLocalEditorTextDragTokens = <int>{};
  final Set<int> _rejectedCrossDocumentMoveTokens = <int>{};
  final Set<int> _mergeCloseInProgress = <int>{};
  final Set<int> _mergeAcceptInProgress = <int>{};
  final Set<Object> _editorCloseInProgress = <Object>{};

  // ---------- 查找/替换 ----------
  bool _findVisible = false;
  bool _replaceVisible = false;
  double _findBarWidth = _findBarInitialWidth;
  double _findQueryInputWidth = 0;
  bool _findQueryWidthUpdateScheduled = false;
  late final FindReplaceHistoryStore _findHistoryStore =
      widget.findReplaceHistoryStore ??
      FindReplaceHistoryStore(
        directory: '${widget.sessionStore.resolvePath()}.find-history',
      );
  final FindReplaceHistoryNavigator _findHistory =
      FindReplaceHistoryNavigator();
  final FindReplaceHistoryNavigator _replaceHistory =
      FindReplaceHistoryNavigator();
  String? _findHistoryWorkspaceIdentity;

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
  String? _sidebarView = 'explorer';
  String? _secondarySidebarView;
  String? _focusedSidebarView = 'explorer';
  // Open Editors 区段折叠态（上游 openEditorsView 的可见性/展开持久化）。
  bool _openEditorsCollapsed = false;
  final Map<String, FocusNode> _openEditorsRowFocus = {};
  // LAY-12a：本进程创建的辅助窗口 id（关闭恢复入口用）。
  final Set<String> _auxiliaryWindowIds = {};
  // LAY-13a：当前模态编辑器的脱离视图（不在任何组内）。
  OpenDoc? _modalEditorDoc;
  ModalEditorUseMode _modalEditorUseMode = ModalEditorUseMode.some;
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
  Completer<void>? _findReplaceWorkerCancellation;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _preserveCase = false;
  bool _regexFind = false;
  bool _findInSelection = false;
  List<TextMatchScope> _findSelectionScopes = const [];
  int _findScopeDocId = -1;
  int _findScopeDocVersion = -1;
  bool _findPending = false;
  bool _findMatchesTruncated = false;
  String? _findError;
  int _findGeneration = 0;
  Completer<void>? _findWorkerCancellation;
  Future<void> _pendingFind = Future<void>.value();

  String? _workspaceRoot;
  final List<TreeNode> _treeRoots = [];
  final List<String> _explorerMultiSelection = [];
  String? _explorerSelectionAnchor;
  _ExplorerCompareSelection? _explorerCompareSelection;

  /// 编辑器组（W2-2）：region → 组；焦点组承载快捷键/保存/补全/新开文档。
  final Map<String, EditorGroup> _groups = {};
  int _editorActivationClock = 0;
  final Map<OpenDoc, _SnapshotCompareBinding> _snapshotCompareViews = {};
  final Map<int,
      ({EditorGroup group, OpenDoc view, int offset, Offset position})>
      _pendingDefinitionPointers = {};
  final Map<int, ({OpenDoc view, List<TextSelection> selections})>
      _pendingColumnSelectionStarts = {};
  String _focusedRegion = 'editor';
  int _syncCount = 0;
  int _abiVersion = 0;

  WbSyncState _state = WbSyncState.idle;
  bool _overtypeMode = false;
  bool _pasteSelectorOpen = false;
  _PasteAsSession? _lastPasteAsSession;
  SnippetSession? _snippetSession;
  int? _snippetSessionDocId;
  OpenDoc? _snippetSessionView;
  SnippetSession? _snippetChoiceUiSession;
  int? _snippetChoiceUiTabstop;
  int _snippetChoiceSelectedIndex = 0;
  bool _snippetChoiceDismissed = false;
  bool _snippetNavigationPending = false;
  int _snippetNavigationEpoch = 0;
  List<TextOp>? _pendingSnippetOperations;
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
    // LAY-12a：辅助窗口关闭恢复入口（主窗自身窗口通道）。
    unawaited(_setupAuxiliaryWindowHandlers());
    final saved = widget.layoutStore.tryLoad();
    if (saved != null) {
      _layout = WorkbenchLayout(root: saved);
    }
    _sidebarView = _layout.primarySidebarView;
    _secondarySidebarView = _layout.secondarySidebarView;
    _focusedSidebarView = _sidebarView ?? _secondarySidebarView;
    _layout.addListener(_scheduleStateSave);
    _layout.addListener(_syncPanelMaximizationCommandContext);
    _keybindings =
        KeybindingSet.load(userJson: widget.keybindingsStore.tryLoadText());
    _registerCommands();
    _panelTab.addListener(_syncCommandContext);
    _ensureGroupsFromLayout(); // 保存的布局可能含多个编辑器组
    if (!_groups.containsKey('editor')) {
      _groups['editor'] = EditorGroup('editor');
    }
    _initCore();
    _syncCommandContext();
    _commands.addListener(_onCommandServiceChanged);
    widget.onCommandServiceReady?.call(_commands);
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

    reg(
      'workbench.action.files.newUntitledFile',
      '文件',
      '新建文本文件',
      _newUntitledFile,
      shortcut: _keybindings.shortcutFor(
        'workbench.action.files.newUntitledFile',
      ),
    );
    reg('file.openFolder', '文件', '打开文件夹…', _showOpenFolderDialog);
    reg(
      '_open.mergeEditor',
      'Merge Editor',
      'Open Merge Editor',
      _openMergeEditorWithoutArguments,
      when: 'workspaceOpen',
      enablement: 'workspaceOpen',
      runWithArguments: _openMergeEditorFromArguments,
    );
    reg(
      'merge.goToNextUnhandledConflict',
      'Merge Editor',
      'Go to Next Unhandled Conflict',
      () async => _navigateMergeConflict(_active, forward: true),
      when: 'mergeEditorActive',
      enablement: 'mergeUnhandledConflictAvailable',
    );
    reg(
      'merge.goToPreviousUnhandledConflict',
      'Merge Editor',
      'Go to Previous Unhandled Conflict',
      () async => _navigateMergeConflict(_active, forward: false),
      when: 'mergeEditorActive',
      enablement: 'mergeUnhandledConflictAvailable',
    );
    reg(
      'merge.toggleActiveConflictInput1',
      'Merge Editor',
      'Toggle Current Conflict from Left',
      () async => _acceptActiveMergeConflict(AlulaMergeSide.input1),
      when: 'mergeEditorActive',
      enablement: 'mergeCurrentConflictAvailable',
    );
    reg(
      'merge.toggleActiveConflictInput2',
      'Merge Editor',
      'Toggle Current Conflict from Right',
      () async => _acceptActiveMergeConflict(AlulaMergeSide.input2),
      when: 'mergeEditorActive',
      enablement: 'mergeCurrentConflictAvailable',
    );
    reg(
      'merge.acceptAllInput1',
      'Merge Editor',
      'Accept All Incoming Changes from Left',
      () async => _acceptAllActiveMergeConflicts(AlulaMergeSide.input1),
      when: 'mergeEditorActive',
      enablement: 'mergeAllConflictsAvailable',
    );
    reg(
      'merge.acceptAllInput2',
      'Merge Editor',
      'Accept All Current Changes from Right',
      () async => _acceptAllActiveMergeConflicts(AlulaMergeSide.input2),
      when: 'mergeEditorActive',
      enablement: 'mergeAllConflictsAvailable',
    );
    reg(
      'mergeEditor.acceptAllCombination',
      'Merge Editor',
      'Accept All Combination',
      () async => _acceptAllActiveMergeCombinations(),
      when: 'mergeEditorActive',
      enablement: 'mergeAllConflictsAvailable',
    );
    reg(
      'mergeEditor.acceptMerge',
      'Merge Editor',
      'Complete Merge',
      () async => _acceptActiveMergeResult(),
      shortcut: _keybindings.shortcutFor('mergeEditor.acceptMerge'),
      when: 'mergeEditorActive',
      enablement: 'mergeEditorActive',
    );
    reg('file.save', '文件', '保存', _saveActive,
        shortcut: 'Ctrl+S', when: 'editorActive', enablement: 'editorActive');
    reg(
      'workbench.action.pinEditor',
      '编辑器',
      '固定编辑器',
      () async => _setActiveEditorSticky(true),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.unpinEditor',
      '编辑器',
      '取消固定编辑器',
      () async => _setActiveEditorSticky(false),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.toggleEditorSticky',
      '编辑器',
      '切换编辑器固定状态',
      () async => _toggleActiveEditorSticky(),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.toggleEditorSticky',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeActiveEditor',
      '编辑器',
      '关闭活动编辑器',
      () async => _closeActiveEditorFromKeyboard(),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeActiveEditor',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeOtherEditors',
      '编辑器',
      '关闭其他编辑器',
      () => _closeFromActiveEditor(EditorTabCloseOperation.closeOthers),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeOtherEditors',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeEditorsToTheLeft',
      '编辑器',
      '关闭左侧编辑器',
      () => _closeFromActiveEditor(EditorTabCloseOperation.closeToLeft),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeEditorsToTheLeft',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeEditorsToTheRight',
      '编辑器',
      '关闭右侧编辑器',
      () => _closeFromActiveEditor(EditorTabCloseOperation.closeToRight),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeEditorsToTheRight',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeUnmodifiedEditors',
      '编辑器',
      '关闭已保存的编辑器',
      () => _closeFromActiveEditor(EditorTabCloseOperation.closeSaved),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeUnmodifiedEditors',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeAllEditors',
      '编辑器',
      '关闭所有编辑器（保留固定项）',
      () async => _closeAllEditorsInFocusedGroup(),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeAllEditors',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.action.closeAllGroups',
      '编辑器',
      '关闭所有编辑器组',
      () async => _closeAllEditorGroups(),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.closeAllGroups',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg('file.saveAs', '文件', '另存为…', _saveAsActive,
        shortcut: 'Ctrl+Shift+S', when: 'editorActive', enablement: 'editorActive');
    reg(
      'workbench.files.action.compareWithSaved',
      '文件',
      '比较活动文件与已保存版本',
      _compareActiveFileWithSaved,
      shortcut: _keybindings.shortcutFor(
        'workbench.files.action.compareWithSaved',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      'workbench.files.action.compareWithClipboard',
      '文件',
      '比较活动文件与剪贴板',
      _compareActiveFileWithClipboard,
      shortcut: _keybindings.shortcutFor(
        'workbench.files.action.compareWithClipboard',
      ),
      when: 'editorActive',
      enablement: 'editorActive',
    );
    reg(
      _selectForCompareCommandId,
      '文件',
      'Select for Compare',
      () => _selectExplorerFileForCompare(null),
      when: 'workspaceOpen',
      enablement: 'workspaceOpen',
      runWithArguments: _selectExplorerFileForCompare,
    );
    reg(
      _compareFilesCommandId,
      '文件',
      'Compare with Selected',
      () => _compareSelectedExplorerFile(null),
      when: 'workspaceOpen',
      enablement: 'workspaceOpen',
      runWithArguments: _compareSelectedExplorerFile,
    );
    reg(
      'diffEditor.revert',
      '差异编辑器',
      'Revert',
      _revertFocusedSnapshotCompare,
      when: 'diffEditorActive',
      enablement: 'diffEditorActive',
    );
    reg('file.revert', '文件', '从磁盘还原', _revertActive,
        when: 'editorHasPath', enablement: 'editorActive');
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
    reg(
      'workbench.action.moveView',
      '查看',
      '移动视图…',
      _showMoveSidebarViewPicker,
    );
    reg(
      'workbench.action.moveFocusedView',
      '查看',
      '移动聚焦的视图…',
      _showMoveFocusedSidebarViewPicker,
    );
    reg(
      'workbench.action.resetViewLocations',
      '查看',
      '重置视图位置',
      _resetSidebarViewLocations,
    );
    reg('view.toggleSidebar', '查看', '切换侧栏',
        () async => _layout.toggleRegion('sidebar'),
        shortcut: 'Ctrl+B');
    _registerToggleSideBarPositionCommand();
    reg(
      'workbench.action.toggleAuxiliaryBar',
      '查看',
      '切换次侧栏',
      () async => _layout.toggleRegion(secondarySidebarRegion),
      shortcut: _keybindings.shortcutFor(
        'workbench.action.toggleAuxiliaryBar',
      ),
    );
    reg('view.togglePanel', '查看', '切换面板',
        () async => _layout.toggleRegion('panel'),
        shortcut:
            defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+J' : 'Ctrl+J');
    reg(
      'workbench.action.toggleMaximizedPanel',
      '查看',
      '切换面板最大化',
      () async {
        _layout.togglePanelMaximization();
      },
      when: 'panelMaximizationSupported',
    );
    reg(
      'workbench.action.positionPanelTop',
      '查看',
      '将面板移到顶部',
      () async {
        _layout.setPanelPosition(PanelPosition.top);
      },
    );
    reg(
      'workbench.action.positionPanelBottom',
      '查看',
      '将面板移到底部',
      () async {
        _layout.setPanelPosition(PanelPosition.bottom);
      },
    );
    reg(
      'workbench.action.positionPanelLeft',
      '查看',
      '将面板移到左侧',
      () async {
        _layout.setPanelPosition(PanelPosition.left);
      },
    );
    reg(
      'workbench.action.positionPanelRight',
      '查看',
      '将面板移到右侧',
      () async {
        _layout.setPanelPosition(PanelPosition.right);
      },
    );
    reg(
      'workbench.action.alignPanelLeft',
      '查看',
      '将面板对齐到左侧',
      () async => _layout.setPanelAlignment(PanelAlignment.left),
    );
    reg(
      'workbench.action.alignPanelRight',
      '查看',
      '将面板对齐到右侧',
      () async => _layout.setPanelAlignment(PanelAlignment.right),
    );
    reg(
      'workbench.action.alignPanelCenter',
      '查看',
      '将面板对齐到居中',
      () async => _layout.setPanelAlignment(PanelAlignment.center),
    );
    reg(
      'workbench.action.alignPanelJustify',
      '查看',
      '将面板对齐到两端',
      () async => _layout.setPanelAlignment(PanelAlignment.justify),
    );
    reg(
      'workbench.action.activityBarLocation.default',
      '查看',
      '将活动栏移到侧边',
      () async {
        _setActivityBarLocation(ActivityBarLocation.side);
      },
    );
    reg(
      'workbench.action.activityBarLocation.top',
      '查看',
      '将活动栏移到顶部',
      () async {
        _setActivityBarLocation(ActivityBarLocation.top);
      },
    );
    reg(
      'workbench.action.activityBarLocation.bottom',
      '查看',
      '将活动栏移到底部',
      () async {
        _setActivityBarLocation(ActivityBarLocation.bottom);
      },
    );
    reg(
      'workbench.action.activityBarLocation.hide',
      '查看',
      '隐藏活动栏',
      () async {
        _setActivityBarLocation(ActivityBarLocation.hidden);
      },
    );
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
      'editor.action.pasteAs',
      '编辑器',
      '粘贴为…',
      () => _pasteAs(),
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Cmd+Shift+V'
          : 'Ctrl+Shift+V',
      enablement: 'editorTextFocus',
      runWithArguments: (arguments) =>
          _pasteAs(providerId: _pasteAsProviderId(arguments)),
    );
    reg(
      'editor.action.pasteAsText',
      '编辑器',
      '粘贴为纯文本',
      _pasteAsText,
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.insertSnippet',
      '编辑器',
      '插入片段…',
      _showInsertSnippetDialog,
      enablement: 'editorTextFocus',
      runWithArguments: _insertSnippetFromArguments,
    );
    reg(
      'editor.changePasteType',
      '编辑器',
      '更改粘贴类型…',
      _changePasteType,
      enablement: 'editorTextFocus',
      runWithArguments: (arguments) =>
          _changePasteType(providerId: _pasteAsProviderId(arguments)),
    );
    reg(
      'editor.hidePasteWidget',
      '编辑器',
      '隐藏粘贴选项',
      _hidePasteWidget,
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
    reg(
      'workbench.action.splitEditorLeft',
      '编辑器',
      '向左拆分编辑器',
      () async => _splitFocusedGroup(axis: Axis.horizontal, insertBefore: true),
    );
    reg(
      'workbench.action.splitEditorRight',
      '编辑器',
      '向右拆分编辑器',
      () async => _splitFocusedGroup(axis: Axis.horizontal),
    );
    reg(
      'workbench.action.splitEditorUp',
      '编辑器',
      '向上拆分编辑器',
      () async => _splitFocusedGroup(axis: Axis.vertical, insertBefore: true),
    );
    reg(
      'workbench.action.splitEditorDown',
      '编辑器',
      '向下拆分编辑器',
      () async => _splitFocusedGroup(axis: Axis.vertical),
    );
    reg(
      'workbench.action.moveEditorToLeftGroup',
      '编辑器',
      '将活动编辑器移至左侧组',
      () async => _moveFocusedEditorToGroup(_EditorGroupMoveDirection.left),
    );
    reg(
      'workbench.action.moveEditorToRightGroup',
      '编辑器',
      '将活动编辑器移至右侧组',
      () async => _moveFocusedEditorToGroup(_EditorGroupMoveDirection.right),
    );
    reg(
      'workbench.action.moveEditorToAboveGroup',
      '编辑器',
      '将活动编辑器移至上方组',
      () async => _moveFocusedEditorToGroup(_EditorGroupMoveDirection.up),
    );
    reg(
      'workbench.action.moveEditorToBelowGroup',
      '编辑器',
      '将活动编辑器移至下方组',
      () async => _moveFocusedEditorToGroup(_EditorGroupMoveDirection.down),
    );
    reg(
      'workbench.action.moveEditorToNewWindow',
      '编辑器',
      '在新窗口打开活动编辑器',
      () async => _moveFocusedEditorToNewWindow(),
    );
    // Existing toolbar command remains the default right-split action.
    reg(
      'editor.split',
      '编辑器',
      '拆分编辑器',
      () async => _splitFocusedGroup(axis: Axis.horizontal),
    );
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
    reg(
      'workbench.action.editorTabs.multiple',
      '查看',
      '显示多个编辑器标签',
      () async => _setEditorTabMode(EditorTabMode.multiple),
    );
    reg(
      'workbench.action.editorTabs.single',
      '查看',
      '仅显示活动编辑器标签',
      () async => _setEditorTabMode(EditorTabMode.single),
    );
    reg(
      'workbench.action.editorTabs.none',
      '查看',
      '隐藏编辑器标签',
      () async => _setEditorTabMode(EditorTabMode.none),
    );
    reg(
      'workbench.action.toggleEditorTabWrapping',
      '查看',
      '切换编辑器标签换行',
      () async => _setEditorTabWrap(!_editorTabWrap.value),
    );
    reg(
      'workbench.action.toggleEditorPinnedTabsSeparateRow',
      '查看',
      '切换固定编辑器标签单独成行',
      () async => _setPinnedTabsOnSeparateRow(!_pinnedTabsOnSeparateRow.value),
    );
    reg(
      'workbench.action.toggleEditorTabCloseActionVisibility',
      '查看',
      '显示关闭操作',
      () async => _setEditorTabCloseActionVisibility(
        !_editorTabCloseActionVisibility.value,
      ),
    );
    reg(
      'workbench.action.toggleEditorTabActionReserveSpace',
      '查看',
      '为关闭操作保留空间',
      () async => _setEditorTabActionReserveSpace(
        !_editorTabActionReserveSpace.value,
      ),
    );
    for (final sizing in EditorTabSizing.values) {
      reg(
        'workbench.action.editorTabs.sizing.${sizing.name}',
        '查看',
        switch (sizing) {
          EditorTabSizing.fit => '按内容适配编辑器标签宽度',
          EditorTabSizing.shrink => '收缩编辑器标签宽度',
          EditorTabSizing.fixed => '固定编辑器标签宽度',
        },
        () async => _setEditorTabSizing(sizing),
      );
    }
    for (final location in EditorTabActionLocation.values) {
      reg(
        'workbench.action.editorTabs.actionLocation.${location.name}',
        '查看',
        switch (location) {
          EditorTabActionLocation.left => '将关闭操作移到编辑器标签左侧',
          EditorTabActionLocation.right => '将关闭操作移到编辑器标签右侧',
        },
        () async => _setEditorTabActionLocation(location),
      );
    }
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
    reg(
      'editor.action.trimTrailingWhitespace',
      '编辑器',
      '修剪尾随空格',
      _trimTrailingWhitespace,
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? 'Cmd+K Cmd+X'
          : 'Ctrl+K Ctrl+X',
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.indentationToSpaces',
      '编辑器',
      '将缩进转换为空格',
      () => _convertIndentation(insertSpaces: true),
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.indentationToTabs',
      '编辑器',
      '将缩进转换为制表符',
      () => _convertIndentation(insertSpaces: false),
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.insertFinalNewLine',
      '编辑器',
      '插入末尾换行',
      _insertFinalNewLine,
      enablement: 'editorTextFocus',
    );
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
    reg(
        'editor.cursorTopSelect',
        '编辑器',
        '选择至文件开头',
        () async =>
            _moveDocumentBoundary(toBottom: false, extendSelection: true),
        enablement: 'editorTextFocus');
    reg('editor.cursorBottom', '编辑器', '移至文件末尾',
        () async => _moveDocumentBoundary(toBottom: true),
        enablement: 'editorTextFocus');
    reg(
        'editor.cursorBottomSelect',
        '编辑器',
        '选择至文件末尾',
        () async =>
            _moveDocumentBoundary(toBottom: true, extendSelection: true),
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
    reg('editor.action.transformToSnakecase', '编辑器', '转换为蛇形命名',
        () => _transformCase(uppercase: false, snakeCase: true),
        enablement: 'editorTextFocus');
    reg('editor.action.transformToPascalcase', '编辑器', '转换为帕斯卡命名',
        () => _transformCase(uppercase: false, pascalCase: true),
        enablement: 'editorTextFocus');
    reg(
      'editor.emmet.action.incrementNumberByOneTenth',
      'Emmet',
      '增加 0.1',
      () => _adjustEmmetNumber(100),
      enablement: 'editorActive',
    );
    reg(
      'editor.emmet.action.incrementNumberByOne',
      'Emmet',
      '增加 1',
      () => _adjustEmmetNumber(1000),
      enablement: 'editorActive',
    );
    reg(
      'editor.emmet.action.incrementNumberByTen',
      'Emmet',
      '增加 10',
      () => _adjustEmmetNumber(10000),
      enablement: 'editorActive',
    );
    reg(
      'editor.emmet.action.decrementNumberByOneTenth',
      'Emmet',
      '减少 0.1',
      () => _adjustEmmetNumber(-100),
      enablement: 'editorActive',
    );
    reg(
      'editor.emmet.action.decrementNumberByOne',
      'Emmet',
      '减少 1',
      () => _adjustEmmetNumber(-1000),
      enablement: 'editorActive',
    );
    reg(
      'editor.emmet.action.decrementNumberByTen',
      'Emmet',
      '减少 10',
      () => _adjustEmmetNumber(-10000),
      enablement: 'editorActive',
    );
    reg(
      'editor.action.transposeLetters',
      '编辑器',
      '转置字母',
      _transposeLetters,
      shortcut: defaultTargetPlatform == TargetPlatform.macOS ? 'Ctrl+T' : null,
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.commentLine',
      '编辑器',
      '切换行注释',
      _toggleLineComment,
      shortcut:
          defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd+/' : 'Ctrl+/',
      enablement: 'editorTextFocus',
    );
    reg(
      'editor.action.blockComment',
      '编辑器',
      '切换块注释',
      _toggleBlockComment,
      shortcut: defaultTargetPlatform == TargetPlatform.linux
          ? 'Ctrl+Shift+A'
          : 'Alt+Shift+A',
      enablement: 'editorTextFocus',
    );
    reg('editor.action.joinLines', '编辑器', '合并行', _joinLines,
        shortcut:
            defaultTargetPlatform == TargetPlatform.macOS ? 'Ctrl+J' : null,
        enablement: 'editorTextFocus');
    reg('editor.replace', '编辑器', '替换…', () async => _openReplace(),
        enablement: 'editorActive');
    reg('lsp.start', '语言服务', '启动 rust-analyzer', _startLsp,
        enablement: 'workspaceOpen && !lspStarting && !lspReady');
    reg('help.about', '帮助', '关于 Alula Code', () async => _showAbout());
    registerGitDiffNavigationCommands(_commands, _gitDiffNavigation);
  }

  void _setActivityBarLocation(ActivityBarLocation location) {
    _layout.setActivityBarLocation(location);
    _syncCommandContext();
  }

  String get _toggleSideBarPositionTitle =>
      _layout.sideBarPosition == SideBarPosition.left
          ? '将主侧栏移到右侧'
          : '将主侧栏移到左侧';

  void _registerToggleSideBarPositionCommand() {
    _commands.register(Command(
      id: 'workbench.action.toggleSidebarPosition',
      category: '查看',
      title: _toggleSideBarPositionTitle,
      run: _toggleSideBarPosition,
    ));
  }

  Future<void> _toggleSideBarPosition() async {
    _layout.toggleSideBarPosition();
    _registerToggleSideBarPositionCommand();
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

  Future<void> _compareActiveFileWithSaved() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      _showSavedCompareStatus('输入法组合输入中，比较已取消');
      return;
    }
    final core = _core;
    final path = doc.path;
    if (core == null || path == null) {
      _showSavedCompareStatus('比较已取消：活动文件没有可用的磁盘版本');
      return;
    }

    try {
      _flushInput(doc);
      final documentId = doc.id;
      final documentUri = doc.uri;
      final documentName = doc.name;
      final documentPath = doc.path;
      final documentEncoding = doc.fileOptions.encoding;
      final probe = doc.doc.readRange(0, maxLenUtf16: 1);
      final documentVersion = probe.version;
      final documentLength = probe.totalUtf16Length;
      const maxCompareInputUtf16 = 2000000;
      const maxSavedFileBytes = 6000016;
      if (documentLength > maxCompareInputUtf16) {
        _showSavedCompareStatus('比较已取消：活动文件超过 2,000,000 UTF-16 单元上限');
        return;
      }

      final stat =
          await (widget.savedCompareFileStat?.call(path) ?? File(path).stat());
      if (!_isSavedCompareSnapshotCurrent(
        doc,
        documentId,
        documentPath,
        documentUri,
        documentName,
        documentVersion,
      )) {
        _showSavedCompareStatus('比较已取消：读取磁盘期间活动文件已变化');
        return;
      }
      if (stat.type != FileSystemEntityType.file) {
        _showSavedCompareStatus(
          stat.type == FileSystemEntityType.notFound
              ? '比较已取消：已保存磁盘版本不存在或不可读取'
              : '比较已取消：活动路径不是可读取的文件',
        );
        return;
      }
      if (stat.size > maxSavedFileBytes) {
        _showSavedCompareStatus('比较已取消：已保存文件超过 6,000,016 字节上限');
        return;
      }

      final saved = _readDiskDocument(
        core,
        path,
        preferredEncoding: documentEncoding,
      );
      if (!_isSavedCompareSnapshotCurrent(
        doc,
        documentId,
        documentPath,
        documentUri,
        documentName,
        documentVersion,
      )) {
        _showSavedCompareStatus('比较已取消：读取磁盘期间活动文件已变化');
        return;
      }
      if (saved.content.length + documentLength > maxCompareInputUtf16) {
        _showSavedCompareStatus('比较已取消：活动文件与磁盘文本合计超过 2,000,000 UTF-16 单元');
        return;
      }

      final documentText = _readDocumentRange(doc, 0, documentLength);
      if (doc.doc.version != documentVersion ||
          !_isSavedCompareSnapshotCurrent(
            doc,
            documentId,
            documentPath,
            documentUri,
            documentName,
            documentVersion,
          )) {
        _showSavedCompareStatus('比较已取消：活动文件快照已变化');
        return;
      }

      final diff = computeDiffViewModel(saved.content, documentText);
      if (diff.isApproximate) {
        _showSavedCompareStatus('比较已取消：差异超过当前预览预算，未显示部分结果');
        return;
      }
      if (!mounted) return;
      await _showEditableSnapshotCompare(
        source: doc,
        title: '已保存版本 ↔ $documentName',
        originalLabel: '已保存版本',
        modifiedLabel: documentName,
        originalText: saved.content,
        initialDiff: diff,
        keyPrefix: 'saved-compare',
      );
    } on AlulaException catch (error) {
      final message = switch (error.code) {
        'BinaryFile' => '比较已取消：磁盘版本是二进制文件',
        'UnsupportedEncoding' => '比较已取消：磁盘版本使用不支持的文本编码',
        _ => '比较失败：无法读取磁盘版本（${error.code}）',
      };
      _showSavedCompareStatus(message);
    } on FileSystemException {
      _showSavedCompareStatus('比较已取消：已保存磁盘版本不存在或不可读取');
    } on Object catch (error) {
      _showSavedCompareStatus('比较失败：$error');
    }
  }

  bool _isSavedCompareSnapshotCurrent(
    OpenDoc doc,
    int documentId,
    String? documentPath,
    String? documentUri,
    String documentName,
    int documentVersion,
  ) =>
      mounted &&
      identical(_active, doc) &&
      _allDocViews.any((view) => identical(view, doc)) &&
      doc.id == documentId &&
      doc.path == documentPath &&
      doc.uri == documentUri &&
      doc.name == documentName &&
      doc.doc.version == documentVersion;

  void _showSavedCompareStatus(String message) {
    if (mounted) setState(() => _statusDetail = message);
  }

  void _showExplorerCompareStatus(String message) {
    if (mounted) setState(() => _statusDetail = message);
  }

  List<_ExplorerOpenDocumentIdentity> _captureExplorerOpenDocuments() => [
        for (final doc in _allDocs)
          if (doc.path != null)
            (
              doc: doc,
              id: doc.id,
              path: doc.path!,
              uri: doc.uri,
              version: doc.doc.version,
            ),
      ];

  bool _isExplorerOpenDocumentCurrent(
    _ExplorerOpenDocumentIdentity identity,
  ) =>
      identity.doc.id == identity.id &&
      identity.doc.path == identity.path &&
      identity.doc.uri == identity.uri &&
      identity.doc.doc.version == identity.version &&
      _allDocViews.any((view) => view.sameDocumentAs(identity.doc));

  Future<_ExplorerOpenDocumentIdentity?> _findExplorerOpenDocument(
    String canonicalPath,
    List<_ExplorerOpenDocumentIdentity> candidates,
  ) async {
    for (final candidate in candidates) {
      if (_canonicalPath(candidate.path) == canonicalPath) return candidate;
    }
    for (final candidate in candidates) {
      try {
        final resolved =
            _canonicalPath(await File(candidate.path).resolveSymbolicLinks());
        if (resolved == canonicalPath) return candidate;
      } on FileSystemException {
        // A stale open path is not a match for the current Explorer resource.
      }
    }
    return null;
  }

  Future<_ResolvedExplorerCompareFile?> _resolveExplorerCompareFile(
    String workspaceRoot,
    String path,
  ) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final canonicalRoot = _canonicalPath(
        await Directory(workspaceRoot).resolveSymbolicLinks(),
      );
      final canonicalPath = _canonicalPath(await file.resolveSymbolicLinks());
      if (!_isStrictWorkspaceChild(canonicalRoot, canonicalPath)) return null;
      return _ResolvedExplorerCompareFile(
        canonicalRoot: canonicalRoot,
        canonicalPath: canonicalPath,
        size: stat.size,
        modified: stat.modified,
      );
    } on FileSystemException {
      return null;
    }
  }

  bool _isStrictWorkspaceChild(String root, String path) {
    final normalizedRoot = _canonicalPath(root).replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = _canonicalPath(path);
    if (normalizedPath == normalizedRoot) return false;
    final prefix = normalizedRoot.isEmpty ? '/' : '$normalizedRoot/';
    return normalizedPath.startsWith(prefix);
  }

  bool _sameExplorerFileRevision(
    _ResolvedExplorerCompareFile first,
    _ResolvedExplorerCompareFile second,
  ) =>
      first.canonicalRoot == second.canonicalRoot &&
      first.canonicalPath == second.canonicalPath &&
      first.size == second.size &&
      first.modified == second.modified;

  Future<void> _selectExplorerFileForCompare(Object? arguments) async {
    final target = arguments;
    if (target is! _ExplorerCompareTarget) {
      _showExplorerCompareStatus('请在资源管理器文件菜单中选择用于比较的文件');
      return;
    }
    final root = _workspaceRoot;
    final core = _core;
    if (root == null || core == null || target.workspaceRoot != root) {
      _showExplorerCompareStatus('选择已取消：工作区已变化');
      return;
    }
    if (target.isDirectory || target.path.isEmpty) {
      _showExplorerCompareStatus('只能选择工作区中的文件进行比较');
      return;
    }

    final candidates = _captureExplorerOpenDocuments();
    var source = candidates
        .where((candidate) =>
            _canonicalPath(candidate.path) == _canonicalPath(target.path))
        .firstOrNull;
    if (source != null) {
      if (source.doc.inputWindow.hasComposition) {
        _showExplorerCompareStatus('输入法组合输入中，选择已取消');
        return;
      }
      _flushInput(source.doc);
      source = (
        doc: source.doc,
        id: source.doc.id,
        path: source.doc.path!,
        uri: source.doc.uri,
        version: source.doc.doc.version,
      );
    }

    final before = await _resolveExplorerCompareFile(root, target.path);
    if (!mounted || _workspaceRoot != root || !identical(_core, core)) {
      _showExplorerCompareStatus('选择已取消：工作区已变化');
      return;
    }
    if (before == null) {
      _showExplorerCompareStatus('选择已取消：文件不存在、不可读或不在当前工作区内');
      return;
    }

    source ??= await _findExplorerOpenDocument(
      before.canonicalPath,
      candidates,
    );
    if (!mounted || _workspaceRoot != root || !identical(_core, core)) {
      _showExplorerCompareStatus('选择已取消：工作区已变化');
      return;
    }

    String originalText;
    if (source != null) {
      if (!_isExplorerOpenDocumentCurrent(source)) {
        _showExplorerCompareStatus('选择已取消：活动文档在读取期间已变化');
        return;
      }
      if (source.doc.inputWindow.hasComposition) {
        _showExplorerCompareStatus('输入法组合输入中，选择已取消');
        return;
      }
      _flushInput(source.doc);
      if (source.doc.doc.version != source.version) {
        _showExplorerCompareStatus('选择已取消：活动文档在读取期间已变化');
        return;
      }
      final probe = source.doc.doc.readRange(0, maxLenUtf16: 1);
      if (probe.totalUtf16Length > _maxExplorerCompareUtf16) {
        _showExplorerCompareStatus('选择已取消：原始文件超过 2,000,000 UTF-16 单元上限');
        return;
      }
      if (probe.version != source.version) {
        _showExplorerCompareStatus('选择已取消：活动文档在读取期间已变化');
        return;
      }
      originalText = _readDocumentRange(source.doc, 0, probe.totalUtf16Length);
      if (!_isExplorerOpenDocumentCurrent(source)) {
        _showExplorerCompareStatus('选择已取消：活动文档在读取期间已变化');
        return;
      }
    } else {
      if (before.size > _maxExplorerCompareDiskBytes) {
        _showExplorerCompareStatus('选择已取消：原始文件超过 6,000,016 字节上限');
        return;
      }
      late final DecodedTextFile decoded;
      try {
        decoded = core.workspace.readFileDocument(target.path);
      } on AlulaException catch (error) {
        final message = switch (error.code) {
          'BinaryFile' => '选择已取消：原始文件是二进制文件',
          'UnsupportedEncoding' => '选择已取消：原始文件使用不支持的文本编码',
          _ => '选择已取消：无法读取原始文件（${error.code}）',
        };
        _showExplorerCompareStatus(message);
        return;
      }
      if (decoded.content.length > _maxExplorerCompareUtf16) {
        _showExplorerCompareStatus('选择已取消：原始文件超过 2,000,000 UTF-16 单元上限');
        return;
      }
      originalText = decoded.content;
      final after = await _resolveExplorerCompareFile(root, target.path);
      if (!mounted ||
          _workspaceRoot != root ||
          !identical(_core, core) ||
          after == null ||
          !_sameExplorerFileRevision(before, after)) {
        _showExplorerCompareStatus('选择已取消：原始文件在读取期间已变化');
        return;
      }
    }

    final finalPath = await _resolveExplorerCompareFile(root, target.path);
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_core, core) ||
        finalPath == null ||
        finalPath.canonicalRoot != before.canonicalRoot ||
        finalPath.canonicalPath != before.canonicalPath ||
        (source != null && !_isExplorerOpenDocumentCurrent(source))) {
      _showExplorerCompareStatus('选择已取消：工作区、路径或文档身份已变化');
      return;
    }

    final selection = _ExplorerCompareSelection(
      workspaceRoot: root,
      canonicalWorkspaceRoot: before.canonicalRoot,
      requestedPath: target.path,
      canonicalPath: before.canonicalPath,
      name: target.name,
      originalText: originalText,
    );
    setState(() {
      _explorerCompareSelection = selection;
      _statusDetail = '已选择 ${target.name} 用于比较';
    });
  }

  Future<void> _compareSelectedExplorerFile(Object? arguments) async {
    final target = arguments;
    if (target is! _ExplorerCompareTarget) {
      _showExplorerCompareStatus('请在资源管理器文件菜单中选择第二个比较文件');
      return;
    }
    final root = _workspaceRoot;
    final core = _core;
    final selection = _explorerCompareSelection;
    if (root == null ||
        core == null ||
        target.workspaceRoot != root ||
        selection == null ||
        selection.workspaceRoot != root) {
      _showExplorerCompareStatus('比较已取消：工作区或原始选择已变化');
      return;
    }
    if (target.isDirectory || target.path.isEmpty) {
      _showExplorerCompareStatus('只能比较工作区中的文件');
      return;
    }

    final originalBefore = await _resolveExplorerCompareFile(
      root,
      selection.requestedPath,
    );
    final modifiedBefore = await _resolveExplorerCompareFile(root, target.path);
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_core, core) ||
        !identical(_explorerCompareSelection, selection)) {
      _showExplorerCompareStatus('比较已取消：工作区或原始选择已变化');
      return;
    }
    if (originalBefore == null ||
        originalBefore.canonicalRoot != selection.canonicalWorkspaceRoot ||
        originalBefore.canonicalPath != selection.canonicalPath) {
      _showExplorerCompareStatus('比较已取消：原始文件已删除、移动或替换');
      return;
    }
    if (modifiedBefore == null ||
        modifiedBefore.canonicalRoot != selection.canonicalWorkspaceRoot) {
      _showExplorerCompareStatus('比较已取消：第二个文件不存在、不可读或不在当前工作区内');
      return;
    }
    if (modifiedBefore.canonicalPath == selection.canonicalPath) {
      _showExplorerCompareStatus('比较已取消：不能将同一文件与自身比较');
      return;
    }

    final candidates = _captureExplorerOpenDocuments();
    var existing = await _findExplorerOpenDocument(
      modifiedBefore.canonicalPath,
      candidates,
    );
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_explorerCompareSelection, selection)) {
      _showExplorerCompareStatus('比较已取消：工作区或原始选择已变化');
      return;
    }
    if (existing != null) {
      if (!_isExplorerOpenDocumentCurrent(existing)) {
        _showExplorerCompareStatus('比较已取消：第二个活动文档在读取期间已变化');
        return;
      }
      if (existing.doc.inputWindow.hasComposition) {
        _showExplorerCompareStatus('输入法组合输入中，比较已取消');
        return;
      }
      _flushInput(existing.doc);
      if (existing.doc.doc.version != existing.version) {
        _showExplorerCompareStatus('比较已取消：第二个活动文档在读取期间已变化');
        return;
      }
    } else if (modifiedBefore.size > _maxExplorerCompareDiskBytes) {
      _showExplorerCompareStatus('比较已取消：第二个文件超过 6,000,016 字节上限');
      return;
    }

    await _openFileByPath(existing?.path ?? target.path);
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_core, core) ||
        !identical(_explorerCompareSelection, selection)) {
      _showExplorerCompareStatus('比较已取消：工作区或原始选择已变化');
      return;
    }
    final modified = _active;
    if (modified == null ||
        modified.path == null ||
        _ownerOfView(modified) == null ||
        (existing != null &&
            (modified.doc.version != existing.version ||
                !modified.sameDocumentAs(existing.doc)))) {
      _showExplorerCompareStatus('比较已取消：第二个文件未能绑定到当前活动文档');
      return;
    }
    if (modified.inputWindow.hasComposition) {
      _showExplorerCompareStatus('输入法组合输入中，比较已取消');
      return;
    }
    _flushInput(modified);
    final probe = modified.doc.readRange(0, maxLenUtf16: 1);
    if (probe.totalUtf16Length > _maxExplorerCompareUtf16) {
      _showExplorerCompareStatus('比较已取消：第二个文件超过 2,000,000 UTF-16 单元上限');
      return;
    }
    final modifiedText =
        _readDocumentRange(modified, 0, probe.totalUtf16Length);
    if (modified.doc.version != probe.version ||
        (existing != null && modified.doc.version != existing.version)) {
      _showExplorerCompareStatus('比较已取消：第二个活动文档在读取期间已变化');
      return;
    }

    final originalAfter = await _resolveExplorerCompareFile(
      root,
      selection.requestedPath,
    );
    final modifiedAfter =
        await _resolveExplorerCompareFile(root, modified.path!);
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_core, core) ||
        !identical(_explorerCompareSelection, selection) ||
        !identical(_active, modified) ||
        modified.doc.version != probe.version ||
        originalAfter == null ||
        originalAfter.canonicalRoot != selection.canonicalWorkspaceRoot ||
        originalAfter.canonicalPath != selection.canonicalPath ||
        modifiedAfter == null ||
        modifiedAfter.canonicalRoot != selection.canonicalWorkspaceRoot ||
        modifiedAfter.canonicalPath != modifiedBefore.canonicalPath ||
        (existing == null &&
            !_sameExplorerFileRevision(modifiedBefore, modifiedAfter))) {
      _showExplorerCompareStatus('比较已取消：工作区、路径或文档身份在读取期间已变化');
      return;
    }

    if (selection.originalText.length + modifiedText.length >
        _maxExplorerCompareUtf16) {
      _showExplorerCompareStatus('比较已取消：两侧合计超过 2,000,000 UTF-16 单元');
      return;
    }
    final diff = computeDiffViewModel(selection.originalText, modifiedText);
    if (diff.isApproximate) {
      _showExplorerCompareStatus('比较已取消：差异超过当前预览预算，未显示部分结果');
      return;
    }
    await _showEditableSnapshotCompare(
      source: modified,
      title: '${selection.name} ↔ ${modified.name}',
      originalLabel: selection.name,
      modifiedLabel: modified.name,
      originalText: selection.originalText,
      initialDiff: diff,
      keyPrefix: 'explorer-compare',
    );
  }

  Future<void> _showEditableSnapshotCompare({
    required OpenDoc source,
    required String title,
    required String originalLabel,
    required String modifiedLabel,
    required String originalText,
    required DiffViewModelResult initialDiff,
    required String keyPrefix,
  }) async {
    final view = OpenDoc.viewOf(source);
    final binding = _SnapshotCompareBinding(
      source: source,
      view: view,
      originalText: originalText,
      initialDiff: initialDiff,
    );
    _snapshotCompareViews[view] = binding;
    _commands.context.setValue('diffEditorActive', true);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          binding.closeRoute = () {
            if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
              Navigator.of(dialogContext, rootNavigator: true).pop();
            }
          };
          final dialogBindings = <ShortcutActivator, VoidCallback>{
            for (final entry in _keybindings
                .resolveBindings(matchesWhen: _commands.context.matches)
                .entries
                .where((entry) =>
                    entry.value.commandId == 'file.save' &&
                    _commands.isEnabled(entry.value.commandId)))
              entry.key: () => _runCommand(
                    entry.value.commandId,
                    arguments: entry.value.arguments,
                  ),
          };
          final isMac = defaultTargetPlatform == TargetPlatform.macOS;
          dialogBindings[const SingleActivator(LogicalKeyboardKey.f1)] =
              _showCommandPalette;
          dialogBindings[SingleActivator(
            LogicalKeyboardKey.keyP,
            control: !isMac,
            meta: isMac,
            shift: true,
          )] = _showCommandPalette;
          dialogBindings[SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: !isMac,
            meta: isMac,
          )] = _undo;
          dialogBindings[SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: !isMac,
            meta: isMac,
            shift: true,
          )] = _redo;
          dialogBindings[SingleActivator(
            LogicalKeyboardKey.keyY,
            control: !isMac,
            meta: isMac,
          )] = _redo;
          return CallbackShortcuts(
            bindings: dialogBindings,
            child: SnapshotComparePreview(
              title: title,
              originalLabel: originalLabel,
              modifiedLabel: modifiedLabel,
              diff: initialDiff,
              keyPrefix: keyPrefix,
              originalText: originalText,
              presentation: binding.presentation,
              modifiedEditorBuilder: (context, state) => _buildCompareEditor(
                binding,
                state,
                keyPrefix,
              ),
              onRevertBlock: (hunkIndex) =>
                  _revertSnapshotCompareHunks(binding, [hunkIndex]),
              onRevertSelection: () => _revertSnapshotCompareSelection(
                binding,
                requireNonCollapsed: true,
              ),
              onClose: binding.closeRoute!,
            ),
          );
        },
      );
    } finally {
      _snapshotCompareViews.remove(view);
      _commands.context
          .setValue('diffEditorActive', _snapshotCompareViews.isNotEmpty);
      binding.dispose();
    }
  }

  Widget _buildCompareEditor(
    _SnapshotCompareBinding binding,
    SnapshotComparePresentation presentation,
    String keyPrefix,
  ) {
    final view = binding.view;
    final diff = presentation.isUpdating ? null : presentation.diff;
    final decorations = diff == null
        ? const <EditorRangeDecoration>[]
        : _snapshotCompareDecorations(diff, view.inputWindow.version);
    return Semantics(
      key: ValueKey('$keyPrefix-modified-editor'),
      label: '${view.name} 比较修改侧编辑器',
      child: RustTextInputField(
        key: view.inputFieldKey,
        inputWindow: view.inputWindow,
        scrollController: view.editorScrollController,
        tabSize: view.tabSize,
        autofocus: true,
        semanticsLabel: '${view.name} 比较修改侧编辑器',
        rangeDecorations: decorations,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        onDelta: (delta) {
          if (binding.isDisposed ||
              !identical(_snapshotCompareViews[view], binding) ||
              !view.sameDocumentAs(binding.source)) {
            return;
          }
          if (_ownerOfView(view) == null) {
            try {
              if (delta.inverseOperations.isNotEmpty) {
                view.doc.applyWith(delta.version, delta.inverseOperations);
              }
            } on Object {
              // A closed/stale view never redirects its write to another doc.
            }
            binding.closeRoute?.call();
            return;
          }
          _onInputDelta(view, delta);
        },
        onError: (error) {
          if (mounted && !binding.isDisposed) {
            setState(() => _statusDetail = '比较编辑未同步：$error');
          }
        },
      ),
    );
  }

  Future<void> _revertFocusedSnapshotCompare() async {
    if (_snapshotCompareViews.isEmpty) return;
    await _revertSnapshotCompareSelection(
      _snapshotCompareViews.values.last,
      requireNonCollapsed: false,
    );
  }

  Future<void> _revertSnapshotCompareSelection(
    _SnapshotCompareBinding binding, {
    required bool requireNonCollapsed,
  }) async {
    final view = binding.view;
    final selection = view.selection;
    if (requireNonCollapsed && selection.isCollapsed) {
      _setSnapshotCompareActionMessage(binding, '请先在修改侧选中要回退的差异块');
      return;
    }
    final presentation = binding.presentation.value;
    final diff = presentation.diff;
    if (diff == null) {
      _setSnapshotCompareActionMessage(
        binding,
        presentation.isUpdating
            ? '差异正在更新，暂时无法回退'
            : presentation.fallbackMessage ?? '当前没有可用的精确差异',
      );
      return;
    }
    final hunkIndices = diffHunksIntersectingModifiedSelection(
      diff,
      selectionStartUtf16: selection.baseOffset,
      selectionEndUtf16: selection.extentOffset,
    );
    if (hunkIndices.isEmpty) {
      _setSnapshotCompareActionMessage(binding, '光标或选区没有对应的差异块');
      return;
    }
    await _revertSnapshotCompareHunks(binding, hunkIndices);
  }

  Future<void> _revertSnapshotCompareHunks(
    _SnapshotCompareBinding binding,
    List<int> hunkIndices,
  ) async {
    final view = binding.view;
    void reject(String message) =>
        _setSnapshotCompareActionMessage(binding, message);

    if (binding.isDisposed ||
        !mounted ||
        !identical(_snapshotCompareViews[view], binding) ||
        !view.sameDocumentAs(binding.source) ||
        _ownerOfView(view) == null) {
      reject('比较文档已关闭或资源身份已变化，回退已取消');
      return;
    }
    if (view.inputWindow.hasComposition) {
      reject('输入法组合输入中，回退已取消');
      return;
    }
    if (view.undoRedoBusy) {
      reject('文档正在撤销或重做，回退已取消');
      return;
    }

    _flushInput(view);
    if (view.inputWindow.hasComposition ||
        view.inputWindow.pendingCount > 0 ||
        view.inputWindow.pendingText != null) {
      reject('修改侧仍有未提交输入，回退已取消');
      return;
    }

    final presentation = binding.presentation.value;
    final diff = presentation.diff;
    if (presentation.isUpdating ||
        presentation.fallbackMessage != null ||
        diff == null ||
        diff.isApproximate ||
        diff.originalText != binding.originalText) {
      reject('差异不是当前精确版本，回退已取消');
      return;
    }

    final expectedVersion = view.doc.version;
    final probe = view.doc.readRange(0, maxLenUtf16: 1);
    if (probe.version != expectedVersion ||
        binding.originalText.length + probe.totalUtf16Length > 2000000) {
      reject('文档版本已变化或超过差异预算，回退已取消');
      return;
    }
    final modifiedText =
        _readDocumentRange(view, 0, probe.totalUtf16Length);
    if (view.doc.version != expectedVersion ||
        !identical(binding.presentation.value, presentation) ||
        modifiedText != diff.modifiedText) {
      reject('修改侧文档与差异快照不一致，回退已取消');
      return;
    }

    final ranges = diffRevertRanges(diff, hunkIndices);
    if (ranges.isEmpty || ranges.length != hunkIndices.toSet().length) {
      reject('差异块映射无效，未应用任何回退');
      return;
    }
    final edits = [
      for (final range in ranges)
        (
          start: range.modifiedStartUtf16,
          end: range.modifiedEndUtf16,
          oldText: modifiedText.substring(
            range.modifiedStartUtf16,
            range.modifiedEndUtf16,
          ),
          newText: binding.originalText.substring(
            range.originalStartUtf16,
            range.originalEndUtf16,
          ),
        ),
    ];
    if (edits.every((edit) => edit.oldText == edit.newText)) {
      reject('差异块已与原始快照一致');
      return;
    }

    final forward = <TextOp>[];
    for (final edit in edits.reversed) {
      if (edit.end > edit.start) {
        forward.add(TextOp.delete(edit.start, edit.end - edit.start));
      }
      if (edit.newText.isNotEmpty) {
        forward.add(TextOp.insert(edit.start, edit.newText));
      }
    }
    final inverse = <TextOp>[];
    for (final edit in edits) {
      if (edit.newText.isNotEmpty) {
        inverse.add(TextOp.delete(edit.start, edit.newText.length));
      }
      if (edit.oldText.isNotEmpty) {
        inverse.add(TextOp.insert(edit.start, edit.oldText));
      }
    }
    if (_operationPayloadChars([forward, inverse]) >
        _undoHistoryBudget.maxTotalChars) {
      reject('回退内容超过撤销历史预算，未应用任何修改');
      return;
    }

    final beforeSelection = view.selection;
    try {
      view.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      reject('Rust 文档拒绝回退：${error.code}');
      return;
    } on Object catch (error) {
      reject('回退失败：$error');
      return;
    }

    final newLength = modifiedText.length +
        edits.fold<int>(0, (n, e) => n + e.newText.length - e.oldText.length);
    TextSelection mapSelection(TextSelection selection) => TextSelection(
          baseOffset: mapWorkspaceEditOffset(
            selection.baseOffset,
            forward,
          ).clamp(0, newLength).toInt(),
          extentOffset: mapWorkspaceEditOffset(
            selection.extentOffset,
            forward,
          ).clamp(0, newLength).toInt(),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        );
    final afterSelection = mapSelection(beforeSelection);
    _recordDocumentOperations(
      view,
      forward: forward,
      inverse: inverse,
      beforeCaret: beforeSelection.extentOffset,
      afterCaret: afterSelection.extentOffset,
      coalesce: false,
    );
    view.replaceInputWindow(
      afterSelection.extentOffset,
      selection: afterSelection,
    );
    view.crossWindowSelection = null;
    _refreshSiblingViews(view, forward);
    _scheduleSnapshotCompareDiff(binding);
    if (_findVisible) _onFindTextChanged();
    if (mounted) {
      setState(() => _statusDetail = '已将所选差异块恢复为原始快照');
    }
  }

  void _setSnapshotCompareActionMessage(
    _SnapshotCompareBinding binding,
    String message,
  ) {
    if (binding.isDisposed) return;
    final state = binding.presentation.value;
    binding.presentation.value = SnapshotComparePresentation(
      diff: state.diff,
      isUpdating: state.isUpdating,
      fallbackMessage: state.fallbackMessage,
      actionMessage: message,
    );
    if (mounted) setState(() => _statusDetail = message);
  }

  List<EditorRangeDecoration> _snapshotCompareDecorations(
    DiffViewModelResult diff,
    int documentVersion,
  ) {
    final changedKinds = <int, DiffViewRowKind>{};
    for (final row in diff.rows) {
      final line = row.modifiedLineNumber;
      if (line == null || row.kind == DiffViewRowKind.unchanged) continue;
      changedKinds[line] = row.kind;
    }
    if (changedKinds.isEmpty) return const [];

    final lineRanges = <int, (int, int)>{};
    final text = diff.modifiedText;
    var lineNumber = 1;
    var lineStart = 0;
    for (var offset = 0; offset <= text.length; offset++) {
      if (offset == text.length || text.codeUnitAt(offset) == 0x0A) {
        if (changedKinds.containsKey(lineNumber)) {
          lineRanges[lineNumber] = (lineStart, offset);
        }
        lineNumber++;
        lineStart = offset + 1;
      }
    }

    return [
      for (final entry in lineRanges.entries)
        EditorRangeDecoration(
          documentVersion: documentVersion,
          startUtf16: entry.value.$1,
          endUtf16:
              entry.value.$1 == entry.value.$2 && entry.value.$2 < text.length
                  ? entry.value.$2 + 1
                  : entry.value.$2,
          backgroundColor: changedKinds[entry.key] == DiffViewRowKind.inserted
              ? const Color(0x55303F2E)
              : const Color(0x553F1D20),
        ),
    ];
  }

  void _scheduleSnapshotCompareDiff(_SnapshotCompareBinding binding) {
    if (binding.isDisposed ||
        !mounted ||
        !identical(_snapshotCompareViews[binding.view], binding)) {
      return;
    }
    binding.timer?.cancel();
    binding.presentation.value = const SnapshotComparePresentation(
      isUpdating: true,
    );
    binding.timer = Timer(const Duration(milliseconds: 100), () {
      _refreshSnapshotCompareDiff(binding);
    });
  }

  void _refreshSnapshotCompareDiff(_SnapshotCompareBinding binding) {
    final view = binding.view;
    if (binding.isDisposed ||
        !mounted ||
        !identical(_snapshotCompareViews[view], binding) ||
        _ownerOfView(view) == null) {
      return;
    }
    const maxCompareInputUtf16 = 2000000;
    try {
      final version = view.doc.version;
      final length = view.doc.readRange(0, maxLenUtf16: 1).totalUtf16Length;
      if (binding.originalText.length + length > maxCompareInputUtf16) {
        binding.presentation.value = const SnapshotComparePresentation(
          fallbackMessage: '差异超过 2,000,000 UTF-16 单元预算；完整编辑仍可继续',
        );
        return;
      }
      final modified = _readDocumentRange(view, 0, length);
      if (view.doc.version != version) {
        _scheduleSnapshotCompareDiff(binding);
        return;
      }
      final diff = computeDiffViewModel(binding.originalText, modified);
      if (view.doc.version != version) {
        _scheduleSnapshotCompareDiff(binding);
        return;
      }
      if (diff.isApproximate) {
        final reason = diff.fallbackReason?.name ??
            diff.lineDiff.fallbackReason?.name ??
            '差异行或单词预算';
        binding.presentation.value = SnapshotComparePresentation(
          fallbackMessage: '差异预算已达到（$reason）；完整编辑仍可继续',
        );
      } else {
        binding.presentation.value = SnapshotComparePresentation(diff: diff);
      }
    } on Object catch (error) {
      binding.presentation.value = SnapshotComparePresentation(
        fallbackMessage: '差异更新失败；完整编辑仍可继续（$error）',
      );
    }
  }

  Future<void> _compareActiveFileWithClipboard() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) {
        setState(() => _statusDetail = '输入法组合输入中，比较已取消');
      }
      return;
    }

    try {
      _flushInput(doc);
      final documentId = doc.id;
      final documentPath = doc.path;
      final documentUri = doc.uri;
      final documentName = doc.name;
      final probe = doc.doc.readRange(0, maxLenUtf16: 1);
      final documentVersion = probe.version;
      final documentLength = probe.totalUtf16Length;
      const maxCompareInputUtf16 = 2000000;
      if (documentLength > maxCompareInputUtf16) {
        _showClipboardCompareStatus('比较已取消：活动文件超过 2,000,000 UTF-16 单元上限');
        return;
      }
      final documentText = _readDocumentRange(doc, 0, documentLength);
      if (doc.doc.version != documentVersion ||
          !_isClipboardCompareSnapshotCurrent(
            doc,
            documentId,
            documentPath,
            documentUri,
            documentName,
            documentVersion,
          )) {
        _showClipboardCompareStatus('比较已取消：活动文件快照已变化');
        return;
      }

      final clipboard = await EditorClipboard.read();
      if (!mounted) return;
      if (!_isClipboardCompareSnapshotCurrent(
        doc,
        documentId,
        documentPath,
        documentUri,
        documentName,
        documentVersion,
      )) {
        _showClipboardCompareStatus('比较已取消：读取剪贴板期间活动文件已变化');
        return;
      }
      if (clipboard == null) {
        _showClipboardCompareStatus('比较已取消：剪贴板没有纯文本内容');
        return;
      }
      if (documentText.length + clipboard.text.length > maxCompareInputUtf16) {
        _showClipboardCompareStatus('比较已取消：文件与剪贴板合计超过 2,000,000 UTF-16 单元');
        return;
      }

      final diff = computeDiffViewModel(clipboard.text, documentText);
      if (diff.isApproximate) {
        _showClipboardCompareStatus('比较已取消：差异超过当前预览预算，未显示部分结果');
        return;
      }
      await _showEditableSnapshotCompare(
        source: doc,
        title: '剪贴板 ↔ $documentName',
        originalLabel: '剪贴板',
        modifiedLabel: documentName,
        originalText: clipboard.text,
        initialDiff: diff,
        keyPrefix: 'clipboard-compare',
      );
    } on Object catch (error) {
      _showClipboardCompareStatus('比较失败：$error');
    }
  }

  bool _isClipboardCompareSnapshotCurrent(
    OpenDoc doc,
    int documentId,
    String? documentPath,
    String? documentUri,
    String documentName,
    int documentVersion,
  ) =>
      mounted &&
      identical(_active, doc) &&
      _allDocViews.any((view) => identical(view, doc)) &&
      doc.id == documentId &&
      doc.path == documentPath &&
      doc.uri == documentUri &&
      doc.name == documentName &&
      doc.doc.version == documentVersion;

  void _showClipboardCompareStatus(String message) {
    if (mounted) setState(() => _statusDetail = message);
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
    final mergeSession = active?.mergeResultSession;
    final currentMergeConflict = active == null
        ? null
        : _mergeConflictAtSelection(active);
    _commands.context.setValues({
      'editorActive': active != null,
      'editorHasPath': active?.path != null,
      'editorDirty': active?.isDirty ?? false,
      'editorTextFocus': active != null && _isEditorRegion(_focusedRegion),
      'editorCanUndo': active?.undoStack.canUndo ?? false,
      'editorCanRedo': active?.undoStack.canRedo ?? false,
      'cursorCanUndo': active?.selectionHistory.canUndo ?? false,
      'cursorCanRedo': active?.selectionHistory.canRedo ?? false,
      'workspaceOpen': _workspaceRoot != null,
      'activityBarLocation': _layout.activityBarLocation.name,
      'panelMaximizationSupported': _layout.canMaximizePanel,
      'lspStarting': _lspStarting,
      'lspReady': _lspReady,
      'mergeEditorActive': mergeSession != null && !mergeSession.isDisposed,
      'mergeUnhandledConflictAvailable': mergeSession != null &&
          !mergeSession.hasStaleConflictRanges &&
          mergeSession.unresolvedConflictCount > 0,
      'mergeAllConflictsAvailable': mergeSession != null &&
          !mergeSession.isDisposed &&
          !mergeSession.hasStaleConflictRanges &&
          mergeSession.conflictCount > 0,
      'mergeCurrentConflictAvailable':
          currentMergeConflict != null && !currentMergeConflict.isCombination,
      gitDiffViewActiveContextKey: _panelTab.index == 3,
      gitDiffNavigationAvailableContextKey: _gitDiffNavigation.canNavigate,
    });
  }

  void _syncPanelMaximizationCommandContext() {
    _commands.context.setValue(
      'panelMaximizationSupported',
      _layout.canMaximizePanel,
    );
  }

  void _onGitDiffNavigationAvailabilityChanged(bool _) {
    if (mounted) _syncCommandContext();
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
    final currentLocation = _layout.activityBarLocation;
    QuickInput.show(
      context,
      hint: '输入命令名（> 前缀可省）',
      items: [
        for (final c in _commands.all)
          if (!_isCurrentActivityBarLocationCommand(c.id, currentLocation))
            QuickItem(label: c.label, detail: c.shortcut, commandId: c.id),
      ],
      commands: _commands,
    );
  }

  bool _isCurrentActivityBarLocationCommand(
      String commandId, ActivityBarLocation currentLocation) {
    final target = switch (commandId) {
      'workbench.action.activityBarLocation.default' =>
        ActivityBarLocation.side,
      'workbench.action.activityBarLocation.top' => ActivityBarLocation.top,
      'workbench.action.activityBarLocation.bottom' =>
        ActivityBarLocation.bottom,
      'workbench.action.activityBarLocation.hide' => ActivityBarLocation.hidden,
      _ => null,
    };
    return target == currentLocation;
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
  void _setEditorTabMode(EditorTabMode mode) {
    if (_editorTabMode.value == mode) return;
    setState(() {
      _editorTabMode.value = mode;
      for (final group in _groups.values) {
        group.lastAutoRevealedTabId = null;
      }
    });
    _scheduleStateSave();
  }

  void _setEditorTabWrap(bool enabled) {
    if (_editorTabWrap.value == enabled) return;
    setState(() => _editorTabWrap.value = enabled);
    _scheduleStateSave();
  }

  void _setPinnedTabsOnSeparateRow(bool enabled) {
    if (_pinnedTabsOnSeparateRow.value == enabled) return;
    setState(() {
      _pinnedTabsOnSeparateRow.value = enabled;
      for (final group in _groups.values) {
        group.lastAutoRevealedTabId = null;
      }
    });
    _scheduleStateSave();
  }

  void _setEditorTabSizing(EditorTabSizing sizing) {
    if (_editorTabSizing.value == sizing) return;
    setState(() {
      _editorTabSizing.value = sizing;
      _editorTabHeldWidths.clear();
    });
    _scheduleStateSave();
  }

  void _setEditorTabActionLocation(EditorTabActionLocation location) {
    if (_editorTabActionLocation.value == location) return;
    setState(() => _editorTabActionLocation.value = location);
    _scheduleStateSave();
  }

  void _setEditorTabCloseActionVisibility(bool visible) {
    if (_editorTabCloseActionVisibility.value == visible) return;
    setState(() => _editorTabCloseActionVisibility.value = visible);
    _scheduleStateSave();
  }

  void _setEditorTabActionReserveSpace(bool reserveSpace) {
    if (_editorTabActionReserveSpace.value == reserveSpace) return;
    setState(() => _editorTabActionReserveSpace.value = reserveSpace);
    _scheduleStateSave();
  }

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
        'editorTabMode': _editorTabMode.value.name,
        'editorTabSizing': _editorTabSizing.value.name,
        'editorTabActionLocation': _editorTabActionLocation.value.name,
        'editorTabCloseActionVisibility': _editorTabCloseActionVisibility.value,
        'editorTabActionReserveSpace': _editorTabActionReserveSpace.value,
        'editorWrapTabs': _editorTabWrap.value,
        'pinnedTabsOnSeparateRow': _pinnedTabsOnSeparateRow.value,
        'focused': _focusedRegion,
        'openEditorsCollapsed': _openEditorsCollapsed,
        'workbench.editor.useModal': _modalEditorUseMode.value,
        if (_workspaceRoot != null) 'workspace': _workspaceRoot,
        'groups': [
          for (final g in _groups.values)
            {
              'region': g.region,
              'active': g.activeDocId,
              'sticky': [
                for (final doc in g.docs)
                  if (g.stickyDocIds.contains(doc.id)) doc.id,
              ],
              if (g.previewDocId != null &&
                  g.docs.any((d) => d.id == g.previewDocId && !d.isDirty))
                'preview': g.previewDocId,
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
      _loadFindHistoryForWorkspace(_workspaceRoot);
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
        _noteActiveDocument(g, g.activeDocId);
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
    _editorTabMode.value =
        EditorTabMode.fromSessionValue(data['editorTabMode']);
    _editorTabSizing.value =
        EditorTabSizing.fromSessionValue(data['editorTabSizing']);
    _editorTabActionLocation.value = EditorTabActionLocation.fromSessionValue(
        data['editorTabActionLocation']);
    _editorTabCloseActionVisibility.value =
        data['editorTabCloseActionVisibility'] is bool
            ? data['editorTabCloseActionVisibility'] as bool
            : true;
    _editorTabActionReserveSpace.value =
        data['editorTabActionReserveSpace'] is bool
            ? data['editorTabActionReserveSpace'] as bool
            : true;
    _editorTabWrap.value = data['editorWrapTabs'] == true;
    _pinnedTabsOnSeparateRow.value = data['pinnedTabsOnSeparateRow'] == true;
    _openEditorsCollapsed = data['openEditorsCollapsed'] == true;
    _modalEditorUseMode =
        ModalEditorUseModeJson.parse(data['workbench.editor.useModal']);
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
        final stickyRaw = gr['sticky'];
        if (stickyRaw is List) {
          for (final value in stickyRaw) {
            if (value is num) {
              final id = value.toInt();
              if (target.docs.any((doc) => doc.id == id)) {
                target.stickyDocIds.add(id);
              }
            }
          }
          _normalizeStickyOrder(target);
        }
        final active = (gr['active'] as num?)?.toInt();
        if (target.docs.isNotEmpty) {
          target.activeDocId = target.docs.any((d) => d.id == active)
              ? active
              : target.docs.last.id;
          _noteActiveDocument(target, target.activeDocId);
        }
        final previewId = (gr['preview'] as num?)?.toInt();
        final restoredPreview = target.docs
            .where((doc) => doc.id == previewId)
            .firstOrNull;
        if (restoredPreview != null &&
            !restoredPreview.isDirty &&
            !target.stickyDocIds.contains(restoredPreview.id)) {
          target.previewDocId = restoredPreview.id;
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
    for (final view in _snapshotCompareViews.keys) {
      if (view.sameDocumentAs(document)) yield view;
    }
  }

  bool _canStartEditorTextDragDrop(OpenDoc document) =>
      !_disposing &&
      _viewsOf(document).every((view) =>
          view.inputWindow.version == view.doc.version &&
          view.inputWindow.pendingCount == 0 &&
          !view.inputWindow.hasComposition &&
          view.pendingInputOperations.isEmpty &&
          view.pendingInputWindowShiftUtf16 == 0);

  bool _canReceiveExternalTextDrop(OpenDoc document) =>
      document.diskState == DiskDocumentState.current &&
      _canStartEditorTextDragDrop(document);

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
    if (_snapshotCompareViews.containsKey(view)) {
      for (final g in _groups.values) {
        if (g.docs.any((candidate) => candidate.sameDocumentAs(view))) {
          return g;
        }
      }
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
    if (!doc.isDirty) return;
    var pinnedPreview = false;
    for (final group in _groups.values) {
      final preview = group.docs
          .where((view) => view.id == group.previewDocId)
          .firstOrNull;
      if (preview != null && preview.sameDocumentAs(doc)) {
        group.previewDocId = null;
        pinnedPreview = true;
      }
    }
    if (pinnedPreview && !_disposing) _scheduleStateSave();
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
    List<int>? linkedDocumentIds,
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
        linkedDocumentIds: linkedDocumentIds,
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
        linkedDocumentIds: linkedDocumentIds,
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
        : TextSelection.collapsed(
            offset: destination, affinity: current.affinity);
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

  List<String>? _copyableDocumentSelectionTexts(
    OpenDoc doc,
    List<TextSelection> selections, {
    required int version,
    required String lineEol,
    required bool forceCrLf,
  }) {
    final ordered = List<TextSelection>.of(selections)
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <String>[];
    int? previousEmptyLineStart;
    for (final selection in ordered) {
      if (doc.doc.version != version) return null;
      if (selection.isCollapsed) {
        final line = doc.doc.lineBoundary(selection.extentOffset);
        if (line.version != version) return null;
        if (line.startUtf16 == previousEmptyLineStart) continue;
        final lineText = _readDocumentRange(
          doc,
          line.startUtf16,
          line.endUtf16,
        );
        if (doc.doc.version != version) return null;
        final copiedLine =
            forceCrLf ? lineText.replaceAll('\n', '\r\n') : lineText;
        result.add('$copiedLine$lineEol');
        previousEmptyLineStart = line.startUtf16;
      } else {
        final selectedText = _readDocumentRange(
          doc,
          selection.start,
          selection.end,
        );
        if (doc.doc.version != version) return null;
        result.add(
          forceCrLf ? selectedText.replaceAll('\n', '\r\n') : selectedText,
        );
        previousEmptyLineStart = null;
      }
    }
    return result;
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
            final inserted = indentationTabText(
              prefix,
              tabSize: doc.tabSize,
              indentSize: doc.tabSize,
              insertSpaces: doc.insertSpaces,
            );
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
            final inserted = indentationTabText(
              prefix,
              tabSize: doc.tabSize,
              indentSize: doc.tabSize,
              insertSpaces: doc.insertSpaces,
            );
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
            final newIndent = shiftLineIndentation(
              line,
              outdent: outdent,
              tabSize: doc.tabSize,
              indentSize: doc.tabSize,
              insertSpaces: doc.insertSpaces,
            );
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

  String? _richHtmlForCopy(
    OpenDoc doc,
    String text,
    int selectionStartUtf16,
  ) {
    final languageId =
        doc.path == null ? 'plaintext' : _languageIdOf(doc.path!);
    if (languageId != 'rust' ||
        _syntaxVersionByDoc[doc.id] != doc.doc.version) {
      return null;
    }
    return buildRichTextClipboardHtml(
      text: text,
      selectionStartUtf16: selectionStartUtf16,
      languageId: languageId,
      tokens: _syntaxByDoc[doc.id] ?? const <Map<String, Object?>>[],
      colorForToken: (kind) {
        final value = _tokenColor(kind).toARGB32() & 0x00FFFFFF;
        return '#${value.toRadixString(16).padLeft(6, '0')}';
      },
    );
  }

  Future<void> _writeEditorClipboardCopy(
    OpenDoc doc,
    String text, {
    required int selectionStartUtf16,
    String? htmlText,
    bool includeHtml = true,
    bool isFromEmptySelection = false,
    List<String>? multiCursorText,
  }) async {
    final html = includeHtml
        ? htmlText ?? _richHtmlForCopy(doc, text, selectionStartUtf16)
        : null;
    final languageId =
        doc.path == null ? 'plaintext' : _languageIdOf(doc.path!);
    await EditorClipboard.write(
      text: text,
      html: html,
      metadata: EditorClipboardMetadata(
        isFromEmptySelection: isFromEmptySelection,
        isBlock: doc.columnSelection != null,
        multiCursorText: multiCursorText,
        mode: html == null ? null : languageId,
      ),
    );
  }

  Future<void> _copyCrossWindowSelection(OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final selection = doc.crossWindowSelection;
    if (selection == null) return;
    final version = doc.doc.version;
    final text = _readDocumentRange(doc, selection.start, selection.end);
    if (doc.doc.version != version || doc.crossWindowSelection != selection) {
      return;
    }
    await _writeEditorClipboardCopy(
      doc,
      text,
      selectionStartUtf16: selection.start,
    );
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

  Future<void> _adjustEmmetNumber(int deltaMilli) async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted && selections.length > maxDocLineDeleteSelections) {
        setState(() => _statusDetail =
            'Emmet 数值调整已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final ranges = <(int, int), TextNumberAdjustmentPlan>{};
    final selectionPlans = <({TextSelection selection, (int, int)? range})>[];
    var payloadChars = 0;
    try {
      for (final selection in selections) {
        // Code-OSS resolves the number from the selection's right endpoint,
        // whether the selection is forward or reversed.
        final caret = selection.end;
        final position = doc.doc.positionAt(caret);
        final boundary = doc.doc.lineBoundary(caret);
        if (position.version != expectedVersion ||
            boundary.version != expectedVersion ||
            boundary.line != position.line ||
            caret < boundary.startUtf16 ||
            caret > boundary.endUtf16) {
          throw StateError('Rust 返回了过期或无效的 Emmet 数值光标位置');
        }

        const windowLimit = maxNumberAdjustmentWindowUtf16;
        final lineLength = boundary.endUtf16 - boundary.startUtf16;
        final column = caret - boundary.startUtf16;
        var windowStart = 0;
        var windowEnd = lineLength;
        if (lineLength > windowLimit) {
          windowStart =
              (column - windowLimit ~/ 2).clamp(0, lineLength).toInt();
          windowEnd = (column + windowLimit ~/ 2)
              .clamp(windowStart, lineLength)
              .toInt();
        }
        final absoluteWindowStart = boundary.startUtf16 + windowStart;
        final absoluteWindowEnd = boundary.startUtf16 + windowEnd;
        final text = _readDocumentRange(
          doc,
          absoluteWindowStart,
          absoluteWindowEnd,
        );
        if (text.codeUnits.length != windowEnd - windowStart) {
          throw StateError('Rust 返回的 Emmet 数值窗口 UTF-16 长度不一致');
        }
        final relativePlan =
            (_core ?? (throw StateError('Alula Rust 核心未初始化'))).adjustNumberText(
          text: text,
          caretUtf16: caret - absoluteWindowStart,
          deltaMilli: deltaMilli,
          includesLineStart: windowStart == 0,
          includesLineEnd: windowEnd == lineLength,
        );
        if (relativePlan == null) {
          selectionPlans.add((selection: selection, range: null));
          continue;
        }
        if (relativePlan.startUtf16 < 0 ||
            relativePlan.endUtf16 <= relativePlan.startUtf16 ||
            relativePlan.endUtf16 > text.codeUnits.length ||
            relativePlan.removedText.codeUnits.length !=
                relativePlan.endUtf16 - relativePlan.startUtf16) {
          throw StateError('Rust 返回了无效的 Emmet 数值范围');
        }
        final start = absoluteWindowStart + relativePlan.startUtf16;
        final end = absoluteWindowStart + relativePlan.endUtf16;
        if (_readDocumentRange(doc, start, end) != relativePlan.removedText) {
          throw StateError('Emmet 数值计划与 Rust 文档内容不一致');
        }
        final plan = TextNumberAdjustmentPlan(
          startUtf16: start,
          endUtf16: end,
          removedText: relativePlan.removedText,
          insertedText: relativePlan.insertedText,
        );
        final key = (start, end);
        final existing = ranges[key];
        if (existing != null &&
            (existing.removedText != plan.removedText ||
                existing.insertedText != plan.insertedText)) {
          throw StateError('Rust 对相同 Emmet 数值范围返回了不同文本');
        }
        ranges[key] = plan;
        selectionPlans.add((selection: selection, range: key));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = 'Emmet 数值调整未应用：$error');
      return;
    }

    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = 'Emmet 数值调整未应用：文档版本已变化');
      return;
    }

    final orderedRanges = ranges.values.toList()
      ..sort((a, b) => a.startUtf16.compareTo(b.startUtf16));
    for (var index = 1; index < orderedRanges.length; index++) {
      if (orderedRanges[index].startUtf16 < orderedRanges[index - 1].endUtf16) {
        if (mounted) {
          setState(() => _statusDetail = 'Emmet 数值调整已取消：多个编辑范围重叠');
        }
        return;
      }
    }

    final mappedRanges = <({
      int start,
      int end,
      String removed,
      String inserted,
      int mappedStart,
    })>[];
    for (final plan in orderedRanges) {
      final mappedStart = plan.startUtf16 + payloadChars;
      mappedRanges.add((
        start: plan.startUtf16,
        end: plan.endUtf16,
        removed: plan.removedText,
        inserted: plan.insertedText,
        mappedStart: mappedStart,
      ));
      if (plan.removedText != plan.insertedText) {
        payloadChars += plan.insertedText.length - plan.removedText.length;
      }
    }

    int mapOffset(int offset) {
      var delta = 0;
      for (final range in mappedRanges) {
        if (offset < range.start) return offset + delta;
        if (offset <= range.end) {
          final relative =
              (offset - range.start).clamp(0, range.inserted.length).toInt();
          return range.mappedStart + relative;
        }
        delta += range.inserted.length - range.removed.length;
      }
      return offset + delta;
    }

    final mappedSelections = normalizeSelectionSet([
      for (final plan in selectionPlans)
        TextSelection(
          baseOffset: mapOffset(plan.selection.baseOffset),
          extentOffset: mapOffset(plan.selection.extentOffset),
          affinity: plan.selection.affinity,
          isDirectional: plan.selection.isDirectional,
        ),
    ]);
    final changedRanges = mappedRanges
        .where((plan) => plan.removed != plan.inserted)
        .toList(growable: false);
    if (changedRanges.isEmpty) return;

    var undoChars = 0;
    for (final plan in changedRanges) {
      undoChars += plan.removed.length + plan.inserted.length;
      if (undoChars > _undoHistoryBudget.maxTotalChars) {
        if (mounted) {
          setState(() => _statusDetail =
              'Emmet 数值调整已取消：撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        return;
      }
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in changedRanges.reversed) {
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
        setState(() =>
            _statusDetail = 'Emmet 数值调整未应用：${error.code} ${error.detail}');
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
    if (mounted) setState(() => _statusDetail = '已调整 Emmet 数值');
  }

  Future<void> _transposeLetters() async {
    final doc = _active;
    if (doc == null || doc.inputWindow.hasComposition) return;

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocTransposeCarets) {
      if (mounted && selections.length > maxDocTransposeCarets) {
        setState(
            () => _statusDetail = '字母转置已取消：光标数超过 $maxDocTransposeCarets 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final carets = selections
        .where((selection) => selection.isCollapsed)
        .map((selection) => selection.extentOffset)
        .toList(growable: false);
    late final DocumentTransposePlans queried;
    try {
      queried = doc.doc.transposeRanges(carets);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '字母转置失败：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion ||
        queried.plans.length != carets.length) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) {
        setState(() => _statusDetail = '字母转置未应用：文档同步版本已变化');
      }
      return;
    }

    final ranges = <(int, int), DocumentTransposePlan>{};
    final mappedSelections = <TextSelection>[];
    var caretIndex = 0;
    try {
      for (final selection in selections) {
        if (!selection.isCollapsed) {
          mappedSelections.add(selection);
          continue;
        }
        final plan = queried.plans[caretIndex++];
        if (plan == null) {
          mappedSelections.add(selection);
          continue;
        }
        if (plan.startUtf16 < 0 ||
            plan.endUtf16 <= plan.startUtf16 ||
            plan.removedText.length != plan.endUtf16 - plan.startUtf16 ||
            plan.insertedText.length != plan.removedText.length) {
          throw StateError('Rust 返回了无效的 UTF-16 字母转置计划');
        }
        final key = (plan.startUtf16, plan.endUtf16);
        final existing = ranges[key];
        if (existing != null &&
            (existing.removedText != plan.removedText ||
                existing.insertedText != plan.insertedText)) {
          throw StateError('Rust 对相同字母转置范围返回了不同文本');
        }
        ranges[key] = plan;
        mappedSelections.add(TextSelection.collapsed(
          offset: plan.endUtf16,
          affinity: selection.affinity,
        ));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '字母转置未应用：$error');
      return;
    }

    final orderedRanges = ranges.values.toList()
      ..sort((a, b) => a.startUtf16.compareTo(b.startUtf16));
    for (var index = 1; index < orderedRanges.length; index++) {
      if (orderedRanges[index].startUtf16 < orderedRanges[index - 1].endUtf16) {
        if (mounted) {
          setState(() => _statusDetail = '字母转置已取消：多个编辑范围重叠');
        }
        return;
      }
    }

    var payloadChars = 0;
    final changedRanges = orderedRanges
        .where((plan) => plan.removedText != plan.insertedText)
        .toList(growable: false);
    for (final plan in changedRanges) {
      payloadChars += plan.removedText.length + plan.insertedText.length;
      if (payloadChars > _undoHistoryBudget.maxTotalChars) {
        if (mounted) {
          setState(() => _statusDetail =
              '字母转置已取消：撤销文本超出 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        return;
      }
    }

    final normalizedSelections = normalizeSelectionSet(mappedSelections);
    if (changedRanges.isEmpty) {
      _setDocSelections(doc, normalizedSelections);
      doc.replaceInputWindow(
        normalizedSelections.first.extentOffset,
        selection: normalizedSelections.first,
      );
      return;
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final plan in changedRanges.reversed) {
      forward
        ..add(TextOp.delete(plan.startUtf16, plan.endUtf16 - plan.startUtf16))
        ..add(TextOp.insert(plan.startUtf16, plan.insertedText));
      inverse
        ..add(TextOp.delete(plan.startUtf16, plan.insertedText.length))
        ..add(TextOp.insert(plan.startUtf16, plan.removedText));
    }

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '字母转置未应用：${error.code} ${error.detail}');
      }
      return;
    }
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: normalizedSelections.first.extentOffset,
      coalesce: false,
    );
    _setDocSelections(doc, normalizedSelections, recordHistory: false);
    doc.replaceInputWindow(
      normalizedSelections.first.extentOffset,
      selection: normalizedSelections.first,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已转置字母');
  }

  Future<void> _trimTrailingWhitespace() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.diskState == DiskDocumentState.readOnly) {
      if (mounted) setState(() => _statusDetail = '当前文件为只读状态');
      return;
    }
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      return;
    }

    _flushInput(doc);
    final expectedVersion = doc.doc.version;
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty) return;
    late final DocumentDeleteRanges plan;
    final removedTexts = <String>[];
    var deletedBefore = 0;
    var previousEnd = 0;
    try {
      plan = doc.doc.trimTrailingWhitespace();
      if (plan.version != expectedVersion ||
          plan.ranges.length > maxDocTrailingWhitespaceEdits) {
        throw StateError('Rust 返回了过期或超限的行尾空格计划');
      }
      for (final range in plan.ranges) {
        if (range.startUtf16 < previousEnd ||
            range.endUtf16 <= range.startUtf16 ||
            range.endUtf16 > doc.inputWindow.totalUtf16Length) {
          throw StateError('Rust 返回了无效或重叠的 UTF-16 删除范围');
        }
        final removed = _readDocumentRange(
          doc,
          range.startUtf16,
          range.endUtf16,
        );
        if (removed.length != range.endUtf16 - range.startUtf16 ||
            removed.isEmpty ||
            removed.runes.any((rune) => rune != 0x20 && rune != 0x09)) {
          throw StateError('Rust 行尾空格计划与权威全文不一致');
        }
        if (removed.length > _undoHistoryBudget.maxTotalChars - deletedBefore) {
          throw StateError('修剪行尾空格超过撤销文本上限');
        }
        removedTexts.add(removed);
        deletedBefore += removed.length;
        previousEnd = range.endUtf16;
      }
      if (doc.doc.version != expectedVersion) {
        throw StateError('文档版本已变化');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '未修剪行尾空格：$error');
      return;
    }
    if (plan.ranges.isEmpty) return;

    final forward = <TextOp>[
      for (final range in plan.ranges.reversed)
        TextOp.delete(range.startUtf16, range.endUtf16 - range.startUtf16),
    ];
    final inverse = <TextOp>[
      for (var index = 0; index < plan.ranges.length; index++)
        TextOp.insert(plan.ranges[index].startUtf16, removedTexts[index]),
    ];

    int mapOffset(int offset) {
      var deleted = 0;
      for (final range in plan.ranges) {
        if (offset < range.startUtf16) break;
        if (offset <= range.endUtf16) return range.startUtf16 - deleted;
        deleted += range.endUtf16 - range.startUtf16;
      }
      return offset - deleted;
    }

    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection(
          baseOffset: mapOffset(selection.baseOffset),
          extentOffset: mapOffset(selection.extentOffset),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '未修剪行尾空格：${error.code} ${error.detail}');
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
    doc.replaceInputWindow(
      mappedSelections.first.extentOffset,
      selection: mappedSelections.first,
    );
    _setDocSelections(doc, mappedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已修剪行尾空格');
  }

  Future<void> _convertIndentation({required bool insertSpaces}) async {
    final doc = _active;
    if (doc == null) return;
    if (doc.diskState == DiskDocumentState.readOnly) {
      if (mounted) setState(() => _statusDetail = '当前文件为只读状态');
      return;
    }
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      return;
    }

    _flushInput(doc);
    final expectedVersion = doc.doc.version;
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) setState(() => _statusDetail = '缩进转换已取消：选区数超出上限');
      return;
    }

    late final DocumentIndentationPlan plan;
    var payloadUtf16 = 0;
    try {
      plan = doc.doc.convertIndentation(
        insertSpaces: insertSpaces,
        tabSize: doc.tabSize,
      );
      if (plan.version != expectedVersion ||
          plan.insertSpaces != insertSpaces ||
          plan.tabSize != doc.tabSize ||
          doc.doc.version != expectedVersion) {
        throw StateError('Rust 返回了过期的缩进转换计划');
      }
      var previousEnd = 0;
      for (final edit in plan.edits) {
        if (edit.startUtf16 < previousEnd ||
            edit.endUtf16 <= edit.startUtf16 ||
            edit.endUtf16 > doc.inputWindow.totalUtf16Length ||
            edit.endUtf16 - edit.startUtf16 != edit.removedText.length) {
          throw StateError('Rust 返回了无效的缩进转换范围');
        }
        final actual = _readDocumentRange(
          doc,
          edit.startUtf16,
          edit.endUtf16,
        );
        if (actual != edit.removedText ||
            actual.runes.any((rune) => rune != 0x20 && rune != 0x09) ||
            edit.insertedText.runes
                .any((rune) => rune != 0x20 && rune != 0x09)) {
          throw StateError('Rust 缩进转换计划与权威全文不一致');
        }
        payloadUtf16 += actual.length + edit.insertedText.length;
        if (payloadUtf16 > _undoHistoryBudget.maxTotalChars) {
          throw StateError('缩进转换超过撤销文本上限');
        }
        previousEnd = edit.endUtf16;
      }
      if (doc.doc.version != expectedVersion) {
        throw StateError('文档版本已变化');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '未转换缩进：$error');
      return;
    }

    if (plan.edits.isEmpty) {
      doc.insertSpaces = insertSpaces;
      if (mounted) {
        setState(() => _statusDetail = insertSpaces ? '缩进模式：空格' : '缩进模式：制表符');
      }
      return;
    }

    var deltaBefore = 0;
    final mappedStarts = <int>[];
    for (final edit in plan.edits) {
      mappedStarts.add(edit.startUtf16 + deltaBefore);
      deltaBefore += edit.insertedText.length - edit.removedText.length;
    }
    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final edit in plan.edits.reversed) {
      if (edit.removedText.isNotEmpty) {
        forward.add(TextOp.delete(
          edit.startUtf16,
          edit.removedText.length,
        ));
      }
      if (edit.insertedText.isNotEmpty) {
        forward.add(TextOp.insert(edit.startUtf16, edit.insertedText));
      }
    }
    for (var index = plan.edits.length - 1; index >= 0; index--) {
      final edit = plan.edits[index];
      final mappedStart = mappedStarts[index];
      if (edit.insertedText.isNotEmpty) {
        inverse.add(TextOp.delete(mappedStart, edit.insertedText.length));
      }
      if (edit.removedText.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, edit.removedText));
      }
    }

    int mapOffset(int offset) {
      var delta = 0;
      for (final edit in plan.edits) {
        if (offset < edit.startUtf16) break;
        final mappedStart = edit.startUtf16 + delta;
        if (offset <= edit.endUtf16) {
          return mappedStart + edit.insertedText.length;
        }
        delta += edit.insertedText.length - edit.removedText.length;
      }
      return offset + delta;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
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
    if (mappedSelections.isEmpty) return;
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '未转换缩进：${error.code} ${error.detail}');
      }
      return;
    }

    doc.insertSpaces = insertSpaces;
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
    if (mounted) {
      setState(() => _statusDetail = insertSpaces ? '已将缩进转换为空格' : '已将缩进转换为制表符');
    }
  }

  Future<void> _insertFinalNewLine() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.diskState == DiskDocumentState.readOnly) {
      if (mounted) setState(() => _statusDetail = '当前文件为只读状态');
      return;
    }
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      return;
    }

    _flushInput(doc);
    final expectedVersion = doc.doc.version;
    final originalLength = doc.inputWindow.totalUtf16Length;
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineDeleteSelections) {
      if (mounted) setState(() => _statusDetail = '插入末尾换行已取消：选区数超出上限');
      return;
    }
    if (selections.any((selection) =>
        selection.baseOffset < 0 ||
        selection.extentOffset < 0 ||
        selection.baseOffset > originalLength ||
        selection.extentOffset > originalLength)) {
      if (mounted) setState(() => _statusDetail = '插入末尾换行已取消：选区超出文档范围');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '插入末尾换行已取消：文档版本已变化');
      return;
    }

    const eol = '\n';
    final forward = <TextOp>[TextOp.insert(originalLength, eol)];
    final inverse = <TextOp>[TextOp.delete(originalLength, eol.length)];
    final newLength = originalLength + eol.length;
    int mapOffset(int offset) =>
        (offset < originalLength ? offset : offset + eol.length)
            .clamp(0, newLength)
            .toInt();
    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection(
          baseOffset: mapOffset(selection.baseOffset),
          extentOffset: mapOffset(selection.extentOffset),
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
    ]);
    if (mappedSelections.isEmpty) return;

    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on SyncMismatchException catch (error) {
      if (mounted) setState(() => _statusDetail = '未插入末尾换行：$error');
      return;
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '未插入末尾换行：${error.code} ${error.detail}');
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
    if (mounted) setState(() => _statusDetail = '已在文档末尾插入换行');
  }

  Future<void> _toggleLineComment() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      return;
    }

    final languageId =
        doc.path == null ? 'plaintext' : _languageIdOf(doc.path!);
    final lineComment = switch (languageId) {
      'rust' || 'typescript' => '//',
      'python' => '#',
      _ => null,
    };
    if (lineComment == null) {
      if (mounted) setState(() => _statusDetail = '当前语言没有配置行注释符');
      return;
    }

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty || selections.length > maxDocLineCommentSelections) {
      if (mounted && selections.length > maxDocLineCommentSelections) {
        setState(() =>
            _statusDetail = '行注释已取消：选区数超过 $maxDocLineCommentSelections 上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentLineCommentPlan queried;
    try {
      queried = doc.doc.toggleLineComment(
        [
          for (final selection in selections)
            DocumentDeleteRange(
              startUtf16: selection.start,
              endUtf16: selection.end,
            ),
        ],
        lineComment,
      );
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '行注释未应用：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) setState(() => _statusDetail = '行注释未应用：文档同步版本已变化');
      return;
    }
    if (queried.edits.isEmpty) return;

    var payloadChars = 0;
    var previousStart = -1;
    var previousEnd = -1;
    final mappedStarts = <int>[];
    var deltaBefore = 0;
    try {
      for (final edit in queried.edits) {
        if (edit.startUtf16 < 0 ||
            edit.endUtf16 < edit.startUtf16 ||
            edit.endUtf16 > doc.inputWindow.totalUtf16Length ||
            edit.removedText.length != edit.endUtf16 - edit.startUtf16 ||
            edit.startUtf16 < previousEnd ||
            edit.startUtf16 == previousStart) {
          throw StateError('Rust 返回了无效或重叠的 UTF-16 行注释计划');
        }
        if (_readDocumentRange(doc, edit.startUtf16, edit.endUtf16) !=
            edit.removedText) {
          throw StateError('Rust 行注释计划与权威全文不一致');
        }
        payloadChars += edit.removedText.length + edit.insertedText.length;
        if (payloadChars > _undoHistoryBudget.maxTotalChars) {
          throw StateError('撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限');
        }
        mappedStarts.add(edit.startUtf16 + deltaBefore);
        deltaBefore +=
            edit.insertedText.length - (edit.endUtf16 - edit.startUtf16);
        previousStart = edit.startUtf16;
        previousEnd = edit.endUtf16;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '行注释未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '行注释未应用：文档版本已变化');
      return;
    }

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final edit in queried.edits.reversed) {
      if (edit.endUtf16 > edit.startUtf16) {
        forward.add(
            TextOp.delete(edit.startUtf16, edit.endUtf16 - edit.startUtf16));
      }
      if (edit.insertedText.isNotEmpty) {
        forward.add(TextOp.insert(edit.startUtf16, edit.insertedText));
      }
    }
    for (var index = queried.edits.length - 1; index >= 0; index--) {
      final edit = queried.edits[index];
      final mappedStart = mappedStarts[index];
      if (edit.insertedText.isNotEmpty) {
        inverse.add(TextOp.delete(mappedStart, edit.insertedText.length));
      }
      if (edit.removedText.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, edit.removedText));
      }
    }
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '行注释未应用：${error.code} ${error.detail}');
      }
      return;
    }

    int mapOffset(int offset) {
      var delta = 0;
      for (final edit in queried.edits) {
        if (offset < edit.startUtf16) break;
        final mappedStart = edit.startUtf16 + delta;
        if (edit.startUtf16 == edit.endUtf16 && offset == edit.startUtf16) {
          return mappedStart + edit.insertedText.length;
        }
        if (offset <= edit.endUtf16) return mappedStart;
        delta += edit.insertedText.length - (edit.endUtf16 - edit.startUtf16);
      }
      return offset + delta;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
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
    if (mounted) setState(() => _statusDetail = '已切换行注释');
  }

  Future<void> _toggleBlockComment() async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，已保留当前编辑');
      return;
    }

    final languageId =
        doc.path == null ? 'plaintext' : _languageIdOf(doc.path!);
    final tokens = switch (languageId) {
      'rust' ||
      'typescript' ||
      'typescriptreact' ||
      'javascript' ||
      'javascriptreact' =>
        ('/*', '*/'),
      _ => null,
    };
    if (tokens == null) {
      if (mounted) setState(() => _statusDetail = '当前语言没有配置块注释符');
      return;
    }

    _flushInput(doc);
    final selections = normalizeSelectionSet(doc.selectionSet);
    if (selections.isEmpty ||
        selections.length > maxDocBlockCommentSelections) {
      if (mounted && selections.length > maxDocBlockCommentSelections) {
        setState(() => _statusDetail = '块注释已取消：超出选区数量上限');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    late final DocumentBlockCommentPlan queried;
    try {
      queried = doc.doc.toggleBlockComment(
        [
          for (final selection in selections)
            DocumentDeleteRange(
              startUtf16: selection.start,
              endUtf16: selection.end,
            ),
        ],
        tokens.$1,
        tokens.$2,
        insertSpace: true,
      );
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '块注释未应用：${error.code} ${error.detail}');
      }
      return;
    }
    if (queried.version != expectedVersion) {
      doc.replaceInputWindow(doc.selection.extentOffset);
      if (mounted) setState(() => _statusDetail = '块注释未应用：文档同步版本已变化');
      return;
    }
    if (queried.edits.isEmpty) return;
    if (queried.selections.length != selections.length) {
      if (mounted) setState(() => _statusDetail = '块注释未应用：Rust 选择映射数量不匹配');
      return;
    }

    var payloadChars = 0;
    var deltaBefore = 0;
    var previousStart = -1;
    var previousEnd = -1;
    final mappedStarts = <int>[];
    try {
      for (final edit in queried.edits) {
        if (edit.startUtf16 < 0 ||
            edit.endUtf16 < edit.startUtf16 ||
            edit.endUtf16 > doc.inputWindow.totalUtf16Length ||
            edit.removedText.length != edit.endUtf16 - edit.startUtf16 ||
            edit.startUtf16 < previousEnd ||
            edit.startUtf16 == previousStart) {
          throw StateError('Rust 返回了无效或重叠的 UTF-16 块注释计划');
        }
        if (_readDocumentRange(doc, edit.startUtf16, edit.endUtf16) !=
            edit.removedText) {
          throw StateError('Rust 块注释计划与权威全文不一致');
        }
        payloadChars += edit.removedText.length + edit.insertedText.length;
        if (payloadChars > _undoHistoryBudget.maxTotalChars) {
          throw StateError('撤销文本超过预算上限');
        }
        mappedStarts.add(edit.startUtf16 + deltaBefore);
        deltaBefore += edit.insertedText.length - edit.removedText.length;
        previousStart = edit.startUtf16;
        previousEnd = edit.endUtf16;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '块注释未应用：$error');
      return;
    }
    if (doc.doc.version != expectedVersion) {
      if (mounted) setState(() => _statusDetail = '块注释未应用：文档版本已变化');
      return;
    }

    final newLength = doc.inputWindow.totalUtf16Length + deltaBefore;
    final mappedSelections = <TextSelection>[];
    for (final mapped in queried.selections) {
      if (mapped.startUtf16 < 0 ||
          mapped.endUtf16 < mapped.startUtf16 ||
          mapped.endUtf16 > newLength) {
        if (mounted) setState(() => _statusDetail = '块注释未应用：Rust 返回了越界选择');
        return;
      }
      mappedSelections.add(TextSelection(
        baseOffset: mapped.startUtf16,
        extentOffset: mapped.endUtf16,
      ));
    }
    final normalizedSelections = normalizeSelectionSet(mappedSelections);

    final forward = <TextOp>[];
    final inverse = <TextOp>[];
    for (final edit in queried.edits.reversed) {
      if (edit.endUtf16 > edit.startUtf16) {
        forward.add(
            TextOp.delete(edit.startUtf16, edit.endUtf16 - edit.startUtf16));
      }
      if (edit.insertedText.isNotEmpty) {
        forward.add(TextOp.insert(edit.startUtf16, edit.insertedText));
      }
    }
    for (var index = queried.edits.length - 1; index >= 0; index--) {
      final edit = queried.edits[index];
      final mappedStart = mappedStarts[index];
      if (edit.insertedText.isNotEmpty) {
        inverse.add(TextOp.delete(mappedStart, edit.insertedText.length));
      }
      if (edit.removedText.isNotEmpty) {
        inverse.add(TextOp.insert(mappedStart, edit.removedText));
      }
    }
    try {
      doc.doc.applyWith(expectedVersion, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '块注释未应用：${error.code} ${error.detail}');
      }
      return;
    }
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: normalizedSelections.first.extentOffset,
      coalesce: false,
    );
    doc.replaceInputWindow(
      normalizedSelections.first.extentOffset,
      selection: normalizedSelections.first,
    );
    _setDocSelections(doc, normalizedSelections, recordHistory: false);
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已切换块注释');
  }

  Future<void> _transformCase({
    required bool uppercase,
    bool titleCase = false,
    bool camelCase = false,
    bool snakeCase = false,
    bool pascalCase = false,
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
            windowStart =
                (column - maxWordLookupUtf16 ~/ 2).clamp(0, lineLength).toInt();
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
          final inserted = pascalCase
              ? core.transformPascalCaseText(removed)
              : snakeCase
                  ? core.transformSnakeCaseText(removed)
                  : camelCase
                  ? core.transformCamelCaseText(removed)
                  : titleCase
                      ? core.transformTitleCaseText(removed)
                          : core.transformCaseText(removed,
                              uppercase: uppercase);
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

    final mappedRanges = <({
            int start,
            int end,
            String removed,
            String inserted,
            int mappedStart,
    })>[];
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
          final relative =
              (offset - range.start).clamp(0, range.inserted.length).toInt();
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
        () => _statusDetail = pascalCase
            ? '已转换为帕斯卡命名'
            : snakeCase
                ? '已转换为蛇形命名'
                : titleCase
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
            final innerIndentation =
                '$indentation${indentationString(doc.tabSize, tabSize: doc.tabSize, insertSpaces: doc.insertSpaces)}';
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
      final caret =
          (mappedStarts[index] + edit.caretOffset).clamp(0, newLength).toInt();
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
    await _writeEditorClipboardCopy(
      doc,
      text,
      selectionStartUtf16: selection.start,
    );
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

  List<PasteAsOption> _pasteAsOptions(
    EditorPasteAsPayload payload, {
    bool automatic = false,
  }) {
    final options = buildPasteAsOptions(
      plainText: payload.hasPlainText ? payload.text : null,
      html: payload.html,
      uriList: payload.uriList,
      workspaceRoot: _workspaceRoot,
      preferences: widget.pasteAsConfiguration.preferences,
    );
    return automatic
        ? options.where((option) => option.id != 'html').toList(growable: false)
        : options;
  }

  String? _pasteAsProviderId(Object? arguments) {
    if (arguments is String) return arguments;
    if (arguments is Map) {
      final providerId =
          arguments['kind'] ?? arguments['providerId'] ?? arguments['id'];
      return providerId is String ? providerId : null;
    }
    return null;
  }

  List<TextSelection> _pasteSelectionSnapshot(OpenDoc doc) =>
      doc.crossWindowSelection == null
          ? normalizeSelectionSet([doc.selection, ...doc.additionalSelections])
          : [doc.crossWindowSelection!];

  bool _pasteSelectionSnapshotMatches(
    OpenDoc doc,
    List<TextSelection> expected, {
    required bool crossWindow,
  }) {
    if (crossWindow) {
      return expected.length == 1 &&
          doc.crossWindowSelection == expected.single;
    }
    return doc.crossWindowSelection == null &&
        listEquals(
          normalizeSelectionSet([doc.selection, ...doc.additionalSelections]),
          expected,
        );
  }

  Future<void> _pasteAs({String? providerId}) async {
    if (!widget.pasteAsConfiguration.enabled) return;
    _lastPasteAsSession = null;
    final doc = _active;
    if (doc == null || doc.diskState == DiskDocumentState.readOnly) return;
    _flushInput(doc, commitComposition: true);
    final expectedVersion = doc.doc.version;
    final expectedFocus = FocusManager.instance.primaryFocus;
    final selections = List<TextSelection>.unmodifiable(
      _pasteSelectionSnapshot(doc),
    );
    final wasCrossWindow = doc.crossWindowSelection != null;
    if (selections.isEmpty || doc.inputWindow.hasComposition) return;

    final payload = await EditorClipboard.readForPasteAs();
    if (!mounted ||
        payload == null ||
        !identical(_active, doc) ||
        doc.doc.version != expectedVersion ||
        FocusManager.instance.primaryFocus != expectedFocus ||
        !_pasteSelectionSnapshotMatches(
          doc,
          selections,
          crossWindow: wasCrossWindow,
        )) {
      return;
    }
    final options = _pasteAsOptions(payload);
    if (providerId case final requested?) {
      final option = options
          .where((item) => item.id == requested || item.kind == requested)
          .firstOrNull;
      if (option != null) {
        await _applyPasteAsOption(
          doc,
          option,
          payload: payload,
          expectedVersion: expectedVersion,
          selections: selections,
          wasCrossWindow: wasCrossWindow,
        );
      }
      return;
    }
    if (options.isEmpty) {
      if (mounted) setState(() => _statusDetail = '剪贴板没有可用的粘贴格式');
      return;
    }
    await _showPasteAsSelector(
      doc,
      payload: payload,
      options: options,
      expectedVersion: expectedVersion,
      selections: selections,
      wasCrossWindow: wasCrossWindow,
    );
  }

  Future<void> _pasteAsText() async {
    if (!widget.pasteAsConfiguration.enabled) return;
    _lastPasteAsSession = null;
    final doc = _active;
    if (doc == null || doc.diskState == DiskDocumentState.readOnly) return;
    _flushInput(doc, commitComposition: true);
    final expectedVersion = doc.doc.version;
    final expectedFocus = FocusManager.instance.primaryFocus;
    final selections = List<TextSelection>.unmodifiable(
      _pasteSelectionSnapshot(doc),
    );
    final wasCrossWindow = doc.crossWindowSelection != null;
    final payload = await EditorClipboard.readForPasteAs();
    if (!mounted ||
        payload == null ||
        !payload.hasPlainText ||
        !identical(_active, doc) ||
        doc.doc.version != expectedVersion ||
        FocusManager.instance.primaryFocus != expectedFocus ||
        !_pasteSelectionSnapshotMatches(
          doc,
          selections,
          crossWindow: wasCrossWindow,
        )) {
      return;
    }
    await _applyPasteAsOption(
      doc,
      PasteAsOption(
        id: 'text',
        kind: 'text.plain',
        label: 'Insert Plain Text',
        text: payload.text,
      ),
      payload: payload,
      expectedVersion: expectedVersion,
      selections: selections,
      wasCrossWindow: wasCrossWindow,
    );
  }

  Future<void> _pasteDefault(OpenDoc doc) async {
    if (doc.diskState == DiskDocumentState.readOnly) {
      return;
    }
    _lastPasteAsSession = null;
    _flushInput(doc, commitComposition: true);
    final expectedVersion = doc.doc.version;
    final expectedFocus = FocusManager.instance.primaryFocus;
    final selections = List<TextSelection>.unmodifiable(
      _pasteSelectionSnapshot(doc),
    );
    final wasCrossWindow = doc.crossWindowSelection != null;
    final payload = widget.pasteAsConfiguration.enabled
        ? await EditorClipboard.readForPasteAs()
        : await EditorClipboard.read().then(
            (plainText) => plainText == null
                ? null
                : EditorPasteAsPayload.fromPlainText(plainText),
          );
    if (!mounted ||
        payload == null ||
        !identical(_active, doc) ||
        doc.doc.version != expectedVersion ||
        FocusManager.instance.primaryFocus != expectedFocus ||
        !_pasteSelectionSnapshotMatches(
          doc,
          selections,
          crossWindow: wasCrossWindow,
        )) {
      return;
    }
    final options = _pasteAsOptions(payload, automatic: true);
    if (options.isEmpty) return;
    await _applyPasteAsOption(
      doc,
      options.first,
      payload: payload,
      expectedVersion: expectedVersion,
      selections: selections,
      wasCrossWindow: wasCrossWindow,
    );
  }

  Future<void> _showPasteAsSelector(
    OpenDoc doc, {
    required EditorPasteAsPayload payload,
    required List<PasteAsOption> options,
    required int expectedVersion,
    required List<TextSelection> selections,
    required bool wasCrossWindow,
    Future<void> Function(PasteAsOption option)? onSelect,
  }) async {
    if (options.isEmpty || !mounted) return;
    _pasteSelectorOpen = true;
    try {
      await QuickInput.show(
        context,
        hint: '选择粘贴格式',
        items: [
          for (final option in options)
            QuickItem(
              label: option.label,
              detail: option.id,
              onRun: () async {
                if (onSelect != null) {
                  await onSelect(option);
                } else {
                  await _applyPasteAsOption(
                    doc,
                    option,
                    payload: payload,
                    expectedVersion: expectedVersion,
                    selections: selections,
                    wasCrossWindow: wasCrossWindow,
                  );
                }
              },
            ),
        ],
      );
    } finally {
      _pasteSelectorOpen = false;
    }
  }

  Future<_PasteAsSession?> _applyPasteAsOption(
    OpenDoc doc,
    PasteAsOption option, {
    required EditorPasteAsPayload payload,
    required int expectedVersion,
    required List<TextSelection> selections,
    required bool wasCrossWindow,
  }) async {
    _flushInput(doc, commitComposition: true);
    if (!mounted ||
        !identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.inputWindow.hasComposition ||
        doc.doc.version != expectedVersion ||
        !_pasteSelectionSnapshotMatches(
          doc,
          selections,
          crossWindow: wasCrossWindow,
        )) {
      return null;
    }
    if (option.text.isEmpty) return null;
    if (option.text.length > maxPasteAsPlainTextUtf16) {
      if (mounted) setState(() => _statusDetail = '粘贴内容超过安全上限，已取消');
      return null;
    }

    if (wasCrossWindow) {
      _replaceCrossWindowSelection(
        doc,
        option.text,
        version: expectedVersion,
      );
      if (doc.doc.version == expectedVersion) return null;
      final after =
          List<TextSelection>.unmodifiable(_pasteSelectionSnapshot(doc));
      return _lastPasteAsSession = _PasteAsSession(
        documentId: doc.id,
        version: doc.doc.version,
        payload: payload,
        beforeSelections: selections,
        afterSelections: after,
        providerId: option.id,
        wasCrossWindow: true,
      );
    }

    final normalized = normalizeSelectionSet(selections);
    if (normalized.isEmpty) return null;
    final multiCursorText =
        option.id == 'text' ? payload.metadata?.multiCursorText : null;
    final pasteTexts = distributeClipboardPasteText(
      clipboardText: option.text,
      selectionCount: normalized.length,
      multiCursorText: multiCursorText,
      selectionStartOffsets: [
        for (final selection in normalized) selection.start,
      ],
    );
    final plans = <({
      int start,
      int end,
      String text,
      String removed,
      int mappedStart,
      bool primary,
    })>[];
    final orderedSelections = [
      for (var index = 0; index < normalized.length; index++)
        (index: index, selection: normalized[index]),
    ]..sort((a, b) => a.selection.start.compareTo(b.selection.start));
    var shift = 0;
    try {
      for (final entry in orderedSelections) {
        final index = entry.index;
        final selection = entry.selection;
        final start = selection.start;
        final end = selection.end;
        final removed = _readDocumentRange(doc, start, end);
        plans.add((
          start: start,
          end: end,
          text: pasteTexts[index],
          removed: removed,
          mappedStart: start + shift,
          primary: index == 0,
        ));
        shift += pasteTexts[index].length - (end - start);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = 'Paste As 范围读取失败：$error');
      return null;
    }
    if (doc.doc.version != expectedVersion ||
        !_pasteSelectionSnapshotMatches(doc, selections, crossWindow: false)) {
      return null;
    }

    final operationChars = plans.fold<int>(
      0,
      (total, plan) => total + plan.removed.length + plan.text.length,
    );
    if (operationChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) setState(() => _statusDetail = '粘贴内容超过撤销历史上限，已取消');
      return null;
    }
    final forward = [
      for (final plan in plans.reversed) ...[
        if (plan.end > plan.start)
          TextOp.delete(plan.start, plan.end - plan.start),
        if (plan.text.isNotEmpty) TextOp.insert(plan.start, plan.text),
      ],
    ];
    if (forward.isEmpty) return null;
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
        setState(
            () => _statusDetail = 'Paste As 未应用：${error.code} ${error.detail}');
      }
      return null;
    }

    final orderedAfter = [
      for (final plan in plans)
        (
          primary: plan.primary,
          selection: TextSelection.collapsed(
            offset: plan.mappedStart + plan.text.length,
          ),
        ),
    ];
    final primaryIndex = orderedAfter.indexWhere((entry) => entry.primary);
    final afterSelections = List<TextSelection>.unmodifiable([
      if (primaryIndex >= 0) orderedAfter[primaryIndex].selection,
      for (var index = 0; index < orderedAfter.length; index++)
        if (index != primaryIndex) orderedAfter[index].selection,
    ]);
    final primarySelection = afterSelections.first;
    _recordDocumentOperations(
      doc,
      forward: forward,
      inverse: inverse,
      beforeCaret: selections.first.extentOffset,
      afterCaret: primarySelection.extentOffset,
      coalesce: false,
    );
    doc.additionalSelections = List.unmodifiable(afterSelections.skip(1));
    doc.columnSelection = null;
    doc.crossWindowSelection = null;
    doc.replaceInputWindow(
      primarySelection.extentOffset,
      selection: primarySelection,
    );
    _refreshSiblingViews(doc, forward);
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() => _statusDetail = '已粘贴：${option.label}');
    return _lastPasteAsSession = _PasteAsSession(
      documentId: doc.id,
      version: doc.doc.version,
      payload: payload,
      beforeSelections: List<TextSelection>.unmodifiable(selections),
      afterSelections: afterSelections,
      providerId: option.id,
      wasCrossWindow: false,
    );
  }

  Future<void> _changePasteType({String? providerId}) async {
    if (!widget.pasteAsConfiguration.enabled) return;
    final session = _lastPasteAsSession;
    final doc = _active;
    if (session == null || doc == null || session.documentId != doc.id) {
      await _pasteAs(providerId: providerId);
      return;
    }
    if (doc.doc.version != session.version ||
        !_pasteSelectionSnapshotMatches(
          doc,
          session.afterSelections,
          crossWindow: false,
        )) {
      _lastPasteAsSession = null;
      await _pasteAs(providerId: providerId);
      return;
    }
    final options = _pasteAsOptions(session.payload);
    if (options.isEmpty) return;
    if (providerId case final requested?) {
      final option = options
          .where((item) => item.id == requested || item.kind == requested)
          .firstOrNull;
      if (option != null) await _changePasteAsProvider(session, option);
      return;
    }
    await _showPasteAsSelector(
      doc,
      payload: session.payload,
      options: options,
      expectedVersion: session.version,
      selections: session.afterSelections,
      wasCrossWindow: false,
      onSelect: (option) => _changePasteAsProvider(session, option),
    );
  }

  Future<void> _changePasteAsProvider(
    _PasteAsSession session,
    PasteAsOption option,
  ) async {
    if (session.providerId == option.id) return;
    final doc = _active;
    if (doc == null ||
        doc.id != session.documentId ||
        doc.doc.version != session.version ||
        !_pasteSelectionSnapshotMatches(
          doc,
          session.afterSelections,
          crossWindow: false,
        )) {
      _lastPasteAsSession = null;
      return;
    }
    _undo();
    if (!mounted || !identical(_active, doc)) return;
    if (session.wasCrossWindow) {
      doc.crossWindowSelection = session.beforeSelections.single;
    } else {
      doc.crossWindowSelection = null;
      doc.additionalSelections =
          List.unmodifiable(session.beforeSelections.skip(1));
      doc.columnSelection = null;
      doc.replaceInputWindow(
        session.beforeSelections.first.extentOffset,
        selection: session.beforeSelections.first,
      );
    }
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await _applyPasteAsOption(
      doc,
      option,
      payload: session.payload,
      expectedVersion: doc.doc.version,
      selections: session.beforeSelections,
      wasCrossWindow: session.wasCrossWindow,
    );
  }

  Future<void> _hidePasteWidget() async {
    if (_pasteSelectorOpen && mounted) {
      await Navigator.of(context).maybePop();
    }
    if (mounted && _lastPasteAsSession != null) {
      setState(() => _lastPasteAsSession = null);
    }
  }

  bool _shouldShowPasteAsWidget(EditorGroup group) {
    final session = _lastPasteAsSession;
    final doc = group.active;
    return widget.pasteAsConfiguration.enabled &&
        widget.pasteAsConfiguration.showPasteSelector == 'afterPaste' &&
        session != null &&
        doc != null &&
        identical(_active, doc) &&
        session.documentId == doc.id &&
        session.version == doc.doc.version &&
        _pasteSelectionSnapshotMatches(
          doc,
          session.afterSelections,
          crossWindow: false,
        ) &&
        _pasteAsOptions(session.payload, automatic: true).length > 1;
  }

  Future<void> _pasteCrossWindowSelection(OpenDoc doc) async {
    final selection = doc.crossWindowSelection;
    if (selection == null) return;
    _flushInput(doc, commitComposition: true);
    final version = doc.doc.version;
    final clipboard = await EditorClipboard.read();
    if (!mounted ||
        clipboard == null ||
        doc.doc.version != version ||
        doc.crossWindowSelection != selection) {
      return;
    }
    _replaceCrossWindowSelection(
      doc,
      clipboard.text,
      version: version,
    );
  }

  Future<void> _copyMultiSelections(OpenDoc doc) async {
    _flushInput(doc);
    if (!identical(_active, doc) ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        doc.additionalSelections.isEmpty) {
      return;
    }

    final selections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (selections.length < 2) return;
    final version = doc.doc.version;
    final documentEol = doc.fileOptions.lineEnding.id == 'crlf' ? '\r\n' : '\n';
    final forceCrLf = defaultTargetPlatform == TargetPlatform.windows;
    final lineEol = forceCrLf ? '\r\n' : documentEol;
    final copied = _copyableDocumentSelectionTexts(
      doc,
      selections,
      version: version,
      lineEol: lineEol,
      forceCrLf: forceCrLf,
    );
    final currentSelections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (copied == null ||
        doc.doc.version != version ||
        !identical(_active, doc) ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        !listEquals(selections, currentSelections)) {
      return;
    }
    final clipboardText = copied.join(documentEol);
    await _writeEditorClipboardCopy(
      doc,
      clipboardText,
      selectionStartUtf16: selections.first.start,
      includeHtml: false,
      multiCursorText: copied,
    );
  }

  Future<void> _copyEmptySelectionLine(OpenDoc doc) async {
    _flushInput(doc);
    final selection = doc.selection;
    if (!selection.isCollapsed || doc.additionalSelections.isNotEmpty) return;

    final version = doc.doc.version;
    final line = doc.doc.lineBoundary(selection.extentOffset);
    if (line.version != version) return;
    final text = _readDocumentRange(doc, line.startUtf16, line.endUtf16);
    if (doc.doc.version != version) return;

    final eol = defaultTargetPlatform == TargetPlatform.windows ||
            doc.fileOptions.lineEnding.id == 'crlf'
        ? '\r\n'
        : '\n';
    final clipboardText = '$text$eol';
    await _writeEditorClipboardCopy(
      doc,
      clipboardText,
      selectionStartUtf16: line.startUtf16,
      htmlText: _richHtmlForCopy(doc, text, line.startUtf16),
      isFromEmptySelection: true,
    );
  }

  Future<void> _copySingleSelection(OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final selection = doc.selection;
    if (!identical(_active, doc) ||
        selection.isCollapsed ||
        doc.additionalSelections.isNotEmpty ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition) {
      return;
    }
    final version = doc.doc.version;
    final text = _readDocumentRange(doc, selection.start, selection.end);
    if (doc.doc.version != version ||
        !identical(_active, doc) ||
        doc.selection != selection ||
        doc.additionalSelections.isNotEmpty ||
        doc.inputWindow.hasComposition) {
      return;
    }
    await _writeEditorClipboardCopy(
      doc,
      text,
      selectionStartUtf16: selection.start,
    );
  }

  Future<void> _cutSingleSelection(OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final selection = doc.selection;
    if (!identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        selection.isCollapsed ||
        doc.additionalSelections.isNotEmpty ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition) {
      return;
    }
    final version = doc.doc.version;
    final text = _readDocumentRange(doc, selection.start, selection.end);
    if (doc.doc.version != version) return;
    try {
      await _writeEditorClipboardCopy(
        doc,
        text,
        selectionStartUtf16: selection.start,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '剪切未执行：剪贴板写入失败：$error');
      return;
    }

    final field = doc.inputFieldKey.currentState;
    final oldValue = doc.editingValue;
    final windowStart = doc.inputWindow.startUtf16;
    final localStart = selection.start - windowStart;
    final localEnd = selection.end - windowStart;
    if (!mounted ||
        !identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.doc.version != version ||
        doc.selection != selection ||
        doc.additionalSelections.isNotEmpty ||
        doc.inputWindow.hasComposition ||
        field == null ||
        localStart < 0 ||
        localEnd < localStart ||
        localEnd > oldValue.text.length ||
        oldValue.text.substring(localStart, localEnd) != text) {
      return;
    }
    field.setEditingValue(TextEditingValue(
      text: oldValue.text.replaceRange(localStart, localEnd, ''),
      selection: TextSelection.collapsed(offset: localStart),
      composing: TextRange.empty,
    ));
    doc.columnSelection = null;
    _flushInput(doc);
  }

  Future<void> _cutEmptySelectionLine(OpenDoc doc) async {
    _flushInput(doc);
    final selection = doc.selection;
    if (!identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        !selection.isCollapsed ||
        doc.additionalSelections.isNotEmpty) {
      return;
    }

    final version = doc.doc.version;
    final line = doc.doc.lineBoundary(selection.extentOffset);
    if (line.version != version) return;
    final text = _readDocumentRange(doc, line.startUtf16, line.endUtf16);
    if (doc.doc.version != version) return;

    final eol = defaultTargetPlatform == TargetPlatform.windows ||
            doc.fileOptions.lineEnding.id == 'crlf'
        ? '\r\n'
        : '\n';
    final clipboardText = '$text$eol';
    await _writeEditorClipboardCopy(
      doc,
      clipboardText,
      selectionStartUtf16: line.startUtf16,
      htmlText: _richHtmlForCopy(doc, text, line.startUtf16),
      isFromEmptySelection: true,
    );

    if (!mounted ||
        !identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.doc.version != version ||
        doc.selection != selection ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        doc.additionalSelections.isNotEmpty) {
      return;
    }
    await _deleteLines();
  }

  Future<bool> _pasteMultiSelections(OpenDoc doc) async {
    if (doc.additionalSelections.isEmpty) return false;
    _flushInput(doc, commitComposition: true);
    final clipboard = await EditorClipboard.read();
    if (clipboard == null || !mounted || _active?.id != doc.id) return false;
    final clipboardText = clipboard.text;
    final clipboardMetadata = clipboard.metadata;
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
      clipboardText: clipboardText,
      multiCursorText: clipboardMetadata?.multiCursorText,
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

    final clipboard = await EditorClipboard.read();
    if (!mounted ||
        clipboard == null ||
        _active?.id != doc.id ||
        doc.doc.version != expectedVersion ||
        !selectionSetUnchanged()) {
      return;
    }
    final clipboardText = clipboard.text;
    final clipboardMetadata = clipboard.metadata;
    if (clipboardText.isEmpty) return;

    final pasteTexts = distributeClipboardPasteText(
      clipboardText: clipboardText,
      selectionCount: selections.length,
      multiCursorText: clipboardMetadata?.multiCursorText,
      selectionStartOffsets: [
        for (final selection in selections) selection.start
      ],
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
    _flushInput(doc);
    if (!identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition) {
      return false;
    }
    final selections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (selections.length < 2) return false;
    if (selections.length > maxDocLineDeleteSelections) {
      if (mounted) {
        setState(() =>
            _statusDetail = '多光标剪切已取消：选区数超过 $maxDocLineDeleteSelections 上限');
      }
      return false;
    }

    final version = doc.doc.version;
    final documentStart = doc.doc.lineOffset(0);
    if (documentStart.version != version) return false;

    final deleteRanges = <({int start, int end})>[];
    try {
      for (final selection in selections) {
        late final int start;
        late final int end;
        if (selection.isCollapsed) {
          final position = doc.doc.positionAt(selection.extentOffset);
          final line = doc.doc.lineBoundary(selection.extentOffset);
          if (position.version != version || line.version != version) {
            throw StateError('文档版本在解析多光标剪切范围时发生变化');
          }
          if (position.line + 1 < documentStart.lineCount) {
            final nextLine = doc.doc.lineOffset(position.line + 1);
            if (nextLine.version != version) {
              throw StateError('文档版本在解析多光标剪切行尾时发生变化');
            }
            start = line.startUtf16;
            end = nextLine.offsetUtf16;
          } else if (position.line > 0) {
            final previousLine = doc.doc.lineOffset(position.line - 1);
            if (previousLine.version != version) {
              throw StateError('文档版本在解析多光标剪切行首时发生变化');
            }
            final previousBoundary =
                doc.doc.lineBoundary(previousLine.offsetUtf16);
            if (previousBoundary.version != version) {
              throw StateError('文档版本在解析多光标剪切行首时发生变化');
            }
            start = previousBoundary.endUtf16;
            end = documentStart.totalUtf16Length;
          } else {
            start = line.startUtf16;
            end = documentStart.totalUtf16Length;
          }
        } else {
          start = selection.start;
          end = selection.end;
        }
        if (start < 0 || end < start || end > documentStart.totalUtf16Length) {
          throw StateError('Rust 返回了无效的多光标剪切范围');
        }
        if (start != end) deleteRanges.add((start: start, end: end));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '多光标剪切未应用：$error');
      return false;
    }

    deleteRanges.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    final mergedRanges = <({int start, int end})>[];
    for (final range in deleteRanges) {
      if (mergedRanges.isEmpty || range.start > mergedRanges.last.end) {
        mergedRanges.add(range);
      } else if (range.end > mergedRanges.last.end) {
        final previous = mergedRanges.removeLast();
        mergedRanges.add((start: previous.start, end: range.end));
      }
    }

    final plans = <({int start, int end, String removed, int mappedStart})>[];
    var deletedUtf16 = 0;
    try {
      for (final range in mergedRanges) {
        final removedLength = range.end - range.start;
        if (removedLength > _undoHistoryBudget.maxTotalChars - deletedUtf16) {
          throw StateError(
            '多光标剪切撤销文本超过 ${_undoHistoryBudget.maxTotalChars} 字符上限',
          );
        }
        final removed = _readDocumentRange(doc, range.start, range.end);
        if (doc.doc.version != version) {
          throw StateError('文档版本在读取多光标剪切文本时发生变化');
        }
        plans.add((
          start: range.start,
          end: range.end,
          removed: removed,
          mappedStart: range.start - deletedUtf16,
        ));
        deletedUtf16 += removedLength;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '多光标剪切未应用：$error');
      return false;
    }

    final documentEol = doc.fileOptions.lineEnding.id == 'crlf' ? '\r\n' : '\n';
    final forceCrLf = defaultTargetPlatform == TargetPlatform.windows;
    final copied = _copyableDocumentSelectionTexts(
      doc,
      selections,
      version: version,
      lineEol: forceCrLf ? '\r\n' : documentEol,
      forceCrLf: forceCrLf,
    );
    final currentSelections = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (copied == null ||
        doc.doc.version != version ||
        !identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        !listEquals(selections, currentSelections)) {
      return false;
    }

    try {
      final clipboardText = copied.join(documentEol);
      await _writeEditorClipboardCopy(
        doc,
        clipboardText,
        selectionStartUtf16: selections.first.start,
        includeHtml: false,
        multiCursorText: copied,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _statusDetail = '多光标剪切未应用：$error');
      return false;
    }
    final selectionsAfterClipboard = normalizeSelectionSet([
      doc.selection,
      ...doc.additionalSelections,
    ]);
    if (!mounted ||
        !identical(_active, doc) ||
        doc.diskState == DiskDocumentState.readOnly ||
        doc.doc.version != version ||
        doc.crossWindowSelection != null ||
        doc.inputWindow.hasComposition ||
        !listEquals(selections, selectionsAfterClipboard)) {
      return false;
    }
    if (plans.isEmpty) return true;

    final forward = [
      for (final plan in plans.reversed)
        TextOp.delete(plan.start, plan.end - plan.start),
    ];
    final inverse = [
      for (final plan in plans.reversed)
        TextOp.insert(plan.mappedStart, plan.removed),
    ];
    try {
      doc.doc.applyWith(version, forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '多光标剪切未应用：${error.code} ${error.detail}');
      }
      return false;
    }

    int mapCaret(int offset) {
      var deletedBefore = 0;
      for (final plan in plans) {
        if (offset < plan.start) return offset - deletedBefore;
        if (offset <= plan.end) return plan.mappedStart;
        deletedBefore += plan.end - plan.start;
      }
      return offset - deletedBefore;
    }

    final mappedSelections = normalizeSelectionSet([
      for (final selection in selections)
        TextSelection.collapsed(
          offset: mapCaret(
            selection.isCollapsed ? selection.extentOffset : selection.start,
          ),
          affinity: selection.affinity,
        ),
    ]);
    if (mappedSelections.isEmpty) return false;
    doc.columnSelection = null;
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
    if (mounted) setState(() => _statusDetail = '已多光标剪切');
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

  AlulaMergeConflict? _mergeConflictAtSelection(OpenDoc doc) {
    final session = doc.mergeResultSession;
    if (session == null ||
        session.isDisposed ||
        session.hasStaleConflictRanges) {
      return null;
    }

    final selection = doc.selection;
    for (final conflict in session.conflicts) {
      final start = conflict.resultStartUtf16;
      final end = conflict.resultEndUtf16;
      if (selection.isCollapsed) {
        final offset = selection.extentOffset;
        if (start == end ? offset == start : offset >= start && offset < end) {
          return conflict;
        }
      } else if (start == end
          ? selection.start <= start && selection.end >= start
          : selection.start < end && selection.end > start) {
        return conflict;
      }
    }
    return null;
  }

  void _navigateMergeConflict(OpenDoc? doc, {required bool forward}) {
    if (doc == null || _disposing) return;
    final session = doc.mergeResultSession;
    if (session == null ||
        session.isDisposed ||
        session.hasStaleConflictRanges) {
      return;
    }

    final conflicts = session.conflicts;
    final resolutions = session.resolutions;
    final unresolved = <AlulaMergeConflict>[];
    final unresolvedIndices = <int>[];
    for (var index = 0; index < conflicts.length; index++) {
      final conflict = conflicts[index];
      if (conflict.isCombination || resolutions.containsKey(conflict.id)) {
        continue;
      }
      unresolved.add(conflict);
      unresolvedIndices.add(index);
    }
    if (unresolved.isEmpty) return;

    final active = _mergeConflictAtSelection(doc);
    final activeIndex = active == null
        ? -1
        : conflicts.indexWhere((conflict) => conflict.id == active.id);
    final caret = doc.selection.extentOffset;
    AlulaMergeConflict? target;
    if (forward) {
      for (var index = 0; index < unresolved.length; index++) {
        final conflict = unresolved[index];
        final conflictIndex = unresolvedIndices[index];
        if (activeIndex >= 0
            ? conflictIndex > activeIndex
            : conflict.resultStartUtf16 > caret) {
          target = conflict;
          break;
        }
      }
      target ??= unresolved.first;
    } else {
      for (var index = unresolved.length - 1; index >= 0; index--) {
        final conflict = unresolved[index];
        final conflictIndex = unresolvedIndices[index];
        if (activeIndex >= 0
            ? conflictIndex < activeIndex
            : conflict.resultStartUtf16 < caret) {
          target = conflict;
          break;
        }
      }
      target ??= unresolved.last;
    }

    _setDocSelections(
      doc,
      [TextSelection.collapsed(offset: target.resultStartUtf16)],
      recordHistory: false,
    );
  }

  void _acceptActiveMergeConflict(AlulaMergeSide side) {
    final doc = _active;
    if (doc != null) _acceptMergeConflict(doc, side);
  }

  void _acceptAllActiveMergeConflicts(AlulaMergeSide side) {
    final doc = _active;
    if (doc != null) _acceptAllMergeConflicts(doc, side);
  }

  void _acceptAllActiveMergeCombinations() {
    final doc = _active;
    if (doc != null) _acceptAllMergeCombinations(doc);
  }

  bool _acceptAllMergeConflicts(OpenDoc doc, AlulaMergeSide side) {
    final session = doc.mergeResultSession;
    if (session == null ||
        session.isDisposed ||
        session.hasStaleConflictRanges ||
        session.conflictCount == 0) {
      return false;
    }

    try {
      final plan = session.planAcceptAll(side);
      if (!_applyMergeResultPlan(doc, plan)) return false;
      _syncCommandContext();
      return true;
    } on MergeResultSessionException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '合并冲突未应用：${error.detail}');
      }
      return false;
    }
  }

  bool _acceptAllMergeCombinations(OpenDoc doc) {
    final session = doc.mergeResultSession;
    if (session == null ||
        session.isDisposed ||
        session.hasStaleConflictRanges ||
        session.unresolvedConflictCount == 0) {
      return false;
    }

    try {
      final plan = session.planAcceptAllCombinations();
      if (plan == null || !_applyMergeResultPlan(doc, plan)) return false;
      _syncCommandContext();
      return true;
    } on MergeResultSessionException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '合并冲突未应用：${error.detail}');
      }
      return false;
    } on AlulaMergeException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '智能组合失败：${error.code}');
      }
      return false;
    }
  }

  Future<void> _acceptActiveMergeResult() async {
    final doc = _active;
    if (doc != null) await _acceptMergeResult(doc);
  }

  Future<void> _acceptMergeResult(OpenDoc doc) async {
    final session = doc.mergeResultSession;
    final owner = _ownerOfView(doc);
    if (_disposing ||
        !mounted ||
        session == null ||
        session.isDisposed ||
        owner == null ||
        !_mergeAcceptInProgress.add(doc.id)) {
      return;
    }

    try {
      var confirmedWithConflicts = false;
      var prompt = session.closePrompt;
      if (prompt.unresolvedConflictCount > 0) {
        if (!await _confirmMergeAcceptWithConflicts(doc)) return;
        confirmedWithConflicts = true;
      }
      if (!mounted ||
          session.isDisposed ||
          !identical(doc.mergeResultSession, session) ||
          !owner.docs.any((view) => identical(view, doc))) {
        return;
      }

      // Commit any pending IME composition before taking the version checked by
      // finishAccept. A newly exposed conflict gets its own confirmation.
      for (final view in _viewsOf(doc).toList(growable: false)) {
        _flushInput(view, commitComposition: true);
      }
      prompt = session.closePrompt;
      if (prompt.unresolvedConflictCount > 0 && !confirmedWithConflicts) {
        if (!await _confirmMergeAcceptWithConflicts(doc)) return;
        confirmedWithConflicts = true;
      }
      if (!mounted || session.isDisposed) return;

      final outcome = await session.finishAccept(
        confirmedWithConflicts: confirmedWithConflicts,
        save: () async {
          if (doc.path == null) {
            await _saveAsDoc(doc);
          } else {
            await _saveDocToPath(doc, doc.path!);
          }
          return mounted &&
              !doc.doc.isDirty &&
              doc.diskState == DiskDocumentState.current;
        },
        closeResultDocument: () async {
          if (mounted) _closeDocNow(owner, doc);
        },
      );
      if (outcome == MergeResultCloseOutcome.closed) {
        // The accepted session is disposed after the close callback. Refresh
        // contexts once more so a surviving split view becomes a plain editor.
        _syncCommandContext();
        return;
      }
      if (outcome == MergeResultCloseOutcome.cancelled || !mounted) return;
      setState(() {
        _statusDetail = switch (outcome) {
          MergeResultCloseOutcome.saveFailed => '合并结果未成功保存，编辑器保持打开',
          MergeResultCloseOutcome.resultChangedDuringSave =>
            '保存期间合并结果发生变化，编辑器保持打开',
          _ => '完成合并未成功，编辑器保持打开',
        };
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '完成合并失败，编辑器保持打开：$error');
      }
    } finally {
      _mergeAcceptInProgress.remove(doc.id);
    }
  }

  Future<bool> _confirmMergeAcceptWithConflicts(OpenDoc doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('merge-editor-accept-merge-dialog'),
        title: const Text('完成合并？'),
        content: Text('是否完成“${doc.name}”的合并？文件中仍有未解决的冲突。'),
        actions: [
          TextButton(
            key: const ValueKey('merge-editor-accept-merge-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续合并'),
          ),
          FilledButton(
            key: const ValueKey('merge-editor-accept-merge-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('仍有冲突也完成合并'),
          ),
        ],
      ),
    );
    return mounted && confirmed == true;
  }

  bool _acceptMergeConflict(OpenDoc doc, AlulaMergeSide side) {
    final session = doc.mergeResultSession;
    final conflict = _mergeConflictAtSelection(doc);
    if (session == null || conflict == null || conflict.isCombination) {
      return false;
    }
    if (session.resolutions[conflict.id] == side) return false;

    try {
      final plan = session.planResolveConflict(conflict.id, side);
      if (!_applyMergeResultPlan(doc, plan)) return false;
      for (final updated in session.conflicts) {
        if (updated.id != conflict.id) continue;
        _setDocSelections(
          doc,
          [TextSelection.collapsed(offset: updated.resultStartUtf16)],
          recordHistory: false,
        );
        break;
      }
      _syncCommandContext();
      return true;
    } on MergeResultSessionException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '合并冲突未应用：${error.detail}');
      }
      return false;
    }
  }

  bool _applyMergeResultPlan(OpenDoc doc, MergeResultEditPlan plan) {
    final session = doc.mergeResultSession;
    if (session == null || session.isDisposed) return false;

    for (final view in _viewsOf(doc).toList(growable: false)) {
      _flushInput(view, commitComposition: true);
    }

    try {
      session.validatePlan(plan);
      final nextText = plan.projection.result;
      _applyProgrammaticEdit(
        doc,
        nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        operations: plan.operations,
        reconcileMergeSession: false,
      );
      session.applyPlan(plan, appliedVersion: doc.doc.resync().version);
      return true;
    } on MergeResultSessionException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '合并计划未应用：${error.detail}');
      }
      return false;
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '合并计划应用失败：${error.code}');
      }
      return false;
    }
  }

  void _applyProgrammaticEdit(
    OpenDoc doc,
    String newText, {
    required TextSelection selection,
    List<TextOp>? operations,
    bool reconcileMergeSession = true,
    bool clearHistory = false,
    bool markSaved = false,
  }) {
    _flushInput(doc, commitComposition: true);
    doc.additionalSelections = const [];
    doc.columnSelection = null;
    final before = doc.doc.resync().content;
    final oldSelection = doc.selection;
    final ops = operations ?? diffToOps(before, newText);
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
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    _scheduleSyntaxRefresh(doc.id);
    if (reconcileMergeSession) {
      doc.mergeResultSession?.reconcileCurrentResult(
        allowKnownProjectionRestore: false,
      );
    }
    _syncCommandContext();
    if (mounted) setState(() {});
  }

  void _onSameDocumentTextDrop(
    OpenDoc view,
    EditorTextDragDropRequest request,
  ) {
    if (_disposing ||
        _appliedLocalEditorTextDragTokens.contains(request.payload.token)) {
      return;
    }
    final document = view.doc;
    final source = request.payload.selection;
    if (source.documentId != document.id) {
      _onCrossDocumentTextCopyDrop(view, request);
      return;
    }
    final views = _viewsOf(view).toList(growable: false);
    if (request.targetDocumentId != document.id ||
        request.targetDocumentVersion != source.documentVersion ||
        document.version != source.documentVersion ||
        views.any((item) =>
            item.inputWindow.pendingCount != 0 ||
            item.inputWindow.hasComposition ||
            item.pendingInputOperations.isNotEmpty ||
            item.pendingInputWindowShiftUtf16 != 0)) {
      return;
    }

    final beforeCaret = view.selection.extentOffset;
    late final TextRangeRead sourceRange;
    try {
      sourceRange = document.readRange(
        source.startUtf16,
        maxLenUtf16: source.lengthUtf16,
      );
    } on AlulaException {
      return;
    }
    if (sourceRange.version != source.documentVersion ||
        sourceRange.startUtf16 != source.startUtf16 ||
        sourceRange.endUtf16 != source.endUtf16 ||
        sourceRange.text != request.payload.selectedText) {
      return;
    }
    final plan = planSameDocumentTextDrag(
      source: source,
      targetDocumentId: request.targetDocumentId,
      targetDocumentVersion: request.targetDocumentVersion,
      targetDocumentLengthUtf16: sourceRange.totalUtf16Length,
      targetOffsetUtf16: request.targetOffsetUtf16,
      selectedText: sourceRange.text,
      operation: request.operation,
    );
    if (plan == null) return;

    try {
      document.applyWith(source.documentVersion, plan.forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(() => _statusDetail = '文本拖放未应用：${error.code} ${error.detail}');
      }
      return;
    }

    if (_appliedLocalEditorTextDragTokens.length >= 32) {
      _appliedLocalEditorTextDragTokens.remove(
        _appliedLocalEditorTextDragTokens.first,
      );
    }
    _appliedLocalEditorTextDragTokens.add(request.payload.token);
    final caret = TextSelection.collapsed(offset: plan.afterCaretUtf16);
    view.additionalSelections = const [];
    view.columnSelection = null;
    _recordDocumentOperations(
      view,
      forward: plan.forward,
      inverse: plan.inverse,
      beforeCaret: beforeCaret,
      afterCaret: plan.afterCaretUtf16,
      coalesce: false,
    );
    view.replaceInputWindow(plan.afterCaretUtf16, selection: caret);
    _refreshSiblingViews(view, plan.forward);
    final owner = _ownerOfView(view);
    if (owner != null) _focusNodeFor(owner, view).requestFocus();
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() {});
  }

  void _onCrossDocumentTextCopyDrop(
    OpenDoc targetView,
    EditorTextDragDropRequest request,
  ) {
    if (request.operation == EditorTextDropOperation.move) {
      _onCrossDocumentTextMoveDrop(targetView, request);
      return;
    }
    if (_disposing ||
        request.operation != EditorTextDropOperation.copy ||
        !_canStartEditorTextDragDrop(targetView)) {
      return;
    }

    final targetDocument = targetView.doc;
    final source = request.payload.selection;
    if (request.targetDocumentId != targetDocument.id ||
        request.targetDocumentVersion != targetDocument.version ||
        targetView.inputWindow.version != request.targetDocumentVersion) {
      return;
    }
    final sourceView = _allDocs
        .where((candidate) => candidate.id == source.documentId)
        .firstOrNull;
    if (sourceView == null ||
        sourceView.doc.version != source.documentVersion ||
        !_canStartEditorTextDragDrop(sourceView)) {
      return;
    }

    late final TextRangeRead sourceRange;
    try {
      sourceRange = sourceView.doc.readRange(
        source.startUtf16,
        maxLenUtf16: source.lengthUtf16,
      );
    } on AlulaException {
      return;
    }
    if (sourceRange.version != source.documentVersion ||
        sourceRange.startUtf16 != source.startUtf16 ||
        sourceRange.endUtf16 != source.endUtf16 ||
        sourceRange.text != request.payload.selectedText) {
      return;
    }

    final plan = planEditorCrossDocumentTextCopy(
      request: request,
      currentSourceDocumentId: sourceView.doc.id,
      currentSourceDocumentVersion: sourceRange.version,
      sourceDocumentLengthUtf16: sourceRange.totalUtf16Length,
      currentSourceText: sourceRange.text,
      currentTargetDocumentId: targetDocument.id,
      currentTargetDocumentVersion: targetDocument.version,
      targetDocumentLengthUtf16: targetView.inputWindow.totalUtf16Length,
    );
    if (plan == null) return;

    final beforeCaret = targetView.selection.extentOffset;
    try {
      targetDocument.applyWith(request.targetDocumentVersion, plan.forward);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '跨文档文本复制未应用：${error.code} ${error.detail}');
      }
      return;
    }

    if (_appliedLocalEditorTextDragTokens.length >= 32) {
      _appliedLocalEditorTextDragTokens.remove(
        _appliedLocalEditorTextDragTokens.first,
      );
    }
    _appliedLocalEditorTextDragTokens.add(request.payload.token);
    targetView.additionalSelections = const [];
    targetView.columnSelection = null;
    _recordDocumentOperations(
      targetView,
      forward: plan.forward,
      inverse: plan.inverse,
      beforeCaret: beforeCaret,
      afterCaret: plan.afterCaretUtf16,
      coalesce: false,
    );
    final caret = TextSelection.collapsed(offset: plan.afterCaretUtf16);
    targetView.replaceInputWindow(plan.afterCaretUtf16, selection: caret);
    _refreshSiblingViews(targetView, plan.forward);
    final owner = _ownerOfView(targetView);
    if (owner != null) _focusNodeFor(owner, targetView).requestFocus();
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() {});
  }

  void _onCrossDocumentTextMoveDrop(
    OpenDoc targetView,
    EditorTextDragDropRequest request,
  ) {
    final token = request.payload.token;
    if (_disposing ||
        request.operation != EditorTextDropOperation.move ||
        _appliedLocalEditorTextDragTokens.contains(token) ||
        _rejectedCrossDocumentMoveTokens.contains(token)) {
      return;
    }
    if (_rejectedCrossDocumentMoveTokens.length >= 32) {
      _rejectedCrossDocumentMoveTokens.remove(
        _rejectedCrossDocumentMoveTokens.first,
      );
    }
    // A rejected internal drop must not fall through to dragCompleted's
    // external-move source deletion.
    _rejectedCrossDocumentMoveTokens.add(token);

    final targetDocument = targetView.doc;
    final source = request.payload.selection;
    if (request.targetDocumentId != targetDocument.id ||
        request.targetDocumentVersion != targetDocument.version ||
        targetView.inputWindow.version != request.targetDocumentVersion ||
        targetView.diskState != DiskDocumentState.current ||
        !_canStartEditorTextDragDrop(targetView)) {
      return;
    }
    final sourceView = _allDocs
        .where((candidate) => candidate.id == source.documentId)
        .firstOrNull;
    if (sourceView == null ||
        sourceView.diskState != DiskDocumentState.current ||
        sourceView.doc.version != source.documentVersion ||
        !_canStartEditorTextDragDrop(sourceView)) {
      return;
    }

    late final TextRangeRead sourceRange;
    try {
      sourceRange = sourceView.doc.readRange(
        source.startUtf16,
        maxLenUtf16: source.lengthUtf16,
      );
    } on AlulaException {
      return;
    }
    if (sourceRange.version != source.documentVersion ||
        sourceRange.startUtf16 != source.startUtf16 ||
        sourceRange.endUtf16 != source.endUtf16 ||
        sourceRange.text != request.payload.selectedText) {
      return;
    }

    final plan = planEditorCrossDocumentTextMove(
      request: request,
      currentSourceDocumentId: sourceView.doc.id,
      currentSourceDocumentVersion: sourceRange.version,
      sourceDocumentLengthUtf16: sourceRange.totalUtf16Length,
      currentSourceText: sourceRange.text,
      currentTargetDocumentId: targetDocument.id,
      currentTargetDocumentVersion: targetDocument.version,
      targetDocumentLengthUtf16: targetView.inputWindow.totalUtf16Length,
    );
    if (plan == null) return;

    final beforeSourceCaret = sourceView.selection.extentOffset;
    final beforeTargetCaret = targetView.selection.extentOffset;
    final linkedDocumentIds = List<int>.unmodifiable(
      [sourceView.doc.id, targetDocument.id],
    );
    final transactionId =
        'cross-document-move-${DateTime.now().microsecondsSinceEpoch}-$token';
    late final AlulaWorkspaceEditResult result;
    try {
      result = targetDocument.core.applyWorkspaceEdit([
        AlulaWorkspaceEditDocument(
          id: sourceView.doc.id,
          baseVersion: source.documentVersion,
          ops: plan.sourceForwardOperations,
        ),
        AlulaWorkspaceEditDocument(
          id: targetDocument.id,
          baseVersion: request.targetDocumentVersion,
          ops: plan.targetForwardOperations,
        ),
      ]);
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '跨文档文本移动已回滚：${error.code} ${error.detail}');
      }
      return;
    }

    sourceView.doc.version = result.versions[sourceView.doc.id]!;
    targetDocument.version = result.versions[targetDocument.id]!;
    _undoHistoryBudget.beginBatch();
    try {
      _recordDocumentOperations(
        sourceView,
        forward: plan.sourceForwardOperations,
        inverse: plan.sourceInverseOperations,
        beforeCaret: beforeSourceCaret,
        afterCaret: plan.sourceCaretUtf16,
        coalesce: false,
        transactionId: transactionId,
        linkedDocumentIds: linkedDocumentIds,
      );
      _recordDocumentOperations(
        targetView,
        forward: plan.targetForwardOperations,
        inverse: plan.targetInverseOperations,
        beforeCaret: beforeTargetCaret,
        afterCaret: plan.targetCaretUtf16,
        coalesce: false,
        transactionId: transactionId,
        linkedDocumentIds: linkedDocumentIds,
      );
    } finally {
      _undoHistoryBudget.endBatch();
    }

    sourceView.replaceInputWindow(
      plan.sourceCaretUtf16,
      selection: TextSelection.collapsed(offset: plan.sourceCaretUtf16),
    );
    targetView.additionalSelections = const [];
    targetView.columnSelection = null;
    targetView.replaceInputWindow(
      plan.targetCaretUtf16,
      selection: TextSelection.collapsed(offset: plan.targetCaretUtf16),
    );
    _refreshSiblingViews(sourceView, plan.sourceForwardOperations);
    _refreshSiblingViews(targetView, plan.targetForwardOperations);
    sourceView.lastEditAt = null;
    targetView.lastEditAt = null;
    _updateDirty(sourceView);
    _updateDirty(targetView);
    _scheduleSyntaxRefresh(sourceView.id);
    _scheduleSyntaxRefresh(targetView.id);

    _rejectedCrossDocumentMoveTokens.remove(token);
    if (_appliedLocalEditorTextDragTokens.length >= 32) {
      _appliedLocalEditorTextDragTokens.remove(
        _appliedLocalEditorTextDragTokens.first,
      );
    }
    _appliedLocalEditorTextDragTokens.add(token);
    targetView.additionalSelections = const [];
    targetView.columnSelection = null;
    final owner = _ownerOfView(targetView);
    if (owner != null) _focusNodeFor(owner, targetView).requestFocus();
    _onFindTextChanged();
    _syncCommandContext();
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    if (mounted) {
      setState(() => _statusDetail = '已移动文本（撤销事务 $transactionId）');
    }
  }

  void _onExternalTextDrop(
    OpenDoc view,
    EditorExternalTextDropRequest request,
  ) {
    if (_disposing || !_canReceiveExternalTextDrop(view)) return;
    final document = view.doc;
    final target = request.externalTextTarget;
    if (target.targetDocumentId != document.id ||
        target.targetDocumentVersion != document.version ||
        view.inputWindow.version != target.targetDocumentVersion) {
      return;
    }
    final plan = planEditorExternalPlainTextDrop(
      targetDocumentId: target.targetDocumentId,
      targetDocumentVersion: target.targetDocumentVersion,
      currentDocumentId: document.id,
      currentDocumentVersion: document.version,
      targetDocumentLengthUtf16: view.inputWindow.totalUtf16Length,
      targetOffsetUtf16: target.targetOffsetUtf16,
      text: request.plainText,
    );
    if (plan == null) return;

    final beforeCaret = view.selection.extentOffset;
    try {
      document.applyWith(
        target.targetDocumentVersion,
        plan.forwardOperations,
      );
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '外部文本拖放未应用：${error.code} ${error.detail}');
      }
      return;
    }

    final caret = TextSelection.collapsed(offset: plan.caretAfterInsertUtf16);
    view.additionalSelections = const [];
    view.columnSelection = null;
    _recordDocumentOperations(
      view,
      forward: plan.forwardOperations,
      inverse: plan.inverseOperations,
      beforeCaret: beforeCaret,
      afterCaret: plan.caretAfterInsertUtf16,
      coalesce: false,
    );
    view.replaceInputWindow(plan.caretAfterInsertUtf16, selection: caret);
    _refreshSiblingViews(view, plan.forwardOperations);
    final owner = _ownerOfView(view);
    if (owner != null) _focusNodeFor(owner, view).requestFocus();
    _onFindTextChanged();
    _syncCommandContext();
    if (mounted) setState(() {});
  }

  void _onEditorTextDragCompleted(
    OpenDoc sourceView,
    EditorTextDragPayload payload,
    EditorTextDropOperation operation,
  ) {
    final alreadyApplied =
        _appliedLocalEditorTextDragTokens.remove(payload.token);
    final rejectedCrossDocumentMove =
        _rejectedCrossDocumentMoveTokens.remove(payload.token);
    if (alreadyApplied ||
        rejectedCrossDocumentMove ||
        operation != EditorTextDropOperation.move ||
        _disposing) {
      return;
    }
    final document = sourceView.doc;
    final source = payload.selection;
    final views = _viewsOf(sourceView).toList(growable: false);
    if (document.version != source.documentVersion ||
        views.any((item) =>
            item.inputWindow.pendingCount != 0 ||
            item.inputWindow.hasComposition ||
            item.pendingInputOperations.isNotEmpty ||
            item.pendingInputWindowShiftUtf16 != 0)) {
      return;
    }

    late final TextRangeRead sourceRange;
    try {
      sourceRange = document.readRange(
        source.startUtf16,
        maxLenUtf16: source.lengthUtf16,
      );
    } on AlulaException {
      return;
    }
    if (sourceRange.version != source.documentVersion ||
        sourceRange.startUtf16 != source.startUtf16 ||
        sourceRange.endUtf16 != source.endUtf16 ||
        sourceRange.text != payload.selectedText) {
      return;
    }

    final beforeCaret = sourceView.selection.extentOffset;
    final forward = [TextOp.delete(source.startUtf16, source.lengthUtf16)];
    final inverse = [TextOp.insert(source.startUtf16, sourceRange.text)];
    try {
      document.applyWith(source.documentVersion, forward);
    } on AlulaException {
      return;
    }
    sourceView.additionalSelections = const [];
    sourceView.columnSelection = null;
    _recordDocumentOperations(
      sourceView,
      forward: forward,
      inverse: inverse,
      beforeCaret: beforeCaret,
      afterCaret: source.startUtf16,
      coalesce: false,
    );
    final caret = TextSelection.collapsed(offset: source.startUtf16);
    sourceView.replaceInputWindow(source.startUtf16, selection: caret);
    _refreshSiblingViews(sourceView, forward);
    _onFindTextChanged();
    _syncCommandContext();
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
    final mergeSession = doc.mergeResultSession;
    if (ops.isNotEmpty &&
        mergeSession != null &&
        !mergeSession.hasStaleConflictRanges) {
      mergeSession.reconcileCurrentResult(allowKnownProjectionRestore: false);
    }
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
    for (final binding in _snapshotCompareViews.values
        .where((binding) => binding.view.sameDocumentAs(source))
        .toList(growable: false)) {
      _scheduleSnapshotCompareDiff(binding);
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

  /// Opens the bounded review UI and applies only its selected edits.
  ///
  /// The source versions are pinned into the callback payload even when the
  /// producer did not supply versions, so a document changed while the review
  /// is open fails the existing transaction preflight instead of being rebased.
  Future<bool> reviewWorkspaceEdit(WorkspaceEdit edit) async {
    if (_core == null) {
      setState(() => _statusDetail = '工作区编辑失败：核心尚未就绪');
      return false;
    }
    for (final doc in _allDocViews) {
      _flushInput(doc, commitComposition: true);
    }
    final snapshots = List<WorkspaceDocumentSnapshot>.unmodifiable([
      for (final doc in _allDocs)
        if (doc.uri != null)
          WorkspaceDocumentSnapshot(
            id: doc.id,
            uri: doc.uri!,
            version: doc.doc.version,
            text: doc.text,
            writable: doc.path != null &&
                doc.diskState == DiskDocumentState.current,
          ),
    ]);
    final snapshotsByUri = {
      for (final snapshot in snapshots) snapshot.uri: snapshot,
    };

    return showBulkEditPreview(
      context: context,
      edit: edit,
      snapshots: snapshots,
      onApply: (selectedEdit) async {
        final versionPinnedEdit = WorkspaceEdit(
          [
            for (final document in selectedEdit.documents)
              WorkspaceDocumentEdit(
                uri: document.uri,
                version:
                    document.version ?? snapshotsByUri[document.uri]!.version,
                edits: document.edits,
              ),
          ],
          transactionId: selectedEdit.transactionId,
        );
        return applyWorkspaceEdit(versionPinnedEdit);
      },
      keyPrefix: 'workbench-bulk-edit-preview',
    );
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

  Future<void> _newUntitledFile() async {
    final core = _core;
    if (core == null) return;
    final previous = _active;
    if (previous != null) _flushInput(previous, commitComposition: true);

    final id = _nextDocId++;
    try {
      final doc = core.openDoc(id, '');
      final untitled = OpenDoc(
        id: id,
        name: '未命名-$id',
        doc: doc,
        undoBudget: _undoHistoryBudget,
      );
      final target = _focused;
      setState(() {
        target.docs.add(untitled);
        target.activeDocId = id;
        _noteActiveDocument(target, id);
      });
      _scheduleStateSave();
      _syncCommandContext();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(target.active, untitled)) return;
        _focusNodeFor(target, untitled).requestFocus();
      });
    } on AlulaException catch (error) {
      if (mounted) setState(() => _statusDetail = '新建文本文件失败：${error.code}');
    }
  }

  void _openFolder(String path) {
    final core = _core;
    if (core == null) return;
    try {
      final entries = core.workspace.listDir(path);
      final historyWorkspaceChanged = _findHistoryWorkspaceIdentity !=
          FindReplaceHistoryStore.workspaceIdentity(path);
      if (historyWorkspaceChanged) _flushFindHistory();
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
        if (_workspaceRoot != path) {
          _explorerCompareSelection = null;
          _explorerMultiSelection.clear();
          _explorerSelectionAnchor = null;
        }
        _workspaceRoot = path;
        _treeRoots.clear();
        _treeRoots.addAll(entries
            .map((e) => TreeNode(
                  name: e['name'] as String,
                  path: e['path'] as String,
                  isDir: (e['is_dir'] as bool?) ?? false,
                ))
            .toList());
        _pruneExplorerMultiSelection();
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
      _loadFindHistoryForWorkspace(path);
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
      setState(() {
        node.expanded = false;
        _pruneExplorerMultiSelection();
      });
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
    setState(() {
      node.expanded = true;
      _pruneExplorerMultiSelection();
    });
  }

  void _openTreeFile(TreeNode node) {
    final previousClickClock = _lastExplorerClickClock;
    final isDoubleClick =
        _lastExplorerClickPath == node.path &&
            previousClickClock != null &&
            previousClickClock.elapsed <= _explorerDoubleClickTimeout;
    if (isDoubleClick) {
      _lastExplorerClickPath = null;
      _lastExplorerClickClock = null;
      if (_pinOpenExplorerPreview(node.path)) return;
      final alreadyOpen = _groups.values
          .any((group) => group.docs.any((doc) => doc.path == node.path));
      if (alreadyOpen) return;
      if ((_explorerPreviewOpenCounts[node.path] ?? 0) > 0) {
        _pendingExplorerPreviewPinPath = node.path;
      } else {
        unawaited(_openFileByPath(node.path, pinPreview: true));
      }
      return;
    }

    _lastExplorerClickPath = node.path;
    _lastExplorerClickClock = Stopwatch()..start();
    unawaited(_openExplorerPreview(node.path));
  }

  Future<void> _openExplorerPreview(String path) async {
    _explorerPreviewOpenCounts.update(path, (count) => count + 1,
        ifAbsent: () => 1);
    try {
      await _openFileByPath(path, asPreview: true);
    } finally {
      final remaining = (_explorerPreviewOpenCounts[path] ?? 1) - 1;
      if (remaining == 0) {
        _explorerPreviewOpenCounts.remove(path);
        if (_pendingExplorerPreviewPinPath == path) {
          _pendingExplorerPreviewPinPath = null;
          _pinOpenExplorerPreview(path);
        }
      } else {
        _explorerPreviewOpenCounts[path] = remaining;
      }
    }
  }

  bool _pinOpenExplorerPreview(String path) {
    var pinned = false;
    for (final group in _groups.values) {
      final preview = group.docs
          .where((doc) => doc.id == group.previewDocId && doc.path == path)
          .firstOrNull;
      if (preview == null) continue;
      group.previewDocId = null;
      pinned = true;
    }
    if (pinned && mounted) {
      setState(() {});
      _scheduleStateSave();
    }
    return pinned;
  }

  void _replaceCleanPreviewBeforeOpen(EditorGroup group) {
    final previewId = group.previewDocId;
    if (previewId == null) return;
    final preview = group.docs.where((doc) => doc.id == previewId).firstOrNull;
    if (preview == null) {
      group.previewDocId = null;
      return;
    }
    if (preview.isDirty) {
      group.previewDocId = null;
      return;
    }
    _closeDocNow(group, preview, keepEmptyGroup: true);
  }

  List<TreeNode> _visibleExplorerFiles() {
    final result = <TreeNode>[];
    void visit(List<TreeNode> nodes) {
      for (final node in nodes) {
        if (node.path.isNotEmpty && !node.isDir) result.add(node);
        if (node.isDir && node.expanded && node.children != null) {
          visit(node.children!);
        }
      }
    }

    visit(_treeRoots);
    return result;
  }

  bool _isExplorerFileSelected(String path) => _explorerMultiSelection
      .any((selected) => _canonicalPath(selected) == _canonicalPath(path));

  void _pruneExplorerMultiSelection() {
    final visible = _visibleExplorerFiles()
        .map((node) => _canonicalPath(node.path))
        .toSet();
    _explorerMultiSelection.removeWhere(
      (path) => !visible.contains(_canonicalPath(path)),
    );
    if (_explorerSelectionAnchor != null &&
        !visible.contains(_canonicalPath(_explorerSelectionAnchor!))) {
      _explorerSelectionAnchor = _explorerMultiSelection.lastOrNull;
    }
  }

  void _selectExplorerFile(TreeNode node) {
    if (node.isDir || node.path.isEmpty) return;
    final visibleFiles = _visibleExplorerFiles();
    final clickedPath = _canonicalPath(node.path);
    final clickedIndex = visibleFiles.indexWhere(
      (file) => _canonicalPath(file.path) == clickedPath,
    );
    if (clickedIndex < 0) return;

    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final keyboard = HardwareKeyboard.instance;
    final toggle = isMac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final extend = keyboard.isShiftPressed;
    setState(() {
      if (extend) {
        var anchorIndex = _explorerSelectionAnchor == null
            ? -1
            : visibleFiles.indexWhere((file) =>
                _canonicalPath(file.path) ==
                _canonicalPath(_explorerSelectionAnchor!));
        if (anchorIndex < 0) {
          anchorIndex = clickedIndex;
          _explorerSelectionAnchor = node.path;
        }
        final first = anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
        final last = anchorIndex > clickedIndex ? anchorIndex : clickedIndex;
        final range = visibleFiles
            .skip(first)
            .take(last - first + 1)
            .map((file) => file.path);
        final paths = toggle ? [..._explorerMultiSelection] : <String>[];
        for (final path in range) {
          if (!paths.any(
              (selected) => _canonicalPath(selected) == _canonicalPath(path))) {
            paths.add(path);
          }
        }
        _explorerMultiSelection
          ..clear()
          ..addAll(paths);
      } else if (toggle) {
        final selectedIndex = _explorerMultiSelection.indexWhere(
          (path) => _canonicalPath(path) == clickedPath,
        );
        if (selectedIndex >= 0) {
          _explorerMultiSelection.removeAt(selectedIndex);
          if (_explorerSelectionAnchor != null &&
              _canonicalPath(_explorerSelectionAnchor!) == clickedPath) {
            _explorerSelectionAnchor = _explorerMultiSelection.lastOrNull;
          }
        } else {
          _explorerMultiSelection.add(node.path);
          _explorerSelectionAnchor = node.path;
        }
      } else {
        _explorerMultiSelection
          ..clear()
          ..add(node.path);
        _explorerSelectionAnchor = node.path;
      }
    });
  }

  bool _sameExplorerSelection(List<String> paths) =>
      listEquals(_explorerMultiSelection, paths);

  List<_ExplorerCompareTarget>? _targetsForExplorerSelection(
    String root,
    List<String> paths,
  ) {
    final files = <String, TreeNode>{
      for (final file in _visibleExplorerFiles())
        _canonicalPath(file.path): file,
    };
    final targets = <_ExplorerCompareTarget>[];
    for (final path in paths) {
      final node = files[_canonicalPath(path)];
      if (node == null) return null;
      targets.add(_ExplorerCompareTarget(
        workspaceRoot: root,
        path: node.path,
        name: node.name,
        isDirectory: false,
      ));
    }
    return targets;
  }

  Future<void> _compareSelectedExplorerFiles(
    List<_ExplorerCompareTarget> targets,
  ) async {
    final root = _workspaceRoot;
    final core = _core;
    final selectedPaths = List<String>.of(_explorerMultiSelection);
    if (root == null ||
        core == null ||
        targets.length != 2 ||
        selectedPaths.length != 2 ||
        targets.any((target) =>
            target.workspaceRoot != root ||
            target.isDirectory ||
            target.path.isEmpty) ||
        _canonicalPath(targets[0].path) == _canonicalPath(targets[1].path) ||
        !_sameExplorerSelection(
            targets.map((target) => target.path).toList())) {
      _showExplorerCompareStatus('比较已取消：请选择当前工作区中的两个不同文件');
      return;
    }

    final previous = _explorerCompareSelection;
    await _selectExplorerFileForCompare(targets.first);
    final original = _explorerCompareSelection;
    if (!mounted ||
        _workspaceRoot != root ||
        !identical(_core, core)) {
      return;
    }
    if (!_sameExplorerSelection(selectedPaths)) {
      _showExplorerCompareStatus('比较已取消：Explorer 选择在读取期间已变化');
      return;
    }
    if (original == null ||
        identical(original, previous) ||
        _canonicalPath(original.requestedPath) !=
            _canonicalPath(targets.first.path)) {
      return;
    }
    await _compareSelectedExplorerFile(targets.last);
  }

  Future<void> _showExplorerCompareContextMenu(
    TreeNode node,
    Offset globalPosition,
  ) async {
    final root = _workspaceRoot;
    if (root == null || node.isDir || node.path.isEmpty) return;
    if (!_isExplorerFileSelected(node.path)) {
      setState(() {
        _explorerMultiSelection
          ..clear()
          ..add(node.path);
        _explorerSelectionAnchor = node.path;
      });
    }
    final selectedPaths = List<String>.unmodifiable(_explorerMultiSelection);
    final selectedTargets = _targetsForExplorerSelection(root, selectedPaths);
    final canCompareSelected = selectedPaths.length == 2 &&
        selectedTargets != null &&
        selectedPaths.any(
          (path) => _canonicalPath(path) == _canonicalPath(node.path),
        );
    final selection = _explorerCompareSelection;
    final canCompareWithSelected = selection != null &&
        selection.workspaceRoot == root &&
        _canonicalPath(selection.requestedPath) != _canonicalPath(node.path);
    final overlay = Overlay.of(context, rootOverlay: true);
    final renderObject = overlay.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final localPosition = renderObject.globalToLocal(globalPosition);
    final action = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1),
        Offset.zero & renderObject.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: _selectForCompareCommandId,
          child: Text('Select for Compare'),
        ),
        if (canCompareSelected)
          const PopupMenuItem<String>(
            value: _compareSelectedExplorerFilesAction,
            child: Text('Compare Selected'),
          ),
        if (canCompareWithSelected)
          const PopupMenuItem<String>(
            value: _compareFilesCommandId,
            child: Text('Compare with Selected'),
          ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == _compareSelectedExplorerFilesAction) {
      if (_workspaceRoot != root ||
          !_sameExplorerSelection(selectedPaths) ||
          selectedTargets == null) {
        _showExplorerCompareStatus('比较已取消：Explorer 选择或工作区已变化');
        return;
      }
      await _compareSelectedExplorerFiles(selectedTargets);
      return;
    }
    final target = _ExplorerCompareTarget(
      workspaceRoot: root,
      path: node.path,
      name: node.name,
      isDirectory: node.isDir,
    );
    final status = await _commands.execute(action, arguments: target);
    if (!mounted || status == CommandExecutionStatus.executed) return;
    _showExplorerCompareStatus('比较命令当前不可用：$action');
  }

  Future<void> _openMergeEditorWithoutArguments() async {
    _showMergeEditorOpenError(
      'Merge Editor 需要 base、input1、input2 和 result 四个本地文件 URI。',
    );
  }

  String? _mergeEditorLocalPath(Uri uri) {
    if (uri.scheme != 'file' ||
        !uri.isAbsolute ||
        uri.path.isEmpty ||
        !uri.path.startsWith('/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.host.isNotEmpty && uri.host != 'localhost')) {
      return null;
    }
    try {
      final path = uri.toFilePath(windows: Platform.isWindows);
      if (path.isEmpty) return null;
      return File(path).absolute.path;
    } on Object {
      return null;
    }
  }

  String _mergeEditorPathIdentity(String path) {
    final absolute = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  OpenDoc? _findOpenDocumentByPath(String path) {
    final identity = _mergeEditorPathIdentity(path);
    for (final group in _groups.values) {
      for (final candidate in group.docs) {
        final candidatePath = candidate.path;
        if (candidatePath != null &&
            _mergeEditorPathIdentity(candidatePath) == identity) {
          return candidate;
        }
      }
    }
    return null;
  }

  String _readMergeEditorSnapshot(AlulaCore core, String path) {
    final open = _findOpenDocumentByPath(path);
    if (open != null) return open.doc.resync().content;
    return core.workspace.readFileDocument(path).content;
  }

  void _showMergeEditorOpenError(String message) {
    if (!mounted) return;
    setState(() => _statusDetail = message);
  }

  void _clearMergeEditorOpenStatus() {
    if (!mounted) return;
    setState(() => _statusDetail = '');
  }

  Future<void> _openMergeEditorFromArguments(Object? arguments) async {
    if (arguments is! MergeEditorOpenRequest) {
      _showMergeEditorOpenError(
        'Merge Editor 参数无效；需要 base、input1、input2 和 result 文件 URI。',
      );
      return;
    }
    final core = _core;
    if (core == null) {
      _showMergeEditorOpenError('Rust 编辑核心尚未就绪。');
      return;
    }

    final paths = [
      _mergeEditorLocalPath(arguments.baseUri),
      _mergeEditorLocalPath(arguments.input1Uri),
      _mergeEditorLocalPath(arguments.input2Uri),
      _mergeEditorLocalPath(arguments.resultUri),
    ];
    if (paths.any((path) => path == null)) {
      _showMergeEditorOpenError('Merge Editor 只接受绝对本地 file URI。');
      return;
    }
    final basePath = paths[0]!;
    final input1Path = paths[1]!;
    final input2Path = paths[2]!;
    final resultPath = paths[3]!;
    final resultIdentity = _mergeEditorPathIdentity(resultPath);
    for (final sourcePath in [basePath, input1Path, input2Path]) {
      var aliasesResult =
          _mergeEditorPathIdentity(sourcePath) == resultIdentity;
      if (!aliasesResult) {
        try {
          aliasesResult = FileSystemEntity.identicalSync(
            sourcePath,
            resultPath,
          );
        } on Object {
          aliasesResult = false;
        }
      }
      if (aliasesResult) {
        _showMergeEditorOpenError(
          'result 必须与 base、input1 和 input2 是不同的文件。',
        );
        return;
      }
    }

    late final String base;
    late final String input1;
    late final String input2;
    try {
      base = _readMergeEditorSnapshot(core, basePath);
      input1 = _readMergeEditorSnapshot(core, input1Path);
      input2 = _readMergeEditorSnapshot(core, input2Path);
    } on Object catch (error) {
      _showMergeEditorOpenError('读取 Merge Editor 输入失败：$error');
      return;
    }

    final existingResult = _findOpenDocumentByPath(resultPath);
    final existingSession = existingResult?.mergeResultSession;
    if (existingSession != null) {
      try {
        if (existingSession.baseText == base &&
            existingSession.input1Text == input1 &&
            existingSession.input2Text == input2) {
          await _openFileByPath(existingResult?.path ?? resultPath);
          _clearMergeEditorOpenStatus();
          return;
        }
      } on Object catch (error) {
        _showMergeEditorOpenError('现有 Merge Editor 会话不可用：$error');
        return;
      }
      _showMergeEditorOpenError(
        'result 已绑定到另一组三方输入；不会替换现有会话。',
      );
      return;
    }
    if (existingResult?.isDirty ?? false) {
      _showMergeEditorOpenError(
        'result 文档有未保存修改；先保存或还原后再打开 Merge Editor。',
      );
      return;
    }

    late final AlulaMergeProjection projection;
    try {
      projection = core.merge.project(
        base: base,
        input1: input1,
        input2: input2,
      );
    } on Object catch (error) {
      _showMergeEditorOpenError('读取或计算 Merge Editor 结果失败：$error');
      return;
    }
    if (existingResult != null &&
        existingResult.doc.resync().content != projection.result) {
      _showMergeEditorOpenError(
        'result 文本与 Rust 三方合并投影不一致；文件未更改。',
      );
      return;
    }

    await _openFileByPath(
      existingResult?.path ?? resultPath,
      expectedContent: projection.result,
    );
    if (!mounted) return;
    final resultDocument = _findOpenDocumentByPath(resultPath);
    if (resultDocument == null) return;
    if (resultDocument.isDirty ||
        resultDocument.doc.resync().content != projection.result) {
      _showMergeEditorOpenError(
        'result 在打开过程中发生变化；未附加 Merge Editor 会话。',
      );
      return;
    }
    final attachedSession = resultDocument.mergeResultSession;
    if (attachedSession != null) {
      if (attachedSession.baseText == base &&
          attachedSession.input1Text == input1 &&
          attachedSession.input2Text == input2) {
        _clearMergeEditorOpenStatus();
        return;
      }
      _showMergeEditorOpenError(
        'result 已绑定到另一组三方输入；不会替换现有会话。',
      );
      return;
    }

    try {
      resultDocument.mergeResultSession = MergeResultSession.open(
        mergeApi: core.merge,
        resultDocument: resultDocument.doc,
        base: base,
        input1: input1,
        input2: input2,
      );
    } on Object catch (error) {
      _showMergeEditorOpenError('创建 Merge Editor 会话失败：$error');
      return;
    }
    _clearMergeEditorOpenStatus();
    _syncCommandContext();
  }

  Future<void> _openFileByPath(
    String path, {
    String? expectedContent,
    bool asPreview = false,
    bool pinPreview = false,
  }) async {
    if (!asPreview && !pinPreview) {
      _lastExplorerClickPath = null;
      _lastExplorerClickClock = null;
    }
    final core = _core;
    if (core == null) return;
    // LAY-13a：配置编辑器路径按 useModal 偏好以模态对话框打开（不进标签）。
    if (expectedContent == null &&
        _findOpenDocumentByPath(path) == null &&
        !(_modalEditorDoc?.path == path) &&
        _modalEditorUseMode.opensAutomatically(path)) {
      await _openModalEditor(core, path);
      return;
    }
    DecodedTextFile? prevalidatedFile;
    if (expectedContent != null) {
      final existing = _findOpenDocumentByPath(path);
      if (existing != null) {
        if (existing.isDirty ||
            existing.doc.resync().content != expectedContent) {
          _showMergeEditorOpenError(
            'result 文本与 Rust 三方合并投影不一致或已变化；文件未更改。',
          );
          return;
        }
      } else {
        try {
          prevalidatedFile = core.workspace.readFileDocument(path);
        } on Object catch (error) {
          _showMergeEditorOpenError('读取 Merge Editor result 失败：$error');
          return;
        }
        if (prevalidatedFile.content != expectedContent) {
          _showMergeEditorOpenError(
            'result 文本与 Rust 三方合并投影不一致或已变化；文件未更改。',
          );
          return;
        }
      }
    }
    final previous = _active;
    if (previous != null) _flushInput(previous, commitComposition: true);
    // 同一文件在不同组打开时共享 Rust 文档，但为组创建独立视图状态。
    for (final g in _groups.values) {
      final existing = g.docs.where((d) => d.path == path).firstOrNull;
      if (existing != null) {
        if (expectedContent != null &&
            (existing.isDirty ||
                existing.doc.resync().content != expectedContent)) {
          _showMergeEditorOpenError(
            'result 文档在打开过程中发生变化；未附加 Merge Editor 会话。',
          );
          return;
        }
        final target = _focused;
        final existingInTarget = target.docs
            .where((candidate) => candidate.sameDocumentAs(existing))
            .firstOrNull;
        final view = identical(g, target)
            ? existing
            : existingInTarget ?? OpenDoc.viewOf(existing);
        if (asPreview && existingInTarget == null) {
          _replaceCleanPreviewBeforeOpen(target);
        }
        setState(() {
          if (!target.docs.contains(view)) target.docs.add(view);
          target.activeDocId = view.id;
          _noteActiveDocument(target, view.id);
          if (target.previewDocId == view.id &&
              (pinPreview || !asPreview)) {
            target.previewDocId = null;
          } else if (asPreview && existingInTarget == null && !view.isDirty) {
            target.previewDocId = view.id;
          }
          _focusedRegion = target.region;
        });
        _scheduleStateSave();
        _syncCommandContext();
        _scheduleSyntaxRefresh(view.id);
        return;
      }
    }
    DecodedTextFile file;
    if (prevalidatedFile != null) {
      file = prevalidatedFile;
    } else {
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
      final mergeSessionFactory = widget.mergeResultSessionFactory;
      if (mergeSessionFactory != null) {
        try {
          open.mergeResultSession = mergeSessionFactory(
            core,
            open,
            (plan) => _applyMergeResultPlan(open, plan),
          );
        } on Object catch (error) {
          open.disposeView();
          if (mounted) {
            setState(() => _statusDetail = '打开合并结果会话失败：$error');
          }
          return;
        }
      }
      _updateDirty(open);
      final target = _focused;
      if (asPreview) _replaceCleanPreviewBeforeOpen(target);
      setState(() {
        target.docs.add(open);
        target.activeDocId = id;
        _noteActiveDocument(target, id);
        target.previewDocId = asPreview && !open.isDirty ? id : null;
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

  void _noteActiveDocument(EditorGroup group, int? documentId) {
    if (documentId == null) return;
    group.recentDocIds.remove(documentId);
    group.recentDocIds.insert(0, documentId);
    group.lastActivationOrder = ++_editorActivationClock;
  }

  OpenDoc? _mostRecentDocument(EditorGroup group,
      {bool nonStickyOnly = false}) {
    for (final id in group.recentDocIds) {
      final doc =
          group.docs.where((candidate) => candidate.id == id).firstOrNull;
      if (doc != null && (!nonStickyOnly || !group.stickyDocIds.contains(id))) {
        return doc;
      }
    }
    for (final doc in group.docs.reversed) {
      if (!nonStickyOnly || !group.stickyDocIds.contains(doc.id)) return doc;
    }
    return null;
  }

  OpenDoc? _mostRecentNonStickyDocument(EditorGroup group) =>
      _mostRecentDocument(group, nonStickyOnly: true);

  /// 剩余组中最近活动的组（上游 editorPart.mostRecentlyActiveGroups）。
  String? _mostRecentlyActiveRegion({String? excluding}) {
    EditorGroup? best;
    for (final group in _groups.values) {
      if (group.region == excluding) continue;
      if (best == null ||
          group.lastActivationOrder > best.lastActivationOrder) {
        best = group;
      }
    }
    return best?.region;
  }

  // ---------- Modal 编辑器（LAY-13a） ----------

  /// 以模态对话框打开配置编辑器路径（脱离视图，不入组；上游 useModal）。
  Future<void> _openModalEditor(AlulaCore core, String path) async {
    final doc = await _createDetachedModalDoc(core, path);
    if (doc == null || !mounted) return;
    var moveBack = false;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '模态编辑器屏障',
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, __) => ModalEditorDialog(
        title: doc.name,
        onMoveBackToTab: () {
          moveBack = true;
          Navigator.of(dialogContext).pop();
        },
        onClose: () => Navigator.of(dialogContext).pop(),
        child: CallbackShortcuts(
          bindings: {
            SingleActivator(
              LogicalKeyboardKey.keyS,
              control: defaultTargetPlatform != TargetPlatform.macOS,
              meta: defaultTargetPlatform == TargetPlatform.macOS,
            ): () {
              final currentPath = doc.path;
              if (currentPath != null) {
                unawaited(_saveDocToPath(doc, currentPath));
              }
            },
          },
          child: RustTextInputField(
            inputWindow: doc.inputWindow,
            scrollController: doc.editorScrollController,
            tabSize: doc.tabSize,
            semanticsLabel: '${doc.name} 模态编辑器',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            onDelta: (delta) {
              try {
                doc.doc.applyWith(delta.version, delta.operations);
                if (mounted) setState(() {});
              } on Object {
                // 陈旧脱离视图：忽略增量。
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() => _statusDetail = '模态编辑错误：$error');
              }
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (moveBack) {
      // 移回标签：同一 OpenDoc 视图入焦点组（状态/选区随行）。
      setState(() {
        _modalEditorDoc = null;
        final group = _focused;
        group.docs.add(doc);
        group.activeDocId = doc.id;
        _noteActiveDocument(group, doc.id);
      });
      _syncCommandContext();
      _scheduleStateSave();
      return;
    }
    _disposeModalEditorDoc(doc);
  }

  Future<OpenDoc?> _createDetachedModalDoc(AlulaCore core, String path) async {
    try {
      final decoded = _readDiskDocument(core, path);
      final id = _nextDocId++;
      final coreDoc = core.openDoc(id, decoded.content);
      coreDoc.setSavepoint(decoded.content);
      return OpenDoc(
        id: id,
        name: _nameOf(path),
        path: path,
        doc: coreDoc,
        fileOptions: decoded.options,
        savedFileOptions: decoded.options,
        undoBudget: _undoHistoryBudget,
      );
    } on Object catch (error) {
      setState(() => _statusDetail = '打开配置编辑器失败：$error');
      return null;
    }
  }

  void _disposeModalEditorDoc(OpenDoc doc) {
    for (final view in _viewsOf(doc).toList(growable: false)) {
      _flushInput(view, commitComposition: true);
    }
    _editorFocusNodes.remove(_focusKeyFor(_focused, doc))?.dispose();
    doc.disposeView();
    setState(() => _modalEditorDoc = null);
  }

  // ---------- 浮动辅助窗口（LAY-12a） ----------

  /// 主窗自身窗口通道：接收辅助窗口的关闭恢复通知。
  Future<void> _setupAuxiliaryWindowHandlers() async {
    try {
      final self = await WindowController.fromCurrentEngine();
      self.setWindowMethodHandler((call) async {
        if (call.method == 'alula_auxiliary_closed') {
          final args = call.arguments is Map
              ? Map<String, Object?>.from(call.arguments as Map)
              : <String, Object?>{};
          _reopenAuxiliaryDocument(args);
        }
        return null;
      });
    } on Object {
      // 平台/测试环境无窗口定义：跳过辅助窗口同步。
    }
  }

  /// 将编辑器移入新的辅助窗口：文本随启动载荷传递，源组移除该视图
  /// （上游移动保留状态，不做脏确认——无数据丢失）。
  Future<void> _moveEditorToNewWindow(EditorGroup group, OpenDoc doc) async {
    _flushInput(doc, commitComposition: true);
    final payload = AuxiliaryWindowPayload.forDocument(
      path: doc.path,
      name: doc.name,
      text: doc.text,
      dirty: doc.isDirty,
    );
    try {
      final controller = await WindowController.create(
        WindowConfiguration(arguments: payload.toArguments()),
      );
      _auxiliaryWindowIds.add(controller.windowId);
      await controller.show();
    } on Object catch (error) {
      setState(() => _statusDetail = '辅助窗口创建失败：$error');
      return;
    }
    _closeDocNow(group, doc);
    _syncCommandContext();
    _scheduleStateSave();
  }

  Future<void> _moveFocusedEditorToNewWindow() async {
    final group = _focused;
    final active = group.active;
    if (active == null) return;
    await _moveEditorToNewWindow(group, active);
  }

  /// 辅助窗口关闭恢复：按 path 重开（干净文件），未命名/脏文本以传递文本
  /// 恢复为对应脏态文档。
  void _reopenAuxiliaryDocument(Map<String, Object?> args) {
    final pathValue = args['path'] as String?;
    final path = pathValue == null || pathValue.isEmpty ? null : pathValue;
    final name = args['name'] as String? ?? '未命名';
    final text = args['text'] as String? ?? '';
    final dirty = args['dirty'] == true;
    if (!mounted) return;
    if (path != null && !dirty) {
      unawaited(_openFileByPath(path, pinPreview: false));
      return;
    }
    final core = _core;
    if (core == null) return;
    try {
      final decoded = path != null ? _readDiskDocument(core, path) : null;
      final id = _nextDocId++;
      final coreDoc = core.openDoc(id, text);
      coreDoc.setSavepoint(decoded?.content ?? '');
      final doc = OpenDoc(
        id: id,
        name: name,
        path: path,
        doc: coreDoc,
        fileOptions: decoded?.options ?? TextFileOptions.defaults,
        savedFileOptions: decoded?.options ?? TextFileOptions.defaults,
        dirtyDisk: dirty && decoded != null && text != decoded.content,
        undoBudget: _undoHistoryBudget,
      );
      setState(() {
        final group = _focused;
        group.docs.add(doc);
        group.activeDocId = id;
        _noteActiveDocument(group, id);
      });
      _syncCommandContext();
      _scheduleStateSave();
    } on Object catch (error) {
      setState(() => _statusDetail = '辅助窗口文档恢复失败：$error');
    }
  }

  void _normalizeStickyOrder(EditorGroup group) {
    final presentIds = group.docs.map((doc) => doc.id).toSet();
    group.stickyDocIds.removeWhere((id) => !presentIds.contains(id));
    final sticky = group.docs
        .where((doc) => group.stickyDocIds.contains(doc.id))
        .toList(growable: false);
    final ordinary = group.docs
        .where((doc) => !group.stickyDocIds.contains(doc.id))
        .toList(growable: false);
    group.docs
      ..clear()
      ..addAll(sticky)
      ..addAll(ordinary);
  }

  void _setEditorSticky(EditorGroup group, OpenDoc doc, bool sticky) {
    if (!group.docs.any((candidate) => identical(candidate, doc))) return;
    final wasSticky = group.stickyDocIds.contains(doc.id);
    if (wasSticky == sticky) return;
    setState(() {
      group.lastAutoRevealedTabId = null;
      if (sticky) {
        group.stickyDocIds.add(doc.id);
        if (group.previewDocId == doc.id) group.previewDocId = null;
      } else {
        group.stickyDocIds.remove(doc.id);
      }
      _normalizeStickyOrder(group);
    });
    _scheduleStateSave();
  }

  void _setActiveEditorSticky(bool sticky) {
    final group = _focused;
    final active = group.active;
    if (active != null) _setEditorSticky(group, active, sticky);
  }

  void _toggleActiveEditorSticky() {
    final group = _focused;
    final active = group.active;
    if (active != null) {
      _setEditorSticky(group, active, !group.stickyDocIds.contains(active.id));
    }
  }

  void _closeActiveEditorFromKeyboard() {
    final group = _focused;
    final active = group.active;
    if (active == null) return;
    if (!group.stickyDocIds.contains(active.id)) {
      _closeDoc(active.id, group: group);
      return;
    }

    EditorGroup? targetGroup = group;
    OpenDoc? target = _mostRecentNonStickyDocument(group);
    if (target == null) {
      final otherGroups = _groups.values
          .where((candidate) => !identical(candidate, group))
          .toList()
        ..sort((left, right) =>
            right.lastActivationOrder.compareTo(left.lastActivationOrder));
      for (final candidateGroup in otherGroups) {
        target = _mostRecentNonStickyDocument(candidateGroup);
        if (target != null) {
          targetGroup = candidateGroup;
          break;
        }
      }
    }
    if (target == null || targetGroup == null) return;
    final selectedGroup = targetGroup;
    final selectedDocument = target;

    _flushInput(active, commitComposition: true);
    setState(() {
      selectedGroup.activeDocId = selectedDocument.id;
      _focusedRegion = selectedGroup.region;
      _noteActiveDocument(selectedGroup, selectedDocument.id);
    });
    _syncCommandContext();
    _focusEditorAfterLayout(selectedGroup, selectedDocument);
    _scheduleStateSave();
  }

  Future<void> _closeFromActiveEditor(EditorTabCloseOperation action) async {
    final group = _focused;
    final target = group.active;
    if (target == null) return;
    await _closeTabsForAction(group, target, action);
  }

  Future<void> _closeTabsForAction(
    EditorGroup group,
    OpenDoc target,
    EditorTabCloseOperation action,
  ) async {
    if (!group.docs.any((doc) => identical(doc, target))) return;
    for (final doc in group.docs.toList(growable: false)) {
      for (final view in _viewsOf(doc).toList(growable: false)) {
        _flushInput(view, commitComposition: true);
      }
      _updateDirty(doc);
    }
    final candidateIds = EditorTabClosePolicy.candidates(
      documentIds: group.docs.map((doc) => doc.id).toList(growable: false),
      targetId: target.id,
      stickyDocumentIds: group.stickyDocIds,
      cleanDocumentIds: {
        for (final doc in group.docs)
          if (!doc.isDirty) doc.id,
      },
      action: action,
    );
    final targets = <_EditorCloseTarget>[
      for (final id in candidateIds)
        for (final doc in group.docs)
          if (doc.id == id) (group: group, doc: doc),
    ];
    await _requestCloseEditorViews(targets);
  }

  Future<void> _closeAllEditorsInFocusedGroup() async {
    final group = _focused;
    await _requestCloseEditorViews([
      for (final doc in group.docs)
        if (!group.stickyDocIds.contains(doc.id)) (group: group, doc: doc),
    ]);
  }

  Future<void> _closeAllEditorGroups() async {
    await _requestCloseEditorViews([
      for (final group in _groups.values.toList(growable: false))
        for (final doc in group.docs.toList(growable: false))
          (group: group, doc: doc),
    ]);
  }

  void _closeDoc(int id, {EditorGroup? group}) {
    final owner = group ??
        (_focused.docs.any((doc) => doc.id == id) ? _focused : _ownerOf(id));
    if (owner == null) return;
    final doc = owner.docs.where((d) => d.id == id).firstOrNull;
    if (doc == null) return;
    unawaited(_requestCloseEditorViews([(group: owner, doc: doc)]));
  }

  Future<void> _requestCloseEditorViews(
    Iterable<_EditorCloseTarget> requestedTargets,
  ) async {
    final targets = <_EditorCloseTarget>[];
    final seenViews = <OpenDoc>{};
    for (final target in requestedTargets) {
      if (!target.group.docs.any((doc) => identical(doc, target.doc)) ||
          !seenViews.add(target.doc) ||
          _editorCloseInProgress.contains(target.doc._shared)) {
        continue;
      }
      targets.add(target);
    }
    if (targets.isEmpty) return;

    final lockedDocuments = targets.map((target) => target.doc._shared).toSet();
    _editorCloseInProgress.addAll(lockedDocuments);
    try {
      final compareBindings = _snapshotCompareViews.values
          .where((binding) =>
              targets.any((target) => target.doc.sameDocumentAs(binding.view)))
          .toSet()
          .toList(growable: false);
      for (final binding in compareBindings) {
        binding.closeRoute?.call();
      }
      if (compareBindings.isNotEmpty) {
        await Future.wait(
          compareBindings.map((binding) => binding.closed.future),
        );
      }
      if (!mounted) return;

      final currentTargets = targets
          .where((target) => target.group.docs.any(
                (doc) => identical(doc, target.doc),
              ))
          .toList(growable: false);
      if (currentTargets.isEmpty) return;

      final affectedDocuments = <OpenDoc>[];
      for (final target in currentTargets) {
        if (affectedDocuments.every((doc) => !doc.sameDocumentAs(target.doc))) {
          affectedDocuments.add(target.doc);
        }
      }
      for (final doc in affectedDocuments) {
        for (final view in _viewsOf(doc).toList(growable: false)) {
          _flushInput(view, commitComposition: true);
        }
        _updateDirty(doc);
      }

      final finalDocuments = <OpenDoc>[];
      for (final target in currentTargets) {
        final closingViews = currentTargets
            .where((candidate) => candidate.doc.sameDocumentAs(target.doc))
            .length;
        if (closingViews < target.doc.sharedViewCount ||
            finalDocuments.any((doc) => doc.sameDocumentAs(target.doc))) {
          continue;
        }
        finalDocuments.add(target.doc);
      }

      final standardDirtyDocuments = finalDocuments
          .where((doc) =>
              doc.isDirty && !(doc.mergeResultSession?.isDisposed == false))
          .toList(growable: false);
      if (standardDirtyDocuments.isNotEmpty) {
        final decision = await _confirmDirtyEditorClose(
          standardDirtyDocuments,
        );
        if (!mounted ||
            decision == null ||
            decision == _DirtyEditorCloseDecision.cancel) {
          return;
        }
        if (decision == _DirtyEditorCloseDecision.save) {
          for (final doc in standardDirtyDocuments) {
            try {
              if (doc.path == null) {
                await _saveAsDoc(doc);
              } else {
                await _saveDocToPath(doc, doc.path!);
              }
            } on Object catch (error) {
              if (mounted) {
                setState(() => _statusDetail = '保存 ${doc.name} 失败：$error');
              }
              return;
            }
            if (!mounted) return;
            if (doc.isDirty || doc.diskState != DiskDocumentState.current) {
              setState(() => _statusDetail = '保存未完成；编辑器仍保持打开');
              return;
            }
          }
        }
      }

      for (final doc in finalDocuments) {
        final mergeSession = doc.mergeResultSession;
        if (mergeSession == null || mergeSession.isDisposed) continue;
        final ownerTarget = currentTargets.firstWhere(
          (target) => target.doc.sameDocumentAs(doc),
        );
        final closed = await _closeMergeResultDocument(
          ownerTarget.group,
          doc,
          mergeSession,
          closeTargets: currentTargets
              .where((target) => target.doc.sameDocumentAs(doc))
              .toList(growable: false),
        );
        if (!mounted || !closed) return;
      }

      for (final target in currentTargets) {
        if (target.group.docs.any((doc) => identical(doc, target.doc))) {
          if (_editorTabSizing.value == EditorTabSizing.fixed &&
              _editorTabPointerInside.contains(target.group.region)) {
            final widths = _editorTabLastWidths[target.group.region];
            if (widths != null) {
              _editorTabHeldWidths[target.group.region] =
                  Map<int, double>.of(widths);
            }
          }
          _closeDocNow(target.group, target.doc);
        }
      }
    } finally {
      _editorCloseInProgress.removeAll(lockedDocuments);
    }
  }

  Future<_DirtyEditorCloseDecision?> _confirmDirtyEditorClose(
    List<OpenDoc> documents,
  ) {
    final names = documents.map((doc) => '“${doc.name}”').join('、');
    return showDialog<_DirtyEditorCloseDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('editor-close-dirty-dialog'),
        title: const Text('保存更改？'),
        content: Text('$names 有未保存的更改。关闭前要保存吗？'),
        actions: [
          TextButton(
            key: const ValueKey('editor-close-cancel'),
            onPressed: () => Navigator.pop(
              dialogContext,
              _DirtyEditorCloseDecision.cancel,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('editor-close-discard'),
            onPressed: () => Navigator.pop(
              dialogContext,
              _DirtyEditorCloseDecision.discard,
            ),
            child: const Text('不保存'),
          ),
          FilledButton(
            key: const ValueKey('editor-close-save'),
            onPressed: () => Navigator.pop(
              dialogContext,
              _DirtyEditorCloseDecision.save,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<bool> _closeMergeResultDocument(
    EditorGroup owner,
    OpenDoc doc,
    MergeResultSession session, {
    List<_EditorCloseTarget>? closeTargets,
  }) async {
    if (!_mergeCloseInProgress.add(doc.id)) return false;
    try {
      final prompt = session.closePrompt;
      final action = prompt.actions.length == 1 &&
              prompt.actions.contains(MergeResultCloseAction.close)
          ? MergeResultCloseAction.close
          : await showDialog<MergeResultCloseAction>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                key: const ValueKey('merge-result-close-dialog'),
                title: const Text('关闭合并结果？'),
                content: Text(
                  prompt.isDirty
                      ? '“${doc.name}”有未保存的修改，'
                          '仍有 ${prompt.unresolvedConflictCount} 个冲突未解决。'
                      : '仍有 ${prompt.unresolvedConflictCount} 个冲突未解决。',
                ),
                actions: [
                  if (prompt.actions.contains(MergeResultCloseAction.cancel))
                    TextButton(
                      key: const ValueKey('merge-result-close-cancel'),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        MergeResultCloseAction.cancel,
                      ),
                      child: const Text('继续编辑'),
                    ),
                  if (prompt.actions.contains(MergeResultCloseAction.discard))
                    TextButton(
                      key: const ValueKey('merge-result-close-discard'),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        MergeResultCloseAction.discard,
                      ),
                      child: const Text('不保存'),
                    ),
                  if (prompt.actions
                      .contains(MergeResultCloseAction.closeWithConflicts))
                    FilledButton(
                      key: const ValueKey('merge-result-close-with-conflicts'),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        MergeResultCloseAction.closeWithConflicts,
                      ),
                      child: const Text('仍然关闭'),
                    ),
                  if (prompt.actions.contains(MergeResultCloseAction.save))
                    FilledButton(
                      key: const ValueKey('merge-result-close-save'),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        MergeResultCloseAction.save,
                      ),
                      child: Text(
                        prompt.saveLabel ==
                                MergeResultSaveLabel.saveWithConflicts
                            ? '保存并保留未解冲突'
                            : '保存',
                      ),
                    ),
                ],
              ),
            );
      if (!mounted || action == null) return false;

      final outcome = await session.finishClose(
        action,
        save: () async {
          if (doc.path == null) {
            await _saveAsDoc(doc);
          } else {
            await _saveDocToPath(doc, doc.path!);
          }
          return mounted &&
              !doc.doc.isDirty &&
              doc.diskState == DiskDocumentState.current;
        },
        revert: () async {
          try {
            final current = doc.doc.resync();
            final savedText = session.latestSavedResult;
            final operations = diffToOps(current.content, savedText);
            if (operations.isNotEmpty) {
              doc.doc.applyWith(current.version, operations);
            }
            doc.doc.setSavepoint(savedText);
            doc.fileOptions = doc.savedFileOptions;
            doc.diskState = DiskDocumentState.current;
            doc.conflictBaselineKnown = true;
            doc.undoStack.clear();
            doc.lastEditAt = null;
            _updateDirty(doc);
            doc.replaceInputWindow(
              doc.selection.extentOffset.clamp(0, savedText.length).toInt(),
            );
            return !doc.doc.isDirty && doc.doc.resync().content == savedText;
          } on Object {
            return false;
          }
        },
        closeResultDocument: () async {
          if (!mounted) return;
          final targets = closeTargets ?? [(group: owner, doc: doc)];
          for (final target in targets) {
            if (target.group.docs.any((view) => identical(view, target.doc))) {
              _closeDocNow(target.group, target.doc);
            }
          }
        },
      );
      if (outcome != MergeResultCloseOutcome.closed && mounted) {
        final detail = switch (outcome) {
          MergeResultCloseOutcome.cancelled => null,
          MergeResultCloseOutcome.saveFailed => '保存失败，合并结果仍保持打开',
          MergeResultCloseOutcome.resultChangedDuringSave =>
            '保存期间合并结果发生变化，文档仍保持打开',
          MergeResultCloseOutcome.revertFailed => '无法还原到最近保存的结果，文档仍保持打开',
          MergeResultCloseOutcome.invalidAction => '合并结果关闭操作已失效，请重试',
          MergeResultCloseOutcome.closed => null,
        };
        if (detail != null) setState(() => _statusDetail = detail);
      }
      return outcome == MergeResultCloseOutcome.closed;
    } on MergeResultSessionException {
      if (mounted) {
        setState(() => _statusDetail = '合并结果已在会话外变化，请先同步会话状态');
      }
      return false;
    } finally {
      _mergeCloseInProgress.remove(doc.id);
    }
  }

  void _closeDocNow(EditorGroup owner, OpenDoc doc,
      {bool keepEmptyGroup = false}) {
    if (!owner.docs.any((view) => identical(view, doc))) return;
    if (_lastExplorerClickPath == doc.path) {
      _lastExplorerClickPath = null;
      _lastExplorerClickClock = null;
    }
    final id = doc.id;
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
    if (owner.previewDocId == id) owner.previewDocId = null;
    owner.stickyDocIds.remove(id);
    owner.recentDocIds.remove(id);
    owner.docs.remove(doc);
    final nextActiveId = wasActive ? _mostRecentDocument(owner)?.id : null;
    if (owner.docs.isEmpty) {
      _editorTabLastWidths.remove(owner.region);
      _editorTabHeldWidths.remove(owner.region);
    }
    doc.disposeView();
    if (isLastView) _navigationHistory.closeDocument(id);
    setState(() {
      _syntaxByDoc = nextSyntax;
      _syntaxVersionByDoc = nextSyntaxVersion;
      _semanticTokensByDoc = nextSemanticTokens;
      _semanticTokensVersionByDoc = nextSemanticTokensVersion;
      if (wasActive) {
        owner.activeDocId = nextActiveId;
        _noteActiveDocument(owner, nextActiveId);
      }
      // 组空且不是唯一的组 → 摘除该组（布局树自动折叠）
      if (owner.docs.isEmpty && _groups.length > 1 && !keepEmptyGroup) {
        _layout.removeRegion(owner.region);
        _groups.remove(owner.region);
        if (_focusedRegion == owner.region) {
          // 上游 doRemoveEmptyGroup：激活剩余组中最近活动的组。
          _focusedRegion = _mostRecentlyActiveRegion(excluding: owner.region) ??
              _groups.keys.first;
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

  Map<String, _EditorGroupBounds> _layoutRegionBounds() {
    final bounds = <String, _EditorGroupBounds>{};

    void visit(
      WbNode node,
      double left,
      double top,
      double right,
      double bottom,
    ) {
      if (node is WbLeaf) {
        bounds[node.region] = _EditorGroupBounds(left, top, right, bottom);
        return;
      }
      if (node is! WbSplit) return;

      final weights = node.children.map((child) {
        if (child is WbLeaf && child.collapsed) return 0.0;
        final weight = child is WbLeaf && child.fixedExtent != null
            ? child.fixedExtent!
            : child.weight;
        return weight < 0 ? 0.0 : weight;
      }).toList();
      final totalWeight =
          weights.fold<double>(0, (sum, weight) => sum + weight);
      var cursor = node.axis == Axis.horizontal ? left : top;
      for (var index = 0; index < node.children.length; index++) {
        final fraction = totalWeight <= 0
            ? 1 / node.children.length
            : weights[index] / totalWeight;
        final extent =
            (node.axis == Axis.horizontal ? right - left : bottom - top) *
                fraction;
        final child = node.children[index];
        if (node.axis == Axis.horizontal) {
          visit(child, cursor, top, cursor + extent, bottom);
        } else {
          visit(child, left, cursor, right, cursor + extent);
        }
        cursor += extent;
      }
    }

    visit(_layout.root, 0, 0, 1, 1);
    return bounds;
  }

  double _intervalGap(
    double firstStart,
    double firstEnd,
    double secondStart,
    double secondEnd,
  ) {
    if (firstEnd < secondStart) return secondStart - firstEnd;
    if (secondEnd < firstStart) return firstStart - secondEnd;
    return 0;
  }

  String? _adjacentEditorRegion(
    String sourceRegion,
    _EditorGroupMoveDirection direction,
  ) {
    final bounds = _layoutRegionBounds();
    final source = bounds[sourceRegion];
    if (source == null) return null;

    String? bestRegion;
    var bestAlongGap = double.infinity;
    var bestAcrossGap = double.infinity;
    var bestAcrossCenter = double.infinity;
    for (final region in _groups.keys) {
      if (region == sourceRegion || !_isEditorRegion(region)) continue;
      final candidate = bounds[region];
      if (candidate == null ||
          candidate.right - candidate.left <= 1e-9 ||
          candidate.bottom - candidate.top <= 1e-9) {
        continue;
      }

      final sourceCenter =
          direction.axis == Axis.horizontal ? source.centerX : source.centerY;
      final candidateCenter = direction.axis == Axis.horizontal
          ? candidate.centerX
          : candidate.centerY;
      final pointsInDirection = direction.insertBefore
          ? candidateCenter < sourceCenter
          : candidateCenter > sourceCenter;
      if (!pointsInDirection) continue;

      final alongGap = switch (direction) {
        _EditorGroupMoveDirection.left =>
          (source.left - candidate.right).clamp(0.0, double.infinity),
        _EditorGroupMoveDirection.right =>
          (candidate.left - source.right).clamp(0.0, double.infinity),
        _EditorGroupMoveDirection.up =>
          (source.top - candidate.bottom).clamp(0.0, double.infinity),
        _EditorGroupMoveDirection.down =>
          (candidate.top - source.bottom).clamp(0.0, double.infinity),
      };
      final acrossGap = direction.axis == Axis.horizontal
          ? _intervalGap(
              source.top, source.bottom, candidate.top, candidate.bottom)
          : _intervalGap(
              source.left, source.right, candidate.left, candidate.right);
      final acrossCenter = direction.axis == Axis.horizontal
          ? (source.centerY - candidate.centerY).abs()
          : (source.centerX - candidate.centerX).abs();

      final candidateActivationOrder =
          _groups[region]?.lastActivationOrder ?? -1;
      final bestActivationOrder =
          _groups[bestRegion]?.lastActivationOrder ?? -1;
      final closer = alongGap < bestAlongGap - 1e-9 ||
          (alongGap - bestAlongGap).abs() <= 1e-9 &&
              (acrossGap < bestAcrossGap - 1e-9 ||
                  (acrossGap - bestAcrossGap).abs() <= 1e-9 &&
                      (acrossCenter < bestAcrossCenter - 1e-9 ||
                          (acrossCenter - bestAcrossCenter).abs() <= 1e-9 &&
                              candidateActivationOrder >
                                  bestActivationOrder));
      if (!closer) continue;
      bestRegion = region;
      bestAlongGap = alongGap;
      bestAcrossGap = acrossGap;
      bestAcrossCenter = acrossCenter;
    }
    return bestRegion;
  }

  void _focusEditorAfterLayout(EditorGroup group, OpenDoc view) {
    final focusNode = _focusNodeFor(group, view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _focusedRegion != group.region ||
          !identical(group.active, view)) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _moveFocusedEditorToGroup(_EditorGroupMoveDirection direction) {
    final source = _focused;
    final active = source.active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);

    var targetRegion = _adjacentEditorRegion(source.region, direction);
    if (targetRegion == null) {
      var index = 2;
      while (_groups.containsKey('editor-$index')) {
        index++;
      }
      targetRegion = 'editor-$index';
      if (!_layout.splitRegion(
        source.region,
        targetRegion,
        direction.axis,
        insertBefore: direction.insertBefore,
      )) {
        setState(() => _statusDetail = '移动失败：区域 ${source.region} 不可拆分');
        return;
      }
      _ensureGroupsFromLayout();
    }

    final target = _groups[targetRegion];
    if (target == null || identical(target, source)) return;
    final movingPreview =
        source.previewDocId == active.id && !active.isDirty;
    final movingSticky = source.stickyDocIds.contains(active.id);
    OpenDoc? existingView;
    for (final view in target.docs) {
      if (view.sameDocumentAs(active)) {
        existingView = view;
        break;
      }
    }
    if (existingView != null) {
      if (movingSticky && !target.stickyDocIds.contains(existingView.id)) {
        target.stickyDocIds.add(existingView.id);
        _normalizeStickyOrder(target);
      }
      _closeDocNow(source, active);
      if (!mounted) return;
      setState(() {
        target.activeDocId = existingView!.id;
        _noteActiveDocument(target, existingView.id);
        _focusedRegion = target.region;
        _scheduleStateSave();
      });
      _syncCommandContext();
      _focusEditorAfterLayout(target, existingView);
      return;
    }

    final removeSourceRegion = source.docs.length == 1 && _groups.length > 1;
    if (removeSourceRegion && !_layout.removeRegion(source.region)) {
      setState(() => _statusDetail = '移动失败：无法移除空编辑器组 ${source.region}');
      return;
    }
    if (movingPreview) _replaceCleanPreviewBeforeOpen(target);

    setState(() {
      source.docs.removeWhere((view) => identical(view, active));
      source.stickyDocIds.remove(active.id);
      source.recentDocIds.remove(active.id);
      if (source.previewDocId == active.id) source.previewDocId = null;
      if (source.docs.isNotEmpty && source.activeDocId == active.id) {
        source.activeDocId = _mostRecentDocument(source)?.id;
        _noteActiveDocument(source, source.activeDocId);
      }
      target.docs.add(active);
      if (movingSticky) target.stickyDocIds.add(active.id);
      _normalizeStickyOrder(source);
      _normalizeStickyOrder(target);
      target.activeDocId = active.id;
      _noteActiveDocument(target, active.id);
      if (movingPreview) target.previewDocId = active.id;

      final sourceFocusKey = _focusKeyFor(source, active);
      final targetFocusKey = _focusKeyFor(target, active);
      final movedFocusNode = _editorFocusNodes.remove(sourceFocusKey);
      if (movedFocusNode != null) {
        final oldTargetFocusNode = _editorFocusNodes.remove(targetFocusKey);
        if (oldTargetFocusNode != null &&
            oldTargetFocusNode != movedFocusNode) {
          oldTargetFocusNode.dispose();
        }
        _editorFocusNodes[targetFocusKey] = movedFocusNode;
      }

      if (source.docs.isEmpty && removeSourceRegion) {
        _groups.remove(source.region);
      }
      _focusedRegion = target.region;
      _statusDetail = '已移动编辑器：${source.region} → ${target.region}';
      _scheduleStateSave();
    });
    _syncCommandContext();
    _focusEditorAfterLayout(target, active);
  }

  /// Split the focused editor leaf and copy its active document into the new
  /// group. The document remains shared while its editor view state is fresh.
  void _splitFocusedGroup({
    Axis axis = Axis.horizontal,
    bool insertBefore = false,
  }) {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final region = _focusedRegion;
    var i = 2;
    while (_groups.containsKey('editor-$i')) {
      i++;
    }
    final fresh = 'editor-$i';
    if (!_layout.splitRegion(
      region,
      fresh,
      axis,
      insertBefore: insertBefore,
    )) {
      setState(() => _statusDetail = '拆分失败：区域 $region 不可拆分');
      return;
    }
    final freshView = OpenDoc.viewOf(active);
    setState(() {
      _ensureGroupsFromLayout();
      final group = _groups[fresh]!;
      group.docs.add(freshView);
      if (_groups[region]?.stickyDocIds.contains(active.id) == true) {
        group.stickyDocIds.add(freshView.id);
        _normalizeStickyOrder(group);
      }
      group.activeDocId = freshView.id;
      _noteActiveDocument(group, freshView.id);
      if (_groups[region]?.previewDocId == active.id && !active.isDirty) {
        group.previewDocId = freshView.id;
      }
      _focusedRegion = fresh; // 新组获焦（对标 VS Code 拆分行为）
      _statusDetail = '已拆分编辑器：$region → $fresh';
      _scheduleStateSave();
    });
    _syncCommandContext();
    _scheduleSyntaxRefresh(freshView.id);
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

  Future<void> _showInsertSnippetDialog() async {
    final controller = TextEditingController(text: r'${1:name} = $1;$0');
    final template = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('插入片段'),
        content: TextField(
          key: const ValueKey('snippet-template-input'),
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '片段模板',
            helperText:
                r'支持 $1、${1:默认值}、$0、$TM_SELECTED_TEXT、$TM_CURRENT_LINE、$TM_CURRENT_WORD 和 $RELATIVE_FILEPATH',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('snippet-template-confirm'),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (template != null) await _insertSnippetTemplate(template);
  }

  Future<void> _insertSnippetFromArguments(Object? arguments) async {
    String? template;
    if (arguments is String) {
      template = arguments;
    } else if (arguments is Map) {
      final candidate = arguments['snippet'] ?? arguments['template'];
      if (candidate is String) template = candidate;
    }
    if (template == null) {
      await _showInsertSnippetDialog();
      return;
    }
    await _insertSnippetTemplate(template);
  }

  Future<void> _insertSnippetTemplate(String template) async {
    final doc = _active;
    if (doc == null) return;
    if (doc.inputWindow.hasComposition) {
      if (mounted) setState(() => _statusDetail = '输入法组合输入中，无法插入片段');
      return;
    }

    if (doc.additionalSelections.isNotEmpty) {
      await _insertSnippetTemplateAtSelections(doc, template);
      return;
    }
    _flushInput(doc);
    final selection = doc.selection;
    final window = doc.inputWindow;
    final field = doc.inputFieldKey.currentState;
    final localStart = selection.start - window.startUtf16;
    final localEnd = selection.end - window.startUtf16;
    final value = doc.editingValue;
    if (field == null ||
        doc.crossWindowSelection != null ||
        doc.columnSelection != null ||
        doc.additionalSelections.isNotEmpty ||
        !selection.isValid ||
        localStart < 0 ||
        localStart > value.text.length ||
        localEnd > window.text.length ||
        localEnd > value.text.length ||
        window.version != doc.doc.version) {
      if (mounted) setState(() => _statusDetail = '片段插入需要输入窗内的单个选区');
      return;
    }

    final selectedText = value.text.substring(localStart, localEnd);
    final cursorPosition = doc.doc.positionAt(selection.extentOffset);
    final lineVariables = snippetLineVariables(cursorPosition.line);
    final clipboardVariables = <String, String>{};
    if (snippetTemplateUsesVariable(template, 'CLIPBOARD')) {
      try {
        final clipboard = await EditorClipboard.read().timeout(
          const Duration(seconds: 6),
        );
        final currentWindow = doc.inputWindow;
        if (!mounted ||
            _active?.id != doc.id ||
            doc.doc.version != window.version ||
            currentWindow.version != window.version ||
            currentWindow.startUtf16 != window.startUtf16 ||
            doc.selection != selection ||
            doc.editingValue != value ||
            !identical(doc.inputFieldKey.currentState, field)) {
          if (mounted) {
            setState(
              () => _statusDetail = '片段插入未应用：读取剪贴板时编辑状态已变化',
            );
          }
          return;
        }

        final clipboardText = clipboard?.text;
        if (clipboardText != null &&
            clipboardText.length > maxSnippetClipboardUtf16) {
          if (mounted) {
            setState(() => _statusDetail = '剪贴板内容过长，无法用于片段插入');
          }
          return;
        }
        clipboardVariables.addAll(snippetClipboardVariables(clipboardText));
      } on TimeoutException {
        if (mounted) setState(() => _statusDetail = '读取剪贴板超时，片段未插入');
        return;
      } on Object {
        if (mounted) setState(() => _statusDetail = '读取剪贴板失败，片段未插入');
        return;
      }
    }
    final homeVariable = Platform.isWindows ? 'USERPROFILE' : 'HOME';
    final pathVariables = snippetDocumentPathVariables(
      doc.uri == null ? null : doc.path,
      windows: Platform.isWindows,
      userHome: Platform.environment[homeVariable],
    );
    final relativeFilePathVariables =
        snippetTemplateUsesVariable(template, 'RELATIVE_FILEPATH')
            ? snippetRelativeFilePathVariables(
                doc.uri == null ? null : doc.path,
                _workspaceRoot,
                windows: Platform.isWindows,
                userHome: Platform.environment[homeVariable],
              )
            : const <String, String>{};
    final needsWorkspaceVariables =
        snippetTemplateUsesVariable(template, 'WORKSPACE_NAME') ||
            snippetTemplateUsesVariable(template, 'WORKSPACE_FOLDER');
    final workspaceVariables = needsWorkspaceVariables
        ? snippetWorkspaceVariables(
            _workspaceRoot,
            windows: Platform.isWindows,
          )
        : const <String, String>{};
    final currentLineVariables = <String, String>{};
    final currentWordVariables = <String, String>{};
    final needsCurrentLine =
        snippetTemplateUsesVariable(template, 'TM_CURRENT_LINE');
    final needsCurrentWord =
        snippetTemplateUsesVariable(template, 'TM_CURRENT_WORD');
    if (needsCurrentLine || needsCurrentWord) {
      try {
        final boundary = doc.doc.lineBoundary(selection.extentOffset);
        if (cursorPosition.version != boundary.version ||
            boundary.version != window.version) {
          doc.replaceInputWindow(selection.extentOffset);
          if (mounted) setState(() => _statusDetail = '片段插入未应用：文档同步版本已变化');
          return;
        }
        if (needsCurrentLine) {
          final lineLengthUtf16 = boundary.endUtf16 - boundary.startUtf16;
          if (lineLengthUtf16 > window.maxWindowUtf16) {
            if (mounted) {
              setState(() => _statusDetail = '当前行过长，无法在片段输入窗中展开');
            }
            return;
          }
          if (lineLengthUtf16 == 0) {
            currentLineVariables.addAll(snippetCurrentLineVariables(''));
          } else {
            final lineRange = doc.doc.readRange(
              boundary.startUtf16,
              maxLenUtf16: lineLengthUtf16,
            );
            if (lineRange.version != boundary.version ||
                lineRange.startUtf16 != boundary.startUtf16 ||
                lineRange.endUtf16 != boundary.endUtf16 ||
                lineRange.text.length != lineLengthUtf16) {
              doc.replaceInputWindow(selection.extentOffset);
              if (mounted) {
                setState(() => _statusDetail = '当前行读取失败：文档同步版本已变化');
              }
              return;
            }
            currentLineVariables.addAll(
              snippetCurrentLineVariables(lineRange.text),
            );
          }
        }
        if (needsCurrentWord) {
          final caretOffset = selection.extentOffset;
          final lineLengthUtf16 = boundary.endUtf16 - boundary.startUtf16;
          var contextStart = boundary.startUtf16;
          var contextEnd = boundary.endUtf16;
          if (lineLengthUtf16 > snippetCurrentWordContextUtf16) {
            const halfContext = snippetCurrentWordContextUtf16 ~/ 2;
            final lineColumnUtf16 = caretOffset - boundary.startUtf16;
            final desiredStart =
                boundary.startUtf16 + lineColumnUtf16 + 1 - halfContext;
            if (desiredStart > contextStart) contextStart = desiredStart;
            final desiredEnd =
                boundary.startUtf16 + lineColumnUtf16 + 1 + halfContext;
            if (desiredEnd < contextEnd) contextEnd = desiredEnd;
          }

          late final DocumentPosition contextPosition;
          try {
            contextPosition = doc.doc.positionAt(contextStart);
          } on AlulaException catch (error) {
            if (error.code != 'InvalidUtf16Offset' ||
                contextStart <= boundary.startUtf16) {
              rethrow;
            }
            contextStart--;
            contextPosition = doc.doc.positionAt(contextStart);
          }
          if (contextPosition.version != boundary.version ||
              contextPosition.offsetUtf16 != contextStart) {
            doc.replaceInputWindow(selection.extentOffset);
            if (mounted) {
              setState(() => _statusDetail = '当前单词读取失败：文档同步版本已变化');
            }
            return;
          }
          if (contextEnd - contextStart > snippetCurrentWordContextUtf16) {
            contextEnd = contextStart + snippetCurrentWordContextUtf16;
          }
          if (contextEnd < caretOffset || contextStart > caretOffset) {
            doc.replaceInputWindow(selection.extentOffset);
            if (mounted) {
              setState(() => _statusDetail = '当前单词读取失败：光标范围无效');
            }
            return;
          }
          if (contextEnd == contextStart) {
            currentWordVariables.addAll(snippetCurrentWordVariables('', 0));
          } else {
            final wordRange = doc.doc.readRange(
              contextStart,
              maxLenUtf16: contextEnd - contextStart,
            );
            if (wordRange.version != boundary.version ||
                wordRange.startUtf16 != contextStart ||
                wordRange.endUtf16 < caretOffset ||
                wordRange.endUtf16 > contextEnd ||
                wordRange.text.length !=
                    wordRange.endUtf16 - wordRange.startUtf16) {
              doc.replaceInputWindow(selection.extentOffset);
              if (mounted) {
                setState(() => _statusDetail = '当前单词读取失败：文档同步版本已变化');
              }
              return;
            }
            currentWordVariables.addAll(
              snippetCurrentWordVariables(
                wordRange.text,
                caretOffset - wordRange.startUtf16,
              ),
            );
          }
        }
      } on AlulaException catch (error) {
        if (mounted) {
          final variableName = needsCurrentLine ? '当前行' : '当前单词';
          setState(() => _statusDetail =
              '$variableName 读取失败：${error.code} ${error.detail}');
        }
        return;
      }
    }
    late final SnippetExpansion expansion;
    try {
      expansion = await expandSnippetTemplate(
        template,
        variables: {
          'TM_SELECTED_TEXT': selectedText,
          ...snippetFilenameVariables(doc.uri == null ? null : doc.name),
          ...clipboardVariables,
          ...pathVariables,
          ...relativeFilePathVariables,
          ...workspaceVariables,
          ...lineVariables,
          ...currentLineVariables,
          ...currentWordVariables,
        },
      );
    } on SnippetTemplateException catch (error) {
      if (mounted) setState(() => _statusDetail = '片段插入失败：${error.message}');
      return;
    }

    if (!mounted) return;
    final currentWindow = doc.inputWindow;
    if (_active?.id != doc.id ||
        doc.doc.version != window.version ||
        currentWindow.version != window.version ||
        currentWindow.startUtf16 != window.startUtf16 ||
        currentWindow.text != window.text ||
        doc.selection != selection ||
        doc.editingValue != value ||
        doc.crossWindowSelection != null ||
        doc.columnSelection != null ||
        doc.additionalSelections.isNotEmpty ||
        !identical(doc.inputFieldKey.currentState, field)) {
      if (mounted) setState(() => _statusDetail = '片段插入未应用：编辑状态已变化');
      return;
    }

    final nextLength =
        value.text.length - (localEnd - localStart) + expansion.text.length;
    if (nextLength > window.maxWindowUtf16) {
      if (mounted) setState(() => _statusDetail = '片段展开后超过当前输入窗上限');
      return;
    }

    _clearSnippetSession();
    final replacement = value.text.replaceRange(
      localStart,
      localEnd,
      expansion.text,
    );
    final firstTabstop = expansion.tabstopOrder.firstOrNull;
    final firstRange = firstTabstop == null
        ? null
        : expansion.rangesFor(firstTabstop).firstOrNull;
    final nextSelection = firstRange == null
        ? TextSelection.collapsed(offset: localStart + expansion.text.length)
        : TextSelection(
            baseOffset: localStart + firstRange.startUtf16,
            extentOffset: localStart + firstRange.endUtf16,
          );

    doc.lastEditAt = null;
    field.applyFormattedValue(TextEditingValue(
      text: replacement,
      selection: nextSelection,
    ));
    field.flushPending();

    final absoluteStart = window.startUtf16 + localStart;
    if (firstTabstop != null) {
      final lineBreakBefore =
          localStart == 0 ? -1 : value.text.lastIndexOf('\n', localStart - 1);
      final linePrefix = value.text.substring(lineBreakBefore + 1, localStart);
      final lineLeadingWhitespace =
          RegExp(r'^[ \t]*').firstMatch(linePrefix)?.group(0) ?? '';
      final session = SnippetSession(
        expansion,
        documentOffsetUtf16: absoluteStart,
        version: doc.doc.version,
        lineLeadingWhitespace: lineLeadingWhitespace,
      );
      _snippetSession = session;
      _snippetSessionDocId = doc.id;
      _snippetSessionView = doc;
      _setDocSelections(doc, session.currentSelections);
    } else {
      _setDocSelections(doc, [
        TextSelection.collapsed(offset: absoluteStart + expansion.text.length),
      ]);
    }
    field.requestFocus();
    if (mounted) setState(() => _statusDetail = '已插入片段');
  }

  Future<void> _insertSnippetTemplateAtSelections(
    OpenDoc doc,
    String template,
  ) async {
    _flushInput(doc);
    final window = doc.inputWindow;
    final field = doc.inputFieldKey.currentState;
    final value = doc.editingValue;
    final primarySelection = doc.selection;
    final selections = doc.selectionSet;
    final additionalSelections = List<TextSelection>.of(
      doc.additionalSelections,
    );
    final capacity = window.maxWindowUtf16 - window.compositionReserveUtf16 - 1;
    if (field == null ||
        doc.crossWindowSelection != null ||
        doc.columnSelection != null ||
        window.version != doc.doc.version ||
        window.pendingText != null ||
        selections.isEmpty ||
        additionalSelections.length + 1 > _maxSnippetInsertionSelections ||
        additionalSelections.any((selection) =>
            !selection.isValid ||
            selection.start < window.startUtf16 ||
            selection.end > window.endUtf16) ||
        selections.any((selection) =>
            !selection.isValid ||
            selection.start < window.startUtf16 ||
            selection.end > window.endUtf16 ||
            selection.start - window.startUtf16 > value.text.length ||
            selection.end - window.startUtf16 > value.text.length)) {
      if (mounted) {
        setState(() => _statusDetail =
            '多光标片段插入仅支持同一输入窗内最多 $_maxSnippetInsertionSelections 个普通选区');
      }
      return;
    }

    final expectedVersion = doc.doc.version;
    final windowStart = window.startUtf16;
    final windowText = window.text;
    bool isCurrentSnapshot() {
      final currentWindow = doc.inputWindow;
      return mounted &&
          !_disposing &&
          identical(_active, doc) &&
          doc.doc.version == expectedVersion &&
          identical(doc.inputFieldKey.currentState, field) &&
          currentWindow.version == window.version &&
          currentWindow.startUtf16 == windowStart &&
          currentWindow.text == windowText &&
          doc.editingValue == value &&
          doc.selection == primarySelection &&
          listEquals(doc.selectionSet, selections) &&
          listEquals(doc.additionalSelections, additionalSelections) &&
          doc.crossWindowSelection == null &&
          doc.columnSelection == null &&
          !currentWindow.hasComposition;
    }

    final clipboardVariables = <String, String>{};
    if (snippetTemplateUsesVariable(template, 'CLIPBOARD')) {
      try {
        final clipboard = await EditorClipboard.read().timeout(
          const Duration(seconds: 6),
        );
        if (!isCurrentSnapshot()) {
          if (mounted) {
            setState(() => _statusDetail = '片段插入未应用：读取剪贴板时编辑状态已变化');
          }
          return;
        }
        final clipboardText = clipboard?.text;
        if (clipboardText != null &&
            clipboardText.length > maxSnippetClipboardUtf16) {
          if (mounted) setState(() => _statusDetail = '剪贴板内容过长，无法用于片段插入');
          return;
        }
        clipboardVariables.addAll(snippetClipboardVariables(clipboardText));
      } on TimeoutException {
        if (mounted) setState(() => _statusDetail = '读取剪贴板超时，片段未插入');
        return;
      } on Object {
        if (mounted) setState(() => _statusDetail = '读取剪贴板失败，片段未插入');
        return;
      }
    }

    final homeVariable = Platform.isWindows ? 'USERPROFILE' : 'HOME';
    final commonVariables = <String, String>{
      ...snippetFilenameVariables(doc.uri == null ? null : doc.name),
      ...clipboardVariables,
      ...snippetDocumentPathVariables(
        doc.uri == null ? null : doc.path,
        windows: Platform.isWindows,
        userHome: Platform.environment[homeVariable],
      ),
      if (snippetTemplateUsesVariable(template, 'RELATIVE_FILEPATH'))
        ...snippetRelativeFilePathVariables(
          doc.uri == null ? null : doc.path,
          _workspaceRoot,
          windows: Platform.isWindows,
          userHome: Platform.environment[homeVariable],
        ),
      if (snippetTemplateUsesVariable(template, 'WORKSPACE_NAME') ||
          snippetTemplateUsesVariable(template, 'WORKSPACE_FOLDER'))
        ...snippetWorkspaceVariables(
          _workspaceRoot,
          windows: Platform.isWindows,
        ),
    };
    final needsCurrentLine =
        snippetTemplateUsesVariable(template, 'TM_CURRENT_LINE');
    final needsCurrentWord =
        snippetTemplateUsesVariable(template, 'TM_CURRENT_WORD');

    Map<String, String> variablesForSelection(TextSelection selection) {
      final localStart = selection.start - windowStart;
      final localEnd = selection.end - windowStart;
      final selectedText = value.text.substring(localStart, localEnd);
      final cursorPosition = doc.doc.positionAt(selection.extentOffset);
      if (cursorPosition.version != expectedVersion ||
          cursorPosition.offsetUtf16 != selection.extentOffset) {
        throw const SnippetTemplateException(
          '选区位置已过期，无法读取片段变量',
          0,
        );
      }
      final variables = <String, String>{
        'TM_SELECTED_TEXT': selectedText,
        ...snippetLineVariables(cursorPosition.line),
      };
      if (!needsCurrentLine && !needsCurrentWord) return variables;

      final boundary = doc.doc.lineBoundary(selection.extentOffset);
      if (boundary.version != expectedVersion) {
        throw const SnippetTemplateException(
          '文档版本已变化，无法读取片段行上下文',
          0,
        );
      }
      final lineLengthUtf16 = boundary.endUtf16 - boundary.startUtf16;
      if (needsCurrentLine) {
        if (lineLengthUtf16 > window.maxWindowUtf16) {
          throw const SnippetTemplateException('当前行过长，无法在片段输入窗中展开', 0);
        }
        final lineText = lineLengthUtf16 == 0
            ? ''
            : (() {
                final range = doc.doc.readRange(
                  boundary.startUtf16,
                  maxLenUtf16: lineLengthUtf16,
                );
                if (range.version != expectedVersion ||
                    range.startUtf16 != boundary.startUtf16 ||
                    range.endUtf16 != boundary.endUtf16 ||
                    range.text.length != lineLengthUtf16) {
                  throw const SnippetTemplateException(
                    '当前行读取时文档版本已变化',
                    0,
                  );
                }
                return range.text;
              })();
        variables.addAll(snippetCurrentLineVariables(lineText));
      }
      if (!needsCurrentWord) return variables;

      final caretOffset = selection.extentOffset;
      var contextStart = boundary.startUtf16;
      var contextEnd = boundary.endUtf16;
      if (lineLengthUtf16 > snippetCurrentWordContextUtf16) {
        const halfContext = snippetCurrentWordContextUtf16 ~/ 2;
        final lineColumnUtf16 = caretOffset - boundary.startUtf16;
        final desiredStart =
            boundary.startUtf16 + lineColumnUtf16 + 1 - halfContext;
        if (desiredStart > contextStart) contextStart = desiredStart;
        final desiredEnd =
            boundary.startUtf16 + lineColumnUtf16 + 1 + halfContext;
        if (desiredEnd < contextEnd) contextEnd = desiredEnd;
      }
      late final DocumentPosition contextPosition;
      try {
        contextPosition = doc.doc.positionAt(contextStart);
      } on AlulaException catch (error) {
        if (error.code != 'InvalidUtf16Offset' ||
            contextStart <= boundary.startUtf16) {
          rethrow;
        }
        contextStart--;
        contextPosition = doc.doc.positionAt(contextStart);
      }
      if (contextPosition.version != expectedVersion ||
          contextPosition.offsetUtf16 != contextStart) {
        throw const SnippetTemplateException(
          '当前单词读取时文档版本已变化',
          0,
        );
      }
      if (contextEnd - contextStart > snippetCurrentWordContextUtf16) {
        contextEnd = contextStart + snippetCurrentWordContextUtf16;
      }
      if (contextEnd < caretOffset || contextStart > caretOffset) {
        throw const SnippetTemplateException('当前单词上下文范围无效', 0);
      }
      var wordText = '';
      if (contextEnd > contextStart) {
        final range = doc.doc.readRange(
          contextStart,
          maxLenUtf16: contextEnd - contextStart,
        );
        if (range.version != expectedVersion ||
            range.startUtf16 != contextStart ||
            range.endUtf16 < caretOffset ||
            range.endUtf16 > contextEnd ||
            range.text.length != range.endUtf16 - range.startUtf16) {
          throw const SnippetTemplateException(
            '当前单词读取时文档版本已变化',
            0,
          );
        }
        wordText = range.text;
      }
      variables.addAll(snippetCurrentWordVariables(
        wordText,
        caretOffset - contextStart,
      ));
      return variables;
    }

    final expansions = <SnippetExpansion>[];
    final deadline = DateTime.now().add(_snippetMultiCursorExpansionTimeout);
    try {
      for (final selection in selections) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('multi-cursor snippet expansion timed out');
        }
        final variables = {
          ...commonVariables,
          ...variablesForSelection(selection),
        };
        final expansion = await expandSnippetTemplate(
          template,
          variables: variables,
        ).timeout(remaining);
        if (!isCurrentSnapshot()) {
          if (mounted) setState(() => _statusDetail = '片段插入未应用：展开期间编辑状态已变化');
          return;
        }
        expansions.add(expansion);
      }
    } on SnippetTemplateException catch (error) {
      if (mounted) setState(() => _statusDetail = '片段插入失败：${error.message}');
      return;
    } on TimeoutException {
      if (mounted) setState(() => _statusDetail = '多光标片段展开超时，未应用任何更改');
      return;
    } on AlulaException catch (error) {
      if (mounted) {
        setState(
            () => _statusDetail = '片段变量读取失败：${error.code} ${error.detail}');
      }
      return;
    }

    if (!isCurrentSnapshot()) {
      if (mounted) setState(() => _statusDetail = '片段插入未应用：编辑状态已变化');
      return;
    }
    final expectedTabstops = expansions.first.tabstopOrder;
    var placeholderCount = 0;
    final transformsByTabstop = <int, int>{};
    for (final expansion in expansions) {
      if (!listEquals(expansion.tabstopOrder, expectedTabstops)) {
        if (mounted) setState(() => _statusDetail = '片段各选区展开结果不一致，未应用任何更改');
        return;
      }
      placeholderCount += expansion.placeholders.length;
      if (placeholderCount > _maxSnippetInsertionPlaceholderOccurrences) {
        if (mounted) setState(() => _statusDetail = '片段占位符总数超过上限，未应用任何更改');
        return;
      }
      for (final placeholder in expansion.placeholders) {
        if (placeholder.transform != null) {
          transformsByTabstop.update(
            placeholder.index,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    if (transformsByTabstop.values.any(
      (count) => count > maxSnippetVariableTransforms,
    )) {
      if (mounted) {
        setState(() => _statusDetail = '单个 tabstop 的转换数超过上限，未应用任何更改');
      }
      return;
    }

    final plansBySelection = <_SnippetInsertionPlan>[];
    for (var index = 0; index < selections.length; index++) {
      final selection = selections[index];
      final localStart = selection.start - windowStart;
      final localEnd = selection.end - windowStart;
      final lineBreakBefore =
          localStart == 0 ? -1 : value.text.lastIndexOf('\n', localStart - 1);
      final linePrefix = value.text.substring(lineBreakBefore + 1, localStart);
      final leadingWhitespace =
          RegExp(r'^[ \t]*').firstMatch(linePrefix)?.group(0) ?? '';
      plansBySelection.add(_SnippetInsertionPlan(
        startUtf16: selection.start,
        endUtf16: selection.end,
        removedText: value.text.substring(localStart, localEnd),
        expansion: expansions[index],
        lineLeadingWhitespace: leadingWhitespace,
      ));
    }
    final orderedPlans = [...plansBySelection]
      ..sort((left, right) => left.startUtf16.compareTo(right.startUtf16));
    var shift = 0;
    for (var index = 0; index < orderedPlans.length; index++) {
      final plan = orderedPlans[index];
      if (index > 0 && plan.startUtf16 < orderedPlans[index - 1].endUtf16) {
        if (mounted) setState(() => _statusDetail = '多光标片段选区相交，未应用任何更改');
        return;
      }
      plan.mappedStartUtf16 = plan.startUtf16 + shift;
      shift += plan.expansion.text.length - (plan.endUtf16 - plan.startUtf16);
    }
    final groupStart = orderedPlans.first.mappedStartUtf16;
    final groupEnd = orderedPlans.last.mappedStartUtf16 +
        orderedPlans.last.expansion.text.length;
    if (groupEnd - groupStart > capacity) {
      if (mounted) setState(() => _statusDetail = '多光标片段展开后超出输入窗范围，未应用任何更改');
      return;
    }
    final operationChars = orderedPlans.fold<int>(
      0,
      (total, plan) =>
          total + plan.removedText.length + plan.expansion.text.length,
    );
    if (operationChars > _undoHistoryBudget.maxTotalChars) {
      if (mounted) setState(() => _statusDetail = '多光标片段超出撤销历史上限，未应用任何更改');
      return;
    }

    final forward = <TextOp>[
      for (final plan in orderedPlans.reversed) ...[
        if (plan.endUtf16 > plan.startUtf16)
          TextOp.delete(plan.startUtf16, plan.endUtf16 - plan.startUtf16),
        if (plan.expansion.text.isNotEmpty)
          TextOp.insert(plan.startUtf16, plan.expansion.text),
      ],
    ];
    final inverse = <TextOp>[];
    for (final plan in orderedPlans.reversed) {
      if (plan.expansion.text.isNotEmpty) {
        inverse.add(TextOp.delete(
          plan.mappedStartUtf16,
          plan.expansion.text.length,
        ));
      }
      if (plan.removedText.isNotEmpty) {
        inverse.add(TextOp.insert(plan.mappedStartUtf16, plan.removedText));
      }
    }

    if (!isCurrentSnapshot()) {
      if (mounted) setState(() => _statusDetail = '片段插入未应用：编辑状态已变化');
      return;
    }
    if (forward.isNotEmpty) {
      try {
        doc.doc.applyWith(expectedVersion, forward);
      } on AlulaException catch (error) {
        if (mounted) {
          setState(
              () => _statusDetail = '片段插入未应用：${error.code} ${error.detail}');
        }
        return;
      }
    }
    _clearSnippetSession(clearSecondarySelections: false);

    final session = expectedTabstops.isEmpty
        ? null
        : SnippetSession.fromInsertions(
            insertions: [
              for (final plan in plansBySelection)
                (
                  expansion: plan.expansion,
                  documentOffsetUtf16: plan.mappedStartUtf16,
                  lineLeadingWhitespace: plan.lineLeadingWhitespace,
                ),
            ],
            version: doc.doc.version,
          );
    final afterSelections = session?.currentSelections ??
        [
          for (final plan in plansBySelection)
            TextSelection.collapsed(
              offset: plan.mappedStartUtf16 + plan.expansion.text.length,
            ),
        ];
    final nextPrimarySelection = afterSelections.first;
    if (forward.isNotEmpty) {
      _recordDocumentOperations(
        doc,
        forward: forward,
        inverse: inverse,
        beforeCaret: primarySelection.extentOffset,
        afterCaret: nextPrimarySelection.extentOffset,
        coalesce: false,
      );
    }

    final freeBefore = capacity - (groupEnd - groupStart);
    final nextWindowStart =
        (groupStart - freeBefore ~/ 2).clamp(0, groupStart).toInt();
    final nextWindow = RustTextInputWindow.open(
      doc.doc,
      startUtf16: nextWindowStart,
      maxWindowUtf16: window.maxWindowUtf16,
      compositionReserveUtf16: window.compositionReserveUtf16,
      selection: nextPrimarySelection,
    );
    doc.inputWindow = nextWindow;
    field.restoreInputWindow(nextWindow);
    if (session != null) {
      _snippetSession = session;
      _snippetSessionDocId = doc.id;
      _snippetSessionView = doc;
    }
    _setDocSelections(doc, afterSelections, recordHistory: false);
    if (forward.isNotEmpty) {
      _refreshSiblingViews(doc, forward);
      _onFindTextChanged();
    }
    _syncCommandContext();
    field.requestFocus();
    if (mounted) {
      setState(() => _statusDetail = '已在 ${selections.length} 个光标处插入片段');
    }
  }

  List<TextOp>? _snippetOperationsForInput(
    OpenDoc doc,
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final session = _snippetSessionFor(doc);
    if (session == null) return null;
    final localOperations = diffToOps(oldValue.text, newValue.text);
    if (localOperations.isEmpty) return const [];
    final editStart =
        doc.inputWindow.startUtf16 + localOperations.first.offsetUtf16;
    final deletedUtf16 = localOperations
        .where((operation) => operation.type == OpType.delete)
        .fold<int>(0, (length, operation) => length + operation.lenUtf16!);
    final insertedText = localOperations
        .where((operation) => operation.type == OpType.insert)
        .map((operation) => operation.text!)
        .join();
    final primarySelection = oldValue.selection;
    if (!primarySelection.isValid) return null;
    final planned = session.operationsForMirroredEdit(
      primarySelection: TextSelection(
        baseOffset: doc.inputWindow.startUtf16 + primarySelection.baseOffset,
        extentOffset:
            doc.inputWindow.startUtf16 + primarySelection.extentOffset,
        affinity: primarySelection.affinity,
        isDirectional: primarySelection.isDirectional,
      ),
      editStartUtf16: editStart,
      deletedUtf16: deletedUtf16,
      insertedText: insertedText,
    );
    return planned;
  }

  SnippetSession? _snippetSessionFor(OpenDoc doc) {
    final session = _snippetSession;
    if (session == null) return null;
    if (_snippetSessionDocId != doc.id || session.version != doc.doc.version) {
      return null;
    }
    return session;
  }

  void _syncSnippetChoiceUi(SnippetSession session) {
    if (identical(_snippetChoiceUiSession, session) &&
        _snippetChoiceUiTabstop == session.currentTabstop) {
      return;
    }
    _snippetChoiceUiSession = session;
    _snippetChoiceUiTabstop = session.currentTabstop;
    _snippetChoiceSelectedIndex = 0;
    _snippetChoiceDismissed = false;
  }

  void _previewSnippetChoice(
    SnippetSession session,
    int optionIndex,
  ) {
    if (!identical(_snippetSession, session)) return;
    _syncSnippetChoiceUi(session);
    final options = session.activeChoiceRange?.choice?.options;
    if (options == null || options.isEmpty) return;
    final index = optionIndex % options.length;
    if (_snippetChoiceSelectedIndex == index && !_snippetChoiceDismissed) {
      return;
    }
    setState(() {
      _snippetChoiceSelectedIndex = index;
      _snippetChoiceDismissed = false;
    });
  }

  void _moveSnippetChoiceHighlight(
    SnippetSession session, {
    required bool forward,
  }) {
    if (!identical(_snippetSession, session)) return;
    _syncSnippetChoiceUi(session);
    final options = session.activeChoiceRange?.choice?.options;
    if (options == null || options.isEmpty) return;
    final delta = forward ? 1 : -1;
    final index = (_snippetChoiceSelectedIndex + delta) % options.length;
    setState(() {
      _snippetChoiceSelectedIndex = index < 0 ? index + options.length : index;
      _snippetChoiceDismissed = false;
    });
  }

  void _acceptSnippetChoice(
    OpenDoc doc,
    SnippetSession session,
    int optionIndex,
  ) {
    if (!identical(_snippetSession, session) ||
        _snippetSessionDocId != doc.id ||
        session.version != doc.doc.version) {
      return;
    }
    final choiceRange = session.activeChoiceRange;
    final options = choiceRange?.choice?.options;
    final field = doc.inputFieldKey.currentState;
    if (choiceRange == null ||
        options == null ||
        options.isEmpty ||
        field == null) {
      return;
    }
    final index = optionIndex.clamp(0, options.length - 1).toInt();
    final replacement = options[index];
    final window = doc.inputWindow;
    final globalSelections = session.currentSelections;
    if (globalSelections.isEmpty ||
        globalSelections.any((selection) =>
            selection.start < window.startUtf16 ||
            selection.end > window.endUtf16)) {
      _clearSnippetSession();
      return;
    }

    // Force the primary and mirror ranges to cover the whole choice so the
    // regular multi-selection formatter replaces each linked occurrence.
    _setDocSelections(doc, globalSelections);
    final value = field.editingValue;
    final primary = value.selection;
    final expectedStart = choiceRange.startUtf16 - window.startUtf16;
    final expectedEnd = choiceRange.endUtf16 - window.startUtf16;
    if (!primary.isValid ||
        primary.start != expectedStart ||
        primary.end != expectedEnd) {
      _clearSnippetSession();
      return;
    }
    final nextText = value.text.replaceRange(
      primary.start,
      primary.end,
      replacement,
    );
    field.applyFormattedValue(TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: primary.start + replacement.length,
      ),
    ));
    field.flushPending();

    if (!identical(_snippetSession, session)) return;
    if (session.version != doc.doc.version) {
      _clearSnippetSession();
      return;
    }
    field.requestFocus();
    unawaited(_moveSnippetTabstop(doc, session, forward: true));
  }

  Future<void> _moveSnippetTabstop(
    OpenDoc doc,
    SnippetSession session, {
    required bool forward,
  }) async {
    if (_snippetNavigationPending) return;
    _flushInput(doc);
    if (!identical(_snippetSession, session) ||
        _snippetSessionDocId != doc.id ||
        session.version != doc.doc.version) {
      _clearSnippetSession();
      return;
    }

    final transforms = session.currentRanges
        .where((range) => range.transform != null)
        .toList(growable: false);
    if (transforms.isEmpty) {
      _finishSnippetTabstopMove(doc, session, forward: forward);
      return;
    }

    final epoch = ++_snippetNavigationEpoch;
    _snippetNavigationPending = true;
    final expectedVersion = session.version;
    final window = doc.inputWindow;
    final windowText = window.text;
    final windowStart = window.startUtf16;
    final windowEnd = window.endUtf16;
    final field = doc.inputFieldKey.currentState;
    final editingValue = field?.editingValue ?? window.initialValue;
    final selectionSet = List<TextSelection>.of(doc.selectionSet);

    bool isCurrentSnapshot() {
      final currentWindow = doc.inputWindow;
      return mounted &&
          !_disposing &&
          _snippetNavigationEpoch == epoch &&
          identical(_snippetSession, session) &&
          _snippetSessionDocId == doc.id &&
          identical(_active, doc) &&
          doc.doc.version == expectedVersion &&
          session.version == expectedVersion &&
          identical(doc.inputFieldKey.currentState, field) &&
          currentWindow.version == window.version &&
          currentWindow.startUtf16 == windowStart &&
          currentWindow.endUtf16 == windowEnd &&
          currentWindow.text == windowText &&
          doc.editingValue == editingValue &&
          listEquals(doc.selectionSet, selectionSet);
    }

    try {
      if (transforms.length > maxSnippetVariableTransforms) {
        throw SnippetVariableTransformException(
          'snippet transform count exceeds the limit',
          transforms[maxSnippetVariableTransforms].transform!.offsetUtf16,
        );
      }
      var totalInputUtf16 = 0;
      final values = <String>[];
      for (final range in transforms) {
        totalInputUtf16 += range.lengthUtf16;
        if (totalInputUtf16 > maxSnippetVariableTransformInputUtf16) {
          throw SnippetVariableTransformException(
            'snippet transform input exceeds the size limit',
            range.transform!.offsetUtf16,
          );
        }
        values.add(_readSnippetTransformRange(
          doc,
          range.startUtf16,
          range.endUtf16,
          expectedVersion: expectedVersion,
        ));
      }
      if (!isCurrentSnapshot()) return;

      final evaluated = await applySnippetVariableTransforms([
        for (var index = 0; index < transforms.length; index++)
          transforms[index].transform!.withValue(values[index]),
      ]);
      if (!isCurrentSnapshot()) return;

      final edits =
          <({SnippetPlaceholderRange range, String text, String old})>[];
      var totalOutputUtf16 = 0;
      for (var index = 0; index < transforms.length; index++) {
        final range = transforms[index];
        final text = _normalizeSnippetPlaceholderTransform(
          evaluated[index],
          session.lineLeadingWhitespaceFor(range),
        );
        totalOutputUtf16 += text.length;
        if (totalOutputUtf16 > maxSnippetVariableTransformOutputUtf16) {
          throw SnippetVariableTransformException(
            'snippet transform output exceeds the size limit',
            range.transform!.offsetUtf16,
          );
        }
        if (text != values[index]) {
          edits.add((range: range, text: text, old: values[index]));
        }
      }
      edits.sort((left, right) =>
          left.range.startUtf16.compareTo(right.range.startUtf16));
      for (var index = 1; index < edits.length; index++) {
        final previous = edits[index - 1].range;
        final current = edits[index].range;
        if (current.startUtf16 < previous.endUtf16 ||
            current.startUtf16 == previous.startUtf16) {
          throw SnippetVariableTransformException(
            'snippet placeholder transforms overlap',
            current.transform!.offsetUtf16,
          );
        }
      }

      final forwardOperations = <TextOp>[];
      final inverse = <TextOp>[];
      var deltaBefore = 0;
      final mappedStarts = <int>[];
      for (final edit in edits) {
        mappedStarts.add(edit.range.startUtf16 + deltaBefore);
        deltaBefore += edit.text.length - edit.old.length;
      }
      for (final edit in edits.reversed) {
        if (edit.old.isNotEmpty) {
          forwardOperations
              .add(TextOp.delete(edit.range.startUtf16, edit.old.length));
        }
        if (edit.text.isNotEmpty) {
          forwardOperations
              .add(TextOp.insert(edit.range.startUtf16, edit.text));
        }
      }
      for (var index = edits.length - 1; index >= 0; index--) {
        final edit = edits[index];
        final mappedStart = mappedStarts[index];
        if (edit.text.isNotEmpty) {
          inverse.add(TextOp.delete(mappedStart, edit.text.length));
        }
        if (edit.old.isNotEmpty) {
          inverse.add(TextOp.insert(mappedStart, edit.old));
        }
      }

      if (forwardOperations.isNotEmpty) {
        if (!isCurrentSnapshot()) return;
        final beforeCaret = doc.selection.extentOffset;
        final nextVersion =
            doc.doc.applyWith(expectedVersion, forwardOperations);
        doc.lastEditAt = null;
        final rangesUpdated = session.applyOperations(
          forwardOperations,
          nextVersion: nextVersion,
          allowPartialActiveGroup: true,
        );
        if (!rangesUpdated) {
          _recordDocumentOperations(
            doc,
            forward: forwardOperations,
            inverse: inverse,
            beforeCaret: beforeCaret,
            afterCaret: beforeCaret,
            coalesce: false,
          );
          _refreshSiblingViews(doc, forwardOperations);
          _clearSnippetSession();
          doc.replaceInputWindow(beforeCaret);
          if (mounted) {
            setState(() => _statusDetail = '片段占位符转换后无法跟踪选区');
          }
          _onFindTextChanged();
          return;
        }
        _refreshSiblingViews(doc, forwardOperations);
      }

      final moved = forward ? session.moveNext() : session.movePrevious();
      final selections = moved || !forward
          ? session.currentSelections
          : [
              TextSelection.collapsed(
                offset: session.currentRanges.firstOrNull?.endUtf16 ??
                    doc.selection.extentOffset,
              ),
            ];
      final afterCaret =
          selections.firstOrNull?.extentOffset ?? doc.selection.extentOffset;
      if (edits.isNotEmpty) {
        _recordDocumentOperations(
          doc,
          forward: forwardOperations,
          inverse: inverse,
          beforeCaret: selectionSet.first.extentOffset,
          afterCaret: afterCaret,
          coalesce: false,
        );
      }
      doc.replaceInputWindow(afterCaret, selection: selections.firstOrNull);
      if (!moved && forward) {
        _clearSnippetSession(clearSecondarySelections: false);
        _setDocSelections(doc, selections);
        _onFindTextChanged();
        return;
      }
      _snippetSessionView = doc;
      _syncSnippetChoiceUi(session);
      _setDocSelections(doc, selections);
      if (session.isAtFinalTabstop) {
        _clearSnippetSession(clearSecondarySelections: false);
      }
      _onFindTextChanged();
      field?.requestFocus();
    } on SnippetVariableTransformException catch (error) {
      if (isCurrentSnapshot() && mounted) {
        setState(() => _statusDetail = '片段占位符转换失败：${error.message}');
      }
    } on AlulaException catch (error) {
      if (isCurrentSnapshot() && mounted) {
        setState(
            () => _statusDetail = '片段占位符转换失败：${error.code} ${error.detail}');
      }
    } on Object catch (error) {
      if (isCurrentSnapshot() && mounted) {
        setState(() => _statusDetail = '片段占位符转换失败：$error');
      }
    } finally {
      if (_snippetNavigationEpoch == epoch) {
        _snippetNavigationPending = false;
      }
    }
  }

  String _readSnippetTransformRange(
    OpenDoc doc,
    int startUtf16,
    int endUtf16, {
    required int expectedVersion,
  }) {
    if (startUtf16 < 0 || endUtf16 < startUtf16) {
      throw const SnippetVariableTransformException(
        'snippet placeholder range is invalid',
        0,
      );
    }
    final output = StringBuffer();
    var cursor = startUtf16;
    while (cursor < endUtf16) {
      final range = doc.doc.readRange(
        cursor,
        maxLenUtf16: (endUtf16 - cursor).clamp(1, 64 * 1024).toInt(),
      );
      if (range.version != expectedVersion ||
          range.startUtf16 != cursor ||
          range.endUtf16 <= cursor ||
          range.endUtf16 > endUtf16 ||
          range.text.length != range.endUtf16 - range.startUtf16) {
        throw SnippetVariableTransformException(
          'snippet placeholder range changed while reading',
          startUtf16,
        );
      }
      output.write(range.text);
      cursor = range.endUtf16;
    }
    return output.toString();
  }

  String _normalizeSnippetPlaceholderTransform(
    String value,
    String lineLeadingWhitespace,
  ) {
    final lines = value.split(RegExp(r'\r\n|\r|\n'));
    if (lines.length == 1) return lines.single;
    for (var index = 1; index < lines.length; index++) {
      lines[index] = '$lineLeadingWhitespace${lines[index]}';
    }
    return lines.join('\n');
  }

  void _finishSnippetTabstopMove(
    OpenDoc doc,
    SnippetSession session, {
    required bool forward,
  }) {
    final moved = forward ? session.moveNext() : session.movePrevious();
    if (!moved && forward) {
      _clearSnippetSession(clearSecondarySelections: false);
      return;
    }
    _snippetSessionView = doc;
    _syncSnippetChoiceUi(session);
    _setDocSelections(doc, session.currentSelections);
    if (session.isAtFinalTabstop) {
      _clearSnippetSession(clearSecondarySelections: false);
    }
  }

  void _clearSnippetSession({bool clearSecondarySelections = true}) {
    _snippetNavigationEpoch++;
    _snippetNavigationPending = false;
    final view = _snippetSessionView;
    _snippetSession = null;
    _snippetSessionDocId = null;
    _snippetSessionView = null;
    _snippetChoiceUiSession = null;
    _snippetChoiceUiTabstop = null;
    _snippetChoiceSelectedIndex = 0;
    _snippetChoiceDismissed = false;
    _pendingSnippetOperations = null;
    if (!clearSecondarySelections || view == null) return;
    if (view.additionalSelections.isNotEmpty) {
      view.additionalSelections = const [];
      if (mounted) _scheduleSelectionRefresh(view);
    }
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
    for (final view in _viewsOf(doc).toList(growable: false)) {
      _flushInput(view, commitComposition: true);
    }
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
      var mergeSessionOutOfSync = false;
      doc.doc.saveFile(targetPath, options: targetOptions);
      doc.doc.markSaved();
      try {
        doc.mergeResultSession?.recordSavepoint();
      } on MergeResultSessionException {
        mergeSessionOutOfSync = true;
      }
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
        final savedStatus = lspWarning
            ? '已保存 ${doc.name}，语言服务未能重新打开文档'
            : '已原子保存 ${doc.name}（v${doc.doc.version}）';
        _statusDetail =
            mergeSessionOutOfSync ? '$savedStatus（合并会话需要同步）' : savedStatus;
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
  KeyChord? _pendingChordPrefix;

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
        final snippetSession = _snippetSession;
        if (active != null && snippetSession != null && !activeHasComposition) {
          if (_snippetSessionDocId != active.id ||
              snippetSession.version != active.doc.version) {
            _clearSnippetSession();
          } else {
            _syncSnippetChoiceUi(snippetSession);
            final activeChoice = snippetSession.activeChoiceRange?.choice;
            if (!ctrl &&
                !meta &&
                !alt &&
                activeChoice != null &&
                (key == LogicalKeyboardKey.arrowDown ||
                    key == LogicalKeyboardKey.arrowUp)) {
              _moveSnippetChoiceHighlight(
                snippetSession,
                forward: key == LogicalKeyboardKey.arrowDown,
              );
              return KeyEventResult.handled;
            }
            if (!ctrl &&
                !meta &&
                !alt &&
                activeChoice != null &&
                (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter)) {
              _acceptSnippetChoice(
                active,
                snippetSession,
                _snippetChoiceSelectedIndex,
              );
              return KeyEventResult.handled;
            }
            if (!ctrl && !meta && !alt && key == LogicalKeyboardKey.tab) {
              if (!shift && activeChoice != null) {
                _acceptSnippetChoice(
                  active,
                  snippetSession,
                  _snippetChoiceSelectedIndex,
                );
                return KeyEventResult.handled;
              }
              unawaited(_moveSnippetTabstop(
                active,
                snippetSession,
                forward: !shift,
              ));
              return KeyEventResult.handled;
            }
            if (!ctrl && !meta && !alt && key == LogicalKeyboardKey.escape) {
              if (activeChoice != null && !_snippetChoiceDismissed) {
                setState(() => _snippetChoiceDismissed = true);
                return KeyEventResult.handled;
              }
              final caret = active.selection.extentOffset;
              _clearSnippetSession();
              _setDocSelections(
                active,
                [TextSelection.collapsed(offset: caret)],
              );
              return KeyEventResult.handled;
            }
          }
        }
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
        final currentChord = KeyChord(
          key: key,
          control: ctrl,
          shift: shift,
          alt: alt,
          meta: meta,
        );
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
          final prefix = _pendingChordPrefix;
          _pendingChordPrefix = null;
          final binding = prefix == null
              ? null
              : _keybindings.bindingForSequence([prefix, currentChord]);
          if (binding != null &&
              _commands.context.matches(binding.when) &&
              _commands.isEnabled(binding.commandId)) {
            _runCommand(binding.commandId, arguments: binding.arguments);
            return KeyEventResult.handled;
          }
        }
        if (_keybindings.hasSequencePrefix(
          currentChord,
          matchesWhen: _commands.context.matches,
          isCommandEnabled: _commands.isEnabled,
        )) {
          _awaitingMoveSelectionChord = true;
          _pendingChordPrefix = currentChord;
          _pendingMoveSelectionChordTimer = Timer(
            const Duration(seconds: 5),
            () {
              _awaitingMoveSelectionChord = false;
              _pendingChordPrefix = null;
            },
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
          if (commandModifier && !shift && key == LogicalKeyboardKey.keyV) {
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
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyC &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isNotEmpty) {
          unawaited(_copyMultiSelections(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyC &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isEmpty &&
            !active.selection.isCollapsed) {
          unawaited(_copySingleSelection(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyC &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isEmpty &&
            active.selection.isCollapsed) {
          unawaited(_copyEmptySelectionLine(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyX &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isEmpty &&
            !active.selection.isCollapsed) {
          unawaited(_cutSingleSelection(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyX &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isEmpty &&
            active.selection.isCollapsed) {
          unawaited(_cutEmptySelectionLine(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyX &&
            !activeHasComposition &&
            active != null &&
            active.additionalSelections.isNotEmpty) {
          unawaited(_cutMultiSelections(active).then((handled) {
            if (!handled && mounted) {
              setState(() => _statusDetail = '多光标剪切未执行（文档只读或状态已变化）');
            }
          }));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyV &&
            _overtypeMode &&
            widget.overtypeOnPaste &&
            !activeHasComposition &&
            active != null) {
          unawaited(_pasteOvertype(active));
          return KeyEventResult.handled;
        }
        if (commandModifier &&
            !shift &&
            !alt &&
            key == LogicalKeyboardKey.keyV &&
            !activeHasComposition &&
            active != null &&
            widget.pasteAsConfiguration.enabled) {
          unawaited(_pasteDefault(active));
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
            if (key == LogicalKeyboardKey.keyV) {
              unawaited(_pasteMultiSelections(active));
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
    doc.mergeResultSession?.reconcileCurrentResult();
    _syncCommandContext();
    doc.lastEditAt = null;
    _onFindTextChanged();
    _scheduleOutlineRefresh();
    _scheduleStateSave();
    _scheduleSyntaxRefresh(doc.id);
    if (mounted) setState(() => _statusDetail = status);
  }

  void _applyLinkedWorkspaceHistory(
    OpenDoc active,
    UndoEntry activeEntry, {
    required bool redo,
  }) {
    final transactionId = activeEntry.transactionId;
    final linkedDocumentIds = activeEntry.linkedDocumentIds;
    void reject(String reason) {
      if (mounted) setState(() => _statusDetail = reason);
    }

    if (transactionId == null ||
        linkedDocumentIds == null ||
        linkedDocumentIds.length != 2 ||
        !linkedDocumentIds.contains(active.id)) {
      reject('跨文档移动历史无效，未修改文档');
      return;
    }

    final viewsById = {for (final doc in _allDocs) doc.id: doc};
    viewsById[active.id] = active;
    final participants = <({OpenDoc doc, UndoEntry entry, List<TextOp> ops})>[];
    for (final id in linkedDocumentIds) {
      final doc = viewsById[id];
      if (doc == null) {
        reject('跨文档移动无法${redo ? '重做' : '撤销'}：参与文档已关闭');
        return;
      }
      if (!_canStartEditorTextDragDrop(doc)) {
        reject('跨文档移动无法${redo ? '重做' : '撤销'}：请先提交参与文档的输入或 IME');
        return;
      }
      final entry = redo
          ? doc.undoStack.peekOperationRedo()
          : doc.undoStack.peekOperationUndo();
      final entryIds = entry?.linkedDocumentIds;
      if (entry == null ||
          !entry.isLinkedWorkspaceTransaction ||
          entry.transactionId != transactionId ||
          entryIds == null ||
          entryIds.length != linkedDocumentIds.length ||
          !linkedDocumentIds.every(entryIds.contains)) {
        reject('跨文档移动无法${redo ? '重做' : '撤销'}：请先处理参与文档中的后续编辑');
        return;
      }
      final batches = redo ? entry.forwardBatches : entry.inverseBatches;
      if (batches == null) {
        reject('跨文档移动历史不完整，未修改文档');
        return;
      }
      final operations = batches.expand((batch) => batch).toList(
            growable: false,
          );
      if (operations.isEmpty) {
        reject('跨文档移动历史为空，未修改文档');
        return;
      }
      participants.add((doc: doc, entry: entry, ops: operations));
    }

    final core = _core;
    if (core == null) {
      reject('跨文档移动无法${redo ? '重做' : '撤销'}：核心尚未就绪');
      return;
    }

    late final AlulaWorkspaceEditResult result;
    try {
      result = core.applyWorkspaceEdit([
        for (final participant in participants)
          AlulaWorkspaceEditDocument(
            id: participant.doc.id,
            baseVersion: participant.doc.doc.version,
            ops: participant.ops,
          ),
      ]);
    } on AlulaException catch (error) {
      reject('跨文档移动${redo ? '重做' : '撤销'}已回滚：${error.code} ${error.detail}');
      return;
    }

    for (final participant in participants) {
      final doc = participant.doc;
      final entry = participant.entry;
      doc.doc.version = result.versions[doc.id]!;
      if (redo) {
        doc.undoStack.takeOperationRedo();
        _restoreRedoFileOptions(doc, entry);
        doc.replaceInputWindow(entry.redoCaret);
      } else {
        entry.redoEncoding = doc.fileOptions.encoding.id;
        entry.redoBom = doc.fileOptions.bom;
        entry.redoLineEnding = doc.fileOptions.lineEnding.id;
        doc.undoStack.takeOperationUndo();
        _restoreFileOptionsFromUndo(doc, entry);
        doc.replaceInputWindow(entry.caret);
      }
      doc.crossWindowSelection = null;
      doc.lastEditAt = null;
      _refreshSiblingViews(doc, participant.ops);
      if (!identical(doc, active)) {
        _updateDirty(doc);
        _scheduleSyntaxRefresh(doc.id);
      }
    }
    _finishHistoryChange(
      active,
      redo ? '已重做跨文档移动' : '已撤销跨文档移动',
    );
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
      if (operation.isLinkedWorkspaceTransaction) {
        _applyLinkedWorkspaceHistory(active, operation, redo: false);
        return;
      }
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
      if (operation.isLinkedWorkspaceTransaction) {
        _applyLinkedWorkspaceHistory(active, operation, redo: true);
        return;
      }
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
    if (_findVisible) {
      final active = _active;
      final group = _focused;
      _flushFindHistory();
      setState(() {
        _findVisible = false;
        _clearFindSelectionScope();
        _findGeneration++;
        _cancelRegexFind();
        _cancelRegexReplace();
        _pendingFind = Future<void>.value();
        _findPending = false;
        _findError = null;
        _matches = const [];
        _findOverviewLines = const [];
        _matchIndex = -1;
      });
      if (active != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_disposing &&
              identical(_active, active) &&
              identical(_focused, group)) {
            _focusNodeFor(group, active).requestFocus();
          }
        });
      }
      return;
    }

    final active = _active;
    final seed = active == null ? null : _findSelectionSeed(active);
    setState(() {
      if (seed != null) {
        _findQuery.value = TextEditingValue(
          text: seed,
          selection: TextSelection.collapsed(offset: seed.length),
        );
        _findHistory.noteEdit(seed);
      }
      _findVisible = true;
      _replaceVisible = false;
      _refreshMatches();
    });
    if (seed != null) _scheduleFindHistoryUpdate();
  }

  String? _findSelectionSeed(OpenDoc doc) {
    final window = doc.inputWindow;
    final version = doc.doc.version;
    if (window.version != version ||
        window.hasComposition ||
        window.pendingText != null ||
        doc.pendingInputOperations.isNotEmpty) {
      return null;
    }

    final selection = doc.selection;
    if (selection.isCollapsed) {
      return _findWordAtCaretSeed(doc, selection.extentOffset, version);
    }
    final start = selection.start;
    final end = selection.end;
    final length = end - start;
    if (!isFindSelectionSeedLengthSupported(length)) return null;

    try {
      final startLine = doc.doc.lineBoundary(start);
      final endLine = doc.doc.lineBoundary(end);
      if (startLine.version != version ||
          endLine.version != version ||
          startLine.line != endLine.line ||
          doc.doc.version != version) {
        return null;
      }

      final selectedText = _readDocumentRange(doc, start, end);
      if (doc.doc.version != version ||
          selectedText.length != length ||
          selectedText.isEmpty ||
          selectedText.contains('\n')) {
        return null;
      }
      return _regexFind ? RegExp.escape(selectedText) : selectedText;
    } catch (_) {
      // Opening Find must remain available if a selection goes stale while it
      // is being read; in that case keep the query the user already had.
      return null;
    }
  }

  String? _findWordAtCaretSeed(OpenDoc doc, int caretUtf16, int version) {
    try {
      final line = doc.doc.lineBoundary(caretUtf16);
      if (line.version != version ||
          line.startUtf16 > caretUtf16 ||
          caretUtf16 > line.endUtf16 ||
          doc.doc.version != version) {
        return null;
      }

      const halfWindowUtf16 = maxFindWordContextUtf16 ~/ 2;
      var contextStart = caretUtf16 - line.startUtf16 > halfWindowUtf16 - 1
          ? caretUtf16 - halfWindowUtf16 + 1
          : line.startUtf16;
      var contextEnd = line.endUtf16 - caretUtf16 > halfWindowUtf16 + 1
          ? caretUtf16 + halfWindowUtf16 + 1
          : line.endUtf16;

      if (contextStart > line.startUtf16) {
        try {
          final position = doc.doc.positionAt(contextStart);
          if (position.version != version ||
              position.offsetUtf16 != contextStart) {
            return null;
          }
        } on AlulaException catch (error) {
          if (error.code != 'InvalidUtf16Offset') return null;
          contextStart--;
        }
      }
      if (contextEnd < line.endUtf16) {
        try {
          final position = doc.doc.positionAt(contextEnd);
          if (position.version != version ||
              position.offsetUtf16 != contextEnd) {
            return null;
          }
        } on AlulaException catch (error) {
          if (error.code != 'InvalidUtf16Offset') return null;
          contextEnd++;
        }
      }

      final text = _readDocumentRange(doc, contextStart, contextEnd);
      if (doc.doc.version != version ||
          text.length != contextEnd - contextStart) {
        return null;
      }
      final match =
          defaultFindWordMatchAtPosition(text, caretUtf16 - contextStart);
      if (match == null || !isFindSelectionSeedLengthSupported(match.length)) {
        return null;
      }
      final word = text.substring(match.start, match.end);
      return _regexFind ? RegExp.escape(word) : word;
    } catch (_) {
      // Find must still open with the previous query if the caret's line is
      // stale or cannot be read at valid UTF-16 boundaries.
      return null;
    }
  }

  void _openReplace() {
    setState(() {
      _findVisible = true;
      _replaceVisible = true;
      _refreshMatches();
    });
    _scheduleFindHistoryUpdate();
  }

  void _onFindTextChanged() {
    if (!_findVisible) return;
    _findHistory.noteEdit(_findQuery.text);
    _scheduleFindHistoryUpdate();
    _refreshMatches();
    setState(() {});
  }

  void _onReplaceTextChanged(String value) {
    _cancelRegexReplace();
    _replaceHistory.noteEdit(value);
    _scheduleFindHistoryUpdate();
  }

  void _togglePreserveCase() {
    _cancelRegexReplace();
    setState(() => _preserveCase = !_preserveCase);
  }

  KeyEventResult _handleFindHistoryKey({
    required bool replace,
    required KeyEvent event,
  }) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final isPrevious = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isPrevious && event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final history = replace ? _replaceHistory : _findHistory;
    final controller = replace ? _replaceInput : _findQuery;
    final value =
        isPrevious ? history.previous(controller.text) : history.next();
    if (value == null) return KeyEventResult.ignored;
    setState(() {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      if (!replace) _refreshMatches();
    });
    _scheduleFindHistoryUpdate();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleFindInputKey({
    required bool replace,
    required KeyEvent event,
  }) {
    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (event is KeyDownEvent &&
        !replace &&
        isEnter &&
        HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      unawaited(_gotoMatch(-1));
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        isEnter &&
        HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      unawaited(_selectAllFindMatches());
      return KeyEventResult.handled;
    }
    return _handleFindHistoryKey(replace: replace, event: event);
  }

  void _loadFindHistoryForWorkspace(String? workspaceRoot) {
    final identity = FindReplaceHistoryStore.workspaceIdentity(workspaceRoot);
    if (_findHistoryWorkspaceIdentity == identity) return;
    final configuration = widget.findReplaceHistoryConfiguration;
    final saved =
        configuration.findScope == FindReplaceHistoryScope.workspace ||
            configuration.replaceScope == FindReplaceHistoryScope.workspace
        ? _findHistoryStore.load(workspaceRoot)
        : const FindReplaceHistorySnapshot();
    _findHistory.replaceEntries(
      configuration.findScope == FindReplaceHistoryScope.workspace
          ? saved.find
          : const [],
    );
    _replaceHistory.replaceEntries(
      configuration.replaceScope == FindReplaceHistoryScope.workspace
          ? saved.replace
          : const [],
    );
    _findHistoryWorkspaceIdentity = identity;
  }

  void _scheduleFindHistoryUpdate() {
    if (!_findVisible) return;
    _findHistoryTimer?.cancel();
    _findHistoryTimer = Timer(const Duration(milliseconds: 500), () {
      _flushFindHistory();
    });
  }

  void _flushFindHistory() {
    _findHistoryTimer?.cancel();
    _findHistoryTimer = null;
    final changed = _findHistory.record(_findQuery.text) |
        _replaceHistory.record(_replaceInput.text);
    if (!changed) return;
    final configuration = widget.findReplaceHistoryConfiguration;
    _findHistoryStore.save(
      _workspaceRoot,
      find: configuration.findScope == FindReplaceHistoryScope.workspace
          ? _findHistory.entries
          : null,
      replace: configuration.replaceScope == FindReplaceHistoryScope.workspace
          ? _replaceHistory.entries
          : null,
    );
  }

  List<TextMatchScope> _captureFindSelectionScopes(OpenDoc doc) {
    final text = doc.text;
    return findScopesFromSelections(
      text,
      doc.selectionSet.map(
        (selection) => TextMatchScope(
          selection.baseOffset,
          selection.extentOffset,
        ),
      ),
    );
  }

  void _clearFindSelectionScope() {
    _findInSelection = false;
    _findSelectionScopes = const [];
    _findScopeDocId = -1;
    _findScopeDocVersion = -1;
  }

  bool _hasFindSelection() =>
      _active?.selectionSet.any(
        (selection) => !selection.isCollapsed,
      ) ??
      false;

  void _toggleFindInSelection() {
    if (_findInSelection) {
      setState(() {
        _clearFindSelectionScope();
        _refreshMatches();
      });
      _scheduleFindHistoryUpdate();
      return;
    }
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final scopes = _captureFindSelectionScopes(active);
    if (scopes.isEmpty) return;
    setState(() {
      _findInSelection = true;
      _findSelectionScopes = scopes;
      _findScopeDocId = active.id;
      _findScopeDocVersion = active.doc.version;
      _refreshMatches();
    });
    _scheduleFindHistoryUpdate();
  }

  void _refreshMatches() {
    _cancelRegexFind();
    _cancelRegexReplace();
    _pendingFind = Future<void>.value();
    final active = _active;
    final text = active?.text ?? '';
    final generation = ++_findGeneration;
    _matchesDocId = active?.id ?? -1;
    _matchesDocVersion = active?.doc.version ?? -1;
    _findPending = false;
    _findMatchesTruncated = false;
    _findError = null;
    if (_findInSelection &&
        (active == null ||
            active.id != _findScopeDocId ||
            active.doc.version != _findScopeDocVersion)) {
      _clearFindSelectionScope();
      _statusDetail = '文档或选区已改变，已退出选区查找';
    }
    final scopes = _findInSelection ? _findSelectionScopes : null;
    if (_findVisible &&
        _regexFind &&
        active != null &&
        _findQuery.text.isNotEmpty) {
      final query = _findQuery.text;
      final docId = active.id;
      final docVersion = active.doc.version;
      final caseSensitive = _caseSensitive;
      final wholeWord = _wholeWord;
      final cancellation = Completer<void>();
      _findWorkerCancellation = cancellation;
      _matches = const [];
      _findOverviewLines = const [];
      _matchIndex = -1;
      _findPending = true;
      _pendingFind = _resolveRegexFind(
        generation: generation,
        text: text,
        query: query,
        docId: docId,
        docVersion: docVersion,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        scopes: scopes,
        cancellation: cancellation,
      );
      return;
    }
    _matches = _findVisible && !_regexFind
        ? findMatches(
            text,
            _findQuery.text,
            caseSensitive: _caseSensitive,
            wholeWord: _wholeWord,
            scopes: scopes,
          )
        : const [];
    _findOverviewLines =
        _findVisible ? buildEditorMinimapFindLines(text, _matches) : const [];
    if (_matchIndex >= _matches.length) {
      _matchIndex = _matches.isEmpty ? -1 : _matches.length - 1;
    }
    if (_matches.isEmpty) _matchIndex = -1;
  }

  Future<void> _resolveRegexFind({
    required int generation,
    required String text,
    required String query,
    required int docId,
    required int docVersion,
    required bool caseSensitive,
    required bool wholeWord,
    required List<TextMatchScope>? scopes,
    required Completer<void> cancellation,
  }) async {
    late final FindRegexMatchesResult result;
    try {
      result = await findRegexMatches(
        text,
        query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        scopes: scopes,
        cancelSignal: cancellation.future,
      );
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      if (identical(_findWorkerCancellation, cancellation)) {
        _findWorkerCancellation = null;
      }
    }
    if (!mounted || generation != _findGeneration) return;
    final active = _active;
    if (!_findVisible ||
        !_regexFind ||
        active?.id != docId ||
        active?.doc.version != docVersion ||
        _findQuery.text != query ||
        _caseSensitive != caseSensitive ||
        _wholeWord != wholeWord ||
        _findInSelection != (scopes != null) ||
        result.cancelled) {
      _matches = const [];
      _findOverviewLines = const [];
      _matchIndex = -1;
      _findPending = false;
      setState(() {});
      return;
    }
    _matches = result.matches;
    _findMatchesTruncated = result.truncated;
    _findError = result.error;
    _findPending = false;
    _findOverviewLines = buildEditorMinimapFindLines(text, _matches);
    if (_matchIndex >= _matches.length) {
      _matchIndex = _matches.isEmpty ? -1 : _matches.length - 1;
    }
    if (_matches.isEmpty) _matchIndex = -1;
    setState(() {});
  }

  void _cancelRegexFind() {
    final cancellation = _findWorkerCancellation;
    _findWorkerCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  void _cancelRegexReplace() {
    final cancellation = _findReplaceWorkerCancellation;
    _findReplaceWorkerCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
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

  Future<void> _gotoMatch(int direction) async {
    final active = _active;
    if (active == null) return;
    _flushInput(active, commitComposition: true);
    final selection = active.selection;
    final previousIndex = _matchIndex;
    final wasOnCurrentMatch = _matchesDocId == active.id &&
        _matchesDocVersion == active.doc.version &&
        previousIndex >= 0 &&
        previousIndex < _matches.length &&
        _matches[previousIndex].start == selection.baseOffset &&
        _matches[previousIndex].end == selection.extentOffset;
    _refreshMatches();
    final findGeneration = _findGeneration;
    if (_regexFind) await _pendingFind;
    if (!mounted ||
        _disposing ||
        findGeneration != _findGeneration ||
        !identical(_active, active) ||
        active.doc.version != _matchesDocVersion) {
      return;
    }
    if (_findError != null) {
      setState(() => _statusDetail = _findError!);
      return;
    }
    if (_matches.isEmpty) {
      setState(() => _matchIndex = -1);
      return;
    }
    TextMatch? match;
    if (wasOnCurrentMatch) {
      final nextIndex =
          (previousIndex + direction + _matches.length) % _matches.length;
      match = _matches[nextIndex];
    } else {
      final from =
          direction > 0 ? selection.extentOffset : selection.baseOffset;
      match = direction > 0
          ? findNext(_matches, from)
          : findPrevious(_matches, from);
    }
    if (match == null) return;
    _matchIndex = _matches.indexOf(match);
    _setDocSelection(
      active,
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    setState(() {});
  }

  Future<void> _selectAllFindMatches() async {
    final active = _active;
    if (active == null || !_findVisible) return;
    _flushInput(active, commitComposition: true);

    final documentId = active.id;
    final documentVersion = active.doc.version;
    final query = _findQuery.text;
    final regex = _regexFind;
    final caseSensitive = _caseSensitive;
    final wholeWord = _wholeWord;
    final selectionScopeEnabled = _findInSelection;
    final scopeDocumentId = _findScopeDocId;
    final scopeDocumentVersion = _findScopeDocVersion;

    _refreshMatches();
    final generation = _findGeneration;
    if (regex) await _pendingFind;
    if (!mounted ||
        _disposing ||
        !_findVisible ||
        generation != _findGeneration ||
        !identical(_active, active) ||
        active.id != documentId ||
        active.doc.version != documentVersion ||
        _matchesDocId != documentId ||
        _matchesDocVersion != documentVersion ||
        _findQuery.text != query ||
        _regexFind != regex ||
        _caseSensitive != caseSensitive ||
        _wholeWord != wholeWord ||
        _findInSelection != selectionScopeEnabled ||
        _findScopeDocId != scopeDocumentId ||
        _findScopeDocVersion != scopeDocumentVersion ||
        _findPending) {
      return;
    }
    if (_findError != null) {
      setState(() => _statusDetail = _findError!);
      return;
    }

    final currentSelection = active.selection;
    final preferredMatch = TextMatch(
      currentSelection.start,
      currentSelection.end,
    );
    final plan = buildFindMatchSelectionPlan(
      matches: _matches,
      maxMatches: defaultMultiCursorLimit,
      preferredMatch: preferredMatch,
    );
    if (plan.matches.isEmpty) return;

    final selections = <TextSelection>[
      for (var index = 0; index < plan.matches.length; index++)
        if (index == 0 &&
            plan.matches[index].start == preferredMatch.start &&
            plan.matches[index].end == preferredMatch.end)
          currentSelection
        else
          TextSelection(
            baseOffset: plan.matches[index].start,
            extentOffset: plan.matches[index].end,
          ),
    ];
    _setDocSelections(active, selections);
    if (plan.truncated || _findMatchesTruncated) {
      setState(() => _statusDetail =
          '已选择 ${plan.matches.length} 个匹配项（达到 editor.multiCursorLimit 上限）');
    }
    _focusNodeFor(_focused, active).requestFocus();
  }

  Future<void> _replaceCurrent() async {
    _scheduleFindHistoryUpdate();
    final active = _active;
    if (active == null) return;
    if (_regexFind) {
      _flushInput(active, commitComposition: true);
      _refreshMatches();
      final findGeneration = _findGeneration;
      if (_findPending) await _pendingFind;
      if (!mounted ||
          _disposing ||
          findGeneration != _findGeneration ||
          !identical(_active, active) ||
          !_findVisible ||
          !_regexFind) {
        return;
      }
      if (_findError != null) {
        setState(() => _statusDetail = _findError!);
        return;
      }
      if (_matches.isEmpty) {
        setState(() => _statusDetail = '无匹配');
        return;
      }
      final selection = active.selection;
      final from = selection.baseOffset >= 0 ? selection.baseOffset : 0;
      final match = findNext(_matches, from);
      if (match == null) {
        setState(() => _statusDetail = '无匹配');
        return;
      }
      final isOnMatch = selection.baseOffset == match.start &&
          selection.extentOffset == match.end;
      if (!isOnMatch) {
        _matchIndex = _matches.indexOf(match);
        _setDocSelection(
          active,
          TextSelection(baseOffset: match.start, extentOffset: match.end),
        );
        setState(() {});
        return;
      }

      final query = _findQuery.text;
      final replacement = _replaceInput.text;
      final preserveCase = _preserveCase;
      final text = active.text;
      final docId = active.id;
      final docVersion = active.doc.version;
      final generation = _findGeneration;
      final scopes = _findInSelection ? _findSelectionScopes : null;
      _cancelRegexReplace();
      final cancellation = Completer<void>();
      _findReplaceWorkerCancellation = cancellation;
      late final ReplaceRegexMatchesResult result;
      try {
        result = await replaceRegexMatches(
          text,
          query,
          replacement,
          caseSensitive: _caseSensitive,
          wholeWord: _wholeWord,
          preserveCase: preserveCase,
          scopes: scopes,
          targetStart: match.start,
          cancelSignal: cancellation.future,
        );
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        if (identical(_findReplaceWorkerCancellation, cancellation)) {
          _findReplaceWorkerCancellation = null;
        }
      }
      if (!mounted ||
          _disposing ||
          result.cancelled ||
          generation != _findGeneration ||
          !identical(_active, active) ||
          active.id != docId ||
          active.doc.version != docVersion ||
          !_findVisible ||
          !_regexFind ||
          _findQuery.text != query ||
          _replaceInput.text != replacement ||
          _preserveCase != preserveCase) {
        return;
      }
      if (result.error != null) {
        setState(() => _statusDetail = result.error!);
        return;
      }
      if (result.count == 0 || result.newText == null) {
        setState(() => _statusDetail = '无匹配');
        return;
      }
      final newText = result.newText!;
      _applyProgrammaticEdit(
        active,
        newText,
        selection: TextSelection.collapsed(
          offset: result.caretOffset ?? newText.length,
        ),
      );
      _refreshMatches();
      final refreshGeneration = _findGeneration;
      if (_findPending) await _pendingFind;
      if (!mounted ||
          _disposing ||
          refreshGeneration != _findGeneration ||
          !identical(_active, active)) {
        return;
      }
      setState(() => _statusDetail = '已替换 1 处（剩余 ${_matches.length} 处）');
      return;
    }
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
    final replacement = _preserveCase
        ? buildPreserveCaseReplacement(
            t.substring(m.start, m.end),
            _replaceInput.text,
          )
        : _replaceInput.text;
    final replaced = t.replaceRange(m.start, m.end, replacement);
    _applyProgrammaticEdit(
      active,
      replaced,
      selection: TextSelection.collapsed(
        offset: m.start + replacement.length,
      ),
    );
    _refreshMatches();
    setState(() => _statusDetail = '已替换 1 处（剩余 ${_matches.length} 处）');
  }

  Future<void> _replaceAll() async {
    _scheduleFindHistoryUpdate();
    final active = _active;
    if (active == null) return;
    if (_regexFind) {
      _flushInput(active, commitComposition: true);
      _refreshMatches();
      _cancelRegexFind();
      final generation = ++_findGeneration;
      _findPending = false;
      final query = _findQuery.text;
      final replacement = _replaceInput.text;
      final preserveCase = _preserveCase;
      final text = active.text;
      final docId = active.id;
      final docVersion = active.doc.version;
      final scopes = _findInSelection ? _findSelectionScopes : null;
      _cancelRegexReplace();
      final cancellation = Completer<void>();
      _findReplaceWorkerCancellation = cancellation;
      late final ReplaceRegexMatchesResult result;
      try {
        result = await replaceRegexMatches(
          text,
          query,
          replacement,
          caseSensitive: _caseSensitive,
          wholeWord: _wholeWord,
          preserveCase: preserveCase,
          scopes: scopes,
          cancelSignal: cancellation.future,
        );
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        if (identical(_findReplaceWorkerCancellation, cancellation)) {
          _findReplaceWorkerCancellation = null;
        }
      }
      if (!mounted ||
          _disposing ||
          result.cancelled ||
          generation != _findGeneration ||
          !identical(_active, active) ||
          active.id != docId ||
          active.doc.version != docVersion ||
          !_findVisible ||
          !_regexFind ||
          _findQuery.text != query ||
          _replaceInput.text != replacement ||
          _preserveCase != preserveCase) {
        return;
      }
      if (result.error != null) {
        setState(() => _statusDetail = result.error!);
        return;
      }
      if (result.count == 0 || result.newText == null) {
        setState(() => _statusDetail = '无匹配');
        return;
      }
      final newText = result.newText!;
      _applyProgrammaticEdit(
        active,
        newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      _refreshMatches();
      setState(() => _statusDetail = '已替换 ${result.count} 处');
      _scheduleStateSave();
      return;
    }
    _flushInput(active, commitComposition: true);
    final r = replaceAllMatches(
        active.text, _findQuery.text, _replaceInput.text,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
        preserveCase: _preserveCase,
        scopes: _findInSelection ? _findSelectionScopes : null);
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
          if (definition == null &&
              stopwatch.elapsed < const Duration(seconds: 2)) {
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
        _noteActiveDocument(targetGroup, view.id);
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
    final hasDocumentTextAfter = primary.extentOffset < window.totalUtf16Length;
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
      if (mounted && gen == _searchGen) {
        setState(() => _searching = false);
      }
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
    // Start native watch cancellation now. Waiting for a queued workspace
    // transition can delay handle release while the workbench is disposing.
    final stopping = watcher?.stop();
    _watcherTransition =
        _watcherTransition.catchError((Object error, StackTrace stack) {
      debugPrint('工作区 watcher 切换失败：$error');
    }).then((_) async {
      await stopping;
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
    _pruneExplorerMultiSelection();
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
    final location = _layout.sidebarViewLocation(view);
    final region = location == primarySidebarViewLocation
        ? 'sidebar'
        : secondarySidebarRegion;
    final selected = _layout.sidebarSelection(location);
    if (view == 'outline') _refreshOutline();
    if (selected == view && !_layout.isCollapsed(region)) {
      _focusedSidebarView = view;
      _layout.toggleRegion(region);
      return;
    }
    _layout.selectSidebarView(view);
    setState(() {
      _sidebarView = _layout.primarySidebarView;
      _secondarySidebarView = _layout.secondarySidebarView;
      _focusedSidebarView = view;
      if (view == 'outline') _refreshOutline();
    });
    _layout.showRegion(region);
  }

  Future<void> _showMoveSidebarViewPicker() async {
    await QuickInput.show(
      context,
      hint: '选择要移动的视图',
      items: [
        for (final view in activityBarViewOrder)
          QuickItem(
            label: _sidebarViewLabel(view),
            detail: _sidebarViewLocationLabel(
              _layout.sidebarViewLocation(view),
            ),
            onRun: () => _showMoveSidebarViewDestination(view),
          ),
      ],
    );
  }

  Future<void> _showMoveFocusedSidebarViewPicker() async {
    final view = _focusedSidebarView;
    if (view == null || !activityBarViewOrder.contains(view)) return;
    await _showMoveSidebarViewDestination(view);
  }

  Future<void> _showMoveSidebarViewDestination(String view) async {
    if (!mounted) return;
    final current = _layout.sidebarViewLocation(view);
    await QuickInput.show(
      context,
      hint: '选择视图的新侧栏位置',
      items: [
        for (final destination in const [
          primarySidebarViewLocation,
          secondarySidebarViewLocation,
        ])
          QuickItem(
            label: _sidebarViewLocationLabel(destination),
            detail: destination == current ? '当前位置' : null,
            onRun: () async => _moveSidebarView(view, destination),
          ),
      ],
    );
  }

  void _moveSidebarView(String view, String destination) {
    if (!_layout.moveSidebarView(view, destination)) return;
    final region = destination == primarySidebarViewLocation
        ? 'sidebar'
        : secondarySidebarRegion;
    setState(() {
      _sidebarView = _layout.primarySidebarView;
      _secondarySidebarView = _layout.secondarySidebarView;
      _focusedSidebarView = view;
    });
    _layout.showRegion(region);
  }

  Future<void> _resetSidebarViewLocations() async {
    if (!_layout.resetSidebarViewLocations()) return;
    setState(() {
      _sidebarView = _layout.primarySidebarView;
      _secondarySidebarView = _layout.secondarySidebarView;
      _focusedSidebarView = _sidebarView ?? _secondarySidebarView;
    });
  }

  String _sidebarViewLabel(String view) => switch (view) {
        'explorer' => '资源管理器',
        'search' => '搜索',
        'outline' => '大纲',
        'git' => '源代码管理',
        _ => view,
      };

  String _sidebarViewLocationLabel(String location) =>
      location == primarySidebarViewLocation ? '主侧栏' : '次侧栏';

  void _focusSidebarRegion(String location) {
    final view = _layout.sidebarSelection(location);
    if (view == null || _focusedSidebarView == view) return;
    setState(() => _focusedSidebarView = view);
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
    _findGeneration++;
    _cancelRegexFind();
    _cancelRegexReplace();
    _pendingDefinitionPointers.clear();
    _pendingColumnSelectionStarts.clear();
    _pendingMoveSelectionChordTimer?.cancel();
    _pendingChordPrefix = null;
    _pollTimer?.cancel();
    _resourceTimer?.cancel();
    _stateSaveTimer?.cancel();
    _flushFindHistory();
    for (final d in _allDocViews) {
      _flushInput(d, commitComposition: true);
    }
    final compareBindings = _snapshotCompareViews.values.toList();
    for (final binding in compareBindings) {
      _flushInput(binding.view, commitComposition: true);
    }
    _shutdownLspWorkspace();
    // 退出前把未落盘的布局与会话冲写
    widget.layoutStore.save(_layout.root);
    widget.sessionStore.save(_encodeSession());
    for (final binding in compareBindings) {
      binding.dispose();
    }
    _snapshotCompareViews.clear();
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
    _panelTab.removeListener(_syncCommandContext);
    _layout.removeListener(_syncPanelMaximizationCommandContext);
    _searchQuery.dispose();
    _findQuery.dispose();
    _replaceInput.dispose();
    _outlineTimer?.cancel();
    _stopWorkspaceWatcher();
    for (final timer in _syntaxRefreshTimers.values) {
      timer.cancel();
    }
    _syntaxRefreshTimers.clear();
    _panelTab.dispose();
    _editorTabMode.dispose();
    _editorTabSizing.dispose();
    _editorTabActionLocation.dispose();
    _editorTabCloseActionVisibility.dispose();
    _editorTabActionReserveSpace.dispose();
    _editorTabHoveredTarget.dispose();
    _editorTabWrap.dispose();
    _pinnedTabsOnSeparateRow.dispose();
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

    final activeDocument = _active;
    final workspaceRoot = _workspaceRoot;
    final workspaceName = workspaceRoot == null
        ? null
        : p.basename(p.normalize(workspaceRoot));
    final windowTitle = WorkbenchWindowTitle.compose(
      platform: defaultTargetPlatform,
      activeEditorName: activeDocument?.name,
      dirty: activeDocument?.isDirty ?? false,
      workspaceName: workspaceName == null || workspaceName.isEmpty
          ? workspaceRoot
          : workspaceName,
    );

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
                  windowTitle: windowTitle,
                  windowControls: widget.windowControls,
                  onCloseRequested: _shutdownLspWorkspace,
                  layoutControlsBuilder: () => [
                    TitleMenuItem(
                      '侧栏',
                      commandId: 'view.toggleSidebar',
                      checked: !_layout.isCollapsed('sidebar'),
                    ),
                    TitleMenuItem(
                      '次侧栏',
                      commandId: 'workbench.action.toggleAuxiliaryBar',
                      checked: !_layout.isCollapsed(secondarySidebarRegion),
                    ),
                    TitleMenuItem(
                      '面板',
                      commandId: 'view.togglePanel',
                      checked: !_layout.isCollapsed('panel'),
                    ),
                  ],
                  menus: [
                    (
                      '文件(&&F)',
                      [
                        TitleMenuItem(
                          '新建文本文件(&&N)'
                              '${_sc('workbench.action.files.newUntitledFile')}',
                          commandId: 'workbench.action.files.newUntitledFile',
                        ),
                        const TitleMenuItem.separator(),
                        const TitleMenuItem('打开文件夹(&&O)',
                            commandId: 'file.openFolder'),
                        const TitleMenuItem.separator(),
                        TitleMenuItem('保存(&&S)${_sc('file.save')}',
                            commandId: 'file.save'),
                        TitleMenuItem('另存为…(&&A)${_sc('file.saveAs')}',
                            commandId: 'file.saveAs'),
                        const TitleMenuItem.separator(),
                        const TitleMenuItem('从磁盘还原(&&R)',
                            commandId: 'file.revert'),
                      ],
                    ),
                    (
                      '编辑(&&E)',
                      [
                        TitleMenuItem('撤销(&&U)${_sc('editor.undo')}',
                            commandId: 'editor.undo'),
                        TitleMenuItem('重做(&&R)${_sc('editor.redo')}',
                            commandId: 'editor.redo'),
                        TitleMenuItem('查找…(&&F)${_sc('editor.find')}',
                            commandId: 'editor.find'),
                        TitleMenuItem('替换…(&&H)${_sc('editor.replace')}',
                            commandId: 'editor.replace'),
                      ],
                    ),
                    (
                      '查看(&&V)',
                      [
                        TitleMenuItem('命令面板(&&C)${_sc('view.commandPalette')}',
                            commandId: 'view.commandPalette'),
                        TitleMenuItem('快速打开文件…(&&O)${_sc('view.quickOpen')}',
                            commandId: 'view.quickOpen'),
                        TitleMenuItem('搜索…(&&S)${_sc('view.search')}',
                            commandId: 'view.search'),
                        const TitleMenuItem('大纲(&&L)',
                            commandId: 'view.outline'),
                        TitleMenuItem.submenu('外观(&&A)', children: [
                          TitleMenuItem.submenu('活动栏位置(&&A)', children: [
                            TitleMenuItem('侧边(&&D)',
                                commandId:
                                    'workbench.action.activityBarLocation.default',
                                checkedBuilder: () =>
                                    _layout.activityBarLocation ==
                                        ActivityBarLocation.side),
                            TitleMenuItem('顶部(&&T)',
                                commandId:
                                    'workbench.action.activityBarLocation.top',
                                checkedBuilder: () =>
                                    _layout.activityBarLocation ==
                                        ActivityBarLocation.top),
                            TitleMenuItem('底部(&&B)',
                                commandId:
                                    'workbench.action.activityBarLocation.bottom',
                                checkedBuilder: () =>
                                    _layout.activityBarLocation ==
                                        ActivityBarLocation.bottom),
                            TitleMenuItem('隐藏(&&H)',
                                commandId:
                                    'workbench.action.activityBarLocation.hide',
                                checkedBuilder: () =>
                                    _layout.activityBarLocation ==
                                        ActivityBarLocation.hidden),
                          ]),
                          TitleMenuItem.submenu('编辑器标签', children: [
                            TitleMenuItem(
                              '多标签',
                              commandId: 'workbench.action.editorTabs.multiple',
                              checkedListenable: _editorTabMode,
                              checkedBuilder: () =>
                                  _editorTabMode.value ==
                                  EditorTabMode.multiple,
                            ),
                            TitleMenuItem(
                              '单标签',
                              commandId: 'workbench.action.editorTabs.single',
                              checkedListenable: _editorTabMode,
                              checkedBuilder: () =>
                                  _editorTabMode.value == EditorTabMode.single,
                            ),
                            TitleMenuItem(
                              '不显示标签',
                              commandId: 'workbench.action.editorTabs.none',
                              checkedListenable: _editorTabMode,
                              checkedBuilder: () =>
                                  _editorTabMode.value == EditorTabMode.none,
                            ),
                            TitleMenuItem(
                              '标签自动换行',
                              commandId:
                                  'workbench.action.toggleEditorTabWrapping',
                              checkedListenable: _editorTabWrap,
                              checkedBuilder: () => _editorTabWrap.value,
                            ),
                            TitleMenuItem(
                              '固定标签单独成行',
                              commandId:
                                  'workbench.action.toggleEditorPinnedTabsSeparateRow',
                              checkedListenable: _pinnedTabsOnSeparateRow,
                              checkedBuilder: () =>
                                  _pinnedTabsOnSeparateRow.value,
                            ),
                            TitleMenuItem(
                              '显示关闭操作',
                              commandId:
                                  'workbench.action.toggleEditorTabCloseActionVisibility',
                              checkedListenable:
                                  _editorTabCloseActionVisibility,
                              checkedBuilder: () =>
                                  _editorTabCloseActionVisibility.value,
                            ),
                            TitleMenuItem(
                              '为关闭操作保留空间',
                              commandId:
                                  'workbench.action.toggleEditorTabActionReserveSpace',
                              checkedListenable: _editorTabActionReserveSpace,
                              checkedBuilder: () =>
                                  _editorTabActionReserveSpace.value,
                            ),
                            TitleMenuItem.submenu('标签尺寸', children: [
                              TitleMenuItem(
                                '按内容适配',
                                commandId:
                                    'workbench.action.editorTabs.sizing.fit',
                                checkedListenable: _editorTabSizing,
                                checkedBuilder: () =>
                                    _editorTabSizing.value ==
                                    EditorTabSizing.fit,
                              ),
                              TitleMenuItem(
                                '收缩',
                                commandId:
                                    'workbench.action.editorTabs.sizing.shrink',
                                checkedListenable: _editorTabSizing,
                                checkedBuilder: () =>
                                    _editorTabSizing.value ==
                                    EditorTabSizing.shrink,
                              ),
                              TitleMenuItem(
                                '固定宽度',
                                commandId:
                                    'workbench.action.editorTabs.sizing.fixed',
                                checkedListenable: _editorTabSizing,
                                checkedBuilder: () =>
                                    _editorTabSizing.value ==
                                    EditorTabSizing.fixed,
                              ),
                            ]),
                            TitleMenuItem.submenu('关闭操作位置', children: [
                              TitleMenuItem(
                                '左侧',
                                commandId:
                                    'workbench.action.editorTabs.actionLocation.left',
                                checkedListenable: _editorTabActionLocation,
                                checkedBuilder: () =>
                                    _editorTabActionLocation.value ==
                                    EditorTabActionLocation.left,
                              ),
                              TitleMenuItem(
                                '右侧',
                                commandId:
                                    'workbench.action.editorTabs.actionLocation.right',
                                checkedListenable: _editorTabActionLocation,
                                checkedBuilder: () =>
                                    _editorTabActionLocation.value ==
                                    EditorTabActionLocation.right,
                              ),
                            ]),
                          ]),
                          TitleMenuItem(
                            _toggleSideBarPositionTitle,
                            commandId: 'workbench.action.toggleSidebarPosition',
                          ),
                          const TitleMenuItem.separator(),
                          const TitleMenuItem('切换侧栏(&&S)',
                              commandId: 'view.toggleSidebar'),
                          TitleMenuItem(
                            '切换次侧栏(&&B)'
                                '${_sc('workbench.action.toggleAuxiliaryBar')}',
                            commandId: 'workbench.action.toggleAuxiliaryBar',
                            checkedBuilder: () =>
                                !_layout.isCollapsed(secondarySidebarRegion),
                          ),
                          const TitleMenuItem.separator(),
                          TitleMenuItem.submenu('面板位置(&&M)', children: [
                            TitleMenuItem('左侧(&&L)',
                                commandId:
                                    'workbench.action.positionPanelLeft',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelPosition ==
                                    PanelPosition.left),
                            TitleMenuItem('右侧(&&R)',
                                commandId:
                                    'workbench.action.positionPanelRight',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelPosition ==
                                    PanelPosition.right),
                            TitleMenuItem('顶部(&&T)',
                                commandId: 'workbench.action.positionPanelTop',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelPosition ==
                                    PanelPosition.top),
                            TitleMenuItem('底部(&&B)',
                                commandId:
                                    'workbench.action.positionPanelBottom',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelPosition ==
                                    PanelPosition.bottom),
                          ]),
                          const TitleMenuItem.separator(),
                          TitleMenuItem.submenu('面板对齐方式', children: [
                            TitleMenuItem('左侧',
                                commandId: 'workbench.action.alignPanelLeft',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelAlignment ==
                                    PanelAlignment.left),
                            TitleMenuItem('右侧',
                                commandId: 'workbench.action.alignPanelRight',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelAlignment ==
                                    PanelAlignment.right),
                            TitleMenuItem('居中',
                                commandId: 'workbench.action.alignPanelCenter',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelAlignment ==
                                    PanelAlignment.center),
                            TitleMenuItem('两端对齐',
                                commandId: 'workbench.action.alignPanelJustify',
                                checkedListenable: _layout,
                                checkedBuilder: () =>
                                    _layout.panelAlignment ==
                                    PanelAlignment.justify),
                          ]),
                          const TitleMenuItem.separator(),
                          const TitleMenuItem('切换面板(&&P)',
                              commandId: 'view.togglePanel'),
                        ]),
                      ],
                    ),
                    (
                      '帮助(&&H)',
                      [
                        const TitleMenuItem('关于 Alula Code(&&A)',
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
                            activeView: _focusedSidebarView ??
                                _sidebarView ??
                                _secondarySidebarView ??
                                'explorer',
                            sidebarCollapsed: _layout.isCollapsed('sidebar'),
                            axis: _layout.activityBarLocation ==
                                    ActivityBarLocation.side
                                ? Axis.vertical
                                : Axis.horizontal,
                            size: _layout.activityBarSize,
                            order: _layout.activityBarOrder,
                            pinnedViews: _layout.activityBarPinnedViews,
                            badgeDisabledViews:
                                _layout.activityBarBadgesDisabledViews,
                            accountsVisible: _layout.activityBarAccountsVisible,
                            onOrderChanged: _layout.setActivityBarOrder,
                            onPinnedViewsChanged:
                                _layout.setActivityBarPinnedViews,
                            onBadgeDisabledViewsChanged:
                                _layout.setActivityBarBadgesDisabledViews,
                            onAccountsVisibilityChanged:
                                _layout.setActivityBarAccountsVisible,
                            onManageCommand: (command) => _runCommand(command),
                            onSizeChanged: _layout.activityBarLocation ==
                                    ActivityBarLocation.side
                                ? _layout.setActivityBarSize
                                : null,
                            onSelectView: _selectSidebarView,
                          ),
                      'sidebar': (_) => _buildSidebarViewRegion(
                            primarySidebarViewLocation,
                            _sidebarView,
                          ),
                      secondarySidebarRegion: (_) => _buildSidebarViewRegion(
                            secondarySidebarViewLocation,
                            _secondarySidebarView,
                          ),
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

  Widget _buildSidebarViewRegion(String location, String? view) {
    final title = _sidebarViewLocationLabel(location);
    return Focus(
      onFocusChange: (focused) {
        if (focused) _focusSidebarRegion(location);
      },
      child: switch (view) {
        'git' => _buildGitPanel(),
        'search' => _buildSearchPanel(),
        'outline' => _buildOutlinePanel(),
        'explorer' => _buildSidebar(),
        _ => SecondarySidebarEmptyState(title: title),
      },
    );
  }

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
          _buildOpenEditorsSection(),
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

  /// Open Editors 侧栏区段（上游 openEditorsView.ts）：按编辑器组分组的
  /// 打开文档树，支持点击/键盘激活、每行脏安全关闭、右键复制路径、脏计数
  /// 徽章与折叠态持久化。
  Widget _buildOpenEditorsSection() {
    final dirtyCount =
        _allDocs.where((doc) => doc.isDirty).length;
    final rows = <Widget>[];
    for (final group in _groups.values) {
      final label = group.region == 'editor'
          ? '主编辑器组'
          : '编辑器组 ${group.region.substring('editor-'.length)}';
      rows.add(Container(
        key: ValueKey('open-editors-group-${group.region}'),
        padding: const EdgeInsets.only(left: 8, top: 3, bottom: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
          ),
        ),
      ));
      for (final doc in group.docs) {
        final active = group.activeDocId == doc.id;
        rows.add(CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () =>
                _activateOpenEditorsRow(group, doc),
            const SingleActivator(LogicalKeyboardKey.space): () =>
                _activateOpenEditorsRow(group, doc),
          },
          child: Focus(
            key: ValueKey('open-editors-focus-${group.region}-${doc.id}'),
            focusNode: _openEditorsRowFocus.putIfAbsent(
                '${group.region}:${doc.id}',
                () => FocusNode(debugLabel: 'open-editors-row')),
            child: InkWell(
              key: ValueKey('open-editors-doc-${group.region}-${doc.id}'),
              canRequestFocus: false,
              onTap: () => _activateOpenEditorsRow(group, doc),
              onSecondaryTapUp: (details) =>
                  _showOpenEditorsContextMenu(details, group, doc),
              child: Container(
                color: active ? const Color(0xFF22262D) : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(
                      doc.path == null
                          ? Icons.description_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 12,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      // RichText：行标签不参与既有 find.text 计数断言
                      // （侧栏/标签/面包屑共存的计数由原测试持有）。
                      child: RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          text: '${doc.name}${doc.isDirty ? " •" : ""}',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: group.previewDocId == doc.id
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: active
                                ? Colors.white
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey(
                          'open-editors-close-${group.region}-${doc.id}'),
                      tooltip: '关闭编辑器',
                      onPressed: () => _closeDoc(doc.id, group: group),
                      icon: const Icon(Icons.close, size: 12),
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: EdgeInsets.zero,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }
    return Container(
      key: const ValueKey('open-editors-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('open-editors-header'),
            onTap: () => setState(() {
              _openEditorsCollapsed = !_openEditorsCollapsed;
              _scheduleStateSave();
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
              child: Row(
                children: [
                  Icon(
                    _openEditorsCollapsed
                        ? Icons.chevron_right
                        : Icons.expand_more,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 2),
                  const Expanded(
                    child: Text(
                      '打开的编辑器',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (dirtyCount > 0)
                    Container(
                      key: const ValueKey('open-editors-dirty-count'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4D5760),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$dirtyCount',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_openEditorsCollapsed)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 4),
                children: rows,
              ),
            ),
        ],
      ),
    );
  }

  void _activateOpenEditorsRow(EditorGroup group, OpenDoc doc) {
    final current = _active;
    if (current != null && !identical(current, doc)) {
      _flushInput(current, commitComposition: true);
    }
    setState(() {
      group.activeDocId = doc.id;
      _noteActiveDocument(group, doc.id);
      _focusedRegion = group.region;
    });
    _syncCommandContext();
    _scheduleStateSave();
  }

  Future<void> _showOpenEditorsContextMenu(
    TapUpDetails details,
    EditorGroup group,
    OpenDoc doc,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final localPosition = overlay.globalToLocal(details.globalPosition);
    final position = RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (doc.path != null)
          const PopupMenuItem(value: 'copy-path', child: Text('复制路径')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'copy-path':
        final path = doc.path;
        if (path != null) {
          await Clipboard.setData(ClipboardData(text: path));
          if (mounted) {
            setState(() => _statusDetail = '已复制路径：$path');
          }
        }
        break;
    }
  }

  Widget _buildNode(TreeNode node, int depth) {
    final activePaths = _allDocs.map((d) => d.path).toSet();
    final compareSelection = _explorerCompareSelection;
    final isSelectedForCompare = compareSelection != null &&
        compareSelection.workspaceRoot == _workspaceRoot &&
        _canonicalPath(compareSelection.requestedPath) ==
            _canonicalPath(node.path);
    final isExplorerMultiSelected =
        !node.isDir && _isExplorerFileSelected(node.path);
    return Column(children: [
      InkWell(
        key: ValueKey('explorer-node:${node.path}'),
        onSecondaryTapUp: node.isDir || node.path.isEmpty
            ? null
            : (details) => unawaited(
                _showExplorerCompareContextMenu(node, details.globalPosition)),
        onTap: () {
          if (node.isDir) {
            setState(() {
              _explorerMultiSelection.clear();
              _explorerSelectionAnchor = null;
            });
            _toggleDir(node);
          } else if (HardwareKeyboard.instance.isShiftPressed ||
              (defaultTargetPlatform == TargetPlatform.macOS
                  ? HardwareKeyboard.instance.isMetaPressed
                  : HardwareKeyboard.instance.isControlPressed)) {
            _selectExplorerFile(node);
          } else {
            _selectExplorerFile(node);
            _openTreeFile(node);
          }
        },
        child: Container(
          padding: EdgeInsets.only(left: 8.0 + depth * 14, top: 3, bottom: 3),
          color: isExplorerMultiSelected
              ? const Color(0xFF24476D)
              : activePaths.contains(node.path)
                  ? const Color(0xFF20252E)
                  : isSelectedForCompare
                      ? const Color(0xFF29394F)
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
    final activeDoc = g.active;
    final mergeSession = activeDoc?.mergeResultSession;
    final activeMergeConflict = activeDoc == null
        ? null
        : _mergeConflictAtSelection(activeDoc);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_hidePasteWidget()),
      },
      child: Builder(
        builder: (paneContext) => DragTarget<int>(
          key: ValueKey('editor-drop-area-${g.region}'),
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) =>
              _handleGroupAreaDrop(g, details.data),
          builder: (context, _, __) => Container(
        color: const Color(0xFF14161A),
        child: Column(
          children: [
            _buildTabStrip(g),
            const Divider(height: 1),
            _buildBreadcrumb(g),
            Expanded(
              child: Builder(
                builder: (bodyContext) => DragTarget<int>(
                  key: ValueKey('editor-body-drop-${g.region}'),
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (details) {
                    final box =
                        bodyContext.findRenderObject() as RenderBox?;
                    _handleBodyAreaDrop(
                      g,
                      details.data,
                      box,
                      details.offset,
                    );
                  },
                  builder: (context, _, __) => Stack(
                fit: StackFit.expand,
                children: [
                  if (mergeSession == null)
                    _buildEditor(g)
                  else
                    MergeEditorSurface(
                      key: ValueKey('merge-editor-surface-${g.region}'),
                      base: mergeSession.baseText,
                      input1: mergeSession.input1Text,
                      input2: mergeSession.input2Text,
                      resultEditor: _buildEditor(g),
                      conflicts: mergeSession.conflicts,
                      resolutions: mergeSession.resolutions,
                      unresolvedConflictCount:
                          mergeSession.unresolvedConflictCount,
                      activeConflict: activeMergeConflict,
                      conflictRangesCurrent:
                          !mergeSession.hasStaleConflictRanges,
                      onNavigatePrevious: activeDoc == null
                          ? null
                          : () => _navigateMergeConflict(
                                activeDoc,
                                forward: false,
                              ),
                      onNavigateNext: activeDoc == null
                          ? null
                          : () => _navigateMergeConflict(
                                activeDoc,
                                forward: true,
                              ),
                      onAcceptInput1: activeDoc == null
                          ? null
                          : () => _acceptMergeConflict(
                                activeDoc,
                                AlulaMergeSide.input1,
                              ),
                      onAcceptInput2: activeDoc == null
                          ? null
                          : () => _acceptMergeConflict(
                                activeDoc,
                                AlulaMergeSide.input2,
                              ),
                      onAcceptAllInput1: activeDoc == null
                          ? null
                          : () => _acceptAllMergeConflicts(
                                activeDoc,
                                AlulaMergeSide.input1,
                              ),
                      onAcceptAllInput2: activeDoc == null
                          ? null
                          : () => _acceptAllMergeConflicts(
                                activeDoc,
                                AlulaMergeSide.input2,
                              ),
                    ),
                  if (_shouldShowPasteAsWidget(g))
                    Positioned(
                      top: 6,
                      right: 12,
                      child: Material(
                        color: const Color(0xFF252932),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(6),
                        child: TextButton.icon(
                          key: const ValueKey('paste-as-widget'),
                          onPressed: () => _changePasteType(),
                          icon: const Icon(Icons.content_paste_go, size: 16),
                          label: const Text('Change Paste Type'),
                        ),
                      ),
                    ),
                ],
              ),
              ),
            ),
            ),
          ],
        ),
        ),
          ),
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
              onTap: () => _onBreadcrumbSegmentTap(g, segments, i),
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
  void _onBreadcrumbSegmentTap(
    EditorGroup group,
    List<String> segments,
    int index,
  ) {
    final node = _findTreeNodeByRelPrefix(segments, index);
    debugPrint(
        'BCDBG seg=$segments idx=$index node=${node?.path} children=${node?.children?.length} roots=${_treeRoots.map((n) => n.path).take(6)}');
    final isLastSegment = index == segments.length - 1;
    if (isLastSegment) {
      // 上游 OutlineItem → BreadcrumbsOutlinePicker：文件段列出文档符号。
      _showBreadcrumbSymbolPicker(group);
      return;
    }
    if (node == null) {
      _revealInExplorer(segments, index);
      return;
    }
    // 上游 FileItem → BreadcrumbsFilePicker：目录段列出子项（懒加载目录
    // 由 picker 现场读取磁盘）。
    _showBreadcrumbFolderPicker(group, segments, index, node);
  }

  TreeNode? _findTreeNodeByRelPrefix(List<String> segments, int index) {
    final root = _workspaceRoot;
    if (root == null) return null;
    final prefix = segments.sublist(0, index + 1).join('/');
    final wanted = _normPath('$root/$prefix');
    TreeNode? find(List<TreeNode> nodes) {
      for (final node in nodes) {
        if (_normPath(node.path) == wanted) return node;
        if (node.children != null) {
          final hit = find(node.children!);
          if (hit != null) return hit;
        }
      }
      return null;
    }

    return find(_treeRoots);
  }

  Future<void> _showBreadcrumbFolderPicker(
    EditorGroup group,
    List<String> segments,
    int index,
    TreeNode node,
  ) async {
    // 文件树懒加载：未展开的目录现场读取磁盘子项（上游 FileItem picker 同样
    // 从文件服务读取）。
    List<TreeNode> children = node.children ?? const <TreeNode>[];
    if (node.children == null) {
      try {
        final entries = _core!.workspace.listDir(node.path);
        children = [
          for (final e in entries)
            TreeNode(
              name: e['name'] as String,
              path: e['path'] as String,
              isDir: (e['is_dir'] as bool?) ?? false,
            ),
        ];
      } on AlulaException {
        children = const <TreeNode>[];
      }
    }
    final action = await showMenu<String>(
      context: context,
      position: _breadcrumbPickerPosition(),
      items: [
        if (children.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('空文件夹')),
        for (final child in children)
          PopupMenuItem(
            value: '${child.isDir ? 'reveal' : 'open'}:${child.path}',
            child: Text(child.isDir ? '${child.name}/' : child.name),
          ),
      ],
    );
    if (!mounted || action == null) return;
    final childPath = action.split(':').sublist(1).join(':');
    final child = children.where((c) => c.path == childPath).firstOrNull;
    if (child == null) return;
    // 上游 _onSelectEvent：picker 交互先激活所属组。
    setState(() => _focusedRegion = group.region);
    if (child.isDir) {
      // 展开到所选子目录（逐级唤起文件树并展开）。_revealInExplorer 的
      // 末段守卫假定最后一段是文件名，追加空段使目录段参与展开。
      _revealInExplorer([...segments, child.name, ''], index + 1);
    } else {
      _openTreeFile(child);
    }
  }

  Future<void> _showBreadcrumbSymbolPicker(EditorGroup group) async {
    final doc = group.active;
    if (doc == null) return;
    // 点击时直查 LSP（不依赖大纲缓存，任意组即时可用）。
    final r = doc.doc.core.lsp.symbols(doc.id);
    final symbols = [
      for (final s in r?.symbols ?? const <Map<String, Object?>>[])
        (
          kind: s['kind'] as String? ?? '',
          name: s['name'] as String? ?? '',
          startUtf16: (s['start_utf16'] as num?)?.toInt() ?? 0,
          line: (s['line'] as num?)?.toInt() ?? 0,
        )
    ];
    final action = await showMenu<String>(
      context: context,
      position: _breadcrumbPickerPosition(),
      items: [
        if (symbols.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('未发现符号')),
        for (final sym in symbols)
          PopupMenuItem(
            value: 'symbol:${sym.startUtf16}:${sym.name}',
            child: Text('${_outlineKindBadge(sym.kind)} ${sym.name}'),
          ),
      ],
    );
    if (!mounted || action == null) return;
    // 上游 _onSelectEvent：picker 交互先激活所属组，再 reveal。
    setState(() {
      group.activeDocId = doc.id;
      _noteActiveDocument(group, doc.id);
      _focusedRegion = group.region;
    });
    final parts = action.split(':');
    final offset = int.tryParse(parts[1]) ?? 0;
    final activeDoc = group.active;
    if (activeDoc != null) {
      _setDocSelection(
        activeDoc,
        TextSelection.collapsed(offset: offset),
      );
      setState(() {});
    }
    _syncCommandContext();
    _scheduleStateSave();
  }

  RelativeRect _breadcrumbPickerPosition() {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final box = context.findRenderObject();
    final local = box is RenderBox && box.hasSize
        ? box.localToGlobal(const Offset(8, 60))
        : const Offset(8, 60);
    final position = overlay.globalToLocal(local);
    return RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );
  }

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

  bool _tabCloseActionReservesSpace(EditorGroup group, OpenDoc doc) =>
      _editorTabActionReserveSpace.value ||
      (_editorTabCloseActionVisibility.value &&
          (doc.id == group.activeDocId || doc.isDirty));

  double _tabFixedMinimumWidth(EditorGroup group, List<OpenDoc> docs) {
    final leftAction =
        _editorTabActionLocation.value == EditorTabActionLocation.left;
    var minimum = leftAction ? 80.0 : EditorTabWidthPolicy.fixedMinWidth;
    for (final doc in docs) {
      final padding = leftAction ? 10.0 : 16.0;
      final action = _tabCloseActionReservesSpace(group, doc) ? 24.0 : 0.0;
      final diskState = doc.diskState == DiskDocumentState.current ? 0.0 : 17.0;
      final stickyMark = group.stickyDocIds.contains(doc.id) ? 15.0 : 0.0;
      final occupied = padding +
          EditorTabFileIcon.slotWidth +
          action +
          diskState +
          stickyMark;
      if (occupied > minimum) minimum = occupied;
    }
    return minimum;
  }

  double _tabContentWidth(
    BuildContext context,
    EditorGroup group,
    OpenDoc doc, {
    required String displayLabel,
    required bool reserveActionSpace,
  }) {
    final label = TextPainter(
      text: TextSpan(
        text: '$displayLabel${doc.isDirty ? " •" : ""}',
        style: const TextStyle(fontSize: 12),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final leftAction =
        _editorTabActionLocation.value == EditorTabActionLocation.left;
    // Keep the action and its gap in the measured width only when this tab
    // allocates it; the optional disk-state marker always retains its width.
    return label.width +
        EditorTabFileIcon.slotWidth +
        (leftAction ? 10 : 24) +
        (reserveActionSpace ? 18 : 0) +
        14 +
        (group.stickyDocIds.contains(doc.id) ? 15 : 0) +
        (doc.diskState == DiskDocumentState.current ? 0 : 17);
  }

  Future<void> _showEditorTabContextMenu(
    TapUpDetails details,
    EditorGroup group,
    OpenDoc doc,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final localPosition = overlay.globalToLocal(details.globalPosition);
    final position = RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );
    final isSticky = group.stickyDocIds.contains(doc.id);
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: isSticky ? 'unpin' : 'pin',
          child: Text(isSticky ? '取消固定编辑器' : '固定编辑器'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'new-window', child: Text('在新窗口打开')),
        const PopupMenuItem(value: 'close', child: Text('关闭')),
        const PopupMenuItem(value: 'close-others', child: Text('关闭其他编辑器')),
        const PopupMenuItem(value: 'close-left', child: Text('关闭左侧编辑器')),
        const PopupMenuItem(value: 'close-right', child: Text('关闭右侧编辑器')),
        const PopupMenuItem(value: 'close-saved', child: Text('关闭已保存的编辑器')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'pin':
        _setEditorSticky(group, doc, true);
        break;
      case 'unpin':
        _setEditorSticky(group, doc, false);
        break;
      case 'new-window':
        await _moveEditorToNewWindow(group, doc);
        break;
      case 'close':
        await _closeTabsForAction(
          group,
          doc,
          EditorTabCloseOperation.close,
        );
        break;
      case 'close-others':
        await _closeTabsForAction(
          group,
          doc,
          EditorTabCloseOperation.closeOthers,
        );
        break;
      case 'close-left':
        await _closeTabsForAction(
          group,
          doc,
          EditorTabCloseOperation.closeToLeft,
        );
        break;
      case 'close-right':
        await _closeTabsForAction(
          group,
          doc,
          EditorTabCloseOperation.closeToRight,
        );
        break;
      case 'close-saved':
        await _closeTabsForAction(
          group,
          doc,
          EditorTabCloseOperation.closeSaved,
        );
        break;
      default:
        break;
    }
  }

  Widget _buildTabStrip(EditorGroup g) {
    final groupLabels = EditorTabLabelPolicy.labelsFor([
      for (final doc in g.docs)
        EditorTabLabelInput(name: doc.name, path: doc.path),
    ]);
    final labelsById = <int, String>{
      for (var index = 0; index < g.docs.length; index++)
        g.docs[index].id: groupLabels[index],
    };
    final visibleDocs = switch (_editorTabMode.value) {
      EditorTabMode.multiple => g.docs,
      EditorTabMode.single =>
        g.active == null ? const <OpenDoc>[] : [g.active!],
      EditorTabMode.none => const <OpenDoc>[],
    };
    final hasStickyTabs =
        visibleDocs.any((doc) => g.stickyDocIds.contains(doc.id));
    final hasOrdinaryTabs =
        visibleDocs.any((doc) => !g.stickyDocIds.contains(doc.id));
    final separatePinnedRows = _editorTabMode.value == EditorTabMode.multiple &&
        _pinnedTabsOnSeparateRow.value &&
        hasStickyTabs &&
        hasOrdinaryTabs;
    final stickyDocs = separatePinnedRows
        ? visibleDocs.where((doc) => g.stickyDocIds.contains(doc.id)).toList()
        : visibleDocs;
    final ordinaryDocs = separatePinnedRows
        ? visibleDocs.where((doc) => !g.stickyDocIds.contains(doc.id)).toList()
        : const <OpenDoc>[];

    Widget buildTabRow(
      List<OpenDoc> rowDocs, {
      required String rowName,
      required double availableWidth,
    }) {
      final sizing = _editorTabSizing.value;
      final widths = EditorTabWidthPolicy.layout(
        contentWidths: [
          for (final doc in rowDocs)
            _tabContentWidth(
              context,
              g,
              doc,
              displayLabel: labelsById[doc.id] ?? doc.name,
              reserveActionSpace: _tabCloseActionReservesSpace(g, doc),
            ),
        ],
        availableWidth: availableWidth,
        sizing: sizing,
        wrapping: _editorTabWrap.value,
        fixedMinWidthOverride: _tabFixedMinimumWidth(g, rowDocs),
      );
      final heldWidths = sizing == EditorTabSizing.fixed
          ? _editorTabHeldWidths[g.region]
          : null;
      final currentWidths = _editorTabLastWidths[g.region] ?? <int, double>{};
      final tabs = <Widget>[];
      for (var i = 0; i < rowDocs.length; i++) {
        final doc = rowDocs[i];
        final width = heldWidths?[doc.id] ?? widths[i];
        currentWidths[doc.id] = width;
        tabs.add(SizedBox(
          key: doc.id == g.activeDocId ? g.activeTabVisibilityKey : null,
          width: width,
          child: _buildTab(
            g,
            doc,
            displayLabel: labelsById[doc.id] ?? doc.name,
          ),
        ));
      }
      _editorTabLastWidths[g.region] = currentWidths;

      if (_editorTabWrap.value || visibleDocs.isEmpty) {
        g.lastAutoRevealedTabId = null;
      } else if (g.active != null && g.lastAutoRevealedTabId != g.activeDocId) {
        g.lastAutoRevealedTabId = g.activeDocId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _editorTabWrap.value) return;
          final activeTabContext = g.activeTabVisibilityKey.currentContext;
          if (activeTabContext != null) {
            unawaited(Scrollable.ensureVisible(
              activeTabContext,
              duration: Duration.zero,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ));
          }
        });
      }

      final tabLayout = _editorTabWrap.value
          ? Wrap(
              key: ValueKey('editor-tab-row-${g.region}-$rowName'),
              spacing: 0,
              runSpacing: 0,
              children: tabs,
            )
          : SingleChildScrollView(
              key: ValueKey('editor-tab-row-${g.region}-$rowName'),
              scrollDirection: Axis.horizontal,
              child: Row(children: tabs),
            );
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: MouseRegion(
          onEnter: (_) => _editorTabPointerInside.add(g.region),
          onExit: (_) {
            _editorTabPointerInside.remove(g.region);
            final held = _editorTabHeldWidths.remove(g.region);
            if (held != null && mounted) setState(() {});
          },
          child: tabLayout,
        ),
      );
    }

    return Container(
      key: ValueKey('editor-tab-strip-${g.region}'),
      constraints: const BoxConstraints(minHeight: 36),
      color: const Color(0xFF181B20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _editorTabLastWidths[g.region] = <int, double>{};
                if (!separatePinnedRows) {
                  return buildTabRow(
                    visibleDocs,
                    rowName: 'shared',
                    availableWidth: constraints.maxWidth,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildTabRow(
                      stickyDocs,
                      rowName: 'pinned',
                      availableWidth: constraints.maxWidth,
                    ),
                    buildTabRow(
                      ordinaryDocs,
                      rowName: 'ordinary',
                      availableWidth: constraints.maxWidth,
                    ),
                  ],
                );
              },
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
  Widget _buildTab(
    EditorGroup g,
    OpenDoc d, {
    required String displayLabel,
  }) {
    final actionLocation = _editorTabActionLocation.value;
    final reserveActionSpace = _tabCloseActionReservesSpace(g, d);
    final fileIcon = EditorTabFileIcon(
      key: ValueKey('editor-tab-file-icon-${g.region}-${d.id}'),
      fileName: d.name,
      languageId: d.path == null ? null : _languageIdOf(d.path!),
    );
    final isSticky = g.stickyDocIds.contains(d.id);
    final label = Tooltip(
      message: isSticky ? '$displayLabel（已固定）' : displayLabel,
      child: Semantics(
        label: displayLabel,
        excludeSemantics: true,
        child: Text(
          key: ValueKey('editor-tab-label-${g.region}-${d.id}'),
          '$displayLabel${d.isDirty ? " •" : ""}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontStyle:
                g.previewDocId == d.id ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
    final closeAction = ValueListenableBuilder<({String region, int docId})?>(
      valueListenable: _editorTabHoveredTarget,
      builder: (context, hoveredTarget, _) => EditorTabCloseAction(
        key: ValueKey('editor-tab-close-action-${g.region}-${d.id}'),
        actionKey: ValueKey('close-tab-${g.region}-${d.id}'),
        enabled: _editorTabCloseActionVisibility.value,
        emphasized: d.id == g.activeDocId ||
            d.isDirty ||
            hoveredTarget == (region: g.region, docId: d.id),
        onPressed: () => _closeDoc(d.id, group: g),
      ),
    );
    final tab = InkWell(
      onSecondaryTapUp: (details) => _showEditorTabContextMenu(details, g, d),
      onTap: () {
        final current = _active;
        if (current != null && !identical(current, d)) {
          _flushInput(current, commitComposition: true);
        }
        setState(() {
          g.activeDocId = d.id;
          _noteActiveDocument(g, d.id);
          _focusedRegion = g.region;
        });
        _syncCommandContext();
        _scheduleStateSave();
      },
      child: Container(
        key: ValueKey('tab-${d.id}'),
        padding: actionLocation == EditorTabActionLocation.left
            ? const EdgeInsets.only(right: 10)
            : EdgeInsets.symmetric(
                horizontal:
                    _editorTabSizing.value == EditorTabSizing.fixed ? 8 : 12,
              ),
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reserveActionSpace &&
                    actionLocation == EditorTabActionLocation.left) ...[
                  closeAction,
                  const SizedBox(width: 6),
                ],
                fileIcon,
                if (isSticky) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.push_pin,
                    key: ValueKey('sticky-tab-indicator-${g.region}-${d.id}'),
                    size: 12,
                    color: Colors.blueGrey.shade200,
                  ),
                ],
                if (_editorTabWrap.value ||
                    _editorTabSizing.value != EditorTabSizing.fit)
                  Flexible(fit: FlexFit.tight, child: label)
                else
                  label,
                if (d.diskState != DiskDocumentState.current) ...[
                  const SizedBox(width: 4),
                  Icon(
                    switch (d.diskState) {
                      DiskDocumentState.current => Icons.check,
                      DiskDocumentState.conflict => Icons.sync_problem_outlined,
                      DiskDocumentState.missing => Icons.file_present_outlined,
                      DiskDocumentState.readOnly => Icons.lock_outline,
                      DiskDocumentState.unavailable =>
                        Icons.warning_amber_outlined,
                    },
                    key: ValueKey('tab-disk-state-${d.id}'),
                    size: 13,
                    color: d.diskState == DiskDocumentState.conflict
                        ? Colors.orangeAccent
                        : Colors.blueGrey.shade300,
                  ),
                ],
                if (reserveActionSpace &&
                    actionLocation == EditorTabActionLocation.right) ...[
                  const SizedBox(width: 6),
                  closeAction,
                ],
              ],
            ),
            if (!reserveActionSpace)
              Positioned(
                left: actionLocation == EditorTabActionLocation.left
                    ? 0
                    : null,
                right: actionLocation == EditorTabActionLocation.right
                    ? (d.diskState == DiskDocumentState.current ? 0 : 17)
                    : null,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.center,
                  child: closeAction,
                ),
              ),
          ],
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) =>
          _editorTabHoveredTarget.value = (region: g.region, docId: d.id),
      onExit: (_) {
        if (_editorTabHoveredTarget.value == (region: g.region, docId: d.id)) {
          _editorTabHoveredTarget.value = null;
        }
      },
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: isSticky ? '取消固定编辑器' : '固定编辑器'): () =>
              _setEditorSticky(g, d, !isSticky),
        },
        child: Builder(
          builder: (tabContext) => DragTarget<int>(
            // 同组禁止落到自身；跨组放行同文档 id（激活目标既有视图）。
            onWillAcceptWithDetails: (details) =>
                details.data != d.id || _tabDragSourceRegion != g.region,
            onAcceptWithDetails: (details) {
              final draggedId = details.data;
              final sourceRegion = _tabDragSourceRegion;
              final source =
                  sourceRegion == null ? null : _groups[sourceRegion];
              if (source == null || identical(source, g)) {
                _moveDoc(g, draggedId, d.id);
                return;
              }
              var insertAfter = true;
              final box = tabContext.findRenderObject();
              if (box is RenderBox && box.hasSize) {
                insertAfter = box.globalToLocal(details.offset).dx >=
                    box.size.width / 2;
              }
              // 上游 isCopyOperation：Windows/Linux 用 Ctrl、macOS 用 Alt；
              // 未命名文档（上游 Singleton）不可复制，回退为移动。
              final movingIndex =
                  source.docs.indexWhere((doc) => doc.id == draggedId);
              final copyModifier =
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? HardwareKeyboard.instance.isAltPressed
                      : HardwareKeyboard.instance.isControlPressed;
              if (copyModifier &&
                  movingIndex >= 0 &&
                  source.docs[movingIndex].path != null) {
                _copyDocAcrossGroups(source, g, draggedId, d.id,
                    insertAfter: insertAfter);
              } else {
                _moveDocAcrossGroups(source, g, draggedId, d.id,
                    insertAfter: insertAfter);
              }
            },
            builder: (context, _, __) => Draggable<int>(
              data: d.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragStarted: () => _tabDragSourceRegion = g.region,
              onDragEnd: (_) => _tabDragSourceRegion = null,
              onDraggableCanceled: (_, __) => _tabDragSourceRegion = null,
              feedback: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252932),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child:
                      Text(displayLabel, style: const TextStyle(fontSize: 12)),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.4, child: tab),
              child: Listener(
                // 中键关闭（kMiddleMouseButton），不影响左键激活
                onPointerDown: (e) {
                  if (e.buttons == kMiddleMouseButton) {
                    _closeDoc(d.id, group: g);
                  }
                },
                child: tab,
              ),
            ),
          ),
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
    final wasSticky = g.stickyDocIds.contains(draggedId);
    _editorFocusNodes.remove(_focusKeyFor(g, moved))?.dispose();
    setState(() {
      g.docs.removeAt(from);
      final targetIndex = g.docs.indexWhere((doc) => doc.id == targetId);
      final stickyCount =
          g.docs.where((doc) => g.stickyDocIds.contains(doc.id)).length;
      final desiredIndex = from < to ? targetIndex + 1 : targetIndex;
      final lowerBound = wasSticky ? 0 : stickyCount;
      final upperBound = wasSticky ? stickyCount : g.docs.length;
      final insertionIndex = desiredIndex.clamp(lowerBound, upperBound).toInt();
      g.docs.insert(insertionIndex, moved);
      _normalizeStickyOrder(g);
    });
    _scheduleStateSave();
  }

  /// 跨组标签拖放移动：把源组的文档视图移到目标组 [target] 的 [targetTabId]
  /// 标签之前/之后（[insertAfter] 由指针相对目标标签中点的位置决定）。
  /// 移动同一个 OpenDoc 视图，保留 Rust 后端文本、脏标/存档点、撤销历史、
  /// 选区/光标、滚动与编辑器焦点；sticky 随动，干净的预览标签转为普通标签。
  /// 目标组已显示同一文档时激活既有视图并移除源组重复视图。
  void _moveDocAcrossGroups(
    EditorGroup source,
    EditorGroup target,
    int draggedId,
    int? targetTabId, {
    required bool insertAfter,
  }) {
    if (identical(source, target)) return;
    final from = source.docs.indexWhere((d) => d.id == draggedId);
    if (from < 0) return;
    final moving = source.docs[from];
    // targetTabId 为空表示落点在组区域：追加到组末尾。
    final targetIndex = targetTabId == null
        ? null
        : target.docs.indexWhere((d) => d.id == targetTabId);
    if (targetTabId != null && (targetIndex == null || targetIndex < 0)) {
      return;
    }
    if (target.docs.any((view) => identical(view, moving))) return;
    _flushInput(moving, commitComposition: true);

    final movingSticky = source.stickyDocIds.contains(moving.id);
    // 目标组已打开同一文档：激活既有视图并移除源组重复视图。
    OpenDoc? existingView;
    for (final view in target.docs) {
      if (!identical(view, moving) && view.sameDocumentAs(moving)) {
        existingView = view;
        break;
      }
    }
    if (existingView != null) {
      if (movingSticky && !target.stickyDocIds.contains(existingView.id)) {
        target.stickyDocIds.add(existingView.id);
        _normalizeStickyOrder(target);
      }
      _closeDocNow(source, moving);
      if (!mounted) return;
      setState(() {
        target.activeDocId = existingView!.id;
        _noteActiveDocument(target, existingView.id);
        _focusedRegion = target.region;
        _scheduleStateSave();
      });
      _syncCommandContext();
      _focusEditorAfterLayout(target, existingView);
      return;
    }

    final removeSourceRegion = source.docs.length == 1 && _groups.length > 1;
    if (removeSourceRegion && !_layout.removeRegion(source.region)) {
      setState(
          () => _statusDetail = '移动失败：无法移除空编辑器组 ${source.region}');
      return;
    }

    setState(() {
      source.docs.removeWhere((view) => identical(view, moving));
      source.stickyDocIds.remove(moving.id);
      source.recentDocIds.remove(moving.id);
      if (source.previewDocId == moving.id) source.previewDocId = null;
      if (source.docs.isNotEmpty && source.activeDocId == moving.id) {
        source.activeDocId = _mostRecentDocument(source)?.id;
        _noteActiveDocument(source, source.activeDocId);
      }

      // 干净的预览标签跨组移动后转为普通标签（不再作为目标组的预览）。
      final stickyCount = target.docs
          .where((doc) => target.stickyDocIds.contains(doc.id))
          .length;
      final int desiredIndex;
      if (targetTabId == null) {
        desiredIndex = target.docs.length;
      } else {
        final resolved = targetIndex!;
        desiredIndex = insertAfter ? resolved + 1 : resolved;
      }
      final lowerBound = movingSticky ? 0 : stickyCount;
      final upperBound = movingSticky ? stickyCount : target.docs.length;
      final insertionIndex =
          desiredIndex.clamp(lowerBound, upperBound).toInt();
      target.docs.insert(insertionIndex, moving);
      if (movingSticky) target.stickyDocIds.add(moving.id);
      _normalizeStickyOrder(source);
      _normalizeStickyOrder(target);
      target.activeDocId = moving.id;
      _noteActiveDocument(target, moving.id);

      final sourceFocusKey = _focusKeyFor(source, moving);
      final targetFocusKey = _focusKeyFor(target, moving);
      final movedFocusNode = _editorFocusNodes.remove(sourceFocusKey);
      if (movedFocusNode != null) {
        final oldTargetFocusNode = _editorFocusNodes.remove(targetFocusKey);
        if (oldTargetFocusNode != null &&
            oldTargetFocusNode != movedFocusNode) {
          oldTargetFocusNode.dispose();
        }
        _editorFocusNodes[targetFocusKey] = movedFocusNode;
      }

      if (source.docs.isEmpty && removeSourceRegion) {
        _groups.remove(source.region);
      }
      _focusedRegion = target.region;
      _statusDetail = '已移动编辑器：${source.region} → ${target.region}';
      _scheduleStateSave();
    });
    _syncCommandContext();
    _focusEditorAfterLayout(target, moving);
  }

  /// 跨组标签复制拖放（上游 editorDropTarget.isCopyOperation 与
  /// editorGroupView.doMoveOrCopyEditorAcrossGroups keepCopy 语义）：
  /// 把源组的文件文档复制为同文档新视图（`OpenDoc.viewOf`）插入目标组，
  /// 指针位置决定前/后；复制视图落在普通分区（不是 sticky、不是 preview），
  /// 源组完全不变；目标组已显示同一文档时仅激活既有视图。
  void _copyDocAcrossGroups(
    EditorGroup source,
    EditorGroup target,
    int draggedId,
    int? targetTabId, {
    required bool insertAfter,
  }) {
    if (identical(source, target)) return;
    final from = source.docs.indexWhere((d) => d.id == draggedId);
    if (from < 0) return;
    final moving = source.docs[from];
    if (moving.path == null) return;
    final targetIndex = targetTabId == null
        ? null
        : target.docs.indexWhere((d) => d.id == targetTabId);
    if (targetTabId != null && (targetIndex == null || targetIndex < 0)) {
      return;
    }
    _flushInput(moving, commitComposition: true);

    final existing = target.docs
        .where((view) => view.sameDocumentAs(moving))
        .firstOrNull;
    if (existing != null) {
      setState(() {
        target.activeDocId = existing.id;
        _noteActiveDocument(target, existing.id);
        _focusedRegion = target.region;
        _statusDetail = '已切换到编辑器：${target.region}';
        _scheduleStateSave();
      });
      _syncCommandContext();
      _focusEditorAfterLayout(target, existing);
      return;
    }

    final copy = OpenDoc.viewOf(moving);
    setState(() {
      final stickyCount = target.docs
          .where((doc) => target.stickyDocIds.contains(doc.id))
          .length;
      final int desiredIndex;
      if (targetTabId == null) {
        desiredIndex = target.docs.length;
      } else {
        final resolved = targetIndex!;
        desiredIndex = insertAfter ? resolved + 1 : resolved;
      }
      final insertionIndex =
          desiredIndex.clamp(stickyCount, target.docs.length).toInt();
      target.docs.insert(insertionIndex, copy);
      _normalizeStickyOrder(target);
      target.activeDocId = copy.id;
      _noteActiveDocument(target, copy.id);
      _focusedRegion = target.region;
      _statusDetail = '已复制编辑器：${source.region} → ${target.region}';
      _scheduleStateSave();
    });
    _syncCommandContext();
    _focusEditorAfterLayout(target, copy);
  }

  /// 组区域拖放落点（上游 editorDropTarget.handleDrop 无 splitDirection 的
  /// 中心区语义）：把被拖文档移入/复制入目标组末尾并激活目标组；同组区域
  /// 落点无操作。拆分落点建组属 LAY-10 独立子项。
  void _handleGroupAreaDrop(EditorGroup g, int draggedId) {
    final sourceRegion = _tabDragSourceRegion;
    final source = sourceRegion == null ? null : _groups[sourceRegion];
    if (source == null || identical(source, g)) return;
    final movingIndex = source.docs.indexWhere((doc) => doc.id == draggedId);
    if (movingIndex < 0) return;
    // 上游 isCopyOperation：Windows/Linux 用 Ctrl、macOS 用 Alt；未命名文档
    // （上游 Singleton）不可复制，回退为移动。
    final copyModifier =
        defaultTargetPlatform == TargetPlatform.macOS
            ? HardwareKeyboard.instance.isAltPressed
            : HardwareKeyboard.instance.isControlPressed;
    final copyRequested =
        copyModifier && source.docs[movingIndex].path != null;
    if (copyRequested) {
      _copyDocAcrossGroups(source, g, draggedId, null, insertAfter: false);
    } else {
      _moveDocAcrossGroups(source, g, draggedId, null, insertAfter: false);
    }
  }

  /// 拆分落点区域判定（上游 positionOverlay 编辑器拖动分支）：中心带
  /// （边缘 10% 以内）返回 null；其余按默认水平偏好：x < 宽/3 → 左、
  /// x > 2·宽/3 → 右、y < 高/2 → 上、否则下。
  _EditorGroupMoveDirection? _bodyDropZone(
    RenderBox? box,
    Offset globalOffset,
  ) {
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalOffset);
    final width = box.size.width;
    final height = box.size.height;
    const edgeFactor = 0.10;
    if (local.dx > width * edgeFactor &&
        local.dx < width * (1 - edgeFactor) &&
        local.dy > height * edgeFactor &&
        local.dy < height * (1 - edgeFactor)) {
      return null;
    }
    if (local.dx < width / 3) return _EditorGroupMoveDirection.left;
    if (local.dx > width * 2 / 3) return _EditorGroupMoveDirection.right;
    if (local.dy < height / 2) return _EditorGroupMoveDirection.up;
    return _EditorGroupMoveDirection.down;
  }

  /// 组编辑器正文区域拖放（上游 handleDrop + positionOverlay）：中心带按
  /// 追加/合并处理（同组无操作）；边缘带按方向建相邻新组并移入/复制入被
  /// 拖文档（同组边缘落点同样建组）；Windows/Linux Alt、macOS Shift 在
  /// 拖动期间禁用拆分区域（整组按中心处理）。
  void _handleBodyAreaDrop(
    EditorGroup g,
    int draggedId,
    RenderBox? bodyBox,
    Offset globalOffset,
  ) {
    final sourceRegion = _tabDragSourceRegion;
    final source = sourceRegion == null ? null : _groups[sourceRegion];
    if (source == null) return;
    final movingIndex = source.docs.indexWhere((doc) => doc.id == draggedId);
    if (movingIndex < 0) return;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final copyModifier = isMac
        ? HardwareKeyboard.instance.isAltPressed
        : HardwareKeyboard.instance.isControlPressed;
    final splitToggled = isMac
        ? HardwareKeyboard.instance.isShiftPressed
        : HardwareKeyboard.instance.isAltPressed;
    final copyRequested =
        copyModifier && source.docs[movingIndex].path != null;

    final zone = splitToggled ? null : _bodyDropZone(bodyBox, globalOffset);
    if (zone == null) {
      // 拆分关闭或中心带：追加/合并（同组无操作）。
      if (identical(source, g)) return;
      if (copyRequested) {
        _copyDocAcrossGroups(source, g, draggedId, null, insertAfter: false);
      } else {
        _moveDocAcrossGroups(source, g, draggedId, null, insertAfter: false);
      }
      return;
    }

    // 边缘带：以目标组为基准按方向建相邻新组（上游 addGroup(groupView, direction)）。
    var index = 2;
    while (_groups.containsKey('editor-$index')) {
      index++;
    }
    final freshRegion = 'editor-$index';
    if (!_layout.splitRegion(g.region, freshRegion, zone.axis,
        insertBefore: zone.insertBefore)) {
      setState(() => _statusDetail = '拆分失败：区域 ${g.region} 不可拆分');
      return;
    }
    _ensureGroupsFromLayout();
    final target = _groups[freshRegion];
    if (target == null) return;
    if (copyRequested) {
      _copyDocAcrossGroups(source, target, draggedId, null,
          insertAfter: false);
    } else {
      _moveDocAcrossGroups(source, target, draggedId, null,
          insertAfter: false);
    }
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
    final snippetSession = _snippetSessionFor(active);
    final choiceRange = snippetSession?.activeChoiceRange;
    final choiceOptions = choiceRange?.choice?.options;
    Widget? choiceOverlay;
    if (snippetSession != null) {
      _syncSnippetChoiceUi(snippetSession);
      if (choiceOptions != null &&
          choiceOptions.isNotEmpty &&
          !_snippetChoiceDismissed) {
        choiceOverlay = SnippetChoiceSuggestionList(
          options: choiceOptions,
          selectedIndex:
              _snippetChoiceSelectedIndex.clamp(0, choiceOptions.length - 1),
          onPreview: (index) => _previewSnippetChoice(snippetSession, index),
          onAccept: (index) =>
              _acceptSnippetChoice(active, snippetSession, index),
        );
      }
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
                                tabSize: active.tabSize,
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
                                caretOverlay: choiceOverlay,
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
                                    final session = _snippetSessionFor(active);
                                    if (session == null) {
                                      if (_snippetSession != null &&
                                          _snippetSessionDocId != active.id) {
                                        _clearSnippetSession();
                                      }
                                      active.additionalSelections = const [];
                                    } else {
                                      final inputWindowShift =
                                          active.inputWindow.startUtf16;
                                      final absoluteSelection = TextSelection(
                                        baseOffset:
                                            newValue.selection.baseOffset +
                                            inputWindowShift,
                                        extentOffset:
                                            newValue.selection.extentOffset +
                                            inputWindowShift,
                                        affinity: newValue.selection.affinity,
                                        isDirectional:
                                            newValue.selection.isDirectional,
                                      );
                                      final mirrors = session
                                          .mirrorSelection(absoluteSelection);
                                      if (mirrors == null) {
                                        _clearSnippetSession(
                                            clearSecondarySelections: false);
                                        active.additionalSelections = const [];
                                      } else {
                                        _snippetSessionView = active;
                                        active.additionalSelections =
                                            List.unmodifiable(mirrors);
                                      }
                                    }
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
                                    _pendingSnippetOperations =
                                        _snippetOperationsForInput(
                                      active,
                                      oldValue,
                                      newValue,
                                    );
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
                                onDelta: (delta) {
                                  _onInputDelta(active, delta);
                                  final session = _snippetSession;
                                  if (session == null ||
                                      _snippetSessionDocId != active.id) {
                                    return;
                                  }
                                  final mirroredOperations =
                                      _pendingSnippetOperations;
                                  _pendingSnippetOperations = null;
                                  if (delta.operations.isNotEmpty &&
                                      delta.version <= session.version) {
                                    _clearSnippetSession();
                                    return;
                                  }
                                  if (delta.operations.isNotEmpty &&
                                      mirroredOperations == null) {
                                    _clearSnippetSession();
                                    return;
                                  }
                                  if (!session.applyOperations(
                                    delta.operations.isEmpty
                                        ? const []
                                        : mirroredOperations!,
                                    nextVersion: delta.version,
                                  )) {
                                    _clearSnippetSession();
                                  }
                                },
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
                                onTextDragDrop:
                                    _canStartEditorTextDragDrop(active)
                                        ? (request) => _onSameDocumentTextDrop(
                                              active,
                                              request,
                                            )
                                        : null,
                                onExternalTextDrop:
                                    _canReceiveExternalTextDrop(active)
                                        ? (request) => _onExternalTextDrop(
                                              active,
                                              request,
                                            )
                                        : null,
                                onTextDragCompleted: (payload, operation) =>
                                    _onEditorTextDragCompleted(
                                  active,
                                  payload,
                                  operation,
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
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final minimapInset = constraints.maxWidth >= 720
                            ? editorMinimapWidth + 6
                            : 0.0;
                        final maxAvailableWidth =
                            (constraints.maxWidth - 24 - minimapInset)
                            .clamp(0.0, double.infinity)
                            .toDouble();
                        return Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: 12 + minimapInset,
                            ),
                            child: SizedBox(
                              key: const ValueKey(
                                'find-bar-available-bounds',
                              ),
                              width: maxAvailableWidth,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: _buildFindBar(
                                  maxAvailableWidth: maxAvailableWidth,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateFindBarWidthFromDrag(double horizontalDelta, double maxWidth) {
    if (maxWidth <= _findBarInitialWidth) return;
    final currentWidth = _findBarWidth > maxWidth ? maxWidth : _findBarWidth;
    final nextWidth = (currentWidth - horizontalDelta)
        .clamp(_findBarInitialWidth, maxWidth)
        .toDouble();
    if ((nextWidth - _findBarWidth).abs() < 0.5) return;
    setState(() => _findBarWidth = nextWidth);
  }

  void _toggleFindBarWidth(double maxWidth) {
    if (maxWidth <= _findBarInitialWidth) return;
    final currentWidth = _findBarWidth > maxWidth ? maxWidth : _findBarWidth;
    final nextWidth = currentWidth <= _findBarInitialWidth + 0.5
        ? maxWidth
        : _findBarInitialWidth;
    if ((nextWidth - _findBarWidth).abs() < 0.5) return;
    setState(() => _findBarWidth = nextWidth);
  }

  void _scheduleFindQueryWidthUpdate(double width) {
    if (!width.isFinite ||
        (_findQueryInputWidth - width).abs() < 0.5 ||
        _findQueryWidthUpdateScheduled) {
      return;
    }
    _findQueryWidthUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findQueryWidthUpdateScheduled = false;
      if (!mounted || (_findQueryInputWidth - width).abs() < 0.5) return;
      setState(() => _findQueryInputWidth = width);
    });
  }

  /// 查找/替换栏（feat-010，对标 VS Code 编辑器右上角浮层）。
  Widget _buildFindBar({required double maxAvailableWidth}) {
    final maxWidth = maxAvailableWidth.isFinite && maxAvailableWidth >= 0
        ? maxAvailableWidth
        : _findBarWidth;
    final width = _findBarWidth > maxWidth ? maxWidth : _findBarWidth;
    final count = _findPending
        ? '查找中…'
        : _findError != null
            ? '正则错误'
            : _matches.isEmpty
                ? (_findQuery.text.isEmpty ? '' : '无匹配')
                : '${_matchIndex < 0 ? '-' : _matchIndex + 1}/${_matches.length}${_findMatchesTruncated ? '+' : ''}';

    Widget buildFindInput() => LayoutBuilder(
          builder: (context, constraints) {
            _scheduleFindQueryWidthUpdate(constraints.maxWidth);
            return Focus(
              onKeyEvent: (node, event) => _handleFindInputKey(
                replace: false,
                event: event,
              ),
              child: TextField(
                key: const ValueKey('find-query-input'),
                controller: _findQuery,
                autofocus: true,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '查找',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onChanged: (_) => _onFindTextChanged(),
                onSubmitted: (_) => _gotoMatch(1),
              ),
            );
          },
        );

    final findControls = <Widget>[
      Tooltip(
        message: _findError ??
            (_findMatchesTruncated
                ? '结果过多，仅显示前 $maxFindRegexMatches 项'
                : count),
        child: Text(
          count,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
      ),
      IconButton(
        tooltip: '区分大小写',
        onPressed: () {
          setState(() {
            _caseSensitive = !_caseSensitive;
            _refreshMatches();
          });
          _scheduleFindHistoryUpdate();
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
        key: const ValueKey('find-whole-word'),
        tooltip: '全字匹配',
        onPressed: () {
          setState(() {
            _wholeWord = !_wholeWord;
            _refreshMatches();
          });
          _scheduleFindHistoryUpdate();
        },
        icon: Text('ab',
            style: TextStyle(
                fontSize: 11,
                color: _wholeWord
                    ? Colors.lightBlueAccent
                    : Colors.grey.shade400)),
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        key: const ValueKey('find-in-selection'),
        tooltip: '在选区中查找',
        isSelected: _findInSelection,
        onPressed: _findInSelection || _hasFindSelection()
            ? _toggleFindInSelection
            : null,
        icon: Text(
          '[]',
          style: TextStyle(
            fontSize: 11,
            color: _findInSelection
                ? Colors.lightBlueAccent
                : Colors.grey.shade400,
          ),
        ),
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        key: const ValueKey('find-regex'),
        tooltip: '使用正则表达式',
        onPressed: () {
          setState(() {
            _regexFind = !_regexFind;
            _refreshMatches();
          });
          _scheduleFindHistoryUpdate();
        },
        icon: Text('.*',
            style: TextStyle(
                fontSize: 12,
                color: _regexFind
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
    ];

    Widget buildFindRow(double availableWidth) {
      if (availableWidth >= 360) {
        return Row(
          children: [Expanded(child: buildFindInput()), ...findControls],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [Expanded(child: buildFindInput())]),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: findControls,
          ),
        ],
      );
    }

    Widget buildReplaceInput(double availableWidth) {
      final requestedWidth =
          _findQueryInputWidth > 0 ? _findQueryInputWidth : availableWidth;
      final inputWidth =
          requestedWidth > availableWidth ? availableWidth : requestedWidth;
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: inputWidth,
          child: Focus(
            onKeyEvent: (node, event) => _handleFindInputKey(
              replace: true,
              event: event,
            ),
            child: TextField(
              key: const ValueKey('replace-query-input'),
              controller: _replaceInput,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '替换为',
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: _onReplaceTextChanged,
            ),
          ),
        ),
      );
    }

    final replaceControls = <Widget>[
      IconButton(
        key: const ValueKey('find-preserve-case'),
        tooltip: '保留大小写',
        isSelected: _preserveCase,
        onPressed: _togglePreserveCase,
        icon: Text('Aa',
            style: TextStyle(
                fontSize: 11,
                color: _preserveCase
                    ? Colors.lightBlueAccent
                    : Colors.grey.shade400)),
        visualDensity: VisualDensity.compact,
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
    ];

    Widget buildReplaceRow(double availableWidth) {
      if (availableWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: availableWidth,
              child: buildReplaceInput(availableWidth),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: replaceControls,
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  buildReplaceInput(constraints.maxWidth),
            ),
          ),
          ...replaceControls,
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _toggleFind,
        const SingleActivator(LogicalKeyboardKey.escape, shift: true):
            _toggleFind,
      },
      child: Container(
        key: const ValueKey('find-bar'),
        width: width,
        padding: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF252932),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black45)],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        buildFindRow(constraints.maxWidth),
                  ),
                  if (_replaceVisible)
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          buildReplaceRow(constraints.maxWidth),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 10,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  key: const ValueKey('find-bar-resize-handle'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      _updateFindBarWidthFromDrag(details.delta.dx, maxWidth),
                  onDoubleTap: () => _toggleFindBarWidth(maxWidth),
                  child: Center(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.white24,
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

  // ---------- 面板：诊断 / 补全 / 语法 ----------

  Widget _buildPanel() {
    return Container(
      color: const Color(0xFF181B20),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _panelTab,
                    onTap: (index) {
                      const commandIds = [
                        'view.panelDiagnostics',
                        'view.panelCompletions',
                        'view.panelSyntax',
                      ];
                      if (index < commandIds.length) {
                        _runCommand(commandIds[index]);
                      }
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
                ),
                ListenableBuilder(
                  listenable: _layout,
                  builder: (context, _) {
                    final maximized = _layout.panelMaximized;
                    return IconButton(
                      key: const ValueKey('panel-maximize-toggle'),
                      tooltip: maximized ? '还原面板' : '最大化面板',
                      onPressed: _layout.canMaximizePanel
                          ? () => _runCommand(
                                'workbench.action.toggleMaximizedPanel',
                              )
                          : null,
                      icon: Icon(
                        maximized
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                        size: 16,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ],
            ),
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
                onPressed: () {
                  setState(() => _gitDiff = '');
                  _onGitDiffNavigationAvailabilityChanged(false);
                },
                icon: const Icon(Icons.close, size: 14),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GitDiffPatchView(
            patch: _gitDiff,
            navigationController: _gitDiffNavigation,
            onNavigationAvailabilityChanged:
                _onGitDiffNavigationAvailabilityChanged,
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

class _SnapshotCompareBinding {
  _SnapshotCompareBinding({
    required this.source,
    required this.view,
    required this.originalText,
    required DiffViewModelResult initialDiff,
  }) : presentation = ValueNotifier<SnapshotComparePresentation>(
          SnapshotComparePresentation(diff: initialDiff),
        );

  final OpenDoc source;
  final OpenDoc view;
  final String originalText;
  final ValueNotifier<SnapshotComparePresentation> presentation;
  final Completer<void> closed = Completer<void>();
  Timer? timer;
  VoidCallback? closeRoute;
  bool isDisposed = false;

  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
    timer?.cancel();
    timer = null;
    view.disposeView();
    presentation.dispose();
    if (!closed.isCompleted) closed.complete();
  }
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
  MergeResultSession? mergeResultSession;
  TextFileOptions fileOptions;
  TextFileOptions savedFileOptions;
  bool lspAttached = false;
  bool dirtyDisk;
  DiskDocumentState diskState;
  bool conflictBaselineKnown;
  bool insertSpaces = true;
  int tabSize = 4;
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
      mergeResultSession?.dispose();
      mergeResultSession = null;
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
  bool get insertSpaces => _shared.insertSpaces;
  set insertSpaces(bool value) => _shared.insertSpaces = value;
  int get tabSize => _shared.tabSize;
  set tabSize(int value) => _shared.tabSize = value;
  DateTime? get lastEditAt => _shared.lastEditAt;
  set lastEditAt(DateTime? value) => _shared.lastEditAt = value;
  bool get undoRedoBusy => _shared.undoRedoBusy;
  set undoRedoBusy(bool value) => _shared.undoRedoBusy = value;
  UndoStack get undoStack => _shared.undoStack;
  MergeResultSession? get mergeResultSession => _shared.mergeResultSession;
  set mergeResultSession(MergeResultSession? value) =>
      _shared.mergeResultSession = value;
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

enum _DirtyEditorCloseDecision { save, discard, cancel }

typedef _EditorCloseTarget = ({EditorGroup group, OpenDoc doc});

/// 一个编辑器组（W2-2）：一组标签 + 组内激活文档。
class EditorGroup {
  EditorGroup(this.region);

  /// 对应布局树里的叶子 region（'editor'、'editor-2'…）。
  final String region;
  final GlobalKey activeTabVisibilityKey = GlobalKey();
  int? lastAutoRevealedTabId;
  final List<OpenDoc> docs = [];
  final Set<int> stickyDocIds = <int>{};
  final List<int> recentDocIds = <int>[];
  int lastActivationOrder = 0;
  int? activeDocId;
  int? previewDocId;

  OpenDoc? get active {
    for (final d in docs) {
      if (d.id == activeDocId) return d;
    }
    return null;
  }
}

/// 文件树节点。
typedef _ExplorerOpenDocumentIdentity = ({
  OpenDoc doc,
  int id,
  String path,
  String? uri,
  int version,
});

class _ExplorerCompareTarget {
  const _ExplorerCompareTarget({
    required this.workspaceRoot,
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  final String workspaceRoot;
  final String path;
  final String name;
  final bool isDirectory;
}

class _ExplorerCompareSelection {
  const _ExplorerCompareSelection({
    required this.workspaceRoot,
    required this.canonicalWorkspaceRoot,
    required this.requestedPath,
    required this.canonicalPath,
    required this.name,
    required this.originalText,
  });

  final String workspaceRoot;
  final String canonicalWorkspaceRoot;
  final String requestedPath;
  final String canonicalPath;
  final String name;
  final String originalText;
}

class _ResolvedExplorerCompareFile {
  const _ResolvedExplorerCompareFile({
    required this.canonicalRoot,
    required this.canonicalPath,
    required this.size,
    required this.modified,
  });

  final String canonicalRoot;
  final String canonicalPath;
  final int size;
  final DateTime modified;
}

class TreeNode {
  TreeNode({required this.name, required this.path, required this.isDir});

  final String name;
  final String path;
  final bool isDir;
  bool expanded = false;
  List<TreeNode>? children;
}
