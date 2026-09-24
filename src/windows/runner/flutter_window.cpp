#include "flutter_window.h"

#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kTrayThemeChannelName[] = "oasx/tray_theme";
constexpr char kSetDarkModeMethod[] = "setDarkMode";
constexpr char kDarkArgument[] = "dark";

enum class PreferredAppMode {
  kDefault = 0,
  kAllowDark = 1,
  kForceDark = 2,
  kForceLight = 3,
  kMax = 4,
};

using SetPreferredAppModeFn = PreferredAppMode(WINAPI*)(PreferredAppMode);
using FlushMenuThemesFn = void(WINAPI*)();

bool ApplyTrayMenuTheme(bool dark) {
  HMODULE uxtheme = ::LoadLibraryW(L"uxtheme.dll");
  if (uxtheme == nullptr) {
    return false;
  }

  auto set_preferred_app_mode = reinterpret_cast<SetPreferredAppModeFn>(
      ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
  auto flush_menu_themes = reinterpret_cast<FlushMenuThemesFn>(
      ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)));

  if (set_preferred_app_mode == nullptr) {
    return false;
  }

  set_preferred_app_mode(dark ? PreferredAppMode::kForceDark
                              : PreferredAppMode::kForceLight);
  if (flush_menu_themes != nullptr) {
    flush_menu_themes();
  }
  return true;
}

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
  RegisterTrayThemeChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterTrayThemeChannel() {
  tray_theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kTrayThemeChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  tray_theme_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name().compare(kSetDarkModeMethod) != 0) {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("bad_arguments", "Expected argument map.");
          return;
        }

        const auto dark_key = flutter::EncodableValue(kDarkArgument);
        const auto dark_iter = arguments->find(dark_key);
        if (dark_iter == arguments->end()) {
          result->Error("bad_arguments", "Missing dark argument.");
          return;
        }

        const auto* dark = std::get_if<bool>(&dark_iter->second);
        if (dark == nullptr) {
          result->Error("bad_arguments", "Dark argument must be bool.");
          return;
        }

        result->Success(flutter::EncodableValue(ApplyTrayMenuTheme(*dark)));
      });
}

void FlutterWindow::OnDestroy() {
  tray_theme_channel_ = nullptr;
  if (flutter_controller_) {
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
