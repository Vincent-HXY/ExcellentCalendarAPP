# ExcellentCalendarAPP

## 开发环境基线

本节记录当前主开发机已经验证通过的开发环境。团队成员请优先保持版本一致；安装路径不强制一致。文中的 `A:\...` 是当前主开发机参考路径，如果安装到其他目录，需要把命令和环境变量中的路径替换成自己电脑上的真实路径。

不要随手执行 `flutter upgrade`、升级 Android Studio、升级 Android SDK/NDK/CMake。确实需要升级时，先在 `test_environment/flutter_native_smoke` 跑完整验证，再同步更新本节。

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

### C++ Core 构建与测试

从仓库根目录执行以下命令。`excellent_calendar_check` 会先构建当前源码对应的测试程序，再运行 CTest；编译或测试任一步失败都会返回失败。

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不要把单独执行 `ctest --test-dir cpp_core/build-ninja` 作为完整验收，因为 CTest 不负责编译，构建失败时可能运行目录中遗留的旧测试程序。

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



### 核心对象包括：

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

---



### Contract Layer：跨语言数据协议层

#### 1. Contract Layer 的定位

本项目采用：

```text
Flutter / Dart
    ↓ MethodChannel / EventChannel
Kotlin Service / Bridge
    ↓ JNI
C++ Core Engine
    ↓
SQLite
```

由于项目存在 Dart、Kotlin、C++、SQLite、未来云端 Backend 等多个数据边界，因此需要在项目顶层建立统一的 `contracts/` 目录，用于描述跨层调用时的数据格式、方法入口、错误码和版本约定。

`contracts/` 不属于某一种具体语言，而是整个项目的跨语言数据协议源头。

它的作用不是替代 Dart DTO、Kotlin data class、C++ struct 或数据库 schema，而是规定这些语言本土化实现必须共同遵守的协议。
如果说，如果涉及到了跨语言的调用，也必须要在contracts里面有过声明，不可以直接调用。

也就是说：

```text
contracts/                 负责定义统一协议
flutter_client/.../dto      负责 Dart 侧本土化实现
android/.../contract        负责 Kotlin 侧本土化实现
cpp_core/.../boundary       负责 C++ 边界层本土化实现
SQLite schema               负责最终持久化结构
```

Contract Layer 的核心目标是：

```text
1. 统一跨语言字段命名
2. 统一请求和响应格式
3. 统一错误返回结构
4. 统一枚举值
5. 避免 Map<String, dynamic> / JSONObject 在各层失控扩散
6. 降低 Dart、Kotlin、C++、SQLite 之间字段不一致导致的隐蔽 bug
7. 为未来云同步、AI 导入、数据导出、Widget、微信推送等模块预留稳定协议
```

---

#### 2. Contract Layer 与 Data Model 的关系

本项目同时存在两类文档：

```text
DATA_MODEL.md
contracts/
```

二者职责不同。

#### DATA_MODEL.md

`DATA_MODEL.md` 描述的是核心业务对象的领域模型，例如：

```text
Event
Habit
HabitCheckIn
Reminder
Notification
Category
Recurrence
SearchIndex
AIExtraction
SyncOperation
UserData
DatedMessage
Anniversary
```

它回答的问题是：

```text
业务世界里有哪些对象？
每个对象的职责是什么？
对象之间是什么关系？
哪些字段属于核心领域概念？
哪些模型当前阶段必须实现？
哪些模型是未来预留？
```

例如：

```text
Event 是日程本体
Reminder 是未来要触发的提醒任务
Notification 是提醒触发后的投递结果日志
HabitCheckIn 是习惯完成记录
Recurrence 是重复规则
```

#### contracts/

`contracts/` 描述的是跨层传输协议。

它回答的问题是：

```text
Dart 调用 Kotlin/C++ 时传什么？
Kotlin 返回给 Dart 什么？
C++ Core 边界层如何把领域对象转成可传输数据？
失败时错误结构是什么？
MethodChannel 方法名是什么？
每个方法对应哪个 request schema 和 response schema？
```

因此：

```text
Data Model = 业务对象模型
Contract = 跨语言传输协议
```

二者不能混用。

例如，`Event` 是业务领域对象；但是 `CreateEventRequest`、`EventResponse`、`SearchEventRequest`、`NativeResult<EventResponse>` 是跨层传输对象。

------

#### 3. 顶层目录结构

项目顶层新增：

```text
ExcellentCalendarAPP/
├── contracts/
│   ├── README.md
│   ├── method_channels.yaml
│   ├── error_codes.yaml
│   ├── enums.yaml
│   │
│   ├── common/
│   │   ├── native_result.schema.json
│   │   ├── native_error.schema.json
│   │   ├── pagination_request.schema.json
│   │   └── pagination_response.schema.json
│   │
│   ├── event/
│   │   ├── create_event_request.schema.json
│   │   ├── update_event_request.schema.json
│   │   ├── delete_event_request.schema.json
│   │   ├── event_response.schema.json
│   │   ├── event_list_response.schema.json
│   │   └── search_event_request.schema.json
│   │
│   ├── recurrence/
│   │   ├── recurrence_rule.schema.json
│   │   └── recurrence_response.schema.json
│   │
│   ├── reminder/
│   │   ├── create_reminder_request.schema.json
│   │   ├── reminder_response.schema.json
│   │   └── reminder_list_response.schema.json
│   │
│   ├── notification/
│   │   ├── notification_response.schema.json
│   │   └── notification_list_response.schema.json
│   │
│   ├── habit/
│   │   ├── create_habit_request.schema.json
│   │   ├── habit_response.schema.json
│   │   ├── habit_check_in_request.schema.json
│   │   └── habit_check_in_response.schema.json
│   │
│   ├── category/
│   │   ├── create_category_request.schema.json
│   │   └── category_response.schema.json
│   │
│   ├── ai/
│   │   ├── ai_extraction_request.schema.json
│   │   ├── ai_extraction_response.schema.json
│   │   └── ai_candidate_event.schema.json
│   │
│   ├── sync/
│   │   ├── sync_operation.schema.json
│   │   └── sync_result.schema.json
│   │
│   └── user/
│       ├── user_data_response.schema.json
│       └── update_user_settings_request.schema.json
```

当前阶段可以先实现 `common/`、`event/`、`reminder/`、`recurrence/`、`habit/`、`category/` 中的核心协议。`ai/`、`sync/`、`user/` 可以先保留文档级设计，不需要立即实现完整逻辑。

------

#### 4. 各文件职责说明

##### 4.1 `contracts/README.md`

负责说明 Contract Layer 的总体原则，包括：

```text
1. contracts/ 是跨语言数据协议源头
2. 所有跨 Dart / Kotlin / C++ / Backend 的数据结构都应在此声明
3. Contract 不直接等于数据库表
4. Contract 不直接等于 C++ Domain Model
5. Contract 不直接等于 Flutter ViewModel
6. 所有 request / response 必须有明确版本和字段说明
7. 所有跨层错误必须使用统一错误码
```

------

##### 4.2 `method_channels.yaml`

负责描述 MethodChannel 的方法入口。

它规定：

```text
1. MethodChannel 名称
2. 方法名
3. 请求 schema
4. 成功时 data 对应的 response schema
5. 失败时 error 对应的 native_error schema
6. 调用归属模块
7. 是否需要异步事件流
```

示例：

```yaml
channel: excellent_calendar/native
version: 1

methods:
  event.create:
    module: event
    request: event/create_event_request.schema.json
    result:
      envelope: common/native_result.schema.json
      data: event/event_response.schema.json

  event.update:
    module: event
    request: event/update_event_request.schema.json
    result:
      envelope: common/native_result.schema.json
      data: event/event_response.schema.json

  event.search:
    module: event
    request: event/search_event_request.schema.json
    result:
      envelope: common/native_result.schema.json
      data: event/event_list_response.schema.json

  reminder.create:
    module: reminder
    request: reminder/create_reminder_request.schema.json
    result:
      envelope: common/native_result.schema.json
      data: reminder/reminder_response.schema.json

  habit.check_in:
    module: habit
    request: habit/habit_check_in_request.schema.json
    result:
      envelope: common/native_result.schema.json
      data: habit/habit_check_in_response.schema.json
```

方法命名采用：

```text
module.action
```

例如：

```text
event.create
event.update
event.delete
event.search
habit.create
habit.check_in
reminder.create
reminder.cancel
notification.list
```

禁止在不同语言中使用不同方法名。

------

##### 4.3 `error_codes.yaml`

负责统一错误码。

所有跨层调用失败时，都必须使用统一错误码，而不是各语言自行发明错误字符串。

示例：

```yaml
version: 1

errors:
  NATIVE_INTERNAL_ERROR:
    module: common
    message: "Native internal error"
    retryable: false

  CONTRACT_VALIDATION_FAILED:
    module: common
    message: "Request does not match contract schema"
    retryable: false

  EVENT_TITLE_EMPTY:
    module: event
    message: "Event title cannot be empty"
    retryable: false

  EVENT_TIME_INVALID:
    module: event
    message: "Event start time must be earlier than end time"
    retryable: false

  EVENT_NOT_FOUND:
    module: event
    message: "Event not found"
    retryable: false

  RECURRENCE_RULE_INVALID:
    module: recurrence
    message: "Recurrence rule is invalid"
    retryable: false

  REMINDER_TIME_INVALID:
    module: reminder
    message: "Reminder time is invalid"
    retryable: false

  REMINDER_TARGET_NOT_FOUND:
    module: reminder
    message: "Reminder target does not exist"
    retryable: false

  HABIT_CHECK_IN_DUPLICATED:
    module: habit
    message: "Habit check-in already exists for this date"
    retryable: false

  PERMISSION_DENIED:
    module: android
    message: "Required Android permission is denied"
    retryable: true

  ALARM_SCHEDULE_FAILED:
    module: android
    message: "Failed to schedule alarm"
    retryable: true
```

错误码命名规则：

```text
MODULE_REASON
```

例如：

```text
EVENT_TIME_INVALID
REMINDER_TARGET_NOT_FOUND
CONTRACT_VALIDATION_FAILED
```

------

##### 4.4 `enums.yaml`

负责统一枚举值。

枚举值必须跨 Dart、Kotlin、C++、SQLite、Backend 保持一致。

示例：

```yaml
Importance:
  values:
    - unimportant_noturgent
    - important_noturgent
    - unimportant_urgent
    - important_urgent

ReminderMethod:
  values:
    - ring
    - popup
    - wechat

RecurrenceFrequency:
  values:
    - daily
    - weekly
    - monthly
    - yearly
    - custom

ReminderStatus:
  values:
    - pending
    - scheduled
    - sent
    - failed
    - cancelled

NotificationStatus:
  values:
    - pending
    - sent
    - failed
    - cancelled

HabitCheckInStatus:
  values:
    - done
    - partial
    - missed
    - skipped

SyncOperationType:
  values:
    - create
    - update
    - delete
    - restore

DataSource:
  values:
    - manual
    - ai_extraction
    - sync
    - import
    - wechat
```

枚举值建议在传输层使用字符串，而不是数字。

原因：

```text
1. 可读性更强
2. 调试方便
3. 跨语言更安全
4. 后续插入新枚举值时不容易破坏旧数据
```

------

#### 5. 通用返回包装

所有跨层函数调用统一返回：

```text
NativeResult<T>
```

其中：

```text
NativeResult = 通用返回外壳
T = 具体业务数据
NativeError = 统一错误结构
```

成功时：

```json
{
  "ok": true,
  "data": {
    "id": "evt_001",
    "title": "算法课作业"
  },
  "error": null
}
```

失败时：

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "EVENT_TIME_INVALID",
    "message": "Event start time must be earlier than end time",
    "details": {
      "field": "start_at"
    }
  }
}
```

##### 5.1 `native_result.schema.json`

负责规定所有跨层调用的统一返回外壳：

```json
{
  "type": "object",
  "required": ["ok", "data", "error"],
  "properties": {
    "ok": {
      "type": "boolean"
    },
    "data": {
      "type": ["object", "array", "string", "number", "boolean", "null"]
    },
    "error": {
      "oneOf": [
        { "$ref": "./native_error.schema.json" },
        { "type": "null" }
      ]
    },
    "contract_version": {
      "type": "integer"
    },
    "request_id": {
      "type": ["string", "null"]
    }
  }
}
```

约束：

```text
1. ok = true 时，error 必须为 null
2. ok = false 时，data 必须为 null
3. ok = false 时，error 必须存在
4. data 的具体结构由 method_channels.yaml 中声明的业务 response schema 决定
```

##### 5.2 `native_error.schema.json`

负责规定失败时的错误结构：

```json
{
  "type": "object",
  "required": ["code", "message"],
  "properties": {
    "code": {
      "type": "string"
    },
    "message": {
      "type": "string"
    },
    "details": {
      "type": ["object", "null"]
    },
    "retryable": {
      "type": "boolean"
    }
  }
}
```

其中：

```text
code       必须来自 error_codes.yaml
message    是面向开发调试的默认错误信息
details    保存字段级错误、底层异常摘要、权限状态等补充信息
retryable  表示该错误是否适合重试
```

------

#### 6. 业务 Response 与 NativeResult 的关系

`native_result.schema.json` 和业务 response schema 不是重复关系，而是嵌套关系。

例如：

```text
event.create 的完整返回
= NativeResult<EventResponse>
```

其中：

```text
native_result.schema.json 规定外层：
- ok
- data
- error
- contract_version
- request_id

event_response.schema.json 规定 data 里面的业务内容：
- id
- title
- content
- start_at
- end_at
- is_all_day
- category_id
- recurrence_id
- importance
- timezone
- source
- created_at
- updated_at
- deleted_at
```

即：

```json
{
  "ok": true,
  "data": {
    "id": "evt_001",
    "title": "算法课作业",
    "content": "完成第三章",
    "start_at": "2026-06-06T10:00:00Z",
    "end_at": "2026-06-06T11:00:00Z",
    "is_all_day": false,
    "has_recurrence": false,
    "recurrence_id": null,
    "category_id": "cat_study",
    "importance": "important_noturgent",
    "location": "library",
    "timezone": "Asia/Singapore",
    "source": "manual",
    "created_at": "2026-06-06T09:00:00Z",
    "updated_at": "2026-06-06T09:00:00Z",
    "deleted_at": null
  },
  "error": null,
  "contract_version": 1,
  "request_id": "req_001"
}
```

因此：

```text
native_result.schema.json = 通用快递箱
event_response.schema.json = 箱子里的日程数据
native_error.schema.json = 出错时箱子里的故障报告
```

------

#### 7. 时间与字段命名约定

##### 7.1 字段命名

Contract 层统一使用：

```text
snake_case
```

例如：

```text
created_at
updated_at
deleted_at
start_at
end_at
is_all_day
category_id
recurrence_id
target_type
target_id
remind_at
advance_minutes
```

各语言内部可以本土化：

```text
Dart: startAt / createdAt
Kotlin: startAt / createdAt
C++: start_at 或 startAt
SQLite: start_at
```

**但跨层传输时必须使用 contract 中定义的字段名。**

------

##### 7.2 时间格式

Contract 层时间字段统一使用 ISO 8601 UTC 字符串。

例如：

```json
{
  "start_at": "2026-06-06T10:00:00Z"
}
```

日期字段使用本地日期字符串：

```json
{
  "check_date": "2026-06-06"
}
```

适用场景：

```text
datetime: start_at, end_at, remind_at, created_at, updated_at, sent_at
date: HabitCheckIn.check_date, Anniversary.date
```

规则：

```text
1. datetime 表示精确时间点，内部统一 UTC
2. date 表示用户本地日期，不携带具体时分秒
3. 展示时由 Flutter 根据用户 timezone 转换
4. 业务计算时由 C++ Core 根据 timezone 处理
```

------

#### 8. Event Contract 设计

##### 8.1 `create_event_request.schema.json`

创建日程请求只表达用户或 AI 创建日程所需的输入，不包含系统生成字段。

不应包含：

```text
id
created_at
updated_at
deleted_at
```

因为这些字段由 C++ Core / Storage Repository 生成。

推荐字段：

```json
{
  "type": "object",
  "required": ["title", "start_at", "end_at", "is_all_day", "source"],
  "properties": {
    "title": {
      "type": "string",
      "minLength": 1
    },
    "content": {
      "type": ["string", "null"]
    },
    "start_at": {
      "type": "string",
      "format": "date-time"
    },
    "end_at": {
      "type": "string",
      "format": "date-time"
    },
    "is_all_day": {
      "type": "boolean"
    },
    "category_id": {
      "type": ["string", "null"]
    },
    "importance": {
      "type": ["string", "null"],
      "enum": [
        "unimportant_noturgent",
        "important_noturgent",
        "unimportant_urgent",
        "important_urgent",
        null
      ]
    },
    "location": {
      "type": ["string", "null"]
    },
    "timezone": {
      "type": ["string", "null"]
    },
    "source": {
      "type": "string"
    },
    "recurrence": {
      "oneOf": [
        { "$ref": "../recurrence/recurrence_rule.schema.json" },
        { "type": "null" }
      ]
    },
    "reminders": {
      "type": "array",
      "items": {
        "$ref": "../reminder/create_reminder_request.schema.json"
      }
    }
  }
}
```

说明：

```text
1. create_event_request 可以携带 recurrence，但最终 Recurrence 应作为独立实体保存。
2. create_event_request 可以携带 reminders，但最终 Reminder 应作为独立实体保存。
3. Event 本体不直接保存提醒时间和提醒方式。
4. 如果用户设置多个提醒时间，则由 Reminder Engine 生成多条 Reminder。
```

------

##### 8.2 `event_response.schema.json`

创建、查询、更新日程成功后，返回 Event 的可传输表示。

推荐字段：

```json
{
  "type": "object",
  "required": [
    "id",
    "title",
    "start_at",
    "end_at",
    "is_all_day",
    "has_recurrence",
    "source",
    "created_at",
    "updated_at"
  ],
  "properties": {
    "id": {
      "type": "string"
    },
    "title": {
      "type": "string"
    },
    "content": {
      "type": ["string", "null"]
    },
    "start_at": {
      "type": "string",
      "format": "date-time"
    },
    "end_at": {
      "type": "string",
      "format": "date-time"
    },
    "is_all_day": {
      "type": "boolean"
    },
    "has_recurrence": {
      "type": "boolean"
    },
    "recurrence_id": {
      "type": ["string", "null"]
    },
    "category_id": {
      "type": ["string", "null"]
    },
    "importance": {
      "type": ["string", "null"]
    },
    "location": {
      "type": ["string", "null"]
    },
    "timezone": {
      "type": ["string", "null"]
    },
    "source": {
      "type": "string"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "updated_at": {
      "type": "string",
      "format": "date-time"
    },
    "deleted_at": {
      "type": ["string", "null"],
      "format": "date-time"
    }
  }
}
```

注意：

```text
event_response 不直接嵌入 reminders。
如果页面需要同时展示日程和提醒，应使用组合型 response，例如 event_detail_response。
```

------

##### 8.3 `event_detail_response.schema.json`

用于详情页，一次性返回 Event、Recurrence、Reminders、Category 等聚合数据。

推荐结构：

```json
{
  "type": "object",
  "required": ["event"],
  "properties": {
    "event": {
      "$ref": "./event_response.schema.json"
    },
    "recurrence": {
      "oneOf": [
        { "$ref": "../recurrence/recurrence_response.schema.json" },
        { "type": "null" }
      ]
    },
    "reminders": {
      "type": "array",
      "items": {
        "$ref": "../reminder/reminder_response.schema.json"
      }
    },
    "category": {
      "oneOf": [
        { "$ref": "../category/category_response.schema.json" },
        { "type": "null" }
      ]
    }
  }
}
```

这样可以避免把所有相关数据都塞进 `event_response`，保持职责清晰。

------

#### 9. Reminder 与 Notification Contract 设计

本项目明确区分：

```text
Reminder      未来要执行的提醒任务
Notification  提醒触发后的投递结果日志
```

因此二者需要独立 contract。

##### 9.1 `reminder_response.schema.json`

推荐字段：

```text
id
target_type
target_id
remind_at
methods
advance_minutes
message
is_enabled
status
scheduled_at
last_triggered_at
failure_reason
created_at
updated_at
deleted_at
```

Reminder 适合被 Reminder Engine / Alarm Scheduler 扫描和调度。

##### 9.2 `notification_response.schema.json`

推荐字段：

```text
id
reminder_id
target_type
target_id
method
title
body
planned_at
sent_at
status
failure_reason
created_at
updated_at
```

Notification 只记录投递结果，不参与未来提醒扫描。

------

#### 10. Habit 与 HabitCheckIn Contract 设计

`Habit` 只表达习惯定义，不能承担打卡记录职责。

因此：

```text
habit_response.schema.json
```

负责描述习惯定义：

```text
id
title
description
category_id
recurrence_id
target_count
unit
start_date
end_date
is_active
created_at
updated_at
deleted_at
```

而：

```text
habit_check_in_response.schema.json
```

负责描述某一天的完成情况：

```text
id
habit_id
check_date
status
completed_count
target_count_snapshot
unit_snapshot
completed_at
note
source
created_at
updated_at
deleted_at
```

约束：

```text
1. Habit 不保存连续天数、总完成天数、完成率等派生统计。
2. 连续天数、完成率优先从 HabitCheckIn 计算。
3. 同一个 habit_id + check_date 默认只保留一条记录。
4. 如果未来需要一天多次明细，再新增 HabitCheckInEntry。
```

------

#### 11. Recurrence Contract 设计

`recurrence_rule.schema.json` 用于描述重复规则。

推荐字段：

```text
frequency
interval
days_of_week
day_of_month
month_of_year
start_at
end_at
count
timezone
```

当前阶段优先支持结构化重复规则：

```text
daily
weekly
monthly
yearly
custom
```

未来如果需要和 Google Calendar、Outlook、系统日历互通，可以新增：

```text
rrule
```

用于保存 iCalendar RRULE 标准字符串。

例如：

```text
FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR
```

但当前阶段不强制实现 RRULE。

------

#### 12. Contract 与各语言实现的对应关系

##### 12.1 Dart 侧

Dart 侧在 `flutter_client` 中新增：

```text
flutter_client/lib/native_contract/
├── common/
│   ├── native_result_dto.dart
│   └── native_error_dto.dart
├── event/
│   ├── create_event_request_dto.dart
│   ├── event_response_dto.dart
│   └── event_detail_response_dto.dart
├── reminder/
│   ├── reminder_response_dto.dart
│   └── create_reminder_request_dto.dart
├── recurrence/
│   └── recurrence_rule_dto.dart
└── habit/
    ├── habit_response_dto.dart
    └── habit_check_in_response_dto.dart
```

Dart DTO 负责：

```text
1. 从 Flutter Application Layer 接收类型安全对象
2. 转成符合 contracts/ 的 Map<String, dynamic>
3. 解析 MethodChannel 返回的 Map
4. 将 native error 转换为 Dart exception
```

Dart UI 不应该直接拼 MethodChannel Map。

------

##### 12.2 Kotlin 侧

Kotlin 侧新增：

```text
android/app/src/main/kotlin/.../bridge/contract/
├── NativeResult.kt
├── NativeError.kt
├── EventContract.kt
├── ReminderContract.kt
├── RecurrenceContract.kt
└── HabitContract.kt
```

Kotlin Contract 负责：

```text
1. 接收 Flutter MethodChannel 参数
2. 做轻量参数转换
3. 转发给 Android Service 或 JNI
4. 将 C++ 返回结果包装回 Flutter
5. 不承载核心业务规则
```

Kotlin 不应该擅自改字段命名，也不应该把跨层协议从 `snake_case` 改成 `camelCase` 后再传给 C++。

------

##### 12.3 C++ 侧

C++ Core 中应区分：

```text
C++ Domain Model
C++ Boundary Contract
```

例如：

```text
cpp_core/
├── include/excellent_calendar/domain/
│   ├── event.hpp
│   ├── reminder.hpp
│   └── recurrence.hpp
│
├── include/excellent_calendar/boundary/contract/
│   ├── create_event_request.hpp
│   ├── event_response.hpp
│   ├── native_result.hpp
│   └── native_error.hpp
│
└── src/boundary/contract/
    ├── create_event_request_json.cpp
    ├── event_response_json.cpp
    └── native_result_json.cpp
```

C++ Domain Model 负责表达核心业务规则。

C++ Boundary Contract 负责和 Dart/Kotlin 传输数据。

禁止 C++ Core 直接把 Domain Model 暴露给 Dart/Kotlin。

正确流程：

```text
JSON request
    ↓
C++ Boundary Request
    ↓
C++ Domain Model / Command
    ↓
C++ Engine 执行业务
    ↓
C++ Domain Result
    ↓
C++ Boundary Response
    ↓
JSON result
```

------

#### 13. 创建日程的完整跨层数据流

以创建日程为例：

```text
EventFormPage
    ↓
CreateEventUseCase
    ↓
CreateEventRequestDto
    ↓
EventNativeGateway
    ↓ MethodChannel: event.create
Kotlin MethodChannel Handler
    ↓
Kotlin EventContract
    ↓ JNI
C++ Boundary CreateEventRequest
    ↓
Event Engine
    ↓
Reminder Engine
    ↓
Recurrence Engine
    ↓
Storage Repository
    ↓
C++ Boundary EventResponse
    ↓
NativeResult<EventResponse>
    ↓ JNI
Kotlin NativeResult
    ↓ MethodChannel
Dart NativeResultDto<EventResponseDto>
    ↓
Application Layer / UI
```

其中：

```text
CreateEventRequestDto
```

只负责创建日程所需输入。

```text
EventResponseDto
```

只负责创建成功后的日程数据。

```text
NativeResultDto<EventResponseDto>
```

负责跨层调用成功或失败的通用外壳。

```text
Reminder Engine
```

负责根据用户选择或默认规则生成 Reminder。

```text
Notification
```

不会在创建日程时直接产生，只有 Reminder 被触发并完成投递后才生成 Notification 记录。

------

#### 14. Contract 优先级

根据当前本地优先阶段，Contract 实现优先级如下。

##### 第一优先级：必须尽快明确

```text
common/native_result.schema.json
common/native_error.schema.json
method_channels.yaml
error_codes.yaml
enums.yaml

event/create_event_request.schema.json
event/update_event_request.schema.json
event/event_response.schema.json
event/event_detail_response.schema.json
event/search_event_request.schema.json
event/event_list_response.schema.json

recurrence/recurrence_rule.schema.json
reminder/create_reminder_request.schema.json
reminder/reminder_response.schema.json
category/category_response.schema.json
```

原因：

```text
这些协议直接影响日程创建、提醒生成、重复规则、分类展示、搜索查询，是当前核心闭环。
```

##### 第二优先级：习惯系统相关

```text
habit/create_habit_request.schema.json
habit/habit_response.schema.json
habit/habit_check_in_request.schema.json
habit/habit_check_in_response.schema.json
```

原因：

```text
习惯功能必须区分 Habit 和 HabitCheckIn，否则无法稳定表达坚持日期、完成次数、连续天数和完成率。
```

##### 第三优先级：通知日志与搜索

```text
notification/notification_response.schema.json
search/search_index_response.schema.json
```

原因：

```text
Notification 是投递结果日志，SearchIndex 是搜索性能优化结构，可以在主流程稳定后补齐。
```

##### 第四优先级：未来能力预留

```text
ai/ai_extraction_request.schema.json
ai/ai_extraction_response.schema.json
sync/sync_operation.schema.json
user/user_data_response.schema.json
```

原因：

```text
AI、云同步、用户云端数据属于未来能力。当前可以保留 schema 草案，但不必强制完整实现。
```

------

#### 15. Contract 设计原则

##### 原则 1：Request、Response、Domain Model 分离

不要用一个万能 `Event` 同时承担：

```text
创建请求
更新请求
数据库实体
C++领域对象
Flutter展示对象
接口返回对象
```

应拆分为：

```text
CreateEventRequest
UpdateEventRequest
EventResponse
EventDetailResponse
EventDomainModel
EventEntity
EventViewModel
```

当前阶段不需要所有层都完整实现，但概念上必须分清。

------

##### 原则 2：跨层传输只使用 Contract 字段

Flutter、Kotlin、C++ 之间传输时，只能使用 `contracts/` 中声明过的字段。

禁止临时传输：

```text
{
  "some_temp_field": "...",
  "frontendOnlyData": "...",
  "cppMagicValue": "..."
}
```

如确实需要新增字段，应先更新 contract。

------

##### 原则 3：错误统一走 NativeResult

禁止不同接口使用不同失败表达方式。

不允许：

```text
有的接口返回 false
有的接口返回 null
有的接口抛字符串
有的接口返回 {error: "..."}
```

统一使用：

```text
NativeResult<T>
```

------

##### 原则 4：Reminder 不嵌入 Event

Event 本体不保存提醒方式和提醒时间。

如果 Event 需要提醒，则创建一条或多条 Reminder。

例如：

```text
提前 1 天提醒
提前 1 小时提醒
开始时提醒
```

应保存为 3 条 Reminder，而不是塞进 Event 的数组字段中作为核心存储。

Contract 层可以在 `event_detail_response` 中聚合返回 reminders，但存储模型和领域模型仍应保持 Reminder 独立。

------

##### 原则 5：Notification 不参与提醒扫描

Reminder 是待执行任务。

Notification 是投递结果日志。

提醒扫描入口只能是 Reminder，不应扫描 Notification。

------

##### 原则 6：HabitCheckIn 是习惯统计来源

Habit 只表示习惯定义。

HabitCheckIn 表示某一天是否完成、完成几次、何时完成。

连续天数、总完成天数、完成率优先从 HabitCheckIn 计算。

------

##### 原则 7：枚举值使用字符串

跨层协议中的枚举值统一使用字符串，例如：

```text
important_urgent
weekly
scheduled
sent
manual
```

不建议使用数字枚举值。

------

##### 原则 8：日期和时间分开

```text
datetime: 精确时间点，使用 ISO 8601 UTC
date: 本地日期，不携带时分秒
```

例如：

```text
Event.start_at        datetime
Reminder.remind_at    datetime
Notification.sent_at  datetime
HabitCheckIn.check_date date
Anniversary.date        date
```

------

#### 16. 后续演进方向

当前阶段可以手写 schema 和 DTO。

当协议逐渐稳定后，可以考虑：

```text
1. 根据 JSON Schema 自动生成 Dart DTO
2. 根据 JSON Schema 自动生成 Kotlin data class
3. 根据 JSON Schema 自动生成 C++ boundary struct
4. 在 CI 中校验 schema 是否合法
5. 在单元测试中校验示例 JSON 是否符合 schema
6. 未来如果云端同步复杂度上升，再考虑 Protobuf / FlatBuffers / OpenAPI
```

但现阶段不建议一开始就引入过重的 IDL 或自动生成体系。

当前最重要的是：

```text
先把跨语言数据边界写清楚。
```

Contract Layer 的价值不是增加形式主义，而是防止项目后期在 Dart、Kotlin、C++、SQLite、Backend 之间出现字段漂移、错误码漂移、时间格式漂移和业务对象职责漂移。



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
├── contracts/
│   ├── README.md
│   ├── method_channels.yaml
│   │   └── 负责描述功能调用的方法，规定方法的入口
│   ├── error_codes.yaml
│   │   └── 负责统一整个项目的错误返回类型
│   ├── common/
│   │   ├── native_result.schema.json
│   │   |   └── 负责规定跨层函数返回数据的格式，如果调用成功返回什么，通用的返回外壳
│   │   ├── native_error.schema.json
│   │   |   └── 负责规定跨层函数返回数据的格式，如果调用失败返回什么，通用的返回外壳
│   └── event/
│       ├── create_event_request.schema.json
│       |   └── 负责规定具体创建日程时的所需要的数据形式
│       └── event_response.schema.json
│           └── 负责规定具体的创建日程后返回结果所需要的数据形式
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
