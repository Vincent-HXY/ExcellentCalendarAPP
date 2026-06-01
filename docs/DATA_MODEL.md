# Excellent Calendar 数据结构模型草案

> 本文档用于审阅核心业务对象的数据结构。字段类型、枚举值和命名后续可根据实现语言、数据库 schema 或 API 协议再统一调整。

## 通用约定

- `id`：实体唯一标识，建议使用 UUID。
- `createdAt`：创建时间。
- `updatedAt`：最后更新时间。
- `deletedAt`：软删除时间，可空。
- `source`：数据来源，例如 `manual`、`ai_extraction`、`sync`、`import`。
- 时间字段建议统一存储为 ISO 8601 字符串或 UTC 时间戳，展示时再按用户时区转换。

## 当前阶段约定

- 当前先不实现 SQL schema，优先保证项目整体可运行。
- 本地能力优先，AI、云端同步、云端投送暂时不做完整实现。
- `AIExtraction`、`SyncOperation`、`UserData` 等模型先作为未来能力预留，字段可先保持文档级设计。
- `Reminder` 作为独立实体保存，不嵌入 `Event`、`Habit`、`Anniversary`。
- 一个 `Event`、`Habit` 或 `Anniversary` 可以关联多条 `Reminder`。业务上可以理解为“提醒时间列表”，存储上是多条提醒记录。

## 模型职责总览

| 模型 | 当前阶段用途 | 数据性质 | 是否本地优先需要 |
| --- | --- | --- | --- |
| `Event` | 保存日程本身，例如会议、临时事项、规律事项 | 主业务数据 | 是 |
| `Habit` | 保存习惯定义，例如每天阅读、每周运动 | 主业务数据 | 是 |
| `HabitCheckIn` | 保存习惯每天是否完成、完成次数和打卡时间 | 行为记录 | 是 |
| `Reminder` | 保存未来需要触发的提醒任务 | 调度任务 | 是 |
| `Notification` | 保存提醒触发后的投递结果 | 投递日志 | 是 |
| `Category` | 保存分类、颜色和排序 | 配置数据 | 是 |
| `Recurrence` | 保存重复规则，例如每天、每周、每月 | 规则数据 | 是 |
| `SearchIndex` | 保存搜索用的冗余文本 | 索引数据 | 可以后置 |
| `AIExtraction` | 保存 AI 从文本、图片中解析出的候选结果 | 未来预留 | 暂缓实现 |
| `SyncOperation` | 保存本地与云端同步操作记录 | 未来预留 | 暂缓实现 |
| `UserData` | 保存用户设置、默认提醒方式、同步游标 | 用户配置 | 先做本地设置 |
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
| `pending` | 待投递 |
| `sent` | 已投递 |
| `failed` | 投递失败 |
| `cancelled` | 已取消 |

### ReminderStatus

提醒任务状态。提醒扫描只需要关注 `Reminder` 表中启用且未完成的记录。

| 值 | 说明 |
| --- | --- |
| `pending` | 待调度，尚未注册到系统闹钟 |
| `scheduled` | 已调度，已经注册到 Android AlarmManager 或其他投递通道 |
| `sent` | 已触发或已发送 |
| `failed` | 调度或发送失败 |
| `cancelled` | 已取消 |

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

## Event：日程

日程是日历中的核心事项，可以设置分类、重复规则和重要性。日程分两种，一种是临时日程，用于记录突发临时时间；一个是规律日程，用于记录相对规律的事件。

说明：

- 全天日程表示这个日程只关心日期，不关心具体几点到几点。例如生日、放假、出差当天、某一天要办但没有固定时间的事项。
- 日程本身不直接保存提醒方式和提醒时间。只要日程需要提醒，就在 `Reminder` 表中创建一条或多条提醒任务。
- 如果一个日程有多个提醒时间，例如提前 1 天、提前 1 小时、开始时各提醒一次，则创建 3 条 `Reminder`，它们的 `targetType = event` 且 `targetId = Event.id`。
- 软删除表示用户删除后先不从数据库物理移除，而是写入 `deletedAt`。这样方便撤销删除、同步删除状态、排查误删。正常查询默认只显示 `deletedAt` 为空的记录。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 日程 ID |
| `title` | `string` | 是 | 标题 |
| `content` | `string` | 否 | 内容、备注或详情 |
| `startAt` | `datetime` | 是 | 日程开始时间 |
| `endAt` | `datetime` | 否 | 日程结束时间 |
| `isAllDay` | `boolean` | 是 | 是否全天日程 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `hasRecurrence` | `boolean` | 是 | 是否循环 |
| `recurrenceId` | `string` | 否 | 重复规则 ID；仅当 `hasRecurrence = true` 时存在 |
| `categoryId` | `string` | 否 | 分类 ID |
| `importance` | `Importance` | 否 | 重要性 |
| `location` | `string` | 否 | 地点 |
| `timezone` | `string` | 否 | 时区，例如 `Asia/Shanghai` |
| `source` | `string` | 是 | 来源，例如来自于微信，手动添加 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

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
| `recurrenceId` | `string` | 是 | 执行频率或打卡规则 |
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

提醒是独立实体，也是提醒扫描和调度的主表。创建日程、习惯、纪念日时，如果用户选择需要提醒，就在这里创建提醒任务。后续后台任务只扫描这张表，把即将到来的提醒交给 Android Alarm Scheduler、微信推送或应用内通知。

职责边界：

- `Reminder` 回答“未来什么时候需要提醒、提醒谁、用什么方式提醒”。
- `Reminder` 是待执行任务，适合被后台扫描、注册系统闹钟、失败重试。
- `Reminder` 不负责记录通知最终有没有展示成功；投递结果由 `Notification` 记录。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 提醒 ID |
| `targetType` | `string` | 是 | 关联对象类型，例如 `event`、`habit`、`anniversary` |
| `targetId` | `string` | 是 | 关联对象 ID |
| `remindAt` | `datetime` | 是 | 提醒触发时间 |
| `methods` | `ReminderMethod[]` | 是 | 提醒方式 |
| `advanceMinutes` | `number` | 否 | 提前提醒分钟数 |
| `message` | `string` | 否 | 提醒文案 |
| `isEnabled` | `boolean` | 是 | 是否启用 |
| `status` | `ReminderStatus` | 是 | 提醒任务状态 |
| `scheduledAt` | `datetime` | 否 | 实际注册到系统闹钟或投递通道的时间 |
| `lastTriggeredAt` | `datetime` | 否 | 最近一次触发时间 |
| `failureReason` | `string` | 否 | 调度或发送失败原因 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

## Category：分类

分类用于组织日程、习惯、纪念日等对象。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 分类 ID |
| `name` | `string` | 是 | 分类名称 |
| `color` | `string` | 否 | 分类颜色，例如十六进制色值 |
| `icon` | `string` | 否 | 图标标识 |
| `sortOrder` | `number` | 否 | 排序值 |
| `isDefault` | `boolean` | 是 | 是否默认分类 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

## Recurrence：重复规则

重复规则用于描述日程、习惯或纪念日的循环方式。如果后面需要涉及到重复与节假日呢？

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 重复规则 ID |
| `frequency` | `RecurrenceFrequency` | 是 | 重复频率 |
| `interval` | `number` | 是 | 间隔，例如每 2 周 |
| `daysOfWeek` | `number[]` | 否 | 周几重复，取值建议 `1-7` |
| `dayOfMonth` | `number` | 否 | 每月第几天 |
| `monthOfYear` | `number` | 否 | 每年第几月 |
| `startAt` | `datetime` | 是 | 规则生效时间 |
| `endAt` | `datetime` | 否 | 规则结束时间 |
| `count` | `number` | 否 | 最大重复次数 |
| `timezone` | `string` | 否 | 时区 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

## Notification：通知

通知是提醒被触发后的投递记录，用于记录某一次弹窗、响铃、微信消息或系统通知是否成功。扫描提醒时不应该以这张表为入口。

职责边界：

- `Notification` 回答“某一次提醒是否真的投递了、什么时候投递、失败原因是什么”。
- `Notification` 是结果日志，不参与未来提醒扫描。
- 本地系统通知、响铃、弹窗、微信提醒都可以生成 `Notification` 记录。
- 由 `Reminder` 触发的通知必须关联 `reminderId`；未来如果 `DatedMessage` 也走通知投递，可以通过 `targetType` 和 `targetId` 关联消息本体。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 通知 ID |
| `reminderId` | `string` | 否 | 关联提醒 ID；由提醒触发时必填 |
| `targetType` | `string` | 是 | 关联对象类型 |
| `targetId` | `string` | 是 | 关联对象 ID |
| `method` | `ReminderMethod` | 是 | 通知渠道 |
| `title` | `string` | 是 | 通知标题 |
| `body` | `string` | 否 | 通知正文 |
| `plannedAt` | `datetime` | 是 | 原计划投递时间 |
| `sentAt` | `datetime` | 否 | 实际发送时间 |
| `status` | `NotificationStatus` | 是 | 通知状态 |
| `failureReason` | `string` | 否 | 失败原因 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

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
| `categoryName` | `string` | 否 | 分类名称冗余字段 |
| `occurAt` | `datetime` | 否 | 发生时间，用于时间排序 |
| `updatedAt` | `datetime` | 是 | 索引更新时间 |

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

## UserData：用户数据

用户数据保存用户级配置、设备信息和同步游标等内容。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 用户 ID |
| `displayName` | `string` | 否 | 昵称 |
| `timezone` | `string` | 是 | 默认时区 |
| `locale` | `string` | 否 | 语言区域 |
| `defaultReminderMethods` | `ReminderMethod[]` | 否 | 默认提醒方式 |
| `settings` | `object` | 否 | 用户设置 |
| `syncCursor` | `string` | 否 | 同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近同步时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

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
| `date` | `date` | 是 | 纪念日日期 |
| `calendarType` | `string` | 否 | 日历类型，例如 `solar`、`lunar` |
| `categoryId` | `string` | 否 | 分类 ID |
| `recurrenceId` | `string` | 否 | 重复规则 ID，通常为每年 |
| `note` | `string` | 否 | 备注 |
| `importance` | `Importance` | 否 | 重要性 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

## 主要关系

| 关系 | 说明 |
| --- | --- |
| `Event.categoryId -> Category.id` | 日程可归属一个分类 |
| `Event.recurrenceId -> Recurrence.id` | 循环日程关联一条重复规则 |
| `Habit.categoryId -> Category.id` | 习惯可归属一个分类 |
| `Habit.recurrenceId -> Recurrence.id` | 习惯通过重复规则描述执行频率 |
| `HabitCheckIn.habitId -> Habit.id` | 习惯打卡记录归属某个习惯 |
| `Reminder.targetId -> Event/Habit/Anniversary.id` | 提醒可以绑定到不同业务对象；一个业务对象可以有多条提醒 |
| `Notification.reminderId -> Reminder.id` | 通知由提醒触发后生成，用于记录投递结果 |
| `SearchIndex.targetId -> Event/Habit/Anniversary.id` | 搜索索引映射到被索引对象 |
| `AIExtraction.candidateEventId -> Event.id` | AI 可生成待确认的候选日程 |
| `SyncOperation.targetId -> any entity id` | 同步操作记录任意实体的变更 |

## 未来待确认问题

- `Recurrence` 未来是否需要兼容 iCalendar RRULE 标准。
- `DatedMessage` 未来是只做本地投送，还是也需要云端运营投放能力。
- `AIExtraction.extractedData` 未来是否需要拆成强类型表，还是先以 JSON 保存。

## 已确认决策

- `Reminder` 作为独立实体保存，通过 `targetType` 和 `targetId` 关联 `Event`、`Habit`、`Anniversary`。
- `Event` 可以有多个提醒时间。概念上是提醒时间列表，存储上是多条 `Reminder`。
- `Habit` 的坚持日期、完成次数、连续天数统计来源于 `HabitCheckIn`，不直接塞进 `Habit` 本体。
- 当前阶段先不上 SQL，优先保证项目整体可运行。
- 当前先做好本地能力，AI 和云端同步暂缓，但保留相关接口和数据模型。

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
| 创建时机 | 用户创建或更新日程、习惯、纪念日后生成 | 提醒触发、系统通知展示、微信投递后生成 |
| 谁会扫描 | Reminder Engine / Alarm Scheduler | 一般不扫描，只用于历史、排错、统计 |
| 是否影响未来提醒 | 是 | 否 |
| 典型状态 | `pending`、`scheduled`、`failed`、`cancelled` | `pending`、`sent`、`failed`、`cancelled` |
| 例子 | 明天 9:00 提醒我开会 | 明天 9:00 的会议提醒已经弹窗成功 |

一句话：`Reminder` 是“待办的提醒任务”，`Notification` 是“提醒投递后的回执”。

## iCalendar RRULE 说明

RRULE 是 iCalendar 标准里的重复规则写法，用一个字符串描述复杂重复逻辑。例如：

```text
FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR
```

上面的意思是每周一、周三、周五重复。

暂时不需要强制兼容 RRULE。当前可以先用 `Recurrence` 表里的结构化字段表达常见重复规则，例如每天、每周、每月、每年、自定义间隔。未来如果要和系统日历、Google Calendar、Outlook 等外部日历互通，再考虑增加 `rrule` 字段保存标准字符串。

## 提醒调度建议

建议采用 `业务对象 -> Reminder -> Android Alarm Scheduler -> Notification` 的流程。

1. 用户创建 `Event`、`Habit` 或 `Anniversary`。
2. 如果需要提醒，Reminder Engine 根据业务对象时间、提前量、重复规则生成一条或多条 `Reminder`。
3. 后台扫描 `Reminder` 表，只取 `isEnabled = true`、`status in (pending, failed)`、`remindAt` 在未来扫描窗口内的记录。
4. Android Alarm Scheduler 将这些提醒注册到系统闹钟，并把成功注册的提醒标记为 `scheduled`。
5. 到点后原生侧触发提醒，Notification Service 展示通知，并写入一条 `Notification` 投递记录。
6. 如果是重复日程、习惯或纪念日，Reminder Engine 再计算下一次提醒，并创建新的 `Reminder`。
