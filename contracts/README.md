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
- `identity.yaml` 定义 Event/Anniversary/Habit occurrence、滚动 Reminder、Anniversary/Habit template 或 action、snooze 和 delivery 的 UUIDv5 namespace、规范化输入和固定测试向量。
- `storage/calendar_core_storage.yaml` 记录已激活的 Calendar Core SQLite v5、v4→v5 原子迁移、数据库事务与完整性规则，以及仅作为 migration source、冻结 payload codec 和 downgrade guard 保留的旧格式兼容规则。
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
23. `prepared` Notification 的投递内容和 PendingIntent payload 一经返回即冻结。普通 Recovery 只能通过 `resolved_by_recovery_batch_id` 接管原 attempt，或把它终结为 `abandoned`；Habit 专属 reconciliation 只能以 Habit 专属原因终结未展示 attempt，且不得伪造 RecoveryBatch 身份。禁止改写原 `recovery_batch_id` 来伪造新 payload。
24. `plan_recovery` 是唯一可写入 `recovery_window_elapsed` 或 Anniversary expiry 的 workflow：只处理它负责的 open `pending/scheduled` Reminder；Habit 明确排除。`habit.reconcile_reminders` 是唯一可写入 `habit_occurrence_elapsed` 的 workflow，只在当地日期跨日后原子禁用并清空调度状态。
25. occurrence reopen 若遇到同模板的后继滚动 Reminder，必须以 `occurrence_reopened` 暂存后继并恢复原 Reminder；滚动链随后复用确定性 ID，任何时刻同模板最多一条 open Reminder。
26. Anniversary V1 的 `date` 是原始本地日期事实；`recurrence = null` 表示一次性，`anniversary_recurrence_rule_input` 表示 `yearly + interval=1`。年度 month/day 锚点只能来自 `date`，不得在 recurrence 中重复保存。
27. `Anniversary.recurrence_id` 非空时必须指向一条活动且独占的 Anniversary 规则。仍为年度重复的标题/日期更新保留原 ID；一次性切到年度重复时创建规则；年度重复切到一次性时必须在同一 C++ transaction 中解除引用并软删除旧规则。
28. Anniversary countdown 是按请求 IANA timezone 动态计算的 query projection，不持久化或预生成未来 occurrence。`days` 按本地自然日计算，当天为 `0`；公历 2 月 29 日在非闰目标年落到二月最后一天。
29. Anniversary V1 只成功处理 `calendar_type=solar`。输入 `lunar` 必须返回 `ANNIVERSARY_CALENDAR_UNSUPPORTED`；不得固定映射为某个公历月日，也不得返回看似成功但不可计算的空快照。
30. `AnniversaryKind`、`AnniversaryCountMode`、图标、主题和本地化日期/星期文案属于 Flutter projection，不进入 Native Contract。Anniversary Reminder R1 使用 `reminder_plan`、`HH:mm`、`follow_device` 和 `popup`；其 occurrence/template/reminder/aggregate identity 只能由 C++ 按 `identity.yaml` 生成。
31. Event、Habit、Anniversary 与 Category 只通过 `category_id` 关联。分类名称和颜色不能作为外键；`SearchIndex.category_name` 只是可重建冗余文本，结构化过滤使用 `category_id/category_ids`。
32. `category.create` 要求显式提交 `name/description/color/icon/sort_order`，其中 nullable 字段也必须出现；C++ Application/Domain 单点负责 UUIDv4、UTC 时间、文本/颜色规范化和默认追加顺序，Flutter/Kotlin 对所有 Schema-valid 值原样转发。`sort_order` 的跨语言精确范围为 `0..9007199254740991`；自动追加已到上界时返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。`category.list` 只返回活动分类，并按 `sort_order(null last) -> created_at -> id` 升序。
33. Category 的账号归属、名称唯一性和系统默认分类尚未冻结。Flutter Fake 的默认项与 owner 文案不进入 Native Contract。`category.list/create`、Category Store 与生产 composition 已在 2026-08-14 完成代码一致性和物理设备重启 smoke，统一标记为 `integrated + active`；未进入公开协议的重命名、删除、恢复、同步、用户归属与默认分类不得据此推断为可用。
34. 成功持久化的普通 Reminder 只能有单一 `["popup"]` 或 `["ring"]`；重复 Reminder 固定为 `["popup"]`。普通 request 的 `methods` 结构只允许一个稳定枚举值，使 `["wechat"]` 能到达领域层返回 `UNSUPPORTED_REMINDER_METHOD`，但空数组、未知值和多 method 在 Contract 边界失败。
35. `ring` 只适用于活动、非全天、非重复 Event。Ring Notification 的 `sent` 必须表示前台控制通知已展示，且声音或振动至少一种真实启动；仅 prepare、仅 Service 启动或仅显示控制通知都不能 finalize `sent`。
36. `ring.stop_active` 只改变 Kotlin 私有的活动会话，不完成 Event、不改写 Reminder/Notification 终态且不保存关闭历史。`ring.complete_item` 必须先成功调用既有 `event.complete`；`ring.snooze_active` 必须逐项调用内部 `reminder.snooze` 并用 per-item result 表达部分失败。
37. snooze 固定 10 分钟且只接受 `source_delivery_id`。ID 为 `UUIDv5(reminder namespace, [source_delivery_id,"snooze",10])`；首次成功时由 C++ Clock 保存 `now + 10min`，任何重放返回同一对象和原 `remind_at`。
38. `ActiveRingItem` 只包含 delivery/reminder/event 身份与时间，不得包含 Event 标题、正文、Reminder message、铃声 URI 或文件路径。`ring.state_changed` 可重复且可能丢失，事件身份是 `(runtime_instance_id, sequence)`；Flutter 必须先订阅再 `ring.get_state`，并结合持久化 `session_revision` 拒绝旧状态。
39. Recovery 的 ring 宽限区间是 `[started_at - 5min, started_at]`：4:59 与恰好 5:00 具备明细资格，5:01 强制进入 popup 摘要。C++ 从持久化 `started_at` 推导边界；Kotlin 不重算。为保持从 JSON v2 迁移的历史记录兼容，`window_overflow_count` 保留原字段并固定等于 `summary_reminder_ids.length`，其计数同时包含超时 ring 与 20 条上限溢出。
40. Anniversary create 中 `reminder_plan` 缺失是唯一旧 writer 兼容入口，明确解释为关闭且空模板；显式 `null` 非法。Update 省略表示保留，传对象整体替换，空 `templates` 删除全部模板，关闭总开关但保留非空模板表示暂停。
41. Anniversary Reminder 使用严格 target-specific 分支：必须携带 `template_key/occurrence_key/occurrence_date/advance_days/local_time/follow_device/fulfillment_delivery_id` 的适用值，并把 Event 专用字段写成 `null`。Event reader/writer 必须把这些 target-specific 字段写成 `null`；Habit 使用下述独立分支，不能冒充 Event 或 Anniversary。
42. `anniversary_catch_up` 是一个真实聚合 popup attempt。其 `covered_reminder_ids` 在 RecoveryBatch 中冻结、唯一且按 UUID 文本升序；所有 covered Reminder 通过同一 `fulfillment_delivery_id` 履约，禁止伪造每成员 attempt。
43. `anniversary.list_occurrences` 使用当地日期半开区间、最多 400 个自然日、每页最多 500 项和绑定查询快照的 opaque cursor。结果按 `(occurrence_date, anniversary_id, occurrence_key)` 升序，无 200 条总量上限。
44. Anniversary mutation 的 NativeResult 失败表示业务数据未保存。成功 response 固定 `data_saved=true`；`pending_permission/pending_reconciliation` 是数据已保存后的平台状态，不能改写为业务保存失败。
45. 共享 `finalize_delivery.timezone` 是可选 additive 字段，不得加入全局 `required`。新 Kotlin writer 统一传当前设备 IANA timezone；C++ 只有在加载 attempt 后确认其为 Anniversary Reminder 或 `anniversary_catch_up` 时才语义必填，缺失返回 `CONTRACT_VALIDATION_FAILED`、非法 ID 返回 `TIMEZONE_ID_INVALID`。首次成功 finalize 用该时区持久化 successor；已提交重放返回原 successor，timezone 不进入 Reminder/delivery/attempt identity；retryable failure 不生成 successor。Event、Ring 与普通 Recovery 的旧 payload 继续合法。
46. Habit V1 是包含首尾的固定期限每日挑战，recurrence 固定 `daily + interval=1 + follow_device`；每个会受当地日期影响的 Habit request 都显式携带当前设备 IANA timezone，C++ 是日期投影与校验 owner。
47. Habit 数量 wire 固定为带 `_hundredths` 后缀的 JSON integer，范围为 `0..9007199254740991`；目标与实际完成量非空时必须大于 0。JSON decimal number 不承载精确业务数量，例如 `1.25` 必须传 `125`。C++ 使用 checked integer 运算，累计或日均超出精确 wire 范围返回 `HABIT_STATISTICS_OVERFLOW`。
48. `habit.check_in` 是按 `(habit_id, check_date)` 的幂等 set/upsert。Flutter 可见的 `habit_check_in_request` 只表达 manual 输入，不接收 `source/occurrence_key/action_id`；Kotlin 将其规范化为内部 `habit_check_in_command_request` 的 manual 分支，只有非导出的通知 action 路径可构造 notification_action 分支。`clear_check_in` 保留 tombstone，后续 set 复活同一逻辑 ID；`missed/absent/upcoming` 只属于查询投影，不得写入 CheckIn。
49. Habit Reminder 使用独立 target-specific 分支，必须携带非空 `template_key/occurrence_key/occurrence_date/local_time/follow_device`，固定 `popup`，并将 Event/Anniversary 不适用字段写成 `null`。修改 `local_time` 必须软删旧 template/chain 并创建新的 UUIDv4 `template_key`；另外以 `(habit_id, occurrence_date)` 跨 template 强制每天最多一次真实展示。当天 sent/prepared 后新配置从下一合法日期生效，尚无 attempt 时可以替换当天 Reminder。
50. `habit.reconcile_reminders` 是最多 100 条一事务、opaque cursor 续跑的 Habit 专属内部 workflow；它不进入普通 72 小时 RecoveryBatch、20 条明细上限或摘要。同日未达标且未占用日级展示槽的 occurrence 可逐条补发一次，次日过期。response 回显 request limit；processed 等于 materialized/expired/cancelled/unchanged 之和且不超过 limit，`has_more=true` 必须至少处理一条。
51. Habit 通知 action 是 C++ 生成的确定性 set-to-done。接收方必须同时验证 `habit_id/check_date/occurrence_key/action_id`，且 `check_date` 必须等于当前当地日期；重复 action 返回同一最终状态。公开 MethodChannel 不得伪造 action source 或 identity。done/skipped 后 clear 仅在该日期跨 template 从未 sent/prepared 时恢复 Reminder。
52. `appearance.get_local/update_local` 是 Kotlin 本机能力，不进入 JNI/C++；只接受预设 token。缺失或损坏持久化值回退 `teal` 并记诊断，未知 wire token 仍严格失败。
53. `habit.list.today_progress` 是不受分页和筛选影响的全局首页聚合：只纳入 today 为 active 的未删除 Habit；done 进入 X/Y，partial 与 absent 只进入 Y，skipped 单列且不进入 Y，upcoming/completed/ended_early 排除。
54. Habit V1 最多 400 个包含首尾的当地自然日；title/description/unit/note 分别最多 80/2000/32/500 个 Unicode code point，list page 最多 100、opaque cursor 最多 512。生命周期 mutation 权限由 `habit/habit_lifecycle_operation_matrix.yaml` 冻结：upcoming 不能 end，最终计划日不能 early-end，completed/ended_early 除 delete 外只读。
55. Calendar View 是 Event/Recurrence/OccurrenceState、Habit/CheckIn、Anniversary/AnniversaryRecurrence 与 Reminder 的只读组合投影，不是领域实体，不新增可写表、缓存事实或 Storage 版本。范围摘要最多 42 个当地自然日，并为请求区间每天恰好返回一个升序项。
56. `calendar.range_summary` 返回 `snapshot_token`；`calendar.list_day_items` 的三个 section 首屏和续页都必须携带该 token。每次查询在一个 SQLite read transaction 内校验所有贡献 Store 的 generation；任何 generation 变化返回 `CALENDAR_SNAPSHOT_EXPIRED`。Flutter 只原子接纳同一 token 的范围与三分组结果，不能混合快照。
57. Calendar cursor 绑定 date、timezone、section、page_size、排序 revision、完整最后排序键和 snapshot token。terminal page 固定 `next_cursor=null`；非终页必须非空并产生严格前进。malformed、query mismatch 与 snapshot expired 使用不同错误码，均不得静默从第一页续接。
58. Calendar Event、Habit 与 Anniversary item 使用 section 判别的强类型 schema。C++ 单点负责当地日重叠、recurrence 展开、daily status、圆点守恒、Reminder 活动态与稳定排序；Flutter/Kotlin 不重算这些规则。Contract 不传“进行中”“待完成”“第 N 周年”等本地化文案，只传枚举、日期、时间和精确数量字段。
59. Search V1 是 Event/Habit/Anniversary/当前 Category 的只读组合查询，不是 `SearchIndex` writer，也不写第二套事实。三组首屏由一个 C++ Search Query Service 在同一 SQLite read snapshot 和同一固定 Clock instant 中产生；Flutter 不得分别查询三类后拼接。
60. Search 关键字最多 128 个 Unicode scalar / 512 UTF-8 bytes。规范化只按冻结 Unicode White_Space 集合 trim、折叠为 U+0020 并切 token；比较只把 ASCII `A-Z` 映射到 `a-z`，不做 Unicode normalization、拼音、语义、错字或完整 case folding。token 使用 AND，可跨允许字段命中。
61. `query_generation` 是 Flutter 的 safe-integer 关联令牌，response 必须原样回显；它不等于 Store generation，也不进入 cursor binding。Search V1 每页固定 20；初始 response 必须恰好返回 requested sections，cursor chain 的累计唯一项、精确 total、has_more、cursor 前进、timezone/evaluated_at/snapshot 必须守恒。`srchcur1.*`/`srchsnap1.*` 由 C++ 每进程 OS-CSPRNG key 的完整 HMAC-SHA-256 认证，采用独立 domain、canonical Base64URL 和 constant-time tag compare；禁止 FNV/Calendar checksum 复用。malformed、query mismatch、expired 分别使用三个错误码。
62. Search Category filter 的三态为：`category_ids=null + include_uncategorized=false` 不限制；空数组 + true 仅未分类；非空 ID 数组可选择是否同时包含未分类。未分类只指目标 `category_id=null`；悬空或软删除弱引用仍是有 ID 的对象。名称匹配和投影只读取当前活动 Category，旧名称不得命中。
63. Search item 按 section 使用三个强类型 Schema。Event 的 `occur_at` 与 `occur_date` 互斥，重复导航必须携带 revision 与 occurrence key；Habit 与 Anniversary 保持 date-only。Event 状态与 completed recurring-series cutoff 分别逐字段等同 Calendar Contract；cutoff 以 timed start instant 或 recurrence timezone 全天日初为 anchor，并严格排除等于/晚于 `completed_at` 的 occurrence。有范围时按 cancelled → cutoff → overlap → 完成开关完成资格过滤，再选距请求 timezone 当地 today 最近 occurrence，open 不优先；无范围的 completed series 选择 cutoff 前最后一个 eligible occurrence。timed 查询窗口以请求 timezone 当地午夜和 TZDB gap/fold 策略映射为 instant 后做半开 overlap，all-day 直接用 civil-date 半开 overlap。C++ 单点负责这些投影、匹配 tier、完成/temporal bucket 与稳定排序；Flutter/Kotlin 不重算。
64. Search history 仅由 Kotlin 通过 `AtomicFile` 保存在 `Context.noBackupFilesDir`，最多 20 个规范化关键字，按 ASCII-insensitive identity 去重并保持最近优先。`replace_local_history` 以 `expected_revision` 原子 compare-and-replace 完整有序列表；只有 `finishWrite` 成功才发布新内存快照。revision 上界的幂等请求零写入成功，变化/修复返回 `SEARCH_HISTORY_STORAGE_FAILED` 并保留原快照。键盘成功查询（含零结果）、历史点击和打开结果记录；失败键盘查询与 debounce 不记录。文件不进入 cloud backup/device transfer。
65. Search V1 不升级 SQLite v5、不新增 table/index/trigger/FTS writer。先以 canonical Store 窄快照、文本预过滤和有界 recurrence 算法执行 1k/10k/50k 性能门禁；失败后另立 Storage v6/SearchIndex/FTS migration 计划，不能在下层实现或集成阶段临时添加索引。

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
├── ring/
├── habit/
├── appearance/
├── category/
├── calendar/
├── ai/
├── sync/
├── user/
├── dated_message/
├── anniversary/
└── search/
```

当前已接入的本地核心协议包括 `common/`、`event/`、`recurrence/`、`reminder/`、`notification/`、`anniversary/`、Habit/Appearance、Ring 和 Category create/list。Calendar View R1 的 Contract、C++/SQLite、Kotlin/JNI、Flutter 与 production composition 已落地并通过主机、Debug、三 ABI、一台 Android 13 设备的隔离 JNI/SQLite 与基础 UI，以及 Release 签名 fail-closed/一次性非生产密钥 APK/AAB 验签；产品负责人于 2026-09-02 明确接受正式生产签名/商店上传、真机时区与 DST、TalkBack、200% 字体/减少动画、强杀恢复、升级回滚/密钥恢复和正式 Release UI 全链作为 `OPEN-CAL-001` 非阻断发布债，`calendar.*` 因此统一为 `implementation_status: integrated`、`release_status: active`。当前仍没有生产密钥签名或商店校验过的正式产物。Search V1 Revision 2 的 Contract、C++/SQLite、Kotlin/JNI/AtomicFile History、Flutter 与 production composition 已落地，并通过主机、Android 13 seeded 三类真实查询、History 强杀恢复、中文 IME/日期流程、旋转及代表设备性能复审；产品负责人于 2026-09-02 接受搜索框 TalkBack 语义和正式签名链为 `OPEN-SEA-001` 非阻断发布债，统一 Search Query 与本地 History 能力已切换为 `integrated + active`。SearchIndex/FTS 仍是 deferred/planned 加速方向。Category 已冻结 Schema、Dart/Kotlin 边界和 Calendar Core SQLite Storage 中的独立表，C++ Domain/Repository/codec/bootstrap、JNI、真实磁盘读写、生产 Flutter composition 与物理设备重启验收均已闭环；对应方法和 Store 统一标记为 `integrated + active`。Ring 与内部 `reminder.snooze` 已完成 C++、Kotlin、Flutter、AlarmManager、前台服务、五分钟安全停止和进程恢复闭环，并在 realme RMX5100 / Android 16（API 36）国产 ROM 通过一期发布验收；经 2026-08-23 明确批准，以该设备验收替代一期完整 API 矩阵，相关公开与内部能力统一为 `integrated + active`。API 24、31、33、34、35 保留为后续兼容验证，不再阻塞一期发布。Habit/Appearance V1 的 Dart、Kotlin/JNI、C++、SQLite v5 和 production composition 已完成实现与集成，并于 2026-08-31 按产品负责人的发布决定统一激活；尚未覆盖的设备场景保留在 `docs/issues/open.md#open-hab-001`，不得描述为已验证通过。`auth/`、`user/` 与 `backend_api.yaml` 是认证和个人资料模块的计划协议；在 Flutter、Kotlin 和 Backend 实现落地前保持 `implementation_status: planned`，调用方不得把它们当作已可用能力。

## Versioning

Native Contract 已设计为 breaking v2，Backend API 继续使用独立的 v1。JSON Schema 使用 Draft 2020-12，并通过 `x-contract-domain`、`x-contract-version` 或独立的 `x-storage-format-version` 标明所属版本。MethodChannel、Backend API、错误码和枚举文件保留顶层 `version`。
`common/native_empty_request.schema.json` 与 `common/native_operation_response.schema.json` 属于 Native v2；未带 `native_` 前缀的同名通用文件继续服务 Backend API v1，禁止跨版本域复用其版本元数据。

局部能力状态必须同时表达“代码是否存在”和“是否可作为发布能力依赖”：`planned` 表示目标层尚无可依赖实现；`implemented_unintegrated` 表示实现代码已经存在，但 Contract 一致性或端到端门禁尚未通过；只有 `integrated` 且对应 `release_status: active` 才表示正式可依赖。`release_status: blocked` 的能力不得因调试入口或底层调用偶然成功而被上层当作已发布功能。

Native Contract v2 的公共外壳保持 active；Calendar Core SQLite Storage v5 已完成冻结 v4 checker、v4→v5 原子迁移、Habit Store/索引/codec metadata 与统一事务接线，当前为 `integrated + active`。Anniversary Reminder R1 的 Flutter、Kotlin/JNI、C++ 与生产存储链已接通，普通到点 Alarm、系统通知正文、持久化 `kind=reminder`、successor、点击去重和完整 Native 更新链已通过 realme Android 13 验证。经产品负责人 2026-08-25 明确批准，相关 MethodChannel/native call 与 `identity.yaml` capability 统一切换为 `implementation_status: integrated`、`release_status: active`；尚未覆盖的 API 24–25、权限、时区/DST、旧 Alarm、重启与长离线设备矩阵作为已接受的发布残余风险继续跟踪，不得描述为已验证通过。Habit V1 则于 2026-08-31 在主机门禁、production JNI/SQLite v5 及已执行实机路径通过后激活；剩余设备矩阵按 `OPEN-HAB-001` 作为明确接受的非阻断发布债。JSON v1/v2/v3 目录只作为 bootstrap 的受支持迁移来源；SQLite 成功接管后，保留 JSON 根只承担诊断与 `storage_version=4` 防降级职责，旧 App 不得继续写入。

| 版本域 | 真相源 | 当前版本 | 兼容策略 |
| --- | --- | --- | --- |
| Native MethodChannel / JNI | `method_channels.yaml`、`native_calls.yaml` | 2（active） | Flutter、Kotlin、JNI、C++ 同一发行版本同步升级；v1/v2 双向拒绝 |
| Backend HTTP API | `backend_api.yaml` | 1 | 正式发布后至少支持 N-1 |
| Flutter 用户资料缓存 | `user/cached_current_user.schema.json` | 1 | 使用连续本地格式迁移，不复用 API 版本 |
| Calendar Core SQLite | `storage/calendar_core_storage.yaml#calendar_core_v5` | 5（integrated / active） | v1/v2/v3 先按冻结链路导入 v4，既有 v4 再通过完整 checker 后以单个 SQLite transaction 追加四个 Habit Store、索引、per-store codec metadata 和 history；保留 JSON 根的 v4 防降级标记，旧 App 不得写入 |

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
- 本地 JSON v1 数据不提升为现代 v3 领域形状；SQLite v4 使用冻结 v1 codec 将 Event、Reminder、Notification 原样导入隔离兼容表，旧 API 行为保持不变。
- 迁移成功后 v1 原记录同时保留在 SQLite 兼容表和带 `storage_version=4` 的 JSON 诊断快照中。任何 pre-v4 JSON App 均禁止写入该目录。
- Backend、用户资料缓存、未来导入/导出和备份各自使用独立版本，不随 Native v2 自动升级。

### Anniversary Reminder R1 Wire 兼容矩阵（Native v2 内部能力 revision）

Native envelope、错误外壳和 `contract_version=2` 不变。R1 是同一 APK 内同步升级的模块能力 revision；Flutter、Kotlin、JNI、C++ 和 SQLite v4 已完成生产接线，当前统一为 `integrated + active`，禁止新旧组件混跑。尚未覆盖的设备矩阵按 2026-08-25 的发布决定作为已接受残余风险继续跟踪。

| Reader / Writer | 旧 Anniversary v2 shape | Reminder R1 shape | 结论 |
| --- | --- | --- | --- |
| 新 C++ reader 读取旧 create | `reminder_plan` 缺失 | 显式 plan | 缺失只在 create 解释为关闭且空模板；可兼容 |
| 新 C++ reader 读取旧 update | `reminder_plan` 缺失 | 显式 replacement | 缺失明确表示保留；可兼容 |
| 旧 Kotlin/C++ reader 读取新 request | 不认识 `reminder_plan`/新方法 | 新字段与方法 | 严格拒绝；不得混跑 |
| 新 Dart/Kotlin reader 读取旧 detail | 无 `reminder_settings/capability` | 新聚合字段必填 | 严格拒绝；同一 APK 必须同步升级 |
| 旧 Dart reader 读取新 public response | 旧 detail 直接作为 data | mutation/detail wrapper | 严格拒绝；同一 APK 必须同步升级 |
| Event/Ring Reminder reader/writer | 无 Anniversary 专用字段 | 专用字段显式 `null` | 升级 writer 后兼容；旧 Store 先由 v2→v3 migration 补全，再导入 SQLite v4 |
| Notification/Recovery reader/writer | 无 aggregate kind/covered groups | target-specific R1 | 必须同步升级并迁移；不可降级 |
| 新 C++ finalize reader 读取 Event/Ring/普通 Recovery 旧 payload | 无 `timezone` | 可选 `timezone` | 继续接受；共享字段不能全局必填 |
| 新 C++ finalize reader 读取 Anniversary payload | 无 `timezone` | 当前 IANA `timezone` | Schema 保持兼容，但加载 attempt 后语义拒绝旧 payload；新 Kotlin writer 必须传入 |
| Anniversary finalize 幂等重放 | 重放无时区投影规则 | 可传与首次不同的当前时区 | 返回已提交 successor，不重新投影且身份不变 |

不提升全局 Native version 的理由是该边界不支持独立部署或滚动混跑，且 `NativeResult` v2 外壳、公共时间/错误语义均未改变；模块 revision 通过同一 APK 的同步构建与 Contract 门禁禁止新旧组件混跑。若未来允许动态组件、跨发行版 native 库或任一旧 reader 与新 writer 混跑，必须提升全局 Native version，而不能复用本例。

### Habit V1 Wire 兼容矩阵（Native v2 integrated / active revision）

Habit 旧 Schema 和两个旧 MethodChannel 入口在首次实现前始终是 `planned`，当时不存在对应 C++ Domain、SQLite 行、JNI/Kotlin handler、Dart DTO/Gateway 或已发布 writer 数据，因此完整 V1 revision 继续使用 Native v2 外壳而未制造伪迁移。Flutter、Kotlin/JNI、C++ 和 SQLite v5 现已在同一 APK 中同步实现、验证并于 2026-08-31 一次性激活。

| Reader / Writer | 旧 planned shape | Habit V1 frozen shape | 结论 |
| --- | --- | --- | --- |
| 旧 Habit 调用方 | 仅 create/check_in 草案，使用含糊 decimal quantity，缺少 timezone、聚合与 occurrence identity | 10 个公开 Habit 方法、11 个内部 call；数量统一为 integer hundredths | 严格拒绝；旧草案从未实现或发布，不造伪迁移 |
| Event/Anniversary Reminder | 已激活的 target-specific 分支 | 新增独立 Habit 分支 | 既有分支形状保持不变；回归夹具必须继续通过 |
| 既有 Event/Anniversary prepare reader | 无 `habit_action_payload` | 非 Habit 时字段仍可省略 | additive compatible |
| 新 Habit prepare reader | 不存在 | Habit 时 action payload 必填且身份一致 | 新组件随同一 APK 接入 |
| 普通 `plan_recovery` | Event/Ring 72 小时与 Anniversary catch-up | 显式排除 Habit | 既有规则不变；Habit 使用独立 cursor workflow |
| 本机 Appearance | 不存在 | 两个 Kotlin-local MethodChannel 方法 | 不进入 JNI、C++ 或云同步 |
| Calendar Core Storage | SQLite v4 active | v5 integrated / active | C++ 先用冻结 v4 checker 验证，再以单事务迁移并由 v5 成为当前 writer；损坏 v4 输入仍须零写入失败 |

Contract validator 入口为 `run_habit_v1_validation.py`，夹具位于 `fixtures/habit/`。它同时校验 Draft 2020-12 schema/ref closure、12 个公开方法、11 个 native call、错误/枚举、`integrated + active` 状态、integer-hundredths 相邻向量、文本/日期/分页上限、今日聚合、生命周期矩阵、日级单展示、reconciliation 正进展、Recovery 隔离、4 个 Habit UUIDv5 向量、冻结 v4 hash、v5 表/索引/per-store codec/migration 原子性及 Event/Reminder additive 兼容形状。共享 Anniversary/Reminder 回归继续由 `run_anniversary_r1_validation.py` 覆盖。

### Calendar View R1 Wire 兼容矩阵（Native v2 integrated / active revision）

Calendar View 在本 revision 前只有 Flutter 占位页，没有 `calendar.*` reader、writer、JNI endpoint、SQLite 行或历史 cursor。R1 因此继续使用 Native v2 外壳，并通过同一 APK 同步升级全部调用方；本次只校准 capability 状态，不改变 wire、Storage 或 revision 常量。

| Reader / Writer | R1 前 | Calendar View R1 | 结论 |
| --- | --- | --- | --- |
| 旧 Flutter/Kotlin/C++ | 不调用、不识别 `calendar.*` | 两个公开方法与两个 internal call | additive；新组件必须同包，不能让新 Flutter 对接旧 Native |
| 既有 Event/Habit/Anniversary reader/writer | 各领域独立 active | Calendar 只读取 typed projection | 既有 wire shape 与 writer 不变，三套共享回归必须通过 |
| Calendar Core SQLite v5 | 现有业务 Store/generation | 同一 read transaction 读取并生成 opaque snapshot token | 无新表、无 writer、无 Storage migration |
| Calendar cursor/snapshot | 不存在 | 仅本地会话中的 opaque `calcur1` / `calsnap1` | 不持久化、不导入导出；App/时区/数据 generation 变化后重建 |
| production capability | 无 Calendar 链 | Contract、四层代码和真实 production composition 已落地；七项发布后矩阵由 `OPEN-CAL-001` 跟踪 | 2026-09-02 产品发布例外后为 `integrated + active`；签名门禁已 fail-closed，但尚无生产密钥/商店正式产物 |

专项 validator 为 `run_calendar_v1_validation.py`，夹具位于 `fixtures/calendar/`；它校验所有 Schema/ref、两个能力映射、错误/枚举、42 天、gap-free summary、三类 typed page、terminal cursor、分页边界、cursor binding 与圆点守恒，并与 Anniversary/Habit validator 共同作为下游启动门禁。

### Search V1 Wire 兼容矩阵（Native v2 / Search Revision 2 / integrated + active）

Search V1 冻结前只有 `event.search` 与未接线的 SearchIndex projection，没有统一 `search.*` reader、JNI endpoint、历史文件或生产 FTS。V1 因此作为 Native v2 additive capability 同包升级，不修改旧 `event.search`，也不触发业务数据 migration。

| Reader / Writer | Search V1 前 | Search V1 | 结论 |
| --- | --- | --- | --- |
| 旧 Flutter/Kotlin/C++ | 不调用、不识别统一 Search | `search.query` + 两个 Kotlin-local history 方法 | additive；新组件必须同包，不能让新 Flutter 对接旧 Native |
| `event.search` | 单 Event 旧 request/response | 原样保留 | 兼容调用方不受影响；统一 Search 不暗改旧排序或 payload |
| Event/Habit/Anniversary/Category | canonical SQLite v5 facts | 只读组合 projection | 不新增字段、writer、表、索引或 Storage version |
| SearchIndex/FTS | 只有 planned 可重建概念 | 性能门禁前仍不启用 | `occur_at/occur_date` 语义补齐不代表 writer、rebuild 或 FTS 已实现 |
| local history | 不存在 | Kotlin AtomicFile format v1 + monotonic revision，位于 noBackupFilesDir | additive local format；天然排除 cloud backup/device transfer，不进入 JNI/C++/SQLite |
| production capability | Search Tab 占位 | Contract、四层实现、同 APK、设备与性能门禁已完成 | 2026-09-02 产品发布例外后为 `integrated + active`；`OPEN-SEA-001` 跟踪搜索框 TalkBack 语义和正式签名链 |

专项 validator 为 `run_search_v1_validation.py`，夹具位于 `fixtures/search/`；Revision 2 的 31 组 fixture 校验 12 个 Search Schema/ref、三条公开方法、唯一 native query、错误/枚举、Unicode 规范化、跨字段 AND、相关度与稳定排序、三类 typed item、Event overlap/status/DST/最近 occurrence、request-response section 守恒、cursor-chain 无重漏与元数据恒定、HMAC tamper/旧进程 key、history revision 上界/CAS 与 NativeResult。下层必须消费同一夹具，不能复制一份漂移的规则。Revision 1 从未投产，已经撤回。

### Calendar Core JSON v1/v2/v3 → SQLite v4 兼容矩阵

| Reader / Writer | JSON v1 | JSON v2 | JSON v3 | SQLite v4 已存在 |
| --- | --- | --- | --- | --- |
| pre-v4 JSON reader/writer | 只可处理尚未迁移且属于自身版本的完整目录 | 同左 | 同左 | 必须拒绝 `storage_version=4` 的保留根；不得忽略 guard、降级或部分写入 |
| v4 bootstrap | 先恢复 v1 journals，以冻结 codec 导入隔离兼容表 | 先恢复全部 v2 prepared journal，再执行已冻结 v2→v3 migration | 严格校验十个实体 Store 与 Category | 校验 application/user version、规范化完整 Schema 定义、metadata、全部 row codec/关系与 `quick_check`；不把 JSON 当作 live data |
| v4 writer | 候选库验证刷盘后持久化 cutover journal；先把全部现存旧 writer 根和必需运行时入口安装并复核为 v4 guard，再发布 SQLite，任一阶段崩溃均前向恢复 | 同左 | 同左 | 只写 `calendar_core.sqlite3`；所有 Repository 与跨 Store workflow 使用同一 SQLite 连接和数据库事务 |
| 回滚旧 App | 不安全且禁止；只能恢复迁移前外部备份或升级 App | 同左 | 同左 | 保留 SQLite 与 guarded JSON，不自动反向迁移，也不能让旧 JSON writer 打开已接管目录 |

迁移后现有 Anniversary 固定 `reminders_enabled=false`、模板集合为空；旧 Reminder/Notification 的新 target-specific 字段按类型补成显式 `null`/空数组，既有 Event、Ring、Recovery、软删除与审计值逐字段保留。具体相邻迁移、journal 和失败恢复规则见 `storage/calendar_core_storage.yaml`。

历史 Native v2 一期的实施依赖顺序为：领域/Contract 定稿 → C++ Domain、Clock、TZDB、workflow、Repository 与 Storage v2 → JNI/Kotlin contract 与调度 → Dart DTO/Gateway → 同一 APK 全链路验证与激活。该阶段于 2026-08-08 完成，并曾由 v2 writer 写入用户正式目录；这些完整 v2 数据现仅是 v4 bootstrap 中冻结 v2→v3 codec 的 migration source。当前 writer 是上述已激活的 SQLite Storage v4，JSON v1/v2/v3 均不再是运行时目标格式。

### v2 公共与内部能力边界

- `event.list_occurrences`、`event_occurrence.*` 与 `event.*_series` 同时出现在 MethodChannel 和 JNI 能力图中。
- `reminder.prepare_delivery`、`reminder.finalize_delivery`、`reminder.plan_recovery` 由 Android 调度服务调用，只出现在 `native_calls.yaml`，不暴露给 Flutter。
- `runtime.initialize(storage_directory, tzdb_directory)` 只出现在 `native_calls.yaml`。目录由 Kotlin 私有解析，Flutter 不得传入文件系统路径。
- `runtime.device_timezone` 只出现在 MethodChannel，由 Kotlin 每次读取 Android 当前系统 IANA timezone，不进入 JNI，也不得长期缓存。
- `runtime.resolve_local_datetime` 与 `runtime.localize_instants` 同时出现在 MethodChannel 和 JNI 能力图中；Flutter 不得用 Dart/设备 offset 代替 C++ 捆绑 TZDB 的解析结果。
- `runtime.localize_instants` 单次最多接收 400 个 UTC Instant，响应严格保留输入顺序与重复项；任一元素无效时整批失败。
- `reminder.reconcile_schedule` 是 Kotlin 本地系统能力编排，可以组合多个 JNI workflow；MethodChannel 与 JNI 方法数量无需一一相等。
- 10 个公开 `habit.*` 方法均有窄 C++ call；mutation 的 C++ commit response 不包含 Android capability，由 Kotlin 完成调度尝试后组装公开 response。额外的 `habit.reconcile_reminders` 只供 Kotlin 系统恢复入口调用，不暴露给 Flutter。
- `appearance.get_local/update_local` 由 Kotlin 本地处理，只出现在 `method_channels.yaml`；它们不得进入 `native_calls.yaml`，也不得把 SharedPreferences 细节暴露给 Flutter。
- `ring.get_state/pick_ringtone/update_settings/test/stop_active` 是 Kotlin 本地平台能力；`ring.snooze_active` 逐项组合内部 `reminder.snooze`，`ring.complete_item` 组合既有 `event.complete`。这些公开方法不要求在 `native_calls.yaml` 一一出现。
- `ring.state_changed` 是独立 EventChannel；允许重复、不能保证无丢失。公开恢复协议固定为“先订阅，再调用 `ring.get_state`”，并用 `runtime_instance_id + sequence + session_revision` 仲裁。

### Ring Contract revision R1（integrated / active）

- 本 revision 冻结 `RingSettings`、`RingCapabilitySnapshot`、`ActiveRingSession`、`ActiveRingItem`、`RingStateSnapshot` 与 `RingStateChangedEvent`，以及七个 `ring.*` 方法、一个 EventChannel 和内部 `reminder.snooze`。C++、Kotlin、Flutter 与 realme RMX5100 / Android 16（API 36）国产 ROM 已在同一 APK 闭环；2026-08-23 已明确批准以该真机验收作为一期发布门禁，相关能力现为 integrated / active。API 24、31、33、34、35 作为后续兼容矩阵继续验证，但不阻塞一期发布。
- Ring Settings 是设备本地平台配置。原始 ringtone URI 只允许保存在 Kotlin 私有、版本化存储中；Flutter 只接收显示名称、可用状态与强提醒开关。URI 失效时 Kotlin 回退默认 Alarm ringtone，并通过 degradation reason 告知 Flutter。
- ActiveRingSession 不是领域真相源。全局最多一个会话/播放器/振动器/控制通知；`prepared -> audible -> quiet_pending` 为公开活动阶段，resolved 通过 `active_session=null` 表达。audible 期间加入 item 不改变当前 generation 的五分钟 deadline；quiet_pending 收到新 ring 才创建新的 audible generation。
- Capability 的 blocking/degradation reason 由 Kotlin 统一计算。全屏 Intent 不可用只降级为高优先级通知；Flutter 禁止复制 SDK 版本判断。
- Recovery 先强制汇总 `remind_at < started_at - 5min` 的 ring，再在其余候选中按既有 `(remind_at, reminder_id)` 降序选择最多 20 条明细。最终明细和摘要仍各自升序投递；摘要 Notification 始终是 popup。

| 读写方/数据 | R1 前 v2 | Ring R1 | 兼容结论 |
| --- | --- | --- | --- |
| 既有普通 Reminder writer | 只会成功写 `["popup"]` | 继续接受 | 双向兼容 |
| 既有理论 Schema 调用方 | 曾可提交多 method/`wechat`，但 integrated C++ 已拒绝且不会持久化 | 多 method 在 Schema 拒绝；单一 `wechat` 稳定返回 unsupported | 无历史成功数据；属于对真实 active 行为的收口 |
| 旧 Flutter/Kotlin/C++ APK | 不理解 ring 会话或 ring Storage 值 | 不接收新 ring payload | 必须同一发行版本同步升级，不做滚动混跑 |
| Calendar Core JSON v2 旧数据 | Reminder/Notification 正式 writer 只保存 popup；RecoveryBatch 保持既有字段 | Ring R1 writer 可保存普通 ring；Recovery 复用既有记录形状 | Ring R1 本身无额外数据迁移；该历史 v2 目录现仅经冻结 v2→v3 codec 进入 SQLite v4，不表示 v2 writer 仍 active |
| Ring Method/EventChannel | 不存在 | additive，integrated / active | 旧调用方不调用；新调用方随同一 APK 使用冻结的 v2 协议 |

Compatibility fixture 位于 `fixtures/ring/`。4:59、5:00、5:01 三个 Recovery golden 固定边界；`identity.yaml` 固定 ring delivery 与 snoozed Reminder UUIDv5 向量。

### Event recurrence v2

- `recurrence/event_recurrence_rule_input.schema.json` 是 Event v2 唯一创建/更新输入，只接收 `frequency/interval/end_at/count`。
- `recurrence/recurrence_response.schema.json` 是 C++ 派生的不可变 revision，不保存 `target_type/target_id`。
- Habit V1 只使用 `habit/habit_recurrence_rule_input.schema.json` 与 `habit/habit_recurrence_response.schema.json`；已经删除的通用 planned `recurrence_rule.schema.json` 不得恢复或跨领域复用。
- `yearly/custom` 保留稳定枚举入口，但 v2 C++ 必须返回 `FEATURE_NOT_IMPLEMENTED`。

### Habit V1 Contract revision（frozen / integrated / active）

- `Habit`、`HabitRecurrence`、`HabitCheckIn` 和 `HabitReminderTemplate` 的事实、聚合、请求与响应已经分离；response 不暴露 SQLite 行，list/detail 直接返回 C++ 计算的生命周期、今日状态、统计、进度和稳定排序投影，list 另含不受分页影响的 `today_progress`。
- create/update/end/delete/check-in/clear/set-reminder 需要数据库 logical commit 与 Android side effect 分离：C++ 成功固定 `data_saved=true`，Kotlin 用 capability 表达 exact、approximate、待权限或待 reconcile。平台失败不得伪装成领域未保存。
- exact 优先、无 exact 权限时允许 approximate 并显式标注降级；通知权限拒绝保存业务数据并进入待权限。全局 `OPEN-NOT-002` 仍跟踪其他 Reminder 产品策略，不回滚本 revision 已冻结的 Habit V1 行为。
- 所有 date-sensitive request 显式传 IANA timezone；local date 是稳定事实，不转换成 UTC 午夜。未知 enum/token、缺失 nullable 字段、decimal/非整数/越界数量都必须在不可信边界严格失败。
- Contract、C++、Kotlin/JNI、Flutter、Storage v5 与 production composition 已落地，运行时 Fake 已移除，主机门禁和本轮明确执行的实机路径通过；相关 capability 已于 2026-08-31 切换为 `integrated + active`。产品负责人接受的剩余真机矩阵只作为 `OPEN-HAB-001` 发布后验证债，不得反向解释为已验证通过。

### Anniversary V1 base + Reminder R1 integrated / active

- `anniversary.create/update/delete/detail/list/preview_countdown/set_reminders_enabled/list_occurrences` 是当前八个公开能力；MethodChannel 已映射到 Kotlin 编排及同名 Kotlin → JNI → C++ call。其实现状态与发布状态统一为 `integrated + active`。未完成设备矩阵由产品负责人按上述发布例外接受，不计入已验证范围。
- 领域实体/逻辑集合命名为 `AnniversaryRecurrence` / `anniversary_recurrences`；跨层只使用分离的 `AnniversaryRecurrenceRuleInput` 和 `AnniversaryRecurrenceResponse`，不得把存储记录直接暴露为 DTO。V1 规则只含 ID、`yearly + interval=1` 与存储生命周期时间；`created_at/deleted_at` 不进入当前 response projection。
- create/update 是完整计划而不是 patch：Anniversary 与可选年度规则由单个 C++ workflow 原子写入。`recurrence=null` 明确表示一次性；对象表示年度重复。客户端不提交 `recurrence_id`，由 C++ 创建或保留。
- update 保持年度重复时复用现有活动 `recurrence_id`，包括仅修改标题或原始日期；从一次性切换为年度重复时创建新规则；从年度重复切换为一次性时原子清空引用并软删除旧规则。缺失、已删除或非法规则引用必须显式失败，不能当作一次性返回。
- delete 只定义软删除并返回带非空 `deleted_at` 的 `DeletedAnniversaryResponse`。restore、hard delete、系统预设隐藏/复制均未进入当前 Flutter 闭环。
- create/update/detail/list/preview 必须携带 IANA `timezone`。公开 Dart create/update Gateway 通过既有设备时区 Gateway 显式补入该字段；C++ Clock 先换算该时区的本地今日日期，再以 `Anniversary.date` 动态计算 `AnniversaryCountdownResponse`。`timezone` 只参与本次查询投影，不写入 Anniversary Store；Flutter 只负责把 `target_occurrence_date` 和 `iso_weekday` 本地化为展示文案。不得预生成或持久化未来年度 occurrence。
- create/update 的必填 `timezone` 相对早期 planned 草案属于请求形状变更，但该草案从未激活或形成历史客户端/持久化数据；Dart、Kotlin、JNI 与 C++ 在首次切换为 `integrated` 时同批升级，因此不提升 Native Contract v2，也不创建伪迁移。后续已发布版本再新增必填字段时必须按 breaking change 提升版本。
- list 支持当前领域已存在的 Category/Importance 过滤及 countdown 排序；`pagination` 只承载 `page/page_size/cursor`，`sort_by/sort_direction` 只允许位于 request top-level，缺失时分别使用 `target_occurrence_date/asc`。不提供 keyword search、独立 upcoming/next-occurrence API 或 Flutter kind 过滤。
- `anniversary_summary_response` 与 `anniversary_detail_response` 只返回非删除、公历实体的成功快照。农历请求使用稳定错误返回，不用 `unavailable` 成功值掩盖未实现能力。
- Reminder 继续作为独立实体和调度任务真相源。Anniversary create/update 接受强类型 `reminder_plan`，detail 返回提醒设置与调度 capability；`anniversary.set_reminders_enabled` 和 `anniversary.list_occurrences` 已进入生产链。occurrence、template、rolling Reminder 和 catch-up delivery 身份由 `identity.yaml` 冻结并只由 C++ 生成。
- `anniversary.update` 是带乐观并发控制的完整 replacement：调用方必须原样回传详情快照中的 `expected_updated_at`；C++ 在同一逻辑事务内比较，失配返回 `ANNIVERSARY_UPDATE_CONFLICT` 且零写入。成功更新必须产生不同的 `updated_at` 令牌，即使两个提交落在同一墙上时钟秒内。
- Anniversary、Recurrence、Template、Reminder、Notification 和 Recovery 的共享写入已接入 Calendar Core SQLite v4 数据库事务；合法 v2 目录先通过连续、无损、可恢复的 v2→v3 migration，再与原生 v3 一样事务导入当前格式，损坏数据必须显式失败。
- 当前 Flutter Fake 中的“周末”和“春节”仅是视觉 fixture：动态“本周末”不保存为 Anniversary，农历春节不属于公历 V1 系统预设。

### Category integrated and active contract

- 当前公开能力只有 `category.list` 与 `category.create`。选择分类不是持久化操作，不新增 `category.select`；Flutter 选择页返回 Category，Event/Anniversary 等请求只提交其 `category_id`。
- Category response 使用分离的传输 DTO，不直接暴露未来 Storage record。新正式 Category ID 为 C++ 生成的规范小写 UUIDv4；创建响应中的 `deleted_at` 必须为 `null`。
- `description` 是可空稳定领域字段；创建请求允许大小写十六进制颜色和 Schema-valid 的前后空白文本。Flutter/Kotlin 只校验结构并原样转发，C++ Application/Domain 是唯一规范化 owner：文本 trim、空白 optional text 变 `null`、颜色转大写。响应颜色暂时可空，以保留早期 Category 草案的读取兼容边界。
- Native Contract v2 已发布过不限制 Event `category_id` 格式的 reader，早期 Flutter 也曾提交非 UUID 硬编码值。因此 Event create/update/response/search 继续把该字段当稳定不透明字符串；本轮不收紧、不重解释历史值。新 Category 返回 UUID 后，自然通过同一字段建立引用。
- `category.list` 使用显式空对象请求与 `CategoryListResponse.items`，不使用分页。返回只包含 `deleted_at = null` 的活动记录，稳定顺序为 `sort_order`（空值最后）、`created_at`、`id`。
- Flutter 默认及 Release 生产 composition 均直接注入 `NativeCategoryRepository`，通过正式 MethodChannel/Kotlin handler/JNI/C++ Category API 访问 Store；不再存在验收开关或 blocked Repository。公开能力仍严格限定为 `category.list` 与 `category.create`。
- Category Storage 当前是 Calendar Core SQLite v4 的独立 `categories` 表；`payload_json` 继续由冻结 v3 九字段存储 codec 严格编解码，SQLite 同时维护主键、稳定位置、活动分类排序索引与事务。当前真相源是 `storage/calendar_core_storage.yaml` 的 `calendar_core_v4`；`storage/category_store.schema.json` 仅保留 v2 迁移源形状，不复用 Response Schema 充当存储记录。
- Store 快照按 `id` 升序序列化；正式本地记录的 `color/sort_order` 必须非空，create 的空顺序在持久化前物化，因此本地业务 list 按 `sort_order -> created_at -> id` 投影。Response 的 null-last comparator 继续兼容非 Store/早期草案 reader。`sort_order` 在 Request、Response 和 Store 中统一限制为 JSON/IEEE-754 可精确往返的 `0..9007199254740991`；未指定顺序时 C++ workflow 在同一 SQLite 事务中按活动记录最大值追加，空集合从 `0` 开始，到达上界则返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。
- Category 当前操作只改一个 SQLite 表，但仍通过完整快照 codec 与领域校验保证语义；写入和 generation 更新使用单个数据库事务。任何未来跨 Store Category workflow 必须复用 Storage v4 数据库事务与既有窄 Repository port。
- Category 与 Event/Habit/Anniversary 是弱引用：缺失或软删除分类不使业务对象不可读，也不得级联清空 `category_id`。Event detail 中，无 ID 返回空 Category；非空 ID 命中活动 Category 时必须返回同 ID 对象；悬空/软删除时返回空对象投影但保留 Event 原 ID。既有非 UUID opaque reference 继续兼容；Category 记录自身只接受新 writer 生成的 UUIDv4。
- `categories.json` 在历史 Storage v2 中是可加性文件；完整 v2 目录作为 migration source 时，缺失文件只可补精确空根，已有文件必须校验且禁止重置。v2→v3 与 v3→SQLite v4 迁移逐字段保留 Category；当前 writer 只写 SQLite，JSON 根仅保留并标记 v4 guard。不存在 Category v1 或 Flutter Fake migration，也不创建默认分类 fixture。
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
| JSON Storage（历史） | v1/v2/v3 codec 与 journal recovery 仅作为 SQLite v4 migration source；迁移成功后保留记录并写 v4 guard | 禁止恢复为 live writer |
| SQLite Storage | v4 schema、Repository adapter、统一事务、完整性校验和 v1/v2/v3 migration 已激活 | FTS 与未来 schema 变更必须独立设计版本化迁移 |
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
habit.check_in -> NativeResult<HabitCheckInMutationResponse>
```

## Backend API Result

Backend HTTPS 接口返回：

```text
ApiResult<T>
```

`ApiResult` 来自 `common/api_result.schema.json`，`ApiError` 来自 `common/api_error.schema.json`，具体 `T`、鉴权、HTTP 路径和允许错误码由 `backend_api.yaml` 声明。Backend 错误只能返回面向客户端的安全消息、字段错误、重试间隔和类型化上下文，不得返回堆栈、数据库异常、Token、密码或验证凭证。

忘记密码申请必须对已注册与未注册邮箱返回相同的成功结构。网络断开和请求超时属于 Flutter transport failure，不得伪装成 Backend 业务错误码。

所有已声明端点对一切应用层结果统一返回 HTTP 200 + `ApiResult` 信封，包括声明路径上的认证失败（信封内 `API_UNAUTHENTICATED` / `AUTH_SESSION_EXPIRED` / `API_FORBIDDEN`）；无有效 `ApiResult` 信封的非 200 响应属于传输/协议失败，只能进入 Flutter 网络层错误路径。限流重试信号只使用 `ApiError.retry_after_seconds`，不定义 `Retry-After` 头语义。

## Authentication Boundaries

- 登录、注册、资料、密码、邮箱和头像请求由 Flutter 直接调用 Backend，不经过 Kotlin 或 C++。
- MethodChannel 只声明 `auth.refresh_token.store/read/delete/exists`，由 Kotlin 本地安全存储实现，不进入 `native_calls.yaml`。
- Access Token 只保存在 Flutter 内存；Refresh Token 只允许出现在 Token 响应、刷新/退出请求和敏感 MethodChannel schema 中。
- `CurrentUserResponse` 与 `CachedCurrentUser` 明确禁止密码、Token、验证 Challenge 和对象存储内部键。
- 尚未验证的注册账号允许通过 `auth.registration.email.update` 在激活前更正登录邮箱（返回新 Challenge）。该端点是公开端点，但必须携带注册时设置的密码作为所有权证明，`account_id` 单独出现不构成授权凭证；密码校验失败返回 `AUTH_CURRENT_PASSWORD_INVALID`。已激活账号的邮箱变更必须走登录态 `auth.email_change.request/confirm` 流程，两条路径不得混用。
- `AUTH_EMAIL_UNVERIFIED` 只由 `auth.login` 返回，且 Schema 强制其 `context.verification_challenge` 非空必填（`challenge_id` + `account_id` + 掩码邮箱 + 过期与重发时间），保证客户端总能继续验证、重发或更正邮箱；后端不得返回不带上下文或 `context=null` 的该错误码。

## Ownership

新增跨层字段、方法、枚举或错误码时，必须先更新 `contracts/`，再由 Dart、Kotlin、C++、SQLite 或 Backend 做本土化实现。禁止在某一语言层临时发明未声明字段。
