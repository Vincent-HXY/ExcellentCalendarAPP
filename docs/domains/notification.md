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

## 枚举定义

### ReminderMethod

提醒方式。

| 值 | 说明 |
| --- | --- |
| `ring` | 响铃 |
| `popup` | 弹窗 |
| `wechat` | 微信提醒 |

### NotificationStatus

通知投递状态。`Notification` 不是提醒扫描的主表，而是一次提醒被系统、微信或应用内渠道投递后的记录。

| 值 | 说明 |
| --- | --- |
| `prepared` | 已由 C++ 创建投递 attempt，等待 Kotlin 调用系统投递 |
| `sent` | 已投递 |
| `failed` | 本次 attempt 已失败；是否重试由 `failureClass` 决定 |
| `abandoned` | Recovery 已原子废弃该 attempt；Android 必须取消旧 delivery tag，旧 attempt 不再允许 finalize |

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

