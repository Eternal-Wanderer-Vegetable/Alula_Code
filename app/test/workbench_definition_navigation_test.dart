import 'dart:async';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart' show ReferencesRequest;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/explorer_preview.dart';
import 'helpers/native_drag_drop.dart';

Future<void> _openWorkspace(
  WidgetTester tester,
  Directory temp,
  Directory workspace, {
  Future<DefinitionResult?> Function(int, int, int)? definitionRequest,
  ReferencesRequest? referencesRequest,
  String openFileName = 'main.rs',
}) async {
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    definitionRequest: definitionRequest,
    referencesRequest: referencesRequest,
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text(openFileName).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(TextField).last);
  await tester.pump();
}

Finder _activeTextField() => find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );

TextEditingController _activeController(WidgetTester tester) =>
    tester.widget<TextField>(_activeTextField()).controller!;

Future<void> _closeNamedTab(WidgetTester tester, String name) async {
  final tab = find.ancestor(
    of: find.text(name).last,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is Container &&
          key is ValueKey<String> &&
          key.value.startsWith('tab-');
    }),
  );
  final close = find.descendant(
    of: tab.first,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return widget is InkWell &&
          key is ValueKey<String> &&
          key.value.startsWith('close-tab-');
    }),
  );
  await tester.tap(close);
  await tester.pump(const Duration(milliseconds: 100));
}

FocusNode _peekPreviewFocus(WidgetTester tester) => tester
    .widget<SelectionArea>(
      find.byKey(const ValueKey('definition-peek-preview-focus')),
    )
    .focusNode!;

Future<void> _pressPeekFocusChord(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pumpAndSettle();
}

Future<void> _runPaletteCommand(WidgetTester tester, String query) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 200));
  final quickInput = find.byKey(const ValueKey('quick-input'));
  await tester.enterText(
    find.descendant(of: quickInput, matching: find.byType(TextField)),
    query,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(mockNativeDragDrop);

  testWidgets(
      'LSP definition opens a cross-file target and back/forward restore it',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-cross-file-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = '\uFEFF// 🦊 target\nfn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);

    await _openWorkspace(
      tester,
      temp,
      workspace,
      definitionRequest: (id, offset, version) async => DefinitionResult(
        version: version,
        uri: Uri.file(targetPath).toString(),
        line: 1,
        character: 3,
      ),
    );
    final callOffset = source.indexOf('target()');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: callOffset);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('跳转到 target.rs'), findsOneWidget);
    expect(
        _activeController(tester).text, targetText.replaceFirst('\uFEFF', ''));
    expect(
      _activeController(tester).selection.extentOffset,
      targetText.replaceFirst('\uFEFF', '').indexOf('target()'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, callOffset);

    await _closeNamedTab(tester, 'target.rs');
    expect(_activeController(tester).text, source);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        _activeController(tester).text, targetText.replaceFirst('\uFEFF', ''));
    expect(
      _activeController(tester).selection.extentOffset,
      targetText.replaceFirst('\uFEFF', '').indexOf('target()'),
    );
  });

  const navigationPlatforms = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.linux,
  });
  testWidgets(
      'multiple definition targets open a peek and confirm the selected row',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-multiple-definitions');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { let _ = "😀"; target(); }\n';
    const firstText = 'fn alpha() {}\n';
    const secondText = '\uFEFF// 🦊 selected target\r\nfn beta() {}\r\n';
    final primary = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync(firstText);
    final secondary = File('${workspace.path}/beta.rs')
      ..writeAsStringSync(secondText);
    final sourceFile = File('${workspace.path}/main.rs')
      ..writeAsStringSync(source);
    final sourceBytes = sourceFile.readAsBytesSync();
    final secondBytes = secondary.readAsBytesSync();
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async => DefinitionResult(
              version: version,
              uri: secondary.uri.toString(),
              line: 1,
              character: 3,
              endLine: 1,
              endCharacter: 7,
              alternatives: [
                DefinitionTarget(
                  uri: primary.uri.toString(),
                  line: 0,
                  character: 3,
                  endLine: 0,
                  endCharacter: 8,
                ),
              ],
            ));
    final sourceOffset = source.indexOf('target()');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    final peek = find.byKey(const ValueKey('definition-peek'));
    Future<void> openPeek() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(peek, findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('alpha.rs')),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('beta.rs')),
          findsOneWidget);
      final nearest = find.byKey(const ValueKey('peek-result:1'));
      expect(tester.widget<Semantics>(nearest).properties.selected, isTrue);
      expect(_activeController(tester).text, source);
      expect(_activeController(tester).selection.extentOffset, sourceOffset);
    }

    Future<void> selectSecondary() async {
      await tester
          .tap(find.byKey(ValueKey('references-file:${secondary.path}')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    await openPeek();
    await selectSecondary();
    final secondPreview = find.descendant(
      of: peek,
      matching: find.textContaining('fn beta()', findRichText: true),
    );
    final watch = Stopwatch()..start();
    while (secondPreview.evaluate().isEmpty &&
        watch.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 25),
          ));
      await tester.pump();
    }
    expect(secondPreview, findsOneWidget);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .focusNode!
            .hasFocus,
        isTrue);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);

    await openPeek();
    await selectSecondary();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    final normalized =
        secondText.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    expect(_activeController(tester).text, normalized);
    expect(_activeController(tester).selection.extentOffset,
        normalized.indexOf('beta()'));
    expect(sourceFile.readAsBytesSync(), sourceBytes);
    expect(secondary.readAsBytesSync(), secondBytes);

    Future<void> moveInHistory({required bool forward}) async {
      if (defaultTargetPlatform == TargetPlatform.linux) {
        final modifier =
            forward ? LogicalKeyboardKey.shiftLeft : LogicalKeyboardKey.altLeft;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(
          forward ? LogicalKeyboardKey.underscore : LogicalKeyboardKey.minus,
          physicalKey: PhysicalKeyboardKey.minus,
          // The legacy Linux test map cannot encode the shifted key value.
          platform: forward ? 'macos' : null,
          character: forward ? '_' : '-',
        );
        await tester.sendKeyUpEvent(modifier);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(
          forward
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      }
      await tester.pumpAndSettle();
    }

    FocusNode activeFocus() => tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .focusNode!;

    await moveInHistory(forward: false);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);
    expect(activeFocus().hasPrimaryFocus, isTrue,
        reason: 'back restores input focus to the source editor');

    await moveInHistory(forward: true);
    expect(_activeController(tester).text, normalized);
    expect(_activeController(tester).selection.extentOffset,
        normalized.indexOf('beta()'));
    expect(activeFocus().hasPrimaryFocus, isTrue,
        reason: 'forward restores input focus to the target editor');
  }, variant: navigationPlatforms);

  testWidgets('Definition Peek cycles through files and wraps with focus',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-definition-cycle');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { resolve(); }\n';
    const alphaText = 'fn near() {}\nfn later() {}\n';
    const betaText = 'fn other() {}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync(alphaText);
    final beta = File('${workspace.path}/beta.rs')..writeAsStringSync(betaText);
    var requests = 0;
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async {
      requests++;
      return DefinitionResult(
        version: version,
        uri: beta.uri.toString(),
        line: 0,
        character: 3,
        endCharacter: 8,
        alternatives: [
          DefinitionTarget(uri: alpha.uri.toString(), line: 1, character: 3),
          DefinitionTarget(uri: alpha.uri.toString(), line: 0, character: 3),
        ],
      );
    });
    _activeController(tester).selection =
        TextSelection.collapsed(offset: source.indexOf('resolve'));
    await tester.pump();

    final peek = find.byKey(const ValueKey('definition-peek'));
    Finder tab(String name) => find.descendant(
          of: find.byKey(const ValueKey('editor-tab-strip-editor')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.data?.startsWith(name) == true,
          ),
        );
    void expectPreview(String name) => expect(
          tester.widget<Text>(tab(name)).style?.fontStyle,
          FontStyle.italic,
        );
    Finder row(int index) => find.byKey(ValueKey('peek-result:$index'));
    Finder group(File file) =>
        find.byKey(ValueKey('references-file:${file.path}'));
    SemanticsProperties semantics(Finder node) =>
        tester.widget<Semantics>(node).properties;
    Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    void expectResult(String text, int offset, int index,
        {bool preview = false}) {
      expect(peek, findsOneWidget);
      expect(_activeController(tester).text, text);
      expect(_activeController(tester).selection.extentOffset, offset);
      expect(semantics(row(index)).selected, isTrue);
      expect(_peekPreviewFocus(tester).hasPrimaryFocus, preview);
      if (!preview) {
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'definition-peek-list');
      }
    }

    await press(LogicalKeyboardKey.f12);
    expectResult(source, source.indexOf('resolve'), 2);
    expectPreview('main.rs');
    expect(semantics(group(alpha)).label, endsWith('2 个定义'));
    expect(semantics(group(alpha)).expanded, isTrue);
    expect(semantics(group(beta)).expanded, isFalse);
    expect(
        tester.getTopLeft(row(2)).dy, lessThan(tester.getTopLeft(row(1)).dy));

    await press(LogicalKeyboardKey.f4);
    expectResult(alphaText, alphaText.indexOf('later'), 1);
    expectPreview('alpha.rs');
    expect(tab('main.rs'), findsNothing);
    await press(LogicalKeyboardKey.f12);
    expectResult(betaText, 3, 0);
    expectPreview('beta.rs');
    expect(tab('alpha.rs'), findsNothing);
    expect(semantics(group(alpha)).expanded, isTrue);
    expect(semantics(group(beta)).expanded, isTrue);
    await _pressPeekFocusChord(tester);
    await press(LogicalKeyboardKey.f4, shift: true);
    expectResult(alphaText, alphaText.indexOf('later'), 1, preview: true);
    await press(LogicalKeyboardKey.f12, shift: true);
    expectResult(alphaText, 3, 2, preview: true);
    await press(LogicalKeyboardKey.f4, shift: true);
    expectResult(betaText, 3, 0, preview: true);
    await press(LogicalKeyboardKey.f4);
    expectResult(alphaText, 3, 2, preview: true);

    await press(LogicalKeyboardKey.escape);
    expect(peek, findsNothing);
    expect(
        tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
        isTrue);
    await press(LogicalKeyboardKey.f4);
    expect(peek, findsNothing);
    expect(_activeController(tester).selection.extentOffset, 3);
    expect(requests, 1);
    await press(LogicalKeyboardKey.f12);
    expect(requests, 2);
    expectResult(alphaText, 3, 2);
    expectPreview('alpha.rs');
    expect(tab('beta.rs'), findsNothing);

    await press(LogicalKeyboardKey.escape);
    await openPinnedExplorerFile(tester, find.text('beta.rs'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(tab('beta.rs')).style?.fontStyle,
        isNot(FontStyle.italic));
    await tester.tap(_activeTextField());
    const changedBeta = '$betaText// unsaved\n';
    await tester.enterText(_activeTextField(), changedBeta);
    await tester.pumpAndSettle();
    expect(_activeController(tester).text, changedBeta);

    await tester.tap(find.text('alpha.rs').first);
    await tester.pumpAndSettle();
    await tester.tap(_activeTextField());
    _activeController(tester).selection =
        const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await press(LogicalKeyboardKey.f12);
    await press(LogicalKeyboardKey.f4);
    expectResult(alphaText, alphaText.indexOf('later'), 1);
    await press(LogicalKeyboardKey.f4);
    expectResult(changedBeta, 3, 0);
    expect(tester.widget<Text>(tab('beta.rs')).style?.fontStyle,
        isNot(FontStyle.italic));
    expectPreview('alpha.rs');
    await press(LogicalKeyboardKey.f4);
    expectResult(alphaText, 3, 2);
    expect(tab('beta.rs'), findsOneWidget);
    expect(beta.readAsStringSync(), betaText);

    await press(LogicalKeyboardKey.enter);
    expect(peek, findsNothing);
    expect(tester.widget<Text>(tab('alpha.rs')).style?.fontStyle,
        isNot(FontStyle.italic));
    expect(_activeController(tester).selection.extentOffset, 3);
    expect(
        tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
        isTrue);

    await tester.tap(find.text('main.rs').first);
    await tester.pumpAndSettle();
    expectPreview('main.rs');
    expect(tab('alpha.rs'), findsOneWidget);
    expect(tab('beta.rs'), findsOneWidget);
  });

  final sideBindings = ValueVariant<String>({
    'ctrl+enter',
    'ctrl+shift+enter',
    'ctrl+k ctrl+shift+enter',
  });

  testWidgets('Peek opens the selected result to the side and remains usable',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-peek-open-side');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final binding = sideBindings.currentValue!;
    final rebound = binding != 'ctrl+enter';
    if (rebound) {
      File('${temp.path}/keybindings.json').writeAsStringSync('''[
        {"key":"ctrl+enter","command":"-openReferenceToSide"},
        {"key":"$binding","command":"openReferenceToSide"}
      ]''');
    }
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { resolve(); }\n';
    const target = '/* 🦊 */ fn resolve() {}\n';
    final main = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    final remote = File('${workspace.path}/target.rs')
      ..writeAsStringSync('\uFEFF${target.replaceAll('\n', '\r\n')}');
    final targetOffset = target.indexOf('resolve');
    final sourceOffset = source.indexOf('resolve');
    var requests = 0;
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async {
      requests++;
      return DefinitionResult(
        version: version,
        uri: requests == 1 ? remote.uri.toString() : main.uri.toString(),
        line: 0,
        character: requests == 1 ? targetOffset : 3,
        endCharacter: requests == 1 ? targetOffset + 'resolve'.length : 7,
        alternatives: requests == 1
            ? [
                DefinitionTarget(
                    uri: main.uri.toString(), line: 0, character: 3)
              ]
            : const [],
      );
    });
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();

    final peek = find.byKey(const ValueKey('definition-peek'));
    final remoteGroup = find.byKey(ValueKey('references-file:${remote.path}'));
    final sourceGroup = find.byKey(ValueKey('references-file:${main.path}'));
    final remoteRow = find.byKey(const ValueKey('peek-result:0'));
    final sourceRow = find.byKey(const ValueKey('peek-result:1'));
    TextField editor(String label) => tester.widget<TextField>(
          find.descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is RustTextInputField && widget.semanticsLabel == label),
            matching: find.byType(TextField),
          ),
        );
    Future<void> selectResult(Finder row) async {
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'definition-peek-list');
    }

    Future<void> selectFileResult(Finder group, Finder row) async {
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      if (tester.widget<Semantics>(group).properties.expanded != true) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(row).properties.selected, isTrue);
    }

    Future<void> pressControlEnter({required bool shifted}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shifted) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      if (shifted) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> openSide() async {
      if (binding.startsWith('ctrl+k ')) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await pressControlEnter(shifted: rebound);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    expect(peek, findsOneWidget);
    await selectFileResult(remoteGroup, remoteRow);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    final expanded = tester.widget<Semantics>(remoteGroup).properties.expanded;
    await openSide();
    expect(tester.widget<Semantics>(remoteGroup).properties.expanded, expanded);
    expect(find.byType(RustTextInputField), findsOneWidget);
    expect(_activeController(tester).text, source);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(remoteRow).properties.selected, isTrue);
    if (rebound) {
      await pressControlEnter(shifted: false);
      expect(peek, findsOneWidget);
      expect(find.byType(RustTextInputField), findsOneWidget);
      expect(_activeController(tester).text, source);
    }
    await openSide();

    TextField right() => editor('target.rs 编辑器 2');
    TextField left() => editor('main.rs 主编辑器');
    expect(peek, findsOneWidget);
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    expect(right().focusNode!.hasPrimaryFocus, isTrue);
    expect(right().controller!.text, target);
    expect(right().controller!.selection.extentOffset, targetOffset);
    expect(left().controller!.selection.extentOffset, sourceOffset);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(peek, findsOneWidget);
    final jumped = editor('main.rs 编辑器 2');
    expect(jumped.controller!.selection.extentOffset, 3);
    expect(jumped.focusNode!.hasPrimaryFocus, isTrue);
    expect(left().controller!.selection.extentOffset, sourceOffset);

    await selectResult(remoteRow);
    await openSide();
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    expect(right().focusNode!.hasPrimaryFocus, isTrue);

    await selectFileResult(sourceGroup, sourceRow);
    await openSide();
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    final sideCopy = editor('main.rs 编辑器 2');
    expect(sideCopy.focusNode!.hasPrimaryFocus, isTrue);
    expect(sideCopy.controller!.selection.extentOffset, 3);
    expect(left().controller!.selection.extentOffset, sourceOffset);
    expect(peek, findsOneWidget);

    await selectResult(remoteRow);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    expect(left().focusNode!.hasPrimaryFocus, isTrue);
    expect(left().controller!.selection.extentOffset, sourceOffset);
  }, variant: sideBindings);

  testWidgets('Modified clicks open Peek results in replaceable side tabs',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-peek-pointer-side');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { resolve(); }\n';
    const alphaText = '/* 🦊 */ fn alpha() {}\n';
    const betaText = 'fn beta() {}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync('\uFEFF${alphaText.replaceAll('\n', '\r\n')}');
    final beta = File('${workspace.path}/beta.rs')..writeAsStringSync(betaText);
    var requests = 0;
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async {
      requests++;
      return DefinitionResult(
        version: version,
        uri: alpha.uri.toString(),
        line: 0,
        character: alphaText.indexOf('alpha'),
        alternatives: [
          DefinitionTarget(uri: beta.uri.toString(), line: 0, character: 3),
        ],
      );
    });
    final sourceOffset = source.indexOf('resolve');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();

    final peek = find.byKey(const ValueKey('definition-peek'));
    Finder row(int index) => find.byKey(ValueKey('peek-result:$index'));
    Finder rightTab(String name) => find.descendant(
          of: find.byKey(const ValueKey('editor-tab-strip-editor-2')),
          matching: find.text(name),
        );
    TextField editor(String label) => tester.widget<TextField>(
          find.descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is RustTextInputField && widget.semanticsLabel == label),
            matching: find.byType(TextField),
          ),
        );

    Future<void> reveal(File file, int index) async {
      final group = find.byKey(ValueKey('references-file:${file.path}'));
      await tester.ensureVisible(group);
      if (tester.widget<Semantics>(group).properties.expanded != true) {
        await tester.tap(group);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(row(index));
    }

    Future<void> clickWith(LogicalKeyboardKey modifier, int index) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.tap(row(index), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    void expectSourcePreserved() {
      final input = editor('main.rs 主编辑器').controller!;
      expect(input.text, source);
      expect(input.selection.extentOffset, sourceOffset);
      expect(peek, findsOneWidget);
      expect(requests, 1);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    await reveal(alpha, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final cancelled = await tester.startGesture(tester.getCenter(row(0)),
        kind: PointerDeviceKind.mouse);
    await cancelled.cancel();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(row(0), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(RustTextInputField), findsOneWidget);
    expectSourcePreserved();

    await clickWith(LogicalKeyboardKey.controlLeft, 0);
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    expectSourcePreserved();
    final alphaEditor = editor('alpha.rs 编辑器 2');
    expect(alphaEditor.focusNode!.hasPrimaryFocus, isTrue);
    expect(alphaEditor.controller!.text, alphaText);
    expect(alphaEditor.controller!.selection.extentOffset,
        alphaText.indexOf('alpha'));
    expect(tester.widget<Text>(rightTab('alpha.rs')).style?.fontStyle,
        FontStyle.italic);

    await reveal(beta, 1);
    await clickWith(LogicalKeyboardKey.altLeft, 1);
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    expectSourcePreserved();
    final betaEditor = editor('beta.rs 编辑器 2');
    expect(betaEditor.focusNode!.hasPrimaryFocus, isTrue);
    expect(betaEditor.controller!.text, betaText);
    expect(betaEditor.controller!.selection.extentOffset, 3);
    expect(tester.widget<Text>(rightTab('beta.rs')).style?.fontStyle,
        FontStyle.italic);
    expect(rightTab('alpha.rs'), findsNothing);

    await reveal(alpha, 0);
    await clickWith(LogicalKeyboardKey.metaLeft, 0);
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    expectSourcePreserved();
    expect(editor('alpha.rs 编辑器 2').focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.widget<Text>(rightTab('alpha.rs')).style?.fontStyle,
        FontStyle.italic);
    expect(rightTab('beta.rs'), findsNothing);
  });

  final previewOpenModes = ValueVariant<bool>({false, true});
  testWidgets(
      'Double-clicking the Peek preview opens the clicked UTF-16 position',
      (tester) async {
    final side = previewOpenModes.currentValue!;
    final temp = Directory.systemTemp.createTempSync('alula-peek-preview-open');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { resolve(); }\n';
    final prefix = ''.padLeft(435, 'x');
    final suffix = ''.padLeft(190, 'z');
    final targetText = 'fn lead() {}\n$prefix /* 🦊 */ clicked $suffix\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final target = File('${workspace.path}/target.rs')
      ..writeAsStringSync('\uFEFF${targetText.replaceAll('\n', '\r\n')}');
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async {
      return DefinitionResult(
        version: version,
        uri: target.uri.toString(),
        line: 1,
        character: 600,
        endCharacter: 601,
      );
    });
    await openPinnedExplorerFile(tester, find.text('main.rs'));
    if (side) {
      await openPinnedExplorerFile(tester, find.text('target.rs'));
      await tester.tap(find.text('main.rs').first);
      await tester.pumpAndSettle();
    }
    await tester.tap(_activeTextField());
    final sourceOffset = source.indexOf('resolve');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();

    if (defaultTargetPlatform == TargetPlatform.linux) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } else {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
    await tester.pumpAndSettle();

    final peek = find.byKey(const ValueKey('definition-peek'));
    final preview = find.byKey(const ValueKey('definition-peek-preview-focus'));
    final code = find.descendant(
      of: preview,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('clicked'),
      ),
    );
    for (var attempt = 0; attempt < 8 && code.evaluate().isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }
    expect(code, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(code);
    final glyphOffset = paragraph.text.toPlainText().indexOf('clicked') + 2;
    final glyph = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: glyphOffset, extentOffset: glyphOffset + 1),
        )
        .single;
    final point = paragraph.localToGlobal(Offset(
      glyph.left + (glyph.right - glyph.left) * .25,
      (glyph.top + glyph.bottom) / 2,
    ));
    expect(tester.getRect(preview).contains(point), isTrue);

    Future<void> clickAt(Duration timestamp) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(point, timeStamp: timestamp);
      await mouse.up(
        timeStamp: timestamp + const Duration(milliseconds: 10),
      );
    }

    await clickAt(Duration.zero);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(peek, findsOneWidget);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);

    if (side) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await clickAt(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 80));
    await clickAt(const Duration(milliseconds: 530));
    if (side) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(peek, side ? findsOneWidget : findsNothing);
    final label = side ? 'target.rs 编辑器 2' : 'target.rs 主编辑器';
    final targetFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RustTextInputField && widget.semanticsLabel == label,
    );
    final input = tester.widget<TextField>(
      find.descendant(of: targetFinder, matching: find.byType(TextField)),
    );
    expect(input.focusNode!.hasPrimaryFocus, isTrue);
    expect(input.controller!.text, targetText);
    expect(input.controller!.selection.extentOffset,
        targetText.indexOf('clicked') + 2);
    final region = side ? 'editor-2' : 'editor';
    final tab = tester.widget<Text>(find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.text('target.rs'),
    ));
    expect(tab.style?.fontStyle, FontStyle.italic);
  }, variant: previewOpenModes);

  testWidgets('default Peek Definition shortcut keeps a single target in peek',
      (tester) async {
    final platform = defaultTargetPlatform;
    const inputChannel = MethodChannel('alula/peek_input');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final inputChanges = <bool>[];
    messenger.setMockMethodCallHandler(inputChannel, (call) async {
      expect(call.method, 'setReadOnlyFocus');
      inputChanges.add(call.arguments as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(inputChannel, null));
    final expectsNativeInputControl = platform == TargetPlatform.windows;
    final temp =
        Directory.systemTemp.createTempSync('alula-explicit-definition-peek');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\nfn target() {}\n';
    final file = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    await _openWorkspace(tester, temp, workspace,
        definitionRequest: (id, offset, version) async => DefinitionResult(
              version: version,
              uri: file.uri.toString(),
              line: 1,
              character: 3,
              endLine: 1,
              endCharacter: 9,
            ));
    final sourceOffset = source.indexOf('target()');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    if (platform == TargetPlatform.linux) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } else {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
    await tester.pumpAndSettle();
    final peek = find.byKey(const ValueKey('definition-peek'));
    expect(peek, findsOneWidget);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);
    expect(
        find.descendant(
          of: peek,
          matching: find.byKey(const ValueKey('definition-peek-preview')),
        ),
        findsOneWidget);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'definition-peek-list');
    await _pressPeekFocusChord(tester);
    expect(_peekPreviewFocus(tester).hasPrimaryFocus, isTrue);
    expect(
      find.descendant(of: peek, matching: find.byType(TextField)),
      findsNothing,
    );
    await _pressPeekFocusChord(tester);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'definition-peek-list');
    expect(inputChanges, expectsNativeInputControl ? [true] : <bool>[]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    expect(inputChanges, expectsNativeInputControl ? [true, false] : <bool>[]);
    expect(_activeController(tester).selection.extentOffset,
        source.lastIndexOf('target()'));
  }, variant: navigationPlatforms);

  final providerColumns = ValueVariant({'counts BOM', 'decoded text'});
  testWidgets('Shift+F12 goes to the single usage and restores input focus',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-single-reference');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = '// 😀\nfn symbol() {}\n';
    const target = '\uFEFF/* 🦊 */ fn caller() { symbol(); }\r\n';
    final declaration = File('${workspace.path}/main.rs')
      ..writeAsStringSync(source);
    final consumer = File('${workspace.path}/consumer.rs')
      ..writeAsStringSync(target);
    final consumerBytes = consumer.readAsBytesSync();
    final reportedStart = target.indexOf('symbol') -
        (providerColumns.currentValue == 'decoded text' ? 1 : 0);
    final calls = <bool>[];
    final sourceOffset = source.indexOf('symbol');
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) async {
        expect(offset, sourceOffset);
        calls.add(includeDeclaration);
        return ReferencesResult(
          version: version,
          targets: [
            if (includeDeclaration)
              DefinitionTarget(
                uri: declaration.uri.toString(),
                line: 1,
                character: 3,
                endLine: 1,
                endCharacter: 9,
              ),
            DefinitionTarget(
              uri: consumer.uri.toString(),
              line: 0,
              character: reportedStart,
              endLine: 0,
              endCharacter: reportedStart + 'symbol'.length,
            ),
          ],
        );
      },
    );
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(calls, [true, false]);
    expect(find.byKey(const ValueKey('references-peek')), findsNothing);
    final text = target.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    expect(_activeController(tester).text, text);
    expect(_activeController(tester).selection.extentOffset,
        text.indexOf('symbol'));
    expect(
      tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    expect(consumer.readAsBytesSync(), consumerBytes);
  }, variant: providerColumns);

  testWidgets(
      'multiple usages open References Peek and Esc restores the source',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-references-peek');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn call() { target(); }\n';
    const one = 'fn caller() { target(); }\n';
    const two = '\uFEFF// 🦊\r\nfn target() {}\r\n';
    final sourceFile = File('${workspace.path}/main.rs')
      ..writeAsStringSync(source);
    final first = File('${workspace.path}/one.rs')..writeAsStringSync(one);
    final second = File('${workspace.path}/two.rs')..writeAsStringSync(two);
    final calls = <bool>[];
    var explicit = false;
    final sourceOffset = source.indexOf('target');
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) async {
        expect(offset, sourceOffset);
        calls.add(includeDeclaration);
        return ReferencesResult(
          version: version,
          targets: [
            if (!explicit) ...[
              DefinitionTarget(
                uri: sourceFile.uri.toString(),
                line: 0,
                character: 12,
              ),
              DefinitionTarget(
                uri: first.uri.toString(),
                line: 0,
                character: 14,
              ),
            ],
            DefinitionTarget(
              uri: second.uri.toString(),
              line: 1,
              character: 3,
              endLine: 1,
              endCharacter: 9,
            ),
          ],
        );
      },
    );
    _activeController(tester).selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    final peek = find.byKey(const ValueKey('references-peek'));
    expect(peek, findsOneWidget);
    expect(find.text('引用 (3)'), findsOneWidget);
    expect(
      find.descendant(of: peek, matching: find.text('one.rs')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: peek, matching: find.text('two.rs')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, sourceOffset);
    expect(
      tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
      isTrue,
    );

    explicit = true;
    await _runPaletteCommand(tester, '速览引用');
    await tester.pumpAndSettle();
    expect(peek, findsOneWidget);
    expect(find.text('引用 (1)'), findsOneWidget);
    expect(_activeController(tester).text, source);
    expect(calls, [true, true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
    final text = two.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    expect(_activeController(tester).text, text);
    expect(_activeController(tester).selection.extentOffset,
        text.indexOf('target'));
    expect(
      tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
      isTrue,
    );
  });

  testWidgets('References Peek groups files and navigates the focused result',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-reference-tree');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn caller() { task(); }\n';
    const alphaText = 'fn alpha() { task(); }\n';
    const zetaText = 'fn b() { task(); }\nfn c() { task(); }\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync(alphaText);
    final zeta = File('${workspace.path}/zeta.rs')..writeAsStringSync(zetaText);
    final later = DefinitionTarget(
      uri: zeta.uri.toString(),
      line: 1,
      character: 9,
      endLine: 1,
      endCharacter: 13,
    );
    final early = DefinitionTarget(
      uri: zeta.uri.toString(),
      line: 0,
      character: 9,
      endLine: 0,
      endCharacter: 13,
    );
    final other = DefinitionTarget(
      uri: alpha.uri.toString(),
      line: 0,
      character: alphaText.indexOf('task'),
      endLine: 0,
      endCharacter: alphaText.indexOf('task') + 4,
    );
    var singleFile = false;
    final calls = <bool>[];
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) async {
        calls.add(includeDeclaration);
        return ReferencesResult(
          version: version,
          targets: [later, early, if (!singleFile) other, early],
        );
      },
    );
    _activeController(tester).selection =
        TextSelection.collapsed(offset: source.indexOf('task'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final peek = find.byKey(const ValueKey('references-peek'));
    Finder group(File file) =>
        find.byKey(ValueKey('references-file:${file.path}'));
    Finder leaf(int entry) => find.byKey(ValueKey('peek-result:$entry'));
    SemanticsProperties semantics(Finder node) =>
        tester.widget<Semantics>(node).properties;
    final alphaGroup = group(alpha);
    final zetaGroup = group(zeta);
    expect(peek, findsOneWidget);
    expect(find.text('引用 (3)'), findsOneWidget);
    expect(semantics(alphaGroup).expanded, isTrue);
    expect(semantics(zetaGroup).expanded, isFalse);
    expect(tester.getTopLeft(alphaGroup).dy,
        lessThan(tester.getTopLeft(zetaGroup).dy));
    expect(semantics(leaf(2)).selected, isTrue);
    expect(leaf(0), findsNothing);
    expect(leaf(1), findsNothing);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset,
        source.indexOf('task'));

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.arrowLeft);
    expect(semantics(alphaGroup).selected, isTrue);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(semantics(alphaGroup).expanded, isFalse);
    expect(leaf(2), findsNothing);
    await tester.tap(zetaGroup);
    await tester.pumpAndSettle();
    expect(semantics(zetaGroup).expanded, isTrue);
    expect(
        tester.getTopLeft(leaf(1)).dy, lessThan(tester.getTopLeft(leaf(0)).dy));
    await press(LogicalKeyboardKey.arrowRight);
    expect(semantics(leaf(1)).selected, isTrue);

    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowUp);
    expect(semantics(alphaGroup).selected, isTrue);
    await press(LogicalKeyboardKey.arrowRight);
    expect(semantics(alphaGroup).expanded, isTrue);
    await press(LogicalKeyboardKey.arrowRight);
    expect(semantics(leaf(2)).selected, isTrue);
    await press(LogicalKeyboardKey.enter);
    expect(peek, findsNothing);
    expect(_activeController(tester).text, alphaText);
    expect(_activeController(tester).selection.extentOffset,
        alphaText.indexOf('task'));
    expect(
        tester.widget<TextField>(_activeTextField()).focusNode!.hasPrimaryFocus,
        isTrue);

    singleFile = true;
    await _runPaletteCommand(tester, '速览引用');
    await tester.pumpAndSettle();
    expect(calls, [true, true]);
    expect(peek, findsOneWidget);
    expect(find.text('引用 (2)'), findsOneWidget);
    expect(zetaGroup, findsNothing);
    expect(semantics(leaf(1)).selected, isTrue);
    expect(
        tester.getTopLeft(leaf(1)).dy, lessThan(tester.getTopLeft(leaf(0)).dy));
  });

  testWidgets('selected reference row uses the resolved UTF-16 column',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-reference-column');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn task() {}\nfn call() { task(); }\n';
    const target = '\uFEFF/* 🦊 */ fn elsewhere() { task(); }\r\n';
    final local = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    final remote = File('${workspace.path}/target.rs')
      ..writeAsStringSync(target);
    final reported = target.indexOf('task');
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) async =>
          ReferencesResult(
        version: version,
        targets: [
          DefinitionTarget(
            uri: remote.uri.toString(),
            line: 0,
            character: reported,
            endLine: 0,
            endCharacter: reported + 4,
          ),
          DefinitionTarget(
            uri: local.uri.toString(),
            line: 0,
            character: 3,
            endLine: 0,
            endCharacter: 7,
          ),
          DefinitionTarget(
            uri: local.uri.toString(),
            line: 1,
            character: 12,
            endLine: 1,
            endCharacter: 16,
          ),
        ],
      ),
    );
    _activeController(tester).selection =
        const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final nearest = find.byKey(const ValueKey('peek-result:1'));
    expect(tester.widget<Semantics>(nearest).properties.selected, isTrue);
    await tester.tap(find.byKey(ValueKey('references-file:${remote.path}')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('peek-result:0'));
    final resolved =
        find.descendant(of: row, matching: find.text('1:$reported'));
    final watch = Stopwatch()..start();
    while (resolved.evaluate().isEmpty &&
        watch.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 25),
          ));
      await tester.pump();
    }
    expect(resolved, findsOneWidget);
    expect(tester.widget<Semantics>(row).properties.selected, isTrue);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, 3);
  });

  testWidgets('Peek shortcuts keep references open across files and wrap',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-reference-step');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn task() {}\nfn call() { let _ = "😀"; task(); }\n';
    const remote = '/* 🦊 */ fn other() { task(); }\n';
    final local = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    final target = File('${workspace.path}/target.rs')
      ..writeAsStringSync('\uFEFF${remote.replaceAll('\n', '\r\n')}');
    final targetBytes = target.readAsBytesSync();
    final declaration = source.indexOf('task');
    final usage = source.lastIndexOf('task');
    final remoteUsage = remote.indexOf('task');
    DefinitionTarget reference(File file, int line, int column) =>
        DefinitionTarget(
          uri: file.uri.toString(),
          line: line,
          character: column,
          endLine: line,
          endCharacter: column + 4,
        );

    var requests = 0;
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) async {
        requests++;
        return ReferencesResult(version: version, targets: [
          reference(target, 0, remoteUsage + 1),
          reference(local, 1, usage - source.indexOf('\n') - 1),
          reference(local, 0, declaration),
        ]);
      },
    );
    _activeController(tester).selection =
        TextSelection.collapsed(offset: declaration + 1);
    await tester.pump();

    final peek = find.byKey(const ValueKey('references-peek'));
    FocusNode editorFocus() =>
        tester.widget<TextField>(_activeTextField()).focusNode!;
    FocusNode listFocus() => tester
        .widget<Focus>(
          find.descendant(
            of: peek,
            matching: find.byWidgetPredicate((widget) =>
                widget is Focus &&
                widget.focusNode?.debugLabel == 'definition-peek-list'),
          ),
        )
        .focusNode!;
    Finder row(int index) => find.byKey(ValueKey('peek-result:$index'));

    Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    void expectReference(String text, int position, int index,
        {bool editorOwnsFocus = false, bool previewOwnsFocus = false}) {
      expect(peek, findsOneWidget);
      expect(_activeController(tester).text, text);
      expect(_activeController(tester).selection.extentOffset, position);
      expect(tester.widget<Semantics>(row(index)).properties.selected, isTrue);
      expect(editorFocus().hasPrimaryFocus, editorOwnsFocus);
      expect(_peekPreviewFocus(tester).hasPrimaryFocus, previewOwnsFocus);
      expect(
          listFocus().hasPrimaryFocus, !editorOwnsFocus && !previewOwnsFocus);
    }

    await press(LogicalKeyboardKey.f4);
    expect(peek, findsNothing);
    expect(requests, 0);
    await press(LogicalKeyboardKey.f12, shift: true);
    expect(listFocus().hasPrimaryFocus, isTrue);
    await _pressPeekFocusChord(tester);
    expect(_peekPreviewFocus(tester).hasPrimaryFocus, isTrue);
    expect(listFocus().hasPrimaryFocus, isFalse);
    expect(editorFocus().hasPrimaryFocus, isFalse);
    await press(LogicalKeyboardKey.keyX);
    expect(_activeController(tester).text, source);
    expect(_activeController(tester).selection.extentOffset, declaration + 1);
    await press(LogicalKeyboardKey.f4);
    expectReference(source, usage, 1, previewOwnsFocus: true);
    await press(LogicalKeyboardKey.f12);
    expectReference(remote, remoteUsage, 0, previewOwnsFocus: true);
    await _pressPeekFocusChord(tester);
    expectReference(remote, remoteUsage, 0);
    for (final path in [local.path, target.path]) {
      final group = find.byKey(ValueKey('references-file:$path'));
      expect(tester.widget<Semantics>(group).properties.expanded, isTrue);
    }
    await press(LogicalKeyboardKey.f4, shift: true);
    expectReference(source, usage, 1);
    await press(LogicalKeyboardKey.f4);
    expectReference(remote, remoteUsage, 0);
    await press(LogicalKeyboardKey.f12);
    expectReference(source, declaration, 2);

    editorFocus().requestFocus();
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.f12, shift: true);
    expectReference(remote, remoteUsage, 0, editorOwnsFocus: true);

    await tester.tap(row(0));
    await tester.pumpAndSettle();
    expectReference(remote, remoteUsage, 0);
    await _pressPeekFocusChord(tester);
    expectReference(remote, remoteUsage, 0, previewOwnsFocus: true);
    await press(LogicalKeyboardKey.escape);
    expect(peek, findsNothing);
    expect(editorFocus().hasPrimaryFocus, isTrue);
    expect(_activeController(tester).selection.extentOffset, remoteUsage);
    await press(LogicalKeyboardKey.f4);
    expect(requests, 1);
    expect(target.readAsBytesSync(), targetBytes);
  });

  testWidgets('reference results are ignored once the source caret moves',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-stale-reference');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn call() { target(); }\n';
    final main = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    final waiting = Completer<ReferencesResult?>();
    int? requestedVersion;
    await _openWorkspace(
      tester,
      temp,
      workspace,
      referencesRequest: (id, offset, version, includeDeclaration) {
        requestedVersion = version;
        return waiting.future;
      },
    );
    final controller = _activeController(tester);
    controller.selection =
        TextSelection.collapsed(offset: source.indexOf('target'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(requestedVersion, isNotNull);

    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    waiting.complete(ReferencesResult(
      version: requestedVersion!,
      targets: [
        DefinitionTarget(uri: main.uri.toString(), line: 0, character: 3)
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('references-peek')), findsNothing);
    expect(controller.selection.extentOffset, 0);
    expect(controller.text, source);
  });

  testWidgets('definition response is ignored after its source version changes',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-stale-definition');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = 'fn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);
    final response = Completer<DefinitionResult?>();
    var requestVersion = -1;

    await _openWorkspace(
      tester,
      temp,
      workspace,
      definitionRequest: (id, offset, version) {
        requestVersion = version;
        return response.future;
      },
    );
    _activeController(tester).selection = TextSelection.collapsed(
      offset: source.indexOf('target()'),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(requestVersion, greaterThan(0));

    await tester.enterText(_activeTextField(), '$source// changed\n');
    await tester.pump(const Duration(milliseconds: 100));
    response.complete(DefinitionResult(
      version: requestVersion,
      uri: Uri.file(targetPath).toString(),
      line: 0,
      character: 3,
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('文档已更改，已取消跳转'), findsOneWidget);
    expect(_activeController(tester).text, '$source// changed\n');
  });

  testWidgets(
      'definition opens an already open file in the source editor group',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-group-definition');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { target(); }\n';
    const targetText = 'fn target() {}\n';
    final targetPath = '${workspace.path}/target.rs';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    File(targetPath).writeAsStringSync(targetText);

    await _openWorkspace(
      tester,
      temp,
      workspace,
      openFileName: 'target.rs',
      definitionRequest: (id, offset, version) async => DefinitionResult(
        version: version,
        uri: Uri.file(targetPath).toString(),
        line: 0,
        character: 3,
      ),
    );
    await _runPaletteCommand(tester, '拆分编辑器');
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(RustTextInputField), findsNWidgets(2));

    final sourceField = find.byType(RustTextInputField).last;
    final sourceTextField = find.descendant(
      of: sourceField,
      matching: find.byType(TextField),
    );
    await tester.tap(sourceTextField);
    await tester.pump();
    final sourceOffset = source.indexOf('target()');
    tester.widget<TextField>(sourceTextField).controller!.selection =
        TextSelection.collapsed(offset: sourceOffset);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RustTextInputField), findsNWidgets(2));
    final firstField = find.byType(RustTextInputField).first;
    final lastField = find.byType(RustTextInputField).last;
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: firstField,
            matching: find.byType(TextField),
          ))
          .controller!
          .text,
      targetText,
    );
    expect(
      tester
          .widget<TextField>(find.descendant(
            of: lastField,
            matching: find.byType(TextField),
          ))
          .controller!
          .selection
          .extentOffset,
      targetText.indexOf('target()'),
    );
  });

  testWidgets('last edit location restores the UTF-16 caret position',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-last-edit-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { let value = 1; }\n';
    const edited = 'fn main() { let answer = 1; }\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);

    await _openWorkspace(tester, temp, workspace);
    final editOffset = source.indexOf('value');
    _activeController(tester).selection =
        TextSelection.collapsed(offset: editOffset);
    await tester.pump();
    await tester.enterText(_activeTextField(), edited);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_activeController(tester).text, edited);

    _activeController(tester).selection =
        const TextSelection.collapsed(offset: edited.length);
    await tester.pump();
    await _runPaletteCommand(tester, '转到上次编辑位置');
    expect(_activeController(tester).selection.extentOffset, editOffset);
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
  });
}
