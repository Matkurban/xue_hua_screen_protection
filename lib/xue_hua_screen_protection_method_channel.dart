import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/models/screen_protection_models.dart';
import 'xue_hua_screen_protection_platform_interface.dart';

/// An implementation of [XueHuaScreenProtectionPlatform] that uses method and
/// event channels to communicate with native platform code.
class MethodChannelXueHuaScreenProtection
    extends XueHuaScreenProtectionPlatform {
  /// Constructs a [MethodChannelXueHuaScreenProtection].
  ///
  /// Native reverse-call handlers are registered lazily on first use so unit
  /// tests can replace [XueHuaScreenProtectionPlatform.instance] before
  /// [WidgetsFlutterBinding.ensureInitialized] runs.
  MethodChannelXueHuaScreenProtection();

  /// The method channel used to invoke native screen protection APIs.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'com.kurban.xue_hua_screen_protection/methods',
  );

  /// The event channel used to receive native screen protection events.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    'com.kurban.xue_hua_screen_protection/events',
  );

  final StreamController<ScreenProtectionEvent> _eventController =
      StreamController<ScreenProtectionEvent>.broadcast();

  StreamSubscription<dynamic>? _eventChannelSubscription;
  bool _eventChannelListening = false;
  bool _nativeHandlerRegistered = false;

  void _ensureNativeHandlerRegistered() {
    if (_nativeHandlerRegistered) {
      return;
    }
    _nativeHandlerRegistered = true;
    methodChannel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onProtectionEvent' && call.arguments is Map) {
      final map = call.arguments as Map<Object?, Object?>;
      _eventController.add(ScreenProtectionEvent.fromMap(map));
    }
  }

  void _ensureEventChannelInitialized() {
    _ensureNativeHandlerRegistered();
    if (_eventChannelListening) return;
    _eventChannelListening = true;
    try {
      _eventChannelSubscription = eventChannel.receiveBroadcastStream().listen(
        (dynamic rawEvent) {
          if (rawEvent is Map) {
            _eventController.add(ScreenProtectionEvent.fromMap(rawEvent));
          }
        },
        onError: (Object _) {
          // Ignore stream errors when a platform uses MethodChannel callbacks.
        },
      );
    } on MissingPluginException {
      // Ignored in unit tests or platforms that emit events via MethodChannel.
    }
  }

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>(
      'setSecureScreen',
      <String, dynamic>{'enabled': enabled},
    );
    return result ?? false;
  }

  @override
  Future<bool> isSecureScreenEnabled() async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>(
      'isSecureScreenEnabled',
    );
    return result ?? false;
  }

  @override
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>(
      'configureAppSwitcherProtection',
      config.toMap(),
    );
    return result ?? false;
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>(
      'configureWebProtection',
      config.toMap(),
    );
    return result ?? false;
  }

  @override
  Future<bool> isScreenBeingRecorded() async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>(
      'isScreenBeingRecorded',
    );
    return result ?? false;
  }

  @override
  Future<ScreenProtectionStatus> getProtectionStatus() async {
    _ensureNativeHandlerRegistered();
    final map = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getProtectionStatus',
    );
    if (map == null) {
      return const ScreenProtectionStatus(
        isSecureScreenEnabled: false,
        isAppSwitcherMaskEnabled: false,
        isScreenBeingRecorded: false,
        isMaskCurrentlyVisible: false,
        platform: 'unknown',
      );
    }
    return ScreenProtectionStatus.fromMap(map);
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    _ensureNativeHandlerRegistered();
    final map = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    if (map == null) {
      return const ScreenProtectionCapabilities(
        platform: 'unknown',
        osVersion: 'unknown',
        supportsHardwareAntiScreenshot: false,
        supportsHardwareAntiRecording: false,
        supportsScreenshotDetection: false,
        supportsRecordingDetection: false,
        supportsNativeAppSwitcherMask: false,
        supportsNativeBlurEffect: false,
      );
    }
    return ScreenProtectionCapabilities.fromMap(map);
  }

  @override
  Future<bool> showPrivacyMask() async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>('showPrivacyMask');
    return result ?? false;
  }

  @override
  Future<bool> hidePrivacyMask() async {
    _ensureNativeHandlerRegistered();
    final result = await methodChannel.invokeMethod<bool>('hidePrivacyMask');
    return result ?? false;
  }

  @override
  Stream<ScreenProtectionEvent> get onProtectionEvent {
    _ensureEventChannelInitialized();
    return _eventController.stream;
  }

  /// Disposes internal stream subscriptions.
  @visibleForTesting
  Future<void> dispose() async {
    await _eventChannelSubscription?.cancel();
    await _eventController.close();
  }
}
