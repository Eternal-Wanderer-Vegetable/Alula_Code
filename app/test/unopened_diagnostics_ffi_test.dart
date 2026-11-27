import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('unopened diagnostic transport keeps provider positions and version',
      () async {
    final core = AlulaCore.load();
    expect(core.abiVersion, 47);
    final root = Directory.systemTemp.createTempSync('alula-unopened-ffi');
    final executable = p.join(
      Directory.current.parent.path,
      'target',
      'debug',
      Platform.isWindows
          ? 'async_completion_fake_lsp.exe'
          : 'async_completion_fake_lsp',
    );
    expect(File(executable).existsSync(), isTrue);
    const source = '\ufeff😀\r\nsource';
    const open = 'file:///E:/fixture/m_open.rs';
    const before = 'file:///e:/fixture/a_unopened.rs';
    const after = 'file:///e:/fixture/z_unopened.rs';
    final doc = core.openDoc(987637, source);
    addTearDown(() {
      core.lsp.shutdownWorkspace(root.path);
      doc.close();
      root.deleteSync(recursive: true);
    });
    core.lsp.start(doc.id, root.path, [
      executable,
      p.join(root.path, 'requests.log'),
      '0',
      'unopened-diagnostics',
    ]);
    core.lsp.setUri(doc.id, open);
    core.lsp.didOpen(doc.id, languageId: 'rust');

    final timer = Stopwatch()..start();
    ({String uri, bool wrapped, Map<String, Object?> diagnostic})? next;
    do {
      next = core.lsp.nextUnopenedDiagnostic(
        doc.id,
        cursorUri: open,
        openUris: const [open],
      );
      if (next?.uri == after) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } while (timer.elapsed < const Duration(seconds: 3));
    expect(next, isNotNull);
    expect(next!.uri, after);
    expect(next.wrapped, isFalse);
    expect(next.diagnostic['message'], '😀 later marker');
    expect(next.diagnostic['line'], 1);
    expect(next.diagnostic['character'], 3);
    expect(next.diagnostic['endCharacter'], 9);
    expect(next.diagnostic['code'], 30);
    expect(next.diagnostic.containsKey('documentVersion'), isFalse);

    final prev = core.lsp.nextUnopenedDiagnostic(
      doc.id,
      cursorUri: open,
      openUris: const [open],
      forward: false,
    );
    expect(prev?.uri, before);
    expect(prev?.wrapped, isFalse);
    final wrapped = core.lsp.nextUnopenedDiagnostic(
      doc.id,
      cursorUri: after,
      openUris: const [open],
    );
    expect(wrapped?.uri, before);
    expect(wrapped?.wrapped, isTrue);
    expect(
        core.lsp.nextUnopenedDiagnostic(
          doc.id,
          cursorUri: null,
          openUris: const [before, open, after],
        ),
        isNull);
    expect(doc.resync().content, source);
    expect(doc.version, 1);
  });
}
