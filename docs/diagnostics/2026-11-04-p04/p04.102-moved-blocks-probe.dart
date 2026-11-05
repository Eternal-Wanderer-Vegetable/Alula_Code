import 'dart:async';
import 'dart:io';

import '../../../app/lib/git/git_diff_moved_blocks.dart';
import '../../../app/lib/git/git_diff_patch.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      (args.single != 'baseline' && args.single != 'model')) {
    stderr.writeln(
      'usage: dart p04.102-moved-blocks-probe.dart baseline|model',
    );
    exitCode = 2;
    return;
  }

  const lineCount = 8188;
  const payloadLength = 95;
  final payload = List<String>.filled(payloadLength, 'x').join();
  final lines = List<String>.generate(
    lineCount,
    (index) => 'final moved_${index.toString().padLeft(5, '0')} = "$payload";',
    growable: false,
  );
  final patch = [
    'diff --git a/lib/probe.dart b/lib/probe.dart',
    'index 1111111..2222222 100644',
    '--- a/lib/probe.dart',
    '+++ b/lib/probe.dart',
    '@@ -1,$lineCount +0,0 @@',
    ...lines.map((line) => '-$line'),
    '@@ -10000,0 +1,$lineCount @@',
    ...lines.map((line) => '+$line'),
  ].join('\n');

  final mode = args.single;
  if (mode == 'baseline') {
    final parsed = parseGitDiffPatch(patch);
    if (!parsed.canRender || parsed.lines.length != 16382) {
      throw StateError('baseline fixture did not parse within its row budget');
    }
    stdout.writeln(
      'baseline rows=${parsed.lines.length} input=${patch.length}',
    );
  } else {
    final result = computeGitDiffMovedBlocks(patch);
    if (!result.canAnalyze || result.blocks.length != 1) {
      throw StateError(
        'candidate fixture expected one move, got ${result.blocks.length} '
        '(${result.fallbackReason})',
      );
    }
    stdout.writeln(
      'candidate rows=16382 input=${patch.length} moves=${result.blocks.length}',
    );
  }

  await Future<void>.delayed(const Duration(seconds: 60));
}
