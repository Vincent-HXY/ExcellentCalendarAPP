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
8. `EventResponse` 不直接嵌入 `Reminder`；详情页聚合数据使用 `EventDetailResponse`。
9. `Event.status` 只表示整个 Event 或整个重复系列的生命周期；重复日程单次 occurrence 状态使用 `EventOccurrenceStateResponse`。
10. `Reminder` 是未来要执行的提醒任务，`Notification` 是投递结果日志，二者不能混用。
11. `Habit` 只描述习惯定义，`HabitCheckIn` 才是完成记录和统计来源。
12. 独立创建 Reminder 必须使用 `CreateReminderRequest` 且包含 `target_id`；嵌入父对象创建流程时使用 `ReminderDraftRequest`。
13. `CreateReminderRequest` 和 `ReminderDraftRequest` 只能创建 `is_enabled = true` 的新 Reminder。修改已有 Reminder 必须使用 `reminder.update`；后续更新或取消可以使持久化的 `is_enabled` 变为 `false`。

## Directory

```text
contracts/
├── README.md
├── method_channels.yaml
├── native_calls.yaml
├── backend_api.yaml
├── error_codes.yaml
├── enums.yaml
├── common/
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

当前 Native Contract 和 Backend API Contract 都从版本 `1` 开始，但属于互相独立的版本域。JSON Schema 使用 Draft 2020-12，并通过 `x-contract-domain`、`x-contract-version` 或独立的 `x-storage-format-version` 标明所属版本。MethodChannel、Backend API、错误码和枚举文件保留顶层 `version`。

| 版本域 | 真相源 | 当前版本 | 兼容策略 |
| --- | --- | --- | --- |
| Native MethodChannel / JNI | `method_channels.yaml`、`native_calls.yaml` | 1 | Flutter、Kotlin、C++ 同一发行版本同步升级 |
| Backend HTTP API | `backend_api.yaml` | 1 | 正式发布后至少支持 N-1 |
| Flutter 用户资料缓存 | `user/cached_current_user.schema.json` | 1 | 使用连续本地格式迁移，不复用 API 版本 |

在协议版本正式发布或被外部客户端依赖前，为使 Schema 与已确定的领域不变量保持一致而进行的修正，可以继续使用当前版本。协议一旦正式发布，收紧已有字段的合法取值范围也属于破坏性变更。

破坏性变更包括：

- 删除字段。
- 修改字段含义。
- 修改枚举值拼写。
- 修改 MethodChannel 方法名。
- 修改错误码含义。

发生破坏性变更时必须提升协议版本，并在各语言边界层同步处理兼容策略。

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
