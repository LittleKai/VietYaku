#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  bool is_glossary_sync = false;
  std::string glossary_mode;
  HWND parent_hwnd = nullptr;
  for (size_t i = 0; i < command_line_arguments.size(); ++i) {
    if (command_line_arguments[i] == "--glossary-sync") {
      is_glossary_sync = true;
      if (i + 1 < command_line_arguments.size() &&
          command_line_arguments[i + 1].rfind("--", 0) != 0) {
        glossary_mode = command_line_arguments[++i];
      }
    } else if (command_line_arguments[i] == "--parent-hwnd" &&
               i + 1 < command_line_arguments.size()) {
      try {
        parent_hwnd = reinterpret_cast<HWND>(
            static_cast<uintptr_t>(std::stoull(command_line_arguments[++i])));
      } catch (...) {
        parent_hwnd = nullptr;
      }
    }
  }

  if (is_glossary_sync) {
    // Run the detached Glossary Sync window in its own OS process so each
    // Flutter engine owns an isolated ANGLE/D3D11 display. Spawning a second
    // FlutterViewController inside the same process crashes in ANGLE
    // (rx::StateManager11 / rx::Renderer11) under both Impeller and Skia.
    project.set_dart_entrypoint("glossarySyncMain");
    if (!glossary_mode.empty()) {
      project.set_dart_entrypoint_arguments({glossary_mode});
    }
    FlutterWindow window(project, /*is_secondary=*/true, parent_hwnd);
    Win32Window::Point origin(120, 80);
    Win32Window::Size size(1180, 760);
    if (!window.Create(
            L"\x0110\x1ED3ng b\x1ED9 Glossary \x2194 VietPhrase \x2014 VietYaku",
            origin, size)) {
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }

    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"vietyaku", origin, size)) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
