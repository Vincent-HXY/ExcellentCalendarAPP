# Excellent Calendar 数据结构模型（Native Contract v2）

> 本文档是本地核心领域语义的真相源。Contract 使用 `snake_case`，本文领域字段使用 `camelCase`；两者的语义、可空性和时间单位必须一一对应。

## 通用约定

- 随机实体 ID 使用 UUIDv4；需要跨重试保持稳定的 occurrence、滚动 Reminder 和 delivery ID 使用 Contract v2 指定的 UUIDv5 算法。
- `createdAt`、`updatedAt`、`deletedAt`、完成、取消、恢复和投递时间均为 ISO 8601 UTC Instant，序列化时必须带 `Z`。
- 参与 recurrence/occurrence 身份的 Event 计划 `startAt/endAt` 固定到整秒，并序列化为 `YYYY-MM-DDTHH:mm:ssZ`；禁止 offset 或小数秒造成跨语言规范化分歧。
- `date` 使用 `YYYY-MM-DD` 本地日期，不得转换成 UTC 午夜保存。
- 普通时间区间和全天日期区间统一使用半开区间 `[start, end)`。
- `timezone` 使用由捆绑 TZDB 校验的 IANA timezone ID；不得保存 `CST` 等缩写或仅保存固定 offset。
- `source`：数据来源，例如 `manual`、`ai_extraction`、`sync`、`import`。
- 缺失字段、显式 `null`、空字符串与空数组含义不同；边界层不得用默认值掩盖 malformed data。

## 当前阶段约定

- 当前正式本地持久化仍是 JSON；SQLite 是后续目标，不与 JSON 同时作为可写真相源。
- Calendar Core JSON Storage format 升级为 `2`。v1 不读取、不迁移、不保留；首次切换只允许在确认目录属于 v1 后清理该目录，再初始化空 v2；确认或初始化失败必须停止初始化且不得删除任何数据。
- Native Contract v2 是一次协调发布的 breaking change，已于 2026-08-08 作为同一发行版本激活。Dart DTO/Gateway、Kotlin validator/bridge、JNI、Android 调度与 JSON Storage v2 均已切换，真机验证记录见 `docs/develop_record.md`。
- 本地能力优先，AI、云端同步、云端投送暂时不做完整实现。
- `AIExtraction`、`SyncOperation` 等模型先作为未来能力预留，字段可先保持文档级设计。
- 用户认证与个人资料由可选 Cloud Backend 作为真相源；本地只缓存可公开展示的当前用户资料，并由 Android 安全保存 Refresh Token。
- `Reminder` 作为独立实体保存，不嵌入 `Event`、`Habit`、`Anniversary`。
- 一个 `Event`、`Habit` 或 `Anniversary` 可以关联多条 `Reminder`。业务上可以理解为“提醒时间列表”，存储上是多条提醒记录。
- 本轮 occurrence 状态和滚动 Reminder 仍只定义 Event 闭环。Anniversary V1 使用本文件独立定义的 `AnniversaryRecurrence` 年度规则，不能复用 Event v2 的 revision/UTC 锚点语义；Habit 重复规则与 Anniversary Reminder 仍为计划态。

## 时区解析与运行时门禁

- C++ Domain 只依赖抽象端口 `LocalTimeResolver`；基础设施使用 `TzdbLocalTimeResolver` 实现 IANA ID 校验、UTC→本地、以及本地→UTC 解析。Dart/Kotlin 不得自行展开 recurrence 或重新计算 occurrence 身份。
- Daily/Weekly/Monthly 必须先在 Event 原时区做本地日历运算，再解析 UTC，禁止用固定 24 小时或固定 7×24 小时累加替代日历语义。
- 本地时间落入 DST gap 时移动到 gap 后第一个合法 Instant；落入 fold 时选择较早 Instant。`occurrenceKey` 仍使用解析前的原始计划本地值，因此 TZDB 解析策略不会改变身份。
- 定时 Event 的本地开始与本地结束分别推进、分别解析，以保持 wall-clock 起止时间。写入前还必须验证原始本地区间为正，不能只验证解析后的 UTC 顺序。
- Flutter 创建定时 Event 前必须调用 `runtime.resolve_local_datetime`，把严格整秒本地日期时间 `YYYY-MM-DDTHH:mm:ss` 与 IANA timezone 解析为 UTC Instant。响应使用 `exact`、`gap_shifted`、`fold_earlier` 明确解析分支，并同时返回实际采用的本地日期时间；Flutter 不得用设备当前 offset 自行换算。
- Flutter 展示定时 Event 或 occurrence 时必须按 Event 原始 timezone 调用批量 `runtime.localize_instants`。单批最多 400 个 UTC Instant，结果保留输入顺序和重复项，任一输入非法则整批失败；全天 Event 继续直接使用本地 date，不进入该接口。
- `runtime.device_timezone` 由 Kotlin 在每次调用时读取 Android 当前系统 IANA timezone。Flutter 在创建页进入、恢复前台或提交前可以重新读取，不能把进程启动时的值视为永久不变；该方法只报告设备默认时区，不覆盖 Event 已保存的原始 timezone。
- Windows 测试与 Android 发行包必须使用同一份捆绑 IANA tzdata 2026c，禁止运行时下载或回退到平台自带、版本未知的时区数据。
- `runtime.initialize(storage_directory, tzdb_directory)` 必须先完成 Storage 恢复和 TZDB 完整性/版本校验。TZDB 缺失、损坏、版本错误或 IANA ID 无效时初始化失败，失败进程不得接受 Event 写入。
- C++ 已固定 Howard Hinnant `date v3.0.4`（commit `f94b8f36c6180be0021876c4a397a054fe50c6f2`）与捆绑 TZDB 2026c；版本证据在 `cpp_core/third_party/date/README.excellent-calendar.md`。

## 模型职责总览

| 模型 | 当前阶段用途 | 数据性质 | 是否本地优先需要 |
| --- | --- | --- | --- |
| `Event` | 保存日程本身，例如会议、临时事项、规律事项 | 主业务数据 | 是 |
| `EventOccurrenceState` | 保存重复日程某一次 occurrence 的完成、跳过、取消或重开状态 | 稀疏状态记录 | 是 |
| `Habit` | 保存习惯定义，例如每天阅读、每周运动 | 主业务数据 | 是 |
| `HabitCheckIn` | 保存习惯每天是否完成、完成次数和打卡时间 | 行为记录 | 是 |
| `Reminder` | 保存未来需要触发的提醒任务 | 调度任务 | 是 |
| `Notification` | 保存提醒触发后的投递结果 | 投递日志 | 是 |
| `Category` | 保存分类、颜色和排序 | 配置数据 | 是 |
| `Recurrence` | 保存 Event 重复规则的不可变 revision | 规则版本数据 | 是 |
| `ReminderRecoveryBatch` | 保存一次 72 小时恢复计划、摘要范围和幂等状态 | 恢复工作流数据 | 是 |
| `SearchIndex` | 保存搜索用的冗余文本 | 索引数据 | 可以后置 |
| `AIExtraction` | 保存 AI 从文本、图片中解析出的候选结果 | 未来预留 | 暂缓实现 |
| `SyncOperation` | 保存本地与云端同步操作记录 | 未来预留 | 暂缓实现 |
| `UserAccount` | 保存邮箱、验证状态和账号生命周期 | 云端账号事实 | Backend |
| `PasswordCredential` | 保存不可逆密码哈希和修改时间 | 云端敏感凭证 | Backend-only |
| `UserProfile` | 保存用户名、昵称和头像引用 | 云端个人资料 | Backend |
| `UserPreferences` | 保存语言、时区和用户级设置 | 用户配置 | Backend + 本地缓存 |
| `UserSyncState` | 保存同步游标和最近同步时间 | 同步内部状态 | 后续同步阶段 |
| `UserAvatarAsset` | 保存头像对象存储元数据 | 云端媒体资产 | Backend |
| `UserSession` | 保存一个设备登录会话的生命周期 | 云端安全状态 | Backend-only |
| `RefreshTokenGrant` | 保存 Refresh Token 轮换链的哈希记录 | 云端敏感凭证 | Backend-only |
| `EmailActionChallenge` | 保存邮箱验证、改邮箱和密码重置挑战 | 云端安全状态 | Backend-only |
| `EmailChangeRequest` | 保存新邮箱验证前的临时变更申请 | 云端安全状态 | Backend-only |
| `UserAgreementAcceptance` | 保存用户协议版本和接受时间 | 云端审计事实 | Backend-only |
| `DatedMessage` | 保存指定日期投送给用户的消息 | 未来预留 | 暂缓实现 |
| `Anniversary` | 保存生日、纪念日等年度事件 | 主业务数据 | 是 |

## 枚举定义

### ReminderMethod

提醒方式。

| 值 | 说明 |
| --- | --- |
| `ring` | 响铃 |
| `popup` | 弹窗 |
| `wechat` | 微信提醒 |

### Importance

重要性。

| 值 | 说明 |
| --- | --- |
| `unimportant_noturgent` | 不重要不紧急 |
| `important_noturgent` | 重要不紧急 |
| `unimportant_urgent` | 不重要紧急 |
| `important_urgent` | 重要且紧急 |

### EventStatus

整个日程或整个重复系列的生命周期状态。

| 值 | 说明 |
| --- | --- |
| `active` | 正常存在，未完成或仍在进行 |
| `completed` | 单次日程已完成，或重复系列彻底结束 |
| `cancelled` | 整个日程或整个重复系列取消 |
| `archived` | 归档，不参与普通列表展示 |

注意：`EventStatus` 不包含 `today_completed`、`skipped`、`overdue`。它们不是整个 Event 的稳定状态。

### EventOccurrenceStatus

重复日程某一次 occurrence 的状态。

| 值 | 说明 |
| --- | --- |
| `scheduled` | 曾被用户操作后又重新打开，恢复为计划状态 |
| `completed` | 这一轮已完成 |
| `skipped` | 这一轮被用户跳过 |
| `cancelled` | 这一轮被取消 |

未被用户操作的 occurrence 不创建状态记录；其 `pending`、`in_progress`、`overdue` 等展示状态根据当前时间动态计算。`scheduled` 只出现在已存在且后来被 reopen 的稀疏状态记录中。

### RecurrenceFrequency

重复频率。

| 值 | 说明 |
| --- | --- |
| `daily` | 每天 |
| `weekly` | 每周 |
| `monthly` | 每月 |
| `yearly` | 每年 |
| `custom` | 自定义 |

### NotificationStatus

通知投递状态。`Notification` 不是提醒扫描的主表，而是一次提醒被系统、微信或应用内渠道投递后的记录。

| 值 | 说明 |
| --- | --- |
| `prepared` | 已由 C++ 创建投递 attempt，等待 Kotlin 调用系统投递 |
| `sent` | 已投递 |
| `failed` | 本次 attempt 已失败；是否重试由 `failureClass` 决定 |
| `abandoned` | Recovery 已原子废弃该 attempt；Android 必须取消旧 delivery tag，旧 attempt 不再允许 finalize |

### ReminderStatus

提醒任务状态。提醒扫描只需要关注 `Reminder` 表中启用且未完成的记录。

| 值 | 说明 |
| --- | --- |
| `pending` | 待调度，尚未注册到系统闹钟 |
| `scheduled` | 已被当前 Dispatcher Alarm 的触发时刻覆盖，不表示一条独立系统 Alarm |
| `sent` | 已触发或已发送 |
| `failed` | 不可重试的永久失败 |
| `cancelled` | 已取消 |
| `expired` | 已物化 Reminder 严格早于恢复窗口，未补发并保留为终结历史 |

`failed` 只表示不可重试的永久失败。可重试投递失败只写入 `Notification` attempt，当前 `Reminder` 保持 `pending`。`expired` 只能由 `planRecovery` 在同一恢复事务中写入：对象必须启用、未删除、处于 `pending/scheduled`，且 `remindAt < windowStartAt`；恰好位于 72 小时边界仍属于恢复窗口。

### ReminderCancellationReason

| 值 | 可恢复 | 说明 |
| --- | --- | --- |
| `user_cancelled` | 否 | 用户直接取消普通单次 Reminder |
| `event_completed` | 是 | 普通单次 Event 完成后自动取消 |
| `occurrence_completed` | 是 | 某次 occurrence 完成 |
| `occurrence_skipped` | 是 | 某次 occurrence 跳过 |
| `occurrence_cancelled` | 是 | 某次 occurrence 取消 |
| `occurrence_reopened` | 仅滚动链 | 较早 occurrence reopen 时，暂存同模板的后继滚动 Reminder |
| `series_completed` | 是 | 整个重复系列完成 |
| `series_cancelled` | 否 | 整个重复系列取消 |
| `series_deleted` | 否 | 整个重复系列软删除 |
| `series_updated` | 否 | 新 revision 替换旧 revision |

恢复仅适用于 `remindAt > reopenedAt` 的同一条 Reminder；不得生成新 ID，也不执行 72 小时补发。

`occurrence_reopened` 不能由普通 `reminder.enable` 恢复。原 occurrence 再次终结，或其 Reminder 成功投递/永久失败时，滚动 workflow 仅在该后继仍在未来时恢复同一确定性 ID；已经过去则保留取消审计并寻找首个未来 occurrence。系列更新、完成、取消或删除可以用相应系列原因覆盖它。

### ReminderExpirationReason

| 值 | 说明 |
| --- | --- |
| `recovery_window_elapsed` | `planRecovery` 判定已物化 Reminder 严格早于 72 小时恢复窗口 |

### NotificationKind

| 值 | 说明 |
| --- | --- |
| `reminder` | 某条 Reminder 的某个渠道投递 |
| `recovery_summary` | 一次恢复批次的聚合摘要投递 |

### NotificationFailureClass

| 值 | 说明 |
| --- | --- |
| `retryable` | 允许使用同一 `deliveryId` 创建新的 attempt；Reminder 保持 `pending` |
| `permanent` | 当前 Reminder 进入 `failed`；重复 Reminder 同事务创建 successor |

### DeliveryAbandonReason

| 值 | 说明 |
| --- | --- |
| `recovery_window_elapsed` | attempt 对应 Reminder 已严格落到 72 小时窗口外并进入 `expired` |
| `recovery_summary_superseded` | attempt 对应 Reminder 改由当前恢复摘要覆盖 |

### PreparedAttemptRecoveryResolution

| 值 | 说明 |
| --- | --- |
| `adopted_detail` | 保留原 frozen attempt，由当前恢复批次接管为明细投递 |
| `abandoned_to_summary` | 废弃原 attempt，改由恢复摘要投递 |
| `abandoned_outside_window` | 废弃原 attempt，Reminder 因窗口已过进入 `expired` |

### ReminderRecoveryBatchStatus

| 值 | 说明 |
| --- | --- |
| `in_progress` | 恢复计划已持久化，仍有摘要或明细投递未终结 |
| `completed` | 本批次所有需要的投递均已达到终结状态 |

### HabitCheckInStatus

习惯打卡状态。

| 值 | 说明 |
| --- | --- |
| `done` | 已完成 |
| `partial` | 部分完成 |
| `missed` | 未完成 |
| `skipped` | 跳过，不计入失败 |

### SyncOperationType

同步操作类型。

| 值 | 说明 |
| --- | --- |
| `create` | 新增 |
| `update` | 更新 |
| `delete` | 删除 |
| `restore` | 恢复 |

### UserAccountStatus

用户账号的服务端生命周期状态。

| 值 | 说明 |
| --- | --- |
| `pending_verification` | 已注册但登录邮箱尚未验证 |
| `active` | 邮箱已验证且账号可正常使用 |
| `disabled` | 账号被服务端禁用 |
| `deleted` | 账号已进入删除状态，不再允许认证 |

### VerificationCredentialType

| 值 | 说明 |
| --- | --- |
| `code` | 用户手动输入的 6 位数字验证码 |
| `link_token` | 邮件深度链接携带的不透明验证 Token |

### EmailActionPurpose

| 值 | 说明 |
| --- | --- |
| `registration_verification` | 注册邮箱验证 |
| `email_change` | 新登录邮箱验证 |
| `password_reset` | 忘记密码后的重置验证 |

### EmailChangeStatus

| 值 | 说明 |
| --- | --- |
| `pending` | 新邮箱等待验证，原邮箱仍然有效 |
| `verified` | 新邮箱已验证并完成替换 |
| `expired` | 申请或验证挑战已过期 |
| `cancelled` | 用户或服务端取消申请 |

### SessionRevocationReason

| 值 | 说明 |
| --- | --- |
| `logout` | 当前设备主动退出 |
| `logout_all` | 用户主动退出所有设备 |
| `password_changed` | 修改密码后撤销其他设备 |
| `password_reset` | 密码重置后撤销全部设备 |
| `email_changed` | 登录邮箱变更后撤销其他设备 |
| `refresh_token_reused` | 检测到已消费 Refresh Token 重放 |
| `account_disabled` | 账号被禁用 |
| `expired` | 会话自然过期 |

## Event：日程

日程是日历中的核心事项。普通定时 Event 与全天 Event 使用互斥时间结构；重复 Event 只保存系列定义和当前 Recurrence revision，不预生成无限 occurrence。

说明：

- 普通定时 Event 使用 `startAt/endAt` UTC Instant；`startDate/endDate` 必须为空。
- 全天 Event 使用 `startDate/endDate` 本地日期；`startAt/endAt` 必须为空。单日全天 Event 示例为 `[2026-08-02, 2026-08-03)`。
- `timezone` 对两类 Event 都必填，并在创建或更新写入前由 C++ 使用捆绑 TZDB 校验。
- 日程本身不直接保存提醒方式和提醒时间。只要日程需要提醒，就在 `Reminder` 表中创建一条或多条提醒任务。
- 如果一个日程有多个提醒时间，例如提前 1 天、提前 1 小时、开始时各提醒一次，则创建 3 条 `Reminder`，它们的 `targetType = event` 且 `targetId = Event.id`。
- `Event.status` 表示整个 Event 或整个重复系列的生命周期状态，不表示“今天已完成”或“今天跳过”。
- 单次非重复 Event 完成时，关联且尚未触发的 `pending` / `scheduled` Reminder 会在同一 C++ workflow transaction 中自动取消，并写入 `lastCancellationReason = event_completed`；重新打开 Event 时，只恢复该原因且仍在未来的 Reminder。
- 重复日程某一次 occurrence 的完成、跳过、取消状态保存到 `EventOccurrenceState`。
- `recurrenceId + recurrenceRevision` 必须同时为空或同时存在；两者存在时指向当前不可变 Recurrence revision。
- `hasRecurrence` 是 Contract 查询投影中的派生布尔值，不是独立持久化事实。
- 重复 Event 的时间、时区、规则或实际 Reminder 模板变化时创建新 revision；标题只有在会改变 Reminder `message` 时才属于模板变化。旧 revision 的 occurrence 状态保留为历史。
- `event.update` 对重复 Event 始终修改整个系列：`reminders` 省略表示保留模板，空数组表示清空，非空数组表示完整替换；不得把部分数组解释成增量 patch。
- 更新已存在的重复 Event 必须携带与当前值相等的 `expectedRecurrenceRevision`；缺失、过期或指向历史 revision 都返回 `RECURRENCE_REVISION_CONFLICT`，不得在旧读结果上静默覆盖新系列。
- `recurrence` 省略表示保留当前规则；v2 不接受含义不明确的 `recurrence = null`。停止重复应使用显式系列取消/删除流程，而不是把更新请求解释成静默拆系。
- 新 revision 提交时，旧 revision 的所有非终结 Reminder 在同一事务以 `series_updated` 取消；新的滚动 Reminder 只能引用新 revision。
- `completeSeries` 后允许 `reopenSeries`，并只恢复未来且因 `series_completed` 取消的 Reminder；已 `cancelled` 或已软删除系列不得 reopen。
- 重复 Event 删除只允许 `all_occurrences + soft delete`；单次 occurrence 使用显式 occurrence cancel，不复用 Event 删除范围。
- 全天非重复 Event 可以继续使用绝对 `remindAt`；全天重复 Event 不允许 Reminder，返回 `ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED`。
- 软删除表示用户删除后先不从数据库物理移除，而是写入 `deletedAt`。这样方便撤销删除、同步删除状态、排查误删。正常查询默认只显示 `deletedAt` 为空的记录。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 日程 ID |
| `title` | `string` | 是 | 标题 |
| `content` | `string` | 否 | 内容、备注或详情 |
| `startAt` | `datetime` | 条件必填 | 普通 Event 的 UTC 开始 Instant；全天 Event 必须为空 |
| `endAt` | `datetime` | 条件必填 | 普通 Event 的 UTC 结束 Instant；全天 Event 必须为空 |
| `startDate` | `date` | 条件必填 | 全天 Event 的本地开始日期；普通 Event 必须为空 |
| `endDate` | `date` | 条件必填 | 全天 Event 的本地右开结束日期；普通 Event 必须为空 |
| `isAllDay` | `boolean` | 是 | 是否全天日程 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `status` | `EventStatus` | 是 | 整个日程或整个重复系列的生命周期状态，默认 `active` |
| `completedAt` | `datetime` | 否 | 单次日程完成时间，或整个重复系列彻底完成时间 |
| `recurrenceId` | `string` | 否 | 当前重复规则族 ID；非重复 Event 为空 |
| `recurrenceRevision` | `integer` | 否 | 当前不可变规则 revision；非重复 Event 为空 |
| `categoryId` | `string` | 否 | 分类 ID |
| `importance` | `Importance` | 否 | 重要性 |
| `location` | `string` | 否 | 地点 |
| `timezone` | `string` | 是 | 有效 IANA timezone ID，例如 `Asia/Shanghai` |
| `source` | `string` | 是 | 来源，例如来自于微信，手动添加 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

## EventOccurrenceState：日程 occurrence 状态

`EventOccurrenceState` 用于记录重复日程某一次 occurrence 的完成、跳过、取消状态。它不是提前生成所有未来 occurrence 的缓存表，而是用户产生明确行为后才写入的稀疏状态记录表。

说明：

- `occurrenceKey` 由 C++ 按 `contracts/identity.yaml` 生成，客户端只能原样透传，其他层不得重新计算。
- occurrence 操作请求同时回传查询结果中的计划开始 Instant 或本地日期，C++ 以该值做有界展开并重新校验 `occurrenceKey`；不得仅凭不可逆 UUID 在无限规则中搜索。
- 定时 occurrence 的身份输入使用 DST 解析前的原始计划本地日期时间；全天 occurrence 使用本地日期。
- 普通日程完成时直接更新 `Event.status`；重复日程单次操作不得污染整个 Event 状态。
- 如果某次 occurrence 没有状态记录，则根据 Recurrence 展开结果和当前时间动态计算展示状态。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `eventId` | `string` | 是 | 关联日程 ID |
| `recurrenceRevision` | `integer` | 是 | 产生该 occurrence 的规则 revision |
| `occurrenceKey` | `string` | 是 | 稳定 UUIDv5 occurrence 身份 |
| `occurrenceStartAt` | `datetime` | 条件必填 | 定时 occurrence 的 UTC 计划开始 Instant |
| `occurrenceStartDate` | `date` | 条件必填 | 全天 occurrence 的本地计划开始日期 |
| `status` | `EventOccurrenceStatus` | 是 | occurrence 状态 |
| `stateChangedAt` | `datetime` | 是 | 最近一次状态操作时间，由 C++ Clock 生成 |
| `reopenedAt` | `datetime` | 否 | 最近一次 reopen 时间，由 C++ Clock 生成 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

建议约束：

- 唯一键为 `(eventId, recurrenceRevision, occurrenceKey)`。
- `occurrenceStartAt` 与 `occurrenceStartDate` 必须恰有一个非空，并与 Event 的时间类型一致。
- complete/skip/cancel 在同一 workflow transaction 中更新状态、以对应原因取消本 occurrence 的非终结 Reminder，并确保下一个合法滚动 Reminder 存在。
- reopen 把状态改为 `scheduled`，仅恢复 `remindAt > reopenedAt` 且取消原因可逆的原 Reminder；不执行 72 小时补发。
- occurrence 查询投影另外计算 `occurrenceEndAt` 或 `occurrenceEndDate`，结束值不是状态表字段。

## Habit：习惯

习惯用于记录需要长期执行、打卡或追踪的行为。习惯是规律的，而且需要特殊记录，比如一共坚持了多久、哪些日子坚持了、某一天完成了多少次。

说明：

- `Habit` 只保存习惯定义，例如名称、目标、单位、开始日期、重复规则。
- 每天是否完成、完成次数、打卡时间不放在 `Habit` 本体里，而是保存到 `HabitCheckIn`。
- 后期用表格呈现时，可以用 `Habit` 作为行或分组，用 `HabitCheckIn.checkDate` 作为列或单元格数据来源。
- 连续天数、总完成天数、完成率建议优先从 `HabitCheckIn` 计算；如果性能不够，再增加缓存字段或统计表。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 习惯 ID |
| `title` | `string` | 是 | 习惯名称 |
| `description` | `string` | 否 | 习惯说明 |
| `categoryId` | `string` | 否 | 分类 ID |
| `recurrenceId` | `string` | 是 | 计划中的 Habit 专用规则引用；不得指向本轮 Event Recurrence revision |
| `targetCount` | `number` | 否 | 目标次数，例如每天喝水 8 次 |
| `unit` | `string` | 否 | 目标单位，例如次、分钟、页 |
| `startDate` | `date` | 是 | 开始日期 |
| `endDate` | `date` | 否 | 结束日期 |
| `isActive` | `boolean` | 是 | 是否启用 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

## HabitCheckIn：习惯打卡记录

习惯打卡记录用于保存某个习惯在某一天的完成情况。这个模型是习惯表格、日历视图、连续天数、完成率统计的主要数据来源。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 打卡记录 ID |
| `habitId` | `string` | 是 | 关联习惯 ID |
| `checkDate` | `date` | 是 | 打卡日期，按用户本地时区计算 |
| `status` | `HabitCheckInStatus` | 是 | 打卡状态 |
| `completedCount` | `number` | 否 | 当天完成数量，例如喝水 6 次 |
| `targetCountSnapshot` | `number` | 否 | 当天目标数量快照，避免后续修改习惯目标影响历史统计 |
| `unitSnapshot` | `string` | 否 | 当天单位快照，例如次、分钟、页 |
| `completedAt` | `datetime` | 否 | 实际完成时间 |
| `note` | `string` | 否 | 当天备注 |
| `source` | `string` | 是 | 来源，例如 `manual`、`auto` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

建议约束：

- 同一个 `habitId + checkDate` 默认只保留一条记录。
- 如果未来需要一天内多次明细，例如每次喝水都记录时间，可以再增加 `HabitCheckInEntry` 明细模型；当前阶段先不需要。

## Reminder：提醒

提醒是独立实体，也是未来调度任务的唯一领域真相源。普通单次 Reminder 与重复 Event 的滚动 Reminder 共用实体，但身份和生成规则不同。

职责边界：

- `Reminder` 回答“未来什么时候需要提醒、提醒谁、用什么方式提醒”。
- `Reminder` 是待执行任务，适合被后台扫描、注册系统闹钟和失败重试。
- `Reminder` 不负责记录通知最终有没有展示成功；投递结果由 `Notification` 记录。
- Android 不再为每条 Reminder 分别注册 Alarm。调度器始终从本表按 `(remindAt, reminderId)` 读取最早任务，使用一个 Dispatcher Alarm 覆盖该触发时刻；触发后排空所有到期 Reminder，再滚动到下一时刻。
- `status = scheduled` 表示该 Reminder 的触发时刻已由当前 Dispatcher Alarm 覆盖，不表示 Android 中存在一条与 Reminder 一一对应的 Alarm。
- 后续切换到 SQLite 时，调度查询应建立覆盖 `isEnabled / deletedAt / status / remindAt / reminderId` 的索引；Notification 仍不得参与扫描。
- 普通单次 Reminder 使用 UUIDv4，不创建 successor；重复 Reminder 使用 Contract 指定的确定性 UUIDv5，并在成功投递或永久失败后滚动创建下一个合法 occurrence 的 Reminder。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `reminderId` | `string` | 是 | 提醒 ID；Contract 字段为 `reminder_id` |
| `targetType` | `string` | 是 | 关联对象类型，例如 `event`、`habit`、`anniversary` |
| `targetId` | `string` | 是 | 关联对象 ID |
| `recurrenceRevision` | `integer` | 否 | 重复 Event 当前 Reminder 所属 revision；普通 Reminder 为空 |
| `occurrenceKey` | `string` | 否 | 重复 Event occurrence 的稳定 UUIDv5；普通 Reminder 为空 |
| `occurrenceStartAt` | `datetime` | 否 | 重复定时 occurrence 的 UTC 开始 Instant；普通 Reminder 为空 |
| `remindAt` | `datetime` | 是 | 提醒触发时间 |
| `methods` | `ReminderMethod[]` | 是 | 提醒方式 |
| `advanceMinutes` | `number` | 否 | 提前提醒分钟数 |
| `message` | `string` | 否 | 提醒文案 |
| `isEnabled` | `boolean` | 是 | 是否启用，初始化为true |
| `status` | `ReminderStatus` | 是 | 提醒任务状态 |
| `scheduledAt` | `datetime` | 否 | 实际注册到系统闹钟或投递通道的时间 |
| `lastTriggeredAt` | `datetime` | 否 | 最近一次触发时间 |
| `failureReason` | `string` | 否 | 调度或发送失败原因 |
| `lastCancellationReason` | `ReminderCancellationReason` | 否 | 最近一次机器可读取消原因 |
| `lastCancelledAt` | `datetime` | 否 | 最近一次取消时间 |
| `expirationReason` | `ReminderExpirationReason` | 否 | `expired` 时固定为 `recovery_window_elapsed`，其他状态为空 |
| `expiredAt` | `datetime` | 否 | Recovery 把已物化 Reminder 终结为 `expired` 的 C++ Clock 时间 |
| `reactivatedAt` | `datetime` | 否 | 最近一次恢复为 `pending` 的时间 |
| `reactivationCount` | `integer` | 是 | 恢复次数，初始为 `0` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

身份与模板不变量：

- 普通 Reminder 的 `recurrenceRevision/occurrenceKey/occurrenceStartAt` 必须全部为空，`reminderId` 使用 UUIDv4，原有绝对 `remindAt`、多渠道和历史保留行为不变。
- 重复 Reminder 的三个 occurrence 字段必须全部存在；由于全天重复 Event 不支持 Reminder，`occurrenceStartAt` 始终是 UTC Instant。
- 重复 Reminder draft 只提交 `advanceMinutes`，不得提交绝对 `remindAt`；`advanceMinutes = 0` 合法。
- v2 重复 Reminder 的 `methods` 必须规范化为 `['popup']`。同一 revision 中 `(advanceMinutes, canonicalMethods)` 模板唯一，`message` 不参与身份计算。
- 重复 Reminder 唯一键为 `(targetId, recurrenceRevision, occurrenceKey, advanceMinutes, canonicalMethods)`；`reminderId` 的 UUIDv5 输入与固定测试向量见 `contracts/identity.yaml`。
- 除 `planRecovery` 外，首次创建、revision 更新、投递终结和 occurrence/series 状态变化只能选择 `remindAt > workflow Clock` 的最早合法 occurrence；不得为了补历史而在普通 workflow 中创建过去 Reminder。
- 重试遇到相同 ID 且业务内容一致时幂等返回原记录；内容冲突返回 `REMINDER_IDEMPOTENCY_CONFLICT`。
- `series_updated`、`series_cancelled`、`series_deleted` 和 `user_cancelled` 不可恢复；其他可逆原因仅能恢复同一条仍在未来的 Reminder。
- 取消时写入/覆盖 `lastCancellationReason` 与 `lastCancelledAt`；恢复时把同一记录改回 `pending`、重新启用、写入 `reactivatedAt` 并递增 `reactivationCount`，但不清空最近取消审计字段。
- occurrence reopen 恢复较早 Reminder 前，必须把同 event/revision/模板且时间更晚的 open successor 以 `occurrence_reopened` 暂存；滚动链随后只恢复仍在未来的确定性 successor，同模板任何时刻最多一条 open Reminder。
- `expired` 是仅由 `planRecovery` 写入的终结状态：严格满足 `remindAt < windowStartAt` 的 open `pending/scheduled` Reminder 被禁用、清空 `scheduledAt` 并保留原 `remindAt` 与审计历史；普通 Reminder 不生成 successor，重复 Reminder 在同一事务确保首个未来 successor。
- 可重试投递失败只追加 `Notification` attempt，Reminder 保持 `pending`。永久失败把当前 Reminder 标记 `failed`，并在同一事务创建 successor，避免无限系列中断。
## Category：分类

分类用于组织日程、习惯、纪念日等对象。Category 是独立配置实体；业务对象只保存稳定的
`categoryId`，分类名称、颜色和列表下标都不能充当关联键。

当前只冻结本地分类本身，不冻结账号归属或系统预设语义。Flutter Fake 中的“默认日程”和
用户名分组仅是开发期数据/展示信息，不产生 `userId`、`isDefault`、`ownerName` 等领域字段。
未分类由业务对象的 `categoryId = null` 表达，不要求存在一条名为“默认日程”的 Category。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 分类 ID；新的正式 writer 由 C++ 生成 UUIDv4 |
| `name` | `string` | 是 | 去除首尾空白后非空，最多 40 个 Unicode 字符 |
| `description` | `string` | 否 | 分类备注；空白规范化为 `null`，最多 200 个 Unicode 字符 |
| `color` | `string` | 否 | 规范化的 `#RRGGBB` 大写十六进制颜色；新建分类时必填，响应保留可空以兼容旧草案 |
| `icon` | `string` | 否 | 稳定图标标识；当前 Flutter 创建页不提交 |
| `sortOrder` | `integer` | 否 | `0..9007199254740991`；`null` 表示没有显式顺序，范围保证 JSON Number 在 Dart/Kotlin/C++ 间精确往返 |
| `createdAt` | `datetime` | 是 | C++ Clock 生成的创建时间 |
| `updatedAt` | `datetime` | 是 | C++ Clock 生成的最近更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间；活动分类为 `null` |

关系与生命周期不变量：

- Category 名称不是身份，也尚未冻结账号范围内的唯一性；当前允许重名，调用方必须使用 `id` 区分。
- `category.list` 只返回 `deletedAt = null` 的活动分类，并按 `sortOrder`（`null` 最后）、
  `createdAt`、`id` 升序稳定排序。
- Category 创建的领域规范化只在 C++ Application/Domain 执行：`name/description/icon` trim，空白
  optional text 变 `null`，`color` 转大写。Flutter/Kotlin 只能校验 wire 结构并原样转发 Schema-valid 值，
  不得提前 trim、blank-to-null 或 uppercase。
- 创建请求未提供显式 `sortOrder` 时，C++ Category workflow 负责选择稳定的追加顺序；
  Flutter/Kotlin 不生成 ID、时间戳或持久化排序值。活动最大值已经是 `9007199254740991` 时返回
  `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。
- Category 软删除不得把 Event、Habit 或 Anniversary 的 `categoryId` 改成名称、颜色或其他替代值。
  Event detail 的 Category 聚合固定为三态：`event.categoryId = null` 时 `category = null`；非空 ID 命中
  活动 Category 时必须返回同 ID 的 Category；非空 ID 悬空或只命中软删除 Category 时返回
  `category = null`，同时原始 `event.categoryId` 必须保留。
- 按分类过滤 Event 必须使用 `categoryId/category_ids`。`categoryName` 只允许作为 SearchIndex 的
  可重建冗余文本，不是结构化过滤或引用完整性的真相源。
- Category 归属于设备、本地资料还是具体云端用户，以及系统默认分类的初始化/隐藏/复制规则，
  仍待账号与同步架构冻结后另行设计；本轮不得据此新增字段或预设写入。

### Category Storage v2 映射（已实现，尚未通过发布集成门禁）

Category 使用 Calendar Core JSON v2 目录中的独立逻辑 Store：

```json
{
  "storage_version": 2,
  "categories": []
}
```

- 文件名固定为 `categories.json`，根对象只允许 `storage_version` 与 `categories`；严格格式由
  `contracts/storage/category_store.schema.json` 定义。
- `CategoryStorageRecord` 与 Create Request、Response DTO、领域对象分离，但使用同一组稳定事实字段：
  `id/name/description/color/icon/sort_order/created_at/updated_at/deleted_at`。所有 nullable 字段也必须
  显式保存，禁止依赖语言默认值补字段。
- 正式本地 Store 比兼容性 Response reader 更严格：`color` 与 `sort_order` 在磁盘上必须非空；
  request 的空顺序由 C++ 在持久化前物化。Response 保留这两项可空只用于既有草案/非 Store reader 兼容，
  不能据此向新 `categories.json` 写入 null。
- 存储快照按 `id` 升序序列化，使同一状态产生稳定文件；本地 Store 投影按
  `sortOrder -> createdAt -> id` 排序，兼容性 Response comparator 仍把非 Store 来源的 null 放在最后；
  任何情况下都不能把数组下标当作排序事实。
- Request、Response 与 Store 的 `sort_order` 都限制为 `0..9007199254740991`。请求直接超限返回
  `CONTRACT_VALIDATION_FAILED`，磁盘记录超限返回 `STORAGE_DATA_CORRUPTED`；`category.create.sort_order = null`
  时 C++ workflow 在目录级写锁内按活动记录的最大 `sort_order + 1` 生成持久化值，没有活动记录时从
  `0` 开始，最大值已达上界时返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且不写入。显式重复顺序值合法，
  由列表次级键稳定消歧。
- 当前 create 只修改 `categories.json`，完整快照校验后使用同目录临时文件、flush/fsync、原子替换和目录同步，
  成功完成目录同步才是 Contract 提交点；任何阶段返回失败都必须让旧快照继续权威。单文件原子替换就是事务
  边界，不需要扩展现有 Event/Reminder 或 Anniversary journal。
- 未来若一个 Category workflow 必须同时修改其他逻辑 Store，必须先定义独立的可恢复 journal；不得静默扩大
  两个既有 journal 的精确 Store 集合。
- 已有 Event/Habit/Anniversary 的 `categoryId` 是弱引用：Category Store 加载不扫描、不清空也不规范化其他
  Store 的引用。缺失或软删除 Category 时保留原 ID，聚合投影可以返回空 Category。
- 这是 Storage v2 的可加性独立文件，不改变现有 Store 的根包络、记录 codec 或 journal。合法旧 v2 目录在
  Category Storage 正式激活后只创建空根；若已有 `categories.json`，必须完整校验并原样保留，损坏或未知版本
  显式失败，禁止重置。
- 没有正式 Category v1 Store，也禁止把 Flutter Fake、“默认日程”fixture 或 owner 文案迁入正式存储。
- 当前选择严格 JSON 完整快照，是因为 Category 属于低基数配置数据，公开操作只有 list/create，且可以直接复用
  现有目录锁、原子替换和损坏检测。Repository 边界保持不变；以后出现账号分区同步、高频写入或明显规模压力时，
  再用显式 migration 切换 SQLite，而不是让 UI/DTO 依赖文件格式。

Category 的 C++ Domain/Repository/JSON codec、bootstrap、JNI export 与真实磁盘读写代码已经存在，故 Store
和两条调用统一标记为 `implementation_status: implemented_unintegrated`；但 `release_status: blocked` 仍表示
不能宣称产品闭环已完成。解除条件是 Event detail 聚合、Kotlin Event Category 校验、原子写 post-replace
失败语义、跨层安全整数/规范化一致性、Flutter 生产 composition 与设备 smoke 全部通过。

## Recurrence：重复规则

本节只定义 Event v2 的重复规则。客户端输入 `EventRecurrenceRuleInput` 与持久化 `Recurrence` revision 必须分离：客户端只能表达意图，锚点、时区和展开字段由 C++ 从 Event 派生。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `recurrenceId` | `string` | 是 | 重复规则族 ID |
| `revision` | `integer` | 是 | 不可变版本号，首版为 `1` |
| `frequency` | `RecurrenceFrequency` | 是 | 重复频率 |
| `interval` | `integer` | 是 | v2 固定为 `1` |
| `startAt` | `datetime` | 条件必填 | 定时 Event 的首个 UTC Instant；全天 Event 为空 |
| `startDate` | `date` | 条件必填 | 全天 Event 的首个本地日期；定时 Event 为空 |
| `timezone` | `string` | 是 | 从 Event 派生的有效 IANA ID |
| `dayOfMonth` | `integer` | 否 | Monthly 的初始本地日号；月份截断不能修改该锚点 |
| `daysOfWeek` | `integer[]` | 否 | Weekly 恰好一个 ISO weekday，Monday=1、Sunday=7 |
| `monthOfYear` | `integer` | 否 | v2 始终为空，预留给未来 Yearly |
| `endAt` | `datetime` | 否 | v2 始终为空，预留结束边界 |
| `count` | `integer` | 否 | v2 始终为空，预留最大 occurrence 数 |
| `createdAt` | `datetime` | 是 | 创建时间 |

约束：

- 主键和唯一键均为 `(recurrenceId, revision)`；revision 不可覆盖、不可软删除改写。
- Event 保存当前 `recurrenceId + recurrenceRevision`，Recurrence 不再保存 `targetType/targetId`，避免双重关系真相源。
- v2 客户端只允许提交 `frequency/interval/endAt/count`。`interval = 1`、`endAt = null`、`count = null`；`daily/weekly/monthly` 可执行，`yearly/custom` 通过 schema 后由 C++ 返回 `FEATURE_NOT_IMPLEMENTED`。
- `startAt/startDate/timezone/dayOfMonth/daysOfWeek/monthOfYear` 均不得由客户端提交；`rrule` 和客户端自定义锚点必须被 schema 拒绝。
- `daysOfWeek` 在 Weekly 中恰好一个元素，在 Daily/Monthly 中返回空数组；`dayOfMonth` 仅 Monthly 非空。
- Daily/Weekly/Monthly 先在原时区做本地日历运算，再把每个 occurrence 的本地开始和结束分别解析为 UTC。DST gap 前移到 gap 后首个合法 Instant，DST fold 选择较早 Instant。
- 不预生成无限 occurrence。查询必须带有界半开窗口，并按原始计划本地开始值稳定排序。

## Notification：通知

Notification 是某个逻辑 delivery 的一次实际 attempt 记录。它采用 `prepare_delivery -> Kotlin 系统投递 -> finalize_delivery` 两阶段流程，绝不作为未来 Reminder 扫描入口。

职责边界：

- `Notification` 回答“哪个逻辑 delivery 的哪次 attempt 是否真的投递、什么时候终结、失败是否可重试”。
- `Notification` 是结果日志，不参与未来提醒扫描。
- 本地系统通知、响铃、弹窗、微信提醒都可以生成 `Notification` 记录。
- 一条 Reminder 的每个 `method` 都是独立逻辑 delivery；部分成功通过各自 Notification attempt 表达，不把渠道结果压成自由文本。
- Android 固定使用 `NotificationManager.notify(tag = deliveryId, id = 0, ...)`。同一逻辑 delivery 重试覆盖同一通知栏条目，不会制造重复条目。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `notificationId` | `string` | 是 | Notification attempt 记录 UUID |
| `deliveryId` | `string` | 是 | 逻辑投递的稳定 UUIDv5 幂等 ID |
| `deliveryAttemptId` | `string` | 是 | 每次实际尝试唯一的 UUID |
| `kind` | `NotificationKind` | 是 | Reminder 投递或恢复摘要 |
| `reminderId` | `string` | 否 | `kind = reminder` 时必填 |
| `recoveryBatchId` | `string` | 否 | 恢复摘要时必填；由 Recovery 新建的明细 attempt 也携带该值。Recovery 接管既有 frozen attempt 时保持原值（通常为空），改用 `resolvedByRecoveryBatchId` 记录裁决归属 |
| `resolvedByRecoveryBatchId` | `string` | 否 | Recovery 对既有 frozen attempt 的裁决归属；与 `recoveryBatchId` 互斥且不进入原 PendingIntent payload |
| `targetType` | `string` | 是 | 业务目标类型；恢复摘要使用 `reminder_recovery_batch` |
| `targetId` | `string` | 是 | 业务目标 ID；恢复摘要等于 batch ID |
| `occurrenceKey` | `string` | 否 | 重复 Reminder 的 occurrence 身份；普通 Reminder/摘要为空 |
| `method` | `ReminderMethod` | 是 | 通知渠道 |
| `title` | `string` | 是 | 通知标题 |
| `body` | `string` | 否 | 通知正文 |
| `plannedAt` | `datetime` | 是 | 原计划投递时间 |
| `preparedAt` | `datetime` | 是 | C++ 创建或复用 attempt 的时间 |
| `finalizedAt` | `datetime` | 否 | attempt 终结时间 |
| `sentAt` | `datetime` | 否 | 实际发送时间 |
| `status` | `NotificationStatus` | 是 | 通知状态 |
| `failureClass` | `NotificationFailureClass` | 否 | 失败是否可重试；非失败状态为空 |
| `errorCode` | `string` | 否 | 失败的稳定 Contract 错误码；非失败状态为空 |
| `abandonReason` | `DeliveryAbandonReason` | 否 | `abandoned` 时说明由窗口过期或恢复摘要替代；其他状态为空 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

两阶段与渠道聚合不变量：

- `prepare_delivery` 由 C++ 校验 Reminder 仍可投递且 `expectedRemindAt` 与当前记录严格相等，并创建或复用唯一 `prepared` attempt；普通调度还必须已到期，绑定有效恢复批次的明细 Reminder 才允许使用窗口内的历史 `remindAt`。响应同时提供真实 Notification ID、展示内容和点击 payload。
- 已存在 `sent` attempt 的 `deliveryId` 不得再次 prepare；C++ 返回 `REMINDER_ALREADY_CONSUMED` 或等价已声明错误，Kotlin 不展示重复通知。
- 同一 `deliveryId` 同时最多一个 `prepared` attempt，历史上最多一个 `sent` attempt。相同 attempt 的相同 finalize 幂等返回，冲突 finalize 返回 `DELIVERY_ATTEMPT_INVALID`。
- `prepared` attempt 的 Notification 内容、delivery identity 和 PendingIntent payload 一经返回即冻结。Recovery detail 接管时只写 `resolvedByRecoveryBatchId` 并复用原 attempt；不得改写原 `recoveryBatchId` 或展示 payload。
- Recovery 把既有 attempt 归入摘要或窗口外时，必须在同一事务写为 `abandoned`、记录 `abandonReason/resolvedByRecoveryBatchId/finalizedAt`。Kotlin 取消旧 `deliveryId` 的 Android notification tag，且旧 attempt 的任何 finalize 都返回 `DELIVERY_ATTEMPT_INVALID` 而不修改状态。
- `deliveryId` 按 `contracts/identity.yaml` 使用 UUIDv5；`notificationId` 与新建的 `deliveryAttemptId` 由 C++ 使用 UUIDv4 生成，幂等复用 prepared attempt 时必须返回原值。
- `sent` 要求 `finalizedAt/sentAt` 非空且失败字段为空；`failed` 要求 `finalizedAt/failureClass/errorCode` 非空且 `sentAt` 为空。
- 多渠道 Reminder 只有当所有方法均已有 `sent` attempt 时才进入 `sent`。任何可重试失败使 Reminder 保持 `pending`，已成功渠道不重复投递；任一永久失败使 Reminder 进入 `failed`。v2 重复 Reminder 仅允许 popup，因此 successor 生成没有多渠道歧义。
- `prepare_delivery` 返回的 PendingIntent payload 必须携带 `notificationId/deliveryId/deliveryAttemptId/reminderId/targetId/occurrenceKey`；不适用的字段显式为 `null`。Android 收到点击后才追加非空 `openedAt`，再作为 `NotificationTapPayload` 发给 Flutter。

## ReminderRecoveryBatch：提醒恢复批次

恢复批次把 App 启动、设备重启和 Alarm reconcile 的 72 小时补发计划持久化，使崩溃重启可以复用同一批次和 delivery ID。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `recoveryBatchId` | `string` | 是 | 批次 UUID |
| `recoveryRequestId` | `string` | 是 | Kotlin 持久化的幂等请求 ID |
| `triggerSource` | `string` | 是 | `app_start`、`device_boot` 或 `alarm_reconcile` |
| `startedAt` | `datetime` | 是 | C++ Clock 生成的开始时间 |
| `windowStartAt` | `datetime` | 是 | `startedAt - 72h`；恰好边界计入窗口 |
| `detailReminderIds` | `string[]` | 是 | 全局最近 20 条明细 Reminder ID |
| `summaryReminderIds` | `string[]` | 是 | 窗口内其余通过摘要投递的 Reminder ID |
| `olderSkippedOccurrenceCount` | `integer` | 是 | 72 小时以前未展开的 occurrence 数 |
| `olderSkippedReminderCount` | `integer` | 是 | 72 小时以前未生成的 Reminder 数，加上本事务终结为 `expired` 的已物化 open Reminder 数 |
| `windowOverflowCount` | `integer` | 是 | 窗口内超过 20 条上限的 Reminder 数 |
| `summaryDeliveryId` | `string` | 否 | 有摘要时的稳定 delivery UUIDv5 |
| `status` | `ReminderRecoveryBatchStatus` | 是 | 批次状态 |
| `completedAt` | `datetime` | 否 | 批次完成时间 |

约束：

- `recoveryRequestId` 唯一；重复调用返回同一批次。同一时间最多一个 `in_progress` 批次，否则返回 `RECOVERY_BATCH_CONFLICT`。
- `detailReminderIds` 与 `summaryReminderIds` 必须互斥，`windowOverflowCount` 必须等于 `summaryReminderIds.length`；`planRecovery.detailReminders` 必须与 `detailReminderIds` 同序且一一对应。
- `planRecovery.preparedAttemptResolutions` 必须完整、稳定地返回本批次裁决的既有 prepared attempts：最近 20 条为 `adopted_detail`，窗口内其余为 `abandoned_to_summary`，严格早于窗口为 `abandoned_outside_window`。后两者的 `replacementDeliveryId` 等于 `summaryDeliveryId`。
- 只要摘要列表非空或任一 older skipped 计数大于 `0`，`summaryDeliveryId` 就必须存在；三者都为空/为 `0` 时必须为 `null`。
- 只为 `[windowStartAt, startedAt]` 内的合法 occurrence 生成真实 Reminder；72 小时以前只记计数，不批量生成对象。
- 已经物化且严格早于 `windowStartAt` 的 open Reminder 不再留在调度队列：同一计划事务把它终结为 `expired` 并计入 `olderSkippedReminderCount`；恰好等于边界的 Reminder 仍参加窗口内明细/摘要选择。
- `planRecovery` workflow 是唯一允许创建 `remindAt <= startedAt` 历史到期 Reminder 的入口；普通 Reminder create/update 仍拒绝过去时间，且恢复 Reminder 必须绑定当前批次。
- 全局先按 `remindAt` 降序、`reminderId` 降序选择最近 20 条，再按 `(remindAt, reminderId)` 升序投递。较早项目摘要先于 20 条明细投递。
- 摘要成功后，`summaryReminderIds` 对应 Reminder 标记为通过摘要送达，而不是 `expired`；批次记录提供审计关联。
- 摘要成功时这些 Reminder 进入 `sent`，`lastTriggeredAt` 使用摘要 finalize 的 C++ Clock 时间；不得逐条再弹出。
- 摘要可重试失败时，覆盖的 Reminder 保持 `pending`、批次保持 `in_progress`；永久失败时，每条覆盖的 Reminder 按普通永久失败规则进入 `failed`，重复 Reminder 在同一事务生成 successor。批量变更通过 batch ID 审计，不要求 `finalizeDelivery` 回传所有对象。
- 当摘要（如有）和全部明细逻辑 delivery 都已 `sent` 或永久失败时批次进入 `completed`；仍有 prepared/可重试失败时保持 `in_progress`。没有任何 delivery 的空批次在计划事务内直接完成。
- 恢复摘要 Notification 的 `plannedAt = startedAt`，`targetType = reminder_recovery_batch`，`targetId = recoveryBatchId`；标题和正文由 C++ 根据持久化计数生成。
- `expired` 重复 Reminder 不补发，但必须在同一事务通过滚动规则确保首个未来 successor；不得因此生成第二条同模板 open Reminder。

## SearchIndex：搜索索引

搜索索引用于加速日程、习惯、纪念日等内容检索。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 索引记录 ID |
| `targetType` | `string` | 是 | 被索引对象类型 |
| `targetId` | `string` | 是 | 被索引对象 ID |
| `titleText` | `string` | 否 | 标题索引文本 |
| `bodyText` | `string` | 否 | 正文索引文本 |
| `keywords` | `string[]` | 否 | 关键词 |
| `categoryId` | `string` | 否 | 从目标对象派生的稳定分类 ID，用于结构化分类过滤 |
| `categoryName` | `string` | 否 | 可重建的分类名称冗余文本，只用于展示或全文检索 |
| `occurAt` | `datetime` | 否 | 发生时间，用于时间排序 |
| `updatedAt` | `datetime` | 是 | 索引更新时间 |

`categoryId/categoryName` 都是索引投影而非新的关系真相源。Category 更名、软删除或索引损坏时，
SearchIndex 必须从目标对象的 `categoryId` 与当前 Category 记录重建；分类筛选不能依赖旧名称。

## AIExtraction：AI 解析结果

AI 解析结果保存从自然语言、图片或分享文本中提取出的候选结构化数据。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | AI 解析结果 ID |
| `inputType` | `string` | 是 | 输入类型，例如 `text`、`image`、`share` |
| `rawInput` | `string` | 是 | 原始输入内容或引用 |
| `extractedType` | `string` | 是 | 解析出的对象类型，例如 `event`、`reminder` |
| `extractedData` | `object` | 是 | 结构化解析结果 |
| `confidence` | `number` | 否 | 置信度，建议范围 `0-1` |
| `candidateEventId` | `string` | 否 | 生成的候选日程 ID |
| `status` | `string` | 是 | 状态，例如 `pending_review`、`accepted`、`rejected` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

## SyncOperation：同步操作

同步操作记录本地与云端之间的数据变更，用于冲突处理和增量同步。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 同步操作 ID |
| `operationType` | `SyncOperationType` | 是 | 操作类型 |
| `targetType` | `string` | 是 | 目标对象类型 |
| `targetId` | `string` | 是 | 目标对象 ID |
| `payload` | `object` | 否 | 变更内容 |
| `baseVersion` | `number` | 否 | 变更前版本 |
| `nextVersion` | `number` | 否 | 变更后版本 |
| `deviceId` | `string` | 否 | 发起设备 ID |
| `userId` | `string` | 是 | 用户 ID |
| `status` | `string` | 是 | 同步状态，例如 `pending`、`synced`、`conflict`、`failed` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `syncedAt` | `datetime` | 否 | 同步完成时间 |

## UserAccount：用户账号

`UserAccount` 只保存登录身份和账号生命周期。它不保存密码哈希、头像文件、用户偏好或 Refresh Token。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 用户 UUID |
| `email` | `string` | 是 | 当前生效的登录邮箱，最大 254 字符 |
| `normalizedEmail` | `string` | 是 | 用于唯一索引和登录匹配的规范化邮箱，不进入公开响应 |
| `status` | `UserAccountStatus` | 是 | 账号生命周期状态 |
| `emailVerifiedAt` | `datetime` | 否 | 当前登录邮箱验证完成时间 |
| `disabledAt` | `datetime` | 否 | 账号被禁用的时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 账号软删除时间 |

约束：

- `normalizedEmail` 在未软删除账号中大小写不敏感唯一；跨层只返回 `email`。
- 注册创建 `pending_verification` 账号；验证成功后原子切换为 `active` 并写入 `emailVerifiedAt`。
- `disabled` 与 `deleted` 账号不能登录或刷新会话。

## PasswordCredential：密码凭证

`PasswordCredential` 是 Backend-only 安全模型，只保存不可逆密码哈希。它不得进入 API 响应、Flutter 缓存、Android 安全记录或日志。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联 `UserAccount.id` |
| `passwordHash` | `string` | 是 | 包含算法、盐和参数的 Argon2id PHC 编码字符串 |
| `algorithm` | `string` | 是 | 当前固定为 `argon2id`，用于算法迁移审计 |
| `passwordChangedAt` | `datetime` | 是 | 最近一次设置或修改密码的时间 |

密码规则为 8 至 128 个 Unicode 字符，不强制字符组合；服务端还必须拒绝常见或已泄露密码。注册、修改密码和密码重置使用同一规则。

## UserProfile：个人资料

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 与 `UserAccount` 一对一 |
| `username` | `string` | 是 | 公开用户名，匹配 `[a-z0-9_]{3,24}` |
| `normalizedUsername` | `string` | 是 | 用于唯一索引的规范化用户名，不进入公开响应 |
| `displayName` | `string` | 是 | 1 至 40 个 Unicode 字符的昵称 |
| `avatarAssetId` | `string` | 否 | 当前头像资产 ID；为空表示客户端使用默认头像 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

`normalizedUsername` 在未删除用户中大小写不敏感唯一。资料更新采用最后写入胜出；客户端提交成功后必须使用服务端返回的完整当前用户资料更新正式状态。

## UserPreferences：用户偏好

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 与 `UserAccount` 一对一 |
| `locale` | `string` | 是 | BCP 47 语言标签，例如 `zh-CN` |
| `timezone` | `string` | 是 | IANA 时区 ID，例如 `Asia/Shanghai` |
| `defaultReminderMethods` | `ReminderMethod[]` | 是 | 默认提醒方式；没有默认值时返回空数组 |
| `settings` | `object` | 是 | 非敏感扩展设置；没有设置时返回空对象 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

`settings` 只接受最多 64 个 `snake_case` 键和字符串、数字或布尔标量值；认证凭证、安全状态和未版本化的嵌套对象不得借此字段跨层传输。

## UserSyncState：用户同步状态

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联用户 ID |
| `syncCursor` | `string` | 否 | 服务端增量同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近一次成功同步时间 |
| `updatedAt` | `datetime` | 是 | 状态更新时间 |

该模型属于同步内部状态，不进入当前用户资料响应，也不参与认证判断。

## UserAvatarAsset：头像资产

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 头像资产 UUID |
| `userId` | `string` | 是 | 资产所有者 |
| `storageKey` | `string` | 是 | 对象存储内部键，不进入公开响应 |
| `mimeType` | `string` | 是 | `image/jpeg`、`image/png` 或 `image/webp` |
| `sizeBytes` | `number` | 是 | 原始上传最大 5 MiB |
| `width` | `number` | 是 | 服务端处理后图片宽度 |
| `height` | `number` | 是 | 服务端处理后图片高度，必须等于宽度 |
| `etag` | `string` | 是 | 客户端头像缓存失效标识 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `deletedAt` | `datetime` | 否 | 被替换或删除时间 |

公开响应只暴露 `assetId`、可访问 URL、缩略图 URL、`etag` 和 `updatedAt`。删除头像后 `UserProfile.avatarAssetId = null`，不保存默认头像 URL。

## UserSession：用户会话

`UserSession` 表示一个设备登录会话和一个 Refresh Token family。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 会话 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `tokenFamilyId` | `string` | 是 | Refresh Token 轮换族 ID |
| `platform` | `string` | 是 | 当前为 `android` |
| `deviceName` | `string` | 否 | 用户可识别的设备名称 |
| `appVersion` | `string` | 否 | 创建或最近刷新会话的客户端版本 |
| `expiresAt` | `datetime` | 是 | 会话最长有效时间，默认 30 天 |
| `lastUsedAt` | `datetime` | 是 | 最近一次成功刷新或认证请求时间 |
| `revokedAt` | `datetime` | 否 | 会话撤销时间 |
| `revocationReason` | `SessionRevocationReason` | 否 | 机器可读撤销原因 |
| `createdAt` | `datetime` | 是 | 创建时间 |

修改密码和确认邮箱变更只保留并轮换当前会话，撤销其他会话；密码重置和“退出所有设备”撤销全部会话。

## RefreshTokenGrant：Refresh Token 轮换记录

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | Grant UUID |
| `sessionId` | `string` | 是 | 关联 `UserSession.id` |
| `tokenHash` | `string` | 是 | Refresh Token 的不可逆哈希，不保存明文 |
| `parentGrantId` | `string` | 否 | 上一次轮换 Grant ID |
| `issuedAt` | `datetime` | 是 | 签发时间 |
| `expiresAt` | `datetime` | 是 | 过期时间 |
| `consumedAt` | `datetime` | 否 | 成功换取下一组 Token 的时间 |
| `revokedAt` | `datetime` | 否 | 主动撤销时间 |

每次刷新在同一事务中消费当前 Grant、创建子 Grant 并签发新 Token。再次使用已消费 Grant 时撤销整个 `tokenFamilyId`，返回 `AUTH_REFRESH_TOKEN_REUSED`。

## EmailActionChallenge：邮箱动作挑战

同一个 Challenge 可以同时签发 6 位验证码和邮件链接 Token；两者只保存哈希，任一凭证验证成功都会消费整个 Challenge 并使另一种凭证失效。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | Challenge UUID |
| `userId` | `string` | 是 | 关联用户 |
| `purpose` | `EmailActionPurpose` | 是 | 注册验证、改邮箱或密码重置 |
| `targetEmail` | `string` | 是 | 本次动作接收邮件的地址 |
| `codeHash` | `string` | 否 | 6 位验证码哈希 |
| `linkTokenHash` | `string` | 否 | 深度链接不透明 Token 哈希 |
| `failedAttemptCount` | `number` | 是 | 验证失败次数，初始为 0 |
| `maxAttempts` | `number` | 是 | 固定为 5 |
| `expiresAt` | `datetime` | 是 | 注册/改邮箱 10 分钟，密码重置 15 分钟 |
| `resendAvailableAt` | `datetime` | 是 | 创建后 60 秒 |
| `consumedAt` | `datetime` | 否 | 验证成功时间 |
| `invalidatedAt` | `datetime` | 否 | 重发、取消或安全事件导致的失效时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |

## EmailChangeRequest：邮箱变更申请

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 申请 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `oldEmail` | `string` | 是 | 申请时的当前邮箱快照 |
| `newEmail` | `string` | 是 | 等待验证的新邮箱 |
| `challengeId` | `string` | 是 | 关联 `EmailActionChallenge.id` |
| `status` | `EmailChangeStatus` | 是 | 申请状态 |
| `expiresAt` | `datetime` | 是 | 申请过期时间 |
| `completedAt` | `datetime` | 否 | 新邮箱正式生效时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |

`pending` 阶段原邮箱继续作为唯一有效登录邮箱。验证成功时，在同一事务中替换账号邮箱、更新验证时间、完成申请并轮换当前会话 Token。

## UserAgreementAcceptance：用户协议接受记录

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 接受记录 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `agreementVersion` | `string` | 是 | 用户明确同意的协议版本 |
| `acceptedAt` | `datetime` | 是 | 服务端记录的接受时间 |

注册请求只提交 `agreement_version` 和固定为 `true` 的 `agreement_accepted`；客户端时间不能作为审计事实。

## DatedMessage：投送消息

投送消息用于在指定日期或时间向用户展示内容，例如每日提醒、节日提示或运营消息。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 消息 ID |
| `title` | `string` | 是 | 消息标题 |
| `content` | `string` | 是 | 消息内容 |
| `deliverAt` | `datetime` | 是 | 投送时间 |
| `expireAt` | `datetime` | 否 | 过期时间 |
| `channel` | `string` | 是 | 投送渠道，例如 `in_app`、`notification`、`wechat` |
| `targetUserId` | `string` | 否 | 指定用户 ID；为空可表示全量或规则投放 |
| `targetRule` | `object` | 否 | 投放规则 |
| `status` | `string` | 是 | 状态，例如 `draft`、`scheduled`、`sent`、`cancelled` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

## Anniversary：纪念日

纪念日用于记录生日、节日、恋爱纪念日、结婚纪念日等年度或特定周期事件。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 纪念日 ID |
| `title` | `string` | 是 | 纪念日名称 |
| `date` | `date` | 是 | 用户保存的原始本地日期；年度重复的月、日锚点只从这里读取 |
| `calendarType` | `string` | 是 | V1 只允许 `solar`；`lunar` 保留为协议拒绝入口 |
| `categoryId` | `string` | 否 | 分类 ID |
| `recurrenceId` | `string` | 否 | Anniversary 专用规则引用；`null` 表示一次性，非空必须指向有效 `AnniversaryRecurrence` |
| `note` | `string` | 否 | 备注 |
| `importance` | `Importance` | 否 | 重要性 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

### AnniversaryRecurrence：纪念日年度规则

`AnniversaryRecurrence` 是 Anniversary 独占的轻量年度规则，持久化集合命名为 `anniversary_recurrences`。它不属于 Event v2 的不可变 Recurrence revision，也不保存 `anniversaryId`、月、日、时区、UTC occurrence 或 RRULE；关系真相只保存在 `Anniversary.recurrenceId`。

当前 JSON Storage v2 已激活 `anniversaries.json` 与 `anniversary_recurrences.json`，create/update/delete 通过独立 `anniversary_workflow_transactions.json` 两 Store journal 原子提交。该 journal 不参与也不改变 Event/Reminder 既有六 Store 事务。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `recurrenceId` | `string` | 是 | UUIDv4 主键，由 C++ 在从一次性切换为年度重复或创建年度重复纪念日时生成 |
| `frequency` | `RecurrenceFrequency` | 是 | V1 固定为 `yearly` |
| `interval` | `integer` | 是 | V1 固定为 `1` |
| `createdAt` | `datetime` | 是 | 规则创建时间，ISO 8601 UTC Instant |
| `deletedAt` | `datetime` | 否 | 规则退出使用时的软删除时间；活动规则必须为 `null` |

关系与生命周期不变量：

- 一次性 Anniversary 必须满足 `recurrenceId = null`；年度重复 Anniversary 必须引用一条 `deletedAt = null`、`frequency = yearly`、`interval = 1` 的有效规则。
- 一个活动 `AnniversaryRecurrence` 最多由一个 Anniversary 引用；不得共享规则，也不得在规则中反向保存 `anniversaryId` 形成双重真相源。
- `Anniversary.date` 始终保存用户输入的原始日期及历史年份。规则不得重复保存 `monthOfYear`、`dayOfMonth` 或另一个日期锚点。
- 创建年度重复纪念日时，C++ workflow 必须在同一事务中创建规则并写入 `Anniversary.recurrenceId`；任一步失败都不得留下半提交数据。
- 仍为年度重复时更新标题或日期，保留原 `recurrenceId`。日期变化只替换 `Anniversary.date`，后续查询使用新日期动态计算，不创建新的规则或未来 occurrence。
- 从一次性切换为年度重复时创建新的 UUIDv4 规则并原子建立引用；不得复活过去已软删除的规则。
- 从年度重复切换为一次性时，必须在同一事务中把 `Anniversary.recurrenceId` 设为 `null`，并以同一 UTC Clock 值写入旧规则的 `deletedAt`。事务失败时两项都回滚。
- 读模型发现非空 `recurrenceId` 指向缺失、已软删除或不满足 V1 常量的规则时必须显式失败，不得降级为一次性或静默新建替代规则。

Occurrence 与查询不变量：

- 不持久化 `2027`、`2028`、`2029` 等未来 occurrence，也不为 Anniversary V1 建立 occurrence 状态表。
- C++ 查询以请求 IANA timezone 得到本地今日日期；年度重复的下一次日期由 `Anniversary.date` 的月、日动态计算。今年候选已过去时计算下一年候选。
- 公历 2 月 29 日在非闰目标年落到该年 2 月最后一天；`next_occurrence_date`、`days_remaining` 和 `is_today` 都是查询投影，不回写 Anniversary 或 `anniversary_recurrences`。
- V1 的 Anniversary occurrence 没有可变状态、Reminder 或投递身份。未来增加 Reminder 前，必须另行冻结 occurrence identity、幂等、唯一键和 reconciliation 语义。

## 主要关系

| 关系 | 说明 |
| --- | --- |
| `Event.categoryId -> Category.id` | 日程可归属一个分类 |
| `(Event.recurrenceId, Event.recurrenceRevision) -> (Recurrence.recurrenceId, Recurrence.revision)` | 循环日程指向当前不可变规则 revision |
| `EventOccurrenceState.eventId -> Event.id` | 重复日程某一次 occurrence 的状态归属某个 Event |
| `Habit.categoryId -> Category.id` | 习惯可归属一个分类 |
| `Habit.recurrenceId -> planned Habit recurrence model` | 非 Event 重复语义尚待独立设计，不指向 Event v2 Recurrence |
| `HabitCheckIn.habitId -> Habit.id` | 习惯打卡记录归属某个习惯 |
| `Anniversary.recurrenceId -> AnniversaryRecurrence.recurrenceId` | 一次性纪念日为空；年度重复纪念日独占引用一条有效的 `yearly + interval=1` 规则 |
| `Anniversary.categoryId -> Category.id` | 纪念日可归属一个分类 |
| `Reminder.targetId -> Event/Habit/Anniversary.id` | 提醒可以绑定到不同业务对象；一个业务对象可以有多条提醒 |
| `Notification.reminderId -> Reminder.reminderId` | 通知由提醒触发后生成，用于记录投递结果 |
| `Notification.recoveryBatchId -> ReminderRecoveryBatch.recoveryBatchId` | 恢复摘要或由 Recovery 新建的明细 attempt 归属一个恢复批次；被接管的既有 frozen attempt 不回填该字段 |
| `Notification.resolvedByRecoveryBatchId -> ReminderRecoveryBatch.recoveryBatchId` | Recovery 对既有 frozen attempt 的接管或废弃裁决归属一个恢复批次 |
| `ReminderRecoveryBatch.detailReminderIds/summaryReminderIds -> Reminder.reminderId` | 恢复批次记录明细与摘要覆盖范围 |
| `SearchIndex.targetId -> Event/Habit/Anniversary.id` | 搜索索引映射到被索引对象 |
| `SearchIndex.categoryId -> Category.id` | 分类 ID 是结构化筛选投影；分类名称仅是可重建冗余文本 |
| `AIExtraction.candidateEventId -> Event.id` | AI 可生成待确认的候选日程 |
| `SyncOperation.targetId -> any entity id` | 同步操作记录任意实体的变更 |
| `UserProfile.userId -> UserAccount.id` | 账号与公开资料一对一 |
| `UserPreferences.userId -> UserAccount.id` | 账号与用户偏好一对一 |
| `PasswordCredential.userId -> UserAccount.id` | 密码凭证只属于一个账号且不跨层暴露 |
| `UserProfile.avatarAssetId -> UserAvatarAsset.id` | 个人资料可引用一个当前头像资产 |
| `UserSession.userId -> UserAccount.id` | 一个账号可以存在多个设备会话 |
| `RefreshTokenGrant.sessionId -> UserSession.id` | 一个会话保留连续的 Token 轮换链 |
| `EmailActionChallenge.userId -> UserAccount.id` | 邮箱动作挑战归属账号 |
| `EmailChangeRequest.challengeId -> EmailActionChallenge.id` | 邮箱变更申请使用独立挑战确认新邮箱 |
| `UserAgreementAcceptance.userId -> UserAccount.id` | 一个用户可保留多个协议版本的接受记录 |

## 未来待确认问题

- Event v3 是否需要支持 `interval > 1`、有界 `endAt/count`、Yearly/Custom 或 iCalendar RRULE；这些能力不得静默塞入 v2。
- Habit 的重复规则仍需独立设计；Anniversary V1 的年度规则和日期锚点已冻结，但 Anniversary Reminder 的 occurrence 身份与生成语义仍需单独设计，不能照搬 Event v2。
- Category 的用户归属范围、名称唯一性、系统默认分类及预设生命周期仍待账号/同步架构确认；当前 Flutter Fake 默认项不构成领域决策。
- `DatedMessage` 未来是只做本地投送，还是也需要云端运营投放能力。
- `AIExtraction.extractedData` 未来是否需要拆成强类型表，还是先以 JSON 保存。
- 后续加入 MFA 时是否把 V1 的 8 位密码下限提升到单因素认证推荐基线。

## 已确认决策

- `Reminder` 作为独立实体保存，通过 `targetType` 和 `targetId` 关联 `Event`、`Habit`、`Anniversary`。
- `Event` 可以有多个提醒时间。概念上是提醒时间列表，存储上是多条 `Reminder`。
- `Event.status` 只表达整个日程或整个重复系列的生命周期状态；重复日程单次 occurrence 状态使用 `EventOccurrenceState`。
- Native Contract 主版本为 `2`，v1 payload 和 v1 Calendar Core JSON 不兼容；v1 数据不再保留（2026-08-08 用户决策），确认旧正式目录为 v1 后直接清理并初始化空 v2，不做字段迁移或静默混读。
- Event 使用互斥的 UTC Instant / 本地 date 时间结构，且所有 Event 必须保存有效 IANA timezone。
- Event Recurrence 使用不可变 `(recurrenceId, revision)`；occurrence、滚动 Reminder 和 delivery 使用固定 UUIDv5 身份规范，不增加 `reminderChainId`。
- Anniversary 年度重复使用独立 `AnniversaryRecurrence`：只保存 `yearly + interval=1`，月/日锚点来自 `Anniversary.date`，未来 occurrence 由 C++ 查询时动态计算。
- 普通单次 Reminder 保持 UUIDv4、绝对触发、历史保留且不创建 successor；重复 Reminder v2 仅支持 popup。
- Notification 使用 prepare/finalize 两阶段 attempt，Android 系统通知以 `deliveryId` 作为稳定 tag。
- 恢复窗口固定为 72 小时、明细全局上限 20 条；更早 occurrence 只计数，不批量生成 Reminder。
- 严格早于恢复窗口的已物化 open Reminder 进入 `expired`；prepared attempt 由 `planRecovery` 原子接管或废弃，投递 payload 保持冻结。
- `Habit` 的坚持日期、完成次数、连续天数统计来源于 `HabitCheckIn`，不直接塞进 `Habit` 本体。
- 新的正式 Category writer 使用 UUIDv4；已激活 Event v2 的 `categoryId` 仍按稳定不透明字符串读取，兼容早期 Flutter 已写入的非 UUID 引用。无法解析到活动 Category 时保留原始 ID，并在聚合投影中返回空分类。
- Category 创建要求名称与颜色，`description/icon/sortOrder` 可空；列表只返回活动记录并使用 `sortOrder(null last) -> createdAt -> id` 的稳定顺序。
- Category JSON Storage v2 已冻结为独立 `categories.json` 与严格 `CategoryStorageRecord`，当前代码状态为 `implemented_unintegrated`、发布状态为 `blocked`；没有历史正式 Store 或 Fake migration，已有磁盘实现不能在门禁完成前被视为正式产品闭环。
- 当前阶段先不上 SQL，优先保证项目整体可运行。
- 当前先做好本地能力，AI 和云端同步暂缓，但保留相关接口和数据模型。
- 旧 `UserData` 草案拆分为 `UserAccount`、`UserProfile`、`UserPreferences` 和 `UserSyncState`；认证安全状态使用独立 Backend-only 模型。
- 登录标识只允许邮箱；用户名只作为大小写不敏感唯一的公开资料标识。
- 邮箱验证和密码重置同时支持手动验证码与邮件链接 Token。
- 当前用户资料更新采用最后写入胜出，客户端以服务端成功响应为准。
- Access Token 只保存在 Flutter 内存；Refresh Token 只在刷新请求期间短暂进入 Flutter，并由 Android 安全存储长期保存。
- 密码重置撤销全部会话且要求重新登录；修改密码与确认邮箱变更保留并轮换当前会话、撤销其他设备。

## 数据类型评审

整体上，当前字段类型可以满足本地优先阶段，但建议按下面的边界理解：

| 类型 | 适合保存 | 注意点 |
| --- | --- | --- |
| `string` | ID、标题、枚举值、来源、时区 | 枚举字段后续应收敛为固定值 |
| `datetime` | 精确到时间点的字段，例如开始时间、提醒时间、投递时间 | 建议内部统一 UTC，展示按用户时区转换 |
| `date` | 只关心日期的字段，例如习惯打卡日期、纪念日日期 | 需要按用户本地时区解释 |
| `boolean` | 开关类字段，例如是否全天、是否启用 | 不适合表达多状态流程 |
| `number` | 次数、排序、版本号、置信度 | 金额或高精度数值未来再单独处理 |
| `object` | AI 结果、同步 payload、用户设置等暂未稳定结构 | 当前可预留，核心本地模型尽量少依赖 |
| `string[]` / `number[]` | 多选提醒方式、周几重复 | 上 SQL 时可能需要拆表或用 JSON |

需要补充的主要结构是 `HabitCheckIn`。没有它，`Habit` 只能表达“我要养成什么习惯”，无法可靠表达“哪些日期坚持了、坚持了多少天、哪天漏了”。

## Reminder 与 Notification 的区别

| 对比项 | `Reminder` | `Notification` |
| --- | --- | --- |
| 核心问题 | 未来什么时候要提醒 | 某一次提醒是否投递成功 |
| 数据性质 | 待执行任务 | 执行结果日志 |
| 创建时机 | 用户创建或更新业务对象后生成；重复 Event 只滚动生成当前合法实例 | `prepare_delivery` 时先创建 attempt，系统投递后 finalize |
| 谁会扫描 | Reminder Engine / Alarm Scheduler | 一般不扫描，只用于历史、排错、统计 |
| 是否影响未来提醒 | 是 | 否 |
| 典型状态 | `pending`、`scheduled`、`sent`、`failed`、`cancelled`、`expired` | `prepared`、`sent`、`failed`、`abandoned` |
| 例子 | 明天 9:00 提醒我开会 | 明天 9:00 的会议提醒已经弹窗成功 |

一句话：`Reminder` 是“待办的提醒任务”，`Notification` 是“提醒投递后的回执”。

## iCalendar RRULE 说明

RRULE 是 iCalendar 标准里的重复规则写法，用一个字符串描述复杂重复逻辑。例如：

```text
FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR
```

上面的意思是每周一、周三、周五重复。

Native Contract v2 明确拒绝客户端 `rrule` 字段，只执行 interval=1 的 Daily/Weekly/Monthly。Yearly/Custom 枚举仅作为稳定入口保留并返回 `FEATURE_NOT_IMPLEMENTED`。未来若要和系统日历、Google Calendar、Outlook 等互通，必须提升协议版本并定义导入、导出、冲突和历史数据策略。

## 提醒调度建议

采用 `业务对象/Recurrence -> 滚动 Reminder -> Dispatcher Alarm -> Notification attempt` 的流程。

1. 用户创建 `Event`、`Habit` 或 `Anniversary`。
2. 单次业务对象创建普通 Reminder；重复 Event 根据模板只确保当前或下一条合法滚动 Reminder 存在。
3. 后台扫描 `Reminder`，只取 `isEnabled = true`、未软删除且 `status = pending` 的记录；永久 `failed` 不进入重试扫描。
4. Android Alarm Scheduler 注册 Dispatcher Alarm 后，以本次读取的 `expectedRemindAt` 调用 `mark_scheduled`；C++ 仅在当前 `remindAt` 仍相等时标记为 `scheduled`，否则返回 `REMINDER_SCHEDULE_CONFLICT` 并由 Kotlin 重新 reconcile。
5. 到点后 C++ `prepare_delivery` 先创建或复用 attempt，Kotlin 再展示系统通知，最后 C++ `finalize_delivery` 原子更新 Notification、当前 Reminder 和 successor。
6. 领域 transaction 提交后 Android 只执行 reconcile；AlarmManager 不是第二真相源。

## Contract v2、Storage v2 与事务边界

| 版本域 | v1 reader 读 v2 | v2 reader 读 v1 | 升级策略 |
| --- | --- | --- | --- |
| Native Contract | 拒绝 | 拒绝 | Flutter、Kotlin、JNI、C++ 在同一发行版本同步升级 |
| Calendar Core JSON | 不支持 | 不支持 | 确认 v1 正式目录后清理，创建空 v2；不迁移业务数据 |
| Backend API | 不受影响 | 不受影响 | 继续使用独立 Backend Contract v1 |
| 导入/导出/备份 | 不复用 Native 版本 | 不复用 Native 版本 | 后续使用独立文件格式版本和迁移链 |

首次升级只允许对解析并确认属于 v1 Calendar Core 的正式目录执行清理；确认或新目录初始化任一步失败都返回错误且不得删除、覆盖或部分迁移数据。v1 数据不归档、不保留，回滚到旧 App 会失去本地数据（已接受）；旧 App 仍禁止打开 v2 目录。

每个 v2 JSON store 根对象必须显式包含 `storage_version = 2` 和该 store 的唯一集合字段；未知版本、未知根字段或任一损坏记录都使整个 store 加载失败。Storage record 使用独立 codec，不得直接把 Contract Response Schema 当作数据库实体。

`workflow_transactions.json` 的 prepared 记录至少保存 `transactionId/operation/intentVersion/intent/affectedStores/state/preparedAt/committedAt`。每个 `operation + intentVersion` 必须选择严格的内部 codec；当前 intent v1 对所有已声明 operation 使用同一个精确的完整 after-state codec，`afterStores/affectedStores` 只允许六个逻辑 store 名，不允许文件名。完整验证后的 after-state 与外层 transaction/operation/Clock 字段共同支持幂等重放；未知字段、operation 或版本不得用默认值恢复。

以下操作必须是单个 C++ workflow transaction，并通过 `prepare -> 幂等应用各 Repository -> commit` journal 在启动时重放未完成事务：

- Event + Recurrence revision + 首个滚动 Reminder 的创建或系列更新；
- occurrence 状态变化 + Reminder 取消/恢复 + successor 创建；
- delivery finalize + Notification attempt + 当前 Reminder + successor；
- recovery batch + 窗口内 Reminder + 摘要覆盖状态；
- 系列完成、取消、软删除和重新打开。
