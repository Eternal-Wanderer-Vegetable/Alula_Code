/// 命令注册表（docs/09 W3-1）：菜单 / 键位 / 命令面板统一引用命令 id。
///
/// 模糊搜索是纯函数（可单测）：子序列匹配 + 连续命中加分 + 前缀加分，
/// 不引第三方包（低内存纪律）。
library;

import 'package:flutter/foundation.dart';

import 'context_keys.dart';

/// 一条可执行命令。
class Command {
  const Command({
    required this.id,
    required this.title,
    required this.category,
    required this.run,
    this.shortcut,
    this.when,
    this.enablement,
    this.runWithArguments,
  });

  /// 全局唯一 id，形如 'file.save'。
  final String id;

  /// 展示名（不含分类），如 '保存'。
  final String title;

  /// 分类名，如 '文件'。
  final String category;

  /// 键位提示（仅展示，如 'Ctrl+S'）。
  final String? shortcut;

  /// Visibility condition; a false condition removes the command from UI lists.
  final String? when;

  /// Enablement condition; a false condition keeps the command visible but
  /// prevents invocation.
  final String? enablement;

  final Future<void> Function() run;
  final Future<void> Function(Object? arguments)? runWithArguments;

  Future<void> invoke(Object? arguments) =>
      runWithArguments?.call(arguments) ?? run();

  /// 面板里的完整展示名（对标 VS Code '分类: 名称'）。
  String get label => '$category: $title';
}

class CommandRegistry {
  final Map<String, Command> _commands = {};

  /// 注册；同 id 覆盖（页面在动作重建时重复注册是合法用法）。
  void register(Command command) => _commands[command.id] = command;

  void unregister(String id) => _commands.remove(id);

  Command? byId(String id) => _commands[id];

  List<Command> get all => _commands.values.toList();

  /// 模糊搜索：返回按相关度排序的命令（不匹配的剔除）。
  List<Command> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return all;
    final scored = <(Command, int)>[];
    for (final c in _commands.values) {
      final s = fuzzyScore(q, c.label);
      if (s != null) scored.add((c, s));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return a.$1.label.compareTo(b.$1.label);
    });
    return scored.map((e) => e.$1).toList();
  }
}

enum CommandExecutionStatus {
  executed,
  unknown,
  hidden,
  disabled,
  unsupportedArguments,
}

/// Shared command registration, context evaluation, and dispatch service.
/// Menus, the command palette, and keybindings all invoke commands by id here.
class CommandService extends ChangeNotifier {
  CommandService({CommandRegistry? registry, ContextKeyService? context})
      : registry = registry ?? CommandRegistry(),
        context = context ?? ContextKeyService() {
    this.context.addListener(_onContextChanged);
  }

  final CommandRegistry registry;
  final ContextKeyService context;

  void register(Command command) {
    registry.register(command);
    notifyListeners();
  }

  void unregister(String id) {
    registry.unregister(id);
    notifyListeners();
  }

  Command? byId(String id) => registry.byId(id);

  List<Command> get all => registry.all;

  List<Command> search(String query) => registry.search(query);

  bool isVisible(String id) {
    final command = registry.byId(id);
    return command != null && context.matches(command.when);
  }

  bool isEnabled(String id) {
    final command = registry.byId(id);
    return command != null &&
        context.matches(command.when) &&
        context.matches(command.enablement);
  }

  List<Command> get visibleCommands =>
      registry.all.where((command) => context.matches(command.when)).toList();

  Future<CommandExecutionStatus> execute(
    String id, {
    Object? arguments,
  }) async {
    final command = registry.byId(id);
    if (command == null) return CommandExecutionStatus.unknown;
    if (!context.matches(command.when)) return CommandExecutionStatus.hidden;
    if (!context.matches(command.enablement)) {
      return CommandExecutionStatus.disabled;
    }
    if (arguments != null && command.runWithArguments == null) {
      return CommandExecutionStatus.unsupportedArguments;
    }
    await command.invoke(arguments);
    return CommandExecutionStatus.executed;
  }

  void _onContextChanged() => notifyListeners();

  @override
  void dispose() {
    context
      ..removeListener(_onContextChanged)
      ..dispose();
    super.dispose();
  }
}

/// 模糊打分：[query] 是 [target] 的子序列时返回分数（越大越相关），否则 null。
///
/// 规则：每命中一个字符 +1；连续命中额外 +2；首字符即命中（前缀倾向）+3；
/// 大小写不敏感。
int? fuzzyScore(String query, String target) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  var score = 0;
  var ti = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final hit = t.indexOf(q[qi], ti);
    if (hit < 0) return null;
    score += 1;
    if (hit == ti && qi > 0) {
      score += 2; // 连续命中
    } else if (hit == 0 || hit == _afterSeparator(t, hit)) {
      score += 3; // 前缀或词首
    }
    ti = hit + 1;
  }
  return score;
}

/// 命中位置是否紧跟分隔符（词首）。
int _afterSeparator(String t, int index) {
  if (index == 0) return 0;
  final prev = t[index - 1];
  return (prev == ' ' || prev == ':' || prev == '.' || prev == '-')
      ? index
      : -1;
}
