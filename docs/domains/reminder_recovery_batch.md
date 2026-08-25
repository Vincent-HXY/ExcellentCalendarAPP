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
| `windowOverflowCount` | `integer` | 是 | 为兼容 v2 保留的字段名；表示窗口内进入摘要的总 Reminder 数，既包括超过 5 分钟的 ring，也包括超过全局 20 条上限的其他候选 |
| `summaryDeliveryId` | `string` | 否 | 有摘要时的稳定 delivery UUIDv5 |
| `anniversaryCatchUpGroups` | `AnniversaryCatchUpGroup[]` | 是 | Anniversary occurrence 专用聚合组；与普通 detail/summary 成员互斥 |
| `status` | `ReminderRecoveryBatchStatus` | 是 | 批次状态 |
| `completedAt` | `datetime` | 否 | 批次完成时间 |

约束：

- `recoveryRequestId` 唯一；重复调用返回同一批次。同一时间最多一个 `in_progress` 批次，否则返回 `RECOVERY_BATCH_CONFLICT`。
- `windowStartAt = startedAt - 72h`。Ring 的 5 分钟边界由 C++ 从同一个已持久化 `startedAt` 推导，不新增持久化字段；宽限区间为闭区间 `[startedAt - 5min, startedAt]`：迟到 4:59 与恰好 5:00 仍具备明细资格，迟到 5:01 强制进入摘要。
- 先把 `remindAt < startedAt - 5min` 的窗口内 ring 放入摘要；再将其余 popup 与宽限窗 ring 按 `remindAt desc, reminderId desc` 选最近 20 条明细，超出部分作为 overflow 摘要。因此宽限窗 ring 仍受全局 20 条安全上限约束。
- `detailReminderIds` 与 `summaryReminderIds` 必须互斥并覆盖全部窗口内候选；`windowOverflowCount = summaryReminderIds.length`。这里的 legacy 名称不再只表示容量溢出，而是 ring 超时与容量溢出的合计摘要数；`planRecovery.detailReminders` 必须与 `detailReminderIds` 同序且一一对应。
- `planRecovery.preparedAttemptResolutions` 必须完整、稳定地返回本批次裁决的既有 prepared attempts：最终进入明细的至多 20 条为 `adopted_detail`，窗口内被 ring 宽限规则或数量上限归入摘要的为 `abandoned_to_summary`，严格早于 72 小时窗口的为 `abandoned_outside_window`。后两者的 `replacementDeliveryId` 等于 `summaryDeliveryId`。
- 5 分钟宽限窗外的既有 ring prepared attempt 必须裁决为 `abandoned_to_summary`；宽限窗内且进入明细的 attempt 使用 `adopted_detail`。Kotlin 不得自行重算 5 分钟边界。
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
- Anniversary 分支不套用 72 小时窗口：候选必须满足 `remindAt <= startedAt < occurrence_date 次日 00:00`（按本次必填 `planRecovery.timezone` 的设备 IANA timezone）。同一 timezone 还负责 expired Anniversary Reminder 的年度 successor，以及 Recovery 中需要重新物化的 Anniversary Reminder；已到 occurrence 次日 00:00 的任务以 `anniversary_occurrence_elapsed` 终结并分别滚动 successor。
- 合法 Anniversary 候选先按 `(anniversaryId, occurrenceKey)` 分组；每组 `coveredReminderIds` 去重后按 UUID 小写文本升序冻结，并生成独立 `anniversary_catch_up` delivery。不同 occurrence 永不合并。
- Anniversary group 成员不进入 `detailReminderIds`、`summaryReminderIds` 或 `windowOverflowCount`，因此既有 Ring 五分钟规则、全局 20 条明细上限、72 小时 older 计数和普通摘要语义保持不变。
- group membership 在 batch 持久化后不可变化。prepare/finalize 只能引用该冻结 group；delivery、attempt 或成员不匹配返回 `ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT`，不能由 Kotlin 重新推导。
- `prepareDelivery` 不接收 timezone，只读取本批次已冻结的 group membership。`finalizeDelivery` 在首次成功提交时使用调用方传入的当前 IANA timezone 生成 successor；提交后的重放即使传入其他 timezone，也返回已持久化结果。
- Batch 只有在普通 summary/detail 与全部 Anniversary group delivery 都终结后才完成。可重试 group 保持 batch `in_progress`；永久失败和过期均按各 covered Reminder 的年度 successor 规则收口。

## 枚举定义

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

