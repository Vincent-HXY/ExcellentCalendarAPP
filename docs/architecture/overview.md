# ExcellentCalendarAPP Architecture Overview

> 定位：这是项目的**当前架构地图**，用于快速判断系统如何分层、代码应放在哪里、哪些边界不能绕过，以及哪些能力已经真实落地。
>
> 基线：2026-08-15。架构来源为项目 `README.md`；实现状态以仓库内 `docs/develop_record.md`、`docs/problems.md` 和实际代码为准。Contract 或目录存在，不代表对应生产能力已经完成。

## 1. Architecture at a Glance

ExcellentCalendarAPP 是一个 **Android 优先、Local-first、Contract-first** 的日历与个人效率应用。当前客户端主链路是：

```text
Flutter Presentation / State
    ↓
Flutter Application / Use Case
    ↓
Dart Gateway Interface + typed Contract DTO
    ↓ MethodChannel / EventChannel
Kotlin modular Handler / Android Service
    ↓ JNI
C++ Boundary Contract
    ↓
C++ Application / Workflow / Domain
    ↓
Repository
    ↓
Calendar Core JSON Storage v2
```

提醒投递是主链路的 Android 平台分支：

```text
C++ Reminder state / recovery plan
    ↓ JNI
Kotlin Reminder coordinator
    ↓
AlarmManager Dispatcher + WorkManager recovery
    ↓
Android Notification
    ↓ click payload / EventChannel
Flutter router / detail page
```

可选云端是扩展路径，不替代本地核心：

```text
Local-first client
    ↓ HTTPS + versioned JSON Contract
Spring Boot modular monolith
    ├─ API
    ├─ Worker
    └─ Scheduler
         ↓
     PostgreSQL
```

AI、云同步、微信、备份等扩展能力不得绕过既有 Application、Contract、Domain 或 Persistence 边界。

## 2. Layer Responsibilities

### Flutter Presentation / State

负责：

- 页面、组件、输入、导航、弹窗、loading 和视觉状态。
- 明确、合法、尽量不可变的页面状态。
- 把用户动作交给 Application 层。

不负责：

- 核心领域规则和跨实体事务。
- 直接拼接 MethodChannel JSON。
- 直接访问 C++、本地文件或数据库。

### Flutter Application

负责：

- 用户流程编排、Use Case、重试和状态转换。
- 调用 typed Gateway，并把结果转换为 UI 可消费的状态。
- AI 导入后的用户确认、页面级操作顺序等客户端流程。

不负责：

- 重复规则、提醒合法性等核心领域判断。
- 需要原子一致性的跨实体生命周期补偿。

### Dart Gateway / DTO

负责：

- 定义 Dart 层调用底层能力的类型安全接口。
- Dart 对象与 Contract `snake_case` payload 的转换。
- 解析 `NativeResult<T>` / `NativeError`。

原始 `Map<String, dynamic>` 只能停留在边界适配范围，不能扩散到 UI 或领域代码。

### Kotlin Bridge / Android Native

负责：

- MethodChannel/EventChannel 注册、严格 Contract 校验和轻量参数转换。
- JNI bridge、Native runtime 初始化和结果回传。
- Android 权限、AlarmManager、Notification、WorkManager、系统广播、分享、Widget、微信 SDK 等平台能力。

不负责：

- 日程、重复、提醒和纪念日的核心业务规则。
- 擅自修改 Contract 字段名或错误语义。
- 保存一份与 C++ Reminder 状态竞争的业务真相源。

Kotlin bridge 按业务模块拆分窄接口；`NativeCalendarCoreBridge` 只做聚合，单模块服务优先依赖 `NativeEventBridge`、`NativeReminderBridge`、`NativeAnniversaryBridge`、`NativeCategoryBridge` 等窄接口。

### C++ Boundary

负责：

- JSON / Contract Request 与 C++ Command、Domain Result 与 Contract Response 之间的转换。
- 严格拒绝缺失必填字段、未知字段、未知枚举、非法外壳和不兼容版本。
- 统一生成 Contract 声明的 `NativeResult<T>` 和稳定错误码。

不负责：

- 把 C++ Domain Model 直接暴露给 Dart/Kotlin。
- 用 codec 或 JSON parser 承担核心领域规则。

### C++ Application / Workflow / Domain

负责：

- Event、Recurrence、Reminder、Notification、Anniversary、Category 等平台无关业务规则。
- 防御性领域校验、状态机、搜索/排序规则、时区与 recurrence 计算。
- 跨实体生命周期和原子 workflow/transaction。

边界校验不能替代 C++ Core 内部的领域校验。跨实体操作必须在 C++ workflow / transaction 中完成，不能让 Flutter 或 Kotlin 分散补偿。

### Repository / Storage

负责：

- Repository 作为持久化统一入口。
- Storage codec、原子写入、事务 journal、软删除、重启恢复和损坏数据显式失败。
- 将领域/应用对象映射为持久化 Record。

Engine 不得直接散落文件读写或 SQL。未来迁移 SQLite 后，SQL 也必须集中在 Storage Repository。

### Optional Cloud Backend

负责：

- 未来的认证、设备、同步中枢、备份、服务器渠道提醒、AI Proxy 和媒体能力。
- 以 Spring Boot modular monolith 组织 API / Worker / Scheduler；业务模块内部按 `api → application → domain ← infrastructure` 分层。

本地 C++ Core 继续负责离线领域语义，Android 继续负责本机 Alarm/Notification。后端不能成为绕过本地领域与 Contract 的第二套规则源。

## 3. Actual Source Map

```text
ExcellentCalendarAPP/
├─ contracts/                         跨语言与客户端/后端协议真相源
├─ flutter_client/lib/
│  ├─ presentation/                   Flutter 页面与组件
│  ├─ application/                    Use Case、Controller、流程编排
│  ├─ gateway_interfaces/             Dart 能力接口
│  ├─ native_contract/                Dart typed DTO
│  └─ boundary_adapters/              Dart MethodChannel adapter
├─ flutter_client/android/app/src/main/kotlin/.../
│  ├─ bridge/channel/                 模块化 MethodChannel handler
│  ├─ bridge/contract/                Kotlin Contract 校验
│  ├─ bridge/native/                  窄 JNI bridge 与聚合 bridge
│  ├─ android/alarm/                  Alarm 调度与恢复
│  └─ android/notification/           系统通知与点击
├─ cpp_core/
│  ├─ include/excellent_calendar/domain/
│  ├─ include/excellent_calendar/application/
│  ├─ include/excellent_calendar/boundary/
│  ├─ include/excellent_calendar/repository/
│  └─ src/storage/json/               当前 JSON v2 持久化实现
├─ cloud_backend/                     Spring Boot 可选云端模块
└─ test_environment/flutter_native_smoke/
                                       Flutter→Kotlin→JNI→C++ smoke
```

仓库顶层的 `android_native/`、`boundary_adapters/`、`local_storage/`、`ai_pipeline/` 目前主要是职责说明或占位骨架。查找真实客户端实现时，应优先进入 `flutter_client/` 和 `cpp_core/`，不要仅凭顶层目录名判断功能已经落地。

## 4. Contract Boundary Rules

`contracts/` 是所有跨语言调用和未来客户端↔后端边界的协议真相源。任何 Dart↔Kotlin、Kotlin↔C++ 或 Client↔Backend 变更，都必须先有 Contract 声明。

跨层变更通常按此顺序进行：

1. 更新适用的 request / response JSON Schema。
2. 更新 Flutter 公开调用的 `method_channels.yaml` 或 Kotlin→C++ 的 `native_calls.yaml`。
3. 更新 `error_codes.yaml`、`enums.yaml`、版本、状态和示例。
4. 同步 Dart DTO/Gateway、Kotlin Contract/JNI、C++ Boundary/Domain/Repository。
5. 补齐跨层正例、边界、非法输入、兼容与 smoke 测试。

强制约定：

- Contract 字段使用 `snake_case`；语言内部可使用本土命名，但 wire format 不变。
- Native 调用统一返回 `NativeResult<T>` / `NativeError`；错误码只能来自 `error_codes.yaml`。
- Backend HTTP 使用 `ApiResult<T>`，不能把本地 `NativeResult<T>` 直接当成 HTTP 协议。
- 传输枚举使用稳定字符串，不使用数字序号。
- `datetime` 是 ISO 8601 UTC 时间点；`date` 是不带时分秒的用户本地日期。
- Request、Response、Domain Model、Storage Record、数据库实体和 ViewModel 必须分离。
- Contract 已声明但状态为 `planned` 或 `blocked`，不等于生产能力可调用。
- 禁止临时增加未声明的 MethodChannel 方法、JNI 函数、字段、枚举值或自由文本错误。

## 5. Architecture Decisions

核心领域不变量以按模块拆分的 ADR 保存。修改相关模块前，应先阅读对应 ADR：

- [ADR-Event-01：Event、Reminder 与 Notification 职责边界](./decisions/ADR-Event-01-Event-Reminder-Notification边界.md)
- [ADR-Recurrence-01：领域专属重复规则与 Occurrence 状态](./decisions/ADR-Recurrence-01-领域专属重复规则与Occurrence状态.md)
- [ADR-Anniversary-01：Anniversary 使用独立实体](./decisions/ADR-Anniversary-01-Anniversary使用独立实体.md)
- [ADR-Habit-01：Habit 与 HabitCheckIn 分离](./decisions/ADR-Habit-01-Habit与HabitCheckIn分离.md)
- [ADR-Category-01：Category 弱引用与最小冻结语义](./decisions/ADR-Category-01-弱引用与最小冻结语义.md)
- [ADR-Common-01：领域校验、派生状态与严格失败](./decisions/ADR-Common-01-领域校验与派生状态.md)

ADR 记录已经接受的设计决定；实时完成度和开放风险仍分别查阅 `develop_record.md` 与 `problems.md`。

## 6. Current Persistence and Runtime

当前 Android Calendar Core 正式数据目录：

```text
files/local_storage/calendar_core_storage_json
```

关键事实：

- 当前为版本化 JSON Storage v2，由 C++ Repository 和严格 codec 统一访问。
- Event/Reminder/Recurrence/Occurrence/Notification/Recovery 使用跨 Store workflow journal。
- Anniversary 使用独立两 Store transaction 和专用 journal，不改变 Event/Reminder journal。
- Category 使用独立 `categories.json`，完整快照原子替换和可恢复 sidecar；恢复失败时拒绝暴露不确定的新快照。
- Calendar Core runtime 是进程级 owner；Android 通过 `AndroidNativeBridgeFactory` 统一创建和初始化。进程内 JNI 测试必须复用正式 factory，隔离 Store 时使用独立测试进程。
- V1 数据按已确认决策不迁移、不归档；识别为 v1 后直接清理。回滚到旧版本可能失去本地数据。
- SQLite/FTS 是后续迁移方向。迁移前必须先冻结 Repository、Schema version、事务、回滚和旧数据验证策略。

## 7. Representative Flows

### Create Event

```text
EventFormPage
  → CreateEventUseCase
  → CreateEventRequestDto
  → EventNativeGateway
  → MethodChannel event.create
  → Kotlin Event handler / Contract
  → JNI
  → C++ Boundary Request
  → Event / Recurrence / Reminder workflow
  → Repository + JSON transaction
  → EventResponse
  → NativeResult<EventResponse>
  → Flutter Application / UI
```

### Deliver Reminder

```text
Reminder reconcile / recovery plan
  → mark_scheduled(expected_remind_at CAS)
  → Dispatcher Alarm
  → prepare_delivery
  → C++ returns real notification_id + delivery_id + attempt_id
  → Android NotificationManager.notify
  → finalize_delivery
  → atomically persist Notification result and Reminder transition/successor
```

旧 Alarm 或旧投递 attempt 必须通过 CAS/identity 被拒绝；不得先展示过期通知再让 C++ 事后纠正。

## 8. Where New Logic Belongs

- 按钮、表单错误、弹窗、loading、视觉选中态 → Flutter Presentation / State。
- 用户操作顺序、页面流程、Gateway 调用和重试 → Flutter Application。
- 重复展开、提醒合法性、状态机、搜索排序、跨实体一致性 → C++ Domain / Application / Workflow。
- 权限、AlarmManager、Notification、WorkManager、Intent、Widget、微信 SDK → Kotlin Android。
- MethodChannel/JNI 名称、序列化、错误映射、DTO 转换 → Boundary / Adapter。
- 文件、JSON codec、事务 journal、未来 SQL/FTS → Repository / Storage。
- 任何跨语言字段或方法 → 先修改 `contracts/`，再改实现。

## 9. Related Documentation

- [项目 README](../../ExcellentCalendarAPP/README.md)：完整产品需求、原始架构论述和开发环境基线。
- [项目 Agent 规则](../../ExcellentCalendarAPP/AGENTS.md)：强制阅读顺序、职责边界和验证要求。
- [实时开发状态](../../ExcellentCalendarAPP/docs/develop_record.md)：**当前进度的权威文档**。
- [已知问题与风险](../../ExcellentCalendarAPP/docs/problems.md)：开放风险、历史根因和规避要求。
- [当前目标](../../ExcellentCalendarAPP/docs/target.md)：近期目标与未完成事项。
- [领域数据模型](../../ExcellentCalendarAPP/docs/DATA_MODEL.md) 与 [拆分后的领域文档](../domains/)：实体、关系和领域不变量。
- [Contract 总则](../../ExcellentCalendarAPP/contracts/README.md)、[MethodChannel](../../ExcellentCalendarAPP/contracts/method_channels.yaml)、[Native Calls](../../ExcellentCalendarAPP/contracts/native_calls.yaml)、[错误码](../../ExcellentCalendarAPP/contracts/error_codes.yaml)、[枚举](../../ExcellentCalendarAPP/contracts/enums.yaml)。
- [架构决策](./decisions/)：后续 ADR 入口。
- [产品路线图](../status/roadmap.md)：从本地核心到 SQLite、云同步和扩展能力的演进顺序。
- [验证指南](../guides/verification.md)：各层测试、构建和真机验收入口。

阅读顺序建议：先读本文定位层级，再按任务进入对应 Domain/Contract；只有需要历史原因、开放风险或实时进度时，再读 `problems.md`、`develop_record.md` 和具体任务记录。
