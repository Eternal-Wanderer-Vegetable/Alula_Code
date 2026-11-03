import 'snapshot_compare_preview.dart';

/// Retains the clipboard compare widget API while sharing the snapshot view.
class ClipboardComparePreview extends SnapshotComparePreview {
  const ClipboardComparePreview({
    super.key,
    required super.title,
    required super.originalLabel,
    required super.modifiedLabel,
    required super.diff,
    required super.onClose,
  }) : super(
          keyPrefix: 'clipboard-compare',
        );
}
