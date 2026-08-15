## Habit：习惯

习惯用于记录需要长期执行、打卡或追踪的行为。习惯是规律的，而且需要特殊记录，比如一共坚持了多久、哪些日子坚持了、某一天完成了多少次。

说明：

- `Habit` 只保存习惯定义，例如名称、目标、单位、开始日期、重复规则。
- 每天是否完成、完成次数、打卡时间不放在 `Habit` 本体里，而是保存到 `HabitCheckIn`。
- 后期用表格呈现时，可以用 `Habit` 作为行或分组，用 `HabitCheckIn.checkDate` 作为列或单元格数据来源。
- 连续天数、总完成天数、完成率建议优先从 `HabitCheckIn` 计算；如果性能不够，再增加缓存字段或统计表。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 习惯 ID |
| `title` | `string` | 是 | 习惯名称 |
| `description` | `string` | 否 | 习惯说明 |
| `categoryId` | `string` | 否 | 分类 ID |
| `recurrenceId` | `string` | 是 | 计划中的 Habit 专用规则引用；不得指向本轮 Event Recurrence revision |
| `targetCount` | `number` | 否 | 目标次数，例如每天喝水 8 次 |
| `unit` | `string` | 否 | 目标单位，例如次、分钟、页 |
| `startDate` | `date` | 是 | 开始日期 |
| `endDate` | `date` | 否 | 结束日期 |
| `isActive` | `boolean` | 是 | 是否启用 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

