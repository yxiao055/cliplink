# 平台、权限与构建说明

剪链使用同一套 Flutter 代码构建 Windows、macOS、iOS 与 Android。不同平台的网络权限、剪贴板限制和签名要求如下。

## 通用

```bash
flutter pub get
flutter analyze
flutter test
```

推荐环境：

- Flutter `3.50.1`，Dart `3.14`
- `super_clipboard 0.9.1` / `super_native_extensions 0.9.1`
- 图片与文本仅在设备之间传输，不依赖后端

构建时 `super_clipboard` 会为当前平台下载 Rust 预编译库；Android 额外需要 NDK。

## Windows

### 构建

需要：

- Windows 10/11 x64
- Visual Studio 2022（Desktop development with C++、MSVC、Windows 10/11 SDK、CMake tools）
- Windows 开发者模式（Flutter 插件符号链接要求）

```powershell
flutter config --enable-windows-desktop
flutter build windows --release
```

产物：

```text
build/windows/x64/runner/Release/cliplink.exe
build/windows/x64/runner/Release/*.dll
build/windows/x64/runner/Release/data/
```

请分发整个 `Release` 目录或打包成 zip，不能只复制 exe。

### 不需要管理员权限

`windows/runner/runner.exe.manifest` 显式声明：

```xml
<requestedExecutionLevel level="asInvoker" uiAccess="false"/>
```

因此 `cliplink.exe` 自身不会向 Windows 请求管理员权限。如果双击后出现 UAC/管理员提示：

1. 先对下载的 ZIP 执行「属性 → 解除锁定」，重新解压到桌面或文档；
2. 不要放在 `C:\Program Files` 或被策略保护的目录；
3. 检查 SmartScreen、Defender 和公司终端安全策略；
4. Windows 防火墙的允许提示属于系统网络权限，不是应用启动权限；取消该提示不影响应用打开，但会影响局域网互连。

### 防火墙

应用第一次监听 TCP/UDP 时，Windows 会询问防火墙权限：

- 勾选**专用网络**；
- 不要勾选公用网络，除非你明确在可信的专用网络中。

如果误点拒绝，可在「Windows 安全中心 → 防火墙和网络保护 → 允许应用通过防火墙」中恢复，或以管理员身份添加规则：

```powershell
New-NetFirewallRule -DisplayName "ClipLink" -Direction Inbound `
  -Program "C:\path\to\Release\cliplink.exe" -Action Allow -Profile Private
```

### 数据位置

配对信息、设置与剪贴板历史在 Windows 的应用支持目录中（通常位于 `%APPDATA%\ClipLink\...`）。删除该目录可重置设备身份与全部配对记录。

便携/自动化场景可以设置 `CLIPLINK_DATA_DIR` 环境变量，把配置和配对数据放到指定目录：

```powershell
$env:CLIPLINK_DATA_DIR = "D:\ClipLinkData"
.\cliplink.exe
```

## macOS

### 构建

需要 macOS 与 Xcode：

```bash
flutter build macos --release
```

产物在 `build/macos/Build/Products/Release/`。App 已配置：

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.network.server`
- `NSLocalNetworkUsageDescription`

首次访问局域网会弹出本地网络权限请求，需要允许，否则只能使用手动地址但 TCP 连接仍可能被拒绝。

正式分发需要 Developer ID 签名和 notarization；开发构建可以直接本地运行。

## iOS

### 构建

需要 macOS、Xcode 和 Apple Developer Team：

```bash
flutter build ipa --release
```

在 Xcode 中打开 `ios/Runner.xcworkspace`，配置：

- Signing & Capabilities → Team / Bundle Identifier
- 真机运行需信任开发者证书

`Info.plist` 已包含：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>剪链需要在局域网内发现你的其他设备并同步剪贴板……</string>
```

首次进行发现/连接时，iOS 会弹「允许查找本地网络设备」。拒绝后可在 设置 → 隐私与安全性 → 本地网络 中重新开启。

### 剪贴板限制

iOS 不允许应用在后台读取剪贴板。程序化读取另一个应用写入的剪贴板会让系统显示粘贴确认，因此：

- 默认关闭自动监听；
- 推荐使用首页的「同步剪贴板」按钮；
- 接收远程内容并写入剪贴板是允许的；
- 在其他 App 粘贴时，iOS 16+ 仍可能显示系统粘贴权限提示。

这是系统隐私机制，不是应用缺陷。

### 本地网络与 Bonjour

剪链使用原始 UDP 广播/组播和 TCP，不依赖 Bonjour 服务，因此不需要 `NSBonjourServices`。如果未来加入 mDNS/NSD，需要补充 Bonjour 服务类型。

## Android

### 构建

已经构建好的通用 APK 位于 `dist/ClipLink-1.0.0-Android-universal.apk`，支持 `arm64-v8a`、`armeabi-v7a`、`x86_64`，使用 debug keystore 签名（v2）。该 APK 已包含 `libirondash_engine_context_native.so` 和 `libsuper_native_extensions.so` 的三个 ABI 版本，并在雷电模拟器 9（Android 9 / x86_64）上实际启动验证。

Flutter 3.50 不再支持 32 位 x86 模拟器；模拟器或真机必须至少支持 x86_64、ARM64 或 ARMv7。如果模拟器是仅 32 位 x86，请改用 64 位实例或真机。

从源码构建需要：

- Android SDK，设置 `ANDROID_HOME` 或 `flutter config --android-sdk`
- JDK 17
- Android NDK `28.2.13676358`（`super_clipboard` 要求；可通过 SDK Manager 安装）
- 接受 Android SDK licenses
- Flutter 3.50.x / Gradle 9.5

```bash
flutter pub get

# super_native_extensions 0.9.x 的 CargoKit 仍使用 Gradle 9 已移除的
# Project.exec API。这个脚本只修补本地 pub cache 中两个插件的构建脚本。
python scripts/android_gradle9_compat.py

flutter build apk --release
# 或按 ABI 拆分
flutter build apk --release --split-per-abi
```

项目还包含：

- `android/compile-sdk.gradle`：让 `super_native_extensions` 等旧插件以 compileSdk 36 构建，避免现代 AndroidX AAR 元数据检查失败。
- `android/settings.gradle.kts` 与 `build.gradle.kts` 中优先使用阿里云 Maven 镜像；不存在时会自动回退到官方仓库，可按需删除。

这些是当前上游插件与 Flutter 3.50 / Gradle 9 的兼容处理，不影响应用运行逻辑。升级 `super_clipboard` / `super_native_extensions` 到修复后的正式版本后，可以移除兼容脚本和 compileSdk 覆盖。

### 已配置的权限和组件

`android/app/src/main/AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
```

以及剪贴板图片写入所需的 ContentProvider：

```xml
<provider
    android:name="com.superlist.super_native_extensions.DataProvider"
    android:authorities="${applicationId}.SuperClipboardDataProvider"
    android:exported="true"
    android:grantUriPermissions="true" />
```

`MainActivity.kt` 通过 `WifiManager.MulticastLock` 提升组播/广播发现成功率。

### 签名

模板的 release 构建目前使用 debug 签名，便于本地安装测试。正式发布前请在 `android/app/build.gradle.kts` 中配置自己的 keystore：

```kotlin
signingConfigs {
    create("release") {
        storeFile = file("path/to/keystore.jks")
        storePassword = System.getenv("KEYSTORE_PASSWORD")
        keyAlias = System.getenv("KEY_ALIAS")
        keyPassword = System.getenv("KEY_PASSWORD")
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

### 后台限制

Android 10（API 29）起，普通应用在后台不能读取剪贴板。剪链不会请求无障碍、悬浮窗或输入法权限来绕过这一限制。应用在前台时可以监听；从其他应用复制后回到剪链，请点一次「同步剪贴板」。

## 局域网发现排障

如果「附近设备」一直为空：

1. 确认两台设备在同一个 Wi-Fi/热点，且没有使用访客网络。
2. 关闭路由器的 AP 隔离 / 客户端隔离。
3. 确认路由网段相同（例如都在 `192.168.1.x`）。
4. 检查 Windows 防火墙是否为专用网络放行。
5. iOS 检查本地网络权限；Android 检查是否授予网络权限。
6. 一些企业网络会阻断 UDP 广播/组播；改用「配对码」，输入对方的 IP 和端口。
7. 如果对方设备有多个网络接口（VPN、虚拟网卡、有线 + 无线），在配对码弹窗里选择正确的地址。

配对码配对仍然使用局域网 TCP，因此两台设备必须能够互相访问。完全离线且没有共同局域网时没有传输通道。

## 剪贴板与历史

- 历史最多 40 条，图片总量上限约 120 MB。
- 文本上限 512 KB；图片上限 20 MB。
- 文本和图片分别可以在设置中关闭同步。
- 剪贴板历史只保存在本机；清空历史不会影响已配对设备。

## 打包 Windows 可分发文件

```powershell
$src = "build\windows\x64\runner\Release"
$dst = "dist\ClipLink-1.0.0-Windows-x64"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "$src\*" $dst -Recurse
Compress-Archive -Path "$dst\*" -DestinationPath "dist\ClipLink-1.0.0-Windows-x64.zip" -Force
```

压缩包必须包含 exe、DLL 和 `data/`。
