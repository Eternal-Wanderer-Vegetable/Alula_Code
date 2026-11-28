/// Location of the close action in an ordinary editor tab.
enum EditorTabActionLocation {
  left,
  right;

  static EditorTabActionLocation fromSessionValue(Object? value) =>
      switch (value) {
        'left' => EditorTabActionLocation.left,
        'right' => EditorTabActionLocation.right,
        _ => EditorTabActionLocation.right,
      };
}
