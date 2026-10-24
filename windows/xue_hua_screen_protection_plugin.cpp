#include "xue_hua_screen_protection_plugin.h"

#include <VersionHelpers.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <chrono>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

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

constexpr char kMethodChannelName[] =
    "com.kurban.xue_hua_screen_protection/methods";
constexpr char kEventChannelName[] =
    "com.kurban.xue_hua_screen_protection/events";
constexpr wchar_t kOverlayClassName[] = L"XueHuaScreenProtectionOverlayClass";
constexpr ULONGLONG kScreenshotDebounceMs = 1200;

std::wstring Utf8ToWide(const std::string &utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(count, 0);
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

  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  XueHuaScreenProtectionPlugin *plugin_ptr = plugin.get();

  method_channel->SetMethodCallHandler(
      [plugin_ptr](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  auto stream_handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_ptr](
          const flutter::EncodableValue *arguments,
          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        plugin_ptr->SetEventSink(std::move(events));
        return nullptr;
      },
      [plugin_ptr](const flutter::EncodableValue *arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        plugin_ptr->SetEventSink(nullptr);
        return nullptr;
      });

  event_channel->SetStreamHandler(std::move(stream_handler));

  plugin->method_channel_ = std::move(method_channel);
  plugin->event_channel_ = std::move(event_channel);

  registrar->AddPlugin(std::move(plugin));
}

XueHuaScreenProtectionPlugin::XueHuaScreenProtectionPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  if (registrar_ != nullptr) {
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
  if (registrar_ != nullptr && window_proc_id_ != -1) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

void XueHuaScreenProtectionPlugin::SetEventSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  event_sink_ = std::move(sink);
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
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
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
        if (mask_enabled_ && mask_style_ != "none" && protect_on_window_blur_) {
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
          EmitEvent("screenshotTaken",
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
          EmitEvent("screenshotTaken",
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
      EmitEvent("maskShown",
                {{flutter::EncodableValue("reason"),
                  flutter::EncodableValue(reason)}});
    }
  } else {
    if (overlay_hwnd_ != nullptr && IsWindow(overlay_hwnd_)) {
      ShowWindow(overlay_hwnd_, SW_HIDE);
    }
    if (is_mask_currently_visible_) {
      is_mask_currently_visible_ = false;
      EmitEvent("maskHidden",
                {{flutter::EncodableValue("reason"),
                  flutter::EncodableValue(reason)}});
    }
  }
}

void XueHuaScreenProtectionPlugin::EmitEvent(
    const std::string &type, const flutter::EncodableMap &metadata) {
  flutter::EncodableMap payload = {
      {flutter::EncodableValue("type"), flutter::EncodableValue(type)},
      {flutter::EncodableValue("timestamp"),
       flutter::EncodableValue(CurrentEpochMillis())},
      {flutter::EncodableValue("platform"),
       flutter::EncodableValue("windows")},
      {flutter::EncodableValue("isCaptured"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("metadata"), flutter::EncodableValue(metadata)},
  };

  flutter::EncodableValue event_val(payload);
  if (event_sink_ != nullptr) {
    event_sink_->Success(event_val);
  }
  if (method_channel_ != nullptr) {
    method_channel_->InvokeMethod(
        "onProtectionEvent",
        std::make_unique<flutter::EncodableValue>(event_val));
  }
}

void XueHuaScreenProtectionPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string &method = method_call.method_name();

  if (method == "setSecureScreen") {
    bool enabled = false;
    if (const auto *args =
            std::get_if<flutter::EncodableMap>(method_call.arguments())) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto *val = std::get_if<bool>(&it->second)) {
          enabled = *val;
        }
      }
    }
    bool ok = ApplyDisplayAffinity(enabled);
    result->Success(flutter::EncodableValue(ok));
  } else if (method == "isSecureScreenEnabled") {
    result->Success(flutter::EncodableValue(is_secure_screen_enabled_));
  } else if (method == "configureAppSwitcherProtection") {
    if (const auto *args =
            std::get_if<flutter::EncodableMap>(method_call.arguments())) {
      auto get_bool = [&](const char *key, bool fallback) {
        auto it = args->find(flutter::EncodableValue(key));
        if (it != args->end()) {
          if (const auto *v = std::get_if<bool>(&it->second)) return *v;
        }
        return fallback;
      };
      auto get_string = [&](const char *key, const std::string &fallback) {
        auto it = args->find(flutter::EncodableValue(key));
        if (it != args->end()) {
          if (const auto *v = std::get_if<std::string>(&it->second)) return *v;
        }
        return fallback;
      };
      auto get_uint32 = [&](const char *key, uint32_t fallback) {
        auto it = args->find(flutter::EncodableValue(key));
        if (it != args->end()) {
          if (const auto *v32 = std::get_if<int32_t>(&it->second)) {
            return static_cast<uint32_t>(*v32);
          }
          if (const auto *v64 = std::get_if<int64_t>(&it->second)) {
            return static_cast<uint32_t>(*v64);
          }
        }
        return fallback;
      };

      mask_enabled_ = get_bool("enabled", true);
      mask_style_ = get_string("style", "blur");
      mask_background_color_ = get_uint32("backgroundColor", 0xEB0F172A);
      mask_text_color_ = get_uint32("textColor", 0xFFFFFFFF);
      mask_title_ = get_string("title", "Privacy Protected");
      mask_subtitle_ = get_string(
          "subtitle",
          "Screen content is hidden to protect sensitive information.");
      mask_show_lock_icon_ = get_bool("showLockIcon", true);
      protect_on_window_blur_ = get_bool("protectOnWindowBlur", true);
    }

    if (!mask_enabled_ || mask_style_ == "none") {
      SetPrivacyMaskVisible(false, "config_disabled");
    } else if (is_mask_currently_visible_) {
      HWND hwnd = GetMainWindowHandle();
      if (hwnd != nullptr) UpdateOverlayLayout(hwnd);
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "configureWebProtection") {
    result->Success(flutter::EncodableValue(false));
  } else if (method == "isScreenBeingRecorded") {
    result->Success(flutter::EncodableValue(false));
  } else if (method == "getProtectionStatus") {
    flutter::EncodableMap status = {
        {flutter::EncodableValue("isSecureScreenEnabled"),
         flutter::EncodableValue(is_secure_screen_enabled_)},
        {flutter::EncodableValue("isAppSwitcherMaskEnabled"),
         flutter::EncodableValue(mask_enabled_ && mask_style_ != "none")},
        {flutter::EncodableValue("isScreenBeingRecorded"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("isMaskCurrentlyVisible"),
         flutter::EncodableValue(is_mask_currently_visible_)},
        {flutter::EncodableValue("platform"),
         flutter::EncodableValue("windows")},
    };
    result->Success(flutter::EncodableValue(status));
  } else if (method == "getCapabilities") {
    std::string os_ver = IsWindows10OrGreater() ? "Windows 10/11+" : "Windows";
    flutter::EncodableList limitations = {
        flutter::EncodableValue(
            "Windows blocks all screen recording and screenshots at the DWM level via SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE), so separate active-recording detection is not exposed by Win32."),
    };
    flutter::EncodableMap caps = {
        {flutter::EncodableValue("platform"),
         flutter::EncodableValue("windows")},
        {flutter::EncodableValue("osVersion"),
         flutter::EncodableValue(os_ver)},
        {flutter::EncodableValue("supportsHardwareAntiScreenshot"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("supportsHardwareAntiRecording"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("supportsScreenshotDetection"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("supportsRecordingDetection"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("supportsNativeAppSwitcherMask"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("supportsNativeBlurEffect"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("limitations"),
         flutter::EncodableValue(limitations)},
    };
    result->Success(flutter::EncodableValue(caps));
  } else if (method == "showPrivacyMask") {
    SetPrivacyMaskVisible(true, "manual");
    result->Success(flutter::EncodableValue(true));
  } else if (method == "hidePrivacyMask") {
    SetPrivacyMaskVisible(false, "manual");
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

}  // namespace xue_hua_screen_protection
