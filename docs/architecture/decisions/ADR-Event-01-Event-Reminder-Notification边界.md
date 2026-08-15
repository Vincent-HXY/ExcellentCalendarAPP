# ADR-Event-01: Event、Reminder 与 Notification 职责边界

Status: Accepted
Date: 2026-08-08

## Context

Event 创建输入可能同时包含日程、重复规则和多个提醒。如果把提醒计划、Android 调度状态和投递结果都嵌入 Event，会让一个实体同时承担日程本体、未来任务和投递历史三类生命周期。

完成或重新打开 Event 还会影响关联 Reminder。若由 Flutter 或 Kotlin 分散补偿，跨实体状态可能在失败或进程中断后不一致。

## Decision

- `Event` 只表示日程本体。
- `Reminder` 是独立的未来待执行任务；多个提醒时间保存为多条 Reminder。
- `Notification` 是一次投递尝试和结果日志，不参与未来提醒扫描。
- Event 创建请求可以聚合 reminder inputs，但 C++ workflow 必须把它们转换并保存为独立实体。
- Event 完成时，在同一 C++ `EventReminderTransaction` 中完成 Event 并取消未触发 Reminder。
- Event 重新打开时，只恢复因 `event_completed` 自动取消且仍在未来的 Reminder。
- Android Alarm/Notification 以当前 Reminder 状态为准，不保存第二份领域真相。

## Consequences

- Event、Reminder、Notification 分别拥有稳定身份、状态和持久化记录。
- Notification 只能由实际投递流程产生，不能在创建 Event 时提前生成。
- 生命周期一致性由 C++ workflow/transaction 保证，上层只负责发起操作和展示结果。
