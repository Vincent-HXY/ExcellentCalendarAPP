# CalendarView：月/周分类日历只读组合投影

`CalendarView` 不是新的领域实体，也没有独立生命周期或持久化表。它是 C++ Calendar Core 在一个只读快照中，对 Event、Habit、Anniversary 与 Reminder 当前事实进行组合后生成的查询投影。

机器 Contract 真相源：

- `contracts/calendar/*.schema.json`：跨层 request/response；
- `contracts/calendar/calendar_query_invariants.yaml`：快照、排序、cursor、圆点和分页不变量；
- `contracts/method_channels.yaml` 与 `contracts/native_calls.yaml`：公开及内部能力；
- `contracts/enums.yaml` 与 `contracts/error_codes.yaml`：枚举及失败语义。

## 1. 所有权与边界

Calendar View 只读取下列事实：

| 投影 | 事实所有者 | Calendar View 可以做 | Calendar View 不可以做 |
| --- | --- | --- | --- |
| Event 日条目 | Event、Recurrence、EventOccurrenceState | 有界展开、当地日重叠、展示状态与排序投影 | 写入完成/跳过状态，复制 Event 状态机 |
| Habit 日条目 | Habit、HabitRecurrence、HabitCheckIn | 按选中日读取 DailyStatus、精确数量和挑战区间 | 创建伪 CheckIn，重算或持久化统计 |
| Anniversary 日条目 | Anniversary、AnniversaryRecurrence | 动态展开当地 occurrence、years elapsed | 转成 Event、保存未来 occurrence |
| 活动提醒标记 | Reminder | 按目标与 occurrence 读取 open task | 从 AlarmManager 或 Notification 反推事实 |

Calendar View 不写任何业务对象，不建立缓存表，不改变 Calendar Core SQLite Storage v5。页面缓存属于 Flutter 会话状态，失效后必须从权威查询重建。

## 2. 公开查询

### `calendar.range_summary`

输入一个 IANA timezone 和当地日期半开区间 `[range_start_date, range_end_date)`：

- 区间必须非空、正向且最多 42 个自然日；
- 返回区间内每天恰好一个 `CalendarRangeDaySummary`，按 date 升序且无缺口；
- 每日只返回三类存在性布尔值，不返回数量、标题或本地化文案；
- 返回一个 opaque `snapshot_token`，供同一页面快照的三个 section 查询使用。

### `calendar.list_day_items`

输入选中 date、timezone、section、`snapshot_token`、cursor 和 page size：

- section 只能是 `event`、`habit`、`anniversary`；
- 第一页 cursor 必须为 `null`；V1 页面使用 20，协议最大 100；
- response 由 section 判别 typed item，不存在所有字段 nullable 的万能条目；
- `has_more=false` 时 `next_cursor=null`；`has_more=true` 时 items 非空且 cursor 必须严格前进；
- 三个 section 独立分页，但只能附着在创建它们的第一页 snapshot 上。

## 3. Snapshot 一致性

范围摘要和三个 section 是四次跨层调用，但页面不能混合四个任意时刻的事实。R1 使用 generation token 协议：

1. `range_summary` 读取一次固定 UTC Clock，并在单个 SQLite read transaction 中读取所有贡献 Store 的 generation；`snapshot_token` 同时封装 generation 向量与这次 `evaluation_clock_utc`；
2. 三个 `list_day_items` 首屏和后续页都携带该 token；
3. C++ 在每次查询的 read transaction 内重新读取贡献 generation；只在与 token 完全一致时返回数据，并始终使用 token 内的固定 Clock 推导时间相关状态和排序，不能改用后续调用时的系统时间；
4. 任一 generation 变化返回 `CALENDAR_SNAPSHOT_EXPIRED`，不返回部分成功数据；
5. Flutter 只在范围与三个首屏都成功且 token 相同时原子替换页面快照；失败时保留最近一次完整成功快照并提供重试；
6. 墙钟前进本身不让一个正在分页的 token 在 C++ 端过期；Flutter 在刷新、详情修改、新建成功、时区变化和请求 timezone 当地跨日时主动废弃旧 token、cursor 与相关缓存并建立新快照。

token 覆盖 Event、Event Recurrence、EventOccurrenceState、Habit、HabitRecurrence、HabitCheckIn、Anniversary、AnniversaryRecurrence 与 Reminder Store。Calendar 查询还会在同一个 SQLite read transaction 内只读 `ReminderRecoveryBatch` identity，用于区分合法的 `Reminder.recovery_batch_id` 与真实孤儿引用；它不拥有 Calendar 输出字段，也不进入 token generation。合法事务若改变该关系必须同时修改 Reminder，因此由 Reminder generation 使旧 token 失效。Notification、Android Alarm 和 Flutter 缓存不参与。

## 4. 日期、时间与重叠

- date 始终是 `YYYY-MM-DD` 的 civil date，不转换成 UTC 午夜；
- timed Event 与选中当地日窗口重叠，当且仅当 `start_at < day_end_instant && end_at > day_start_instant`；
- all-day Event 覆盖选中日期，当且仅当 `start_date <= selected_date < end_date`；
- Event recurrence 在 Event 原 timezone 的当地墙上时间展开，DST gap 前移至首个合法 Instant，fold 取较早 Instant，再与请求 timezone 的当地日窗口判断重叠；
- occurrence 在查询范围前开始但跨入范围时仍必须返回；结束恰好等于日初时不返回到该日；
- Habit 与 Anniversary 都保持 date-only；设备 timezone 改变不重解释既有 CheckIn 或 Anniversary 原始日期。

## 5. Event 日投影

`CalendarEventItem` 返回实际 Event/occurrence 的时间结构和详情路由身份：

- 非重复 Event 的 `occurrence_key`、`recurrence_revision` 和 occurrence anchor 全为 `null`；
- 重复 timed occurrence 携带 `occurrence_key + recurrence_revision + occurrence_start_at`；
- 重复 all-day occurrence 携带 `occurrence_key + recurrence_revision + occurrence_start_date`；
- `day_display` 是 `all_day / starts_at / continues / ends_at`，`display_local_time` 只在 `starts_at/ends_at` 时存在；Flutter 只把枚举本地化，不重新判断跨日；
- 可见 status 是 `pending / in_progress / overdue / completed / skipped`；cancelled occurrence、cancelled/archived series 和软删除 Event 不返回；
- completed 继续返回但不产生 Event 圆点；skipped 返回、弱化展示且仍产生圆点。

状态推导统一使用 `range_summary` 写入 `snapshot_token` 的固定 UTC Clock，禁止逐条读取当前时间或让后续分页改用新的 Clock。显式 occurrence state 的 `completed / skipped` 优先；非重复 Event 的持久化 `completed` 投影为 `completed`。其余 active timed Event/occurrence 按实际 `[start_at, end_at)` 与固定 Clock 比较：Clock 在开始前为 `pending`，处于半开区间内为 `in_progress`，到达或超过结束时为 `overdue`。active all-day Event/occurrence 先把同一 Clock 转成请求 timezone 的当地日期，再按实际 `[start_date, end_date)` 作同样三段判定。查询的 selected date 只决定该条目是否落在当天，不替代 Clock 参与状态判定。

重复系列进入 `completed` 后，以 `completed_at` 作为不可再生成实例的严格截止点。timed occurrence 以 `occurrence_start_at` 为锚点；all-day occurrence 以其 `occurrence_start_date` 在该 recurrence timezone 中解析出的当地日初 Instant 为锚点。只有锚点严格早于 `completed_at` 的 occurrence 才保留，锚点恰好等于截止时刻时排除；截止前已经开始的跨时或多日 occurrence 保留完整原区间，不在 `completed_at` 截断。由此，完成当日是否保留全天 occurrence 取决于系列时区当地日初是否早于完成时刻。保留下来的 occurrence 继续遵守显式 occurrence state 优先级，否则投影为 `completed` 且不产生 Event 圆点。

对 timed item，先把选中当地日解析为 Instant 半开窗口 `[day_start, day_end)`：实际开始位于窗口内时为 `starts_at` 并显示请求 timezone 下的开始 `HH:mm`；开始早于 `day_start` 且结束不晚于 `day_end` 时为 `ends_at` 并显示结束 `HH:mm`；开始早于 `day_start` 且结束晚于 `day_end` 时为 `continues` 且时间为空。用于排序和 cursor 的“当地开始”不是 `display_local_time`，而是 `max(actual_start_at, day_start)`：因此所有从前一日跨入的 timed item 都以当天日初作为有效开始点，结束时间不会错误参与开始排序。结束恰好等于 `day_end` 属于 `ends_at`。all-day item 的有效开始键也统一为请求 timezone 的选中日 `day_start`，不以原始 `start_date` 区分；同一天同完成 bucket 的全天条目直接进入标题与稳定 identity tie-breaker。

稳定排序 tuple 为：

```text
is_all_day desc
→ completion bucket（pending/in_progress/overdue/skipped 在前，completed 在后）
→ 选中日有效开始 Instant `max(actual_start_at, day_start)` asc
→ title Unicode code point asc
→ event_id asc
→ recurrence_revision null-first asc
→ occurrence_key null-first asc
```

## 6. Habit 日投影

只在 Habit 的有效挑战区间内返回 `CalendarHabitItem`：

- `upcoming / absent / partial / done / skipped / missed` 完全复用 Habit DailyStatus 语义；
- upcoming、absent、missed 没有 CheckIn；clear 后今天为 absent、过去为 missed；
- done 条目继续显示但不产生 Habit 圆点；其他状态产生圆点；
- 数量型使用 `_hundredths` JSON safe integer：`0 < completed_count_hundredths < target_count_hundredths` 才是 partial，`completed_count_hundredths >= target_count_hundredths` 才是 done，超额真实保留；二元 done 的数量、目标和单位为 `null`；
- Calendar 不重算 lifecycle、streak、rate 或 CheckIn 事实。

稳定排序 tuple 为：

```text
status bucket（absent/partial → done → skipped → missed → upcoming）
→ active Reminder local_time null-last asc
→ Habit.created_at asc
→ habit_id asc
```

## 7. Anniversary 日投影

- 一次性 Anniversary 只在原始 date 返回；
- 年度 Anniversary 从 source year 起动态展开；2 月 29 日在非闰年落该年 2 月最后一天；
- occurrence 是当地 date，没有 UTC Instant、Event revision 或完成/跳过状态；
- `occurrence_key` 继续按 `anniversary_id + occurrence_date` 由 C++ 生成；
- `years_elapsed` 为 0 或非负整数，Contract 不传“第 N 周年”本地化文本。

稳定排序 tuple 为：

```text
importance（important_urgent → important_noturgent → unimportant_urgent
            → unimportant_noturgent → null）
→ title Unicode code point asc
→ anniversary_id asc
→ occurrence_key asc
```

## 8. 圆点守恒

同一 `snapshot_token` 下，完整拉取某日三组分页后必须满足：

- `has_open_event` 等于至少存在一个返回且 status 不为 completed 的 Event item；
- `has_pending_habit` 等于至少存在一个返回且 status 不为 done 的 Habit item；
- `has_anniversary` 等于至少存在一个 Anniversary item；
- 圆点不依赖第一页、page size 或 Flutter 是否已加载对应分组。

## 9. 活动 Reminder

`has_active_reminder=true` 只表示权威 Reminder 中存在匹配目标/occurrence、`is_enabled=true`、`deleted_at=null` 且 status 为 `pending` 或 `scheduled` 的任务。它不表示 Android 一定已经注册 Alarm，也不从 Notification 历史推断。

## 10. Cursor 与失败恢复

cursor 是 opaque 值，绑定：date、timezone、section、page size、排序 revision、完整最后排序键和 snapshot token。禁止 offset 分页、SQL rowid、hash/map 迭代顺序或 Flutter 去重掩盖重复。

- malformed token：`CALENDAR_SNAPSHOT_INVALID`；
- generation 已变化：`CALENDAR_SNAPSHOT_EXPIRED`，Flutter 重新获取范围和三个首屏；
- malformed cursor：`CALENDAR_CURSOR_INVALID`；
- cursor 查询条件不匹配：`CALENDAR_CURSOR_QUERY_MISMATCH`；
- 非法 date、section、page size 或结构：`CONTRACT_VALIDATION_FAILED`；
- 非法 IANA timezone：`TIMEZONE_ID_INVALID`；
- SQLite 或损坏数据：返回既有 Storage/Domain 错误，不能降级为空日历。

## 11. 版本与迁移

Calendar View R1 是 Native Contract v2 内从未发布过的 additive capability revision。它没有旧 Calendar reader/writer 或持久化数据，因此不提升全局 Native version，也不创建伪 migration；Dart、Kotlin/JNI 与 C++ 必须在同一 APK 同步升级。

两个 `calendar.*` 方法的 Contract、C++/SQLite、Kotlin/JNI、Flutter 与真实 production composition 已实现。产品负责人于 2026-09-02 明确接受正式签名/商店上传、真机时区与 DST、TalkBack、200% 字体/减少动画、强杀恢复、升级回滚/签名密钥恢复和正式 Release UI 全链为非阻断发布债后，能力标记为 `implementation_status: integrated`、`release_status: active`。该发布决定不改变 Native v2 wire、Storage v5 或 Calendar View revision，也不得将 `OPEN-CAL-001` 的未执行场景描述为已验证；Release 签名门禁虽然已 fail-closed 并通过一次性非生产密钥验证，当前仍没有生产密钥签名或商店校验过的正式产物。
