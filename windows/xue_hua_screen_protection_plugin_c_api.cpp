#include "include/xue_hua_screen_protection/xue_hua_screen_protection_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "xue_hua_screen_protection_plugin.h"

void XueHuaScreenProtectionPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  xue_hua_screen_protection::XueHuaScreenProtectionPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
