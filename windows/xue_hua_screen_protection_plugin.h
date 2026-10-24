#ifndef FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

namespace xue_hua_screen_protection {

class XueHuaScreenProtectionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit XueHuaScreenProtectionPlugin(
      flutter::PluginRegistrarWindows *registrar = nullptr);

  virtual ~XueHuaScreenProtectionPlugin();

  // Disallow copy and assign.
  XueHuaScreenProtectionPlugin(const XueHuaScreenProtectionPlugin &) = delete;
  XueHuaScreenProtectionPlugin &operator=(
      const XueHuaScreenProtectionPlugin &) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetEventSink(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);

 private:
  HWND GetMainWindowHandle() const;
  bool ApplyDisplayAffinity(bool enabled);
  void SetPrivacyMaskVisible(bool visible, const std::string &reason);
  void EnsureOverlayWindowCreated(HWND parent_hwnd);
  void DestroyOverlayWindow();
  void UpdateOverlayLayout(HWND parent_hwnd);
  void EmitEvent(const std::string &type,
                 const flutter::EncodableMap &metadata = {});

  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);

  static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                         LPARAM lparam);

  flutter::PluginRegistrarWindows *registrar_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  int window_proc_id_ = -1;
  bool clipboard_listener_registered_ = false;
  HWND tracked_hwnd_ = nullptr;
  HWND overlay_hwnd_ = nullptr;

  bool is_secure_screen_enabled_ = false;
  bool is_mask_currently_visible_ = false;

  bool mask_enabled_ = false;
  std::string mask_style_ = "blur";
  double mask_blur_sigma_ = 20.0;
  uint32_t mask_background_color_ = 0xEB0F172A;
  uint32_t mask_text_color_ = 0xFFFFFFFF;
  std::string mask_title_ = "Privacy Protected";
  std::string mask_subtitle_ =
      "Screen content is hidden to protect sensitive information.";
  bool mask_show_lock_icon_ = true;
  bool protect_on_window_blur_ = true;

  ULONGLONG last_screenshot_tick_ = 0;
};

}  // namespace xue_hua_screen_protection

#endif  // FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_
