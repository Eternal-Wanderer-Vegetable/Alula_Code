import 'dart:async';

const lockedScrollMotionMethod = 'alula_locked_scroll_motion_v1';

typedef LockedScrollDelta = ({double top, double? left});
typedef LockedScrollSource = ({String windowId, int sequence});

/// A new anchor revision records each local viewport's current position.
final class LockedScrollMotion {
  const LockedScrollMotion({
    required this.lockRevision,
    required this.anchorRevision,
    required this.sequence,
    this.delta,
    this.source,
  });

  final int lockRevision;
  final int anchorRevision;
  final int sequence;
  final LockedScrollDelta? delta;
  final LockedScrollSource? source;

  Map<String, Object?> toMap() => {
        'lockRevision': lockRevision,
        'anchorRevision': anchorRevision,
        'sequence': sequence,
        if (delta case final movement?) ...{
          'top': movement.top,
          'left': movement.left,
        },
        if (source case final origin?) ...{
          'sourceWindowId': origin.windowId,
          'sourceSequence': origin.sequence,
        },
      };

  static LockedScrollMotion? tryParse(Object? value) {
    if (value is! Map) return null;
    final lock = value['lockRevision'];
    final anchor = value['anchorRevision'];
    final sequence = value['sequence'];
    if (lock is! int ||
        lock < 0 ||
        anchor is! int ||
        anchor < 0 ||
        sequence is! int ||
        sequence < 0) {
      return null;
    }
    LockedScrollDelta? delta;
    if (value.containsKey('top') || value.containsKey('left')) {
      final top = value['top'];
      final left = value['left'];
      if (top is! num ||
          !top.isFinite ||
          (left != null && (left is! num || !left.isFinite))) {
        return null;
      }
      delta = (top: top.toDouble(), left: (left as num?)?.toDouble());
    }
    LockedScrollSource? source;
    if (value.containsKey('sourceWindowId') ||
        value.containsKey('sourceSequence')) {
      final windowId = value['sourceWindowId'];
      final sourceSequence = value['sourceSequence'];
      if (delta == null ||
          windowId is! String ||
          windowId.isEmpty ||
          sourceSequence is! int ||
          sourceSequence < 0) {
        return null;
      }
      source = (windowId: windowId, sequence: sourceSequence);
    }
    return LockedScrollMotion(
      lockRevision: lock,
      anchorRevision: anchor,
      sequence: sequence,
      delta: delta,
      source: source,
    );
  }
}

/// Retains at most one unsent frame while a native delivery is in flight.
final class LockedScrollMotionRelay {
  LockedScrollMotionRelay(this._deliver);

  final Future<void> Function(LockedScrollMotion) _deliver;
  LockedScrollMotion? _pending;
  bool _running = false;

  void offer(LockedScrollMotion motion) {
    _pending = motion;
    if (!_running) unawaited(_drain());
  }

  void clear() => _pending = null;

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending != null) {
        final motion = _pending!;
        _pending = null;
        await _deliver(motion);
      }
    } finally {
      _running = false;
    }
  }
}
