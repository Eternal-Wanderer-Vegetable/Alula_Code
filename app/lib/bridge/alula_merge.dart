/// Typed, stateless bridge for Rust three-way merge projections.
library;

import 'dart:convert';

import 'alula_ffi.dart';

enum AlulaMergeSide {
  input1('input1'),
  input2('input2');

  const AlulaMergeSide(this.wireValue);

  final String wireValue;

  static AlulaMergeSide? fromWireValue(Object? value) => switch (value) {
        'input1' => AlulaMergeSide.input1,
        'input2' => AlulaMergeSide.input2,
        _ => null,
      };
}

class AlulaMergeConflict {
  const AlulaMergeConflict({
    required this.id,
    required this.baseStartLine,
    required this.baseEndLineExclusive,
    required this.resultStartUtf16,
    required this.resultEndUtf16,
    required this.baseText,
    required this.input1Text,
    required this.input2Text,
    required this.resolution,
  });

  final int id;
  final int baseStartLine;
  final int baseEndLineExclusive;
  final int resultStartUtf16;
  final int resultEndUtf16;
  final String baseText;
  final String input1Text;
  final String input2Text;
  final AlulaMergeSide? resolution;

  factory AlulaMergeConflict.fromJson(Map<String, Object?> json) {
    final resolution = AlulaMergeSide.fromWireValue(json['resolution']);
    if (json['resolution'] != null && resolution == null) {
      throw const FormatException('未知的合并冲突 resolution 值');
    }
    return AlulaMergeConflict(
      id: json['id'] as int,
      baseStartLine: json['baseStartLine'] as int,
      baseEndLineExclusive: json['baseEndLineExclusive'] as int,
      resultStartUtf16: json['resultStartUtf16'] as int,
      resultEndUtf16: json['resultEndUtf16'] as int,
      baseText: json['baseText'] as String,
      input1Text: json['input1Text'] as String,
      input2Text: json['input2Text'] as String,
      resolution: resolution,
    );
  }
}

class AlulaMergeProjection {
  AlulaMergeProjection({
    required this.result,
    required this.conflictCount,
    required this.unresolvedConflictCount,
    required List<AlulaMergeConflict> conflicts,
  }) : conflicts = List.unmodifiable(conflicts);

  final String result;
  final int conflictCount;
  final int unresolvedConflictCount;
  final List<AlulaMergeConflict> conflicts;

  factory AlulaMergeProjection.fromJson(Map<String, Object?> json) {
    final conflicts = (json['conflicts'] as List)
        .cast<Map<String, Object?>>()
        .map(AlulaMergeConflict.fromJson)
        .toList(growable: false);
    final projection = AlulaMergeProjection(
      result: json['result'] as String,
      conflictCount: json['conflictCount'] as int,
      unresolvedConflictCount: json['unresolvedConflictCount'] as int,
      conflicts: conflicts,
    );
    if (projection.conflictCount != projection.conflicts.length ||
        projection.unresolvedConflictCount < 0 ||
        projection.unresolvedConflictCount > projection.conflictCount) {
      throw const FormatException('合并投影计数不一致');
    }
    var previousEndUtf16 = 0;
    for (final conflict in projection.conflicts) {
      final start = conflict.resultStartUtf16;
      final end = conflict.resultEndUtf16;
      if (start < previousEndUtf16 ||
          end < start ||
          end > projection.result.length) {
        throw const FormatException('合并冲突 result 范围无效');
      }
      final expectedText = switch (conflict.resolution) {
        AlulaMergeSide.input1 => conflict.input1Text,
        AlulaMergeSide.input2 => conflict.input2Text,
        null => conflict.baseText,
      };
      if (projection.result.substring(start, end) != expectedText) {
        throw const FormatException('合并冲突 result 范围与当前投影不一致');
      }
      previousEndUtf16 = end;
    }
    return projection;
  }
}

class AlulaMergeException implements Exception {
  const AlulaMergeException(this.code, this.detail);

  final String code;
  final Object? detail;

  @override
  String toString() => 'AlulaMergeException($code): ${jsonEncode(detail)}';
}

class AlulaMergeCombinationCandidateResponse {
  const AlulaMergeCombinationCandidateResponse(this.candidateText);

  final String? candidateText;

  factory AlulaMergeCombinationCandidateResponse.fromJson(
    Map<String, Object?> json,
  ) {
    if (json['ok'] != true) {
      final error = json['error'];
      if (error is! Map<String, Object?>) {
        throw const FormatException('合并组合候选错误 envelope 无效');
      }
      throw AlulaMergeException(
        error['code'] as String? ?? 'Unknown',
        error['detail'],
      );
    }
    if (!json.containsKey('candidateText')) {
      throw const FormatException('合并组合候选 envelope 缺少 candidateText');
    }
    final candidateText = json['candidateText'];
    if (candidateText != null && candidateText is! String) {
      throw const FormatException('合并组合候选 candidateText 类型无效');
    }
    return AlulaMergeCombinationCandidateResponse(candidateText as String?);
  }
}

/// Calls the Rust model once per request; the native side retains no session.
class AlulaMergeApi {
  const AlulaMergeApi(this._ffi);

  final AlulaFfi _ffi;

  AlulaMergeProjection project({
    required String base,
    required String input1,
    required String input2,
    AlulaMergeSide? acceptAll,
    Map<int, AlulaMergeSide> resolutions = const {},
  }) {
    final request = <String, Object?>{
      'base': base,
      'input1': input1,
      'input2': input2,
      if (acceptAll != null) 'acceptAll': acceptAll.wireValue,
      'resolutions': resolutions.entries
          .map((entry) => {
                'conflictId': entry.key,
                'side': entry.value.wireValue,
              })
          .toList(growable: false),
    };
    final response = jsonDecode(_ffi.mergeProjectJson(jsonEncode(request)))
        as Map<String, Object?>;
    if (response['ok'] != true) {
      final error = response['error']! as Map<String, Object?>;
      throw AlulaMergeException(
        error['code'] as String? ?? 'Unknown',
        error['detail'],
      );
    }
    return AlulaMergeProjection.fromJson(response);
  }

  String? combinationCandidate({
    required String base,
    required String input1,
    required String input2,
  }) {
    final request = jsonEncode({
      'base': base,
      'input1': input1,
      'input2': input2,
    });
    final response = jsonDecode(
      _ffi.mergeCombinationCandidateJson(request),
    ) as Map<String, Object?>;
    return AlulaMergeCombinationCandidateResponse.fromJson(response)
        .candidateText;
  }
}
