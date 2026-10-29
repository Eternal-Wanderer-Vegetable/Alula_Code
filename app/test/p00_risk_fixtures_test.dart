// P00.3 current-state fixtures. These deliberately record the baseline behavior;
// they do not define the desired parity result.
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/editor/rust_text_input_window.dart'
    show maxRustTextInputWindowUtf16;
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final String _fixtureRoot =
    '${Directory.current.parent.path}/tests/fixtures/rust-mini';

String _repeatAscii(int units) {
  const blockSize = 4096;
  final block = List<String>.filled(blockSize, 'x').join();
  final buffer = StringBuffer();
  final completeBlocks = units ~/ blockSize;
  for (var i = 0; i < completeBlocks; i++) {
    buffer.write(block);
  }
  final remainder = units % blockSize;
  if (remainder > 0) {
    buffer.write(List<String>.filled(remainder, 'x').join());
  }
  return buffer.toString();
}

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  late Directory temp;
  late LayoutStore layout;
  late SessionStore session;
  late KeybindingsStore keybindings;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_p00_risk_');
    final base = temp.path.replaceAll(r'\', '/');
    layout = LayoutStore(path: '$base/layout.json');
    session = SessionStore(path: '$base/session.json');
    keybindings = KeybindingsStore(path: '$base/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  String editorText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  Future<void> startWorkbench(WidgetTester tester, String root) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: root,
      layoutStore: layout,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> waitWallClock(WidgetTester tester, Duration duration) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(duration);
    });
  }

  testWidgets('P02.1 REF-07-UNDO-01 keeps undo/redo histories per document',
      (tester) async {
    await startWorkbench(tester, _fixtureRoot);

    await tester.tap(find.text('Cargo.toml').first);
    await tester.pump(const Duration(milliseconds: 200));
    final aBefore = editorText(tester);
    await tester.enterText(find.byType(TextField).first, '$aBefore\n# A-edit');
    await tester.pump(const Duration(milliseconds: 500));
    // Undo coalescing uses DateTime.now(), which does not advance with test pump time.
    await waitWallClock(tester, const Duration(milliseconds: 450));

    await tester.tap(find.text('src').first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 200));
    final bBefore = editorText(tester);
    // File activation may update the shared edit timestamp. Let its coalescing
    // window expire so this fixture records two independent document edits.
    await waitWallClock(tester, const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField).first, '$bBefore\n// B-edit');
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(TextField).first);
    await _pressChord(tester, LogicalKeyboardKey.keyZ, control: true);
    final aAfterUndo = editorText(tester);
    await _pressChord(tester, LogicalKeyboardKey.keyY, control: true);
    final aAfterRedo = editorText(tester);

    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(TextField).first);
    await _pressChord(tester, LogicalKeyboardKey.keyZ, control: true);
    final bAfterUndo = editorText(tester);
    await _pressChord(tester, LogicalKeyboardKey.keyY, control: true);
    final bAfterRedo = editorText(tester);

    final observed = {
      'fixture': 'p02.1-ref-07-undo-01',
      'aBeforeLength': aBefore.length,
      'bBeforeLength': bBefore.length,
      'aUndoRestoredOwnText': aAfterUndo == aBefore,
      'aRedoRestoredOwnEdit': aAfterRedo == '$aBefore\n# A-edit',
      'bUndoRestoredOwnText': bAfterUndo == bBefore,
      'bRedoRestoredOwnEdit': bAfterRedo == '$bBefore\n// B-edit',
    };
    expect(aAfterUndo, aBefore);
    expect(aAfterRedo, '$aBefore\n# A-edit');
    expect(bAfterUndo, bBefore);
    expect(bAfterRedo, '$bBefore\n// B-edit');
    // ignore: avoid_print
    print('P02.1_FIXTURE=${jsonEncode(observed)}');
  });

  testWidgets('P00.3 REF-07-RECOVERY-01 unsaved text above 2M UTF-16 units',
      (tester) async {
    final root = Directory('${temp.path}/workspace')..createSync();
    final diskFile = File('${root.path}/large.txt')
      ..writeAsStringSync('seed\n');
    await startWorkbench(tester, root.path);
    await tester.tap(find.text('large.txt').first);
    await tester.pump(const Duration(milliseconds: 200));

    final acceptedText = _repeatAscii(2000001);
    await tester.enterText(find.byType(TextField).first, acceptedText);
    await tester.pump(const Duration(milliseconds: 800));

    final stored = session.tryLoad()!;
    final docs = (stored['groups'] as List)
        .expand((group) => (group as Map)['docs'] as List)
        .cast<Map>();
    final journalDoc = docs.firstWhere(
      (doc) => (doc['path'] as String?)?.endsWith('large.txt') ?? false,
    );
    final journalTextPresent = journalDoc.containsKey('text');

    await tester.pumpWidget(const SizedBox.shrink());
    await startWorkbench(tester, root.path);
    final recoveredWindow = editorText(tester);
    final recoveredSession = session.tryLoad()!;
    final recoveredDocs = (recoveredSession['groups'] as List)
        .expand((group) => (group as Map)['docs'] as List)
        .cast<Map>();
    final recoveredJournalDoc = recoveredDocs.firstWhere(
      (doc) => (doc['path'] as String?)?.endsWith('large.txt') ?? false,
    );
    final recoveredJournalText = recoveredJournalDoc['text'] as String?;
    await _pressChord(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('external-conflict-dialog')), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('external-conflict-confirm-overwrite')));
    await tester.pumpAndSettle();
    final savedText = diskFile.readAsStringSync();
    final observed = {
      'fixture': 'parity-ref-07-recovery-01',
      'acceptedUtf16Units': acceptedText.length,
      'journalTextPresent': journalTextPresent,
      'recoveredJournalUtf16Units': recoveredJournalText?.length,
      'diskUtf16Units': diskFile.readAsStringSync().length,
      'boundedInputWindowUtf16Units': recoveredWindow.length,
      'recoveredFromJournal': recoveredJournalText == acceptedText,
      'savedRecoveredRustText': savedText == acceptedText,
    };
    // The journal and Rust buffer preserve the complete edit while Flutter
    // exposes only the bounded window after restart.
    expect(acceptedText.length, greaterThan(2000000));
    expect(journalTextPresent, isTrue);
    expect(recoveredJournalText, acceptedText);
    expect(
        recoveredWindow.length, lessThanOrEqualTo(maxRustTextInputWindowUtf16));
    expect(savedText, acceptedText);
    // ignore: avoid_print
    print('P00.3_FIXTURE=${jsonEncode(observed)}');
  });
}
