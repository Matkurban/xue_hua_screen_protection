import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

class RecordingMockScreenProtectionPlatform
    with MockPlatformInterfaceMixin
    implements XueHuaScreenProtectionPlatform {
  bool secureEnabled = false;
  bool recordingActive = false;
  bool maskVisible = false;
  ScreenProtectionMaskConfig maskConfig =
      const ScreenProtectionMaskConfig.disabled();
  WebProtectionConfig webConfig = const WebProtectionConfig();

  final List<String> callLog = <String>[];
  final StreamController<ScreenProtectionEvent> eventController =
      StreamController<ScreenProtectionEvent>.broadcast();

  Completer<void>? setSecureScreenGate;
  Completer<void>? configureMaskGate;

  bool get isAppSwitcherMaskActive =>
      maskConfig.enabled && maskConfig.style != ScreenProtectionMaskStyle.none;

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    callLog.add('setSecureScreen($enabled)');
    if (setSecureScreenGate != null) {
      await setSecureScreenGate!.future;
    }
    secureEnabled = enabled;
    return true;
  }

  @override
  Future<bool> isSecureScreenEnabled() async => secureEnabled;

  @override
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) async {
    callLog.add(
      'configureMask(enabled=${config.enabled},style=${config.style.name},title=${config.title})',
    );
    if (configureMaskGate != null) {
      await configureMaskGate!.future;
    }
    maskConfig = config;
    return true;
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    webConfig = config;
    return true;
  }

  @override
  Future<bool> isScreenBeingRecorded() async => recordingActive;

  @override
  Future<ScreenProtectionStatus> getProtectionStatus() async {
    return ScreenProtectionStatus(
      isSecureScreenEnabled: secureEnabled,
      isAppSwitcherMaskEnabled: isAppSwitcherMaskActive,
      isScreenBeingRecorded: recordingActive,
      isMaskCurrentlyVisible: maskVisible,
      platform: 'ios',
    );
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    return const ScreenProtectionCapabilities(
      platform: 'ios',
      osVersion: 'iOS 18.0',
      supportsHardwareAntiScreenshot: true,
      supportsHardwareAntiRecording: true,
      supportsScreenshotDetection: true,
      supportsRecordingDetection: true,
      supportsNativeAppSwitcherMask: true,
      supportsNativeBlurEffect: true,
    );
  }

  @override
  Future<bool> showPrivacyMask() async {
    maskVisible = true;
    return true;
  }

  @override
  Future<bool> hidePrivacyMask() async {
    maskVisible = false;
    return true;
  }

  @override
  Stream<ScreenProtectionEvent> get onProtectionEvent => eventController.stream;
}

/// Simulates `KeepUnderlyingTickerRoute` from `xue_hua_adaptive_sliding_layout`:
/// `PageRoute.opaque` is `true`, while `OverlayEntry.opaque` is forced to `false`
/// so underlying routes keep `TickerMode == true` and never trigger
/// `didChangeDependencies` when covered.
class _KeepUnderlyingTickerPageRoute<T> extends PageRoute<T> {
  _KeepUnderlyingTickerPageRoute({
    required this.builder,
    super.settings,
    this.isOpaqueRoute = true,
    this.duration = const Duration(milliseconds: 250),
  });

  final WidgetBuilder builder;
  final bool isOpaqueRoute;
  final Duration duration;

  @override
  bool get opaque => isOpaqueRoute;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return super.createOverlayEntries().map(
      (OverlayEntry entry) => OverlayEntry(
        builder: entry.builder,
        opaque: false,
        maintainState: entry.maintainState,
        canSizeOverlay: entry.canSizeOverlay,
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }
}

/// Simulates `OffstagePageHost` / `RenderOffstagePage` from
/// `xue_hua_adaptive_sliding_layout`, keeping full child layout size & TickerMode
/// while reporting `describeApproximatePaintClip == Rect.zero` when offstage.
class _ZeroPaintClipOffstageHost extends SingleChildRenderObjectWidget {
  const _ZeroPaintClipOffstageHost({
    required this.offstage,
    required super.child,
  });

  final bool offstage;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderZeroPaintClipOffstage(offstage);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZeroPaintClipOffstage renderObject,
  ) {
    renderObject.offstage = offstage;
  }
}

class _RenderZeroPaintClipOffstage extends RenderProxyBox {
  _RenderZeroPaintClipOffstage(this._offstage);

  bool _offstage;
  set offstage(bool value) {
    if (_offstage == value) return;
    _offstage = value;
    markNeedsPaint();
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    return _offstage ? Rect.zero : null;
  }
}

/// Simulates `SlidingPaneFrame` from `xue_hua_adaptive_sliding_layout`:
/// each pane has its own independent `Navigator` (`ModalRoute.isCurrent == true`),
/// and panes slid off-viewport have `ticking == false` (`ExcludeSemantics` +
/// `ExcludeFocus` + `IgnorePointer`).
class _SimulatedSlidingPaneFrame extends StatelessWidget {
  const _SimulatedSlidingPaneFrame({
    super.key,
    required this.ticking,
    required this.child,
  });

  final bool ticking;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      height: 600,
      child: ExcludeSemantics(
        excluding: !ticking,
        child: ExcludeFocus(
          excluding: !ticking,
          child: IgnorePointer(
            ignoring: !ticking,
            child: Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => child),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  late RecordingMockScreenProtectionPlatform mockPlatform;

  setUp(() {
    mockPlatform = RecordingMockScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = mockPlatform;
  });

  tearDown(() async {
    await mockPlatform.eventController.close();
  });

  testWidgets(
    'disposing ScreenProtectionScope disables both secure screen and app-switcher mask',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScreenProtectionScope(
            enableSecureScreen: true,
            maskConfig: ScreenProtectionMaskConfig(
              enabled: true,
              style: ScreenProtectionMaskStyle.blur,
              title: 'Vault Protected',
            ),
            child: Scaffold(body: Text('Vault Page')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);
      expect(mockPlatform.maskConfig.title, 'Vault Protected');

      // Replace root widget so ScreenProtectionScope unmounts and disposes.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Unprotected Home'))),
      );
      await tester.pumpAndSettle();

      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);
    },
  );

  testWidgets(
    'pushing an unprotected route disables protection while scope stays mounted underneath, and popping re-enables it',
    (WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const ScreenProtectionScope(
            child: Scaffold(body: Text('Protected Page A')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Push Page B on top; Page A remains mounted in Navigator history!
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unprotected Page B')),
        ),
      );
      await tester.pump();
      // Even on the first transition frame, Page A is covered by active opaque Page B.
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      await tester.pumpAndSettle();
      expect(find.text('Unprotected Page B'), findsOneWidget);
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      // Pop Page B -> Page A becomes visible onstage again.
      navKey.currentState!.pop();
      await tester.pump();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('Protected Page A'), findsOneWidget);
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);
    },
  );

  testWidgets(
    'pushReplacement and pushAndRemoveUntil release protection immediately at transition start',
    (WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const ScreenProtectionScope(
            child: Scaffold(body: Text('Protected Entry')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      navKey.currentState!.pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) =>
              const Scaffold(body: Text('Next Unprotected')),
        ),
      );

      // Frame 1 of exit animation (before dispose runs at 300ms):
      await tester.pump();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);
    },
  );

  testWidgets(
    'navigating from Protected Page A to Protected Page B keeps protection continuously active without dispose drop',
    (WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const ScreenProtectionScope(
            maskConfig: ScreenProtectionMaskConfig(
              enabled: true,
              style: ScreenProtectionMaskStyle.blur,
              title: 'Mask A',
            ),
            child: Scaffold(body: Text('Protected A')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.maskConfig.title, 'Mask A');

      mockPlatform.callLog.clear();

      // pushReplacement with 300ms transition: Protected A disposes AFTER 300ms,
      // which previously wiped out Protected B's setSecureScreen(true)!
      navKey.currentState!.pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => const ScreenProtectionScope(
            maskConfig: ScreenProtectionMaskConfig(
              enabled: true,
              style: ScreenProtectionMaskStyle.solidColor,
              title: 'Mask B',
            ),
            child: Scaffold(body: Text('Protected B')),
          ),
        ),
      );

      await tester.pump();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.maskConfig.title, 'Mask B');

      await tester.pumpAndSettle();
      expect(find.text('Protected B'), findsOneWidget);
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);
      expect(mockPlatform.maskConfig.title, 'Mask B');
      // setSecureScreen(false) must NEVER have been called during A -> B handoff!
      expect(mockPlatform.callLog, isNot(contains('setSecureScreen(false)')));
    },
  );

  testWidgets(
    'non-opaque dialogs and modal bottom sheets over a protected page keep protection enabled',
    (WidgetTester tester) async {
      late BuildContext pageContext;

      await tester.pumpWidget(
        MaterialApp(
          home: ScreenProtectionScope(
            child: Builder(
              builder: (BuildContext context) {
                pageContext = context;
                return const Scaffold(body: Text('Underlying Protected Page'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Show non-opaque AlertDialog above Protected Page.
      unawaited(
        showDialog<void>(
          context: pageContext,
          builder: (_) => const AlertDialog(title: Text('Confirm Action')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm Action'), findsOneWidget);
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Dismiss dialog.
      Navigator.of(pageContext).pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);

      // Show non-opaque ModalBottomSheet above Protected Page.
      unawaited(
        showModalBottomSheet<void>(
          context: pageContext,
          builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sheet'), findsOneWidget);
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      Navigator.of(pageContext).pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
    },
  );

  testWidgets(
    'AdaptiveRouter KeepUnderlyingTickerRoute (OverlayEntry.opaque=false) and nested shell/chrome/root Navigators disable protection when covered',
    (WidgetTester tester) async {
      final rootNavKey = GlobalKey<NavigatorState>();
      final chromeNavKey = GlobalKey<NavigatorState>();
      final branchNavKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavKey,
          onGenerateRoute: (_) => _KeepUnderlyingTickerPageRoute<void>(
            settings: const RouteSettings(name: 'adaptive-shell'),
            builder: (_) => Navigator(
              key: chromeNavKey,
              onGenerateRoute: (_) => _KeepUnderlyingTickerPageRoute<void>(
                settings: const RouteSettings(name: 'adaptive-chrome'),
                builder: (_) => Navigator(
                  key: branchNavKey,
                  onGenerateRoute: (_) => _KeepUnderlyingTickerPageRoute<void>(
                    settings: const RouteSettings(name: '/vault'),
                    builder: (_) => const ScreenProtectionScope(
                      child: Scaffold(body: Text('Branch Vault Page')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // 1. Push onto inner branch Navigator using KeepUnderlyingTickerRoute
      //    (TickerMode stays true, OverlayEntry.opaque is false).
      branchNavKey.currentState!.push(
        _KeepUnderlyingTickerPageRoute<void>(
          settings: const RouteSettings(name: '/branch-next'),
          builder: (_) => const Scaffold(body: Text('Branch Next Page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      branchNavKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // 2. Push compact cover route (`hidesBottomBarWhenPushed: true`) onto
      //    outer chrome Navigator while inner branch route remains `isCurrent == true`!
      chromeNavKey.currentState!.push(
        _KeepUnderlyingTickerPageRoute<void>(
          settings: const RouteSettings(name: '/cover-detail'),
          builder: (_) => const Scaffold(body: Text('Chrome Cover Page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      chromeNavKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // 3. Push root route (`onRootNavigator: true` or `pushNamedAndRemoveUntil`
      //    keeping `adaptive-shell` mounted underneath at index 0 of root Navigator)!
      rootNavKey.currentState!.push(
        _KeepUnderlyingTickerPageRoute<void>(
          settings: const RouteSettings(name: '/root-page'),
          builder: (_) => const Scaffold(body: Text('Root Overlay Page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      rootNavKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);
    },
  );

  testWidgets(
    'IndexedStack branch switching, Offstage (ParkedCovers), Visibility, and OffstagePageHost zero paint clip toggle protection accurately',
    (WidgetTester tester) async {
      var activeBranch = 0;
      var parkedOffstage = false;
      var maintainSizeVisible = true;
      var zeroClipOffstage = false;
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return IndexedStack(
                index: activeBranch,
                children: <Widget>[
                  Offstage(
                    offstage: parkedOffstage,
                    child: Visibility(
                      visible: maintainSizeVisible,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: _ZeroPaintClipOffstageHost(
                        offstage: zeroClipOffstage,
                        child: const ScreenProtectionScope(
                          child: Scaffold(body: Text('Branch 0 Protected')),
                        ),
                      ),
                    ),
                  ),
                  const Scaffold(body: Text('Branch 1 Public')),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Switch IndexedStack to Branch 1 (`router.goBranch(1)`).
      updateHost(() => activeBranch = 1);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      // Switch back to Branch 0.
      updateHost(() => activeBranch = 0);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Park in Offstage (`ParkedCovers`).
      updateHost(() => parkedOffstage = true);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      updateHost(() => parkedOffstage = false);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);

      // Hide via Visibility(maintainState: true, maintainAnimation: true, maintainSize: true).
      updateHost(() => maintainSizeVisible = false);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      updateHost(() => maintainSizeVisible = true);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);

      // Hide via OffstagePageHost (`describeApproximatePaintClip == Rect.zero`).
      updateHost(() => zeroClipOffstage = true);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      updateHost(() => zeroClipOffstage = false);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
    },
  );

  testWidgets(
    '2-column SlidingPaneViewport keeps protection ON when protected pane is visible in left column, and turns OFF when 3rd pane slides it offscreen',
    (WidgetTester tester) async {
      var paneCount =
          2; // Depth 2: [Pane 0 (Protected), Pane 1 (Public)] -> both visible!
      late StateSetter updateStrip;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                updateStrip = setState;
                final start = paneCount - 2; // visibleCount == 2
                return OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 1200,
                  maxWidth: 1200,
                  minHeight: 600,
                  maxHeight: 600,
                  child: Row(
                    children: <Widget>[
                      _SimulatedSlidingPaneFrame(
                        key: const ValueKey<String>('pane-0'),
                        ticking: 0 >= start,
                        child: const ScreenProtectionScope(
                          child: Text('Pane 0 Protected'),
                        ),
                      ),
                      _SimulatedSlidingPaneFrame(
                        key: const ValueKey<String>('pane-1'),
                        ticking: 1 >= start,
                        child: const Text('Pane 1 Public'),
                      ),
                      if (paneCount >= 3)
                        _SimulatedSlidingPaneFrame(
                          key: const ValueKey<String>('pane-2'),
                          ticking: 2 >= start,
                          child: const Text('Pane 2 Public'),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // At depth 2 (`start == 0`), Pane 0 is visible in the left column!
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);

      // Push 3rd pane (`paneCount = 3`, `start = 1`): Pane 0 slides off-screen (`ticking: false`)
      // while its PaneNavigator stays mounted!
      updateStrip(() => paneCount = 3);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);

      // Pop 3rd pane (`paneCount = 2`, `start = 0`): Pane 0 slides back into view!
      updateStrip(() => paneCount = 2);
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.isAppSwitcherMaskActive, isTrue);
    },
  );

  testWidgets(
    'covered ScreenProtectionScope suppresses screenshot/recording callbacks until popped back onstage',
    (WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();
      final screenshots = <ScreenProtectionEvent>[];
      final recordingChanges = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: ScreenProtectionScope(
            onScreenshotTaken: screenshots.add,
            onRecordingStateChanged: recordingChanges.add,
            child: const Scaffold(body: Text('Protected Vault')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Push an unprotected page covering Protected Vault.
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Public Feed')),
        ),
      );
      await tester.pumpAndSettle();

      // Emit screenshot + recordingStarted while Vault is covered:
      mockPlatform.recordingActive = true;
      mockPlatform.eventController.add(
        ScreenProtectionEvent(
          type: ScreenProtectionEventType.screenshotTaken,
          timestamp: DateTime(2026, 1, 1),
          platform: 'ios',
        ),
      );
      mockPlatform.eventController.add(
        ScreenProtectionEvent(
          type: ScreenProtectionEventType.recordingStarted,
          timestamp: DateTime(2026, 1, 1),
          platform: 'ios',
          isCaptured: true,
        ),
      );
      await tester.pump();

      expect(screenshots, isEmpty);
      expect(recordingChanges, isEmpty);

      // Pop back to Protected Vault -> syncs active recording state and resumes events!
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(recordingChanges, equals(<bool>[true]));
      expect(find.text('Screen Recording Detected'), findsOneWidget);

      mockPlatform.eventController.add(
        ScreenProtectionEvent(
          type: ScreenProtectionEventType.screenshotTaken,
          timestamp: DateTime(2026, 1, 1),
          platform: 'ios',
        ),
      );
      await tester.pump();
      expect(screenshots, hasLength(1));
    },
  );

  testWidgets(
    'rapid mount + dispose mid-await serializes channel calls and guarantees final disabled state',
    (WidgetTester tester) async {
      final gate = Completer<void>();
      mockPlatform.setSecureScreenGate = gate;

      await tester.pumpWidget(
        const MaterialApp(
          home: ScreenProtectionScope(
            child: Scaffold(body: Text('Transient Protected Page')),
          ),
        ),
      );
      await tester.pump();

      // setSecureScreen(true) is now suspended mid-await on `gate`!
      // Immediately unmount ScreenProtectionScope BEFORE `gate` completes.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Unprotected Page'))),
      );
      await tester.pump();

      // Release the delayed platform channel gate.
      mockPlatform.setSecureScreenGate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);
    },
  );

  testWidgets(
    'restores imperative baseline when global protection was enabled prior to ScreenProtectionScope',
    (WidgetTester tester) async {
      const plugin = XueHuaScreenProtection.instance;
      const globalMask = ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.solidColor,
        title: 'Global App Shield',
      );

      await plugin.enableSecureScreen();
      await plugin.configureAppSwitcherProtection(globalMask);
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.maskConfig.title, 'Global App Shield');

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('Global Home')),
        ),
      );
      await tester.pumpAndSettle();

      // Push scoped route with its own custom mask config.
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const ScreenProtectionScope(
            maskConfig: ScreenProtectionMaskConfig(
              enabled: true,
              style: ScreenProtectionMaskStyle.blur,
              title: 'Scoped Route Shield',
            ),
            child: Scaffold(body: Text('Scoped Route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.maskConfig.title, 'Scoped Route Shield');

      // Pop scoped route -> restores global imperative baseline!
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(mockPlatform.secureEnabled, isTrue);
      expect(mockPlatform.maskConfig.title, 'Global App Shield');

      // Explicitly disable global protection.
      await plugin.disableSecureScreen();
      await plugin.configureAppSwitcherProtection(
        const ScreenProtectionMaskConfig.disabled(),
      );
      expect(mockPlatform.secureEnabled, isFalse);
      expect(mockPlatform.isAppSwitcherMaskActive, isFalse);
    },
  );
}
