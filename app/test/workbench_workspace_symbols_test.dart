import 'dart:async';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/native_drag_drop.dart';

void main() {
  setUp(mockNativeDragDrop);

  testWidgets(
      'workspace symbol picker reports unavailable provider without fake results',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-empty');
    final file = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97,
            'docs': [
              {'id': 97, 'path': file.path}
            ]
          }
        ],
      });
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '#anything');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('当前工作区没有可用符号提供程序'), findsOneWidget);
    expect(find.text('Source'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    expect(find.byKey(const ValueKey('qi-当前工作区没有可用符号提供程序')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 120));
    await opening;
  });

  testWidgets('workspace symbol query cancellation discards late results',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-cancel');
    final file = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97,
            'docs': [
              {'id': 97, 'path': file.path}
            ]
          }
        ],
      });
    final pending = Completer<List<Map<String, Object?>>?>();
    final cancelled = Completer<void>();
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) async {
        signal.then((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        });
        return pending.future;
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '#slow');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => cancelled.future.timeout(const Duration(seconds: 2)));
    pending.complete([
      {
        'name': 'late',
        'kind': 12,
        'uri': 'file:///late.rs',
        'line': 0,
        'character': 0,
        'endLine': 0,
        'endCharacter': 4
      }
    ]);
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(find.text('late'), findsNothing);
    await opening;
  });

  testWidgets(
      'workspace symbol provider fixture navigates cross-file UTF-16 ranges',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-picker');
    final source = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}\n');
    final target = File('${temp.path}/target.rs')
      ..writeAsStringSync('head\r\n😀target\r\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 98,
            'docs': [
              {'id': 98, 'path': source.path}
            ]
          }
        ],
      });
    CommandService? commands;
    final queries = <String>[];
    var staleRange = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, cancel) async {
        queries.add(query);
        if (query == 'missing') return [];
        return [
          {
            'name': 'target',
            'kind': 12,
            'uri': Uri.file(target.path).toString(),
            'line': 1,
            'character': 2,
            'endLine': staleRange ? 99 : 1,
            'endCharacter': 8,
            'containerName': 'fixture'
          }
        ];
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('输入符号名称以搜索工作区'), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-输入符号名称以搜索工作区')), findsNothing);
    expect(queries, isEmpty);
    await tester.enterText(input, '#missing');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的工作区符号。'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    await tester.enterText(input, '#target');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-target')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      final fields = find.byKey(const ValueKey('rust-bounded-text-input'));
      if (fields.evaluate().isNotEmpty &&
          tester
              .widget<TextField>(fields)
              .controller!
              .text
              .contains('😀target')) {
        break;
      }
    }
    await opening;
    final controller = tester
        .widget<TextField>(
            find.byKey(const ValueKey('rust-bounded-text-input')))
        .controller!;
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
    expect(queries, ['missing', 'target']);
    final oldSelection = controller.selection;
    staleRange = true;
    final stale = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final staleInput = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(staleInput, '#target');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await stale;
    expect(controller.selection, oldSelection);
    expect(tester.takeException(), isNull);
    expect(target.readAsStringSync(), 'head\r\n😀target\r\n');
  });

  testWidgets(
      'workspace symbol side shortcuts reuse the right group and preserve the source',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-side');
    const sourceText = 'fn source() {}\n';
    const targetText = 'head\r\n😀target\r\n';
    final source = File('${temp.path}/source.rs')
      ..writeAsStringSync(sourceText);
    final target = File('${temp.path}/target.rs')
      ..writeAsStringSync(targetText);
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'workspace': temp.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 96,
            'preview': 96,
            'docs': [
              {'id': 96, 'path': source.path}
            ],
          }
        ],
      });
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) async => [
        {
          'name': 'target',
          'kind': 12,
          'uri': Uri.file(target.path).toString(),
          'line': 1,
          'character': 2,
          'endLine': 1,
          'endCharacter': 8,
        },
      ],
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    Finder field(String region) => find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        );
    RustTextInputField editor(String region) =>
        tester.widget<RustTextInputField>(field(region));
    final sourceTab = find.byKey(const ValueKey('editor-tab-label-editor-96'));

    Future<void> aside(LogicalKeyboardKey? modifier) async {
      await tester.tap(sourceTab);
      await tester.pumpAndSettle();
      final sourceEditor = editor('editor');
      expect(sourceEditor.focusNode!.hasPrimaryFocus, isTrue);
      final sourceSelection = sourceEditor.inputWindow.initialValue.selection;
      final opening = commands.execute('workbench.action.showAllSymbols');
      await tester.pumpAndSettle();
      await tester.enterText(input, '#target');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qi-target')), findsOneWidget);
      if (modifier == null) {
        await tester.tap(find.byKey(const ValueKey('qi-button-target-0')));
      } else {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(modifier);
      }
      for (var frame = 0; frame < 50; frame++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (field('editor-2').evaluate().isNotEmpty &&
            editor('editor-2').focusNode!.hasPrimaryFocus) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(await opening, CommandExecutionStatus.executed);
      expect(panel, findsNothing);
      expect(find.byType(RustTextInputField), findsNWidgets(2));
      expect(editor('editor').inputWindow.document.id, 96);
      expect(
          editor('editor').inputWindow.initialValue.selection, sourceSelection);
      expect(tester.widget<Text>(sourceTab).style?.fontStyle, FontStyle.italic);
      final right = editor('editor-2');
      expect(right.focusNode!.hasPrimaryFocus, isTrue);
      expect(right.inputWindow.initialValue.selection,
          const TextSelection.collapsed(offset: 7));
      final targetTab = find.byKey(ValueKey(
          'editor-tab-label-editor-2-${right.inputWindow.document.id}'));
      expect(tester.widget<Text>(targetTab).style?.fontStyle,
          isNot(FontStyle.italic));
      expect(find.byKey(const ValueKey('editor-tab-label-editor-2-96')),
          findsNothing);
    }

    await aside(LogicalKeyboardKey.altLeft);
    final right = editor('editor-2').focusNode;
    final platform = Theme.of(tester.element(field('editor'))).platform;
    await aside(platform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft);
    expect(editor('editor-2').focusNode, same(right));
    await aside(null);
    expect(editor('editor-2').focusNode, same(right));
    expect(source.readAsStringSync(), sourceText);
    expect(target.readAsStringSync(), targetText);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }));

  testWidgets(
      'blank workspace symbols show guidance in the first frame and cancel pending work',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-idle');
    final file = File('${temp.path}/source.rs')
      ..writeAsStringSync('pub struct Source;\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 99,
            'docs': [
              {'id': 99, 'path': file.path},
            ],
          },
        ],
      });
    final pending = Completer<List<Map<String, Object?>>?>();
    final cancelled = Completer<void>();
    final queries = <String>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) {
        queries.add(query);
        unawaited(signal.then((_) => cancelled.complete()));
        return pending.future;
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands.execute('workbench.action.showAllSymbols');
    await tester.pump();

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final loading = find.byKey(const ValueKey('quick-input-loading'));
    final guide = find.text('输入符号名称以搜索工作区');
    expect(loading, findsNothing);
    expect(guide, findsOneWidget);
    expect(queries, isEmpty);

    await tester.enterText(input, '#Source');
    await tester.pump();
    expect(loading, findsOneWidget);
    expect(guide, findsNothing);
    expect(queries, ['Source']);

    await tester.enterText(input, '#   ');
    await tester.pump();
    expect(loading, findsNothing);
    expect(guide, findsOneWidget);
    expect(cancelled.isCompleted, isTrue);
    pending.complete([
      {
        'name': 'Source',
        'kind': 23,
        'uri': Uri.file(file.path).toString(),
        'line': 0,
        'character': 11,
        'endLine': 0,
        'endCharacter': 17,
      },
    ]);
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-Source')), findsNothing);
    expect(guide, findsOneWidget);
    expect(queries, ['Source']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
  });

  testWidgets(
      'workspace symbol compound queries keep path and name matches separate',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-query');
    final directory = Directory('${temp.path}/src')..createSync();
    final file = File('${directory.path}/entry.rs')
      ..writeAsStringSync('pub struct Entry;\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'workspace': temp.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 100,
            'docs': [
              {'id': 100, 'path': file.path},
            ],
          },
        ],
      });
    Map<String, Object?> symbol(
            String name, String fileName, String container) =>
        {
          'name': name,
          'kind': 23,
          'uri': Uri.file('${directory.path}/$fileName').toString(),
          'line': 0,
          'character': 0,
          'endLine': 0,
          'endCharacter': name.length,
          'containerName': container,
        };
    final symbols = List<Map<String, Object?>>.unmodifiable([
      symbol('CandleProbeWidget', 'target.rs', 'alpha'),
      symbol('Unrelated', 'target.rs', 'alpha'),
      symbol('CandleProbeMirror', 'mirror.rs', 'beta'),
    ]);
    final queries = <String>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) async {
        queries.add(query);
        return symbols;
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands.execute('workbench.action.showAllSymbols');
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    Finder row(String name) => find.byKey(ValueKey('qi-$name'));
    List<String?> marks(String name, String text) {
      final label = tester.widget<Text>(find.descendant(
        of: row(name),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == text),
      ));
      final spans = (label.textSpan as TextSpan?)?.children ?? const [];
      return [
        for (final span in spans.whereType<TextSpan>())
          if (span.style?.fontWeight == FontWeight.bold) span.text,
      ];
    }

    Future<void> query(String value) async {
      await tester.enterText(input, value);
      await tester.pumpAndSettle();
    }

    const widget = 'CandleProbeWidget';
    const mirror = 'CandleProbeMirror';
    final description = 'alpha • src${Platform.pathSeparator}target.rs';
    await query('#CandleProbe target.rs');
    expect(queries, ['CandleProbe']);
    expect(row(widget), findsOneWidget);
    expect(row(mirror), findsNothing);
    expect(row('Unrelated'), findsNothing);
    expect(marks(widget, widget), ['CandleProbe']);
    expect(marks(widget, description), ['target.rs']);

    await query('#Candle Probe');
    expect(queries.last, 'Candle');
    expect(row(widget), findsOneWidget);
    expect(row(mirror), findsOneWidget);
    expect(row('Unrelated'), findsNothing);
    expect(tester.getTopLeft(row(mirror)).dy,
        lessThan(tester.getTopLeft(row(widget)).dy));
    expect(marks(widget, widget), ['CandleProbe']);
    expect(marks(widget, description), isEmpty);

    await query('#CandleProbe missing.rs');
    expect(queries.last, 'CandleProbe');
    expect(row(widget), findsNothing);
    expect(row(mirror), findsNothing);
    expect(find.text('没有匹配的工作区符号。'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
  });

  testWidgets(
      'workspace symbol background acceptance keeps the query and input focus',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-symbol-background');
    const sourceText = 'pub struct Origin;\n';
    const sideText = 'head\r\n😀Other\r\n';
    const middleText = '// 😀\nstruct Third;\n';
    const bomText = '\uFEFFpub struct ByteOrderMark;\r\n';
    final source = File('${temp.path}/source.rs')
      ..writeAsStringSync(sourceText);
    final side = File('${temp.path}/side.rs')..writeAsStringSync(sideText);
    final middle = File('${temp.path}/middle.rs')
      ..writeAsStringSync(middleText);
    final bom = File('${temp.path}/bom.rs')..writeAsStringSync(bomText);
    final bomBytes = bom.readAsBytesSync();
    expect(bomBytes.take(3), [0xef, 0xbb, 0xbf]);
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'workspace': temp.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 101,
            'preview': 101,
            'docs': [
              {'id': 101, 'path': source.path}
            ],
          },
        ],
      });
    Map<String, Object?> symbol(
            String name, File file, int line, int start, int end) =>
        {
          'name': name,
          'kind': 23,
          'uri': Uri.file(file.path).toString(),
          'line': line,
          'character': start,
          'endLine': line,
          'endCharacter': end,
        };
    final results = {
      'Origin': symbol('Origin', source, 0, 11, 17),
      'Other': symbol('Other', side, 1, 2, 7),
      'Third': symbol('Third', middle, 1, 7, 12),
      'ByteOrderMark': symbol('ByteOrderMark', bom, 0, 12, 25),
    };
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) async =>
          [if (results[query] case final item?) item],
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final panel = find.byKey(const ValueKey('quick-input'));
    final filter = find.descendant(of: panel, matching: find.byType(TextField));
    final sourceTab = find.byKey(const ValueKey('editor-tab-label-editor-101'));
    Finder field(String region) => find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        );
    RustTextInputField editor(String region) =>
        tester.widget<RustTextInputField>(field(region));
    final opening = commands.execute('workbench.action.showAllSymbols');
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(filter);
    final edit = input.controller!;
    Future<void> query(String name) async {
      await tester.enterText(filter, '#$name');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('qi-$name')), findsOneWidget);
    }

    Future<void> keyRight({LogicalKeyboardKey? modifier}) async {
      if (modifier != null) await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      if (modifier != null) await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
    }

    Future<void> waitEditor(String region, String text) async {
      for (var frame = 0; frame < 50; frame++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (field(region).evaluate().isNotEmpty &&
            editor(region).inputWindow.text == text) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(editor(region).inputWindow.text, text);
    }

    await query('Origin');
    edit.selection = TextSelection(
        baseOffset: edit.text.length - 1, extentOffset: edit.text.length);
    await tester.pump();
    await keyRight();
    expect(edit.selection, TextSelection.collapsed(offset: edit.text.length));
    expect(tester.widget<Text>(sourceTab).style?.fontStyle, FontStyle.italic);
    expect(editor('editor').inputWindow.initialValue.selection.extentOffset, 0);
    await keyRight();
    expect(tester.widget<Text>(sourceTab).style?.fontStyle,
        isNot(FontStyle.italic));
    expect(editor('editor').inputWindow.initialValue.selection,
        const TextSelection.collapsed(offset: 11));
    expect(input.focusNode!.hasPrimaryFocus, isTrue);
    expect(edit.text, '#Origin');

    await query('Other');
    final platform = Theme.of(tester.element(filter)).platform;
    await keyRight(
        modifier: platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft);
    await waitEditor('editor-2', 'head\n😀Other\n');
    final right = editor('editor-2');
    expect(right.inputWindow.initialValue.selection,
        const TextSelection.collapsed(offset: 7));
    final sideTab = find.byKey(
        ValueKey('editor-tab-label-editor-2-${right.inputWindow.document.id}'));
    expect(
        tester.widget<Text>(sideTab).style?.fontStyle, isNot(FontStyle.italic));
    expect(editor('editor').inputWindow.document.id, 101);
    expect(input.focusNode!.hasPrimaryFocus, isTrue);
    expect(edit.text, '#Other');

    await query('Third');
    final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('qi-Third'))),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton);
    await press.up();
    await waitEditor('editor', middleText);
    expect(panel, findsOneWidget);
    expect(input.focusNode!.hasPrimaryFocus, isTrue);
    expect(edit.text, '#Third');
    expect(editor('editor').inputWindow.initialValue.selection,
        TextSelection.collapsed(offset: middleText.indexOf('Third')));
    expect(editor('editor-2').inputWindow.document.id,
        right.inputWindow.document.id);
    await tester.pump(const Duration(milliseconds: 900));
    expect(session.tryLoad()!['focused'], 'editor');

    await query('ByteOrderMark');
    await keyRight();
    await waitEditor('editor', 'pub struct ByteOrderMark;\n');
    expect(editor('editor').inputWindow.initialValue.selection,
        const TextSelection.collapsed(offset: 11));
    expect(input.focusNode!.hasPrimaryFocus, isTrue);
    expect(bom.readAsBytesSync(), bomBytes);

    await query('Origin');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
    expect(editor('editor').focusNode!.hasPrimaryFocus, isTrue);
    expect(source.readAsStringSync(), sourceText);
    expect(side.readAsStringSync(), sideText);
    expect(middle.readAsStringSync(), middleText);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }));
}
