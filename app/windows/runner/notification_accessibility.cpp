#include "notification_accessibility.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <tlhelp32.h>

#include <cwchar>
#include <string>

namespace {

bool IsSystemNarrator(DWORD process_id, DWORD session_id,
                      const std::wstring& expected_path) {
  DWORD process_session = 0;
  if (!ProcessIdToSessionId(process_id, &process_session) ||
      process_session != session_id) {
    return false;
  }

  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                     process_id);
  if (!process) {
    return false;
  }
  wchar_t path[MAX_PATH];
  DWORD length = MAX_PATH;
  const bool matches = QueryFullProcessImageNameW(process, 0, path, &length) &&
                       _wcsicmp(path, expected_path.c_str()) == 0;
  CloseHandle(process);
  return matches;
}

bool IsNarratorRunning() {
  DWORD session_id = 0;
  wchar_t system_directory[MAX_PATH];
  const UINT length = GetSystemDirectoryW(system_directory, MAX_PATH);
  if (length == 0 || length >= MAX_PATH ||
      !ProcessIdToSessionId(GetCurrentProcessId(), &session_id)) {
    return false;
  }

  const std::wstring expected_path =
      std::wstring(system_directory, length) + L"\\Narrator.exe";
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return false;
  }
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  bool running = false;
  for (BOOL found = Process32FirstW(snapshot, &entry); found;
       found = Process32NextW(snapshot, &entry)) {
    if (_wcsicmp(entry.szExeFile, L"Narrator.exe") == 0 &&
        IsSystemNarrator(entry.th32ProcessID, session_id, expected_path)) {
      running = true;
      break;
    }
  }
  CloseHandle(snapshot);
  return running;
}

bool IsRegisteredScreenReaderEnabled() {
  BOOL screen_reader = FALSE;
  return SystemParametersInfoW(SPI_GETSCREENREADER, 0, &screen_reader, 0) &&
         screen_reader;
}

void AnnounceNotificationClear(HWND alert, const std::string& message) {
  if (!alert) {
    return;
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         message.c_str(), -1, nullptr, 0);
  if (length < 2) {
    return;
  }

  std::wstring text(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, message.c_str(), -1,
                          text.data(), length) &&
      SetWindowTextW(alert, text.c_str())) {
    // Send only the Win32 alert. Flutter's alert also raises a UIA system alert.
    NotifyWinEvent(EVENT_SYSTEM_ALERT, alert, OBJID_CLIENT, CHILDID_SELF);
  }
}

}  // namespace

void RegisterNotificationAccessibilityChannel(
    flutter::FlutterViewController& controller) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      controller.engine()->messenger(), "alula/accessibility",
      &flutter::StandardMethodCodec::GetInstance());
  // The Flutter view owns the hidden alert source. It has no tab stop and
  // stays alive for Narrator to read its text after the notification.
  const HWND alert = CreateWindowExW(
      0, L"STATIC", L"", WS_CHILD, 0, 0, 0, 0,
      controller.view()->GetNativeWindow(), nullptr, GetModuleHandleW(nullptr),
      nullptr);
  channel.SetMethodCallHandler([alert](const auto& call, auto result) {
    if (call.method_name() == "screenReaderEnabled") {
      result->Success(flutter::EncodableValue(
          IsNarratorRunning() || IsRegisteredScreenReaderEnabled()));
      return;
    }
    if (call.method_name() != "notificationCleared") {
      result->NotImplemented();
      return;
    }
    const auto* message = call.arguments()
                              ? std::get_if<std::string>(call.arguments())
                              : nullptr;
    if (!message || message->empty()) {
      result->Error("invalid_announcement");
      return;
    }

    if (IsNarratorRunning()) {
      AnnounceNotificationClear(alert, *message);
      MessageBeep(MB_OK);
      result->Success(flutter::EncodableValue(false));
      return;
    }

    // Narrator does not set SPI_GETSCREENREADER. Registered readers can still
    // use the existing Flutter feedback path when Narrator is absent.
    result->Success(flutter::EncodableValue(IsRegisteredScreenReaderEnabled()));
  });
}
