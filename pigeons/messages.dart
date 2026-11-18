import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/kurban/xue_hua_screen_protection/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.kurban.xue_hua_screen_protection',
    ),
    swiftOut:
        'ios/xue_hua_screen_protection/Sources/xue_hua_screen_protection/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    cppHeaderOut: 'windows/messages.g.h',
    cppSourceOut: 'windows/messages.g.cpp',
    cppOptions: CppOptions(namespace: 'xue_hua_screen_protection'),
    gobjectHeaderOut: 'linux/messages.g.h',
    gobjectSourceOut: 'linux/messages.g.cc',
    gobjectOptions: GObjectOptions(module: 'XueHuaScreenProtection'),
    dartPackageName: 'xue_hua_screen_protection',
  ),
)
/// Visual style applied to the native or DOM privacy overlay.
enum ScreenProtectionMaskStyleMessage {
  blur,
  solidColor,
  none,
}

/// Types of security and lifecycle events emitted by the host platform.
enum ScreenProtectionEventTypeMessage {
  screenshotTaken,
  recordingStarted,
  recordingStopped,
  maskShown,
  maskHidden,
  shortcutBlocked,
}

/// Configuration payload for the app-switcher / inactive-window privacy mask.
class ScreenProtectionMaskConfigMessage {
  ScreenProtectionMaskConfigMessage({
    required this.enabled,
    required this.style,
    required this.blurSigma,
    required this.backgroundColor,
    required this.textColor,
    required this.title,
    required this.subtitle,
    required this.showLockIcon,
    required this.protectOnWindowBlur,
  });

  final bool enabled;
  final ScreenProtectionMaskStyleMessage style;
  final double blurSigma;
  final int backgroundColor;
  final int textColor;
  final String title;
  final String subtitle;
  final bool showLockIcon;
  final bool protectOnWindowBlur;
}

/// Configuration payload for Web-specific content protection rules.
class WebProtectionConfigMessage {
  WebProtectionConfigMessage({
    required this.disableContextMenu,
    required this.disablePrint,
    required this.disableDragAndSelect,
    required this.interceptCaptureShortcuts,
    required this.blurOnVisibilityChange,
  });

  final bool disableContextMenu;
  final bool disablePrint;
  final bool disableDragAndSelect;
  final bool interceptCaptureShortcuts;
  final bool blurOnVisibilityChange;
}

/// Snapshot of the current screen protection state on the active platform.
class ScreenProtectionStatusMessage {
  ScreenProtectionStatusMessage({
    required this.isSecureScreenEnabled,
    required this.isAppSwitcherMaskEnabled,
    required this.isScreenBeingRecorded,
    required this.isMaskCurrentlyVisible,
    required this.platform,
  });

  final bool isSecureScreenEnabled;
  final bool isAppSwitcherMaskEnabled;
  final bool isScreenBeingRecorded;
  final bool isMaskCurrentlyVisible;
  final String platform;
}

/// Describes which screen protection capabilities are natively supported by the
/// current operating system and runtime environment.
class ScreenProtectionCapabilitiesMessage {
  ScreenProtectionCapabilitiesMessage({
    required this.platform,
    required this.osVersion,
    required this.supportsHardwareAntiScreenshot,
    required this.supportsHardwareAntiRecording,
    required this.supportsScreenshotDetection,
    required this.supportsRecordingDetection,
    required this.supportsNativeAppSwitcherMask,
    required this.supportsNativeBlurEffect,
    required this.limitations,
  });

  final String platform;
  final String osVersion;
  final bool supportsHardwareAntiScreenshot;
  final bool supportsHardwareAntiRecording;
  final bool supportsScreenshotDetection;
  final bool supportsRecordingDetection;
  final bool supportsNativeAppSwitcherMask;
  final bool supportsNativeBlurEffect;
  final List<String> limitations;
}

/// Real-time screen security event emitted by the host platform.
class ScreenProtectionEventMessage {
  ScreenProtectionEventMessage({
    required this.type,
    required this.timestamp,
    required this.platform,
    required this.isCaptured,
    required this.metadata,
  });

  final ScreenProtectionEventTypeMessage type;
  final int timestamp;
  final String platform;
  final bool isCaptured;
  final Map<String, Object?> metadata;
}

/// Host API implemented natively on Android, iOS, macOS, Windows, and Linux.
@HostApi()
abstract class ScreenProtectionHostApi {
  bool setSecureScreen(bool enabled);

  bool isSecureScreenEnabled();

  bool configureAppSwitcherProtection(ScreenProtectionMaskConfigMessage config);

  bool configureWebProtection(WebProtectionConfigMessage config);

  bool isScreenBeingRecorded();

  ScreenProtectionStatusMessage getProtectionStatus();

  ScreenProtectionCapabilitiesMessage getCapabilities();

  bool showPrivacyMask();

  bool hidePrivacyMask();
}

/// Flutter API invoked by native platforms to stream real-time security events.
@FlutterApi()
abstract class ScreenProtectionFlutterApi {
  void onProtectionEvent(ScreenProtectionEventMessage event);
}
