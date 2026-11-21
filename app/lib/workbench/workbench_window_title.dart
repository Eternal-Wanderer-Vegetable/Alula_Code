import 'package:flutter/foundation.dart' show TargetPlatform;

/// Builds the currently supported portion of VS Code's default window title.
/// User supplied title templates and profile names are wired with P07.
class WorkbenchWindowTitle {
  const WorkbenchWindowTitle._();

  static String compose({
    required TargetPlatform platform,
    required String? activeEditorName,
    required bool dirty,
    required String? workspaceName,
    String profileName = '',
    String appName = 'Alula Code',
  }) {
    final separator = platform == TargetPlatform.macOS ? ' — ' : ' - ';
    final parts = <String>[];
    final editorName = activeEditorName?.trim();
    if (editorName != null && editorName.isNotEmpty) {
      parts.add('${dirty ? '● ' : ''}$editorName');
    }
    final workspace = workspaceName?.trim();
    if (workspace != null && workspace.isNotEmpty) parts.add(workspace);
    final profile = profileName.trim();
    if (profile.isNotEmpty) parts.add(profile);
    final application = appName.trim();
    if (application.isNotEmpty) parts.add(application);
    return parts.join(separator);
  }
}
