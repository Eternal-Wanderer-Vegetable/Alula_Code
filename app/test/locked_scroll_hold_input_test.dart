import 'dart:async';

import 'package:alula_app/workbench/locked_scroll_hold_input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('alula/hold_input');

  Future<LockedScrollHoldInput> mountHold(
    WidgetTester tester,
    List<bool> changes,
    Future<bool?> Function(MethodCall) verify,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, verify);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final input = LockedScrollHoldInput(changes.add);
    addTearDown(input.cancel);
    await tester.pumpWidget(
      Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.f8) {
            return KeyEventResult.ignored;
          }
          input.begin(event);
          return KeyEventResult.handled;
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    return input;
  }

  testWidgets('receiving an OS repeat cannot start a new Hold', (tester) async {
    final changes = <bool>[];
    var fresh = false;
    final input = await mountHold(tester, changes, (call) async {
      expect(call.method, 'isFreshHoldPress');
      expect(
        (call.arguments as List<dynamic>).first,
        defaultTargetPlatform == TargetPlatform.linux ? 74 : 0x42,
      );
      return fresh;
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(changes, isEmpty);
    expect(input.triggerKey, isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    expect(changes, isEmpty);

    fresh = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(changes, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    expect(changes, [true, false]);
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.linux, TargetPlatform.windows}));

  testWidgets('release and blur invalidate outstanding native replies',
      (tester) async {
    final changes = <bool>[];
    final responses = [Completer<bool>(), Completer<bool>(), Completer<bool>()];
    var nextResponse = 0;
    final input = await mountHold(tester, changes, (_) {
      return responses[nextResponse++].future;
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    responses[0].complete(true);
    await tester.pump();
    expect(changes, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    input.cancel();
    responses[1].complete(true);
    await tester.pump();
    expect(changes, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    responses[2].complete(true);
    await tester.pump();
    expect(changes, [true]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f9);
    expect(changes, [true, false]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    expect(changes, [true, false]);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}
