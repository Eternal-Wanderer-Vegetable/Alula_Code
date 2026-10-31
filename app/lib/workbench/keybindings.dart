/// 键位注册（docs/09 W3-2）：默认键位表 + 用户 keybindings.json 覆盖。
///
/// 用户文件（`~/.alula/keybindings.json`，数组）：
/// ```json
/// [
///   {"key": "ctrl+alt+f", "command": "view.quickOpen"},
///   {"key": "ctrl+p", "command": "-view.quickOpen"}
/// ]
/// ```
/// Entries may also provide `args` and a context-expression `when` condition.
/// - `command` 以 `-` 开头表示移除该命令的这条默认键位；
/// - 其余为追加；同一键位串后写者胜。
///
/// 本文件不含 widget：解析与合成均为纯函数（可单测）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// 解析后的键位：主键 + 修饰键。
class KeyChord {
  const KeyChord({
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  SingleActivator toActivator() =>
      SingleActivator(key,
          control: control, shift: shift, alt: alt, meta: meta);

  /// 展示串（'Ctrl+Shift+P' 风格）。
  String get display {
    final parts = <String>[
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
      _displayKey(key),
    ];
    return parts.join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);
}

/// A keybinding target with optional command arguments and a context condition.
class KeybindingBinding {
  const KeybindingBinding({
    required this.commandId,
    this.arguments,
    this.when,
  });

  final String commandId;
  final Object? arguments;
  final String? when;
}

String _displayKey(LogicalKeyboardKey key) {
  final name = key.keyLabel;
  if (name.length == 1) return name.toUpperCase();
  return name;
}

/// 键位名 → LogicalKeyboardKey（覆盖本项目用到的键）。
final Map<String, LogicalKeyboardKey> _keyNames = () {
  final m = <String, LogicalKeyboardKey>{};
  const letters = [
    LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.keyM, LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyT, LogicalKeyboardKey.keyU,
    LogicalKeyboardKey.keyV, LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyY, LogicalKeyboardKey.keyZ,
  ];
  for (var i = 0; i < letters.length; i++) {
    m[String.fromCharCode(97 + i)] = letters[i]; // 'a'..'z'
  }
  const digits = [
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  ];
  for (var i = 0; i < digits.length; i++) {
    m['$i'] = digits[i];
  }
  const fn = [
    LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
  ];
  for (var i = 0; i < fn.length; i++) {
    m['f${i + 1}'] = fn[i];
  }
  m['space'] = LogicalKeyboardKey.space;
  m['enter'] = LogicalKeyboardKey.enter;
  m['tab'] = LogicalKeyboardKey.tab;
  m['home'] = LogicalKeyboardKey.home;
  m['end'] = LogicalKeyboardKey.end;
  m['arrowup'] = LogicalKeyboardKey.arrowUp;
  m['arrowdown'] = LogicalKeyboardKey.arrowDown;
  m['arrowleft'] = LogicalKeyboardKey.arrowLeft;
  m['arrowright'] = LogicalKeyboardKey.arrowRight;
  m['-'] = LogicalKeyboardKey.minus;
  m['minus'] = LogicalKeyboardKey.minus;
  m['escape'] = LogicalKeyboardKey.escape;
  return m;
}();

/// 解析 'ctrl+shift+p' 风格键位串；无法识别返回 null。
KeyChord? parseChord(String spec) {
  final parts = spec.toLowerCase().split('+').map((e) => e.trim()).toList();
  if (parts.isEmpty || parts.any((e) => e.isEmpty)) return null;
  final keyName = parts.removeLast();
  final key = _keyNames[keyName];
  if (key == null) return null;
  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  for (final p in parts) {
    switch (p) {
      case 'ctrl':
      case 'control':
        control = true;
      case 'shift':
        shift = true;
      case 'alt':
        alt = true;
      case 'cmd':
        meta = true;
      default:
        return null; // 未知修饰键：整条作废（宁可不下发也不误触发）
    }
  }
  return KeyChord(
      key: key, control: control, shift: shift, alt: alt, meta: meta);
}

/// 键位集合：默认表 + 用户覆盖 → 可直接喂给 CallbackShortcuts 的映射。
class KeybindingSet {
  KeybindingSet._(this._chordToCommand);

  /// 默认键位表（命令 id → 键位串，逗号分隔可给一条命令多个键位）。
  static const Map<String, String> defaults = {
    'view.commandPalette': 'ctrl+shift+p',
    'view.quickOpen': 'ctrl+p',
    'view.search': 'ctrl+shift+f',
    'view.toggleSidebar': 'ctrl+b',
    'view.togglePanel': 'ctrl+j',
    'file.save': 'ctrl+s',
    'file.saveAs': 'ctrl+shift+s',
    'editor.completion': 'ctrl+space,f8',
    // 撤销/重做/查找的键位同时硬编码在编辑器 FocusNode 拦截器里
    // （要在焦点链第一站抢占原生 UndoHistory），此处供菜单/面板展示。
    'editor.undo': 'ctrl+z',
    'editor.redo': 'ctrl+shift+z,ctrl+y',
    'editor.find': 'ctrl+f',
    'editor.gotoDef': 'f12',
    'workbench.action.navigateBack': 'alt+arrowleft',
    'workbench.action.navigateForward': 'alt+arrowright',
    'editor.replace': 'ctrl+h',
    'editor.addCursorAbove': 'ctrl+alt+arrowup',
    'editor.addCursorBelow': 'ctrl+alt+arrowdown',
    'editor.selectNextOccurrence': 'ctrl+d',
    'editor.skipNextOccurrence': 'ctrl+shift+d',
    'editor.selectAllOccurrences': 'ctrl+shift+l',
    'editor.columnSelectUp': 'alt+shift+arrowup',
    'editor.columnSelectDown': 'alt+shift+arrowdown',
    'editor.columnSelectLeft': 'alt+shift+arrowleft',
    'editor.columnSelectRight': 'alt+shift+arrowright',
    'editor.cursorUndo': 'ctrl+u',
    'editor.cursorRedo': 'ctrl+shift+u',
    'editor.cursorHome': 'home',
    'editor.cursorHomeSelect': 'shift+home',
    'editor.cursorEnd': 'end',
    'editor.cursorEndSelect': 'shift+end',
    'editor.cursorTop': 'ctrl+home',
    'editor.cursorTopSelect': 'ctrl+shift+home',
    'editor.cursorBottom': 'ctrl+end',
    'editor.cursorBottomSelect': 'ctrl+shift+end',
    'view.panelDiagnostics': 'f1',
    'view.panelCompletions': 'f2',
    'view.panelSyntax': 'f3',
  };

  /// Platform defaults from the pinned Code-OSS editor/workbench keybindings.
  /// The word-left/right bindings use Alt on macOS, so history navigation must
  /// move to the platform-specific minus chords there.
  static Map<String, String> defaultsFor(TargetPlatform platform) {
    final result = Map<String, String>.of(defaults);
    switch (platform) {
      case TargetPlatform.macOS:
        result['workbench.action.navigateBack'] = 'ctrl+-';
        result['workbench.action.navigateForward'] = 'ctrl+shift+-';
        result['editor.wordPartLeft'] = 'ctrl+alt+arrowleft';
        result['editor.wordPartLeftSelect'] = 'ctrl+alt+shift+arrowleft';
        result['editor.wordPartRight'] = 'ctrl+alt+arrowright';
        result['editor.wordPartRightSelect'] = 'ctrl+alt+shift+arrowright';
        result['editor.cursorHome'] = 'home,cmd+arrowleft,ctrl+a';
        result['editor.cursorHomeSelect'] =
            'shift+home,shift+cmd+arrowleft,ctrl+shift+a';
        result['editor.cursorEnd'] = 'end,cmd+arrowright,ctrl+e';
        result['editor.cursorEndSelect'] =
            'shift+end,shift+cmd+arrowright,ctrl+shift+e';
        result['editor.cursorTop'] = 'cmd+arrowup';
        result['editor.cursorTopSelect'] = 'shift+cmd+arrowup';
        result['editor.cursorBottom'] = 'cmd+arrowdown';
        result['editor.cursorBottomSelect'] = 'shift+cmd+arrowdown';
        result.remove('editor.columnSelectUp');
        result.remove('editor.columnSelectDown');
        result.remove('editor.columnSelectLeft');
        result.remove('editor.columnSelectRight');
        break;
      case TargetPlatform.linux:
        result['workbench.action.navigateBack'] = 'ctrl+alt+-';
        result['workbench.action.navigateForward'] = 'ctrl+shift+-';
        break;
      default:
        break;
    }
    return result;
  }

  /// 从默认表出发应用用户覆盖（`-command` 移除；同键位串后写者胜）。
  /// [userJson] 为 keybindings.json 的原始文本；损坏或非法条目逐条忽略。
  factory KeybindingSet.load({
    String? userJson,
    TargetPlatform? platform,
  }) {
    final map = <KeyChord, KeybindingBinding>{};
    for (final e in defaultsFor(platform ?? defaultTargetPlatform).entries) {
      for (final spec in e.value.split(',')) {
        final chord = parseChord(spec.trim());
        if (chord != null) {
          map[chord] = KeybindingBinding(commandId: e.key);
        }
      }
    }
    _applyUserJson(map, userJson);
    return KeybindingSet._(map);
  }

  static void _applyUserJson(
      Map<KeyChord, KeybindingBinding> map, String? userJson) {
    if (userJson == null) return;
    Object? decoded;
    try {
      decoded = jsonDecode(userJson);
    } catch (_) {
      return; // 损坏文件：只用默认键位
    }
    if (decoded is! List) return;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final keySpec = entry['key'];
      final command = entry['command'];
      if (keySpec is! String || command is! String) continue;
      final chord = parseChord(keySpec);
      if (chord == null) continue;
      if (command.startsWith('-')) {
        // 移除：键位与命令都匹配才算
        if (map[chord]?.commandId == command.substring(1)) {
          map.remove(chord);
        }
      } else {
        // 重绑定语义：同命令旧键位全部让位（含默认），用户键位成为唯一展示
        map.removeWhere((_, binding) => binding.commandId == command);
        final condition = entry['when'];
        map[chord] = KeybindingBinding(
          commandId: command,
          arguments: entry['args'],
          when: condition is String ? condition : null,
        );
      }
    }
  }

  final Map<KeyChord, KeybindingBinding> _chordToCommand;

  /// 键位 → 命令 id（供 CallbackShortcuts 合成）。
  Map<SingleActivator, String> resolve() => {
        for (final e in _chordToCommand.entries)
          e.key.toActivator(): e.value.commandId,
      };

  /// Full keybinding records for context-aware dispatch.
  Map<SingleActivator, KeybindingBinding> resolveBindings({
    bool Function(String? condition)? matchesWhen,
  }) =>
      {
        for (final e in _chordToCommand.entries)
          if (matchesWhen == null || matchesWhen(e.value.when))
            e.key.toActivator(): e.value,
      };

  /// 键位 → 命令 id（值查询用 KeyChord：它有正确的相等性；
  /// SingleActivator 没有重写 ==，不能当查询键用）。
  String? commandForChord(KeyChord chord) => _chordToCommand[chord]?.commandId;

  KeybindingBinding? bindingForChord(KeyChord chord) => _chordToCommand[chord];

  /// 命令 id → 展示键位串（菜单提示用，如 'Ctrl+Shift+P'）。
  /// 重绑定语义下同命令只剩用户键位，首匹配即正确展示。
  String? shortcutFor(String commandId) {
    for (final e in _chordToCommand.entries) {
      if (e.value.commandId == commandId) return e.key.display;
    }
    return null;
  }
}


/// keybindings.json 存取（原始文本；注入路径供测试隔离）。
/// V1 只读：键位编辑直接改文件，UI 不提供编辑器。
class KeybindingsStore {
  KeybindingsStore({String? path}) : _overridePath = path;

  final String? _overridePath;

  String resolvePath() {
    if (_overridePath != null) return _overridePath;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.alula/keybindings.json';
  }

  String? tryLoadText() {
    try {
      final file = File(resolvePath());
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }
}
