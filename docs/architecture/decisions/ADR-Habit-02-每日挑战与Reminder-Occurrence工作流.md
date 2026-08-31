# ADR-Habit-02：每日挑战与 Reminder Occurrence 工作流

Status: Accepted
Date: 2026-08-28
Implemented: 2026-08-31

## Context

Habit 是固定期限的 date-only 每日挑战，既不能使用 Event 的 revision/UTC occurrence，也不能使用普通 Reminder 的 72 小时补发摘要。通知栏完成还要求一个在 Flutter 未启动时仍可幂等执行的稳定 action identity。

## Decision

- Habit V1 独占 `daily + interval=1 + follow_device` 的 `HabitRecurrence`；挑战日是包含首尾的当地日期区间。
- `HabitCheckIn` 以 `(habit_id, check_date)` 为唯一逻辑事实；set/upsert 幂等，clear 保留 tombstone 并在重建时复活同一 ID，missed 只派生。
- 一个 Habit 最多一个未删除 `HabitReminderTemplate`。template 使用 UUIDv4；local_time 改变时软删旧 template/chain 并创建新 key。
- occurrence 继续由 template_key 区分，但同一 `(habit_id, occurrence_date)` 跨 template 最多一次真实展示。当天 sent 或 prepared 后修改时间/关闭再开启均从下一合法日期生效；尚无 attempt 时可替换当天任务。prepared 保守占用当天展示槽并原子 abandon，防止 finalize 崩溃窗口造成第二次展示。
- occurrence、Reminder 和 notification action 分别按 `contracts/identity.yaml` 的 UUIDv5 规则由 C++ 唯一生成。timezone、remind_at 和文案不参与身份。
- Habit Reminder 是 `reminder_response` 的独立 target-specific 分支，必须携带 `occurrence_key/template_key/occurrence_date/local_time/follow_device`，固定 popup。
- Habit reconciliation 独立于普通 72 小时 RecoveryBatch：仅同当地日期逐条补发，次日 00:00 过期；以有界 cursor 分块，但不把多 Habit 合并成无法快捷完成的摘要。`has_more=true` 必须产生正进展，processed 必须等于全部 outcome 计数之和且不超过请求 limit。
- Habit reconciliation 也负责终结未展示的 prepared attempt：跨日使用 `habit_occurrence_elapsed`，业务取消使用 `habit_reminder_cancelled`；两者的 `resolved_by_recovery_batch_id` 均为空。
- 通知 action 是 set-to-done，而非增量：二元 Habit 写 done；数量型写目标快照并 done。C++ 在一个事务中验证日期/身份、upsert CheckIn、取消当天 open Reminder 并返回最终状态。
- done/skipped 后 clear 只在该 occurrence 尚无 sent delivery 时恢复同一 Reminder；已经真实展示过则不二次通知。
- C++ logical commit 先于 Android scheduling。权限或 Alarm 失败不回滚数据，Kotlin 依据类型化 capability 重试 reconcile，Android 不保存第二份领域真相。
- 生命周期 mutation 权限以 `contracts/habit/habit_lifecycle_operation_matrix.yaml` 为机器真相源；最终计划日不能调用 early-end，自然完成或提前结束后仅允许 query、delete 与通过全新 create“再来一轮”。

## Consequences

- Flutter 只消费组合投影，不计算 lifecycle、streak/rate、Reminder/action identity。
- Kotlin 只校验/转发 Contract、执行 Android side effect 和本机 appearance；后台 action 不启动 Flutter Engine。
- C++/SQLite v5 必须为 Habit、Recurrence、CheckIn、template、Reminder/Notification 联动提供同一事务。
- Habit 能力已在 Flutter、Kotlin/JNI、C++、SQLite v5 与真实 production composition 中落地并切换为 `integrated + active`；仍未执行的设备场景由 `OPEN-HAB-001` 跟踪，不得被解释为已验证通过。
