import 'dart:convert';
import 'dart:io';

String workspaceStateIdentity(String? workspaceRoot) {
  if (workspaceRoot == null || workspaceRoot.isEmpty) {
    return 'empty-workspace';
  }
  var normalized = workspaceRoot.replaceAll('\\', '/');
  while (normalized.length > 1 &&
      normalized.endsWith('/') &&
      !RegExp(r'^[a-zA-Z]:/$').hasMatch(normalized)) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (Platform.isWindows) normalized = normalized.toLowerCase();
  return 'workspace:$normalized';
}

String workspaceStateFileKey(String value) {
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final byte in utf8.encode(value)) {
    hash ^= BigInt.from(byte);
    hash = (hash * BigInt.from(0x100000001b3)) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
