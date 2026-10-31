import 'dart:io';

import 'package:alula_app/workbench/session_store.dart';

void main(List<String> args) {
  if (args.length != 1) exit(64);
  final store = SessionStore(
    path: args.single,
    afterTemporaryJournalFlushed: () {
      stdout.writeln('SESSION_TEMP_FLUSHED');
      stdout.flush();
      stdin.readLineSync();
    },
  );
  if (!store.save({'v': 1, 'value': 'written by child process'})) {
    stderr.writeln(store.lastSaveError);
    exit(1);
  }
}
