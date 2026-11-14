/// Modal 编辑器基础设施（LAY-13a）。
///
/// `workbench.editor.useModal`（off/some/all）决定配置类编辑器
/// （settings.json/keybindings.json）以模态对话框而非标签打开：
/// - some（默认）：仅配置编辑器路径自动模态；
/// - all：所有文档模态；
/// - off：全部标签。
/// 对话框含 Esc 关闭、移回标签、最大化切换与焦点陷阱。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ModalEditorUseMode { off, some, all }

extension ModalEditorUseModeJson on ModalEditorUseMode {
  String get value => name;

  static ModalEditorUseMode parse(Object? value) => switch (value) {
        'off' => ModalEditorUseMode.off,
        'all' => ModalEditorUseMode.all,
        'some' => ModalEditorUseMode.some,
        _ => ModalEditorUseMode.some,
      };
}

extension ModalEditorUseModeAuto on ModalEditorUseMode {
  bool opensAutomatically(String? path) => switch (this) {
        ModalEditorUseMode.off => false,
        ModalEditorUseMode.all => true,
        ModalEditorUseMode.some => isConfigurationEditorPath(path),
      };
}

class ModalEditorPreferences {
  const ModalEditorPreferences({this.useModal = ModalEditorUseMode.some});

  final ModalEditorUseMode useModal;

  bool opensAutomatically(String? path) {
    return switch (useModal) {
      ModalEditorUseMode.off => false,
      ModalEditorUseMode.all => true,
      ModalEditorUseMode.some => isConfigurationEditorPath(path),
    };
  }

  ModalEditorPreferences withUseModal(ModalEditorUseMode mode) =>
      ModalEditorPreferences(useModal: mode);

  Map<String, Object?> toJson() => {
        'version': 1,
        'workbench.editor.useModal': useModal.value,
      };

  factory ModalEditorPreferences.fromJson(Object? value) {
    if (value is! Map) return const ModalEditorPreferences();
    return ModalEditorPreferences(
      useModal: ModalEditorUseModeJson.parse(
        value['workbench.editor.useModal'],
      ),
    );
  }
}

bool isConfigurationEditorPath(String? path) {
  if (path == null || path.isEmpty) return false;
  final name = path.replaceAll('\\', '/').split('/').last.toLowerCase();
  return name == 'settings.json' || name == 'keybindings.json';
}

class ModalEditorStore {
  ModalEditorStore({String? path}) : _overridePath = path;

  final String? _overridePath;

  String resolvePath() {
    if (_overridePath != null) return _overridePath;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.alula/modal_editor.json';
  }

  ModalEditorPreferences load() {
    try {
      final file = File(resolvePath());
      if (!file.existsSync()) return const ModalEditorPreferences();
      return ModalEditorPreferences.fromJson(
          jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return const ModalEditorPreferences();
    }
  }

  void save(ModalEditorPreferences preferences) {
    try {
      final file = File(resolvePath());
      file.parent.createSync(recursive: true);
      final temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(jsonEncode(preferences.toJson()));
      if (file.existsSync()) file.deleteSync();
      temporary.renameSync(file.path);
    } catch (_) {
      // Losing a workbench preference must not affect document state.
    }
  }
}

/// 模态编辑器对话框：标题行（移回标签/最大化/关闭）、Esc 关闭、焦点陷阱。
class ModalEditorDialog extends StatefulWidget {
  const ModalEditorDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onMoveBackToTab,
    required this.onClose,
  });

  final String title;
  final Widget child;
  final VoidCallback onMoveBackToTab;
  final VoidCallback onClose;

  @override
  State<ModalEditorDialog> createState() => ModalEditorDialogState();
}

class ModalEditorDialogState extends State<ModalEditorDialog> {
  bool _maximized = false;

  void toggleMaximized() => setState(() => _maximized = !_maximized);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = _maximized
        ? screen.width
        : math.min(1120, screen.width - 64).toDouble();
    final height = _maximized
        ? screen.height
        : math.min(820, screen.height - 64).toDouble();
    return Dialog(
      key: const ValueKey('modal-editor-dialog'),
      insetPadding: EdgeInsets.all(_maximized ? 0 : 32),
      backgroundColor: const Color(0xFF1D2027),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
            },
            child: Column(
              children: [
                Container(
                  key: const ValueKey('modal-editor-titlebar'),
                  height: 42,
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  color: const Color(0xFF252932),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('modal-editor-move-to-tab'),
                        tooltip: '移回编辑器标签',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onMoveBackToTab,
                        icon: const Icon(Icons.open_in_new, size: 16),
                      ),
                      IconButton(
                        key: const ValueKey('modal-editor-maximize'),
                        tooltip: _maximized ? '还原大小' : '最大化模态编辑器',
                        visualDensity: VisualDensity.compact,
                        onPressed: toggleMaximized,
                        icon: Icon(
                          _maximized
                              ? Icons.close_fullscreen
                              : Icons.open_in_full,
                          size: 16,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('modal-editor-close'),
                        tooltip: '关闭模态编辑器',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
