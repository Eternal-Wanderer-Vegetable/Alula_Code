import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One window's physical Hold trigger, including a pending native check.
class LockedScrollHoldInput {
  LockedScrollHoldInput(this.onChanged);

  final ValueChanged<bool> onChanged;
  KeyDownEvent? _trigger;
  bool _held = false;

  PhysicalKeyboardKey? get triggerKey => _trigger?.physicalKey;

  static const _channel = MethodChannel('alula/hold_input');

  void begin(KeyDownEvent event) {
    if (event.synthesized || _trigger != null) return;
    _trigger = event;
    HardwareKeyboard.instance.addHandler(_observeKey);
    final scanCode = _scanCode(event.physicalKey);
    if (scanCode == null) {
      _activate();
    } else {
      unawaited(_verifyPress(event, scanCode));
    }
  }

  void cancel({bool notify = true}) {
    if (_trigger == null) return;
    _trigger = null;
    HardwareKeyboard.instance.removeHandler(_observeKey);
    final held = _held;
    _held = false;
    if (held && notify) onChanged(false);
  }

  bool _observeKey(KeyEvent event) {
    if (event is KeyUpEvent) cancel();
    return false;
  }

  void _activate() {
    _held = true;
    onChanged(true);
  }

  Future<void> _verifyPress(KeyDownEvent event, int scanCode) async {
    bool fresh;
    try {
      fresh = await _channel.invokeMethod<bool>(
            'isFreshHoldPress',
            [scanCode, event.timeStamp.inMicroseconds],
          ) ??
          true;
    } on MissingPluginException {
      fresh = true;
    } on PlatformException {
      fresh = false;
    }
    if (!identical(_trigger, event)) return;
    if (!fresh ||
        !HardwareKeyboard.instance.isPhysicalKeyPressed(event.physicalKey)) {
      cancel();
      return;
    }
    _activate();
  }

  int? _scanCode(PhysicalKeyboardKey key) {
    final (map, plane) = switch (defaultTargetPlatform) {
      TargetPlatform.linux => (
          kLinuxToPhysicalKey,
          LogicalKeyboardKey.gtkPlane
        ),
      TargetPlatform.windows => (
          kWindowsToPhysicalKey,
          LogicalKeyboardKey.windowsPlane
        ),
      _ => (const <int, PhysicalKeyboardKey>{}, 0),
    };
    for (final entry in map.entries) {
      if (entry.value == key) return entry.key;
    }
    return plane != 0 && key.usbHidUsage & LogicalKeyboardKey.planeMask == plane
        ? key.usbHidUsage & LogicalKeyboardKey.valueMask
        : null;
  }
}
