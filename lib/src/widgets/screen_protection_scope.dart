import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../xue_hua_screen_protection.dart';

/// A declarative lifecycle widget that automatically enables screen protection
/// while mounted and optionally renders an in-app shield during active screen
/// recording or background transitions.
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
    with WidgetsBindingObserver {
  final XueHuaScreenProtection _plugin = XueHuaScreenProtection.instance;
  StreamSubscription<ScreenProtectionEvent>? _eventSubscription;
  bool _isRecording = false;
  bool _isLifecycleInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer native calls until after the first frame so route pushes / Driver
    // taps can settle before secure-screen + mask configuration runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyConfiguration();
    });
    _eventSubscription = _plugin.onProtectionEvent.listen(_handleEvent);
  }

  @override
  void didUpdateWidget(covariant ScreenProtectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableSecureScreen != widget.enableSecureScreen ||
        oldWidget.maskConfig != widget.maskConfig) {
      _applyConfiguration();
    }
  }

  Future<void> _applyConfiguration() async {
    await _plugin.setSecureScreen(widget.enableSecureScreen);
    await _plugin.configureAppSwitcherProtection(widget.maskConfig);
    final recording = await _plugin.isScreenBeingRecorded();
    if (mounted && recording != _isRecording) {
      setState(() {
        _isRecording = recording;
      });
    }
  }

  void _handleEvent(ScreenProtectionEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case ScreenProtectionEventType.screenshotTaken:
      case ScreenProtectionEventType.shortcutBlocked:
        widget.onScreenshotTaken?.call(event);
      case ScreenProtectionEventType.recordingStarted:
        if (!_isRecording) {
          setState(() {
            _isRecording = true;
          });
          widget.onRecordingStateChanged?.call(true);
        }
      case ScreenProtectionEventType.recordingStopped:
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
    if (!widget.maskConfig.enabled ||
        widget.maskConfig.style == ScreenProtectionMaskStyle.none) {
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
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    if (widget.enableSecureScreen) {
      _plugin.setSecureScreen(false);
    }
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
