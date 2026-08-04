# Contract Layer

`contracts/` 是 ExcellentCalendarAPP 的跨语言数据协议源头，负责统一 Dart、Kotlin、C++、SQLite 以及未来 Backend 之间传输的数据结构、方法入口、错误码、枚举值和版本约定。

本目录不属于任何单一语言，也不替代 Dart DTO、Kotlin data class、C++ struct、C++ Domain Model 或 SQLite schema。各语言可以在本层协议之上做本土化实现，但跨层传输时必须使用这里声明的字段、方法名和错误结构。

## Scope

本层只定义跨语言传输协议：

- `method_channels.yaml` 定义 MethodChannel / EventChannel 的稳定入口。
- `native_calls.yaml` 定义 Kotlin ↔ JNI/C++ 的内部调用入口。
- `backend_api.yaml` 定义 Flutter ↔ Backend 的 HTTPS API 入口、鉴权、幂等和 schema 映射。
- `error_codes.yaml` 定义所有跨层失败返回可使用的错误码。
- `enums.yaml` 定义跨语言传输时使用的字符串枚举。
- `identity.yaml` 定义 occurrence、滚动 Reminder 和 delivery 的 UUIDv5 namespace、规范化输入和固定测试向量。
- `storage/calendar_core_storage.yaml` 定义 Calendar Core JSON v2 的兼容、归档和事务规则。
- `*.schema.json` 定义 request、response 和通用返回外壳的 JSON Schema。

本层不放业务流程编排、不放 Android 系统能力实现、不放 C++ 核心领域规则、不放 Flutter 页面状态，也不直接等于数据库表。

## Rules

1. 跨层字段统一使用 `snake_case`。
2. 枚举值统一使用字符串，不使用数字枚举。
3. 精确时间点使用 ISO 8601 UTC 字符串，例如 `2026-06-06T10:00:00Z`。
4. 本地日期使用 `YYYY-MM-DD` 字符串，例如 `2026-06-06`。
5. Flutter ↔ Kotlin 和 Kotlin ↔ C++ 使用 `NativeResult<T>`；Flutter ↔ Backend 使用独立的 `ApiResult<T>`，不得混用两种版本域。
6. 两种返回外壳都要求 `ok = true` 时 `error = null`。
7. 两种返回外壳都要求 `ok = false` 时 `data = null`，且 `error.code` 必须来自 `error_codes.yaml`。
8. `EventResponse` 不直接嵌入 `Reminder`；详情页聚合数据使用 `EventDetailResponse`。四个时间字段必须全部出现，未启用的一组显式为 `null`。
9. `Event.status` 只表示整个 Event 或整个重复系列的生命周期；重复日程单次 occurrence 状态使用 `EventOccurrenceStateResponse`。
10. `Reminder` 是未来要执行的提醒任务，`Notification` 是投递结果日志，二者不能混用。
11. `Habit` 只描述习惯定义，`HabitCheckIn` 才是完成记录和统计来源。
12. 独立创建 Reminder 必须使用 `CreateReminderRequest` 且包含 `target_id`；嵌入父对象创建流程时使用 `ReminderDraftRequest`。
13. `CreateReminderRequest` 和 `ReminderDraftRequest` 只能创建 `is_enabled = true` 的新 Reminder。修改已有 Reminder 必须使用 `reminder.update`；后续更新或取消可以使持久化的 `is_enabled` 变为 `false`。
14. Event recurrence 客户端输入固定使用 `EventRecurrenceRuleInput`；Habit/Anniversary 的计划态规则不得被解释为 Event v2 规则。
15. 重复 Event 的 occurrence 和滚动 Reminder 身份只能由 C++ 按 `identity.yaml` 生成；Dart/Kotlin 只透传。
16. Notification 必须走 `reminder.prepare_delivery` / `reminder.finalize_delivery`；v1 的 `notification.create`、`reminder.consume_after_delivery` 和 `reminder.mark_sent` 不属于 v2。
17. `finalize_delivery.error_code` 必须来自 `error_codes.yaml`，且 `failure_class` 必须与该错误码的 `retryable` 元数据一致。
18. Native v2 的 Reminder 主键字段统一为 `reminder_id`；v1 的通用 `id` 不得在 Reminder request/response 或调度游标中继续接受。
19. `event.update.recurrence` 省略表示保留，传对象表示设置或修改；v2 不接受含义不明确的 `null` 拆系操作。
20. `prepare_delivery` 返回 `PreparedNotificationPayload`，其中没有 `opened_at`；Android 收到点击后追加非空 `opened_at`，才形成 EventChannel 使用的 `NotificationTapPayload`。
21. `reminder.mark_scheduled` 必须携带 Kotlin 本次注册所依据的 `expected_remind_at`；C++ 仅在持久化 `remind_at` 仍严格相等时写入 `scheduled`，否则返回可重试的 `REMINDER_SCHEDULE_CONFLICT` 且不得修改 Reminder。
22. `prepared` Notification 的投递内容和 PendingIntent payload 一经返回即冻结。Recovery 只能通过 `resolved_by_recovery_batch_id` 接管原 attempt，或把它终结为 `abandoned`；禁止改写原 `recovery_batch_id` 来伪造新 payload。
23. `plan_recovery` 是唯一可写入 `ReminderStatus.expired` 的 workflow：只处理严格早于 72 小时窗口的 open `pending/scheduled` Reminder，原子禁用并清空 `scheduled_at`；重复 Reminder 同一事务保证未来 successor。
24. occurrence reopen 若遇到同模板的后继滚动 Reminder，必须以 `occurrence_reopened` 暂存后继并恢复原 Reminder；滚动链随后复用确定性 ID，任何时刻同模板最多一条 open Reminder。

## Directory

```text
contracts/
├── README.md
├── method_channels.yaml
├── native_calls.yaml
├── backend_api.yaml
├── error_codes.yaml
├── enums.yaml
├── identity.yaml
├── common/
├── runtime/
├── storage/
├── auth/
├── event/
├── recurrence/
├── reminder/
├── notification/
├── habit/
├── category/
├── ai/
├── sync/
├── user/
├── dated_message/
├── anniversary/
└── search/
```

当前本地核心闭环优先级为 `common/`、`event/`、`recurrence/`、`reminder/` 和 `notification/`。`auth/`、`user/` 与 `backend_api.yaml` 是认证和个人资料模块的计划协议；在 Flutter、Kotlin 和 Backend 实现落地前保持 `implementation_status: planned`，调用方不得把它们当作已可用能力。

## Versioning

Native Contract 已设计为 breaking v2，Backend API 继续使用独立的 v1。JSON Schema 使用 Draft 2020-12，并通过 `x-contract-domain`、`x-contract-version` 或独立的 `x-storage-format-version` 标明所属版本。MethodChannel、Backend API、错误码和枚举文件保留顶层 `version`。
`common/native_empty_request.schema.json` 与 `common/native_operation_response.schema.json` 属于 Native v2；未带 `native_` 前缀的同名通用文件继续服务 Backend API v1，禁止跨版本域复用其版本元数据。

`method_channels.yaml`、`native_calls.yaml` 与 Calendar Core JSON v2 当前仍标记为 `release_status: design_only`。C++ Domain/Boundary、JSON Storage 与 native_calls 中对应的 C++ 入口已经实现，但 Flutter、Kotlin、JNI 和 Android 调度尚未切换到 v2，因此只能标记 `implementation_status: cpp_core_complete_unintegrated`，不能描述为 APK 已支持或把 writer 指向用户正式目录。只有 Dart、Kotlin、JNI、C++、JSON Storage 与全链路测试在同一发行版本同步完成后，才可切换为 active。

| 版本域 | 真相源 | 当前版本 | 兼容策略 |
| --- | --- | --- | --- |
| Native MethodChannel / JNI | `method_channels.yaml`、`native_calls.yaml` | 2（design only） | Flutter、Kotlin、JNI、C++ 同一发行版本同步升级；v1/v2 双向拒绝 |
| Backend HTTP API | `backend_api.yaml` | 1 | 正式发布后至少支持 N-1 |
| Flutter 用户资料缓存 | `user/cached_current_user.schema.json` | 1 | 使用连续本地格式迁移，不复用 API 版本 |
| Calendar Core JSON | `storage/calendar_core_storage.yaml` | 2（design only） | 不读、不迁移 v1；先原子归档 v1，再初始化空 v2 |

在协议版本正式发布或被外部客户端依赖前，为使 Schema 与已确定的领域不变量保持一致而进行的修正，可以继续使用当前版本。协议一旦正式发布，收紧已有字段的合法取值范围也属于破坏性变更。

破坏性变更包括：

- 删除字段。
- 修改字段含义。
- 修改枚举值拼写。
- 修改 MethodChannel 方法名。
- 修改错误码含义。

发生破坏性变更时必须提升协议版本，并在各语言边界层同步处理兼容策略。

### Native v2 兼容矩阵

| Reader | v1 payload | v2 payload |
| --- | --- | --- |
| v1 | 接受 | 拒绝 |
| v2 | 拒绝 | 接受 |

- `NativeResult.contract_version` 在 v2 中是必填常量 `2`。
- 不提供 v1/v2 双写、字段猜测或默认值兼容层。
- 本地 v1 数据不是协议迁移输入；只允许按 Storage Contract 归档。
- 回滚必须保持 v1 归档和 v2 目录隔离，由显式恢复流程选择，禁止旧 App 打开 v2 目录。
- Backend、用户资料缓存、未来导入/导出和备份各自使用独立版本，不随 Native v2 自动升级。

实施依赖顺序为：领域/Contract 定稿 → C++ Domain、Clock、TZDB、workflow、Repository 与 Storage v2 → JNI/Kotlin contract 与调度 → Dart DTO/Gateway → 全链路测试与同一 APK 激活。任何中间构建都必须保持 `design_only`，不得让 v2 writer 写入用户正式目录。首次 Storage 归档只能发生在全部 v2 reader/writer 已随同一发行包就绪之后。

### v2 公共与内部能力边界

- `event.list_occurrences`、`event_occurrence.*` 与 `event.*_series` 同时出现在 MethodChannel 和 JNI 能力图中。
- `reminder.prepare_delivery`、`reminder.finalize_delivery`、`reminder.plan_recovery` 由 Android 调度服务调用，只出现在 `native_calls.yaml`，不暴露给 Flutter。
- `runtime.initialize(storage_directory, tzdb_directory)` 只出现在 `native_calls.yaml`。目录由 Kotlin 私有解析，Flutter 不得传入文件系统路径。
- `reminder.reconcile_schedule` 是 Kotlin 本地系统能力编排，可以组合多个 JNI workflow；MethodChannel 与 JNI 方法数量无需一一相等。

### Event recurrence v2

- `recurrence/event_recurrence_rule_input.schema.json` 是 Event v2 唯一创建/更新输入，只接收 `frequency/interval/end_at/count`。
- `recurrence/recurrence_response.schema.json` 是 C++ 派生的不可变 revision，不保存 `target_type/target_id`。
- `recurrence/recurrence_rule.schema.json` 仅保留给尚未实施的 Habit/Anniversary 计划协议，不能被 Event 引用。
- `yearly/custom` 保留稳定枚举入口，但 v2 C++ 必须返回 `FEATURE_NOT_IMPLEMENTED`。

### TZDB 实施门禁

Contract v2 固定返回 `tzdb_version = 2026c`，该版本可从 [IANA Time Zone Database releases](https://www.iana.org/time-zones/releases) 获取。需求中指定的 Howard Hinnant `date v3.0.5` 未出现在 [date 官方 release 列表](https://github.com/HowardHinnant/date/releases)；C++ 实施前必须由项目负责人选择真实 release（当前官方最新为 v3.0.4）或审核过的固定 commit。该依赖决策不由 Contract 静默替换。

### v2 影响矩阵

| 层 | 本轮结果 | 后续实施要求 |
| --- | --- | --- |
| Data Model | v2 领域语义已定稿并同步本轮恢复/竞态规则 | 后续实现必须保持字段、状态机和事务一致 |
| Contract | schema、方法、枚举、错误、身份和 Storage 规则已同步 | 激活前通过 Dart/Kotlin/C++ 契约与全链路测试，再移除 `design_only` |
| Dart | 未修改 | DTO/Gateway 必须拒绝 v1 与 malformed v2 |
| Kotlin/JNI | 仍为 v1，未接入本轮 v2 | 新增 v2 validator/bridge、CAS Alarm acknowledgement 与 prepared attempt 串行仲裁；Kotlin 只编排系统能力 |
| C++ Domain/Boundary | 已实现但未接入 APK | 保持 Core 测试通过，并在 JNI 接入后做 native smoke |
| JSON Storage | v2 codec、v1 归档、空目录初始化和 journal 重放已实现但未激活 | 接入 APK 前验证真实 Android 路径、崩溃恢复与回滚隔离 |
| Import/Backup/Backend | 不受 Native v2 版本驱动 | 继续使用各自独立版本域 |

### UserData 预发布纠正

旧 `UserData`、`user.update_settings` 及其两个 schema 从未被 Dart、Kotlin、C++、Backend 或正式存储实现，也没有历史用户数据。本次在协议正式发布前将其替换为 `UserAccount`、`UserProfile`、`UserPreferences` 和 `UserSyncState`，因此不创建伪造的数据迁移。`EntityType.user_data` 同步替换为 `user_preferences`。如果后续已有发行客户端依赖这些名称，再做相同变更时必须提升对应版本并提供兼容窗口。

## Native Result

完整返回结构为：

```text
NativeResult<T>
```

其中 `NativeResult` 来自 `common/native_result.schema.json`，`T` 来自 `method_channels.yaml` 中该方法声明的业务 response schema。

示例：

```text
event.create -> NativeResult<EventResponse>
event.search -> NativeResult<EventListResponse>
event.complete -> NativeResult<EventResponse>
event.reopen -> NativeResult<EventResponse>
habit.check_in -> NativeResult<HabitCheckInResponse>
```

## Backend API Result

Backend HTTPS 接口返回：

```text
ApiResult<T>
```

`ApiResult` 来自 `common/api_result.schema.json`，`ApiError` 来自 `common/api_error.schema.json`，具体 `T`、鉴权、HTTP 路径和允许错误码由 `backend_api.yaml` 声明。Backend 错误只能返回面向客户端的安全消息、字段错误、重试间隔和类型化上下文，不得返回堆栈、数据库异常、Token、密码或验证凭证。

忘记密码申请必须对已注册与未注册邮箱返回相同的成功结构。网络断开和请求超时属于 Flutter transport failure，不得伪装成 Backend 业务错误码。

## Authentication Boundaries

- 登录、注册、资料、密码、邮箱和头像请求由 Flutter 直接调用 Backend，不经过 Kotlin 或 C++。
- MethodChannel 只声明 `auth.refresh_token.store/read/delete/exists`，由 Kotlin 本地安全存储实现，不进入 `native_calls.yaml`。
- Access Token 只保存在 Flutter 内存；Refresh Token 只允许出现在 Token 响应、刷新/退出请求和敏感 MethodChannel schema 中。
- `CurrentUserResponse` 与 `CachedCurrentUser` 明确禁止密码、Token、验证 Challenge 和对象存储内部键。

## Ownership

新增跨层字段、方法、枚举或错误码时，必须先更新 `contracts/`，再由 Dart、Kotlin、C++、SQLite 或 Backend 做本土化实现。禁止在某一语言层临时发明未声明字段。
