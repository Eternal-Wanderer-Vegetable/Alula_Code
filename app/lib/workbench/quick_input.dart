/// 快速输入面板（docs/09 W3-1）：命令面板（Ctrl+Shift+P）与文件快速打开
/// （Ctrl+P）共用的浮层。顶部居中、失焦即关；过滤用 commands.dart 的
/// fuzzyScore（label、description 与 detail 三个字段）。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'commands.dart';

/// 候选项类型：普通条目或分组标题（上游 QuickPickItemKind）。
enum QuickItemKind {
  /// 可选条目。
  defaultItem,

  /// 分组标题/分隔行：不可选、不接收方向键与 Enter，过滤时随查询一起隐藏。
  separator,
}

/// 面板里的一个候选项。
///
/// 分隔行与多选条目可以没有动作：`commandId`/`onRun` 都缺省时该行只参与
/// 选择（上游 quick pick 的 item 只是数据）。
class QuickItem {
  const QuickItem({
    required this.label,
    this.semanticsLabel,
    this.description,
    this.detail,
    this.commandId,
    this.arguments,
    this.onRun,
    this.onPreview,
    this.buttons = const <QuickItemButton>[],
    this.kind = QuickItemKind.defaultItem,
    this.picked = false,
  });

  final String label;
  final String? semanticsLabel;

  /// 与 label 同行、右侧暗色的补充列（上游 `QuickPickItem.description`）：
  /// 命令面板的快捷键、快速打开的路径都属于这一列。
  final String? description;

  /// label 下方的第二行说明（上游 `QuickPickItem.detail`）。
  final String? detail;
  final String? commandId;
  final Object? arguments;
  final Future<void> Function()? onRun;
  final VoidCallback? onPreview;
  final List<QuickItemButton> buttons;
  final QuickItemKind kind;

  /// 多选模式的初始勾选状态（上游 `QuickPickItem.picked`）。
  final bool picked;
}

/// Quick Pick row action. Runs independently of the row's onRun/commandId.
class QuickItemButton {
  const QuickItemButton({
    required this.icon,
    required this.tooltip,
    required this.onRun,
    this.altEnter = false,
    this.ctrlCmdEnter = false,
    this.acceptModifiedClick = false,
    this.refreshItems = false,
    this.alwaysVisible = false,
    this.hoverIcon,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onRun;

  /// Use this button when the active row is accepted with Alt+Enter.
  final bool altEnter;

  /// Use this button when accepting with Ctrl+Enter or Command+Enter.
  final bool ctrlCmdEnter;

  /// Also applies the accept modifiers when clicking the row.
  final bool acceptModifiedClick;

  /// Keeps the picker open and reloads its provider after this action.
  final bool refreshItems;

  /// Shows this action on rows that are not selected.
  final bool alwaysVisible;

  /// Overrides the button icon while the pointer is over its row.
  final IconData? hoverIcon;
}

enum QuickInputValidationSeverity { info, warning, error }

class QuickInputValidationMessage {
  const QuickInputValidationMessage(this.message, this.severity);

  final String message;
  final QuickInputValidationSeverity severity;
}

/// A picker entered from an editor switch shortcut, with no filter field.
class QuickInputNavigation {
  const QuickInputNavigation({
    this.startAtLast = false,
    this.acceptOnRelease = const {},
  });

  final bool startAtLast;
  final Set<LogicalKeyboardKey> acceptOnRelease;
}

typedef QuickInputItemsProvider = Future<List<QuickItem>> Function(
  String query,
  ValueChanged<List<QuickItem>> publish,
);

class QuickInput {
  QuickInput._();

  /// 面板输入框的焦点节点。它们既不是可恢复的“先前焦点”，也不能作为下一步
  /// 的恢复目标：步骤切换时上一层路由会销毁，节点随之失效。
  static final Set<FocusNode> _panelFocusNodes = <FocusNode>{};

  /// 当前应恢复焦点的节点：跳过 QuickInput 面板自身的输入框。多步 flow 在
  /// 第一步捕获并把结果透传给后续步骤，使取消时回到流程外焦点。
  static FocusNode? externalFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (node != null && _panelFocusNodes.contains(node)) return null;
    return node;
  }

  static Future<String?> input(
    BuildContext context, {
    required String prompt,
    String value = '',
    FutureOr<String?> Function(String value)? validateInput,
    FutureOr<QuickInputValidationMessage?> Function(String value)?
        validateInputMessage,
    ValueChanged<String>? onValueChanged,
    Widget Function(BuildContext context, String value, VoidCallback refresh)?
        inputActionBuilder,
    List<String> history = const [],
    FocusNode? restoreFocus,
    VoidCallback? Function(String)? redirectOnInput,
  }) async {
    String? accepted;
    await show(
      context,
      hint: prompt,
      items: const [],
      inputMode: true,
      initialValue: value,
      validateInput: validateInput,
      validateInputMessage: validateInputMessage,
      onValueChanged: onValueChanged,
      inputActionBuilder: inputActionBuilder,
      inputHistory: history,
      restoreFocus: restoreFocus,
      redirectOnInput: redirectOnInput,
      onInputAccepted: (value) => accepted = value,
    );
    return accepted;
  }

  static Future<void> show(
    BuildContext context, {
    required String hint,
    required List<QuickItem> items,
    CommandService? commands,
    VoidCallback? onBack,
    FocusNode? restoreFocus,
    bool canSelectMany = false,
    String? validationMessage,
    void Function(List<QuickItem> picked)? onAccept,
    void Function(String commandId)? onCommandExecuted,
    bool inputMode = false,
    String initialValue = '',
    FutureOr<String?> Function(String value)? validateInput,
    FutureOr<QuickInputValidationMessage?> Function(String value)?
        validateInputMessage,
    List<String> inputHistory = const [],
    ValueChanged<String>? onInputAccepted,
    ValueChanged<String>? onValueChanged,
    VoidCallback? Function(String)? redirectOnInput,
    Widget Function(BuildContext context, String value, VoidCallback refresh)?
        inputActionBuilder,
    String? queryPrefix,
    Future<List<QuickItem>> Function(String query)? itemsProvider,
    QuickInputItemsProvider? progressiveItemsProvider,
    Object Function(String query)? itemsQueryKey,
    VoidCallback? onClose,
    QuickInputNavigation? navigation,
  }) {
    if (validateInput != null && validateInputMessage != null) {
      throw ArgumentError('Only one QuickInput validator may be provided');
    }
    if (itemsProvider != null && progressiveItemsProvider != null) {
      throw ArgumentError('Only one QuickInput item provider may be provided');
    }
    final QuickInputItemsProvider? resolvedItemsProvider =
        progressiveItemsProvider ??
            (itemsProvider == null ? null : (query, _) => itemsProvider(query));
    // 取消（Esc/屏障点击）且没有执行候选项/按钮、也没有返回上一步时恢复先前
    // 焦点（上游 quickInput 取消恢复语义）；执行/返回都会接管后续焦点。
    final restoreTarget = restoreFocus ?? externalFocus();
    var handled = false;
    var closeNotified = false;
    void notifyClosed() {
      if (closeNotified) return;
      closeNotified = true;
      onClose?.call();
    }

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'quick-input',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 80),
      pageBuilder: (context, _, __) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            type: MaterialType.transparency,
            child: _QuickInputPanel(
              hint: hint,
              items: items,
              commands: commands,
              onBack: onBack,
              canSelectMany: canSelectMany,
              validationMessage: validationMessage,
              onAccept: onAccept,
              onCommandExecuted: onCommandExecuted,
              inputMode: inputMode,
              initialValue: initialValue,
              validateInput: validateInput,
              validateInputMessage: validateInputMessage,
              inputHistory: inputHistory,
              onInputAccepted: onInputAccepted,
              onValueChanged: onValueChanged,
              redirectOnInput: redirectOnInput,
              inputActionBuilder: inputActionBuilder,
              queryPrefix: queryPrefix,
              itemsProvider: resolvedItemsProvider,
              itemsQueryKey: itemsQueryKey,
              navigation: navigation,
              onDispose: notifyClosed,
              onHandled: () => handled = true,
            ),
          ),
        );
      },
    ).then((_) {
      notifyClosed();
      if (handled) return;
      final target = restoreTarget;
      if (target != null && target.context != null) target.requestFocus();
    });
  }
}

class _QuickInputPanel extends StatefulWidget {
  const _QuickInputPanel({
    required this.hint,
    required this.items,
    this.commands,
    this.onBack,
    required this.canSelectMany,
    this.validationMessage,
    this.onAccept,
    this.onCommandExecuted,
    required this.inputMode,
    required this.initialValue,
    this.validateInput,
    this.validateInputMessage,
    required this.inputHistory,
    this.onInputAccepted,
    this.onValueChanged,
    this.redirectOnInput,
    this.inputActionBuilder,
    this.queryPrefix,
    this.itemsProvider,
    this.itemsQueryKey,
    this.navigation,
    required this.onDispose,
    required this.onHandled,
  });

  final String hint;
  final List<QuickItem> items;
  final CommandService? commands;
  final VoidCallback? onBack;
  final bool canSelectMany;
  final String? validationMessage;
  final void Function(List<QuickItem> picked)? onAccept;
  final void Function(String commandId)? onCommandExecuted;
  final VoidCallback onHandled;
  final VoidCallback onDispose;
  final bool inputMode;
  final String initialValue;
  final FutureOr<String?> Function(String value)? validateInput;
  final FutureOr<QuickInputValidationMessage?> Function(String value)?
      validateInputMessage;
  final List<String> inputHistory;
  final ValueChanged<String>? onInputAccepted;
  final ValueChanged<String>? onValueChanged;
  final VoidCallback? Function(String)? redirectOnInput;
  final Widget Function(
          BuildContext context, String value, VoidCallback refresh)?
      inputActionBuilder;
  final String? queryPrefix;
  final QuickInputItemsProvider? itemsProvider;

  /// Equal keys keep the current results and any active provider request.
  final Object Function(String query)? itemsQueryKey;
  final QuickInputNavigation? navigation;

  @override
  State<_QuickInputPanel> createState() => _QuickInputPanelState();
}

class _QuickInputPanelState extends State<_QuickInputPanel> {
  static final _noSpaces = FilteringTextInputFormatter.deny(RegExp(' '));
  static const _rowHeight = 22.0;
  static const _detailRowHeight = _rowHeight * 2;
  static const _listPadding = EdgeInsets.only(top: 4, bottom: 3);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  int _navigationGeneration = 0;
  Future<void>? _pendingPages;
  final _focusNode = FocusNode(debugLabel: 'quick-input-field');
  final _rowKeys = <QuickItem, GlobalKey>{};
  final _buttonFocusNodes = <QuickItem, List<FocusNode>>{};
  QuickItem? _hoveredRow;
  final _picked = <QuickItem>{};
  var _filtered = const <QuickItem>[];
  var _selected = 0;
  int _validationGeneration = 0;
  bool _validating = false;
  Future<bool>? _validationTask;
  QuickInputValidationMessage? _validation;

  bool get _hasValidator =>
      widget.validateInput != null || widget.validateInputMessage != null;
  int _historyIndex = -1;
  String _historyDraft = '';
  String _lastInputText = '';
  bool _accepting = false;
  bool _accepted = false;
  int _itemsGeneration = 0;
  bool _itemsLoading = false;
  String? _itemsError;
  List<QuickItem> _providedItems = const [];

  @override
  void initState() {
    super.initState();
    QuickInput._panelFocusNodes.add(_focusNode);
    for (final item in widget.items) {
      if (widget.canSelectMany && item.picked) _picked.add(item);
    }
    _controller.text = widget.initialValue;
    _lastInputText = _controller.text;
    _refilter(_controller.text);
    _controller.addListener(_onInputChanged);
    if (_hasValidator) unawaited(_validate());
    if (widget.itemsProvider != null) unawaited(_loadItems());
    widget.commands?.addListener(_onCommandsChanged);
    final navigation = widget.navigation;
    if (navigation != null) {
      final keyboard = HardwareKeyboard.instance;
      if (navigation.acceptOnRelease.isNotEmpty) {
        keyboard.addHandler(_onNavigationKeyRelease);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (navigation.acceptOnRelease
            .any((key) => !keyboard.logicalKeysPressed.contains(key))) {
          // The initiating modifier can be released before the route builds.
          unawaited(_runAt(_selected));
        } else if (navigation.startAtLast) {
          unawaited(_revealBoundary(_navigationGeneration, last: true));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _QuickInputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commands != widget.commands) {
      oldWidget.commands?.removeListener(_onCommandsChanged);
      widget.commands?.addListener(_onCommandsChanged);
      _refilter(_controller.text);
    }
  }

  @override
  void dispose() {
    if (widget.navigation?.acceptOnRelease.isNotEmpty == true) {
      HardwareKeyboard.instance.removeHandler(_onNavigationKeyRelease);
    }
    widget.onDispose();
    _validationGeneration++;
    _itemsGeneration++;
    widget.commands?.removeListener(_onCommandsChanged);
    QuickInput._panelFocusNodes.remove(_focusNode);
    for (final nodes in _buttonFocusNodes.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }
    _focusNode.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onCommandsChanged() => _refilter(_controller.text);

  Object _itemsQueryKey(String query) =>
      widget.itemsQueryKey?.call(query) ?? query;

  void _onInputChanged() {
    final query = _controller.text;
    final previous = _lastInputText;
    if (previous == query) return;
    _lastInputText = query;
    if (widget.redirectOnInput?.call(query) case final redirect?) {
      if (!_claimPickerAcceptance()) return;
      widget.onHandled();
      Navigator.of(context).pop();
      redirect();
      return;
    }
    final keepItems = widget.itemsProvider != null &&
        _itemsQueryKey(previous) == _itemsQueryKey(query);
    if (keepItems) {
      setState(() {});
    } else {
      _refilter(query);
    }
    widget.onValueChanged?.call(query);
    if (_hasValidator) unawaited(_validate());
    if (widget.itemsProvider != null && !keepItems) unawaited(_loadItems());
  }

  Future<void> _loadItems() async {
    final provider = widget.itemsProvider;
    if (provider == null) return;
    final generation = ++_itemsGeneration;
    final query = _controller.text;
    final key = _itemsQueryKey(query);
    bool current() =>
        mounted &&
        !_accepted &&
        generation == _itemsGeneration &&
        key == _itemsQueryKey(_controller.text);

    setState(() {
      _itemsLoading = true;
      _hoveredRow = null;
      _itemsError = null;
      _providedItems = const [];
      _filtered = const [];
    });
    var published = false;
    void applyItems(List<QuickItem> items) {
      if (!current()) return;
      final selected =
          published && _selected >= 0 && _selected < _filtered.length
              ? _filtered[_selected]
              : null;
      final retained = published ? items.toSet() : const <QuickItem>{};
      _rowKeys.removeWhere((item, _) => !retained.contains(item));
      final oldButtonNodes = <FocusNode>[];
      _buttonFocusNodes.removeWhere((item, nodes) {
        if (retained.contains(item)) return false;
        oldButtonNodes.addAll(nodes);
        return true;
      });
      if (oldButtonNodes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final node in oldButtonNodes) {
            node.dispose();
          }
        });
      }
      _providedItems = items;
      _refilter(query, keepSelected: selected);
    }

    try {
      final items = await provider(query, (partial) {
        if (!current() || !_itemsLoading) return;
        applyItems(partial);
        published = true;
      });
      applyItems(items);
    } catch (error) {
      if (!current()) return;
      if (published) applyItems(const []);
      setState(() => _itemsError = '搜索失败：$error');
    } finally {
      if (mounted && generation == _itemsGeneration) {
        setState(() => _itemsLoading = false);
      }
    }
  }

  Future<bool> _validate() {
    final task = _runValidation();
    _validationTask = task;
    return task;
  }

  Future<bool> _runValidation() async {
    if (!_hasValidator) return true;
    final generation = ++_validationGeneration;
    final value = _controller.text;
    setState(() => _validating = true);
    QuickInputValidationMessage? validation;
    try {
      final typed = widget.validateInputMessage;
      if (typed != null) {
        validation = await typed(value);
      } else {
        final message = await widget.validateInput!(value);
        if (message != null && message.isNotEmpty) {
          validation = QuickInputValidationMessage(
              message, QuickInputValidationSeverity.error);
        }
      }
    } catch (failure) {
      validation = QuickInputValidationMessage(
          '校验失败：$failure', QuickInputValidationSeverity.error);
    }
    if (!mounted ||
        generation != _validationGeneration ||
        value != _controller.text) {
      return false;
    }
    setState(() {
      _validating = false;
      _validation = validation;
    });
    return validation?.severity != QuickInputValidationSeverity.error;
  }

  Future<void> _acceptInput() async {
    if (_validating || _accepting || _accepted) return;
    _accepting = true;
    final route = ModalRoute.of(context);
    final value = _controller.text;
    try {
      if (!await (_validationTask ?? _validate()) ||
          !mounted ||
          route?.isCurrent != true ||
          value != _controller.text) {
        return;
      }
      _accepted = true;
      widget.onHandled();
      Navigator.of(context).pop();
      widget.onInputAccepted?.call(value);
    } finally {
      _accepting = false;
    }
  }

  void _refreshInputAction() {
    if (widget.itemsProvider != null) unawaited(_loadItems());
    widget.onValueChanged?.call(_controller.text);
    if (_hasValidator) unawaited(_validate());
    setState(() {});
    _focusNode.requestFocus();
  }

  void _navigateHistory(int delta) {
    final history = widget.inputHistory.take(50).toList();
    if (history.isEmpty) return;
    if (_historyIndex < 0) _historyDraft = _controller.text;
    final next = (_historyIndex + delta).clamp(-1, history.length - 1);
    if (next == _historyIndex) return;
    _historyIndex = next;
    _controller.text = next < 0 ? _historyDraft : history[next];
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  void _refilter(String query, {QuickItem? keepSelected}) {
    var q = query.trim();
    final prefix = widget.queryPrefix;
    if (prefix != null && q.startsWith(prefix)) {
      q = q.substring(prefix.length).trimLeft();
    }
    final scored = <(QuickItem, int, int)>[];
    final sourceItems =
        widget.itemsProvider == null ? widget.items : _providedItems;
    for (final (index, item) in sourceItems.indexed) {
      if (item.kind == QuickItemKind.separator) {
        // 上游：分组标题不参与匹配，有查询时与不匹配条目一起消失。
        if (q.isEmpty || widget.itemsProvider != null) {
          scored.add((item, 0, index));
        }
        continue;
      }
      if (item.commandId case final id?
          when !(widget.commands?.isVisible(id) ?? false)) {
        continue;
      }
      final s = widget.itemsProvider != null
          ? 0
          : fuzzyScore(q, item.label) ??
              fuzzyScore(q, item.description ?? '') ??
              fuzzyScore(q, item.detail ?? '');
      if (s != null) scored.add((item, s, index));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
    });
    final filtered = scored.map((e) => e.$1).toList();
    final selectedIndex =
        keepSelected == null ? -1 : filtered.indexOf(keepSelected);
    final generation = ++_navigationGeneration;
    setState(() {
      _filtered = filtered;
      _selected = selectedIndex >= 0 ? selectedIndex : _initialSelectionIndex();
    });
    if (selectedIndex < 0 && _scroll.hasClients && _scroll.offset != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canNavigate(generation)) {
          _scroll.jumpTo(_scroll.position.minScrollExtent);
        }
      });
    }
    _previewSelected();
  }

  int _initialSelectionIndex() {
    final first = _firstSelectable();
    final navigation = widget.navigation;
    if (_filtered.isEmpty || navigation == null) return first;
    if (navigation.startAtLast) {
      return _filtered.lastIndexWhere(_isSelectable);
    }
    final second = _filtered.indexWhere(_isSelectable, first + 1);
    return second < 0 ? first : second;
  }

  bool _onNavigationKeyRelease(KeyEvent event) {
    if (event is! KeyUpEvent ||
        event.synthesized ||
        _accepted ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !widget.navigation!.acceptOnRelease.contains(event.logicalKey)) {
      return false;
    }
    unawaited(_runAt(_selected));
    return true;
  }

  void _previewSelected() {
    if (_selected < 0 || _selected >= _filtered.length) return;
    final item = _filtered[_selected];
    if (item.onPreview == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          _selected < _filtered.length &&
          identical(_filtered[_selected], item)) {
        item.onPreview?.call();
      }
    });
  }

  int _firstSelectable() {
    for (var i = 0; i < _filtered.length; i++) {
      if (_isSelectable(_filtered[i])) return i;
    }
    return 0;
  }

  bool _isSelectable(QuickItem item) => item.kind != QuickItemKind.separator;

  bool _enabled(QuickItem item) =>
      item.commandId == null ||
      (widget.commands?.isEnabled(item.commandId!) ?? false);

  /// 活动行 item 按钮的焦点节点：Tab 从输入框进入按钮、按钮间用默认遍历移动。
  List<FocusNode> _buttonNodesFor(QuickItem item) =>
      _buttonFocusNodes.putIfAbsent(
        item,
        () => [
          for (var i = 0; i < item.buttons.length; i++)
            FocusNode(debugLabel: 'quick-input-item-button-$i'),
        ],
      );

  /// 上游：Tab 把焦点交给活动条目的行尾按钮（没有按钮时不拦截）。
  bool _focusActiveItemButton() {
    if (_selected < 0 || _selected >= _filtered.length) return false;
    final item = _filtered[_selected];
    if (item.buttons.isEmpty || !_isSelectable(item)) return false;
    _buttonNodesFor(item).first.requestFocus();
    return true;
  }

  void _moveSelection(int delta) {
    final generation = ++_navigationGeneration;
    if (_filtered.isEmpty) return;
    var index = _selected;
    var wrapped = false;
    for (var step = 0; step < _filtered.length; step++) {
      final next = index + delta;
      if (next < 0 || next >= _filtered.length) {
        if (widget.navigation == null) return;
        wrapped = true;
        index = next % _filtered.length;
      } else {
        index = next;
      }
      if (_isSelectable(_filtered[index])) break;
    }
    if (index == _selected) return;
    _selectIndex(index);
    if (wrapped) {
      unawaited(_revealBoundary(generation, last: delta < 0));
    } else {
      _revealSelected();
    }
  }

  void _selectIndex(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    _previewSelected();
  }

  bool _canNavigate(int generation) =>
      mounted &&
      generation == _navigationGeneration &&
      _scroll.hasClients &&
      ModalRoute.of(context)?.isCurrent == true;

  int? _visiblePageEdge({required bool down}) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    for (var i = 0; i < _filtered.length; i++) {
      final index = down ? _filtered.length - i - 1 : i;
      final item = _filtered[index];
      if (!_isSelectable(item)) continue;
      final row = _rowKeys[item]?.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) continue;
      final rowTop = row.localToGlobal(Offset.zero).dy;
      if (rowTop >= top - 0.5 && rowTop + row.size.height <= bottom + 0.5) {
        return index;
      }
    }
    return null;
  }

  void _movePage({required bool down}) {
    if (!_scroll.hasClients) return;
    final generation = _navigationGeneration;
    final pending = _pendingPages;
    final next = pending == null
        ? _moveToPageEdge(generation, down: down)
        : pending.then((_) => _moveToPageEdge(generation, down: down));
    _pendingPages = next;
    unawaited(next.whenComplete(() {
      if (identical(_pendingPages, next)) _pendingPages = null;
    }));
  }

  Future<void> _moveToPageEdge(int generation, {required bool down}) async {
    if (!_canNavigate(generation)) return;
    final edge = _visiblePageEdge(down: down);
    if (edge != null && (down ? edge > _selected : edge < _selected)) {
      _selectIndex(edge);
      return;
    }
    // The first press reaches the edge of the current page. At that edge,
    // scroll one viewport and choose the outermost fully visible item again.
    for (var i = 0; i < _filtered.length && _canNavigate(generation); i++) {
      final position = _scroll.position;
      final offset = (position.pixels +
              (down ? position.viewportDimension : -position.viewportDimension))
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (offset == position.pixels) return;
      _scroll.jumpTo(offset);
      await WidgetsBinding.instance.endOfFrame;
      if (!_canNavigate(generation)) return;
      final nextEdge = _visiblePageEdge(down: down);
      if (nextEdge != null) {
        _selectIndex(nextEdge);
        return;
      }
    }
  }

  void _moveGroup({required bool down}) {
    final starts = <int>[];
    var startsGroup = true;
    var lastItem = -1;
    for (final (index, item) in _filtered.indexed) {
      if (!_isSelectable(item)) {
        startsGroup = true;
      } else {
        if (startsGroup) starts.add(index);
        startsGroup = false;
        lastItem = index;
      }
    }
    if (starts.isEmpty) return;

    final nextGroup = down
        ? starts.firstWhere((index) => index > _selected,
            orElse: () => starts.first)
        : starts.reversed.firstWhere((index) => index < _selected,
            orElse: () => starts.last);
    final target = down && nextGroup == _selected ? lastItem : nextGroup;
    final generation = ++_navigationGeneration;
    _selectIndex(target);
    if (target == starts.first || target == lastItem) {
      unawaited(_revealBoundary(generation, last: target == lastItem));
    } else {
      unawaited(_revealGroup(generation, target, down: down));
    }
  }

  Future<void> _revealGroup(int generation, int target,
      {required bool down}) async {
    await WidgetsBinding.instance.endOfFrame;
    for (var attempt = 0;
        attempt < _filtered.length && _canNavigate(generation);
        attempt++) {
      final firstVisible = _visiblePageEdge(down: false);
      final row = _rowKeys[_filtered[target]]?.currentContext;
      if (row != null && row.mounted) {
        final lastVisible = _visiblePageEdge(down: true);
        if (firstVisible == null ||
            lastVisible == null ||
            target < firstVisible ||
            target > lastVisible) {
          await Scrollable.ensureVisible(row, alignment: 0);
        }
        return;
      }

      final position = _scroll.position;
      final viewport = position.viewportDimension;
      // Jump near the unbuilt row first, then use the actual mounted rows to
      // correct for variable heights and the list's estimated scroll extent.
      final estimate = attempt == 0
          ? (position.maxScrollExtent + viewport) * target / _filtered.length
          : position.pixels +
              ((firstVisible == null ? down : target > firstVisible)
                  ? viewport
                  : -viewport);
      final offset = estimate
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (offset == position.pixels) {
        if (attempt == 0) continue;
        return;
      }
      _scroll.jumpTo(offset);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _moveToBoundary({required bool last}) {
    final generation = ++_navigationGeneration;
    for (var i = 0; i < _filtered.length; i++) {
      final index = last ? _filtered.length - i - 1 : i;
      if (!_isSelectable(_filtered[index])) continue;
      _selectIndex(index);
      unawaited(_revealBoundary(generation, last: last));
      return;
    }
  }

  Future<void> _revealBoundary(int generation, {required bool last}) async {
    // The lazy list can refine its maximum extent as variable-height rows
    // mount. Use the latest extent until the chosen boundary is visible.
    for (var i = 0; i < _filtered.length && _canNavigate(generation); i++) {
      final position = _scroll.position;
      final extent = last ? position.maxScrollExtent : position.minScrollExtent;
      if (extent == position.pixels) return;
      _scroll.jumpTo(extent);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _afterPendingPages(VoidCallback run) {
    final pending = _pendingPages;
    if (pending == null) {
      run();
      return;
    }
    final generation = _navigationGeneration;
    unawaited(pending.then((_) {
      if (_canNavigate(generation)) run();
    }));
  }

  /// 过滤/导航后把选中行滚入可视区（行高随 detail 第二行变化，不能按固定
  /// 行高估算）。
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selected < 0 || _selected >= _filtered.length) return;
      final context = _rowKeys[_filtered[_selected]]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(context,
          alignment: 0.5, duration: Duration.zero);
    });
  }

  bool _claimPickerAcceptance() {
    if (_accepted || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _accepted = true;
    return true;
  }

  Future<void> _runAt(
    int index, {
    ({bool alt, bool ctrlCmd}) modifiers = (alt: false, ctrlCmd: false),
    bool rowClick = false,
  }) async {
    if (index < 0 || index >= _filtered.length) return;
    final item = _filtered[index];
    if (!_isSelectable(item) || !_enabled(item)) return;
    if (modifiers.alt || modifiers.ctrlCmd) {
      final button = item.buttons
          .where((button) =>
              (!rowClick || button.acceptModifiedClick) &&
              ((modifiers.alt && button.altEnter) ||
                  (modifiers.ctrlCmd && button.ctrlCmdEnter)))
          .firstOrNull;
      if (button != null) {
        await _runItemButton(button);
        return;
      }
    }
    if (!_claimPickerAcceptance()) return;
    widget.onHandled();
    Navigator.of(context).pop();
    if (item.commandId case final id?) {
      widget.onCommandExecuted?.call(id);
      await widget.commands?.execute(id, arguments: item.arguments);
    } else {
      await item.onRun?.call();
    }
  }

  void _togglePicked(QuickItem item) {
    if (!_isSelectable(item) || !_enabled(item)) return;
    setState(() {
      if (!_picked.remove(item)) _picked.add(item);
    });
  }

  Iterable<QuickItem> get _pickableMatches =>
      _filtered.where((item) => _isSelectable(item) && _enabled(item));

  void _toggleAllFiltered(bool checked) {
    setState(() {
      if (checked) {
        _picked.addAll(_pickableMatches);
      } else {
        _picked.removeAll(_pickableMatches);
      }
    });
  }

  void _accept() {
    if (!_claimPickerAcceptance()) return;
    final items = widget.itemsProvider == null ? widget.items : _picked;
    final picked = [
      for (final item in items)
        if (_isSelectable(item) && _picked.contains(item)) item,
    ];
    widget.onHandled();
    Navigator.of(context).pop();
    widget.onAccept?.call(picked);
  }

  Future<void> _runItemButton(QuickItemButton button) async {
    if (button.refreshItems) {
      if (!mounted || _accepted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final generation = _itemsGeneration;
      final key = _itemsQueryKey(_controller.text);
      await button.onRun();
      if (mounted &&
          !_accepted &&
          generation == _itemsGeneration &&
          key == _itemsQueryKey(_controller.text) &&
          ModalRoute.of(context)?.isCurrent == true) {
        _focusNode.requestFocus();
        await _loadItems();
      }
      return;
    }
    if (!_claimPickerAcceptance()) return;
    widget.onHandled();
    Navigator.of(context).pop();
    await button.onRun();
  }

  /// 返回上一步：pop 当前层后由调用方重新显示上一步（上游 quick pick back）。
  /// 这是步骤导航而非取消，因此不恢复流程外焦点——焦点留给新面板的输入框。
  void _goBack() {
    if (!_claimPickerAcceptance()) return;
    widget.onHandled();
    Navigator.of(context).pop();
    widget.onBack?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (widget.navigation != null &&
        event is KeyDownEvent &&
        key == LogicalKeyboardKey.escape) {
      if (_claimPickerAcceptance()) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (widget.navigation != null &&
        key == LogicalKeyboardKey.tab &&
        keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      _moveSelection(keyboard.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final listModifiers =
        !keyboard.isShiftPressed && (!keyboard.isMetaPressed || isMac);
    if (!widget.inputMode &&
        listModifiers &&
        (key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.pageUp)) {
      _movePage(down: key == LogicalKeyboardKey.pageDown);
      return KeyEventResult.handled;
    }
    if (!widget.inputMode &&
        listModifiers &&
        (isMac ? keyboard.isMetaPressed : keyboard.isAltPressed) &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      _moveGroup(down: key == LogicalKeyboardKey.arrowDown);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!widget.inputMode &&
        listModifiers &&
        keyboard.isControlPressed &&
        (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end)) {
      _moveToBoundary(last: key == LogicalKeyboardKey.end);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed) {
      // 上游：Tab 进入活动条目的行尾按钮；没有按钮时交回默认焦点遍历。
      if (_focusActiveItemButton()) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (widget.inputMode && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _navigateHistory(-1);
      return KeyEventResult.handled;
    }
    if (widget.inputMode && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _navigateHistory(1);
      return KeyEventResult.handled;
    }
    if (widget.inputMode &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      unawaited(_acceptInput());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (widget.canSelectMany && event.logicalKey == LogicalKeyboardKey.space) {
      _afterPendingPages(() {
        if (_selected >= 0 && _selected < _filtered.length) {
          _togglePicked(_filtered[_selected]);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final modifiers = (
        alt: keyboard.isAltPressed,
        ctrlCmd: keyboard.isControlPressed || keyboard.isMetaPressed,
      );
      _afterPendingPages(() {
        if (widget.canSelectMany) {
          _accept();
        } else {
          unawaited(_runAt(_selected, modifiers: modifiers));
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final showMultiSelectControls = widget.canSelectMany && !widget.inputMode;
    final pickedCount =
        showMultiSelectControls ? _picked.where(_isSelectable).length : 0;
    final severity = _validation?.severity;
    final validationColor = switch (severity) {
      QuickInputValidationSeverity.info => Colors.lightBlue.shade300,
      QuickInputValidationSeverity.error => Colors.red.shade300,
      _ => Colors.orange.shade300,
    };
    final severityLabel = switch (severity) {
      QuickInputValidationSeverity.info => '信息',
      QuickInputValidationSeverity.warning => '警告',
      QuickInputValidationSeverity.error => '错误',
      null => '',
    };
    final validationText = _validation?.message ?? widget.validationMessage;
    final window = MediaQuery.sizeOf(context);
    final listHeight =
        (window.height * 0.4 / _detailRowHeight).floor() * _detailRowHeight;
    // Leave a small part of the next row visible when the list overflows.
    final maxListHeight = listHeight + 6 + _listPadding.vertical;
    final panel = Container(
      key: const ValueKey('quick-input'),
      margin: const EdgeInsets.only(top: 56),
      width: math.min(600.0, window.width * 0.62),
      decoration: BoxDecoration(
        color: const Color(0xFF252932),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black45)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.navigation == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (widget.onBack != null)
                    IconButton(
                      key: const ValueKey('quick-input-back'),
                      tooltip: '返回上一步',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      color: Colors.grey.shade400,
                    ),
                  if (showMultiSelectControls)
                    TextFieldTapRegion(
                      child: Tooltip(
                        message: '选择或清除所有匹配项',
                        child: Checkbox(
                          key: const ValueKey('quick-input-check-all'),
                          visualDensity: VisualDensity.compact,
                          value: _pickableMatches.isNotEmpty &&
                              _pickableMatches.every(_picked.contains),
                          onChanged: (value) =>
                              _toggleAllFiltered(value ?? false),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        inputFormatters:
                            widget.canSelectMany ? [_noSpaces] : null,
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          isDense: true,
                          border: severity == null
                              ? InputBorder.none
                              : UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: validationColor)),
                          enabledBorder: severity == null
                              ? InputBorder.none
                              : UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: validationColor)),
                          focusedBorder: severity == null
                              ? InputBorder.none
                              : UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: validationColor)),
                        ),
                      ),
                    ),
                  ),
                  if (widget.inputActionBuilder case final builder?)
                    builder(context, _controller.text, _refreshInputAction),
                  if (showMultiSelectControls) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '已选择 $pickedCount 项',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('quick-input-confirm'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _accept,
                      child: const Text('确定'),
                    ),
                  ],
                ],
              ),
            ),
          if (severity != null || (validationText?.isNotEmpty ?? false))
            Semantics(
              label: severityLabel,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    validationText ?? '',
                    key: const ValueKey('quick-input-validation'),
                    style: TextStyle(fontSize: 11, color: validationColor),
                  ),
                ),
              ),
            ),
          if (_itemsLoading)
            const LinearProgressIndicator(
                key: ValueKey('quick-input-loading'), minHeight: 2),
          if (_validating)
            const LinearProgressIndicator(
                key: ValueKey('quick-input-validating'), minHeight: 2),
          if (!widget.inputMode) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                          _itemsError ?? (_itemsLoading ? '正在搜索…' : '无匹配项'),
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    )
                  : ListView.builder(
                      key: _viewportKey,
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: _listPadding,
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => _buildRow(_filtered[i], i),
                    ),
            ),
          ],
        ],
      ),
    );
    if (widget.navigation == null) return panel;
    return Semantics(
      label: widget.hint,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: panel,
      ),
    );
  }

  Widget _buildRow(QuickItem item, int index) {
    if (item.kind == QuickItemKind.separator) {
      return Container(
        key: ValueKey('qi-separator-${item.label}'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
        alignment: Alignment.centerLeft,
        child: Text(
          item.label,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.4,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final selected = index == _selected;
    final enabled = _enabled(item);
    final picked = _picked.contains(item);
    final detail = item.detail;
    final hasDetail = detail != null && detail.isNotEmpty;
    final rowKey = _rowKeys.putIfAbsent(item, GlobalKey.new);
    final row = InkWell(
      onTap: enabled
          ? () {
              if (widget.canSelectMany) {
                _togglePicked(item);
              } else {
                final keyboard = HardwareKeyboard.instance;
                unawaited(_runAt(
                  index,
                  rowClick: true,
                  modifiers: (
                    alt: keyboard.isAltPressed,
                    ctrlCmd: keyboard.isControlPressed || keyboard.isMetaPressed,
                  ),
                ));
              }
            }
          : null,
      child: Container(
        key: ValueKey('qi-${item.label}'),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: BoxConstraints(
            minHeight: hasDetail ? _detailRowHeight : _rowHeight),
        color: selected ? const Color(0xFF2F3542) : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (widget.canSelectMany) ...[
                  Icon(
                    picked ? Icons.check_box : Icons.check_box_outline_blank,
                    key: ValueKey('qi-check-${item.label}'),
                    size: 14,
                    color:
                        enabled ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(item.label,
                      semanticsLabel: item.semanticsLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: enabled ? null : Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (item.description != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Text(item.description!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                // Tab traverses the active row's actions.
                for (final (buttonIndex, button) in item.buttons.indexed)
                  if (selected || button.alwaysVisible)
                    SizedBox.square(
                      dimension: _rowHeight,
                      child: ExcludeFocusTraversal(
                        excluding: !selected,
                        child: IconButton(
                          key: ValueKey('qi-button-${item.label}-$buttonIndex'),
                          focusNode: _buttonNodesFor(item)[buttonIndex],
                          tooltip: button.tooltip,
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          onPressed:
                              enabled ? () => _runItemButton(button) : null,
                          icon: Icon(
                            _hoveredRow == item
                                ? button.hoverIcon ?? button.icon
                                : button.icon,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
            if (detail != null && detail.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: 2,
                  left: widget.canSelectMany ? 22 : 0,
                ),
                child: Text(detail,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
    return Listener(
      key: rowKey,
      onPointerHover: (_) {
        if (_selected == index) return;
        _navigationGeneration++;
        _selectIndex(index);
      },
      child: item.buttons.any((button) => button.hoverIcon != null)
          ? MouseRegion(
              onEnter: (_) => setState(() => _hoveredRow = item),
              onExit: (_) {
                if (_hoveredRow == item) {
                  setState(() => _hoveredRow = null);
                }
              },
              child: row,
            )
          : row,
    );
  }
}
