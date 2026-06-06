# Contract Layer

`contracts/` 是 ExcellentCalendarAPP 的跨语言数据协议源头，负责统一 Dart、Kotlin、C++、SQLite 以及未来 Backend 之间传输的数据结构、方法入口、错误码、枚举值和版本约定。

本目录不属于任何单一语言，也不替代 Dart DTO、Kotlin data class、C++ struct、C++ Domain Model 或 SQLite schema。各语言可以在本层协议之上做本土化实现，但跨层传输时必须使用这里声明的字段、方法名和错误结构。

## Scope

本层只定义跨语言传输协议：

- `method_channels.yaml` 定义 MethodChannel / EventChannel 的稳定入口。
- `error_codes.yaml` 定义所有跨层失败返回可使用的错误码。
- `enums.yaml` 定义跨语言传输时使用的字符串枚举。
- `*.schema.json` 定义 request、response 和通用返回外壳的 JSON Schema。

本层不放业务流程编排、不放 Android 系统能力实现、不放 C++ 核心领域规则、不放 Flutter 页面状态，也不直接等于数据库表。

## Rules

1. 跨层字段统一使用 `snake_case`。
2. 枚举值统一使用字符串，不使用数字枚举。
3. 精确时间点使用 ISO 8601 UTC 字符串，例如 `2026-06-06T10:00:00Z`。
4. 本地日期使用 `YYYY-MM-DD` 字符串，例如 `2026-06-06`。
5. 所有跨层调用统一返回 `NativeResult<T>`。
6. `ok = true` 时 `error` 必须为 `null`。
7. `ok = false` 时 `data` 必须为 `null`，且 `error.code` 必须来自 `error_codes.yaml`。
8. `EventResponse` 不直接嵌入 `Reminder`；详情页聚合数据使用 `EventDetailResponse`。
9. `Reminder` 是未来要执行的提醒任务，`Notification` 是投递结果日志，二者不能混用。
10. `Habit` 只描述习惯定义，`HabitCheckIn` 才是完成记录和统计来源。
11. 独立创建 Reminder 必须使用 `CreateReminderRequest` 且包含 `target_id`；嵌入父对象创建流程时使用 `ReminderDraftRequest`。

## Directory

```text
contracts/
├── README.md
├── method_channels.yaml
├── error_codes.yaml
├── enums.yaml
├── common/
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

当前核心闭环优先级为 `common/`、`event/`、`recurrence/`、`reminder/`、`habit/`、`category/`。`notification/`、`search/`、`ai/`、`sync/`、`user/` 先作为稳定协议草案保留，后续实现层必须先更新本目录再落代码。

## Versioning

当前协议版本为 `1`。JSON Schema 使用 Draft 2020-12，并通过 `x-contract-version` 标明协议版本。MethodChannel、错误码、枚举文件也必须保留顶层 `version`。

破坏性变更包括：

- 删除字段。
- 修改字段含义。
- 修改枚举值拼写。
- 修改 MethodChannel 方法名。
- 修改错误码含义。

发生破坏性变更时必须提升协议版本，并在各语言边界层同步处理兼容策略。

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
habit.check_in -> NativeResult<HabitCheckInResponse>
```

## Ownership

新增跨层字段、方法、枚举或错误码时，必须先更新 `contracts/`，再由 Dart、Kotlin、C++、SQLite 或 Backend 做本土化实现。禁止在某一语言层临时发明未声明字段。
