#include "flutter_window.h"

#include <cctype>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include <flutter/standard_message_codec.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kClipboardHotkeyId = 0x5659;
constexpr ULONG_PTR kIpcRegisterChildHwnd = 0x56590001;
constexpr ULONG_PTR kIpcSyncWindowActivated = 0x56590002;
constexpr ULONG_PTR kIpcMainWindowChanged = 0x56590003;
constexpr ULONG_PTR kIpcGlossaryWindowChanged = 0x56590004;
constexpr UINT kIpcTimeoutMs = 2000;

std::wstring GetCurrentExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  for (;;) {
    const DWORD len = GetModuleFileNameW(nullptr, buffer.data(),
                                         static_cast<DWORD>(buffer.size()));
    if (len == 0) {
      return {};
    }
    if (len < buffer.size()) {
      buffer.resize(len);
      return buffer;
    }
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring SanitizeAsciiToken(const std::string& raw) {
  std::wstring out;
  out.reserve(raw.size());
  for (unsigned char ch : raw) {
    if (std::isalnum(ch) || ch == '_' || ch == '-') {
      out.push_back(static_cast<wchar_t>(ch));
    }
  }
  return out;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool is_secondary,
                             HWND parent_hwnd)
    : project_(project),
      is_secondary_(is_secondary),
      parent_hwnd_(parent_hwnd) {}

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
  if (!is_secondary_) {
    RegisterPlugins(flutter_controller_->engine());
  }
  windows_bridge_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "vietyaku/windows_bridge",
          &flutter::StandardMethodCodec::GetInstance());
  windows_bridge_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "setEnabled") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid-arguments", "setEnabled expects a bool");
            return;
          }
          SetClipboardBridgeEnabled(*enabled);
          flutter::EncodableMap response;
          response[flutter::EncodableValue("hotkeyRegistered")] =
              flutter::EncodableValue(hotkey_registered_);
          result->Success(flutter::EncodableValue(response));
          return;
        }
        if (method == "openGlossarySyncWindow") {
          const bool ok = OpenOrActivateGlossarySyncWindow(call.arguments());
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        if (method == "notifyGlossaryWindow") {
          if (glossary_sync_hwnd_ != nullptr && IsWindow(glossary_sync_hwnd_)) {
            SendIpcMessage(glossary_sync_hwnd_, kIpcMainWindowChanged,
                           call.arguments());
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "closeGlossarySyncWindow") {
          CloseGlossarySyncChild();
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "notifyMainWindow") {
          if (parent_hwnd_ != nullptr && IsWindow(parent_hwnd_)) {
            SendIpcMessage(parent_hwnd_, kIpcGlossaryWindowChanged,
                           call.arguments());
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (is_secondary_ && parent_hwnd_ != nullptr && IsWindow(parent_hwnd_)) {
    SendIpcMessage(parent_hwnd_, kIpcRegisterChildHwnd, nullptr);
  }

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    this->Show();
    if (is_secondary_ && GetHandle() != nullptr) {
      SetForegroundWindow(GetHandle());
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

bool FlutterWindow::SendIpcMessage(
    HWND target, ULONG_PTR message_type,
    const flutter::EncodableValue* payload) {
  if (target == nullptr || !IsWindow(target)) {
    return false;
  }
  std::unique_ptr<std::vector<uint8_t>> encoded;
  COPYDATASTRUCT cds{};
  cds.dwData = message_type;
  if (payload != nullptr) {
    encoded = flutter::StandardMessageCodec::GetInstance().EncodeMessage(
        *payload);
    if (encoded && !encoded->empty()) {
      cds.cbData = static_cast<DWORD>(encoded->size());
      cds.lpData = encoded->data();
    }
  }
  DWORD_PTR unused = 0;
  return SendMessageTimeoutW(
             target, WM_COPYDATA, reinterpret_cast<WPARAM>(GetHandle()),
             reinterpret_cast<LPARAM>(&cds), SMTO_ABORTIFHUNG, kIpcTimeoutMs,
             &unused) != 0;
}

void FlutterWindow::HandleCopyData(HWND sender, const COPYDATASTRUCT* cds) {
  if (cds == nullptr || sender == nullptr || !IsWindow(sender)) {
    return;
  }
  auto decode_payload = [cds]() -> std::unique_ptr<flutter::EncodableValue> {
    if (cds->cbData > 0 && cds->lpData != nullptr) {
      auto decoded = flutter::StandardMessageCodec::GetInstance().DecodeMessage(
          reinterpret_cast<const uint8_t*>(cds->lpData), cds->cbData);
      if (decoded) {
        return decoded;
      }
    }
    return std::make_unique<flutter::EncodableValue>();
  };

  if (!is_secondary_) {
    if (cds->dwData == kIpcRegisterChildHwnd) {
      if (!glossary_sync_registered_ && glossary_sync_hwnd_ == nullptr &&
          glossary_sync_process_ != nullptr &&
          WaitForSingleObject(glossary_sync_process_, 0) == WAIT_TIMEOUT) {
        DWORD sender_pid = 0;
        GetWindowThreadProcessId(sender, &sender_pid);
        if (glossary_sync_pid_ != 0 && sender_pid == glossary_sync_pid_) {
          glossary_sync_hwnd_ = sender;
          glossary_sync_registered_ = true;
        }
      }
      return;
    }
    if (cds->dwData == kIpcGlossaryWindowChanged &&
        sender == glossary_sync_hwnd_ && windows_bridge_channel_) {
      windows_bridge_channel_->InvokeMethod("glossaryWindowChanged",
                                            decode_payload());
    }
    return;
  }

  if (sender != parent_hwnd_ || !windows_bridge_channel_) {
    return;
  }
  if (cds->dwData == kIpcSyncWindowActivated) {
    windows_bridge_channel_->InvokeMethod("syncWindowActivated",
                                          decode_payload());
  } else if (cds->dwData == kIpcMainWindowChanged) {
    windows_bridge_channel_->InvokeMethod("mainWindowChanged",
                                          decode_payload());
  }
}

bool FlutterWindow::OpenOrActivateGlossarySyncWindow(
    const flutter::EncodableValue* args) {
  std::string mode_arg;
  if (args != nullptr) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
      auto it = map->find(flutter::EncodableValue("mode"));
      if (it != map->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) {
          mode_arg = *s;
        }
      }
    }
  }

  if (glossary_sync_hwnd_ != nullptr && !IsWindow(glossary_sync_hwnd_)) {
    glossary_sync_hwnd_ = nullptr;
    glossary_sync_pid_ = 0;
  }

  if (glossary_sync_hwnd_ != nullptr) {
    if (IsIconic(glossary_sync_hwnd_)) {
      ShowWindow(glossary_sync_hwnd_, SW_RESTORE);
    } else {
      ShowWindow(glossary_sync_hwnd_, SW_SHOW);
    }
    SetForegroundWindow(glossary_sync_hwnd_);
    SendIpcMessage(glossary_sync_hwnd_, kIpcSyncWindowActivated, args);
    return true;
  }

  if (glossary_sync_process_ != nullptr) {
    if (!glossary_sync_registered_ &&
        WaitForSingleObject(glossary_sync_process_, 0) == WAIT_TIMEOUT) {
      // Child process is still starting up and will register its HWND shortly.
      return true;
    }
    CloseHandle(glossary_sync_process_);
    glossary_sync_process_ = nullptr;
    glossary_sync_pid_ = 0;
    glossary_sync_registered_ = false;
  }

  const std::wstring exe_path = GetCurrentExecutablePath();
  if (exe_path.empty()) {
    return false;
  }

  std::wstring cmd_line = L"\"" + exe_path + L"\" --glossary-sync";
  const std::wstring safe_mode = SanitizeAsciiToken(mode_arg);
  if (!safe_mode.empty()) {
    cmd_line += L" " + safe_mode;
  }
  const auto parent_id = reinterpret_cast<uintptr_t>(GetHandle());
  cmd_line += L" --parent-hwnd " + std::to_wstring(parent_id);

  std::vector<wchar_t> mutable_cmd(cmd_line.begin(), cmd_line.end());
  mutable_cmd.push_back(L'\0');

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  // Inherit parent working directory (nullptr) so debug runs keep finding
  // `<repo>/data` while release runs resolve `<exe>/data/flutter_assets/data`.
  if (!CreateProcessW(exe_path.c_str(), mutable_cmd.data(), nullptr, nullptr,
                      FALSE, 0, nullptr, nullptr, &si, &pi)) {
    return false;
  }

  CloseHandle(pi.hThread);
  glossary_sync_process_ = pi.hProcess;
  glossary_sync_pid_ = pi.dwProcessId;
  glossary_sync_registered_ = false;
  AllowSetForegroundWindow(pi.dwProcessId);
  return true;
}

void FlutterWindow::CloseGlossarySyncChild() {
  if (glossary_sync_hwnd_ != nullptr && IsWindow(glossary_sync_hwnd_)) {
    PostMessageW(glossary_sync_hwnd_, WM_CLOSE, 0, 0);
  } else if (glossary_sync_process_ != nullptr &&
             WaitForSingleObject(glossary_sync_process_, 0) == WAIT_TIMEOUT) {
    TerminateProcess(glossary_sync_process_, 0);
  }
  glossary_sync_hwnd_ = nullptr;
  glossary_sync_pid_ = 0;
  glossary_sync_registered_ = false;
  if (glossary_sync_process_ != nullptr) {
    CloseHandle(glossary_sync_process_);
    glossary_sync_process_ = nullptr;
  }
}

void FlutterWindow::OnDestroy() {
  CloseGlossarySyncChild();
  SetClipboardBridgeEnabled(false);
  windows_bridge_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetClipboardBridgeEnabled(bool enabled) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  if (enabled) {
    if (!clipboard_listener_registered_) {
      clipboard_listener_registered_ = AddClipboardFormatListener(window) != 0;
    }
    if (!hotkey_registered_) {
      hotkey_registered_ =
          RegisterHotKey(window, kClipboardHotkeyId,
                         MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'V') != 0;
    }
  } else {
    if (clipboard_listener_registered_) {
      RemoveClipboardFormatListener(window);
      clipboard_listener_registered_ = false;
    }
    if (hotkey_registered_) {
      UnregisterHotKey(window, kClipboardHotkeyId);
      hotkey_registered_ = false;
    }
  }
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
    case WM_COPYDATA:
      if (lparam != 0) {
        HandleCopyData(reinterpret_cast<HWND>(wparam),
                       reinterpret_cast<const COPYDATASTRUCT*>(lparam));
        return TRUE;
      }
      break;
    case WM_GETMINMAXINFO:
      if (is_secondary_ && lparam != 0) {
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
        const double scale_factor = dpi / 96.0;
        info->ptMinTrackSize.x = static_cast<LONG>(900 * scale_factor);
        info->ptMinTrackSize.y = static_cast<LONG>(560 * scale_factor);
        return 0;
      }
      break;
    case WM_CLIPBOARDUPDATE:
      if (clipboard_listener_registered_ && windows_bridge_channel_) {
        windows_bridge_channel_->InvokeMethod(
            "clipboardChanged",
            std::make_unique<flutter::EncodableValue>());
      }
      break;
    case WM_HOTKEY:
      if (static_cast<int>(wparam) == kClipboardHotkeyId &&
          windows_bridge_channel_) {
        windows_bridge_channel_->InvokeMethod(
            "hotkeyPressed", std::make_unique<flutter::EncodableValue>());
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
