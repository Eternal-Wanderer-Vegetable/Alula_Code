import 'package:alula_app/workbench/window_chrome_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowChromeConfiguration', () {
    test('uses a 35 logical pixel custom title bar', () {
      final config =
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux);

      expect(config.mode, WorkbenchTitleBarMode.custom);
      expect(config.titleBarHeight, 35);
      expect(config.usesCustomWindowControls, isTrue);
    });

    test('uses native controls by default on Windows and macOS', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        final config = WindowChromeConfiguration.forPlatform(platform);

        expect(config.mode, WorkbenchTitleBarMode.custom);
        expect(config.titleBarHeight, 35);
        expect(config.usesCustomWindowControls, isFalse);
      }
    });

    test('native title bar reserves no custom workbench row', () {
      final config = WindowChromeConfiguration.fromArguments(
        const [WindowChromeConfiguration.nativeTitleBarArgument],
        targetPlatform: TargetPlatform.linux,
      );

      expect(config.mode, WorkbenchTitleBarMode.native);
      expect(config.titleBarHeight, 0);
      expect(config.usesCustomWindowControls, isFalse);
    });

    test('custom title bar argument overrides native argument', () {
      final config = WindowChromeConfiguration.fromArguments(
        const [
          WindowChromeConfiguration.nativeTitleBarArgument,
          WindowChromeConfiguration.customTitleBarArgument,
        ],
        targetPlatform: TargetPlatform.windows,
      );

      expect(config.mode, WorkbenchTitleBarMode.custom);
    });
  });
}
