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
