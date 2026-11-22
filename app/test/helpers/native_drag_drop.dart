import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
// Widget tests supply the native plugin response through its test override.
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

/// Registers the native drag/drop channels for workbench widget tests.
void mockNativeDragDrop() {
  final context = MockMessageChannelContext();
  for (final channel in ['DragManager', 'DropManager']) {
    context.registerMockChannelHandler(channel, (_) async => ['ok', null]);
  }
  setContextOverride(context);
  TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.irondash.engine_context'),
        (call) async => call.method == 'getEngineHandle' ? 1 : null,
      );
}
