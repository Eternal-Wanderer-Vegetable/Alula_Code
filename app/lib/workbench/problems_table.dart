import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

class ProblemsTable extends StatelessWidget {
  const ProblemsTable({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('problems-table'),
      role: SemanticsRole.table,
      container: true,
      explicitChildNodes: true,
      label: '诊断表格',
      child: Column(
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SizedBox(
              height: 28,
              child: ProblemsTableLine(
                header: true,
                severity: Semantics(label: '严重级别', child: const SizedBox()),
                code: const Text('代码'),
                message: const Text('消息'),
                file: const Text('文件'),
                source: const Text('来源'),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class ProblemsTableLine extends StatelessWidget {
  const ProblemsTableLine({
    super.key,
    this.header = false,
    required this.severity,
    required this.code,
    required this.message,
    required this.file,
    required this.source,
  });

  final bool header;
  final Widget severity;
  final Widget code;
  final Widget message;
  final Widget file;
  final Widget source;

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child) {
      return Semantics(
        role: header ? SemanticsRole.columnHeader : SemanticsRole.cell,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        ),
      );
    }

    return Semantics(
      role: SemanticsRole.row,
      container: true,
      explicitChildNodes: true,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: Row(
          children: [
            SizedBox(width: 36, child: Center(child: cell(severity))),
            Expanded(child: cell(code)),
            Expanded(flex: 4, child: cell(message)),
            Expanded(flex: 2, child: cell(file)),
            Expanded(child: cell(source)),
          ],
        ),
      ),
    );
  }
}
