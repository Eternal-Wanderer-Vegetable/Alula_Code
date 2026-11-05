import 'package:alula_app/editor/indentation.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Code-OSS default indentation', () {
    test('Tab inserts to the next four-column stop', () {
      expect(indentationTabText(''), '    ');
      expect(indentationTabText('ab'), '  ');
      expect(indentationTabText('\t'), '    ');
      expect(indentationTabText('a😀'), ' ');
      expect(indentationTabText('a👩‍💻'), ' ');
      expect(indentationVisibleColumn('é'), 1);
      expect(indentationVisibleColumn('汉'), 2);
    });

    test('line indent rounds existing whitespace to the next stop', () {
      expect(shiftLineIndentation('x', outdent: false), '    ');
      expect(shiftLineIndentation('  x', outdent: false), '    ');
      expect(shiftLineIndentation('    x', outdent: false), '        ');
      expect(shiftLineIndentation('\tx', outdent: false), '        ');
    });

    test('line outdent removes one indentation stop and leaves plain lines',
        () {
      expect(shiftLineIndentation('  x', outdent: true), '');
      expect(shiftLineIndentation('    x', outdent: true), '');
      expect(shiftLineIndentation('      x', outdent: true), '    ');
      expect(shiftLineIndentation('x', outdent: true), isNull);
    });

    test('insert-tabs mode uses tab characters and display tab stops', () {
      expect(
        indentationTabText('a', insertSpaces: false),
        '\t',
      );
      expect(
        shiftLineIndentation('    x', outdent: false, insertSpaces: false),
        '\t\t',
      );
      expect(
        shiftLineIndentation('\t\tx', outdent: true, insertSpaces: false),
        '\t',
      );
    });

    test('line command chords follow Ctrl on Windows/Linux and Cmd on macOS',
        () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final keys = KeybindingSet.load(platform: platform);
        expect(
          keys.commandForChord(parseChord('ctrl+bracketright')!),
          'editor.action.indentLines',
        );
        expect(
          keys.commandForChord(parseChord('ctrl+bracketleft')!),
          'editor.action.outdentLines',
        );
      }
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        mac.commandForChord(parseChord('cmd+bracketright')!),
        'editor.action.indentLines',
      );
      expect(
        mac.commandForChord(parseChord('cmd+bracketleft')!),
        'editor.action.outdentLines',
      );
      expect(parseChord('ctrl+bracketright')!.key,
          LogicalKeyboardKey.bracketRight);
    });
  });
}
