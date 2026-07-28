# ExcellentCalendarAPP 团队环境配置说明

本文档记录本项目当前已经在 Windows 机器上跑通的开发环境。团队成员请尽量按这里的版本和路径配置，避免出现“某个人能跑，其他人跑不了”的问题。

当前已经验证通过的最小链路是：

```text
Flutter / Dart UI
  -> MethodChannel
  -> Kotlin MainActivity
  -> JNI
  -> C++ native library
  -> Android debug APK
  -> 真机运行
```

验证工程位于：

```text
test_environment/flutter_native_smoke
```

运行成功后，手机页面应显示：

```text
pong from C++ via Kotlin JNI
```

## 1. 推荐开发系统

当前已验证系统：

- Windows 11 24H2
- PowerShell
- Android 真机 USB 调试
- 可选：Android Emulator

Chrome 缺失只会影响 Flutter Web，不影响本项目 Android App 开发。

## 2. 团队统一版本

请优先使用下表版本。

| 工具 | 推荐版本 / 当前已验证版本 | 说明 |
| --- | --- | --- |
| Flutter | 3.41.9 stable | 当前项目已验证版本 |
| Dart | 3.11.5 | Flutter 内置 |
| DevTools | 2.54.2 | Flutter 内置 |
| Android Studio | AI-253.32098.37.2534.15336583 | 安装目录为 `A:\Android\AndroidStudio` |
| JDK | Android Studio JBR 21.0.10 | 路径为 `A:\Android\AndroidStudio\jbr` |
| Android SDK | 36 / 36.1 | 路径为 `A:\Android\sdk` |
| Android SDK Platform Tools | 37.0.0 | 包含 `adb` |
| Android SDK Command-line Tools | latest 20.0 | 包含 `sdkmanager` / `avdmanager` |
| Android Build Tools | 35.0.0 / 36.0.0 / 36.1.0 / 37.0.0 | 当前机器已安装 |
| Android Emulator | 36.5.11 | 用于 AVD |
| Android NDK | 28.2.13676358 | 团队推荐基线 |
| CMake | 3.22.1 | 团队推荐基线 |
| SQLite CLI | 3.50.6 | 位于 `A:\Android\sdk\platform-tools\sqlite3.exe` |
| Git | 2.53.0.2 | 当前机器已验证 |
| Visual Studio | Professional 2026 18.2.1 | 仅 Flutter Windows 桌面目标需要，Android 开发不是必需 |

注意：

- 不推荐把 `A:\Android\jdk-17` 作为本项目主 JDK。该 JDK 的版本输出是 `java version "17"`，在当前 Android 命令行工具中可能被误判为低于 Java 17。
- 本项目已验证使用 Android Studio 自带 JBR 21.0.10，可以正常通过 `flutter doctor`、`flutter build apk --debug` 和真机运行。
- 如果团队成员坚持使用 JDK 17，请使用版本输出为 `17.0.x` 的 JDK 17，并重新执行 `flutter config --jdk-dir <JDK路径>`。

## 3. 推荐目录结构

为了和当前已跑通环境保持一致，不一定建议统一放在 A 盘，可根据自身情况调整

```text
A:\flutter\flutter
A:\Android\AndroidStudio
A:\Android\sdk
```

如果某位成员必须安装到其他盘，也可以，但需要同步修改环境变量和 Flutter 配置。

## 4. 安装步骤

### 4.1 安装 Git

安装 Git for Windows 后验证：

```powershell
git --version
```

当前已验证版本：

```text
git version 2.53.0.windows.2
```

### 4.2 安装 Flutter

将 Flutter stable SDK 放到：

```text
A:\flutter\flutter
```

验证：

```powershell
A:\flutter\flutter\bin\flutter.bat --version
```

期望看到：

```text
Flutter 3.41.9
Dart 3.11.5
DevTools 2.54.2
```

### 4.3 安装 Android Studio

安装到：

```text
A:\Android\AndroidStudio
```

Android Studio 自带 JBR 路径应为：

```text
A:\Android\AndroidStudio\jbr
```

验证：

```powershell
A:\Android\AndroidStudio\jbr\bin\java.exe -version
```

期望看到类似：

```text
openjdk version "21.0.10"
```

### 4.4 安装 Android SDK 组件

SDK 根目录统一使用：

```text
A:\Android\sdk
```

在 Android Studio 的 SDK Manager 中安装这些组件，或者使用命令行：

```powershell
sdkmanager --sdk_root=A:\Android\sdk `
  "platform-tools" `
  "cmdline-tools;latest" `
  "platforms;android-36" `
  "platforms;android-36.1" `
  "build-tools;35.0.0" `
  "build-tools;36.1.0" `
  "cmake;3.22.1" `
  "ndk;28.2.13676358" `
  "emulator"
```

接受 Android licenses：

```powershell
flutter doctor --android-licenses
```

一路输入 `y` 接受即可。

## 5. 环境变量

推荐设置用户环境变量，按照自己安装时候的目录来，这里不能直接抄：

```text
ANDROID_HOME=A:\Android\sdk
ANDROID_SDK_ROOT=A:\Android\sdk
FLUTTER_ROOT=A:\flutter\flutter
JAVA_HOME=A:\Android\AndroidStudio\jbr
```

用户 Path 至少加入：

```text
A:\flutter\flutter\bin
A:\Android\sdk\platform-tools
A:\Android\sdk\cmdline-tools\latest\bin
A:\Android\sdk\emulator
A:\Android\sdk\cmake\3.22.1\bin
A:\Android\AndroidStudio\jbr\bin
```

PowerShell 设置示例：

```powershell
$sdk = 'A:\Android\sdk'
$flutter = 'A:\flutter\flutter'
$jbr = 'A:\Android\AndroidStudio\jbr'

[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdk, 'User')
[Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $flutter, 'User')
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jbr, 'User')

$pathsToAdd = @(
  "$flutter\bin",
  "$sdk\platform-tools",
  "$sdk\cmdline-tools\latest\bin",
  "$sdk\emulator",
  "$sdk\cmake\3.22.1\bin",
  "$jbr\bin"
)

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($userPath) {
  $parts = $userPath -split ';' | Where-Object { $_ }
}

foreach ($path in $pathsToAdd) {
  if (($parts | ForEach-Object { $_.TrimEnd('\') }) -notcontains $path.TrimEnd('\')) {
    $parts += $path
  }
}

[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
```

设置完成后，关闭并重新打开 PowerShell。

验证：

```powershell
java -version
flutter --version
adb version
sdkmanager --list_installed --sdk_root=A:\Android\sdk
```

`java -version` 推荐显示：

```text
openjdk version "21.0.10"
```

## 6. Flutter 指向 Android SDK 和 JDK

每台机器都执行一次：

```powershell
flutter config --android-sdk A:\Android\sdk
flutter config --jdk-dir A:\Android\AndroidStudio\jbr
```

然后验证：

```powershell
flutter doctor -v
```

Android toolchain 应为绿色：

```text
[√] Android toolchain - develop for Android devices
```

如果只有 Chrome 是红叉，可以先忽略；本项目当前主目标是 Android。

## 7. 真机调试

手机端：

1. 打开设置。
2. 进入关于手机。
3. 连续点击版本号 / Build number 7 次，开启开发者选项。
4. 回到设置，进入开发者选项。
5. 开启 USB 调试。
6. 用支持数据传输的 USB 线连接电脑。
7. 手机上弹出允许 USB 调试时，点击允许。

电脑端验证：

```powershell
adb devices
```

正常应看到：

```text
设备序列号    device
```

如果显示 `unauthorized`，看手机屏幕并点击允许。

如果没有设备：

- 换 USB 线；
- 换 USB 口；
- 确认手机 USB 模式不是仅充电；
- 安装手机厂商 USB 驱动；
- 在开发者选项中开启 USB 安装或类似权限。

## 8. 可选：创建 Android 模拟器 AVD

如果没有真机，可以创建 AVD。

先查看可用 system image：

```powershell
sdkmanager --list | Select-String "system-images;android-36"
```

推荐安装 x86_64 Google APIs 镜像：

```powershell
sdkmanager --sdk_root=A:\Android\sdk "system-images;android-36.1;google_apis;x86_64"
```

创建 AVD：

```powershell
avdmanager create avd -n ExcellentCalendar_API36 -k "system-images;android-36.1;google_apis;x86_64" -d pixel_7
```

如果 `pixel_7` 不存在，查看可用设备模板：

```powershell
avdmanager list device
```

启动模拟器：

```powershell
emulator -avd ExcellentCalendar_API36
```

验证：

```powershell
flutter devices
```

## 9. 项目验证流程

### 9.1 基础环境检查

在仓库根目录执行：

```powershell
flutter doctor -v
```

期望：

- Flutter 绿色；
- Android toolchain 绿色；
- Connected device 至少有一个真机或模拟器；
- Chrome 红叉可忽略。

### 9.2 Smoke test：验证 Flutter / Kotlin / JNI / C++

进入测试工程：

```powershell
cd A:\calendar\ExcellentCalendarAPP\test_environment\flutter_native_smoke
```

执行测试：

```powershell
flutter test
```

执行静态分析：

```powershell
flutter analyze
```

构建 Android debug APK：

```powershell
flutter build apk --debug
```

真机或模拟器运行：

```powershell
flutter run
```

如果有多个设备，指定设备：

```powershell
flutter devices
flutter run -d <device-id>
```

页面显示以下内容即为通过：

```text
pong from C++ via Kotlin JNI
```

### 9.3 确认 APK 包含 C++ so

可选验证：

```powershell
A:\Android\AndroidStudio\jbr\bin\jar.exe tf build\app\outputs\flutter-apk\app-debug.apk | Select-String native_smoke
```

期望看到：

```text
lib/arm64-v8a/libnative_smoke.so
lib/armeabi-v7a/libnative_smoke.so
lib/x86_64/libnative_smoke.so
```

## 10. 常见问题

### 10.1 `sdkmanager` 提示 SDK XML version 警告

可能出现：

```text
Warning: This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered.
```

如果 `flutter doctor`、`sdkmanager --list_installed`、`flutter build apk --debug` 都能正常执行，可以先忽略。它通常是 Android Studio 和 command-line tools 元数据版本不完全一致导致的警告。

### 10.2 `flutter doctor` 只有 Chrome 红叉

可以忽略。本项目当前不是 Flutter Web 项目。

### 10.3 `Lost connection to device`

如果 APK 已安装并启动，但之后出现：

```text
Lost connection to device.
```

通常是 USB 调试连接中断、手机锁屏、App 被系统切到后台或厂商系统限制后台调试。优先检查：

- 数据线是否稳定；
- 手机是否保持解锁；
- 是否允许 USB 调试；
- 是否开启了 USB 安装；
- 是否被省电策略限制。

### 10.4 Java 17 和 JBR 21 怎么选

本项目团队基线使用：

```text
A:\Android\AndroidStudio\jbr
```

也就是 Android Studio 自带 OpenJDK 21.0.10。

原因：

- 当前机器已经用它通过 Flutter、Gradle、Kotlin、NDK、C++ 构建；
- Android Studio 自带 JBR 和 Android 工具链兼容性最好；
- 原先 `A:\Android\jdk-17` 的版本字符串可能被 `sdkmanager` 误判。

如果后续必须切回 Java 17，请使用规范的 JDK 17.0.x，并同步通知团队修改 README 和 Flutter 配置。

## 11. 当前还未纳入本地环境验证的能力

以下能力属于后续功能开发阶段，不是当前最小 Android 本地链路必需：

- WeChat SDK / 微信登录 / 微信推送；
- 云同步后端；
- AI API Proxy；
- OCR；
- 服务器部署；
- 生产签名证书；
- 数据库正式 schema 和迁移工具。

这些能力接入时需要单独补充密钥、账号、后端地址和安全配置。