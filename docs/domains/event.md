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

## 枚举定义

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

