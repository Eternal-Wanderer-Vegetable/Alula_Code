/// 快速输入面板（docs/09 W3-1）：命令面板（Ctrl+Shift+P）与文件快速打开
/// （Ctrl+P）共用的浮层。顶部居中、失焦即关；过滤用 commands.dart 的
/// fuzzyScore（label 与 detail 双字段）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'commands.dart';

/// 面板里的一个候选项。
class QuickItem {
  const QuickItem({
    required this.label,
    this.detail,
    this.commandId,
    this.arguments,
    this.onRun,
    this.buttons = const <QuickItemButton>[],
  }) : assert(commandId != null || onRun != null);

  final String label;
  final String? detail;
  final String? commandId;
  final Object? arguments;
  final Future<void> Function()? onRun;
  final List<QuickItemButton> buttons;
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

  static Future<void> show(
    BuildContext context, {
    required String hint,
    required List<QuickItem> items,
    CommandService? commands,
    VoidCallback? onBack,
    FocusNode? restoreFocus,
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
    required this.onHandled,
  });

  final String hint;
  final List<QuickItem> items;
  final CommandService? commands;
  final VoidCallback? onBack;
  final VoidCallback onHandled;

  @override
  State<_QuickInputPanel> createState() => _QuickInputPanelState();
}

class _QuickInputPanelState extends State<_QuickInputPanel> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'quick-input-field');
  var _filtered = const <QuickItem>[];
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    QuickInput._panelFocusNodes.add(_focusNode);
    _refilter('');
    _controller.addListener(() => _refilter(_controller.text));
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
    widget.commands?.removeListener(_onCommandsChanged);
    QuickInput._panelFocusNodes.remove(_focusNode);
    _focusNode.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onCommandsChanged() => _refilter(_controller.text);

  void _refilter(String query) {
    final q = query.trim();
    final scored = <(QuickItem, int)>[];
    for (final item in widget.items) {
      if (item.commandId case final id?
          when !(widget.commands?.isVisible(id) ?? false)) {
        continue;
      }
      final s = fuzzyScore(q, item.label) ?? fuzzyScore(q, item.detail ?? '');
      if (s != null) scored.add((item, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    setState(() {
      _filtered = scored.map((e) => e.$1).toList();
      _selected = 0;
    });
  }

  Future<void> _runAt(int index) async {
    if (index < 0 || index >= _filtered.length) return;
    final item = _filtered[index];
    if (item.commandId case final id?) {
      if (!(widget.commands?.isEnabled(id) ?? false)) return;
    }
    widget.onHandled();
    Navigator.of(context).pop();
    if (item.commandId case final id?) {
      await widget.commands?.execute(id, arguments: item.arguments);
    } else {
      await item.onRun?.call();
    }
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
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
          () => _selected = (_selected + 1).clamp(0, _filtered.length - 1));
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
          () => _selected = (_selected - 1).clamp(0, _filtered.length - 1));
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _runAt(_selected);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    const itemHeight = 34.0;
    final target = _selected * itemHeight;
    if (target < _scroll.offset) {
      _scroll.jumpTo(target);
    } else if (target + itemHeight > _scroll.offset + 340) {
      _scroll.jumpTo(target + itemHeight - 340);
    }
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
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                    itemBuilder: (context, i) {
                      final item = _filtered[i];
                      final selected = i == _selected;
                      final enabled = item.commandId == null ||
                          (widget.commands?.isEnabled(item.commandId!) ??
                              false);
                      return InkWell(
                        onTap: enabled ? () => _runAt(i) : null,
                        onHover: (hovering) {
                          if (hovering && !selected) {
                            setState(() => _selected = i);
                          }
                        },
                        child: Container(
                          key: ValueKey('qi-${item.label}'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          color: selected
                              ? const Color(0xFF2F3542)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(item.label,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: enabled
                                            ? null
                                            : Colors.grey.shade600),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (item.detail != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  flex: 2,
                                  child: Text(item.detail!,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                              for (final (buttonIndex, button)
                                  in item.buttons.indexed)
                                IconButton(
                                  key: ValueKey(
                                      'qi-button-${item.label}-$buttonIndex'),
                                  tooltip: button.tooltip,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                      minWidth: 24, minHeight: 24),
                                  padding: EdgeInsets.zero,
                                  iconSize: 14,
                                  onPressed: enabled
                                      ? () => _runItemButton(button)
                                      : null,
                                  icon: Icon(button.icon,
                                      size: 14, color: Colors.grey.shade400),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
