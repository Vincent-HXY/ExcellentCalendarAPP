# 搜索-03：C++ 与 SQLite 查询开发计划

Status: Completed / Production Integrated / Host + Android Device Verified / Released

> 2026-09-02 发布校准：本计划代码、主机门禁、独立复审和 Android 13 代表设备性能已完成；Review findings 与 completed recurring-series cutoff 漂移均已返修。产品负责人接受 `OPEN-SEA-001` 发布后债务后，Search capability 已激活。下方未勾选项保留为原始派发验收矩阵，不表示当前层仍未完成。

负责人：C++ 下层（`cpp-core-feature`）  
允许修改：`cpp_core/**`  
依赖：搜索-02 Contract Revision 2 冻结基线  
禁止修改：`contracts/**`、Flutter、Android/Kotlin、SQLite schema/version

## 1. 交付目标

实现统一 `SearchQueryService`、严格 Boundary/API 与 SQLite v5 只读快照，让唯一 internal `search.query` 能真实查询 Event、Habit、Anniversary 和当前 Category，并生成 Contract 冻结的三组结果。

V1 不做 Storage migration、索引或 FTS。生产 Event 必须读取 `RecurringEventState`；禁止读取 `legacy_events` 或把旧 `EventRepository::search` 的 offset 结果当作新 Search。

## 2. 当前基线与架构边界

- Event 生产源：`RecurringEventTransaction::load`、`RecurringEventQueryService`、`SqliteCalendarDatabase::load_recurring_state`。
- Habit `HabitService::list` 会构造完整详情/统计，不适合搜索热路径；Search 不读取 CheckIn。
- Anniversary list 无关键词和 Search cursor；既有 `annocc1` cursor 不能复用。
- `common/string_utils` 只有 ASCII helper；Category 内已有严格 UTF-8/Unicode 空白实现，可抽成公共窄模块并保留原 API 包装。
- SQLite v5 是 20 tables / 24 indexes / 17 generations 的严格 schema，未知 DDL 会被 checker 拒绝。
- 搜索历史完全不进入 C++、SQLite 或 cursor。

## 3. 建议模块与符号

新增或按现有命名收敛：

- `domain/search.hpp`、`src/domain/search.cpp`
  - `NormalizedSearchText`、`SearchMatch`、`SearchMatchField`、`SearchRelevanceTier`；
  - strict UTF-8 decode、规范化、token AND、snippet。
- `application/search_query_service.hpp/.cpp`
  - `SearchQuery`、`SearchSectionRequest/Result`、三类 result projection；
  - `SearchQueryService::query`。
- `repository/search_query_repository.hpp`
  - `SearchQuerySnapshot`、per-target generation snapshot、deferred read transaction port。
- `boundary/contract/search_json.hpp/.cpp`；
- `boundary/api/search_api.hpp`、`src/boundary/api/search_v2_endpoint.cpp`；
- Search Core/Boundary/SQLite/Performance tests。

共享底层工具可以与 Calendar 计划复用“deferred read snapshot”和“recurrence window seek”，但 Search 不得依赖 Calendar 页面 DTO 或复制一套 Store owner。

## 4. 实现拆解

### C0：Contract 消费与基线保护

- [ ] 运行 Search Contract validator 并把 31 fixtures 接入 C++ 正反例；任何 `x-search-contract-revision != 2` 立即停止；
- [ ] 列出 Contract 字段到 Boundary/Application 类型的逐字段映射；
- [ ] 确认 `event.search` 原 endpoint 和测试不变；
- [ ] 识别 Calendar/Habit 在途 diff 的共享文件，避免覆盖；
- [ ] 新能力保持 planned/blocked，不修改 contracts 或 docs。

### C1：Unicode 与匹配领域模块

- [ ] 严格验证 UTF-8，拒绝 overlong、surrogate encoding、截断 sequence 和非法 scalar；
- [ ] 按冻结 White_Space trim/collapse/tokenize，限制 128 scalar / 512 bytes；
- [ ] 只实现 locale-independent ASCII A-Z fold；不得调用 locale `tolower`；
- [ ] 允许字段内连续子串、token 跨字段 AND；禁止匹配技术字段；
- [ ] 实现 7 个 relevance tier 与跨字段最差 tier 规则；
- [ ] 生成 primary/matched fields 和最多 200 scalar snippet，不切断 UTF-8；
- [ ] canonical Store 中出现非法 UTF-8 时返回 `STORAGE_DATA_CORRUPTED`，不跳过记录。

### C2：一次只读快照

- [ ] 新建窄 `SearchQueryRepository`，只加载本次 requested target types；
- [ ] 使用显式 deferred SQLite read transaction，而非写向 `BEGIN IMMEDIATE`；
- [ ] 数据行与 generation 在同一个 SQLite snapshot 中读取；
- [ ] contributor：Event=`events/recurrence_versions/event_occurrence_states/categories`；
- [ ] Habit=`habits/habit_recurrences/categories`；
- [ ] Anniversary=`anniversaries/anniversary_recurrences/categories`；
- [ ] CheckIn/Reminder/Notification/Template mutation 不使 Search cursor 过期；
- [ ] Category rename/delete 通过 categories generation 正确失效；
- [ ] 如果整 Store JSON 重建造成内存峰值，只可在 schema 不变前提下改成逐行严格 decode。

### C3：三类 projection

#### Event

- [ ] 基于 production `RecurringEventState`，过滤 deleted/cancelled/archived；
- [ ] recurrence 必须先按 Event 自身 timezone 展开成 canonical occurrence；请求日期范围完全按请求 timezone 解释，Event timezone 不得重解释 filter；
- [ ] 请求当地日期边界用随包 TZDB 解析为当地午夜：gap 取 gap 后第一个有效 instant，fold 取较早 instant；timed overlap 固定 `start < queryEnd && end > queryStart`；
- [ ] all-day 直接使用 civil date 的 `startDate < queryEndDate && endDate > queryStartDate`；timed/all-day/multi-day/cross-midnight 均用同一半开公式，不按 24 小时猜 DST；
- [ ] recurrence 按目标窗口算术 seek，只检查有限邻域，禁止从 index 0 展开到 1,000,000；
- [ ] cancelled occurrence 隐藏，completed/skipped 遵循 include_completed；
- [ ] completed recurring series 使用 Calendar/Search 共用 eligibility helper：timed start instant 或 recurrence timezone 全天日初必须严格早于 `completed_at`；cutoff 前长区间保留完整范围，等于/晚于 cutoff 的显式 state 不得复活；
- [ ] 状态投影逐字段复用 Calendar Contract：显式 completed/skipped 优先；活动 timed 依固定 clock 与 `[start,end)` 得到 pending/in_progress/overdue；all-day 依请求 timezone 当地日期与 `[startDate,endDate)`；reopen 后重新动态投影；
- [ ] ongoing 的 temporal bucket/distance 为 `0/0`；未来从 start 算，过去从 end 算；all-day 过去距最后占用日期算，completion bucket 独立；
- [ ] 无日期范围选择 current/next open，否则最近 closed/past；completed series 特例为 cutoff 前最后一个 eligible occurrence，无 eligible occurrence 则不返回。有范围固定按 series/cancelled → cutoff → overlap → include_completed 过滤，再选择距请求 timezone 当地 today 最近者。timed 占用日期按实际半开 instant 区间投影到请求 timezone，午夜 end 不占结束日；all-day 不移位。禁止 open 优先；等距按当前/未来、当地 start、revision、occurrence key；
- [ ] recurring item 返回 revision、UUIDv5 occurrence key 和正确 timed/date anchor；
- [ ] 一个 Event 最多一项，系列未来仍 open 时不能被一次 closed occurrence错误变成完成结果。

#### Habit

- [ ] 只加载定义、recurrence、Category，不调用完整详情/统计和 CheckIn；
- [ ] challenge 与 query date range 以当地自然日期相交；
- [ ] upcoming/active/completed/ended_early 与开关严格对应；
- [ ] 选择交集内距 today 最近 `occur_date`，closed remaining_days 固定 0；
- [ ] `_hundredths` 保持 safe integer，不用 double 表示目标事实。

#### Anniversary

- [ ] 复用现有 solar、一年一次、2 月 29 日和 UUIDv5 identity；
- [ ] 只检查目标年附近有限候选，禁止逐年无界循环；
- [ ] 无范围返回 next 或 recent past；有范围返回距 today 最近 occurrence；
- [ ] 只返回 date、relation/days/years elapsed，不生成 UTC 午夜；
- [ ] include_completed 不影响 Anniversary。

### C4：Application pipeline 与稳定排序

固定流水线：

1. strict Boundary 校验并规范化 keyword；
2. 首屏捕获一次 `evaluated_at`；
3. 在一个 deferred transaction 加载 requested stores/generations；
4. 批量构建 Category、recurrence、occurrence-state hash map；
5. 先做 lifecycle/category/text 预过滤；
6. 再做有限 occurrence/date projection；
7. 生成 Contract 完整 sort tuple；
8. 计算每 section 精确 total；
9. keyset pagination；
10. 返回相同 `query_generation`、snapshot token 和 requested typed sections。

- [ ] 三种排序共享 comparator 与 cursor last-key encoder；
- [ ] updated_at descending 与 ID tie-break 稳定；
- [ ] date-only 与 datetime 比较不互相转换；
- [ ] section 固定子序，空 section 仍在 response 中；
- [ ] target ID 跨页无重复/漏项，cursor 必须严格前进。

### C5：cursor 与 Boundary/API

- [ ] native runtime 每次进程启动时由 OS CSPRNG 生成 32-byte Search-only HMAC key，只驻内存且随进程重建轮换；生成失败使 Search runtime 以 `NATIVE_INTERNAL_ERROR` fail closed；
- [ ] 输出 `prefix.base64url(payload || tag)` 的 `srchsnap1.*`/`srchcur1.*`；tag 为 `HMAC-SHA-256(key, ascii(domain) || 0x00 || payload)` 完整 32 bytes，cursor/snapshot 使用不同 domain；
- [ ] 解码先校验长度、alphabet、无 padding 与 canonical Base64URL，再 constant-time 校验 tag，最后解析 payload/query；旧进程 key、tamper、truncated tag 均返回 `SEARCH_CURSOR_INVALID`；
- [ ] payload 是 C++ 私有的 versioned canonical length-prefixed binary，首 byte 为 1 并覆盖所有冻结 binding；Kotlin/Dart 不编码或解析。禁止裸 JSON、FNV-1a、Calendar checksum、只存 ID或持久化 key；仅测试 factory 可注入确定 key；
- [ ] cursor 绑定 invariants 列出的 15 项，包括 evaluated_at、完整 last key 与 per-target generations；
- [ ] 无关 section Store mutation 不使当前 section 过期；相关 mutation 返回 `SEARCH_CURSOR_EXPIRED`；
- [ ] tamper/decode/auth 失败为 `SEARCH_CURSOR_INVALID`；query/filter/type/timezone/page mismatch 为 `SEARCH_CURSOR_QUERY_MISMATCH`；
- [ ] strict JSON 拒绝缺字段、额外字段、null/type/enum/date/safe integer/UTF-8 错误；
- [ ] endpoint 建议稳定为 `search_query_v2(std::string_view)`，只返回 `NativeResult<SearchQueryResponse>`；
- [ ] RuntimeState 暴露唯一 Search service，不创建第二 SQLite runtime owner；
- [ ] C++ exception 不逃逸，错误 metadata 与 Contract 完全一致。

## 5. SQLite/FTS 与性能门禁

V1 明确禁止：

- 修改 v5 DDL、schema hash、table/index/trigger 数量；
- 启用 FTS5 或第三方 tokenizer；
- 新建 SearchIndex writer/rebuild；
- 用 SQL `%LIKE%` 假装已经解决中文一字查询性能。

性能数据至少覆盖均衡的三类对象、长历史 recurrence、Category 与状态：

| 数据规模 | 必须记录 |
| --- | --- |
| 1k | cold/warm、P50/P95、峰值内存、SQL 次数、candidate 数 |
| 10k | core query P95 目标 ≤300ms；端到首屏由集成轨目标 ≤500ms |
| 50k | 不得卡死/OOM/百万级 occurrence loop；记录可用性与退化曲线 |

先优化窄 Store 读取、流式 decode、文本预过滤、hash lookup 和 recurrence seek。仍失败时停止发布，提交 query plan/实测报告给总工程师，由其另立 SQLite v6/FTS 计划；不得自行迁移。

## 6. 测试矩阵

- Boundary：missing/extra/null/type/enum/date/timezone/safe integer/cursor/invalid UTF-8；
- 文本：单字中文、ASCII case、非 ASCII 不 fold、全部冻结 whitespace、emoji、跨字段 AND、Category、snippet scalar 边界；
- Event：one-time/recurring、timed/all-day/multi-day/cross-midnight、23h/25h DST window、gap/fold、月末、长期 anchor、reopen、五种投影状态、ongoing distance、最近 closed 胜更远 open、route identity；
- Habit：4 lifecycle、challenge 边界、Category、CheckIn mutation 不使 cursor 过期；
- Anniversary：one-time/yearly、1900/2000/2100 leap rule、date-only；
- Category：rename/delete/dangling/uncategorized/selected IDs；
- 排序分页：0/1/19/20/21/40/41/100/101+，首屏 requested section 守恒、精确 total、跨页重复/漏项、cursor 不前进、total/timezone/evaluated_at/snapshot 漂移、三 section 独立；
- cursor：固定 key HMAC golden、payload/tag tamper、truncated/noncanonical Base64URL、错误 domain、旧进程 key、query/type/sort/timezone/page mismatch、相关/无关 mutation、跨午夜延续；
- SQLite：真实临时 v5、deferred snapshot、并发 mutation、零写入、schema byte/hash/count 不变；
- 性能：1k/10k/50k 与长 recurrence；
- 回归：完整 build-after-test。

必须执行：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不得只运行可能陈旧的 CTest binary。

## 7. 完成门禁与下层回报

C++ 层仅在以下条件下报告 `Layer Complete / Awaiting Integration`：

- Search Contract fixtures 与全部新增/回归测试通过；
- 稳定 endpoint 可供 Kotlin JNI 调用；
- Unicode、occurrence、排序、cursor 只有 C++ 一份权威实现；
- SQLite v5 schema/version/数据无写入；
- `event.search` 未暗改；
- 提供 1k/10k/50k 性能证据与 FTS 决策；
- 无 Contract/docs/Flutter/Kotlin 修改。

回报必须包含：修改文件/符号、字段映射、Runtime 注入点、snapshot contributor、cursor payload/version、完整 sort tuple、recurrence 候选上界、测试命令与结果、性能环境与原始摘要、未验证项和集成所需 JNI 签名。
