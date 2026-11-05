import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bulk_edit_multidiff_preview.dart';
import 'bulk_edit_multidiff_projection.dart';
import 'bulk_edit_preview.dart';
import 'workspace_edit.dart';

/// Opens the bounded selection review for a text-only workspace edit.
///
/// [onApply] receives an immutable edit containing only the selected changes.
/// The review closes only when the callback reports a successful transaction.
Future<bool> showBulkEditPreview({
  required BuildContext context,
  required WorkspaceEdit edit,
  required List<WorkspaceDocumentSnapshot> snapshots,
  required Future<bool> Function(WorkspaceEdit selectedEdit) onApply,
  String title = '应用工作区编辑',
  String keyPrefix = 'bulk-edit-preview',
}) async {
  final BulkEditPreviewSession session;
  try {
    session = BulkEditPreviewSession(edit);
  } on BulkEditPreviewException {
    return false;
  }

  final frozenSnapshots = List<WorkspaceDocumentSnapshot>.unmodifiable([
    for (final snapshot in snapshots)
      WorkspaceDocumentSnapshot(
        id: snapshot.id,
        uri: snapshot.uri,
        version: snapshot.version,
        text: snapshot.text,
        writable: snapshot.writable,
      ),
  ]);
  if (!_hasUniqueSnapshotUris(frozenSnapshots) ||
      session.documents.any(
        (document) =>
            !frozenSnapshots.any((snapshot) => snapshot.uri == document.uri),
      )) {
    return false;
  }

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _BulkEditPreviewDialog(
          session: session,
          snapshots: frozenSnapshots,
          onApply: onApply,
          title: title,
          keyPrefix: keyPrefix,
          onClose: () => Navigator.of(dialogContext).maybePop(false),
        ),
      ) ??
      false;
}

bool _hasUniqueSnapshotUris(List<WorkspaceDocumentSnapshot> snapshots) {
  final uris = <String>{};
  return snapshots.every((snapshot) => uris.add(snapshot.uri));
}

class _BulkEditPreviewDialog extends StatefulWidget {
  const _BulkEditPreviewDialog({
    required this.session,
    required this.snapshots,
    required this.onApply,
    required this.title,
    required this.keyPrefix,
    required this.onClose,
  });

  final BulkEditPreviewSession session;
  final List<WorkspaceDocumentSnapshot> snapshots;
  final Future<bool> Function(WorkspaceEdit selectedEdit) onApply;
  final String title;
  final String keyPrefix;
  final VoidCallback onClose;

  @override
  State<_BulkEditPreviewDialog> createState() => _BulkEditPreviewDialogState();
}

class _BulkEditPreviewDialogState extends State<_BulkEditPreviewDialog> {
  late final FocusNode _dialogFocusNode;
  int _activeDocument = 0;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _dialogFocusNode = FocusNode(debugLabel: 'bulk-edit-preview-dialog');
  }

  @override
  void dispose() {
    _dialogFocusNode.dispose();
    super.dispose();
  }

  List<BulkEditPreviewDocumentState> get _documents => widget.session.documents;

  void _changeSelection(bool Function() change) {
    setState(() {
      change();
      _error = null;
    });
  }

  void _discard() {
    if (_applying) return;
    widget.onClose();
  }

  List<WorkspaceDocumentSnapshot> _snapshotsFor(WorkspaceEdit edit) {
    final snapshotsByUri = {
      for (final snapshot in widget.snapshots) snapshot.uri: snapshot,
    };
    return List.unmodifiable([
      for (final document in edit.documents) snapshotsByUri[document.uri]!,
    ]);
  }

  WorkspaceEdit _selectedEdit() => widget.session.toWorkspaceEdit();

  Future<void> _openMultiDiff() async {
    if (!widget.session.hasSelection || _applying) return;
    try {
      final selectedEdit = _selectedEdit();
      final projection = BulkEditMultiDiffProjection(
        selectedEdit: selectedEdit,
        snapshots: _snapshotsFor(selectedEdit),
      );
      await showBulkEditMultiDiffPreview(
        context: context,
        projection: projection,
        title: '重构预览',
        keyPrefix: '${widget.keyPrefix}-multidiff',
      );
    } on BulkEditPreviewException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on BulkEditMultiDiffException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _apply() async {
    if (_applying || !widget.session.hasSelection) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final selectedEdit = _selectedEdit();
      const WorkspaceEditPlanner().plan(
        selectedEdit,
        _snapshotsFor(selectedEdit),
      );
      final applied = await widget.onApply(selectedEdit);
      if (!mounted) return;
      if (applied) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = '工作区编辑未应用；检查文档状态后可重试。');
      }
    } on BulkEditPreviewException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on WorkspaceEditException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '工作区编辑失败；文档未确认应用。');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width - 32).clamp(320.0, 1040.0).toDouble();
    final height = (media.height - 32).clamp(320.0, 760.0).toDouble();
    final documents = _documents;
    final keyPrefix = widget.keyPrefix;
    if (_activeDocument >= documents.length) _activeDocument = 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _discard,
      },
      child: Focus(
        focusNode: _dialogFocusNode,
        autofocus: true,
        child: PopScope(
          canPop: !_applying,
          child: Dialog(
            key: ValueKey('$keyPrefix-dialog'),
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            key: ValueKey('$keyPrefix-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('$keyPrefix-close'),
                          tooltip: 'Discard',
                          onPressed: _applying ? null : _discard,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _buildSelectionToolbar(documents, keyPrefix),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 700) {
                          return Column(
                            children: [
                              SizedBox(
                                height: 160,
                                child: _buildResourceList(documents, keyPrefix),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _buildEditList(
                                  documents[_activeDocument],
                                  keyPrefix,
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 300,
                              child: _buildResourceList(documents, keyPrefix),
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(
                              child: _buildEditList(
                                documents[_activeDocument],
                                keyPrefix,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: ValueKey('$keyPrefix-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        TextButton(
                          key: ValueKey('$keyPrefix-preview'),
                          onPressed: _applying || !widget.session.hasSelection
                              ? null
                              : _openMultiDiff,
                          child: const Text('Preview'),
                        ),
                        const Spacer(),
                        TextButton(
                          key: ValueKey('$keyPrefix-discard'),
                          onPressed: _applying ? null : _discard,
                          child: const Text('Discard'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: ValueKey('$keyPrefix-apply'),
                          onPressed: _applying || !widget.session.hasSelection
                              ? null
                              : _apply,
                          child: _applying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionToolbar(
    List<BulkEditPreviewDocumentState> documents,
    String keyPrefix,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          TextButton(
            key: ValueKey('$keyPrefix-select-all'),
            onPressed: _applying
                ? null
                : () => _changeSelection(widget.session.selectAll),
            child: const Text('全选'),
          ),
          TextButton(
            key: ValueKey('$keyPrefix-clear-all'),
            onPressed: _applying
                ? null
                : () => _changeSelection(widget.session.clearAll),
            child: const Text('清空'),
          ),
          const SizedBox(width: 8),
          Semantics(
            liveRegion: true,
            label:
                '已选择 ${widget.session.selectedEditCount} / ${widget.session.editCount} 项',
            child: Text(
              '已选择 ${widget.session.selectedEditCount} / ${widget.session.editCount} 项',
              key: ValueKey('$keyPrefix-selected-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (documents.isEmpty)
            const SizedBox.shrink()
          else
            Text(
              ' · ${documents.length} 个资源',
              key: ValueKey('$keyPrefix-resource-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildResourceList(
    List<BulkEditPreviewDocumentState> documents,
    String keyPrefix,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            '更改的资源',
            key: ValueKey('$keyPrefix-resource-heading'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: ValueKey('$keyPrefix-resource-list'),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              final active = index == _activeDocument;
              final state = document.selectionState;
              final selected = switch (state) {
                BulkEditPreviewSelectionState.none => false,
                BulkEditPreviewSelectionState.some => null,
                BulkEditPreviewSelectionState.all => true,
              };
              final label = _resourceLabel(document.uri);
              final semantics = '$label，已选 ${document.selectedEditCount} / '
                  '${document.edits.length} 项，版本 ${document.version ?? '未指定'}';
              return Semantics(
                key: ValueKey('$keyPrefix-resource-semantics-$index'),
                label: semantics,
                selected: active,
                child: ExcludeSemantics(
                  child: ListTile(
                    key: ValueKey('$keyPrefix-resource-$index'),
                    selected: active,
                    contentPadding: const EdgeInsets.only(left: 4, right: 8),
                    leading: Checkbox(
                      key: ValueKey('$keyPrefix-resource-checkbox-$index'),
                      tristate: true,
                      value: selected,
                      onChanged: _applying
                          ? null
                          : (value) => _changeSelection(
                                () => widget.session.setDocumentSelected(
                                  index,
                                  value ?? false,
                                ),
                              ),
                    ),
                    title: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${document.selectedEditCount} / ${document.edits.length} 项 · '
                      'v${document.version ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      setState(() {
                        _activeDocument = index;
                        _error = null;
                      });
                    },
                    trailing: IconButton(
                      key: ValueKey('$keyPrefix-invert-$index'),
                      tooltip: '反选此资源',
                      onPressed: _applying
                          ? null
                          : () => _changeSelection(
                                () => widget.session
                                    .invertDocumentSelection(index),
                              ),
                      icon: const Icon(Icons.flip_to_back_outlined, size: 18),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditList(
    BulkEditPreviewDocumentState document,
    String keyPrefix,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            '${_resourceLabel(document.uri)} · ${document.edits.length} 项',
            key: ValueKey('$keyPrefix-edit-heading'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: ValueKey('$keyPrefix-edit-list'),
            itemCount: document.edits.length,
            itemBuilder: (context, index) {
              final edit = document.edits[index];
              final selected = widget.session.isEditSelected(
                document.documentIndex,
                edit.editIndex,
              );
              final range = edit.edit.range;
              final label =
                  '${range.start.line + 1}:${range.start.character + 1} '
                  '→ ${range.end.line + 1}:${range.end.character + 1}';
              final replacement = _singleLine(edit.edit.newText);
              return CheckboxListTile(
                key: ValueKey(
                  '$keyPrefix-edit-checkbox-${document.documentIndex}-${edit.editIndex}',
                ),
                value: selected,
                onChanged: _applying
                    ? null
                    : (value) => _changeSelection(
                          () => widget.session.setEditSelected(
                            document.documentIndex,
                            edit.editIndex,
                            value ?? false,
                          ),
                        ),
                title: Text(label),
                subtitle: Text(
                  replacement.isEmpty ? '(空文本)' : replacement,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }

  String _resourceLabel(String uri) {
    final path = Uri.tryParse(uri)?.path;
    if (path == null || path.isEmpty) return uri;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String _singleLine(String text) {
    final normalized = text.replaceAll('\r\n', '↵').replaceAll('\n', '↵');
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 119)}…';
  }
}
