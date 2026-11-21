import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String nativeTestPath(String path) => p.normalize(p.absolute(path));

String workbenchFileUri(String path) {
  final normalized = nativeTestPath(path).replaceAll(r'\', '/');
  final uriPath = normalized.startsWith(RegExp(r'[A-Za-z]:/'))
      ? '${normalized[0].toLowerCase()}${normalized.substring(1)}'
      : normalized;
  return 'file:///$uriPath';
}

Finder explorerFileNode(String path) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      if (key is! ValueKey<String> || !key.value.startsWith('explorer-node:')) {
        return false;
      }
      return nativeTestPath(key.value.substring('explorer-node:'.length)) ==
          nativeTestPath(path);
    });
