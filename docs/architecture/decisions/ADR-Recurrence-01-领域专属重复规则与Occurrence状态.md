# ADR-Recurrence-01: 领域专属重复规则与 Occurrence 状态

Status: Accepted
Date: 2026-08-08

## Context

Event、Habit 和 Anniversary 都可能重复，但它们的锚点、生命周期和单次 occurrence 语义不同。使用一个万能 Recurrence DTO 会隐藏差异，并可能让某次 occurrence 的状态污染整个系列。

## Decision

- Recurrence 是独立规则，不嵌入业务实体作为无类型配置。
- 不用一个通用 DTO 抹平 Event、Habit 和 Anniversary 的重复语义。
- Event 使用不可变的 `(recurrence_id, revision)`，由 Event 时间字段派生锚点，并为 occurrence 建立稳定身份和独立状态。
- Anniversary 使用独立的 `AnniversaryRecurrence`，V1 只允许 `yearly + interval=1`。
- Habit V1 已冻结独立 `daily + interval=1 + follow_device` 的 HabitRecurrence 与 date-only Reminder occurrence identity；在 SQLite v5 和三语言实现通过门禁前仍保持未激活，且始终不从 Event Recurrence 推导。
- occurrence 的完成、跳过、取消或重新打开只影响该次 occurrence，除非用户明确执行系列操作。
- `overdue`、`in_progress` 等派生状态默认动态计算，不随意持久化。

## Consequences

- 各领域可以独立演进重复规则，不需要用大量 nullable 字段兼容彼此。
- occurrence 操作与系列操作必须使用不同的 Command、Contract 和测试。
- 新增领域的重复能力前，必须先冻结该领域的 identity、锚点、状态和持久化语义。
