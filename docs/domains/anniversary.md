## Anniversary：纪念日

纪念日用于记录生日、节日、恋爱纪念日、结婚纪念日等年度或特定周期事件。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 纪念日 ID |
| `title` | `string` | 是 | 纪念日名称 |
| `date` | `date` | 是 | 用户保存的原始本地日期；年度重复的月、日锚点只从这里读取 |
| `calendarType` | `string` | 是 | V1 只允许 `solar`；`lunar` 保留为协议拒绝入口 |
| `categoryId` | `string` | 否 | 分类 ID |
| `recurrenceId` | `string` | 否 | Anniversary 专用规则引用；`null` 表示一次性，非空必须指向有效 `AnniversaryRecurrence` |
| `note` | `string` | 否 | 备注 |
| `importance` | `Importance` | 否 | 重要性 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

### AnniversaryRecurrence：纪念日年度规则

`AnniversaryRecurrence` 是 Anniversary 独占的轻量年度规则，持久化集合命名为 `anniversary_recurrences`。它不属于 Event v2 的不可变 Recurrence revision，也不保存 `anniversaryId`、月、日、时区、UTC occurrence 或 RRULE；关系真相只保存在 `Anniversary.recurrenceId`。

当前 JSON Storage v2 已激活 `anniversaries.json` 与 `anniversary_recurrences.json`，create/update/delete 通过独立 `anniversary_workflow_transactions.json` 两 Store journal 原子提交。该 journal 不参与也不改变 Event/Reminder 既有六 Store 事务。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `recurrenceId` | `string` | 是 | UUIDv4 主键，由 C++ 在从一次性切换为年度重复或创建年度重复纪念日时生成 |
| `frequency` | `RecurrenceFrequency` | 是 | V1 固定为 `yearly` |
| `interval` | `integer` | 是 | V1 固定为 `1` |
| `createdAt` | `datetime` | 是 | 规则创建时间，ISO 8601 UTC Instant |
| `deletedAt` | `datetime` | 否 | 规则退出使用时的软删除时间；活动规则必须为 `null` |

关系与生命周期不变量：

- 一次性 Anniversary 必须满足 `recurrenceId = null`；年度重复 Anniversary 必须引用一条 `deletedAt = null`、`frequency = yearly`、`interval = 1` 的有效规则。
- 一个活动 `AnniversaryRecurrence` 最多由一个 Anniversary 引用；不得共享规则，也不得在规则中反向保存 `anniversaryId` 形成双重真相源。
- `Anniversary.date` 始终保存用户输入的原始日期及历史年份。规则不得重复保存 `monthOfYear`、`dayOfMonth` 或另一个日期锚点。
- 创建年度重复纪念日时，C++ workflow 必须在同一事务中创建规则并写入 `Anniversary.recurrenceId`；任一步失败都不得留下半提交数据。
- 仍为年度重复时更新标题或日期，保留原 `recurrenceId`。日期变化只替换 `Anniversary.date`，后续查询使用新日期动态计算，不创建新的规则或未来 occurrence。
- 从一次性切换为年度重复时创建新的 UUIDv4 规则并原子建立引用；不得复活过去已软删除的规则。
- 从年度重复切换为一次性时，必须在同一事务中把 `Anniversary.recurrenceId` 设为 `null`，并以同一 UTC Clock 值写入旧规则的 `deletedAt`。事务失败时两项都回滚。
- 读模型发现非空 `recurrenceId` 指向缺失、已软删除或不满足 V1 常量的规则时必须显式失败，不得降级为一次性或静默新建替代规则。

Occurrence 与查询不变量：

- 不持久化 `2027`、`2028`、`2029` 等未来 occurrence，也不为 Anniversary V1 建立 occurrence 状态表。
- C++ 查询以请求 IANA timezone 得到本地今日日期；年度重复的下一次日期由 `Anniversary.date` 的月、日动态计算。今年候选已过去时计算下一年候选。
- 公历 2 月 29 日在非闰目标年落到该年 2 月最后一天；`next_occurrence_date`、`days_remaining` 和 `is_today` 都是查询投影，不回写 Anniversary 或 `anniversary_recurrences`。
- V1 的 Anniversary occurrence 没有可变状态、Reminder 或投递身份。未来增加 Reminder 前，必须另行冻结 occurrence identity、幂等、唯一键和 reconciliation 语义。

## 枚举定义

### Importance

重要性。

| 值 | 说明 |
| --- | --- |
| `unimportant_noturgent` | 不重要不紧急 |
| `important_noturgent` | 重要不紧急 |
| `unimportant_urgent` | 不重要紧急 |
| `important_urgent` | 重要且紧急 |

### RecurrenceFrequency

重复频率。

| 值 | 说明 |
| --- | --- |
| `daily` | 每天 |
| `weekly` | 每周 |
| `monthly` | 每月 |
| `yearly` | 每年 |
| `custom` | 自定义 |

