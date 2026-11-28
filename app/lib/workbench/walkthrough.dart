/// Built-in Getting Started walkthrough and its bounded progress journal.
///
/// Alula does not currently host extensions, so this slice registers one
/// application-owned walkthrough with explicit command links.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'session_store.dart';

const String alulaGettingStartedWalkthroughId = 'alula.gettingStarted';
const int maxWalkthroughProgressJournalBytes = 16 * 1024;

class WalkthroughStep {
  const WalkthroughStep({
    required this.id,
    required this.title,
    required this.description,
    this.commandId,
    this.commandLabel,
  });

  final String id;
  final String title;
  final String description;
  final String? commandId;
  final String? commandLabel;
}

class WalkthroughDefinition {
  const WalkthroughDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
  });

  final String id;
  final String title;
  final String description;
  final List<WalkthroughStep> steps;

  int completedCount(Set<String> completedStepIds) =>
      steps.where((step) => completedStepIds.contains(step.id)).length;
}

const WalkthroughDefinition alulaGettingStartedWalkthrough =
    WalkthroughDefinition(
  id: alulaGettingStartedWalkthroughId,
  title: '开始使用 Alula Code',
  description: '用几个简短步骤熟悉编辑器、工作区和常用入口。',
  steps: <WalkthroughStep>[
    WalkthroughStep(
      id: 'create-edit-file',
      title: '创建并编辑文本',
      description: '新建文本文件，在编辑器中输入内容，然后保存文件。',
      commandId: 'workbench.action.files.newUntitledFile',
      commandLabel: '新建文本文件',
    ),
    WalkthroughStep(
      id: 'open-folder',
      title: '打开项目文件夹',
      description: '打开一个文件夹，在资源管理器中浏览项目文件。',
      commandId: 'file.openFolder',
      commandLabel: '打开文件夹…',
    ),
    WalkthroughStep(
      id: 'command-palette',
      title: '使用命令面板',
      description: '按 Ctrl+Shift+P（macOS 为 Cmd+Shift+P）搜索并运行工作台命令。',
      commandId: 'view.commandPalette',
      commandLabel: '打开命令面板',
    ),
    WalkthroughStep(
      id: 'quick-open',
      title: '快速打开文件',
      description: '使用快速打开按名称查找当前工作区中的文件。',
      commandId: 'view.quickOpen',
      commandLabel: '快速打开文件…',
    ),
    WalkthroughStep(
      id: 'welcome-recent',
      title: '查看最近项目',
      description: '欢迎页会保留最近打开的文件和工作区，方便下次继续。',
      commandId: 'workbench.action.welcome',
      commandLabel: '打开欢迎页',
    ),
  ],
);

/// Checksummed atomic progress journal with a strict size cap and known IDs.
class WalkthroughProgressStore {
  WalkthroughProgressStore({required this.path});

  final String path;

  Set<String> load() {
    if (_hasOversizedJournal()) return <String>{};
    final data = SessionStore(path: path).tryLoad();
    if (data == null ||
        data['format'] != 'alula-walkthrough-progress' ||
        data['version'] != 1 ||
        data['completed'] is! List) {
      return <String>{};
    }
    final allowed = _knownStepIds;
    return (data['completed'] as List)
        .whereType<String>()
        .where(allowed.contains)
        .toSet();
  }

  bool setCompleted(String stepId, bool completed) {
    if (!_knownStepIds.contains(stepId)) return false;
    final updated = load();
    if (completed) {
      updated.add(stepId);
    } else {
      updated.remove(stepId);
    }
    return save(updated);
  }

  bool reset() => save(const <String>{});

  bool save(Set<String> completedStepIds) {
    final completed = completedStepIds
        .where(_knownStepIds.contains)
        .toList(growable: false)
      ..sort();
    final payload = <String, Object?>{
      'format': 'alula-walkthrough-progress',
      'version': 1,
      'completed': completed,
    };
    if (utf8.encode(jsonEncode(payload)).length >
        maxWalkthroughProgressJournalBytes * 3 ~/ 4) {
      return false;
    }
    if (_hasOversizedJournal()) _deleteJournal();
    return SessionStore(path: path).save(payload);
  }

  bool _hasOversizedJournal() {
    for (final file in _journalFiles()) {
      try {
        if (file.existsSync() &&
            file.lengthSync() > maxWalkthroughProgressJournalBytes) {
          return true;
        }
      } on FileSystemException {
        return true;
      }
    }
    return false;
  }

  void _deleteJournal() {
    for (final file in _journalFiles()) {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // A failed cleanup remains a safe read fallback; save reports failure.
      }
    }
  }

  List<File> _journalFiles() => <File>[
        File(path),
        File('$path.bak'),
        File('$path.tmp'),
      ];
}

Set<String> get _knownStepIds =>
    alulaGettingStartedWalkthrough.steps.map((step) => step.id).toSet();

class WalkthroughPage extends StatelessWidget {
  const WalkthroughPage({
    super.key,
    required this.walkthrough,
    required this.completedStepIds,
    required this.selectedStepId,
    required this.isCommandVisible,
    required this.onSelectStep,
    required this.onToggleStep,
    required this.onRunCommand,
    required this.onBackToWelcome,
    required this.onClose,
  });

  final WalkthroughDefinition walkthrough;
  final Set<String> completedStepIds;
  final String selectedStepId;
  final bool Function(String commandId) isCommandVisible;
  final void Function(String stepId) onSelectStep;
  final void Function(String stepId, bool completed) onToggleStep;
  final void Function(String commandId) onRunCommand;
  final VoidCallback onBackToWelcome;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = walkthrough.steps.indexWhere(
      (step) => step.id == selectedStepId,
    );
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    final step = walkthrough.steps[index];
    final completedCount = walkthrough.completedCount(completedStepIds);
    final commandId = step.commandId;
    final canRunCommand = commandId != null && isCommandVisible(commandId);
    final isCompleted = completedStepIds.contains(step.id);
    return Container(
      key: const ValueKey('walkthrough-page'),
      color: const Color(0xFF14161A),
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('walkthrough-back-welcome'),
                  onPressed: onBackToWelcome,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('返回欢迎页'),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('walkthrough-close'),
                  tooltip: '关闭引导',
                  onPressed: onClose,
                  icon:
                      Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 22, 14, 6),
                        child: Semantics(
                          header: true,
                          child: Text(
                            walkthrough.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 14, 16),
                        child: Semantics(
                          label:
                              '已完成 $completedCount 项，共 ${walkthrough.steps.length} 项',
                          child: LinearProgressIndicator(
                            value: walkthrough.steps.isEmpty
                                ? 0
                                : completedCount / walkthrough.steps.length,
                            minHeight: 3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: walkthrough.steps.length,
                          itemBuilder: (context, itemIndex) {
                            final item = walkthrough.steps[itemIndex];
                            final selected = item.id == step.id;
                            final done = completedStepIds.contains(item.id);
                            return Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                key: ValueKey('walkthrough-step-${item.id}'),
                                selected: selected,
                                leading: Icon(
                                  done
                                      ? Icons.check_circle_outline
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => onSelectStep(item.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(42, 38, 42, 30),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '步骤 ${index + 1} / ${walkthrough.steps.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            header: true,
                            child: Text(
                              step.title,
                              key: ValueKey('walkthrough-current-${step.id}'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            step.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade300,
                              height: 1.55,
                            ),
                          ),
                          if (canRunCommand) ...[
                            const SizedBox(height: 22),
                            OutlinedButton.icon(
                              key: ValueKey('walkthrough-command-${step.id}'),
                              onPressed: () => onRunCommand(commandId),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: Text(step.commandLabel ?? '运行命令'),
                            ),
                          ],
                          const SizedBox(height: 26),
                          Semantics(
                            key: ValueKey(
                                'walkthrough-checkbox-semantics-${step.id}'),
                            container: true,
                            label: '标记为已完成：${step.title}',
                            checked: isCompleted,
                            onTap: () => onToggleStep(step.id, !isCompleted),
                            child: ExcludeSemantics(
                              child: Material(
                                type: MaterialType.transparency,
                                child: CheckboxListTile(
                                  key: ValueKey(
                                      'walkthrough-complete-${step.id}'),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: const Text('标记为已完成'),
                                  value: isCompleted,
                                  onChanged: (value) {
                                    if (value != null) {
                                      onToggleStep(step.id, value);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('walkthrough-previous'),
                                onPressed: index == 0
                                    ? null
                                    : () => onSelectStep(
                                          walkthrough.steps[index - 1].id,
                                        ),
                                icon: const Icon(Icons.arrow_back, size: 16),
                                label: const Text('上一步'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                key: const ValueKey('walkthrough-next'),
                                onPressed: index + 1 == walkthrough.steps.length
                                    ? null
                                    : () => onSelectStep(
                                          walkthrough.steps[index + 1].id,
                                        ),
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                label: const Text('下一步'),
                                iconAlignment: IconAlignment.end,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
