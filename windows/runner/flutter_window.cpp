#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kClipboardHotkeyId = 0x5659;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool is_secondary,
                             FlutterWindow* parent_window)
    : project_(project),
      is_secondary_(is_secondary),
      parent_window_(parent_window) {}

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
          if (glossary_sync_window_ &&
              glossary_sync_window_->windows_bridge_channel_) {
            const auto* args = call.arguments();
            glossary_sync_window_->windows_bridge_channel_->InvokeMethod(
                "mainWindowChanged",
                args != nullptr
                    ? std::make_unique<flutter::EncodableValue>(*args)
                    : std::make_unique<flutter::EncodableValue>());
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "closeGlossarySyncWindow") {
          if (glossary_sync_window_ &&
              glossary_sync_window_->GetHandle() != nullptr) {
            ShowWindow(glossary_sync_window_->GetHandle(), SW_HIDE);
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "notifyMainWindow") {
          if (parent_window_ != nullptr &&
              parent_window_->windows_bridge_channel_) {
            const auto* args = call.arguments();
            parent_window_->windows_bridge_channel_->InvokeMethod(
                "glossaryWindowChanged",
                args != nullptr
                    ? std::make_unique<flutter::EncodableValue>(*args)
                    : std::make_unique<flutter::EncodableValue>());
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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

  if (glossary_sync_window_ &&
      glossary_sync_window_->GetHandle() != nullptr) {
    HWND child_hwnd = glossary_sync_window_->GetHandle();
    if (IsIconic(child_hwnd)) {
      ShowWindow(child_hwnd, SW_RESTORE);
    } else {
      ShowWindow(child_hwnd, SW_SHOW);
    }
    SetForegroundWindow(child_hwnd);
    if (glossary_sync_window_->windows_bridge_channel_) {
      glossary_sync_window_->windows_bridge_channel_->InvokeMethod(
          "syncWindowActivated",
          args != nullptr
              ? std::make_unique<flutter::EncodableValue>(*args)
              : std::make_unique<flutter::EncodableValue>());
    }
    return true;
  }

  flutter::DartProject child_project(L"data");
  child_project.set_dart_entrypoint("glossarySyncMain");
  if (!mode_arg.empty()) {
    child_project.set_dart_entrypoint_arguments({mode_arg});
  }

  auto window = std::make_unique<FlutterWindow>(child_project, true, this);
  window->SetQuitOnClose(false);
  Win32Window::Point origin(120, 80);
  Win32Window::Size size(1180, 760);
  if (!window->Create(
          L"\x0110\x1ED3ng b\x1ED9 Glossary \x2194 VietPhrase \x2014 VietYaku",
          origin, size)) {
    return false;
  }
  glossary_sync_window_ = std::move(window);
  return true;
}

void FlutterWindow::OnDestroy() {
  if (glossary_sync_window_) {
    glossary_sync_window_->Destroy();
    glossary_sync_window_.reset();
  }
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
    case WM_CLOSE:
      if (is_secondary_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
