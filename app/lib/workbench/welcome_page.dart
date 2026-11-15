/// 欢迎页与空编辑器组 watermark（docs/11 LAY-19a）。
///
/// 上游 Welcome 是编辑器区的欢迎标签页（Start/Recent/Walkthroughs/Help）；Alula 用
/// 编辑器区整页视图实现（不进入 editor 标签、不参与 split/move，差异登记在
/// docs/diagnostics/2026-11-15-p05/p05.60-welcome-and-watermark.md）。条目只是命令
/// 入口：命令不可见/不可用时由工作台过滤，按钮默认即键盘可达。
library;

import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.isCommandVisible,
    required this.onRunCommand,
    required this.onClose,
  });

  /// 命令存在且可见（`when` 通过）时才渲染对应条目。
  final bool Function(String commandId) isCommandVisible;
  final void Function(String commandId) onRunCommand;
  final VoidCallback onClose;

  static const List<({String id, IconData icon, String label})> startActions = [
    (
      id: 'workbench.action.files.newUntitledFile',
      icon: Icons.note_add_outlined,
      label: '新建文本文件',
    ),
    (
      id: 'file.openFolder',
      icon: Icons.folder_open_outlined,
      label: '打开文件夹…',
    ),
    (
      id: 'view.quickOpen',
      icon: Icons.search_outlined,
      label: '快速打开文件…',
    ),
    (
      id: 'view.commandPalette',
      icon: Icons.terminal_outlined,
      label: '命令面板',
    ),
  ];

  static const List<({String id, IconData icon, String label})> helpActions = [
    (
      id: 'help.about',
      icon: Icons.info_outline,
      label: '关于 Alula Code',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final start = startActions
        .where((action) => isCommandVisible(action.id))
        .toList(growable: false);
    final help = helpActions
        .where((action) => isCommandVisible(action.id))
        .toList(growable: false);
    return Container(
      key: const ValueKey('welcome-page'),
      color: const Color(0xFF14161A),
      child: Stack(
        children: [
          Positioned(
            top: 6,
            right: 10,
            child: IconButton(
              key: const ValueKey('welcome-close'),
              tooltip: '关闭欢迎页',
              onPressed: onClose,
              icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        'Alula Code',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '低内存跨平台代码编辑器 · Flutter 工作台 + Rust 编辑核心',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 20),
                    if (start.isNotEmpty)
                      _WelcomeSection(
                        title: '开始',
                        actions: start,
                        onRunCommand: onRunCommand,
                      ),
                    if (help.isNotEmpty) ...[
                      if (start.isNotEmpty) const SizedBox(height: 18),
                      _WelcomeSection(
                        title: '帮助',
                        actions: help,
                        onRunCommand: onRunCommand,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      '提示：缺失的功能会按 docs/03 的里程碑逐项接入。',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({
    required this.title,
    required this.actions,
    required this.onRunCommand,
  });

  final String title;
  final List<({String id, IconData icon, String label})> actions;
  final void Function(String commandId) onRunCommand;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: ValueKey('welcome-section-$title'),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade300),
        ),
        const SizedBox(height: 6),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: TextButton.icon(
              key: ValueKey('welcome-action-${action.id}'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.lightBlueAccent,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => onRunCommand(action.id),
              icon: Icon(action.icon, size: 15),
              label: Text(action.label),
            ),
          ),
      ],
    );
  }
}

/// 空编辑器组 watermark：没有标签时提示并给出入口（上游空组 watermark）。
class EmptyEditorGroupWatermark extends StatelessWidget {
  const EmptyEditorGroupWatermark({
    super.key,
    required this.isCommandVisible,
    required this.onRunCommand,
    required this.onShowWelcome,
  });

  final bool Function(String commandId) isCommandVisible;
  final void Function(String commandId) onRunCommand;
  final VoidCallback onShowWelcome;

  @override
  Widget build(BuildContext context) {
    final canNew = isCommandVisible('workbench.action.files.newUntitledFile');
    final canOpen = isCommandVisible('file.openFolder');
    return Center(
      child: Semantics(
        container: true,
        label: '空编辑器组',
        child: Column(
          key: const ValueKey('empty-group-watermark'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 34, color: Colors.grey.shade700),
            const SizedBox(height: 10),
            Text(
              '此编辑器组没有打开的文件',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (canNew)
                  TextButton(
                    key: const ValueKey(
                        'watermark-action-workbench.action.files.newUntitledFile'),
                    onPressed: () =>
                        onRunCommand('workbench.action.files.newUntitledFile'),
                    child: const Text('新建文件'),
                  ),
                if (canOpen)
                  TextButton(
                    key: const ValueKey('watermark-action-file.openFolder'),
                    onPressed: () => onRunCommand('file.openFolder'),
                    child: const Text('打开文件夹…'),
                  ),
                TextButton(
                  key: const ValueKey('watermark-show-welcome'),
                  onPressed: onShowWelcome,
                  child: const Text('显示欢迎页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
