/// Resource arguments for the internal VS Code-compatible `_open.mergeEditor`
/// workbench command.
///
/// All four resources must be absolute local file URIs. The Workbench resolves
/// the frozen inputs and an existing result document before attaching a merge
/// session; this request never writes to a resource.
class MergeEditorOpenRequest {
  const MergeEditorOpenRequest({
    required this.baseUri,
    required this.input1Uri,
    required this.input2Uri,
    required this.resultUri,
  });

  final Uri baseUri;
  final Uri input1Uri;
  final Uri input2Uri;
  final Uri resultUri;
}
