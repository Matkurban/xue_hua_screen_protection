#ifndef FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_PRIVATE_H_
#define FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_PRIVATE_H_

#include <flutter_linux/flutter_linux.h>

#include "include/xue_hua_screen_protection/xue_hua_screen_protection_plugin.h"
#include "messages.g.h"

// Exposes plugin internals for unit testing on Linux.
XueHuaScreenProtectionScreenProtectionCapabilitiesMessage*
get_linux_capabilities_message();

#endif  // FLUTTER_PLUGIN_XUE_HUA_SCREEN_PROTECTION_PLUGIN_PRIVATE_H_
