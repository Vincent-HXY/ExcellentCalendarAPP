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

## 拆分文件索引

全部枚举汇总：[enums.md](enums.md)

| 数据结构 | 文件 |
| --- | --- |
| `Event` | [event.md](event.md) |
| `EventOccurrenceState` | [event_occurrence_state.md](event_occurrence_state.md) |
| `Habit` | [habit.md](habit.md) |
| `HabitCheckIn` | [habit_check_in.md](habit_check_in.md) |
| `Reminder` | [reminder.md](reminder.md) |
| `Category` | [category.md](category.md) |
| `Recurrence` | [recurrence.md](recurrence.md) |
| `Notification` | [notification.md](notification.md) |
| `ReminderRecoveryBatch` | [reminder_recovery_batch.md](reminder_recovery_batch.md) |
| `SearchIndex` | [search_index.md](search_index.md) |
| `AIExtraction` | [ai_extraction.md](ai_extraction.md) |
| `SyncOperation` | [sync_operation.md](sync_operation.md) |
| `UserAccount` | [user_account.md](user_account.md) |
| `PasswordCredential` | [password_credential.md](password_credential.md) |
| `UserProfile` | [user_profile.md](user_profile.md) |
| `UserPreferences` | [user_preferences.md](user_preferences.md) |
| `UserSyncState` | [user_sync_state.md](user_sync_state.md) |
| `UserAvatarAsset` | [user_avatar_asset.md](user_avatar_asset.md) |
| `UserSession` | [user_session.md](user_session.md) |
| `RefreshTokenGrant` | [refresh_token_grant.md](refresh_token_grant.md) |
| `EmailActionChallenge` | [email_action_challenge.md](email_action_challenge.md) |
| `EmailChangeRequest` | [email_change_request.md](email_change_request.md) |
| `UserAgreementAcceptance` | [user_agreement_acceptance.md](user_agreement_acceptance.md) |
| `DatedMessage` | [dated_message.md](dated_message.md) |
| `Anniversary` | [anniversary.md](anniversary.md) |

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
