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
| `templateKey` | `string` | 否 | Anniversary 分支必填的稳定模板 UUIDv5；Event/Habit 分支为空 |
| `occurrenceDate` | `date` | 否 | Anniversary 分支必填的当地 occurrence 日期；Event/Habit 分支为空 |
| `advanceDays` | `integer` | 否 | Anniversary 分支必填，范围 `0..365` |
| `localTime` | `string` | 否 | Anniversary 分支必填，格式 `HH:mm` |
| `timezoneMode` | `string` | 否 | Anniversary 分支固定 `follow_device` |
| `fulfillmentDeliveryId` | `string` | 否 | Anniversary `sent` 时必填；证明提醒义务由哪个真实 delivery 履约 |
| `remindAt` | `datetime` | 是 | 提醒触发时间 |
| `methods` | `ReminderMethod[]` | 是 | 成功持久化时恰好一个值：普通 Reminder 为 `[popup]` 或 `[ring]`，重复 Reminder 固定为 `[popup]` |
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

- 普通 Reminder 的 `recurrenceRevision/occurrenceKey/occurrenceStartAt` 必须全部为空，`reminderId` 通常使用 UUIDv4；成功态 `methods` 只允许恰好一个 `[popup]` 或 `[ring]`，不再创建多渠道 Reminder。`wechat` 保留为稳定枚举入口，但当前请求返回 `UNSUPPORTED_REMINDER_METHOD`，不得持久化为成功记录。
- `ring` 只允许关联活动、非全天、非重复的普通 Event；全天 Event、重复 Event、Habit 与 Anniversary 的 ring 请求必须在领域入口失败。`popup` 与 `ring` 互斥，`['popup','ring']`、空数组、重复值和未知值均为非法输入。
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
- Anniversary Reminder 必须满足：`targetType=anniversary`、`occurrenceKey/templateKey/occurrenceDate/advanceDays/localTime/timezoneMode` 全部存在，`timezoneMode=follow_device`、`methods=[popup]`，而 `recurrenceRevision/occurrenceStartAt/advanceMinutes` 全部为空。Event/Habit 分支必须把这些 Anniversary 专用字段全部写成 `null`。
- Anniversary Reminder ID 按 `contracts/identity.yaml` 由 target、occurrence 和 template 生成。同一模板链任何时刻最多一条 open Reminder；相同 ID 与相同业务内容重放幂等，内容冲突返回 `REMINDER_IDEMPOTENCY_CONFLICT`。
- Anniversary 的 `sent` 表示该 Reminder 的义务已被一个真实成功的 Notification 履行。正常单条投递和 catch-up 聚合都必须写非空 `fulfillmentDeliveryId`；聚合时多个 Reminder 可以共享该值，但不能为未展示的成员伪造独立 Notification attempt。
- Anniversary 可重试失败保持 `pending` 且不创建 successor；永久失败或 occurrence 日末过期进入终态，并为年度模板分别创建首个未来 successor。日末过期使用 `anniversary_occurrence_elapsed`，不改变普通 Event/Ring 的 `recovery_window_elapsed` 语义。
- Anniversary 单条或聚合 attempt 的 `finalizeDelivery` 在加载 prepared attempt 后要求非空、有效的当前设备 IANA timezone；共享 Wire 字段保持可选以兼容 Event、Ring 和普通 Recovery。第一次成功 finalize 使用该时区计算并持久化年度 successor；journal/transaction 已提交后的重放只返回原 successor，不使用后来传入的时区重新计算。timezone 不参与 Reminder、delivery 或 attempt identity。
- `anniversary_paused` 与 `anniversary_template_disabled` 只允许 workflow 在仍有意义时恢复确定性任务；`anniversary_updated`、`anniversary_template_replaced` 与 `anniversary_deleted` 不可恢复。所有原因都保留取消审计。

## Ring 与稍后提醒

- Ring 继续复用 `Reminder -> Notification attempt` 的两阶段投递，不创建第二套领域投递记录。Ring attempt 的 `sent` 只能表示 Android 前台控制通知已经展示，并且声音或振动至少一种真实启动；仅完成 prepare、仅启动 Service 或仅展示控制通知都不能 finalize 为 `sent`。
- Android `ActiveRingSession` 是可恢复的平台会话，不是 Reminder 或 Notification 的第二真相源。`stop_active` 只停止/移除 Android 会话项，不完成 Event、不改变 Reminder/Notification 的既有终态，也不保存“关闭响铃”历史。
- `ring.complete_item` 先通过现有 `event.complete` workflow 完成对应普通 Event，再从 Android 会话移除该项；Event 完成失败时会话项必须保留。
- `ring.snooze_active` 对每个 item 调用 C++ `reminder.snooze(source_delivery_id)`。稍后时长固定为 10 分钟，由首次成功调用时的 C++ Clock 计算；Flutter/Kotlin 不提交分钟数。
- snooze Reminder 使用 `UUIDv5(reminder namespace, [source_delivery_id, "snooze", 10])`，方法固定为 `[ring]`。首次调用原子保存 `now + 10min`，同一 `source_delivery_id` 的重放返回完全相同的 Reminder 与原 `remindAt`，不得按重试时间顺延。
- snooze 前必须确认源 delivery 是已成功的普通 Event ring attempt，且源 Reminder 与 Event 仍存在、未删除、Event 仍活动且保持非全天/非重复；否则返回 `REMINDER_SNOOZE_NOT_ALLOWED`，不创建对象。

## 枚举定义

### ReminderMethod

提醒方式。

| 值 | 说明 |
| --- | --- |
| `ring` | 响铃 |
| `popup` | 弹窗 |
| `wechat` | 微信提醒 |

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
| `anniversary_paused` | 有条件 | Anniversary 总开关关闭；恢复时只复用仍处于有效窗口或未来的确定性任务 |
| `anniversary_template_disabled` | 有条件 | 单条模板关闭；重新开启时按当前时间选择同一 occurrence 或下一 occurrence |
| `anniversary_updated` | 否 | 日期或一次性/年度规则变化终结旧链 |
| `anniversary_template_replaced` | 否 | 模板删除或 identity 字段变化终结旧链 |
| `anniversary_deleted` | 否 | Anniversary 已软删除 |

恢复仅适用于 `remindAt > reopenedAt` 的同一条 Reminder；不得生成新 ID，也不执行 72 小时补发。

`occurrence_reopened` 不能由普通 `reminder.enable` 恢复。原 occurrence 再次终结，或其 Reminder 成功投递/永久失败时，滚动 workflow 仅在该后继仍在未来时恢复同一确定性 ID；已经过去则保留取消审计并寻找首个未来 occurrence。系列更新、完成、取消或删除可以用相应系列原因覆盖它。

### ReminderExpirationReason

| 值 | 说明 |
| --- | --- |
| `recovery_window_elapsed` | `planRecovery` 判定已物化 Reminder 严格早于 72 小时恢复窗口 |
| `anniversary_occurrence_elapsed` | 当前设备时区已到 occurrence 次日 00:00，Anniversary 本次任务不再补发 |

