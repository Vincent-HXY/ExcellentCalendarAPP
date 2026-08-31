# HabitCheckIn：习惯每日事实

`HabitCheckIn` 保存某个 Habit 在一个设备当地日期上的唯一事实，是统计的事实来源。`absent`、`missed` 和 `upcoming` 都是查询投影，不创建 CheckIn 行。

## 字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUIDv4 | 是 | 逻辑行 ID；clear/recreate 保持同一 ID |
| `habitId` | UUIDv4 | 是 | 所属 Habit |
| `checkDate` | date | 是 | 操作时设备当地计划日期，后续时区变化不重解释 |
| `status` | enum | 是 | 仅 `done`、`partial`、`skipped` 可持久化 |
| `completedCountHundredths` | integer | 否 | 数量型 partial/done 必填且大于 0；精确百分位 wire |
| `targetCountSnapshotHundredths` | integer | 否 | 数量型首次写入时的精确目标快照 |
| `unitSnapshot` | string | 否 | 数量型单位快照，最多 32 个 Unicode code point |
| `completedAt` | UTC instant | 否 | done/partial 由 C++ Clock 生成；skipped 为空 |
| `note` | string | 否 | 当日备注，最多 500 个 Unicode code point |
| `source` | enum | 是 | `manual` 或 `notification_action` |
| `createdAt` | UTC instant | 是 | 首次创建时间，复活不重置 |
| `updatedAt` | UTC instant | 是 | 最近 set/clear 时间 |
| `deletedAt` | UTC instant | 否 | clear 的 tombstone；普通投影排除 |

## 身份、set 与 clear

- 业务唯一身份是 `(habitId, checkDate)`，历史 tombstone 也参与唯一性；不得因 clear 插入第二条逻辑记录。
- `habit.check_in` 是幂等 set/upsert，不返回 duplicated failure。Flutter 公开请求只允许 manual shape；Kotlin 为内部 C++ command 添加 `source=manual` 和空 action identity，只有非导出的 Android 通知 action 路径可以构造 `source=notification_action`。相同意图重放返回同一最终状态；不同意图更新同一逻辑行。
- `habit.clear_check_in` 幂等地软删除活动行；不存在时仍返回最终 cleared 状态。再次 set 复活同一 ID，并保留首次 `createdAt`。
- 数量输入 0 在 Flutter Application 层路由为 clear，不保存伪 partial。
- 第一次 CheckIn 发生过这一事实必须独立保留，因此 clear 不能解锁 Habit 的目标、单位或开始日。

## 状态与快照

- 二元打卡型的非 skipped 完成状态只允许 `done`：数量、目标快照和单位快照均为空；`skipped` 同样允许，但仍遵守下一条的空快照规则。
- 数量型 `0 < completedCountHundredths < targetCountSnapshotHundredths` 为 partial；达到或超过目标为 done。超额真实保留。
- skipped 的所有数量、快照和 `completedAt` 均为空；备注可选。
- `missed` 永远不写入。过去计划日缺少活动 CheckIn 时动态投影 missed。
- 普通手工操作 source 为 `manual`。通知 action 是 set-to-done：二元写 done；数量型由 C++ 写当前目标快照作为 `completedCountHundredths`，不执行 `+1`。

## 日期与只读规则

- 允许写 `startDate..effectiveEndDate` 内的今天或过去日期；拒绝未来和有效期外日期。
- `effectiveEndDate` 是自然挑战的 `endDate`，或提前结束的 `endedDate`。
- completed、ended_early 或 deleted Habit 的历史只读；陈旧通知 action 不得绕过。
- 所有日期判断使用请求携带、经校验的当前设备 IANA timezone；不把 date 转成 UTC 午夜。

## DailyStatus 投影

- `upcoming`：未来计划日，无 CheckIn；
- `absent`：今天尚无 CheckIn，午夜前非最终失败；
- `partial`：有数量型 partial；今天午夜前 `isFinal=false`，过去日期为 true；
- `done`：有 done，最终；
- `skipped`：有 skipped，最终；
- `missed`：过去日期无活动 CheckIn，动态派生。
- partial/done/skipped 投影只能引用 `deletedAt=null` 的活动 CheckIn；clear 后 tombstone 不得作为事实返回，今天投影 absent、过去投影 missed。

## 统计

- 完成率：`done / (elapsed eligible days - skipped)`；分母为 0 时返回 0。
- skipped 不进分子/分母、不增加连续天数，但可桥接前后 done。
- 今天 absent/partial 在午夜前不提前打断当前 streak；过去 partial 会打断。
- 当前 streak 从最近已结算的非 skipped 计划日向前统计连续 done；最长 streak 在有效期内按同一规则。
- 数量进度先逐日计算 `min(completedCountHundredths / targetSnapshotHundredths, 1)` 再取平均，超额不能抵消其他日期不足。
- 累计完成量保留真实超额；7/30/all 窗口按设备当地自然日计算。日均数量按百分位整数求和后以 eligible day 为分母，使用十进制 round-half-up 保留两位小数。
- 累计与日均投影使用 `total_completed_count_hundredths` 与 `average_completed_count_per_eligible_day_hundredths`，必须继续落在 JSON safe-integer 范围；C++ 使用 checked addition，超界返回 `HABIT_STATISTICS_OVERFLOW`，不得截断、环绕或转成 decimal JSON number。
- 所有统计是可重算查询投影，不写回 Habit。
