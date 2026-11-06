import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../xue_hua_screen_protection.dart';
import 'screen_protection_coordinator.dart';

/// A declarative lifecycle widget that automatically enables screen protection
/// while visible onstage and restores previous settings when covered, moved
/// offstage, or disposed. Also optionally renders an in-app shield during
/// active screen recording or background transitions.
class ScreenProtectionScope extends StatefulWidget {
  /// Creates a [ScreenProtectionScope].
  const ScreenProtectionScope({
    super.key,
    required this.child,
    this.enableSecureScreen = true,
    this.maskConfig = const ScreenProtectionMaskConfig(),
    this.hideContentWhileRecording = true,
    this.watermarkText,
    this.watermarkSubText,
    this.recordingOverlayBuilder,
    this.onScreenshotTaken,
    this.onRecordingStateChanged,
  });

  /// The protected subtree.
  final Widget child;

  /// Whether to enable OS-level anti-screenshot / anti-recording protection
  /// while this widget is mounted.
  final bool enableSecureScreen;

  /// App-switcher / inactive-window privacy mask configuration applied while
  /// this widget is mounted.
  final ScreenProtectionMaskConfig maskConfig;

  /// Whether to automatically cover [child] with a Flutter-level shield when
  /// active screen recording or mirroring is detected.
  final bool hideContentWhileRecording;

  /// Optional watermark text overlaid on top of [child].
  final String? watermarkText;

  /// Optional secondary watermark text overlaid on top of [child].
  final String? watermarkSubText;

  /// Custom builder displayed when [hideContentWhileRecording] is `true` and
  /// active recording is detected.
  final WidgetBuilder? recordingOverlayBuilder;

  /// Callback invoked whenever a screenshot event is detected.
  final ValueChanged<ScreenProtectionEvent>? onScreenshotTaken;

  /// Callback invoked whenever screen recording state changes.
  final ValueChanged<bool>? onRecordingStateChanged;

  @override
  State<ScreenProtectionScope> createState() => _ScreenProtectionScopeState();
}

class _ScreenProtectionScopeState extends State<ScreenProtectionScope>
    with WidgetsBindingObserver
    implements ScreenProtectionScopeHandle {
  final XueHuaScreenProtection _plugin = XueHuaScreenProtection.instance;
  final ScreenProtectionCoordinator _coordinator =
      ScreenProtectionCoordinator.instance;
  StreamSubscription<ScreenProtectionEvent>? _eventSubscription;
  bool _isRecording = false;
  bool _hasInitializedRecordingState = false;
  bool _isLifecycleInactive = false;
  bool _isActiveInTree = false;
  bool _isOnstage = false;

  @override
  BuildContext get scopeContext => context;

  @override
  bool get isActiveInTree => mounted && _isActiveInTree;

  @override
  bool get enableSecureScreen => widget.enableSecureScreen;

  @override
  ScreenProtectionMaskConfig get maskConfig => widget.maskConfig;

  @override
  bool get isOnstage => _isOnstage;

  @override
  void initState() {
    super.initState();
    _isActiveInTree = true;
    WidgetsBinding.instance.addObserver(this);
    _eventSubscription = _plugin.onProtectionEvent.listen(_handleEvent);
    _coordinator.registerScope(this);
  }

  @override
  void activate() {
    super.activate();
    _isActiveInTree = true;
    _coordinator.notifyScopeChanged(this);
  }

  @override
  void deactivate() {
    _isActiveInTree = false;
    _coordinator.notifyScopeChanged(this);
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant ScreenProtectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableSecureScreen != widget.enableSecureScreen ||
        oldWidget.maskConfig != widget.maskConfig) {
      _coordinator.notifyScopeChanged(this);
    }
    if ((!widget.maskConfig.enabled ||
            widget.maskConfig.style == ScreenProtectionMaskStyle.none) &&
        _isLifecycleInactive) {
      _isLifecycleInactive = false;
    }
  }

  @override
  void notifyOnstageChanged(bool onstage, {required bool fromDispose}) {
    _isOnstage = onstage;
    if (fromDispose || !mounted) {
      return;
    }
    if (onstage) {
      unawaited(_refreshRecordingState());
    } else if (_isLifecycleInactive) {
      setState(() {
        _isLifecycleInactive = false;
      });
    }
  }

  Future<void> _refreshRecordingState() async {
    final recording = await _plugin.isScreenBeingRecorded();
    if (!mounted || !_isOnstage) {
      return;
    }
    final isInitialCheck = !_hasInitializedRecordingState;
    _hasInitializedRecordingState = true;
    if (recording != _isRecording) {
      setState(() {
        _isRecording = recording;
      });
      if (!isInitialCheck) {
        widget.onRecordingStateChanged?.call(recording);
      }
    }
  }

  void _handleEvent(ScreenProtectionEvent event) {
    if (!mounted || !_isOnstage) return;
    switch (event.type) {
      case ScreenProtectionEventType.screenshotTaken:
      case ScreenProtectionEventType.shortcutBlocked:
        widget.onScreenshotTaken?.call(event);
      case ScreenProtectionEventType.recordingStarted:
        _hasInitializedRecordingState = true;
        if (!_isRecording) {
          setState(() {
            _isRecording = true;
          });
          widget.onRecordingStateChanged?.call(true);
        }
      case ScreenProtectionEventType.recordingStopped:
        _hasInitializedRecordingState = true;
        if (_isRecording) {
          setState(() {
            _isRecording = false;
          });
          widget.onRecordingStateChanged?.call(false);
        }
      case ScreenProtectionEventType.maskShown:
      case ScreenProtectionEventType.maskHidden:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOnstage ||
        !widget.maskConfig.enabled ||
        widget.maskConfig.style == ScreenProtectionMaskStyle.none) {
      if (_isLifecycleInactive && mounted) {
        setState(() {
          _isLifecycleInactive = false;
        });
      }
      return;
    }
    final shouldMask =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused;
    if (shouldMask != _isLifecycleInactive && mounted) {
      setState(() {
        _isLifecycleInactive = shouldMask;
      });
    }
  }

  @override
  void dispose() {
    _isActiveInTree = false;
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    _coordinator.unregisterScope(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;

    if (widget.watermarkText != null &&
        widget.watermarkText!.trim().isNotEmpty) {
      content = ScreenProtectionWatermark(
        text: widget.watermarkText!,
        subText: widget.watermarkSubText,
        child: content,
      );
    }

    final showRecordingShield =
        widget.hideContentWhileRecording && _isRecording;
    final showLifecycleShield =
        _isLifecycleInactive &&
        widget.maskConfig.enabled &&
        widget.maskConfig.style != ScreenProtectionMaskStyle.none;

    if (!showRecordingShield && !showLifecycleShield) {
      return content;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        content,
        Positioned.fill(
          child: showRecordingShield && widget.recordingOverlayBuilder != null
              ? widget.recordingOverlayBuilder!(context)
              : _DefaultPrivacyOverlay(
                  config: widget.maskConfig,
                  isRecordingShield: showRecordingShield,
                ),
        ),
      ],
    );
  }
}

class _DefaultPrivacyOverlay extends StatelessWidget {
  const _DefaultPrivacyOverlay({
    required this.config,
    required this.isRecordingShield,
  });

  final ScreenProtectionMaskConfig config;
  final bool isRecordingShield;

  @override
  Widget build(BuildContext context) {
    final title = isRecordingShield
        ? 'Screen Recording Detected'
        : (config.title ?? 'Privacy Protected');
    final subtitle = isRecordingShield
        ? 'Sensitive content is hidden while screen capture or mirroring is active.'
        : (config.subtitle ??
              'Screen content is hidden to protect sensitive information.');

    Widget overlayBody = Container(
      color: config.style == ScreenProtectionMaskStyle.blur
          ? config.backgroundColor.withValues(alpha: 0.78)
          : config.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (config.showLockIcon) ...<Widget>[
            Icon(
              isRecordingShield
                  ? Icons.videocam_off_rounded
                  : Icons.shield_outlined,
              size: 52.0,
              color: config.textColor,
            ),
            const SizedBox(height: 16.0),
          ],
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: config.textColor,
                fontSize: 20.0,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          if (subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8.0),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: config.textColor.withValues(alpha: 0.82),
                fontSize: 14.0,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );

    if (config.style == ScreenProtectionMaskStyle.blur &&
        config.blurSigma > 0) {
      overlayBody = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: config.blurSigma,
            sigmaY: config.blurSigma,
          ),
          child: overlayBody,
        ),
      );
    }

    return overlayBody;
  }
}
