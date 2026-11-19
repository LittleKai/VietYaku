#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool is_secondary = false,
                         HWND parent_hwnd = nullptr);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetClipboardBridgeEnabled(bool enabled);
  bool OpenOrActivateGlossarySyncWindow(const flutter::EncodableValue* args);
  bool SendIpcMessage(HWND target, ULONG_PTR message_type,
                      const flutter::EncodableValue* payload);
  void HandleCopyData(HWND sender, const COPYDATASTRUCT* cds);
  void CloseGlossarySyncChild();

  // The project to run.
  flutter::DartProject project_;
  bool is_secondary_ = false;
  HWND parent_hwnd_ = nullptr;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      windows_bridge_channel_;

  // Detached child process for "Đồng bộ Glossary ↔ VietPhrase".
  HWND glossary_sync_hwnd_ = nullptr;
  HANDLE glossary_sync_process_ = nullptr;
  DWORD glossary_sync_pid_ = 0;
  bool glossary_sync_registered_ = false;

  bool clipboard_listener_registered_ = false;
  bool hotkey_registered_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
