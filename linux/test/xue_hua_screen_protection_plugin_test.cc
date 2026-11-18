#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/xue_hua_screen_protection/xue_hua_screen_protection_plugin.h"
#include "messages.g.h"
#include "xue_hua_screen_protection_plugin_private.h"

namespace xue_hua_screen_protection {
namespace test {

TEST(XueHuaScreenProtectionPlugin, GetCapabilitiesReturnsPigeonLinuxMessage) {
  g_autoptr(XueHuaScreenProtectionScreenProtectionCapabilitiesMessage) caps =
      get_linux_capabilities_message();
  ASSERT_NE(caps, nullptr);
  EXPECT_STREQ(
      xue_hua_screen_protection_screen_protection_capabilities_message_get_platform(
          caps),
      "linux");
  EXPECT_FALSE(
      xue_hua_screen_protection_screen_protection_capabilities_message_get_supports_hardware_anti_screenshot(
          caps));
  EXPECT_TRUE(
      xue_hua_screen_protection_screen_protection_capabilities_message_get_supports_native_app_switcher_mask(
          caps));
}

}  // namespace test
}  // namespace xue_hua_screen_protection
