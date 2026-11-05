import 'package:flutter/widgets.dart';

/// Whether the workbench draws its own title bar or keeps the OS title bar.
enum WorkbenchTitleBarMode { custom, native }

/// Window chrome resolved for the current app launch and target platform.
///
/// The default is VS Code's custom title bar. The native mode is selected at
/// launch because desktop window decorations cannot be swapped safely after
/// the first frame on every supported platform.
@immutable
class WindowChromeConfiguration {
  const WindowChromeConfiguration({
    required this.mode,
    required this.targetPlatform,
  });

  static const String nativeTitleBarArgument = '--native-titlebar';
  static const String customTitleBarArgument = '--custom-titlebar';
  static const double customTitleBarHeight = 35;

  final WorkbenchTitleBarMode mode;
  final TargetPlatform targetPlatform;

  factory WindowChromeConfiguration.forPlatform(TargetPlatform platform) =>
      WindowChromeConfiguration(
        mode: WorkbenchTitleBarMode.custom,
        targetPlatform: platform,
      );

  factory WindowChromeConfiguration.fromArguments(
    List<String> arguments, {
    required TargetPlatform targetPlatform,
  }) {
    final native = arguments.contains(nativeTitleBarArgument) &&
        !arguments.contains(customTitleBarArgument);
    return WindowChromeConfiguration(
      mode:
          native ? WorkbenchTitleBarMode.native : WorkbenchTitleBarMode.custom,
      targetPlatform: targetPlatform,
    );
  }

  bool get isCustom => mode == WorkbenchTitleBarMode.custom;

  double get titleBarHeight => isCustom ? customTitleBarHeight : 0;

  /// Linux removes server decorations when the title bar is hidden, so it
  /// needs workbench controls. Windows keeps native caption controls and
  /// macOS keeps its traffic lights.
  bool get usesCustomWindowControls =>
      isCustom && targetPlatform == TargetPlatform.linux;
}

/// Makes launch-time window chrome available to the workbench title bar.
class WindowChromeConfigurationScope extends InheritedWidget {
  const WindowChromeConfigurationScope({
    super.key,
    required this.configuration,
    required super.child,
  });

  final WindowChromeConfiguration configuration;

  static WindowChromeConfiguration? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WindowChromeConfigurationScope>()
      ?.configuration;

  @override
  bool updateShouldNotify(WindowChromeConfigurationScope oldWidget) =>
      configuration != oldWidget.configuration;
}
