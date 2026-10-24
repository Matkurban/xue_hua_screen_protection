#ifndef FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace xue_hua_screen_protection {

class XueHuaScreenProtectionPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  XueHuaScreenProtectionPlugin();

  virtual ~XueHuaScreenProtectionPlugin();

  // Disallow copy and assign.
  XueHuaScreenProtectionPlugin(const XueHuaScreenProtectionPlugin&) = delete;
  XueHuaScreenProtectionPlugin& operator=(const XueHuaScreenProtectionPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace xue_hua_screen_protection

#endif  // FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_H_
