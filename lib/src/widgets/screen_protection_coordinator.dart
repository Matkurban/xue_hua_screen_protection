import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../xue_hua_screen_protection_platform_interface.dart';
import '../models/screen_protection_models.dart';

/// Internal handle implemented by [ScreenProtectionScope]'s [State] so
/// [ScreenProtectionCoordinator] can evaluate visibility and reconcile native
/// protection state across route, branch, and multi-pane transitions.
abstract interface class ScreenProtectionScopeHandle {
  /// Build context (`Element`) of the [ScreenProtectionScope].
  BuildContext get scopeContext;

  /// Whether the [State] is currently in the active lifecycle state (mounted
  /// and not between `deactivate()` and `activate()`/`dispose()`).
  bool get isActiveInTree;

  /// Whether OS-level anti-screenshot / anti-recording should be enabled while
  /// this scope is onstage.
  bool get enableSecureScreen;

  /// App-switcher / window-blur mask configuration while this scope is onstage.
  ScreenProtectionMaskConfig get maskConfig;

  /// Last computed onstage visibility flag for this scope.
  bool get isOnstage;

  /// Called by [ScreenProtectionCoordinator] whenever onstage status changes.
  void notifyOnstageChanged(bool onstage, {required bool fromDispose});
}

/// Coordinates imperative [XueHuaScreenProtection] calls with all mounted
/// [ScreenProtectionScope] widgets, ensuring protection is accurately enabled
/// only while at least one scope is visible onstage (or imperatively armed)
/// and reliably restored on route push, pop, replacement, branch switch,
/// sliding-pane offscreen shift, or widget disposal.
final class ScreenProtectionCoordinator {
  ScreenProtectionCoordinator._();

  /// Shared singleton coordinator instance.
  static final ScreenProtectionCoordinator instance =
      ScreenProtectionCoordinator._();

  final List<ScreenProtectionScopeHandle> _scopes =
      <ScreenProtectionScopeHandle>[];

  XueHuaScreenProtectionPlatform? _lastPlatform;
  WidgetsBinding? _attachedBinding;
  bool _postFrameCheckScheduled = false;

  // Baseline state configured directly through imperative XueHuaScreenProtection APIs.
  bool _imperativeSecureScreen = false;
  ScreenProtectionMaskConfig _imperativeMaskConfig =
      const ScreenProtectionMaskConfig.disabled();
  bool _hasExplicitImperativeMask = false;

  // Last state confirmed applied to the current XueHuaScreenProtectionPlatform.
  bool? _appliedSecureScreen;
  ScreenProtectionMaskConfig? _appliedMaskConfig;

  // Target state desired by active onstage scopes (or imperative baseline).
  bool _desiredSecureScreen = false;
  ScreenProtectionMaskConfig _desiredMaskConfig =
      const ScreenProtectionMaskConfig.disabled();
  bool _scopeSessionActive = false;

  bool _forceImperativeSecureSync = false;
  bool _forceImperativeMaskSync = false;
  bool _lastSecureCallResult = true;
  bool _lastMaskCallResult = true;

  Future<void>? _reconcileInFlight;

  XueHuaScreenProtectionPlatform get _platform =>
      XueHuaScreenProtectionPlatform.instance;

  void _syncPlatformInstance() {
    final current = _platform;
    if (identical(_lastPlatform, current)) {
      return;
    }
    _lastPlatform = current;
    _imperativeSecureScreen = false;
    _imperativeMaskConfig = const ScreenProtectionMaskConfig.disabled();
    _hasExplicitImperativeMask = false;
    _appliedSecureScreen = null;
    _appliedMaskConfig = null;
    _desiredSecureScreen = false;
    _desiredMaskConfig = const ScreenProtectionMaskConfig.disabled();
    _scopeSessionActive = false;
    _forceImperativeSecureSync = false;
    _forceImperativeMaskSync = false;
    _lastSecureCallResult = true;
    _lastMaskCallResult = true;
  }

  void _ensureFrameCallbacksAttached() {
    final binding = WidgetsBinding.instance;
    if (identical(_attachedBinding, binding)) {
      return;
    }
    _attachedBinding = binding;
    binding.addPersistentFrameCallback((Duration _) {
      if (_scopes.isEmpty) {
        return;
      }
      _schedulePostFrameEvaluation();
    });
  }

  void _schedulePostFrameEvaluation() {
    if (_postFrameCheckScheduled) {
      return;
    }
    _postFrameCheckScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _postFrameCheckScheduled = false;
      evaluateAndReconcile();
    });
  }

  /// Registers a newly mounted [ScreenProtectionScopeHandle].
  ///
  /// Defers native channel activation to the post-frame phase so route pushes
  /// and Flutter Driver interactions complete first-frame rasterization cleanly.
  void registerScope(ScreenProtectionScopeHandle scope) {
    _syncPlatformInstance();
    if (!_scopes.contains(scope)) {
      _scopes.add(scope);
    }
    _ensureFrameCallbacksAttached();
    _schedulePostFrameEvaluation();
  }

  /// Notifies the coordinator that a registered scope's widget configuration or
  /// tree activation state changed.
  void notifyScopeChanged(ScreenProtectionScopeHandle scope) {
    _syncPlatformInstance();
    if (!_scopes.contains(scope)) {
      return;
    }
    _schedulePostFrameEvaluation();
  }

  /// Unregisters a disposing [ScreenProtectionScopeHandle] and immediately
  /// reconciles protection state so unmounted pages never leave stale native
  /// flags or app-switcher masks behind.
  void unregisterScope(ScreenProtectionScopeHandle scope) {
    _syncPlatformInstance();
    _scopes.remove(scope);
    if (scope.isOnstage) {
      scope.notifyOnstageChanged(false, fromDispose: true);
    }
    evaluateAndReconcile();
  }

  /// Records an imperative `setSecureScreen` / `enableSecureScreen` /
  /// `disableSecureScreen` request and reconciles with any onstage scopes.
  Future<bool> setImperativeSecureScreen(bool enabled) async {
    _syncPlatformInstance();
    _imperativeSecureScreen = enabled;
    final onstageScopes = _collectOnstageScopes(notifyChanges: true);
    if (onstageScopes.isEmpty) {
      _desiredSecureScreen = enabled;
      _forceImperativeSecureSync = true;
      await _reconcile();
      return _lastSecureCallResult;
    }
    _updateDesiredFromOnstageScopes(onstageScopes);
    await _reconcile();
    return true;
  }

  /// Records an imperative `configureAppSwitcherProtection` request and
  /// reconciles with any onstage scopes.
  Future<bool> setImperativeMaskConfig(
    ScreenProtectionMaskConfig config,
  ) async {
    _syncPlatformInstance();
    _imperativeMaskConfig = config;
    _hasExplicitImperativeMask = true;
    final onstageScopes = _collectOnstageScopes(notifyChanges: true);
    if (onstageScopes.isEmpty) {
      _desiredMaskConfig = config;
      _forceImperativeMaskSync = true;
      await _reconcile();
      return _lastMaskCallResult;
    }
    _updateDesiredFromOnstageScopes(onstageScopes);
    await _reconcile();
    return true;
  }

  /// Evaluates onstage visibility for all mounted [ScreenProtectionScope]s and
  /// reconciles platform state if needed.
  void evaluateAndReconcile() {
    _syncPlatformInstance();
    final onstageScopes = _collectOnstageScopes(notifyChanges: true);
    if (onstageScopes.isNotEmpty) {
      _scopeSessionActive = true;
      _updateDesiredFromOnstageScopes(onstageScopes);
      unawaited(_reconcile());
      return;
    }

    if (_scopeSessionActive) {
      _desiredSecureScreen = _imperativeSecureScreen;
      _desiredMaskConfig = _imperativeMaskConfig;
      unawaited(_reconcile());
    }
  }

  List<ScreenProtectionScopeHandle> _collectOnstageScopes({
    required bool notifyChanges,
  }) {
    if (_scopes.isEmpty) {
      return const <ScreenProtectionScopeHandle>[];
    }
    final onstage = <ScreenProtectionScopeHandle>[];
    // Iterate over a snapshot in case notifyOnstageChanged triggers listener work.
    final snapshot = List<ScreenProtectionScopeHandle>.of(_scopes);
    for (final scope in snapshot) {
      if (!_scopes.contains(scope)) {
        continue;
      }
      final visible = _isScopeHandleOnstage(scope);
      if (notifyChanges && visible != scope.isOnstage) {
        scope.notifyOnstageChanged(visible, fromDispose: false);
      }
      if (visible) {
        onstage.add(scope);
      }
    }
    return onstage;
  }

  void _updateDesiredFromOnstageScopes(
    List<ScreenProtectionScopeHandle> onstageScopes,
  ) {
    _desiredSecureScreen = onstageScopes.any(
      (ScreenProtectionScopeHandle s) => s.enableSecureScreen,
    );

    ScreenProtectionMaskConfig? activeMask;
    for (var i = onstageScopes.length - 1; i >= 0; i--) {
      final candidate = onstageScopes[i].maskConfig;
      if (candidate.enabled &&
          candidate.style != ScreenProtectionMaskStyle.none) {
        activeMask = candidate;
        break;
      }
    }
    _desiredMaskConfig = activeMask ?? onstageScopes.last.maskConfig;
  }

  Future<void> _reconcile() {
    return _reconcileInFlight ??= _runReconcileLoop().whenComplete(() {
      _reconcileInFlight = null;
    });
  }

  Future<void> _runReconcileLoop() async {
    while (true) {
      final platform = _platform;
      if (!identical(_lastPlatform, platform)) {
        _syncPlatformInstance();
        return;
      }

      final hasOnstageScopes = _scopes.any(
        (ScreenProtectionScopeHandle s) => s.isOnstage && s.isActiveInTree,
      );

      final needImperativeSecure = _forceImperativeSecureSync;
      final needImperativeMask = _forceImperativeMaskSync;

      final needScopeSecure =
          _scopeSessionActive &&
          (hasOnstageScopes
              ? _appliedSecureScreen != _desiredSecureScreen
              : (_appliedSecureScreen != null &&
                    _appliedSecureScreen != _desiredSecureScreen));

      final needScopeMask =
          _scopeSessionActive &&
          (hasOnstageScopes
              ? _appliedMaskConfig != _desiredMaskConfig
              : (_appliedMaskConfig != null &&
                    _appliedMaskConfig != _desiredMaskConfig));

      if (!needImperativeSecure &&
          !needImperativeMask &&
          !needScopeSecure &&
          !needScopeMask) {
        if (!hasOnstageScopes) {
          _scopeSessionActive = false;
        }
        return;
      }

      // When restoring an imperative secure=true baseline without an explicit
      // imperative mask config, clear the scope's mask first so setSecureScreen(true)
      // can re-arm Linux's focus-out mask fallback cleanly.
      final restoreMaskBeforeSecure =
          !hasOnstageScopes &&
          _desiredSecureScreen &&
          !_hasExplicitImperativeMask &&
          needScopeMask;

      if (restoreMaskBeforeSecure) {
        final targetMask = _desiredMaskConfig;
        _forceImperativeMaskSync = false;
        _lastMaskCallResult = await platform.configureAppSwitcherProtection(
          targetMask,
        );
        if (identical(_lastPlatform, platform)) {
          _appliedMaskConfig = targetMask;
          // Force secure re-application so platforms like Linux re-arm secure fallback.
          _appliedSecureScreen = null;
        }
        continue;
      }

      if (needImperativeSecure ||
          needScopeSecure ||
          (!hasOnstageScopes &&
              _scopeSessionActive &&
              _desiredSecureScreen &&
              _appliedSecureScreen == null)) {
        final targetSecure = _desiredSecureScreen;
        _forceImperativeSecureSync = false;
        _lastSecureCallResult = await platform.setSecureScreen(targetSecure);
        if (identical(_lastPlatform, platform)) {
          _appliedSecureScreen = targetSecure;
        }
        continue;
      }

      if (needImperativeMask || needScopeMask) {
        final targetMask = _desiredMaskConfig;
        _forceImperativeMaskSync = false;
        _lastMaskCallResult = await platform.configureAppSwitcherProtection(
          targetMask,
        );
        if (identical(_lastPlatform, platform)) {
          _appliedMaskConfig = targetMask;
        }
        continue;
      }
    }
  }

  bool _isScopeHandleOnstage(ScreenProtectionScopeHandle handle) {
    if (!handle.isActiveInTree) {
      return false;
    }
    final BuildContext context = handle.scopeContext;
    if (!context.mounted || context is! Element) {
      return false;
    }
    return _isElementOnstage(context);
  }

  bool _isElementOnstage(Element scopeElement) {
    if (!scopeElement.mounted) {
      return false;
    }

    final readOnlyContext = _NonSubscribingBuildContext(scopeElement);

    // 1. Check Inherited _VisibilityScope (covers Visibility(visible: false) in
    //    all maintain modes and Flutter 3.47+ IndexedStack inactive branches).
    if (!Visibility.of(readOnlyContext)) {
      return false;
    }

    // 2. Walk ancestor Elements to catch:
    //    - Explicit Offstage(offstage: true) (e.g. ParkedCovers, user Offstage).
    //      Note: MaterialApp's HeroController sets `toRoute.offstage = true`
    //      during Frame 1 build and clears `toRoute.offstage = false` in its
    //      post-frame callback before our coordinator runs, leaving _ModalScope's
    //      internal Offstage widget at its pre-callback value until Frame 2.
    //      We distinguish _ModalScope's internal Offstage (the direct child of
    //      _ModalScopeStatus) and consult the live `route.offstage` flag.
    //    - Visibility(visible: false)
    //    - Combined IgnorePointer(ignoring: true) + ExcludeFocus(excluding: true)
    //      + ExcludeSemantics(excluding: true) ancestors used by sliding multi-pane
    //      viewports (such as SlidingPaneFrame when ticking == false).
    var hiddenByAncestorWidget = false;
    var hasIgnorePointer = false;
    var hasExcludeFocus = false;
    var hasExcludeSemantics = false;
    Element? pendingOffstageElement;
    ModalRoute<dynamic>? pendingOffstageRoute;
    Set<RenderObject>? heroClearedModalOffstages;

    scopeElement.visitAncestorElements((Element ancestor) {
      if (pendingOffstageElement != null) {
        if (ancestor is InheritedElement) {
          // Step past _ModalScopeStatus itself (whose _inheritedElements map
          // includes itself) so we inspect the ModalRoute above it.
          return true;
        }
        final ModalRoute<dynamic>? parentRoute = _modalRouteOfWithoutDependency(
          ancestor,
        );
        final isModalScopeInternalOffstage =
            pendingOffstageRoute != null &&
            !identical(parentRoute, pendingOffstageRoute);
        if (isModalScopeInternalOffstage && !pendingOffstageRoute!.offstage) {
          final RenderObject? ro = pendingOffstageElement!.renderObject;
          if (ro != null) {
            (heroClearedModalOffstages ??= <RenderObject>{}).add(ro);
          }
          pendingOffstageElement = null;
          pendingOffstageRoute = null;
        } else {
          hiddenByAncestorWidget = true;
          pendingOffstageElement = null;
          pendingOffstageRoute = null;
          return false;
        }
      }

      final Widget w = ancestor.widget;
      if (w is Offstage && w.offstage) {
        pendingOffstageElement = ancestor;
        pendingOffstageRoute = _modalRouteOfWithoutDependency(ancestor);
        return true;
      }
      if (w is Visibility && !w.visible) {
        hiddenByAncestorWidget = true;
        return false;
      }
      if (w is IgnorePointer && w.ignoring) {
        hasIgnorePointer = true;
      } else if (w is ExcludeFocus && w.excluding) {
        hasExcludeFocus = true;
      } else if (w is ExcludeSemantics && w.excluding) {
        hasExcludeSemantics = true;
      }
      if (hasIgnorePointer && hasExcludeFocus && hasExcludeSemantics) {
        hiddenByAncestorWidget = true;
        return false;
      }
      return true;
    });
    if (pendingOffstageElement != null) {
      hiddenByAncestorWidget = true;
    }
    if (hiddenByAncestorWidget) {
      return false;
    }

    // 3. Walk ancestor RenderObjects to detect render-level offstage containers:
    //    - RenderOffstage(offstage: true)
    //    - RenderIndexedStack inactive children
    //    - OffstagePageHost / RenderOffstagePage (non-empty child layout size
    //      whose parent paint clip is Rect.zero).
    final RenderObject? scopeRenderObject = scopeElement.findRenderObject();
    if (scopeRenderObject != null) {
      if (!scopeRenderObject.attached) {
        return false;
      }
      RenderObject? child = scopeRenderObject;
      RenderObject? parent = child.parent;
      while (parent != null && child != null) {
        if (parent is RenderOffstage &&
            parent.offstage &&
            !(heroClearedModalOffstages?.contains(parent) ?? false)) {
          return false;
        }
        if (parent is RenderIndexedStack) {
          final int? activeIndex = parent.index;
          if (activeIndex == null) {
            return false;
          }
          RenderBox? current = parent.firstChild;
          var idx = 0;
          var isSelected = false;
          while (current != null) {
            if (identical(current, child)) {
              isSelected = idx == activeIndex;
              break;
            }
            current = parent.childAfter(current);
            idx++;
          }
          if (!isSelected) {
            return false;
          }
        }
        if (child is RenderBox &&
            child.hasSize &&
            !child.size.isEmpty &&
            parent.describeApproximatePaintClip(child) == Rect.zero) {
          return false;
        }
        child = parent;
        parent = child.parent;
      }
    }

    // 4. Walk all enclosing ModalRoutes from inner-most Navigator up to the
    //    root Navigator (handles nested branch Navigators, chrome cover
    //    Navigators, and root Navigator shell containers).
    ModalRoute<dynamic>? route = _modalRouteOfWithoutDependency(scopeElement);
    while (route != null) {
      if (!route.isActive || route.offstage) {
        return false;
      }
      if (!route.isCurrent && _isObscuredByOpaqueRouteAbove(route)) {
        return false;
      }
      final NavigatorState? nav = route.navigator;
      if (nav == null || !nav.mounted) {
        break;
      }
      route = _modalRouteOfWithoutDependency(nav.context);
    }

    return true;
  }

  ModalRoute<dynamic>? _modalRouteOfWithoutDependency(BuildContext context) {
    if (!context.mounted) {
      return null;
    }
    return ModalRoute.of<dynamic>(_NonSubscribingBuildContext(context));
  }

  bool _isObscuredByOpaqueRouteAbove(ModalRoute<dynamic> route) {
    final NavigatorState? nav = route.navigator;
    if (nav == null || !nav.mounted) {
      return true;
    }

    final OverlayState? overlay = nav.overlay;
    if (overlay != null && overlay.mounted) {
      Element? theaterElement;
      overlay.context.visitChildElements((Element child) {
        theaterElement ??= child;
      });

      if (theaterElement != null) {
        var seenTarget = false;
        var seenAnyNavRoute = false;
        var obscuredByOpaqueAbove = false;

        theaterElement!.visitChildElements((Element overlayEntryElement) {
          if (obscuredByOpaqueAbove) {
            return;
          }
          final ModalRoute<dynamic>? entryRoute =
              _extractModalRouteFromOverlayEntry(overlayEntryElement, nav);
          if (entryRoute == null) {
            return;
          }
          seenAnyNavRoute = true;
          if (identical(entryRoute, route)) {
            seenTarget = true;
            return;
          }
          if (seenTarget &&
              entryRoute.isActive &&
              !entryRoute.offstage &&
              entryRoute.opaque) {
            obscuredByOpaqueAbove = true;
          }
        });

        if (obscuredByOpaqueAbove) {
          return true;
        }
        if (seenTarget) {
          return false;
        }
        if (seenAnyNavRoute) {
          // Target route was skipped by Overlay because maintainState == false
          // while covered by an opaque OverlayEntry above it.
          return true;
        }
      }
    }

    final Animation<double>? secondary = route.secondaryAnimation;
    if (secondary != null && secondary.status != AnimationStatus.dismissed) {
      return true;
    }
    return true;
  }

  ModalRoute<dynamic>? _extractModalRouteFromOverlayEntry(
    Element overlayEntryElement,
    NavigatorState targetNavigator,
  ) {
    var budget = 32;

    ModalRoute<dynamic>? search(Element element, int depth) {
      if (budget <= 0 || depth > 20 || !element.mounted) {
        return null;
      }
      budget--;

      if (!identical(element, overlayEntryElement)) {
        final ModalRoute<dynamic>? candidate = _modalRouteOfWithoutDependency(
          element,
        );
        if (candidate != null &&
            identical(candidate.navigator, targetNavigator)) {
          return candidate;
        }
        if (element.widget is Navigator) {
          return null;
        }
      }

      ModalRoute<dynamic>? found;
      element.visitChildElements((Element child) {
        if (found != null || budget <= 0) {
          return;
        }
        found = search(child, depth + 1);
      });
      return found;
    }

    return search(overlayEntryElement, 0);
  }
}

/// Read-only [BuildContext] proxy that resolves [InheritedWidget] /
/// [InheritedModel] lookups (such as [ModalRoute.of] and [Visibility.of]) in
/// O(1) without registering rebuild dependencies or mutating element state.
final class _NonSubscribingBuildContext implements BuildContext {
  const _NonSubscribingBuildContext(this._delegate);

  final BuildContext _delegate;

  @override
  Widget get widget => _delegate.widget;

  @override
  BuildOwner? get owner => _delegate.owner;

  @override
  bool get mounted => _delegate.mounted;

  @override
  bool get debugDoingBuild => _delegate.debugDoingBuild;

  @override
  RenderObject? findRenderObject() => _delegate.findRenderObject();

  @override
  Size? get size => _delegate.size;

  @override
  InheritedWidget dependOnInheritedElement(
    InheritedElement ancestor, {
    Object? aspect,
  }) => ancestor.widget as InheritedWidget;

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) => _delegate.getInheritedWidgetOfExactType<T>();

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _delegate.getInheritedWidgetOfExactType<T>();

  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _delegate.getElementForInheritedWidgetOfExactType<T>();

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() =>
      _delegate.findAncestorWidgetOfExactType<T>();

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() =>
      _delegate.findAncestorStateOfType<T>();

  @override
  T? findRootAncestorStateOfType<T extends State<StatefulWidget>>() =>
      _delegate.findRootAncestorStateOfType<T>();

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() =>
      _delegate.findAncestorRenderObjectOfType<T>();

  @override
  void visitAncestorElements(ConditionalElementVisitor visitor) =>
      _delegate.visitAncestorElements(visitor);

  @override
  void visitChildElements(ElementVisitor visitor) =>
      _delegate.visitChildElements(visitor);

  @override
  void dispatchNotification(Notification notification) =>
      _delegate.dispatchNotification(notification);

  @override
  DiagnosticsNode describeElement(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) => _delegate.describeElement(name, style: style);

  @override
  DiagnosticsNode describeWidget(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) => _delegate.describeWidget(name, style: style);

  @override
  List<DiagnosticsNode> describeMissingAncestor({
    required Type expectedAncestorType,
  }) => _delegate.describeMissingAncestor(
    expectedAncestorType: expectedAncestorType,
  );

  @override
  DiagnosticsNode describeOwnershipChain(String name) =>
      _delegate.describeOwnershipChain(name);
}
