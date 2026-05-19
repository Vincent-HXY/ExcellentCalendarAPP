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

# ExcellentCalendarAPP

## 功能需求分析

#### (1) 日程

1. 创建一个日程，需要包含信息：时间（必选），日程标题（必选），日程详情，提醒时间（提前多久，可以设置，没有设置的话默认提前一小时），地点，重要性，是否响铃提醒，是否微信提醒，是否重复，属于哪个分类
2. 搜索日程，可以根据，时间，日程内容，地点，重要性，属于哪个分类进行搜索，
3. 可以为日程自定义创建分类，方便归类，同时设计好几个默认分类，比如购物清单，学习安排，工作计划
4. 可以通过图片识别，识别其他日程相关的文本，创建日程
5. 所有信息可以选择同步到服务器端，可自主选择
6. 如果没有提供必要的信息的，比如什么时候提醒，这里就要结合AI然后推到大概需要提醒的时间

#### (2) 日常习惯

1. 可以设置每日要坚持的习惯，比如每天阅读一小时
2. 可以通过微信提醒，AI提醒习惯
3. 可以通过图表显示自己习惯坚持情况

#### (3) 日历显示

1. 可以让显示一个日历，分别可以选择让他用年，月，周，最近三日的方式显示 
2. 可以点击日历的具体某一天，然后显示这一天所有的日程，没有则显示空
3. 同步显示假期，工作日，具体纪念日
4. 可以搜索/模糊搜索某一天的一个日程任务
5. 可以筛选显示日历上的内容，比如只显示重要日程，

---

#### (4) 微信

1. 可以通过微信实时推送最近的日程情况
2. 可以通过微信消息的发送自动识别并且创建对立日程，图片，消息，转发消息都可以。
3. 可以实现微信登陆
4. 可以实现多个设备的同一个账户的同步，前提是开启了日程的同步到服务器

---

#### (5) 今日任务

1. 作为主页显示，分为几个横栏显示
2. 习惯坚持（0/7），点击可以展开今日需要坚持的习惯任务
3. 日程安排（0/1），今日需要完成的日程任务
4. 准备任务，即可能最近需要提前准备的日程任务，比如某人的生日礼物，这就需要结合AI识别了，并给出分类建议

---

#### (6) 纪念日倒计时 

1. 可以自行设置纪念日，并且显示倒计时
2. （可以做？）在纪念日当天为使用者生成一条对应的生日祝福，结合AI生成祝福

#### (7) 搜索

1. 可以按照条件过滤搜索自己的相关日程
2. 按照时间区间，按照重要性，按照分类，按照内容，是否显示已完成，地点这些过滤条件，显示所有符合条件的日程

---

#### (8) 四象限

1. 重要不紧急，不重要但紧急，重要且紧急，不重要不紧急，按照四类显示**指定日期内**的所有日程任务

---

#### (9) 通知

1. 生成弹窗通知
2. 生成微信通知
3. 生成响铃通知

#### (10) 桌面小插件显示

1. 可以把显示在桌面上的那种小插件，可以切换：今日日程，日常习惯，最近3天
2. 这个是重点，后面可以再构思

#### (11) 个人信息界面

1. 名字，头像什么的，该有的都有点
2. 可以选择清楚某些时段的日志，节约空间，也可以选择导出

#### (12) 可选？投送

这是一个玩法

1. 可以选择日历上的某一天，投送一个消息，这条消息可以选择被其他人看到，也可以选择是写给自己的内容，当然这条消息不会显示在日程上面。可以选择往过去某一天投送，也可以往未来的某一天投送
2. 可以穿越到日期上面的任意一天，可以看到发生的发事情，未来或者过去

---



## 架构设计

```
Flutter UI
负责页面展示、按钮、输入、状态显示
        ↓ MethodChannel / EventChannel
Kotlin Service / Bridge
负责权限、通知、后台服务、系统回调、网络请求等Android系统能力
        ↓ JNI
C++ Core
负责核心算法、搜索、压缩、加密、日志存储、全文搜索、本地索引、数据库修改等等
		↓ 
SQLite
数据持久化存储
```

数据库的设计，数据库ER图

重复日程是日历系统最恶心的模块之一。

核心对象不是 UI，而是：

- Event：日程
- Habit：习惯
- Reminder：提醒
- Category：分类
- Recurrence：重复规则
- Notification：通知
- SearchIndex：搜索索引
- AIExtraction：AI 解析结果
- SyncOperation：同步操作
- UserData：用户数据
- DatedMessage：投送消息
- Anniversary：纪念日

### 判断一个逻辑应该放哪一层

你可以用这个方法判断。

问题 1：这个逻辑和页面显示强相关吗？

比如：

```
按钮是否可点击
表单错误文字
弹窗显示
loading 状态
```

放 UI / Controller。

问题 2：这个逻辑是用户业务流程吗？

比如：

```
创建日程时默认提醒
删除日程时取消通知
AI 导入后必须用户确认
完成习惯后更新今日统计
```

放 Application Layer。

问题 3：这个逻辑是核心领域规则吗？

比如：

```
重复日程如何展开
某个提醒时间是否合法
事件时间是否冲突
搜索排序规则
```

放 Domain / C++ Core。

问题 4：这个逻辑是 Android 系统能力吗？

比如：

```
通知权限
AlarmManager
桌面小组件
微信 SDK
分享 Intent
```

放 Kotlin。

问题 5：这个逻辑只是跨语言调用细节吗？

比如：

```
MethodChannel 名字
JSON 序列化
错误码转换
Dart 对象转换
```

放 Native Gateway



```
ExcellentCalendarAPP
│
├── Flutter Client 客户端表现层
│   ├── Presentation Layer
│   │   └── 负责页面展示、用户输入、按钮、弹窗、loading 状态
│   │
│   ├── Application Layer
│   │   └── 负责编排业务流程，例如创建日程、AI 导入、搜索、生成今日任务
│   │
│   ├── State Management
│   │   └── 负责页面状态管理，例如当前选中日期、搜索结果、表单状态
│   │
│   └── Dart Gateway Interfaces
│       └── 定义 Dart 层调用底层能力的接口契约
│
├── Boundary / Adapter Layer 边界适配层
│   ├── Dart MethodChannel Adapter
│   │   └── 将 Dart 请求转换为 MethodChannel 调用
│   │
│   ├── Kotlin MethodChannel Handler
│   │   └── 接收 Flutter 调用，并转发给 Android 服务或 C++ Core
│   │
│   ├── JNI Adapter
│   │   └── 负责 Kotlin 与 C++ 之间的参数转换和函数调用
│   │
│   ├── Storage Adapter
│   │   └── 负责 C++ 领域模型与 SQLite 数据结构之间的转换
│   │
│   └── Backend Sync Adapter
│       └── 负责本地同步模块与云端 API 之间的通信
│
├── Android Native Layer Android 系统能力层
│   ├── Notification Service
│   │   └── 负责系统通知、通知渠道、弹窗通知
│   │
│   ├── Alarm Scheduler
│   │   └── 负责定时提醒、系统闹钟、开机后恢复提醒
│   │
│   ├── Permission Manager
│   │   └── 负责通知权限、闹钟权限、文件权限等
│   │
│   ├── Share Receiver
│   │   └── 负责接收其他 App 分享来的文本或图片
│   │
│   ├── Widget Provider
│   │   └── 负责桌面小组件，例如今日日程、习惯、最近三天
│   │
│   └── WeChat Bridge
│       └── 负责微信登录、微信分享、微信推送相关能力
│
├── C++ Core Engine 核心引擎层
│   ├── Event Engine
│   │   └── 负责日程创建、修改、删除、查询、基础校验（防御性编程，这里的东西也是必须的）
│   │
│   ├── Reminder Engine
│   │   └── 负责提醒时间计算、默认提醒规则、生成提醒任务
│   │
│   ├── Recurrence Engine
│   │   └── 负责重复日程规则解析、展开、下一次发生时间计算
│   │
│   ├── Search Engine
│   │   └── 负责全文搜索、条件过滤、排序、分页
│   │
│   ├── Habit Engine
│   │   └── 负责习惯打卡、统计、连续天数、完成率
│   │
│   ├── Calendar Query Engine
│   │   └── 负责年/月/周/日/最近三日视图的数据聚合
│   │
│   ├── Quadrant Engine
│   │   └── 负责按照重要性和紧急性生成四象限数据
│   │
│   ├── AI Result Validator
│   │   └── 负责校验 AI 生成的候选日程是否可靠、合法
│   │
│   ├── Sync Log Engine
│   │   └── 负责记录本地操作日志，为后续云同步和冲突处理做准备
│   │
│   ├── Crypto / Export Engine
│   │   └── 负责本地数据加密、备份导出、备份导入
│   │
│   └── Storage Repository
│       └── 负责统一访问 SQLite，避免各个 Engine 直接乱写 SQL，所有的SQL语句都写在这里
│
├── Local Storage 本地存储层，所有的数据库文件，内容都写在这里
│   ├── SQLite
│   │   └── 负责结构化数据持久化
│   │
│   ├── SQLite FTS
│   │   └── 负责全文搜索索引
│   │
│   ├── Attachment Store
│   │   └── 负责保存图片、导入文件、附件
│   │
│   └── Operation Log
│       └── 负责保存本地增删改操作记录
│
├── AI Pipeline AI 输入管道
│   ├── OCR Adapter
│   │   └── 负责从图片中提取文字
│   │
│   ├── Text Extraction
│   │   └── 负责清洗文本、提取可能包含日程的信息
│   │
│   ├── Time Parser
│   │   └── 负责识别“明天上午”“下周五”等自然语言时间
│   │
│   ├── Category Recommender
│   │   └── 负责推荐分类，例如学习、工作、购物、纪念日
│   │
│   ├── Reminder Recommender
│   │   └── 负责推荐提前多久提醒
│   │
│   └── Candidate Event Builder
│       └── 负责生成候选日程，等待用户确认
│
└── Optional Cloud Backend 可选云端
    ├── Auth
    │   └── 负责账号登录和身份验证
    │
    ├── Sync API
    │   └── 负责多设备数据同步
    │
    ├── Backup API
    │   └── 负责云端备份和恢复
    │
    ├── AI API Proxy
    │   └── 负责转发 AI 请求，隐藏密钥和控制成本
    │
    └── WeChat Push Gateway
        └── 负责服务端微信提醒推送
```
