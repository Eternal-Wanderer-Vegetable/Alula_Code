/// 快速输入面板（docs/09 W3-1）：命令面板（Ctrl+Shift+P）与文件快速打开
/// （Ctrl+P）共用的浮层。顶部居中、失焦即关；过滤用 commands.dart 的
/// fuzzyScore（label、description 与 detail 三个字段）。
library;

import 'dart:async';

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
    this.description,
    this.detail,
    this.commandId,
    this.arguments,
    this.onRun,
    this.buttons = const <QuickItemButton>[],
    this.kind = QuickItemKind.defaultItem,
    this.picked = false,
  });

  final String label;

  /// 与 label 同行、右侧暗色的补充列（上游 `QuickPickItem.description`）：
  /// 命令面板的快捷键、快速打开的路径都属于这一列。
  final String? description;

  /// label 下方的第二行说明（上游 `QuickPickItem.detail`）。
  final String? detail;
  final String? commandId;
  final Object? arguments;
  final Future<void> Function()? onRun;
  final List<QuickItemButton> buttons;
  final QuickItemKind kind;

  /// 多选模式的初始勾选状态（上游 `QuickPickItem.picked`）。
  final bool picked;
}

/// 行尾动作按钮（上游 quick pick item buttons）：点击执行按钮动作并关闭
/// picker，不触发 item 的 onRun/commandId。
class QuickItemButton {
  const QuickItemButton({
    required this.icon,
    required this.tooltip,
    required this.onRun,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onRun;
}

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
    ValueChanged<String>? onValueChanged,
    Widget Function(BuildContext context, String value, VoidCallback refresh)?
        inputActionBuilder,
    List<String> history = const [],
    FocusNode? restoreFocus,
  }) async {
    String? accepted;
    await show(
      context,
      hint: prompt,
      items: const [],
      inputMode: true,
      initialValue: value,
      validateInput: validateInput,
      onValueChanged: onValueChanged,
      inputActionBuilder: inputActionBuilder,
      inputHistory: history,
      restoreFocus: restoreFocus,
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
    List<String> inputHistory = const [],
    ValueChanged<String>? onInputAccepted,
    ValueChanged<String>? onValueChanged,
    Widget Function(BuildContext context, String value, VoidCallback refresh)?
        inputActionBuilder,
    String? queryPrefix,
  }) {
    // 取消（Esc/屏障点击）且没有执行候选项/按钮、也没有返回上一步时恢复先前
    // 焦点（上游 quickInput 取消恢复语义）；执行/返回都会接管后续焦点。
    final restoreTarget = restoreFocus ?? externalFocus();
    var handled = false;
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
              inputHistory: inputHistory,
              onInputAccepted: onInputAccepted,
              onValueChanged: onValueChanged,
              inputActionBuilder: inputActionBuilder,
              queryPrefix: queryPrefix,
              onHandled: () => handled = true,
            ),
          ),
        );
      },
    ).then((_) {
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
    required this.inputHistory,
    this.onInputAccepted,
    this.onValueChanged,
    this.inputActionBuilder,
    this.queryPrefix,
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
  final bool inputMode;
  final String initialValue;
  final FutureOr<String?> Function(String value)? validateInput;
  final List<String> inputHistory;
  final ValueChanged<String>? onInputAccepted;
  final ValueChanged<String>? onValueChanged;
  final Widget Function(
          BuildContext context, String value, VoidCallback refresh)?
      inputActionBuilder;
  final String? queryPrefix;

  @override
  State<_QuickInputPanel> createState() => _QuickInputPanelState();
}

class _QuickInputPanelState extends State<_QuickInputPanel> {
  static final _noSpaces = FilteringTextInputFormatter.deny(RegExp(' '));

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'quick-input-field');
  final _rowKeys = <QuickItem, GlobalKey>{};
  final _buttonFocusNodes = <QuickItem, List<FocusNode>>{};
  final _picked = <QuickItem>{};
  var _filtered = const <QuickItem>[];
  var _selected = 0;
  int _validationGeneration = 0;
  bool _validating = false;
  Future<bool>? _validationTask;
  String? _validationError;
  int _historyIndex = -1;
  String _historyDraft = '';
  String _lastInputText = '';
  bool _accepting = false;
  bool _accepted = false;

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
    if (widget.validateInput != null) unawaited(_validate());
    widget.commands?.addListener(_onCommandsChanged);
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
    _validationGeneration++;
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

  void _onInputChanged() {
    if (_lastInputText == _controller.text) return;
    _lastInputText = _controller.text;
    _refilter(_controller.text);
    widget.onValueChanged?.call(_controller.text);
    if (widget.validateInput != null) unawaited(_validate());
  }

  Future<bool> _validate() {
    final task = _runValidation();
    _validationTask = task;
    return task;
  }

  Future<bool> _runValidation() async {
    final validate = widget.validateInput;
    if (validate == null) return true;
    final generation = ++_validationGeneration;
    final value = _controller.text;
    setState(() => _validating = true);
    String? error;
    try {
      error = await validate(value);
    } catch (failure) {
      error = '校验失败：$failure';
    }
    if (!mounted ||
        generation != _validationGeneration ||
        value != _controller.text) {
      return false;
    }
    setState(() {
      _validating = false;
      _validationError = error;
    });
    return error == null || error.isEmpty;
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
    widget.onValueChanged?.call(_controller.text);
    if (widget.validateInput != null) unawaited(_validate());
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

  void _refilter(String query) {
    var q = query.trim();
    final prefix = widget.queryPrefix;
    if (prefix != null && q.startsWith(prefix)) {
      q = q.substring(prefix.length).trimLeft();
    }
    final scored = <(QuickItem, int, int)>[];
    for (final (index, item) in widget.items.indexed) {
      if (item.kind == QuickItemKind.separator) {
        // 上游：分组标题不参与匹配，有查询时与不匹配条目一起消失。
        if (q.isEmpty) scored.add((item, 0, index));
        continue;
      }
      if (item.commandId case final id?
          when !(widget.commands?.isVisible(id) ?? false)) {
        continue;
      }
      final s = fuzzyScore(q, item.label) ??
          fuzzyScore(q, item.description ?? '') ??
          fuzzyScore(q, item.detail ?? '');
      if (s != null) scored.add((item, s, index));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
    });
    final filtered = scored.map((e) => e.$1).toList();
    setState(() {
      _filtered = filtered;
      _selected = _firstSelectable();
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
    if (_filtered.isEmpty) return;
    var index = _selected;
    for (var step = 0; step < _filtered.length; step++) {
      final next = index + delta;
      if (next < 0 || next >= _filtered.length) return;
      index = next;
      if (_isSelectable(_filtered[index])) break;
    }
    if (index != _selected) {
      setState(() => _selected = index);
      _revealSelected();
    }
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

  Future<void> _runAt(int index) async {
    if (index < 0 || index >= _filtered.length) return;
    final item = _filtered[index];
    if (!_isSelectable(item)) return;
    if (!_enabled(item)) return;
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

  void _accept() {
    final picked = [
      for (final item in widget.items)
        if (_isSelectable(item) && _picked.contains(item)) item,
    ];
    widget.onHandled();
    Navigator.of(context).pop();
    widget.onAccept?.call(picked);
  }

  Future<void> _runItemButton(QuickItemButton button) async {
    widget.onHandled();
    Navigator.of(context).pop();
    await button.onRun();
  }

  /// 返回上一步：pop 当前层后由调用方重新显示上一步（上游 quick pick back）。
  /// 这是步骤导航而非取消，因此不恢复流程外焦点——焦点留给新面板的输入框。
  void _goBack() {
    widget.onHandled();
    Navigator.of(context).pop();
    widget.onBack?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
      if (_selected >= 0 && _selected < _filtered.length) {
        _togglePicked(_filtered[_selected]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.canSelectMany) {
        _accept();
      } else {
        _runAt(_selected);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('quick-input'),
      margin: const EdgeInsets.only(top: 56),
      width: 560,
      decoration: BoxDecoration(
        color: const Color(0xFF252932),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black45)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                if (widget.inputActionBuilder case final builder?)
                  builder(context, _controller.text, _refreshInputAction),
              ],
            ),
          ),
          if ((_validationError ?? widget.validationMessage) case final message?
              when message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  key: const ValueKey('quick-input-validation'),
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade300),
                ),
              ),
            ),
          if (_validating)
            const LinearProgressIndicator(
                key: ValueKey('quick-input-validating'), minHeight: 2),
          if (!widget.inputMode) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('无匹配项',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => _buildRow(_filtered[i], i),
                    ),
            ),
          ],
        ],
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
    final rowKey = _rowKeys.putIfAbsent(item, GlobalKey.new);
    return InkWell(
      key: rowKey,
      onTap: enabled
          ? () {
              if (widget.canSelectMany) {
                _togglePicked(item);
              } else {
                _runAt(index);
              }
            }
          : null,
      onHover: (hovering) {
        if (hovering && !selected) {
          setState(() => _selected = index);
        }
      },
      child: Container(
        key: ValueKey('qi-${item.label}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: selected ? const Color(0xFF2F3542) : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                // 上游：item 按钮只在 hover/活动行显示（hover 会选中该行），
                // 键盘用户 Tab 进入当前行的按钮、Enter 触发。
                if (selected)
                  for (final (buttonIndex, button) in item.buttons.indexed)
                    IconButton(
                      key: ValueKey('qi-button-${item.label}-$buttonIndex'),
                      focusNode: _buttonNodesFor(item)[buttonIndex],
                      tooltip: button.tooltip,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      onPressed: enabled ? () => _runItemButton(button) : null,
                      icon: Icon(button.icon,
                          size: 14, color: Colors.grey.shade400),
                    ),
              ],
            ),
            if (item.detail case final detail? when detail.isNotEmpty)
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
  }
}
