# HabitRecurrence：习惯每日计划规则

Habit V1 使用独占的轻量规则，不复用 Event Recurrence revision 或 Anniversary 年度规则。

| 字段 | 类型 | 必填 | V1 语义 |
| --- | --- | --- | --- |
| `id` | UUIDv4 | 是 | 规则 ID，由一个 Habit 独占 |
| `frequency` | enum | 是 | 固定 `daily` |
| `interval` | integer | 是 | 固定 `1` |
| `timezoneMode` | enum | 是 | 固定 `follow_device` |
| `createdAt` | UTC instant | 是 | C++ Clock |
| `updatedAt` | UTC instant | 是 | V1 与创建时间相同或仅作审计 |
| `deletedAt` | UTC instant | 否 | Habit 软删除时可一并终结 |

规则创建后不可变；`startDate/endDate` 属于 Habit，不在规则内重复保存。`start_at/end_at/rrule/timezone/days_of_week` 等 Event 字段在 Habit request 中必须被拒绝。未来 weekly/custom 需要新的明确协议与迁移，不能改变既有 daily 记录的解释。
