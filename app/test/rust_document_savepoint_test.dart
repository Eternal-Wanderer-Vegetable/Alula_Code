import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _CoreBootstrap();

void main() {
  test('Rust savepoint detects edits, exact revert, and restored baseline', () {
    final doc = _bootstrap.core!.openDoc(9712, '甲🦊\r\n');
    try {
      expect(doc.isDirty, isFalse);
      expect(doc.savepointMatches('甲🦊\r\n'), isTrue);

      doc.apply([const TextOp.insert(5, 'x')]);
      expect(doc.isDirty, isTrue);
      expect(doc.savepointMatches('甲🦊\r\n'), isTrue);

      doc.apply([const TextOp.delete(5, 1)]);
      expect(doc.isDirty, isFalse);

      doc.apply([const TextOp.insert(5, 'x')]);
      final dirtyVersion = doc.version;
      doc.setSavepoint('disk 🦊\r\n');
      expect(doc.version, dirtyVersion);
      expect(doc.isDirty, isTrue);
      expect(doc.savepointMatches('disk 🦊\r\n'), isTrue);
      expect(doc.savepointMatches('disk 🦊\n'), isFalse);

      doc.markSaved();
      expect(doc.version, dirtyVersion);
      expect(doc.isDirty, isFalse);
      expect(doc.savepointMatches(doc.resync().content), isTrue);
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);
}
