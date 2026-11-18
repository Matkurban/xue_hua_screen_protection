import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/screen_protection_models.dart';
import '../screen_protection_backend.dart';
import 'messages.g.dart';

/// Pigeon-powered [ScreenProtectionBackend] communicating with Android, iOS,
/// macOS, Windows, and Linux hosts through strongly-typed
/// [ScreenProtectionHostApi] and [ScreenProtectionFlutterApi].
class PigeonScreenProtectionBackend implements ScreenProtectionBackend {
  /// Constructs a [PigeonScreenProtectionBackend] with an optional custom
  /// [binaryMessenger] or [hostApi] for testing.
  PigeonScreenProtectionBackend({
    this.binaryMessenger,
    @visibleForTesting ScreenProtectionHostApi? hostApi,
  }) : _hostApiOverride = hostApi;

  /// Optional custom [BinaryMessenger] used for Pigeon channel communication.
  final BinaryMessenger? binaryMessenger;

  final ScreenProtectionHostApi? _hostApiOverride;

  /// Lazily initialized Pigeon [ScreenProtectionHostApi] client.
  @visibleForTesting
  late final ScreenProtectionHostApi hostApi =
      _hostApiOverride ??
      ScreenProtectionHostApi(binaryMessenger: binaryMessenger);

  final StreamController<ScreenProtectionEvent> _eventController =
      StreamController<ScreenProtectionEvent>.broadcast();

  bool _flutterApiRegistered = false;

  void _ensureFlutterApiRegistered() {
    if (_flutterApiRegistered) {
      return;
    }
    _flutterApiRegistered = true;
    ScreenProtectionFlutterApi.setUp(
      _ProtectionFlutterApiHandler(_handleProtectionEvent),
      binaryMessenger: binaryMessenger,
    );
  }

  void _handleProtectionEvent(ScreenProtectionEventMessage event) {
    if (!_eventController.isClosed) {
      _eventController.add(_eventFromMessage(event));
    }
  }

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    _ensureFlutterApiRegistered();
    return hostApi.setSecureScreen(enabled);
  }

  @override
  Future<bool> isSecureScreenEnabled() async {
    _ensureFlutterApiRegistered();
    return hostApi.isSecureScreenEnabled();
  }

  @override
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) async {
    _ensureFlutterApiRegistered();
    return hostApi.configureAppSwitcherProtection(_maskConfigToMessage(config));
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    _ensureFlutterApiRegistered();
    return hostApi.configureWebProtection(_webConfigToMessage(config));
  }

  @override
  Future<bool> isScreenBeingRecorded() async {
    _ensureFlutterApiRegistered();
    return hostApi.isScreenBeingRecorded();
  }

  @override
  Future<ScreenProtectionStatus> getProtectionStatus() async {
    _ensureFlutterApiRegistered();
    final message = await hostApi.getProtectionStatus();
    return _statusFromMessage(message);
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    _ensureFlutterApiRegistered();
    final message = await hostApi.getCapabilities();
    return _capabilitiesFromMessage(message);
  }

  @override
  Future<bool> showPrivacyMask() async {
    _ensureFlutterApiRegistered();
    return hostApi.showPrivacyMask();
  }

  @override
  Future<bool> hidePrivacyMask() async {
    _ensureFlutterApiRegistered();
    return hostApi.hidePrivacyMask();
  }

  @override
  Stream<ScreenProtectionEvent> get onProtectionEvent {
    _ensureFlutterApiRegistered();
    return _eventController.stream;
  }

  /// Unregisters the Pigeon [ScreenProtectionFlutterApi] handler and closes the
  /// internal event broadcast controller.
  @visibleForTesting
  Future<void> dispose() async {
    if (_flutterApiRegistered) {
      ScreenProtectionFlutterApi.setUp(
        null,
        binaryMessenger: binaryMessenger,
      );
      _flutterApiRegistered = false;
    }
    await _eventController.close();
  }
}

final class _ProtectionFlutterApiHandler extends ScreenProtectionFlutterApi {
  _ProtectionFlutterApiHandler(this._onEvent);

  final void Function(ScreenProtectionEventMessage event) _onEvent;

  @override
  Future<void> onProtectionEvent(ScreenProtectionEventMessage event) async {
    _onEvent(event);
  }
}

ScreenProtectionMaskStyleMessage _maskStyleToMessage(
  ScreenProtectionMaskStyle style,
) {
  switch (style) {
    case ScreenProtectionMaskStyle.blur:
      return ScreenProtectionMaskStyleMessage.blur;
    case ScreenProtectionMaskStyle.solidColor:
      return ScreenProtectionMaskStyleMessage.solidColor;
    case ScreenProtectionMaskStyle.none:
      return ScreenProtectionMaskStyleMessage.none;
  }
}

ScreenProtectionMaskConfigMessage _maskConfigToMessage(
  ScreenProtectionMaskConfig config,
) {
  return ScreenProtectionMaskConfigMessage(
    enabled: config.enabled && config.style != ScreenProtectionMaskStyle.none,
    style: _maskStyleToMessage(config.style),
    blurSigma: config.blurSigma,
    backgroundColor: config.backgroundColor.toARGB32(),
    textColor: config.textColor.toARGB32(),
    title: config.title ?? '',
    subtitle: config.subtitle ?? '',
    showLockIcon: config.showLockIcon,
    protectOnWindowBlur: config.protectOnWindowBlur,
  );
}

WebProtectionConfigMessage _webConfigToMessage(WebProtectionConfig config) {
  return WebProtectionConfigMessage(
    disableContextMenu: config.disableContextMenu,
    disablePrint: config.disablePrint,
    disableDragAndSelect: config.disableDragAndSelect,
    interceptCaptureShortcuts: config.interceptCaptureShortcuts,
    blurOnVisibilityChange: config.blurOnVisibilityChange,
  );
}

ScreenProtectionStatus _statusFromMessage(
  ScreenProtectionStatusMessage message,
) {
  return ScreenProtectionStatus(
    isSecureScreenEnabled: message.isSecureScreenEnabled,
    isAppSwitcherMaskEnabled: message.isAppSwitcherMaskEnabled,
    isScreenBeingRecorded: message.isScreenBeingRecorded,
    isMaskCurrentlyVisible: message.isMaskCurrentlyVisible,
    platform: message.platform,
  );
}

ScreenProtectionCapabilities _capabilitiesFromMessage(
  ScreenProtectionCapabilitiesMessage message,
) {
  return ScreenProtectionCapabilities(
    platform: message.platform,
    osVersion: message.osVersion,
    supportsHardwareAntiScreenshot: message.supportsHardwareAntiScreenshot,
    supportsHardwareAntiRecording: message.supportsHardwareAntiRecording,
    supportsScreenshotDetection: message.supportsScreenshotDetection,
    supportsRecordingDetection: message.supportsRecordingDetection,
    supportsNativeAppSwitcherMask: message.supportsNativeAppSwitcherMask,
    supportsNativeBlurEffect: message.supportsNativeBlurEffect,
    limitations: List<String>.unmodifiable(message.limitations),
  );
}

ScreenProtectionEventType _eventTypeFromMessage(
  ScreenProtectionEventTypeMessage type,
) {
  switch (type) {
    case ScreenProtectionEventTypeMessage.screenshotTaken:
      return ScreenProtectionEventType.screenshotTaken;
    case ScreenProtectionEventTypeMessage.recordingStarted:
      return ScreenProtectionEventType.recordingStarted;
    case ScreenProtectionEventTypeMessage.recordingStopped:
      return ScreenProtectionEventType.recordingStopped;
    case ScreenProtectionEventTypeMessage.maskShown:
      return ScreenProtectionEventType.maskShown;
    case ScreenProtectionEventTypeMessage.maskHidden:
      return ScreenProtectionEventType.maskHidden;
    case ScreenProtectionEventTypeMessage.shortcutBlocked:
      return ScreenProtectionEventType.shortcutBlocked;
  }
}

ScreenProtectionEvent _eventFromMessage(ScreenProtectionEventMessage message) {
  return ScreenProtectionEvent(
    type: _eventTypeFromMessage(message.type),
    timestamp: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
    platform: message.platform,
    isCaptured: message.isCaptured,
    metadata: Map<String, dynamic>.from(message.metadata),
  );
}
