#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <variant>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "hold_input.h"
#include "notification_accessibility.h"

namespace {

// The Windows runner owns one workbench window. The multi-window callback is
// a C function pointer, so the auxiliary engines read its current handle here.
HWND main_workbench_window = nullptr;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterNotificationAccessibilityChannel(*flutter_controller_);
  RegisterHoldInputChannel(*flutter_controller_);
  flutter::MethodChannel<flutter::EncodableValue> drag_input_channel(
      flutter_controller_->engine()->messenger(), "alula/drag_input",
      &flutter::StandardMethodCodec::GetInstance());
  drag_input_channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "splitTogglePressed") {
      result->Success(flutter::EncodableValue(GetAsyncKeyState(VK_MENU) < 0));
      return;
    }
    result->NotImplemented();
  });
  main_workbench_window = GetHandle();
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
    RegisterHoldInputChannel(*view_controller);
    const HWND source_view = view_controller->view()->GetNativeWindow();
    flutter::MethodChannel<flutter::EncodableValue> close_focus_channel(
        view_controller->engine()->messenger(), "alula/auxiliary_close_focus",
        &flutter::StandardMethodCodec::GetInstance());
    close_focus_channel.SetMethodCallHandler(
        [source_view](const auto& call, auto result) {
          if (call.method_name() != "restoreMainIfSourceForeground") {
            result->NotImplemented();
            return;
          }
          const HWND source = GetAncestor(source_view, GA_ROOT);
          const HWND target = main_workbench_window;
          if (source && source != target && IsWindowVisible(target) &&
              !IsIconic(target) && GetForegroundWindow() == source) {
            SetForegroundWindow(target);
          }
          result->Success();
        });
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter::MethodChannel<flutter::EncodableValue> peek_input_channel(
      flutter_controller_->engine()->messenger(), "alula/peek_input",
      &flutter::StandardMethodCodec::GetInstance());
  peek_input_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setReadOnlyFocus") {
          result->NotImplemented();
          return;
        }
        const auto* focused = std::get_if<bool>(call.arguments());
        if (!focused) {
          result->Error("invalid-arguments", "Expected a boolean");
          return;
        }
        SetReadOnlyPeekFocus(*focused);
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetReadOnlyPeekFocus(bool focused) {
  const HWND view = flutter_controller_->view()->GetNativeWindow();
  if (focused && !peek_input_context_) {
    // The read-only pane has no text input client to complete composition.
    peek_input_context_ = ImmAssociateContext(view, nullptr);
  } else if (!focused && peek_input_context_) {
    ImmAssociateContext(view, peek_input_context_);
    peek_input_context_ = nullptr;
  }
}

void FlutterWindow::OnDestroy() {
  main_workbench_window = nullptr;
  if (flutter_controller_) {
    SetReadOnlyPeekFocus(false);
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
