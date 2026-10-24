import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Visual style applied to the native or DOM privacy overlay when the app
/// enters the background, app switcher, or loses window focus.
enum ScreenProtectionMaskStyle {
  /// Applies a frosted-glass blur effect over the application window.
  ///
  /// Falls back to a styled translucent/solid overlay on platforms or OS
  /// versions where real-time window blur is unavailable.
  blur,

  /// Covers the application window with a solid opaque color and optional
  /// title, subtitle, and lock icon.
  solidColor,

  /// Disables the privacy mask overlay.
  none;

  /// Converts a string identifier into a [ScreenProtectionMaskStyle].
  static ScreenProtectionMaskStyle fromName(String? name) {
    switch (name) {
      case 'blur':
        return ScreenProtectionMaskStyle.blur;
      case 'solidColor':
        return ScreenProtectionMaskStyle.solidColor;
      case 'none':
        return ScreenProtectionMaskStyle.none;
      default:
        return ScreenProtectionMaskStyle.blur;
    }
  }
}

/// Configuration for the privacy mask shown in the OS app switcher, recents
/// screen, or when the application window becomes inactive.
@immutable
class ScreenProtectionMaskConfig {
  /// Creates a [ScreenProtectionMaskConfig].
  const ScreenProtectionMaskConfig({
    this.enabled = true,
    this.style = ScreenProtectionMaskStyle.blur,
    this.blurSigma = 20.0,
    this.backgroundColor = const Color(0xEB0F172A),
    this.textColor = const Color(0xFFFFFFFF),
    this.title = 'Privacy Protected',
    this.subtitle =
        'Screen content is hidden to protect sensitive information.',
    this.showLockIcon = true,
    this.protectOnWindowBlur = true,
  }) : assert(blurSigma >= 0.0, 'blurSigma must be non-negative.');

  /// Creates a preset configuration that disables the privacy mask.
  const ScreenProtectionMaskConfig.disabled()
    : enabled = false,
      style = ScreenProtectionMaskStyle.none,
      blurSigma = 0.0,
      backgroundColor = const Color(0xFF0F172A),
      textColor = const Color(0xFFFFFFFF),
      title = null,
      subtitle = null,
      showLockIcon = false,
      protectOnWindowBlur = false;

  /// Whether the app-switcher / inactive-window privacy mask is enabled.
  final bool enabled;

  /// The visual style of the privacy overlay.
  final ScreenProtectionMaskStyle style;

  /// The blur intensity (radius/sigma, typically `5.0` to `40.0`) used when
  /// [style] is [ScreenProtectionMaskStyle.blur].
  final double blurSigma;

  /// The primary background/tint color of the privacy overlay.
  final Color backgroundColor;

  /// The foreground color used for the lock icon, [title], and [subtitle].
  final Color textColor;

  /// Optional headline text displayed in the center of the privacy overlay.
  final String? title;

  /// Optional secondary description displayed below [title].
  final String? subtitle;

  /// Whether to render a security shield/lock icon in the overlay center.
  final bool showLockIcon;

  /// Whether losing window focus (e.g., switching to another desktop window or
  /// browser tab, or opening a system dialog) should immediately display the
  /// privacy overlay.
  final bool protectOnWindowBlur;

  /// Serializes this configuration to a platform-channel compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled && style != ScreenProtectionMaskStyle.none,
      'style': style.name,
      'blurSigma': blurSigma,
      'backgroundColor': backgroundColor.toARGB32(),
      'textColor': textColor.toARGB32(),
      'title': title ?? '',
      'subtitle': subtitle ?? '',
      'showLockIcon': showLockIcon,
      'protectOnWindowBlur': protectOnWindowBlur,
    };
  }

  /// Creates a [ScreenProtectionMaskConfig] from a map.
  factory ScreenProtectionMaskConfig.fromMap(Map<Object?, Object?> map) {
    final style = ScreenProtectionMaskStyle.fromName(map['style'] as String?);
    final bgValue = map['backgroundColor'];
    final fgValue = map['textColor'];
    return ScreenProtectionMaskConfig(
      enabled: (map['enabled'] as bool?) ?? true,
      style: style,
      blurSigma: ((map['blurSigma'] as num?) ?? 20.0).toDouble(),
      backgroundColor: bgValue is int
          ? Color(bgValue)
          : const Color(0xEB0F172A),
      textColor: fgValue is int ? Color(fgValue) : const Color(0xFFFFFFFF),
      title: map['title'] as String?,
      subtitle: map['subtitle'] as String?,
      showLockIcon: (map['showLockIcon'] as bool?) ?? true,
      protectOnWindowBlur: (map['protectOnWindowBlur'] as bool?) ?? true,
    );
  }

  /// Returns a copy of this [ScreenProtectionMaskConfig] with updated fields.
  ScreenProtectionMaskConfig copyWith({
    bool? enabled,
    ScreenProtectionMaskStyle? style,
    double? blurSigma,
    Color? backgroundColor,
    Color? textColor,
    String? title,
    String? subtitle,
    bool? showLockIcon,
    bool? protectOnWindowBlur,
  }) {
    return ScreenProtectionMaskConfig(
      enabled: enabled ?? this.enabled,
      style: style ?? this.style,
      blurSigma: blurSigma ?? this.blurSigma,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      showLockIcon: showLockIcon ?? this.showLockIcon,
      protectOnWindowBlur: protectOnWindowBlur ?? this.protectOnWindowBlur,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScreenProtectionMaskConfig &&
        other.enabled == enabled &&
        other.style == style &&
        other.blurSigma == blurSigma &&
        other.backgroundColor.toARGB32() == backgroundColor.toARGB32() &&
        other.textColor.toARGB32() == textColor.toARGB32() &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.showLockIcon == showLockIcon &&
        other.protectOnWindowBlur == protectOnWindowBlur;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    style,
    blurSigma,
    backgroundColor.toARGB32(),
    textColor.toARGB32(),
    title,
    subtitle,
    showLockIcon,
    protectOnWindowBlur,
  );
}

/// Web-specific hardening options to deter content extraction, printing, and
/// browser-based capture shortcuts.
@immutable
class WebProtectionConfig {
  /// Creates a [WebProtectionConfig].
  const WebProtectionConfig({
    this.disableContextMenu = true,
    this.disablePrint = true,
    this.disableDragAndSelect = true,
    this.interceptCaptureShortcuts = true,
    this.blurOnVisibilityChange = true,
  });

  /// Blocks the browser context menu (`contextmenu` event / right-click).
  final bool disableContextMenu;

  /// Injects `@media print` CSS rules to hide page content when printing or
  /// exporting to PDF.
  final bool disablePrint;

  /// Prevents image/element dragging (`dragstart`) and text selection via CSS.
  final bool disableDragAndSelect;

  /// Intercepts common capture, print, save, and DevTools keyboard shortcuts
  /// (`PrintScreen`, `Ctrl/Cmd+P`, `Ctrl/Cmd+S`, `Ctrl/Cmd+Shift+I`).
  final bool interceptCaptureShortcuts;

  /// Automatically displays the privacy overlay when the browser tab is hidden
  /// (`document.hidden`) or the browser window loses focus.
  final bool blurOnVisibilityChange;

  /// Serializes this configuration to a map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'disableContextMenu': disableContextMenu,
      'disablePrint': disablePrint,
      'disableDragAndSelect': disableDragAndSelect,
      'interceptCaptureShortcuts': interceptCaptureShortcuts,
      'blurOnVisibilityChange': blurOnVisibilityChange,
    };
  }

  /// Creates a [WebProtectionConfig] from a map.
  factory WebProtectionConfig.fromMap(Map<Object?, Object?> map) {
    return WebProtectionConfig(
      disableContextMenu: (map['disableContextMenu'] as bool?) ?? true,
      disablePrint: (map['disablePrint'] as bool?) ?? true,
      disableDragAndSelect: (map['disableDragAndSelect'] as bool?) ?? true,
      interceptCaptureShortcuts:
          (map['interceptCaptureShortcuts'] as bool?) ?? true,
      blurOnVisibilityChange: (map['blurOnVisibilityChange'] as bool?) ?? true,
    );
  }

  /// Returns a copy of this [WebProtectionConfig] with updated fields.
  WebProtectionConfig copyWith({
    bool? disableContextMenu,
    bool? disablePrint,
    bool? disableDragAndSelect,
    bool? interceptCaptureShortcuts,
    bool? blurOnVisibilityChange,
  }) {
    return WebProtectionConfig(
      disableContextMenu: disableContextMenu ?? this.disableContextMenu,
      disablePrint: disablePrint ?? this.disablePrint,
      disableDragAndSelect: disableDragAndSelect ?? this.disableDragAndSelect,
      interceptCaptureShortcuts:
          interceptCaptureShortcuts ?? this.interceptCaptureShortcuts,
      blurOnVisibilityChange:
          blurOnVisibilityChange ?? this.blurOnVisibilityChange,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebProtectionConfig &&
        other.disableContextMenu == disableContextMenu &&
        other.disablePrint == disablePrint &&
        other.disableDragAndSelect == disableDragAndSelect &&
        other.interceptCaptureShortcuts == interceptCaptureShortcuts &&
        other.blurOnVisibilityChange == blurOnVisibilityChange;
  }

  @override
  int get hashCode => Object.hash(
    disableContextMenu,
    disablePrint,
    disableDragAndSelect,
    interceptCaptureShortcuts,
    blurOnVisibilityChange,
  );
}

/// Snapshot of the current screen protection state on the active platform.
@immutable
class ScreenProtectionStatus {
  /// Creates a [ScreenProtectionStatus].
  const ScreenProtectionStatus({
    required this.isSecureScreenEnabled,
    required this.isAppSwitcherMaskEnabled,
    required this.isScreenBeingRecorded,
    required this.isMaskCurrentlyVisible,
    required this.platform,
  });

  /// Whether secure screen protection (anti-screenshot / anti-recording) is
  /// currently enabled.
  final bool isSecureScreenEnabled;

  /// Whether the app-switcher / inactive-window privacy mask is configured and
  /// active.
  final bool isAppSwitcherMaskEnabled;

  /// Whether the screen is currently being recorded, mirrored, or captured.
  final bool isScreenBeingRecorded;

  /// Whether the privacy mask overlay is currently visible on screen.
  final bool isMaskCurrentlyVisible;

  /// Identifier of the current host platform (e.g. `android`, `ios`, `macos`,
  /// `windows`, `linux`, `web`).
  final String platform;

  /// Creates a [ScreenProtectionStatus] from a platform channel map.
  factory ScreenProtectionStatus.fromMap(Map<Object?, Object?> map) {
    return ScreenProtectionStatus(
      isSecureScreenEnabled: (map['isSecureScreenEnabled'] as bool?) ?? false,
      isAppSwitcherMaskEnabled:
          (map['isAppSwitcherMaskEnabled'] as bool?) ?? false,
      isScreenBeingRecorded: (map['isScreenBeingRecorded'] as bool?) ?? false,
      isMaskCurrentlyVisible: (map['isMaskCurrentlyVisible'] as bool?) ?? false,
      platform: (map['platform'] as String?) ?? 'unknown',
    );
  }

  /// Serializes this status to a map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'isSecureScreenEnabled': isSecureScreenEnabled,
      'isAppSwitcherMaskEnabled': isAppSwitcherMaskEnabled,
      'isScreenBeingRecorded': isScreenBeingRecorded,
      'isMaskCurrentlyVisible': isMaskCurrentlyVisible,
      'platform': platform,
    };
  }

  /// Returns a copy of this [ScreenProtectionStatus] with updated fields.
  ScreenProtectionStatus copyWith({
    bool? isSecureScreenEnabled,
    bool? isAppSwitcherMaskEnabled,
    bool? isScreenBeingRecorded,
    bool? isMaskCurrentlyVisible,
    String? platform,
  }) {
    return ScreenProtectionStatus(
      isSecureScreenEnabled:
          isSecureScreenEnabled ?? this.isSecureScreenEnabled,
      isAppSwitcherMaskEnabled:
          isAppSwitcherMaskEnabled ?? this.isAppSwitcherMaskEnabled,
      isScreenBeingRecorded:
          isScreenBeingRecorded ?? this.isScreenBeingRecorded,
      isMaskCurrentlyVisible:
          isMaskCurrentlyVisible ?? this.isMaskCurrentlyVisible,
      platform: platform ?? this.platform,
    );
  }

  @override
  String toString() {
    return 'ScreenProtectionStatus(platform: $platform, '
        'isSecureScreenEnabled: $isSecureScreenEnabled, '
        'isAppSwitcherMaskEnabled: $isAppSwitcherMaskEnabled, '
        'isScreenBeingRecorded: $isScreenBeingRecorded, '
        'isMaskCurrentlyVisible: $isMaskCurrentlyVisible)';
  }
}

/// Describes which screen protection capabilities are natively supported by the
/// current operating system and runtime environment.
@immutable
class ScreenProtectionCapabilities {
  /// Creates a [ScreenProtectionCapabilities].
  const ScreenProtectionCapabilities({
    required this.platform,
    required this.osVersion,
    required this.supportsHardwareAntiScreenshot,
    required this.supportsHardwareAntiRecording,
    required this.supportsScreenshotDetection,
    required this.supportsRecordingDetection,
    required this.supportsNativeAppSwitcherMask,
    required this.supportsNativeBlurEffect,
    this.limitations = const <String>[],
  });

  /// Identifier of the current platform (`android`, `ios`, `macos`, `windows`,
  /// `linux`, `web`).
  final String platform;

  /// Human-readable OS or browser version string.
  final String osVersion;

  /// Whether the OS supports blocking system-level screenshots of the window.
  final bool supportsHardwareAntiScreenshot;

  /// Whether the OS supports blocking system-level screen recording or screen
  /// sharing of the window.
  final bool supportsHardwareAntiRecording;

  /// Whether the platform can detect when a user takes a screenshot or presses
  /// a capture shortcut.
  final bool supportsScreenshotDetection;

  /// Whether the platform can detect active screen recording, mirroring, or
  /// virtual display capture.
  final bool supportsRecordingDetection;

  /// Whether the platform supports displaying a native/DOM privacy overlay when
  /// switching apps or losing focus.
  final bool supportsNativeAppSwitcherMask;

  /// Whether the platform supports real-time frosted-glass blur on the privacy
  /// overlay (`RenderEffect` on Android 12+, `UIVisualEffectView` on iOS,
  /// `NSVisualEffectView` on macOS, `backdrop-filter` on Web).
  final bool supportsNativeBlurEffect;

  /// Platform-specific notes or security limitations to be aware of.
  final List<String> limitations;

  /// Creates a [ScreenProtectionCapabilities] from a platform channel map.
  factory ScreenProtectionCapabilities.fromMap(Map<Object?, Object?> map) {
    final rawLimitations = map['limitations'];
    final limitations = rawLimitations is List
        ? rawLimitations.whereType<String>().toList(growable: false)
        : const <String>[];
    return ScreenProtectionCapabilities(
      platform: (map['platform'] as String?) ?? 'unknown',
      osVersion: (map['osVersion'] as String?) ?? 'unknown',
      supportsHardwareAntiScreenshot:
          (map['supportsHardwareAntiScreenshot'] as bool?) ?? false,
      supportsHardwareAntiRecording:
          (map['supportsHardwareAntiRecording'] as bool?) ?? false,
      supportsScreenshotDetection:
          (map['supportsScreenshotDetection'] as bool?) ?? false,
      supportsRecordingDetection:
          (map['supportsRecordingDetection'] as bool?) ?? false,
      supportsNativeAppSwitcherMask:
          (map['supportsNativeAppSwitcherMask'] as bool?) ?? false,
      supportsNativeBlurEffect:
          (map['supportsNativeBlurEffect'] as bool?) ?? false,
      limitations: limitations,
    );
  }

  /// Serializes these capabilities to a map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'platform': platform,
      'osVersion': osVersion,
      'supportsHardwareAntiScreenshot': supportsHardwareAntiScreenshot,
      'supportsHardwareAntiRecording': supportsHardwareAntiRecording,
      'supportsScreenshotDetection': supportsScreenshotDetection,
      'supportsRecordingDetection': supportsRecordingDetection,
      'supportsNativeAppSwitcherMask': supportsNativeAppSwitcherMask,
      'supportsNativeBlurEffect': supportsNativeBlurEffect,
      'limitations': limitations,
    };
  }
}

/// Types of security and lifecycle events emitted by [XueHuaScreenProtection].
enum ScreenProtectionEventType {
  /// The user took a screenshot (or triggered a screenshot key/clipboard image
  /// capture).
  screenshotTaken,

  /// Screen recording, screen sharing, AirPlay mirroring, or virtual display
  /// capture started.
  recordingStarted,

  /// Screen recording, screen sharing, or virtual display capture stopped.
  recordingStopped,

  /// The privacy mask overlay was shown (e.g. app entered background/switcher
  /// or lost focus).
  maskShown,

  /// The privacy mask overlay was hidden (e.g. app returned to foreground).
  maskHidden,

  /// A restricted capture, print, or save shortcut/action was intercepted.
  shortcutBlocked;

  /// Parses a string identifier into a [ScreenProtectionEventType].
  static ScreenProtectionEventType fromName(String? name) {
    switch (name) {
      case 'screenshotTaken':
        return ScreenProtectionEventType.screenshotTaken;
      case 'recordingStarted':
        return ScreenProtectionEventType.recordingStarted;
      case 'recordingStopped':
        return ScreenProtectionEventType.recordingStopped;
      case 'maskShown':
        return ScreenProtectionEventType.maskShown;
      case 'maskHidden':
        return ScreenProtectionEventType.maskHidden;
      case 'shortcutBlocked':
        return ScreenProtectionEventType.shortcutBlocked;
      default:
        return ScreenProtectionEventType.screenshotTaken;
    }
  }
}

/// Represents a real-time screen security event emitted by the underlying
/// platform implementation.
@immutable
class ScreenProtectionEvent {
  /// Creates a [ScreenProtectionEvent].
  const ScreenProtectionEvent({
    required this.type,
    required this.timestamp,
    required this.platform,
    this.isCaptured = false,
    this.metadata = const <String, dynamic>{},
  });

  /// The type of screen protection event.
  final ScreenProtectionEventType type;

  /// Timestamp when the event occurred.
  final DateTime timestamp;

  /// Platform that emitted the event.
  final String platform;

  /// Whether the screen is actively being recorded/captured at the time of the
  /// event.
  final bool isCaptured;

  /// Additional platform-specific diagnostic metadata (e.g. blocked key combo,
  /// detection source, or display count).
  final Map<String, dynamic> metadata;

  /// Creates a [ScreenProtectionEvent] from a platform channel map.
  factory ScreenProtectionEvent.fromMap(Map<Object?, Object?> map) {
    final rawTimestamp = map['timestamp'];
    final timestamp = rawTimestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
        : DateTime.now();
    final rawMeta = map['metadata'];
    final metadata = <String, dynamic>{};
    if (rawMeta is Map) {
      for (final entry in rawMeta.entries) {
        if (entry.key != null) {
          metadata[entry.key.toString()] = entry.value;
        }
      }
    }
    return ScreenProtectionEvent(
      type: ScreenProtectionEventType.fromName(map['type'] as String?),
      timestamp: timestamp,
      platform: (map['platform'] as String?) ?? 'unknown',
      isCaptured: (map['isCaptured'] as bool?) ?? false,
      metadata: metadata,
    );
  }

  /// Serializes this event to a map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'platform': platform,
      'isCaptured': isCaptured,
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'ScreenProtectionEvent(type: ${type.name}, platform: $platform, '
        'isCaptured: $isCaptured, timestamp: ${timestamp.toIso8601String()}, '
        'metadata: $metadata)';
  }
}
