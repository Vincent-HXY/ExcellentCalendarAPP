## HabitCheckIn：习惯打卡记录

习惯打卡记录用于保存某个习惯在某一天的完成情况。这个模型是习惯表格、日历视图、连续天数、完成率统计的主要数据来源。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 打卡记录 ID |
| `habitId` | `string` | 是 | 关联习惯 ID |
| `checkDate` | `date` | 是 | 打卡日期，按用户本地时区计算 |
| `status` | `HabitCheckInStatus` | 是 | 打卡状态 |
| `completedCount` | `number` | 否 | 当天完成数量，例如喝水 6 次 |
| `targetCountSnapshot` | `number` | 否 | 当天目标数量快照，避免后续修改习惯目标影响历史统计 |
| `unitSnapshot` | `string` | 否 | 当天单位快照，例如次、分钟、页 |
| `completedAt` | `datetime` | 否 | 实际完成时间 |
| `note` | `string` | 否 | 当天备注 |
| `source` | `string` | 是 | 来源，例如 `manual`、`auto` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

建议约束：

- 同一个 `habitId + checkDate` 默认只保留一条记录。
- 如果未来需要一天内多次明细，例如每次喝水都记录时间，可以再增加 `HabitCheckInEntry` 明细模型；当前阶段先不需要。

## 枚举定义

### HabitCheckInStatus

习惯打卡状态。

| 值 | 说明 |
| --- | --- |
| `done` | 已完成 |
| `partial` | 部分完成 |
| `missed` | 未完成 |
| `skipped` | 跳过，不计入失败 |

