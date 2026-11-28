import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/walkthrough.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_walkthrough_widget');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
      'welcome opens walkthrough, completion persists, and reset clears it',
      (tester) async {
    CommandService? commands;
    await _mount(
      tester,
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: keybindingsStore,
      onCommands: (service) => commands = service,
    );
    try {
      await commands!.execute('workbench.action.welcome');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-section-Walkthroughs')),
          findsOneWidget);
      expect(find.text('0 / 5 个步骤已完成'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('welcome-walkthrough-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walkthrough-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('walkthrough-current-create-edit-file')),
          findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(const ValueKey('walkthrough-complete-create-edit-file')))
            .value,
        isFalse,
      );

      await tester.tap(
          find.byKey(const ValueKey('walkthrough-complete-create-edit-file')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(const ValueKey('walkthrough-complete-create-edit-file')))
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('walkthrough-back-welcome')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 5 个步骤已完成'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
    } finally {
      await _unmount(tester);
    }

    await _mount(
      tester,
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: keybindingsStore,
      onCommands: (service) => commands = service,
    );
    try {
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsOneWidget);
      expect(find.text('1 / 5 个步骤已完成'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('welcome-walkthrough-open')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(const ValueKey('walkthrough-complete-create-edit-file')))
            .value,
        isTrue,
      );

      await commands!.execute('resetGettingStartedProgress');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find
                .byKey(const ValueKey('walkthrough-complete-create-edit-file')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('walkthrough-back-welcome')));
      await tester.pumpAndSettle();
      expect(find.text('0 / 5 个步骤已完成'), findsOneWidget);
    } finally {
      await _unmount(tester);
    }
  });

  testWidgets('argument routing, QuickInput selection, and checkbox semantics',
      (tester) async {
    CommandService? commands;
    await _mount(
      tester,
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: keybindingsStore,
      onCommands: (service) => commands = service,
    );
    try {
      await commands!.execute(
        'workbench.action.openWalkthrough',
        arguments: <String, Object?>{
          'category': alulaGettingStartedWalkthroughId,
          'step': 'quick-open',
        },
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walkthrough-current-quick-open')),
          findsOneWidget);

      final semantics = tester.ensureSemantics();
      final checkbox = tester.getSemantics(
        find.byKey(const ValueKey('walkthrough-checkbox-semantics-quick-open')),
      );
      expect(
        checkbox.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      semantics.dispose();

      await commands!.execute(
        'welcome.markStepComplete',
        arguments: 'quick-open',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('walkthrough-complete-quick-open')))
            .value,
        isTrue,
      );

      final picker = commands!.execute('welcome.showAllWalkthroughs');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qi-开始使用 Alula Code')));
      await picker;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walkthrough-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('walkthrough-current-create-edit-file')),
          findsOneWidget);
    } finally {
      await _unmount(tester);
    }
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required LayoutStore layoutStore,
  required SessionStore sessionStore,
  required KeybindingsStore keybindingsStore,
  required void Function(CommandService) onCommands,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: WorkbenchPage(
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: keybindingsStore,
      onCommandServiceReady: onCommands,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
