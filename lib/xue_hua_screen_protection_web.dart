// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/painting.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/models/screen_protection_models.dart';
import 'xue_hua_screen_protection_platform_interface.dart';

/// The Web implementation of [XueHuaScreenProtectionPlatform].
///
/// Since web browsers operate inside a sandboxed environment and cannot block
/// OS-level screenshot tools (`FLAG_SECURE`), [XueHuaScreenProtectionWeb]
/// provides multi-layered DOM hardening:
/// - `@media print` CSS rule injection to block printing and PDF export.
/// - Automatic full-viewport `backdrop-filter: blur()` overlay when the browser
///   tab is hidden (`visibilitychange`) or the window loses focus (`blur`).
/// - Interception of `PrintScreen` and common capture/print/save shortcuts.
/// - Optional blocking of right-click context menus, text selection, and drag.
class XueHuaScreenProtectionWeb extends XueHuaScreenProtectionPlatform {
  /// Constructs a [XueHuaScreenProtectionWeb] and registers DOM listeners.
  XueHuaScreenProtectionWeb() {
    _attachDomListeners();
  }

  /// Registers [XueHuaScreenProtectionWeb] as the platform implementation.
  static void registerWith(Registrar registrar) {
    XueHuaScreenProtectionPlatform.instance = XueHuaScreenProtectionWeb();
  }

  static const String _styleElementId = 'xue-hua-screen-protection-style';
  static const String _maskElementId = 'xue-hua-screen-protection-mask';

  final StreamController<ScreenProtectionEvent> _eventController =
      StreamController<ScreenProtectionEvent>.broadcast();

  bool _isSecureScreenEnabled = false;
  bool _isMaskVisible = false;
  ScreenProtectionMaskConfig _maskConfig =
      const ScreenProtectionMaskConfig.disabled();
  WebProtectionConfig _webConfig = const WebProtectionConfig();

  bool _listenersAttached = false;

  void _attachDomListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        _handleVisibilityOrFocusChange();
      }).toJS,
    );

    web.window.addEventListener(
      'blur',
      ((web.Event _) {
        if (_shouldShowMaskOnBlur()) {
          _setMaskDomVisible(true, reason: 'window_blur');
        }
      }).toJS,
    );

    web.window.addEventListener(
      'focus',
      ((web.Event _) {
        if (!web.document.hidden) {
          _setMaskDomVisible(false, reason: 'window_focus');
        }
      }).toJS,
    );

    web.window.addEventListener(
      'contextmenu',
      ((web.Event event) {
        if (_isSecureScreenEnabled && _webConfig.disableContextMenu) {
          event.preventDefault();
          _emitEvent(
            ScreenProtectionEventType.shortcutBlocked,
            metadata: <String, dynamic>{'action': 'contextmenu'},
          );
        }
      }).toJS,
    );

    web.window.addEventListener(
      'dragstart',
      ((web.Event event) {
        if (_isSecureScreenEnabled && _webConfig.disableDragAndSelect) {
          event.preventDefault();
        }
      }).toJS,
    );

    web.window.addEventListener(
      'keydown',
      ((web.KeyboardEvent event) {
        _handleKeyEvent(event, isKeyUp: false);
      }).toJS,
      true.toJS,
    );

    web.window.addEventListener(
      'keyup',
      ((web.KeyboardEvent event) {
        _handleKeyEvent(event, isKeyUp: true);
      }).toJS,
      true.toJS,
    );
  }

  bool _shouldShowMaskOnBlur() {
    final maskActive =
        _maskConfig.enabled &&
        _maskConfig.style != ScreenProtectionMaskStyle.none;
    return (maskActive && _maskConfig.protectOnWindowBlur) ||
        (_isSecureScreenEnabled && _webConfig.blurOnVisibilityChange);
  }

  void _handleVisibilityOrFocusChange() {
    final maskActive =
        _maskConfig.enabled &&
        _maskConfig.style != ScreenProtectionMaskStyle.none;
    if (!maskActive &&
        !(_isSecureScreenEnabled && _webConfig.blurOnVisibilityChange)) {
      return;
    }
    if (web.document.hidden) {
      _setMaskDomVisible(true, reason: 'visibility_hidden');
    } else if (web.document.hasFocus()) {
      _setMaskDomVisible(false, reason: 'visibility_visible');
    }
  }

  void _handleKeyEvent(web.KeyboardEvent event, {required bool isKeyUp}) {
    final key = event.key;
    final lowerKey = key.toLowerCase();
    final ctrlOrMeta = event.ctrlKey || event.metaKey;

    // Detect PrintScreen or macOS screenshot shortcuts (Cmd+Shift+3/4/5)
    final isPrintScreen = key == 'PrintScreen' || event.keyCode == 44;
    final isMacScreenshot =
        event.metaKey &&
        event.shiftKey &&
        (lowerKey == '3' || lowerKey == '4' || lowerKey == '5');

    if (isPrintScreen || (isMacScreenshot && !isKeyUp)) {
      if (_isSecureScreenEnabled && _webConfig.interceptCaptureShortcuts) {
        event.preventDefault();
        event.stopPropagation();
        // Temporarily flash the privacy mask to obscure rapid clipboard grabs.
        _setMaskDomVisible(true, reason: 'screenshot_key');
      }
      _emitEvent(
        ScreenProtectionEventType.screenshotTaken,
        metadata: <String, dynamic>{
          'key': key,
          'ctrlKey': event.ctrlKey,
          'metaKey': event.metaKey,
          'shiftKey': event.shiftKey,
        },
      );
      return;
    }

    if (isKeyUp) return;

    if (_isSecureScreenEnabled && _webConfig.interceptCaptureShortcuts) {
      final isPrintOrSave = ctrlOrMeta && (lowerKey == 'p' || lowerKey == 's');
      final isDevTools =
          (ctrlOrMeta &&
              event.shiftKey &&
              (lowerKey == 'i' || lowerKey == 'c' || lowerKey == 'j')) ||
          key == 'F12';

      if (isPrintOrSave || isDevTools) {
        event.preventDefault();
        event.stopPropagation();
        _emitEvent(
          ScreenProtectionEventType.shortcutBlocked,
          metadata: <String, dynamic>{
            'key': key,
            'ctrlKey': event.ctrlKey,
            'metaKey': event.metaKey,
            'shiftKey': event.shiftKey,
          },
        );
      }
    }
  }

  void _syncDomStyles() {
    final head = web.document.head;
    if (head == null) return;

    var styleElement =
        web.document.getElementById(_styleElementId) as web.HTMLStyleElement?;
    if (!_isSecureScreenEnabled) {
      styleElement?.remove();
      return;
    }

    if (styleElement == null) {
      styleElement =
          web.document.createElement('style') as web.HTMLStyleElement;
      styleElement.id = _styleElementId;
      head.appendChild(styleElement);
    }

    final buffer = StringBuffer();
    if (_webConfig.disablePrint) {
      buffer.writeln('''
@media print {
  html, body {
    display: none !important;
    visibility: hidden !important;
  }
}
''');
    }
    if (_webConfig.disableDragAndSelect) {
      buffer.writeln('''
body, flt-glass-pane, flutter-view {
  -webkit-user-select: none !important;
  user-select: none !important;
  -webkit-touch-callout: none !important;
}
''');
    }
    styleElement.textContent = buffer.toString();
  }

  void _setMaskDomVisible(bool visible, {String reason = 'manual'}) {
    if (_isMaskVisible == visible) {
      if (visible) {
        _renderMaskOverlayElement();
      }
      return;
    }
    _isMaskVisible = visible;

    if (visible) {
      _renderMaskOverlayElement();
      _emitEvent(
        ScreenProtectionEventType.maskShown,
        metadata: <String, dynamic>{'reason': reason},
      );
    } else {
      final existing = web.document.getElementById(_maskElementId);
      existing?.remove();
      _emitEvent(
        ScreenProtectionEventType.maskHidden,
        metadata: <String, dynamic>{'reason': reason},
      );
    }
  }

  void _renderMaskOverlayElement() {
    final body = web.document.body;
    if (body == null) return;

    var overlay =
        web.document.getElementById(_maskElementId) as web.HTMLDivElement?;
    if (overlay == null) {
      overlay = web.document.createElement('div') as web.HTMLDivElement;
      overlay.id = _maskElementId;
      body.appendChild(overlay);
    }

    final effectiveConfig = _maskConfig.enabled
        ? _maskConfig
        : const ScreenProtectionMaskConfig();
    final bgCss = _colorToCssRgba(
      effectiveConfig.backgroundColor,
      overrideAlpha: effectiveConfig.style == ScreenProtectionMaskStyle.blur
          ? 0.78
          : null,
    );
    final fgCss = _colorToCssRgba(effectiveConfig.textColor);
    final blurPx = effectiveConfig.style == ScreenProtectionMaskStyle.blur
        ? effectiveConfig.blurSigma.round()
        : 0;

    overlay.style.cssText =
        '''
position: fixed;
inset: 0;
width: 100vw;
height: 100vh;
z-index: 2147483647;
display: flex;
flex-direction: column;
align-items: center;
justify-content: center;
padding: 32px;
box-sizing: border-box;
background-color: $bgCss;
color: $fgCss;
backdrop-filter: ${blurPx > 0 ? 'blur(${blurPx}px)' : 'none'};
-webkit-backdrop-filter: ${blurPx > 0 ? 'blur(${blurPx}px)' : 'none'};
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
text-align: center;
user-select: none;
pointer-events: all;
''';

    final title = effectiveConfig.title ?? 'Privacy Protected';
    final subtitle =
        effectiveConfig.subtitle ??
        'Screen content is hidden to protect sensitive information.';

    // Clear children safely and construct DOM elements without innerHTML injection
    while (overlay.firstChild != null) {
      overlay.removeChild(overlay.firstChild!);
    }

    if (effectiveConfig.showLockIcon) {
      final iconBadge = web.document.createElement('div') as web.HTMLDivElement;
      iconBadge.style.cssText = '''
width: 64px;
height: 64px;
border-radius: 32px;
display: flex;
align-items: center;
justify-content: center;
margin-bottom: 16px;
background: rgba(255, 255, 255, 0.14);
font-size: 30px;
''';
      iconBadge.textContent = '🔒';
      overlay.appendChild(iconBadge);
    }

    if (title.isNotEmpty) {
      final titleEl = web.document.createElement('div') as web.HTMLDivElement;
      titleEl.style.cssText =
          'font-size: 22px; font-weight: 700; margin-bottom: 8px;';
      titleEl.textContent = title;
      overlay.appendChild(titleEl);
    }

    if (subtitle.isNotEmpty) {
      final subEl = web.document.createElement('div') as web.HTMLDivElement;
      subEl.style.cssText =
          'font-size: 14px; opacity: 0.85; max-width: 460px; line-height: 1.5;';
      subEl.textContent = subtitle;
      overlay.appendChild(subEl);
    }
  }

  String _colorToCssRgba(Color color, {double? overrideAlpha}) {
    final argb = color.toARGB32();
    final a = overrideAlpha ?? (((argb >> 24) & 0xFF) / 255.0);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
  }

  void _emitEvent(
    ScreenProtectionEventType type, {
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    _eventController.add(
      ScreenProtectionEvent(
        type: type,
        timestamp: DateTime.now(),
        platform: 'web',
        isCaptured: false,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    _isSecureScreenEnabled = enabled;
    _syncDomStyles();
    if (!enabled && !_maskConfig.enabled && _isMaskVisible) {
      _setMaskDomVisible(false, reason: 'secure_screen_disabled');
    }
    return true;
  }

  @override
  Future<bool> isSecureScreenEnabled() async => _isSecureScreenEnabled;

  @override
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) async {
    _maskConfig = config;
    if (!config.enabled || config.style == ScreenProtectionMaskStyle.none) {
      if (_isMaskVisible && !_isSecureScreenEnabled) {
        _setMaskDomVisible(false, reason: 'mask_disabled');
      }
    } else if (_isMaskVisible) {
      _renderMaskOverlayElement();
    }
    return true;
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    _webConfig = config;
    _syncDomStyles();
    return true;
  }

  @override
  Future<bool> isScreenBeingRecorded() async => false;

  @override
  Future<ScreenProtectionStatus> getProtectionStatus() async {
    return ScreenProtectionStatus(
      isSecureScreenEnabled: _isSecureScreenEnabled,
      isAppSwitcherMaskEnabled:
          _maskConfig.enabled &&
          _maskConfig.style != ScreenProtectionMaskStyle.none,
      isScreenBeingRecorded: false,
      isMaskCurrentlyVisible: _isMaskVisible,
      platform: 'web',
    );
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    return ScreenProtectionCapabilities(
      platform: 'web',
      osVersion: web.window.navigator.userAgent,
      supportsHardwareAntiScreenshot: false,
      supportsHardwareAntiRecording: false,
      supportsScreenshotDetection: true,
      supportsRecordingDetection: false,
      supportsNativeAppSwitcherMask: true,
      supportsNativeBlurEffect: true,
      limitations: const <String>[
        'Web browsers cannot block OS-level screenshot or screen recording tools outside the browser sandbox.',
        'Protection on Web relies on @media print blocking, visibility/blur DOM overlays, keyboard shortcut interception, and watermarks.',
      ],
    );
  }

  @override
  Future<bool> showPrivacyMask() async {
    _setMaskDomVisible(true, reason: 'manual');
    return true;
  }

  @override
  Future<bool> hidePrivacyMask() async {
    _setMaskDomVisible(false, reason: 'manual');
    return true;
  }

  @override
  Stream<ScreenProtectionEvent> get onProtectionEvent =>
      _eventController.stream;
}
