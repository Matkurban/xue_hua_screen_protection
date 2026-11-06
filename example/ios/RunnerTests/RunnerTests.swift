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

    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { !$0.isHidden } ?? UIApplication.shared.delegate?.window ?? nil
    if let window = window {
      let winMaskEnabled = (window.layer.value(forKey: "disableUpdateMask") as? NSNumber)?.intValue ?? 0
      XCTAssertNotEqual(winMaskEnabled, 0, "window.layer disableUpdateMask should be set when enabled")
    }

    let disableCall = FlutterMethodCall(
      methodName: "setSecureScreen",
      arguments: ["enabled": false]
    )
    let disableExpectation = expectation(description: "disableSecureScreen completes")
    plugin.handle(disableCall) { result in
      XCTAssertEqual(result as? Bool, true)
      disableExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)

    let queryDisabledExpectation = expectation(description: "isSecureScreenEnabled after disable completes")
    plugin.handle(queryCall) { result in
      XCTAssertEqual(result as? Bool, false)
      queryDisabledExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)

    if let window = window {
      let winMaskDisabled = (window.layer.value(forKey: "disableUpdateMask") as? NSNumber)?.intValue ?? -1
      let rootMaskDisabled = (window.rootViewController?.view.layer.value(forKey: "disableUpdateMask") as? NSNumber)?.intValue ?? -1
      let superlayerMaskDisabled = (window.layer.superlayer?.value(forKey: "disableUpdateMask") as? NSNumber)?.intValue ?? -1
      XCTAssertEqual(winMaskDisabled, 0, "window.layer disableUpdateMask must be cleared on disable")
      XCTAssertEqual(rootMaskDisabled, 0, "rootViewController.view.layer disableUpdateMask must be cleared on disable")
      XCTAssertEqual(superlayerMaskDisabled, 0, "window.layer.superlayer disableUpdateMask must be cleared on disable")
    }
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
