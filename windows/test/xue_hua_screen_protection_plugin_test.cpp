#include <gtest/gtest.h>
#include <windows.h>

#include "messages.g.h"
#include "xue_hua_screen_protection_plugin.h"

namespace xue_hua_screen_protection {
namespace test {

TEST(XueHuaScreenProtectionPlugin, SetAndQuerySecureScreenViaPigeonHostApi) {
  XueHuaScreenProtectionPlugin plugin;

  ErrorOr<bool> set_result = plugin.SetSecureScreen(true);
  ASSERT_FALSE(set_result.has_error());
  EXPECT_TRUE(set_result.value());

  ErrorOr<bool> is_enabled = plugin.IsSecureScreenEnabled();
  ASSERT_FALSE(is_enabled.has_error());
  EXPECT_TRUE(is_enabled.value());

  ErrorOr<ScreenProtectionStatusMessage> status = plugin.GetProtectionStatus();
  ASSERT_FALSE(status.has_error());
  EXPECT_TRUE(status.value().is_secure_screen_enabled());
  EXPECT_EQ(status.value().platform(), "windows");

  ErrorOr<ScreenProtectionCapabilitiesMessage> caps = plugin.GetCapabilities();
  ASSERT_FALSE(caps.has_error());
  EXPECT_EQ(caps.value().platform(), "windows");
  EXPECT_TRUE(caps.value().supports_hardware_anti_screenshot());
}

}  // namespace test
}  // namespace xue_hua_screen_protection
