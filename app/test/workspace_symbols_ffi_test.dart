import 'dart:async';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ABI41 workspace symbols preserve ranges and cancel through real FFI',
      () async {
    final core = AlulaCore.load();
    expect(core.abiVersion, 41);
    final root =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-ffi');
    final executable = p.join(
        Directory.current.parent.path,
        'target',
        'debug',
        Platform.isWindows
            ? 'async_completion_fake_lsp.exe'
            : 'async_completion_fake_lsp');
    expect(File(executable).existsSync(), isTrue,
        reason: 'cargo test --workspace builds the fixture before Flutter');
    final doc = core.openDoc(98761, '😀\r\nsource');
    addTearDown(() {
      core.lsp.shutdownWorkspace(root.path);
      doc.close();
      root.deleteSync(recursive: true);
    });
    core.lsp.start(
        doc.id, root.path, [executable, '${root.path}/trace.log', '100']);
    final result = await core.lsp.workspaceSymbols(doc.id, 'workspace');
    expect(result, hasLength(1));
    expect(result!.single['name'], '😀workspace_target');
    expect(result.single['line'], 1);
    expect(result.single['character'], 3);
    expect(result.single['endLine'], 1);
    expect(result.single['endCharacter'], 9);
    final cancellation = Completer<void>();
    final pending = core.lsp
        .workspaceSymbols(doc.id, 'slow', cancelSignal: cancellation.future);
    cancellation.complete();
    expect(await pending, isNull);
    expect(doc.resync().content, '😀\r\nsource');
  });
}
