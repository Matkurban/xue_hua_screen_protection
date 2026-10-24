# xue_hua_screen_protection

[English](./README.md) | **简体中文**

一款功能完整、跨六端（**Android、iOS、macOS、Windows、Linux、Web**）的 Flutter 屏幕隐私安全保护插件，提供 **系统级防截屏、防录屏/防屏幕共享、截屏与录屏事件实时检测、切后台/多任务切换毛玻璃模糊遮罩、Web 端防打印与快捷键拦截、以及防拍照泄密动态水印组件**。

- **作者**：Matkurban (`3496354336@qq.com`)
- **仓库地址**：[https://github.com/Matkurban/xue_hua_screen_protection](https://github.com/Matkurban/xue_hua_screen_protection)
- **当前版本**：`1.0.0`

## 核心特性

- **系统硬件级防截屏与防录屏**：在 Android、iOS、macOS、Windows 上调用系统底层安全 API，阻止系统截屏、录屏及第三方会议软件（Zoom、腾讯会议、OBS 等）采集窗口画面。
- **截屏与录屏实时检测流**：提供 `onScreenCaptured`、`onScreenRecordingChanged` 与 `onProtectionEvent` 广播流，实时监听用户截屏、开始录屏/镜像投屏与结束录屏事件。
- **切后台 / 多任务切换 / 窗口失焦隐私遮罩**：当应用进入多任务切换界面、退至后台或桌面窗口失去焦点时，自动覆盖原生毛玻璃模糊层（`RenderEffect`、`UIVisualEffectView`、`NSVisualEffectView`、CSS `backdrop-filter`）或纯色安全护盾。
- **Web 浏览器多维防采集加固**：支持动态注入 `@media print` 禁止打印与导出 PDF、禁用右键菜单、禁止文本选择与图片拖拽，并拦截 `PrintScreen`、`Ctrl/Cmd+P`、`Ctrl/Cmd+S`、`F12` 等快捷键。
- **声明式 Flutter 保护组件**：
  - `ScreenProtectionScope`：页面级生命周期保护组件，进入页面自动开启防截屏与遮罩、录屏时自动隐藏敏感内容，退出页面自动恢复。
  - `ScreenProtectionWatermark`：基于 `CustomPaint` 与 `IgnorePointer` 的高性能斜向平铺防拍屏水印组件。
- **运行时平台能力自检**：通过 `getCapabilities()` 与 `getProtectionStatus()` 动态查询当前宿主系统的原生支持矩阵与平台限制说明。
- **内置标准 AI Package Skill**：遵循 [Dart 官方 Package Skills 规范](https://dart.dev/tools/pub/package-skills)，随包内置 `skills/xue-hua-screen-protection-usage/SKILL.md`。

## 全平台实现与能力对比

| 功能特性            | Android (API 24+)                                      | iOS (15.0+)                              | macOS (12.0+)                                | Windows (10/11+)                                      | Linux (GTK 3)              | Web (现代浏览器)                       |
|:--------------------|:-------------------------------------------------------|:-----------------------------------------|:---------------------------------------------|:------------------------------------------------------|:---------------------------|:---------------------------------------|
| **防系统截屏**      | `FLAG_SECURE`                                          | `UITextField` 安全图层容器               | `NSWindow.sharingType = .none`               | `SetWindowDisplayAffinity` (`WDA_EXCLUDEFROMCAPTURE`) | 窗口失焦遮罩 + 水印        | `@media print` + 快捷键拦截            |
| **防系统录屏/共享** | `FLAG_SECURE`                                          | `UITextField` 安全图层容器               | `NSWindow.sharingType = .none`               | `SetWindowDisplayAffinity` (`WDA_EXCLUDEFROMCAPTURE`) | 窗口失焦遮罩 + 水印        | 标签页隐藏遮罩 + 水印                  |
| **截屏事件检测**    | API 34 `ScreenCaptureCallback` + `ContentObserver`     | `userDidTakeScreenshotNotification`      | `NSMetadataQuery` (`kMDItemIsScreenCapture`) | `WM_CLIPBOARDUPDATE` + `VK_SNAPSHOT`                  | X11/Wayland 暂不支持       | `PrintScreen` / `Cmd+Shift+3/4/5`      |
| **录屏/投屏检测**   | API 35 `addScreenRecordingCallback` + `DisplayManager` | `UIScreen.capturedDidChangeNotification` | `NSWorkspace` 采集进程监测                   | DWM 底层直接屏蔽采集                                  | X11/Wayland 暂不支持       | 浏览器沙箱不暴露系统录屏状态           |
| **切后台/失焦遮罩** | `ActivityLifecycle` + API 31 `RenderEffect` 模糊       | `UIVisualEffectView` 毛玻璃 / 纯色遮罩   | `NSVisualEffectView` 毛玻璃 / 纯色遮罩       | `WM_ACTIVATE` Win32 置顶遮罩层                        | GTK `focus-out-event` 遮罩 | `visibilitychange` + `backdrop-filter` |
| **防拍照泄密水印**  | 支持                                                   | 支持                                     | 支持                                         | 支持                                                  | 支持                       | 支持                                   |

## 安装与集成

在项目的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  xue_hua_screen_protection: ^1.0.0
```

或者直接通过 Git 仓库依赖：

```yaml
dependencies:
  xue_hua_screen_protection:
    git:
      url: https://github.com/Matkurban/xue_hua_screen_protection.git
```

### 安装随包附带的 AI 编程助手 Skill

本插件已按照 [Ship skills with packages](https://dart.dev/tools/pub/package-skills) 标准内置 AI Skill，宿主项目可通过以下命令一键安装：

```bash
dart run skills@ get
```

## 各端配置说明

### Android

插件的 `AndroidManifest.xml` 已默认声明 Android 14+ (API 34) 截屏检测与 Android 15+ (API 35) 录屏检测权限，宿主项目无需额外手动请求动态权限：

```xml
<uses-permission android:name="android.permission.DETECT_SCREEN_CAPTURE" />
<uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING" />
```

### iOS 与 macOS

无需额外配置 `Info.plist` 权限。最低系统版本要求：
- **iOS**：`15.0`
- **macOS**：`12.0`

### Windows、Linux 与 Web

开箱即用，无需额外原生配置。

## 快速上手

### 1. 命令式全局控制 (`XueHuaScreenProtection.instance`)

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

Future<void> initScreenProtection() async {
  final protection = XueHuaScreenProtection.instance;

  // 1. 开启系统级防截屏与防录屏
  await protection.enableSecureScreen();

  // 2. 配置切后台 / 多任务切换 / 窗口失焦时的隐私遮罩
  await protection.configureAppSwitcherProtection(
    const ScreenProtectionMaskConfig(
      enabled: true,
      style: ScreenProtectionMaskStyle.blur,
      blurSigma: 20.0,
      backgroundColor: Color(0xEB0F172A),
      textColor: Colors.white,
      title: '隐私安全保护中',
      subtitle: '当前页面包含敏感信息，已自动隐藏窗口内容。',
      showLockIcon: true,
      protectOnWindowBlur: true,
    ),
  );

  // 3. 配置 Web 端防打印、禁用右键及快捷键拦截（在原生端调用会安全返回 false）
  await protection.configureWebProtection(
    const WebProtectionConfig(
      disableContextMenu: true,
      disablePrint: true,
      disableDragAndSelect: true,
      interceptCaptureShortcuts: true,
      blurOnVisibilityChange: true,
    ),
  );

  // 4. 监听截屏事件
  protection.onScreenCaptured.listen((ScreenProtectionEvent event) {
    debugPrint('检测到截屏行为 (${event.platform}): ${event.metadata}');
  });

  // 5. 监听录屏 / 屏幕镜像状态变化
  protection.onScreenRecordingChanged.listen((bool isRecording) {
    debugPrint('当前是否正在录屏/投屏: $isRecording');
  });
}
```

### 2. 声明式页面级保护组件 (`ScreenProtectionScope`)

使用 `ScreenProtectionScope` 包裹敏感业务页面（如账单详情、密钥展示、内部文档），组件挂载时自动开启防截屏与遮罩，检测到录屏时自动展示防窥护盾，页面销毁时自动恢复：

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

class SecretDocumentPage extends StatelessWidget {
  const SecretDocumentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenProtectionScope(
      enableSecureScreen: true,
      hideContentWhileRecording: true,
      watermarkText: '核心机密 • Matkurban',
      watermarkSubText: '工号 8842 • 严禁外传',
      onScreenshotTaken: (event) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前页面包含敏感信息，已限制截屏！')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('机密文档')),
        body: const Center(child: Text('受保护的核心业务数据')),
      ),
    );
  }
}
```

### 3. 独立防拍照泄密水印组件 (`ScreenProtectionWatermark`)

```dart
ScreenProtectionWatermark(
  enabled: true,
  text: '内部资料 • Matkurban',
  subText: 'UID-9041 • 拍照留痕',
  angleDegrees: -24.0,
  opacity: 0.12,
  child: YourSensitiveWidget(),
)
```

### 4. 查询当前平台支持能力与实时状态

```dart
final capabilities = await XueHuaScreenProtection.instance.getCapabilities();
debugPrint('是否支持硬件级防截屏: ${capabilities.supportsHardwareAntiScreenshot}');
for (final note in capabilities.limitations) {
  debugPrint('平台注意事项: $note');
}

final status = await XueHuaScreenProtection.instance.getProtectionStatus();
debugPrint('当前保护状态: $status');
```

## 注意事项与平台差异说明

1. **iOS 真机与模拟器测试提示**：iOS 端采用 `UITextField(isSecureTextEntry = true)` 安全图层容器挂载方案。在模拟器上测试时，请使用模拟器菜单 `Device -> Trigger Screenshot` 触发 iOS 系统截屏，而不要直接使用 macOS 宿主机对模拟器窗口截屏。
2. **Android 版本差异说明**：
   - Android 14 (API 34) 及以上支持官方 `Activity.ScreenCaptureCallback`；Android 15 (API 35) 及以上支持官方 `WindowManager.addScreenRecordingCallback`。
   - Android 12 (API 31) 及以上支持 `RenderEffect` 硬件高斯模糊遮罩；Android 7.0–11 自动回退为高对比度半透明/纯色安全遮罩。
   - 当开启 `FLAG_SECURE` 时，Android 系统会直接阻止生成截屏文件，因此在 Android 13 及以下版本开启防截屏后不会写入媒体库文件。
3. **Windows 版本差异说明**：Windows 10 2004 (Build 19041) 及 Windows 11 使用 `WDA_EXCLUDEFROMCAPTURE`（截屏与录制时窗口完全排除/透明）；旧版 Windows 自动回退为 `WDA_MONITOR`（截屏画面呈现纯黑）。
4. **Linux 与 Web 安全边界**：受限于 Linux 桌面合成器（X11/Wayland）与 Web 浏览器沙箱机制，应用层无法直接阻断操作系统外部的硬件截屏工具。建议在 Linux 与 Web 端同时启用 `configureAppSwitcherProtection`（窗口失焦自动模糊遮罩）、`configureWebProtection` 与 `ScreenProtectionWatermark` 水印组件实现纵深防御。

## 开源协议

详见 [LICENSE](./LICENSE)。
