/// A document symbol with a UTF-16 offset and one-based, inclusive line range.
class DocumentSymbolNode {
  DocumentSymbolNode({
    required this.kind,
    required this.name,
    required this.startUtf16,
    required this.line,
    required this.endLine,
    List<DocumentSymbolNode> children = const [],
  }) : children = List.unmodifiable(children);

  final String kind;
  final String name;
  final int startUtf16;
  final int line;
  final int endLine;
  final List<DocumentSymbolNode> children;

  /// Length-prefixing the kind keeps IDs unambiguous even with ':' in names.
  String get id => '$startUtf16:${kind.length}:$kind:$name';
}

enum DocumentSymbolSort { position, name, kind }

/// Builds a tree without changing [raw]. Invalid rows are omitted.
///
/// More than 10,000 input rows throws [ArgumentError], including invalid rows.
/// A parent must precede its child in UTF-16 position and contain its inclusive
/// line range. Equal ranges and equal starts cannot establish parentage. When
/// several parents qualify, the latest preceding symbol wins.
List<DocumentSymbolNode> buildDocumentSymbolTree(
  List<Map<String, Object?>> raw,
) {
  if (raw.length > 10000) {
    throw ArgumentError.value(
      raw.length,
      'raw.length',
      'Document symbol input exceeds the 10000 row limit',
    );
  }
  final symbols = <DocumentSymbolNode>[];
  for (final row in raw) {
    final kind = row['kind'];
    final name = row['name'];
    final start = row['start_utf16'];
    final line = row['line'];
    final endLine = row['end_line'];
    if (kind is! String ||
        kind.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        start is! int ||
        start < 0 ||
        line is! int ||
        line < 1 ||
        endLine is! int ||
        endLine < line) {
      continue;
    }
    symbols.add(DocumentSymbolNode(
      kind: kind,
      name: name,
      startUtf16: start,
      line: line,
      endLine: endLine,
    ));
  }
  symbols.sort(_comparePosition);
  final childIndices = List.generate(symbols.length, (_) => <int>[]);
  final rootIndices = <int>[];
  for (var index = 0; index < symbols.length; index++) {
    final child = symbols[index];
    int? parentIndex;
    for (var previous = index - 1; previous >= 0; previous--) {
      final parent = symbols[previous];
      if (parent.startUtf16 < child.startUtf16 &&
          parent.line <= child.line &&
          parent.endLine >= child.endLine &&
          (parent.line != child.line || parent.endLine != child.endLine)) {
        parentIndex = previous;
        break;
      }
    }
    if (parentIndex == null) {
      rootIndices.add(index);
    } else {
      childIndices[parentIndex].add(index);
    }
  }
  // Construct from the leaves, avoiding recursion even at the input cap.
  final built = List<DocumentSymbolNode?>.filled(symbols.length, null);
  for (var index = symbols.length - 1; index >= 0; index--) {
    final symbol = symbols[index];
    built[index] = DocumentSymbolNode(
      kind: symbol.kind,
      name: symbol.name,
      startUtf16: symbol.startUtf16,
      line: symbol.line,
      endLine: symbol.endLine,
      children: [for (final child in childIndices[index]) built[child]!],
    );
  }
  return [for (final index in rootIndices) built[index]!];
}

/// Preorder display rows, sorting each sibling group independently.
///
/// A case-insensitive name substring query retains matches and their ancestors,
/// but no unrelated descendants. While querying, collapse state is ignored.
List<({DocumentSymbolNode symbol, int depth})> projectDocumentSymbols(
  List<DocumentSymbolNode> roots, {
  String query = '',
  DocumentSymbolSort sort = DocumentSymbolSort.position,
  Set<String> collapsed = const {},
}) {
  final needle = query.trim().toLowerCase();
  Set<DocumentSymbolNode>? included;
  if (needle.isNotEmpty) {
    included = <DocumentSymbolNode>{};
    final pending = <({DocumentSymbolNode symbol, DocumentSymbolNode? parent})>[
      for (final root in roots) (symbol: root, parent: null),
    ];
    final visited =
        <({DocumentSymbolNode symbol, DocumentSymbolNode? parent})>[];
    while (pending.isNotEmpty) {
      final entry = pending.removeLast();
      visited.add(entry);
      for (final child in entry.symbol.children) {
        pending.add((symbol: child, parent: entry.symbol));
      }
    }
    // Reverse preorder visits every descendant before its ancestors.
    for (final entry in visited.reversed) {
      if (entry.symbol.name.toLowerCase().contains(needle) ||
          included.contains(entry.symbol)) {
        included.add(entry.symbol);
        if (entry.parent != null) included.add(entry.parent!);
      }
    }
  }

  final output = <({DocumentSymbolNode symbol, int depth})>[];
  final pending = <({DocumentSymbolNode symbol, int depth})>[];
  void pushSiblings(List<DocumentSymbolNode> siblings, int depth) {
    final ordered = siblings.toList()..sort((a, b) => _compare(a, b, sort));
    for (final symbol in ordered.reversed) {
      if (included == null || included.contains(symbol)) {
        pending.add((symbol: symbol, depth: depth));
      }
    }
  }

  pushSiblings(roots, 0);
  while (pending.isNotEmpty) {
    final entry = pending.removeLast();
    output.add(entry);
    if (needle.isNotEmpty || !collapsed.contains(entry.symbol.id)) {
      pushSiblings(entry.symbol.children, entry.depth + 1);
    }
  }
  return output;
}

/// Returns the deepest symbol containing [line], independent of display state.
/// Ties at the same depth prefer the later UTF-16 start.
DocumentSymbolNode? documentSymbolAtLine(
  List<DocumentSymbolNode> roots,
  int line,
) {
  if (line < 1) return null;
  DocumentSymbolNode? found;
  var foundDepth = -1;
  final pending = <({DocumentSymbolNode symbol, int depth})>[
    for (final root in roots) (symbol: root, depth: 0),
  ];
  while (pending.isNotEmpty) {
    final entry = pending.removeLast();
    final symbol = entry.symbol;
    if (line < symbol.line || line > symbol.endLine) continue;
    if (entry.depth > foundDepth ||
        (entry.depth == foundDepth &&
            (found == null || symbol.startUtf16 > found.startUtf16))) {
      found = symbol;
      foundDepth = entry.depth;
    }
    for (final child in symbol.children) {
      pending.add((symbol: child, depth: entry.depth + 1));
    }
  }
  return found;
}

/// Returns the inclusive ancestor chain containing [line], from root to the
/// deepest symbol. Ties match [documentSymbolAtLine]: deeper nodes win, then
/// the later UTF-16 start at the same depth.
List<DocumentSymbolNode> documentSymbolPathAtLine(
  List<DocumentSymbolNode> roots,
  int line,
) {
  if (line < 1) return const [];
  final pending = <_SymbolPathEntry>[];
  for (final root in roots) {
    if (line >= root.line && line <= root.endLine) {
      pending.add(_SymbolPathEntry(root, 0, null));
    }
  }
  _SymbolPathEntry? found;
  while (pending.isNotEmpty) {
    final entry = pending.removeLast();
    final symbol = entry.symbol;
    if (found == null ||
        entry.depth > found.depth ||
        (entry.depth == found.depth &&
            symbol.startUtf16 > found.symbol.startUtf16)) {
      found = entry;
    }
    for (final child in symbol.children) {
      if (line >= child.line && line <= child.endLine) {
        pending.add(_SymbolPathEntry(child, entry.depth + 1, entry));
      }
    }
  }
  if (found == null) return const [];
  final path = <DocumentSymbolNode>[];
  _SymbolPathEntry? entry = found;
  while (entry != null) {
    path.add(entry.symbol);
    entry = entry.parent;
  }
  return path.reversed.toList(growable: false);
}

class _SymbolPathEntry {
  const _SymbolPathEntry(this.symbol, this.depth, this.parent);

  final DocumentSymbolNode symbol;
  final int depth;
  final _SymbolPathEntry? parent;
}

int _comparePosition(DocumentSymbolNode a, DocumentSymbolNode b) {
  var result = a.startUtf16.compareTo(b.startUtf16);
  if (result != 0) return result;
  result = a.line.compareTo(b.line);
  if (result != 0) return result;
  result = b.endLine.compareTo(a.endLine);
  if (result != 0) return result;
  result = a.kind.compareTo(b.kind);
  return result != 0 ? result : a.name.compareTo(b.name);
}

int _compare(
  DocumentSymbolNode a,
  DocumentSymbolNode b,
  DocumentSymbolSort sort,
) {
  if (sort == DocumentSymbolSort.kind) {
    final kind = a.kind.toLowerCase().compareTo(b.kind.toLowerCase());
    if (kind != 0) return kind;
  }
  if (sort != DocumentSymbolSort.position) {
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (name != 0) return name;
  }
  return _comparePosition(a, b);
}
