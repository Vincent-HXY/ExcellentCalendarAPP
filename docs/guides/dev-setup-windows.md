## 1.安装步骤

### 1.1 安装 Git

安装 Git for Windows 后验证：

```powershell
git --version
```

当前已验证版本：

```text
git version 2.53.0.windows.2
```

### 1.2 安装 Flutter

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

### 1.3 安装 Android Studio

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

### 1.4 安装 Android SDK 组件

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

## 2.环境变量

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

## 3.Flutter 指向 Android SDK 和 JDK

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



## 4.常见问题

### 4.1 `sdkmanager` 提示 SDK XML version 警告

可能出现：

```text
Warning: This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered.
```

如果 `flutter doctor`、`sdkmanager --list_installed`、`flutter build apk --debug` 都能正常执行，可以先忽略。它通常是 Android Studio 和 command-line tools 元数据版本不完全一致导致的警告。

### 4.2 `flutter doctor` 只有 Chrome 红叉

可以忽略。本项目当前不是 Flutter Web 项目。

### 4.3 `Lost connection to device`

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

### 4.4 Java 17 和 JBR 21 怎么选

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

## 5.当前还未纳入本地环境验证的能力

以下能力属于后续功能开发阶段，不是当前最小 Android 本地链路必需：

- WeChat SDK / 微信登录 / 微信推送；
- 云同步后端；
- AI API Proxy；
- OCR；
- 服务器部署；
- 生产签名证书；
- 数据库正式 schema 和迁移工具。

这些能力接入时需要单独补充密钥、账号、后端地址和安全配置。