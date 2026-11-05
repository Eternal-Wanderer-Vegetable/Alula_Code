import '../workbench/commands.dart';
import 'git_diff_navigation.dart';

const gitDiffViewActiveContextKey = 'gitDiffViewActive';
const gitDiffNavigationAvailableContextKey = 'gitDiffNavigationAvailable';
const gitDiffNavigationCommandWhen =
    '$gitDiffViewActiveContextKey && $gitDiffNavigationAvailableContextKey';

/// Registers the pinned Code-OSS F1 diff-navigation actions for the workbench.
void registerGitDiffNavigationCommands(
  CommandService commands,
  GitDiffPatchNavigationController navigation,
) {
  commands
    ..register(Command(
      id: 'editor.action.accessibleDiffViewer.next',
      category: '差异查看器',
      title: '转到下一处差异',
      shortcut: 'F7',
      when: gitDiffNavigationCommandWhen,
      run: () async {
        navigation.navigateNext();
      },
    ))
    ..register(Command(
      id: 'editor.action.accessibleDiffViewer.prev',
      category: '差异查看器',
      title: '转到上一处差异',
      shortcut: 'Shift+F7',
      when: gitDiffNavigationCommandWhen,
      run: () async {
        navigation.navigatePrevious();
      },
    ));
}
