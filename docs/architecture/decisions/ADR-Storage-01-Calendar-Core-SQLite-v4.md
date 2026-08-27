# ADR-Storage-01: Calendar Core 使用 SQLite v4

Status: Accepted
Date: 2026-08-27

## Context

Calendar Core JSON v3 已能严格保存 Event、Recurrence、Occurrence、Anniversary、Reminder、Notification、RecoveryBatch 与 Category，但跨 Store 写入需要目录锁、generation、冻结 after-image 和可恢复 journal 共同模拟事务。当前任务要求把正式存储升级为 SQLite，同时保证所有 JSON 已支持字段、软删除、顺序、幂等、恢复和跨实体工作流都不丢失，并安全处理合并或中断迁移形成的目录。

## Decision

- 正式 writer 升级为 Calendar Core SQLite Storage v4，数据库固定为既有应用私有目录中的 `calendar_core.sqlite3`。目录名暂时保留 `calendar_core_storage_json`，用于原地发现旧数据，不代表 JSON 仍是主存储。
- C++ Application 继续只依赖现有窄 Repository/Transaction ports；Flutter、Kotlin、JNI、Domain 与 Application 不接触 `sqlite3` handle，也不引入暴露全部实体的大型可变 transaction。
- SQLite 使用捆绑的 3.53.4 amalgamation、WAL、`synchronous=FULL`、`BEGIN IMMEDIATE`、defensive mode 和进程拥有的单一连接。嵌套 Repository 写入参加外层数据库事务，失败同时回滚实体行和 Store generation。
- 十个现代 Store 与 Category 各使用独立表。每行保存主键、稳定连续位置和一个严格 v3 `payload_json`；冻结 v3 codec 仍是字段完整性与领域映射的唯一 owner，SQLite 另外承担主键、业务唯一性、调度/排序索引、持久性与事务。这样迁移不会因重新手写第二套字段映射而漏掉 nullable、审计或 target-specific 字段。
- JSON v1 的 Event、Reminder、Notification 先恢复冻结 journal，再原样导入三张隔离兼容表；不得把非 UUID 或旧生命周期记录重解释为现代 v3 实体。JSON v2 先执行既有 journal recovery 和 v2→v3 连续迁移；严格 v3 再在单个 SQLite transaction 中完整导入。
- 新数据库先写入 `.migrating`，通过规范化完整 `CREATE` 定义、schema metadata、row identity、完整 codec/关系校验与 `quick_check` 后刷盘关闭。随后持久化 `calendar_core_sqlite_cutover.json`，其中记录真实来源和所有旧 JSON writer 根的精确快照；只有全部已存在根以及缺失时必须创建的 `storage_migrations`、Event、Reminder、Notification 入口屏障已原子改写并复核为 `storage_version=4`，且 journal 已进入 `guards_installed`，才允许原子发布数据库。fresh 初始化仍创建十个空实体诊断根；迁移来源中其他原本缺失的实体或事务文件继续保持缺失，以保留 v1 隔离和 journal 清理语义。Windows 使用 write-through rename，POSIX 在 rename 后同步父目录。混合 v1 与现代 Store/journal 必须显式失败，不能选择性导入。
- cutover journal 是前向恢复状态机：数据库尚未发布时从已验证候选库继续安装屏障；数据库已存在时重新验证 SQLite 与全部屏障后再清理 journal。任一当前 JSON 根既不等于捕获快照也不等于预期 guard，都按可能的并发旧 writer 拒绝发布，禁止猜测真相源。
- SQLite 成为权威后不再把 JSON 当作 live data。旧集合和 journal 内容继续保留用于诊断和显式恢复，但在数据库发布前 envelope 已改为 `storage_version=4` downgrade guard；旧 JSON writer 必须拒绝，禁止双写与自动反向迁移。
- `create_schema()` 只创建结构和 metadata。迁移历史按实际入口分别记录 fresh、v1→v4、v2→v3→v4 或 v3→v4，并只接受这些合法组合。
- 实体行不建立级联外键：`category_id` 是已发布的弱引用，Reminder target 是多态引用，Notification/Recovery 审计可能长于活动目标生命周期。跨表关系继续由严格 aggregate validator 在打开和提交前校验。
- v4 不引入 FTS。现有功能没有 FTS 依赖；全文索引作为后续独立 schema migration 设计。

精确 schema、迁移、约束和测试要求以 `contracts/storage/calendar_core_storage.yaml` 的 `calendar_core_v4` 为准。

## Alternatives

### A. JSON 与 SQLite 长期双写

拒绝。两套 writer 会产生提交顺序、崩溃恢复和版本仲裁问题，无法保证单一真相源。

### B. 首次迁移即把全部字段拆成普通列

拒绝作为本次方案。当前十个 Store 的 target-specific nullable 字段和跨实体不变量较多，立即维护第二套完整字段 codec 会放大漏字段风险。v4 先以严格 payload codec 保证行为等价，并为关键身份和查询建立 SQLite expression indexes；后续可按可测量查询需求做版本化列迁移。

### C. 继续扩展 JSON journal

拒绝。它能维持现状，却不能提供 SQLite 的原生事务、约束和索引，也不满足本次存储升级目标。

## Consequences

Positive:

- 原有 Repository 能力和业务语义保持不变，跨 Store 原子性由真实数据库事务承担。
- v1/v2/v3 都有显式、可重试且不删除源记录的迁移路径。
- 数据库打开会拒绝未知版本、缺失 schema 对象、身份错配和领域损坏，不发布半可信服务。

Negative:

- v4 仍需保留冻结 JSON codec，单次状态写入暂时会重写对应逻辑表，而不是逐字段增量更新。
- 现有应用私有目录名称带有历史 `json` 字样；修改目录需要单独迁移，不能在本次同时重命名。
- FTS、备份 API、长期规模压力和更多 Android 设备迁移仍需后续验证。

## Revisit When

- 某个 Store 的规模或写入频率证明整表 replacement 成为实际瓶颈；
- Search/FTS、账号分区同步或备份需要稳定普通列；
- 需要多进程 writer、跨版本回滚工具或显式 JSON 快照清理策略。
