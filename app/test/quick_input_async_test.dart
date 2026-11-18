import 'dart:async';

import 'package:alula_app/workbench/quick_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picker accepts a candidate only once during route dismissal',
      (tester) async {
    var runs = 0;
    final action = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  child: const Text('open'),
                  onPressed: () =>
                      QuickInput.show(context, hint: 'pick', items: [
                    QuickItem(
                        label: 'target',
                        onRun: () async {
                          runs++;
                          await action.future;
                        }),
                  ]),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runs, 1);
    expect(find.text('open'), findsOneWidget);
    action.complete();
    await tester.pump();
  });

  testWidgets(
      'async picker ignores stale results and late completion after close',
      (tester) async {
    final pending = <String, Completer<List<QuickItem>>>{};
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => QuickInput.show(context,
                      hint: 'query',
                      items: const [],
                      itemsProvider: (query) => (pending[query] =
                              Completer<List<QuickItem>>())
                          .future,
                      onClose: () => closed++),
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    pending['old']!.complete([const QuickItem(label: 'obsolete')]);
    pending['new']!.complete([const QuickItem(label: 'current')]);
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-obsolete')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    pending['']!.complete([const QuickItem(label: 'late')]);
    await tester.pump();
    expect(closed, 1);
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the Navigator cancels a pending picker once',
      (tester) async {
    final pending = Completer<List<QuickItem>>();
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  child: const Text('open'),
                  onPressed: () => QuickInput.show(context,
                      hint: 'pending',
                      items: const [],
                      itemsProvider: (_) => pending.future,
                      onClose: () => closed++),
                ))));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed, 1);
    pending.complete([const QuickItem(label: 'late')]);
    await tester.pump();
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'input validates asynchronously, rejects stale results and accepts current text',
      (tester) async {
    final pending = <String, Completer<String?>>{};
    String? accepted;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    accepted = await QuickInput.input(context, prompt: 'name',
                        validateInput: (value) {
                      final result = Completer<String?>();
                      pending[value] = result;
                      return result.future;
                    });
                  },
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.byType(TextField);
    pending['']!.complete('required');
    await tester.pump();
    expect(find.text('required'), findsOneWidget);
    await tester.enterText(input, 'old');
    await tester.pump();
    await tester.enterText(input, 'new');
    await tester.pump();
    pending['old']!.complete('obsolete');
    await tester.pump();
    expect(find.text('obsolete'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
    pending['new']!.complete(null);
    await tester.pump();
    final validated = pending['new'];
    tester.widget<TextField>(input).controller!.selection =
        const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(pending['new'], same(validated),
        reason: 'caret movement does not revalidate');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, 'new');
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
  });

  for (final severity in QuickInputValidationSeverity.values) {
    testWidgets('typed $severity controls input acceptance', (tester) async {
      String? accepted;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => accepted = await QuickInput.input(context,
              prompt: 'typed',
              value: 'current',
              validateInputMessage: (_) =>
                  QuickInputValidationMessage('message', severity)),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('message'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      if (severity == QuickInputValidationSeverity.error) {
        expect(accepted, isNull);
        expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      } else {
        expect(accepted, 'current');
        expect(find.byKey(const ValueKey('quick-input')), findsNothing);
      }
    });
  }

  testWidgets('empty typed error blocks and current valid clears decoration',
      (tester) async {
    String? accepted;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => accepted = await QuickInput.input(context,
            prompt: 'typed',
            validateInputMessage: (value) => value.isEmpty
                ? const QuickInputValidationMessage(
                    '', QuickInputValidationSeverity.error)
                : null),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
    expect(find.bySemanticsLabel('错误'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'valid');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-input-validation')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).decoration!.border,
        InputBorder.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, 'valid');
  });

  testWidgets(
      'typed validation retains pending message and ignores stale errors',
      (tester) async {
    final pending = <String, Completer<QuickInputValidationMessage?>>{};
    String? accepted;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => accepted = await QuickInput.input(context,
            prompt: 'typed',
            validateInputMessage: (value) => (pending[value] =
                    Completer<QuickInputValidationMessage?>())
                .future),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 120));
    pending['']!.complete(const QuickInputValidationMessage(
        'previous error', QuickInputValidationSeverity.error));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump();
    expect(find.text('previous error'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'current');
    await tester.pump();
    pending['current']!.complete(const QuickInputValidationMessage(
        'warning', QuickInputValidationSeverity.warning));
    await tester.pump();
    pending['old']!.completeError(StateError('obsolete'));
    await tester.pump();
    expect(find.text('warning'), findsOneWidget);
    expect(find.textContaining('obsolete'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, 'current');
  });

  testWidgets('legacy and typed validators are mutually exclusive at runtime',
      (tester) async {
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      host = context;
      return const SizedBox.shrink();
    })));
    expect(
        () => QuickInput.show(host,
            hint: 'both',
            items: const [],
            validateInput: (_) => null,
            validateInputMessage: (_) => null),
        throwsArgumentError);
    await expectLater(
        QuickInput.input(host,
            prompt: 'both',
            validateInput: (_) => null,
            validateInputMessage: (_) => null),
        throwsArgumentError);
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
  });

  testWidgets('input history retains draft and Escape returns null',
      (tester) async {
    String? accepted = 'not closed';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () async => accepted = await QuickInput.input(
                      context,
                      prompt: 'name',
                      value: 'draft',
                      history: ['newer', 'older']),
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'newer');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'older');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(accepted, isNull);
  });

  testWidgets('multi selection accepts picked items hidden by query',
      (tester) async {
    List<QuickItem>? accepted;
    const alpha = QuickItem(label: 'alpha', picked: true);
    const beta = QuickItem(label: 'beta');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => QuickInput.show(context,
                      hint: 'pick',
                      items: [alpha, beta],
                      canSelectMany: true,
                      onAccept: (items) => accepted = items),
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, [alpha, beta]);
  });
}
