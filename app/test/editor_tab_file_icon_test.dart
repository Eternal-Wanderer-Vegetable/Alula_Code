import 'package:alula_app/workbench/editor_tab_file_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorTabFileIconTheme theme;

  setUpAll(() async {
    theme = EditorTabFileIconTheme.fromJson(
      await rootBundle.loadString('assets/seti/vs-seti-icon-theme.json'),
    );
  });

  test('special filename associations take precedence over extensions', () {
    final icon = theme.lookup(fileName: 'Readme.MD', languageId: 'dart');

    expect(icon.definitionId, '_info');
    expect(icon.glyph, String.fromCharCode(0xe04d));
    expect(icon.color, const Color(0xff519aba));
  });

  test('Seti font license notice is included in the app asset bundle',
      () async {
    final license = await rootBundle.loadString('assets/seti/LICENSE-SETI.md');

    expect(license, contains('Copyright (c) 2014 Jesse Weed'));
    expect(license, contains('Permission is hereby granted'));
  });

  test('compound extensions use the longest matching Seti association', () {
    final icon = theme.lookup(fileName: 'app.spec.tsx');

    expect(icon.definitionId, '_react_1');
    expect(icon.glyph, String.fromCharCode(0xe07d));
  });

  test('language ID is used after filename and extension lookup', () {
    final icon = theme.lookup(fileName: 'module.unknown', languageId: 'DART');

    expect(icon.definitionId, '_dart');
    expect(icon.glyph, String.fromCharCode(0xe021));
    expect(icon.color, const Color(0xff519aba));
  });

  test('unknown, untitled, and pathless documents use the Seti file fallback',
      () {
    for (final name in ['mystery.unknown', 'Untitled-1', '']) {
      final icon = theme.lookup(fileName: name);
      expect(icon.definitionId, '_default', reason: name);
      expect(icon.glyph, String.fromCharCode(0xe023), reason: name);
    }
  });

  testWidgets(
      'icon reserves a decorative 22px slot and does not intercept input',
      (tester) async {
    const key = ValueKey('file-icon');

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EditorTabFileIcon(key: key, fileName: 'main.dart'),
      ),
    ));
    await tester.runAsync(EditorTabFileIconTheme.load);
    await tester.pump();
    final renderedIcon = tester.widget<Text>(find.byType(Text));

    expect(tester.getSize(find.byKey(key)), const Size(22, 16));
    expect(
      renderedIcon.data,
      theme.lookup(fileName: 'main.dart').glyph,
    );
    expect(renderedIcon.style?.fontFamily, 'AlulaSeti');
    final iconSlot = find.byKey(key);
    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: iconSlot,
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isTrue,
    );
    expect(
      find.descendant(of: iconSlot, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
  });
}
