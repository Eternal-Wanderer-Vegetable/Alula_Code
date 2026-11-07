/// Activity Bar Accounts visibility preference.
library;

import 'layout_controller.dart';

extension WorkbenchActivityBarGlobalActions on WorkbenchLayout {
  /// Accounts is visible for new and legacy layouts unless explicitly hidden.
  bool get activityBarAccountsVisible =>
      root.activityBarAccountsVisible ?? true;

  /// Store an explicit Accounts visibility value in the root layout metadata.
  bool setActivityBarAccountsVisible(bool visible) {
    if (activityBarAccountsVisible == visible) return false;
    root.activityBarAccountsVisible = visible;
    notifyLayoutChanged();
    return true;
  }
}
