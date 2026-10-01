#include <windows.h>

#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "win32_window.h"

namespace {

struct ResizeEvent {
  UINT width;
  UINT height;
};

struct ChildMetrics {
  std::vector<ResizeEvent> events;
};

void Require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

LRESULT CALLBACK ChildWindowProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* creation = reinterpret_cast<const CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
  }
  auto* metrics = reinterpret_cast<ChildMetrics*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_SIZE && metrics != nullptr) {
    metrics->events.push_back({LOWORD(lparam), HIWORD(lparam)});
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

// The test uses the production Win32Window implementation and an instrumented
// child HWND instead of a Flutter engine. WM_SIZE is the engine's input for
// viewport metrics, so recording this boundary catches missing final updates.
class TestWindow : public Win32Window {
 public:
  explicit TestWindow(ChildMetrics& metrics) : metrics_(metrics) {}

  HWND child() const { return child_; }

 protected:
  bool OnCreate() override {
    child_ = CreateWindowEx(
        0, L"OASX_NATIVE_RESIZE_TEST_CHILD", L"", WS_CHILD, 0, 0, 1, 1,
        GetHandle(), nullptr, GetModuleHandle(nullptr), &metrics_);
    if (child_ == nullptr) {
      return false;
    }
    SetChildContent(child_);
    return true;
  }

 private:
  ChildMetrics& metrics_;
  HWND child_ = nullptr;
};

RECT ReadClient(HWND hwnd) {
  RECT rect{};
  Require(GetClientRect(hwnd, &rect) != 0, "GetClientRect failed");
  return rect;
}

RECT ReadWindow(HWND hwnd) {
  RECT rect{};
  Require(GetWindowRect(hwnd, &rect) != 0, "GetWindowRect failed");
  return rect;
}

void CheckAligned(const TestWindow& window,
                  HWND parent,
                  const ChildMetrics& metrics,
                  const std::string& context) {
  const RECT parent_client = ReadClient(parent);
  const RECT child_client = ReadClient(window.child());
  const LONG width = parent_client.right - parent_client.left;
  const LONG height = parent_client.bottom - parent_client.top;
  Require(width > 0 && height > 0, context + ": parent size must be positive");
  Require(child_client.right - child_client.left == width &&
              child_client.bottom - child_client.top == height,
          context + ": child client does not match parent client");

  POINT origin{0, 0};
  Require(ClientToScreen(window.child(), &origin) != 0,
          context + ": ClientToScreen failed");
  Require(ScreenToClient(parent, &origin) != 0,
          context + ": ScreenToClient failed");
  Require(origin.x == 0 && origin.y == 0,
          context + ": child is not at the parent client origin");
  Require(!metrics.events.empty(), context + ": child received no WM_SIZE");
  const ResizeEvent last = metrics.events.back();
  Require(last.width == static_cast<UINT>(width) &&
              last.height == static_cast<UINT>(height),
          context + ": last WM_SIZE contains stale viewport dimensions");
  Require(!IsWindowVisible(parent) && !IsWindowVisible(window.child()),
          context + ": test windows must remain hidden");
}

void SetHiddenBounds(HWND parent, const RECT& rect) {
  Require(SetWindowPos(parent, nullptr, rect.left, rect.top,
                       rect.right - rect.left, rect.bottom - rect.top,
                       SWP_NOZORDER | SWP_NOACTIVATE) != 0,
          "SetWindowPos failed");
}

void TestContinuousEdgeResizes(TestWindow& window, ChildMetrics& metrics) {
  const HWND parent = window.GetHandle();
  const RECT initial = ReadWindow(parent);
  // Alternate growing/shrinking on every edge. All rectangles are physical
  // pixels; the production runner must not apply the display scale again.
  const LONG changes[] = {48, -64, 112, -88, 176, -128, 64, 0};
  const char* edge_names[] = {"right", "bottom", "left", "top"};
  int checked_resizes = 0;
  for (int edge = 0; edge < 4; ++edge) {
    SetHiddenBounds(parent, initial);
    for (LONG change : changes) {
      RECT target = initial;
      switch (edge) {
        case 0:
          target.right += change;
          break;
        case 1:
          target.bottom += change;
          break;
        case 2:
          target.left += change;
          break;
        case 3:
          target.top += change;
          break;
      }
      const auto before = metrics.events.size();
      SetHiddenBounds(parent, target);
      const std::string context =
          std::string(edge_names[edge]) + " edge delta " + std::to_string(change);
      Require(metrics.events.size() > before,
              context + ": native resize did not notify child WM_SIZE");
      CheckAligned(window, parent, metrics, context);
      ++checked_resizes;
    }
  }
  std::cout << "PASS: " << checked_resizes
            << " physical resizes across all four edges keep child and metrics aligned\n";
}

void TestFinalResizeRepairsStaleChild(TestWindow& window,
                                     ChildMetrics& metrics) {
  const HWND parent = window.GetHandle();
  const RECT frame = ReadClient(parent);
  Require(MoveWindow(window.child(), 17, 11, frame.right / 2,
                     frame.bottom / 2, TRUE) != 0,
          "Failed to inject stale child bounds");
  const RECT stale = ReadClient(window.child());
  Require(stale.right != frame.right || stale.bottom != frame.bottom,
          "Stale-child setup did not change the size");
  const auto before = metrics.events.size();
  SendMessage(parent, WM_EXITSIZEMOVE, 0, 0);
  Require(metrics.events.size() > before,
          "Final resize did not notify corrected viewport metrics");
  CheckAligned(window, parent, metrics, "final resize repairs stale child");
  std::cout << "PASS: WM_EXITSIZEMOVE repairs stale child size and origin\n";
}

void TestFinalResizeResendsUnchangedMetrics(TestWindow& window,
                                           ChildMetrics& metrics) {
  const HWND parent = window.GetHandle();
  CheckAligned(window, parent, metrics, "before unchanged final resize");
  const RECT previous = ReadClient(window.child());
  const auto before = metrics.events.size();
  SendMessage(parent, WM_EXITSIZEMOVE, 0, 0);
  const RECT current = ReadClient(window.child());
  Require(previous.right == current.right && previous.bottom == current.bottom,
          "Unchanged final resize unexpectedly changed child size");
  Require(metrics.events.size() > before,
          "Same-size final resize did not re-send WM_SIZE to recover metrics");
  CheckAligned(window, parent, metrics, "unchanged final resize metrics");
  std::cout << "PASS: unchanged final size still re-sends correct WM_SIZE\n";
}

}  // namespace

int main() {
  // Keep Win32 geometry in physical pixels, including on 125%/150% monitors.
  const HMODULE user32 = GetModuleHandle(L"user32.dll");
  using SetDpiContext = BOOL(WINAPI*)(DPI_AWARENESS_CONTEXT);
  const auto set_dpi_context = reinterpret_cast<SetDpiContext>(
      GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
  if (set_dpi_context != nullptr) {
    set_dpi_context(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  }

  WNDCLASS child_class{};
  child_class.lpfnWndProc = ChildWindowProc;
  child_class.hInstance = GetModuleHandle(nullptr);
  child_class.lpszClassName = L"OASX_NATIVE_RESIZE_TEST_CHILD";
  if (RegisterClass(&child_class) == 0) {
    std::cerr << "FAIL: could not register test child window\n";
    return 1;
  }

  int result = 0;
  try {
    ChildMetrics metrics;
    TestWindow window(metrics);
    Require(window.Create(L"OASX hidden resize regression test",
                          Win32Window::Point(80, 80),
                          Win32Window::Size(900, 650)),
            "Could not create hidden test window");
    CheckAligned(window, window.GetHandle(), metrics, "initial layout");
    TestContinuousEdgeResizes(window, metrics);
    TestFinalResizeRepairsStaleChild(window, metrics);
    TestFinalResizeResendsUnchangedMetrics(window, metrics);
    window.Destroy();
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    result = 1;
  }
  UnregisterClass(child_class.lpszClassName, child_class.hInstance);
  return result;
}
