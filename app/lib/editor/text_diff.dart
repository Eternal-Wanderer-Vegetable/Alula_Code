/// 旧文本 → 新文本的增量操作计算。
///
/// MVP 说明（docs/02 §5）：第一版 Flutter 侧编辑控件不提供原生 op 流，
/// 用前后文本 diff 代替；换用真正的编辑组件（CodeForge/Re-Editor）后，
/// 本文件将被组件直接输出的 op 事件替换，接口保持 TextOp 不变。
///
/// 坐标口径：Dart String 索引即 UTF-16 code unit，与协议一致；
/// 唯一要小心的是 diff 边界不能切开代理对（emoji 等）。
library;

import 'package:alula_app/bridge/alula_core.dart';

bool _isHighSurrogate(int cu) => cu >= 0xD800 && cu <= 0xDBFF;
bool _isLowSurrogate(int cu) => cu >= 0xDC00 && cu <= 0xDFFF;

/// 计算 oldText → newText 的操作序列（先删后插，offset 均为变更起点的 UTF-16 下标）。
/// 两文本相同时返回空列表。
List<TextOp> diffToOps(String oldText, String newText) {
  if (oldText == newText) return const [];

  // 公共前缀
  var prefix = 0;
  final minLen =
      oldText.length < newText.length ? oldText.length : newText.length;
  while (prefix < minLen &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  // 前缀边界回退：不能落在代理对中间
  if (prefix > 0 &&
      prefix < newText.length &&
      _isLowSurrogate(newText.codeUnitAt(prefix)) &&
      _isHighSurrogate(newText.codeUnitAt(prefix - 1))) {
    prefix--;
  }

  // 公共后缀（不越过前缀）
  var suffix = 0;
  while (suffix < minLen - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  // 后缀边界回退：变更区结束位置不能切开代理对
  final oldStart = oldText.length - suffix;
  if (suffix > 0 &&
      oldStart < oldText.length &&
      _isLowSurrogate(oldText.codeUnitAt(oldStart)) &&
      oldStart > 0 &&
      _isHighSurrogate(oldText.codeUnitAt(oldStart - 1)) &&
      oldStart - 1 >= prefix) {
    suffix--;
  }

  final ops = <TextOp>[];
  final deletedLen = oldText.length - prefix - suffix;
  if (deletedLen > 0) {
    ops.add(TextOp.delete(prefix, deletedLen));
  }
  final inserted = newText.substring(prefix, newText.length - suffix);
  if (inserted.isNotEmpty) {
    ops.add(TextOp.insert(prefix, inserted));
  }
  return ops;
}
