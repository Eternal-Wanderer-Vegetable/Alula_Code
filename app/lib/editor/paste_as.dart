import 'dart:io';

/// Limits applied before clipboard-derived values are offered to providers.
const int maxPasteAsHtmlUtf16 = 64 * 1024;
const int maxPasteAsUriListUtf16 = 64 * 1024;
const int maxPasteAsUriCount = 100;
const int maxPasteAsUriUtf16 = 8192;
const int maxPasteAsPlainTextUtf16 = 1024 * 1024;

class PasteAsConfiguration {
  const PasteAsConfiguration({
    this.enabled = true,
    this.showPasteSelector = 'afterPaste',
    this.preferences = const [],
  });

  final bool enabled;
  final String showPasteSelector;
  final List<String> preferences;

  factory PasteAsConfiguration.fromSettings(Map<String, Object?> settings) {
    final rawPreferences = settings['editor.pasteAs.preferences'];
    final rawShowSelector = settings['editor.pasteAs.showPasteSelector'];
    return PasteAsConfiguration(
      enabled: settings['editor.pasteAs.enabled'] is bool
          ? settings['editor.pasteAs.enabled']! as bool
          : true,
      showPasteSelector: rawShowSelector is String &&
              const {'afterPaste', 'never'}.contains(rawShowSelector)
          ? rawShowSelector
          : 'afterPaste',
      preferences: rawPreferences is List
          ? rawPreferences
              .whereType<String>()
              .where((preference) => preference.length <= 128)
              .take(16)
              .toList(growable: false)
          : const [],
    );
  }
}

class PasteAsOption {
  const PasteAsOption({
    required this.id,
    required this.kind,
    required this.label,
    required this.text,
  });

  final String id;
  final String kind;
  final String label;
  final String text;
}

/// Produces bounded built-in Paste As edits from clipboard MIME snapshots.
/// The provider kinds match the pinned Code-OSS defaults. Preferences are
/// hierarchical kinds; unmatched providers keep their built-in order.
List<PasteAsOption> buildPasteAsOptions({
  required String? plainText,
  required String? html,
  required String? uriList,
  required String? workspaceRoot,
  List<String> preferences = const [],
}) {
  final options = <PasteAsOption>[];
  final uris = parsePasteAsUriList(uriList);
  if (uris.isNotEmpty) {
    final fileUriCount = uris.where((uri) => uri.scheme == 'file').length;
    final genericUriCount = uris.length - fileUriCount;
    options.add(PasteAsOption(
      id: 'uri',
      kind: 'uri.path.absolute',
      label: genericUriCount > 0
          ? (uris.length > 1 ? 'Insert URIs' : 'Insert URI')
          : (uris.length > 1 ? 'Insert Paths' : 'Insert Path'),
      text: uris.map(_absoluteUriText).join(' '),
    ));
    final relative = _relativeUris(uris, workspaceRoot);
    if (relative != null && relative.isNotEmpty) {
      options.add(PasteAsOption(
        id: 'relativeUri',
        kind: 'uri.path.relative',
        label: relative.length > 1
            ? 'Insert Relative Paths'
            : 'Insert Relative Path',
        text: relative.join(' '),
      ));
    }
  } else if (plainText != null &&
      plainText.length <= maxPasteAsPlainTextUtf16) {
    options.add(PasteAsOption(
      id: 'text',
      kind: 'text.plain',
      label: 'Insert Plain Text',
      text: plainText,
    ));
  }

  // The HTML provider is only eligible for an explicit Paste As command.
  if (html != null && html.isNotEmpty && html.length <= maxPasteAsHtmlUtf16) {
    options.add(PasteAsOption(
      id: 'html',
      kind: 'html',
      label: 'Insert HTML',
      text: html,
    ));
  }

  const defaultOrder = ['text', 'uri', 'relativeUri', 'html'];
  final preferenceOrder = preferences.take(16).toList(growable: false);
  int preferenceIndex(PasteAsOption option) {
    for (var index = 0; index < preferenceOrder.length; index++) {
      final preference = preferenceOrder[index];
      if (option.kind == preference || option.kind.startsWith('$preference.')) {
        return index;
      }
    }
    return preferenceOrder.length;
  }

  final ordered = options.toList()
    ..sort((a, b) {
      final byPreference = preferenceIndex(a).compareTo(preferenceIndex(b));
      if (byPreference != 0) return byPreference;
      return defaultOrder.indexOf(a.id).compareTo(defaultOrder.indexOf(b.id));
    });
  return List.unmodifiable(ordered);
}

List<Uri> parsePasteAsUriList(String? value) {
  if (value == null || value.length > maxPasteAsUriListUtf16) {
    return const [];
  }
  final result = <Uri>[];
  for (final line in value.split(RegExp(r'\r?\n'))) {
    final candidate = line.trim();
    if (candidate.isEmpty || candidate.startsWith('#')) continue;
    if (candidate.length > maxPasteAsUriUtf16) return const [];
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme) return const [];
    result.add(uri);
    if (result.length > maxPasteAsUriCount) return const [];
  }
  return List.unmodifiable(result);
}

String _absoluteUriText(Uri uri) {
  if (uri.scheme != 'file') return uri.toString();
  try {
    return uri.toFilePath(windows: Platform.isWindows);
  } on Object {
    return uri.toString();
  }
}

List<String>? _relativeUris(List<Uri> uris, String? workspaceRoot) {
  if (workspaceRoot == null || workspaceRoot.isEmpty) return null;
  final normalizedRoot = _normalizePath(Directory(workspaceRoot).absolute.path);
  final rootPrefix =
      normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
  final comparableRoot =
      Platform.isWindows ? rootPrefix.toLowerCase() : rootPrefix;
  final result = <String>[];
  for (final uri in uris) {
    if (uri.scheme != 'file') continue;
    late final String path;
    try {
      path = _normalizePath(uri.toFilePath(windows: Platform.isWindows));
    } on Object {
      continue;
    }
    final comparablePath = Platform.isWindows ? path.toLowerCase() : path;
    if (!comparablePath.startsWith(comparableRoot)) continue;
    result.add(path.substring(rootPrefix.length));
  }
  return result;
}

String _normalizePath(String path) => path.replaceAll('\\', '/');
