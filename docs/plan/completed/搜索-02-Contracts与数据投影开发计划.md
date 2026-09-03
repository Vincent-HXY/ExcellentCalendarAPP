# 搜索-02：Contracts 与数据投影开发计划

Status: Completed / Contract Frozen Revision 2 + Pre-release Amendment / Integrated + Active

负责人：总工程师（`calendar-data-contracts`）  
上游：`搜索-01-三类聚合搜索与本地历史开发计划.md`  
下游：搜索-03 C++、搜索-04 Kotlin、搜索-05 Flutter

## 1. 目标与完成口径

为三类聚合搜索冻结一套 Native v2 additive Contract，使 Dart、Kotlin 和 C++ 可以在不复制规则、不依赖彼此未完成代码的前提下并行开发，并通过同一组机器 fixture 校验 Unicode、筛选、date/datetime、occurrence、排序、分页、cursor 和本地历史。

本计划最初完成只代表协议冻结；在 C++、Kotlin/JNI、Flutter、真实 SQLite、同一 APK、代表设备性能与独立 Review 通过前，`search.*` 曾保持 `implementation_status: planned`、`release_status: blocked`。上述生产链与门禁现已完成，产品负责人接受 `OPEN-SEA-001` 发布后债务后，统一 Search Query 与本地 History 当前为 `integrated + active`。

2026-08-31 开发前复核撤回了从未被 production reader/writer 消费的 Revision 1，并以 Revision 2 定向补齐 Event 时间/状态、分页序列、游标认证和 History 持久化失败语义。该修订不需要数据迁移；下游只能以 `x-search-contract-revision: 2` 开发，Revision 1 不再是可实现基线。

2026-09-02 在 capability 仍为 `planned + blocked`、且不存在 production reader/writer 的前提下，对 Revision 2 做发布前 amendment：Search 新增对 Calendar `completed_recurring_series_cutoff` 的完整引用与机器副本，validator 同时深比较 status projection 与 cutoff，并冻结 eligibility 顺序、无日期选择和“显式 occurrence state 不得复活 cutoff 后实例”。本修订不改变 wire shape、Schema metadata、存储格式或跨层 revision 常量，因此不升级 Revision 3，也不需要数据迁移。

## 2. 影响矩阵

| 层 | 当前语义 | 本计划交付 | 兼容/迁移 | 下游验证 |
| --- | --- | --- | --- | --- |
| Domain | SearchIndex 只是未来加速概念 | Search Query 是 canonical facts 的只读组合投影 | 不新增领域实体 | 不变量/fixture |
| Contract | 仅 `event.search`，无统一搜索 | 3 public methods、1 native call、12 Schema、6 错误、4 enum | Native v2 additive | Search validator |
| Dart | Search Tab 占位 | typed query/history 输入输出基线 | 同 APK 同步升级 | DTO/adapter/widget |
| Kotlin/JNI | 无 Search handler/history | 1 个 JNI query + 2 个 Kotlin-local history 方法 | 新 local format v1 | unit/JNI/APK |
| C++ | Event 单类旧搜索 | 统一三类 Query Service 与 typed projection | 旧 `event.search` 不变 | Core/Boundary/SQLite |
| SQLite | active v5 canonical Store | 只读窄快照；不加表/索引/trigger | 无 Storage migration | schema unchanged/perf |
| SearchIndex/FTS | 无 production writer/rebuild | 继续 deferred | 性能失败后另立 v6 计划 | 1k/10k/50k gate |
| Backend/Sync | 无云搜索 | 不修改 | 不适用 | 确认无网络链路 |

## 3. 已冻结能力

### 3.1 方法映射

| 公开方法 | Request | Response | 实现 owner | Native call |
| --- | --- | --- | --- | --- |
| `search.query` | `SearchQueryRequest` | `SearchQueryResponse` | C++，Kotlin 严格转发 | `search.query` |
| `search.get_local_history` | `NativeEmptyRequest` | `SearchHistoryResponse` | Kotlin local | 无 |
| `search.replace_local_history` | `ReplaceSearchHistoryRequest` | `SearchHistoryResponse` | Kotlin local | 无 |

三条公开方法都返回 `NativeResult<T>`，当前均为 `integrated + active`。History 不得增加虚假 JNI/C++ 入口。

### 3.2 查询关联与分组

- `query_generation` 是 Flutter Application 生成的非负 safe integer；C++ response 必须原样回显。
- 它只用于拒绝 stale response，不是 Store generation，不写入 cursor。
- `target_types` 和 section 使用固定子序：`event → habit → anniversary`，非空、唯一。
- 多 section 请求只允许首屏且 sections 必须等于 `target_types`；续页恰好请求一个 section。
- 即使总数为 0，response 也必须返回每个 requested section；Flutter 再隐藏空卡片。
- 首次多 section 查询共享一个 SQLite read snapshot 与一个 `evaluated_at` C++ Clock instant。

### 3.3 关键字与匹配

- 原请求及规范化结果最多 128 个 Unicode scalar / 512 UTF-8 bytes；拒绝孤立 UTF-16 surrogate。
- 冻结 Unicode White_Space 集合；trim 后把连续 whitespace 折叠成单个 U+0020。
- 不执行 NFC/NFKC；只对 ASCII `A-Z` 映射 `a-z`，其他 Unicode 原文比较。
- token 以 U+0020 分割并使用 AND，可命中同一对象的不同允许字段。
- 中文为每 token 连续原文子串，不做分词、拼音、语义、错别字或同义词扩展。
- 三类允许字段与禁止字段、7 级 relevance、跨字段最差 tier 规则均由 `search_query_invariants.yaml` 冻结。
- `SearchMatchProjection` 返回 `primary_field`、有序 `matched_fields` 和 nullable snippet；snippet 最多 200 scalar，C++ 不得切断 UTF-8 scalar，Flutter 根据 truncation flag 加省略号。

### 3.4 Category filter

| Wire 值 | 语义 |
| --- | --- |
| `category_ids=null`, `include_uncategorized=false` | 不限制 Category |
| `category_ids=[]`, `include_uncategorized=true` | 仅目标 `category_id=null` |
| 非空 IDs, `include_uncategorized=false` | 仅指定弱引用 ID |
| 非空 IDs, `include_uncategorized=true` | 指定 ID 或未分类 |

空数组 + false 非法。筛选使用目标保存的 opaque `category_id`；悬空/软删除引用不等于未分类。展示与名称全文匹配只读取当前活动 Category，缺失时 `category=null`，旧名称不得命中。

### 3.5 日期、完成状态与 occurrence

- 日期范围为当地 date-only 半开区间；两个边界同时 null 或同时存在，空/倒序范围返回 `SEARCH_QUERY_INVALID`。
- Flutter 把 UI inclusive end 转为 `date_to_exclusive`；任何层不得把 date-only 转为 UTC 午夜。
- 对 timed Event，C++ 用请求 IANA timezone 把两个当地午夜解析成 UTC instant window；DST gap 取 gap 后第一个有效 instant，fold 取较早 instant，并使用随包 TZDB。Event 自身 timezone 只负责 recurrence 展开，不能重解释请求范围。
- timed overlap 固定为 `event_start < query_end && event_end > query_start`；all-day overlap 固定为 `start_date < query_end_date && end_date > query_start_date`。跨午夜和多日 Event 不设特例，使用同一半开公式。
- Event 排除 cancelled/archived/deleted 系列和 cancelled occurrence；`include_completed=false` 排除 completed/skipped item。
- completed recurring Event 的 occurrence anchor 必须严格早于 `completed_at`；timed 使用 `occurrence_start_at`，all-day 使用 recurrence timezone 当地日初。等于/晚于 cutoff 的 occurrence 不存在，显式 completed/skipped state 也不能复活；cutoff 前开始的长区间保留完整范围。处理顺序固定为 series/cancelled → cutoff → date overlap → `include_completed` → occurrence selection → total/sort/cursor。
- completed recurring Event 在无日期范围时选择 cutoff 前最后一个 eligible occurrence；截止前没有 occurrence 时不返回该 Event。
- Event 状态投影逐字段等同 `calendar_query_invariants.yaml#/sections/event/status_projection`：显式 completed/skipped 优先；活动 timed 依固定 query clock 与 `[start,end)` 得到 pending/in_progress/overdue；活动 all-day 依请求 timezone 当地日期与 `[start_date,end_date)` 得到同三态。reopen 后回到动态 clock 投影，不能永久写成 pending。
- ongoing timed/all-day 的 temporal bucket 为 0、distance 为 0；未来从开始算距离，过去从结束（all-day 为最后占用日期）算距离，完成 bucket 与 temporal bucket 相互独立。
- 重复 Event 返回一个逻辑对象和一个选择 occurrence；导航身份为 `target_id + recurrence_revision + occurrence_key + occur_at/occur_date`。有日期范围时先过滤合法/完成条件，再选择距请求 timezone 当地 today 最近的 occurrence；timed 的占用日期由实际半开 instant 区间投影到请求 timezone（恰在当地午夜结束不占结束日），all-day 使用原 civil dates。open 不优先于更近的 closed；等距时当前/未来优先于过去，再按当地开始、revision、occurrence key 稳定决胜。
- Habit 以 challenge 有效日期区间匹配；upcoming/active 为 open，completed/ended_early 为 closed；CheckIn 日状态不改变 lifecycle filter。
- Anniversary 只支持现有 solar 语义，复用既有 2 月 29 日规则与 UUIDv5 occurrence identity；完成开关不影响它。
- Event timed 使用 `occur_at`；Event all-day、Habit、Anniversary 使用 `occur_date`，强类型 item 不允许万能 nullable ViewModel。

### 3.6 排序、snapshot 与 cursor

- relevance：tier → completion bucket → temporal bucket/distance → `updated_at desc` → ID。
- occur time：当前/未来近到远 → 最近过去 → 无业务时间 → ID。
- updated at：`updated_at desc → ID`。
- Event 同日 mixed time 以请求 timezone 的当地日期比较，全天在定时前，但不把 date-only 变成 instant。
- V1 每一页固定 20，首屏和 continuation 都不接受其他 `page_size`；每 section 精确 `total_count`，独立 keyset pagination。
- 首屏 response 必须恰好包含所有 requested sections，并各返回 `min(total_count,20)` 项；续页必须返回 `min(remaining,20)` 项。整个 cursor chain 中 total 不漂移、identity 不重复不遗漏、cursor 严格前进，且 `has_more` 当且仅当累计唯一项数小于 total。
- `srchcur1.*` 与 `srchsnap1.*` 使用 `prefix.base64url(payload || HMAC-SHA-256 tag)`，MAC 输入为各自 ASCII domain separator + `0x00` + versioned payload，完整 tag 为 32 bytes。key 由 C++ native runtime 在每次进程启动时用 OS CSPRNG 生成、仅驻内存；旧进程 cursor 返回 `SEARCH_CURSOR_INVALID`。解码必须拒绝 padding/非规范 Base64URL，并以 constant-time 比较 tag；禁止裸 JSON、FNV 或 Calendar checksum 复用，仅测试允许注入确定 key。
- cursor payload 只由 C++ 编解码，Dart/Kotlin 完全 opaque；它绑定完整 query/filter/type/timezone/固定 page size/contract/sort revision/evaluated_at/last sort key/相关 Store generations。
- Event、Habit、Anniversary cursor 只绑定自身贡献 Store 与共享 Category；无关 section mutation 不应使它过期。
- malformed、query mismatch、Store mutation 分别为 `SEARCH_CURSOR_INVALID`、`SEARCH_CURSOR_QUERY_MISMATCH`、`SEARCH_CURSOR_EXPIRED`；只有 expired 可自动从该 section 第一页恢复。

### 3.7 本地历史

- 最多 20 条规范化 display keyword，ASCII-insensitive identity 去重，最新显示字形置顶。
- response 带 monotonic safe-integer `revision`；缺省 Store 初始为 0。
- replace 必须提交完整有序列表和 `expected_revision`；revision mismatch 零写入并返回 `SEARCH_HISTORY_CONFLICT`。
- 列表未变化时即使 revision 已达 `9007199254740991` 也幂等返回原 revision且零写入；真实变化或损坏修复在上界必须返回 `SEARCH_HISTORY_STORAGE_FAILED`，保留原 bytes/快照且不得回绕。
- 已知 v1 损坏值需要规范化、去重、保序、截到 20 并原子修复；未知未来版本保留原 bytes 并失败。
- Kotlin 使用 `android.util.AtomicFile` 在 `Context.noBackupFilesDir` 保存一个 versioned JSON 文件；在 `finishWrite` 成功前不得发布新内存 snapshot，异常必须 `failWrite` 并返回 `SEARCH_HISTORY_STORAGE_FAILED`。禁止以 SharedPreferences `commit()` 充当 confirmed CAS。
- `noBackupFilesDir` 天然不进入 Auto Backup/设备迁移；不得再添加与实际存储无关的 preference backup XML，也不保存账号、筛选、结果或 sync metadata。
- 自动 debounce 不记录。键盘提交仅在 query 成功（包括零结果）后记录 response 的 `normalized_keyword`，失败不记录；点击历史先立即置顶并提交 history，再使用该词查询；打开结果先记录当前已接纳 response 的规范化词，再导航。history 写失败不阻断查询/导航，但 UI 必须回滚并提示。

### 3.8 兼容与 FTS

- 旧 `event.search` request/response/排序不变。
- 不修改 Event/Habit/Anniversary/Category persisted facts。
- `SearchIndexResponse` 补充 optional `occur_date` 并禁止与 `occur_at` 同时非空，但仍为 planned 可重建概念。
- SQLite v5 精确 schema 不变；V1 不新增 FTS table/index/trigger/writer。
- 只有 canonical scan + 窄 snapshot + 有界 recurrence 在代表设备门禁失败后，才建立独立 Storage v6/SearchIndex/FTS migration 计划。

## 4. 文件交付

- [x] 扩充 `docs/domains/search_index.md`，区分 Search Query 与 SearchIndex；
- [x] 新增 `contracts/search/search_query_invariants.yaml`；
- [x] 新增 query/section request 与 response Schema；
- [x] 新增 Event/Habit/Anniversary typed item Schema；
- [x] 新增 Category、match/snippet projection Schema；
- [x] 新增 history response 与 atomic replace Schema；
- [x] 修订 `search_index_response.schema.json` 的 date/datetime 投影；
- [x] 新增 3 public methods 与唯一 `search.query` native call；
- [x] 新增 Search enum/error 并闭合 `NativeError`；
- [x] 新增 31 组 schema/semantic/golden fixture，包括 request-response pair、cursor-chain 守恒、Event DST/状态和 HMAC tamper；
- [x] 新增 `run_search_v1_validation.py` 与 `validate_search_v1.py`；
- [x] 更新 Contract README 的不变量与兼容矩阵。

## 5. 下游冻结输入

| 负责人 | 必须消费 | 不得自行决定 |
| --- | --- | --- |
| C++ | Revision 2 invariants、12 Schema、31 fixtures、6 errors | Unicode、状态/时间、排序、occurrence、HMAC cursor、FTS/Storage |
| Kotlin/JNI | 3 public methods、唯一 native call、AtomicFile history CAS、错误 metadata | Kotlin 匹配/排序、虚假 JNI history、SharedPreferences/备份 XML替代方案 |
| Flutter | query_generation、typed items、history revision/触发时机、filter 三态 | Dart 聚合三类、重算 lifecycle/relevance/occurrence |

下游若发现 Contract 与实际 canonical 数据无法同时满足，必须以字段/fixture/实现证据回报总工程师；不得增加临时字段或弱化 validator。

## 6. 验证与完成边界

- Search 专项：`python contracts/run_search_v1_validation.py`；
- 共享回归：Calendar、Habit、Anniversary 及仓库既有 Contract 验证入口；
- JSON/YAML 解析、全量 `$ref` closure、NativeResult success/failure、public/internal capability map、旧 `event.search` additive compatibility 均由专项 validator 覆盖。

2026-09-02 Revision 2 amendment 与发布校准证据：Search validator 在发布前通过 `planned+blocked` 基线；四层实现、主机和 Android 13 设备门禁随后完成。产品负责人接受 `OPEN-SEA-001` 两项发布后债务后，validator、3 个公开方法、1 个 native call、11 个 Search Query/History Schema 和 invariants 统一为 `integrated+active`；仅未实现的 `search_index_response.schema.json` 继续 `planned`，FTS deferred。Calendar、Habit、Anniversary 回归继续作为共享门禁。

本计划与下层交付均已完成并通过发布校准；统一 Search Query 与本地 History 可作为正式能力依赖。`OPEN-SEA-001` 必须继续如实跟踪，SearchIndex/FTS 不得因 Search V1 激活而被视为已实现。
