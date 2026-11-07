/// Display mode for an editor group's open-document tabs.
///
/// The value is stored in the workbench session journal so older session files
/// naturally keep the default multi-tab presentation.
enum EditorTabMode {
  multiple,
  single,
  none;

  static EditorTabMode fromSessionValue(Object? value) => switch (value) {
        'single' => EditorTabMode.single,
        'none' => EditorTabMode.none,
        'multiple' => EditorTabMode.multiple,
        _ => EditorTabMode.multiple,
      };
}
