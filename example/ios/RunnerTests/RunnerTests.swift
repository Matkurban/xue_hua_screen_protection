import Flutter
import UIKit
import XCTest

@testable import xue_hua_screen_protection

class RunnerTests: XCTestCase {

  func testSetAndQuerySecureScreen() {
    let plugin = XueHuaScreenProtectionPlugin()

    let enableCall = FlutterMethodCall(
      methodName: "setSecureScreen",
      arguments: ["enabled": true]
    )

    let enableExpectation = expectation(description: "setSecureScreen completes")
    plugin.handle(enableCall) { result in
      XCTAssertEqual(result as? Bool, true)
      enableExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)

    let queryCall = FlutterMethodCall(
      methodName: "isSecureScreenEnabled",
      arguments: nil
    )
    let queryExpectation = expectation(description: "isSecureScreenEnabled completes")
    plugin.handle(queryCall) { result in
      XCTAssertEqual(result as? Bool, true)
      queryExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testGetCapabilitiesReturnsIOS() {
    let plugin = XueHuaScreenProtectionPlugin()
    let call = FlutterMethodCall(methodName: "getCapabilities", arguments: nil)

    let expectation = expectation(description: "getCapabilities completes")
    plugin.handle(call) { result in
      let map = result as? [String: Any]
      XCTAssertEqual(map?["platform"] as? String, "ios")
      XCTAssertEqual(map?["supportsHardwareAntiScreenshot"] as? Bool, true)
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
