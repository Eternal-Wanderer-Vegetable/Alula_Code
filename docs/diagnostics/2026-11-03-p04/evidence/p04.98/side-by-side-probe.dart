import 'dart:io';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_side_by_side.dart';
import 'package:alula_app/git/git_diff_word_highlights.dart';

Future<void> main(List<String> args) async {
  const count = 8191;
  final withSideBySide = args.single == 'side-by-side';
  final patchText = StringBuffer()
    ..writeln('diff --git a/probe.txt b/probe.txt')
    ..writeln('@@ -1,$count +1,$count @@');
  for (var index = 0; index < count; index++) {
    patchText.writeln('-old-$index');
  }
  for (var index = 0; index < count; index++) {
    patchText.writeln('+new-$index');
  }
  final parsed = parseGitDiffPatch(patchText.toString());
  final wordChanges = computeGitDiffPatchWordChanges(parsed);
  final projection = withSideBySide
      ? computeGitDiffSideBySideRows(parsed)
      : null;
  stdout.writeln(
    'sideBySide=$withSideBySide patchRows=${parsed.lines.length} '
    'wordPairs=${wordChanges.pairedCount} '
    'projectedRows=${projection?.rows.length ?? 0}',
  );
  await Future<void>.delayed(const Duration(seconds: 10));
  if (parsed.lines.length != count * 2 + 2 ||
      (projection != null && !projection.canRender)) {
    exitCode = 1;
  }
}
