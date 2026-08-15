## 1. 真机调试

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

## 2. 可选：创建 Android 模拟器 AVD

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

## 3. 项目验证流程

### 3.1 基础环境检查

在仓库根目录执行：

```powershell
flutter doctor -v
```

期望：

- Flutter 绿色；
- Android toolchain 绿色；
- Connected device 至少有一个真机或模拟器；
- Chrome 红叉可忽略。

### 3.2 Smoke test：验证 Flutter / Kotlin / JNI / C++

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

### 3.3 确认 APK 包含 C++ so

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

## 4. 常见问题

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

## 5. 当前还未纳入本地环境验证的能力

以下能力属于后续功能开发阶段，不是当前最小 Android 本地链路必需：

- WeChat SDK / 微信登录 / 微信推送；
- 云同步后端；
- AI API Proxy；
- OCR；
- 服务器部署；
- 生产签名证书；
- 数据库正式 schema 和迁移工具。

这些能力接入时需要单独补充密钥、账