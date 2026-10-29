/// 状态栏（docs/09 W1）：同步状态 / 详情 + 右侧语言服务信息 + 面板开关。
library;

import 'package:flutter/material.dart';

enum WbSyncState { idle, synced, mismatch, error }

class AlulaStatusBar extends StatelessWidget {
  const AlulaStatusBar({
    super.key,
    required this.state,
    required this.detail,
    required this.lspStatus,
    required this.diagnosticsCount,
    required this.tabCount,
    required this.abiVersion,
    this.resourcePressure,
    this.availableBytes,
    this.totalBytes,
    this.resourceSource,
    required this.syncCount,
    required this.panelCollapsed,
    required this.onTogglePanel,
  });

  final WbSyncState state;
  final String detail;
  final String lspStatus;
  final int diagnosticsCount;
  final int tabCount;
  final int abiVersion;
  final String? resourcePressure;
  final int? availableBytes;
  final int? totalBytes;
  final String? resourceSource;
  final int syncCount;
  final bool panelCollapsed;
  final VoidCallback onTogglePanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
      child: Row(
        children: [
          _stateIcon(),
          const SizedBox(width: 8),
          Expanded(child: Text(detail, style: const TextStyle(fontSize: 11))),
          Text(
            '$lspStatus · 诊断 $diagnosticsCount · 标签 $tabCount · '
            'ABI v$abiVersion · 同步 $syncCount 次',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
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
        return const Icon(Icons.check_circle, size: 12, color: Colors.greenAccent);
      case WbSyncState.mismatch:
        return const Icon(Icons.warning_amber_rounded,
            size: 12, color: Colors.orangeAccent);
      case WbSyncState.error:
        return const Icon(Icons.error, size: 12, color: Colors.redAccent);
    }
  }
}
