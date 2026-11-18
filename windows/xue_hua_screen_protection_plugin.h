#ifndef FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

#include "messages.g.h"

namespace xue_hua_screen_protection {

class XueHuaScreenProtectionPlugin : public flutter::Plugin,
                                     public ScreenProtectionHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit XueHuaScreenProtectionPlugin(
      flutter::PluginRegistrarWindows *registrar = nullptr);

  ~XueHuaScreenProtectionPlugin() override;

  // Disallow copy and assign.
  XueHuaScreenProtectionPlugin(const XueHuaScreenProtectionPlugin &) = delete;
  XueHuaScreenProtectionPlugin &operator=(
      const XueHuaScreenProtectionPlugin &) = delete;

  // ScreenProtectionHostApi implementation.
  ErrorOr<bool> SetSecureScreen(bool enabled) override;
  ErrorOr<bool> IsSecureScreenEnabled() override;
  ErrorOr<bool> ConfigureAppSwitcherProtection(
      const ScreenProtectionMaskConfigMessage &config) override;
  ErrorOr<bool> ConfigureWebProtection(
      const WebProtectionConfigMessage &config) override;
  ErrorOr<bool> IsScreenBeingRecorded() override;
  ErrorOr<ScreenProtectionStatusMessage> GetProtectionStatus() override;
  ErrorOr<ScreenProtectionCapabilitiesMessage> GetCapabilities() override;
  ErrorOr<bool> ShowPrivacyMask() override;
  ErrorOr<bool> HidePrivacyMask() override;

 private:
  HWND GetMainWindowHandle() const;
  bool ApplyDisplayAffinity(bool enabled);
  void SetPrivacyMaskVisible(bool visible, const std::string &reason);
  void EnsureOverlayWindowCreated(HWND parent_hwnd);
  void DestroyOverlayWindow();
  void UpdateOverlayLayout(HWND parent_hwnd);
  void EmitEvent(ScreenProtectionEventTypeMessage type,
                 const flutter::EncodableMap &metadata = {});

  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);

  static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                         LPARAM lparam);

  flutter::PluginRegistrarWindows *registrar_ = nullptr;
  std::unique_ptr<ScreenProtectionFlutterApi> flutter_api_;

  int window_proc_id_ = -1;
  bool clipboard_listener_registered_ = false;
  HWND tracked_hwnd_ = nullptr;
  HWND overlay_hwnd_ = nullptr;

  bool is_secure_screen_enabled_ = false;
  bool is_mask_currently_visible_ = false;

  bool mask_enabled_ = false;
  ScreenProtectionMaskStyleMessage mask_style_ =
      ScreenProtectionMaskStyleMessage::kBlur;
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
