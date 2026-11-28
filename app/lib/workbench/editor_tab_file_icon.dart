import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorTabFileIconData {
  const EditorTabFileIconData({
    required this.definitionId,
    required this.glyph,
    required this.color,
  });

  final String definitionId;
  final String glyph;
  final Color color;
}

/// The pinned Code-OSS Seti associations used by the default tab icon theme.
class EditorTabFileIconTheme {
  EditorTabFileIconTheme._({
    required Map<String, String> fileNames,
    required Map<String, String> fileExtensions,
    required Map<String, String> languageIds,
    required Map<String, EditorTabFileIconData> icons,
    required EditorTabFileIconData defaultIcon,
  })  : _fileNames = fileNames,
        _fileExtensions = fileExtensions,
        _languageIds = languageIds,
        _icons = icons,
        _defaultIcon = defaultIcon,
        _extensionsLongestFirst = fileExtensions.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));

  final Map<String, String> _fileNames;
  final Map<String, String> _fileExtensions;
  final Map<String, String> _languageIds;
  final Map<String, EditorTabFileIconData> _icons;
  final EditorTabFileIconData _defaultIcon;
  final List<String> _extensionsLongestFirst;

  static Future<EditorTabFileIconTheme>? _cached;

  static Future<EditorTabFileIconTheme> load() => _cached ??= rootBundle
      .loadString('assets/seti/vs-seti-icon-theme.json')
      .then(EditorTabFileIconTheme.fromJson);

  factory EditorTabFileIconTheme.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Seti icon theme must be a JSON object');
    }
    final file = decoded['file'];
    final iconDefinitions = decoded['iconDefinitions'];
    if (file is! String || iconDefinitions is! Map) {
      throw const FormatException('Seti icon theme is missing file icons');
    }

    final icons = <String, EditorTabFileIconData>{};
    for (final entry in iconDefinitions.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final definition = entry.value as Map;
      final character = definition['fontCharacter'];
      final color = definition['fontColor'];
      if (character is! String || color is! String) continue;
      final codePointText = character.replaceAll('\\', '');
      final codePoint = int.tryParse(codePointText, radix: 16);
      if (codePoint == null) continue;
      icons[entry.key as String] = EditorTabFileIconData(
        definitionId: entry.key as String,
        glyph: String.fromCharCode(codePoint),
        color: _parseColor(color),
      );
    }

    final defaultIcon = icons[file];
    if (defaultIcon == null) {
      throw FormatException('Seti default icon "$file" is not defined');
    }
    return EditorTabFileIconTheme._(
      fileNames: _readStringMap(decoded['fileNames']),
      fileExtensions: _readStringMap(decoded['fileExtensions']),
      languageIds: _readStringMap(decoded['languageIds']),
      icons: Map.unmodifiable(icons),
      defaultIcon: defaultIcon,
    );
  }

  EditorTabFileIconData lookup({
    required String fileName,
    String? languageId,
  }) {
    final basename = fileName.split(RegExp(r'[/\\]')).last.toLowerCase();
    final specialFile = _fileNames[basename];
    if (specialFile != null) return _icons[specialFile] ?? _defaultIcon;

    for (final extension in _extensionsLongestFirst) {
      if (basename == extension || basename.endsWith('.$extension')) {
        final icon = _icons[_fileExtensions[extension]];
        if (icon != null) return icon;
        break;
      }
    }

    final languageIcon = languageId == null
        ? null
        : _icons[_languageIds[languageId.toLowerCase()]];
    return languageIcon ?? _defaultIcon;
  }

  static Map<String, String> _readStringMap(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          (entry.key as String).toLowerCase(): entry.value as String,
    });
  }

  static Color _parseColor(String value) {
    final hex = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.parse(hex, radix: 16);
    return Color(switch (hex.length) {
      6 => 0xff000000 | parsed,
      8 => parsed,
      _ => throw FormatException('Invalid Seti icon color "$value"'),
    });
  }
}

/// Decorative icon with a stable leading slot so async theme loading never
/// shifts the tab label or changes tab width.
class EditorTabFileIcon extends StatelessWidget {
  const EditorTabFileIcon({
    required this.fileName,
    this.languageId,
    super.key,
  });

  static const double slotWidth = 22;

  final String fileName;
  final String? languageId;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: SizedBox(
            width: slotWidth,
            height: 16,
            child: FutureBuilder<EditorTabFileIconTheme>(
              future: EditorTabFileIconTheme.load(),
              builder: (context, snapshot) {
                final theme = snapshot.data;
                if (theme == null) return const SizedBox.shrink();
                final icon = theme.lookup(
                  fileName: fileName,
                  languageId: languageId,
                );
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    icon.glyph,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'AlulaSeti',
                      fontSize: 16,
                      height: 1,
                      color: icon.color,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}
