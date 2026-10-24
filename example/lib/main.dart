import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScreenProtectionDemoApp());
}

/// Root application demonstrating all features of `xue_hua_screen_protection`.
class ScreenProtectionDemoApp extends StatelessWidget {
  /// Creates a [ScreenProtectionDemoApp].
  const ScreenProtectionDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XueHua Screen Protection Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ScreenProtectionHomePage(),
    );
  }
}

/// Interactive dashboard showcasing anti-screenshot/recording, app-switcher
/// blur masks, watermark overlays, platform capabilities, and real-time events.
class ScreenProtectionHomePage extends StatefulWidget {
  /// Creates a [ScreenProtectionHomePage].
  const ScreenProtectionHomePage({super.key});

  @override
  State<ScreenProtectionHomePage> createState() =>
      _ScreenProtectionHomePageState();
}

class _ScreenProtectionHomePageState extends State<ScreenProtectionHomePage> {
  final XueHuaScreenProtection _protection = XueHuaScreenProtection.instance;
  StreamSubscription<ScreenProtectionEvent>? _eventSubscription;

  ScreenProtectionCapabilities? _capabilities;
  ScreenProtectionStatus? _status;

  bool _secureScreenEnabled = false;
  bool _maskEnabled = true;
  ScreenProtectionMaskStyle _maskStyle = ScreenProtectionMaskStyle.blur;
  double _blurSigma = 20.0;
  bool _protectOnWindowBlur = true;
  bool _watermarkEnabled = true;
  String _watermarkText = 'CONFIDENTIAL • Matkurban';
  String _watermarkSubText = 'UID-8842 • DO NOT DISTRIBUTE';

  // Web hardening options
  bool _webDisableContextMenu = true;
  bool _webDisablePrint = true;
  bool _webInterceptShortcuts = true;

  final List<ScreenProtectionEvent> _eventLog = <ScreenProtectionEvent>[];

  @override
  void initState() {
    super.initState();
    _initializePluginState();
    _eventSubscription = _protection.onProtectionEvent.listen((event) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, event);
        if (_eventLog.length > 50) {
          _eventLog.removeLast();
        }
      });
      _refreshStatus();
    });
  }

  Future<void> _initializePluginState() async {
    try {
      await _applyMaskConfig();
      final capabilities = await _protection.getCapabilities();
      final status = await _protection.getProtectionStatus();
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _status = status;
        _secureScreenEnabled = status.isSecureScreenEnabled;
      });
    } catch (_) {
      // Safely ignore in widget unit tests where platform channel is mocked.
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _protection.getProtectionStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _secureScreenEnabled = status.isSecureScreenEnabled;
      });
    } catch (_) {}
  }

  Future<void> _toggleSecureScreen(bool value) async {
    await _protection.setSecureScreen(value);
    await _refreshStatus();
  }

  Future<void> _applyMaskConfig() async {
    final config = ScreenProtectionMaskConfig(
      enabled: _maskEnabled,
      style: _maskStyle,
      blurSigma: _blurSigma,
      backgroundColor: const Color(0xEB0F172A),
      textColor: Colors.white,
      title: 'Privacy Protected',
      subtitle: 'Sensitive financial & identity information is hidden.',
      showLockIcon: true,
      protectOnWindowBlur: _protectOnWindowBlur,
    );
    await _protection.configureAppSwitcherProtection(config);
    await _refreshStatus();
  }

  Future<void> _applyWebConfig() async {
    await _protection.configureWebProtection(
      WebProtectionConfig(
        disableContextMenu: _webDisableContextMenu,
        disablePrint: _webDisablePrint,
        disableDragAndSelect: true,
        interceptCaptureShortcuts: _webInterceptShortcuts,
        blurOnVisibilityChange: true,
      ),
    );
  }

  Future<void> _previewPrivacyMaskFor3Seconds() async {
    await _protection.showPrivacyMask();
    await _refreshStatus();
    await Future<void>.delayed(const Duration(seconds: 3));
    await _protection.hidePrivacyMask();
    await _refreshStatus();
  }

  void _openScopedVaultPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ScopedVaultDemoPage(),
      ),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('XueHua Screen Protection'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _initializePluginState,
          ),
          TextButton.icon(
            onPressed: _openScopedVaultPage,
            icon: const Icon(Icons.enhanced_encryption_rounded),
            label: const Text('Scoped Vault Page'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ScreenProtectionWatermark(
        enabled: _watermarkEnabled,
        text: _watermarkText,
        subText: _watermarkSubText,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildSensitiveAccountPreviewCard(theme),
            const SizedBox(height: 16),
            _buildCoreControlsCard(theme),
            const SizedBox(height: 16),
            _buildMaskControlsCard(theme),
            const SizedBox(height: 16),
            _buildWatermarkControlsCard(theme),
            const SizedBox(height: 16),
            _buildWebControlsCard(theme),
            const SizedBox(height: 16),
            _buildCapabilitiesCard(theme),
            const SizedBox(height: 16),
            _buildEventLogCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSensitiveAccountPreviewCard(ThemeData theme) {
    final status = _status;
    final isSecured = status?.isSecureScreenEnabled ?? _secureScreenEnabled;
    final isRecorded = status?.isScreenBeingRecorded ?? false;

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isSecured
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Confidential Treasury Vault',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(isSecured ? 'PROTECTED' : 'UNPROTECTED'),
                  backgroundColor: isSecured
                      ? Colors.green.withValues(alpha: 0.18)
                      : Colors.orange.withValues(alpha: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Account No: 6228 •••• •••• 9401   |   Balance: \$1,482,910.00',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                _buildStatusBadge(
                  icon: Icons.devices_rounded,
                  label:
                      'Platform: ${status?.platform ?? _capabilities?.platform ?? "..."}',
                ),
                _buildStatusBadge(
                  icon: Icons.fiber_manual_record_rounded,
                  label: isRecorded ? 'Recording: ACTIVE' : 'Recording: Idle',
                  isAlert: isRecorded,
                ),
                _buildStatusBadge(
                  icon: Icons.blur_on_rounded,
                  label:
                      'App Switcher Mask: ${(status?.isAppSwitcherMaskEnabled ?? _maskEnabled) ? "ON" : "OFF"}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    bool isAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAlert
            ? Colors.red.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: isAlert ? Colors.red : null),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isAlert ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoreControlsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '1. Anti-Screenshot & Anti-Recording',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Hardware Secure Screen'),
              subtitle: const Text(
                'Android FLAG_SECURE • iOS Secure Layer • macOS sharingType = .none • Windows WDA_EXCLUDEFROMCAPTURE',
              ),
              value: _secureScreenEnabled,
              onChanged: _toggleSecureScreen,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () => _toggleSecureScreen(true),
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('Enable Protection'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleSecureScreen(false),
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Disable Protection'),
                ),
                ElevatedButton.icon(
                  onPressed: _previewPrivacyMaskFor3Seconds,
                  icon: const Icon(Icons.visibility_off_rounded),
                  label: const Text('Preview Privacy Mask (3s)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaskControlsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '2. App Switcher & Inactive Window Privacy Mask',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Background / App-Switcher Mask'),
              subtitle: const Text(
                'Automatically obscures window contents when switching apps or minimizing.',
              ),
              value: _maskEnabled,
              onChanged: (bool value) {
                setState(() {
                  _maskEnabled = value;
                });
                _applyMaskConfig();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trigger Mask on Window Focus Loss'),
              subtitle: const Text(
                'Covers window immediately when another desktop/browser window takes focus.',
              ),
              value: _protectOnWindowBlur,
              onChanged: (bool value) {
                setState(() {
                  _protectOnWindowBlur = value;
                });
                _applyMaskConfig();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Text('Mask Style: '),
                const SizedBox(width: 12),
                SegmentedButton<ScreenProtectionMaskStyle>(
                  segments: const <ButtonSegment<ScreenProtectionMaskStyle>>[
                    ButtonSegment<ScreenProtectionMaskStyle>(
                      value: ScreenProtectionMaskStyle.blur,
                      label: Text('Frosted Blur'),
                      icon: Icon(Icons.blur_on_rounded),
                    ),
                    ButtonSegment<ScreenProtectionMaskStyle>(
                      value: ScreenProtectionMaskStyle.solidColor,
                      label: Text('Solid Shield'),
                      icon: Icon(Icons.format_color_fill_rounded),
                    ),
                  ],
                  selected: <ScreenProtectionMaskStyle>{_maskStyle},
                  onSelectionChanged: (Set<ScreenProtectionMaskStyle> values) {
                    setState(() {
                      _maskStyle = values.first;
                    });
                    _applyMaskConfig();
                  },
                ),
              ],
            ),
            if (_maskStyle == ScreenProtectionMaskStyle.blur) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text('Blur Sigma (${_blurSigma.toStringAsFixed(0)}):'),
                  Expanded(
                    child: Slider(
                      value: _blurSigma,
                      min: 5.0,
                      max: 40.0,
                      divisions: 7,
                      label: _blurSigma.toStringAsFixed(0),
                      onChanged: (double value) {
                        setState(() {
                          _blurSigma = value;
                        });
                      },
                      onChangeEnd: (_) => _applyMaskConfig(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWatermarkControlsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '3. Anti-Photo Leak Dynamic Watermark',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show Diagonal Security Watermark Overlay'),
              subtitle: Text('$_watermarkText • $_watermarkSubText'),
              value: _watermarkEnabled,
              onChanged: (bool value) {
                setState(() {
                  _watermarkEnabled = value;
                });
              },
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    initialValue: _watermarkText,
                    decoration: const InputDecoration(
                      labelText: 'Primary Watermark Text',
                      isDense: true,
                    ),
                    onChanged: (String value) {
                      setState(() {
                        _watermarkText = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _watermarkSubText,
                    decoration: const InputDecoration(
                      labelText: 'Secondary Watermark Text',
                      isDense: true,
                    ),
                    onChanged: (String value) {
                      setState(() {
                        _watermarkSubText = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebControlsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '4. Web Browser Hardening Options',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disable Right-Click Context Menu'),
              value: _webDisableContextMenu,
              onChanged: (bool value) {
                setState(() {
                  _webDisableContextMenu = value;
                });
                _applyWebConfig();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Block Browser Print & PDF Export (@media print)',
              ),
              value: _webDisablePrint,
              onChanged: (bool value) {
                setState(() {
                  _webDisablePrint = value;
                });
                _applyWebConfig();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Intercept Capture & Print Shortcuts (PrintScreen / Ctrl+P)',
              ),
              value: _webInterceptShortcuts,
              onChanged: (bool value) {
                setState(() {
                  _webInterceptShortcuts = value;
                });
                _applyWebConfig();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard(ThemeData theme) {
    final caps = _capabilities;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '5. Current Platform Capability Matrix',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (caps == null)
              const Text('Loading platform capabilities...')
            else ...<Widget>[
              Text('OS Version: ${caps.osVersion}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _buildCapChip(
                    'Anti-Screenshot',
                    caps.supportsHardwareAntiScreenshot,
                  ),
                  _buildCapChip(
                    'Anti-Recording',
                    caps.supportsHardwareAntiRecording,
                  ),
                  _buildCapChip(
                    'Screenshot Detection',
                    caps.supportsScreenshotDetection,
                  ),
                  _buildCapChip(
                    'Recording Detection',
                    caps.supportsRecordingDetection,
                  ),
                  _buildCapChip(
                    'App Switcher Mask',
                    caps.supportsNativeAppSwitcherMask,
                  ),
                  _buildCapChip('Native Blur', caps.supportsNativeBlurEffect),
                ],
              ),
              if (caps.limitations.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                ...caps.limitations.map(
                  (String note) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $note', style: theme.textTheme.bodySmall),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCapChip(String label, bool supported) {
    return Chip(
      avatar: Icon(
        supported ? Icons.check_circle_rounded : Icons.info_outline_rounded,
        size: 18,
        color: supported ? Colors.green : Colors.orange,
      ),
      label: Text(label),
    );
  }

  Widget _buildEventLogCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '6. Real-Time Security Event Stream (${_eventLog.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_eventLog.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _eventLog.clear();
                      });
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_eventLog.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No events captured yet. Try taking a screenshot, switching windows, or clicking "Preview Privacy Mask (3s)".',
                ),
              )
            else
              ..._eventLog
                  .take(10)
                  .map(
                    (ScreenProtectionEvent event) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        event.type == ScreenProtectionEventType.screenshotTaken
                            ? Icons.camera_alt_rounded
                            : event.type ==
                                  ScreenProtectionEventType.recordingStarted
                            ? Icons.videocam_rounded
                            : Icons.shield_rounded,
                      ),
                      title: Text(
                        '${event.type.name} (${event.platform})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${event.timestamp.toIso8601String()} • ${event.metadata}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Secondary route demonstrating declarative [ScreenProtectionScope] usage.
class ScopedVaultDemoPage extends StatelessWidget {
  /// Creates a [ScopedVaultDemoPage].
  const ScopedVaultDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenProtectionScope(
      enableSecureScreen: true,
      hideContentWhileRecording: true,
      watermarkText: 'VAULT SCOPE • Matkurban',
      watermarkSubText: 'AUTO-ENABLED ON ROUTE ENTER',
      onScreenshotTaken: (ScreenProtectionEvent event) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screenshot attempt detected (${event.platform})!'),
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Declarative ScreenProtectionScope')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.security_rounded, size: 64, color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  'Protected by ScreenProtectionScope',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'While this page is mounted, hardware anti-screenshot protection, '
                  'app-switcher blur masks, active recording shields, and watermarks '
                  'are automatically active. Popping this page restores previous settings.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
