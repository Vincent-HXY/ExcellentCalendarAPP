# Habit：固定期限每日习惯挑战

`Habit` 只保存挑战定义。每日事实属于 `HabitCheckIn`；生命周期、每日状态、连续天数、完成率和页面进度均由 C++ 查询时投影，不写回 Habit。

## 字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUIDv4 | 是 | C++ 创建的 Habit ID |
| `title` | string | 是 | wire 最多 80 个 Unicode code point；trim 后不可为空，Emoji 原样保留 |
| `description` | string | 否 | 可空说明，最多 2000 个 Unicode code point |
| `categoryId` | string | 否 | Category 弱引用；悬空或软删除不影响 Habit 可读性 |
| `recurrenceId` | UUIDv4 | 是 | 独占引用 `HabitRecurrence.id`，不得指向 Event Recurrence |
| `targetCountHundredths` | integer | 否 | 数量型每日目标的精确百分位整数；UI 用两位小数展示 |
| `unit` | string | 否 | 数量型单位，最多 32 个 Unicode code point |
| `startDate` | date | 是 | 第一个计划日 |
| `endDate` | date | 是 | 最后一个计划日，不得为空 |
| `endedDate` | date | 否 | 用户提前结束的设备当地日期；自然到期为空 |
| `isActive` | boolean | 是 | `false` 只表示用户提前结束，不用于自然到期 |
| `createdAt` | UTC instant | 是 | C++ Clock 生成 |
| `updatedAt` | UTC instant | 是 | 乐观并发 token；成功 mutation 必须变化 |
| `deletedAt` | UTC instant | 否 | 软删除时间 |

数量 wire 字段统一使用 `_hundredths` 后缀的 JSON integer，必须位于 `1..9_007_199_254_740_991`；例如用户输入 `1.25` 传输为 `125`。`90_071_992_547_409.90` 与 `90_071_992_547_409.91` 在 wire 上分别是两个相邻整数，不经过 IEEE-754 小数。JSON decimal number、NaN、Infinity、非整数百分位和越界值均非法；C++ 使用 checked integer 运算。

## 核心不变量

- 用户语义是包含首尾的闭区间 `[startDate, endDate]`；内部日期展开使用 `[startDate, endDate + 1 day)`。
- V1 挑战最多包含 400 个当地自然日；create/update 超过上限返回 `HABIT_CHALLENGE_TOO_LONG`。
- `targetCountHundredths` 与 `unit` 必须同时为空（二元打卡型）或同时非空（数量型）。数量型目标必须大于 0。
- 首次产生任意 CheckIn 后，`targetCountHundredths`、`unit` 和 `startDate` 永久锁定；之后即使 clear 也不解锁。
- `endDate` 可延长或缩短，但不得早于今天、`startDate` 或历史 CheckIn 的最晚日期。
- 提前结束不可恢复：同一事务写 `endedDate=当前设备当地日期`、`isActive=false`，保留原 `endDate` 和历史 CheckIn，并取消所有 open Habit Reminder。
- 自然到期不回写 `isActive`；`endDate` 次日由查询投影为 completed。
- 软删除不物理删除历史 CheckIn、Reminder 或 Notification 审计；普通查询排除 `deletedAt != null`。
- “再来一轮”只预填新的 create request，必须生成全新 Habit、Recurrence、template、occurrence 和 CheckIn 身份。

## 派生生命周期

按 C++ Clock 与请求中的当前设备 IANA timezone 得到 `today`：

- `upcoming`：`today < startDate`；
- `active`：`isActive=true` 且 `startDate <= today <= endDate`；
- `completed`：`isActive=true` 且 `today > endDate`；
- `ended_early`：`isActive=false`、`endedDate != null` 且未软删除；
- `deleted`：只用于内部/错误路径，不进入普通 list/detail 投影。

## 生命周期 × 操作权限

机器真相源是 `contracts/habit/habit_lifecycle_operation_matrix.yaml`：

| 生命周期 | update | end | delete | check-in / clear | set-reminder |
| --- | --- | --- | --- | --- | --- |
| upcoming | 允许 | 拒绝：`HABIT_NOT_STARTED` | 允许 | 由未来/范围规则拒绝 | 允许 |
| active 且 `today < endDate` | 允许 | 允许提前结束 | 允许 | 允许有效日期 | 允许 |
| active 且 `today == endDate` | 允许 | 拒绝：`HABIT_END_NOT_EARLY` | 允许 | 允许有效日期 | 允许 |
| completed / ended_early | 拒绝：`HABIT_ALREADY_ENDED` | 拒绝 | 允许软删除 | 拒绝 | 拒绝 |
| deleted | 全部拒绝：`HABIT_TARGET_DELETED` | 拒绝 | 拒绝 | 拒绝 | 拒绝 |

最后一个计划日直到当地午夜前仍是 active，因此不能标成“提前结束”；自然完成后也不能通过 update 延长 `endDate` 重新打开历史。“再来一轮”始终是全新 create，而不是恢复旧对象。

## 页面投影

- 时间进度：upcoming 为 0；active 为 `(today-startDate+1)/(endDate-startDate+1)`；自然完成为 1；提前结束冻结为 `(endedDate-startDate+1)/(endDate-startDate+1)`，统一限制在 `0..1`。
- `remainingDays`：upcoming 返回总计划日数；active 返回包含今天的剩余计划日数；completed/ended_early 为 0。
- `habit.list` 返回卡片组合投影和稳定顺序；Flutter 不重算生命周期、统计、进度或排序键。
- `habit.list.today_progress` 是不受分页和筛选影响的全局首页聚合。只统计 today 为 active 的未删除 Habit：done 进入 X 与 Y，partial/absent 只进入 Y，skipped 不进入 Y；upcoming/completed/ended_early 均排除。
- `habit.detail` 返回 Habit、独占 recurrence、reminder settings、统计、今天状态和首屏历史；当前当地日期不在挑战区间时 `today=null`。它还返回 `has_ever_checked_in/latest_check_in_date`，供 Flutter 正确锁定目标、单位、开始日并约束结束日；统计与内部锁定时间不进入 `HabitResponse`。

## V1 范围

只支持固定期限、每日一次计划、打卡型/数量型、补签、skipped、提前结束、单 popup reminder。weekly/custom/infinite、暂停、多个提醒、ring、云同步、每 Habit 颜色与一天多条行为明细均不属于 V1。
