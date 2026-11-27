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
  });

  final String fileName;
  final int ordinal;
  final int total;
  final int severity;
  final String message;
  final VoidCallback onClose;
  final String? source;
  final String? code;

  static final _lineBreak = RegExp(r'\r\n|\r|\n');

  int get preferredHeightInEditorLines =>
      4 + _lineBreak.allMatches(message).take(16).length;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, accent, severityLabel) = switch (severity) {
      1 => (Icons.error_outline, colors.error, '错误'),
      2 => (Icons.warning_amber_outlined, colors.tertiary, '警告'),
      _ => (Icons.info_outline, colors.primary, '信息'),
    };
    final origin = [
      if (source case final String text when text.isNotEmpty) text,
      if (code case final String text when text.isNotEmpty) text,
    ].join(' · ');
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$severityLabel，$fileName，第 $ordinal / $total 条诊断',
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
                    Text('$ordinal / $total',
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
