# HabitReminderTemplate：习惯每日提醒配置

Habit V1 每个 Habit 最多一个未删除 template。Reminder 是物化的未来任务，Notification 是真实投递 attempt；template 本身不是 Alarm 或投递日志。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `templateKey` | UUIDv4 | 是 | C++ 创建的 template identity |
| `habitId` | UUIDv4 | 是 | 所属有效 Habit |
| `localTime` | `HH:mm` | 是 | 设备当地墙上时间 |
| `timezoneMode` | enum | 是 | 固定 `follow_device` |
| `method` | enum | 是 | 固定 `popup` |
| `isEnabled` | boolean | 是 | 是否继续物化 occurrence |
| `createdAt` | UTC instant | 是 | 创建时间 |
| `updatedAt` | UTC instant | 是 | 更新时间 |
| `deletedAt` | UTC instant | 否 | identity-bearing 设置被替换或 Habit 删除时写入 |

## 身份与替换

- 首次开启生成 UUIDv4 `templateKey`；关闭可保留禁用审计行。
- `localTime` 改变时软删除旧 template 和旧链，创建新的 UUIDv4 templateKey；不得原地改变旧 occurrence 的身份解释。
- Habit occurrence identity 是 `habitId + templateKey + occurrenceDate`；timezone、localTime 和 `remindAt` 不参与 UUIDv5 name。
- Habit Reminder 唯一业务键是 `targetType=habit + targetId + templateKey + occurrenceDate`，同一业务内容重放幂等，冲突严格失败。
- occurrence 身份仍包含 templateKey，但真实展示另有更强的日级约束：同一 `(habitId, occurrenceDate)` 跨所有历史 templateKey 最多一条 sent Reminder。

## 修改、关闭与重新开启的同日规则

- 当天没有 Notification attempt 时，修改时间或关闭后重开可以在同一事务取消旧 Reminder，并按新 template 替换当天任务。
- 当天已经 sent 时，修改时间或重新开启只从下一个合法挑战日生效；当天不得因新 templateKey 再展示。
- 当天存在 prepared attempt 时，按“可能已经由 Android 展示”保守处理：该 attempt 预留当天展示槽，事务内以 `habit_reminder_cancelled` 终结旧 attempt，并让新 template 从下一个合法挑战日生效。
- SQLite v5 的 `ux_habit_sent_display_per_day` 是最终 sent 防线；C++ transaction 与 prepared 预留规则共同覆盖 finalize 崩溃窗口。

## 生命周期

- 开启时只物化当前应调度 occurrence/后继，不预生成整个挑战。
- 启用 template 的 `activeReminderCount` 可以是 0：例如当天完成后、挑战结束后或等待 reconciliation 时；`isEnabled=true` 不能被误解为一定存在一个 open Reminder。
- 当天 done/skipped 原子取消未投递 Reminder；partial 保持有效并由 C++ 生成剩余量文案。
- clear 时，如果该 occurrence 从未成功展示，则恢复同一确定性 Reminder；原时间已过时进入同日补发。如果已有 sent delivery，则允许清除 CheckIn，但同一 occurrence 不再次展示。
- 提前结束、删除、禁用或替换 template 会终结相应 open 链；自然到期不生成结束日之后的 successor。
- Android 调度失败或权限拒绝不回滚 Habit/template。C++ 保留 `scheduleReconciliationRequired`，Kotlin 后续 reconcile。

## 同日 reconciliation

Habit 使用独立、有界、可续跑的 reconciliation，不进入普通 Reminder 的 72 小时 RecoveryBatch、20 条明细上限或摘要：

- 当前当地日期内、未 done/skipped、该 `(habitId, occurrenceDate)` 跨 template 尚无 sent/prepared 展示占用的 occurrence 可以补发一次；
- 当地次日 00:00 起标记 `habit_occurrence_elapsed`，永不跨日补发；
- 若跨日前已经创建但未真实展示的 prepared Notification attempt，同一 reconciliation 以 `habit_occurrence_elapsed` 终结；done/skipped、提前结束、删除、禁用或替换导致的未展示 attempt 以 `habit_reminder_cancelled` 终结，均不创建 RecoveryBatch；
- 大量 Habit 以最多 100 条的事务分块和 opaque seek-after cursor 续跑，每条仍是独立、可快捷完成的 popup；Android continuation 必须持久化 cursor、原 trigger、发起时 timezone 及 dispatcher identity，进程重启后从该 cursor 继续。cursor 边界 Habit 在两页之间删除时仍从其排序位置之后恢复；续跑前若设备时区已变化，则丢弃旧 cursor 并以 `timezone_changed` 全量重启。`has_more=true` 必须至少处理一条，四类 outcome 计数之和必须等于 processed 且不超过 request limit；
- 重启、权限恢复、时间/时区变化和重复扫描由 occurrence/reminder/delivery/action identity 去重。
