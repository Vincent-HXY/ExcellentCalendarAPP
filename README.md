# ExcellentCalendarAPP

## 开发环境基线

本节记录当前主开发机已经验证通过的开发环境。团队成员请优先保持版本一致；安装路径不强制一致。文中的 `A:\...` 是当前主开发机参考路径，如果安装到其他目录，需要把命令和环境变量中的路径替换成自己电脑上的真实路径。

不要随手执行 `flutter upgrade`、升级 Android Studio、升级 Android SDK/NDK/CMake。确实需要升级时，先在 `test_environment/flutter_native_smoke` 跑完整验证，再同步更新本节。

### 已验证通过的技术链路

```text
Flutter / Dart UI
  -> MethodChannel
  -> Kotlin MainActivity
  -> JNI
  -> C++ native library
  -> Android debug APK
  -> Android 真机运行
```

Smoke test 工程：

```text
test_environment/flutter_native_smoke
```

运行成功后，手机页面应显示：

```text
pong from C++ via Kotlin JNI
```

### 统一版本

| 工具 | 当前已验证版本 | 当前主开发机参考路径 / 说明 |
| --- | --- | --- |
| Windows | Windows 11 24H2, build 10.0.26100 | PowerShell 环境已验证 |
| Flutter | 3.41.9 stable | `A:\flutter\flutter` |
| Dart | 3.11.5 | Flutter 内置 |
| Flutter DevTools | 2.54.2 | Flutter 内置 |
| Android Studio | AI-253.32098.37.2534.15336583 | `A:\Android\AndroidStudio` |
| JDK | Android Studio JBR 21.0.10 | `A:\Android\AndroidStudio\jbr` |
| Android SDK | 36 / 36.1 | `A:\Android\sdk` |
| Android SDK Platform Tools | 37.0.0 | 包含 `adb`，当前 adb 为 1.0.41 / 37.0.0-14910828 |
| Android SDK Command-line Tools | latest 20.0 | 包含 `sdkmanager` / `avdmanager` |
| Android Build Tools | 35.0.0 / 36.0.0 / 36.1.0 / 37.0.0 | 当前主开发机已安装 |
| Android Emulator | 36.5.11 | 可选，用于 AVD |
| Android NDK | 28.2.13676358 | 团队默认基线；不要默认使用 `30.0.14904198 rc1` |
| CMake | 3.22.1 | 团队默认基线 |
| SQLite CLI | 3.50.6 | `A:\Android\sdk\platform-tools\sqlite3.exe` |
| Git | 2.53.0.2 | 当前主开发机已验证 |
| Visual Studio | Professional 2026 18.2.1 | 仅 Flutter Windows 桌面目标需要；Android 开发不是必需 |

### JDK 说明

本项目当前统一使用 Android Studio 自带 JBR：

```text
A:\Android\AndroidStudio\jbr
```

当前版本：

```text
openjdk version "21.0.10" 2026-01-20
```

不推荐把 `A:\Android\jdk-17` 作为本项目主 JDK。该 JDK 的版本输出是 `java version "17"`，在当前 Android 命令行工具中可能被误判为低于 Java 17。Java 17 本身不是问题；如果必须使用 Java 17，请使用版本输出为 `17.0.x` 的 JDK 17，并在团队内统一更新配置。

### 环境变量

当前主开发机参考配置：

```text
ANDROID_HOME=A:\Android\sdk
ANDROID_SDK_ROOT=A:\Android\sdk
FLUTTER_ROOT=A:\flutter\flutter
JAVA_HOME=A:\Android\AndroidStudio\jbr
```

Path 至少需要包含：

```text
A:\flutter\flutter\bin
A:\Android\sdk\platform-tools
A:\Android\sdk\cmdline-tools\latest\bin
A:\Android\sdk\emulator
A:\Android\sdk\cmake\3.22.1\bin
A:\Android\AndroidStudio\jbr\bin
```

如果团队成员安装到了其他目录，只需要替换成自己的实际路径，例如：

```powershell
flutter config --android-sdk "C:\Users\<用户名>\AppData\Local\Android\Sdk"
flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
```

### Flutter 配置

当前主开发机执行过：

```powershell
flutter config --android-sdk A:\Android\sdk
flutter config --jdk-dir A:\Android\AndroidStudio\jbr
flutter doctor --android-licenses
```

团队成员配置完成后执行：

```powershell
flutter doctor -v
```

期望：

- Flutter 为 `3.41.9 stable`；
- Android toolchain 为绿色；
- Android licenses 已接受；
- JDK 指向 Android Studio JBR 21.0.10；
- Connected device 至少能看到真机或模拟器；
- Chrome 红叉可以暂时忽略，因为本项目当前主目标是 Android。

### Android SDK 组件安装参考

如果缺少 SDK 组件，可执行：

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

然后接受 licenses：

```powershell
flutter doctor --android-licenses
```

### 真机验证

手机端开启开发者选项和 USB 调试后，电脑执行：

```powershell
adb devices
```

正常应看到：

```text
设备序列号    device
```

如果显示 `unauthorized`，需要在手机上点击允许 USB 调试。

### Smoke test 验证流程

```powershell
cd A:\calendar\ExcellentCalendarAPP\test_environment\flutter_native_smoke
flutter test
flutter analyze
flutter build apk --debug
flutter run
```

如果有多个设备：

```powershell
flutter devices
flutter run -d <device-id>
```

运行成功后，页面显示：

```text
pong from C++ via Kotlin JNI
```

可选检查 APK 是否包含 C++ so：

```powershell
A:\Android\AndroidStudio\jbr\bin\jar.exe tf build\app\outputs\flutter-apk\app-debug.apk | Select-String native_smoke
```

期望看到：

```text
lib/arm64-v8a/libnative_smoke.so
lib/armeabi-v7a/libnative_smoke.so
lib/x86_64/libnative_smoke.so
```

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


## 详细功能模块
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
