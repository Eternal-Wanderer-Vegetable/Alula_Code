import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DiagnosticNavigationPeek extends StatelessWidget {
  const DiagnosticNavigationPeek({
    super.key,
    required this.fileName,
    required this.ordinal,
    required this.total,
    required this.severity,
    required this.message,
    required this.onClose,
    this.source,
    this.code,
    this.isStale = false,
    this.reservedHeightInEditorLines,
  });

  final String fileName;
  final int ordinal;
  final int total;
  final int severity;
  final String message;
  final VoidCallback onClose;
  final String? source;
  final String? code;
  final bool isStale;
  final int? reservedHeightInEditorLines;

  static final _lineBreak = RegExp(r'\r\n|\r|\n');

  int get preferredHeightInEditorLines =>
      reservedHeightInEditorLines ?? _preferredHeightForMessage(message);

  static int _preferredHeightForMessage(String message) =>
      4 + _lineBreak.allMatches(message).take(16).length;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, severityAccent, severityLabel) = switch (severity) {
      1 => (Icons.error_outline, colors.error, '错误'),
      2 => (Icons.warning_amber_outlined, colors.tertiary, '警告'),
      _ => (Icons.info_outline, colors.primary, '信息'),
    };
    final accent = isStale ? colors.outline : severityAccent;
    final origin = [
      if (source case final String text when text.isNotEmpty) text,
      if (code case final String text when text.isNotEmpty) text,
    ].join(' · ');
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${isStale ? '已过期，' : ''}$severityLabel，$fileName，第 $ordinal / $total 条诊断',
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                        isStale
                            ? '已过期 · $ordinal / $total'
                            : '$ordinal / $total',
                        style: TextStyle(color: colors.onSurfaceVariant)),
                    IconButton(
                      tooltip: '关闭诊断详情',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(message, key: const ValueKey('diagnostic-peek-message')),
                if (origin.isNotEmpty)
                  Text(origin,
                      style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DiagnosticNavigationSnapshot {
  DiagnosticNavigationSnapshot(
    Map<String, Object?> diagnostic, {
    ({int line, int character})? anchor,
  }) : this._(diagnostic, false, _heightFor(diagnostic), anchor);

  const DiagnosticNavigationSnapshot._(
    this.diagnostic,
    this.isStale,
    this.heightInEditorLines,
    this._anchor,
  );

  final Map<String, Object?> diagnostic;
  final bool isStale;
  final int heightInEditorLines;
  final ({int line, int character})? _anchor;

  static const _identityFields = [
    '_documentId',
    'documentVersion',
    'severity',
    'source',
    'code',
  ];
  static const _rangeFields = [
    'line',
    'character',
    'endLine',
    'endCharacter',
  ];

  static int _heightFor(Map<String, Object?> diagnostic) =>
      DiagnosticNavigationPeek._preferredHeightForMessage(
        diagnostic['message'] as String? ?? '',
      );

  bool _coversAnchor(Map<String, Object?> entry) {
    final anchor = _anchor;
    if (anchor == null) return false;
    final line = entry['line'];
    final character = entry['character'];
    final endLine = entry['endLine'];
    final endCharacter = entry['endCharacter'];
    if (line is! int ||
        character is! int ||
        endLine is! int ||
        endCharacter is! int ||
        line < 0 ||
        character < 0 ||
        endCharacter < 0) {
      return false;
    }
    final startsBeforeAnchor = line < anchor.line ||
        (line == anchor.line && character <= anchor.character);
    final endsAfterAnchor = endLine > anchor.line ||
        (endLine == anchor.line && endCharacter >= anchor.character);
    return startsBeforeAnchor && endsAfterAnchor;
  }

  DiagnosticNavigationSnapshot reconcile(
    Iterable<Map<String, Object?>> diagnostics,
  ) {
    Map<String, Object?>? replacement;
    var replacementMatchesRange = false;
    var ambiguous = false;
    for (final entry in diagnostics) {
      if (mapEquals(entry, diagnostic)) {
        return isStale
            ? DiagnosticNavigationSnapshot._(
                entry, false, heightInEditorLines, _anchor)
            : this;
      }
      if (!_identityFields.every((key) => entry[key] == diagnostic[key])) {
        continue;
      }
      final sameRange =
          _rangeFields.every((key) => entry[key] == diagnostic[key]);
      if (!sameRange && (replacementMatchesRange || !_coversAnchor(entry))) {
        continue;
      }
      if (replacement == null || (sameRange && !replacementMatchesRange)) {
        replacement = entry;
        replacementMatchesRange = sameRange;
        ambiguous = false;
      } else if (!mapEquals(replacement, entry)) {
        ambiguous = true;
      }
    }
    if (replacement != null && !ambiguous) {
      return DiagnosticNavigationSnapshot._(
        replacement,
        false,
        heightInEditorLines,
        _anchor,
      );
    }
    return isStale
        ? this
        : DiagnosticNavigationSnapshot._(
            diagnostic,
            true,
            _heightFor(diagnostic),
            _anchor,
          );
  }
}
