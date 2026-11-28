/// 状态栏（docs/09 W1）：同步状态 / 详情 + 右侧语言服务信息 + 面板开关。
library;

import 'package:flutter/material.dart';

enum WbSyncState { idle, synced, mismatch, error }

class ProblemsStatusCounts {
  const ProblemsStatusCounts({
    this.errors = 0,
    this.warnings = 0,
    this.infos = 0,
  });

  factory ProblemsStatusCounts.fromDiagnostics(
    Iterable<Map<String, Object?>> diagnostics,
  ) {
    var errors = 0;
    var warnings = 0;
    var infos = 0;
    for (final diagnostic in diagnostics) {
      switch (diagnostic['severity']) {
        case 1:
          errors++;
        case 2:
          warnings++;
        case 3 || null:
          infos++;
      }
    }
    return ProblemsStatusCounts(errors: errors, warnings: warnings, infos: infos);
  }

  final int errors;
  final int warnings;
  final int infos;

  int get total => errors + warnings + infos;

  String get description {
    final parts = [
      if (errors > 0) '错误 $errors',
      if (warnings > 0) '警告 $warnings',
      if (infos > 0) '信息 $infos',
    ];
    return parts.isEmpty ? '没有问题' : parts.join('，');
  }
}

class AlulaStatusBar extends StatelessWidget {
  const AlulaStatusBar({
    super.key,
    required this.state,
    required this.detail,
    required this.lspStatus,
    required this.problems,
    this.onToggleProblems,
    required this.tabCount,
    required this.abiVersion,
    this.resourcePressure,
    this.availableBytes,
    this.totalBytes,
    this.resourceSource,
    required this.syncCount,
    required this.panelCollapsed,
    required this.onTogglePanel,
    this.lockedScrolling = false,
    this.onToggleLockedScrolling,
    this.encodingLabel,
    this.encodingTooltip,
    this.lineEndingLabel,
    this.onEncodingTap,
    this.onLineEndingTap,
    this.overtypeMode = false,
    this.onToggleOvertype,
    this.notificationButton,
    this.notificationAtStart = false,
  });

  final WbSyncState state;
  final String detail;
  final String lspStatus;
  final ProblemsStatusCounts problems;
  final VoidCallback? onToggleProblems;
  final int tabCount;
  final int abiVersion;
  final String? resourcePressure;
  final int? availableBytes;
  final int? totalBytes;
  final String? resourceSource;
  final int syncCount;
  final bool panelCollapsed;
  final VoidCallback onTogglePanel;
  final bool lockedScrolling;
  final VoidCallback? onToggleLockedScrolling;
  final String? encodingLabel;
  final String? encodingTooltip;
  final String? lineEndingLabel;
  final VoidCallback? onEncodingTap;
  final VoidCallback? onLineEndingTap;
  final bool overtypeMode;
  final VoidCallback? onToggleOvertype;

  final Widget? notificationButton;
  final bool notificationAtStart;

  @override
  Widget build(BuildContext context) {
    final combinedCount =
        onToggleProblems == null ? ' · 诊断 ${problems.total}' : '';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
      child: Row(
        children: [
          if (notificationButton != null && notificationAtStart) ...[
            notificationButton!,
            const SizedBox(width: 8),
          ],
          _stateIcon(),
          const SizedBox(width: 8),
          Expanded(child: Text(detail, style: const TextStyle(fontSize: 11))),
          Flexible(
            child: Text(
              '$lspStatus$combinedCount · 标签 $tabCount · '
              'ABI v$abiVersion · 同步 $syncCount 次',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ),
          if (onToggleProblems case final toggleProblems?) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: problems.description,
              child: Tooltip(
                message: problems.description,
                excludeFromSemantics: true,
                child: InkWell(
                  key: const ValueKey('status-problems'),
                  onTap: toggleProblems,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _problemCount(Icons.cancel_outlined, problems.errors),
                        const SizedBox(width: 6),
                        _problemCount(
                          Icons.warning_amber_outlined,
                          problems.warnings,
                        ),
                        if (problems.infos > 0) ...[
                          const SizedBox(width: 6),
                          _problemCount(Icons.info_outline, problems.infos),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (encodingLabel != null && onEncodingTap != null) ...[
            const SizedBox(width: 10),
            InkWell(
              key: const ValueKey('status-encoding'),
              onTap: onEncodingTap,
              child: Tooltip(
                message: encodingTooltip ?? '文件编码',
                child: Text(
                  encodingLabel!,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ),
            ),
          ],
          if (lineEndingLabel != null && onLineEndingTap != null) ...[
            const SizedBox(width: 8),
            InkWell(
              key: const ValueKey('status-line-ending'),
              onTap: onLineEndingTap,
              child: Tooltip(
                message: '行尾格式',
                child: Text(
                  lineEndingLabel!,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ),
            ),
          ],
          if (overtypeMode && onToggleOvertype != null) ...[
            const SizedBox(width: 8),
            InkWell(
              key: const ValueKey('status-overtype'),
              onTap: onToggleOvertype,
              child: const Tooltip(
                message: '启用插入模式',
                child: Text(
                  'OVR',
                  style: TextStyle(color: Color(0xFFE8E8E8), fontSize: 11),
                ),
              ),
            ),
          ],
          if (resourcePressure != null) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: _resourceDetails,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.memory, size: 13, color: _resourceColor),
                  const SizedBox(width: 4),
                  Text(_resourceLabel,
                      style: TextStyle(color: _resourceColor, fontSize: 11)),
                ],
              ),
            ),
          ],
          if (lockedScrolling && onToggleLockedScrolling != null) ...[
            const SizedBox(width: 8),
            Semantics(
              container: true,
              button: true,
              child: InkWell(
                key: const ValueKey('status-bar-locked-scrolling'),
                onTap: onToggleLockedScrolling,
                child: const Tooltip(
                  message: '滚动锁定已开启',
                  excludeFromSemantics: true,
                  child: ColoredBox(
                    color: Color(0xFF2B435A),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        '滚动已锁定',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (notificationButton != null && !notificationAtStart) ...[
            const SizedBox(width: 8),
            notificationButton!,
          ],
          const SizedBox(width: 8),
          InkWell(
            onTap: onTogglePanel,
            child: Icon(
              panelCollapsed
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _problemCount(IconData icon, int count) {
    final color = Colors.grey.shade400;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          _packProblemCount(count),
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }

  static String _packProblemCount(int count) {
    if (count >= 10000) return '10K+';
    if (count >= 1000) return '${count ~/ 1000}K';
    return '$count';
  }

  String get _resourceLabel => switch (resourcePressure) {
        'warn' => '资源告警',
        'critical' => '资源紧张',
        _ => '资源正常',
      };

  Color get _resourceColor => switch (resourcePressure) {
        'warn' => Colors.orangeAccent,
        'critical' => Colors.redAccent,
        _ => Colors.greenAccent,
      };

  String get _resourceDetails {
    final available = availableBytes;
    final total = totalBytes;
    if (available == null || total == null) return _resourceLabel;
    return '$_resourceLabel · 可用 ${_formatBytes(available)} / '
        '${_formatBytes(total)} · ${resourceSource ?? 'system'}';
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Widget _stateIcon() {
    switch (state) {
      case WbSyncState.idle:
        return const Icon(Icons.circle_outlined, size: 12, color: Colors.grey);
      case WbSyncState.synced:
        return const Icon(Icons.check_circle,
            size: 12, color: Colors.greenAccent);
      case WbSyncState.mismatch:
        return const Icon(Icons.warning_amber_rounded,
            size: 12, color: Colors.orangeAccent);
      case WbSyncState.error:
        return const Icon(Icons.error, size: 12, color: Colors.redAccent);
    }
  }
}
