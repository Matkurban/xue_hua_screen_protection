#include "xue_hua_screen_protection_plugin.h"

#include <VersionHelpers.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <chrono>
#include <memory>
#include <string>
#include <utility>

#ifndef WDA_NONE
#define WDA_NONE 0x00000000
#endif

#ifndef WDA_MONITOR
#define WDA_MONITOR 0x00000001
#endif

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

namespace xue_hua_screen_protection {

namespace {

constexpr wchar_t kOverlayClassName[] = L"XueHuaScreenProtectionOverlayClass";
constexpr ULONGLONG kScreenshotDebounceMs = 1200;

std::wstring Utf8ToWide(const std::string &utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      &wide[0], count);
  return wide;
}

COLORREF ArgbToColorRef(uint32_t argb) {
  BYTE r = static_cast<BYTE>((argb >> 16) & 0xFF);
  BYTE g = static_cast<BYTE>((argb >> 8) & 0xFF);
  BYTE b = static_cast<BYTE>(argb & 0xFF);
  return RGB(r, g, b);
}

int64_t CurrentEpochMillis() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

}  // namespace

// static
void XueHuaScreenProtectionPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<XueHuaScreenProtectionPlugin>(registrar);
  ScreenProtectionHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

XueHuaScreenProtectionPlugin::XueHuaScreenProtectionPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  if (registrar_ != nullptr) {
    flutter_api_ =
        std::make_unique<ScreenProtectionFlutterApi>(registrar_->messenger());
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
          return this->HandleWindowProc(hwnd, message, wparam, lparam);
        });
  }
}

XueHuaScreenProtectionPlugin::~XueHuaScreenProtectionPlugin() {
  DestroyOverlayWindow();
  if (clipboard_listener_registered_ && tracked_hwnd_ != nullptr &&
      IsWindow(tracked_hwnd_)) {
    RemoveClipboardFormatListener(tracked_hwnd_);
    clipboard_listener_registered_ = false;
  }
  if (registrar_ != nullptr) {
    if (window_proc_id_ != -1) {
      registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    }
    ScreenProtectionHostApi::SetUp(registrar_->messenger(), nullptr);
  }
}

HWND XueHuaScreenProtectionPlugin::GetMainWindowHandle() const {
  if (registrar_ == nullptr) return nullptr;
  flutter::FlutterView *view = registrar_->GetView();
  if (view == nullptr) return nullptr;
  HWND view_hwnd = view->GetNativeWindow();
  if (view_hwnd == nullptr) return nullptr;
  HWND root_hwnd = GetAncestor(view_hwnd, GA_ROOT);
  return root_hwnd != nullptr ? root_hwnd : view_hwnd;
}

bool XueHuaScreenProtectionPlugin::ApplyDisplayAffinity(bool enabled) {
  is_secure_screen_enabled_ = enabled;
  HWND hwnd = GetMainWindowHandle();
  if (hwnd == nullptr) {
    // Still store state for unit tests or pre-window initialization.
    return true;
  }

  if (!clipboard_listener_registered_ && IsWindow(hwnd)) {
    if (AddClipboardFormatListener(hwnd)) {
      clipboard_listener_registered_ = true;
      tracked_hwnd_ = hwnd;
    }
  }

  if (enabled) {
    // Try WDA_EXCLUDEFROMCAPTURE first (Windows 10 2004+ / Build 19041+).
    if (!SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)) {
      // Fallback to WDA_MONITOR on earlier Windows versions.
      SetWindowDisplayAffinity(hwnd, WDA_MONITOR);
    }
  } else {
    SetWindowDisplayAffinity(hwnd, WDA_NONE);
  }
  return true;
}

std::optional<LRESULT> XueHuaScreenProtectionPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM /*lparam*/) {
  if (!clipboard_listener_registered_ && IsWindow(hwnd)) {
    if (AddClipboardFormatListener(hwnd)) {
      clipboard_listener_registered_ = true;
      tracked_hwnd_ = hwnd;
    }
  }

  switch (message) {
    case WM_ACTIVATE: {
      WORD state = LOWORD(wparam);
      if (state == WA_INACTIVE) {
        if (mask_enabled_ &&
            mask_style_ != ScreenProtectionMaskStyleMessage::kNone &&
            protect_on_window_blur_) {
          SetPrivacyMaskVisible(true, "window_deactivated");
        }
      } else {
        if (is_mask_currently_visible_) {
          SetPrivacyMaskVisible(false, "window_activated");
        }
      }
      break;
    }
    case WM_SIZE: {
      if (is_mask_currently_visible_) {
        UpdateOverlayLayout(hwnd);
      }
      break;
    }
    case WM_KEYUP:
    case WM_SYSKEYUP: {
      if (wparam == VK_SNAPSHOT) {
        ULONGLONG now = GetTickCount64();
        if (now - last_screenshot_tick_ >= kScreenshotDebounceMs) {
          last_screenshot_tick_ = now;
          EmitEvent(ScreenProtectionEventTypeMessage::kScreenshotTaken,
                    {{flutter::EncodableValue("source"),
                      flutter::EncodableValue("VK_SNAPSHOT")}});
        }
      }
      break;
    }
    case WM_CLIPBOARDUPDATE: {
      if (IsClipboardFormatAvailable(CF_BITMAP) ||
          IsClipboardFormatAvailable(CF_DIB)) {
        ULONGLONG now = GetTickCount64();
        if (now - last_screenshot_tick_ >= kScreenshotDebounceMs) {
          last_screenshot_tick_ = now;
          EmitEvent(ScreenProtectionEventTypeMessage::kScreenshotTaken,
                    {{flutter::EncodableValue("source"),
                      flutter::EncodableValue("WM_CLIPBOARDUPDATE_BITMAP")}});
        }
      }
      break;
    }
    default:
      break;
  }
  return std::nullopt;
}

LRESULT CALLBACK XueHuaScreenProtectionPlugin::OverlayWndProc(HWND hwnd,
                                                              UINT message,
                                                              WPARAM wparam,
                                                              LPARAM lparam) {
  auto *self = reinterpret_cast<XueHuaScreenProtectionPlugin *>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));

  if (message == WM_NCCREATE) {
    auto *create_struct = reinterpret_cast<CREATESTRUCTW *>(lparam);
    SetWindowLongPtrW(
        hwnd, GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }

  if (message == WM_PAINT && self != nullptr) {
    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(hwnd, &ps);

    RECT client_rect;
    GetClientRect(hwnd, &client_rect);

    HBRUSH bg_brush =
        CreateSolidBrush(ArgbToColorRef(self->mask_background_color_));
    FillRect(hdc, &client_rect, bg_brush);
    DeleteObject(bg_brush);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, ArgbToColorRef(self->mask_text_color_));

    int center_y = (client_rect.bottom - client_rect.top) / 2;

    if (!self->mask_title_.empty()) {
      HFONT title_font = CreateFontW(
          28, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
          DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
      HGDIOBJ old_font = SelectObject(hdc, title_font);

      RECT title_rect = client_rect;
      title_rect.top = center_y - 36;
      title_rect.bottom = center_y + 4;
      std::wstring wide_title = Utf8ToWide(
          self->mask_show_lock_icon_ ? ("[LOCKED] " + self->mask_title_)
                                     : self->mask_title_);
      DrawTextW(hdc, wide_title.c_str(), -1, &title_rect,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

      SelectObject(hdc, old_font);
      DeleteObject(title_font);
    }

    if (!self->mask_subtitle_.empty()) {
      HFONT sub_font = CreateFontW(
          18, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
          DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
      HGDIOBJ old_font = SelectObject(hdc, sub_font);

      RECT sub_rect = client_rect;
      sub_rect.top = center_y + 10;
      sub_rect.bottom = center_y + 60;
      std::wstring wide_sub = Utf8ToWide(self->mask_subtitle_);
      DrawTextW(hdc, wide_sub.c_str(), -1, &sub_rect,
                DT_CENTER | DT_WORDBREAK);

      SelectObject(hdc, old_font);
      DeleteObject(sub_font);
    }

    EndPaint(hwnd, &ps);
    return 0;
  }

  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void XueHuaScreenProtectionPlugin::EnsureOverlayWindowCreated(
    HWND parent_hwnd) {
  if (overlay_hwnd_ != nullptr && IsWindow(overlay_hwnd_)) {
    return;
  }

  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  if (!GetClassInfoExW(instance, kOverlayClassName, &wc)) {
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = OverlayWndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kOverlayClassName;
    RegisterClassExW(&wc);
  }

  RECT rect;
  GetClientRect(parent_hwnd, &rect);

  overlay_hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST, kOverlayClassName, L"", WS_CHILD | WS_CLIPSIBLINGS, 0, 0,
      rect.right - rect.left, rect.bottom - rect.top, parent_hwnd, nullptr,
      instance, this);
}

void XueHuaScreenProtectionPlugin::UpdateOverlayLayout(HWND parent_hwnd) {
  if (overlay_hwnd_ == nullptr || !IsWindow(overlay_hwnd_)) return;
  RECT rect;
  GetClientRect(parent_hwnd, &rect);
  SetWindowPos(overlay_hwnd_, HWND_TOP, 0, 0, rect.right - rect.left,
               rect.bottom - rect.top, SWP_SHOWWINDOW);
  InvalidateRect(overlay_hwnd_, nullptr, TRUE);
}

void XueHuaScreenProtectionPlugin::DestroyOverlayWindow() {
  if (overlay_hwnd_ != nullptr && IsWindow(overlay_hwnd_)) {
    DestroyWindow(overlay_hwnd_);
  }
  overlay_hwnd_ = nullptr;
}

void XueHuaScreenProtectionPlugin::SetPrivacyMaskVisible(
    bool visible, const std::string &reason) {
  HWND parent_hwnd = GetMainWindowHandle();
  if (visible) {
    if (parent_hwnd != nullptr && IsWindow(parent_hwnd)) {
      EnsureOverlayWindowCreated(parent_hwnd);
      UpdateOverlayLayout(parent_hwnd);
      ShowWindow(overlay_hwnd_, SW_SHOW);
      UpdateWindow(overlay_hwnd_);
    }
    if (!is_mask_currently_visible_) {
      is_mask_currently_visible_ = true;
      EmitEvent(ScreenProtectionEventTypeMessage::kMaskShown,
                {{flutter::EncodableValue("reason"),
                  flutter::EncodableValue(reason)}});
    }
  } else {
    if (overlay_hwnd_ != nullptr && IsWindow(overlay_hwnd_)) {
      ShowWindow(overlay_hwnd_, SW_HIDE);
    }
    if (is_mask_currently_visible_) {
      is_mask_currently_visible_ = false;
      EmitEvent(ScreenProtectionEventTypeMessage::kMaskHidden,
                {{flutter::EncodableValue("reason"),
                  flutter::EncodableValue(reason)}});
    }
  }
}

void XueHuaScreenProtectionPlugin::EmitEvent(
    ScreenProtectionEventTypeMessage type,
    const flutter::EncodableMap &metadata) {
  if (flutter_api_ == nullptr) {
    return;
  }
  ScreenProtectionEventMessage event(type, CurrentEpochMillis(), "windows",
                                     false, metadata);
  flutter_api_->OnProtectionEvent(
      event, []() {}, [](const FlutterError & /*error*/) {});
}

// -----------------------------------------------------------------------------
// ScreenProtectionHostApi implementation
// -----------------------------------------------------------------------------

ErrorOr<bool> XueHuaScreenProtectionPlugin::SetSecureScreen(bool enabled) {
  return ApplyDisplayAffinity(enabled);
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::IsSecureScreenEnabled() {
  return is_secure_screen_enabled_;
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::ConfigureAppSwitcherProtection(
    const ScreenProtectionMaskConfigMessage &config) {
  mask_enabled_ = config.enabled();
  mask_style_ = config.style();
  mask_blur_sigma_ = config.blur_sigma();
  mask_background_color_ = static_cast<uint32_t>(config.background_color());
  mask_text_color_ = static_cast<uint32_t>(config.text_color());
  mask_title_ =
      config.title().empty() ? "Privacy Protected" : config.title();
  mask_subtitle_ = config.subtitle();
  mask_show_lock_icon_ = config.show_lock_icon();
  protect_on_window_blur_ = config.protect_on_window_blur();

  if (!mask_enabled_ ||
      mask_style_ == ScreenProtectionMaskStyleMessage::kNone) {
    SetPrivacyMaskVisible(false, "config_disabled");
  } else if (is_mask_currently_visible_) {
    HWND hwnd = GetMainWindowHandle();
    if (hwnd != nullptr) UpdateOverlayLayout(hwnd);
  }
  return true;
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::ConfigureWebProtection(
    const WebProtectionConfigMessage & /*config*/) {
  return false;
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::IsScreenBeingRecorded() {
  return false;
}

ErrorOr<ScreenProtectionStatusMessage>
XueHuaScreenProtectionPlugin::GetProtectionStatus() {
  return ScreenProtectionStatusMessage(
      is_secure_screen_enabled_,
      mask_enabled_ && mask_style_ != ScreenProtectionMaskStyleMessage::kNone,
      false, is_mask_currently_visible_, "windows");
}

ErrorOr<ScreenProtectionCapabilitiesMessage>
XueHuaScreenProtectionPlugin::GetCapabilities() {
  std::string os_ver = IsWindows10OrGreater() ? "Windows 10/11+" : "Windows";
  flutter::EncodableList limitations = {
      flutter::EncodableValue(
          "Windows blocks all screen recording and screenshots at the DWM level via SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE), so separate active-recording detection is not exposed by Win32."),
  };
  return ScreenProtectionCapabilitiesMessage("windows", os_ver, true, true,
                                             true, false, true, true,
                                             limitations);
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::ShowPrivacyMask() {
  SetPrivacyMaskVisible(true, "manual");
  return true;
}

ErrorOr<bool> XueHuaScreenProtectionPlugin::HidePrivacyMask() {
  SetPrivacyMaskVisible(false, "manual");
  return true;
}

}  // namespace xue_hua_screen_protection
