import 'dart:async';

import 'package:alula_app/git/git_changes_list.dart';
import 'package:alula_app/git/git_cli.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GitStatusEntry entry(String path, {bool staged = false, String? origPath}) =>
    GitStatusEntry(
        x: staged ? 'M' : ' ',
        y: staged ? ' ' : 'M',
        path: path,
        origPath: origPath);

Finder row(String path, {bool staged = false}) =>
    find.byKey(ValueKey('git-${staged ? 's' : 'w'}-$path'));

bool focused(WidgetTester tester, String path, {bool staged = false}) => tester
    .widget<Semantics>(
        find.byKey(ValueKey('git-focus-${staged ? 's' : 'w'}-$path')))
    .properties
    .focused!;

FocusNode listFocus(WidgetTester tester) => tester
    .widget<Focus>(find.byKey(const ValueKey('git-changes-list-focus')))
    .focusNode!;

Future<void> focusList(WidgetTester tester) async {
  listFocus(tester).requestFocus();
  await tester.pump();
}

Widget surface({
  required List<GitStatusEntry> entries,
  Future<void> Function(GitStatusEntry, {required bool preserveFocus})? onOpen,
  Future<void> Function(String)? onStage,
  Future<void> Function(String)? onUnstage,
  Widget? sibling,
  double height = 180,
}) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Column(children: [
          SizedBox(
            width: 400,
            height: height,
            child: GitChangesList(
              entries: entries,
              onOpen: onOpen ?? (_, {required preserveFocus}) async {},
              onStage: onStage ?? (_) async {},
              onUnstage: onUnstage ?? (_) async {},
            ),
          ),
          if (sibling != null) sibling,
        ]),
      ),
    );

void main() {
  testWidgets('Enter and Space select focused row and pass preserveFocus',
      (tester) async {
    final opened = <(String, bool)>[];
    final actions = <String>[];
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt'), entry('beta.txt')],
      onOpen: (entry, {required preserveFocus}) async =>
          opened.add((entry.path, preserveFocus)),
      onStage: (path) async => actions.add(path),
      onUnstage: (path) async => actions.add(path),
    ));
    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(tester, 'alpha.txt'), isTrue,
        reason: 'Initial Up focuses the first row');
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'beta.txt'), isTrue);
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isTrue);
    expect(tester.widget<ListTile>(row('beta.txt')).selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isFalse);
    expect(tester.widget<ListTile>(row('beta.txt')).selected, isTrue);
    expect(listFocus(tester).hasPrimaryFocus, isTrue);
    expect(opened, [('alpha.txt', false), ('beta.txt', true)]);
    expect(actions, isEmpty);
  });

  testWidgets('Enter from a focused row preserves its async focus owner',
      (tester) async {
    final pending = Completer<void>();
    final destination = FocusNode();
    addTearDown(destination.dispose);
    FocusNode? source;
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt')],
      sibling: TextButton(
          focusNode: destination, onPressed: () {}, child: const Text('Diff')),
      onOpen: (_, {required preserveFocus}) async {
        expect(preserveFocus, isFalse);
        source = FocusManager.instance.primaryFocus;
        await pending.future;
        if (FocusManager.instance.primaryFocus == source) {
          destination.requestFocus();
        }
      },
    ));
    final rowFocus = Focus.of(tester.element(find.text('alpha.txt')));
    rowFocus.requestFocus();
    await tester.pump();
    expect(rowFocus.hasPrimaryFocus, isTrue);
    expect(listFocus(tester).hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(destination.hasPrimaryFocus, isTrue,
        reason: 'Internal focus normalization must not defeat the open guard');
  });

  testWidgets('pending Space never reclaims deliberate external focus',
      (tester) async {
    final pending = Completer<void>();
    final other = FocusNode();
    addTearDown(other.dispose);
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt')],
      sibling: TextButton(
          focusNode: other, onPressed: () {}, child: const Text('Other')),
      onOpen: (_, {required preserveFocus}) {
        expect(preserveFocus, isTrue);
        return pending.future;
      },
    ));
    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(listFocus(tester).hasPrimaryFocus, isTrue);
    await tester.tap(find.text('Other'));
    other.requestFocus();
    await tester.pump();
    expect(other.hasPrimaryFocus, isTrue);
    pending.complete();
    await tester.pump();
    expect(other.hasPrimaryFocus, isTrue);
    expect(listFocus(tester).hasFocus, isFalse);
  });

  testWidgets('hover leaves focus, selection and keyboard target unchanged',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt'), entry('beta.txt')],
      onOpen: (entry, {required preserveFocus}) async => opened.add(entry.path),
    ));
    await tester.tap(row('alpha.txt'));
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(row('beta.txt')));
    await tester.pump();
    expect(focused(tester, 'alpha.txt'), isTrue);
    expect(focused(tester, 'beta.txt'), isFalse);
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isTrue);
    expect(tester.widget<ListTile>(row('beta.txt')).selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['alpha.txt', 'alpha.txt']);
    await mouse.removePointer();
  });

  testWidgets('modified navigation and activation are ignored', (tester) async {
    final opened = <String>[];
    final actions = <String>[];
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt'), entry('beta.txt')],
      onOpen: (entry, {required preserveFocus}) async => opened.add(entry.path),
      onStage: (path) async => actions.add(path),
    ));
    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    for (final modifier in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(focused(tester, 'alpha.txt'), isTrue);
      expect(tester.widget<ListTile>(row('alpha.txt')).selected, isFalse);
    }
    expect(opened, isEmpty);
    expect(actions, isEmpty);
  });

  testWidgets(
      'focused action activates once; navigation transfers focus to list',
      (tester) async {
    final opened = <String>[];
    final staged = <String>[];
    final unstaged = <String>[];
    await tester.pumpWidget(surface(
      entries: [
        entry('indexed.txt', staged: true),
        entry('alpha.txt'),
        entry('beta.txt')
      ],
      height: 240,
      onOpen: (entry, {required preserveFocus}) async => opened.add(entry.path),
      onStage: (path) async => staged.add(path),
      onUnstage: (path) async => unstaged.add(path),
    ));
    FocusNode actionFocus(String path, {bool staged = false}) {
      final button =
          find.byKey(ValueKey('git-action-${staged ? 's' : 'w'}-$path'));
      final icon = find.descendant(of: button, matching: find.byType(Icon));
      return Focus.of(tester.element(icon));
    }

    actionFocus('alpha.txt').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(staged, ['alpha.txt', 'alpha.txt']);
    expect(opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(listFocus(tester).hasPrimaryFocus, isTrue);
    expect(focused(tester, 'beta.txt'), isTrue);
    expect(tester.widget<ListTile>(row('beta.txt')).selected, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['beta.txt']);

    actionFocus('indexed.txt', staged: true).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(unstaged, ['indexed.txt']);
    expect(opened, ['beta.txt']);
  });

  testWidgets('arrows, Home and End reveal focus across section headers',
      (tester) async {
    final entries = List.generate(
        40,
        (i) => entry('file-$i.txt',
            staged: i < 2, origPath: i == 39 ? 'old.txt' : null));
    await tester.pumpWidget(surface(entries: entries));
    await focusList(tester);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('git-changes-list')));
    Future<void> expectVisible(String path, {bool staged = false}) async {
      await tester.pumpAndSettle();
      final target = tester.getRect(row(path, staged: staged));
      expect(target.top, greaterThanOrEqualTo(viewport.top));
      expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(focused(tester, path, staged: staged), isTrue);
      expect(
          tester.widget<ListTile>(row(path, staged: staged)).selected, isFalse);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await expectVisible('file-39.txt');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await expectVisible('file-0.txt', staged: true);
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await expectVisible('file-12.txt');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await expectVisible('file-11.txt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged parent rebuild preserves manual list scrolling',
      (tester) async {
    final entries = List.generate(40, (i) => entry('file-$i.txt'));
    await tester.pumpWidget(surface(entries: entries));
    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final list = find.byKey(const ValueKey('git-changes-list'));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(list).controller!;
    final before = scroll.offset;
    expect(before, greaterThan(0));
    await tester.pumpWidget(surface(entries: entries));
    await tester.pump();
    expect(scroll.offset, before,
        reason: 'Unrelated rebuilds must not reveal an offscreen focused row');
    expect(listFocus(tester).hasFocus, isTrue);
  });

  testWidgets(
      'focus and selection independently survive updates and clear on removal',
      (tester) async {
    var entries = [entry('alpha.txt'), entry('beta.txt')];
    final opened = <String>[];
    Future<void> rebuild() => tester.pumpWidget(surface(
          entries: entries,
          onOpen: (entry, {required preserveFocus}) async =>
              opened.add(entry.path),
        ));
    await rebuild();
    await tester.tap(row('alpha.txt'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    entries = [entry('beta.txt'), entry('alpha.txt')];
    await rebuild();
    expect(focused(tester, 'beta.txt'), isTrue);
    expect(tester.widget<ListTile>(row('alpha.txt')).selected, isTrue);
    entries = [
      entry('alpha.txt', staged: true),
      entry('beta.txt', staged: true)
    ];
    await rebuild();
    expect(focused(tester, 'beta.txt', staged: true), isTrue);
    expect(tester.widget<ListTile>(row('alpha.txt', staged: true)).selected,
        isTrue);
    expect(tester.widget<ListTile>(row('beta.txt', staged: true)).selected,
        isFalse);
    expect(row('beta.txt'), findsNothing);
    entries = [entry('alpha.txt', staged: true)];
    await rebuild();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['alpha.txt'],
        reason: 'Removed focus does not reopen selection');
    expect(tester.widget<ListTile>(row('alpha.txt', staged: true)).selected,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(tester, 'alpha.txt', staged: true), isTrue);
    entries = [entry('beta.txt')];
    await rebuild();
    expect(focused(tester, 'beta.txt'), isFalse);
    expect(tester.widget<ListTile>(row('beta.txt')).selected, isFalse);
  });

  testWidgets('mixed changes keep the existing staged group identity',
      (tester) async {
    final staged = <String>[];
    final unstaged = <String>[];
    await tester.pumpWidget(surface(
      entries: const [GitStatusEntry(x: 'M', y: 'M', path: 'mixed.txt')],
      onStage: (path) async => staged.add(path),
      onUnstage: (path) async => unstaged.add(path),
    ));
    expect(row('mixed.txt', staged: true), findsOneWidget);
    expect(row('mixed.txt'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('git-action-s-mixed.txt')));
    await tester.pump();
    expect(unstaged, ['mixed.txt']);
    expect(staged, isEmpty);
  });

  testWidgets('pending Space completion after disposal does not restore focus',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(surface(
      entries: [entry('alpha.txt')],
      onOpen: (_, {required preserveFocus}) => pending.future,
    ));
    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
