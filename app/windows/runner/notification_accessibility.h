#ifndef RUNNER_NOTIFICATION_ACCESSIBILITY_H_
#define RUNNER_NOTIFICATION_ACCESSIBILITY_H_

#include <flutter/flutter_view_controller.h>

// Registers feedback for notification clearing in the main workbench.
void RegisterNotificationAccessibilityChannel(
    flutter::FlutterViewController& controller);

#endif  // RUNNER_NOTIFICATION_ACCESSIBILITY_H_
