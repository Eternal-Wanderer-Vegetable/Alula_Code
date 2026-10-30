import '../bridge/alula_core.dart';

const int defaultMultiCursorLimit = 10000;

typedef OccurrenceRangeReader = TextRangeRead Function(
  int startUtf16, {
  required int maxLenUtf16,
});

/// Yields non-overlapping UTF-16 match offsets from bounded Rust document reads.
///
/// At most one [maxDocReadRangeUtf16] range and a `needle.length - 1` overlap
/// are retained at a time. The overlap lets a match span two Rust reads without
/// transferring or materializing the document as a Dart string.
Iterable<int> findTextOccurrenceOffsets({
  required String needle,
  required int totalUtf16Length,
  required OccurrenceRangeReader readRange,
  int startUtf16 = 0,
  int? endUtf16,
  int? maxMatches,
}) sync* {
  if (needle.isEmpty || totalUtf16Length <= 0 || maxMatches == 0) return;
  if (maxMatches != null && maxMatches < 0) {
    throw RangeError.value(maxMatches, 'maxMatches');
  }

  final start = startUtf16.clamp(0, totalUtf16Length).toInt();
  final end =
      (endUtf16 ?? totalUtf16Length).clamp(start, totalUtf16Length).toInt();
  if (start >= end || needle.length > totalUtf16Length) return;

  final readThrough =
      (end + needle.length - 1).clamp(end, totalUtf16Length).toInt();
  var cursor = start;
  var carry = '';
  var nextCandidateStart = start;
  var matchCount = 0;

  while (cursor < readThrough) {
    final page = readRange(
      cursor,
      maxLenUtf16:
          (totalUtf16Length - cursor).clamp(0, maxDocReadRangeUtf16).toInt(),
    );
    if (page.startUtf16 != cursor ||
        page.endUtf16 <= cursor ||
        page.endUtf16 > totalUtf16Length ||
        page.text.length != page.endUtf16 - page.startUtf16) {
      throw StateError('Rust occurrence range is not contiguous');
    }

    final combined = '$carry${page.text}';
    final combinedStart = page.startUtf16 - carry.length;
    var searchFrom = 0;
    while (searchFrom <= combined.length - needle.length) {
      final localOffset = combined.indexOf(needle, searchFrom);
      if (localOffset < 0) break;
      final absoluteOffset = combinedStart + localOffset;
      if (absoluteOffset >= nextCandidateStart &&
          absoluteOffset >= start &&
          absoluteOffset < end &&
          absoluteOffset + needle.length <= totalUtf16Length) {
        yield absoluteOffset;
        matchCount++;
        if (maxMatches != null && matchCount >= maxMatches) return;
      }
      searchFrom = localOffset + needle.length;
    }

    final fullyScannedUntil = page.endUtf16 >= totalUtf16Length
        ? end
        : page.endUtf16 - needle.length + 1;
    if (fullyScannedUntil > nextCandidateStart) {
      nextCandidateStart = fullyScannedUntil.clamp(start, end).toInt();
    }
    final overlap = (needle.length - 1).clamp(0, combined.length).toInt();
    carry = overlap == 0 ? '' : combined.substring(combined.length - overlap);
    cursor = page.endUtf16;
  }
}
