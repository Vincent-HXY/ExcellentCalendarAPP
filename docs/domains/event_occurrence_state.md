## EventOccurrenceState：日程 occurrence 状态

`EventOccurrenceState` 用于记录重复日程某一次 occurrence 的完成、跳过、取消状态。它不是提前生成所有未来 occurrence 的缓存表，而是用户产生明确行为后才写入的稀疏状态记录表。

说明：

- `occurrenceKey` 由 C++ 按 `contracts/identity.yaml` 生成，客户端只能原样透传，其他层不得重新计算。
- occurrence 操作请求同时回传查询结果中的计划开始 Instant 或本地日期，C++ 以该值做有界展开并重新校验 `occurrenceKey`；不得仅凭不可逆 UUID 在无限规则中搜索。
- 定时 occurrence 的身份输入使用 DST 解析前的原始计划本地日期时间；全天 occurrence 使用本地日期。
- 普通日程完成时直接更新 `Event.status`；重复日程单次操作不得污染整个 Event 状态。
- 如果某次 occurrence 没有状态记录，则根据 Recurrence 展开结果和当前时间动态计算展示状态。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `eventId` | `string` | 是 | 关联日程 ID |
| `recurrenceRevision` | `integer` | 是 | 产生该 occurrence 的规则 revision |
| `occurrenceKey` | `string` | 是 | 稳定 UUIDv5 occurrence 身份 |
| `occurrenceStartAt` | `datetime` | 条件必填 | 定时 occurrence 的 UTC 计划开始 Instant |
| `occurrenceStartDate` | `date` | 条件必填 | 全天 occurrence 的本地计划开始日期 |
| `status` | `EventOccurrenceStatus` | 是 | occurrence 状态 |
| `stateChangedAt` | `datetime` | 是 | 最近一次状态操作时间，由 C++ Clock 生成 |
| `reopenedAt` | `datetime` | 否 | 最近一次 reopen 时间，由 C++ Clock 生成 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

建议约束：

- 唯一键为 `(eventId, recurrenceRevision, occurrenceKey)`。
- `occurrenceStartAt` 与 `occurrenceStartDate` 必须恰有一个非空，并与 Event 的时间类型一致。
- complete/skip/cancel 在同一 workflow transaction 中更新状态、以对应原因取消本 occurrence 的非终结 Reminder，并确保下一个合法滚动 Reminder 存在。
- reopen 把状态改为 `scheduled`，仅恢复 `remindAt > reopenedAt` 且取消原因可逆的原 Reminder；不执行 72 小时补发。
- occurrence 查询投影另外计算 `occurrenceEndAt` 或 `occurrenceEndDate`，结束值不是状态表字段。

## 枚举定义

### EventOccurrenceStatus

重复日程某一次 occurrence 的状态。

| 值 | 说明 |
| --- | --- |
| `scheduled` | 曾被用户操作后又重新打开，恢复为计划状态 |
| `completed` | 这一轮已完成 |
| `skipped` | 这一轮被用户跳过 |
| `cancelled` | 这一轮被取消 |

未被用户操作的 occurrence 不创建状态记录；其 `pending`、`in_progress`、`overdue` 等展示状态根据当前时间动态计算。`scheduled` 只出现在已存在且后来被 reopen 的稀疏状态记录中。

