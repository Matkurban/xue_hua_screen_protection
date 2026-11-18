import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/messages.g.dart';
import 'src/models/screen_protection_models.dart';
import 'xue_hua_screen_protection_platform_interface.dart';

/// Pigeon-powered implementation of [XueHuaScreenProtectionPlatform] using
/// strongly-typed [ScreenProtectionHostApi] and [ScreenProtectionFlutterApi].
class PigeonXueHuaScreenProtection extends XueHuaScreenProtectionPlatform {
  /// Constructs a [PigeonXueHuaScreenProtection] with an optional custom
  /// [binaryMessenger] or [hostApi] for testing.
  PigeonXueHuaScreenProtection({
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
      _PigeonFlutterApiHandler(_handleProtectionEvent),
      binaryMessenger: binaryMessenger,
    );
  }

  void _handleProtectionEvent(ScreenProtectionEventMessage event) {
    if (!_eventController.isClosed) {
      _eventController.add(ScreenProtectionEvent.fromPigeon(event));
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
    return hostApi.configureAppSwitcherProtection(config.toPigeon());
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    _ensureFlutterApiRegistered();
    return hostApi.configureWebProtection(config.toPigeon());
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
    return ScreenProtectionStatus.fromPigeon(message);
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    _ensureFlutterApiRegistered();
    final message = await hostApi.getCapabilities();
    return ScreenProtectionCapabilities.fromPigeon(message);
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

final class _PigeonFlutterApiHandler extends ScreenProtectionFlutterApi {
  _PigeonFlutterApiHandler(this._onEvent);

  final void Function(ScreenProtectionEventMessage event) _onEvent;

  @override
  void onProtectionEvent(ScreenProtectionEventMessage event) {
    _onEvent(event);
  }
}
