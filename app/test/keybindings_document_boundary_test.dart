import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and Linux use Ctrl+Home/End for document boundaries', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      final bindings = KeybindingSet.load(platform: platform);
      expect(bindings.commandForChord(parseChord('ctrl+home')!),
          'editor.cursorTop');
      expect(bindings.commandForChord(parseChord('ctrl+shift+home')!),
          'editor.cursorTopSelect');
      expect(bindings.commandForChord(parseChord('ctrl+end')!),
          'editor.cursorBottom');
      expect(bindings.commandForChord(parseChord('ctrl+shift+end')!),
          'editor.cursorBottomSelect');
      expect(bindings.commandForChord(parseChord('cmd+arrowup')!), isNull);
    }
  });

  test('macOS uses Command+Up/Down with Shift selection variants', () {
    final bindings = KeybindingSet.load(platform: TargetPlatform.macOS);
    expect(bindings.commandForChord(parseChord('cmd+arrowup')!),
        'editor.cursorTop');
    expect(bindings.commandForChord(parseChord('shift+cmd+arrowup')!),
        'editor.cursorTopSelect');
    expect(bindings.commandForChord(parseChord('cmd+arrowdown')!),
        'editor.cursorBottom');
    expect(bindings.commandForChord(parseChord('shift+cmd+arrowdown')!),
        'editor.cursorBottomSelect');
    expect(bindings.commandForChord(parseChord('ctrl+home')!), isNull);

    final chord = parseChord('shift+cmd+arrowdown')!;
    expect(chord.meta, isTrue);
    expect(chord.shift, isTrue);
    expect(chord.toActivator().meta, isTrue);
  });
}
