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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
              uri: primary.uri.toString(),
              line: 0,
              character: 3,
              endLine: 0,
              endCharacter: 8,
              alternatives: [
                DefinitionTarget(
                  uri: secondary.uri.toString(),
                  line: 1,
                  character: 3,
                  endLine: 1,
                  endCharacter: 7,
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
      expect(_activeController(tester).text, source);
      expect(_activeController(tester).selection.extentOffset, sourceOffset);
    }

    await openPeek();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
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

  testWidgets('default Peek Definition shortcut keeps a single target in peek',
      (tester) async {
    final platform = defaultTargetPlatform;
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(peek, findsNothing);
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
