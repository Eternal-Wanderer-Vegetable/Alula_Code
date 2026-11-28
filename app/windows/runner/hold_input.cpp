#include "hold_input.h"

#include <commctrl.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <memory>
#include <variant>

namespace {

struct ObservedPress {
  int64_t time_us = 0;
  int32_t scan_code = 0;
  bool repeat = false;
};

struct HoldInput {
  std::array<ObservedPress, 128> presses;
  size_t next_press = 0;
};

constexpr UINT_PTR hold_input_subclass = 1;

LRESULT CALLBACK ObserveKeyDown(HWND view, UINT message, WPARAM wparam,
                               LPARAM lparam, UINT_PTR subclass,
                               DWORD_PTR data) {
  auto* reference = reinterpret_cast<std::shared_ptr<HoldInput>*>(data);
  if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) {
    auto& input = **reference;
    const auto flags = static_cast<uint32_t>(lparam);
    const auto scan_code = static_cast<int32_t>(
        ((flags >> 16) & 0xff) | ((flags & (1U << 24)) ? 0xe000 : 0));
    // Flutter's Windows key embedder stamps the resulting event immediately
    // after this message with the same clock.
    const auto time = std::chrono::duration_cast<std::chrono::microseconds>(
                          std::chrono::high_resolution_clock::now()
                              .time_since_epoch())
                          .count();
    input.presses[input.next_press] = {
        time, scan_code, (flags & (1U << 30)) != 0};
    input.next_press = (input.next_press + 1) % input.presses.size();
  }
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(view, ObserveKeyDown, subclass);
    delete reference;
  }
  return DefSubclassProc(view, message, wparam, lparam);
}

bool IsFreshPress(const HoldInput& input, int64_t scan_code, int64_t time_us) {
  auto index = input.next_press;
  for (size_t i = 0; i < input.presses.size(); ++i) {
    index = (index + input.presses.size() - 1) % input.presses.size();
    const auto& press = input.presses[index];
    if (press.scan_code == scan_code && press.time_us <= time_us) {
      return !press.repeat;
    }
  }
  return true;
}

}  // namespace

void RegisterHoldInputChannel(flutter::FlutterViewController& controller) {
  const HWND view = controller.view()->GetNativeWindow();
  auto input = std::make_shared<HoldInput>();
  auto* reference = new std::shared_ptr<HoldInput>(input);
  if (!SetWindowSubclass(view, ObserveKeyDown, hold_input_subclass,
                         reinterpret_cast<DWORD_PTR>(reference))) {
    delete reference;
    return;
  }
  flutter::MethodChannel<flutter::EncodableValue> channel(
      controller.engine()->messenger(), "alula/hold_input",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [view, input](const auto& call, auto result) {
        if (call.method_name() != "isFreshHoldPress") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
        if (!args || args->size() != 2) {
          result->Error("invalid-arguments", "Expected a scan code and timestamp");
          return;
        }
        const auto scan_code = (*args)[0].TryGetLongValue();
        const auto time = (*args)[1].TryGetLongValue();
        if (!scan_code || !time) {
          result->Error("invalid-arguments", "Expected integer key metadata");
          return;
        }
        const bool focused =
            IsWindow(view) && GetAncestor(view, GA_ROOT) == GetForegroundWindow();
        result->Success(flutter::EncodableValue(
            focused && IsFreshPress(*input, *scan_code, *time)));
      });
}
