# 云同步-02：Contracts 与数据模型开发计划

> 状态：ACTIVE PLAN / DECISION REQUIRED / CT0 PARTIAL
> 建立时间：2026-09-04
> 上位计划：[云同步-01：Local-first 多设备同步开发计划](./云同步-01-Local-first多设备同步开发计划.md)
> 负责范围：`docs/domains/` 中同步相关语义、`docs/architecture/decisions/` 中同步 ADR、`contracts/**`、跨层 fixture/validator 以及 SQLite v6 / PostgreSQL 逻辑模型冻结
> 下游计划：云同步-03（C++/SQLite）、云同步-04（Cloud Backend）、云同步-05（Kotlin/Android）、云同步-06（Flutter）
> 文内语义锚点：第 5–12 节定义版本、协议、方法、模型与错误；第 13–17 节只登记 fixture、执行顺序和冻结证据，不得重新定义前述语义。
> 2026-09-05 执行记录：[CT0 审计与决策记录](./云同步-02-CT0审计与决策记录.md)。完成安全基线校准、旧协议保护、HTTP静态盘点与部分隔离实验；七项ADR仍为Proposed，加密/JCS/身份兼容等门禁未关闭，CT1–CT4未开始，不代表Contract冻结或下游可实现。

## 1. 目标与完成口径

本计划先把云同步 V1 的领域语义、传输协议、版本、错误、状态机、持久化逻辑模型和跨层调用名称冻结，再允许四个实现层进入写代码阶段。它是五份分计划共同依赖的协议基线，不承担产品 UI、Android 网络、C++ 业务实现或 Backend Controller 实现。

本计划的完成状态只能是以下三种之一：

- `CONTRACT FROZEN`：ADR、Schema、方法表、错误码、兼容矩阵、fixture、validator 和两端数据模型均已通过评审与机器校验；下游可以按冻结版本实现。
- `DECISION REQUIRED`：存在会改变数据语义、接口形状或迁移路径的未决项；相关下游只能只读盘点或 spike。
- `BLOCKED`：加密可行性、历史数据解释、身份稳定性或现有协议冲突无法安全解决。

仅新增文件、写出草案或让 JSON Schema 能解析，不能视为完成。所有下游计划在本计划达到 `CONTRACT FROZEN` 前均保持 `planned`，不得各自发明字段、方法、错误字符串或兼容分支。

## 2. 上位原则与不可变边界

本计划严格引用云同步-01 §1.1 的唯一裁决顺序。冻结前必须分别记录“当前 active 真相”和“本次目标”：当前行为按 active machine Contract/Schema → 当前领域不变量 → Accepted ADR → active计划 → 架构 → 实现判断；本次明确验收目标若要改变前三者，先修订ADR/领域文档/Contract并提供迁移。本文及 planned/blocked Schema 在 `CONTRACT FROZEN` 前不是下游实现真相源；冻结后机器Contract才成为03–06的直接接口真相源。冲突未闭合时标`DECISION REQUIRED`，不得用兼容双分支掩盖。

以下规则直接继承总计划，分计划无权改变：

1. 客户端 SQLite 是离线业务真相源；Backend 是账号同步中枢，不替代 C++ Core。
2. 游客 workspace 与账号 workspace 物理隔离；游客数据永不上传。
3. 账号 workspace 的可同步业务写与 Outbox 必须在同一 SQLite 事务提交；远端 apply、设备本地状态和投递日志不得反向产生 Outbox。
4. 服务端以认证账号、注册设备、`client_sequence`、`mutation_id`、`entity_version`、`server_sequence` 和 opaque cursor 建立幂等与顺序；客户端时钟不参与并发裁决。
5. 不同可独立合并字段自动合并；同一字段或同一语义字段组发生竞争时形成可见冲突。
6. 删除使用 tombstone；删除与编辑并发时列表先隐藏对象，同时保留本机候选以供恢复。
7. Reminder 只同步用户意图或模板。Android 权限、Alarm、RingSettings、铃声 URI、Notification、投递 attempt、搜索历史等设备事实不上传。
8. Backend 不展开 occurrence，也不复制 Event/Habit/Anniversary recurrence engine。
9. Native 边界使用 `NativeResult<T>`；HTTP 边界使用 `ApiResult<T>`；两个外壳及版本域不得混用。
10. `datetime` 使用 ISO 8601 UTC，`date` 使用 civil date，timezone 使用 IANA ID；缺失、`null`、空值和默认值保持不同语义。
11. V1 无 FCM、无附件同步、无共享协作、无历史版本恢复、无整账号备份；只面向小规模内测。

## 3. 当前基线与冻结前冲突清单

| 项目 | 当前事实 | V1 目标 | 冻结动作 |
| --- | --- | --- | --- |
| Sync Schema | `sync_operation.schema.json` 允许任意 `payload`，`sync_result.schema.json` 只有两个布尔值 | 强类型 mutation、逐项结果、change、conflict、cursor、bootstrap | 原占位标记 deprecated/blocked；新建 Sync Protocol v1 Schema |
| `sync.apply` | 仅在 `method_channels.yaml` 声明，无生产实现 | 批次上传、下载原子应用、状态、冲突和 workspace 能力 | 保留不可调用的兼容墓碑，不为其补运行时实现 |
| Native Contract | Native v2 已 active | 新 Sync 能力随同一 APK 增量加入 | 若不改变已发布方法语义则保留 v2；任何已发布必填形状变化必须升版 |
| Runtime storage version | C++/Kotlin 已要求 SQLite v5，但 runtime initialize response 的 Schema/fixture 仍残留常量 v4 | v5 基线一致后再定义 v6 open result | Contract 阶段先校准现状漂移；不得让 v6 计划掩盖错误的 v4 fixture |
| Backend Contract | `backend_api.yaml` 顶层和现有端点仍 `planned` | 校准 16 个已实现端点并增加设备/同步端点 | 逐端点核对 Controller、测试和 Schema；不能用顶层状态掩盖混合完成度 |
| HTTP 错误 | Contract 写成所有应用结果 HTTP 200；实现已使用语义 4xx/5xx | 采用一套可测试规则 | 冻结前由 ADR 选择；本计划推荐“语义 HTTP 状态 + 始终可解析的 `ApiResult`”并同步 Flutter/Backend 测试 |
| HTTP 幂等 | Contract 要求同 key 异 payload 明确失败；现实现可重放旧成功 | payload 不同绝不能重放 | 增加 request digest，返回 `API_IDEMPOTENCY_KEY_REUSED` 或冻结后的等价码 |
| Auth token owner | Flutter 当前执行 refresh；Kotlin 只存取 Refresh Token | Kotlin `SessionCredentialBroker` 单一刷新 owner | 新增 session broker Contract，同一发行版本移除 Flutter refresh owner |
| Refresh 崩溃窗 | 旋转成功但新 token 未落盘时无法证明请求结果 | 必须 fail-closed 且有可重复测试的恢复 | V1 默认在不确定状态清除本机会话并要求重新登录，不重放旧 Refresh Token |
| Category | Accepted ADR 只允许 create/list，明确未决定 update/delete/sync | V1 要同步名称、描述、颜色、图标、排序和删除状态 | 先新增/修订 Category 生命周期与账号同步 ADR；未接受前 Category mutation Contract 不冻结 |
| Anniversary timezone | 当前 Anniversary 是 date-only；查询 timezone 不持久化，提醒为 `follow_device` | 总计划要求日期不漂移并同步提醒意图 | V1 不新增 Anniversary 实体 timezone；总计划中的“时区”解释为 reminder `timezone_mode` 和查询上下文，若要固定实体时区必须另开 ADR |
| Appearance | `appearance.*_local` 已是 Kotlin 本机 active 能力 | 账号 workspace 同步白名单设置，游客仍本机 | 保留旧方法语义；新增 workspace-aware `preferences.*`，迁移后再决定旧入口弃用窗口 |
| 账号资料传播 | `user.get_current/update_current`、头像与邮箱安全接口已有实现，但没有多设备变更通知闭环 | 资料更新后其他设备最终看到一致的安全资料投影 | 新增 download-only `account_profile` change；资料写仍走既有专用 API，禁止进入普通 Outbox |
| 通知点击身份 | 当前 tap payload 只有业务 `target_id`，没有 workspace 身份 | 账号登录期间游客提醒仍可执行，点击必须定位原 workspace | 兼容增加可选 `workspace_id`；所有 v6 新调度强制写入，歧义旧 payload fail closed |
| Storage | SQLite v5 active，单一进程级 runtime | SQLite v6、workspace、Outbox、导入和加密账号库 | v5 冻结输入 checker + 相邻 v5→v6 migration，不修改已发布 v5 定义 |

以上差异不得由单一实现层私自兼容。涉及现有 active 能力的改变必须在兼容矩阵中明确旧 reader、旧 writer、升级顺序和失败行为。

## 4. ADR 与可行性门禁

### 4.1 必须接受的 ADR

Contract 写入前先建立并接受下列决策；名称可按仓库 ADR 编号规范调整，但议题不可省略：

- [ ] Sync Protocol：设备顺序、mutation 幂等、字段/字段组版本、change feed、cursor snapshot、bootstrap、tombstone 与保留窗口。
- [ ] Workspace Lifecycle：游客/账号隔离、同时存活的提醒 runtime、切换/退出/撤销/缓存清理、可信时间与30天目标保留窗口、跨库导入恢复，以及导入后本机Reminder/Notification/Alarm/Ring/Recovery审计与执行图的处置。
- [ ] Account SQLite Encryption：SQLCipher 或等价方案、密钥生命周期、三 ABI、WAL/临时页、备份与密钥丢失行为。
- [ ] SessionCredentialBroker：Refresh Token 单一 owner、single-flight、崩溃窗、logout/revoke/auth failure 的统一终止路径。
- [ ] Category Sync Lifecycle：账号归属、update/delete/reorder、弱引用、旧 opaque `category_id`、冲突与恢复语义；不得静默改写 ADR-Category-01。
- [ ] Backend HTTP Contract Calibration：HTTP 状态、`ApiResult`、`Retry-After`、Idempotency-Key payload digest 和现有 16 个端点的状态校准。
- [ ] Android Backup / Device Transfer：冻结Auto Backup、cloud backup与device-to-device transfer的包含/排除矩阵。`installation_id`、Broker凭据、Keystore/wrapped key、账号DB/WAL/SHM、workspace/device registry内容、transport/import/clear lifecycle journal、远端设备cache以及guest数据库都必须从Auto Backup/任何cloud backup排除，贯彻“游客本机空间永不上传”。device-to-device direct transfer默认同样排除；只有独立ADR明确证明传输通道不落入第三方云、恢复前可原子换新guest workspace/source identity并阻止重复导入时，才可单独允许guest direct-transfer re-home，不能沿用Android默认行为或把换identity当作云上传补救。

### 4.2 Spike 与审计退出条件

- [ ] SQLCipher 候选完成许可证、Android 三 ABI、当前 sqlite3 API、WAL/defensive 配置、20,000 条数据和强杀恢复 spike。
- [ ] 完成 RFC 8785/JCS + SHA-256 跨端可行性 spike：以官方/等价边界向量覆盖Unicode、对象键排序、数字/nullable/array及JSON safe-integer边界，在Windows C++、Android三ABI与Java得到完全相同UTF-8 bytes/hash。现有`cpp_core/src/common/search_token_crypto.cpp`中的SHA-256实现只可在抽取、独立KAT与许可证/边界审计通过后复用；Java/C++均不得在未批准时新增依赖。该JCS规则与`contracts/identity.yaml`为UUID identity定义的紧凑数组canonical规则是两个版本域，禁止相互替换。
- [ ] 所有 V1 业务实体 ID 完成稳定性审计；记录哪些是 canonical UUID、哪些必须继续作为 opaque ID，并给出引用图重映射规则。
- [ ] 明确现有 SQLite v5 生产目录、v1/v2/v3→v4→v5 migration 链和 v5 checker hash，不允许修改历史 migration。
- [ ] 核对当前 Auth/Profile Controller 与 `backend_api.yaml` 的每个 request、response、error、HTTP status 和幂等行为。
- [ ] 明确游客提醒在账号登录期间继续运行；这要求 workspace registry 可同时路由游客提醒 runtime 与当前账号 runtime，不能只保存单一全局 Core。
- [ ] 冻结通知身份迁移：`NotificationTapPayload.workspace_id` 为兼容性可选字段，但所有 v6 writer 必须提供；旧 PendingIntent 缺失该字段时仅可在唯一无歧义的 legacy workspace 中解析，否则拒绝路由，绝不跨库按 `target_id` 搜索或回退当前账号。
- [ ] 审计主Manifest当前未声明`allowBackup/dataExtractionRules/fullBackupContent`且仓库无备份规则XML的现状；ADR落地前，任何账号缓存保留、重装后新installation或guest transfer语义均不得宣称完成。fixture必须覆盖uninstall/reinstall、Auto Backup/cloud restore、device transfer、Keystore key缺失及同一迁移源到两台设备；cloud路径必须证明guest也未进入备份，direct transfer若获准则证明开放业务前已re-home且不会复用lineage/lease。

任一项失败时，只阻塞受影响 Contract；不得用 Android 私有目录冒充加密、用时间戳冒充版本、用运行时 Fake 冒充协议完成。

## 5. 版本域与发布状态

| 版本域 | 目标版本 | 策略 |
| --- | --- | --- |
| Sync Protocol | `sync_protocol/v1` | 独立业务 payload 版本，可同时被 Backend API 和 Native apply Schema `$ref`；发布后至少支持 N−1 |
| Backend HTTP API | `/api/v1` / `backend_api` v1 | 现有端点尚未正式激活，可在冻结前校准；发布后按 N−1 和明确弃用窗口演进 |
| Native MethodChannel/JNI | Native v2 的 additive revision | 新方法逐项 `planned → implemented_unintegrated → integrated/active`；不改变既有 active 方法形状 |
| Calendar Core Storage | SQLite v6 | 仅允许冻结 v5 输入后的相邻原子 migration；旧 runtime 必须对 v6 fail closed |
| Workspace registry | 独立格式 v1 | Kotlin 私有、原子写入、只保存路由/密钥别名/缓存期限，不保存业务事实或 token |
| Flutter ordinary cache | 独立格式版本 | 不复用 API/Native/Storage 版本；换号和锁定时不得泄露标题或搜索结果 |

`implementation_status` 与 `release_status` 必须逐 capability 表达。Schema 存在只代表 `planned`；四个层的单元测试完成只代表 `implemented_unintegrated`；同一真实 APK、真实 Backend、真实 SQLite 和双设备验收通过后才可统一切换为 `integrated + active`。

## 6. Sync Protocol v1 身份与顺序

### 6.1 身份定义

| 字段 | 生成方 | 作用域与约束 | 禁止替代物 |
| --- | --- | --- | --- |
| `account_id` | Backend | 从已验证 Principal 获取；HTTP body 不接受调用方声明 | email、username |
| `workspace_id` | Kotlin `WorkspaceIdentityFactory` / `WorkspaceRegistry` | 本机稳定 UUID；Kotlin是唯一物理分配方，先于open生成并传入C++；C++只校验、在v6 metadata原子持久化且之后不可变。legacy v5 guest由Kotlin迁移journal一次分配并在重试中复用 | C++临时自造、目录名、账号 ID |
| `runtime_instance_id` | C++ `runtime.open_workspace` | 仅当前进程内该已打开runtime有效、不可跨close或进程重启复用；already-open只有workspace/metadata/key binding完全相同时返回同一值，所有后续Native响应必须回显 | workspace id、指针地址、进程号 |
| `installation_id` | Kotlin 首次安装 | 本机随机 UUID；重装变化；Backend 只保存摘要 | Android ID、IMEI、广告 ID |
| `device_id` | Backend `device.register` | 账号内注册设备 UUID；所有同步请求必须校验归属和未撤销 | installation_id |
| `sync_transport_generation` | Backend `sync.device_fence` | 同一 active `device_id` 从 0 开始、仅由服务端 checked increment；隔离清库/销毁前后的 HTTP 生命周期 | App 进程号、session generation、sync account generation |
| `entity_id` | 对应领域 writer | 沿用实体已审计的稳定身份；按实体 Schema 校验 | rowid、数组位置 |
| `mutation_id` | C++ Outbox | UUIDv4；一次逻辑 mutation 永不改变 | request timestamp |
| `client_sequence` | C++ 设备序列分配器 | 同一 `device_id` 从 1 严格递增，JSON safe integer | 本机时间、Outbox rowid |
| `operation_id` | Habit CheckIn 命令 owner | 增量/替换/清空跨 rebase 保持稳定 | 新重试产生的新 mutation_id |
| `entity_version` | Backend | 实体每次被接受的逻辑版本，严格递增 | JPA `@Version`、`updated_at` |
| `server_sequence` | Backend | 账号 generation 内 change feed 单调序列，可有空洞 | entity_version |
| `cursor` | Backend | HMAC 认证 opaque token，绑定 account/device/generation/snapshot upper bound | 可解析页码、时间戳 |
| `conflict_id` | Backend | 冲突 UUID；`conflict_version` 单独 CAS | entity_id |
| `import_lineage_id` | Contract确定算法；C++生成/Backend复算 | UUIDv5（冻结namespace）作用于canonical `account_id + LF + source_workspace_id + LF + decimal(source_epoch)`；同账号/源/epoch内永久稳定，跨端golden验证 | snapshot hash、随机run id、忽略epoch的旧算法 |
| `import_batch_id` | C++ import preview | 每次源快照/repair的UUIDv4 proposed id，preview返回后上层只可回传；Backend幂等回执键 | UI自造id、lineage id |

所有 JSON integer 必须落在 `0..9007199254740991`；序列耗尽显式失败，不能回绕。opaque cursor 的最大长度、字符集和 canonical Base64URL 规则由 Schema 固定，客户端不得解析或拼接。

`device.register` 返回该设备权威的 `sync_transport_generation`、`highest_client_sequence`、nullable `next_client_sequence`、`client_confirmed_through` 和 `client_sequence_exhausted`。highest 小于上限时 exhausted=false 且 next=highest+1；highest 等于上限时 exhausted=true 且 next=null。

已有账号库只用这些值校验本地 transport、sequence 和确认水位不倒退，不能覆盖未确认 Outbox。立即清库、缓存到期或显式销毁后，若沿用 active `device_id` 新建账号库，必须先完成 transport fence，再以其合法 next 初始化分配器并 bootstrap，不能从 1 重新起号。

达到上限后账号库仍可 bootstrap 只读；任何需要新 client sequence 的 writer 返回 `SYNC_CLIENT_SEQUENCE_EXHAUSTED`，事实和 Outbox 零写，并进入 blocked 诊断。V1 不自动轮换当前 device identity。账号 server sequence 耗尽同样返回 `SYNC_SERVER_SEQUENCE_EXHAUSTED`，阻止需要 change 的事务。已撤销设备不能因相同 installation 登录而复活；显式登录产生新登记和新 `device_id`。

`sync_transport_generation` 是“旧 HTTP 请求是否仍有资格提交”的服务端栅栏，而不是业务 cursor generation。所有会写同步状态、事实、receipt、bootstrap session 或 import lifecycle 的请求都必须携带调用开始前持久化的该值；Backend 在同一事务按固定顺序锁定并重新验证有效 Session、`user_devices` 与 `sync_device_state`，随后才可读写其他同步行，并在提交前再次满足generation未变。`sync.device_fence`携带`fence_operation_id + expected_sync_transport_generation + reason`，在相同锁序下等待更早事务结束、checked increment generation，持久保存同operation的结果回执，并返回新generation、完整sequence recovery bundle及防篡改fence receipt；同operation同payload在响应丢失后返回原结果，同id异payload fail closed。若旧请求先取得锁则它先完整提交，fence读取其最新highest；若fence先提交，旧generation请求稳定返回`SYNC_TRANSPORT_GENERATION_MISMATCH`且零写，因此不存在“本地已删库，旧响应/旧请求随后又提交”的窗口。

active clear 必须在零删除预检中阻写本地账号 writer、收敛或显式终结 Outbox/import、完成尾部ack-only，再在线取得fence并由C++接纳后才允许毁key/DB。`force_local`、30天到期或可信安全终态可为隐私立即销毁而不等待网络，但必须在Broker的非业务生命周期记录中留下`transport_fence_required`；以后同一active device任何fresh账号库在writer/open-bootstrap门禁前都要先register取current generation、执行/幂等恢复fence，并只消费fence返回的sequence bundle。旧runtime收到的响应也必须因runtime/session/transport binding不符而丢弃。fence到MAX时返回`SYNC_TRANSPORT_GENERATION_EXHAUSTED`且零销毁/零新写；隐私销毁仍可完成，但该device不得再次打开可写账号库。

safe-integer上限与checked-increment只适用于机器`sync_counter_registry`逐项登记的**单调计数器**，字段名后缀本身不决定语义。`pending_upload_count`、`failed_local_change_count`、`unresolved_conflict_count`、`unclaimed_conflict_notice_count`等状态快照派生数量可以增加、减少或重算；`total_item_count`、各target count等请求基数只要求非负、受Schema上限约束，也不是revision allocator。任何新单调计数器必须先登记唯一owner、初值、MAX动作与错误；未登记的`*_count`不得被通配实现为只增不减。`source_epoch`等已登记项继续按registry执行：MAX epoch的已发布导入仍可完成compare-and-retire、cleanup-confirm、lease释放与提醒切换，只是不再允许该guest workspace发起新导入。

为使冻结不再悬空，机器`counter_registry`至少固化下表；同一码的`context.counter_kind`必须是闭合enum，owner和动作不可由消费层改写：

| Counter | 唯一 owner | MAX边界结果 |
| --- | --- | --- |
| client/server sequence、transport generation、source epoch | C++ allocator / Backend account或device state / Backend fence / C++ guest metadata | 分别使用既有`SYNC_CLIENT_SEQUENCE_EXHAUSTED`、`SYNC_SERVER_SEQUENCE_EXHAUSTED`、`SYNC_TRANSPORT_GENERATION_EXHAUSTED`、`IMPORT_SOURCE_EPOCH_EXHAUSTED`及其已冻结只读/销毁语义 |
| `active_route_revision` | Kotlin WorkspaceRegistry | 需推进时整次route事务零写并返回`WORKSPACE_ROUTE_REVISION_EXHAUSTED`；保留最后稳定route，只开放导出/安全终止，不换workspace id绕过 |
| `local_settings_revision`、`lifecycle_revision` | Kotlin DeviceSettings/Lifecycle journal | 需推进时相关设置/clear/logout operation零跨owner写并返回`LOCAL_SETTINGS_REVISION_EXHAUSTED`或`WORKSPACE_LIFECYCLE_REVISION_EXHAUSTED`；已提交journal仍按原revision收尾 |
| `access_token_generation` | Kotlin SessionCredentialBroker | 在产生下一token snapshot前终止本地Session family并返回`AUTH_TOKEN_GENERATION_EXHAUSTED`；不得回0、继续使用无法排序的新token或伪造Backend generation |
| `sync_policy_revision` | C++ SyncPolicyService | toggle事务零写并返回`SYNC_POLICY_REVISION_EXHAUSTED`；现有策略/Outbox/提醒保持 |
| `native_state_revision`、Kotlin `status_revision` | C++ sync state / Kotlin SyncStatusAggregator | owner在最后一次可递增时发布MAX的durable blocked终态；后续需推进的sync控制事务返回`SYNC_STATUS_REVISION_EXHAUSTED`，不得饱和后继续发同revision事件 |
| `notice_sequence` | C++ notice queue | 达MAX后原子置`notice_sequence_exhausted`并返回/记录`SYNC_NOTICE_SEQUENCE_EXHAUSTED`；停止新增一次性toast但继续下载、保留unresolved count和冲突列表，不清旧notice |
| Backend `account_generation/device_version/entity_version/field_version/conflict_version/account_profile_revision/preferences_revision/import_revision` | 各PostgreSQL聚合/行事务 | 在事实写前checked increment；不足则该能力事务零写并返回`SYNC_COUNTER_EXHAUSTED`，`counter_kind`严格取对应字段，不能以新id/LWW/时间戳绕过 |

所有max−1→MAX、MAX后重试、同operation重放、并发双写和跨层error映射必须进入golden；公开计数值本身可以等于MAX，但任何需要再增长的动作只能走上表结果。

fresh account DB 不能只靠 register 响应重建“哪些旧 receipt 已在本机生效”的证据。bootstrap 创建事务必须在设备锁与账号 sequence 锁下冻结 `device_highest_client_sequence_at_snapshot`、`device_client_confirmed_through_at_snapshot`，并物化该 requesting device 当前每个 target/entity/merge-key 的紧凑 causal anchor；这些值属于 bootstrap session identity并由所有页的 hash/token 绑定。只有 finalize 已证明完整事实、tombstone、unresolved conflict、import marker与该 upper bound 一致时，C++才可把 fresh DB 的本地确认基线提升到 `device_highest_client_sequence_at_snapshot`、把分配器提升到其下一号并恢复 causal anchors；随后下一次exchange才把新确认水位报告给Backend。existing DB只做单调一致性校验，绝不借bootstrap越过本地gate/Outbox。这样清库前服务端已终结但客户端确认水位尚未推进的receipt/effect group可安全释放，不会被永久pin；若不能提供这组证明，则必须走独立receipt-recovery分页，禁止猜测确认。

所有跨端比较的`payload_hash`统一为：先按RFC 8785对Contract envelope生成UTF-8 bytes，再SHA-256，wire为64个小写hex。hash输入包含target/operation/base version、per-key causal predecessors、全部import identity、typed payload与nullable conflict-recovery snapshot，不包含HTTP header、重试次数、`created_at`等诊断字段；精确envelope由机器invariants/golden固定，Java/C++不得各自拼字符串。

### 6.2 上传批次规则

1. `upload_mutations` 按 `client_sequence` 严格升序且无重复；每批最多 100 项。解压后 1 MiB 请求上限在冻结前用真实 fixture 校准。
   - 机器 invariants 分别冻结单 mutation、普通 `change_group`、import publish chunk、bootstrap item、exchange/bootstrap response 的 soft/hard cap 和固定 envelope 开销，并证明三类最大 canonical bytes 都能装入对应 hard response cap。
   - 合法但超过 soft cap 的单个普通组或 bootstrap item 独占一页。普通 mutation 若可能形成超过 hard cap 的最终组，消费 sequence 并返回 terminal `rejected + SYNC_CHANGE_GROUP_TOO_LARGE`。
   - 导入 item 或 bootstrap 可物化对象若无法装入 hard cap，必须在写入事实或形成冲突前用 typed 容量错误终止，事实、field version 和 group 零写。不能制造不可修改的 Outbox 头或永远无法分页的状态。
2. 服务端允许一个完全匹配已保存 receipt 的重复前缀，随后只能接收从 `highest_client_sequence + 1` 开始的连续新项。
3. 相同 `(account_id, device_id, client_sequence)` 或 `mutation_id` 的 payload hash 不同，返回 `SYNC_SEQUENCE_REPLAY_MISMATCH`，冻结该设备同步且零业务写。
4. 序号跳跃返回 `SYNC_CLIENT_SEQUENCE_GAP`，整个新后缀零写；不靠猜测补洞。
5. 结构、版本、所有权等 envelope 级错误使整批零写。合法普通 mutation 的 `accepted`、`partially_merged`、`conflict`、`rejected`，以及合法导入 begin/item 的 `staged`，都是可重复的终态 wire receipt 并消费对应 sequence；基础设施失败回滚整批且不消费 sequence。`staged` 只证明隔离导入区已耐久接收，绝不表示 canonical 事实已发布。
6. 同一 PostgreSQL 事务写入业务事实、字段版本、tombstone、change、conflict、mutation receipt 和 device highest sequence；提交后才返回。
7. 重新开启同步时必须先以空上传批次追平 pull，再准备本地上传；Contract 不提供绕过此顺序的快捷标志。

每个 `sync.exchange` 还携带 nullable、单调的 `acknowledged_client_sequence_through`。对无effect group的terminal结果，C++在exact ack持久化后可确认；对引用effect group的结果，必须等terminal receipt已保存且该组已由apply或权威bootstrap覆盖后，才把该sequence纳入连续确认水位。Kotlin只原样传输。Backend验证水位不倒退且不超过已发出的highest，将其写入 `sync_device_state.client_confirmed_through`。响应丢失或ack→apply间强杀时水位不会越过待应用效果，因此active device所有 `> client_confirmed_through` receipts及其引用的effect change group必须无限期pin；否则多年后duplicate会建立无法解除的本地gate。已确认receipt/group也至少保留到冻结的180天/retention安全窗后再清。revoked device从撤销时起仍保留全部未确认receipt/effect group至少180天，设备最终清除策略另由保留ADR冻结。

请求只能携带本次 HTTP 开始前已持久化的 ack 水位，不能用本轮 response 经 ack/apply 后的新尾部做隐式确认。`sync_state` 另存 `server_accepted_client_sequence_through` 和派生 `ack_watermark_dirty`；exchange response 回显本事务接纳的 `accepted_client_sequence_through`，C++ 只在 apply 或 ack-only receipt 事务中推进 server-accepted 水位。

Sync request/response 对 normal 与 ack-only 使用严格 `oneOf`。ack-only 请求固定为 `upload_mutations=[] + download_limit=0 + cursor=null + acknowledged...非空`；Backend 只校验 Session、active device 和 ack 单调且不超过 highest，不校验 cursor freshness/generation，也不读 change。响应固定 `mode=ack_only/results=[]/changes=[]/next_cursor=null/has_more=false/cleanup水位=null`；C++ 不得改变本地 cursor、generation 或 cleanup 水位。

当 `has_more=false` 且 Outbox 为空，但 dirty 仍为 true，run 必须继续发送 ack-only，直至 server-accepted 等于本地 ack 或进入耐久 continuation。run success、logout-final 和 active clear-rebuild 都不能越过该门槛。该分支不上传 mutation、不下载 change；policy paused 或旧 cursor 过期时仍允许 receipt housekeeping，除此之外 paused 不运行普通网络同步。强杀后必须恢复 dirty 并继续同一 flush。

逐项结果使用严格 `oneOf`：首次处理的 `status` 为 `accepted/partially_merged/conflict/rejected/staged` 之一，其中 `staged` 仅允许导入 begin/item；完全匹配 receipt 的重放使用 `status=duplicate`，并强制携带 `original_status`、原 terminal result/receipt identity、`client_sequence`、`mutation_id` 和 `payload_hash`。会产生或引用下载效果的普通结果还必须携带 `effect_change_group_id`、该组末序列与 per-key applied/resulting version；纯 staged 或与事实无关的 rejected 对应字段为 null，`SYNC_ENTITY_CONFLICT_BLOCKED` 则引用当前权威 conflict 所在/最新可下载组。duplicate 不是新的业务结果，也不得丢失这些原 conflict/rejected/staged/effect 细节；C++ 在前次响应未落盘时必须能仅凭该分支完成同一 ack。

Upload ack 与 change-group apply 是两个可强杀恢复的本地事务：ack 只终结 Outbox、保存 terminal receipt、更新“已成功应用”的本机 causal anchor，并为尚未本地应用的 `effect_change_group_id` 写隐藏 `awaiting_change_group` entity gate；不得在 ack 中直接发布服务端 entity version、可见 conflict 或 notice。该 gate 下普通 writer 返回 `SYNC_ENTITY_SYNC_EFFECT_PENDING` 且零事实/零 Outbox；随后 `sync.apply_download_batch` 在应用精确组、发布 fact/conflict lifecycle 的同一事务解除 gate。若组已幂等应用，ack 不重建 gate。这样 ack 后强杀、duplicate 或用户立即编辑都不会产生半状态，上传触发的 conflict 仍只在 group apply 时进入 discovery journal并最多提示一次。

普通用户 mutation 或 conflict-resolution mutation 收到“已消费 sequence、但业务零效果”的 terminal `rejected` 时，ack 事务不能只删 Outbox。它必须将 typed intent、merge keys、本机候选或草稿、base/per-key 前驱、failure code 和安全 context 原子转存为 `failed_local_change`；同步事实回到权威 server baseline，并以该记录形成明确“未同步”的 device-local presentation overlay。

`failed_local_change` 不进 Outbox、不自动重传、不推进成功 causal anchor，也不进 Backend/bootstrap。后续 download/bootstrap 先更新 baseline，再按 sequence 重放 pending Outbox 与仍适用的 failed overlay，避免重启或远端变化静默丢输入。

用户可 discard 并重投影 baseline，或基于当前 baseline 另存为新 mutation、新 sequence 和新 hash；同设备因果链继续使用第 7.3 节 no-effect receipt，不能改写旧项。新 mutation 可将被覆盖的旧记录标为 `superseded_pending`，但只有新项取得有业务效果的 terminal+apply 后才清除；再次 rejected 则形成新的可恢复失败记录。Import lifecycle 不进入此表。active clear/destroy 将 failed count 纳入确认，retain-cache 保留记录。

导入commit沿用上述status闭包但有严格typed result：成功为`status=accepted + import_disposition=server_confirmed + publish_group_id/commit_server_sequence/canonical_digest/import_revision`；完整性或领域失败为`status=rejected + import_disposition=repair_required + error/next_revision`，canonical零写；duplicate完整重放原分支。begin/item仍只能是staged。C++在ack同一事务终结commit Outbox并推进batch handle，但server-confirmed绝不等于publish-applied。

### 6.3 下载与 Cursor

- 每个 response 绑定固定 `snapshot_upper_bound`；一页最多 500 个顶层 change group，按其首个 `server_sequence` 升序，并同时受冻结的响应 soft/hard 字节上限约束。单个普通组可以超过 soft cap并独占一页，但绝不能超过机器 invariants 的hard cap。
- exchange每页携带同generation的 `retention_floor_server_sequence` 与服务端UTC `resolved_conflict_cleanup_before`；bootstrap创建时冻结同两水位并在全部页面回显。它们与response/cursor identity一起认证，缺失、倒退或generation不符时客户端只是不做本地清理，绝不用本机时钟补值。
- 普通 mutation/冲突解决产生一个不可拆的 `change_group`：同一 `server_sequence` 下包含有序 `entity_changes[]` 与 `conflict_deltas[]`，二者至少一个非空。`conflict_delta.created`携带完整 unresolved 快照；`resolved`携带 conflict id/version、resolved_at、resolution mode/resulting entity version和最小审计receipt identity。服务端分页绝不拆普通 group，C++ 在一个 SQLite 事务中整组应用；这样页面边界、断网或强杀都不能暴露“事实已变但冲突生命周期未变”的半状态。
- 导入发布是唯一允许跨页的原子可见组：同一 `import_publish_group_id` 的 `import_publish_begin`、typed chunks 与 `import_publish_commit` 占用连续 `server_sequence` 区间并在同一 PostgreSQL commit 中生成。chunk按冻结的 target/order/source-id 稳定排序和canonical byte first-fit规则确定性装箱，每个chunk都必须满足机器 invariants 中的单chunk hard cap；同manifest重试必须生成相同chunk边界/hash，单个item无法装入时commit在canonical零写前稳定失败，不能制造不可下载publish group。Backend分页必须让begin位于新页首、commit位于该组末页尾，组内页面不得夹普通group，前后普通group另起页；snapshot upper bound包含该连续区间的全部或完全不包含。
- C++维护双cursor：`visible_committed_cursor`在begin前最后普通页停住，`import_staging_transport_cursor`随每个已耐久chunk/page receipt推进。Kotlin后续请求只能使用C++成功返回的`next_request_cursor`（组内即staging cursor），不能直接采用HTTP值；收到并验证commit、完整ordinal/manifest/digest后，C++才把整图/冲突与visible cursor一次事务发布并清staging cursor。在此之前普通读取不可见。staging丢失/损坏必须从visible cursor重拉，若低于floor则bootstrap，绝不凭HTTP末尾cursor跳过导入。
- `has_more=true` 时 `next_cursor` 必须前进且页面非空；终页仍返回表示已应用上界的 cursor。
- 普通页只有在业务事实、entity state、conflict、group receipt和visible cursor同一SQLite事务提交后才返回`next_request_cursor`；import中间页只有在staged chunk、page receipt和staging transport cursor同事务提交后才返回。Kotlin永远不直接保存/使用Backend raw next cursor。
- retry 使用旧 cursor 可重放同一不可变 group/chunk；客户端按 `(generation, server_sequence, group identity/hash)` 严格幂等。
- cursor 篡改/形状错误、低于保留下界、跨账号、跨设备、generation 不符分别返回 `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH`、`SYNC_CURSOR_GENERATION_MISMATCH`；只有 expired/generation mismatch 进入全量 bootstrap，其他三类 fail closed，绝不把 cursor 置空后普通重试。正常 HMAC 轮换为每个 key id 记录签发 generation/最大 sequence；旧验证 key 至少保留到所有账号对其签发范围均已推进 retention floor 或 generation，且引用它的 bootstrap session全部过期。只有取得该水位证明后才可删 key，因此长期离线客户端先得到可认证的 expired/generation-mismatch并安全bootstrap，而不会因常规轮换退化为 INVALID；紧急泄露吊销走独立安全事件/显式重建流程，不伪装成普通轮换。
- bootstrap 使用独立 `bootstrap_id`、固定 generation/snapshot upper bound 和 opaque 分页 token。唯一建链顺序是：Kotlin 以 `bootstrap_cursor=null` 请求；Backend 在短事务创建或幂等复用 materialized session/items，并返回服务端 `bootstrap_id`、generation、upper bound、device-sequence recovery bundle 和首/下一页；Kotlin 校验后才调用 C++ `sync.begin_bootstrap` 并写各页。
- materialized item 是 strict union：typed fact after-image/tombstone、无业务 payload 的 `deleted_entity_anchor`、requesting-device causal anchor，以及 snapshot 时全部 unresolved conflict。deleted anchor 携带 target/id/entity version/delete sequence 和 nullable immutable import provenance；排序键固定为 kind/target/id/conflict id/merge key。
- Validator 必须证明各 union 分支单项上限与 envelope 预算，分页只按 item 边界装箱。无法装入 hard cap 的状态在原写入或冲突形成前由 typed 容量门禁拒绝，不能创建无法完成的 bootstrap。未 commit 的 import staging 不进快照；commit 后整图进入同一 materialized snapshot。
- 首响应丢失后，只有 active session 的 generation、device highest 和 client-confirmed 均未变化，才按 `(account_id,device_id,protocol_version)` 复用；否则 null 请求在 device 锁下 supersede 旧 session 并创建新 snapshot。后续请求只携带 Backend 返回的 opaque `bootstrap_cursor`；候选 TTL 为 24 小时，最终由 Sync Protocol ADR 签署。
- 事实、冲突、anchor 和 page receipt 先进入 C++ staging。只有 finalize 完整校验后，才与最终 cursor 和 fresh-DB receipt 确认基线原子发布，并按第 7.3 节重放未确认 Outbox 和仍适用的 failed-local overlay。
- bootstrap session/token 绑定 account、device、protocol、generation 和 upper bound；过期返回 `SYNC_BOOTSTRAP_EXPIRED`，generation 改变返回 `SYNC_BOOTSTRAP_GENERATION_CHANGED`，客户端丢弃未发布 staging 后重新 begin，绝不续用部分快照。
- materialized bootstrap union还必须包含每个已published且`commit_server_sequence <= snapshot_upper_bound`的typed `import_publish_marker`（source workspace/epoch、lineage/batch/publish group/commit sequence/manifest hash、永久mapping digest、snapshot provenance digest/count）。导入生成的canonical事实及其后继版本、tombstone/deleted anchor都保留不可变`source epoch + lineage + source identity` provenance；marker只对同epoch当前snapshot的provenance集合而非旧业务值做digest。C++在同一finalize证明upper bound覆盖commit、所有provenance item完整且digest/count匹配后，先作为server baseline按sequence重放受影响pending与failed-local overlay，再写`publish_applied`；后续编辑不会使旧canonical-value digest失效。更早已创建并被复用的bootstrap没有marker，必须finalize后继续增量取得原publish group，绝不能仅凭`sync.import.status=server_confirmed`清guest。

## 7. Mutation 与字段合并模型

### 7.1 通用外壳

每个 `SyncMutation` 必须包含且只包含：

```text
protocol_version
mutation_id
client_sequence
target_type
target_id
operation_type
base_entity_version
causal_predecessors  // 按 merge_key 排序；每项为最近同设备前驱 client_sequence 或 null
import_lineage_id (nullable)
import_batch_id (nullable)
import_source_workspace_id (nullable)
import_source_epoch (nullable)
import_item_ordinal (nullable)
import_manifest_hash (nullable)
predecessor_batch_id (nullable)
payload              // target + operation 判别的 oneOf
conflict_recovery_snapshot (nullable) // registry裁剪完整after-image，仅用于已清tombstone冲突
created_at           // 客户端事实，仅诊断；不参与顺序
```

`payload` 由 `target_type + operation_type` 判别 strict `oneOf`，所有分支 `additionalProperties: false`。update patch 只带变化字段：缺失为不修改，显式 `null` 仅清空声明 nullable 的字段，空字符串不等于 null。create 使用完整同步事实；delete/restore 使用专用 request，不能使用通用空 Map。普通 mutation 的 import identity 全为 null。

导入批次由 `import_begin`、ordinal 为 `0..total_item_count-1` 的业务 mutation 和 `import_commit` 组成，共享 lineage/batch/source workspace/source epoch/manifest hash。successor 另带 `predecessor_batch_id` 和 nullable strict `takeover_reason=local_evidence_lost|origin_unavailable|ttl_payload_reclaimed`；普通 repair 为 null，只有 `IMP-07` 的不可续传非 published 替换才非空。

`source_epoch` 是 guest workspace 内从 0 开始的 durable non-negative safe integer，只在同 epoch 精确 compare-and-retire 后递增。begin/commit manifest 固定 source identity/epoch/snapshot hash、各 target count、portable preference count、item count、canonical bytes、mapping digest 和 manifest hash；`total_canonical_bytes` 是各 ordinal typed payload 的 RFC 8785 UTF-8 字节数之和，且 begin/commit 完全一致。

successor identity 闭包遵守 `IMP-05`：当前同 epoch 引用图与该 lineage 历史 mapping 的并集，缺失 source 使用 typed delete/tombstone；completed 旧 epoch provenance 不进入新 epoch 删除闭包。Backend 按 `(account_id, source_workspace_id, source_epoch)` 复用永久 lineage，snapshot hash 仅标识 batch。begin/item 只进入隔离 staging 并返回 `staged`；只有 `IMP-03` 原子发布后产生 `server_confirmed`。

“patch只含变化字段”不妨碍独立恢复证据：可能与delete竞争的update/增量operation必须同时携带由C++在同一writer事务冻结、按target registry裁剪的完整`conflict_recovery_snapshot`，并进入canonical hash；create/delete、download-only profile与不进冲突中心的preferences必须为null。Backend正常合并绝不读取它；仅当typed fact/tombstone payload已清、但`deleted_entity_anchor`证明对象曾删除时，用它构造完整local candidate。这样单字段旧编辑也能在第181天执行keep-local/manual restore，而不是猜缺失必填字段。

导入sequence控制分支使用保留的`target_type=workspace_import`，其`target_id=import_batch_id`，`causal_predecessors=[]`：`import_begin`携带lineage/batch/source workspace/source epoch/manifest与nullable predecessor，ordinal为null；业务items使用真实业务target且ordinal必填；`import_commit`重复完整manifest且ordinal为null。只有begin/items/commit进入client sequence且仅允许origin device。`import_takeover`、`import_abandon`与`import_cleanup_confirm`都不进入client sequence/Outbox，固定走第8.1节各自独立HTTP CAS；cleanup confirmation可由同账号任一registered device提交。否则接管/取消可能排在未上传items/commit之后形成死锁，cleanup也会因sequence耗尽、origin revoke或账号库丢失永远无法完成。

`import_begin`在服务端接纳其sequence的同一事务中必须建立完整active sequence reservation：begin后第`1..total_item_count`个sequence分别只允许同batch/manifest的ordinal `0..N-1`，terminal sequence只允许对应`import_commit`。之后generic route在任何duplicate/gap/业务处理前先查reservation；active range内错batch、错ordinal、普通mutation或另一import均返回请求级`SYNC_SEQUENCE_ROUTE_MISMATCH`，零业务/receipt/highest推进，并由Kotlin通过`sync.record_transport_terminal`耐久blocked，不能让错误请求占掉合法ordinal。一个exchange中begin后的items也必须看到刚写入的reservation。reservation只可被commit、confirmed abandon/capacity终态或takeover range-close转换为terminal range，不能因staging TTL直接消失。

### 7.2 原子语义字段组

总计划的“字段级合并”按可独立维护不变量的 `merge_key` 执行。以下字段必须作为同一原子组比较版本，不能逐 JSON key 拆开：

| 目标 | `merge_key` 示例 | 必须共同处理的字段 |
| --- | --- | --- |
| Event | `timing` | `is_all_day`、`start_at/end_at`、`start_date/end_date`、`timezone` |
| Event | `lifecycle` | `status`、`completed_at`、`deleted_at` |
| Event | `recurrence_link` | `has_recurrence`、`recurrence_id`、`recurrence_revision` |
| Occurrence state | `occurrence_state` | `status`、`state_changed_at`、`reopened_at` |
| Anniversary | `date_rule` | `date`、`calendar_type`、`recurrence_id` |
| Habit | `target` | `target_count_hundredths`、`unit` |
| Habit | `lifecycle` | `start_date`、`end_date`、`ended_date`、`is_active`、`deleted_at` |
| HabitCheckIn | `completion` | `status`、`completed_count_hundredths`、`completed_at` |
| Reminder intent | `schedule` | 提前量、local time、timezone mode、method、enabled 状态 |
| Category | `ordering` | `sort_order` 与独立 reorder revision（由 Category ADR 冻结） |

Contract 同时提供机器可读 `sync_field_registry.yaml`，为每个 wire 字段声明：所属 `target_type`、传输方向（upload/download/both）、Schema 类型、nullable、merge key、是否服务端生成、是否允许 create/update/clear、是否敏感、是否进入冲突中心。Backend、C++ validator 和 fixture runner 均消费该 registry；不得在 Java/C++ 复制一份未校验白名单。

### 7.3 同设备因果链

“同一字段冲突”只指不同设备或无法证明因果关系的写入。同一设备离线连续编辑同一 `merge_key` 不得因为前一条刚被 Backend 接纳而与自己冲突：

1. C++每次账号writer仍把事实和Outbox原子持久化，并为每个touched merge key记录同device/target/key最近“已知成功应用”的sequence；若其后有尚未终态的本机链，则记录该pending链尾。因此B在A尚pending时可以稳定引用A，即使A后来被服务端terminal拒绝；已进入prepared/sent的mutation、sequence、payload与hash永不改写。
2. Backend按sequence处理时，有效前驱有两类：其一是相同device/target/key且该key确实应用的receipt或紧凑`device causal anchor`，当前服务端field version必须精确等于其resulting version；其二是同一链上terminal `rejected/conflict` receipt携带的per-key `causal_disposition=no_effect`、`effective_prior_sequence/version`，且该继承基线在处理前一项时已被验证、当前field version仍等于该effective version。第二类只让已冻结的后继越过无效果节点，不推进成功anchor、不把拒绝伪成应用；`staged`与未消费的请求级失败永远不能成为前驱。anchor只在accepted或partially-merged中该key确实应用时推进，保存最近成功sequence/version且不含payload；receipt到期后anchor继续保留。
3. 当前 field version 晚于前驱/effective版本，说明中间有其他设备写入，仍按真实并发生成冲突；前驱指向未来/其他对象/未触及字段、no-effect继承链未验证或链断裂时fail closed。已有 unresolved conflict 的字段仍返回 `SYNC_ENTITY_CONFLICT_BLOCKED`，不得借no-effect指针绕过。C++计算`acknowledged_client_sequence_through`时还必须停在“仍被任一非终态本机Outbox的causal predecessor引用”的最早terminal sequence之前，使Backend继续pin该no-effect receipt；后继终结或新的成功anchor接管后才可跨过。这样A rejected→B离线超过180天仍可验证，不会因普通receipt清理成为永久死链。
4. 同一上传批内的连续写也逐项产生可供后继验证的 receipt；响应丢失后 duplicate receipt必须保留各merge key resulting version。C++可限制单批链深以控制事务，但不能靠重写已发送 mutation实现正确性。

### 7.4 重复规则编辑的三个作用域

R2-C 不新增重复 Event 三作用域编辑 Contract。当前领域规定 `event.update` 对重复 Event 始终修改整个系列；已有 occurrence cancel/complete/reopen 保持各自typed操作。云同步只传输系列定义、不可变revision、已有exception/occurrence state与冲突，不让Backend展开未来occurrence。`update_occurrence/split_future/update_series`及“仅本次/本次及以后/整个系列”UI整体延后到R3，必须先有Event Recurrence专项ADR、领域文档和机器Contract，不能由本同步计划提前激活。

### 7.5 冲突快照、编辑门禁与保留

- `conflict.created`、detail 与 bootstrap snapshot 同时携带 `conflicting_groups[]` 和 immutable `auto_merged_groups[]`。每个auto-merged项只含 `merge_key`、按registry裁剪的accepted typed value/projection、resulting entity/field version；不复制完整原mutation或敏感字段。这样UI能解释“部分已合并”，而不会把已合并值误当待选择候选。
- unresolved conflict显式保存其target/entity与conflicting merge keys，但门禁按整个冲突对象生效。C++对该entity的普通update/delete/restore writer在同一SQLite事务以 `SYNC_ENTITY_CONFLICT_BLOCKED` 零事实/零Outbox拒绝；只有冲突详情中的 `sync.conflict.resolve`（含manual edit）可继续修改。Backend对旧客户端做同样entity级防线：合法envelope仍消费sequence并返回稳定 `rejected + SYNC_ENTITY_CONFLICT_BLOCKED`，事实/field version/change不变。
- 任一 unresolved conflict 引用的 tombstone 都被保留策略 pin住，即使已满180天也不得删除。只有冲突 resolved 后，再同时满足 `resolved_at + 30 days`、原 tombstone retention floor/安全cursor条件才可清；第181天bootstrap仍必须返回该tombstone与冲突，keep-remote/restore都可完成。
- 未被pin的tombstone payload在安全清理后，Backend仍保留不含业务内容的`deleted_entity_anchor(account,target,id,delete entity version/server sequence)`直到账号删除。过期设备bootstrap看不到已清payload时保留本机pending edit；随后上传由该anchor生成Backend id的typed“云端已删除/本机编辑”conflict，keep-remote保持删除，keep-local/manual-edit产生restore新版本。不存在local provisional conflict id，也不得把旧update当create或not-found丢弃。
- `sync.conflict.resolve`虽使用专用HTTP route，仍是占用device sequence的合法mutation。合法envelope下的not-found、version-mismatch、already-resolved或领域校验失败必须作为`status=rejected` terminal receipt消费该sequence，并携带当前conflict/resolved effect group或可重读metadata；duplicate完整重放。C++终结旧resolution Outbox、保留manual草稿并用新sequence/最新expected version重试，不能修改旧payload或让后继sequence卡死。只有auth/protocol/hash/gap等请求级失败不消费。

### 7.6 游客导入的全有或全无与修复谱系

导入不是普通 mutation 的逐条可见复制，而是跨本地双库与服务端的可恢复 publish saga。本节 `IMP-01` 至 `IMP-12` 是导入语义的唯一文字锚点；SQLite/PostgreSQL 表、调用账本、fixture、阶段和完成定义只能引用这些编号。

#### IMP-01：preview、谱系与双库 lease

- C++ preview 冻结源快照和当前 `source_epoch`，并检查 guest-local exclusive source lease。互斥唯一键只使用稳定 `source_workspace_id`；lease 内绑定 epoch，graph/snapshot hash 仅作 compare 字段，guest 编辑不能借换 hash 绕过互斥。
- 同一 `(account_id, source_workspace_id, source_epoch)` 永久复用服务端发现或首次建立的 `import_lineage_id`，并按 `(lineage_id, source target_type, source id)` 生成确定性目标映射。前一 epoch 已 compare-and-retire、但 cleanup 尚未 Native completed/release 时，preview 只返回 `disposition=previous_epoch_cleanup_pending` 和不含账号明文的恢复 handle，不创建新 token、lineage 或 lease。
- commit 的双库 saga 固定为：guest 事务写 `reserved(operation_id, source_epoch, opaque lineage id, protected account-binding digest, snapshot hash)`；account 事务以同 operation 写隔离 staging/manifest/Outbox 和 lease-operation receipt；guest CAS 为 `active(batch_id, manifest_hash, begin/terminal range)`。只有 active 后才可 enqueue 网络。
- reserved 后强杀时，无 matching account receipt 且可证明网络从未可见，owner 才可 CAS 释放；存在 receipt 则幂等补 active。crypto-destroy 走 `IMP-08` 和 `IMP-10`。其他账号、lineage 或 epoch 已持有 reserved/active lease 时返回 `IMPORT_SOURCE_OWNED`，账号 staging/Outbox 零写。account live 事实不提前发布，guest 源和提醒继续唯一可见。

#### IMP-02：服务端隔离 staging

Backend 的 begin/item 在 typed staging 表校验并耐久保存，返回 `staged` receipt 且消费 sequence，但不触碰 canonical 事实、field version、change 或 conflict。相同 batch/ordinal 异 hash 失败；其他设备不得续传。

#### IMP-03：原子 commit

`import_commit` 在锁内验证 manifest、完整 ordinal `0..N-1`、引用图、全部领域约束和 payload digest。任一缺项或非法项都返回稳定 `rejected`，batch 进入 `repair_required` 且 canonical 零写；部分 `staged` 项不算成功。全部合法时，在一个 PostgreSQL 事务内应用整图，生成 field versions/conflicts 和连续 import publish sequence 区间，并保存 `server_confirmed` summary/digest。冲突是整图原子发布后的合法结果，不是半导入。

#### IMP-04：canonical publish 与本机可见性

所有客户端（包括源设备）都按第 6.3 节下载并 staging canonical import publish group，到 commit marker 才原子可见；bootstrap 仅能用同一 upper-bound 验证通过的 `import_publish_marker` 建立等价 `publish_applied` 证据。commit、duplicate 或 status response 只能推进到 `server_confirmed`，不能把原始 local 候选当 canonical。只有本机记录 `publish_applied` 后，才可执行 guest 提醒取消、guest 源清理和 account 提醒协调；每个强杀点均须可继续，不能双提醒或先删 guest。

#### IMP-05：repair successor 与永久映射

- `repair_required` 包括领域/完整性失败和 publish 后同 epoch 的 guest source 变化；它使用新 preview、新 `import_batch_id`、相同 lineage 和 `predecessor_batch_id` 建立完整后继批次。每个 source epoch 同时最多一个可上传非终态批。
- successor manifest 覆盖“当前 guest 同 epoch 完整引用图 ∪ 该 lineage 历史 mapping”，并为已从 guest 删除但曾映射/发布的 source identity 生成 typed delete/tombstone。completed 旧 epoch 的 mapping/provenance 只验证旧 marker；新 epoch 使用新 lineage 和映射命名空间，缺失项不得删除或覆盖旧 target。
- 后继发布事务将旧批标为 `superseded`，或保留其 published 审计终态，同时把 lineage current 指向后继；历史 published 证明不可改写。canonical 零写的失败/abandoned staging 可在安全接管后删除 payload，batch/ordinal receipt 至少保留 180 天；紧凑 epoch→lineage 和 source→target 映射保留至账号删除。

#### IMP-06：status 查询与状态闭包

- 带 `batch_id` 时精确返回该批当前状态，包括终态和必要 current-head 指针；不带 batch 时，以 `source_workspace_id + source_epoch + target workspace` 只发现仍需恢复的 handle。不存在时返回严格 empty union，不能拿 completed 旧 epoch 冒充 current；`source_snapshot_hash` 仅为可选精确筛选。Kotlin 将 HTTP 结果交给唯一 Method/Native `workspace.import_status`。
- `stage` 只允许 `local_staging/server_staging/repair_required/server_confirmed/publish_applied/cleanup_pending/completed/superseded/abandoned`；`failed` 属于 `NativeResult/ApiResult`，不改变 stage。
- 三个正交字段分别为 `abandon_status=not_requested/pending/confirmed/unconfirmed/not_applicable`、`reconciliation_status=not_required/full_successor_required/cleanup_recovery_required`、`resume_disposition=none/resume_upload/resume_publish/close_range_then_successor/create_successor/resume_cleanup/terminal`。
- 无谱系时，`stage=null`，三个正交字段为 `not_applicable/not_required/none`，batch/head/revision 均为 null；有谱系时，batch/lineage/source epoch/head/revision 必填，proof/predecessor/publish/cleanup 字段只在对应 disposition 下出现。离线取消为 pending，网络结果不确定为 unconfirmed，二者都不能启新 batch。
- 状态可跨账号内设备发现，但 ordinal 续传只允许原设备；原设备 revoked 或 fresh lifecycle 丢失证据时，先按 `IMP-07` 关闭旧 range，再在同 lineage 完整 restage successor。commit 响应丢失、销毁后重登、bootstrap 或保留缓存恢复都先按稳定 source workspace id + epoch 发现，不能新建 lineage 制造重复。

#### IMP-07：takeover 与 range-close proof

- current 非 published 批的 origin revoked、同 origin fresh lifecycle 丢失 manifest/ordinal/mutation 证据，或 reconciliation staging payload 被 TTL 回收时，客户端以 current revision 调独立 HTTP `sync.import.takeover`，不能直接建新 Outbox。
- Backend 按全局锁序与旧 commit 仲裁，返回 strict `ImportRangeCloseProof` oneOf。`seen_range_closed` 表示 begin reservation 已转为 virtual terminal no-effect range，origin highest 推进到 terminal；`never_visible_after_transport_fence` 只在第 6.1 节 fence 已关闭旧 transport generation、且服务端从未接纳任何相关 sequence 时产生，它不推进 sequence，并绑定 fence operation、resulting generation 和权威 sequence bundle。
- takeover 先赢时旧批标为 `superseded(reason=evidence_lost|origin_unavailable|ttl_payload_reclaimed)`，旧 receipt 保留，迟到 ordinal/commit 先命中 batch/range fence 并返回 `IMPORT_BATCH_SUPERSEDED`。旧 commit 先赢返回 `already_confirmed`；revision 竞态返回 `IMPORT_VERSION_CONFLICT`。
- Kotlin 先将 proof 交 `workspace.import_accept_range_close` 原子落盘。当前 device 的 `seen_range_closed` 终结 matching Outbox range、推进 ack 基线、标 dirty 并采用 proof allocator；其他 origin 只更新 lineage head/revision。`never_visible_after_transport_fence` 只适用于旧 runtime 已冻结/销毁的 fresh lifecycle，不能给仍含旧 generation 普通 Outbox 的保留库挪洞。
- proof 接纳和必要 ack-only 均需跨强杀恢复，完成后才能按 resulting revision 创建 successor。sequence 或 generation 耗尽时保持只读 blocked；fresh lifecycle 在 fence、status/range-close 恢复完成前禁止普通 writer 分配 sequence。reconciliation successor 的 TTL 只能回收 payload，不能把 lineage 标为 completed/abandoned。

#### IMP-08：隐私销毁与 abandon

- 非终态导入不能阻止隐私删除。`clear_account_cache` 或 logout `destroy_now` 先提示导入将中止；在线 best-effort 调 `sync.import.abandon`，但二次确认、安全事件或 30 天到期立即 crypto-destroy，不等待网络。结果只用 `abandon_status=confirmed/unconfirmed/not_applicable`，unconfirmed 不得宣称导入成功。
- 已有 active reservation 时，confirmed abandon 在 origin-device + lineage 事务内转为可重取的 `seen_range_closed`。batch 尚不存在时，Backend 校验 manifest/count/bytes/range/origin generation，并写不消费 sequence 的 `absent_batch_fence`：begin 恰为 highest+1 且范围合法时可原子建批并关段；有前序 gap 时只返回 `proof=null + sequence_advanced=false`。
- generic replay/route 检查前先查 identity fence。matching 迟到 begin/item/commit 要么在 begin 成为合法 next 时原子关段，要么返回 `IMPORT_BATCH_ABANDONED` 且零 receipt/零 highest；其他 receipt 已占 sequence 时也不能误冻设备。
- 保留库离线取消只标 pending 并保留 range；联网后补齐前序并重复 abandon，取得 proof、Native 接纳和 ack-only 后才可复用后继序号。隐私销毁可留下 unconfirmed/absent fence；未来登录先做 transport fence，再由 Backend 对旧 generation 的零 receipt fence 产生 `never_visible_after_transport_fence`，之后 fresh allocator 才能按 server next 恢复同 lineage successor。
- commit 先赢则转入发布。带未 cleanup predecessor 的 reconciliation successor 不允许普通取消；privacy destroy 可停止本机，但未来仍按 lineage 恢复。

#### IMP-09：guest 退休、审计图与 epoch 推进

- 仅 `publish_applied` 后可清 guest。guest 单一 `BEGIN IMMEDIATE` 事务重算整张引用图的 snapshot hash/count/version/epoch；只有匹配 lineage current published head 才退休整个 live 业务图，并写不含账号身份的 `guest_import_cleanup_receipt(source_epoch,lineage,through_published_batch_id,through_import_revision,source_snapshot_hash,mapping_digest)`。
- epoch 未到 safe-int 上限时，同事务递增 durable source epoch 并置 `previous_epoch_cleanup_pending=true`；达到上限仍完成退休和 receipt，置 `source_epoch_exhausted=true`，旧 epoch 仍可 cleanup/释放 lease/切换提醒，但之后 preview/commit 返回 `IMPORT_SOURCE_EPOCH_EXHAUSTED` 且零 lease/staging。
- 退休后的 guest 新写可继续本机保存；旧 receipt 未经 HTTP + Native completed 并释放 lease 前，新 preview 只返回 previous-epoch-pending。post-commit 源变化使本次零退休、epoch 不进，并按同 epoch/lineage 建完整 successor。
- cleanup-confirm 使用 source epoch 和 exact disposition；C++ 原子标 completed、解除匹配 preview gate 并允许释放 lease。owner-bound authenticated account-deleted proof 由 `workspace.import_finalize_source_lease` 在同一 guest 事务释放 lease、终结旧 cleanup receipt/gate且不回退 current epoch。账号库丢失但账号仍存在时必须重登补正常 confirmation；旧 lineage 不得触及新 epoch 数据。
- Notification、真实 Reminder、Alarm/Work、Ring/Recovery 和 Search History 不复制到账号。非终态 guest Reminder 与 prepared Notification attempt 分别以不可恢复的 `source_migrated` reason 终结，迟到 finalize 零写；Kotlin 只取消事务返回的 workspace-bound affected identities。
- 终态 Reminder/Notification 和领域审计历史留在 guest 分区，不改挂 account。SQLite v6 必须唯一冻结紧凑 migrated audit anchor 或等价不可见表示，保证引用不悬空、普通查询不见已迁出事实、无业务 payload 的 anchor 不进入后续 manifest。Search History 仅含规范化关键词，继续归 guest 且不参与导入。

#### IMP-10：source lease 释放闭包

active guest source lease 跨账号切换、logout、active clear、30 天到期、device 换号和强杀保留，proof/receipt 均绑定 source epoch。仅以下三类证据允许释放：

1. 该 epoch 从未 published，Backend 已 confirmed abandon，且残留 Outbox 已 terminal 或存在匹配 crypto-destroy final receipt。
2. 该 epoch 整条 lineage cleanup-confirm 已由 Native 落为 completed，并同时解除 previous-epoch preview gate。
3. Backend 权威 account-deleted receipt 与 protected owner binding 匹配，并按 `IMP-09` 同事务终结旧 cleanup receipt/gate。

destroy proof 不能替代 confirmed abandon；unconfirmed abandon、普通 logout/revoke/session expiry/refresh reuse/account mismatch、TTL 回收或本机文件缺失都不能猜测释放。V1 不支持跨账号转移 active lease；完成旧 epoch 后可为新 epoch 重取 source lease，但不得复用旧 lineage/mapping 删除闭包。

#### IMP-11：容量边界

- 初始上限为每 batch 50,000 items/128 MiB canonical bytes；每账号最多 2 个非终态 batch，active staging 合计 100,000 items/256 MiB；同 source 最多一个可上传 batch。单批必须覆盖总计划 20,000 条组合事实展开后的全部 item，实测不足则 B0 阻止冻结，不能截断。
- C++ 在分配 begin sequence 前按实际 typed items 计算 `total_canonical_bytes`；本地可证明超限时，账号 staging/Outbox 零写。Backend 在账号锁内复核 manifest 并预留容量；超限 begin 只写最小 capacity-rejected batch/range tombstone 和 terminal rejected receipt、消费该 sequence，不接纳 staging/canonical，后续已排 items/commit 稳定 rejected/no-op。
- 每个 item 累加实际 canonical bytes。少报、累计超声明或超限时，当前 item terminal capacity-rejected，剩余 range 转 no-effect tombstone；commit 复算数量/字节并须与 manifest 完全一致。status/abandon/takeover 可命中该终态。上限变更必须走正式 Contract revision 和五层 fixture。

#### IMP-12：sequence reservation 保留

`import_begin` 保存并 checked 推导完整 range，guest active lease 和 account operation receipt 同样保存。Backend 为 active batch 保留 route reservation；已有 begin reservation 的 abandon/supersede/capacity/TTL early terminal 转为 virtual no-effect terminal range 并推进 highest。

batch absent 时，只有完整 manifest/range 合法且 begin==highest+1 才可原子建立并关闭 range；否则只建持久 `absent_batch_fence` 且不推进 highest，等待前序补齐，或等待 transport fence 证明旧 generation 永不可提交并产生不消费 sequence 的 never-visible proof。首次与重复响应返回或可重取同一 proof/disposition。

compact terminal range、absent fence 和 receipt 在 origin confirmed-through/fence lifecycle 满足清理条件前不得删除。matching 迟到请求先命中这些状态并返回 `IMPORT_BATCH_ABANDONED|IMPORT_BATCH_SUPERSEDED`；非 matching mutation 才进入普通 receipt/route/replay。保留 runtime 只凭 `seen_range_closed` 终结 matching range 并发 ack-only；`never_visible_after_transport_fence` 只用于旧 runtime 已冻结的 fresh lifecycle，不能删 Outbox 后猜 allocator、复用缺口或伪造逐项 receipt。

### 7.7 V1 目标类型闭包

| `target_type` | 同步事实 | 特殊约束 |
| --- | --- | --- |
| `category` | name、description、color、icon、sort、tombstone | 保留业务对象中的 opaque weak reference；新 Category 自身使用 UUIDv4；生命周期以新 ADR 为准 |
| `event` | Event 稳定字段和生命周期 | 时间四字段完整出现；服务端不派生展示状态 |
| `event_recurrence` | immutable recurrence revision | `(recurrence_id, revision)` 稳定；不覆写旧 revision |
| `event_occurrence_state` | 单次 occurrence 状态/例外 | 身份包含 event、revision、occurrence key；不污染 series status |
| `anniversary` | date-only Anniversary 稳定字段 | 不新增持久化 timezone；农历仍保持当前未实现边界 |
| `anniversary_recurrence` | 专属 yearly rule | 不复用 Event Recurrence；V1 固定 `yearly + interval=1` |
| `habit` | Habit 定义与生命周期 | 数量使用 `_hundredths` safe integer；统计不上传 |
| `habit_recurrence` | 专属 daily rule | 不复用 Event/Anniversary recurrence |
| `habit_check_in` | 当地日期事实、快照、来源、tombstone | 原始 `source` 保持 manual/action，不因传输改成 sync；增量另带 operation identity |
| `reminder_intent` | Event/Anniversary/Habit 的用户意图/模板 | target-specific `oneOf`；不上传 Reminder 调度状态或 Notification；V1 禁止 wechat |
| `user_preferences` | 白名单可移植设置 | 初始仅 `timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 ring/popup）与 `auto_enable_reminders_on_other_devices`；按服务端接收序列 LWW，不进业务冲突中心 |
| `account_profile` | email、username、display_name、头像引用的安全投影 | **仅服务端产生、客户端下载**；写入继续走邮箱验证码、`user.update_current` 和头像专用 API，不允许客户端构造该 target 的 upload mutation |

`Notification`、实际 `Reminder`、Alarm/Work、RingSettings、搜索历史、权限、附件、AI、微信、Widget 和游客数据必须出现在 validator 的负例中，证明无法构造上传 mutation。

`timezone`、颜色和账号默认提醒策略的唯一同步 owner 是 `user_preferences`；`account_profile` 不复制这些字段。V1 Flutter只有`zh-CN`，所以`locale`不在同步白名单：现有Backend/DTO中的locale只作为升级兼容输入保留和审计，新`preferences.update`、`user.update_current`与Sync mutation均不得写它，也不产生locale change。当前active `registration_request`仍要求locale，兼容revision只接受固定`zh-CN`并创建同值历史字段；Flutter不得展示选择器，Backend不得把这次初始化发布为可同步偏好变化。只有第二个locale完成真实本地化并另行修订Contract后才能加入。`user.get_current` 可以聚合返回 profile 与 preferences，但两个部分必须分别携带 revision。资料 API 成功写入时，Backend 在同一 PostgreSQL 事务递增 `account_profile_revision` 并追加一条安全投影 change；邮箱变更只有验证码确认成功后才产生 change。

`auto_enable_reminders_on_other_devices` 的 V1 精确含义是“未来注册的新设备是否默认开启本机提醒”，默认值为 `false`；账号首台设备无论该偏好初值如何均以 `receive_reminders=true` 注册，后续设备按注册事务读取的偏好初始化。偏好变化只影响未来设备，不批量改写既有设备；设备注册完成后，是否物化 Android 提醒仅由该设备的 `receive_reminders` 与系统能力决定，远端 reminder intent 始终下载。Contract 不引入“原始创建设备”隐式例外。

`default_reminder_methods`冻结为有序、无重复、长度`0..2`的enum数组，顺序必须跨Backend→C++→Kotlin→Flutter原样保留。它只为新建草稿选择第一个合法候选，真实Reminder仍恰好一种method：

| 目标 | 合法默认候选 |
| --- | --- |
| 非全天、非重复 Event | `ring`, `popup` |
| 全天、非重复 Event | `popup` |
| 非全天、重复 Event | `popup` |
| 全天、重复 Event | 无（当前领域不支持Reminder） |
| Habit / Anniversary | `popup` |

如果偏好与目标合法集合无交集，UI不自动预选/创建Reminder；用户可显式选择该目标允许的方法。任何层都不得静默回退到popup、把`[ring,popup]`写成真实Reminder、因无默认值阻止保存无提醒对象，或在偏好变化时修改/reconcile既有Reminder。机器交付固定为`contracts/reminder/default_reminder_method_applicability.yaml`并由所有创建入口fixture引用。

同步的`user_preferences.timezone`与本机`device_timezone`是两条轴。前者是workspace Event展示/范围查询与新建定时Event的默认候选，创建workspace时仅可从OS时区播种一次；后者由Kotlin从OS IANA timezone注入，供Habit/Anniversary当地日期和`follow_device` Reminder计算，永不上传。混合Calendar/Search Native查询若同时需要两者，字段固定命名为`workspace_timezone`与`device_timezone`，其中workspace值由C++读取当前workspace偏好、device值由Kotlin注入；Flutter不得用一个`timezone`覆盖两者。workspace timezone变化只使Event投影/文案失效，不重排follow-device Reminder；OS timezone变化才触发Habit/Anniversary投影与其open Reminder reconcile。

升级前的全局 `appearance.*_local` 值归属 guest workspace：Kotlin 以一次性、带版本回执的迁移写入 guest `habit_progress_color`，绝不自动归给第一个登录账号。只有用户明确执行 guest→account 导入时，导入 manifest 才可声明 `portable_preferences_count=1` 并把该颜色作为可审计项复制到账号；timezone和其他账号偏好不从全局历史值猜测，locale不属于V1可移植偏好。

## 8. 跨层接口基线

以下名称是本计划的冻结目标。达到 `CONTRACT FROZEN` 前均为 `planned`；若 ADR 改名，必须在同一变更中更新五份分计划和全部映射表。

### 8.1 Backend API（`ApiResult<T>`）

统一 base path 为 `/api/v1`。需要账号能力的请求，其账号身份只来自 bearer Principal；除既有公开注册端点与下表无账号语义的`system.time`外，请求不得包含可伪造的 `account_id`/`user_id`。

| Operation key | HTTP | Path | Request 核心参数 | Response data | 幂等/授权 |
| --- | --- | --- | --- | --- | --- |
| `system.time` | GET | `/system/time` | 空 | `ServerTimeResponse{server_time}` | 唯一新增的无bearer端点；HTTPS、按IP有界限流、`Cache-Control: no-store`，不读写账号/Session/Device/数据库；响应生成时的UTC只作为当前时间下界与缓存到期判断，不作为同步并发时钟 |
| `auth.reauthenticate` | POST | `/auth/reauthenticate` | `current_password`, `purpose=device_revoke`, `target_device_id` | 短期 `reauth_token`, `expires_at`, `purpose`, `target_device_id` | bearer；绑定当前 session、actor device（pending registration 时可空）、attempted installation 摘要与目标设备，单次消费；不记录密码/token；5 分钟候选 TTL 由 ADR 冻结 |
| `device.register` | POST | `/devices` | `installation_id`, `display_name`, `platform`, `app_version`, `protocol_version` | `DeviceResponse`，含transport generation、highest、nullable next、client-confirmed与sequence-exhausted严格分支 | bearer；同账号 active installation 幂等；revoked 记录不复活；第 11 台失败并建立受限 pending-registration 状态 |
| `device.list` | GET | `/devices` | 空 | `DeviceListResponse`，含 `registration_pending` 与 nullable `current_device_id` | bearer；只列当前账号；pending-registration 恢复流可调用 |
| `device.rename` | PATCH | `/devices/{device_id}/name` | `display_name`, `expected_device_version` | `DeviceResponse` | bearer + CAS |
| `device.update_settings` | PATCH | `/devices/{device_id}/settings` | typed patch：`receive_reminders` / `sync_enabled` 至少一项，另带 `expected_device_version` | `DeviceResponse` | 仅当前设备可改；服务端 `sync_enabled` 是最后上报的诊断镜像，本机 C++ 状态才决定是否调度同步 |
| `device.revoke` | POST | `/devices/{device_id}/revoke` | `expected_device_version` | `DeviceRevocationResponse` | bearer + reauth header；V1 只撤销其他设备；同时撤销其会话 |
| `sync.device_fence` | POST | `/sync/device-fence` | `device_id`、`fence_operation_id`、`expected_sync_transport_generation`、`reason=clear_rebuild/fresh_recovery/force_local_relogin` | strict receipt：resulting transport generation、highest/nullable-next/client-confirmed/exhausted sequence bundle、resolved absent-import fences | bearer + registered device；Session→device→sync-state锁内幂等checked increment；同operation重放原结果，旧generation请求从此零写 |
| `sync.exchange` | POST | `/sync/exchange` | normal含protocol/device/`sync_transport_generation`/cursor/download limit/receipt ack/ordered uploads；ack-only严格为uploads空、download limit=0、cursor=null、ack非空 | normal为ordered download union + cursor + 两个cleanup水位 + accepted ack；ack-only为empty results/changes、null cursor/cleanup水位 + accepted ack | 同步专用sequence/receipt；冲突生命周期同cursor传播；ack-only不校验cursor freshness/account generation但仍验证Session与transport generation，只推进确认水位 |
| `sync.bootstrap` | POST | `/sync/bootstrap` | protocol/device/`sync_transport_generation`/null-or-page cursor/page limit | identity、fact/tombstone/deleted-entity-anchor/conflict/import-marker/requesting-device-anchor union、next/final cursor、冻结transport+cleanup水位与device-sequence recovery bundle | 首请求创建/复用active session；全部恢复证据同快照；旧transport generation不得创建/续页 |
| `sync.import.status` | GET | `/sync/imports/status` | nullable `import_batch_id`，或`source_workspace_id + source_epoch + nullable source_snapshot_hash`；epoch来自guest current epoch或旧cleanup receipt/opaque recovery handle | 该epoch最近谱系/manifest revision/expiry/abandon disposition、resume/takeover要求、origin及begin/terminal sequence range；published时含publish group id、commit server sequence、canonical digest与cleanup状态；无谱系为none | bearer + registered device；元数据只供恢复，不能单独证明本机publish-applied；不得省略epoch或把completed旧lineage当current；只有原设备可续传旧ordinal |
| `sync.import.takeover` | POST | `/sync/imports/{import_batch_id}/takeover` | `sync_transport_generation`、lineage/source workspace/source epoch/完整manifest/count/bytes/origin、begin/terminal range、`expected_import_revision`、严格takeover reason | `disposition=range_closed/already_range_closed/already_confirmed`；range-closed返回防篡改`ImportRangeCloseProof` oneOf、resulting lineage revision与origin device transport/sequence bundle；stale CAS为`IMPORT_VERSION_CONFLICT`并附current stage/head/revision | 独立lineage+origin-device sequence CAS，不占调用设备client sequence；`local_evidence_lost`只允许caller=origin，`origin_unavailable`只在Backend权威确认origin revoked（若未来支持同installation换号还须冻结绑定证明）时允许，`ttl_payload_reclaimed`只接受已持久化TTL终态/内部Scheduler，外部不能自报；失败零写；先关闭旧range并接纳Native proof，之后才允许创建successor |
| `sync.import.abandon` | POST | `/sync/imports/{import_batch_id}/abandon` | `sync_transport_generation`、`import_lineage_id`、`source_workspace_id + source_epoch`、完整manifest/count/bytes/range/origin generation、nullable predecessor batch、expected import revision、reason | strict oneOf：`abandoned/already_abandoned`在Backend已有/可合法建立begin reservation时携`seen_range_closed` proof + transport/sequence bundle；有gap则`proof=null + sequence_advanced=false`并持久化absent fence；旧generation经device fence后可取`never_visible_after_transport_fence` proof；`already_confirmed`携publish/lineage metadata；stale为`IMPORT_VERSION_CONFLICT + current stage/head/revision` | bearer +当前账号registered device；独立CAS/幂等且按全局锁序与commit/TTL仲裁，不占调用device sequence；不得凭客户端自报range跨gap推进highest；已有未cleanup predecessor不得终结reconciliation successor |
| `sync.import.cleanup_confirm` | POST | `/sync/imports/{import_lineage_id}/cleanup-confirm` | `sync_transport_generation`、source workspace/source epoch、through published batch/revision、source snapshot/mapping digest、guest cleanup receipt hash、expected lineage revision | `disposition=cleanup_confirmed/already_cleanup_confirmed` + resulting lineage revision/confirmed-through；stale CAS为`IMPORT_VERSION_CONFLICT`并附current stage/head/revision | bearer +任一当前账号registered device；独立lineage CAS/幂等、不占client sequence；同一epoch/through终态先幂等返回，其他revision不符零写；原子确认该epoch连续published predecessor chain |
| `sync.get_status` | GET | `/sync/status` | 当前 `device_id` query | `RemoteSyncStatusResponse` | 诊断读取；不代替本地状态 |
| `sync.conflict.list` | GET | `/sync/conflicts` | status/type/cursor/page_size | `ConflictListResponse` | 稳定排序与 opaque cursor |
| `sync.conflict.get` | GET | `/sync/conflicts/{conflict_id}` | 空 | `ConflictDetailResponse` | 当前账号所有权 |
| `sync.conflict.resolve` | POST | `/sync/conflicts/{conflict_id}/resolve` | `device_id`, `sync_transport_generation`, `client_sequence`, `mutation_id`, `expected_conflict_version`, resolution | `ConflictResolutionResponse` | 复用同步 sequence/receipt；锁内重验Session/transport generation；解决产生新 entity version/change |

`sync.conflict.resolve` 是同步序列中的单项命令，不得绕过 device ordering。C++ Outbox 遇到该 mutation 时将其作为单项 route；Kotlin 串行发送并用普通 `acknowledge_upload` 落本机终态。

`DEVICE_LIMIT_REACHED` 不能造成“未注册所以无法清理设备”的死锁：

- Backend 在失败事务后建立只含账号、当前 session 和 attempted installation 摘要的 `pending_registration`；Broker 加密持久化相应 session/account/RT/installation 摘要，并向 MethodChannel 投影 `registration_pending`，使进程重启可恢复。
- 该状态只授权 refresh/logout、`user.get_current`、`device.list`、针对明确旧设备的 `auth.reauthenticate`、`device.revoke` 和相同 installation 的 `device.register`。Sync、资料/偏好写、账号 workspace open 及其他业务 API 默认拒绝。
- 此模式 reauth grant 可有 `actor_device_id=null`，但仍绑定 session、installation 摘要、target device 和 purpose。
- Flutter 没有 register 方法。Broker 恢复 pending 且联网时先幂等 register，覆盖 revoke 已提交但响应丢失或调用后强杀；仍超限才展示列表。pending 下 revoke 无论明确成功或结果不确定都销毁 grant，并立即或恢复后用持久 installation/规范化名称重试。结果仅为 registered（binding/seed 已接纳）或 still_limited；后者重新 list/reauth，不依赖旧 AuthenticationResponse 或临时值。

Session注册三态采用中央 capability矩阵，默认拒绝：`unregistered`（首次登录、尚未尝试register）只允许 refresh/logout、`user.get_current`、`device.register`，不允许device list/reauth/revoke；`pending_registration` 才增加device list/target reauth/revoke，并只准相同installation重试register；`registered` 才按普通endpoint授权开放业务能力。`unregistered` 没有attempted-installation绑定，不得签发 actor-null reauth grant。新增Backend endpoint若未显式归类，在前两态一律拒绝。

`system.time`不属于上述账号capability矩阵，也不能据此探测Session或设备状态。它只返回exact-key的UTC`server_time`，无请求body、cookie、账号标识或可变业务字段；客户端只能把合法HTTPS响应作为保守时间下界，超时、缓存响应、非法时间或时钟倒退均不得授权销毁。

默认设备名由 Kotlin 生成、Backend 校验：对 `Build.MANUFACTURER + Build.MODEL` 做 Unicode trim、连续空白折叠，model 已含 manufacturer 前缀时不重复，空值回退本地化的“Android 设备”，并按 Unicode code point 安全截断到 64；wire `display_name` 必须为 1..64 个 code point。Backend 不读取或派生硬件标识。

Backend `DeviceListResponse` 仍是纯远端快照；MethodChannel `device.list` 是明确的 Kotlin组合投影，不得把两者误当同一Schema。它返回 `remote_snapshot_state=fresh/stale/unavailable`、nullable `remote_snapshot_at`、脱敏remote devices，以及 nullable `current_device_local_settings`（正式绑定时必须有）：`receive_reminders`、C++权威 `sync_enabled`、`settings_remote_pending`、`local_settings_revision`。离线冷启动只可从账号/工作区绑定的加密缓存返回stale快照：可放入SQLCipher账号库，或用独立account-scoped Keystore AEAD并以account/workspace/schema作AAD；普通SharedPreferences/Workspace Registry只能留`freshness/schema/cache-present`等无内容索引，绝不明文保存display name、平台或活动时间。A退出或切换B后A快照不可查询/解密；destroy/revoke/clear按同一crypto生命周期立即清除。从未成功读取远端时remote devices为空且state=unavailable，不伪造“没有其他设备”。`registration_pending`无current local settings且管理动作要求在线。

HTTP `device.update_settings` 可在Backend单事务合并两个字段，但同名MethodChannel为严格`oneOf`，每次只改`receive_reminders`或`sync_enabled`一个本机owner字段。Kotlin先在加密、workspace/device绑定的lifecycle journal原子写`operation_id + desired value + expected_local_settings_revision + expected_sync_policy_revision`，再幂等完成C++ policy CAS或Registry reminder写，最后推进combined `local_settings_revision`并写remote-pending reporter记录后才返回`local_saved`；任一强杀点按operation id续做，不能半保存或丢远端镜像。Reporter可把多个已完成本机操作合并成一个HTTP patch，但不得改变各字段owner。

既有 `user.get_current`、`user.update_current`、`user.avatar.upload/delete` 与邮箱修改 API 继续作为资料写入入口，但须冻结以下联动：`user.update_current` 只允许 `username/display_name`；timezone、颜色与提醒默认迁移到 `preferences.update`，locale用户更新在V1关闭并只保留兼容读取/审计，注册仅接收固定`zh-CN`兼容常量。所有成功响应携带 `account_profile_revision` 和 `preferences_revision`。资料、头像或已确认邮箱更新必须与 `account_profile` change 原子提交。`sync.exchange/bootstrap` 下载该 change，上传 validator 对 `target_type=account_profile` 一律拒绝。

### 8.2 Flutter ↔ Kotlin MethodChannel（`NativeResult<T>`）

| Method | Kotlin 实现路径 | Request / Result 要点 |
| --- | --- | --- |
| `auth.session.adopt` | SessionCredentialBroker | 输入完整且严格校验的 `AuthenticationResponse`；Broker 先以 access token 调权威 `user.get_current` 交叉校验 identity，再调用 `device.register` 绑定当前 session，最后原子接管 token pair + account/device binding；不回传 Refresh Token |
| `auth.session.get_access_token` | Broker single-flight refresh | `minimum_validity_seconds` + nullable `rejected_access_token_generation` → access token、expiry、session id、`access_token_generation` |
| `auth.session.get_status` | Broker | 七态 + nullable safe-integer `session_generation`（empty为null）；registration_pending含能力标志但不含device/token，供pending logout CAS |
| `auth.session.logout` | Broker + Backend | discriminated oneOf：active首次以`mode=server_then_local + final_sync_policy=attempt_once`携带expected session generation与observed route tuple，Broker建立耐久logout operation、阻写session-bound账号lane并内部final-sync；风险/失败返回`review_required`及opaque operation id、risk revision、精确pending/failed/import快照。重试、`skip_after_confirmation`或`cancel_after_review`必须引用同operation/revision；skip仍调用server logout。只有已得到`server_logout_status=unreachable`的同operation才接受二次确认后的`mode=force_local`，且不声称服务端终止。pending态route/final-sync/review字段必须null并只带expected session generation；请求含`cache_policy=retain_30d/destroy_now`，review/不可达投影含严格`allowed_cache_policies`。服务端`succeeded/already_invalid`终态必带UTC `server_time`，本地结果返回typed cache/clock状态 |
| `auth.session.clear_local` | Broker | Kotlin 派生的终止 reason，或 Flutter 已确认的 `user_requested_destroy` → typed cache action、nullable retained-until、`retention_clock_state`、cleanup/lifecycle revision |
| `auth.session.reauthenticate` | Broker + Backend | password + purpose + target device id → Kotlin 内部 reauth grant id；Flutter 不持有 server reauth token |
| `workspace.get_state` | WorkspaceCoordinator | 恢复型只读请求不要求expected CAS，可带nullable `known_active_route_revision`仅作诊断；始终返回下述`ready/locked/empty`严格union、route revision、可见统计及nullable active import handle/revision，不暴露目录/密钥别名；切换线性化前返回上一个稳定union，期间mutating调用以`WORKSPACE_SWITCH_CONFLICT`拒绝，不公开第四种半切换状态 |
| `workspace.list` | WorkspaceRegistry | 仅 local + 当前已认证且可解锁账号；其他账号保留缓存完全不可见，只供 Kotlin 内部到期清理索引使用 |
| `workspace.activate` | WorkspaceCoordinator | target `workspace_id + expected_active_route_revision`；串行 close/open/switch并推进route revision |
| `workspace.import_preview` | Kotlin → C++ | source/target workspace + expected active-route revision；ready分支返回稳定source epoch/snapshot、C++生成的`proposed_import_batch_id`/lineage、实体数量、mapping/manifest digest、提醒影响和preview expiry；前一epoch未completed时返回`previous_epoch_cleanup_pending`恢复handle且不生成新token/id |
| `workspace.import_commit` | Flutter → Kotlin协调器 → C++ | `preview_token`, `import_batch_id`, target workspace + `expected_active_route_revision + expected_import_revision`；首批只允许revision 0，普通repair必须等于status current；takeover分支由Kotlin先完成独立HTTP range-close与Native proof接纳，再以resulting revision调用C++冻结manifest/ordinal；账号副本在publish-applied前抑制提醒物化 |
| `workspace.import_status` | Kotlin HTTP + C++ | workspace + expected active-route revision，batch id可空；始终携guest current/receipt source epoch，按source/epoch/target发现或恢复唯一active handle，合并server staging/terminal与本地manifest/hash/提醒切换状态 |
| `workspace.import_abandon` | Kotlin HTTP + C++ local state | workspace + expected active-route revision、batch/lineage + expected import revision；Kotlin调用独立HTTP后把typed disposition交C++，离线privacy destroy返回unconfirmed；不建Outbox/不占sequence |
| `workspace.clear_account_cache` | Kotlin lifecycle | session绑定账号专用：`workspace_id + expected_session_generation + observed_active_workspace_id + expected_active_route_revision + expected_lifecycle_revision + confirmation_id`，workspace必须匹配Broker账号binding但前台可为该账号或local；先处理非终态import、阻写并收敛normal/ack-only，再在线执行`sync.device_fence`且让C++接纳，之后才close/crypto-destroy/fresh-open/bootstrap/import recovery；会话保持active，游客workspace本身不可清 |
| `sync.get_status` | Kotlin 聚合 C++/Worker/Broker | UI 完整同步状态和未解决冲突数 |
| `sync.claim_conflict_notice` | Kotlin → C++ local state | 展示前以exact head notice id/sequence原子claim；返回claimed/no-longer-actionable + 新状态，零Outbox |
| `sync.export_diagnostics` | Kotlin + C++ safe snapshot | workspace + expected active-route revision → 生成脱敏JSON并打开系统分享；结果只含 export id/hash/生成时间/处置，不返回路径或payload |
| `sync.set_enabled` | Kotlin → C++ + WorkManager | `workspace_id + expected_active_route_revision + enabled + expected_sync_policy_revision`；成功返回完整SyncStatusDto。关闭取消业务sync链但不丢Outbox/不暂停本机提醒；独立settings reporter仍可只上报镜像 |
| `sync.run_now` | 唯一 SyncCoordinator | 仅普通用户/前台触发；请求为`workspace_id + expected_active_route_revision`，暂停时拒绝；结果为`run_id + disposition(queued/already_running) + status_revision`。只入同一唯一工作链，不另开并发路径；logout一次性override只由Broker内部流程发起 |
| `sync.conflict.list` | Kotlin → C++ local store | 离线可读，稳定分页 |
| `sync.conflict.detail` | Kotlin → C++ local store | 对象快照、`conflicting_groups/auto_merged_groups`、本机候选、云端值、设备、接收时间 |
| `sync.conflict.resolve` | Kotlin → C++ Outbox | expected conflict version + keep_local/keep_remote/per_field/manual_edit；成功只返回`queued/resolving`与新status revision，不能伪报server resolved |
| `sync.failed_change.list` | Kotlin → C++ local store | 当前workspace未同步失败意图的稳定分页；只返回安全摘要、failure code、target与时间，不返回任意payload Map |
| `sync.failed_change.detail` | Kotlin → C++ local store | typed本机候选/手工草稿、当前server baseline、失败原因、可编辑/可丢弃能力；离线可读 |
| `sync.failed_change.discard` | Kotlin → C++ local transaction | `failed_change_id + expected_failed_change_revision + expected_active_route_revision`；只删除该device-local overlay并重算presentation，零Outbox/零client sequence |
| `device.list` | Kotlin HTTP/cache + local registry | remote设备快照带 `fresh/stale/unavailable`，并合并当前设备本机权威 `receive_reminders/sync_enabled/settings_remote_pending/local_settings_revision`；pending-registration只允许在线受限列表 |
| `device.rename` | Kotlin HTTP + Broker | Backend `device.rename` 的严格映射 |
| `device.update_settings` | Kotlin lifecycle + HTTP | strict oneOf一次只改receive_reminders或sync_enabled；operation journal跨C++/Registry强杀恢复，完成后可合并远端镜像；离线返回本机已保存但远端待上报状态 |
| `device.revoke` | Kotlin HTTP + Broker | target/version/grant；普通态返回revocation；registration-pending成功撤销后Kotlin内部立即重试register并返回 `registration_outcome=registered/still_limited`及后续准备状态 |
| `preferences.get` | Kotlin → C++ workspace store | 返回可移植白名单与 revision |
| `preferences.update` | Kotlin → C++ workspace transaction | typed patch + expected revision；账号写 Outbox，游客零 Outbox |
| `search.get_workspace_history` | Kotlin workspace-scoped local store | `workspace_id + expected_active_route_revision` → 同identity/revision的规范化关键词列表；不读取其他workspace |
| `search.replace_workspace_history` | Kotlin workspace-scoped local store | 上述route字段 + ordered keywords + `expected_history_revision`；原子CAS替换并回显workspace/route/history revision |
| `profile.get_cached` | Kotlin → C++ account profile cache | 返回当前 workspace 的安全资料投影、profile revision 与 freshness；游客返回 not-applicable |
| `profile.accept_server_snapshot` | Kotlin → C++ account profile cache | 仅接收严格校验的既有资料 API 成功响应；按 revision 幂等写缓存且不生成 Outbox |

`WorkspaceStateDto`只有三个可公开分支：`ready`要求`active_workspace_id/workspace_kind/runtime_instance_id`全部非空且lock reason为空；`locked`要求active workspace id/kind与稳定lock reason非空、`runtime_instance_id=null`；`empty`要求三项identity与lock reason全为null。三个分支都要求非负`active_route_revision`。`workspace.state_changed`只携同一union的route identity与revision，不携统计；Flutter无论收到哪个分支都重读`workspace.get_state`。因此empty/locked事件不得伪造旧runtime id，Event丢失也不会导致恢复死锁。

Search History固定采用单一产品方案，不再允许“隔离或清空”二选一：旧active `search.get_local_history/replace_local_history`及全局v1文件只供升级时一次性迁入guest，耐久migration receipt成功后从production composition移除并删除旧文件；新方法始终按workspace寻址。guest历史继续位于`noBackupFilesDir`；account历史使用workspace-scoped AtomicFile + Keystore AEAD（workspace/schema作为AAD），退出/锁定立即清内存且不可见，retain窗口内同账号重登可恢复，revoke/destroy/可信到期时随key密码学销毁。历史只含`normalized_display_keywords`，不含对象ID或标题引用；guest→account导入不复制历史。Search Contract必须以兼容revision保留旧reader迁移顺序，禁止两个可写store并存。

`sync.get_status` 与 `sync.status_changed` 复用同一完整 DTO。字段名和顺序固定为：

```text
workspace_id, workspace_kind, runtime_instance_id, active_route_revision, device_id,
sync_enabled, sync_policy_revision, phase,
pending_upload_count, failed_local_change_count, next_failed_local_change_id,
unresolved_conflict_count, unclaimed_conflict_notice_count,
next_conflict_notice_id, next_conflict_notice_count, next_conflict_notice_sequence,
backlog_state, backlog_reason_codes, diagnostics_export_available,
last_attempt_at, last_success_at, next_retry_at, failure_code, retryable,
status_revision, active_run_id
```

failed count 为 0 时 next failed id 必须 null。notice 队列为空时 `unclaimed count/next id/next count/next sequence` 为 `0/null/0/null`；非空时 id/sequence 非空且 head count>0。不存在第二个“new conflict count”。

`status_revision` 由 Kotlin `SyncStatusAggregator` 单调拥有，只排序聚合 snapshot/event；`sync_policy_revision` 由 C++ 持久化，只用于开关 CAS，Work/Broker phase 变化不能推进它。`phase` 为十态，`backlog_state=normal/warning/critical`。

V1 warning 阈值为 pending 5,000、最老 72 小时或 Outbox 64 MiB；critical 为 20,000、14 天或 256 MiB，reason 为 `pending_count/oldest_pending_age/outbox_bytes`。failed overlay 单独告警且不计 pending upload。M6 只能通过正式 Contract revision 和五层 fixture 调整阈值，不能由各端硬编码。

Native `sync.get_status` 返回完整 `NativeSyncStatusSnapshot`。C++ 唯一拥有 workspace/runtime/device identity、policy、pending/failed/conflict/notice、backlog/diagnostic、native blocked reason 和 `native_state_revision`，但不返回 raw cursor。

Kotlin 以 workspace/runtime/route 绑定快照，并唯一耐久保存 Work/Broker 派生的 phase、attempt/success/retry/failure、active run 和 `status_revision`。只有 normal 或 bootstrap 的全部 Native 提交、必要 ack-only 和 journal 收尾成功后才推进 `last_success_at`。

guest `local_only` 的 device/policy/count/head/run/failure/retry/null 组合由 Schema 固定，backlog 为 normal 且 diagnostics=false。locked/empty route 不调用 `sync.get_status`，只能由 WorkspaceState 投影。任何层都不能用默认值补齐畸形 Native 快照。

十态固定为`local_only/idle/queued/syncing/offline_pending/paused/auth_required/rebuilding/blocked/failed`，同一快照只能有一个phase。投影优先级从高到低为：local workspace→`local_only`；账号身份/设备无效→`auth_required`；Contract/hash/storage corruption等全局不可继续故障→`blocked`；迁移/bootstrap/clear重建→`rebuilding`；已执行的normal/logout-final内部run→`syncing`；已获Broker授权且尚未执行的logout-final内部run→`queued`；`sync_enabled=false`→`paused`；普通sync有pending且当前网络不可用→`offline_pending`（即使WorkManager内部存在CONNECTED约束请求也不能显示queued）；网络可用且普通run已入唯一链→`queued`；自动重试预算耗尽或最近可恢复run失败→`failed`；其余→`idle`。`failure_code/retryable/next_retry_at`可作为附加历史字段保留，但不能改变优先级。ImportStatus的`repair_required`只是该导入的业务子状态，不把全局sync phase设为blocked；普通sync、successor、HTTP abandon和source-cleanup route仍可运行。

新冲突提示采用device-local不可变队列和 at-most-once claim。C++为每个download snapshot upper bound持久化发现journal：created加入、同窗口或后续resolved不复活；仅在terminal page对“窗口开始时未知且窗口结束仍unresolved”的净集合生成一个单调notice sequence，已有notice永不因后来冲突改写，新集合排在其后。Flutter显示前调用 `sync.claim_conflict_notice`；C++原子claim精确head，并按当前unresolved集合返回 `claimed(count>0)`或`no_longer_actionable`，提升native state revision，由Kotlin再发布新的聚合status revision。B在A claim前后到达都形成独立后继notice，claim A不清B。claim后到实际绘制前强杀可能漏一次弹窗，这是明确接受的at-most-once取舍；红点/冲突列表仍由unresolved总数保证，不得宣称UI与SQLite跨进程exactly-once。

队列必须有可证明的有界清理：`sync_state`持久化`next_conflict_notice_sequence`和单调`last_claimed_conflict_notice_sequence`。exact head claim在同一事务推进claimed水位、删除/标记该head并发布新head；旧claim只凭水位与当前head返回`no_longer_actionable`，不得清理后继。每个download/bootstrap discovery journal在terminal窗口成功提交notice或确认净集合为空时即删除其临时set；maintenance只能删除`sequence <= last_claimed`、非当前head且不被active discovery window引用的旧行，并保留水位，不能按本机时间或表大小清未claim notice。强杀发生在claim提交后仍采用“可能漏toast”的已接受语义，但不会重新展示或无限增长。

队列诊断不得导出业务内容。`backlog_state`只告警而不自行丢Outbox；`sync.export_diagnostics` 调用C++安全统计后由Kotlin加入版本、Work/transport、设备能力的枚举/计数/age bucket，禁止标题、payload、conflict candidate、token、cursor、账号明文、目录、alias、精确device id。文件使用短期cache + FileProvider，系统分享关闭后/固定TTL清理；导出失败返回 `SYNC_DIAGNOSTIC_EXPORT_FAILED` 且不改变同步状态。

`sync.run_now` 只接受当前 `workspace_id + expected_active_route_revision`，返回 `run_id + disposition(queued/already_running) + status_revision`。guest、paused、未绑定 device 或 blocked 使用冻结错误，不能伪装 queued。

logout final sync 不是第二个公开同步入口。active `auth.session.logout(final_sync_policy=attempt_once)` 先建立 durable operation 并阻写 session-bound account lane，再以该账号 workspace/runtime/transport generation 加入唯一链，内部使用 `run_intent=logout_final`。前台 route 可以是 account 或 local，但 local 不能成为退出目标；即使 `sync_enabled=false`，也只覆盖本轮且不改持久开关。无法安全终止时返回 operation-bound review；Flutter 只能以同 operation/revision retry、cancel 或 skip。skip 只跳过 final sync，仍走 `server_then_local`；仅在同 operation 已记录 server unreachable 后可另行确认 `force_local`。

`sync.set_enabled` 接受 `workspace_id + expected_active_route_revision + enabled + expected_sync_policy_revision` 并返回完整状态。false→true 先建立 durable pull-before-push gate，不能拿聚合 `status_revision` 做 C++ CAS。

除只读恢复入口 `workspace.get_state` 外，所有 workspace-scoped 方法显式携带 workspace identity 和 active route revision；有业务并发时再携其专属 revision。`workspace.get_state` 不做 CAS，只回显权威 route snapshot，避免重启或 Event 丢失后的恢复死锁。

内部协调器的run intent闭包为`normal/logout_final/receipt_ack_flush/reenable_pull_only/clear_rebuild_bootstrap`五态。`receipt_ack_flush`只在local ack高于server-accepted时由内部恢复逻辑创建，强制ack-only union且可在paused执行；`reenable_pull_only`只在C++ false→true事务已持久化pull gate后创建，必须以空uploads但有效current cursor完成全部固定上界下载页，cursor需bootstrap时以完整bootstrap替代，terminal apply/finalize才原子解除gate并允许normal prepare读Outbox；`clear_rebuild_bootstrap`只由已通过二次确认的clear lifecycle operation创建，只调用bootstrap begin/pages/finalize，不prepare/upload普通Outbox，但其finalize产生的dirty仍必须转入ack-flush收尾。后三者都不改开关，clear完成后phase回原paused/idle。任何Flutter参数或任意Worker都不能伪造后三种内部capability。

Access Token 每次被 Broker 替换时 `access_token_generation` 单调递增。普通请求传 null；HTTP 收到 401 后只能以刚被拒绝的 generation 再调用一次：若 Broker 当前 generation 更大，直接返回新 token；若相等，即使时间上仍有效也强制加入同一 single-flight refresh。调用方最多重放原请求一次，第二次 401 进入冻结 Auth 终止路径，避免无限 refresh/replay。

`auth.session.logout` 的 active 与 pending request 使用 strict exclusive `oneOf`。尚无 account runtime 的 `pending_adoption/registration_pending` 只能以 session generation CAS 退出，不能携 route、final-sync 或 review 字段。

active 首次 `attempt_once` 同时 CAS session generation 和调用方观察到的 route tuple；目标账号只取 Broker session binding。Broker 创建 opaque `logout_operation_id` 和 durable lifecycle gate，阻止新 account writer/settings/import 后执行 logout-final。run 失败、仍有 pending/failed-local 或非终态 import 时，gate 保持并返回 `review_required` risk snapshot 和 `logout_risk_revision`。同 operation retry 保持 gate；`cancel_after_review` 原子解锁且零 logout；`skip_after_confirmation` 仅在 revision 匹配时跳过 final sync并继续 server logout。

`server_then_local` 只在 final sync 成功或明确 skip 后调用服务端；只有 `succeeded/already_invalid` 才终止本地 session。网络不可达记录 `server_logout_status=unreachable` 并保持 session、cache、gate 和 route；UI 可 retry/cancel，或再次确认后以同 operation `force_local`。force-local 不声称服务端成功，并在 destroy/重登时遵守 transport fence。

成功后，原 route 为 local 则保持同一 graph；原 route 为 account 才切到 local 并推进 route revision。`server_then_local`可选择 retain 30d 或 crypto-destroy，因为成功终态会提供可信`server_time`；`force_local`只有在同boot可信锚仍可验证时才允许retain。非终态 import 遵守 `IMP-08`–`IMP-10`。未验证 binding 的 pending adoption 其 cache action 为 not-applicable；已验证 registration pending 可定位旧 retained cache。

`auth.session.clear_local` 的 reason→action 固定为：`normal_logout/session_expired/password_reset/logout_all`只有在能建立可信deadline时才保留加密隐藏缓存30天；normal logout直接使用终态`server_time`，其余不可继续Session的reason若无当前可信响应/同boot锚则按隐私优先先毁key再清文件，不得建立无deadline retained。`device_revoked/account_deleted/refresh_token_reused/session_account_mismatch/storage_corrupted/user_requested_destroy`固定先毁key再有界清文件。除用户确认的`user_requested_destroy`外，Flutter不得自报安全reason，必须由Kotlin从可信服务端或本地故障派生。

30天是目标保留窗口，不是Android能保证的整点物理删除SLA。保留协议的唯一规则如下：

1. `cache_state=retained`蕴含`retention_started_at`与`retained_until`均为非null且已由可信时间锚建立；禁止“retained + null deadline”。正常`server_then_local`使用Backend logout终态的UTC `server_time`。`force_local`只能使用仍处于同一boot的既有可信服务端锚，并以`server_time_anchor + (elapsedRealtime_now - elapsed_realtime_at_anchor)`建立保守起点。
2. 初始`server_then_local`以及有可验证同boot锚的`force_local`，`allowed_cache_policies`精确为`[retain_30d,destroy_now]`；无锚`force_local`精确为`[destroy_now]`。后一分支收到`retain_30d`请求时返回`RETENTION_TRUSTED_TIME_REQUIRED`，保持同一logout operation、writer gate、Session、cache与route，既不终止也不静默降级为删除。用户只能取消/重试服务端退出，或二次确认`destroy_now`。
3. `RetentionDeadlineRecord`固定包含成对非空或成对为空的`retention_started_at/retained_until`、`server_time_anchor`、`elapsed_realtime_at_anchor`、`boot_id`、`retention_clock_state=trusted/untrusted/expired/deleting/destroyed`与`lifecycle_revision`。一旦建立，起点与截止值不得重算或延长；空值只允许not-applicable/destroyed等非retained分支。
4. `boot_id`是Kotlin-local、canonical lowercase UUIDv4字符串，不进入Flutter/JNI/HTTP/Event或日志。`BootEpochRecord`类型固定为：positive Int `schema_version`、`source=global_boot_count/process_only`、仅global分支存在的nonnegative Int `observed_boot_count`、UUID字符串`boot_id`、nonnegative Long `last_elapsed_realtime_ms`。唯一owner `BootEpochProvider`在API 24+读取`Settings.Global.BOOT_COUNT`作为重启检测输入，并把该记录写入`noBackupFilesDir`下的Keystore-AEAD `AtomicFile`；AAD绑定当前`installation_id`与schema，且Backup/Device Transfer明确排除。
5. API 24+进程重启时，只有boot count相同、当前`elapsedRealtime`不小于已记录值且installation/AAD一致才复用`boot_id`，并在每次可信读取后原子更新不下降的`last_elapsed_realtime_ms`；boot count变化即生成新UUID。API 23及以下或BOOT_COUNT不可读时，boot identity只在当前进程存活期可信，进程重启后必须视为unavailable。记录缺失/损坏、boot count倒退、elapsed倒退、installation变化、同UUID绑定不同boot count，或安全随机源不能产生不同新UUID时全部fail closed：旧deadline转`untrusted`，elapsed不得授权删除。
6. 已建立deadline在重启或boot identity不可验证后保持hidden + untrusted。普通wall clock只可触发检查，不能授权删除或延长；Kotlin仅可用无账号数据、限流、no-store、合法HTTPS的`GET /api/v1/system/time`恢复当前时间下界，并且只评估既有deadline。可信下界达到deadline后，在首次系统允许的cleanup机会先crypto-destroy，再以deleting状态清文件。

用户文案固定表达“预计保留30天；到期后的首次允许清理机会先销毁密钥”。进入`force_local`确认页时必须按`allowed_cache_policies`展示选项；无可信锚只提供取消/重试或“立即清除并仅本机退出”，不能展示可选的30天保留。

“立即清除此设备缓存”不是 logout；目标只由 Broker session binding 解析，前台 route 可为该 account 或 local。

1. 先阻写 account runtime，收敛普通 Outbox/effect apply、尾部 ack-only 和非终态 import range，并完成或耐久冻结 settings reporter。任一预检失败都恢复 lane 且零删除。
2. 以同一 `clear_operation_id` 调 `sync.device_fence(expected=current, reason=clear_rebuild)`；持久化 exact receipt，并由 C++ `sync.accept_transport_fence` 原子接纳。receipt 与 Native 都提交后才越过不可逆线，旧 generation 请求/响应从此零写。
3. 毁库前，把 C++ policy、Registry reminder/settings owner、reporter 恢复值、import handle 和 fence receipt 冻结为 atomic lifecycle seed；AAD 绑定 `workspace_id + device_id + session_generation + clear_operation_id + resulting_sync_transport_generation`。seed 不是第二日常 owner，也不能取 Backend 诊断镜像。
4. 取消 account reminder、close、毁 key/删 DB；以新 DEK、fence sequence bundle 和本机 owner seed fresh-open。完成 materialized bootstrap、import/lease 恢复、必要 ack-only 与 settings reporter 后，才开放 writer/reminder 并删除 seed。

强杀或毁 key 后失败保持 `rebuilding/blocked` 且 session 仍 active；原 route 为 local 时保持 local，不能自动 logout 或回退 guest。可信 revoke、refresh reuse、account/session mismatch 或 account-deleted 可抢占任一阶段并立即销毁；若跳过在线 fence，必须保留 future `transport_fence_required`，除非权威终态已永久关闭 device/account。

旧 `sync.apply` 保持 `deprecated + release_status: blocked`，生产 Handler 必须 `notImplemented`；旧 `auth.refresh_token.read` 在 broker 同包迁移后不得继续被 Flutter 调用或向上返回 token。是否保留其他三个旧 refresh-token 方法作为一个版本的兼容 adapter，由 Session ADR 冻结，不能形成第二 owner。

`auth.session.adopt` 不允许只接收裸 `token_pair` 或让 Flutter 另传未验证 `account_id`，也不允许解析 opaque access token 猜账号。登录本身需要网络，因此 adopt 的身份交叉校验是激活账号 workspace 的前置步骤；校验网络失败时 token 只处于 Broker 的 pending-adoption 安全状态，不打开账号库，重试仍使用同一 session。identity 不一致立即清除 pending token 并返回 fail-closed 错误。

新登录/注册后的固定顺序为：`auth.session.adopt` 身份校验成功 → 校验服务端账号同步 entitlement → `device.register` 绑定当前 session → 创建或解锁 account workspace → 导入决策 → 进入业务首页。测试阶段非白名单账号在 register/业务 capability gate 统一得到 `SYNC_NOT_ENABLED_FOR_ACCOUNT`；Broker安全清除pending adoption（可best-effort logout但不等待），保持原guest active，不创建device、账号DB或Outbox，Flutter只展示“同步测试暂未开放”。若 register 返回设备上限，adopt 保持受限 pending-registration，先列设备→reauth→撤销旧设备→重试 register，不开放账号业务。账号 workspace 在缺少已绑定且未撤销的 `device_id` 时不得以可写模式打开，因此不需要、也不允许临时 device id 或未分配 sequence 的上传队列。既有账号离线冷启动只能复用已安全持久化的 session/account/device binding；新建账号 DB 必须消费 register 返回的 `next_client_sequence` seed，cursor 为空且先完成 bootstrap。若同账号保留DB绑定的旧`device_id`与本次register权威`device_id`不同，Kotlin必须先crypto-destroy旧账号缓存/Outbox，再用新seed新建DB并bootstrap；绝不迁移或重发旧device序列空间的Outbox。

本机同步策略的fresh初始化也必须唯一：真正首次/新device，以及logout `destroy_now`、30天到期或其他已完成crypto-destroy后的未来重登，都由Contract genesis seed初始化C++ `sync_enabled=true, sync_policy_revision=0`；Backend诊断镜像不得反向充当owner，Flutter在重登确认中明示将恢复同步。`retain_30d`期限内重登直接保留原C++值/revision。active session内的`workspace.clear_account_cache`不是新登录，Kotlin必须在毁key前把当前C++ `sync_enabled + sync_policy_revision`冻结到operation-bound受保护seed，新库只凭同operation receipt恢复，不能回落genesis。只有真正新device行的Backend `sync_enabled`镜像在注册事务初始化为true；同active device完整destroy/到期后重建本地库时，服务端旧镜像可能仍为false，Kotlin必须把本地genesis与register快照比较、置`settings_remote_pending`并由独立reporter幂等收敛，绝不能让镜像反向覆盖C++或把pending误清。

升级时若只存在旧版 `{refresh_token, session_id, expires_at}` 安全记录而没有 account/device binding，Broker 在生产 Flutter 停止旧 refresh owner 后执行一次受控迁移：在线时用旧 RT refresh，先原子保存旋转后的 pending token，再调用 `user.get_current` 和 `device.register` 建立权威 binding，最后写入新版 Broker record；离线时保留旧加密记录但只开放游客 workspace，等待同一迁移重试，绝不向 Flutter 返回 RT。若服务端已旋转而新 token 落盘结果不确定，按崩溃窗规则清会话并要求登录，不重放旧 RT。

### 8.3 Kotlin ↔ JNI/C++ Native calls（`NativeResult<T>`）

| Native call | Request 核心参数 | Response / 原子性 |
| --- | --- | --- |
| `runtime.open_workspace` | Kotlin已分配的workspace metadata+binary key；fresh account带register/fence的`sync_transport_generation + highest/nullable-next/client-confirmed/client-sequence-exhausted` recovery bundle、fence receipt及genesis policy seed；clear-rebuild另传`workspace_id + device_id + session_generation + clear_operation_id + sync_enabled + sync_policy_revision` seed | 校验transport/sequence严格分支及fence requirement后fresh续号/bootstrap；C++生成并返回非空`runtime_instance_id`及全identity匹配的seed-consumed receipt；exact already-open返回同runtime id，任何metadata/key binding差异拒绝；`receive_reminders/settings_remote_pending/revision`与reporter恢复上下文始终留在Kotlin Registry lifecycle，key不进JSON |
| `runtime.close_workspace` | workspace/runtime identity | 等待受控调用结束、checkpoint/close；幂等 |
| `workspace.get_state` | Kotlin Registry解析的nullable current workspace/runtime identity | 只查询该权威runtime的metadata与typed counts；无current runtime返回empty投影，不自行选择目录或active route |
| `workspace.import_preview` | source/target workspace id + nullable predecessor lineage | strict oneOf：ready含source epoch、snapshot token/hash、C++生成的proposed batch id/lineage、typed counts/bytes、mapping/manifest digest、warnings；previous-epoch-cleanup-pending只含旧epoch opaque恢复handle；若guest已有异owner/lineage/epoch opaque lease则返回`IMPORT_SOURCE_OWNED`而不泄露账号 |
| `workspace.import_accept_range_close` | Backend `ImportRangeCloseProof` + current workspace/runtime/session binding | 仅Kotlin lifecycle内部调用；用于takeover/confirmed-abandon/capacity/TTL，strict验证proof identity/revision/range/reason并原子更新lineage head。origin为当前device时同时终结matching本地Outbox range、落virtual terminal、本地ack基线、allocator next/exhausted与ack-watermark dirty；其他origin不碰当前allocator。重复proof幂等，错range/revision零写；Flutter无此Method |
| `workspace.import_commit` | preview token、lineage/import batch id、`expected_import_revision`、nullable predecessor batch/takeover reason/range-close proof id | Schema以strict `oneOf`冻结：首次批为revision 0/predecessor、reason、proof均null；普通repair为current/predecessor且reason/proof null；证据丢失/原设备不可用/TTL回收后的完整接管必须引用已由`workspace.import_accept_range_close`接纳的takeover proof，并使用其resulting revision。先取得/复用source epoch lease，再只写隔离staging + begin/items/commit Outbox；未接纳proof一律零写 |
| `workspace.import_status` | nullable batch id或source workspace/source epoch/target + nullable server snapshot | 发现/恢复该epoch唯一active handle并返回第7.6节状态闭包、manifest revision、staging/publish计数及 affected reminder ids；旧epoch cleanup receipt优先恢复，不跨epoch合并 |
| `workspace.import_abandon` | batch/lineage + expected revision + exact Backend abandon result | 只验证/落本地terminal或already-confirmed状态，零Outbox；无HTTP结果时仅标local-abandon-unconfirmed，不伪报服务端terminal |
| `workspace.import_cleanup_confirm` | guest source epoch cleanup receipt identity + exact Backend cleanup-confirm disposition/revision | 只在HTTP结果与本地同epoch through head/hash完全匹配时原子标记completed、解除previous-epoch preview gate并允许源设备解除account reminder suppression；零Outbox/零client sequence，重复幂等 |
| `workspace.import_finalize_source_lease` | guest/source/source epoch/opaque owner binding + strict proof oneOf：prepublish confirmed-abandon并残留terminal、prepublish confirmed-abandon+destroy-final receipt、cleanup completed receipt、owner-bound authenticated account-deleted receipt | 仅Kotlin lifecycle内部调用；在guest事务验证lease/revision/epoch/proof后幂等释放，零账号业务写/Outbox；account-deleted分支同时把matching cleanup receipt置terminal/删除并解除previous-epoch gate且不回退current epoch；unconfirmed或普通auth/device终态拒绝，绝不向Flutter公开 |
| `sync.accept_transport_fence` | exact Backend fence receipt + current workspace/device/runtime/session/old transport binding | lifecycle内部调用；验证签名/operation/old→new generation/sequence bundle并原子失效旧run响应、落new generation与resolved absent-import proof；同receipt幂等，错binding零写。fresh DB可在open seed内等价消费 |
| `sync.prepare_upload_batch` | workspace/device/runtime/transport binding、`run_intent=normal/logout_final/receipt_ack_flush/reenable_pull_only`、Contract max_items≤100/max_bytes | 返回完整`PreparedExchangeRequest`严格union且由C++持久化：normal/logout为wire `mode=normal`并含protocol/device/transport/current opaque cursor/download limit/current acknowledged watermark、stable batch id/route和连续typed uploads；reenable-pull为wire normal但`uploads=[]`、带current cursor/download limit/ack及durable pull gate；ack-flush为wire `mode=ack_only`、uploads空/download-limit 0/cursor null/ack非空。Kotlin只加Bearer并原样编码，不能保存/拼cursor。paused只接受Broker绑定logout-final或确有dirty的ack-flush；clear-rebuild不调用prepare |
| `sync.acknowledge_upload` | strict request union：normal含prepared batch identity、exact Backend item results/effect refs及response transport/accepted-ack；ack-only含prepared ack-only identity、reported acknowledged watermark、response `mode=ack_only`与accepted watermark且batch/results/changes/cursor/cleanup字段必须空/null | normal只终结Outbox/receipt、成功causal anchor与import staging；未apply效果写gate且用户mutation rejected转failed overlay，不发布伪server事实/conflict/notice。ack-only只验证`accepted==reported`、单调且不超过当前local ack，在单事务推进`server_accepted_client_sequence_through`并按是否追平派生dirty；不改cursor/account generation/cleanup/business。ack-only成功后跳过`sync.apply_download_batch` |
| `sync.apply_download_batch` | 仅接收wire `mode=normal`的完整`ApplyExchangeResponse`：response transport/account generation、snapshot upper bound、ordered change groups/import publish chunks、raw next cursor、`has_more`、两个冻结cleanup水位、accepted ack及prepared request identity | 校验响应与prepared/current binding后，在单事务完成baseline+pending+failed-local overlay、group/conflict lifecycle、notice terminal window、receipt/cursor/cleanup/accepted-ack；import跨页staging到commit才整图发布。terminal reenable-pull页或等价bootstrap finalize原子解除pull-before-push gate；返回next prepared cursor、affected ids/native status，不接受ack-only伪normal |
| `sync.record_transport_terminal` | workspace/device/runtime/session generation + 闭合terminal code + strict error envelope evidence hash | 幂等持久化sync terminal gate与native state revision；至少覆盖protocol unsupported、sequence replay/active-import-route mismatch、client/server sequence exhausted及不可恢复cursor identity错误，先落盘再结束run；V1无通用自动clear，upload writer/prepare重启后仍fail closed |
| `sync.begin_bootstrap` | 首个Backend响应的exact identity：`bootstrap_id + sync_transport_generation + account_generation + snapshot_upper_bound_server_sequence + device_highest_client_sequence_at_snapshot + device_client_confirmed_through_at_snapshot + nullable device_next_client_sequence_at_snapshot + device_client_sequence_exhausted_at_snapshot + retention_floor_server_sequence + resolved_conflict_cleanup_before + trigger_reason(cursor_expired/account_generation_changed/fresh_database/clear_rebuild)` | 全字段与workspace/device/runtime/session/fence及严格next/exhausted分支校验后建立或恢复同一隔离staging；不覆盖live facts、不自行生成id/水位；首页仍另交`sync.apply_bootstrap_page` |
| `sync.apply_bootstrap_page` | exact Backend bootstrap page | 校验fact/tombstone/deleted-entity-anchor/conflict/marker/causal-anchor union（含auto-merged groups）、page token/order/refs后幂等写staging |
| `sync.finalize_bootstrap` | bootstrap id +同一transport/account generation/upper bound、terminal page-set digest、final cursor及与begin完全相同的冻结cleanup/sequence bundle | facts+unresolved conflicts+receipts+cursor/水位原子发布并按per-key因果链rebase/overlay；fresh DB恢复device anchors/allocator，若存在reenable gate则只在该snapshot覆盖当前上界时解除；返回notice/affected ids/native status |
| `sync.get_status` | workspace/device/runtime identity | 返回上文完整`NativeSyncStatusSnapshot`，不返回raw cursor或Kotlin-owned run/time/status revision字段 |
| `sync.set_enabled` | operation id + enabled + expected sync policy revision | 同operation/payload幂等返回原receipt；只改变策略并推进policy revision，不丢Outbox；false→true同时持久化pull-before-push gate，只有terminal pull/bootstrap可解除；聚合status revision不是CAS输入 |
| `sync.claim_conflict_notice` | workspace/device、head notice id/sequence | 原子claim一个不可变notice，返回claimed/no-longer-actionable和新状态；不改conflict/不产Outbox |
| `sync.build_diagnostic_snapshot` | workspace/device、Contract redaction profile | 只返回分桶计数/版本/状态/安全水位；不含业务payload、身份明文或路径 |
| `sync.run_local_maintenance` | workspace/device、`max_items≤500` | 只按已持久化安全水位有界清理 resolved candidates/change receipts；返回水位、删除计数、`has_more`，不推进 cursor/不产 Outbox |
| `sync.conflict.list/detail/resolve` | 与 MethodChannel 同名业务字段 | 本地读；detail含conflicting/auto-merged组；resolve原子写resolution mutation + Outbox并只返回queued/resolving |
| `sync.failed_change.list/detail/discard` | 与 MethodChannel 同名业务字段 | 本地稳定读；discard按revision原子删overlay并重投影baseline+pending，零Outbox；正常编辑入口另建新mutation而非“重发旧项” |
| `preferences.get/update` | workspace + typed preference patch | workspace-aware；账号 update 与 Outbox 同事务 |
| `profile.get_cached/accept_server_snapshot` | workspace + typed safe projection + profile revision | 账号库内缓存；server snapshot/download apply 不生成 Outbox，旧 revision 不得覆盖新值 |

`runtime.open_workspace` 的二进制 key 参数必须由加密 ADR 和 spike 最终确认。若选型无法安全支持该签名，本方法保持 blocked 并修订 Contract；禁止临时把 key Base64 放入 JSON。

Kotlin 处理 wire `mode=normal` 的成功响应时，顺序固定：

1. 把完整逐项 results 和 response identity 交 `sync.acknowledge_upload(mode=normal)`；即使 results 为空也执行，以闭合同一 prepared identity。
2. 把完整 groups/chunks/cursor/upper-bound/has-more/cleanup/accepted-ack 交 `sync.apply_download_batch(mode=normal)`。

两调用各自幂等。ack 只落 terminal receipt/成功 causal anchor，并为未 apply 的 effect 建隐藏 entity gate，不发布服务端可见状态；中间退出依靠 Backend duplicate receipt 和固定下载页恢复。wire `mode=ack_only` 只调用 acknowledge 并跳过 apply。

normal apply 应用精确 effect group 并解除 gate，先更新 server baseline，再按 field registry/sequence 重放受影响 pending 和仍适用 failed-local overlay。若远端 group 与未裁决 pending 竞争，C++ 只写 `awaiting_server_adjudication`，不增加 unresolved/notice、不生成 `conflict_id`、不阻断 Outbox；只有 `conflict_delta.created` 建立权威 conflict 和门禁。

baseline、overlay、marker、group/conflict/import staging、receipt、gate 和 cursor 在同一 SQLite 事务更新。Kotlin 不修改 payload、不拆 group、不合并字段、不提前保存 cursor。

### 8.4 EventChannel

| Event | Identity / Ordering | 恢复协议 |
| --- | --- | --- |
| `sync.status_changed` | `(workspace_id, runtime_instance_id, active_route_revision, status_revision)`；status revision 单调，可重复、可丢失 | Flutter 先订阅再调用 `sync.get_status`，只接纳当前route的更新 revision |
| `workspace.state_changed` | `route_state + active_route_revision`及与`WorkspaceStateDto`相同的nullable identity union；ready三项identity非空，locked runtime为空，empty全部为空 | 切换/锁定/撤销后重新调用 `workspace.get_state`；event不是完整快照 |

事件不得包含业务 payload、token、cursor 原文、目录或密钥；冲突红点通过状态中的计数更新，不发送系统通知。

通知与提醒的本机 wire identity 另遵守：调度唯一键和新 `NotificationTapPayload` 均包含 `workspace_id + workspace_kind + target_type + target_id + reminder/occurrence identity`。`workspace_id/workspace_kind` 仅是本机路由投影，禁止上传；它们对现有 payload Schema 采用 additive optional 兼容演进，但 v6 创建/更新提醒的 writer fixture 将其设为条件必需。guest 通知必须显示本地化“本机”来源标签，account 通知不显示该标签。点击 guest 通知时明确激活 guest workspace 后导航；当前已认证且可解锁的 account 通知激活对应 account 后导航；已退出隐藏账号的遗留通知返回 unavailable，绝不自动登录或跨库扫描。旧 payload 无法唯一定位时返回稳定 ambiguous 错误。

### 8.5 端到端调用账本

以下链路是五份计划共同使用的顺序，不得在实现层增加旁路：

| 用户/系统动作 | Flutter → Kotlin | Kotlin → C++ | Kotlin → Backend | 落盘与回传 |
| --- | --- | --- | --- | --- |
| 登录后激活账号 | `auth.session.adopt` → `workspace.activate` | `runtime.open_workspace`（仅在身份校验、设备注册后） | `user.get_current` 交叉校验 → `device.register` | account/session/device/workspace identity 全部匹配后发布 `workspace.state_changed` |
| 手动/自动同步 | `sync.run_now`；UI随后读status | prepare→ack→apply ordered atomic groups | `sync.exchange` | server baseline+pending+failed-local overlay、conflict lifecycle/receipt/cursor原子；B解决后A拉resolved并清红点 |
| 重新开启同步 | `sync.set_enabled(true)` | C++ policy事务建立pull gate；`prepare(reenable_pull_only)`只给空uploads/current cursor，terminal apply或bootstrap finalize解除后才允许normal读取Outbox | wire normal空上传拉完固定上界，必要时bootstrap；dirty可独立ack-only | 强杀后仍先pull，pending Outbox身份/hash不变，绝不先push |
| Cursor 过期/代际不符 | UI 只显示 rebuilding | 收到 Backend 首页后 `sync.begin_bootstrap` → 首/每页 `sync.apply_bootstrap_page` → `sync.finalize_bootstrap` | 先以 null cursor 调 `sync.bootstrap` 建/复用 session，再按 token 分页 | 完整 staging 发布、pending Outbox与failed-local overlay按因果顺序rebase后恢复普通 exchange |
| 首次本机数据迁移 | `workspace.import_preview/commit/status/abandon` | 执行 `IMP-01`、`IMP-04`–`IMP-10`、`IMP-12` 的本机职责 | 执行 `IMP-02`、`IMP-03`、`IMP-05`–`IMP-08`、`IMP-11`–`IMP-12` 的服务端职责 | 只按 `IMP-04` 与 `IMP-09` 的证据推进可见性和 guest 退休；任何失败保留可恢复 source/lineage 状态 |
| 查看/解决冲突 | `sync.conflict.list/detail/resolve` | 同名 native calls | resolve Outbox 使用 `sync.conflict.resolve` 单项 route | 提交只进入resolving；exact terminal ack或resolved delta后才移除，异步拒绝/版本过期恢复详情与草稿 |
| 编辑重复Event | 复用当前 `event.update` 整系列语义及已有occurrence状态方法 | C++沿用当前领域事务并产生普通账号Outbox | 账号写随普通`sync.exchange` | 三作用域编辑为R3 deferred，本版本不新增Method/Native/API |
| 修改可移植偏好 | `preferences.update` | `preferences.update` | 后续普通 `sync.exchange` | 账号事实 + Outbox 同事务；游客无 Outbox |
| 资料读取/修改 | `profile.get_cached`；现有资料 Gateway 成功后调用 `profile.accept_server_snapshot` | 同名 cache calls | 既有 `user.*` / avatar / email API | 专用 API 写产生 download-only `account_profile` change；缓存按 revision 幂等 |
| 修改设备 | `device.rename/update_settings/revoke` | 无业务事实写；`sync.set_enabled` 只管本机状态 | 对应 device API；独立 reporter 在 sync disabled 时仍可只上报设备镜像；revoke 使用 Broker 内部 grant | device DTO 原样映射；被撤销设备下次联网进入统一销毁 |
| 本地低频维护 | 无公开 UI 方法 | `sync.run_local_maintenance` 有界重复 | 无 Backend 请求 | open 后/低频 Worker按 C++已持久化安全水位清理，强杀可恢复且不影响业务 sync开关 |
| 提示/人工诊断 | 状态有notice/backlog；展示前claim；用户点导出 | notice claim + safe diagnostic snapshot | 无 Backend 请求 | claim at-most-once；Kotlin分享脱敏文件并按TTL清除 |
| 设备上限恢复 | adopt 页内 `device.list` → `auth.session.reauthenticate` → `device.revoke` | 不开账号 runtime | revoke成功后Kotlin内部立即以持久化installation重试 `device.register` | Method结果给registered/still-limited；不依赖旧auth response，正式binding/seed后才激活 |
| 立即清账号缓存 | 二次确认后 `workspace.clear_account_cache` | 非终态import先取得可接纳range-close/terminal；随后block→drain normal/ack-only→accept fence→close/destroy→fresh open→bootstrap/import recovery | import status/takeover/abandon→`sync.device_fence`→bootstrap→cleanup-confirm | 常规路径fence失败零删除；隐私/安全终止例外可先销毁但写future-fence gate；不退出session，原route为local时保持local，账号graph在全部恢复前不可写 |
| 退出 | 首次`auth.session.logout(attempt_once)`；review后同operation retry/cancel/skip；server unreachable后才可force-local | Broker耐久阻写session-bound账号lane并执行logout-final；review snapshot/revision保持无TOCTOU，cancel才解锁 | final sync同一`sync.exchange`/ack-only链；success或明确skip后server logout | final sync失败/风险保持会话与原route；skip仍是server-then-local，force-local不冒充服务端成功；原route为local时成功后保持local |

Workspace route CAS 的唯一 owner 是 Kotlin `WorkspaceRegistry`。它持久化进程级、跨 workspace 单调的 `active_route_revision`，并在 activate/lock/logout/revoke/clear-open 改变可路由实例时递增；C++ 的 local/native-state/preferences revision 不能代替它。

Registry 在一次 atomic replace/CAS 中提交 `route_state + nullable active_workspace_id/workspace_kind/runtime_instance_id + active_route_revision` 并满足 union，成功后才发 event。重启导致 runtime identity 变化时，同样先以新 revision 提交完整 tuple。

除 `workspace.get_state` 外，workspace-scoped Flutter 请求携带 `workspace_id + expected_active_route_revision`；需要业务并发控制时另带专属 revision。Kotlin 命中 Registry CAS 后才绑定不可复用的 `runtime_instance_id` 调 Native，并核对 response identity。`workspace.get_state` 无条件返回当前 tuple，`workspace.state_changed` 只提示重读。

Flutter 不接触 cursor、client sequence、Outbox、raw change 或 Refresh Token；Kotlin 不重建 typed mutation、不计算领域合并；C++ 不执行 HTTP。

## 9. Schema 与机器文件交付清单

### 9.1 Sync 核心

- [ ] `contracts/sync/sync_protocol_invariants.yaml`
- [ ] `contracts/sync/sync_counter_registry.yaml`：owner、safe MAX、checked-increment、stable error/context与terminal action。
- [ ] `contracts/sync/sync_field_registry.yaml`
- [ ] `contracts/sync/sync_mutation.schema.json`
- [ ] `contracts/sync/sync_upload_result.schema.json`
- [ ] `contracts/sync/sync_change_group.schema.json`：普通mutation的typed entity changes + conflict deltas不可拆原子组。
- [ ] `contracts/sync/sync_conflict_delta.schema.json`，以及 `sync_import_publish_item.schema.json` 的 begin/chunk/commit strict union。
- [ ] `contracts/sync/sync_exchange_request.schema.json`
- [ ] `contracts/sync/sync_exchange_response.schema.json`
- [ ] `contracts/sync/native_prepared_exchange_request.schema.json`与`native_apply_exchange_response.schema.json`：冻结normal/logout/pull-only/ack-only本机分支、wire mode、cursor/download/ack/upper-bound/has-more/cleanup的required/null矩阵。
- [ ] `contracts/sync/sync_device_fence_request.schema.json` 与 `sync_device_fence_response.schema.json`：冻结operation幂等、old→new transport generation、sequence recovery bundle、resolved absent-import fence proof。
- [ ] `contracts/sync/sync_bootstrap_request.schema.json`
- [ ] `contracts/sync/sync_bootstrap_item.schema.json`：严格 `fact_after_image/tombstone/deleted_entity_anchor/unresolved_conflict/import_publish_marker/requesting_device_causal_anchor` union；每分支有独立required/exact-key，deleted anchor不含业务payload且可携不可变import provenance。
- [ ] `contracts/sync/sync_bootstrap_page_response.schema.json`：冻结session/generation/upper-bound、device highest/client-confirmed recovery bundle、两个cleanup水位、page hash/cursor与terminal规则。
- [ ] `contracts/sync/sync_status_response.schema.json`
- [ ] `contracts/sync/sync_conflict_summary.schema.json`
- [ ] `contracts/sync/sync_conflict_detail.schema.json`：冻结`conflicting_groups/auto_merged_groups`的typed投影。
- [ ] `contracts/sync/resolve_sync_conflict_request.schema.json`
- [ ] `contracts/sync/sync_conflict_resolution_response.schema.json`
- [ ] `contracts/sync/sync_failed_local_change_summary.schema.json`、detail/discard request/response：只允许typed候选/草稿与安全错误context，严禁自动重传字段。
- [ ] 每个 `target_type` 的 create/update/delete/restore 或专属 operation Schema，禁止通用 `additionalProperties: true` payload。

### 9.2 Workspace、设备、会话与偏好

- [ ] `contracts/workspace/`：ready/locked/empty state/event union、list/activate/import preview/commit/status九态+三个正交enum/abandon/cleanup，以及内部import range-close proof接纳Schema；status固定“exact batch可回终态 / source discovery只回当前handle或empty”。
- [ ] `contracts/sync/import_takeover_request.schema.json`、`import_range_close_proof.schema.json`与对应HTTP response：冻结virtual no-effect range、resulting revision、origin-device highest/nullable-next/exhausted及防篡改字段。
- [ ] `contracts/device/`：register/list/rename/settings/revoke 与 device response Schema。
- [ ] `contracts/auth/`：session adopt/access/status/logout/clear/reauth Schema；服务端logout终态`server_time`、`allowed_cache_policies`、`RETENTION_TRUSTED_TIME_REQUIRED`、RetentionDeadlineRecord/clock state/null矩阵、Kotlin-local BootEpochRecord及所有 token/password sensitive标记。
- [ ] `contracts/common/server_time_response.schema.json`与`backend_api.yaml`中的`system.time`：exact UTC字段、无body/无账号数据/no-store/限流语义；不得复用为同步冲突裁决时钟。
- [ ] `contracts/preferences/`：四项portable preference response、typed patch、revision CAS、timezone双轴；locale新写拒绝与历史兼容矩阵。
- [ ] `contracts/reminder/default_reminder_method_applicability.yaml`：有序候选、五类目标适用集合、无交集和“既有Reminder零变化”。
- [ ] Search Contract兼容revision：additive `search.get_workspace_history/replace_workspace_history` Schema、workspace/route/history revision、旧全局v1→guest一次迁移和account AEAD生命周期；旧local方法不形成第二writer。
- [ ] 复核现有 `event.update` 整系列与 occurrence cancel/complete/reopen Schema可以进入同步typed mutation；三作用域operation在R2-C不得出现。
- [ ] `contracts/user/`：资料安全投影、profile/preferences 双 revision、download-only change 与 cached snapshot Schema；收紧 update request 的字段 owner。
- [ ] 更新通知 tap payload 与调度 identity Contract：兼容旧 reader、v6 writer 强制 workspace identity，并增加歧义拒绝 fixture。
- [ ] `contracts/common/`：仅在真正跨版本域稳定时新增公共类型；不得让 API/Native envelope 互相 `$ref`。

### 9.3 映射与状态

- [ ] 更新 `backend_api.yaml`、`method_channels.yaml`、`native_calls.yaml`。
- [ ] 更新 `enums.yaml`：WorkspaceKind、SyncRunState、SyncMutationType、SyncTargetType、SyncUploadResultStatus、SyncConflictStatus、SyncResolutionMode、ImportStatus、DeviceStatus 等稳定字符串。
- [ ] 更新 `error_codes.yaml` 并为每个错误声明边界、retryable、是否允许已保存数据、可选 context shape。
- [ ] 更新 `contracts/storage/calendar_core_storage.yaml`，新增冻结的 v6 节点且保留 v5 节点/hash 不变。
- [ ] 新建 PostgreSQL 逻辑模型机器文件或等价 Schema，供 Backend migration 测试核对；不得让 JPA Entity 充当 Contract。

## 10. SQLite v6 逻辑模型冻结

SQLite v6 的精确 DDL 由本计划机器文件冻结，C++ 分计划只实现，不自行改列。至少包含：

| 表 | 核心列/约束 | 说明 |
| --- | --- | --- |
| `workspace_metadata` | 单行 workspace id/kind/account id/schema/encryption profile/created_at；guest另有current import source epoch与previous-epoch cleanup gate | 账号绑定不可变；游客 account id 必须 null；epoch只在精确compare-and-retire事务安全加一，溢出fail closed |
| `workspace_preferences` | 固定白名单列或严格 versioned payload + revision | 不允许任意 settings key；账号写参与 Outbox |
| `account_profile_cache` | 安全资料投影、profile revision、server received/updated time | 仅账号 workspace；download/API snapshot 写不产生 Outbox；不含 token、密码、challenge、密钥 |
| `sync_state` | device id、sync transport generation、local receipt-ack与server-accepted水位/dirty、cursor/account generation/cleanup水位、status/backlog、next/last-claimed notice sequence、enabled/policy revision、nullable transport-terminal code/evidence hash/binding | ack/apply/ack-only flush各自原子且水位不倒退；旧transport response拒绝；terminal gate跨重启阻断upload writer/prepare；每设备隔离；fresh genesis与clear rebuild按冻结fence/policy seed恢复 |
| `sync_local_device_causal_anchors` | target/entity/merge key、最近成功应用的本机sequence/resulting version | receipt裁剪后仍可生成合法后继；conflict/rejected/staged不推进 |
| `sync_awaiting_change_groups` | effect group id/末序列、target/entity、upload receipt identity、created_at | ack→apply强杀恢复门禁；apply精确组同事务删除，普通writer不可绕过 |
| `sync_policy_operation_receipts` | operation id、expected/resulting policy revision、enabled、result hash | 每workspace只保留当前latest receipt；C++提交后响应丢失可幂等恢复，同id异payload fail closed；协调器闭合旧journal后发起新operation，新operation接纳事务才可替换旧receipt，O(1)且不按年龄误删 |
| `sync_conflict_notice_queue/journal` | device + immutable notice sequence/id/set；generation+upper-bound discovery set | terminal page净集合入队；claim原子推进持久水位并清已claim前缀；terminal窗口清journal，resolved过滤actionability |
| `sync_outbox` | mutation id、client sequence、target、operation、base version、per-key causal predecessors、typed payload、payload hash、route、状态/重试 | `(device_id, client_sequence)` unique；prepared/sent不可改；因果链引用更早同设备sequence |
| `sync_failed_local_changes` | failed change/mutation id、target/entity/merge keys、typed intent/local candidate/manual draft、base/predecessor、failure code/safe context、revision、superseding mutation与状态 | rejected ack与Outbox终结同事务写；device-local、不可上传；download/bootstrap按其重放presentation，discard或成功supersede才清 |
| `sync_entity_state` | target/entity、entity version、last sequence、field-version map、nullable device-local awaiting-server-adjudication keys | field map必须由registry严格验证；pending overlay竞争只等待Backend裁决，不自造conflict id或增加unresolved计数 |
| `sync_deleted_entity_anchors` | target/entity、delete entity version/server sequence、nullable immutable import lineage/source workspace/source epoch/source identity | tombstone payload清理后仍持久；支持delete-vs-edit裁决、bootstrap marker验证与同epoch历史source mapping重建，不含已删业务payload |
| `sync_change_receipts` | generation + server sequence、payload hash、applied_at | download/operation 幂等，尤其 Habit 增量 |
| `sync_conflicts` | conflict id/version、target、blocked merge keys、server/local candidate、auto-merged groups、source device、status/timestamps | unresolved 无限期并pin相关tombstone；resolved retain 30 天 |
| `sync_import_batches` | lineage/batch/predecessor、source workspace/epoch/snapshot hash、per-target/portable-preference/total counts、total canonical bytes、mapping/manifest hash、begin/terminal client sequence、active route reservation、takeover reason/range-close proof、stage、reconciliation/resume/abandon状态、server expiry/error | 隔离local staging、跨库恢复、提醒抑制、successor与Backend exact confirmation；abandon/takeover不属于Outbox receipt；active range防普通mutation占位，compact terminal range按origin confirmed-through+180天保留 |
| `sync_import_items/staging_*` | batch id + ordinal unique、target/id、mutation/hash、staged/terminal status、typed staged graph | commit确认前live account读取不可见；证明0..N-1完整 |
| `sync_import_mappings` | lineage + source workspace/epoch/target/id → target target/id、first/last published batch、provenance version | 由publish group或bootstrap facts/deleted anchors原子重建/校验，账号销毁前不由maintenance删除；只作为同epoch successor source-set union与碰撞映射依据，completed旧epoch不得进入新epoch删除闭包 |
| `sync_import_publish_staging_*` | publish group、begin/chunk/commit receipt、ordinal/digest | 增量跨页耐久staging；commit完整时才与live facts/cursor原子发布 |
| `guest_import_cleanup_receipts` | guest workspace + source epoch + lineage/through-published-batch/import-revision/source snapshot/mapping digest、cleaned_at、receipt hash | 只在精确guest清理同事务写，并与current source epoch加一/previous-epoch gate原子提交；不含account id/token，供账号库丢失后补该epoch整条published predecessor chain的cleanup confirmation |
| `guest_import_source_leases` | stable source workspace唯一键、source epoch、opaque lineage id、protected account-binding digest、snapshot compare字段、reserved operation/active batch/range、state/revision | reserved→account receipt→active双库saga；跨账号/退出/clear/device/30天保留，只有冻结release闭包才释放；不含账号明文，graph hash/epoch不参与唯一键以防换epoch绕过active owner |
| `guest_import_audit_anchors`（逻辑名） | guest target/reminder identity、source epoch/lineage、retired reason/time、最小引用字段 | live图退休后承接终态Reminder/Notification审计引用；普通业务查询和后续import manifest均排除，不保存可删除的完整业务payload；精确DDL名与FK在冻结时唯一确定 |
| `habit_check_in_operations` | operation id、habit/date/type/delta-or-total、mutation id、applied state | increment/decrement/replace/clear 去重 |
| `sync_bootstrap_staging_*` | bootstrap id/page receipt/typed staged facts/tombstones/deleted anchors/unresolved conflicts/markers/causal anchors | 完整校验后与cursor、永久mapping原子发布；不得半快照覆盖 live facts/conflict store |

规则：

- v5→v6 必须先运行完整冻结 v5 checker，再在一个 `BEGIN IMMEDIATE` transaction 中增加精确对象、metadata、history 和 `PRAGMA user_version=6`。
- guest v6 可为明文 profile，account v6 必须是加密 profile；两者业务 Schema 相同，但 key/open policy 不同。
- 既有 20 个业务表、索引、payload bytes、position、generation、history 和 JSON guard 均保持不变，除非单独 migration 步骤有明确机器定义。
- account workspace 的普通local-user业务writer在同一事务写live事实 + generation/history + Outbox；guest对应writer只写事实/history且Outbox恒为零。Import不走该通用规则：commit只写guest source lease与账号隔离staging/manifest/begin-items-commit Outbox，直到权威publish group/marker被原子apply才发布live事实。Conflict resolution先写本地resolution intent/state + Outbox，只有服务端effect group或resolved delta被apply后才改live事实、冲突终态与计数。remote apply统一写事实/实体状态/receipt/cursor并明确抑制echo Outbox。
- Scheduler/Notification/Alarm/投递状态更新不产生同步 Outbox；这不是漏同步，而是 V1 数据闭包要求。
- schema checker 必须检查同名错定义对象、未知 metadata、非法 history、加密 profile、quick_check、关系和 payload codec。
- 导入图直到本机取得`publish_applied`前都只存在隔离staging，普通account查询不可见，reminder intent自然不得物化；`server_confirmed`只启动canonical publish group下载或bootstrap marker验证。只有commit完整时才在一个事务把服务端canonical设为baseline、按sequence重放pending与failed-local overlay、发布account live整图并记receipt；随后可恢复地按精确identity取消guest调度、清理guest源、启用/协调account提醒。任一点强杀均靠batch状态和幂等schedule key收敛为一份。
- 本地 maintenance 使用短小、有界事务：已解决冲突到服务端 `resolved_at + 30 days` 后先标记/识别 expired，再删除整条本地 resolved conflict及候选 payload，使UI不可再查询；resolution mutation 的重放幂等由独立 receipt安全窗口承担，不靠永久保留conflict行。`sync_change_receipts` 只能在当前 generation、已提交 cursor/retention floor 与 bootstrap 状态共同证明不会再合法重放时按水位裁剪，generation 未知、bootstrap 未完成或 cursor 落后时禁止删除。notice只能按`last_claimed_conflict_notice_sequence`清理已claim非head前缀，active discovery window不可删且terminal后必须释放journal。maintenance 不推进 cursor、不生成 Outbox，并可在 workspace open 与 Android 低频任务中安全重试。

## 11. PostgreSQL 逻辑模型冻结

Backend migration 至少实现并由 Contract fixture 映射以下逻辑表；实际物理命名在冻结后不得由实现层改写：

- `user_devices`：账号设备、installation 摘要、显示名、协议/App 版本、提醒设置、版本、last seen/sync、撤销信息；同账号 active installation 唯一，revoked row 不被重新激活。
- 既有 `user_sessions` 增加 nullable `device_id`、`registration_state` 与 attempted installation 摘要（或冻结的等价关联）：登录后尚未注册设备可为空；`device.register` 成功时在同一事务绑定，设备超限时只能进入上述受限 pending-registration；所有 sync API 在未绑定时返回 `DEVICE_NOT_REGISTERED`；撤销设备同时撤销其全部 session。
- `reauth_grants`：只保存 reauth token hash、account/session/nullable actor device、attempted installation 摘要、target device、purpose、expires/consumed time；5 分钟候选 TTL、单次消费，消费与 `device.revoke` 同事务。
- `account_profile_revisions`（或冻结的等价账号列）：资料 revision；资料/头像/确认邮箱更新与安全投影 change 在同一事务提交。
- `sync_device_state`：sync transport generation、highest client sequence、`client_confirmed_through`、blocked reason、last cursor摘要、account generation、last sync；confirmed不可倒退/超highest，所有写事务锁内验证transport generation。
- `sync_device_fence_receipts`：device + operation唯一、expected/resulting transport generation、reason、冻结sequence bundle、resolved absent-import fences与result hash；同id同payload永久幂等至device/account删除，同id异payload拒绝。
- `sync_device_causal_anchors`：每active device/target/entity/merge key最近成功应用的client sequence与resulting field version；不含payload，conflict/rejected/staged不推进，普通receipt过期不删除anchor，设备revoke后再按保留ADR清理。
- `sync_deleted_entity_anchors`：account/target/entity唯一，保存delete version/sequence与typed deletion marker，不含被删业务payload；tombstone清后仍保留至账号删除，供长期离线旧编辑形成delete-vs-edit conflict。
- `sync_mutation_receipts`：sequence/mutation/payload hash/稳定结果，以及每个merge key resulting field version；保留期不得短于离线与 tombstone 安全窗口。
- 各强类型事实表：Category、Event、Event recurrence revision、OccurrenceState、Anniversary/Recurrence、Habit/Recurrence/CheckIn、ReminderIntent；全部带 `account_id`、`entity_version` 和 tombstone 语义。
- `sync_entity_field_versions`：`account_id + target_type + entity_id + merge_key` 唯一，保存最近 entity version。
- `sync_account_sequences`：账号 generation、next server sequence、retention floor；分配不可依赖全局 wall clock。
- `sync_change_groups/items`：账号/generation/首sequence、group identity/hash；普通组把typed entity changes与conflict deltas不可拆绑定，import publish使用连续begin/chunk/commit并在同一服务端事务生成；均由同一cursor流读取。
- `sync_conflicts`：当前值、本机候选、blocked/conflicting merge keys、typed auto-merged groups、source device、版本、状态、received/resolved/retain_until及引用tombstone pin。
- `sync_import_lineages/batches/staging_items/receipts`：account/source workspace+epoch+snapshot、lineage/batch/predecessor/origin device及transport generation、per-target/total counts/bytes、mapping/manifest hash、isolated typed payload、ordinal `staged` receipts、terminal commit、lineage级`cleanup_confirmed_through_batch/revision`、expiry，以及独立HTTP abandon CAS/absent-batch-fence状态；同 ID 异 manifest失败，只有原子commit才发布canonical，head cleanup确认原子覆盖连续published predecessors。
- `sync_import_publish_markers`：lineage/batch/publish group/commit sequence/manifest/mapping identity的紧凑不可变证明保留至账号删除；即使大批payload、receipt和旧change已清，bootstrap仍据marker与当前canonical provenance动态生成digest/count并证明`publish_applied`。
- `sync_bootstrap_sessions` 与 `sync_bootstrap_items`：绑定account/device/protocol/generation/upper bound/expiry并冻结requesting-device highest/client-confirmed recovery bundle；items按kind/target/id/conflict-id/merge-key/ordinal排序，保存immutable typed fact after-image/tombstone、无payload deleted entity anchor、全部当前unresolved conflict、import publish marker或requesting-device causal anchor。V1不使用跨HTTP长事务；过期/superseded session分批清理。
- tombstone 可位于事实表并有独立清理元数据，或使用专表；无论物理选择如何，180 天保留、cursor floor 和 bootstrap 规则必须一致；被unresolved conflict引用时必须额外pin到解决后满足30天与安全cursor。

所有业务表查询同时以 Principal account scope 和数据库约束隔离。Backend request DTO、domain object、JPA Entity、change payload 与 Contract DTO 必须分离；不允许一个 JSONB 万能实体代替强类型列。JSONB 仅可保存已经由 `sync_field_registry` 验证的 patch/result 快照，并必须有 payload version/hash。

## 12. 错误与重试分类

最低错误集合在冻结时逐一补齐 context Schema：

| 类别 | 代表错误 | Retry 规则 |
| --- | --- | --- |
| 协议 | `SYNC_PROTOCOL_VERSION_UNSUPPORTED`, `SYNC_BATCH_TOO_LARGE`, `SYNC_PAYLOAD_INVALID` | 不自动无限重试；升级或诊断 |
| 顺序/幂等 | `SYNC_CLIENT_SEQUENCE_GAP`, `SYNC_SEQUENCE_REPLAY_MISMATCH`, `SYNC_SEQUENCE_ROUTE_MISMATCH`, `SYNC_CLIENT_SEQUENCE_EXHAUSTED`, `SYNC_SERVER_SEQUENCE_EXHAUSTED`, `SYNC_TRANSPORT_GENERATION_MISMATCH`, `SYNC_TRANSPORT_GENERATION_EXHAUSTED` | gap先本机修复；replay/active-import-route mismatch与数值耗尽先经internal native terminal入口耐久冻结；旧transport generation是lifecycle-stale且零写，旧worker停止，由当前Broker恢复/执行fence，不能被当业务corruption；generation耗尽禁止该device再开可写库 |
| 其他计数器耗尽 | `WORKSPACE_ROUTE_REVISION_EXHAUSTED`, `LOCAL_SETTINGS_REVISION_EXHAUSTED`, `WORKSPACE_LIFECYCLE_REVISION_EXHAUSTED`, `AUTH_TOKEN_GENERATION_EXHAUSTED`, `SYNC_POLICY_REVISION_EXHAUSTED`, `SYNC_STATUS_REVISION_EXHAUSTED`, `SYNC_NOTICE_SEQUENCE_EXHAUSTED`, `SYNC_COUNTER_EXHAUSTED` | 严格按§6.1 counter registry零写或进入一次性durable terminal；`SYNC_COUNTER_EXHAUSTED.context.counter_kind`闭合，不自动换identity、回0或用时间戳替代 |
| Cursor/Bootstrap | `SYNC_CURSOR_INVALID`, `SYNC_CURSOR_EXPIRED`, `SYNC_CURSOR_ACCOUNT_MISMATCH`, `SYNC_CURSOR_DEVICE_MISMATCH`, `SYNC_CURSOR_GENERATION_MISMATCH`, `SYNC_BOOTSTRAP_EXPIRED`, `SYNC_BOOTSTRAP_GENERATION_CHANGED` | cursor expired/generation mismatch 进入 bootstrap；bootstrap expired/generation changed 丢未发布 staging 后重新首请求；tamper/跨账号/跨设备不重试 |
| 能力/设备 | `SYNC_NOT_ENABLED_FOR_ACCOUNT`, `DEVICE_LIMIT_REACHED`, `DEVICE_NOT_REGISTERED`, `DEVICE_NOT_FOUND`, `DEVICE_REVOKED`, `DEVICE_VERSION_CONFLICT`, `DEVICE_REAUTH_REQUIRED`, `DEVICE_REAUTH_TARGET_MISMATCH` | 非白名单不创建device/workspace；revoked 统一退出并清缓存；grant 不匹配不重试 |
| 本机设置CAS | `SYNC_POLICY_VERSION_CONFLICT`, `LOCAL_SETTINGS_VERSION_CONFLICT` | 返回current enabled/policy/local-settings revision；不改C++ policy、Registry、Work、reconcile或remote reporter，UI重读后由用户决定是否重试 |
| Workspace/密钥 | `WORKSPACE_NOT_FOUND`, `WORKSPACE_ACCOUNT_MISMATCH`, `WORKSPACE_LOCKED`, `WORKSPACE_KEY_UNAVAILABLE`, `WORKSPACE_SWITCH_CONFLICT` | fail closed；不回退游客库 |
| 通知路由 | `NOTIFICATION_WORKSPACE_AMBIGUOUS`, `NOTIFICATION_WORKSPACE_UNAVAILABLE` | legacy 缺 identity 且不唯一时拒绝；显式 workspace 当前不可见/不可解锁时不跨库搜索 |
| 本地数据/导入 | `SYNC_OUTBOX_CORRUPTED`, `SYNC_APPLY_FAILED`, `SYNC_BOOTSTRAP_INCOMPLETE`, `IMPORT_SOURCE_CHANGED`, `IMPORT_SOURCE_OWNED`, `IMPORT_SOURCE_EPOCH_EXHAUSTED`, `IMPORT_LINEAGE_MISMATCH`, `IMPORT_VERSION_CONFLICT`, `IMPORT_PUBLISH_INCOMPLETE`, `IMPORT_BATCH_ABANDONED`, `IMPORT_BATCH_SUPERSEDED`, `SYNC_IMPORT_CAPACITY_EXCEEDED`, `SYNC_CHANGE_GROUP_TOO_LARGE` | 保留原数据；source-owned要求切回持有opaque lease的原账号收尾且不泄露身份；epoch exhausted不阻止已发布批cleanup/lease释放，但永久禁止该guest workspace新导入；import CAS冲突返回current stage/head/revision且零写；abandoned/superseded批的残留sequence稳定消费且零canonical；capacity需resume/HTTP-abandon释放，privacy destroy以typed unconfirmed结果表达 |
| 本地诊断 | `SYNC_DIAGNOSTIC_EXPORT_FAILED` | 不改变同步/notice状态；清理半成品并允许用户重试 |
| 冲突/效果门禁 | `SYNC_CONFLICT_NOT_FOUND`, `SYNC_CONFLICT_VERSION_MISMATCH`, `SYNC_CONFLICT_ALREADY_RESOLVED`, `SYNC_ENTITY_CONFLICT_BLOCKED`, `SYNC_ENTITY_SYNC_EFFECT_PENDING` | stale version重新加载；普通writer命中unresolved或ack待apply门禁均零写，后者先恢复下载精确组 |
| 本机失败意图 | `SYNC_FAILED_CHANGE_NOT_FOUND`, `SYNC_FAILED_CHANGE_VERSION_CONFLICT` | 重读本地列表/详情；不得把failed overlay重新塞回旧sequence，用户另存时生成全新mutation |
| Auth | `AUTH_SESSION_EXPIRED`, `AUTH_REFRESH_TOKEN_REUSED`, `AUTH_SESSION_ACCOUNT_MISMATCH`, `AUTH_REAUTH_FAILED` | identity mismatch 清除 pending adoption 并 fail closed；其余按分类停止同步/进入 reauth，不盲目重试 |
| 会话保留 | `RETENTION_TRUSTED_TIME_REQUIRED` | 不自动重试或静默改选；保持logout operation、writer gate、Session、cache与route，重读`allowed_cache_policies`后由用户取消/重试server logout或确认destroy-now |
| Transport | DNS、TLS、timeout、offline、HTTP 无合法 envelope | Kotlin transport failure；指数退避，不伪装业务码 |

可重试429、冻结列表内的5xx/DNS/timeout使用同一强制算法：第`attempt`次（从0开始）取full jitter `uniform[0, min(15min, 5s × 2^attempt)]`；连续自动尝试最多8次。合法`retry_after_seconds`范围为1..86400，只能把本次delay提高为`max(jitter, hint)`并封顶24小时；B0 ADR若保留HTTP `Retry-After`，它必须是同一数值的兼容镜像，body/header不一致按非法envelope处理。没有server hint仍使用基础算法，绝不能直接blocked或无限热循环。预算耗尽后进入retryable failed，等待用户手动、离线→在线或间隔至少30分钟的前台恢复开启一轮新预算；一次成功exchange清零。Contract/data corruption、未知enum、非法业务envelope、证书/hostname失败和sequence mismatch立即诊断/blocked，不因手动同步绕过分类。

## 13. Fixtures 与 Validator

### 13.1 Fixture 目录

建立 `contracts/fixtures/sync/v1/manifest.json`。每个 fixture 记录稳定 ID、`rule_anchor`、输入文件、期望结果或错误、适用 consumer，以及是否要求 byte-for-byte hash；期望语义只引用第 5–12 节，不在 manifest 或下游计划中另写一份算法。

| Fixture 族 | 唯一规则锚点 | 必须覆盖的变化维度 |
| --- | --- | --- |
| `FX-TARGET` | §7.1–§7.3、§7.7 | 各 target 的合法 operation、exact-key/null/引用反例；Event timed/all-day、日期/时间/IANA/DST；Habit 专用 operation；Reminder intent 上传白名单与本机事实拒绝；R3 recurrence 方法不存在性 |
| `FX-MERGE` | §6.2、§7.2–§7.5 | 独立 merge key、同 key、相同值、delete-vs-edit、restore、partial merge 投影、同设备连续编辑和跨设备插写 |
| `FX-CONFLICT` | §7.5、§8、§12 | created/resolved 跨设备闭环、entity writer gate、四类 resolve 业务拒绝、迟到/重复 delta、分页和红点收敛 |
| `FX-SEQUENCE` | §6.1–§6.2、§12 | duplicate prefix、gap、同序号异 payload、route mismatch、transport fence 竞态、耗尽、HTTP 后到 Native terminal 前的强杀恢复 |
| `FX-CANONICAL` | §4.2、§6.2 | RFC 8785 官方/等价边界向量、业务 envelope、64 位小写 hex SHA-256、Windows/C++/Android 三 ABI/Java 一致，以及 identity-array 误用负例 |
| `FX-COUNTER` | §6.1 | registry 中每个 owner 的 max−1→MAX、MAX 后重试、并发、response-loss、strict context 和各类 MAX 动作 |
| `FX-RUN` | §6.2–§6.3、§8 | 四种 prepared exchange union、仅 normal 可 apply、五种 original status duplicate、ack watermark/dirty flush、暂停下 ack-only、reenable pull gate 与 fresh DB 确认基线 |
| `FX-FAILED-LOCAL` | §6.2、§7.5、§8 | rejected 后 overlay 保留、download/bootstrap/restart 重投影、discard、编辑另存新 sequence，以及 pending/failed/conflict 计数隔离 |
| `FX-CURSOR` | §6.3、§12 | tamper、account/device/generation mismatch、expired、terminal cursor、固定上界和页面间新增写入 |
| `FX-BOOTSTRAP` | §6.3、§8、§10–§11 | 各 union 最大 item/hard cap、facts/tombstones/deleted anchors/全部 unresolved conflicts/import marker/causal anchor、TTL、重复/漏/乱序页、finalize/rebase/delete 竞态和每个强杀点 |
| `FX-WORKSPACE` | §5、§8.3–§8.4、§10 | ready/locked/empty null 矩阵、workspace/runtime identity owner、旧 event/route revision、guest/account/A/B 隔离、v5→v6、wrong key/binding、fresh seed 与 revoked device |
| `FX-IMPORT-STAGE` | §7.6 `IMP-01`–`IMP-06` | 双库 reserved→receipt→active 强杀点、begin/item/commit、manifest/ordinal/domain/cap 边界、九个 stage、三个正交 enum、exact-batch 与 source discovery |
| `FX-IMPORT-PUBLISH` | §7.6 `IMP-03`–`IMP-05` | 原子整图发布、500 项跨页/强杀、server-confirmed 与 publish-applied 区分、repair successor、历史 mapping 并集和 typed delete |
| `FX-IMPORT-RANGE` | §7.6 `IMP-07`、`IMP-08`、`IMP-12` | partial prefix、batch absent 的 next/gap/占号、seen/never-visible proof、takeover actor/reason、旧 commit 竞态、response-loss、TTL payload 回收、离线 abandon 与 proof 接纳后的 ack-only |
| `FX-IMPORT-CLEANUP` | §7.6 `IMP-09`–`IMP-10` | epoch 0→1、MAX epoch、previous-epoch gate、A/B lease ownership、四类允许 proof、source_migrated 执行终结、终态审计 anchor、Search History 不复制和 account-deleted 收尾 |
| `FX-PREFERENCE` | §7.7、§8、§10 | 四字段白名单、默认提醒有序候选/适用矩阵、timezone 双轴、appearance 一次迁 guest、Search History A/guest/B 隔离与 account 加密、profile download-only 双 revision |
| `FX-SESSION-DEVICE` | §8、§12 | adopt/account binding、pending registration 白名单、reauth、设备名边界、提前 401 single-flight、logout review/force-local、`allowed_cache_policies`、无锚retain零副作用拒绝、active+local、settings reporter 与未来设备默认 |
| `FX-RETENTION-NOTIFY` | §7.6 `IMP-08`–`IMP-10`、§8、§12 | 30 天可信时间矩阵、retained必有deadline、API 24+进程/系统重启与boot-count异常、API 23/process-only、备份恢复/AAD/UUID复用fail-closed、key 已毁文件残留、v6/legacy notification workspace 路由、guest“本机”标签、导入前后提醒唯一性 |
| `FX-MAINTENANCE` | §6.2–§6.3、§7.5、§8、§10、§12 | receipt/conflict/notice 水位、百万 notice 窗口、policy operation response-loss、transport retry 分类、remote device cache 加密与脱敏诊断/FileProvider TTL |
| `FX-CROSS-LAYER` | §9、§13.2 | Backend、Dart、Kotlin、C++ 对全部适用 fixture 的 byte/semantic round trip，以及每个 Schema/方法/error 的 consumer 闭包 |

任何新增边界只应新增 fixture 维度或修改其 `rule_anchor`；不得把规则正文复制到 fixture 名称、README、下游测试计划或完成清单。

### 13.2 Validator 必须检查

- Draft 2020-12 Schema、`$ref` closure、`oneOf` 排他性、exact keys、safe integer、nullable 语义。
- `sync_field_registry` 与所有 entity Schema、enum、error、merge key 完全闭合。
- `sync_counter_registry`中的每个counter恰有一个owner，所有可单调推进的公开safe-integer计数器字段均被覆盖；MAX动作、stable error、strict context与各层状态/方法Schema一致。
- Backend API ↔ Kotlin HTTP DTO ↔ C++ apply payload 使用同一 Sync Protocol Schema；只允许 envelope 不同。
- MethodChannel 每个方法有实现路径；Native call 每个方法有 Kotlin bridge/C++ boundary 目标；Kotlin-local 方法不得伪造 JNI。
- 敏感字段不会出现在 response、event、日志 fixture 或 ordinary cache。
- Storage v5 hash 保持不变、v6 只通过相邻迁移、旧 runtime 对 v6 拒写。
- capability 状态不能在任一消费层缺失时提前 active。

机器入口固定为 `contracts/run_sync_v1_validation.py`（若仓库命名规范要求不同，可在冻结前一次性调整并同步五计划）。Validator 必须由普通开发环境和 CI 重复执行，不依赖真实用户数据。

## 14. 实施阶段与依赖

阶段只安排产物和依赖，不重复定义协议：

| 阶段 | 规范性工作锚点 | 必交证据 | 退出条件 |
| --- | --- | --- | --- |
| CT0 冲突审计与 ADR | §3–§4 | ADR/spike 结论、每项冲突的 Source of Truth/替代规则/影响层、JCS 与 counter 可执行 golden | 无影响 Schema 的未决项；否则 `DECISION REQUIRED` |
| CT1 领域与字段注册表 | §6–§7 | target/identity/merge key/field owner、nullable、权限、版本与冲突语义闭包 | 通用任意 payload 已退出目标状态，所有字段可机器追踪 |
| CT2 HTTP / Native 能力图 | §8 | Auth/Profile 校准和每个公开方法的 Kotlin-local、HTTP、JNI workflow 唯一路径 | 无孤立公开方法或无上游 production native call |
| CT3 Schema、错误与存储 | §9–§12 | 机器定义、兼容矩阵、前滚/回退行为 | Schema/ref/enum/error/storage 静态闭合 |
| CT4 Golden 与冻结评审 | §13、§15–§17 | 四层 parser/validator 结果、既有领域回归、签署的 Contract revision/hash | 达到 `CONTRACT FROZEN` 后才允许实现分支 |

## 15. 下游交付契约

| 下游 | 本计划提供 | 下游必须回报 |
| --- | --- | --- |
| C++ / SQLite | Native request/response、field registry、v6 DDL/迁移、fixture | Boundary 映射、事务/Outbox/apply/bootstrap/导入测试、storage checker hash |
| Cloud Backend | HTTP operation、Sync Protocol、PostgreSQL 逻辑模型、错误/幂等 | Controller/Application/Repository/Migration 映射、并发/隔离/清理/容量证据 |
| Kotlin / Android | MethodChannel、Native call、HTTP payload、Broker/Workspace 状态 | 每方法实现路径、线程/生命周期/Keystore/WorkManager/JNI/设备证据 |
| Flutter | MethodChannel、Backend Auth 校准、typed UI response/error | DTO/Gateway/Application/UI 映射、状态机、Widget/adapter 测试 |

任何下游需要改变字段、方法、错误或状态时，必须先回到本计划修改 Contract 和兼容矩阵；不得在实现计划中用“临时字段”绕过。

## 16. 验证矩阵

| 证据包 | 通过标准 |
| --- | --- |
| Validator | `run_sync_v1_validation.py` 正例通过、负例失败；既有 Contract validator 无回归 |
| 现状校准 | Backend API 17 个声明逐项核对，16 个已实现端点的差异有处置，延迟端点状态真实 |
| 兼容性 | Native v2、`sync.apply` 墓碑、Broker 切换、Appearance/Preferences 和 reader/writer 矩阵完整 |
| 存储 | SQLite v5 hash 未变；v6 fresh/migrate/downgrade/corruption 与 PostgreSQL 逻辑模型均被机器检查 |
| 跨层一致性 | 03–06 对 `FX-*` 的字段、null、enum、时间、错误、hash、counter owner/action 和 round trip 结果一致 |
| 变更卫生 | diff 不含实现代码、无关格式化或伪造的“已完成/已验证”状态 |

## 17. 完成定义

本计划只有在以下条件同时成立时才标记 `CONTRACT FROZEN`：

- [ ] CT0–CT4 的退出条件及第 16 节全部证据已签署，关键技术选择无悬空。
- [ ] 第 5–12 节均有唯一机器表示；所有 mutation 为 target-specific typed payload，兼容与失败行为闭合。
- [ ] 03–06 已锁定同一 Contract revision/hash，并用第 13 节相同 fixture manifest 证明消费结果一致。
- [ ] 状态只表示设计与 Contract 已冻结，不暗示任何实现层或真实多设备集成已经完成。

## 18. 本计划之外

- 不实现 C++、Kotlin、Flutter 或 Backend 业务代码。
- 不选择或升级未经 ADR/spike 批准的 SQLCipher、HTTP、序列化或状态管理依赖。
- 不把 V1.1 历史、V2 备份、FCM、服务端提醒、附件、共享协作或微信扩入 V1 Contract。
- 不修改既有已应用 migration、SQLite v5 冻结节点或已发布 active 方法的语义来省略 v6/兼容设计。
