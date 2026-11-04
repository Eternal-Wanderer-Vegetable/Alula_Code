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
    required this.baseText,
    required this.input1Text,
    required this.input2Text,
    required this.resolution,
  });

  final int id;
  final int baseStartLine;
  final int baseEndLineExclusive;
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
}
