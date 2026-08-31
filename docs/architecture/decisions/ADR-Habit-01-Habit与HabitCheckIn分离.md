# ADR-Habit-01: Habit 与 HabitCheckIn 分离

Status: Accepted (Contract Frozen, Implementation Pending)
Date: 2026-08-15 (Recorded)

## Context

习惯定义和每日完成记录具有不同生命周期。若把每日状态、连续天数和完成率直接写入 Habit，会同时保存原始事实与可重新计算的统计，容易产生不一致。

## Decision

- `Habit` 只表示习惯定义，包括目标、单位、有效期和重复计划。
- `HabitCheckIn` 记录某个本地日期的实际行为，并作为习惯统计的事实来源。
- 连续天数、总完成天数和完成率优先从 HabitCheckIn 动态计算。
- 同一 `habit_id + check_date` 默认只保留一条 CheckIn；若未来需要一天多次明细，新增独立 `HabitCheckInEntry`，不改变现有记录语义。
- Habit 的重复规则必须单独设计，不能直接复用 Event Recurrence。
- Habit 数量在所有 Native wire 上使用 `_hundredths` JSON safe integer；展示小数只在 UI 边缘转换，禁止使用 JSON decimal number 表达精确业务值。
- Habit V1 挑战区间最多 400 个包含首尾的当地自然日，文本与分页上限由机器 Contract 冻结。

## Consequences

- Habit 定义与历史行为可以独立修改、查询和同步。
- 派生统计可以重算，不需要把缓存值当成领域真相。
- Habit V1 的字段、daily recurrence、CheckIn set/clear、统计与 Reminder/action identity 已由 ADR-Habit-02 和机器 Contract 冻结；Flutter、Kotlin/JNI、C++ 与 SQLite v5 仍待实现，因此不表示生产能力已完成。
