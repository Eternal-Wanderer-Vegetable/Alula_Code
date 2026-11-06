import 'package:window_manager/window_manager.dart';

/// The desktop window operations needed by the title bar.
///
/// Keeping this boundary injectable lets widget tests exercise control and
/// close behavior without sending input to the user's desktop.
abstract class WindowChromeDriver {
  void addListener(WindowListener listener);

  void removeListener(WindowListener listener);

  Future<bool> isMaximized();

  Future<void> minimize();

  Future<void> maximize();

  Future<void> unmaximize();

  Future<void> startDragging();

  Future<void> close();

  Future<void> setPreventClose(bool preventClose);

  Future<void> setTitle(String title);
}

class PluginWindowChromeDriver implements WindowChromeDriver {
  const PluginWindowChromeDriver();

  @override
  void addListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> setPreventClose(bool preventClose) =>
      windowManager.setPreventClose(preventClose);

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);
}
