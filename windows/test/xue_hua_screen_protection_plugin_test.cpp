#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "xue_hua_screen_protection_plugin.h"

namespace xue_hua_screen_protection {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(XueHuaScreenProtectionPlugin, SetAndQuerySecureScreen) {
  XueHuaScreenProtectionPlugin plugin;
  bool set_result = false;
  EncodableMap args = {{EncodableValue("enabled"), EncodableValue(true)}};
  plugin.HandleMethodCall(
      MethodCall("setSecureScreen", std::make_unique<EncodableValue>(args)),
      std::make_unique<MethodResultFunctions<>>(
          [&set_result](const EncodableValue *result) {
            set_result = std::get<bool>(*result);
          },
          nullptr, nullptr));
  EXPECT_TRUE(set_result);

  bool is_enabled = false;
  plugin.HandleMethodCall(
      MethodCall("isSecureScreenEnabled", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&is_enabled](const EncodableValue *result) {
            is_enabled = std::get<bool>(*result);
          },
          nullptr, nullptr));
  EXPECT_TRUE(is_enabled);
}

}  // namespace test
}  // namespace xue_hua_screen_protection
