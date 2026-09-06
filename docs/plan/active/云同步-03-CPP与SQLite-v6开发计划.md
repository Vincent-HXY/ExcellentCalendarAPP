# 云同步-03：C++ Core 与 SQLite v6 开发计划

> 状态：ACTIVE PLAN / CONTRACT FROZEN / IMPLEMENTATION NOT STARTED
> 2026-09-07 Review 修订：提交 `5d8fb0a` 的 11 类问题经独立复核成立，修订依据和跨层交接规则见[Review 复核与兼容修订记录](./云同步-02-Review复核与兼容修订记录.md)。03–06 以机器锁中的最新内容摘要为共同输入；初次交付的旧摘要仅作历史记录。
> 上位统筹：`docs/plan/active/云同步-01-Local-first多设备同步开发计划.md`
> 协议与数据真相源：`docs/plan/active/云同步-02-Contracts与数据模型开发计划.md`
> 实施范围：`cpp_core/**`；本文只制定计划，不执行实现
> 文内语义锚点：第 5–15 节定义 C++/SQLite 设计；第 16–19 节只描述实施顺序、测试证据和交接门禁，冲突时必须回到前述章节及冻结 Contract。

> 协议输入锁：`contracts/sync/sync_v1_revision_lock.json` 中的 `03_cpp_sqlite` 与其他三端锁定同一 revision/hash/fixture manifest。只在 `contracts/run_sync_v1_validation.py` 默认入口通过后按该机器版本实施；本层生产 implementation/release status 仍为 planned。

## 1. 计划结论

本计划负责把账号 workspace 的 Local-first 语义真正落到 C++ Core 和 SQLite：本地业务事实仍是客户端真相源；账号空间的本地业务写与 Sync Outbox 同事务提交；远端下载、冲突、回执和 Cursor 同事务应用；游客空间使用同一业务 Schema 但永不产生可上传 Outbox。

该工作不是在旧 `sync.apply` 占位上补代码，而是依照 Contracts-02 建立新的 typed workspace/sync boundary。完成本分计划只可标记为 `Layer Complete / Awaiting Integration`；只有 Kotlin/JNI、Backend、Flutter、真实加密库和双设备验收全部通过后，统筹计划才可标记云同步完成。

## 2. 权威顺序与变更规则

唯一裁决顺序来自云同步-01 §1.1：判断当前行为时按active machine Contract/Schema → 当前领域不变量 → Accepted ADR → active计划 → 架构 → 实现；本次目标若要改变前三者，先修订ADR/领域/Contract及迁移。Contracts-02冻结前，本文只能盘点、设计和spike，不能把planned Schema当实现真相；冻结后，其机器Contract/SQLite v6 DDL/hash/fixture是C++直接真相源，本计划只决定`cpp_core/**`内部拆分和测试顺序。任何冲突都停止受影响实现并同步回流01–06；不得自行兼容字段别名、宽松JSON或隐式默认值。

## 3. 当前基线与差距

| 领域 | 当前事实 | V1 缺口 | 处理原则 |
| --- | --- | --- | --- |
| Runtime | `src/boundary/api/native_runtime.cpp` 使用进程全局 `RuntimeState g_state`，重新初始化会清空旧状态 | 无法同时承载“账号前台 + 游客提醒” | 改为按 opaque runtime identity 管理的多实例 registry；全局只可保留线程安全 registry，不可保留全局业务状态 |
| Writer lease | 已有 `RuntimeStorageLease`，可撤销旧 writer | 只能辅助单例切换，不能证明多 workspace 路由正确 | lease 下沉到每个 `WorkspaceRuntime`；close/switch 必须使迟到调用稳定失败 |
| Storage | 当前为严格 SQLite v5、固定数据库名、vendored SQLite 3.53.4、WAL/defensive/checker | 无 workspace metadata、Outbox、Cursor、Conflict、Import、profile cache，也无 SQLCipher | 冻结 v5 hash；新增 fresh-v6 与 v5→v6 相邻迁移；加密依赖先过 ADR/spike |
| 事务 | Repository/Transaction 有业务 transaction/operation id | 没有可信 `WriteOrigin`、client sequence、entity state 与 Outbox | 在 Application/Transaction 内引入不可由 wire 伪造的写入来源和同步提交计划 |
| Sync | C++ 没有生产 `sync.apply`、SyncOperation 或 SyncResult 实现 | 所有同步能力待建 | 旧占位保持 blocked；实现 Contracts-02 §8.3 的新调用 |
| Reminder | Event Reminder 仍混有部分用户意图和设备执行状态；Habit/Anniversary 使用模板 | 直接同步整行会上传 Android 本地状态 | 先由 Contract 冻结 target-specific `reminder_intent`；仅序列化用户意图 |
| Storage version Contract | C++/Kotlin 已要求 v5，部分 initialize response Schema/fixture 仍残留 v4 | v6 开发可能掩盖既有漂移 | Contracts 阶段先把现状校准到 v5，再冻结 v6 |
| Entity writers | Event、Recurrence、Occurrence、Anniversary、Habit、CheckIn、Category 各有既有 workflow/repository | 若只改部分 writer 会漏 Outbox | 建立 writer inventory，并逐入口证明账号本地写“事实 + Outbox”同事务 |

## 4. 开发前门禁

### 4.1 必须已冻结

- [ ] Contracts-02 达到 `CONTRACT FROZEN`，包含 Native request/response、所有 target typed payload、错误码、field registry、hash fixture 和 SQLite v6 精确 DDL。
- [ ] Workspace Lifecycle ADR 已接受，明确游客提醒与当前账号 runtime 可同时存活、切换/退出/撤销次序和迟到调用失效。
- [ ] Category Sync Lifecycle ADR 已接受；未接受时不实现 Category update/delete/reorder 或其 Outbox。
- [ ] Account SQLite Encryption ADR 与 SQLCipher spike 已通过许可证、三 ABI、WAL、defensive、强杀、密钥丢失和 20,000 条性能门禁。
- [ ] 所有同步实体 stable ID 与引用图完成审计。
- [ ] SQLite v5 schema hash、既有 migration 和 initialize v5 Contract 已校准并锁定。
- [ ] Reminder intent 每个 target 的字段 owner 已冻结，明确哪些字段属于本机调度事实。

### 4.2 阻塞行为

- 加密 spike 未通过：允许在测试专用临时库开发非加密同步算法，但账号 workspace 的生产 open、30 天保留缓存与发布集成保持 blocked；不得以 Android 私有目录代替加密。
- Category ADR 未通过：其他 target 可继续，Category sync capability 保持 blocked；不得制造临时软删除语义。
- typed payload 或 DDL 未冻结：只允许做 writer inventory、接口 fake 和 characterization test，不写生产 codec/SQL。

## 5. 目标内部架构

建议在现有分层中增加窄模块，不建立第二套 Core：

```text
boundary/api
  ├─ runtime_workspace_api
  ├─ sync_batch_api
  ├─ sync_conflict_api
  ├─ workspace_import_api
  └─ preferences/profile_cache_api
        ↓ typed boundary DTO + exact Contract validation
application
  ├─ WorkspaceRuntimeService
  ├─ LocalMutationCoordinator
  ├─ SyncUploadService
  ├─ SyncDownloadApplyService
  ├─ SyncBootstrapService
  ├─ SyncConflictService
  ├─ SyncStatusAndDiagnosticsService
  ├─ SyncLocalMaintenanceService
  ├─ WorkspaceImportService
  └─ WorkspacePreferenceService
        ↓ trusted WriteOrigin + transaction plan
domain
  ├─ existing Event/Recurrence/Anniversary/Habit/Category rules
  └─ sync identity/state value objects only
        ↓ narrow repositories
storage/sqlite
  ├─ existing business repositories
  ├─ SyncState/Outbox/Receipt/EntityState/Conflict repositories
  ├─ Import/Bootstrap/ProfileCache repositories
  └─ v5 checker + v5→v6/fresh-v6 schema
```

约束：

- Boundary 只做 JSON/类型/错误映射，不承担合并、重放、导入或领域校验。
- 同步不复制 Event、Recurrence、Habit、Anniversary、Category 的领域规则；远端 apply 必须调用所属 Application/Domain 能力或等价的受校验事务入口。
- Sync repository 不得成为万能业务 Repository；业务表仍由既有窄 repository 管理。
- 不新增与 SQLite 并行的生产 JSON 同步存储。

## 6. 多 Workspace Runtime

### 6.1 实例模型

引入进程级、线程安全的 `WorkspaceRuntimeRegistry`，其唯一全局职责是为Kotlin已分配并传入的`workspace_id`生成不可复用的进程态`runtime_instance_id`，再由该id找到独立`WorkspaceRuntime`。C++不得分配或重写workspace id；legacy v5 guest也只接纳Kotlin迁移journal给出的稳定id并在v6 metadata原子持久化。每个实例包含：

- 不可变 `workspace_id/workspace_kind/account_binding/storage_version`，以及账号runtime本次打开时绑定的`device_id/session_generation/sync_transport_generation`。
- 自己的数据库连接、repository/service graph、writer lease 和串行写队列。
- 运行状态 `opening/open/closing/closed/failed` 与单调 runtime generation。
- 账号空间仅在 open 期间持有的解密材料；密钥不进入日志、JSON、异常或持久化 DTO。
- 每实例的同步状态发布器；任何事件都携带 workspace 和 runtime identity。

不得把 C++ 对象地址直接作为 wire handle。Contract 冻结 UUID string 或安全整数 + generation 后，全链只使用该表示。

### 6.2 open

`runtime.open_workspace` 的顺序：

1. 严格解析 workspace metadata；拒绝未知字段、非法 kind 和不匹配 account binding。仅 fresh account DB 允许接收 Backend `device.register`/`sync.device_fence` 返回的`sync_transport_generation + highest_client_sequence/next_client_sequence/client_confirmed_through/client_sequence_exhausted` recovery bundle、nullable required fence receipt与Kotlin按Contract生成的policy seed，并校验confirmed≤highest、未耗尽时next=highest+1、耗尽时highest=JSON上限且next=null。凡Broker生命周期标记`transport_fence_required`，缺少同device/session且old→new generation匹配的receipt必须拒绝open/bootstrap writer；existing DB 收到register seed时只能做单调一致性校验，fence则必须经`sync.accept_transport_fence`原子推进，绝不覆盖本机未确认Outbox、确认水位或分配器。clear-rebuild另带`clear_operation_id/workspace_id/device_id/session_generation/sync_enabled_seed/sync_policy_revision_seed`，必须全部与当前open上下文匹配。
2. 账号空间从 JNI 二进制参数接收 32-byte key；游客空间必须无 key。key 不得 Base64 塞入 JSON。
3. 检查路径由 Kotlin 已解析且属于 registry 允许的精确 workspace；C++ 不接受任意用户路径。
4. 打开数据库并判别 fresh/v5/v6/unsupported/corrupted。
5. fresh 创建 v6；fresh account 以register/fence seed初始化transport与设备序列并标记`bootstrap_required=true`，在bootstrap finalize及旧import-fence恢复前保持业务不可写。真正首次/新device或已完成destroy后的未来重登只接受Contract genesis `sync_enabled=true, sync_policy_revision=0`；active clear-rebuild只接受operation-bound旧值/revision seed并落一次性consumed receipt。二者都绝不从Backend诊断镜像推断owner，也不接管Kotlin-owned reminder/settings字段；v5执行冻结的相邻迁移；大于v6 fail closed。
6. 运行加密 profile、schema shape、`quick_check`、metadata/account binding 和历史记录校验。
7. 构造完整 service graph 后一次性发布 open 实例；此前不得对外可见。

重复 open 相同 workspace 和相同预期 revision 返回既有实例或稳定 already-open 结果；参数不同不得悄悄替换。

clear lifecycle seed 由Kotlin在账号DB外持久化到operation-bound受保护记录。C++重复收到同一operation必须返回同一consumed结果，不得二次覆盖；Kotlin只有看到匹配receipt且Registry字段也恢复后才删seed。毁库/open/bootstrap任一点强杀都继续同一operation，不能回落到genesis同步开关。`retain_30d`直接重开原库并保留policy；logout destroy/到期后的未来重登是已声明的新genesis，不能误套clear seed。

### 6.3 close

`runtime.close_workspace` 必须：

1. 原子标记 closing，拒绝新业务写和新 sync batch。
2. 撤销 writer lease，并使旧 runtime identity 的迟到调用返回 `WORKSPACE_SWITCH_CONFLICT` 或冻结后的稳定错误。
3. 等待已进入临界区的短事务完成；不得持 registry 锁等待 I/O。
4. checkpoint/关闭连接、销毁 service graph、清零可控明文 key buffer。
5. 标记 closed 并从 registry 移除；重复 close 幂等。

close 失败不能自动回退或打开游客库。Kotlin 决定 UI active runtime 与 guest reminder runtime 的生命周期，C++ 只执行显式命令。

### 6.4 并发模型

- 同一 workspace 所有写事务串行化；读可并行但必须取得有效实例 lease。
- 不同 workspace 可并行读写，各自连接与锁独立。
- prepare/ack/apply/bootstrap/import/本地编辑在同一 workspace 共享写队列，避免 Cursor 与 Outbox 竞态。
- 每个边界响应回显 `workspace_id/runtime_instance_id`；Kotlin 必须核对。

## 7. 本地写入与 Outbox 原子性

### 7.1 可信写入来源

在 C++ 内部引入不可从 JSON 直接构造的 `WriteOrigin`：

| Origin | 业务事实 | Outbox | 典型入口 |
| --- | --- | --- | --- |
| `LocalUser` | 写 | 账号写；游客禁写 | Flutter 发起的 create/update/delete/complete |
| `GuestLocal` | 写 | 永不写 | 游客 workspace 的本机操作 |
| `Import` | 只写隔离 import staging；下载publish group或验证bootstrap marker后才原子发布live事实 | 仅begin/items/commit进入Outbox；abandon与source-cleanup confirmation均走独立HTTP | 游客数据迁入账号 |
| `ConflictResolution` | 只写本地冲突草稿/resolution intent，不改live fact或unresolved计数；服务端effect/delta由RemoteApply发布 | 账号写，使用专用 route | 冲突解决 |
| `RemoteApply` | 写 | 明确抑制 | exchange/bootstrap 下载 |
| `DeviceLocalEffect` | 仅本机表或不入 Core | 禁止 | Notification/Alarm/调度结果 |
| `ServerSnapshot` | 只写安全 profile cache | 禁止 | account_profile change 或资料 API 成功响应 |

wire 中的 `source=sync` 不能选择 `RemoteApply`；只有 Sync Application Service 的内部 capability 可创建该 origin。

### 7.2 Writer inventory

在编码前列出所有会改变 V1 同步闭包的生产入口，至少覆盖：

- Category create/update/delete/restore/reorder。
- Event create/update/delete/restore、状态/完成时间、分类/重要性/地点、普通 reminder intent。
- Event recurrence revision、当前整系列`event.update`，以及既有occurrence cancel/complete/reopen；三作用域编辑属于R3，不进入本计划writer inventory。
- Anniversary create/update/delete/restore、专属 yearly recurrence、reminder intent。
- Habit create/update/end/reopen/delete/restore、专属 recurrence、reminder intent。
- HabitCheckIn increment/decrement/replace/clear 及 action workflow。
- portable preferences update。
- conflict resolution 与首次/后继 import（两者使用各自专用事务模型，不并入普通writer模板）。

普通local-user入口都要有一条“账号live事实 + generation/history + Outbox 同事务”测试和一条“游客事实成功 + Outbox为零”测试。Import另测“guest lease + 账号隔离staging/manifest/Outbox原子、publish-applied前live事实为零、发布后原子可见”；conflict resolution另测“本地resolution intent + Outbox原子、服务端effect/delta apply前事实与unresolved计数不提前改变”。不得依赖事务提交后的observer、定时扫描或diff猜测来补Outbox。

### 7.3 Transaction plan

Application workflow 在进入 SQLite 前构造 typed `LocalMutationPlan`：

- target/operation/entity identity。
- base entity version 与受影响 merge keys。
- 每个受影响merge key最近的同设备前驱client sequence（无则null）。
- Contract typed payload；只含真实变化字段。
- 对可能与delete竞争的update/增量，另冻结同writer事务、按registry裁剪的完整`conflict_recovery_snapshot`；它参与canonical hash但不混入普通patch。
- 稳定 mutation/operation/import identity。
- 需要更新的业务事实和引用图。

SQLite transaction 按同一提交执行：

1. 校验 workspace kind、writer lease 与 expected local revision。
2. 对update/delete/restore按entity检查unresolved conflict与`awaiting_change_group`门禁；分别返回`SYNC_ENTITY_CONFLICT_BLOCKED`或`SYNC_ENTITY_SYNC_EFFECT_PENDING`且零写。随后执行业务 invariant 和引用完整性校验。
3. 写业务事实/history/generation。
4. 账号空间分配严格连续 `client_sequence`，canonicalize payload，写 hash 和 Outbox。
5. 更新本机 entity pending state与仅供native幂等观察的`native_state_revision`；对外`status_revision`由Kotlin聚合器拥有。
6. commit 后才发布状态事件和 reminder affected ids。

任何一步失败都回滚事实与 Outbox；不得出现“数据已保存但没有 Outbox”或“Outbox 指向不存在事实”。

### 7.4 Event recurrence 的 R2-C 边界

- 沿用当前领域：`event.update`对重复Event始终修改整个系列，并以`expectedRecurrenceRevision`做CAS；已有occurrence cancel/complete/reopen保持typed事务。
- 同步保存/上传系列revision、既有exception与occurrence state，Backend不展开occurrence；旧revision竞争按冻结field/causal规则合并或形成typed conflict。
- `update_occurrence/split_future/update_series`与对应三作用域UI属于R3；本计划不得新增Boundary DTO、Native writer、表或兼容scope字段。

## 8. SQLite v6

### 8.1 Schema 所有权

精确表、列、索引、CHECK、FK、触发器和 migration checksum 全部来自 Contracts-02 机器文件。本计划实现至少包括：

- `workspace_metadata`、`workspace_preferences`、`account_profile_cache`。
- `sync_state`（含sync transport generation、local receipt-ack/server-accepted/dirty、cursor/cleanup、next/last-claimed notice与policy水位，以及nullable transport-terminal code/evidence hash/session-device binding）、`sync_outbox`（含per-key causal predecessors与nullable recovery snapshot）、`sync_failed_local_changes`（typed失败意图/候选/草稿/revision/supersede状态）、`sync_entity_state`（含device-local awaiting-server-adjudication keys）、`sync_deleted_entity_anchors`（delete version/sequence、nullable immutable import lineage/source workspace/epoch provenance）、`sync_change_receipts`、`sync_local_device_causal_anchors`、`sync_awaiting_change_groups`、`sync_policy_operation_receipts`。
- `sync_conflicts`（含entity门禁、auto-merged投影与tombstone pin）、`sync_conflict_notice_queue/journal`（含active-window引用）、`habit_check_in_operations`。
- `sync_import_batches/items/staging_*`（含source epoch、begin/derived-terminal sequence、total canonical bytes、takeover/range-close proof、reconciliation/resume/abandon状态与compact range identity）、账号销毁前永久保留并可由bootstrap provenance重建的同epoch `sync_import_mappings`、`sync_import_publish_staging_*`、`guest_import_cleanup_receipts`、guest current source epoch/previous-epoch gate、跨账号生命周期保留且不含账号明文的`guest_import_source_leases`、live图退休后的`guest_import_audit_anchors`逻辑表，以及`sync_bootstrap_staging_*`。
- 既有 20 个业务表、索引、payload bytes、position、generation 和 history。

不得用一个宽松 JSON 表替代 typed facts。JSON 列只能保存经 field registry 验证且带 payload version/hash 的快照。

### 8.2 v5→v6

迁移步骤：

1. 在任何写入前运行冻结的完整 v5 checker，拒绝“表名相同但定义错误”的输入。
2. `BEGIN IMMEDIATE`，创建 v6 新对象、写 workspace metadata 和 migration history。
3. 游客现有生产库标记 `workspace_kind=local`、`account_id=null`，不生成历史 Outbox。
4. 初始化 sync tables 为空；不得把既有游客事实误标为账号 pending upload。
5. 设置 `user_version=6`，运行 v6 shape/FK/quick check 后提交。
6. 任一步失败回滚并保持可再次识别的 v5；不得发布半迁移。

还必须覆盖 fresh-v6、重复启动、v6 正常重开、v7/downgrade fail closed、磁盘满、WAL 恢复、损坏和未知 metadata。

### 8.3 加密集成

- 游客 v6 延续明文数据库；账号 v6 必须使用获批的加密 provider。
- build 中只能有一个提供 SQLite ABI 的实现，必须排除普通 sqlite3 与 SQLCipher 重复符号。
- account DB、WAL、SHM 和临时页必须在静态/动态检查中证明不可读取明文业务字段。
- key 只活在 Kotlin Keystore 解包结果、JNI direct bytes 和 C++ 受控 buffer；打开完成后按 provider 要求清理输入副本。
- key 不可用、错误 key、账号绑定错、加密 header 错全部 fail closed，不创建新空库覆盖旧文件。

## 9. Outbox、序列与上传批次

### 9.1 序列分配

- `client_sequence` 作用域为注册 `device_id`，首次设备从 1 连续递增，必须在写 Outbox 的同一事务分配；如果同一 active device 的账号缓存曾被立即/到期删除，fresh DB 必须先消费服务端transport fence receipt，再从其认证的 nullable next/exhausted分支续号，不能回到 1。transport generation仅隔离HTTP生命周期，不进入mutation hash、也不允许回绕任何已被Backend接受的sequence。
- 当前next为JSON safe-integer上限时允许原子分配最后一个sequence并把allocator置exhausted；其后任何需要Outbox的writer返回`SYNC_CLIENT_SEQUENCE_EXHAUSTED`且零事实/零Outbox，workspace进入blocked诊断。V1不自行换device id、不回绕、不以本地事实无Outbox降级；fresh exhausted DB仍可bootstrap只读。
- 账号 workspace 进入可写 active 状态前必须已有持久化且与当前 session 绑定的 `device_id`：新登录按“adopt 校验 → device.register → open account workspace”执行；既有账号离线启动复用已绑定 device。fresh account DB 还必须完成 bootstrap 才解除写锁。未注册不得打开可写账号 runtime，也不得发明临时 device id 或 pending-unassigned 序列；被撤销 device 的序列空间永久封存，新登录只接受 Backend 新签发的 device id。
- `mutation_id` 一次逻辑写固定；Habit operation 另有稳定 `operation_id`。

`sync.accept_transport_fence`仅接收Kotlin严格解析且签名/identity完整的Backend fence receipt。existing runtime在同一写事务验证workspace/device/session、expected=current generation、resulting=current+1、sequence bundle不倒退及operation幂等，随后推进generation、使全部旧generation prepared transport handle/迟到ack/apply失效，并落resolved import-fence状态；它不修改mutation payload/hash。若receipt含`never_visible_after_transport_fence`，只允许旧runtime已被冻结且将被销毁，或fresh DB启动恢复消费；不得用它在仍含旧generation普通Outbox的保留库中删除/重排序列。fresh runtime在open seed中执行等价校验。错binding、跳generation、MAX溢出或同operation异receipt均零写并保持writer blocked。

### 9.2 payload 与 hash

- payload 必须按 target + operation 的 oneOf codec 生成；禁止通用 Map 外泄到 Application/Domain。
- hash 严格使用 Contracts-02 的 RFC 8785 + SHA-256 envelope golden fixture。
- `created_at`、尝试次数、next retry 等诊断字段不进入跨端 hash。
- base version 与 merge keys 必须来自本机 `sync_entity_state`，不能从 UI 参数信任；每个key的causal predecessor取“最近成功应用的本机causal anchor”或其后的pending链尾并进入canonical hash。后者后来若成为terminal rejected/conflict，只能由Backend冻结的`no_effect + effective prior version`证明让已冻结后继越过，绝不成为成功anchor；staged不能成为前驱。ack清理普通receipt后成功anchor仍保留。

### 9.3 prepare

`sync.prepare_upload_batch`：

1. 校验account workspace、device/session/`sync_transport_generation` binding与blocked state。`run_intent=normal`要求sync enabled且不存在pull-before-push gate；`logout_final`只接受Kotlin Broker绑定session账号与当前transport generation的一次性内部capability，即使前台route为local或账号paused也仅放行一轮且不改开关；`receipt_ack_flush`只在local ack大于server-accepted时接受；`reenable_pull_only`只在false→true策略事务留下durable gate时接受。四者均不能由Flutter伪造。ack-only即使普通cursor已过期也可构造，但仍携current transport generation。
2. 若已有 prepared batch，重复调用返回相同 `batch_id`、items、route 和 hash。
3. `run_intent=normal/logout_final`从最小sequence开始取连续prefix，最多100项且不超过Contract bytes上限；每项携带按merge key排序的前驱sequence，链断裂/指向未来/其他target立即blocked。`reenable_pull_only`强制uploads空但携current opaque cursor/download limit/ack；`receipt_ack_flush`强制uploads空/download-limit 0/null cursor/ack非空。
4. conflict-resolution route 必须为单项；普通 exchange 不跨 route 混批。
5. 在事务中冻结 prepared membership；不得因重试或新写入改变已有 batch。
6. 返回完整`PreparedExchangeRequest` strict union，不返回数据库内部路径/rowid：`normal/logout_final/reenable_pull_only`都映射wire normal并由C++给出protocol/device/transport/current cursor/download limit/ack、stable batch/route及uploads；`receipt_ack_flush`映射wire ack-only并给出全部固定空/null字段。Kotlin只附Bearer逐字传HTTP，不能保存或拼装cursor/ack。

同一device任一时刻最多一个未ack prepared batch；该batch未exact acknowledge前，不得准备/发送更高sequence的新batch。prepare结果同时带C++已持久化的 `acknowledged_client_sequence_through`，Kotlin原样放入exchange；这既阻止响应丢失后越过receipt，也让Backend拥有可证明的清理水位。

### 9.4 acknowledge

`sync.acknowledge_upload`先按strict mode分支：

- `mode=ack_only`要求prepared identity、reported ack、response transport与accepted ack精确存在，batch/results/changes/cursor/cleanup/account-generation字段全部空/null；校验`accepted==reported`、不倒退且不超过当前local ack后，只在单事务推进`server_accepted_client_sequence_through`并重新派生dirty。即使HTTP在途时local ack继续前进也只保持dirty，不失败、不越过reported；绝不调用`apply_download_batch`或改任何cursor/cleanup/business事实。
- `mode=normal`才执行下列逐项ack：

- 必须先核对response transport generation与workspace/runtime/session/device binding仍等于prepared handle，再核对batch、mutation、sequence、hash、逐项数量和顺序完全一致；fence后迟到的旧response整体零写。
- accepted/partially_merged/conflict/rejected只终结Outbox并保存exact terminal receipt、effect group引用与per-key applied/resulting version；terminal rejected/conflict还须原样保存Contract返回的per-key `causal_disposition=no_effect`及effective prior sequence/version，供已经冻结且引用它的后继验证，但只有实际成功应用的key推进`sync_local_device_causal_anchors`。导入begin/item的`staged`只更新隔离import receipt/staging状态。ack不得写服务端entity version、可见conflict或notice。`status=duplicate`必须验证`original_status=accepted/partially_merged/conflict/rejected/staged`、原terminal result/effect group/receipt identity、sequence、mutation id与payload hash，并按原结果补做完全相同的本机ack。
- 对尚未存在于`sync_change_receipts`的effect group，ack原子写`sync_awaiting_change_groups` entity gate；若组已apply则不重建。gate存在时普通writer零写，直到精确group或覆盖它的权威bootstrap发布事务解除。这样上传产生的conflict只由后续group apply进入discovery journal，duplicate不重复提示。
- import commit的`accepted + server_confirmed + publish metadata`或`rejected + repair_required metadata`在终结commit Outbox的同一事务推进batch handle；duplicate重放同一分支。该状态只驱动继续下载/修复，不发布live account事实。
- 合法普通用户mutation或conflict-resolution的领域级rejected已消费sequence：在终结Outbox的同一事务把typed intent、本机候选/manual draft、merge keys、base/per-key前驱、failure code/safe context写入`sync_failed_local_changes`，并以明确“未同步”overlay继续投影；不能修改原payload、复用sequence或自动重传。用户discard只删overlay并从server baseline+pending重投影；用户编辑另存产生全新mutation/sequence/hash，成功effect apply后才清其superseded旧failed记录。Import rejected继续由import状态机处理，不写该表。协议/hash/batch/gap错误整批不消费，按Contract阻塞或冻结该workspace/device。
- 无effect group的terminal结果在exact ack后通常可纳入确认；引用effect group的结果只有该组已apply后才可纳入连续`acknowledged_client_sequence_through`。但若某terminal sequence仍被任一非终态本机Outbox作为causal predecessor引用，确认水位必须停在它之前，直至后继终结或成功anchor接管，保证Backend不会在长期离线时清掉no-effect链证明。任何推进同时设置`ack_watermark_dirty`，直到后续response回显的`accepted_client_sequence_through`追平；ack→apply之间强杀时水位停在gate前，使Backend继续pin receipt/group；apply事务解除gate后再推进可证明的连续前缀。
- 同一normal exchange即使results为空也先调用`acknowledge_upload(mode=normal)`闭合prepared identity，随后完整normal response调用`apply_download_batch`；两步分别幂等。若中间强杀，重试由Backend返回相同duplicate receipt和同一下载页，C++可安全补完；download facts/conflicts/receipts/cursor只在第二步同一事务。

## 10. 下载批次与远端应用

`sync.apply_download_batch` 在单一 SQLite 事务中完成：

1. 先校验response `sync_transport_generation`等于当前runtime；旧generation响应零业务写且不得更新cursor/ack。再校验account generation/cursor continuity、ordered group sequence/identity/hash，以及`retention_floor_server_sequence/resolved_conflict_cleanup_before`与response account generation绑定且不倒退；水位缺失/异常只禁用maintenance并记录Contract错误，不用本机时间替代。
2. 普通`change_group`必须同时携带完整typed entity changes与conflict deltas，分页不得拆组；通过`sync_change_receipts`整组幂等，相同sequence/group id不同hash立即blocked。对组中全部target先完成引用/版本校验，再在一个事务中应用，禁止出现fact已变而created/resolved delta未落盘。
3. `import_publish_begin/chunk/commit`按group/manifest/ordinal跨页写隔离`sync_import_publish_staging_*`。每个chunk先验证Contract确定性装箱边界/hash及`max_import_publish_chunk_canonical_bytes`，单chunk不得超过exchange hard-cap预算。Backend组首页面以begin起始、组末页面以commit结束，中间页只含chunks；整个区间不得夹普通group。begin/chunk只与page receipt原子推进`import_staging_transport_cursor`，`visible_committed_cursor`停在begin前。只有commit证明全区间、全ordinal与digest完整时，才先把canonical整图/冲突设为server baseline、重放全部受影响pending overlay，再在本事务记录`publish_applied`、把visible cursor跃迁到组尾并清staging；缺失返回`IMPORT_PUBLISH_INCOMPLETE`且不越过commit。
4. 对普通group先更新server baseline/entity state，再找出全部受影响的unconfirmed本机mutation与仍适用的`failed_local_changes`，按field registry/per-key因果链与本地sequence顺序重放为可见overlay。pending值标“待上传”，failed值标“未同步且需处理”，二者不可混计；安全的不同组继续显示本机值。同组、delete-vs-edit或链断裂在Backend尚未裁决时只写device-local `awaiting_server_adjudication`，继续显示并上传本机pending overlay，不增加unresolved/notice、不生成provisional conflict id、也不阻断既有Outbox。只有下载到Backend生成的`conflict_delta.created`才建立/更新权威conflict与entity gate；绝不让远端echo覆盖HTTP在途后的编辑，也不改任何已发送mutation/sequence/hash。
5. `conflict_delta.created`按id/version upsert完整unresolved候选、`conflicting_groups`与immutable `auto_merged_groups`；迟到/重复不得倒退。`resolved`按id/version终结本地记录、清未解决计数并保留30天；本机没有id时只写receipt，resolved后迟到created不得复活。
6. 为本次固定snapshot upper bound维护持久化discovery journal：created只加入窗口开始未知的id，resolved从净集合删除；import publish commit只把其delta并入同一journal，不视为整个窗口terminal。仅当普通下载已达该upper bound且`has_more=false`的terminal page时，才对仍unresolved净集合生成一个immutable notice并清窗口journal；bootstrap只在finalize做同义结算。已排队notice永不改id/改count，后来的B另排新notice；同窗口created→resolved不提示。
7. account_profile只更新安全缓存；user_preferences按服务端接收序列；二者不进业务冲突中心。RemoteApply明确不生成Outbox，也不把HabitCheckIn原始source改成sync。
8. `apply_download_batch`只接受完整wire normal response，必须含prepared identity、transport/account generation、snapshot upper bound、has-more、groups/chunks、raw next cursor、两个server-derived cleanup水位与`accepted_client_sequence_through`；原子写group/chunk receipt、baseline+overlay、冲突/notice journal、entity/field version、last server sequence、visible或staging cursor、cleanup与accepted水位。普通group同时解除精确effect gate并据连续已apply结果推进local upload确认水位；terminal reenable-pull固定上界页原子解除pull-before-push gate，之后normal prepare才可读Outbox。ack-only永不进入本方法。
9. 全部成功后commit，并返回C++权威`next_request_cursor`、affected reminder/entity ids、`sync_policy_revision`与新native state revision；Kotlin据此生成自己的聚合`status_revision`，不得直接使用Backend raw cursor。UI只能在随后exact `sync.claim_conflict_notice`成功时显示一次性提示。

任何group/chunk非法、引用缺失、未知enum/field或领域不变量失败时，整个batch回滚且cursor不推进。C++不“跳过坏项继续同步”。

### 10.1 引用与顺序

- Backend page 可以按依赖顺序发送，但 C++ 仍必须验证引用。
- 同一事务内允许先建立 typed staging map 再按 Category → Recurrence → 主体 → ReminderIntent → Occurrence/CheckIn 应用。
- 不能安全满足引用时返回 `SYNC_APPLY_FAILED` 的稳定 context，不创建残缺实体。
- tombstone 参与同样的 version/merge 规则；旧编辑不得复活已删除对象。

## 11. Cursor 过期与 Bootstrap

### 11.1 staging

Kotlin 必须以当前已持久化的sync transport generation和null bootstrap cursor请求 Backend；只有严格校验首个响应中的`bootstrap_id/sync_transport_generation/account_generation/snapshot_upper_bound_server_sequence/device_highest_client_sequence_at_snapshot/device_client_confirmed_through_at_snapshot/nullable device_next_client_sequence_at_snapshot/device_client_sequence_exhausted_at_snapshot/retention_floor_server_sequence/resolved_conflict_cleanup_before`严格分支及`trigger_reason`后，才把该exact identity交`sync.begin_bootstrap`创建/恢复隔离staging，再把同一响应首页交`apply_bootstrap_page`。已有live facts在完整快照前继续可读；fresh account DB保持不可写/重建中。`apply_bootstrap_page`校验：

- bootstrap id、snapshot generation、page cursor 与 page hash。
- Backend materialized snapshot session 的 account/device/protocol/upper-bound identity；V1 不假定跨 HTTP 长事务。
- page receipt 幂等；重复 page 相同 hash no-op，不同 hash blocked。
- discriminated typed facts/tombstones、无业务payload的deleted entity anchors、全部unresolved conflict snapshots（含conflicting/auto-merged groups）、field versions、requesting-device per-key causal anchors和引用完整性；每种fact/tombstone/deleted-anchor/conflict/marker/causal-anchor单项先验证不超过Contract bootstrap response hard-cap减envelope预算，冲突候选严格验证且不写live store，超限状态不得被静默截断或卡死分页。deleted anchor的nullable immutable source workspace/epoch/lineage/source identity provenance必须进入对应marker digest/count，使服务端tombstone payload清理后fresh库仍能验证同epoch publish证明。服务端未commit的import staging不得出现；已commit整图携带immutable epoch/lineage/source provenance，并有永久compact marker的epoch/lineage/batch/group/commit/manifest/mapping identity及当前snapshot provenance digest/count。
- 固定快照分页期间新服务端写不混入快照。

### 11.2 finalize 与 rebase

`sync.finalize_bootstrap` 必须在单事务：

1. 证明所有page连续、terminal cursor有效、typed facts/全部unresolved conflicts完整，所有页的retention/cleanup水位一致且绑定同generation。
2. 用快照替换账号server-derived事实基线和unresolved conflict store，但保留未确认本地Outbox；已在live存在且仍unresolved的同id幂等。以bootstrap开始时已知conflict集合为基线建立discovery journal，只有finalize时仍unresolved的新id形成一个immutable notice。
3. 校验每个import marker的upper bound、永久identity和provenance digest/count；随后按field registry与per-key causal predecessors依次重放pending mutation和device-local failed overlay作为可见投影，不改已发送identity/hash，也不把failed项变成Outbox。验证成功的批次才写`publish_applied`。
4. 快照中没有fact/tombstone但本机仍有pending update时，保留该意图并标`awaiting_server_adjudication`，不得自造本地conflict id；下次上传携带`conflict_recovery_snapshot`，由Backend deleted anchor返回权威delete-vs-edit conflict。其他pending overlay竞争也遵循同一规则：无论本机是否已有足够业务值，只有服务端`conflict_delta.created`可使其进入unresolved store/计数/notice。
5. facts、conflicts、page receipts、account generation/cursor/entity state、两个cleanup水位、pending/failed overlay、import marker状态与notice queue在同一事务发布；同generation且upper bound覆盖effect末序列的gate可按权威快照解除，其他gate保留。全程还须证明bootstrap session的transport generation等于runtime current；fence后旧页/finalize整体零写。对fresh DB还必须校验session绑定的`device_highest_client_sequence_at_snapshot/client_confirmed_through_at_snapshot`与全部requesting-device causal anchors，随后把本地确认基线提升至highest并恢复anchors；若`highest < JSON安全整数上限`则分配器置`next=highest+1, exhausted=false`，若等于上限则必须置`next=null, exhausted=true`并保持业务writer只读blocked，绝不做溢出加一。existing DB只做单调校验，不越过本地gate/Outbox。清理staging；异常水位则保守保持旧水位。

强杀后根据 receipt 继续；无法证明完整时丢弃 staging 并重启 bootstrap，live facts 保持不变。

`SYNC_BOOTSTRAP_EXPIRED` 或 `SYNC_BOOTSTRAP_GENERATION_CHANGED` 都只销毁对应未发布 staging，再由 Kotlin发起新的 null-cursor HTTP 请求并以其响应 bootstrap id 开始；不得由 C++生成 id，也不得把不同 snapshot session 的页面拼接。24 小时候选 TTL 由 Contracts ADR 最终签署，C++ 不自行延长或解释服务端 token。

## 12. 冲突模型

### 12.1 保存

`sync_conflicts`保存Contract允许的typed server/local candidate、`conflicting_groups`、immutable `auto_merged_groups`、source device、server received order、conflict version和状态；auto-merged项只保留registry裁剪的accepted投影与resulting version，不保存完整mutation。未解决冲突无限期保留并按entity阻断普通update/delete/restore，同时pin其引用tombstone；已解决保留30天。

### 12.2 查询

`sync.conflict.list/detail`：

- 按服务端顺序与稳定 identity 分页，不使用设备 wall clock。
- filter/cursor/snapshot 绑定；opaque cursor 不解析。
- 只返回当前 account workspace；游客调用 not-applicable。
- response 不泄露其他 workspace 或账号缓存。
- detail明确区分“需要选择的冲突组”和“已自动合并组”；离线查询与bootstrap恢复字段完全一致。

### 12.3 解决

`sync.conflict.resolve`：

- 校验 expected conflict version，过期则返回 mismatch，不自动重试用户编辑。
- keep-local、keep-remote、per-field、manual-edit 均映射为 typed resolution。
- manual edit 再经过目标领域校验。
- 单事务更新本地候选/冲突状态并产生具有连续 sequence 的专用 Outbox mutation。
- 服务端 ack 后才进入 resolved terminal；本地提交到 ack 前为 resolving，可重启恢复。
- Native成功结果只返回`queued/resolving + native_state_revision`；Kotlin据此推进聚合status revision。只有对应effect group/更高版本resolved delta被apply后才可移除未解决项；异步version mismatch/rejected恢复最新detail并保留manual-edit草稿，重复点击不创建第二条resolution。

### 12.4 本地保留与有界 maintenance

- 已解决冲突只在合法apply/finalize持久化的 `resolved_conflict_cleanup_before` 已越过其服务端resolved_at时到期；删除整条resolved记录/payload，UI不可再查。缺水位、generation不符或本机时钟前拨/回拨都不清理。
- unresolved conflict引用的tombstone永不由180天maintenance删除；解决后还需同时满足resolved+30天与原tombstone retention floor/cursor安全条件，才可解除pin并分批清理。
- `sync_change_receipts`仅按同generation的已提交cursor与 `retention_floor_server_sequence` 安全交集裁剪；无进行中bootstrap且水位不倒退才可小批删除，不按本机年龄/表大小猜测。
- maintenance 不推进 cursor、不改变业务事实、不生成 Outbox；在 open 后或 Kotlin低频任务触发均返回可重复的水位/删除计数，强杀后从已提交小批继续。
- conflict notice的exact head claim在同一事务推进`last_claimed_conflict_notice_sequence`、移除已claim head并发布后继；旧claim只返回no-longer-actionable。terminal download/bootstrap窗口生成notice或净零后立即删除discovery journal临时set；maintenance只清`sequence <= last_claimed`、非当前head且不被active window引用的旧行，永不按年龄删除未claim notice，水位永久保留。
- 长期离线、generation 切换、bootstrap staging、磁盘满与 maintenance/apply 并发必须证明不误删幂等证据。

## 13. 首次游客数据导入

### 13.1 preview

`workspace.import_preview` 对游客库建立一致性只读快照，返回：

- strict preview oneOf：ready返回不透明token、C++生成的UUIDv4 `proposed_import_batch_id`、按冻结namespace对canonical `account_id + LF + source_workspace_id + LF + decimal(source_epoch)`计算的UUIDv5稳定`import_lineage_id`、source workspace id/epoch/snapshot hash、过期时间；repair另返回predecessor batch。前一epoch compare-and-retire后尚未Native completed/release时只返回`previous_epoch_cleanup_pending`与旧epoch opaque恢复handle，不生成新token/id。Backend必须复算并拒绝不匹配，Flutter/Kotlin不生成identity。
- Category、各 Recurrence、Event、Anniversary、Habit、ReminderIntent、OccurrenceState、HabitCheckIn typed counts。
- 确定性mapping/manifest digest、引用/提醒影响与阻塞warning。映射按`(source_epoch, lineage, source target type/id)`稳定生成，Flutter/Kotlin不得自造id；completed旧epoch映射不可进入新epoch删除闭包。

不得把业务记录送到 Flutter，也不得只按行数猜测可导入性。

preview/commit在分配任何client sequence前按Contract同一静态上限计算typed item count，以及每个ordinal item RFC 8785 canonical payload的UTF-8字节数之和`total_canonical_bytes`；该值进入begin/commit manifest与hash。单批超限返回`SYNC_IMPORT_CAPACITY_EXCEEDED`且零账号staging/Outbox。账号并发总quota只能由Backend裁决；若begin或恶意少报检测返回capacity-rejected，C++按terminal receipt终结它，并让已冻结的后续items/commit继续取得稳定no-op回执以排空序列，不改写或跳过sequence。

### 13.2 commit

`workspace.import_commit` 只接受 preview 返回的 batch/lineage/source epoch，并按依赖顺序构建完整图：

- guest lease 唯一键为稳定 source workspace；epoch/snapshot hash 只是 compare 字段。lineage、epoch 或 account-binding digest 不匹配时返回 `IMPORT_SOURCE_OWNED`，且不泄露 owner。
- commit 执行 `guest reserved(operation_id, epoch) → account staging/Outbox + matching operation receipt → guest active(batch/manifest/range, epoch)`。active lease 与 account receipt 保存 epoch、begin/terminal sequence、item count 和 canonical bytes；active 前禁止网络 enqueue，reserved 后强杀按 Contract 恢复。
- active lease 跨账号切换、logout/clear/cache 到期、device 换号和强杀保留，只凭 strict proof 释放。
- preview 冻结 source workspace/epoch/snapshot hash、各 target count、portable preference count、总 count/bytes、mapping digest 和 manifest hash。首次批覆盖完整当前 epoch 图；repair/source-change successor 覆盖当前图与同 lineage/epoch 永久 mapping 的并集，并为已不存在但曾发布的 source 生成 typed delete/tombstone。
- account 库在一个事务内分配完整 begin/items/commit Outbox range并让 allocator 越过 terminal；普通 writer 不能占用其中 sequence。这里只写隔离 typed staging，不写 live 表。

跨两个 SQLite 文件采用以下可恢复状态机：

```text
local_staging → server_staging → server_confirmed → publish_applied → cleanup_pending → completed
      │                └→ repair_required → superseded
      └────────────────────────────────────→ abandoned
```

这里的`stage`严格只取Contracts-02冻结的九态；本地/HTTP方法失败走error envelope并保持原stage，绝不持久化额外`failed` stage。取消等待/不确定性使用正交`abandon_status=pending/unconfirmed`，full-successor与cleanup恢复分别使用`reconciliation_status`和`resume_disposition`，所有null矩阵直接消费同一fixture。

要求：

- source snapshot 改变则返回 `IMPORT_SOURCE_CHANGED`，不得导入部分新旧混合数据。
- ID碰撞按整张引用图确定性重映射，lineage/mapping digest、source id/hash、typed counts和manifest写入receipt；重试与repair successor复用同一映射/目标id。相同source快照先调用`workspace.import_status`（batch可空并合并Backend `sync.import.status`），发现confirmed不得再创建新lineage。
- begin/item收到`staged`或`duplicate(original_status=staged)`只推进server-staging证据；漏ordinal、重复/异hash、domain reject均保持live account零写和guest完整。commit确认是唯一发布门槛。
- exact `server_confirmed`只证明Backend已原子发布，C++仍不得把local候选staging写live。源设备与其他设备一样下载服务端canonical import publish group；commit marker完整应用后，在单一账号SQLite事务把canonical设为baseline、重放受影响pending overlay、写live业务表/entity/conflict state并记录`publish_applied` receipt。bootstrap只在永久compact marker identity与当前provenance digest/count全部验证后提供等价证据。这样partial merge/conflict使用服务端权威结果；发布前普通查询和提醒物化均看不到account副本。
- 清理游客源必须在guest单一`BEGIN IMMEDIATE`事务重算整张引用图的snapshot hash/count/version/epoch并compare-and-retire。完全等于lineage current published head时原子退休live业务图：非终态Reminder以`source_migrated`取消、prepared Notification attempt以同reason废弃，迟到finalize被CAS拒绝；终态Reminder/Notification审计留在guest并通过Contract冻结的紧凑audit anchor保持无悬空引用，普通查询与下一epoch manifest均排除这些锚。Search History只有关键词且不参与导入，保持guest所有。事务同时写含source epoch但不含账号身份的cleanup receipt，并把current source epoch安全加一、设置previous-epoch cleanup gate；若epoch已达safe-int上限，仍完成退休/receipt并置`source_epoch_exhausted=true`，照常完成cleanup/lease释放/提醒切换。任一post-commit变化都使本次零退休且epoch不进，并以same-epoch/same-lineage successor完整restage。
- `publish_applied`后的提醒切换按可恢复阶段返回精确affected identities：仅当本机拥有该guest source/epoch cleanup responsibility时，account提醒在HTTP cleanup-confirm + Native completed前保持suppressed；compare-and-retire成功后guest live事实/非终态执行失效，但终态审计anchor仍保留，且绝不能立即解除account抑制。只有Native completed（或匹配account-deleted终态收尾）才解除并reconcile account；其他设备在publish-applied后直接按receive开关reconcile。任意崩溃点不得出现guest与account双提醒。
- repair 或 post-publish source 变化都从新 preview 取得 new batch + same epoch/lineage + predecessor，并完整 restage；旧失败批只在后继接管后 superseded，旧 published 批保留审计终态。同 epoch mapping/provenance 跨 snapshot 复用，completed 旧 epoch 不参加新 epoch。
- origin revoked、fresh lifecycle 丢失旧证据或 TTL 回收 payload 时，status 返回 `full_successor_required`；C++ 在任何普通 writer 分配 sequence 前要求 Kotlin 完成独立 HTTP takeover。
- `workspace.import_accept_range_close` 校验 epoch、origin transport generation 和 proof identity。当前 device 的 `seen_range_closed` 原子终结 matching Outbox/range、推进 ack 基线、标 dirty 并采用 proof allocator；其他 origin 只推进该 epoch lineage revision。
- `never_visible_after_transport_fence` 必须绑定已接纳 device fence，只供旧 runtime 已冻结/销毁后的 fresh recovery 使用同一 fence sequence bundle；不能给仍含旧 generation 普通 Outbox 的保留库挪洞。该入口也接纳 confirmed-abandon/capacity/TTL proof；接纳前 commit 拒绝后继或销毁依赖 proof 的库。sequence/transport exhausted 时保持只读 blocked。
- `workspace.get_state/import_status`暴露nullable active handle/revision、source epoch、lineage级`reconciliation_required`、resume/abandon disposition及previous-epoch cleanup gate；无batch-id时用guest稳定source id + current/receipt epoch发现。pending重启后仍先HTTP abandon且禁新batch，unconfirmed不伪终态。不得省略epoch误命中completed旧lineage；原设备revoked或证据丢失只能按takeover CAS在同epoch lineage完整restage。
- `workspace.import_abandon`只接纳Kotlin独立HTTP CAS的typed disposition并幂等落本地状态，零新Outbox/零新client sequence；无HTTP结果或`proof=null`只记`abandon_pending/local-unconfirmed`，已有begin/items/commit Outbox及其range保持不可变。保留库若Backend尚未见batch且begin前有gap，先让更早Outbox终结，再重复HTTP abandon；只有取得`seen_range_closed` proof才可由Native一次终结matching range并ack-only，不能逐项伪造、删除或跳号。Backend的persistent absent fence保证matching迟到请求在generic replay前返回batch-abandoned，不把设备误冻；隐私destroy可立即crypto-destroy并返回unconfirmed，未来fresh login必须先完成transport fence并接纳`never_visible_after_transport_fence` proof/sequence bundle后才能开放writer。guest源不删。commit先提交则already-confirmed并继续下载publish group；重登靠账号级lineage+epoch发现，服务端孤立staging按TTL收敛。
- begin写入时校验`terminal_client_sequence=begin+total+1`不溢出并持久化到account receipt与guest active lease。已有Backend reservation的capacity/TTL/abandon/takeover由compact range terminal稳定覆盖，C++取得一个`seen_range_closed` proof后一次终结matching本地range、推进ack并发ack-only，不要求每个ordinal逐项HTTP回执。batch absent且begin正好是server next可由abandon原子建+关；有gap时proof必须保持null直至前序补齐，或由destructive lifecycle的transport fence证明never-visible。fresh evidence-loss不得本地伪造receipt；同origin proof/fence落盘后才从权威next创建successor。两条路径都不能因180天、status superseded或maintenance跳sequence。

## 14. Preferences、账号资料缓存与提醒影响

### 14.1 Preferences

- `preferences.get/update` 只接受冻结四项白名单：`timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 ring/popup）与 `auto_enable_reminders_on_other_devices`；locale只保留历史兼容读取/审计，不生成偏好Outbox。
- update 使用 typed patch + expected revision；账号空间写 Outbox，游客空间只本机写。
- wechat 与任意未知 settings key 拒绝。
- 既有全局 Kotlin-local appearance 值的首次迁移只允许 Kotlin 读取后，以版本化回执调用 guest workspace 的一次 typed update；C++ 不扫描 Android Preferences，也不把它自动归给首个登录账号。用户明确 guest→account 导入时，manifest 可包含唯一 `portable_preferences` 颜色项。
- `default_reminder_methods`按Contract保持有序、去重、长度0..2；C++创建Reminder时用目标适用矩阵选择首个合法默认候选，最终Reminder仍恰好一种method。无交集返回“无默认”而非静默popup；偏好update不返回affected reminder ids，也不重算既有Reminder。
- C++从workspace偏好读取`workspace_timezone`用于Event展示/范围投影，从Kotlin注入的`device_timezone`计算Habit/Anniversary当地日期及follow-device Reminder。两者不能互相覆盖；workspace timezone更新不返回Reminder affected ids，OS timezone变化才通过现有reconcile入口重算open follow-device Reminder。

### 14.2 账号资料

- `account_profile` 是 server-only/download-only target；C++ 永不为它生成 Outbox。
- `profile.get_cached` 只返回 email、username、display_name、头像引用、profile revision 和 freshness。
- `profile.accept_server_snapshot` 接受严格资料 API 成功响应，按 revision 幂等应用；旧 revision 不覆盖新 change。
- timezone不复制到profile cache，唯一owner是workspace preferences；locale不是V1同步偏好，只保留现有兼容数据。
- 游客或 account binding 不一致时拒绝，不回退全局 profile cache。

### 14.3 Reminder

- Outbox 只包含 target-specific user intent/template，不包含 Reminder 调度状态、Notification、Alarm、权限、铃声 URI 或投递记录。
- 下载/Bootstrap或导入的权威事实应用commit后返回精确affected identities；本地`sync.conflict.resolve`只返回queued/resolving且不返回affected ids，只有后续服务端effect/resolved delta被apply时才触发Kotlin reconcile。
- C++ 不调用 Android 调度 API；Kotlin reconcile 失败不回滚已提交的同步事实，而进入独立可恢复设备任务。
- 调度和 tap identity 必须包含 workspace；C++ 返回的 affected key 也必须带 workspace。

## 15. Native Boundary 精确对照

实现名称必须逐字来自 Contracts-02 §8.3：

| Native call | C++ Application owner | 关键保证 |
| --- | --- | --- |
| `runtime.open_workspace` | WorkspaceRuntimeService | account binding、v5/v6、key policy、fresh-only transport-fence/sequence/policy seed与bootstrap写锁；clear operation只消费C++的enabled+policy-revision seed并回receipt |
| `runtime.close_workspace` | WorkspaceRuntimeService | revoke、drain、checkpoint、zeroize、幂等 |
| `workspace.get_state` | WorkspaceQueryService | workspace/runtime identity、typed counts与nullable active import handle/revision |
| `workspace.import_preview` | WorkspaceImportService | stable source epoch/snapshot/token/lineage/proposed batch/count/bytes/mapping digest；previous-epoch pending或epoch exhausted时不建新preview |
| `workspace.import_commit` | WorkspaceImportService | epoch/manifest/ordinal、连续完整range、隔离local staging + Outbox；本机publish-applied前live账号零写 |
| `workspace.import_status` | WorkspaceImportService | batch可空的source/epoch/hash发现、server snapshot合并、exact confirmation与提醒切换区分 |
| `workspace.import_accept_range_close` | WorkspaceImportService + SyncStateService | strict接纳含source epoch与origin transport generation的Backend proof oneOf；seen-range同origin原子终结matching Outbox并恢复virtual terminal/ack/allocator/dirty，never-visible只随fresh fence恢复，异origin只推进该epoch lineage；重复幂等、错误proof零写 |
| `workspace.import_abandon` | WorkspaceImportService | 接纳Kotlin独立HTTP CAS的expected revision/disposition并落本地状态；零Outbox/sequence，无结果仅标unconfirmed |
| `workspace.import_cleanup_confirm` | WorkspaceImportService | 接纳独立HTTP cleanup-confirm exact disposition/through revision；匹配guest receipt才completed并解除源设备提醒抑制，零Outbox/sequence |
| `workspace.import_finalize_source_lease` | WorkspaceImportService | 仅接纳Contract strict proof oneOf，在guest事务校验source/epoch/opaque owner/revision后幂等释放reserved/active lease；account-deleted proof还在同事务终结matching cleanup receipt并解除previous-epoch gate而不回退current epoch；无公开Flutter入口、零账号Outbox |
| `sync.accept_transport_fence` | SyncStateService | exact receipt验证old→new generation、operation/session/device、sequence bundle与resolved absent-import fence；使旧run响应失效，fresh open可等价消费；同receipt幂等、错binding零写 |
| `sync.prepare_upload_batch` | SyncUploadService | 精确接受`normal/logout_final/receipt_ack_flush/reenable_pull_only`四种会调用prepare的内部capability，返回含current cursor/download/ack/transport的完整PreparedExchangeRequest union；pull-only/ack-only均空uploads但null规则不同；第五态`clear_rebuild_bootstrap`只走bootstrap方法 |
| `sync.acknowledge_upload` | SyncUploadService | normal验证五种original status/effect refs并落terminal/anchor/import/failed/gate；ack-only只把Backend accepted watermark与prepared reported watermark原子对齐并派生dirty，零cursor/business |
| `sync.apply_download_batch` | SyncDownloadApplyService | 仅normal完整response的transport/account generation/upper-bound/has-more/groups/raw cursor/cleanup/accepted ack；baseline+pending+failed、import双cursor/notice及reenable gate同事务 |
| `sync.record_transport_terminal` | SyncStateService | 校验workspace/device/runtime/session generation与闭合code，按evidence hash幂等持久化blocked gate；写成功前调用方不得宣告run终止，V1无通用清除入口 |
| `sync.begin_bootstrap` | SyncBootstrapService | 只接收 Backend 首响应exact bootstrap/transport/account/upper-bound、highest/client-confirmed/next/exhausted、cleanup水位与trigger reason，隔离staging |
| `sync.apply_bootstrap_page` | SyncBootstrapService | page receipt、typed validation |
| `sync.finalize_bootstrap` | SyncBootstrapService | transport绑定下publish + pending/failed causal overlay + net notice |
| `sync.get_status` | SyncStatusQueryService | 完整Native snapshot：policy、pending/age/bytes、failed/head、conflict、notice四元组、backlog/diagnostics/blocked与native revision；不返回cursor或Kotlin聚合run/time/status revision |
| `sync.set_enabled` | SyncPolicyService | operation id + expected policy revision幂等CAS；false→true原子建立pull-before-push gate；每workspace保留latest receipt，只有接纳新operation才替换旧receipt；不删除Outbox、不影响本机提醒 |
| `sync.claim_conflict_notice` | SyncStatusAndDiagnosticsService | 展示前exact head id/sequence原子claim；返回claimed/no-longer-actionable，零Outbox |
| `sync.build_diagnostic_snapshot` | SyncStatusAndDiagnosticsService | Contract redaction后只输出分桶统计/状态/安全水位，零业务内容 |
| `sync.run_local_maintenance` | SyncLocalMaintenanceService | 持久化安全水位、有界清理、强杀幂等、不推进 cursor |
| `sync.conflict.list` | SyncConflictService | 稳定 snapshot/filter/cursor 分页 |
| `sync.conflict.detail` | SyncConflictService | typed conflicting/auto-merged groups、candidate与conflict version |
| `sync.conflict.resolve` | SyncConflictService | typed resolution、expected version CAS、resolution Outbox；只返回queued/resolving |
| `sync.failed_change.list/detail/discard` | SyncFailedLocalChangeService | typed失败意图稳定读；discard以revision原子删overlay并重投影，零Outbox；正常编辑另建新mutation |
| `preferences.get` | WorkspacePreferenceService | workspace 白名单与 revision |
| `preferences.update` | WorkspacePreferenceService | typed CAS；账号 Outbox、游客零 Outbox |
| `profile.get_cached` | AccountProfileCacheService | 当前账号安全投影与 freshness |
| `profile.accept_server_snapshot` | AccountProfileCacheService | server-only revision、no Outbox、旧 revision 不覆盖 |

每个 codec 必须有：

- exact-key 正反例。
- null/缺失/空值区分。
- enum、safe integer、date/datetime/timezone 校验。
- workspace/runtime/account mismatch。
- error code 到 `NativeError` 的稳定映射。
- encode→decode→encode golden round trip。

错误所有权只在此表登记；错误全集、retryable 与 context 仍以 Contracts-02 §12 为准：

| 类别 | C++ 责任与动作 |
| --- | --- |
| C++ 原生错误 | 只产生 `WORKSPACE_*`、`SYNC_OUTBOX_CORRUPTED`、`SYNC_APPLY_FAILED`、`SYNC_BOOTSTRAP_INCOMPLETE`、`SYNC_ENTITY_CONFLICT_BLOCKED`、`SYNC_ENTITY_SYNC_EFFECT_PENDING`、`SYNC_POLICY_VERSION_CONFLICT`、`SYNC_FAILED_CHANGE_*`、`SYNC_CLIENT_SEQUENCE_EXHAUSTED`、`SYNC_POLICY_REVISION_EXHAUSTED`、`SYNC_STATUS_REVISION_EXHAUSTED`、`SYNC_NOTICE_SEQUENCE_EXHAUSTED`、`SYNC_IMPORT_CAPACITY_EXCEEDED`、`IMPORT_SOURCE_CHANGED`、`IMPORT_SOURCE_OWNED`、`IMPORT_SOURCE_EPOCH_EXHAUSTED`、`IMPORT_LINEAGE_MISMATCH`、`IMPORT_PUBLISH_INCOMPLETE` 和 `SYNC_CONFLICT_*`。`WORKSPACE_*` 不含 Kotlin Registry 拥有的 route/lifecycle revision exhaustion。 |
| 本机计数器耗尽 | policy 耗尽使 toggle 零写并保留策略、Outbox 和提醒；native-state 在 MAX 发布一次 durable blocked；notice 耗尽只停止新增提示，不影响下载、未解决数、冲突列表或旧 notice。 |
| Backend 终态输入 | Auth/Device/Cursor/sequence/bootstrap/import-CAS 结果由 Kotlin 按 strict `counter_kind/origin` 分类后驱动 C++ 状态迁移。C++ 保留 import current stage/head/revision，不改写本机意图；能力级零写不能伪装 Native 成功、换 identity 或无限重试。 |
| 容量来源 | 本地 preview 可在 sequence 分配前返回 `SYNC_IMPORT_CAPACITY_EXCEEDED` 且零 staging/Outbox；与服务端终态用 `origin=local_preflight/server_terminal` 区分。 |
| 必须耐久化的 transport 终态 | protocol、sequence replay/route mismatch、client/server sequence exhaustion 和不可恢复 cursor identity 错误，由 Kotlin 调 `sync.record_transport_terminal`；C++ 校验 workspace/device/runtime/session binding 与 evidence hash 后幂等写 `sync_state`。之后所有 Outbox writer/prepare 跨重启 fail closed；V1 仅由 crypto-destroy/fresh lifecycle 或正式迁移解除。 |
| 非永久 generation mismatch | `SYNC_TRANSPORT_GENERATION_MISMATCH` 只终止旧 lifecycle run并恢复当前 fence，不能把当前 workspace 标为永久 corrupted。 |
| Kotlin 原生错误 | `LOCAL_SETTINGS_VERSION_CONFLICT`、route/local-settings/lifecycle/token-generation exhaustion 和 `NOTIFICATION_WORKSPACE_*` 由 Kotlin 路由/协调层产生。 |

任何层都不得为了覆盖错误表而伪造不属于自己的来源。

## 16. 分阶段实施顺序

本节只排序第 5–15 节的交付，不新增规则：

| 阶段 | 工作锚点 | 主要产物 | 退出证据 |
| --- | --- | --- | --- |
| C0 基线与门禁 | §3–§4、§15 | v5 hash、writer/ID/field-owner inventory、ADR 与 SQLCipher/JCS spike、Contract fixture runner | blocker 均有决定；Contract 未冻结则不进 C1 |
| C1 Runtime 与 v6 | §5–§6 | 多实例 registry、open/close/lease/generation、fresh-v6 与 v5→v6 | v5 无回归，guest/account 并行不串库 |
| C2 存储与本地写 | §7–§9、§13–§14 | repositories、trusted origin、事务 Outbox、failed overlay、preferences/profile cache | writer inventory 逐项通过故障注入原子性证明，guest 零 Outbox |
| C3 上传 | §9、§15 | fence/sequence/prepared/ack/receipt/effect gate 与五类 terminal 结果 | C++ 与 Java 对适用 `FX-*` 的 payload/hash/result 一致 |
| C4 下载与冲突 | §10、§12、§15 | atomic apply、双 cursor、overlay、conflict/notice/maintenance、affected identities | 非法批次零写，cursor 仅随完整事务推进 |
| C5 Bootstrap | §11、§15 | staging/page receipt/finalize/rebase 和 recovery bundle | 20,000 条固定快照可强杀恢复且无半发布 |
| C6 Import | §13、Contracts-02 §7.6 | 本机双库 saga、publish evidence、range proof、cleanup/audit/lease 收尾 | 全部 `FX-IMPORT-*` crash point 无丢失、重复或提前清理 |
| C7 加密集成 | §6、§14 | 单一 SQLCipher provider、三 ABI、WAL/SHM/temp 与 key lifecycle | 静态文件无业务明文，性能达到统筹门限 |
| C8 层完成 | §17–§19 | 新构建测试、checker、性能和 Kotlin/JNI handoff + Contract hash | 只标记 `Layer Complete / Awaiting Integration` |

## 17. 测试与验证矩阵

### 17.1 自动化套件与规则追踪

每个套件都必须消费 Contracts-02 §13 对应 `FX-*`，并在 C++ 侧增加事务故障点、强杀重开和并发交错；期望业务语义来自 fixture 的 `rule_anchor`，不在本节重写。

| 套件 | 实现锚点 | Contract fixture | C++ 特有证据 |
| --- | --- | --- | --- |
| Codec / origin | §7、§15 | `FX-TARGET`、`FX-CANONICAL`、`FX-COUNTER` | exact-key/null/enum/safe-int/identity，六类 trusted origin 权限，encode→decode→encode |
| Runtime / storage | §5–§6、§8 | `FX-WORKSPACE` | fresh/migrate/downgrade/corruption、wrong key/binding、双 runtime、close 与在途调用、WAL/磁盘满 |
| Local writer | §7–§9 | `FX-TARGET`、`FX-MERGE`、`FX-FAILED-LOCAL` | 事实+Outbox、resolution+Outbox、remote/profile/guest 零 Outbox 的逐 writer 故障注入 |
| Upload / ack / fence | §6、§9、§15 | `FX-SEQUENCE`、`FX-RUN`、`FX-COUNTER` | prepared 稳定性、五种 original status、receipt/effect gate、dirty ack-only、旧 generation 零写和 causal anchor 保留 |
| Download / conflict | §10、§12、§15 | `FX-MERGE`、`FX-CONFLICT`、`FX-FAILED-LOCAL` | baseline+pending+failed overlay、不可拆 group、notice exact claim、resolve 后 affected identities 与 cursor 原子性 |
| Bootstrap | §11、§15 | `FX-CURSOR`、`FX-BOOTSTRAP` | 服务端 session id 复用、page receipt/finalize 强杀点、hard cap、pending/failed rebase 和 deleted-anchor recovery |
| Import | §13、Contracts-02 §7.6 | 全部 `FX-IMPORT-*` | 双库事务边界、range proof 接纳、allocator/ack 恢复、publish-applied、epoch/lease/audit 收尾和每个状态转换强杀点 |
| Policy / profile / maintenance | §12、§14 | `FX-PREFERENCE`、`FX-MAINTENANCE` | latest operation receipt、genesis/retain/destroy/clear-rebuild seed、download-only profile、有限批清理与百万 notice 窗口 |
| Domain / reminder regression | §7、§14 | `FX-TARGET`、`FX-RETENTION-NOTIFY` | Event/Anniversary/Habit recurrence 隔离、现有整系列 Event update、HabitCheckIn、reminder intent 与设备执行状态分离 |

### 17.2 性能

基于总计划场景测量并记录硬数据：

- 20,000 条事实 + 大量unresolved conflicts的首次migration、open、bootstrap和import。
- 500 changes download apply。
- 100 items/1 MiB 上限附近 prepare/hash。
- 日常单条业务写增加 Outbox 后的 p50/p95。
- WAL checkpoint 与加密前后差异。

如未达到总计划 §19 指标，不能通过调整文档宣称完成；需分析索引、批量事务或协议上限，并协调 Contract。

### 17.3 必须执行的命令门禁

```text
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

必须使用“构建后测试”目标，不能只运行可能陈旧的 CTest 二进制。SQLCipher/Android ABI 另由 Kotlin/集成计划在真实 APK 中验证。

## 18. 跨计划交接

### 18.1 输入

| 来源 | C++ 所需冻结输入 |
| --- | --- |
| Contracts-02 | Native Schema、target payload、field registry、errors/enums、hash fixture、v6 DDL/migration、notification workspace identity |
| Backend-04 | upload result/change/bootstrap/conflict fixture；server version/sequence/receipt 语义 |
| Kotlin-05 | workspace path/key/device identity 的可信传入方式；JNI 二进制 key；worker batch 上限 |

### 18.2 输出

| 消费层 | C++ 提供 |
| --- | --- |
| Kotlin-05 | §15 全部 Native calls、runtime/transport identity、native state revision与sync-policy revision、failed-local/status、affected reminder identities、错误映射；聚合`status_revision`仍由Kotlin唯一拥有 |
| Flutter-06 | 通过 Kotlin 暴露的 workspace/status/import/conflict/failed-change/preferences/profile typed 状态，不暴露 cursor/outbox/raw payload |
| Backend-04 | 同一 golden payload/hash、sequence/receipt、bootstrap 和 conflict resolution 行为 |

### 18.3 联调不变量

- Kotlin 发送给 Backend 的 upload item 必须是 C++ prepared batch 原样映射，禁止重建 payload 或重算 hash。
- Backend response 必须原样映射到 C++ acknowledge/apply DTO，Kotlin 不合并业务字段。
- C++ 返回 affected reminder identities 后 Kotlin 才 reconcile；失败进入本机重试，不伪装同步回滚。
- Flutter 看到的 pending/conflict/last success 来自 C++/Worker 聚合权威状态，不从按钮点击推断。
- 五份计划任何接口改名必须在同一文档变更中更新 Contracts 映射与双方计划。

## 19. 完成定义

只有同时满足以下条件，本分计划才可标记 `Layer Complete / Awaiting Integration`：

- [ ] C0–C8 的退出证据完整，且实现仅使用第 15 节冻结调用和同一 Contract revision/hash；旧 `sync.apply` 与 runtime Fake 未进入生产路径。
- [ ] 第 17 节全部自动化套件通过，涵盖 writer/apply/cursor 原子性、guest 零 Outbox、多 runtime、v5→v6、Import/Bootstrap crash recovery 和 C++/Backend golden 一致性。
- [ ] 账号 SQLite 加密、WAL/SHM/temp、错误 key 和三 ABI 已在真实目标验证；`excellent_calendar_check` 从新构建成功。
- [ ] 第 18 节输入、输出和联调不变量均由消费方签收，未把单层结果描述为端到端完成。
- [ ] diff 仅含任务范围，用户既有修改未被覆盖；未执行的门禁明确标为 `UNVERIFIED`。

真实 Flutter→Kotlin→JNI→C++、WorkManager、HTTPS Backend、双设备/弱网/撤销/通知点击仍由云同步-01 的集成验收统一签署。

## 20. 明确不做

- 不在 C++ 实现 HTTP、WorkManager、Keystore、Android Permission、Alarm 或 Notification。
- 不上传游客数据、搜索历史、RingSettings、投递记录、附件、AI、微信或 Widget 状态。
- 不让 Backend/C++ 展开同一套 occurrence 形成双真相源。
- 不顺带重构无关业务 Repository、修改历史 v5 Contract 或升级无关工具链。
- 不以轮询扫描补 Outbox，不以时间戳/rowid 代替序列或版本，不以宽松 JSON 兼容未知字段。
- 不在本分计划宣称端到端完成。
