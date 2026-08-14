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
- `storage/calendar_core_storage.yaml` 定义 Calendar Core JSON v2 的兼容、v1 清理和事务规则。
- `*.schema.json` 定义 request、response 和通用返回外壳的 JSON Schema。

本层不放业务流程编排、不放 Android 系统能力实现、不放 C++ 核心领域规则、不放 Flutter 页面状态，也不直接等于数据库表。

## Rules

1. 跨层字段统一使用 `snake_case`。
2. 枚举值统一使用字符串，不使用数字枚举。
3. 精确时间点使用 ISO 8601 UTC 字符串，例如 `2026-06-06T10:00:00Z`。
4. 本地日期使用 `YYYY-MM-DD` 字符串，例如 `2026-06-06`。
5. 不携带 offset 的本地日期时间只允许用于时区解析请求，格式固定为 `YYYY-MM-DDTHH:mm:ss`；它不是 UTC Instant，禁止直接写入 Event。
6. Flutter ↔ Kotlin 和 Kotlin ↔ C++ 使用 `NativeResult<T>`；Flutter ↔ Backend 使用独立的 `ApiResult<T>`，不得混用两种版本域。
7. 两种返回外壳都要求 `ok = true` 时 `error = null`。
8. 两种返回外壳都要求 `ok = false` 时 `data = null`，且 `error.code` 必须来自 `error_codes.yaml`。
9. `EventResponse` 不直接嵌入 `Reminder`；详情页聚合数据使用 `EventDetailResponse`。四个时间字段必须全部出现，未启用的一组显式为 `null`。
10. `Event.status` 只表示整个 Event 或整个重复系列的生命周期；重复日程单次 occurrence 状态使用 `EventOccurrenceStateResponse`。
11. `Reminder` 是未来要执行的提醒任务，`Notification` 是投递结果日志，二者不能混用。
12. `Habit` 只描述习惯定义，`HabitCheckIn` 才是完成记录和统计来源。
13. 独立创建 Reminder 必须使用 `CreateReminderRequest` 且包含 `target_id`；嵌入父对象创建流程时使用 `ReminderDraftRequest`。
14. `CreateReminderRequest` 和 `ReminderDraftRequest` 只能创建 `is_enabled = true` 的新 Reminder。修改已有 Reminder 必须使用 `reminder.update`；后续更新或取消可以使持久化的 `is_enabled` 变为 `false`。
15. Event recurrence 客户端输入固定使用 `EventRecurrenceRuleInput`；Habit 的计划态规则和 Anniversary V1 的专属年度规则都不得被解释为 Event v2 规则。
16. 重复 Event 的 occurrence 和滚动 Reminder 身份只能由 C++ 按 `identity.yaml` 生成；Dart/Kotlin 只透传。
17. Notification 必须走 `reminder.prepare_delivery` / `reminder.finalize_delivery`；v1 的 `notification.create`、`reminder.consume_after_delivery` 和 `reminder.mark_sent` 不属于 v2。
18. `finalize_delivery.error_code` 必须来自 `error_codes.yaml`，且 `failure_class` 必须与该错误码的 `retryable` 元数据一致。
19. Native v2 的 Reminder 主键字段统一为 `reminder_id`；v1 的通用 `id` 不得在 Reminder request/response 或调度游标中继续接受。
20. `event.update.recurrence` 省略表示保留，传对象表示设置或修改；v2 不接受含义不明确的 `null` 拆系操作。
21. `prepare_delivery` 返回 `PreparedNotificationPayload`，其中没有 `opened_at`；Android 收到点击后追加非空 `opened_at`，才形成 EventChannel 使用的 `NotificationTapPayload`。
22. `reminder.mark_scheduled` 必须携带 Kotlin 本次注册所依据的 `expected_remind_at`；C++ 仅在持久化 `remind_at` 仍严格相等时写入 `scheduled`，否则返回可重试的 `REMINDER_SCHEDULE_CONFLICT` 且不得修改 Reminder。
23. `prepared` Notification 的投递内容和 PendingIntent payload 一经返回即冻结。Recovery 只能通过 `resolved_by_recovery_batch_id` 接管原 attempt，或把它终结为 `abandoned`；禁止改写原 `recovery_batch_id` 来伪造新 payload。
24. `plan_recovery` 是唯一可写入 `ReminderStatus.expired` 的 workflow：只处理严格早于 72 小时窗口的 open `pending/scheduled` Reminder，原子禁用并清空 `scheduled_at`；重复 Reminder 同一事务保证未来 successor。
25. occurrence reopen 若遇到同模板的后继滚动 Reminder，必须以 `occurrence_reopened` 暂存后继并恢复原 Reminder；滚动链随后复用确定性 ID，任何时刻同模板最多一条 open Reminder。
26. Anniversary V1 的 `date` 是原始本地日期事实；`recurrence = null` 表示一次性，`anniversary_recurrence_rule_input` 表示 `yearly + interval=1`。年度 month/day 锚点只能来自 `date`，不得在 recurrence 中重复保存。
27. `Anniversary.recurrence_id` 非空时必须指向一条活动且独占的 Anniversary 规则。仍为年度重复的标题/日期更新保留原 ID；一次性切到年度重复时创建规则；年度重复切到一次性时必须在同一 C++ transaction 中解除引用并软删除旧规则。
28. Anniversary countdown 是按请求 IANA timezone 动态计算的 query projection，不持久化或预生成未来 occurrence。`days` 按本地自然日计算，当天为 `0`；公历 2 月 29 日在非闰目标年落到二月最后一天。
29. Anniversary V1 只成功处理 `calendar_type=solar`。输入 `lunar` 必须返回 `ANNIVERSARY_CALENDAR_UNSUPPORTED`；不得固定映射为某个公历月日，也不得返回看似成功但不可计算的空快照。
30. `AnniversaryKind`、`AnniversaryCountMode`、图标、主题和本地化日期/星期文案属于当前 Flutter projection，不进入 Native Contract。Anniversary Reminder 草案也不进入本轮 create/update，直到本地触发时刻、occurrence 身份、幂等和滚动规则完成独立设计。
31. Event、Habit、Anniversary 与 Category 只通过 `category_id` 关联。分类名称和颜色不能作为外键；`SearchIndex.category_name` 只是可重建冗余文本，结构化过滤使用 `category_id/category_ids`。
32. `category.create` 要求显式提交 `name/description/color/icon/sort_order`，其中 nullable 字段也必须出现；C++ Application/Domain 单点负责 UUIDv4、UTC 时间、文本/颜色规范化和默认追加顺序，Flutter/Kotlin 对所有 Schema-valid 值原样转发。`sort_order` 的跨语言精确范围为 `0..9007199254740991`；自动追加已到上界时返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。`category.list` 只返回活动分类，并按 `sort_order(null last) -> created_at -> id` 升序。
33. Category 的账号归属、名称唯一性和系统默认分类尚未冻结。Flutter Fake 的默认项与 owner 文案不进入 Native Contract。`category.list/create`、Category Store 与生产 composition 已在 2026-08-14 完成代码一致性和物理设备重启 smoke，统一标记为 `integrated + active`；未进入公开协议的重命名、删除、恢复、同步、用户归属与默认分类不得据此推断为可用。

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

当前已接入的本地核心协议包括 `common/`、`event/`、`recurrence/`、`reminder/`、`notification/`、`anniversary/` 和 Category create/list。Category 已冻结 Schema、Dart/Kotlin 边界和独立 JSON Storage v2 格式，C++ Domain/Repository/codec/bootstrap、JNI、真实磁盘读写、生产 Flutter composition 与物理设备重启验收均已闭环；对应方法和 Store 统一为 `implementation_status: integrated`、`release_status: active`。`auth/`、`user/` 与 `backend_api.yaml` 是认证和个人资料模块的计划协议；在 Flutter、Kotlin 和 Backend 实现落地前保持 `implementation_status: planned`，调用方不得把它们当作已可用能力。

## Versioning

Native Contract 已设计为 breaking v2，Backend API 继续使用独立的 v1。JSON Schema 使用 Draft 2020-12，并通过 `x-contract-domain`、`x-contract-version` 或独立的 `x-storage-format-version` 标明所属版本。MethodChannel、Backend API、错误码和枚举文件保留顶层 `version`。
`common/native_empty_request.schema.json` 与 `common/native_operation_response.schema.json` 属于 Native v2；未带 `native_` 前缀的同名通用文件继续服务 Backend API v1，禁止跨版本域复用其版本元数据。

局部能力状态必须同时表达“代码是否存在”和“是否可作为发布能力依赖”：`planned` 表示目标层尚无可依赖实现；`implemented_unintegrated` 表示实现代码已经存在，但 Contract 一致性或端到端门禁尚未通过；只有 `integrated` 且对应 `release_status: active` 才表示正式可依赖。`release_status: blocked` 的能力不得因调试入口或底层调用偶然成功而被上层当作已发布功能。

`method_channels.yaml`、`native_calls.yaml`、`identity.yaml` 与 Calendar Core JSON v2 已切换为 `release_status: active`、`implementation_status: integrated`（2026-08-08 激活）。Dart DTO/Gateway、Kotlin validator/bridge、JNI 与 Android 调度均已切换到 v2，并已在真机（realme RMX5100, Android 16 / API 36）完成首轮验证；Anniversary 六条调用与专用 Storage 于 2026-08-10 接续激活并通过真实 JNI 持久化 smoke。验证记录与剩余未验证项见 `docs/develop_record.md`。V1 数据不再保留：C++ bootstrap 在确认目录为 v1 后直接清理，不再创建时间戳归档；`files/local_storage/test_storage_json` 不再作为迁移来源。

| 版本域 | 真相源 | 当前版本 | 兼容策略 |
| --- | --- | --- | --- |
| Native MethodChannel / JNI | `method_channels.yaml`、`native_calls.yaml` | 2（active） | Flutter、Kotlin、JNI、C++ 同一发行版本同步升级；v1/v2 双向拒绝 |
| Backend HTTP API | `backend_api.yaml` | 1 | 正式发布后至少支持 N-1 |
| Flutter 用户资料缓存 | `user/cached_current_user.schema.json` | 1 | 使用连续本地格式迁移，不复用 API 版本 |
| Calendar Core JSON | `storage/calendar_core_storage.yaml` | 2（active） | 不读、不迁移、不保留 v1；确认 v1 后清理，再初始化空 v2 |

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
- 本地 v1 数据不是协议迁移输入，也不再保留；按 Storage Contract 在确认后清理。
- v1 数据不归档、不恢复；回滚到旧版会失去本地数据（已接受）。旧 App 仍禁止打开 v2 目录。
- Backend、用户资料缓存、未来导入/导出和备份各自使用独立版本，不随 Native v2 自动升级。

实施依赖顺序为：领域/Contract 定稿 → C++ Domain、Clock、TZDB、workflow、Repository 与 Storage v2 → JNI/Kotlin contract 与调度 → Dart DTO/Gateway → 同一 APK 全链路验证与激活。该顺序已执行完毕（2026-08-08）；v2 writer 已写入用户正式目录，剩余未验证项（Alarm 到点触发、崩溃 journal 重放、Recovery 废弃分支、OEM 后台限制）记录在 `docs/develop_record.md`。

### v2 公共与内部能力边界

- `event.list_occurrences`、`event_occurrence.*` 与 `event.*_series` 同时出现在 MethodChannel 和 JNI 能力图中。
- `reminder.prepare_delivery`、`reminder.finalize_delivery`、`reminder.plan_recovery` 由 Android 调度服务调用，只出现在 `native_calls.yaml`，不暴露给 Flutter。
- `runtime.initialize(storage_directory, tzdb_directory)` 只出现在 `native_calls.yaml`。目录由 Kotlin 私有解析，Flutter 不得传入文件系统路径。
- `runtime.device_timezone` 只出现在 MethodChannel，由 Kotlin 每次读取 Android 当前系统 IANA timezone，不进入 JNI，也不得长期缓存。
- `runtime.resolve_local_datetime` 与 `runtime.localize_instants` 同时出现在 MethodChannel 和 JNI 能力图中；Flutter 不得用 Dart/设备 offset 代替 C++ 捆绑 TZDB 的解析结果。
- `runtime.localize_instants` 单次最多接收 400 个 UTC Instant，响应严格保留输入顺序与重复项；任一元素无效时整批失败。
- `reminder.reconcile_schedule` 是 Kotlin 本地系统能力编排，可以组合多个 JNI workflow；MethodChannel 与 JNI 方法数量无需一一相等。

### Event recurrence v2

- `recurrence/event_recurrence_rule_input.schema.json` 是 Event v2 唯一创建/更新输入，只接收 `frequency/interval/end_at/count`。
- `recurrence/recurrence_response.schema.json` 是 C++ 派生的不可变 revision，不保存 `target_type/target_id`。
- `recurrence/recurrence_rule.schema.json` 仅保留给尚未实施的 Habit 计划协议，不能被 Event 或 Anniversary 引用。
- `yearly/custom` 保留稳定枚举入口，但 v2 C++ 必须返回 `FEATURE_NOT_IMPLEMENTED`。

### Anniversary V1 integrated contract

- `anniversary.create/update/delete/detail/list/preview_countdown` 是当前 Flutter 原型对应的最小公开能力；六个 MethodChannel 都映射到同名 Kotlin → JNI → C++ call，并保持 `implementation_status: integrated`。
- 领域实体/逻辑集合命名为 `AnniversaryRecurrence` / `anniversary_recurrences`；跨层只使用分离的 `AnniversaryRecurrenceRuleInput` 和 `AnniversaryRecurrenceResponse`，不得把存储记录直接暴露为 DTO。V1 规则只含 ID、`yearly + interval=1` 与存储生命周期时间；`created_at/deleted_at` 不进入当前 response projection。
- create/update 是完整计划而不是 patch：Anniversary 与可选年度规则由单个 C++ workflow 原子写入。`recurrence=null` 明确表示一次性；对象表示年度重复。客户端不提交 `recurrence_id`，由 C++ 创建或保留。
- update 保持年度重复时复用现有活动 `recurrence_id`，包括仅修改标题或原始日期；从一次性切换为年度重复时创建新规则；从年度重复切换为一次性时原子清空引用并软删除旧规则。缺失、已删除或非法规则引用必须显式失败，不能当作一次性返回。
- delete 只定义软删除并返回带非空 `deleted_at` 的 `DeletedAnniversaryResponse`。restore、hard delete、系统预设隐藏/复制均未进入当前 Flutter 闭环。
- create/update/detail/list/preview 必须携带 IANA `timezone`。公开 Dart create/update Gateway 通过既有设备时区 Gateway 显式补入该字段；C++ Clock 先换算该时区的本地今日日期，再以 `Anniversary.date` 动态计算 `AnniversaryCountdownResponse`。`timezone` 只参与本次查询投影，不写入 Anniversary Store；Flutter 只负责把 `target_occurrence_date` 和 `iso_weekday` 本地化为展示文案。不得预生成或持久化未来年度 occurrence。
- create/update 的必填 `timezone` 相对早期 planned 草案属于请求形状变更，但该草案从未激活或形成历史客户端/持久化数据；Dart、Kotlin、JNI 与 C++ 在首次切换为 `integrated` 时同批升级，因此不提升 Native Contract v2，也不创建伪迁移。后续已发布版本再新增必填字段时必须按 breaking change 提升版本。
- list 支持当前领域已存在的 Category/Importance 过滤及 countdown 排序；`pagination` 只承载 `page/page_size/cursor`，`sort_by/sort_direction` 只允许位于 request top-level，缺失时分别使用 `target_occurrence_date/asc`。不提供 keyword search、独立 upcoming/next-occurrence API 或 Flutter kind 过滤。
- `anniversary_summary_response` 与 `anniversary_detail_response` 只返回非删除、公历实体的成功快照。农历请求使用稳定错误返回，不用 `unavailable` 成功值掩盖未实现能力。
- Reminder 仍是独立实体，但本轮 Anniversary Contract 不接受 Reminder draft，也不返回 Reminder aggregate。当前 Flutter “提前几天”输入缺少本地投递时刻，年度提醒也尚未冻结 occurrence identity、唯一键、重试与 reconciliation；这些语义完成独立评审后再以单一 C++ workflow 扩展。
- shared Reminder schema 中既有的 `target_type=anniversary` 目前只保留为计划态扩展边界；在上述门禁完成前，Dart/Kotlin 不得把独立 `reminder.create` 暴露成可用的 Anniversary 提醒绕行路径。
- Anniversary 使用独立的 `anniversaries.json`、`anniversary_recurrences.json` 与 `anniversary_workflow_transactions.json`。专用两 Store journal 不修改 Event/Reminder 既有六 Store journal；合法旧 v2 目录通过增量空 Store 初始化升级，损坏数据必须显式失败。
- 当前 Flutter Fake 中的“周末”和“春节”仅是视觉 fixture：动态“本周末”不保存为 Anniversary，农历春节不属于公历 V1 系统预设。

### Category integrated and active contract

- 当前公开能力只有 `category.list` 与 `category.create`。选择分类不是持久化操作，不新增 `category.select`；Flutter 选择页返回 Category，Event/Anniversary 等请求只提交其 `category_id`。
- Category response 使用分离的传输 DTO，不直接暴露未来 Storage record。新正式 Category ID 为 C++ 生成的规范小写 UUIDv4；创建响应中的 `deleted_at` 必须为 `null`。
- `description` 是可空稳定领域字段；创建请求允许大小写十六进制颜色和 Schema-valid 的前后空白文本。Flutter/Kotlin 只校验结构并原样转发，C++ Application/Domain 是唯一规范化 owner：文本 trim、空白 optional text 变 `null`、颜色转大写。响应颜色暂时可空，以保留早期 Category 草案的读取兼容边界。
- Native Contract v2 已发布过不限制 Event `category_id` 格式的 reader，早期 Flutter 也曾提交非 UUID 硬编码值。因此 Event create/update/response/search 继续把该字段当稳定不透明字符串；本轮不收紧、不重解释历史值。新 Category 返回 UUID 后，自然通过同一字段建立引用。
- `category.list` 使用显式空对象请求与 `CategoryListResponse.items`，不使用分页。返回只包含 `deleted_at = null` 的活动记录，稳定顺序为 `sort_order`（空值最后）、`created_at`、`id`。
- Flutter 默认及 Release 生产 composition 均直接注入 `NativeCategoryRepository`，通过正式 MethodChannel/Kotlin handler/JNI/C++ Category API 访问 Store；不再存在验收开关或 blocked Repository。公开能力仍严格限定为 `category.list` 与 `category.create`。
- Category Storage 已定义为 Calendar Core JSON v2 目录中的独立 `categories.json`，严格根对象为 `storage_version + categories`；持久化记录的九个字段全部显式存在，格式真相源是 `storage/category_store.schema.json`，不复用 Response Schema 充当存储记录。
- Store 快照按 `id` 升序序列化；正式本地记录的 `color/sort_order` 必须非空，create 的空顺序在持久化前物化，因此本地业务 list 按 `sort_order -> created_at -> id` 投影。Response 的 null-last comparator 继续兼容非 Store/早期草案 reader。`sort_order` 在 Request、Response 和 Store 中统一限制为 JSON/IEEE-754 可精确往返的 `0..9007199254740991`；未指定顺序时 C++ workflow 在目录写锁中按活动记录最大值追加，空集合从 `0` 开始，到达上界则返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。
- Category 当前操作只改一个 Store，使用完整快照校验与同目录原子替换，不接入现有两个精确 Store 集合的 journal。任何未来跨 Store Category workflow 必须先新增独立可恢复事务协议。
- Category 与 Event/Habit/Anniversary 是弱引用：缺失或软删除分类不使业务对象不可读，也不得级联清空 `category_id`。Event detail 中，无 ID 返回空 Category；非空 ID 命中活动 Category 时必须返回同 ID 对象；悬空/软删除时返回空对象投影但保留 Event 原 ID。既有非 UUID opaque reference 继续兼容；Category 记录自身只接受新 writer 生成的 UUIDv4。
- `categories.json` 是 Storage v2 的可加性文件，不改变既有 Store codec；旧 v2 目录激活时只可补精确空根，已有文件必须校验且禁止重置。不存在 Category v1 或 Flutter Fake migration，也不创建默认分类 fixture。
- 2026-08-14 已关闭发布前的代码级一致性缺口：Event detail 三态聚合、Kotlin Event Category 校验、安全整数与 C++ 单点规范化已同步；Category 原子写增加持久化 prepared/committed 恢复状态，失败后读取与重建会先恢复旧快照，恢复持续失败则拒绝把 replacement 当作权威；Kotlin 已完整登记并透传 `CATEGORY_SORT_ORDER_EXHAUSTED`。
- 同日物理 Android 16 设备完成隔离 max→null JNI 零写入、正式 Flutter 页面→MethodChannel→Kotlin→JNI→C++→Storage、Event 关联、清除/恢复分类、强停进程和覆盖安装后的重启读取 smoke；Category 因此在同一集成变更中切换为 `integrated + active` 并启用正式生产 composition。重命名、删除、恢复、同步、用户归属和默认分类仍未进入当前公开协议。

### TZDB 实施门禁

Contract v2 固定返回 `tzdb_version = 2026c`。C++ 已 vendored Howard Hinnant `date v3.0.4`（commit `f94b8f36c6180be0021876c4a397a054fe50c6f2`），并关闭运行时下载、平台 TZDB 回退和 Windows timezone 名称映射；依赖证据记录在 `cpp_core/third_party/date/README.excellent-calendar.md`。

### v2 影响矩阵

| 层 | 本轮结果 | 后续实施要求 |
| --- | --- | --- |
| Data Model | v2 领域语义已定稿并同步本轮恢复/竞态规则 | 后续实现必须保持字段、状态机和事务一致 |
| Contract | schema、方法、枚举、错误、身份和 Storage 规则已同步并激活 | 后续协议变更按破坏性变更流程提升版本 |
| Dart | 已切换到 v2 DTO/Gateway，拒绝 v1 与 malformed v2 | 保持契约与真实链路测试一致 |
| Kotlin/JNI | 已切换到 v2 validator/bridge、CAS Alarm acknowledgement 与 prepared attempt 串行仲裁 | Kotlin 只编排系统能力，不复制 C++ 规则 |
| C++ Domain/Boundary | 已接入 APK，Core 测试保持通过 | 后续变更必须同步真机验证 |
| JSON Storage | v2 codec、空目录初始化、journal 重放已激活；v1 确认后直接清理，不再归档 | 补做崩溃场景的 journal 重放真机验证 |
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
