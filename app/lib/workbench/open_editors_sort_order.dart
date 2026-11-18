/// The two Open Editors policies supported by the P05 workbench adapter.
enum OpenEditorsSortOrder {
  editorOrder,
  fullPath;

  /// Unknown persisted values use the original editor order.
  static OpenEditorsSortOrder parse(Object? value) =>
      value == 'fullPath' ? fullPath : editorOrder;
}

/// Returns a new list; document identities and the input order are untouched.
///
/// Full-path ordering follows Code-OSS 4bda's extUriIgnorePathCase comparison:
/// lowercase the decoded path, serialize the URI, then compare UTF-16 units.
/// Resource-less and malformed entries retain their original relative order
/// before non-file resources, then file resources. Sorting those first entries
/// by name needs the upstream Intl collator and is deliberately deferred.
///
/// [uriOf] supplies URI strings, not native filesystem paths. Unlike VS Code's
/// permissive URI.parse, missing schemes, invalid percent escapes/UTF-8 and raw
/// control characters are treated as malformed. Userinfo follows the reference's
/// first decoded `@` / first `:` splitting, not browser credential parsing; host
/// and port syntax is not validated. Ill-formed UTF-16 is outside this contract.
/// No locale/natural sort is used.
List<T> sortOpenEditors<T>(
  Iterable<T> docs,
  OpenEditorsSortOrder order, {
  required String? Function(T) uriOf,
}) {
  if (order == OpenEditorsSortOrder.editorOrder) return docs.toList();

  final entries = <({T doc, int index, int bucket, String key})>[];
  for (final doc in docs) {
    final resource = _resourceKey(uriOf(doc));
    entries.add((
      doc: doc,
      index: entries.length,
      bucket: resource?.bucket ?? 0,
      key: resource?.key ?? '',
    ));
  }
  entries.sort((a, b) {
    final bucket = a.bucket.compareTo(b.bucket);
    if (bucket != 0) return bucket;
    final key = a.key.compareTo(b.key);
    return key != 0 ? key : a.index.compareTo(b.index);
  });
  return [for (final entry in entries) entry.doc];
}

final _uriPattern = RegExp(
  r'^([A-Za-z][A-Za-z0-9+.-]*):(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#([\s\S]*))?$',
);
final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

({int bucket, String key})? _resourceKey(String? value) {
  if (value == null || _controlCharacters.hasMatch(value)) return null;
  final match = _uriPattern.firstMatch(value);
  if (match == null) return null;
  try {
    final scheme = match[1]!;
    var authority = _decode(match[2] ?? '');
    var path = _decode(match[3]!).toLowerCase();
    final query = _decode(match[4] ?? '');
    final fragment = _decode(match[5] ?? '');
    // URI._referenceResolution and _validateUri (no dot-segment normalization).
    if (scheme == 'file' || scheme == 'http' || scheme == 'https') {
      if (!path.startsWith('/')) path = '/$path';
    }
    if ((authority.isNotEmpty && path.isNotEmpty && !path.startsWith('/')) ||
        (authority.isEmpty && path.startsWith('//'))) {
      return null;
    }

    // uri.ts:541–603 / 666–734, pinned Code-OSS 4bda. Preserve scheme
    // casing; encode user/password separately; lowercase only the host part
    // of authority; preserve the final colon suffix as the reference does.
    final key = StringBuffer('$scheme:');
    if (authority.isNotEmpty || scheme == 'file') key.write('//');
    if (authority.isNotEmpty) {
      final at = authority.indexOf('@');
      if (at != -1) {
        final userinfo = authority.substring(0, at);
        authority = authority.substring(at + 1);
        final colon = userinfo.indexOf(':');
        if (colon == -1) {
          key.write(_encode(userinfo));
        } else {
          key
            ..write(_encode(userinfo.substring(0, colon)))
            ..write(':')
            ..write(_encode(userinfo.substring(colon + 1)));
        }
        key.write('@');
      }
      authority = authority.toLowerCase();
      final colon = authority.lastIndexOf(':');
      if (colon == -1) {
        key.write(_encode(authority, authority: true));
      } else {
        key
          ..write(_encode(authority.substring(0, colon), authority: true))
          ..write(authority.substring(colon));
      }
    }
    key.write(_encode(path, path: true));
    if (query.isNotEmpty) key.write('?${_encode(query)}');
    if (fragment.isNotEmpty) key.write('#${_encode(fragment)}');
    return (bucket: scheme == 'file' ? 2 : 1, key: key.toString());
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

final _percentRuns = RegExp(r'(?:%[0-9A-Fa-f]{2})+');

String _decode(String value) {
  final decoded = StringBuffer();
  var end = 0;
  for (final match in _percentRuns.allMatches(value)) {
    final literal = value.substring(end, match.start);
    if (literal.contains('%')) throw const FormatException('Invalid escape');
    decoded
      ..write(literal)
      ..write(Uri.decodeComponent(match[0]!));
    end = match.end;
  }
  final literal = value.substring(end);
  if (literal.contains('%')) throw const FormatException('Invalid escape');
  return (decoded..write(literal)).toString();
}

String _encode(String value, {bool path = false, bool authority = false}) {
  // Dart's encodeComponent leaves these five characters unescaped; the pinned
  // encodeURIComponentFast table escapes them, using uppercase hexadecimal.
  var encoded = Uri.encodeComponent(value)
      .replaceAll('!', '%21')
      .replaceAll("'", '%27')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll('*', '%2A');
  if (path) encoded = encoded.replaceAll('%2F', '/');
  if (authority) {
    encoded = encoded
        .replaceAll('%5B', '[')
        .replaceAll('%5D', ']')
        .replaceAll('%3A', ':');
  }
  return encoded;
}
