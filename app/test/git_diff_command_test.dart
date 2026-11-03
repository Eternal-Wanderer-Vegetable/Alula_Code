import 'package:alula_app/git/git_diff_commands.dart';
import 'package:alula_app/git/git_diff_navigation.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/quick_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _nextId = 'editor.action.accessibleDiffViewer.next';
const _previousId = 'editor.action.accessibleDiffViewer.prev';
const _nextTitle = '转到下一处差异';
const _previousTitle = '转到上一处差异';

void main() {
  testWidgets('Command Palette next/previous route once to inline navigation',
      (tester) async {
    final commands = CommandService();
    final navigation = GitDiffPatchNavigationController();
    commands.context.setValues({
      gitDiffViewActiveContextKey: true,
      gitDiffNavigationAvailableContextKey: false,
    });
    registerGitDiffNavigationCommands(commands, navigation);

    await tester.pumpWidget(_commandHarness(
      patch: _twoChangePatch(),
      commands: commands,
      navigation: navigation,
    ));
    await tester.pumpAndSettle();

    expect(navigation.canNavigate, isTrue);
    expect(commands.isVisible(_nextId), isTrue);
    expect(commands.isVisible(_previousId), isTrue);

    await _invokePaletteCommand(tester, _nextTitle);
    expect(find.text('1 / 2'), findsOneWidget);

    await _invokePaletteCommand(tester, _previousTitle);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    commands.dispose();
  });

  testWidgets('Command Palette navigation also uses side-by-side state',
      (tester) async {
    final commands = CommandService();
    final navigation = GitDiffPatchNavigationController();
    commands.context.setValues({
      gitDiffViewActiveContextKey: true,
      gitDiffNavigationAvailableContextKey: false,
    });
    registerGitDiffNavigationCommands(commands, navigation);

    await tester.pumpWidget(_commandHarness(
      patch: _twoChangePatch(),
      commands: commands,
      navigation: navigation,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('并排'));
    await tester.pumpAndSettle();

    await _invokePaletteCommand(tester, _nextTitle);

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('git-diff-side-by-side-rows')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    commands.dispose();
  });

  testWidgets('commands stay hidden for fallback patches and inactive views',
      (tester) async {
    final commands = CommandService();
    final navigation = GitDiffPatchNavigationController();
    commands.context.setValues({
      gitDiffViewActiveContextKey: true,
      gitDiffNavigationAvailableContextKey: false,
    });
    registerGitDiffNavigationCommands(commands, navigation);

    await tester.pumpWidget(_commandHarness(
      patch: 'diff --git a/image.png b/image.png\nGIT binary patch\n',
      commands: commands,
      navigation: navigation,
    ));
    await tester.pumpAndSettle();

    expect(navigation.canNavigate, isFalse);
    expect(commands.isVisible(_nextId), isFalse);
    await _openPaletteAndSearch(tester, '差异');
    expect(find.text('无匹配项'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    commands.context.setValue(gitDiffViewActiveContextKey, true);
    await tester.pumpWidget(_commandHarness(
      patch: _twoChangePatch(),
      commands: commands,
      navigation: navigation,
    ));
    await tester.pumpAndSettle();
    expect(navigation.canNavigate, isTrue);
    commands.context.setValue(gitDiffViewActiveContextKey, false);
    expect(commands.isVisible(_nextId), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    commands.dispose();
  });
}

Widget _commandHarness({
  required String patch,
  required CommandService commands,
  required GitDiffPatchNavigationController navigation,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SizedBox(
              width: 760,
              child: GitDiffPatchView(
                patch: patch,
                navigationController: navigation,
                onNavigationAvailabilityChanged: (_) {
                  commands.context.setValue(
                    gitDiffNavigationAvailableContextKey,
                    navigation.canNavigate,
                  );
                },
              ),
            ),
          ),
          Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-command-palette'),
              onPressed: () => QuickInput.show(
                context,
                hint: '输入命令名',
                items: [
                  for (final command in commands.all)
                    QuickItem(
                      label: command.label,
                      detail: command.shortcut,
                      commandId: command.id,
                    ),
                ],
                commands: commands,
              ),
              child: const Text('打开命令面板'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _invokePaletteCommand(WidgetTester tester, String title) async {
  await _openPaletteAndSearch(tester, title);
  await tester.tap(find.text('差异查看器: $title'));
  await tester.pumpAndSettle();
}

Future<void> _openPaletteAndSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byKey(const ValueKey('open-command-palette')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pumpAndSettle();
}

String _twoChangePatch() {
  final lines = <String>[
    'diff --git a/file.txt b/file.txt',
    '--- a/file.txt',
    '+++ b/file.txt',
    '@@ -1,24 +1,24 @@',
  ];
  for (var line = 1; line <= 24; line++) {
    if (line == 2 || line == 22) {
      lines
        ..add('-old line $line')
        ..add('+new line $line');
    } else {
      lines.add(' context $line');
    }
  }
  return '${lines.join('\n')}\n';
}
