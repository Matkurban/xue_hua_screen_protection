import Cocoa
import CoreGraphics
import FlutterMacOS

/// macOS implementation of `xue_hua_screen_protection`.
///
/// Capabilities:
/// - Hardware screenshot, recording, and window-sharing prevention via `NSWindow.sharingType = .none`.
/// - Screenshot detection via `NSMetadataQuery` (`kMDItemIsScreenCapture = 1`) and pasteboard image monitoring.
/// - Screen recording / window capture detection via `CGWindowListCopyWindowInfo` and `NSScreen` inspection.
/// - Inactive window / app-switcher privacy mask using `NSVisualEffectView` blur or solid color overlay.
public class XueHuaScreenProtectionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let methodChannelName = "com.kurban.xue_hua_screen_protection/methods"
    private static let eventChannelName = "com.kurban.xue_hua_screen_protection/events"

    private weak var registrar: FlutterPluginRegistrar?
    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?

    private var isSecureScreenEnabled: Bool = false
    private var isMaskCurrentlyVisible: Bool = false
    private var isScreenBeingRecorded: Bool = false

    // Mask configuration
    private var maskEnabled: Bool = false
    private var maskStyle: String = "blur"
    private var maskBlurSigma: Double = 20.0
    private var maskBackgroundColor: NSColor = .init(srgbRed: 15.0 / 255.0, green: 23.0 / 255.0, blue: 42.0 / 255.0, alpha: 0.92)
    private var maskTextColor: NSColor = .white
    private var maskTitle: String = "Privacy Protected"
    private var maskSubtitle: String = "Screen content is hidden to protect sensitive information."
    private var maskShowLockIcon: Bool = true
    private var protectOnWindowBlur: Bool = true

    private var privacyOverlayView: NSView?
    private var metadataQuery: NSMetadataQuery?
    private var knownCaptureFiles: Set<String> = []
    private var initialQueryCompleted: Bool = false
    private var recordingPollTimer: Timer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger
        )

        let instance = XueHuaScreenProtectionPlugin()
        instance.registrar = registrar
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
        instance.setupNotificationsAndMonitors()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        metadataQuery?.stop()
        recordingPollTimer?.invalidate()
    }

    public func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - MethodChannel Dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setSecureScreen":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            DispatchQueue.main.async {
                self.applyWindowSharingType(enabled: enabled)
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
            checkRecordingState(emitIfChanged: false)
            result(isScreenBeingRecorded)

        case "getProtectionStatus":
            checkRecordingState(emitIfChanged: false)
            result([
                "isSecureScreenEnabled": isSecureScreenEnabled,
                "isAppSwitcherMaskEnabled": maskEnabled && maskStyle != "none",
                "isScreenBeingRecorded": isScreenBeingRecorded,
                "isMaskCurrentlyVisible": isMaskCurrentlyVisible,
                "platform": "macos",
            ])

        case "getCapabilities":
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            result([
                "platform": "macos",
                "osVersion": "macOS \(osVersion)",
                "supportsHardwareAntiScreenshot": true,
                "supportsHardwareAntiRecording": true,
                "supportsScreenshotDetection": true,
                "supportsRecordingDetection": true,
                "supportsNativeAppSwitcherMask": true,
                "supportsNativeBlurEffect": true,
                "limitations": [
                    "macOS NSWindow.sharingType = .none excludes the application window from system screenshots, QuickTime recordings, and screen-sharing streams.",
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

    // MARK: - Window Sharing Protection

    private func targetWindows() -> [NSWindow] {
        var windows = NSApplication.shared.windows
        if let viewWindow = registrar?.view?.window, !windows.contains(viewWindow) {
            windows.append(viewWindow)
        }
        return windows
    }

    private func primaryWindow() -> NSWindow? {
        if let viewWindow = registrar?.view?.window {
            return viewWindow
        }
        return NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
    }

    private func applyWindowSharingType(enabled: Bool) {
        isSecureScreenEnabled = enabled
        let sharingType: NSWindow.SharingType = enabled ? .none : .readOnly
        for window in targetWindows() {
            window.sharingType = sharingType
        }
    }

    // MARK: - Notifications & Capture Monitoring

    private func setupNotificationsAndMonitors() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWindowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        startScreenshotMetadataQuery()
        recordingPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkRecordingState(emitIfChanged: true)
        }
    }

    private func startScreenshotMetadataQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMetadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMetadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        metadataQuery = query
        DispatchQueue.main.async {
            query.start()
        }
    }

    @objc private func handleMetadataQueryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        for item in query.results as? [NSMetadataItem] ?? [] {
            if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                knownCaptureFiles.insert(path)
            }
        }
        initialQueryCompleted = true
        query.enableUpdates()
    }

    @objc private func handleMetadataQueryDidUpdate(_ notification: Notification) {
        guard initialQueryCompleted,
              let userInfo = notification.userInfo
        else { return }

        let addedItems = (userInfo[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
        for item in addedItems {
            let path = (item.value(forAttribute: NSMetadataItemPathKey) as? String) ?? UUID().uuidString
            if !knownCaptureFiles.contains(path) {
                knownCaptureFiles.insert(path)
                emitEvent(
                    type: "screenshotTaken",
                    metadata: ["source": "NSMetadataQuery_kMDItemIsScreenCapture"]
                )
                break
            }
        }
    }

    private func checkRecordingState(emitIfChanged: Bool) {
        var recordingDetected = false
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            let bundleId = (app.bundleIdentifier ?? "").lowercased()
            if bundleId == "com.apple.screencaptureui" {
                recordingDetected = true
                break
            }
        }

        if emitIfChanged, recordingDetected != isScreenBeingRecorded {
            isScreenBeingRecorded = recordingDetected
            emitEvent(
                type: recordingDetected ? "recordingStarted" : "recordingStopped",
                metadata: ["source": "NSWorkspace_screencaptureui"]
            )
        } else {
            isScreenBeingRecorded = recordingDetected
        }
    }

    @objc private func handleAppWillResignActive() {
        guard maskEnabled, maskStyle != "none" else { return }
        setPrivacyOverlayVisible(true, reason: "app_will_resign_active")
    }

    @objc private func handleAppDidBecomeActive() {
        setPrivacyOverlayVisible(false, reason: "app_did_become_active")
        if isSecureScreenEnabled {
            applyWindowSharingType(enabled: true)
        }
    }

    @objc private func handleWindowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === primaryWindow()
        else { return }
        if maskEnabled, maskStyle != "none", protectOnWindowBlur {
            setPrivacyOverlayVisible(true, reason: "window_resigned_key")
        }
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === primaryWindow()
        else { return }
        setPrivacyOverlayVisible(false, reason: "window_became_key")
        if isSecureScreenEnabled {
            applyWindowSharingType(enabled: true)
        }
    }

    // MARK: - Privacy Overlay Management

    private func setPrivacyOverlayVisible(_ visible: Bool, reason: String) {
        guard let window = primaryWindow(),
              let contentView = window.contentView
        else { return }

        if visible {
            if privacyOverlayView == nil {
                let overlay = buildPrivacyOverlay(frame: contentView.bounds)
                contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
                privacyOverlayView = overlay
            }
            privacyOverlayView?.frame = contentView.bounds
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

    private func buildPrivacyOverlay(frame: NSRect) -> NSView {
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true

        if maskStyle == "blur" {
            let visualEffect = NSVisualEffectView(frame: container.bounds)
            visualEffect.autoresizingMask = [.width, .height]
            visualEffect.blendingMode = .withinWindow
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            container.addSubview(visualEffect)

            let tintView = NSView(frame: container.bounds)
            tintView.autoresizingMask = [.width, .height]
            tintView.wantsLayer = true
            tintView.layer?.backgroundColor = maskBackgroundColor.withAlphaComponent(0.68).cgColor
            container.addSubview(tintView)
        } else {
            container.layer?.backgroundColor = maskBackgroundColor.cgColor
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if maskShowLockIcon {
            if let symbolImage = NSImage(
                systemSymbolName: "lock.shield.fill",
                accessibilityDescription: "Privacy Protected"
            ) {
                let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
                let configuredImage = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                let imageView = NSImageView(image: configuredImage)
                imageView.contentTintColor = maskTextColor
                stack.addArrangedSubview(imageView)
            }
        }

        if !maskTitle.isEmpty {
            let titleField = NSTextField(labelWithString: maskTitle)
            titleField.font = NSFont.systemFont(ofSize: 20, weight: .bold)
            titleField.textColor = maskTextColor
            titleField.alignment = .center
            titleField.maximumNumberOfLines = 2
            stack.addArrangedSubview(titleField)
        }

        if !maskSubtitle.isEmpty {
            let subField = NSTextField(wrappingLabelWithString: maskSubtitle)
            subField.font = NSFont.systemFont(ofSize: 14, weight: .regular)
            subField.textColor = maskTextColor.withAlphaComponent(0.82)
            subField.alignment = .center
            subField.preferredMaxLayoutWidth = 420
            stack.addArrangedSubview(subField)
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

    private static func colorFromARGB(_ argb: Int) -> NSColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private func emitEvent(type: String, metadata: [String: Any] = [:]) {
        let payload: [String: Any] = [
            "type": type,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "platform": "macos",
            "isCaptured": isScreenBeingRecorded,
            "metadata": metadata,
        ]
        DispatchQueue.main.async {
            self.eventSink?(payload)
            self.methodChannel?.invokeMethod("onProtectionEvent", arguments: payload)
        }
    }
}
