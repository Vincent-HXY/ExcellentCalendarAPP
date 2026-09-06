# 云同步-04：CloudBackend 开发计划

> 状态：ACTIVE PLAN / CONTRACT FROZEN / IMPLEMENTATION NOT STARTED
> 2026-09-07 Review 修订：提交 `5d8fb0a` 的 11 类问题经独立复核成立，修订依据和跨层交接规则见[Review 复核与兼容修订记录](./云同步-02-Review复核与兼容修订记录.md)。03–06 以机器锁中的最新内容摘要为共同输入；初次交付的旧摘要仅作历史记录。
> 建立时间：2026-09-04
> 上位计划：[云同步-01：Local-first 多设备同步开发计划](./云同步-01-Local-first多设备同步开发计划.md)
> 协议与数据前置：[云同步-02：Contracts 与数据模型开发计划](./云同步-02-Contracts与数据模型开发计划.md)
> 负责范围：`cloud_backend/**` 内的 Spring Boot API、Application、Domain、PostgreSQL/Flyway、同步清理任务、测试与测试服务器制品
> 协作下游：云同步-03（C++/SQLite）、云同步-05（Kotlin/Android）、云同步-06（Flutter）及真实跨层集成
> 文内语义锚点：第 5–13 节定义 Backend 设计；第 14–19 节只描述实施顺序、测试证据、部署和交接门禁，不得形成第二套协议定义。

> 协议输入锁：`contracts/sync/sync_v1_revision_lock.json` 中的 `04_cloud_backend` 与其他三端锁定同一 revision/hash/fixture manifest。只在 `contracts/run_sync_v1_validation.py` 默认入口通过后按该机器版本实施；本层生产 implementation/release status 仍为 planned。

## 1. 目标、状态与完成口径

本计划在不改变 Local-first 边界的前提下，把冻结后的 Sync Protocol v1 落到现有 Java 21 / Spring Boot 模块化单体中。CloudBackend 负责认证账号下的设备登记、上传顺序与幂等、强类型云端事实、字段组版本合并、change feed、冲突、bootstrap、保留策略和账号隔离；它不替代客户端 C++ Core，不展开 occurrence，也不负责本机提醒调度。

当前只完成计划设计，尚未修改 `cloud_backend/**`。在云同步-02 达到 `CONTRACT FROZEN` 前，本计划只能执行只读盘点、Contract 对照和明确获批的基础设施 spike，不得创建同步 Controller、表、临时 payload 或兼容错误码。

本计划实施后的单层最高状态是 `BACKEND IMPLEMENTED / AWAITING INTEGRATION`。只有同一真实 APK、真实 SQLite、真实 Backend 和至少两台 Android 设备通过云同步-01 的端到端矩阵后，相关 capability 才能统一切换为 `integrated + active`。

## 2. 继承的不可变边界

冲突裁决只使用云同步-01 §1.1：当前行为按active machine Contract/Schema → 当前领域不变量 → Accepted ADR → active计划 → 架构 → 实现判断；本次目标如改变前三者，先完成ADR/领域/Contract及迁移。云同步-02冻结前只是目标草案，Backend不得用planned Schema覆盖现有active接口；冻结后机器Contract是Controller/DTO/DDL的直接真相源，本文示例冲突时必须回流修正而不是兼容两套。

以下规则直接继承云同步-01 和云同步-02，本分计划无权改变：

1. 客户端 SQLite 继续是离线业务真相源；Backend 是账号同步中枢，不是客户端 Core 或本地数据库的替代品。
2. 游客 workspace 永不上传；Backend 不接受游客数据、客户端声明的 `account_id` 或 `user_id`。
3. Backend 只从验证后的 bearer Principal 获取账号和会话身份，并校验 session 绑定的注册设备。
4. `client_sequence`、`mutation_id`、`entity_version`、`server_sequence`、JPA `@Version` 和通用 HTTP `Idempotency-Key` 是不同机制，禁止互相代替。
5. 合法上传批次的业务事实、字段版本、tombstone、change、conflict、mutation receipt 和设备最高序号必须在同一 PostgreSQL 事务提交。
6. 不同 `merge_key` 可以自动合并；同一 `merge_key`、delete-vs-edit、clear/replace-vs-increment 等真实竞争进入冲突中心。
7. Reminder 只保存用户意图或模板。Android 权限、Alarm、Work、RingSettings、铃声 URI、Notification、投递历史和本机搜索历史不得进入 Backend。
8. Backend 不运行 Event、Habit 或 Anniversary recurrence engine，不展开未来 occurrence，不重算 Habit 统计。
9. HTTP 使用 `ApiResult<T>`；不得复用 Native `NativeResult<T>`，不得在 Java 内复制未受机器 Contract 校验的字段表或错误字符串。
10. V1 无 FCM、附件、共享协作、服务端到期提醒、历史恢复、整账号备份、Redis/MQ 强依赖或高可用集群。
11. 现有认证、资料与头像能力必须被保护；云同步不得降低 Refresh Token 轮换、账号隐私、头像处理或既有数据库约束的安全性。
12. `account_profile` 只含 `email/username/display_name/avatar` 安全投影，只能由资料、头像和确认邮箱的服务端流程产生并供客户端下载；`user.update_current` 只写 `username/display_name`。`timezone`、`habit_progress_color`、`default_reminder_methods` 与 `auto_enable_reminders_on_other_devices` 的唯一同步 owner 是 `user_preferences`；locale在V1只保留历史兼容读取/审计，不接受用户更新或同步。当前注册兼容入口仅接受固定`zh-CN`并初始化同值历史字段，不产生locale change。
13. 第 11 台设备注册失败后，只能进入绑定当前 Session 与本次 installation 摘要的 `pending_registration` 受限态；该状态不是已注册设备，除白名单中的 `user.get_current` 身份快照与设备恢复能力外，不能访问账号事实、任何写资料入口或同步接口。
14. 游客导入只有在 Backend 对同一 manifest 的全部 ordinal 与 terminal commit 给出完整耐久回执、且没有 `rejected` 项后才可确认；`conflict` 可表示候选已耐久接收，但绝不等于自动解决。
15. `auto_enable_reminders_on_other_devices` 只决定未来新设备注册时的 `receive_reminders` 初值，默认 `false`；首台设备固定为 `true`，既有设备之后只受各自设备开关控制，偏好变化不得回写既有设备。

## 3. 当前实现基线：事实证据

下表仅陈述 2026-09-04 的仓库事实，不表示同步能力已经完成。

| 范围 | 路径 / 符号 | 已确认事实 | 状态 |
| --- | --- | --- | --- |
| 构建 | `cloud_backend/pom.xml` | Java 21、Spring Boot 4.1.0、Spring MVC、JPA、Flyway、Spring Security、Spring Modulith、Maven Wrapper；Failsafe 执行 `*IT` | 可复用 |
| 运行角色 | `boot/api`、`boot/worker`、`boot/scheduler`，`application-*.yml` | 单制品按 `api/worker/scheduler` Profile 装配；Worker/Scheduler 尚无业务任务 | API 可用；后台占位 |
| 认证 API | `RegistrationController`、`SessionController`、`PasswordController`、`EmailChangeController` | 注册/验证/重发、登录/刷新/logout/logout_all、密码重置/修改、邮箱修改共 12 个端点已实现 | 已实现，Contract 未激活 |
| 资料 API | `UserController`、`AvatarController` | `user.get_current`、`user.update_current`、头像上传/删除共 4 个端点已实现 | 已实现，Contract 未激活 |
| 声明端点 | `contracts/backend_api.yaml` | 当前声明 17 个端点；其中 `auth.registration.email.update` 尚无 Controller，其余 16 个存在实现；顶层及逐端点仍为 `planned` | 状态待校准 |
| 安全 | `ApiSecurityConfiguration`、`BearerTokenAuthenticationFilter`、`DbAuthenticatedPrincipalResolver` | 无状态 bearer 链；JWT 携带账号 `sub` 与会话 `sid`，每次请求回查 Session/Account；未知 API 默认拒绝 | 可复用 |
| 会话 | `SessionService`、`RefreshTokenGrantRepository.findWithLockingByTokenHash` | Refresh Token 只存哈希；刷新使用悲观锁并原子轮换；重放撤销 token family | 可复用 |
| 设备关联 | `UserSessionEntity`、`V1__identity_schema.sql` | Session 有 `platform/device_name/app_version` 列，但当前签发只固定 `platform=android`；没有 `device_id`、installation 身份或设备撤销映射 | 缺失 |
| 用户偏好 | `UserSettingsValue`、`UpdateCurrentUserRequestDto` | `settings` 当前接受最多 64 个任意合法标量键；`default_reminder_methods` 接受 `wechat` | 与 V1 白名单目标冲突 |
| 资料边界 | `UpdateCurrentUserRequestDto`、`CurrentUserResponseDto` | 当前 `user.update_current` 同时接收 profile 与 locale/timezone/reminder/settings；响应没有 profile/preferences revision，也不会追加同步 change | 与 download-only `account_profile` 目标冲突 |
| 通用幂等 | `IdempotencyFilter`、`idempotency_records` | 24 小时成功响应缓存；未计算请求 payload digest，同 key 异 payload 会重放旧成功 | 不可承担同步幂等 |
| HTTP 错误 | `ApiErrorCode`、`GlobalApiExceptionHandler`、`ApiSecurityErrorHandlers` | 实现返回语义 4xx/5xx；429 同时发送 `Retry-After` | 与当前 planned Contract 文本冲突 |
| Auth 错误枚举 | `contracts/common/api_error.schema.json`、`ApiErrorCode` | Contract 的 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`、`AUTH_ACCOUNT_NOT_FOUND`、`AUTH_ACCOUNT_ALREADY_VERIFIED` 不在 Java enum；后二者属于尚未实现的 `auth.registration.email.update` | 映射不闭合 |
| PostgreSQL | `src/main/resources/db/migration/V1__identity_schema.sql` 至 `V3__avatar_assets.sql` | 只有账号/资料/会话/幂等、邮箱修改、头像资产表；无设备、日历事实、同步、change、conflict、import 表 | 同步缺失 |
| 业务模块 | `calendar/package-info.java`、`sync/package-info.java` | 两个模块只有边界说明，没有 Controller、Application、Domain、Repository 或 Migration | 占位 |
| 设备模块 | `userdevice/**` | 已实现资料、偏好和头像编排；没有设备实体、Repository、服务或 API | 部分实现 |
| 模块验证 | `ModuleArchitectureTest` | Spring Modulith 当前验证直接子包和无环依赖 | 可扩展门禁 |
| PostgreSQL 测试 | `ApiIntegrationTestSupport`、`PostgreSqlInfrastructureIT` | Testcontainers 使用 PostgreSQL 17.11；`disabledWithoutDocker=true` 会在 Docker 不可用时跳过 | 可复用但需防伪通过 |
| 历史验证 | `cloud_backend/docs/implementation-status.md` | 2026-08-27 记录 91 个 JVM/上下文测试和 58 个 PostgreSQL 集成测试通过 | 历史证据；本次未重跑 |
| 本地 Compose | `cloud_backend/compose.yaml` | PostgreSQL 5432 与 API 8080 映射宿主机、API 由服务器现场 `build`、无 HTTPS 入口 | 仅本地开发可用 |
| 文档一致性 | `cloud_backend/docs/architecture.md`、`db/migration/README.md` | 仍有“业务路由未实现”“无 versioned migration”等过期描述，与实际代码/V1–V3 不一致 | 实施时需校准 |

本次计划编制未运行 Maven、Testcontainers、Migration 或部署命令；不得把历史验证记录表述为当前代码重新通过。

## 4. B0 前置门禁：Contract 与现状校准

### 4.1 已确认漂移及目标处理

| 议题 | 当前事实 | 目标处理 | 未解除前状态 |
| --- | --- | --- | --- |
| 端点状态 | 17 个声明均 `planned`，16 个已有实现 | 按真实 Controller、Schema 和测试逐项校准；延迟的 `auth.registration.email.update` 继续明确 `planned/blocked` | 禁止把 Backend 整体标 active |
| HTTP 状态 | Contract 写应用结果统一 HTTP 200；实现和 IT 使用 400/401/403/409/413/415/429/500 | 等待 Backend HTTP Contract Calibration ADR；按云同步-02 推荐，优先冻结“语义 HTTP 状态 + 合法 `ApiResult`”并同步客户端 | `DECISION REQUIRED` |
| 限流信号 | Contract 写 `retry_after_seconds` 是唯一信号；实现另发 `Retry-After` | ADR 明确是否保留 header；Backend 和 Kotlin 只实现冻结的一种组合 | `DECISION REQUIRED` |
| HTTP 幂等 | Contract 要求同 key 异 payload 失败；当前 Filter 不计算 digest并重放旧成功 | 冻结并实现 payload digest；不一致返回 `API_IDEMPOTENCY_KEY_REUSED` 或 Contract 最终等价码 | 现有端点不可激活 |
| Auth 错误 | Contract 已声明 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`，Java 现以 `AUTH_VERIFICATION_INVALID` 覆盖尝试耗尽；另两个缺失 enum 只服务延迟端点 | 校准 ADR逐 endpoint 选择并同步 Schema/Java/测试；不得为尚未实现端点伪造 active 映射，也不得静默保留双语义 | `DECISION REQUIRED` |
| 偏好白名单 | 当前 Contract/Java 允许任意标量 settings；`default_reminder_methods` 还接受 `wechat` | 严格收口为 `timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 `ring/popup`）、`auto_enable_reminders_on_other_devices`；locale历史值保留审计但新写/同步拒绝；Java、DDL和迁移同步收口 | 同步偏好 blocked |
| 微信值 | 当前用户偏好允许 `wechat`；Sync Protocol v1 的 reminder intent 禁止 `wechat` | 明确现有数据处置与兼容读取；V1 新写和同步 mutation 必须拒绝 | Migration 决策待定 |
| 资料/偏好 owner | 当前 `user.update_current` 混合接收资料与偏好，成功响应无双 revision/change | 收紧到 `username/display_name`；偏好只走 `preferences.update` → C++ Outbox → `sync.exchange`；资料/头像/确认邮箱原子写 `account_profile` change，响应携带双 revision | 现有资料端点不可激活 |
| 请求 exact keys | Schema 要求 `additionalProperties:false`；Backend 没有覆盖全部端点的 Contract fixture 测试 | 建立逐端点正反 fixture Web 测试，证明未知字段、显式 null、空 body、未知 enum 和超限均按冻结错误失败 | 未验证 |

### 4.2 云同步-02 冻结前必须固化的跨层语义

云同步-02 已明确 `account_profile` 为服务端产生、客户端下载的安全投影，也已明确 nullable `user_sessions.device_id`、`reauth_grants` 和撤销设备时撤销全部 Session。这些不再是 Backend 可选方案。下列语义必须原样进入机器 Schema、错误目录、DDL 和 golden fixture；Backend 不得另选行为：

1. Backend HTTP Contract Calibration ADR 必须冻结语义 HTTP status、`ApiResult`、`Retry-After`、通用 `Idempotency-Key` payload digest，以及 16 个既有端点的兼容/激活状态。
2. Category Sync Lifecycle ADR 必须先接受；账号归属、update/delete/reorder、弱引用、冲突和恢复语义未定时，Category mutation 不能进入 Backend 实现。
3. `auth.reauthenticate` 的 Grant 固定为 5 分钟、只存哈希并单次消费。普通态绑定当前 Session、actor device、target device 与 `purpose=device_revoke`；`pending_registration` 态允许 `actor_device_id=null`，但必须绑定当前 Session、本次 attempted installation digest、target device 与 purpose，二者不得互换或跨 Session 消费。
4. `account_profile` download-only 语义已经确定；仍需由机器 Schema 固定 typed change payload、profile/preferences revision 字段和既有 User/Profile 响应的兼容升级顺序。
5. bootstrap固定采用持久化materialized session/items；item为immutable typed after-image/tombstone或snapshot时全部unresolved conflict，HMAC分页、24小时TTL。过期/账号generation变化和普通cursor错误保持各自稳定码。
6. 导入固定使用lineage + begin manifest + 连续ordinal业务项 + terminal commit。manifest含`source_workspace_id/source_snapshot_hash`、各target数量、`portable_preferences_count`、`total_item_count`、ordinal items的`total_canonical_bytes`、`mapping_digest/manifest_hash`；begin按声明容量预留，items累计实算，commit完整复算。begin/items只进隔离staging并返回`staged`；commit完整验证后才在一个事务原子发布canonical整图和连续publish group。缺项/拒绝进入`repair_required`，successor复用lineage/mapping；证据丢失/TTL回收先以独立takeover CAS关闭旧sequence range，绝无逐项可见半导入或sequence复用。
7. 重复前缀wire result固定为`status=duplicate`，并携带`original_status`（`accepted/partially_merged/conflict/rejected/staged`）、原terminal result/receipt/hash及per-key resulting version；Schema/fixture必须把exact keys和嵌套形状闭合，Java不得只返回空duplicate标志。
8. `DEVICE_LIMIT_REACHED` 固定把当前 Session 留在 `pending_registration` 受限态；该状态只允许 refresh/logout、`user.get_current`、`device.list`、`auth.reauthenticate`、`device.revoke` 与同 installation 的 `device.register` 重试，其他请求统一拒绝。撤销旧设备后必须重试注册并成功绑定，才可离开受限态。
9. 注册中央授权矩阵默认拒绝：`unregistered`只允许refresh/logout、`user.get_current`和首次`device.register`，不允许list/reauth/revoke且不能签发actor-null grant；`pending_registration`才增加list/target reauth/revoke和同installation register重试；`registered`才进入普通endpoint授权。新增endpoint必须显式归类。
10. RFC 8785/JCS + SHA-256不是“任一JSON序列化后hash”：Java必须与C++在官方/等价Unicode、对象键排序、数字、null/array、safe-integer边界向量上产生完全相同UTF-8 bytes/hash。依赖选型须经许可证/构建批准；不得复用`identity.yaml`的紧凑数组UUID canonical规则冒充JCS。

### 4.3 B0 退出标准

- [ ] 云同步-02 已达到 `CONTRACT FROZEN`，记录 Contract revision/hash。
- [ ] 上述漂移都有明确 Source of Truth、迁移/兼容动作和跨层测试，不存在“双行为都支持”的临时分支。
- [ ] 云同步-02 §8.1 的 operation key、HTTP method、path 已逐项进入 `backend_api.yaml`，请求/响应 Schema 和错误码全部闭合。
- [ ] PostgreSQL 逻辑模型覆盖 reauth、Session/Device 绑定和安全资料传播，或明确采用无需新增表的冻结方案。
- [ ] C++、Kotlin 与 Backend 对 sequence、receipt、cursor、bootstrap 和 conflict resolve 使用同一 fixture。
- [ ] Java JCS canonicalizer已通过Contracts-02跨Windows/Android三ABI/Java golden与独立SHA-256 KAT；实现/依赖未定时同步写事务保持blocked。

未满足任一项时，后续阶段保持 `BLOCKED BY CONTRACT`。

## 5. 模块边界与依赖方向

所有实现继续使用现有模块化单体和模块内 `api → application → domain ← infrastructure` 分层。

| 模块 | 本计划职责 | 明确禁止 |
| --- | --- | --- |
| `platform` | `ApiResult`、请求 ID、JSON exact-key 配置、请求大小、JWT/CORS、Clock/ID、游标 HMAC 的技术适配和可观测基础 | 同步冲突规则、设备所有权、业务 Entity |
| `identity` | `auth.reauthenticate`、rehash/限流、Session 注册状态与 Device 绑定、注册/撤销的跨模块安全编排、设备撤销时的会话族撤销、`DEVICE_REVOKED` 认证映射 | 读取 calendar/sync JPA Entity 或直接操作 userdevice Repository |
| `userdevice` | 设备注册领域操作、`device.list/rename/update_settings`、10 台上限、installation 摘要、设备 CAS、偏好白名单和资料安全快照 | Token 明文、同步字段合并、直接写 identity Repository |
| `calendar` | 账号范围内的强类型事实、引用完整性、target-specific mutation handler、tombstone/restore 业务约束 | recurrence 展开、同步顺序、HTTP cursor、设备调度状态 |
| `sync` | exchange/bootstrap/status/conflict API、sequence/receipt、merge orchestration、field version、account sequence、change feed、cursor、import receipt、保留策略 | 绕过 Calendar Application Service 直接改业务 Repository；通用 JSON 实体 |
| `boot.scheduler` | tombstone/change/conflict/receipt/reauth 到期清理任务的装配 | 假设单实例；承载业务规则 |
| `boot.worker` | V1 不新增必须常驻的 MQ consumer | 用空 Worker 冒充同步能力 |

为避免模块循环和内部 Repository 越界，采用以下约束：

1. `sync` 定义窄的 `SyncMutationHandler` 与 `SyncDeviceGate` SPI；`calendar`、`userdevice` 以 adapter 实现 target-specific 处理，`sync` 不导入它们的 JPA 类型。`sync` 另提供由自身实现的公开 `SyncChangeAppender` Application port，供资料/头像/确认邮箱入口在同一事务追加 download-only change。
2. exchange 的外层事务位于 `sync.application`；被调用 handler 必须加入同一事务并只返回 wire-neutral 结果。
3. `identity` 已依赖 `userdevice.application`。为避免反向依赖，`device.register` 与 `device.revoke` 的跨模块安全编排都放在 `identity.application`，由 `identity.api` 下的 Controller 暴露冻结路径；注册结果与 Session registered/pending 转换、以及标记设备撤销与撤销 Session/Grant，分别必须在同一事务完成。`userdevice` 只返回领域 outcome，绝不直接写 identity Repository。
4. 非 sync 入口产生的安全资料/偏好变化，必须通过冻结的公开 change appender 同事务记录，不能依赖提交后的普通 ApplicationEvent 补写 change feed。
5. `ModuleArchitectureTest` 必须验证无循环、无其他模块 JPA Entity/Repository 引用，并对新增 named interface 建立显式断言。

## 6. HTTP API 映射：严格继承云同步-02 §8.1

统一 base path 为 `/api/v1`。下表名称和路径不得在 Backend 实现中自行调整；若 Contract 冻结前发生改名，必须先同步云同步-02及其他分计划。

| Operation key / HTTP / Path | Controller → Application | 请求职责 | 响应与事务职责 |
| --- | --- | --- | --- |
| `system.time` `GET /system/time` | `identity.api`或独立无状态system controller | 无body、无bearer、无cookie/账号/设备参数；仅接受HTTPS，按IP有界限流 | exact `ServerTimeResponse{server_time}`、`Cache-Control: no-store`；使用注入`Clock`在响应生成时给出UTC下界，不访问业务Repository、不产生审计主体或同步事实 |
| `auth.reauthenticate`  `POST /auth/reauthenticate` | `identity.api` → reauth use case | bearer Principal；`current_password`、`purpose=device_revoke`、`target_device_id`；密码/token 禁止日志 | 5 分钟 `reauth_token/expires_at/purpose/target_device_id`；普通态绑定当前 Session/actor device/target，`pending_registration` 态的 actor device 可为空但必须额外绑定 attempted installation digest；均为单次消费 |
| `device.register`  `POST /devices` | `identity.api` → registration security workflow → `userdevice.application` | `installation_id/display_name/platform/app_version/protocol_version`；账号从 Principal；`display_name` 为 1..64 Unicode code points | 同账号同 active installation 幂等复用并原子绑定当前 Session；响应含sync transport generation、highest、nullable next、client-confirmed、sequence-exhausted严格分支；revoked 记录不复活；并发第 11 台提交受限态后稳定失败 |
| `device.list`  `GET /devices` | `userdevice.api` → list devices | 空 body，只使用当前账号 | 返回当前账号的脱敏设备列表、`receive_reminders`、最后上报的 `sync_enabled` 镜像和版本；受限态明确返回 `registration_pending=true/current_device_id=null`；不返回 installation 摘要/Session/Token |
| `device.rename`  `PATCH /devices/{device_id}/name` | `userdevice.api` → rename device | 1..64 Unicode code points 的 `display_name`、`expected_device_version` | 账号范围 + CAS；返回更新后的 `DeviceResponse` |
| `device.update_settings`  `PATCH /devices/{device_id}/settings` | `userdevice.api` → update current-device settings | typed patch 的 `receive_reminders` / `sync_enabled` 至少一项，另带 `expected_device_version`；仅当前设备 | CAS 更新并返回 `DeviceResponse`；相同版本和相同 typed patch 的安全重试幂等，版本已推进则返回当前快照供客户端收敛；`sync_enabled` 只保存诊断镜像，可由独立 settings reporter 在业务同步关闭时上报 |
| `device.revoke`  `POST /devices/{device_id}/revoke` | `identity.api` → revoke-device security workflow | `expected_device_version` + Contract 冻结的 reauth header；V1 只撤销其他设备 | 同事务标记设备撤销、撤销其全部 Session/Grant并返回 `DeviceRevocationResponse` |
| `sync.device_fence` `POST /sync/device-fence` | `sync.api` → device transport lifecycle use case | `device_id/fence_operation_id/expected_sync_transport_generation/reason` | Session→device→state锁内等待旧事务、checked increment并持久化幂等receipt；返回new generation、完整sequence bundle和resolved absent-import fences；同id异payload拒绝 |
| `sync.exchange`  `POST /sync/exchange` | `sync.api` → exchange use case | normal含protocol/device/transport generation/cursor/download limit/ack/≤100 mutations；ack-only严格为uploads空、download limit=0、cursor=null、ack非空 | normal返回同transport generation的groups/chunks+cursor/cleanup+accepted ack；ack-only返回empty results/changes、null cursor/cleanup+accepted ack；不要求有效普通cursor但仍锁内重验Session/transport generation |
| `sync.bootstrap`  `POST /sync/bootstrap` | `sync.api` → bootstrap query | `protocol_version/device_id/sync_transport_generation/bootstrap_cursor/page_limit` | 首次原子创建/复用materialized snapshot；首响应精确返回bootstrap/transport/account generation、upper bound、device highest/client-confirmed/nullable-next/exhausted、两个cleanup水位与trigger reason；页面为fact/tombstone/deleted-entity-anchor/unresolved-conflict/import-marker/requesting-device-causal-anchor严格union；无跨HTTP长事务 |
| `sync.import.status` `GET /sync/imports/status` | `sync.api` → import lineage query | nullable batch id，或`source_workspace_id + source_epoch + nullable source_snapshot_hash` | 有batch id时精确返回九态中的当前状态，含completed/superseded/abandoned终态与current-head指针；无batch时只发现该epoch仍需恢复的nonterminal/confirmed/publish/cleanup handle或严格empty union。不返回payload、不把completed旧epoch当current；仅原设备可续旧ordinal |
| `sync.import.takeover` `POST /sync/imports/{import_batch_id}/takeover` | `sync.api` → import range-close use case | caller transport generation、lineage/source workspace/source epoch/完整manifest/count/bytes/origin generation/range/expected import revision/严格reason | 独立range-close CAS且不占调用设备sequence；`local_evidence_lost`仅caller=origin，`origin_unavailable`仅Backend确认origin revoked，`ttl_payload_reclaimed`仅已持久化TTL状态或内部Scheduler。按全局锁序与旧commit仲裁，原子supersede旧批并返回seen-range或已完成transport fence的never-visible proof；非法actor/reason零写 |
| `sync.import.abandon` `POST /sync/imports/{import_batch_id}/abandon` | `sync.api` → import abandon use case | caller transport generation、lineage/source workspace/source epoch、nullable `predecessor_batch_id`、完整manifest/count/bytes/origin generation/range/expected import revision/reason；当前账号registered device调用 | 独立幂等CAS并把predecessor纳入exact-key/digest/lineage校验。已有begin reservation复用seen-range close；batch absent且begin=current highest+1可原子建立+关闭，否则持久化absent fence并返回proof null/不推进；旧origin generation经device fence后可返回never-visible proof；已有published predecessor不得普通abandon |
| `sync.import.cleanup_confirm` `POST /sync/imports/{import_lineage_id}/cleanup-confirm` | `sync.api` → import cleanup confirmation use case | caller transport generation、source workspace/source epoch、through published batch/revision、source snapshot/mapping digest、guest receipt hash、expected lineage revision | 独立lineage CAS，不占client sequence且任一当前registered device可调；只验证该epoch连续published chain，completed旧epoch与新epoch严格隔离；stale返回current stage/head/revision且零写 |
| `sync.get_status`  `GET /sync/status` | `sync.api` → status query | 当前 `device_id` query，与 Session 绑定设备一致 | 只返回远端sequence、sync transport/account generation、floor/冲突和阻塞摘要，不替代C++本地同步状态或充当fence receipt |
| `sync.conflict.list`  `GET /sync/conflicts` | `sync.api` → conflict query | `status/type/cursor/page_size` | 账号范围、稳定排序、固定分页上界和 opaque cursor |
| `sync.conflict.get`  `GET /sync/conflicts/{conflict_id}` | `sync.api` → conflict detail | 空 body | 只返回当前账号拥有的 typed server/local candidate 和版本 |
| `sync.conflict.resolve`  `POST /sync/conflicts/{conflict_id}/resolve` | `sync.api` → sequenced resolution use case | `device_id/sync_transport_generation/client_sequence/mutation_id/expected_conflict_version/resolution` | 锁内重验Session/transport generation并复用同步 sequence/receipt；同事务解决冲突、生成新 entity version/change；不得旁路 C++ Outbox |

所有请求与响应 DTO 必须由冻结 Schema 显式映射，JSON wire format 为 `snake_case`。Controller 不接收 JPA Entity、不查询多个 Repository、不从 body 读取账号身份，也不把 HTTP DTO传入 Domain。

现有 `POST /auth/logout` 继续是服务端 Session 终止端点，并固定为幂等：首次成功返回 `succeeded`，已经失效的同一 Session 返回 `already_invalid`；两个终态都必须带同一响应事务取得的UTC `server_time`，供Kotlin建立30天目标保留窗口的可信锚。`server_then_local`、`force_local`、`cache_policy`及其`allowed_cache_policies`是Kotlin MethodChannel编排语义；无可信锚的force-local retain由Kotlin按Contract拒绝，Backend不参与该选择。`server_then_local`只有收到上述服务端终态才能本地终止，网络失败必须返回`unreachable`，不得由Backend或客户端伪造成功；`force_local`不请求Backend。Backend不接收、保存或执行客户端cache policy，也不承诺Android物理清理时刻。

`system.time`是唯一为退出后、无Session的保留缓存恢复时间信任而新增的匿名端点；它显式绕过账号注册三态，但仍经过HTTPS、host与限流门禁。安全配置只精确放行`GET /api/v1/system/time`，其他未知API继续默认拒绝；该响应不得包含节点、版本、账号或会话可观察信息，也不得被任何同步merge/sequence逻辑用作客户端时钟。

Controller/filter在事务外解析出Principal不构成提交授权。所有会写sync/import/bootstrap/sequence/receipt的Application事务必须把当前`user_sessions`行作为第一把锁并重新验证token所指session仍有效、账号一致、registration state与device binding未变；随后才锁device/state并验证request transport generation。服务端logout/refresh-reuse/session-family revoke使用同一Session锁序：若旧sync事务先锁则它完整提交后logout才返回，若logout先锁并终止session则旧事务醒来后零写返回Auth终态。不得出现logout已向客户端成功但旧请求随后提交的窗口。

### 6.1 错误与重试职责：严格继承云同步-02 §12

HTTP status 尚由 B0 ADR 冻结，但 `ApiResult.error.code/context` 的类别和调用方责任不得被 status 选择改写：

| 云同步-02 类别 | Backend 必须返回/保证 | Backend 不得做 |
| --- | --- | --- |
| 协议 | `SYNC_PROTOCOL_VERSION_UNSUPPORTED`、`SYNC_BATCH_TOO_LARGE`、`SYNC_PAYLOAD_INVALID`；在业务事务前失败。服务端候选使组超过hard cap时为逐项terminal `rejected + SYNC_CHANGE_GROUP_TOO_LARGE`并消费sequence、canonical零写 | 自动降级协议、截断 mutation、产生不可下载组或无限重试 |
| 顺序/幂等 | `SYNC_CLIENT_SEQUENCE_GAP`保持事实零写；`SYNC_SEQUENCE_REPLAY_MISMATCH`冻结设备；active import reservation错route返回`SYNC_SEQUENCE_ROUTE_MISMATCH`；旧transport generation返回`SYNC_TRANSPORT_GENERATION_MISMATCH`且零写，generation到MAX返回`SYNC_TRANSPORT_GENERATION_EXHAUSTED`；client/server上限返回各自exhausted | 猜测补洞、让普通mutation占import range、按到达时间改序、把lifecycle-stale误报corruption、回绕/截断safe integer、自动轮换device，或以短期HTTP cache替代持久receipt |
| 其他服务端计数器 | `account_generation/device_version/entity_version/field_version/conflict_version/account_profile_revision/preferences_revision/import_revision`在事实写前checked increment；无法推进时整个能力事务零写并返回`SYNC_COUNTER_EXHAUSTED`，strict `context.counter_kind`固定指出唯一字段 | 饱和、回0、换ID、借用时间戳/LWW、只写事实不写version，或伪造客户端owner的route/settings/lifecycle/token/policy/status/notice耗尽错误 |
| Cursor / Bootstrap | 语法/签名、保留下界、账号、设备、generation 分别返回 `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH`、`SYNC_CURSOR_GENERATION_MISMATCH`；只有 expired/generation mismatch 进入 bootstrap；materialized session/token 过期返回 `SYNC_BOOTSTRAP_EXPIRED`，账号 generation 变化返回 `SYNC_BOOTSTRAP_GENERATION_CHANGED` | 篡改/跨账号/跨设备继续、过期后静默回第一页、把 generation mismatch 或 bootstrap expiry 伪装成普通空页 |
| 能力/设备 | 非白名单账号统一`SYNC_NOT_ENABLED_FOR_ACCOUNT`且不创建device；其余为`DEVICE_LIMIT_REACHED`、`DEVICE_NOT_REGISTERED`、`DEVICE_NOT_FOUND`、`DEVICE_REVOKED`、`DEVICE_VERSION_CONFLICT`、`DEVICE_REAUTH_REQUIRED`、`DEVICE_REAUTH_TARGET_MISMATCH`。普通未绑定 Session 与 `pending_registration` 访问白名单外端点均返回 `DEVICE_NOT_REGISTERED` | 把客户端开关当entitlement、把 pending registration 当登录完成、把 revoked 降级成普通 401、泄露其他账号设备、自动重放 reauth |
| 冲突 | `SYNC_CONFLICT_NOT_FOUND`、`SYNC_CONFLICT_VERSION_MISMATCH`、`SYNC_CONFLICT_ALREADY_RESOLVED`、`SYNC_ENTITY_CONFLICT_BLOCKED`；stale version促使客户端重载，旧客户端普通writer命中冲突对象返回稳定rejected | 以last-write覆盖、允许普通写绕过冲突详情，或绕过sequence/receipt |
| 导入 | `IMPORT_LINEAGE_MISMATCH`拒绝UUIDv5/账号/source/epoch不符；`IMPORT_VERSION_CONFLICT`用于import CAS stale并携current stage/head/revision且零写；`IMPORT_BATCH_ABANDONED`/`IMPORT_BATCH_SUPERSEDED`用于迟到matching range项；本地预检或服务端terminal统一使用`SYNC_IMPORT_CAPACITY_EXCEEDED`并以strict origin/context区分，服务端分支返回range-close proof | 发布部分图、跨epoch复用mapping/delete闭包、信任未授权takeover reason、把early terminal留成active sequence洞，或伪造仅C++可产生的`IMPORT_SOURCE_EPOCH_EXHAUSTED/IMPORT_PUBLISH_INCOMPLETE` |
| Auth | `AUTH_SESSION_EXPIRED`、`AUTH_REFRESH_TOKEN_REUSED`、`AUTH_SESSION_ACCOUNT_MISMATCH`、`AUTH_REAUTH_FAILED` 沿用认证边界；identity mismatch fail closed，并与设备撤销保持可区分 | 把 auth failure 伪装成可重试同步错误 |
| Transport / 429 / 5xx | 只有冻结Contract允许的暂时故障才标retryable；可提供1..86400的`retry_after_seconds`，若B0保留header则必须数值一致 | 将非法envelope、未知enum、数据损坏或mismatch标为自动重试，或把无hint误作永久blocked |

云同步-02 的 Workspace/密钥错误 `WORKSPACE_NOT_FOUND`、`WORKSPACE_ACCOUNT_MISMATCH`、`WORKSPACE_LOCKED`、`WORKSPACE_KEY_UNAVAILABLE`、`WORKSPACE_SWITCH_CONFLICT`，通知路由错误 `NOTIFICATION_WORKSPACE_AMBIGUOUS`、`NOTIFICATION_WORKSPACE_UNAVAILABLE`，以及本地数据错误 `SYNC_OUTBOX_CORRUPTED`、`SYNC_APPLY_FAILED`、`SYNC_BOOTSTRAP_INCOMPLETE`、`IMPORT_SOURCE_CHANGED`、`IMPORT_PUBLISH_INCOMPLETE`，由 Kotlin/C++ 产生，不应由 Backend HTTP 伪造。响应 context 必须来自冻结 Schema；Java 不附加客户端无法识别的自由文本控制字段。

客户端基础重试不依赖server hint：full jitter `uniform[0,min(15min,5s×2^attempt)]`、每轮最多8次；Backend只决定错误是否retryable与可选hint。合法hint只提高delay并封顶24小时；body/header不一致是非法envelope。B0 ADR必须冻结header是否发送，但不能改变此算法。

## 7. PostgreSQL 与 Flyway 交付

### 7.1 Migration 原则

- [ ] 先验证现有 V1–V3 checksum 与可迁移样本；任何已应用 Migration 永不修改、改名或重排。
- [ ] 后续只新增 `V4__...` 及之后的前滚 Migration；实际编号和表/列名以云同步-02冻结的 PostgreSQL 机器模型为准。
- [ ] DTO、Domain、JPA Entity、数据库 Record 和 change payload 分离；正式 Profile 继续 `ddl-auto=validate`。
- [ ] 每个表明确 PK、FK、NOT NULL、CHECK、唯一约束、时间类型与容量索引；并发正确性最终由数据库约束兜底。
- [ ] 所有账号业务表具有 `account_id`；跨表引用使用包含 `account_id` 的复合唯一键/FK 或冻结的等价约束，数据库层阻止跨账号引用。
- [ ] 时间点使用 `timestamptz`，civil date 使用 `date`，数量使用 safe-integer 定点数；不以 `timestamp without time zone` 或浮点数保存同步真相。
- [ ] JSONB 只保存已被 field registry 验证、带 payload version/hash 的 immutable patch/result/change snapshot；不得建立万能业务实体表。

### 7.2 冻结逻辑表到物理 DDL 的职责

| 逻辑表 | Backend DDL / Repository 必须证明 |
| --- | --- |
| `user_devices` | 账号内 active installation 摘要唯一、active/revoked 状态、display name、platform/App/protocol、receive_reminders、最后上报的 sync_enabled 诊断镜像、device version、last seen/sync；第 11 台并发注册不会穿透；revoked 历史保留但不阻止同 installation 的后续显式新注册 |
| 既有 `user_sessions` | nullable account-scoped `device_id` FK；另存三态`registration_state`（`unregistered / pending_registration / registered`）与 nullable attempted installation digest；第 11 台失败原子进入受限态，注册成功原子清理摘要并绑定 device；撤销设备可按账号/设备索引撤销全部 Session |
| `reauth_grants` | 只保存 token hash、account/session/nullable actor device/nullable attempted installation digest/target device/purpose/expires/consumed time；CHECK 保证普通态绑定 actor device、pending 态绑定 installation 摘要且二者互斥；目标、TTL、单次消费和撤销事务由约束/锁共同证明 |
| `account_profile_revisions` 或冻结的等价账号列 | profile revision 单调推进；资料、头像、确认邮箱的事实写入、revision 和 download-only `account_profile` change 同事务 |
| 既有 `user_preferences` | 用户更新/同步精确收口到`timezone`、`habit_progress_color`、有序去重的`default_reminder_methods`（V1仅`ring/popup`）、`auto_enable_reminders_on_other_devices`并携带独立preferences revision；locale及未知key/`wechat`历史值先审计、隔离为兼容数据，禁止无审计删除；注册仅接受固定`zh-CN`兼容常量且不发change；auto-enable默认false且只供未来设备注册取样 |
| `sync_device_state` | 与device一对一；从0开始的sync transport generation、highest sequence、单调`client_confirmed_through`、blocked、cursor/account generation/last sync；confirmed≤highest；所有mutating sync/import事务锁内重验transport generation |
| `sync_device_fence_receipts` | device + operation唯一；expected/resulting transport generation、reason、冻结sequence recovery bundle、resolved absent-import fence proofs与response hash；同operation同payload重放原结果，同id异payload拒绝，保留至device/account删除 |
| `sync_device_causal_anchors` | 每active device/target/entity/merge key最近成功应用的client sequence/resulting field version；conflict/rejected/staged不推进，不含payload，receipt过期后仍可验证长期离线后继 |
| `sync_mutation_receipts` | `(account_id,device_id,client_sequence)`和mutation identity唯一；保存canonical payload hash、per-key predecessor/resulting version与原`accepted/partially_merged/conflict/rejected/staged` terminal result；duplicate由该行完整重放；保留遵守ack/tombstone/import安全窗口 |
| 强类型事实表 | Category、Event、Event recurrence revision、OccurrenceState、Anniversary/Recurrence、Habit/Recurrence/CheckIn、ReminderIntent；全部有 account scope、entity version、last server sequence 和 tombstone 语义；导入产生的行另有nullable且一经设置不可变的`import_lineage_id/source_target_type/source_entity_id` provenance或等价account-scoped mapping FK，后继版本/删除仍保留 |
| `habit_check_in_operations` | operation identity 唯一；increment/decrement/replace/clear 重放不重复累计；引用同账号 Habit/CheckIn |
| `sync_entity_field_versions` | `(account_id,target_type,entity_id,merge_key)` 唯一；只保存 Contract registry 中存在的 merge key |
| `sync_account_sequences` | 每账号 generation、next server sequence、retention floor；分配使用行锁，不依赖 wall clock |
| `sync_change_groups/items` | 普通组把entity changes与conflict deltas绑定一个不可拆sequence/group hash；import publish以同事务生成的连续begin/chunk/commit区间表示；cursor流按sequence读取且分页遵守组边界 |
| `sync_conflicts` | 账号/实体/conflicting groups/typed auto-merged groups/server-local candidate/source device/version/status/received/resolved/retain_until；unresolved稳定分页并pin引用tombstone |
| `sync_import_lineages/batches/staging_items/receipts` | lineage按`(account_id,source_workspace_id,source_epoch)`稳定并保存该epoch cleanup/reconciliation水位；batch绑定origin device/transport generation/predecessor/source epoch/完整manifest/count/total canonical bytes/mapping、takeover reason、active sequence reservation、begin/derived-terminal sequence与range-close proof；absent batch fence在无receipt时仍持久；item只存隔离typed staging与receipt；compact terminal range按origin confirmed-through+180天保留，head cleanup只覆盖同epoch published predecessors |
| `sync_import_publish_markers` | account/lineage/batch/group/commit sequence/manifest/mapping identity唯一；紧凑marker保留至账号删除，当前provenance digest/count在bootstrap物化时从canonical事实生成 |
| tombstone 元数据 | 事实表列或Contract专表；180天、retention floor和bootstrap一致；被unresolved conflict引用时pin至resolve+30天且满足安全cursor |
| `sync_deleted_entity_anchors` | account/target/entity唯一，保存delete entity version/server sequence与typed deletion marker，不含原业务payload；导入来源的anchor继续保存immutable lineage/source identity或等价mapping FK；tombstone清后仍保留至账号删除，供长期离线旧编辑产生delete-vs-edit conflict并让bootstrap marker重算provenance |

本计划提交给云同步-02 C3 机器模型的物理命名目标如下；一旦 Contract 冻结，这些名字只能通过正式兼容迁移演进，不能由 JPA 实现临时改名：

| DDL slice | 精确物理对象 | 主键、唯一键与引用职责 |
| --- | --- | --- |
| Device/Auth | `user_devices`、`reauth_grants`，并为 `user_sessions` 增加 `device_id/registration_state/attempted_installation_digest` | `user_devices` 使用账号范围 device key，并以 partial unique 约束 active `(account_id,installation_digest)`；revoked 行永不复活；Session/Grant 的 device FK 同时含 account scope；pending Grant 以约束绑定 Session + attempted digest + target + purpose；Grant 只存 hash |
| Profile/Preferences | `account_profile_revisions`，前滚收口既有 `user_preferences` | 每账号各一条 revision 真相；资料 revision 与 preferences revision 分离；旧 settings 先兼容扫描/回填，再增加 NOT NULL/CHECK |
| Calendar facts | `categories`、`calendar_events`、`event_recurrence_versions`、`event_occurrence_states`、`anniversaries`、`anniversary_recurrences`、`habits`、`habit_recurrences`、`habit_check_ins`、`habit_check_in_operations`、`reminder_intents`、`anniversary_reminder_templates`、`habit_reminder_templates` | 普通事实以 `(account_id, entity_id)` 为账号范围 key；revision/occurrence/operation 使用冻结复合 identity；所有引用都由 account-scoped composite FK 防止跨账号；nullable immutable import lineage/source provenance列或独立mapping FK覆盖事实、后继与tombstone |
| Sync ordering | `sync_device_state`、`sync_device_fence_receipts`、`sync_device_causal_anchors`、`sync_mutation_receipts`、`sync_account_sequences` | device state对user device一对一；transport fence operation持久幂等并冻结sequence bundle；causal anchor唯一到device/target/entity/key；receipt同时唯一sequence与mutation；account sequence每账号一行 |
| Merge/feed/conflict/import | `sync_entity_field_versions`、`sync_change_groups`、`sync_change_group_items`、`sync_conflicts`、`sync_import_lineages`、`sync_import_batches`、`sync_import_staging_items`、`sync_import_item_receipts`、`sync_import_range_proofs`、`sync_import_absent_fences` | field version唯一；普通group不可拆；import publish连续区间；lineage唯一`(account_id,source_workspace_id,source_epoch)`，batch/ordinal/proof/absent-fence复合FK不跨账号/epoch；absent fence先于generic replay路由查询 |
| Bootstrap snapshot | `sync_bootstrap_sessions`、`sync_bootstrap_items` | session唯一并保存identity/upper-bound/expiry、requesting-device highest/client-confirmed；item按kind/target/id/conflict-id/merge-key/ordinal稳定排序，保存immutable typed fact/tombstone、全部unresolved conflict、import marker或该device causal anchor及hash；TTL固定24小时 |
| Tombstone | typed fact统一`is_deleted/deleted_at/retain_until`及`sync_deleted_entity_anchors` | 删除payload保留窗口/冲突pin与retention floor同事务；轻量anchor在payload清后继续识别旧编辑 |

Migration 按“Device/Auth → Profile/Preferences → typed facts → ordering/feed/conflict → materialized bootstrap → retention/index”拆成可前滚切片。实施开始时从 V1–V3 之后当时尚未占用的下一个 Flyway 版本连续编号；文件名、DDL 和回滚/前滚恢复步骤在代码评审前锁定，禁止因并行开发冲突改写已经执行的版本。

### 7.3 认证与既有资料的相邻迁移

以下物理变化已经由云同步-02给出目标逻辑模型；Backend 必须等对应 ADR、Schema、错误和迁移兼容规则冻结后再编码，不得另选语义：

- Session 与注册设备的 nullable FK、三态 `registration_state`、`pending_registration` attempted installation digest、`device_revoked` reason，以及旧 Session 的 nullable/backfill/强制注册兼容策略；受限态白名单由统一授权门禁执行，不能靠各 Controller 自觉过滤。
- `reauth_grants` 的 token hash、account/session/nullable actor device/nullable attempted installation digest/target device/purpose/expiry/consumed 约束；pending 与普通 Grant 的字段组合由 CHECK 固定，严禁改为存 token 明文。
- 既有 `user_preferences` 的四项V1同步白名单、source device/received time/revision；`timezone/habit_progress_color/default_reminder_methods/auto_enable_reminders_on_other_devices` 不再由 `user.update_current` 或 `account_profile` 重复拥有。locale历史值留作兼容审计，新写入口关闭且不产生change。
- 既有任意 settings key 和 `wechat` 数据的扫描报告、兼容读取和前滚处置；不得无审计删除用户值。
- 安全资料 change/hint 所需 revision 或 change 表映射；不得把密码、Token、Challenge 或密钥放入 change feed。

### 7.4 索引最低门禁

至少用真实 PostgreSQL 和代表数据验证：

- `sync_change_groups(account_id,generation,first_server_sequence)`与items的增量/固定上界扫描；import连续区间可按group定位且不夹普通group；
- `sync_mutation_receipts(account_id,device_id,client_sequence)` 重放与清理；
- `sync_device_fence_receipts(account_id,device_id,fence_operation_id)` 响应丢失重放，以及按resulting transport generation恢复未见import fence；
- `sync_conflicts(account_id,status,target_type,received_at,conflict_id)` 稳定分页；
- `sync_import_lineages(account_id,source_workspace_id,source_epoch)`发现，`sync_import_item_receipts(account_id,import_batch_id,ordinal)`完整性/commit/cleanup确认，以及`sync_import_absent_fences(account_id,origin_device_id,origin_transport_generation,import_batch_id)`迟到路由；
- 所有事实表 `(account_id,id)`、tombstone/last sequence 查询和 account-scoped FK；
- `user_devices(account_id,installation_digest)` 唯一与 active device 列表；
- `habit_check_in_operations(account_id,operation_id)` 去重；
- `sync_bootstrap_items(account_id,device_id,bootstrap_id,ordinal)` 页面读取，以及 `sync_bootstrap_sessions(status,expires_at)` 有界清理；
- 清理任务的 `retain_until/status` 索引。

不得只以“已创建索引”验收；需要 `EXPLAIN (ANALYZE, BUFFERS)` 或等价证据确认 20,000/50,000 条基线下没有无界全表扫描。

## 8. `sync.exchange` 事务与并发算法

### 8.1 请求写入前校验

在持有业务锁前完成不会访问用户事实的校验：协议版本、`ApiResult`/DTO形状、exact keys、safe integer、批次数、解压后字节数、连续排序、typed `oneOf`、枚举、request `sync_transport_generation`、payload canonical hash和cursor语法。每个mutation的`causal_predecessors`必须按merge key排序且与touched registry keys完全一致。导入还必须校验begin/commit manifest及声明的`total_canonical_bytes`，以及`import_lineage_id/import_batch_id/import_source_workspace_id/import_source_epoch/import_item_ordinal/import_manifest_hash/predecessor_batch_id`的合法组合；普通mutation七字段全为空。任何envelope级错误使整批零写。

随后从 Principal 取得账号与Session标识并做快速校验；这只是拒绝明显非法请求，不能授权提交。请求`device_id`、Session有效性/绑定、设备未撤销与transport generation都必须在下述事务持锁后重验。设备身份只用于幂等/审计，不能替代账号授权。

### 8.2 单事务步骤

`SyncExchangeService.exchange` 的公开 Application 方法建立一个 PostgreSQL 事务，并按固定顺序：

1. 以token中的session id锁定当前账号`user_sessions`行，重新验证未终止、账号一致、`registration_state=registered`且绑定request device；logout/revoke/refresh-reuse与本事务共享这把首锁。
2. 锁定当前账号`user_devices`行并验证active/protocol，再锁对应`sync_device_state`并要求request `sync_transport_generation`精确等于current；不符返回`SYNC_TRANSPORT_GENERATION_MISMATCH`且整个请求零写。
3. 校验 `acknowledged_client_sequence_through` 不倒退且不超过highest；只有本请求整体提交时才推进 `client_confirmed_through`，所有成功响应回显`accepted_client_sequence_through`与current transport generation。缺失表示客户端尚未确认，绝不据“已发过响应”猜测ack。`uploads=[] + download_limit=0 + cursor=null + ack非空`是唯一ack-only分支：只验证持锁Session、active device、transport generation、协议形状与ack范围，不进入普通cursor签名/freshness/account generation、account sequence或change查询，不建receipt；提交后返回empty results/changes、null next cursor/cleanup水位和accepted ack。普通cursor已过期、account generation改变或客户端paused都不能阻止这条housekeeping；transport fence与Auth终态仍能阻止旧请求。
4. 在generic receipt/replay比较前，先按batch identity查询`sync_import_absent_fences`与compact terminal range。matching迟到begin/item/commit若已有closed proof则返回原no-effect；若为同transport generation的absent fence且begin现已成为`highest+1`，在完整manifest/count/bytes/range重验后原子升级为seen-range closed；仍有gap或序号已被其他receipt占用则返回request-level`IMPORT_BATCH_ABANDONED|SUPERSEDED`、零receipt/零highest且绝不触发replay freeze。随后才校验普通重复前缀：receipt payload hash完全相同返回完整duplicate，其他同sequence/mutation异hash只写blocked审计并零业务写。
5. 新后缀必须从 `highest_client_sequence + 1` 连续开始；跳号返回gap且新后缀零写。随后在generic route前校验active import sequence reservation：已有reservation只允许同source epoch/batch/manifest及由sequence唯一推导的ordinal或commit，错route返回请求级`SYNC_SEQUENCE_ROUTE_MISMATCH`、零业务/receipt/highest推进。若本请求新后缀含`import_begin`，先checked计算`terminal=begin+total_item_count+1`且必须≤JSON MAX，再建立事务内routing map供同一exchange后续items即时校验；溢出时整请求新后缀零写，不能留下永远无commit的reservation。
6. 锁定 `sync_account_sequences`，取得generation与后续server sequence分配权；在任何事实写前按本批最坏/精确group数证明全部sequence落在JSON safe-integer内，不足则`SYNC_SERVER_SEQUENCE_EXHAUSTED`整批回滚。client highest已达上限时只允许完全匹配duplicate/ack-only请求，新mutation返回`SYNC_CLIENT_SEQUENCE_EXHAUSTED`，不回绕或换device。
7. 按`(target_type,target_id)`排序预锁目标事实，再按`merge_key`排序锁field version；处理顺序仍保持client sequence。`account_profile`为download-only，上传validator必须在锁业务事实前拒绝。
8. target-specific handler执行所有权、引用、base version、operation和领域边界校验。若entity已有unresolved conflict，普通update/delete/restore返回消费sequence的`rejected + SYNC_ENTITY_CONFLICT_BLOCKED`。每个merge key的causal predecessor必须对应同device/target/key的更早成功receipt/紧凑anchor，或同一链上已验证的terminal no-effect receipt。成功分支要求当前field version精确等于resulting version；no-effect分支要求receipt保存`effective_prior_sequence/version`、其继承基线在前项处理时有效且当前version仍精确相等，只允许已冻结后继越过拒绝节点，不推进成功anchor、不绕过unresolved gate。中间其他设备写仍冲突，链断/receipt缺失fail closed。若tombstone payload已清但deleted anchor存在，只验证并读取hash覆盖的完整`conflict_recovery_snapshot`构造local candidate；正常merge绝不读取它。
9. 普通mutation先按Contract registry上限计算完整fact/conflict/group canonical bytes；若服务端当前候选使其超过hard cap，返回消费sequence的terminal `rejected + SYNC_CHANGE_GROUP_TOO_LARGE`且canonical/field/group零写。其余在一个不可拆`change_group`中写强类型事实/tombstone、field version、完整`entity_changes[] + conflict_deltas[]`、conflict和immutable receipt；receipt返回同一effect group id/末序列。conflict snapshot同时保存`conflicting_groups`与registry裁剪的immutable `auto_merged_groups`。同group只分配一个排序sequence/identity，分页不能拆fact与lifecycle。
10. 导入遵守 Contracts-02 `IMP-02`、`IMP-03`、`IMP-07`、`IMP-08`、`IMP-11` 和 `IMP-12`：
    - begin 在账号锁内按 manifest item/byte 预留 quota，并在接纳 begin receipt/highest 的同一事务写完整 active route reservation。items 只写 `sync_import_*` staging 和 `status=staged` receipt、消费 sequence 并累计实际 canonical bytes。
    - begin 配额拒绝、少报或累计超过声明/单批/账号上限时，返回 `rejected + SYNC_IMPORT_CAPACITY_EXCEEDED + origin=server_terminal`；当前 item terminal，剩余 reservation 经统一 range-close 转为 virtual no-effect 并推进 highest，返回可重取 `seen_range_closed` proof，canonical 零写。
    - commit 复算 count/bytes 并要求与 manifest 相同；失败为 repair-required 且 canonical 零写，成功才原子发布。confirmed abandon、takeover 和 TTL early terminal 复用同一 range-close use case。
    - batch absent abandon 重算 manifest/count/bytes/range。begin==highest+1 且无 receipt/reservation 时可原子建批、关段并推进 highest；否则只写不消费 sequence 的 absent fence。transport fence 可将旧 generation 且零 receipt 的 fence 转为 `never_visible_after_transport_fence` proof，但不推进 highest。
    - 只有 begin/items/commit 使用 client sequence；device fence、takeover、abandon 和 cleanup-confirm 均为独立 HTTP CAS。
11. 普通`accepted/partially_merged/conflict/rejected`与导入`staged`均写稳定terminal wire receipt；每个结果记录per-key resulting version，conflict/rejected还记录可验证的`causal_disposition=no_effect + effective prior sequence/version`及Contract允许的稳定failure code/safe context，使客户端可保存failed-local intent而不猜文本。causal anchor只在accepted或partial中该key确实应用时同事务推进；conflict/rejected/staged不覆盖最近成功anchor。Backend不保存或自动重传客户端failed overlay。客户端确认水位尚未越过的receipt必须继续pin；Contract要求客户端对仍被非终态后继引用的terminal no-effect sequence停住ack，故清理器不得只按年龄删除。基础设施异常回滚整批，不消费任何新sequence。
12. 更新device highest/last sync；在account sequence锁下固定upper bound，按第10.1节组边界查询download groups，生成cursor，并取同generation `retention_floor_server_sequence`与服务端UTC `resolved_conflict_cleanup_before=now-30d`。
13. 提交后返回transport generation、results、download groups/chunks、cursor与两水位；水位绑定response/cursor identity，不得用节点漂移时钟或跨account generation缓存。提交前Session/device/transport条件必须仍由所持行锁保证，不能在事务外二次猜测。

普通mutation中无冲突merge key可提交；冲突组保持云端当前值并保存本机候选，二者共同进入同一个change group。若没有canonical变化，是否分配版本严格服从fixture。导入ordinal的`staged`只证明收件；commit只有完整验证并成功提交整图后才携带`server_confirmed=true/publish_group_id/publish_upper_bound/summary_digest`。客户端仍须下载canonical publish group并记录`publish_applied`后才能清guest；单个commit HTTP成功、空Outbox或summary都不是本地完成证据。

### 8.3 全局锁顺序

所有 `sync.exchange`、`sync.conflict.resolve`、import commit/takeover/abandon/cleanup-confirm及会改变Session↔Device绑定的安全流程，对实际触及的锁统一遵守以下全序（可跳过不需要的类别，不可倒序）：

```text
account-scoped session/device lifecycle advisory guard（仅绑定/撤销类流程）
→ user_sessions（actor + target device全部session；多个时按session_id排序）
→ user_devices（actor/origin按device_id排序）
→ sync_device_state（actor/origin按device_id排序）
→ sync_account_sequences
→ sync_import_lineages / sync_import_batches（仅import route，lineage/batch排序）
→ typed fact rows（target_type, target_id 排序）
→ sync_entity_field_versions（merge_key 排序）
→ habit operation / import item receipts（ordinal 升序）
→ sync_conflicts
→ sync_changes
→ sync_mutation_receipts
```

takeover必须按上述顺序先锁actor Session、actor/origin device与对应state，再锁account sequence、lineage/batch；virtual range、origin highest、import revision与proof在同一事务提交。commit不得先锁batch再回头锁Session/device，Scheduler的TTL range-close也复用同一Application use case和锁序。`sync.device_fence`按Session→device→state取得相同锁，因而会等待所有旧写事务；它checked increment generation、把该old generation仍为absent且零receipt的import fence标为never-visible、冻结当时highest/client-confirmed/next/exhausted并写持久operation receipt后一起提交。重试先按operation id返回原receipt，不能再次increment。

`device.register`、Session↔Device bind与`device.revoke`共享按account派生的transaction advisory lifecycle guard。revoke在guard内先无锁读取actor与target-device session id候选集，再按`session_id`一次锁齐并重新查询；集合变化则整事务回滚并从guard起有界重试。集合稳定后才依次锁target device/state、一次性reauth grant与按id排序的refresh grants，最后在同一事务撤销device及全部目标Session/Grant。任何Session绑定/创建路径在写device binding前也必须取得同一guard，故不会在revoke重验后插入漏网Session。绝不能采用“actor Session→target device→target Sessions”的反序，否则会与exchange的“target Session→device”形成死锁环；也不得用“先查数量再插入”、JVM`synchronized`或Redis锁替代数据库一致性保障。

默认采用 PostgreSQL `READ COMMITTED + 显式行锁/唯一约束`，不为简单起见把整个服务切成 `SERIALIZABLE`。死锁、连接失败或数据库重启必须回滚，并以冻结的 retryable 5xx/transport 语义返回；不得在服务端盲目重放未受 sequence 保护的业务方法。

## 9. 合并、删除与特殊实体处理

### 9.1 普通 typed entity

- [ ] 每个 target handler 只接受 `sync_field_registry.yaml` 声明的字段、nullable、operation 和 `merge_key`。
- [ ] field version `<= base_entity_version` 时可接受；晚于 base 且值相同为幂等接受；晚于 base 且值不同生成冲突。
- [ ] 同设备per-key predecessor只可由exact receipt/causal anchor吸收；ack后离线超过180天再上传仍可验证。链断、前驱未应用或当前version已被其他设备推进时不得误判为同设备顺序。
- [ ] entity存在unresolved conflict时，普通update/delete/restore即使修改其他merge key也返回稳定`rejected + SYNC_ENTITY_CONFLICT_BLOCKED`并消费sequence，只有sequenced resolve route可写。
- [ ] entity version 只由 Backend 分配，`updated_at/created_at` 仅用于展示和诊断。
- [ ] create race、唯一性、弱引用和跨账号引用由数据库约束与 Application 授权共同防守。
- [ ] change payload 必须是冻结的 typed 形状，使旧 cursor 重试可安全重放。

### 9.2 删除与恢复

- [ ] delete 在同事务写 tombstone、field/entity version 和 change；普通读取立即排除。
- [ ] delete-vs-edit 保持 tombstone，编辑值只进入 conflict candidate。
- [ ] restore 是新的 sequenced mutation、新 entity version 和新 server sequence，不回拨旧版本。
- [ ] tombstone 至少保留 180 天；低于 retention floor 的 cursor 明确 `SYNC_CURSOR_EXPIRED`，不能静默从第一页继续。
- [ ] unresolved conflict引用的tombstone被pin到resolve+30天且满足安全cursor；不得在180天任务中删。payload可清后仍永久保留轻量`sync_deleted_entity_anchors(account,target,id,delete_version,delete_sequence)`至账号删除，使过期设备bootstrap后上传旧编辑时能形成“云端已删/本机编辑”typed conflict，而非not-found或静默create。

### 9.3 HabitCheckIn

- [ ] increment/decrement 以 `operation_id` 去重并可交换累计；网络重试不得重复计数。
- [ ] replace/clear 与 base 后增量竞争时生成冲突，不以请求到达顺序静默覆盖。
- [ ] target/unit snapshot 保持打卡时事实；服务端不根据当前 Habit 重算历史。
- [ ] 定点 `_hundredths` 和合计必须保持 JSON safe integer，并有溢出失败测试。

### 9.4 recurrence 与 occurrence state

- [ ] recurrence revision 为 immutable；系列修改创建新 revision，不覆写旧 revision。
- [ ] R2-C只接收当前整系列`event.update`与已有occurrence cancel/complete/reopen的typed mutation；`update_occurrence/split_future/update_series`及自由scope字段均拒绝，等待R3专项ADR/Contract。
- [ ] occurrence state 使用稳定 event/revision/occurrence identity，不写回 Event series status。
- [ ] Backend 只验证 Contract 形状、引用和 revision 竞争；不展开 occurrence，不复制 DST/gap/fold 算法。
- [ ] 无法证明旧 revision exception 可安全挂接时生成冲突，不由 Java 猜测等价。

### 9.5 用户偏好与安全资料

- [ ] `user_preferences` 新写/同步只接受 `timezone`、`habit_progress_color`、`default_reminder_methods`（V1仅`ring/popup`）和`auto_enable_reminders_on_other_devices`，按服务端接收sequence LWW；locale新写拒绝且不进入change。
- [ ] `default_reminder_methods`严格为有序、唯一、长度0..2的数组；Backend验证并原样保存顺序，不排序、不静默补popup。目标适用矩阵由C++/Flutter消费，Backend不从偏好物化Reminder。
- [ ] `timezone`只校验/保存IANA workspace偏好并生成其change；Backend不接收OS device timezone，不解释`follow_device`，也不因偏好变化生成Reminder事实或调度副作用。
- [ ] `auto_enable_reminders_on_other_devices` 的账号默认值固定为 `false`，只在未来设备首次注册时取样：账号生命周期首个成功注册设备的 `receive_reminders=true`，后续新设备按该偏好初始化。revoked历史行或独立first-device marker必须阻止“active清零后再次首台”；之后修改偏好不得批量更新既有 `user_devices`，也不需要记录 reminder origin device。
- [ ] `user.update_current` 只允许 `username/display_name`；四项偏好通过 `preferences.update` 写本地事实/Outbox，再由 `sync.exchange` 上传为 `user_preferences` mutation；locale只兼容读，注册请求仅允许固定`zh-CN`且不产生同步change。
- [ ] `user.update_current`、头像专用 API 和已确认邮箱流程必须在各自事实事务内递增 `account_profile_revision` 并追加 download-only `account_profile` typed change；邮箱确认前不广播。
- [ ] 既有 `user.get_current`、`user.update_current`、头像与确认邮箱成功响应按冻结 Schema 同时携带 `account_profile_revision` 和 `preferences_revision`；二者独立推进，旧 revision 不得覆盖新快照。
- [ ] Backend 对任何 `target_type=account_profile` upload mutation 在业务锁前返回冻结的 payload/operation 错误；不得把它当作客户端 LWW 设置。
- [ ] 邮箱、密码、Token、Session、Challenge、installation 摘要和密钥永不进入普通 mutation、change payload 或 conflict candidate。
- [ ] V1 `reminder_intent` 明确拒绝 `wechat`；Notification/Alarm/Ring payload 必须在 Contract 或 Application 边界失败。

### 9.6 游客导入回执

- [ ] `import_begin`复算冻结UUIDv5 namespace上的canonical `account_id + LF + source_workspace_id + LF + decimal(source_epoch)`，以`(account_id,source_workspace_id,source_epoch)`取得/创建稳定lineage，绑定origin device、source snapshot、C++提出的UUIDv4 batch/predecessor、nullable严格takeover reason、各target/portable/total counts、`total_canonical_bytes`、mapping/manifest hash。checked证明`begin+total+1<=JSON MAX`后才能写receipt/reservation/highest；账号锁内按声明bytes预留quota；相同batch任一值不同为replay mismatch，只有origin device可续旧ordinal。
- [ ] begin/items只写typed staging与`staged` mutation/item receipt，不调用canonical target handler。duplicate必须回放`original_status=staged`；普通查询/bootstrap看不到未commit staging。
- [ ] `import_commit`是单项route：锁全batch/target，验证恰好`0..N-1`、hash/count/ref/domain规则后，才在一个事务调用handlers并生成连续publish begin/chunks/commit区间。任一失败canonical零写，commit稳定rejected，batch=`repair_required`。
- [ ] repair及published后同epoch guest source变化，都以same epoch/lineage/new batch/predecessor完整restage并复用该lineage mapping；successor source闭包只并集当前guest同epoch图与同epoch历史mapping，缺失者发typed delete。completed旧epoch mapping/provenance保留供审计/marker，但绝不进入新epoch删除闭包；新epoch使用新UUIDv5 lineage。后继成功时旧失败批superseded，旧published批保持审计。普通staging可按规则abandon；reconciliation payload TTL必须走range-close并保持required/full-successor。
- [ ] current非published batch因origin revoked、同origin fresh lifecycle丢失本地证据，或TTL回收reconciliation payload时，status返回`full_successor_required`及source epoch/range；registered client必须先调独立takeover。服务端按reason授权门禁与§8.3全序仲裁：已有begin reservation则建立virtual no-effect terminal range、推进origin highest并保存`seen_range_closed` proof；只有已完成device fence且旧origin generation零receipt的absent fence可保存不推进sequence的`never_visible_after_transport_fence` proof。已到达receipt不改写，迟到旧payload先命中batch fence返回`IMPORT_BATCH_SUPERSEDED`。旧commit先赢返回already-confirmed，stale返回`IMPORT_VERSION_CONFLICT`。客户端接纳proof后才能以resulting revision发送同epoch完整successor；sequence/transport generation=MAX分别返回对应exhausted。该接管不是abandon，有未cleanup predecessor也允许并保持reconciliation_required。
- [ ] `sync.import.status`按exact batch返回九态中的当前状态（含completed/superseded/abandoned），或按source workspace + source epoch（snapshot hash可选）发现当前需恢复handle/严格empty；返回published head、cleanup-through、reconciliation/resume、origin及range而不返回payload。range已关闭时可重取proof；completed旧epoch不得充当current。published大payload/receipt在该epoch head cleanup确认前pin，永久lineage/mapping/provenance/marker保留但不参加新epoch删除闭包。
- [ ] begin/item/commit只允许batch origin device。cleanup-confirm由同账号任一registered device提交，但request/receipt/lineage锁全部带source epoch；只验证该epoch current head与连续predecessor chain并推进该epoch cleanup-through，绝不能覆盖新epoch。相同epoch/through终态幂等优先，其他stale返回`IMPORT_VERSION_CONFLICT`且零写。
- [ ] `sync.import.abandon` 与 commit/TTL 使用同一锁序和独立 HTTP CAS。batch 存在时先返回相同 terminal 幂等结果，再校验 revision；其他 stale 返回 `IMPORT_VERSION_CONFLICT + current stage/head/revision` 且零写。
- [ ] batch 缺失且 `expected_import_revision=0` 时，复算 UUIDv5 lineage，并校验 source epoch、manifest/count/bytes、batch/origin generation 与 begin/terminal range。begin 为 origin highest+1 且无 receipt/reservation 时，原子建 closed batch/range、推进 highest 并返回 seen proof；有 gap 时只建不消费 sequence 的 absent fence，返回 `proof=null/sequence_advanced=false`，重复请求稳定。
- [ ] matching 迟到 begin/items/commit 在 generic replay 前命中 fence：begin 后来成为 next 时可原子关段，否则返回 request-level abandoned 且零 receipt/highest；其他 receipt 占号也不能触发 device replay freeze。旧 generation 经 device fence 后可转 never-visible proof。
- [ ] commit 先赢返回 already-confirmed 与 publish metadata。带未 cleanup published predecessor 的 reconciliation successor 不可普通 abandon；privacy destroy/30 天本机到期不等待网络。`server_confirmed` 只表示服务端已发布，客户端仍须取得 canonical publish group 或 bootstrap marker，并记录 `publish_applied` 后才可清 guest。

### 9.7 Conflict lifecycle feed

- [ ] 任一mutation首次形成冲突时，在事实/field-version/conflict/receipt同一事务写一个不可拆change group，含entity change与`conflict_delta.created`完整typed unresolved快照（conflicting + auto-merged groups）；上传terminal result与download引用同一id/version。
- [ ] `sync.conflict.resolve`在expected version与device sequence校验后，同一不可拆group写最终事实、conflict resolved/version/time、resolved delta与receipt；客户端无需猜测。合法envelope下的not-found/version-mismatch/already-resolved/domain failure也必须写稳定`rejected` terminal receipt并消费sequence，附当前conflict/resolved effect group或refresh metadata；duplicate完整重放，客户端以新sequence重试。只有auth/protocol/hash/gap等请求级失败不消费。普通writer在事务提交前仍受entity门禁。
- [ ] 普通group分页永不拆；import publish区间采用begin/chunks/commit隔离分页。重复/迟到读取保持同一hash/version，resolved后旧created不能复活。

## 10. Cursor、增量下载与 bootstrap

### 10.1 Cursor

- [ ] 使用云同步-02冻结的 HMAC 认证 opaque cursor，绑定 account、device、generation、last sequence、snapshot upper bound、协议版本和 key id。
- [ ] 使用独立 cursor key 配置和 key ring，不复用 JWT secret；密钥只从环境/受限文件注入，不进入日志或响应。每个key记录签发generation/最大sequence；常规退休key只在所有账号签发范围都被retention floor/generation越过且相关bootstrap session过期后删除，保证长期离线旧cursor仍先被认证为expired/generation-mismatch。紧急泄露吊销走显式安全事件，不冒充常规轮换。
- [ ] 语法/签名无效、早于 retention floor、跨账号、跨设备、generation 不符分别返回 `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH`、`SYNC_CURSOR_GENERATION_MISMATCH`；只有 expired/generation mismatch 指示 bootstrap，其余 fail closed。
- [ ] exchange每页携带同generation `retention_floor_server_sequence` 与服务端UTC `resolved_conflict_cleanup_before`；二者来自注入Clock/同一事务快照并绑定cursor响应，绝不读取客户端时间。
- [ ] 每页按`server_sequence`升序且`<= snapshot_upper_bound`；普通change group不可跨页，limit按顶层group并同时受response soft/hard bytes限制。超过soft cap的单一合法组独占页；registry与写入预检保证不超过hard cap。`has_more=true`必须非空且next cursor严格前进。
- [ ] import publish interval在同一commit分配，upper bound包含全区间或完全不含；组首页以begin起始、末页以commit结束、中间页仅chunks，区间不得夹普通group，前后普通group另起页。客户端可用staging transport cursor续页，但visible cursor只在commit后跃迁。
- [ ] retry旧cursor返回相同immutable group/chunk。staging cursor丢失从begin前visible cursor重拉；若已低于floor明确expired→bootstrap，不根据wall clock重排或跳过区间。

### 10.2 bootstrap

- [ ] `bootstrap_cursor`为空时依固定锁序锁当前Session、requesting device/state与account sequence，重验request sync transport generation，并冻结transport/account generation、upper bound、retention floor、server cleanup-before以及`device_highest_client_sequence_at_snapshot/device_client_confirmed_through_at_snapshot`；所有页/token绑定同一bundle，后续变化不污染该bootstrap。旧transport generation零写且不创建session/items。
- [ ] 同一创建事务按冻结kind/target/id/conflict-id/merge-key/ordinal顺序，把typed after-image/tombstone（含entity/field version）、无业务payload的typed deleted entity anchor、全部unresolved conflict、requesting-device当前per-key causal anchors及所有`commit_server_sequence<=upper_bound`的typed import publish marker materialize到immutable items。每个union单项在其源事实/冲突形成前已受Contract hard-cap门禁，materialize再防御性验证`max_bootstrap_item <= response hard cap - envelope`，绝不截断或生成无法翻页的session。导入canonical事实的后继/tombstone/deleted anchor保留immutable lineage+source provenance；marker含lineage/batch/group/commit sequence/manifest、永久mapping digest及当前snapshot provenance digest/count，不对旧业务值做digest。未commit staging不入快照，已commit整图/后继与marker全入；客户端校验后仍需把当前快照作为baseline重放pending overlay才记publish-applied。
- [ ] 首次响应由 Backend 返回服务端生成的 `bootstrap_id`、sync transport/account generation、snapshot upper bound、device-sequence recovery bundle、第一页与下一页 token；Kotlin 收到并校验它之后才调用 C++ `sync.begin_bootstrap`。fresh DB只有在完整finalize后才可把本机ack基线提升到snapshot highest并在后续exchange确认；Backend在此之前继续pin旧receipt/effect。Backend 不要求客户端在首请求前提供或猜测 bootstrap id。
- [ ] 创建事务提交后释放全部锁和连接；后续 HTTP 页只从该 session 的 immutable items 按 ordinal 读取，不跨请求保持事务、数据库 snapshot 或连接。
- [ ] HMAC page token 绑定 account、device、bootstrap session、protocol、sync transport generation、account generation、upper bound、last ordinal 和 expiry；每页事务重新锁/验证Session与current transport generation，fence后旧token零写且不能续页；正常重试返回相同 items/page hash，不能受当前事实变化影响。
- [ ] snapshot upper bound 之后的写入只由 finalize 后的普通增量 change 补齐，绝不能混入已 materialize 页面；所有 change producer 都必须先遵守 account sequence 锁顺序。
- [ ] TTL 固定为 24 小时；过期 session/token 返回 `SYNC_BOOTSTRAP_EXPIRED`，当前账号 generation 与 session 不同时返回 `SYNC_BOOTSTRAP_GENERATION_CHANGED`；客户端丢弃未发布 staging 并重新 begin，不返回空页或部分完成假象。
- [ ] 首页响应丢失后的相同`bootstrap_cursor=null`请求只有在session冻结的sync transport/account generation与device highest/client-confirmed仍等于当前state时，才按`(account_id,device_id,protocol_version,transport_generation)`幂等复用并返回同一首页；若旧session创建后该device继续同步、推进确认水位或完成fence，设备锁内先将旧session标superseded再创建新snapshot。这样真正response-loss仍稳定，旧bootstrap→继续sync→清库的fresh client不会取得过时recovery bundle。过期/superseded/旧generation items按TTL有界清理且不得污染新session。

## 11. 设备、re-auth 与会话终止

### 11.1 注册与 10 台上限

- [ ] `installation_id` 由客户端随机生成；Backend 只保存 Contract 冻结的摘要/HMAC，不记录 Android ID、IMEI、广告 ID或原值日志。
- [ ] `display_name` 由 Kotlin 生成规范化默认值或用户提供；Backend 只接受 trim 后 1..64 个 Unicode code points 的非空值并拒绝超限，不按 UTF-16 code unit/UTF-8 byte 错截断，也不自行读取或推测硬件名称。
- [ ] 同账号同 installation 重试在上限计数前返回同一 active device；新 device 与 `sync_device_state(sync_transport_generation=0, highest_client_sequence=0, client_confirmed_through=0)` 同事务创建，`sync_enabled`诊断镜像genesis为true。响应严格为highest<MAX时`next=highest+1/exhausted=false`，highest=MAX时`next=null/exhausted=true`，并含transport generation与client-confirmed。现有账号库只用register结果防倒退；同一active device清库/销毁后新建本地库必须先执行device fence，再以其合法next值播种并bootstrap，最终由snapshot recovery bundle闭合旧receipt水位。sequence或transport generation耗尽的device只读/不可重建可写库，V1不自动revoke/register换号；Backend绝不重置为1或拿sync镜像决定客户端调度。
- [ ] active device 上限在同一 transaction guard 内计数并插入；并发第 10/11 台必须只有一个可成功。
- [ ] 第 11 台返回 `DEVICE_LIMIT_REACHED` 时，在同一事务把当前 Session 标为 `pending_registration` 并保存本次 attempted installation digest；此状态只允许 refresh/logout、`user.get_current`、`device.list`、`auth.reauthenticate`、`device.revoke` 和相同 installation 的 `device.register` 重试，所有其他 API 在统一授权门禁返回 `DEVICE_NOT_REGISTERED`。
- [ ] pending 态的 `device.list` 返回 `registration_pending=true/current_device_id=null`；reauth Grant 允许 `actor_device_id=null`，但必须绑定当前 Session + attempted installation digest + target device + purpose。撤销一个旧设备后，客户端必须以同一 installation 重试 register；成功创建/复用 active device、绑定 Session 并清除 pending 状态后才可打开同步能力。
- [ ] 账号生命周期首台成功注册设备 `receive_reminders=true`；后续新设备读取当时的 `auto_enable_reminders_on_other_devices`（默认 `false`）作为初值。该取样与注册事务一致，revoked历史不重置首台判定，偏好后续变化不改既有设备。
- [ ] revoked device 行与历史 Session 保留，不得被相同 installation 的普通重试复活。用户以后显式登录时可用同一 installation 创建新的 `device_id`；partial unique active installation 约束保证同时最多一个 active 行，UI 将其展示为一次新设备登记。

### 11.2 rename/settings CAS

- [ ] 路径 device 必须属于 Principal account；跨账号一律按冻结的不可枚举语义失败。
- [ ] `expected_device_version` 是设备资料 CAS，不是 sync `entity_version`。
- [ ] `device.update_settings` 只允许当前 Session 绑定设备以 typed patch 修改 `receive_reminders` 和/或上报 `sync_enabled`；服务端镜像只用于设备列表/诊断，绝不控制 Worker、本机网络调度或提醒调度。业务同步关闭时，Kotlin 的独立 settings reporter 仍可调用本端点，但请求不得携带 mutation、cursor 或业务事实。
- [ ] settings report 在行锁内执行 CAS：`current_version=expected_device_version` 时更新；响应丢失后的同 expected version + 同 typed patch 重试，若当前版本恰为 expected+1 且目标字段已等于请求值，则幂等返回当前快照；其他版本或字段差异返回 `DEVICE_VERSION_CONFLICT` 与脱敏当前快照，客户端重新基于新版本决策。

### 11.3 revoke

- [ ] reauth token 固定 5 分钟 TTL；普通态绑定 account/current session/actor device/purpose/target device，pending 态绑定 account/current session/attempted installation digest/purpose/target device 且 actor device 为空。消费时重新核对 Session 当前 registration state 与 device/digest，任何变化均拒绝，并在撤销事务中原子单次消费。
- [ ] V1 禁止撤销当前设备；当前设备退出复用 logout 路径。
- [ ] 同事务标记目标 device revoked、更新 device version、撤销其全部 Session 和 Refresh Grant并写审计时间/原因。
- [ ] Access 与 Refresh 路径对 device-revoked Session 返回 `DEVICE_REVOKED`，使 Kotlin 进入统一清 token、关库、销毁 key/cache 的终止路径，而不是只显示普通登录过期。
- [ ] revoked device 记录保留到足以阻止旧 installation 复活；V1 不提供后台物理远程擦除假象。

### 11.4 Access Token generation 与服务端提前拒绝

- [ ] `access_token_generation` 是 Kotlin Broker 对本地 token 快照分配的单调版本，不进入 Backend 请求/响应、JWT claim 或 PostgreSQL。Backend 不新增 generation endpoint，也不读取客户端 generation。
- [ ] JWT 验证与 Session 查询可以因撤销、密钥轮换或安全状态提前返回冻结的 401，即使客户端时间上 token 尚未过期；既有 refresh 端点继续悲观锁轮换并保持 Refresh Token 重放撤销 family 的安全语义。
- [ ] 客户端以被拒绝的本地 generation 判断“直接换用较新 token”或“加入一次 single-flight refresh”，且最多重放原请求一次。Backend 必须让 401/Auth error 与 refresh 成功/终止结果稳定可区分，不提供第二个 refresh endpoint，也不把业务错误伪装成 401。

### 11.5 Logout 的服务端终态

- [ ] `POST /auth/logout` 对当前 Session 幂等，返回 `succeeded` 或 `already_invalid`；重复调用不会创建新 Session、不会改变其他设备，也不因 token family 已终止而伪装 5xx。
- [ ] Kotlin 的 `server_then_local` 必须等到上述终态后才清本机会话；网络/5xx 返回 `unreachable` 并保留本地会话供用户重试，Backend 不参与 `force_local`。
- [ ] `cache_policy=retain_30d|destroy_now` 与 `auth.session.clear_local` 的 reason/action matrix 只控制本机密钥和账号缓存；Backend 不接收该字段、不声称远程擦除，只保证 logout/session/device-revoked 的可区分终止原因稳定可重放。
- [ ] `GET /system/time`是无body、无bearer、no-store且有界限流的exact响应；只返回注入`Clock`的UTC `server_time`，不访问数据库，也不泄露节点/Session/Device状态。

## 12. 清理、保留与 Scheduler

Scheduler 只执行持久化清理，不参与在线合并，也不扫描 Reminder。所有任务使用注入 `Clock`、有界批次以及 PostgreSQL advisory lock、租约或 `FOR UPDATE SKIP LOCKED`，多实例启动时仍只处理一次。

清理顺序与规则：

1. 清理过期且未消费的 reauth grant；保留最小安全审计，不记录 token 原文。
2. resolved conflict到`resolved_at+30 days`且相关tombstone也满足安全cursor后，才CAS标记expired并有界删除整条candidate；unresolved conflict无限期保留并pin其tombstone。resolution幂等由独立receipt承担。
3. 未被pin的tombstone满180天后，先原子推进account retention floor/必要generation，再按小批删除payload/change；落后设备收到`SYNC_CURSOR_EXPIRED`。同步写/保留轻量deleted-entity anchor，使其bootstrap后上传旧编辑仍得到typed delete-vs-edit conflict；anchor只随账号删除。
4. 普通change feed按Contract冻结窗口清理：先在账号序列锁内原子推进`retention_floor_server_sequence`或必要generation，再小批删除低于floor且未被unconfirmed upload receipt、import publish、active bootstrap或unresolved conflict pin住的groups/items。旧cursor因此稳定得到expired/generation-mismatch；在ADR尚未冻结具体窗口前该清理切片保持blocked，不能默认永久保留或按表大小猜删。
5. active device中所有 `client_sequence > client_confirmed_through` receipt及其引用的effect group无限期保留；客户端只有在terminal receipt与effect已本地apply/权威bootstrap覆盖后，才由后续exchange推进confirmed水位。`≤ confirmed`仍至少保留180天/retention安全窗；revoked device未确认receipt/effect group自撤销至少180天。不能用“响应已发送”或通用24h TTL清理。
6. import staging满30天时，普通且无published收敛义务的批可abandon；若已有begin reservation而suffix未收齐，必须用统一range-close事务生成proof并推进origin highest。reconciliation批通过同一use case标`superseded(reason=ttl_payload_reclaimed)`，lineage仍required/full-successor。compact range/proof/receipts受origin confirmed-through保护并至少保留180天；source workspace+epoch→lineage、同epoch mapping/provenance与marker保留至账号删除。published payload在同epoch cleanup-through越过前pin；清理不得留下失去manifest/epoch/lineage/range/proof的孤立ordinal。
7. active device的`sync_device_causal_anchors`不随180天receipt清理；只保留每target/entity/key最新紧凑行。device revoke后按专门保留ADR清，不能影响active设备长期离线后继验证。
8. materialized bootstrap session到固定24小时TTL后先CAS标记expired，使新页请求稳定返回`SYNC_BOOTSTRAP_EXPIRED`；再按账号/session小批删除items，最后删除session，避免与正在读取的页事务竞争。
9. 每批提交并记录数量、耗时、最老retained sequence和失败原因；日志不得含业务payload。

清理失败不得影响 API 已提交业务事实；有限重试后保持可再次认领状态。没有 MQ、Redis 或外部 Scheduler 依赖时，PostgreSQL 仍是唯一保留真相源。

## 13. 安全与滥用防护

- [ ] 所有账号范围查询同时带 `account_id`；禁止先按全局 entity id 查询再在 Java 中比账号。
- [ ] 在认证过滤器后的统一 capability gate 强制 `pending_registration` 白名单；任何新增 Controller 默认不在白名单，不能依赖 URL 前缀或各 Controller 手写判断。
- [ ] `device_id`、`conflict_id`、`entity_id` 和 cursor 均不构成授权；猜测其他账号 ID 不得泄露存在性、标题或版本。
- [ ] 同步请求限制最多 100 mutation、下载最多 500 change；1 MiB 是解压后候选上限，最终值以冻结 Contract 为准。
- [ ] 若支持 request compression，必须流式计数并抵抗 gzip bomb；若 Contract 未声明压缩则明确拒绝，不做隐式兼容。
- [ ] 配置 JSON 最大深度、字符串/集合长度和处理超时；超限在进入事务前失败。
- [ ] Sync、reauth 和 device 操作分别按账号/设备/IP 进行有界限流；单实例内存限流只可作为内测已知边界，公开发布前必须重新评估多实例语义。
- [ ] import quota在B0冻结为初始门槛：每batch最多50,000 items/128MiB canonical bytes，每账号最多2个非终态batch且active staging合计不超过100,000 items/256MiB；同source仍最多一个可上传batch。单批必须实测覆盖总计划20,000组合业务事实展开后的全部ordinal，否则B0不通过。begin按manifest声明bytes在账号锁/约束下预留，item按RFC 8785实际canonical bytes累计，commit复算；换source或少报不能绕过。超限begin或累计越界写最小capacity-rejected batch/range tombstone并消费当前sequence，但零canonical，已排队items/commit稳定rejected/no-op使客户端排空，status/abandon/takeover可发现。M6调整须先修Contract与五层fixture。
- [ ] 不记录 Authorization、Refresh/Reauth Token、密码、验证码、cursor 原文、installation 原值、请求/响应业务 payload 或 conflict candidate。
- [ ] 日志只保留 request id、脱敏 account/device 摘要、operation、数量、结果类别、耗时和首个根因。
- [ ] CORS 继续默认拒绝浏览器来源；生产/公网只允许系统信任 HTTPS，不能关闭证书校验。
- [ ] 同步能力默认只对测试账号白名单开放，entitlement由服务端账号能力表/受控配置拥有并审计。`user.get_current`可返回只读能力投影供解释，但`device.register`与所有同步业务gate必须再次校验；非白名单统一`SYNC_NOT_ENABLED_FOR_ACCOUNT`且事务中不创建device、pending-registration、sync state或业务事实。不能用客户端开关当授权。
- [ ] Cursor HMAC、JWT、数据库、SMTP 和 TLS secret 分离，可独立轮换；生产配置不得使用本地默认值。

## 14. 分阶段实施

本节只排序第 5–13 节的实现，不重述事务或协议：

| 阶段 | 工作锚点 | 主要产物 | 退出证据 |
| --- | --- | --- | --- |
| B0 Contract/现状门禁 | §3–§4 | 16 个已实现端点校准、Contract revision/hash、V1–V3 checksum、JCS 与模型决策 | `CONTRACT FROZEN` 且无模型/安全未决项 |
| B1 DTO/Migration 骨架 | §5–§7 | 显式 DTO/validator/error mapping、前滚 Flyway、JPA/Repository、fixture runner | DDL/JPA/索引/模块依赖与机器模型一致 |
| B2 Device/Session | §6、§11 | reauth、entitlement、registration/pending、fence、CAS/revoke 和 Session 绑定 | 并发第 11 台可恢复、撤销闭环、跨账号全拒绝 |
| B3 Typed facts | §7、§9 | target handler、复合 FK、field/entity version、tombstone/restore | `FX-TARGET` 正反例通过，无万能 Map/Entity 或 occurrence engine |
| B4 Exchange/change | §8、§10 | 单事务 exchange、sequence/receipt/anchor、merge、fixed-bound feed 与 cursor | 并发/重试/断线/数据库故障不重写、不跳号、不丢 change |
| B5 Bootstrap/conflict/import | §9–§11 | materialized bootstrap、conflict route、remote status、Contracts-02 `IMP-*` 的服务端职责 | `FX-CURSOR`、`FX-BOOTSTRAP`、`FX-CONFLICT`、全部 `FX-IMPORT-*` 通过 |
| B6 Retention/security | §12–§13 | Scheduler、限流/上限、脱敏、白名单、secret 与运行文档 | 30/180 天、落后设备、unresolved pin 和多实例认领有 PostgreSQL 证据 |
| B7 验证与制品 | §15–§18 | 未跳过的 Testcontainers、容量报告、预构建镜像、部署/回滚/ACME 证据和交接包 | 只达到 `BACKEND IMPLEMENTED / AWAITING INTEGRATION` |

CloudBackend当前只采用云同步-01的冻结前ROM `25–40`人日，不作为承诺或范围上限。B0/Contract冻结后按强类型DDL、历史迁移、冲突/导入并发和Testcontainers矩阵重新基线化；可拆分独立验收批次，但不得为贴合估算削减事务、安全或测试门禁。

## 15. 测试与验证矩阵

### 15.1 自动化套件与规则追踪

Backend 测试必须消费 Contracts-02 §13 的 `FX-*`；下表只补充 Java/PostgreSQL 可观察证据，不复制第 6–13 节算法。所有时间测试注入 `Clock`，禁止真实 `sleep`。

| 套件 | 实现锚点 | Contract fixture | Backend 特有证据 |
| --- | --- | --- | --- |
| HTTP / DTO | §6 | `FX-TARGET`、`FX-CANONICAL`、`FX-COUNTER`、`FX-CROSS-LAYER` | endpoint/method/auth/content type、`ApiResult`/HTTP、strict parse、Principal identity、JCS/hash 和 counter 并发耗尽 |
| Device / Session | §11 | `FX-SESSION-DEVICE`、`FX-RETENTION-NOTIFY` | entitlement 零写、register/pending/reauth/settings/revoke、提前 401、logout `server_time`/`system.time`、Session 锁竞态 |
| Exchange / merge | §8–§9 | `FX-SEQUENCE`、`FX-RUN`、`FX-MERGE`、`FX-CONFLICT`、`FX-FAILED-LOCAL` | 五类 terminal/duplicate、receipt pin 与 ack-only、no-effect predecessor、field/change/conflict/sequence 同事务故障注入 |
| Cursor / bootstrap | §10 | `FX-CURSOR`、`FX-BOOTSTRAP` | HMAC 五类错误、key rotation 水位、materialized snapshot/TTL/hard cap、response-loss 重用或 supersede 和事务整批回滚 |
| Import | §9.6、Contracts-02 §7.6 | 全部 `FX-IMPORT-*` | begin reservation、commit 原子发布、status/CAS、takeover/abandon/range proof、epoch mapping、quota、cleanup-confirm 与旧 commit 并发 |
| JPA / Migration / concurrency | §7–§12 | 全部适用 `FX-*` | fresh/V1–V3 前滚与 checksum、JPA validate/FK/CHECK/index、固定锁序、10/11 台注册、deadlock/连接中断安全重试 |
| Security | §13 | `FX-CURSOR`、`FX-SESSION-DEVICE`、`FX-CROSS-LAYER` | 未认证/撤销/跨账号全拒绝、不泄露存在性、日志无 secret/payload、Refresh Token reuse 仍撤销 family |
| Scheduler | §12 | `FX-MAINTENANCE`、`FX-IMPORT-CLEANUP` | 30/180 天边界、pin/floor/marker、双实例唯一认领、强杀恢复、unresolved 永不 TTL 删除及旧 cursor 过期 |

### 15.2 必须执行的命令

在 `cloud_backend/` 使用仓库现有 Wrapper：

```powershell
.\mvnw.cmd test
.\mvnw.cmd verify
```

`verify` 必须实际运行 PostgreSQL Testcontainers；当前 `disabledWithoutDocker=true` 会跳过，因此验收记录必须核对 Failsafe 报告的 executed/skipped 数，Docker 不可用时本阶段标记“数据库集成未验证”，不得以退出码 0 冒充通过。CI/发布门禁应增加一个要求 Docker 可用且关键 IT 数量非零的 profile 或等价检查。

## 16. 容量与性能门禁

严格采用总计划内测基线：

- 100 个测试账号；每账号最多 10 台设备。
- 每账号至少 20,000 条组合事实，另有单账号 50,000 条压力样本。
- 单批最多 100 mutation；单页最多 500 change。
- 20 个并发同步客户端下，100 mutation 服务端处理 p95 候选目标不高于 1 秒；该值是需实测校准的内测目标，不是生产 SLA。

必须证明：

- [ ] 空增量 exchange 不产生业务写、receipt 垃圾或无意义 change。
- [ ] 100/500 项处理不一次加载账号全部事实，不产生 N+1 或 collection fetch + pagination。
- [ ] 20,000 条 bootstrap 可中断续传；50,000 条下 heap、GC、连接池和响应体有界。
- [ ] materialize 20,000/50,000 条 snapshot 的事务时间、writer 阻塞、临时磁盘增长和 TTL 清理吞吐有独立上限；不得把全量 payload 堆入 JVM heap。
- [ ] 20,000-item import commit专项测量完整validation/锁等待/单事务canonical publish/change-group生成/WAL与磁盘峰值；候选门槛为p95≤10秒、transaction timeout 30秒、锁等待≤2秒，超时/进程强杀必须整批回滚。最终数字在B0/容量记录签署，不能拆事务牺牲原子可见性。
- [ ] import commit与同账号ordinary mutation、resolve、bootstrap materialize并发时遵守统一锁序：普通写要么在有界等待后成功，要么得到冻结retryable错误；不得死锁、饿死或看见半图。staging quota/30天abandon清理的磁盘与吞吐单独记录。
- [ ] 热点账号 sequence row、同实体锁和同设备锁的等待时间有统计；无死锁或饥饿。
- [ ] change/conflict/receipt/tombstone 180 天模拟后的索引大小、查询 p95、清理吞吐与磁盘增长已记录。
- [ ] 数据库连接池在 4 GB 测试机从最大 5 开始校准；API 容器上限约 1.5 GB，JVM 从 256 MiB/1 GiB 堆区间实测。
- [ ] 压力发生器和 Maven 构建在开发机/CI 运行，不与测试服务器 API/PostgreSQL 争用 4 GB 内存。
- [ ] 磁盘 70% 进入人工关注，85% 暂停压力写入并按测试数据清理 runbook 处理；不静默删除在线同步事实。

## 17. 测试服务器部署门禁

现有 `compose.yaml` 只用于本地开发。公网测试另建 override，不能破坏本地配置：

- PostgreSQL 不发布宿主机公网 5432；API 8080 只绑定 loopback 或容器网络。
- 80 仅用于 ACME/HTTPS 跳转，443 提供系统信任的 TLS；API 不直接明文暴露公网。
- 部署预构建且已验证的镜像，不在 4 GB 服务器长期执行 Dockerfile Maven 构建。
- 数据库、JWT、cursor HMAC、SMTP 和 TLS secret 从服务器环境/受限文件注入，禁止提交仓库或共用。
- API/入口日志轮转，不保存请求/响应业务 payload；PostgreSQL、镜像和日志分别统计磁盘。
- 测试与正式账号环境隔离；同步功能默认只对白名单账号开放。
- APK与运维交付只引用受控DNS hostname/构建配置，不硬编码服务器公网IP；动态IP变化由DNS记录更新和可观测TTL收敛处理。证书SAN必须匹配hostname，旧/新地址切换要以两端解析、TLS和health证据验收；短期临时endpoint也必须经同一配置注入并明确到期，不让客户端发版绑定IP。
- CentOS 7 已 EOL，只能复用已稳定运行的现有容器环境做短期测试。若现有运行时不能安全运行 Java 21/PostgreSQL 镜像，停止部署并更换受支持系统，不现场盲升内核/Docker。
- 每次部署同时记录 current/previous 镜像 digest、Contract hash、Flyway version 与配置模板版本；配置新增项必须具备向后兼容默认或在发布前 fail-fast，previous 镜像必须在新 Schema 上完成兼容验证后才可列为回滚目标。
- 回滚固定为“切回已验证 previous 镜像 + 对应兼容配置”，不回滚已执行 Flyway；一旦 Migration 使 previous 镜像不兼容，就禁止镜像回退并只走经过演练的前滚修复。测试服务器至少完成一次健康检查失败触发的回退演练并保存时间线、命令结果和数据一致性证据。
- 80/443 入口启用 ACME 自动续期；以 staging CA 或等价安全方式演练签发与续期，监控证书剩余天数和最近续期结果。续期失败必须产生可见告警，并由人工按 runbook 核对证书链、DNS/80 challenge、入口 reload 与最终到期时间，保存告警和复核证据。
- 记录健康检查、重启、前滚修复、清库和 fixture 重建步骤；测试服务器发布记录必须同时附镜像/配置回滚与 ACME 证据。

该环境除证书续期和部署健康检查所需的最低告警外，没有完整业务监控或灾难恢复备份，只能用于可清空的内测数据；不得描述为生产就绪。公开发布仍受云同步-01 §21.2 的备份恢复、监控、账号注销、生产密钥、隐私和安全审查门槛约束。

## 18. 跨计划输入、输出与协调

| 协作方 | Backend 必须接收 | Backend 必须交付 / 回报 |
| --- | --- | --- |
| 云同步-02 Contracts | operation/path、Schema、field registry、merge key、error/retry、PostgreSQL 模型、fixture、revision/hash | 每个 Controller/Application/Repository/Migration 映射，所有 fixture 消费结果；任何变更先回到 02 |
| 云同步-03 C++/SQLite | mutation canonical hash、连续 sequence、transport binding、route、bootstrap/conflict、完整 import manifest/ordinal/commit 协议 | `status=duplicate` + `original_status` + 原 terminal receipt/hash、权威transport/sequence bundle、typed change/conflict、cursor/account generation/floor、带device anchors/recovery bundle的materialized bootstrap page、import range proof/server confirmation；rejected携稳定safe context供本机failed overlay，Backend不拥有该overlay |
| 云同步-05 Kotlin/Android | bearer/session/device/transport/attempted installation identity、固定 HTTP DTO、Broker 本地 token generation/reauth header、批次/page limit、独立 device settings report | 精确 HTTP status/ApiResult/retry 分类、pending registration 白名单、稳定的401/refresh结果、`DEVICE_REVOKED`、device fence receipt、五类cursor错误、sequence/protocol永久终态的strict envelope与可hash evidence、服务端限制与base URL；使Kotlin可先调用Native耐久状态迁移而不猜测错误 |
| 云同步-06 Flutter | 既有 Auth/Profile 校准结果、设备/冲突/导入展示字段 | 脱敏 Device/Conflict/Profile 数据、`registration_pending/current_device_id`、server-confirmed import 状态、稳定分页和 expected version 语义；不暴露 token/cursor/payload |
| 跨层集成 | 同一 Contract hash、测试账号、真实 APK 请求 | 镜像 digest、Migration version、测试数据重建、日志关联 ID、容量与故障证据 |

接口协调规则：

1. Java 内部可使用 `camelCase`，HTTP wire 只使用 Contract `snake_case`。
2. Backend 对 mutation/change/conflict 的 canonical payload hash 算法必须与 C++/Kotlin fixture 完全一致。
3. `sync.conflict.resolve` 是单项 sequenced route；成功或合法业务/CAS拒绝都写terminal receipt并消费sequence，Backend 返回结果由 Kotlin 交给 C++ `sync.acknowledge_upload`，不得在 Flutter 直接构造第二条解决请求。
4. `DEVICE_REVOKED`、`AUTH_SESSION_EXPIRED`、`SYNC_CURSOR_EXPIRED`、429/5xx 和 Contract/data 错误必须保持不同终止/重试路径。
5. Backend 的 `received_at/server_sequence/entity_version` 是展示与并发依据；客户端 `created_at` 只诊断，不能影响顺序。
6. 任一层发现冻结 Schema 无法实现时，停止该切片并回报云同步-02；不得添加临时字段、自由文本错误或 Java-only fallback。
7. `sync_enabled=false` 不阻止独立 `device.update_settings` 报告自身诊断镜像；该调用不进入业务 Sync chain、不得携带 Outbox mutation，也不得重新开启业务同步。
8. Backend 只在完整 import manifest/ordinal/terminal 条件满足时发出 `server_confirmed`；Kotlin/C++/Flutter 均不得从上传数量、空 Outbox 或单个 commit HTTP 成功自行推断确认。

## 19. 完成定义

只有以下条件全部满足，本计划才可标记 `BACKEND IMPLEMENTED / AWAITING INTEGRATION`：

- [ ] B0–B7 全部退出条件满足，第 6 节冻结端点和第 7–13 节设计均有真实实现；无占位 Controller、Map payload、runtime Fake 或历史 Migration 改写。
- [ ] 第 15 节套件全部通过，Maven `test`/`verify` 成功且 PostgreSQL IT executed 非零、skipped 为零；账号隔离、事务原子性、固定锁序、生命周期栅栏和 retention 均有数据库证据。
- [ ] 第 16 节容量门禁有实测数据，第 17 节测试服务器制品可重建，并完成 TLS/secret/日志/磁盘、镜像与配置回滚、ACME 续期及失败告警演练。
- [ ] 第 18 节交接方收到同一 Contract hash、Migration version、字段/错误映射和真实验证结果；单层状态未被描述为云同步 active 或生产就绪。
- [ ] `git diff/status` 无越界或用户改动覆盖，文档明确记录所有未验证项。

完成本计划仍不能宣称“云同步内测完成”或“生产就绪”。双设备真实收敛、Android 强杀/弱网、提醒 reconcile、workspace 隔离和 Flutter 冲突 UX 必须由其他分计划与总计划共同验收。

## 20. 本计划之外

- 不实现 Flutter 页面、Kotlin HTTP/WorkManager/Broker、JNI、C++ Outbox/merge、SQLite v6 或 SQLCipher。
- 不实现 FCM、服务端 popup/ring/到期提醒、Notification 投递、微信、附件、共享日历、多人协作、AI 或备份。
- 不实现 V1.1 历史版本恢复、V2 整账号备份、账号自助注销或高可用集群。
- 不引入 WebFlux/R2DBC、Kafka、Redis、微服务、CQRS/事件溯源或 GraphQL 来替代当前 Spring MVC/JPA/PostgreSQL 基线。
- 不修改已应用 Flyway Migration，不升级 Java/Spring Boot/PostgreSQL/依赖版本，不把 CentOS 7 测试机包装成生产环境。
- 不在 Contract 冻结前编写同步业务代码，也不以空包、Schema 文件、单层 Fake 或被跳过的 Testcontainers 作为完成证据。
