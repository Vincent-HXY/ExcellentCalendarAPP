# ExcellentCalendarAPP

> 项目状态基线：2026-09-02（Asia/Shanghai）。本 README 保留完整产品设想、架构解释和开发环境说明；实时完成度以 [`docs/status/current.md`](docs/status/current.md)、机器 Contract 和实际代码/测试为准，目录或 Schema 存在不代表生产能力已经实现。

## 当前开发状态

ExcellentCalendarAPP 当前处于 **R2 开发阶段**，执行拓扑已经转为“已发布能力维护 + 开放验证债收口 + Local-first 云同步产品决策”。

| 能力 | 当前状态 | 重要边界 |
| --- | --- | --- |
| Calendar Core | SQLite Storage v5、Event、Recurrence、Reminder、Anniversary、Category 与通知/响铃主链已落地 | JSON v1/v2/v3 只作为迁移输入和降级 guard，不再是 live writer |
| Habit V1 | Contract、C++/SQLite v5、Kotlin/JNI/Android、Flutter/Appearance 与 production composition 已 `integrated + active` | 未完成真机系统行为矩阵由 `OPEN-HAB-001` 跟踪 |
| Calendar View V1 | 月/周分类视图及三类聚合查询已 `integrated + active` | 正式签名、时区/DST、无障碍和恢复矩阵由 `OPEN-CAL-001` 跟踪 |
| Search V1 | 三类 canonical 查询、独立分页和设备本地 History 已 `integrated + active` | 搜索框 TalkBack 语义与正式签名链由 `OPEN-SEA-001` 跟踪；SearchIndex/FTS 仍为 `planned/deferred` |
| 认证与个人资料 | Cloud Backend、Flutter 页面、会话恢复和 Android Keystore 代码已实现并完成开发联调 | `contracts/backend_api.yaml` 和 `auth.refresh_token.*` 仍为 `planned`，尚未校准为正式发布能力 |
| Local-first 云同步 | 已完成首轮需求与架构盘点，当前为 `SPECIALIST_SPLIT / DECISION_REQUIRED` | 尚无 active plan、生产同步 Contract、服务端日历表、本地 Outbox、设备注册或客户端同步引擎 |
| 四象限、AI/OCR、微信、Widget、备份 | 仍属于后续范围 | 不得由占位目录、Schema 或目标架构图推断为已实现 |

当前架构入口见 [`docs/architecture/overview.md`](docs/architecture/overview.md)，领域语义见 [`docs/domains/`](docs/domains/)，文档导航见 [`docs/index.md`](docs/index.md)，开放风险见 [`docs/issues/open.md`](docs/issues/open.md)。

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

### C++ Core 构建与测试

从仓库根目录执行以下命令。`excellent_calendar_check` 会先构建当前源码对应的测试程序，再运行 CTest；编译或测试任一步失败都会返回失败。

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不要把单独执行 `ctest --test-dir cpp_core/build-ninja` 作为完整验收，因为 CTest 不负责编译，构建失败时可能运行目录中遗留的旧测试程序。


## 功能需求分析

本节描述产品目标范围，不是完成清单。上表未标记为已实现的项目仍需经过领域、Contract、分层实现和验证门禁。

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
负责权限、通知、后台服务、系统回调等 Android 平台能力
        ↓ JNI
C++ Core
负责领域规则、跨实体 Workflow、Calendar/Search 查询与 Repository；加密、导出、全文索引等后续能力必须另行进入 Contract 和实施计划
		↓ 
SQLite
Calendar Core Storage v5 数据持久化
```



### 核心对象包括：

- Event：日程
- EventOccurrenceState：重复日程单次 occurrence 状态
- Habit：习惯
- HabitRecurrence：Habit 独占的 date-only 每日规则
- HabitCheckIn：习惯打卡事实
- HabitReminderTemplate：Habit 每日提醒配置
- Reminder：提醒
- Notification：提醒投递结果
- ReminderRecoveryBatch：提醒恢复批次
- Category：分类
- Recurrence：Event 重复规则的不可变 revision
- Anniversary：纪念日及其独立年度规则
- CalendarView：Calendar Core 生成的只读组合投影
- SearchQuery：三类 canonical 数据生成的只读组合查询
- SearchIndex：未来可选的搜索加速索引
- AIExtraction：AI 解析结果
- SyncOperation：未来同步操作占位模型
- UserAccount / UserProfile / UserPreferences / UserSyncState：拆分后的账号、资料、偏好与同步状态
- DatedMessage：投送消息

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
docs/domains/
contracts/
```

二者职责不同。

#### docs/domains/

`docs/domains/README.md` 与按对象拆分的领域文档描述核心业务对象、组合查询投影和数据边界，例如：

```text
Event
EventOccurrenceState
Habit
HabitRecurrence
HabitCheckIn
HabitReminderTemplate
Reminder
Notification
ReminderRecoveryBatch
Category
Recurrence
Anniversary
CalendarView
SearchQuery
SearchIndex
AIExtraction
SyncOperation
UserAccount / UserProfile / UserPreferences / UserSyncState
DatedMessage
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

例如，`Event` 是业务领域对象；但是 `CreateEventRequest`、`EventResponse`、`SearchQueryRequest`、`NativeResult<EventResponse>` 是跨层传输对象。

------

#### 3. 顶层目录结构

项目顶层新增：

```text
ExcellentCalendarAPP/
├── contracts/
│   ├── README.md
│   ├── method_channels.yaml
│   ├── native_calls.yaml
│   ├── error_codes.yaml
│   ├── enums.yaml
│   ├── identity.yaml
│   ├── backend_api.yaml
│   │
│   ├── common/
│   │   └── NativeResult、NativeError、分页与通用响应
│   ├── event/
│   │   └── Event 创建、更新、详情、列表与生命周期
│   ├── recurrence/
│   │   └── Event Recurrence request/response
│   ├── reminder/
│   │   └── Reminder、recovery 与调度工作流
│   ├── notification/
│   │   └── Notification attempt、点击与权限状态
│   ├── habit/
│   │   └── Habit、Recurrence、CheckIn、Reminder 与统计
│   ├── anniversary/
│   │   └── Anniversary、独立年度规则、Reminder 与 occurrence
│   ├── category/
│   │   └── Category create/list
│   ├── calendar/
│   │   └── Calendar range summary 与三类 day item
│   ├── search/
│   │   └── Search Query、分组分页与设备本地 History
│   ├── appearance/
│   ├── ring/
│   ├── runtime/
│   ├── auth/
│   ├── user/
│   ├── ai/
│   │   └── AI candidate 占位协议
│   ├── sync/
│   │   └── SyncOperation / SyncResult 概念占位
│   └── storage/
│       └── Calendar Core SQLite v5 与连续迁移真相源
```

当前 `common/event/recurrence/reminder/anniversary/category/habit/calendar/search/ring/appearance` 的已发布部分已经按机器 Contract 接入真实链路。`auth/user/backend_api.yaml` 对应代码已经实现并完成开发联调，但机器状态仍为 `planned`；`ai/sync` 与 SearchIndex/FTS 继续是概念占位或 deferred 能力。具体状态必须读取文件内的 `implementation_status/release_status`，不能按目录是否存在推断。

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
        { "$ref": "../recurrence/event_recurrence_rule_input.schema.json" },
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

重复规则必须按领域拆分，不能用一个通用 DTO 抹平 Event、Habit 和 Anniversary 的锚点、生命周期与 occurrence 语义。

- Event 使用 `event_recurrence_rule_input.schema.json` 与不可变 `(recurrence_id, revision)`；其锚点由 C++ 从 Event 时间字段派生。
- Habit 使用独立的 `habit_recurrence_rule_input.schema.json` 与 `habit_recurrence_response.schema.json`，V1 固定为 date-only `daily + interval=1 + follow_device`，并已随 Habit V1 激活；不得复用 Event Recurrence revision。
- Anniversary V1 使用独立的 `anniversary_recurrence_rule_input.schema.json` 与 `anniversary_recurrence_response.schema.json`，不得引用 Event Recurrence revision。

##### 11.1 `anniversary_recurrences` 数据结构

领域实体名为 `AnniversaryRecurrence`，持久化逻辑集合名为 `anniversary_recurrences`。它是 Anniversary 独占的轻量规则；跨层 Request、Response、Domain 和 Storage Record 仍保持分离。

| 字段 | 领域/存储语义 | 跨层语义 |
| --- | --- | --- |
| `recurrence_id` | UUIDv4 主键；一个活动规则最多由一个 Anniversary 引用 | 只由 response 返回，客户端 input 不提交 |
| `frequency` | V1 固定 `yearly` | schema 使用 `const: yearly` |
| `interval` | V1 固定 `1` | schema 使用 `const: 1` |
| `created_at` | 规则创建的 UTC Instant | 当前 recurrence response 不暴露 |
| `deleted_at` | 软删除 UTC Instant；活动规则为 `null` | 当前 recurrence response 不暴露 |

核心不变量：

1. 一次性纪念日的 `Anniversary.recurrence_id = null`；年度重复必须指向活动且有效的 `yearly + interval=1` 规则。
2. 原始日期和历史年份只保存在 `Anniversary.date`。规则不重复保存月、日、时区、RRULE 或 UTC occurrence。
3. 仍为年度重复时更新标题或日期保留原 `recurrence_id`；日期变化只改变后续动态计算使用的锚点。
4. 从一次性切换为年度重复时创建新规则；从年度重复切换为一次性时，在同一 C++ transaction 中清空引用并软删除旧规则。
5. 不提前生成 2027、2028、2029 等 occurrence。C++ 查询按请求 IANA timezone 动态计算下一次本地日期；2 月 29 日在非闰目标年落到二月最后一天。
6. Anniversary occurrence 不持久化状态，但已经具有由 `anniversary_id + occurrence_date` 生成的稳定 `occurrence_key`；Reminder R1 使用 occurrence、template 与 reminder 的确定性 identity，并由 C++ workflow 负责幂等、滚动 successor 和 reconciliation。

Anniversary Contract 已切换为 `implementation_status: integrated`、`release_status: active`。`anniversaries`、`anniversary_recurrences`、Reminder template、Reminder 与 Notification 等表在 SQLite Storage v4 引入，并由当前正式的 Calendar Core SQLite Storage v5 原样继承；相关 Workflow 通过同一数据库事务原子提交。合法 JSON v2/v3 目录会连续迁移到 SQLite v4，再通过受控相邻迁移进入 v5；旧集合保留为带版本 4 降级 guard 的诊断快照，不再参与运行时读写。Flutter → Kotlin → JNI → C++、Repository/workflow、Anniversary Reminder/Notification、occurrence 查询及自动化回归均已接入。

------

#### 12. Contract 与各语言实现的对应关系

##### 12.1 Dart 侧

Dart 侧当前按边界模块组织：

```text
flutter_client/lib/native_contract/
├── common/、shared/                    # 统一结果、错误、分页与 JSON 归一化
├── event/、recurrence/                # 事件、occurrence 与重复规则
├── reminder/、notification/           # 提醒、调度与通知
├── anniversary/、category/、habit/    # 纪念日、分类与习惯
├── calendar/、search/                 # Calendar View 与 Search Query V1
├── runtime/、appearance/、ring/       # 运行时、外观与圆环状态
└── auth/、user/                       # 本地认证边界与用户缓存模型
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

Kotlin 侧当前以 Contract 校验器和模块契约文件承接同一份跨层协议：

```text
android/app/src/main/kotlin/.../bridge/contract/
├── NativeResultContract.kt、NativeErrorContract.kt
├── EventV2Contracts.kt、RecurrenceV2Contracts.kt
├── ReminderV2Contracts.kt、NotificationContracts.kt
├── AnniversaryContracts.kt、CategoryContracts.kt、HabitContracts.kt
├── CalendarContracts.kt、SearchContracts.kt
├── RuntimeTimezoneContracts.kt、AppearanceContracts.kt、RingContracts.kt
└── AuthRefreshTokenContracts.kt
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

Native Calendar Core Bridge 拆分约定：

```text
android/app/src/main/kotlin/.../bridge/native/
├── NativeEventBridge.kt
├── NativeReminderBridge.kt
├── NativeNotificationBridge.kt
├── NativeAnniversaryBridge.kt
├── NativeCategoryBridge.kt
├── NativeHabitBridge.kt
├── NativeCalendarViewBridge.kt
├── NativeSearchBridge.kt
├── NativeRuntimeBridge.kt
├── NativeCalendarCoreBridge.kt
├── JniNativeCalendarCoreBridge.kt
├── JniHabitBridge.kt
├── JniCalendarViewBridge.kt
├── JniSearchBridge.kt
├── CalendarCoreStorageDirectoryResolver.kt
└── AndroidNativeBridgeFactory.kt
```

约定如下：

1. 单个业务模块的 JNI 能力必须先放进独立接口文件，例如事件放在 `NativeEventBridge.kt`，提醒放在 `NativeReminderBridge.kt`。
2. `NativeCalendarCoreBridge.kt` 是聚合接口，只继承各模块接口，不直接新增方法。
3. `JniNativeCalendarCoreBridge.kt` 是聚合实现类，负责加载 native 库、初始化 C++ storage，并实现所有模块接口方法。
4. `AndroidNativeBridgeFactory.kt` 是 Android 统一创建入口，文件名和职责保持稳定，并通过 `CalendarCoreStorageDirectoryResolver.kt` 指定正式数据目录。
5. Android Calendar Core 继续使用历史兼容目录名 `files/local_storage/calendar_core_storage_json`，但当前唯一 live writer 是其中的 SQLite v5 文件 `calendar_core.sqlite3`；目录内 JSON v1/v2/v3 只作迁移输入和降级 guard。历史 `files/local_storage/test_storage_json` 仅作为旧版本升级迁移来源，不再作为新代码的正式目录名。
6. 后续新增模块时继续沿用现有 Anniversary、Habit、Calendar View 与 Search 的拆分方式：先新增窄接口，再让 `NativeCalendarCoreBridge.kt` 聚合，并同步补齐 JNI 实现、C++ 导出符号、contracts、Kotlin contract 校验和测试 fake。
7. 只需要单模块能力的服务应依赖窄接口，例如 reminder 调度服务依赖 `NativeReminderBridge`；只有 MethodChannel 总入口或跨模块编排流程才依赖 `NativeCalendarCoreBridge`。

------

##### 12.3 C++ 侧

C++ Core 中应区分：

```text
C++ Domain Model
C++ Boundary Contract
```

当前实现示例：

```text
cpp_core/
├── include/excellent_calendar/domain/
│   ├── event.hpp
│   ├── reminder.hpp
│   ├── recurrence.hpp
│   ├── anniversary.hpp
│   ├── habit.hpp
│   └── search.hpp
│
├── include/excellent_calendar/boundary/contract/
│   ├── create_event_request.hpp
│   ├── event_response.hpp
│   ├── native_result.hpp
│   ├── anniversary_json.hpp
│   ├── habit_json.hpp
│   ├── calendar_view_json.hpp
│   └── search_json.hpp
│
└── src/boundary/contract/
    ├── event_response.cpp
    ├── native_result.cpp
    ├── anniversary_json.cpp
    ├── habit_json.cpp
    ├── calendar_view_json.cpp
    └── search_json.cpp
```

C++ Domain Model 负责表达核心业务规则。

C++ Boundary Contract 负责和 Dart/Kotlin 传输数据。

禁止 C++ Core 直接把 Domain Model 暴露给 Dart/Kotlin。

跨实体生命周期变更必须放在 C++ workflow / transaction 层完成，而不是让 Flutter 或 Kotlin 分散补偿。当前约定：

1. `event.complete` 仍返回 `EventResponse`，但内部必须通过 `EventLifecycleWorkflowService` 在同一个 `EventReminderTransaction` 中完成 Event，并取消关联的未触发 Reminder。
2. `event.reopen` 同样走 `EventLifecycleWorkflowService`，只恢复因 `event_completed` 自动取消、且仍在未来的 Reminder。
3. Reminder 的 `cancellation_reason` 是领域字段，用于区分 `user_cancelled` 和 `event_completed`；Android Alarm/Notification 只根据当前 Reminder 表状态执行，不保存额外真相源。

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

#### 14. Contract 当前状态

早期“第一至第四优先级”已经不能代表实际进度。当前应按机器 Contract 和真实 production composition 区分以下三类。

##### 已集成并激活

```text
NativeResult / NativeError / error_codes / enums / identity
Event / Event Recurrence / Reminder / Anniversary / Category
Habit / HabitCheckIn / HabitRecurrence / HabitReminderTemplate
Ring / Appearance
Calendar View range/day query
Search Query / device-local Search History
Calendar Core SQLite Storage v5
```

这些能力已有对应跨层实现和验证，但已激活不等于所有设备、正式签名或恢复矩阵均已通过；开放边界分别记录在 `docs/issues/open.md`。

##### 代码已实现、机器状态仍待校准

```text
Backend Auth / User Profile / Avatar HTTP API
auth.refresh_token.* Android secure-store MethodChannel
```

Cloud Backend、Flutter 账号/个人资料和 Android Keystore 代码已经完成开发联调，但 `contracts/backend_api.yaml` 及四个 `auth.refresh_token.*` 仍为 `planned`，不能描述为正式 active。

##### Planned / Deferred

```text
notification.list 与通知历史页面
SearchIndex / SQLite FTS
SyncOperation / UserSyncState / sync.apply
AI extraction / OCR / Candidate Event
四象限、附件、导入导出与备份
```

其中 Local-first 云同步已完成需求与架构盘点，但仍处于 `DECISION_REQUIRED`；必须先冻结产品语义、数据所有权、Outbox、游标、版本、删除和冲突策略，再建立生产 Contract 与分层计划。

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

对 `planned/deferred` 能力可以只保留概念设计；一旦能力标记为 `integrated + active`，相关 Contract、调用方、边界适配、真实存储/平台实现和验证必须完整闭环，不能只实现其中一层。

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

当前仍以人工维护的 Schema、DTO 和边界映射为主，并通过模块 validator、单元测试与跨层 smoke 防止漂移。

当协议逐渐稳定后，可以考虑：

```text
1. 根据 JSON Schema 自动生成 Dart DTO
2. 根据 JSON Schema 自动生成 Kotlin data class
3. 根据 JSON Schema 自动生成 C++ boundary struct
4. 将现有模块 Contract validator 固化进 CI
5. 持续用 fixture、语义 validator 和跨层测试校验示例 JSON
6. 未来如果云端同步复杂度上升，再考虑 Protobuf / FlatBuffers / OpenAPI
```

在现有 Native Contract v2 和已发布能力稳定运行期间，不应为单个功能贸然引入新的重型 IDL 或自动生成体系；若统一引入，必须作为独立工具链变更并验证全部调用方。

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
│       └── [planned] 负责本地同步模块与云端 API 之间的通信
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
│   │   └── [planned] 负责接收其他 App 分享来的文本或图片
│   │
│   ├── Widget Provider
│   │   └── [planned] 负责桌面小组件，例如今日日程、习惯、最近三天
│   │
│   └── WeChat Bridge
│       └── [planned] 负责微信登录、微信分享、微信推送相关能力
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
│   │   └── [V1 active] 负责 canonical 三类查询、条件过滤、排序、分页；全文索引/FTS deferred
│   │
│   ├── Habit Engine
│   │   └── 负责习惯打卡、统计、连续天数、完成率
│   │
│   ├── Calendar Query Engine
│   │   └── [V1 active] 负责月/周范围与选中日的 Event/Habit/Anniversary 聚合；年/最近三日另行规划
│   │
│   ├── Quadrant Engine
│   │   └── [planned] 负责按照重要性和紧急性生成四象限数据
│   │
│   ├── AI Result Validator
│   │   └── [planned] 负责校验 AI 生成的候选日程是否可靠、合法
│   │
│   ├── Sync Log Engine
│   │   └── [decision required] 负责与业务写同事务记录 Outbox；当前尚未实现
│   │
│   ├── Crypto / Export Engine
│   │   └── [planned] 负责本地数据加密、备份导出、备份导入
│   │
│   └── Storage Repository
│       └── 负责统一访问 SQLite，避免各个 Engine 直接乱写 SQL，所有的SQL语句都写在这里
│
├── Local Storage 本地存储层，所有的数据库文件，内容都写在这里
│   ├── SQLite
│   │   └── [v5 active] 负责 Calendar Core 结构化数据持久化
│   │
│   ├── SQLite FTS
│   │   └── [deferred] 负责未来全文搜索加速索引
│   │
│   ├── Attachment Store
│   │   └── [planned] 负责保存图片、导入文件、附件
│   │
│   └── Operation Log
│       └── [decision required] 负责未来同步 Outbox；当前尚未实现
│
├── AI Pipeline AI 输入管道
│   ├── OCR Adapter
│   │   └── [planned] 负责从图片中提取文字
│   │
│   ├── Text Extraction
│   │   └── [planned] 负责清洗文本、提取可能包含日程的信息
│   │
│   ├── Time Parser
│   │   └── [planned] 负责识别“明天上午”“下周五”等自然语言时间
│   │
│   ├── Category Recommender
│   │   └── [planned] 负责推荐分类，例如学习、工作、购物、纪念日
│   │
│   ├── Reminder Recommender
│   │   └── [planned] 负责推荐提前多久提醒
│   │
│   └── Candidate Event Builder
│       └── [planned] 负责生成候选日程，等待用户确认
│
└── Optional Cloud Backend 可选云端
    ├── Auth
    │   └── [代码已实现、Contract planned] 负责账号登录、会话和个人资料
    │
    ├── Sync API
    │   └── [decision required] 负责多设备数据同步；当前只有空包占位
    │
    ├── Backup API
    │   └── [planned] 负责云端备份和恢复
    │
    ├── AI API Proxy
    │   └── [planned] 负责转发 AI 请求，隐藏密钥和控制成本
    │
    └── WeChat Push Gateway
        └── [planned] 负责服务端微信提醒推送
```
