import Flutter
import UIKit

/// iOS implementation of `xue_hua_screen_protection`.
///
/// Capabilities:
/// - Hardware screenshot & recording protection via dual CoreAnimation layer hardening:
///   1. Hosting `UIWindow.layer` inside `UITextField`'s `_UITextLayoutCanvasView` secure sublayer
///      (`field.layer.sublayers?.last` on iOS 17/18/26+ and `CanvasView` lookup).
///   2. Applying UIKit's internal `_UITextLayoutCanvasView` secure layer mask directly onto
///      `window.layer` and `rootViewController.view.layer`.
/// - Screenshot detection via `UIApplication.userDidTakeScreenshotNotification`.
/// - Screen recording / AirPlay mirroring detection via `UIScreen.capturedDidChangeNotification`
///   and `UIScreen.main.isCaptured`.
/// - Native app-switcher / inactive privacy overlay using `UIVisualEffectView` blur or solid color.
public class XueHuaScreenProtectionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "com.kurban.xue_hua_screen_protection/methods"
  private static let eventChannelName = "com.kurban.xue_hua_screen_protection/events"

  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?

  private var isSecureScreenEnabled: Bool = false
  private var isMaskCurrentlyVisible: Bool = false

  // App-switcher mask config
  private var maskEnabled: Bool = false
  private var maskStyle: String = "blur"
  private var maskBlurSigma: Double = 20.0
  private var maskBackgroundColor: UIColor = UIColor(
    red: 15.0 / 255.0,
    green: 23.0 / 255.0,
    blue: 42.0 / 255.0,
    alpha: 0.92
  )
  private var maskTextColor: UIColor = .white
  private var maskTitle: String = "Privacy Protected"
  private var maskSubtitle: String = "Screen content is hidden to protect sensitive information."
  private var maskShowLockIcon: Bool = true
  private var protectOnWindowBlur: Bool = true

  // Per-window secure UITextField containers & privacy overlay view
  private var windowSecureFields: [ObjectIdentifier: UITextField] = [:]
  private var privacyOverlayView: UIView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )

    let instance = XueHuaScreenProtectionPlugin()
    instance.methodChannel = methodChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    instance.registerSystemNotifications()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - MethodChannel Handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setSecureScreen":
      let args = call.arguments as? [String: Any]
      let enabled = args?["enabled"] as? Bool ?? false
      isSecureScreenEnabled = enabled
      DispatchQueue.main.async {
        self.applySecureScreen(enabled: enabled)
        result(true)
      }

    case "isSecureScreenEnabled":
      result(isSecureScreenEnabled)

    case "configureAppSwitcherProtection":
      let args = call.arguments as? [String: Any] ?? [:]
      maskEnabled = args["enabled"] as? Bool ?? true
      maskStyle = args["style"] as? String ?? "blur"
      maskBlurSigma = args["blurSigma"] as? Double ?? 20.0
      if let bgInt = args["backgroundColor"] as? Int {
        maskBackgroundColor = Self.colorFromARGB(bgInt)
      }
      if let fgInt = args["textColor"] as? Int {
        maskTextColor = Self.colorFromARGB(fgInt)
      }
      maskTitle = args["title"] as? String ?? "Privacy Protected"
      maskSubtitle = args["subtitle"] as? String ?? ""
      maskShowLockIcon = args["showLockIcon"] as? Bool ?? true
      protectOnWindowBlur = args["protectOnWindowBlur"] as? Bool ?? true

      DispatchQueue.main.async {
        if !self.maskEnabled || self.maskStyle == "none" {
          self.setPrivacyOverlayVisible(false, reason: "config_disabled")
        } else if self.isMaskCurrentlyVisible {
          self.rebuildPrivacyOverlayIfNeeded()
        }
        result(true)
      }

    case "configureWebProtection":
      result(false)

    case "isScreenBeingRecorded":
      result(UIScreen.main.isCaptured)

    case "getProtectionStatus":
      result([
        "isSecureScreenEnabled": isSecureScreenEnabled,
        "isAppSwitcherMaskEnabled": maskEnabled && maskStyle != "none",
        "isScreenBeingRecorded": UIScreen.main.isCaptured,
        "isMaskCurrentlyVisible": isMaskCurrentlyVisible,
        "platform": "ios",
      ])

    case "getCapabilities":
      let version = UIDevice.current.systemVersion
      result([
        "platform": "ios",
        "osVersion": "iOS \(version)",
        "supportsHardwareAntiScreenshot": true,
        "supportsHardwareAntiRecording": true,
        "supportsScreenshotDetection": true,
        "supportsRecordingDetection": true,
        "supportsNativeAppSwitcherMask": true,
        "supportsNativeBlurEffect": true,
        "limitations": [
          "iOS notifies screenshot events after capture; enableSecureScreen() excludes window layers from screenshots and screen recordings via CoreAnimation secure canvas layers."
        ],
      ])

    case "showPrivacyMask":
      DispatchQueue.main.async {
        self.setPrivacyOverlayVisible(true, reason: "manual")
        result(true)
      }

    case "hidePrivacyMask":
      DispatchQueue.main.async {
        self.setPrivacyOverlayVisible(false, reason: "manual")
        result(true)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - System Notifications

  private func registerSystemNotifications() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(handleUserDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(handleCapturedDidChange),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(handleWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc private func handleUserDidTakeScreenshot() {
    emitEvent(
      type: "screenshotTaken",
      metadata: ["source": "UIApplication.userDidTakeScreenshotNotification"]
    )
  }

  @objc private func handleCapturedDidChange() {
    let captured = UIScreen.main.isCaptured
    emitEvent(
      type: captured ? "recordingStarted" : "recordingStopped",
      metadata: ["source": "UIScreen.capturedDidChangeNotification"]
    )
  }

  @objc private func handleWillResignActive() {
    guard maskEnabled && maskStyle != "none" else { return }
    setPrivacyOverlayVisible(true, reason: "will_resign_active")
  }

  @objc private func handleDidBecomeActive() {
    setPrivacyOverlayVisible(false, reason: "did_become_active")
    if isSecureScreenEnabled {
      applySecureScreen(enabled: true)
    }
  }

  // MARK: - Secure Screen Implementation (CoreAnimation + UITextField Secure Canvas Layer)

  private func targetWindows() -> [UIWindow] {
    var windows: [UIWindow] = []
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      for window in scene.windows where !window.isHidden {
        if !windows.contains(where: { $0 === window }) {
          windows.append(window)
        }
      }
    }
    if let delegateWindow = UIApplication.shared.delegate?.window ?? nil {
      if !windows.contains(where: { $0 === delegateWindow }) {
        windows.append(delegateWindow)
      }
    }
    return windows
  }

  private func activeKeyWindow() -> UIWindow? {
    let windows = targetWindows()
    if let keyWindow = windows.first(where: { $0.isKeyWindow }) {
      return keyWindow
    }
    if let flutterWindow = windows.first(where: { $0.rootViewController is FlutterViewController }) {
      return flutterWindow
    }
    return windows.first
  }

  private func applySecureScreen(enabled: Bool) {
    isSecureScreenEnabled = enabled
    let windows = targetWindows()
    guard !windows.isEmpty else {
      // Window scene not yet attached; retry on next runloop turn.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        guard let self = self, self.isSecureScreenEnabled == enabled else { return }
        if !self.targetWindows().isEmpty {
          self.applySecureScreen(enabled: enabled)
        }
      }
      return
    }

    for window in windows {
      ensureWindowLayerHostedInSecureField(window, enabled: enabled)
      applyKvcSecureFlag(to: window.layer, enabled: enabled)
      if let rootLayer = window.rootViewController?.view.layer {
        applyKvcSecureFlag(to: rootLayer, enabled: enabled)
      }
    }
  }

  /// Hosts `window.layer` inside a `UITextField`'s internal `_UITextLayoutCanvasView`
  /// layer (`field.layer.sublayers?.last` on iOS 17/18/26+) while keeping `field.frame`
  /// at `.zero` and `semanticContentAttribute = .forceLeftToRight` so `window.layer`
  /// remains aligned at `(0, 0)` and touch handling on `window` is unaffected.
  private func ensureWindowLayerHostedInSecureField(_ window: UIWindow, enabled: Bool) {
    let key = ObjectIdentifier(window)
    if let existingField = windowSecureFields[key] {
      existingField.isSecureTextEntry = enabled
      return
    }

    guard enabled else { return }

    guard let windowSuperlayer = window.layer.superlayer else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
        guard let self = self, let window = window else { return }
        self.ensureWindowLayerHostedInSecureField(window, enabled: self.isSecureScreenEnabled)
      }
      return
    }

    let field = UITextField()
    let leftView = UIView(
      frame: CGRect(x: 0, y: 0, width: field.frame.width, height: field.frame.height)
    )
    field.backgroundColor = .clear
    field.isUserInteractionEnabled = false
    field.isSecureTextEntry = true
    field.semanticContentAttribute = .forceLeftToRight
    field.leftView = leftView
    field.leftViewMode = .always

    window.addSubview(field)
    field.setNeedsLayout()
    field.layoutIfNeeded()

    windowSuperlayer.addSublayer(field.layer)

    let secureSublayer: CALayer? = {
      if let canvasSubview = field.subviews.first(where: {
        let name = NSStringFromClass(type(of: $0))
        return name.contains("TextLayoutCanvasView") || name.contains("CanvasView")
      }) {
        return canvasSubview.layer
      }
      return field.layer.sublayers?.last ?? field.layer.sublayers?.first
    }()

    secureSublayer?.addSublayer(window.layer)
    field.isSecureTextEntry = enabled
    windowSecureFields[key] = field
  }

  /// Applies UIKit's internal `_UITextLayoutCanvasView` capture-exclusion mask directly
  /// to the given `CALayer` by temporarily binding it to a detached `UITextField`'s
  /// canvas subview and toggling `isSecureTextEntry`.
  private func applyKvcSecureFlag(to layer: CALayer, enabled: Bool) {
    let textField = UITextField()
    textField.isSecureTextEntry = !enabled
    let canvasView = textField.subviews.first(where: {
      let name = NSStringFromClass(type(of: $0))
      return name.contains("TextLayoutCanvasView") || name.contains("CanvasView")
    }) ?? textField.subviews.first

    guard let secureView = canvasView else { return }
    let previousLayer = secureView.layer
    secureView.setValue(layer, forKey: "layer")
    textField.isSecureTextEntry = enabled
    secureView.setValue(previousLayer, forKey: "layer")
  }

  // MARK: - App Switcher Privacy Overlay

  private func setPrivacyOverlayVisible(_ visible: Bool, reason: String) {
    guard let window = activeKeyWindow() else { return }

    if visible {
      if privacyOverlayView == nil {
        let overlay = buildPrivacyOverlay(frame: window.bounds)
        window.addSubview(overlay)
        privacyOverlayView = overlay
      }
      privacyOverlayView?.frame = window.bounds
      if let overlay = privacyOverlayView {
        window.bringSubviewToFront(overlay)
      }
      if !isMaskCurrentlyVisible {
        isMaskCurrentlyVisible = true
        emitEvent(type: "maskShown", metadata: ["reason": reason])
      }
    } else {
      privacyOverlayView?.removeFromSuperview()
      privacyOverlayView = nil
      if isMaskCurrentlyVisible {
        isMaskCurrentlyVisible = false
        emitEvent(type: "maskHidden", metadata: ["reason": reason])
      }
    }
  }

  private func rebuildPrivacyOverlayIfNeeded() {
    guard isMaskCurrentlyVisible else { return }
    privacyOverlayView?.removeFromSuperview()
    privacyOverlayView = nil
    isMaskCurrentlyVisible = false
    setPrivacyOverlayVisible(true, reason: "config_updated")
  }

  private func buildPrivacyOverlay(frame: CGRect) -> UIView {
    let container = UIView(frame: frame)
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.isUserInteractionEnabled = true

    if maskStyle == "blur" {
      let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
      let blurView = UIVisualEffectView(effect: blurEffect)
      blurView.frame = container.bounds
      blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(blurView)

      let tintOverlay = UIView(frame: container.bounds)
      tintOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      tintOverlay.backgroundColor = maskBackgroundColor.withAlphaComponent(0.65)
      container.addSubview(tintOverlay)
    } else {
      container.backgroundColor = maskBackgroundColor
    }

    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false

    if maskShowLockIcon {
      let iconConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
      let iconImage = UIImage(systemName: "lock.shield.fill", withConfiguration: iconConfig)
      let imageView = UIImageView(image: iconImage)
      imageView.tintColor = maskTextColor
      stack.addArrangedSubview(imageView)
    }

    if !maskTitle.isEmpty {
      let titleLabel = UILabel()
      titleLabel.text = maskTitle
      titleLabel.textColor = maskTextColor
      titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
      titleLabel.textAlignment = .center
      titleLabel.numberOfLines = 0
      stack.addArrangedSubview(titleLabel)
    }

    if !maskSubtitle.isEmpty {
      let subtitleLabel = UILabel()
      subtitleLabel.text = maskSubtitle
      subtitleLabel.textColor = maskTextColor.withAlphaComponent(0.82)
      subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
      subtitleLabel.textAlignment = .center
      subtitleLabel.numberOfLines = 0
      stack.addArrangedSubview(subtitleLabel)
    }

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
    ])

    return container
  }

  // MARK: - Helpers & Event Emission

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }

  private func emitEvent(type: String, metadata: [String: Any] = [:]) {
    let payload: [String: Any] = [
      "type": type,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
      "platform": "ios",
      "isCaptured": UIScreen.main.isCaptured,
      "metadata": metadata,
    ]
    DispatchQueue.main.async {
      self.eventSink?(payload)
      self.methodChannel?.invokeMethod("onProtectionEvent", arguments: payload)
    }
  }
}
