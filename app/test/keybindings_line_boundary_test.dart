import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home/End default bindings match each desktop platform', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      final bindings = KeybindingSet.load(platform: platform);
      expect(bindings.commandForChord(parseChord('home')!), 'editor.cursorHome');
      expect(bindings.commandForChord(parseChord('shift+home')!),
          'editor.cursorHomeSelect');
      expect(bindings.commandForChord(parseChord('end')!), 'editor.cursorEnd');
      expect(bindings.commandForChord(parseChord('shift+end')!),
          'editor.cursorEndSelect');
      expect(bindings.commandForChord(parseChord('cmd+arrowleft')!), isNull);
    }
  });

  test('macOS keeps Home/End and adds Command line-boundary aliases', () {
    final bindings = KeybindingSet.load(platform: TargetPlatform.macOS);
    expect(bindings.commandForChord(parseChord('home')!), 'editor.cursorHome');
    expect(bindings.commandForChord(parseChord('shift+home')!),
        'editor.cursorHomeSelect');
    expect(bindings.commandForChord(parseChord('cmd+arrowleft')!),
        'editor.cursorHome');
    expect(bindings.commandForChord(parseChord('shift+cmd+arrowleft')!),
        'editor.cursorHomeSelect');
    expect(bindings.commandForChord(parseChord('cmd+arrowright')!),
        'editor.cursorEnd');
    expect(bindings.commandForChord(parseChord('shift+cmd+arrowright')!),
        'editor.cursorEndSelect');
    expect(bindings.commandForChord(parseChord('ctrl+a')!), 'editor.cursorHome');
    expect(bindings.commandForChord(parseChord('ctrl+shift+e')!),
        'editor.cursorEndSelect');

    final commandChord = parseChord('cmd+arrowleft')!;
    expect(commandChord.meta, isTrue);
    expect(commandChord.toActivator().meta, isTrue);
  });
}
