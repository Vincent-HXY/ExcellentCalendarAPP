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
| `remindersEnabled` | `boolean` | 是 | Anniversary 级提醒总开关；关闭只暂停未来任务并保留模板 |
| `deletedAt` | `datetime` | 否 | 软删除时间 |

### AnniversaryRecurrence：纪念日年度规则

`AnniversaryRecurrence` 是 Anniversary 独占的轻量年度规则，持久化集合命名为 `anniversary_recurrences`。它不属于 Event v2 的不可变 Recurrence revision，也不保存 `anniversaryId`、月、日、时区、UTC occurrence 或 RRULE；关系真相只保存在 `Anniversary.recurrenceId`。

`anniversaries`、`anniversary_recurrences` 与 `anniversary_reminder_templates` 表在 SQLite Storage v4 引入，并由当前 active 的 Storage v5 原样继承。Anniversary create/update/delete/toggle/recovery/finalize 与其他会共享 Reminder 等表的 Workflow，统一通过同一 SQLite 连接和数据库事务原子提交；旧 JSON workflow journal 只在 v1/v2/v3→v4 迁移前恢复，不再承担运行时写入。

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
- Anniversary occurrence 是用户当地 `date`，不包含 UTC `occurrence_start_at`，也没有完成、跳过、取消或 reopen 状态。
- `occurrence_key` 由 C++ 按 `contracts/identity.yaml` 使用 `anniversary_id + occurrence_date` 生成；标题、note、category 和 importance 不参与身份。
- `anniversary.list_occurrences` 只接受当地日期半开区间 `[range_start_date, range_end_date)`，单次最多 400 个自然日。一次性只投影原始日期；年度规则从原始年份开始动态展开，历史查询按当前 Anniversary 事实重算。
- 查询结果按 `(occurrence_date, anniversary_id, occurrence_key)` 稳定升序；cursor 绑定完整查询条件和稳定排序位置，不设置 200 条总结果上限。

### AnniversaryReminderTemplate：提醒配置

提醒模板是 Anniversary 拥有的强类型配置事实，不是 Android Alarm，也不是已经物化的 Reminder。每个 Anniversary 最多保存 5 条模板。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `templateKey` | `string` | 是 | Contract 冻结的 UUIDv5；由 Anniversary、提前天数、当地时间、时区模式和渠道共同决定 |
| `anniversaryId` | `string` | 是 | 所属 Anniversary |
| `advanceDays` | `integer` | 是 | `0..365`，按当地自然日从 occurrence 日期向前计算 |
| `localTime` | `string` | 是 | `HH:mm`，24 小时制、分钟精度 |
| `timezoneMode` | `string` | 是 | V1 固定 `follow_device` |
| `method` | `string` | 是 | V1 固定 `popup` |
| `isEnabled` | `boolean` | 是 | 模板级开关；只有它与 `Anniversary.remindersEnabled` 同时为 true 才物化未来任务 |

配置与生命周期不变量：

- 同一 Anniversary 的 `(advanceDays, localTime, timezoneMode, method)` 必须唯一；空模板集合合法，现有 Anniversary 升级后固定为总开关关闭且模板为空，不自动生成 Reminder。
- Create 中 `reminder_plan` 缺失是显式兼容旧调用方，等价于关闭且空模板；显式 `null` 非法。Update 中省略表示保留完整计划，传对象表示整体替换；对象内空数组表示删除全部模板，关闭总开关但保留非空数组表示暂停。
- 一次性 Anniversary 只物化原始 occurrence 的任务且没有 successor；创建时已经过期则不补发、不创建过去任务。
- 年度 Anniversary 为每个启用模板只保持一条 open 滚动任务；本次触发时刻已过则跳到下一年度，成功、永久失败或 occurrence 日末过期后分别创建下一年度 successor。
- 用户意图保存为 `advanceDays/localTime/follow_device/popup`；调度投影保存 `occurrenceDate/remindAt`。DST gap 前移到首个合法 Instant，fold 选择较早 Instant；设备时区变化只重算 open Reminder 的 UTC `remindAt`。
- 标题、note、category 和 importance 更新不替换模板、occurrence 或 Reminder identity；日期、repeat 或模板身份变化终结受影响旧链并从首个仍有意义的 occurrence 重新物化。日期改回原值恢复确定性 identity，但旧终结记录只能由 workflow 在校验业务内容后安全恢复或替换。
- 总开关关闭或模板关闭会取消未来任务但保留配置；恢复时复用仍有意义的确定性 ID，否则物化下一合法 occurrence。软删除 Anniversary 会终结全部未来 Reminder，但保留 Notification 历史。

### Workflow、补发与调度边界

- Create/Update/Delete/Toggle、occurrence 查询、时区重算、recovery、prepare/finalize 都属于 C++ workflow；Flutter 只提交用户意图，Kotlin 只执行平台调度和真实通知副作用。
- 跨 Anniversary、Recurrence、Template、Reminder、Notification 和 RecoveryBatch 的变更通过窄 `AnniversaryReminderWorkflowRepository`（或等价拆分）提交。当前 SQLite adapter 以同一 port 使用数据库事务，不建立暴露全部实体的 `CalendarTransaction`；冻结 JSON adapter 只服务旧数据迁移。
- 数据 logical commit 先成功，Scheduler reconciliation 后执行且可重试。调度或权限失败不能回滚、删除或清空已保存 Anniversary、模板或 Reminder。
- Anniversary 迟到补发窗口为 `[remind_at, occurrence_date 在当前设备时区下的次日 00:00)`。同一 `(anniversary_id, occurrence_key)` 的到期任务聚合为一个真实 popup；不同 occurrence 不合并。
- 聚合 membership 在 recovery plan/prepare 前由 C++ 冻结。真实发送成功后，所有 covered Reminder 写入同一 `fulfillment_delivery_id` 并分别滚动 successor；Kotlin 不重新分组、不追加成员，也不把 Android Alarm 当作真相源。

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

