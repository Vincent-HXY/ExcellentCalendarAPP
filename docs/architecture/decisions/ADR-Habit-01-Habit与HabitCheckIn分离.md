# ADR-Habit-01: Habit 与 HabitCheckIn 分离

Status: Accepted (Implementation Pending)
Date: 2026-08-15 (Recorded)

## Context

习惯定义和每日完成记录具有不同生命周期。若把每日状态、连续天数和完成率直接写入 Habit，会同时保存原始事实与可重新计算的统计，容易产生不一致。

## Decision

- `Habit` 只表示习惯定义，包括目标、单位、有效期和重复计划。
- `HabitCheckIn` 记录某个本地日期的实际行为，并作为习惯统计的事实来源。
- 连续天数、总完成天数和完成率优先从 HabitCheckIn 动态计算。
- 同一 `habit_id + check_date` 默认只保留一条 CheckIn；若未来需要一天多次明细，新增独立 `HabitCheckInEntry`，不改变现有记录语义。
- Habit 的重复规则必须单独设计，不能直接复用 Event Recurrence。

## Consequences

- Habit 定义与历史行为可以独立修改、查询和同步。
- 派生统计可以重算，不需要把缓存值当成领域真相。
- 当前 Contract 只表示已接受的模型边界，不表示 Habit 已有生产实现。
