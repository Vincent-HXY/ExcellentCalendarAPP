## Search Query 与 SearchIndex

### Search Query：三类只读组合查询

Search Query 是 Event、Habit、Anniversary 与当前 Category 的只读组合投影，不是领域实体，也不是可写事实源。V1 直接从 canonical SQLite Store 在一次 read transaction 中生成分组结果；匹配、状态、业务时间、occurrence 选择、排序、精确计数和 cursor 都由 C++ Search Query Service 单点负责。

跨层投影必须保持以下边界：

- 一个逻辑对象在自己的 section 中最多出现一次；
- Event 精确时间使用 `occur_at`，全天 Event、Habit 与 Anniversary 的当地日期使用 `occur_date`，二者不得互相伪装；
- 重复 Event 的导航身份由 `event_id + recurrence_revision + occurrence_key + occur_at/occur_date` 组成；
- 有日期范围时，Event 先完成下述固定 eligibility pipeline，再选距请求 timezone 当地 today 最近的 occurrence；open 不优先于更近的 closed。等距使用当前/未来、当地开始、revision、occurrence key 稳定决胜；
- Event 状态投影逐字段复用 Calendar Contract。timed 以固定 query clock 和 `[start,end)` 得到 pending/in_progress/overdue，all-day 以请求 timezone 当地日期和 `[start_date,end_date)`；reopen 后重新动态投影；
- completed recurring Event 的实例存在性逐字段复用 Calendar Contract 的 `completed_recurring_series_cutoff`：timed 以 `occurrence_start_at`、all-day 以 recurrence timezone 当地日初为 anchor，只有 anchor 严格早于 `completed_at` 才存在；等于或晚于 cutoff 的实例不能被显式 completed/skipped state 恢复。cutoff 前开始的跨时或多日实例保留完整原区间；无日期范围时选择 cutoff 前最后一个 eligible occurrence，若不存在则不返回该 Event；
- Event eligibility 的固定顺序为 series/occurrence cancelled → completed-series cutoff → date overlap → `include_completed` → occurrence selection；精确 total、排序和 cursor 只消费该序列产生的最终逻辑对象；
- timed filter 将请求的当地日期边界按请求 timezone/TZDB 解析为 instant（gap 取后一个有效 instant，fold 取较早 instant）并按半开 overlap；all-day 直接按 civil-date 半开 overlap，覆盖跨午夜与多日；
- Anniversary occurrence 复用 `contracts/identity.yaml` 的稳定 UUIDv5 identity；
- Category 结构化筛选使用目标对象保存的 `category_id`，名称匹配与展示只使用当前活动 Category；缺失或软删除 Category 时投影为 null，旧名称不再命中；
- 搜索结果、snippet、相关度和 snapshot/cursor 都是可丢弃派生数据，不写回 Event、Habit、Anniversary 或 Category；
- V1 不创建 SearchIndex/FTS 表、trigger、writer 或 Storage migration。只有代表性设备性能门禁失败后，才能另立迁移计划。
- V1 每页固定 20。单响应 Schema 只约束本消息形状；requested section、累计 total、无重漏、cursor 前进及 timezone/evaluated_at/snapshot 恒定由 request-response/cursor-chain semantic validator 与运行时共同保证。
- `srchcur1.*`/`srchsnap1.*` 由 C++ native runtime 的每进程 OS-CSPRNG key 以 HMAC-SHA-256 认证；Dart/Kotlin 视 payload 为完全 opaque，进程重建后旧 cursor 失效。
- 搜索历史是 Kotlin `noBackupFilesDir` 中的 AtomicFile 私有状态，不属于 Search Query、SearchIndex 或 Calendar Core SQLite；只有 durable write 成功才提升 revision/发布新快照。

Search Query 的完整机器语义位于 `contracts/search/search_query_invariants.yaml`，跨层形状位于同目录的 query、section、三类 item 与 history Schema。

发布状态：统一 Search Query 与设备本地 History 已于 2026-09-02 完成四层生产接线、主机和 Android 13 设备验证，并在产品负责人接受 `OPEN-SEA-001` 两项发布后债务后切换为 `integrated + active`。该发布校准不改变任何 wire shape、Search Revision、SQLite 格式或历史文件格式；下述 SearchIndex/FTS 仍为 `planned/deferred`，不属于已发布能力。

### SearchIndex：可选的可重建加速索引

SearchIndex 只表示未来可能启用的可重建搜索加速投影。它不证明生产 writer、rebuild、失效、FTS tokenizer 或 migration 已存在，也不能直接充当统一 Search Query response。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 索引记录 ID |
| `targetType` | `string` | 是 | 被索引对象类型 |
| `targetId` | `string` | 是 | 被索引对象 ID |
| `titleText` | `string` | 否 | 标题索引文本 |
| `bodyText` | `string` | 否 | 正文索引文本 |
| `keywords` | `string[]` | 否 | 关键词 |
| `categoryId` | `string` | 否 | 从目标对象派生的稳定分类 ID，用于结构化分类过滤 |
| `categoryName` | `string` | 否 | 可重建的分类名称冗余文本，只用于展示或全文检索 |
| `occurAt` | `datetime` | 否 | 精确发生时间；不得承载 date-only 值 |
| `occurDate` | `date` | 否 | 用户当地发生日期；不得转换为 UTC 午夜 |
| `updatedAt` | `datetime` | 是 | 索引更新时间 |

`categoryId/categoryName` 都是索引投影而非新的关系真相源。Category 更名、软删除或索引损坏时，
SearchIndex 必须从目标对象的 `categoryId` 与当前 Category 记录重建；分类筛选不能依赖旧名称。

`occurAt` 与 `occurDate` 最多一个非空。未来启用持久化索引前，必须先冻结 canonical 数据与索引的同事务增量维护或可靠全量 rebuild、Category 更名/软删除失效、版本不匹配恢复、中文连续子串等价 tokenizer、Storage migration 与回滚；索引始终不得成为第二套业务事实。

