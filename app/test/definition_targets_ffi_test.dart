import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('definition FFI preserves provider order and UTF-16 selection ranges',
      () async {
    final core = AlulaCore.load();
    expect(core.abiVersion, expectedAbiVersion);
    final root = Directory.systemTemp.createTempSync('alula-definition-ffi');
    final executable = p.join(
      Directory.current.parent.path,
      'target',
      'debug',
      Platform.isWindows
          ? 'async_completion_fake_lsp.exe'
          : 'async_completion_fake_lsp',
    );
    const source = '\uFEFF😀\r\nsource';
    final file = File(p.join(root.path, 'source.rs'))
      ..writeAsStringSync(source);
    final disk = file.readAsBytesSync();
    final doc = core.openDoc(98762, source);
    addTearDown(() {
      core.lsp.shutdownWorkspace(root.path);
      doc.close();
      root.deleteSync(recursive: true);
    });
    expect(File(executable).existsSync(), isTrue);
    core.lsp.setUri(doc.id, file.uri.toString());
    core.lsp.start(
        doc.id, root.path, [executable, '${root.path}/trace.log', '100']);
    core.lsp.didOpen(doc.id);
    final result = await core.lsp.definition(doc.id, 5);
    expect(result, isNotNull);
    expect(result!.version, doc.version);
    expect(result.uri, 'file:///workspace/target.rs');
    expect(
      result.targets.map((target) => (
            target.uri,
            target.line,
            target.character,
            target.endLine,
            target.endCharacter,
          )),
      [
        ('file:///workspace/target.rs', 1, 3, 1, 9),
        ('file:///workspace/other.rs', 3, 5, 3, 11),
      ],
    );
    expect(doc.resync().content, source);
    expect(file.readAsBytesSync(), disk);
  });
}
