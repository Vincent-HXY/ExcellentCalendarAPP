# ADR-Anniversary-02: Anniversary Reminder 与 Occurrence 工作流

Status: Accepted
Date: 2026-08-23

## Context

Anniversary 已经是 date-only 的独立实体，并使用专属年度规则。接入 Reminder、日历 occurrence 查询和迟到补发时，如果复用 Event recurrence revision、伪造 UTC occurrence，或由 Flutter/Kotlin 分散写入 Anniversary 与 Reminder，会破坏身份、历史投递审计和崩溃恢复。

当前 JSON writer 还存在多个 workflow 共享 `reminders.json` 的现实约束。新的 Anniversary create/update/delete、聚合 finalize 和普通 Event/Recovery writer 必须避免独立 journal 基于陈旧 after-image 相互覆盖。

## Decision

- Anniversary 继续使用独立实体与 `AnniversaryRecurrence`，不转换为 Event，不引入 Event recurrence revision。
- Anniversary occurrence 是动态投影的当地 `date`，以 `anniversary_id + occurrence_date` 生成确定性身份；不保存 UTC `occurrence_start_at`，不建立完成/跳过/取消状态，也不无限预生成。
- Anniversary 拥有最多 5 条强类型 Reminder template。Reminder 是未来任务真相源；Notification 是真实 delivery attempt/履约审计；Android Alarm 只执行可重建的平台副作用。
- Create、Update、Delete、Toggle、时区重算、Recovery、prepare/finalize 由 C++ workflow 负责。Application 依赖窄 `AnniversaryReminderWorkflowRepository` 或等价的意图型 ports，不依赖文件、journal、SQLite 或 AlarmManager。
- 不建设向 Application 暴露全部实体的大型 `CalendarTransaction`。JSON v3 adapter 使用目录锁与共享 storage-level recoverable commit coordinator，只提交本次触及 Store 的已验证 after-image；未来 SQLite adapter 在相同 port 后使用数据库事务。
- runtime bootstrap 必须先恢复旧 v2 journal，再完成 v2→v3 migration，再重放所有 v3 prepared commit；这些步骤完成前不得向 Query、Scheduler 或 JNI 开放能力。
- 领域 logical commit 先于 Scheduler reconciliation。Kotlin 在 commit 成功后执行 exact/approximate 调度或记录待恢复状态；权限或系统调度失败不得回滚已保存业务数据。
- Anniversary 迟到窗口截止当地 occurrence 次日 00:00。同 occurrence 的到期 Reminder 由一个 `anniversary_catch_up` Notification 履约，membership 在 RecoveryBatch/prepare 前冻结；每个成员通过共同 `fulfillment_delivery_id` 与唯一真实投递闭环。
- `plan_recovery.timezone` 必填并负责 Anniversary 日末边界、过期任务的年度 successor 与 Recovery 重物化；`prepare_delivery` 不接收 timezone，只消费冻结 membership。共享 `finalize_delivery.timezone` 保持可选以兼容 Event/Ring/普通 Recovery，但 Anniversary 单条与 catch-up attempt 在加载后语义必填。首次成功 finalize 用当前时区持久化 successor，提交后重放返回原对象且不重新投影；timezone 不参与任何身份。
- 普通 Event/Ring Recovery 继续使用 72 小时窗口、Ring 五分钟宽限和全局 20 条明细上限。Anniversary groups 是 target-specific 分支，不进入普通 detail/summary 选择与计数。

## Consequences

- Dart、Kotlin 和 C++ 可以从同一份 date/time、identity、错误和 fixture 独立实现，不需要语言层自行推导 UUID 或补偿跨实体状态。
- JSON Storage 必须升级为 v3 并提供连续、可恢复、无损的 v2→v3 migration；旧 App 不可安全降级打开 v3 目录。
- 新 Wire shape 在三层与真实 APK 验收前保持 blocked，不得因 Schema 已冻结而被当成已发布能力。
- SQLite 迁移可以替换存储 adapter，而不改变 occurrence、Reminder、Notification、RecoveryBatch 或 Scheduler 边界。
