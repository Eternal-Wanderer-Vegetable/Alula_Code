import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/walkthrough.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late String journalPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_walkthrough');
    journalPath = '${temp.path.replaceAll(r'\', '/')}/progress.json';
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('progress round trips, ignores unknown IDs, and reset persists empty',
      () {
    final store = WalkthroughProgressStore(path: journalPath);
    expect(store.setCompleted('open-folder', true), isTrue);
    expect(store.save(<String>{'command-palette', 'future-step'}), isTrue);
    expect(
      WalkthroughProgressStore(path: journalPath).load(),
      <String>{'command-palette'},
    );

    expect(store.reset(), isTrue);
    expect(WalkthroughProgressStore(path: journalPath).load(), isEmpty);
  });

  test('corrupt, unknown-version, and oversized journals load empty', () {
    final file = File(journalPath);
    final store = WalkthroughProgressStore(path: journalPath);
    file.writeAsStringSync('{broken');
    expect(store.load(), isEmpty);

    expect(store.setCompleted('create-edit-file', true), isTrue);
    final envelope = jsonDecode(file.readAsStringSync()) as Map;
    envelope['version'] = 99;
    file.writeAsStringSync(jsonEncode(envelope));
    expect(store.load(), isEmpty);

    file.writeAsStringSync(
      'x' * (maxWalkthroughProgressJournalBytes + 1),
    );
    expect(store.load(), isEmpty);
  });
}
