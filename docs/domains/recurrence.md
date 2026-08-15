## Recurrence：重复规则

本节只定义 Event v2 的重复规则。客户端输入 `EventRecurrenceRuleInput` 与持久化 `Recurrence` revision 必须分离：客户端只能表达意图，锚点、时区和展开字段由 C++ 从 Event 派生。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `recurrenceId` | `string` | 是 | 重复规则族 ID |
| `revision` | `integer` | 是 | 不可变版本号，首版为 `1` |
| `frequency` | `RecurrenceFrequency` | 是 | 重复频率 |
| `interval` | `integer` | 是 | v2 固定为 `1` |
| `startAt` | `datetime` | 条件必填 | 定时 Event 的首个 UTC Instant；全天 Event 为空 |
| `startDate` | `date` | 条件必填 | 全天 Event 的首个本地日期；定时 Event 为空 |
| `timezone` | `string` | 是 | 从 Event 派生的有效 IANA ID |
| `dayOfMonth` | `integer` | 否 | Monthly 的初始本地日号；月份截断不能修改该锚点 |
| `daysOfWeek` | `integer[]` | 否 | Weekly 恰好一个 ISO weekday，Monday=1、Sunday=7 |
| `monthOfYear` | `integer` | 否 | v2 始终为空，预留给未来 Yearly |
| `endAt` | `datetime` | 否 | v2 始终为空，预留结束边界 |
| `count` | `integer` | 否 | v2 始终为空，预留最大 occurrence 数 |
| `createdAt` | `datetime` | 是 | 创建时间 |

约束：

- 主键和唯一键均为 `(recurrenceId, revision)`；revision 不可覆盖、不可软删除改写。
- Event 保存当前 `recurrenceId + recurrenceRevision`，Recurrence 不再保存 `targetType/targetId`，避免双重关系真相源。
- v2 客户端只允许提交 `frequency/interval/endAt/count`。`interval = 1`、`endAt = null`、`count = null`；`daily/weekly/monthly` 可执行，`yearly/custom` 通过 schema 后由 C++ 返回 `FEATURE_NOT_IMPLEMENTED`。
- `startAt/startDate/timezone/dayOfMonth/daysOfWeek/monthOfYear` 均不得由客户端提交；`rrule` 和客户端自定义锚点必须被 schema 拒绝。
- `daysOfWeek` 在 Weekly 中恰好一个元素，在 Daily/Monthly 中返回空数组；`dayOfMonth` 仅 Monthly 非空。
- Daily/Weekly/Monthly 先在原时区做本地日历运算，再把每个 occurrence 的本地开始和结束分别解析为 UTC。DST gap 前移到 gap 后首个合法 Instant，DST fold 选择较早 Instant。
- 不预生成无限 occurrence。查询必须带有界半开窗口，并按原始计划本地开始值稳定排序。

## 枚举定义

### RecurrenceFrequency

重复频率。

| 值 | 说明 |
| --- | --- |
| `daily` | 每天 |
| `weekly` | 每周 |
| `monthly` | 每月 |
| `yearly` | 每年 |
| `custom` | 自定义 |

