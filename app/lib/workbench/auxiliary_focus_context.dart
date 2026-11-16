/// Cross-window active editor metadata for auxiliary workbench parts.
///
/// The channel deliberately carries identity and ordering metadata only. It
/// never carries editor text, selection, dirty state, or session state.
library;

const String auxiliaryFocusContextMethod = 'alula_focus_context_v1';

const int maxAuxiliaryFocusWindows = 32;

enum AuxiliaryFocusEventKind { register, update }

class AuxiliaryFocusContextEvent {
  const AuxiliaryFocusContextEvent({
    required this.kind,
    required this.windowId,
    required this.sequence,
    required this.groupId,
    required this.documentId,
    required this.focused,
  });

  static const protocol = 'alula.auxiliary_focus.v1';

  final AuxiliaryFocusEventKind kind;
  final String windowId;
  final int sequence;
  final String groupId;
  final String? documentId;
  final bool focused;

  Map<String, Object?> toMap() => {
        'protocol': protocol,
        'type': kind.name,
        'windowId': windowId,
        'sequence': sequence,
        'groupId': groupId,
        'documentId': documentId,
        'focused': focused,
      };

  static AuxiliaryFocusContextEvent? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    final type = map['type'];
    final windowId = map['windowId'];
    final sequence = map['sequence'];
    final groupId = map['groupId'];
    final documentId = map['documentId'];
    final focused = map['focused'];
    if (map['protocol'] != protocol ||
        (type != AuxiliaryFocusEventKind.register.name &&
            type != AuxiliaryFocusEventKind.update.name) ||
        windowId is! String ||
        windowId.isEmpty ||
        windowId.length > 128 ||
        sequence is! int ||
        sequence < 0 ||
        groupId is! String ||
        groupId.isEmpty ||
        groupId.length > 256 ||
        (documentId != null &&
            (documentId is! String || documentId.length > 4096)) ||
        focused is! bool) {
      return null;
    }
    return AuxiliaryFocusContextEvent(
      kind: type == AuxiliaryFocusEventKind.register.name
          ? AuxiliaryFocusEventKind.register
          : AuxiliaryFocusEventKind.update,
      windowId: windowId,
      sequence: sequence,
      groupId: groupId,
      documentId: documentId as String?,
      focused: focused,
    );
  }
}

class AuxiliaryFocusContextSnapshot {
  const AuxiliaryFocusContextSnapshot({
    required this.windowId,
    required this.groupId,
    required this.documentId,
    required this.revision,
  });

  final String windowId;
  final String groupId;
  final String? documentId;
  final int revision;

  Map<String, Object?> toMap() => {
        'windowId': windowId,
        'groupId': groupId,
        'documentId': documentId,
        'revision': revision,
      };

  static AuxiliaryFocusContextSnapshot? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    final windowId = map['windowId'];
    final groupId = map['groupId'];
    final documentId = map['documentId'];
    final revision = map['revision'];
    if (windowId is! String ||
        windowId.isEmpty ||
        groupId is! String ||
        groupId.isEmpty ||
        (documentId != null && documentId is! String) ||
        revision is! int ||
        revision < 0) {
      return null;
    }
    return AuxiliaryFocusContextSnapshot(
      windowId: windowId,
      groupId: groupId,
      documentId: documentId as String?,
      revision: revision,
    );
  }
}

class AuxiliaryFocusApplyResult {
  const AuxiliaryFocusApplyResult({
    required this.accepted,
    required this.snapshotChanged,
  });

  final bool accepted;
  final bool snapshotChanged;
}

/// Main-window authority for active-part ownership and MRU fallback.
class AuxiliaryFocusContextRegistry {
  String? _mainWindowId;
  String? _activeWindowId;
  int _revision = 0;
  int _activationOrder = 0;
  final Map<String, _Owner> _owners = {};

  int get auxiliaryWindowCount =>
      _owners.length - (_mainWindowId == null ? 0 : 1);

  AuxiliaryFocusContextSnapshot? get snapshot {
    final id = _activeWindowId;
    final owner = id == null ? null : _owners[id];
    if (id == null || owner == null) return null;
    return AuxiliaryFocusContextSnapshot(
      windowId: id,
      groupId: owner.groupId,
      documentId: owner.documentId,
      revision: _revision,
    );
  }

  bool get isInitialized => _mainWindowId != null;

  void initializeMain({
    required String windowId,
    required String groupId,
    required String? documentId,
  }) {
    if (windowId.isEmpty || groupId.isEmpty) {
      throw ArgumentError(
          'Main window and group identifiers must be non-empty');
    }
    if (_mainWindowId != null && _mainWindowId != windowId) {
      throw StateError(
          'The focus registry already has a different main window');
    }
    _mainWindowId = windowId;
    _activeWindowId = windowId;
    _owners[windowId] = _Owner(
      windowId: windowId,
      groupId: groupId,
      documentId: documentId,
      lastSequence: -1,
      lastActivationOrder: ++_activationOrder,
    );
    _revision++;
  }

  AuxiliaryFocusApplyResult apply(AuxiliaryFocusContextEvent event) {
    if (!isInitialized) {
      return const AuxiliaryFocusApplyResult(
        accepted: false,
        snapshotChanged: false,
      );
    }

    final mainWindowId = _mainWindowId!;
    var owner = _owners[event.windowId];
    if (owner == null) {
      if (event.kind != AuxiliaryFocusEventKind.register ||
          event.windowId == mainWindowId ||
          auxiliaryWindowCount >= maxAuxiliaryFocusWindows) {
        return const AuxiliaryFocusApplyResult(
          accepted: false,
          snapshotChanged: false,
        );
      }
      owner = _Owner(
        windowId: event.windowId,
        groupId: event.groupId,
        documentId: event.documentId,
        lastSequence: -1,
        lastActivationOrder: 0,
      );
      _owners[event.windowId] = owner;
    }

    if (event.sequence <= owner.lastSequence) {
      return const AuxiliaryFocusApplyResult(
        accepted: false,
        snapshotChanged: false,
      );
    }

    final previous = _currentIdentity;
    owner
      ..lastSequence = event.sequence
      ..groupId = event.groupId
      ..documentId = event.documentId
      ..isFocused = event.focused;

    if (event.focused) {
      for (final candidate in _owners.values) {
        candidate.isFocused = false;
      }
      owner.isFocused = true;
      owner.lastActivationOrder = ++_activationOrder;
      _activeWindowId = event.windowId;
    } else if (_activeWindowId == event.windowId) {
      _selectMostRecentOwner(excluding: event.windowId);
    }

    final changed = previous != _currentIdentity;
    if (changed) _revision++;
    return AuxiliaryFocusApplyResult(
      accepted: true,
      snapshotChanged: changed,
    );
  }

  AuxiliaryFocusApplyResult removeAuxiliaryWindow(String windowId) {
    if (windowId == _mainWindowId || !_owners.containsKey(windowId)) {
      return const AuxiliaryFocusApplyResult(
        accepted: false,
        snapshotChanged: false,
      );
    }
    final previous = _currentIdentity;
    _owners.remove(windowId);
    if (_activeWindowId == windowId) {
      _selectMostRecentOwner(excluding: windowId);
    }
    final changed = previous != _currentIdentity;
    if (changed) _revision++;
    return AuxiliaryFocusApplyResult(
      accepted: true,
      snapshotChanged: changed,
    );
  }

  String _selectMostRecentOwner({required String excluding}) {
    _Owner? fallback;
    for (final candidate in _owners.values) {
      if (candidate.windowId == excluding ||
          candidate.lastActivationOrder == 0) {
        continue;
      }
      if (fallback == null ||
          candidate.lastActivationOrder > fallback.lastActivationOrder) {
        fallback = candidate;
      }
    }
    final mainWindowId = _mainWindowId!;
    _activeWindowId = fallback?.windowId ?? mainWindowId;
    return _activeWindowId!;
  }

  (String, String, String?)? get _currentIdentity {
    final id = _activeWindowId;
    final owner = id == null ? null : _owners[id];
    if (id == null || owner == null) return null;
    return (id, owner.groupId, owner.documentId);
  }
}

class _Owner {
  _Owner({
    required this.windowId,
    required this.groupId,
    required this.documentId,
    required this.lastSequence,
    required this.lastActivationOrder,
  });

  final String windowId;
  String groupId;
  String? documentId;
  int lastSequence;
  int lastActivationOrder;
  bool isFocused = false;
}
