# 云同步-05：Kotlin / Android 与会话调度开发计划

> 状态：ACTIVE PLAN / CONTRACT FROZEN / IMPLEMENTATION NOT STARTED
> 2026-09-07 Review 修订：提交 `5d8fb0a` 的 11 类问题经独立复核成立，修订依据和跨层交接规则见[Review 复核与兼容修订记录](./云同步-02-Review复核与兼容修订记录.md)。03–06 以机器锁中的最新内容摘要为共同输入；初次交付的旧摘要仅作历史记录。
> 建立时间：2026-09-04
> 上位计划：[云同步-01：Local-first 多设备同步开发计划](./云同步-01-Local-first多设备同步开发计划.md)
> 协议基线：[云同步-02：Contracts 与数据模型开发计划](./云同步-02-Contracts与数据模型开发计划.md)
> 负责范围：`flutter_client/android/**` 内的 Kotlin/Android 平台实现、JNI adapter、Android Manifest 与该层测试
> 依赖计划：云同步-03（C++/SQLite）、云同步-04（Cloud Backend）
> 下游计划：云同步-06（Flutter）与真实跨层集成
> 文内语义锚点：第 5–16 节定义 Android 编排与生命周期；第 17–20 节只登记实施、验证和交接证据，不得重述或扩展状态机。

> 协议输入锁：`contracts/sync/sync_v1_revision_lock.json` 中的 `05_kotlin_android` 与其他三端锁定同一 revision/hash/fixture manifest。只在 `contracts/run_sync_v1_validation.py` 默认入口通过后按该机器版本实施；本层生产 implementation/release status 仍为 planned。

> 2026-09-07 执行检查点：K0 默认 validator 因两份 Appearance Schema 与冻结输入漂移而阻塞。已交付测试先行的隔离组件与 29 项 JVM 先行测试（27 通过、2 个真实前置门禁失败），未接入生产同步链。测试范围、预期与剩余未写测试见 [Android 先行验收记录](../../../flutter_client/android/sync-v1-acceptance.md)，冲突及构建阻塞见 [problem-kotlin](../../issues/problem-kotlin.md)。K1–K6 尚未签收，不表示整份计划已完成。

## 1. 目标与完成口径

本计划负责把已经冻结的云同步 Contract 接入 Android：建立账号凭据唯一所有者、workspace 与多 runtime 生命周期、账号数据库密钥管理、严格 HTTP transport、唯一后台同步队列、JNI batch adapter，以及 workspace-aware 的提醒 reconcile、退出、撤销和缓存清理。

本层必须保持“协调者”定位：

- Kotlin 负责 Android 生命周期、Keystore、HTTP、WorkManager、网络状态、系统提醒和跨边界编排。
- C++ 负责业务事实、SQLite v6、Outbox、Cursor、冲突、导入和远端 apply 的原子性。
- Backend 负责账号、设备、同步顺序、幂等、change feed 和服务端冲突。
- Flutter 负责用户流程和状态展示，不读取 Refresh Token、Cursor 或 mutation payload。

本计划完成后只能标记 `LAYER COMPLETE / AWAITING INTEGRATION`。只有真实 Flutter、Kotlin、JNI、C++ SQLite、Backend、双设备和弱网验收全部通过后，相关 capability 才能切换为 `integrated + active`。

当前没有开始实现。本文件中的所有任务均为待办；现有认证、提醒和 Native v2 代码不能被解释为云同步已完成。

## 2. Source of Truth 与不可变边界

唯一裁决顺序引用云同步-01 §1.1：当前行为按active machine Contract/Schema → 当前领域不变量 → Accepted ADR → active计划 → 架构 → 实现；本次目标如改变前三者，先修订ADR/领域/Contract及迁移。云同步-02冻结前只是协调草案，planned/blocked机器文件不能压过本次目标；冻结后机器Contract才是Kotlin直接接口真相源。冲突未闭合时本层停止，不得兼容两套字段或状态。

以下规则由上位计划冻结，本分计划不得改变：

1. 游客与账号 workspace 物理隔离；游客数据永不上传，也不得生成可上传 Outbox。
2. 一台设备同一时刻只有一个活跃账号，但游客提醒与当前账号提醒可以同时存活；不能用单一全局 Core 隐式切库实现。
3. 账号业务写与 Outbox 的原子性、下载 apply 与 Cursor 的原子性均由 C++/SQLite 保证，Kotlin 不复制领域事务。
4. Kotlin `SessionCredentialBroker` 是 Refresh Token 读取、刷新、轮换和删除的唯一 owner；Flutter 与 Worker 共用同一 single-flight。
5. 关闭同步只停止网络，不清空 Outbox，也不暂停本机提醒；重新开启必须先拉取再上传。
6. Reminder 只同步用户意图或模板；权限、Alarm、铃声 URI、调度状态、Notification、投递记录与搜索历史不上传。
7. 拉取后由 C++ 先提交事实，再由 Kotlin 对精确 workspace 做提醒 reconcile；reconcile 失败不得回滚或伪装同步事务。
8. 退出账号的可保留缓存立即隐藏，且retained状态必须已有可信deadline；force-local无同boot可信锚时只允许立即销毁或取消/重试，不产生无限期隐藏分支。可信期限越过后的首次系统允许机会先销毁密钥，WorkManager不提供第30天整点SLA。设备撤销、立即清理或账号删除立即销毁。
9. Native 使用 `NativeResult<T>`，HTTP 使用 `ApiResult<T>`；Kotlin 不能把两个 envelope 混成一个 DTO。
10. V1 无 FCM、无常驻服务、无服务端到期提醒、无附件/微信/共享协作。

任何字段、方法、枚举、错误码或状态机需要调整时，先修改云同步-02及机器 Contract，再更新本计划；不允许在 Kotlin 中临时增加私有 wire 字段。

## 3. 当前基线证据（事实，不是目标状态）

| 范围 | 当前事实与证据 | 计划影响 |
| --- | --- | --- |
| Native runtime | `AndroidNativeBridgeFactory.kt` 仅缓存一个进程级 `v2Bridge`；没有 open/close/switch 或 workspace handle | 必须替换为显式 workspace/runtime registry，且不能继续让 Activity、Worker、Receiver各自获取“当前单例” |
| 存储目录 | `CalendarCoreV2RuntimeDirectories.kt` 始终解析到 `files/local_storage/calendar_core_storage_json`，请求只有 `storage_directory`、`tzdb_directory` | 现状只有游客生产目录；账号摘要目录、账号绑定、加密 key 参数和 runtime identity 均不存在 |
| Kotlin runtime 初始化 | `JniNativeCalendarCoreBridge.kt` 用 `runtimeInitAttempted` 缓存一次初始化结果，成功后不再打开其他 workspace；Kotlin要求 Storage v5 | 必须拆开“加载 native library”与“打开 workspace”，并让 close/reopen 可测试、可幂等 |
| C++ runtime | `cpp_core/src/boundary/api/native_runtime.cpp` 只有全局 `RuntimeState g_state`；重初始化会清空旧 state，虽有 `RuntimeStorageLease` 防止旧 writer 继续写 | C++-03 必须先提供可并存或可安全路由的 runtime identity；Kotlin不能在并发 UI/提醒调用中反复切换全局库 |
| Storage 版本 | `calendar_core_storage.yaml`、C++ 与 Kotlin实际为 SQLite v5；但 `contracts/runtime/initialize_runtime_response.schema.json` 和 runtime fixture 仍固定 Storage v4 | Contract 冻结前必须先消除此漂移；Kotlin不得接受“Schema 说 v4、实现说 v5/6”的响应 |
| Sync 占位 | `contracts/method_channels.yaml` 声明旧 `sync.apply`，但 `NativeMethodChannelHandler.kt` 无对应常量/Handler，JNI/C++也无运行时实现 | 不补做旧入口；按云同步-02保留 `deprecated + blocked` 墓碑并在生产返回 `notImplemented` |
| JNI 构建 | Android `CMakeLists.txt` 当前只编译 `event_jni.cpp`、`habit_jni.cpp`、`calendar_view_jni.cpp`、`search_jni.cpp`；`native_calls.yaml` 没有 workspace/sync能力 | 新增独立 workspace/sync JNI adapter并登记构建；所有新符号与三 ABI都要真实加载验证 |
| MethodChannel | `NativeMethodChannelHandler` 使用单线程 executor、主线程回传和 exactly-once completion，按领域拆分 Handler | 保留这一薄边界模式；新增 Session/Workspace/Sync/Device/Preferences 窄 Handler，不把网络循环塞入总 Handler |
| Refresh Token | `RefreshTokenSecureStore` 只存一个 RT 记录；`AuthMethodHandler` 暴露 `store/read/delete/exists`，其中 `read` 会把 RT 返回 Flutter | 与 Broker 单一 owner 目标冲突；新旧入口必须同一发行版本完成迁移，生产 Flutter不得再读 RT |
| Keystore | `KeystoreRefreshTokenCipher.kt` 使用单一静态 alias、AES-256-GCM 与随机 12-byte IV；解密会调用 `getOrCreateKey()`；Store 为单文件 temp+rename+file fsync | 可复用测试思路，不能复用同一 alias 保护账号 DB；缺 key 不能自动新建后再归类为普通损坏；还缺 alias 删除、目录持久性与账号绑定 |
| 前台刷新 | Flutter `TokenRefreshCoordinator` 当前拥有刷新 single-flight，Dart Dio 执行 `/auth/token/refresh` | Kotlin Broker 上线时必须删除生产 Dart 刷新 owner，否则旋转 RT 会竞争并撤销 token family |
| Android HTTP | Kotlin 主代码没有 Sync HTTP client，也没有已选定的 OkHttp/Ktor/其他 HTTP 依赖 | HTTP 库与序列化方案必须等 ADR/依赖评审，不得借同步任务擅自升级工具链 |
| 设备身份 | 当前 Android没有云同步 `installation_id` / Backend `device_id` 的持久化与绑定组件 | 新增安装级随机身份和账号 workspace级 device binding；禁止使用 Android ID、IMEI、广告ID或临时device id |
| Manifest | 主 `AndroidManifest.xml` 没有 `INTERNET`；Debug/Profile overlay 才声明该权限；没有云同步 Release 网络策略 | 主 Manifest补权限；Debug 明文例外仅在 Debug source set；Release 必须构建时 fail closed |
| Android系统备份/迁移 | 主Manifest未声明`allowBackup/dataExtractionRules/fullBackupContent`，仓库也无规则XML；默认Auto Backup/设备迁移可能恢复files/shared preferences，但Keystore材料不会形成可依赖的同一恢复边界 | 增加Backup/Device Transfer ADR和版本化规则；敏感、账号生命周期数据和guest库从Auto Backup/任何cloud backup强制排除。direct device-to-device transfer默认也排除，只有ADR证明非云通道且开放前可原子re-home时才单独允许guest迁移 |
| WorkManager | `app/build.gradle.kts`当前固定`work-runtime:2.11.2`；生产代码只有提醒`ReminderQueueWorker`使用APPEND_OR_REPLACE continuation/KEEP watchdog，无SyncWorker、同步合并器或网络链 | 现有提醒链不是同步实现证据；同步可用当前版本的APPEND_OR_REPLACE与stable WorkRequest id，但必须新建按workspace+device隔离的耐久有界Pump，不能复制“每次触发都append” |
| 保留时钟 | 当前没有RetentionDeadlineRecord、BootEpochProvider、BOOT_COUNT读取或system-time恢复实现 | Contract先冻结boot token生成/存储/fail-closed矩阵；Kotlin实现前不得用wall clock或仅持久化elapsed值冒充跨重启可信时间 |
| 提醒 Alarm | `ReminderDispatchAlarmScheduler` 使用一个固定 URI 和 request code；Receiver/Worker通过全局 Bridge factory 获取 runtime | 当前只能表示一个全局 dispatcher；游客和账号提醒会互相覆盖或读错库，必须把 workspace identity 纳入调度、接收和取消 |
| 通知点击 | 现有 `NotificationTapPayloadContract` 没有 workspace identity，路由只携带 reminder/target 等业务 ID | 登录账号期间点击游客通知可能查到错误 workspace；Contract、PendingIntent、Event 与 Flutter route 都必须协同升级 |
| Habit 通知操作 | `HabitNotificationActionWorker` 以 `action_id` 做 Work 唯一键，但工作 payload 与 native 调用没有 workspace identity | 必须把 workspace identity 绑定到 action、Work 名与 runtime 获取；成功业务写后还要触发同一 SyncCoordinator |
| 本机设置 | `habit_progress_color` 当前在全局 SharedPreferences；搜索历史是 `noBackupFilesDir` 下的进程单例文件 | 账号偏好写改走C++ `preferences.update`与Outbox；Search History固定迁成workspace-scoped，account以Keystore-AEAD保留、guest独立，旧全局文件只迁guest一次 |
| 账号资料缓存 | 当前资料缓存由 Flutter单一文件承担，Kotlin/C++没有 workspace-aware `account_profile` 安全投影接收路径 | 按更新后的 Contracts增加 download-only profile cache；Kotlin只验收并路由权威 server snapshot，不把 profile构造成上传 mutation |
| 既有验证 | Android已有 MethodChannel、Keystore、WorkManager、Reminder 与 JNI 的 JVM/instrumentation 测试基座 | 新能力应扩展现有测试结构；不能用 Fake 通过生产组合验收 |

## 4. 实现准入门禁

以下条件未满足时，本计划只允许盘点、接口测试骨架与 spike，不得提交生产同步路径：

- [ ] 云同步-02达到 `CONTRACT FROZEN`，§8.2/§8.3 方法、Schema、错误、状态与 fixture hash 已固定。
- [ ] Workspace Lifecycle、Account SQLite Encryption、SessionCredentialBroker、Sync Protocol、HTTP Calibration 与 Android Backup/Device Transfer ADR 已接受。
- [ ] SQLCipher/等价方案通过许可证、Android 三 ABI、sqlite3 API、WAL/defensive、强杀、密钥丢失和 20,000 条性能 spike。
- [ ] C++-03提供 SQLite v6、`runtime.open_workspace` / `runtime.close_workspace`、全部 sync/workspace/preferences/profile Native calls 与 runtime identity。
- [ ] Backend-04提供经 Contract 测试的 Auth、Device、Sync、Bootstrap、Conflict 端点和可复现的测试环境。
- [ ] Flutter-06接受 Broker 迁移：不再构造第二刷新器，不再调用 `auth.refresh_token.read`。

云同步-02已经在计划层明确下列结论；Kotlin开工前仍须确认它们已经落入 Schema、fixture、mapping YAML与 validator，而不是只停留在文字中：

1. `workspace.list` 只返回游客与当前已认证且可解锁账号；其他账号保留缓存完全不可见，只供 Kotlin内部到期清理索引使用。
2. `auth.session.adopt` 接收完整 `AuthenticationResponse`，Broker必须用 Access Token调用权威 `user.get_current` 交叉校验后，才原子绑定 session/account并允许开库；不得接收裸 token pair或另一个未验证 account id。
3. `account_profile` 是 download-only target，SQLite v6由 `account_profile_cache` 接收；客户端上传 validator拒绝该 target，公开/Native入口固定为 `profile.get_cached` 与 `profile.accept_server_snapshot`。
4. `NotificationTapPayload.workspace_id` 兼容旧 reader为可选，但所有 v6 writer必须提供；旧 payload只有在唯一无歧义 legacy workspace中才可解析，否则返回稳定 stale/ambiguous错误。

## 5. 目标 Android 组件与调用关系

建议的内部组件名不是 wire Contract；实现可按现有目录命名习惯微调，但职责不可合并回巨型 Handler：

```text
Flutter MethodChannel / EventChannel
        ↓
SessionMethodHandler   WorkspaceMethodHandler   SyncMethodHandler
DeviceMethodHandler    PreferencesMethodHandler   ProfileMethodHandler
        ↓
SessionCredentialBroker ── SyncHttpClient ── Backend /api/v1
        ↓                         ↑
WorkspaceCoordinator ── SyncCoordinator / SyncWakePump ── Sync Worker unique chain
        ↓                         ↓
WorkspaceRuntimeRegistry ── NativeWorkspaceBridge / NativeSyncBridge
        ↓                         ↓
                JNI adapter ── C++ runtime handle / SQLite v6
        ↓
WorkspaceReminderCoordinator ── Alarm / Notification / Ring / tap

BootEpochProvider ── retention lifecycle only
```

关键所有权：

- `Application` 进程级 owner：Broker、WorkspaceRegistry、WorkspaceRuntimeRegistry、SyncCoordinator、SyncWakePump、BootEpochProvider、HTTP client、状态 EventHub。
- `InstallationIdentityStore` 进程级保存随机 UUID `installation_id`；每个账号 workspace保存 Backend分配的 `device_id` 与版本/撤销状态。
- `Activity` 只注册 Flutter channel，并借用进程级 owner；Flutter engine 销毁不得关闭仍被 Worker/Receiver使用的 runtime。
- Worker、Receiver、Activity只能用同一个 WorkspaceRuntimeRegistry；禁止直接 `AndroidNativeBridgeFactory.create()` 后隐式打开游客库。
- 每个已打开runtime有不可复用的`runtime_instance_id`；`WorkspaceRegistry`持久化全局单调`active_route_revision`，每次可路由实例变化递增。C++各业务revision不得冒充路由CAS；迟到回调必须同时校验workspace/runtime/route revision。
- C++ handle 负责事实隔离，Kotlin registry 负责 Android调用路由；两边都校验 workspace/account binding，任一不匹配立即 fail closed。

## 6. Flutter ↔ Kotlin 精确 MethodChannel 映射

以下方法名严格继承云同步-02 §8.2；不得使用近义别名。所有方法继续使用 `excellent_calendar/native` 与 `NativeResult<T>`，请求/响应必须由冻结 Schema 校验 exact keys。

### 6.1 Session

| Method | Kotlin owner | 实现任务与下游 |
| --- | --- | --- |
| `auth.session.adopt` | `SessionCredentialBroker` + DeviceClient | 输入完整 `AuthenticationResponse` → 用 AT调用权威 `user.get_current` 交叉校验/entitlement → `device.register`；成功后持久化 binding/sequence seed并开库，超限则进入受限 pending-registration 清理流，非白名单则清pending并保持guest；响应不含RT |
| `auth.session.get_access_token` | Broker | `minimum_validity_seconds` + nullable `rejected_access_token_generation`；返回 token/expiry/session/当前 generation，按 generation加入或跳过 single-flight |
| `auth.session.get_status` | Broker | 返回七态与nullable `session_generation`（empty为null）；供pending logout CAS，绝不返回token、device、目录或alias |
| `auth.session.logout` | Broker + HTTP + lifecycle | active首次attempt-once建立耐久logout operation并阻写session-bound账号lane；风险/失败返回operation id、risk revision、精确counts/import快照与`allowed_cache_policies`。retry/cancel/skip必须引用同operation，skip仍server-then-local；只有同operation已记录server unreachable后才接受二次确认force-local。无同boot可信锚的force-local只允许destroy-now，旧请求retain返回稳定错误且零终止；pending只用session generation且route/final-sync/review字段为null；strict返回server/session/cache/import终态 |
| `auth.session.clear_local` | Broker + lifecycle | 可信终止 reason或已确认 `user_requested_destroy`映射到冻结的保留/crypto-destroy动作与 lifecycle revision |
| `auth.session.reauthenticate` | Broker + HTTP | 严格接收 `password + purpose + target_device_id`；密码仅在调用期间存在，服务端 `reauth_token` 留在 Kotlin内存，向 Flutter只返回短时 grant id |

迁移要求：

- 旧 `auth.refresh_token.read` 在同一发行包中停止被生产 Flutter调用，并不得再向上返回 RT。
- 旧 `auth.refresh_token.store/delete/exists` 是否保留一个兼容期只服从 Session ADR；即使保留，也必须委托 Broker，不能形成第二持久化 owner。
- 旧 `sync.apply` 始终 `notImplemented`；不能因为其已写入 YAML 就注册运行时 Handler。

### 6.2 Workspace、Sync、Device 与 Preferences

| Method | Kotlin owner | 精确下游映射 |
| --- | --- | --- |
| `workspace.get_state` | WorkspaceCoordinator | 外部为无CAS恢复读：请求可带nullable known route revision仅诊断，Registry始终返回当前active/empty route tuple；有current runtime时再按Registry绑定identity调用JNI投影统计，并过滤目录、alias、key等Android私有信息 |
| `workspace.list` | WorkspaceRegistry | 只返回 Contract最终允许可见的 workspace；其他账号保留缓存不出现在 Flutter结果 |
| `workspace.activate` | WorkspaceCoordinator | 串行校验`expected_active_route_revision`、close/open/switch；成功后推进并发布`active_route_revision` |
| `workspace.import_preview` | WorkspaceCoordinator | JNI同名调用；strict消费ready/previous-epoch-cleanup-pending分支、source epoch/count/bytes，不在Kotlin读取业务记录；epoch exhausted原样返回 |
| `workspace.import_commit` | WorkspaceCoordinator | 普通分支调用JNI冻结manifest/ordinal/terminal；full-successor分支先完成HTTP range-close→Native proof接纳→必要ack-only，再以proof resulting revision调用JNI，账号副本publish-applied前不物化提醒 |
| `workspace.import_status` | WorkspaceCoordinator | 有batch时精确合并并可返回九态终态；无batch时只按source workspace + current/receipt epoch发现当前handle或empty。保留reconciliation/resume/abandon、previous-epoch gate、range/proof与current head/revision，绝不把completed旧epoch误当current |
| `workspace.import_abandon` | WorkspaceLifecycleCoordinator | 调独立HTTP abandon CAS并把typed disposition交JNI同名入口；零Outbox/sequence，privacy destroy离线可返回unconfirmed继续 |
| `workspace.clear_account_cache` | WorkspaceLifecycleCoordinator | 严格接收`workspace_id + expected_session_generation + observed_active_workspace_id + expected_active_route_revision + expected_lifecycle_revision + confirmation_id`；workspace必须等于Broker session-bound账号，前台可为账号或local。随后阻写/drain/ack/import、在线fence并接纳receipt后才crypto-destroy/fresh-open/bootstrap；session保持active，游客目标硬拒绝 |
| `sync.get_status` | SyncStatusAggregator | 合并 JNI `sync.get_status`、WorkManager运行态与 Broker状态；使用单调 `status_revision` |
| `sync.claim_conflict_notice` | SyncStatusAggregator | 展示前把exact head notice id/sequence传JNI原子claim；返回claimed/no-longer-actionable后的完整新快照，不改未解决数 |
| `sync.export_diagnostics` | SyncDiagnosticsCoordinator | 调JNI安全快照、加入脱敏Android统计、短期FileProvider分享；不向Flutter返回路径/内容 |
| `sync.set_enabled` | SyncCoordinator + DeviceSettingsCoordinator | JNI以`expected_sync_policy_revision`做CAS；关闭时取消网络链而不丢Outbox/不取消提醒，开启时排队“先pull后push”，并把新值作为设备诊断镜像待上报；聚合status revision不参与CAS |
| `sync.run_now` | SyncCoordinator | 只入队同一唯一链并快速返回`run_id + disposition(queued/already_running) + status_revision`；不在 MethodChannel中直接执行 HTTP |
| `sync.conflict.list` | NativeSyncBridge | JNI同名本地分页读取，离线可用 |
| `sync.conflict.detail` | NativeSyncBridge | JNI同名读取 typed 快照；Kotlin不解析合并业务规则 |
| `sync.conflict.resolve` | NativeSyncBridge + SyncCoordinator | JNI同名写 resolution mutation + Outbox，随后机会调度唯一链 |
| `sync.failed_change.list` | NativeSyncBridge | JNI同名稳定分页读取未同步失败意图摘要；离线可用 |
| `sync.failed_change.detail` | NativeSyncBridge | JNI同名typed详情；Kotlin不记录候选/草稿，不把它改造成旧mutation重试 |
| `sync.failed_change.discard` | NativeSyncBridge | expected failed revision + route CAS；JNI原子删除overlay并返回新状态，零Outbox；正常编辑走既有业务writer产生新mutation |
| `device.list` | DeviceClient + DeviceSettingsCoordinator | 组合remote fresh/stale/unavailable脱敏快照与当前设备本机权威settings；离线快照只来自SQLCipher或account-scoped Keystore AEAD内容缓存，pending-registration只走在线受限列表 |
| `device.rename` | DeviceClient | HTTP `device.rename`，透传 expected device version/CAS结果 |
| `device.update_settings` | DeviceSettingsCoordinator + DeviceClient + Broker | Method strict oneOf一次只改receive-reminders或sync-enabled；先写operation journal，幂等跨C++/Registry完成并推进combined local revision，再尝试可合并HTTP镜像；离线返回local-saved + remote-pending |
| `device.revoke` | DeviceClient + Broker | 普通态消费grant并返回revocation；registration-pending撤销后内部立即以持久化installation/name重试register，返回registered/still-limited，不泄露token |
| `preferences.get` | NativePreferencesBridge | JNI同名读取 workspace白名单与 revision |
| `preferences.update` | NativePreferencesBridge + SyncCoordinator | JNI同名 typed patch；账号事实+Outbox由 C++同事务提交，游客零 Outbox |
| `search.get_workspace_history` | WorkspaceSearchHistoryStore | 校验workspace/route后读取唯一分区；account解密AEAD AtomicFile，guest读guest分区；返回同identity/history revision |
| `search.replace_workspace_history` | WorkspaceSearchHistoryStore | 校验workspace/route/history CAS后原子替换有序规范化关键词；不得回退全局文件或跨账号读写 |
| `profile.get_cached` | NativeProfileBridge | JNI同名读取当前账号 workspace安全资料投影、profile revision与 freshness；游客返回 not-applicable |
| `profile.accept_server_snapshot` | NativeProfileBridge | 严格校验资料 API成功响应后调用 JNI同名入口；按 revision幂等写缓存，绝不产生 Outbox |

`workspace.get_state`与`workspace.state_changed`共同使用`route_state=ready/locked/empty` strict union：ready的workspace/kind/runtime三项必填，locked的workspace/kind与reason必填而runtime为空，empty的identity/reason全部为空；revision始终必填。Registry切换线性化前继续返回旧稳定union，mutating请求收到`WORKSPACE_SWITCH_CONFLICT`，不对Flutter发布半切换第四态。Event只带union identity/revision并提示重读，不带业务统计。

`preferences.get/update` 的 V1固定白名单只有四项：`timezone`、`habit_progress_color`、`default_reminder_methods`（仅`ring/popup`）和`auto_enable_reminders_on_other_devices`。locale新写拒绝且不进入同步；Kotlin不得接受任意settings map、`wechat`或额外key。`default_reminder_methods`必须保持0..2有序唯一数组，不排序/补值；目标合法性由同一机器矩阵和C++最终writer保证，偏好变化不触发既有Reminder reconcile。`receive_reminders`与`sync_enabled`属于device设置；Backend保存的`sync_enabled`只是跨请求可见镜像，Android是否排队网络工作的权威状态始终来自当前workspace内C++ `sync.set_enabled/get_status`。

Kotlin唯一提供OS `device_timezone`，不得用同步的`user_preferences.timezone`覆盖；后者是workspace Event展示/新建默认，由C++ workspace偏好读取。OS时区广播触发Habit/Anniversary当地日期刷新及`follow_device` open Reminder reconcile；workspace timezone更新只通知Flutter刷新Event Calendar/Search投影，不执行Reminder reconcile。混合查询的`workspace_timezone/device_timezone`字段按Contracts-02原样注入，禁止复用一个值。

`sync.set_enabled` 与 `device.update_settings` 不能形成两个本机 owner：二者必须委托同一个 `DeviceSettingsCoordinator`。Method一次只改一个字段；协调器先在账号加密lifecycle journal原子写operation id、desired值、expected combined local revision与expected C++ policy revision，再以同operation id幂等调用C++ `sync.set_enabled`（C++ receipt可恢复“已提交但响应丢失”）或写Registry `receive_reminders`，全部完成后才推进combined `local_settings_revision`、执行Work/reconcile并写remote-pending。每个中间强杀点重启续做，绝不返回半保存。一个workspace有未闭合journal时不接纳第二个设置operation；新operation能被发起即证明旧journal已完成，C++只在接纳该新operation的同一事务替换latest policy receipt，故长期无操作仍保留最后幂等证据且空间O(1)。远端 reporter可合并多个已完成本机操作为typed HTTP patch，成功后清pending，失败不回滚本机开关；即使`sync_enabled=false`也可运行，但不得prepare/上传业务mutation，并在logout/revoke时精确取消。

`auto_enable_reminders_on_other_devices` 默认 false且只影响未来注册：首台账号设备 `receive_reminders=true`，后续设备按注册时偏好初始化；之后偏好变化不改既有设备，本机实际执行只看当前设备开关与系统能力。Flutter文案必须表达“新设备默认”，Kotlin不得按 reminder intent 的来源设备推断例外。

### 6.3 同步状态与控制方法的精确形状

`sync.get_status` 与 `sync.status_changed` 必须返回/携带同一个完整状态快照，字段闭包至少为：

- `workspace_id`、`workspace_kind`、非空`runtime_instance_id`、Kotlin注入的`active_route_revision`、`device_id`（游客为 null）、`sync_enabled`、C++权威`sync_policy_revision`。
- `phase`，V1只允许 `local_only / idle / queued / syncing / offline_pending / paused / auth_required / rebuilding / blocked / failed`。
- `pending_upload_count`、`failed_local_change_count`、nullable `next_failed_local_change_id`、`unresolved_conflict_count`、`unclaimed_conflict_notice_count`；nullable `next_conflict_notice_id`、必填非负`next_conflict_notice_count`、nullable `next_conflict_notice_sequence`。空队列严格为`0/null/0/null`，非空时id/sequence必填且head count>0；failed不计入pending upload。
- `backlog_state=normal/warning/critical`、闭合 `backlog_reason_codes`、`diagnostics_export_available`。
- `last_attempt_at`、`last_success_at`、`next_retry_at`、`failure_code`、`retryable`。
- `status_revision`、`active_run_id`。

时间、failure、device与 run id的可空规则只服从 Schema；计数、布尔值或未知 phase不得由 Kotlin补默认值。JNI `NativeSyncStatusSnapshot`必须完整提供C++ owner字段：workspace/runtime/device、policy、pending count/oldest/bytes、failed count/head、conflict、notice四元组、backlog/reasons/diagnostics、native blocked reason与native revision，不含cursor。Kotlin `SyncStatusAggregator`是`phase/last_attempt_at/last_success_at/next_retry_at/failure_code/retryable/active_run_id/status_revision`唯一owner并把这些run元数据耐久保存；只有normal/bootstrap全部Native提交、必要ack-only和journal收尾成功才推进last-success。聚合时以当前`workspace_id + runtime_instance_id + active_route_revision`校验来源并单调发布；Work/Auth相位变化只推进status revision，不改C++ `sync_policy_revision`。local-only使用Contracts-02固定常量/null矩阵，locked/empty不伪造Native snapshot。

Backlog阈值只能来自冻结的 `sync_protocol_invariants.yaml`校准常量，Kotlin不另设阈值。warning/critical只改变告警投影，绝不自动删Outbox；诊断导出必须由用户显式触发。C++ conflict notice队列跨后台run/重启保存；Kotlin不得用内存`active_run_id`猜一次性提示，Flutter实际呈现前调用exact head claim，只有claimed才显示。

控制方法精确约束：

- `sync.run_now` 请求只含当前 `workspace_id + expected_active_route_revision`；结果为 `run_id + disposition(queued | already_running) + status_revision`。游客、paused、未绑定 device或 blocked 必须返回冻结错误，不能伪造 queued。
- `sync.set_enabled` 请求为`workspace_id + expected_active_route_revision + enabled + expected_sync_policy_revision`；成功返回上述完整状态快照。CAS失败不调整Work，成功后才由统一`DeviceSettingsCoordinator`取消或排队精确workspace链；不得用聚合status revision替代policy CAS。
- `sync.get_status` 的请求 workspace identity、结果 identity和 Event identity不一致时 fail closed；不得把其他 workspace最后一次状态当当前值。
- `sync.claim_conflict_notice`只接受当前status中的exact head notice id/sequence；旧claim返回no-longer-actionable及最新完整快照，不能清掉后来排队的新notice。
- `sync.failed_change.list/detail/discard`只处理当前route的device-local失败overlay；discard必须使用详情revision并返回完整新状态。用户选择“修改并保存”时Flutter调用原业务编辑方法产生新sequence，Kotlin不得把失败记录或旧payload直接送HTTP。
- `sync.export_diagnostics` 只在 `diagnostics_export_available=true` 且用户显式操作时执行。Kotlin对C++结果做第二次字段allowlist，加入app/contract版本、Work/transport枚举和age bucket后写短期cache，通过FileProvider打开系统分享；返回export id/hash/time/disposition，不向Flutter暴露文件路径或内容，取消/TTL后清理。

## 7. Kotlin ↔ JNI/C++ 精确 Native call 映射

以下 operation key 严格继承云同步-02 §8.3。建议新增窄接口 `NativeWorkspaceBridge`、`NativeSyncBridge`、`NativePreferencesBridge`、`NativeProfileBridge`，并使用独立 `workspace_jni.cpp` / `sync_jni.cpp` adapter；JVM/NDK函数名可遵循现有命名方式，但映射测试必须逐项证明对应唯一 operation key。

| Native call | Kotlin调用时机 | Kotlin必须校验/保留的语义 |
| --- | --- | --- |
| `runtime.open_workspace` | 创建或解锁 runtime | JSON传typed metadata、账号另用binary key；fresh DB严格传register/fence的`sync_transport_generation + highest/nullable next/client-confirmed/client-sequence-exhausted` recovery bundle、需要时的fence receipt与Contract genesis `sync_enabled=true/policy_revision=0`并保持bootstrap/import-recovery写锁；active clear重建另传`clear_operation_id + workspace_id + device_id + session_generation + 旧sync_enabled/sync_policy_revision seed`并要求全字段matching consumed receipt，existing/retain DB不重置 |
| `runtime.close_workspace` | 切换、退出、清理、撤销 | 按 workspace/runtime identity幂等 close；等待受控调用结束，不在主线程阻塞 |
| `workspace.get_state` | 页面查询、Event丢失/重启恢复 | 外部不要求expected revision；Kotlin先读当前Registry tuple，有runtime才用该权威identity查询Native统计，始终回当前route而非因调用方未知revision失败 |
| `workspace.import_preview` | 用户请求预览 | source/target 均先在 registry验证；不把数据行提升到 Kotlin |
| `workspace.import_commit` | 用户确认导入 | 传frozen preview token、source epoch、batch/predecessor、expected import revision与nullable takeover reason；takeover必须引用已接纳range-close proof/resulting revision；C++冻结完整连续range，重复调用得到同一状态 |
| `workspace.import_status` | UI重连、进程恢复/ack后 | 原样映射source epoch、状态、manifest/终态计数、server confirmation、previous-epoch gate、reconciliation/resume/abandon dispositions、range/proof和 affected reminder ids |
| `workspace.import_abandon` | 独立HTTP CAS返回后或privacy destroy无响应 | 把exact disposition/expected revision或local-unconfirmed交C++；不得构造Outbox/sequence |
| `workspace.import_cleanup_confirm` | cleanup-confirm HTTP返回后及崩溃恢复 | 传source epoch与exact disposition/resulting lineage revision/confirmed-through；仅与guest同epoch receipt head/hash匹配才completed并解除previous-epoch gate，重复幂等且不得构造Outbox/sequence |
| `workspace.import_accept_range_close` | takeover/confirmed-abandon/capacity/TTL或device fence返回proof后 | 仅内部传strict proof与current workspace/runtime/session/transport binding；seen-range同origin时Native原子终结matching Outbox range、恢复ack/allocator/dirty，never-visible只随旧runtime已冻结的fresh lifecycle采用同一fence sequence bundle，异origin只推进同epoch lineage；成功前不得创建successor或销毁依赖该proof的保留账号库 |
| `workspace.import_finalize_source_lease` | abandon/drain、crypto-destroy、cleanup completed或account-deleted生命周期收尾 | 仅内部传strict proof oneOf与guest/source/source epoch/opaque owner/revision；account-deleted分支要求Native同事务终结matching cleanup receipt/previous-epoch gate且不回退current epoch。Native幂等成功后才闭合lifecycle，unconfirmed及普通session/device终态不得调用，Flutter无此Method |
| `sync.accept_transport_fence` | active clear不可逆删除前，或fresh recovery open seed的等价消费 | 传Backend exact fence receipt与old workspace/device/runtime/session/transport binding；Native幂等推进generation、失效旧run响应并落resolved import fences。错binding/跳号零写；成功前不得毁保留库 |
| `sync.prepare_upload_batch` | normal/logout-final、dirty ack flush或reenable pull阶段 | 消费完整PreparedExchangeRequest union：normal/logout/pull-only均带C++ current opaque cursor/download limit/ack/transport，pull-only uploads空；ack-only固定uploads空/download 0/cursor null/ack非空。Kotlin只加Bearer，不重算/私存任何字段 |
| `sync.acknowledge_upload` | HTTP strict响应后 | normal即使results空也传prepared identity与exact item/effect refs，duplicate保留全部原终态；只落terminal/gate/failed overlay。ack-only则传reported与accepted水位，Native只推进server-accepted/dirty并明确跳过apply；Kotlin不得把空ack-only当normal |
| `sync.apply_download_batch` | 仅wire normal exchange完成ack后 | 原样传prepared identity、transport/account generation、snapshot upper bound、has-more、不可拆groups/import chunks、raw next cursor、两个cleanup水位与accepted ack；只用Native返回next request state，terminal pull页由Native解除gate |
| `sync.record_transport_terminal` | 收到闭合请求级永久错误并strict校验后 | 传workspace/device/runtime/session generation、error code与脱敏envelope evidence hash；Native幂等落blocked gate成功后才结束run，禁止只改内存Aggregator |
| `sync.begin_bootstrap` | Backend null-cursor首页严格校验后 | 原样传bootstrap/transport/account generation、upper bound、device highest/client-confirmed/nullable-next/exhausted、两个cleanup水位与trigger reason建立/恢复staging；Kotlin/C++不生成id，fence后旧页不得进入Native |
| `sync.apply_bootstrap_page` | 每个合法 bootstrap page | 原样传 page token/order/refs；重复页依赖 C++幂等 |
| `sync.finalize_bootstrap` | 完整页集合确认后 | 原子发布/rebase由 C++完成；Kotlin只继续拉取与提醒 reconcile |
| `sync.get_status` | UI/Worker恢复/错误处理 | 完整消费C++ owner的policy/pending/failed/conflict/notice/backlog/native blocked snapshot；cursor原文不得进入Event、日志或ordinary cache |
| `sync.set_enabled` | 本机设备开关变化 | operation id + expected sync-policy revision幂等CAS；false→true同时建立Native pull gate，Kotlin只排reenable-pull链，终态pull/bootstrap解除后才允许normal push；随后发布新聚合status revision |
| `sync.claim_conflict_notice` | Flutter即将呈现提示 | exact head id/sequence；只接受当前workspace/runtime，返回claimed/no-longer-actionable与完整状态 |
| `sync.build_diagnostic_snapshot` | 用户显式导出诊断 | 只接收Contract redaction profile；Kotlin二次allowlist校验后才制品化 |
| `sync.run_local_maintenance` | workspace open后与低频无网约束任务 | 每次 max 500，按C++安全水位处理；循环受预算限制，has_more续跑，不隐藏到status查询 |
| `sync.conflict.list` | Flutter同名方法 | 本地稳定分页；Kotlin仅 strict codec |
| `sync.conflict.detail` | Flutter同名方法 | 不把候选值写日志或 WorkData |
| `sync.conflict.resolve` | Flutter同名方法 | expected conflict version；成功后排队 Outbox route |
| `sync.failed_change.list/detail/discard` | Flutter同名方法 | strict本地DTO；discard按revision原子执行，修改并保存只能调用领域writer产生新mutation |
| `preferences.get` | Flutter同名方法 | workspace-aware strict response |
| `preferences.update` | Flutter同名方法 | typed patch + expected revision；成功后机会同步 |
| `profile.get_cached` | Flutter同名方法、冷启动资料恢复 | 只读当前账号 workspace安全投影；游客 not-applicable，不能回退全局文件 |
| `profile.accept_server_snapshot` | adopt后开库、资料/头像/确认邮箱API成功 | 传 typed safe projection + profile revision；旧 revision不得覆盖新值且不得产生 Outbox；change feed仍由 `sync.apply_download_batch`内部应用，不在Kotlin重复拆包 |

边界规则：

- JNI key 参数不得 Base64塞入 JSON、`String`、日志、Exception message 或 `NativeResult`。Kotlin只用可清零 `ByteArray`，调用完成后在 `finally` 覆盖；Native侧的复制和清零由加密 ADR规定。
- 每个JNI调用都绑定Kotlin Registry解析出的`workspace_id + runtime_instance_id`。除外部恢复读`workspace.get_state`外，Method先校验`expected_active_route_revision`；get-state不做CAS，而是先读取当前原子route tuple、再用其中identity查询Native。任何路径都不从“当前Activity”或默认目录猜workspace。
- Native返回未知 enum、额外字段、错误 envelope、错 contract version 或错 runtime identity 时，Kotlin判定 Contract错误并停止自动重试。
- 不把一整个 exchange response拆成 Kotlin领域对象再重建 JSON；使用受限 strict DTO验证 envelope/route后，把冻结 payload语义保持给 C++，并以 golden round-trip证明未漂移。
- close 与调用并发时，由 registry的 lease/ref-count或等价机制保证：新调用被拒绝，已进入调用受控完成，旧 handle永不路由到新 workspace。

## 8. EventChannel 与状态恢复

只新增云同步-02 §8.4冻结的两个事件：

| EventChannel | Identity / ordering | Android实现要求 |
| --- | --- | --- |
| `sync.status_changed` | `workspace_id + runtime_instance_id + active_route_revision + status_revision` | 可重复、可丢失；不含 payload/token/cursor/path/key；Broker、Worker、C++状态改变统一投影 |
| `workspace.state_changed` | `route_state + active_route_revision`及与WorkspaceState相同的nullable identity union | activate/lock/logout/revoke/cleanup后发布；ready/locked/empty null矩阵严格校验，Flutter用`workspace.get_state`恢复 |

实现要求：

- EventHub为进程级 owner；Activity重建只替换 sink，不清空权威 revision。
- 先建立订阅、再查询状态时，Flutter只接收更大的 revision；Kotlin测试必须覆盖订阅/查询乱序。
- 后台无 Flutter engine 时只更新权威状态，不缓存无限事件；新订阅靠 get方法恢复。
- 冲突红点只来自状态计数，不发送系统通知，也不在 Event中携带冲突内容。

## 9. WorkspaceRegistry 与多 runtime 生命周期

### 9.1 Registry 持久化

新增版本化、原子写入的 Kotlin私有 Workspace Registry v1，只允许保存：

- `workspace_id`、workspace kind、不可逆账号摘要、精确目录路由；`WorkspaceIdentityFactory`是workspace UUID唯一物理分配方，创建/legacy v5 guest迁移时先用journal稳定分配再传C++ open，C++不得回传另一id。
- C++ `runtime_instance_id` 只作为当前进程态，不能跨进程复用。
- Keystore包装 alias 的不可逆路由标识，不保存明文 DEK。
- 当前活跃账号、reminder eligibility、cache state、`retained_until` 与全局单调`active_route_revision`。
- 每个session-bound账号的current `sync_transport_generation`、nullable `transport_fence_required/fence_operation_id`与不含业务payload的lifecycle receipt摘要；它们只用于防旧HTTP提交，不能充当C++ sequence/cursor owner。
- `receive_reminders` 的本机调度状态，以及不含 token/payload的 device settings镜像待上报元数据；`sync_enabled` 的权威值仍只在 C++ `sync_state`。
- remote device内容不得进入普通Registry；Registry只留cache-present/freshness/schema等无内容索引。真正的脱敏快照放SQLCipher账号库，或独立account-scoped Keystore AEAD记录并以account/workspace/schema作AAD，随账号key lifecycle销毁；不得缓存installation摘要、session/token或将“无快照”伪装为空列表。
- 清理状态机所需的精确阶段；不得保存业务事实、token、cursor、mutation、标题或搜索历史。

账号目录使用 account UUID的不可逆摘要，经过 canonical-path校验后必须仍位于唯一账号 cache root。游客继续使用现有生产目录，以保证 v5→v6相邻迁移可以发现历史数据。目录名、alias、缓存摘要均不向 Flutter或日志暴露。

installation identity 存在版本化、原子且不参与系统备份的本机记录中：首次安装生成安全随机 UUID，升级保持，清数据或重装后变化；不得由 Android ID、IMEI、广告 ID、邮箱或账号派生。

一个 installation 可分别注册多个账号并取得不同 `device_id`。同账号 active registration 幂等复用，revoked registration 永不复活；显式再登录接受 Backend 新 device id。仍有未确认 sequence/Outbox 时不能替换 workspace 的 device id；未注册、已撤销或 account/session mismatch 时，account runtime 不得可写打开。

缓存已删而 Backend 仍复用 active device 时，register 只提供 current transport/sequence snapshot。Kotlin 必须以 durable `fence_operation_id` 调 `sync.device_fence`，严格消费 `sync_transport_generation + highest_client_sequence/next_client_sequence/client_confirmed_through/client_sequence_exhausted` recovery bundle，之后才传给 fresh C++ 并 bootstrap。union 不匹配是 Contract 错误；耗尽时只允许相应只读/blocked。

最终确认基线只由 bootstrap recovery bundle 证明；existing DB 不能被 register 值重置，active clear 的 existing runtime 先 Native accept fence。retained DB 绑定的旧 device id 若与新 register 不同，先 crypto-destroy 旧 key/DB/Outbox，再以新 device/register+fence seed fresh-open/bootstrap；禁止迁移旧 device Outbox。

账号级Android设置记录fresh/rebind初始化也必须原子：若本机不存在可信Registry记录，`receive_reminders`只在此次新local lifecycle中从已认证`device.register`响应播种，`local_settings_revision=0`；真正新device的服务端值已按账号生命周期首台/未来设备默认计算，同active device缓存销毁后的重登则恢复服务端现值。C++ `sync_enabled`不读取响应中的诊断镜像，完整destroy/到期后的新local lifecycle始终采用Contract genesis true/revision 0；若register响应的服务端sync镜像不是true，Registry必须置`settings_remote_pending=true`并幂等排一次独立report（或统一对新lifecycle排幂等report），把新owner值收敛到镜像，不能写`remote_pending=false`后永久漂移。active clear从operation journal保留两位owner的旧值，retain直接保留；完整destroy/到期后future login采用上述genesis/rebind并由UI明示，不能从残留普通Preferences猜值。

### 9.2 同时存活模型

- Registry至少能路由“游客 reminder runtime”和“当前账号 runtime”；登录账号不关闭游客提醒能力。
- Broker session state与UI active route是正交状态：允许且必须持久恢复`session=active + route=local`。进程重启、Event丢失或后台账号sync都不得自动把前台切回account；只有用户/通知显式`workspace.activate`成功才改变route。此时“退出登录”仍由Broker处理session绑定账号，local route不是同步/清理目标。
- UI active workspace与 reminder-eligible workspaces是两套集合：前者同时只有一个，后者可以包含游客和当前账号。
- `workspace.activate` 释放旧 workspace的 UI route lease并取得目标 UI lease；只要旧 workspace仍承担游客/账号提醒或同步角色，其 runtime不得被误关。只有该 workspace所有角色lease释放后才能调用最终 close。
- 账号退出后立即从 reminder-eligible集合移除并取消该账号提醒；游客保持不变。
- 未登录的其他账号缓存既不打开 runtime，也不执行提醒、搜索、同步或页面查询。
- C++按云同步-03实现多 handle registry，Kotlin持有 workspace与 handle的一一对应映射；UI、Worker、Alarm/Receiver并发只能经该 registry路由。反复重初始化全局 `g_state` 或以“受控串行切库”代替同时存活模型均不可接受。

### 9.3 激活状态机

```text
idle(workspace A)
  → validating(target B, expected_active_route_revision)
  → blocking_new_ui_calls
  → opening_or_unlocking_B
  → committing_route_tuple(B, runtime_instance_id, revision+1, ready)
  → publishing_workspace_state_changed
  → idle(workspace B)

任一步失败：保留 A 的可用 route；B 不可见；不得回退到默认游客路径。
```

如果 C++ open是先关闭旧 active runtime的模型，则失败回滚语义必须由 Workspace ADR与 C++ Contract重新冻结；Kotlin不得假装切换成功。切换期间所有 Flutter业务调用应收到稳定的 `WORKSPACE_SWITCH_CONFLICT`/冻结等价错误，而不是排到错误库执行。

`committing_route_tuple`是唯一切换线性化点：Registry用一次原子replace/CAS共同持久化`active_workspace_id + runtime_instance_id + active_route_revision + route_state`，提交前A仍权威，提交后B完整权威，绝不分别写workspace与revision。Event只在提交后发布且允许丢失；若进程在提交后、event前强杀，`workspace.get_state`仍无CAS返回B。进程重启需要新runtime identity时，也先以revision+1提交完整tuple再开放业务调用，旧identity/revision全部拒绝。

### 9.4 Workspace-local Android state

- Search History固定采用workspace-scoped保留方案，不再二选一。升级时旧全局`excellent_calendar_search_history_v1.json`只迁入guest一次，写入耐久`search_history_global_to_guest_v2`回执后删除旧文件并停用旧生产writer。新guest文件仍在`noBackupFilesDir`；account使用以workspace/schema作AAD的Keystore-AEAD AtomicFile和独立key，文件名只含不可逆workspace摘要。离开/锁定/退出立刻清内存并停止访问，retain窗口内同账号重登恢复；revoke/destroy/可信到期先毁key。历史只含normalized keyword，不含对象ID或标题引用；guest导入不复制或清空历史，A/B永不互读。
- 旧全局 `appearance.*_local` 在升级时通过一次性 `appearance_to_guest_v1`回执迁入 guest `preferences.update`；强杀后重复执行必须幂等，绝不把值归给首个登录账号。账号 `habit_progress_color` 只通过账号 workspace的 `preferences.get/update`；仅用户明确 guest→account 导入且 manifest包含 portable preference时才复制颜色，不能双写全局 SharedPreferences。
- 旧 Flutter `cached_current_user_v1.json` 在新 profile cache切换时必须按兼容迁移决定删除/拒读；账号生产页面不得再把它作为 fallback。
- reminder recovery、Work唯一名、Alarm/PendingIntent、Notification ID、Ring session、Habit action都必须纳入 workspace identity。
- `SyncWakeRecord`是Kotlin-local、每`workspace_id + device_id`一份的无业务内容唤醒索引，位于`noBackupFilesDir`的Keystore-AEAD `AtomicFile`；只保存schema、workspace不可逆摘要、current/successor的wake token与稳定WorkRequest UUID，以及最后drained token。它不能保存mutation、cursor、凭据或run capability，并与账号cache key一同按生命周期清理。
- 不允许在任何 Worker/Receiver错误路径调用无参数 factory并回退游客库。

## 10. Keystore 与账号 SQLite key 生命周期

### 10.1 密钥层次

- 每个账号 workspace首次创建时，用 `SecureRandom` 生成独立 32-byte DEK。
- 每个账号使用独立、不可导出的 Android Keystore wrapping key；不得复用 `excellent_calendar_refresh_token_v1`。
- DEK只以带版本、workspace/account binding和 AEAD认证的 wrapped record落盘；文件位于 app-private/no-backup 的精确账号密钥目录。
- 包装记录使用临时文件、flush/fsync、同目录原子替换，并验证目录边界；是否需要目录 fsync由 ADR和Android文件系统测试决定。
- 打开账号 workspace时解包为 `ByteArray`，通过 `runtime.open_workspace` 的独立二进制 JNI参数传入，随后清零 Kotlin缓冲。
- Access/Refresh Token 与数据库 DEK使用不同 alias、不同文件、不同生命周期和不同错误类型。

### 10.2 Missing/corrupt key

- 解密路径只允许“读取既有 key”；missing alias不得调用 get-or-create 后把 AEAD失败伪装为普通数据损坏。
- `WORKSPACE_KEY_UNAVAILABLE`、包装记录损坏、账号绑定不符、数据库 wrong-key分别形成稳定失败；全部 fail closed，不打开游客库。
- 账号 DB、WAL、SHM、临时页和迁移文件均必须由选定方案加密；仅放在 Android私有目录不算达标。
- Kotlin日志只能记录稳定错误码、workspace摘要和阶段，不能记录 key、alias、账号ID、路径、SQL或 payload。

### 10.3 生命周期矩阵

| 事件 | Token | runtime/内存 DEK | wrapping材料与加密 DB | 提醒/Work |
| --- | --- | --- | --- | --- |
| 正常退出 `server_then_local` | 服务端 succeeded/already_invalid 后删除 | close并清零 | 按 `retain_30d/destroy_now`执行 | 取消该账号；游客不变 |
| 服务端退出网络失败 | 保留且仍为当前会话 | 保持当前状态 | 不改变 | 返回 unreachable，等待重试或显式 force-local |
| 强制本地退出 `force_local` | 删除 | close并清零 | 同boot可信锚可选`retain_30d/destroy_now`；无锚只允许`destroy_now`，retain请求零终止并返回`RETENTION_TRUSTED_TIME_REQUIRED`；destroy留下future transport-fence-required | 取消账号；local不变 |
| `workspace.clear_account_cache` | 当前session保持active | 阻写/drain/ack→transport fence后close并清零 | fence receipt/sequence bundle/owner seed齐全才进入deleting；fresh key+DB+bootstrap+import recovery | 暂停账号提醒，全部恢复门禁完成后按设备开关恢复 |
| 当前设备收到 `DEVICE_REVOKED` | 删除全部该会话凭据 | 立即close并清零 | 立即密码学销毁并删除，不走30天保留 | 停止同步并取消账号提醒 |
| 账号删除 | 删除 | 立即close并清零 | 立即销毁 | 同上 |
| App数据清除/卸载 | 系统删除 | 系统终止 | 系统删除 | 系统取消 |

清理是可恢复状态机：先持久化目标和阶段，再阻止打开，随后取消Work/Alarm、close、销毁alias/wrapped DEK并删除精确文件。logout/revoke/到期最终移除registry；active的“立即清缓存”则保留session/account/device路由，进入fresh-key/open/bootstrap重建。中断后只继续同一精确目标；绝不能扩大到workspace root或游客目录。

## 11. SessionCredentialBroker

### 11.1 状态与并发

Broker为 Application作用域，状态闭包为 `empty / pending_adoption / registration_pending / active / refreshing / reauth_required / terminating`。所有入口——Flutter前台 HTTP、Sync Worker、设备管理、logout——调用同一实例。

- adopt先将完整 `AuthenticationResponse` 放入不可对业务开放的 pending-adoption状态，用其中AT调用`user.get_current`；account/profile/preferences identity/revision及服务端sync entitlement交叉校验通过后，再用规范化设备名调用`device.register`。非白名单的`SYNC_NOT_ENABLED_FOR_ACCOUNT`使Broker安全清除pending（best-effort logout不阻塞），保持原guest active且不创建device/账号DB/Outbox。注册成功时Broker持久化account/device/session/RT binding、current transport与sequence bundle；若发现该active device对应本机业务库已destroy/fence-required，则先完成`sync.device_fence`再允许fresh open。`DEVICE_LIMIT_REACHED`时原子持久化已验证account/session/installation摘要与RT为受限`registration_pending`，明确不保存伪device id、不开放账号库。
- adopt交叉校验网络失败时保留同一 session的受控 pending-adoption以供幂等重试，但不打开账号 workspace；identity不一致立即清除 pending token并 fail closed。
- 固定首次顺序是 `auth.session.adopt` 内完成 identity交叉校验与 `device.register` → Broker原子接管 account/device/session/sequence seed → 创建或解锁账号 workspace；fresh DB先 bootstrap → 用 `profile.accept_server_snapshot`接纳已交叉校验的安全资料投影 → 导入决策。缺少 device binding时不得以可写模式开账号库。
- `registration_pending`恢复且网络可用时先自动幂等register：这覆盖revoke已提交但响应丢失、或revoke后内部register前强杀；仍超限才给Flutter列表。revoke结果无论明确或不确定都立即销毁grant，随后只靠持久化installation/name重试register；registered则保存binding/seed并准备workspace，still-limited则刷新列表并要求新reauth，绝不重放旧grant/依赖旧AuthenticationResponse。其他HTTP、sync、profile/preferences写及workspace激活均先拒绝。
- 若registration-pending账号存在旧retained cache，Broker只凭已验证account binding定位但不开库；pending logout的destroy-now必须执行import abandon best-effort与真实crypto-destroy并回传cache/abandon结果，retain-30d回传原期限。未验证pending-adoption没有可信cache目标，返回not-applicable，绝不按UI提供的账号猜目录。
- 默认设备名取 `Build.MANUFACTURER`与`Build.MODEL`：Unicode trim/空白折叠，model已有厂商前缀时不重复，空值回退本地化“Android 设备”，按 code point安全截断64；禁止 Android ID等硬件标识。
- 普通 `get_access_token` 在 AT剩余时间满足阈值时直接返回当前 token与 `access_token_generation`；每次 token替换 generation单调递增。
- AT不足时第一个调用启动 refresh，其余调用等待同一结果。若请求携带刚被服务器401拒绝的 generation：Broker当前值更大则直接返回较新token；相等则即使未过期也强制加入一次 single-flight refresh。每个HTTP调用最多重放一次，第二次401终止，不并发旋转RT、不无限重放。
- refresh成功：严格验证 `ApiResult<TokenPairResponse>` 与 session/account binding，先原子持久化新 RT，再发布新 AT。
- RT持久化失败：不发布 AT、不继续业务请求，进入 fail-closed状态。
- 服务端已旋转而响应/落盘结果不确定：按 Session ADR默认清空本机会话并要求重新登录，不重放旧 RT。
- 进程重启：只从安全记录恢复 RT/session/account binding；AT默认不落盘，首次需要时刷新。
- `AUTH_REFRESH_TOKEN_REUSED`、`AUTH_SESSION_EXPIRED`、`DEVICE_REVOKED` 等终态错误停止自动重试并进入统一 termination；普通 DNS/timeout不得错误删除仍有效本地缓存。

Broker内部锁不得包住长时间 JNI、HTTP或主线程 callback。使用“锁内决定/登记 flight → 锁外网络 → 锁内 CAS发布”的结构，并以 generation防止 logout期间迟到 refresh重新发布 token。

### 11.2 旧 Refresh Token 受控迁移

当前旧安全记录只有 `{refresh_token, session_id, expires_at}`，没有可验证的 account/device binding；它不能直接升级成新版 Broker active record，也不能据此打开账号 workspace。新包首次发现旧记录时执行单一、可恢复的 migration state machine：

1. 先停用生产 Flutter refresh owner和 `auth.refresh_token.read`，把旧记录标为 migration-pending；任何 MethodChannel都不得返回 RT。
2. 在线时由 Broker独占旧 RT完成一次受控 refresh。成功响应必须在同一次原子状态转换中落盘 pending新 token并把旧 RT标记为永久 retired；从这一刻起 pending新 RT是唯一可恢复凭据，即使旧加密字节尚待最终删除也绝不允许再次读取或发送。身份未完成前不发布 AT、不开放账号库。
3. 用新 AT调用 `user.get_current`，严格交叉校验 session/profile/preferences identity与 revision；随后调用 `device.register`取得当前 session的稳定 account/device binding。
4. 只有上述步骤全部成功，才把 pending token、account、device、session一次 CAS提交为新版 Broker record，删除旧记录/迁移标记并允许创建或解锁账号 workspace。
5. 离线、DNS或可重试 transport失败时只激活游客 workspace；保留原加密旧记录和 migration-pending供下次联网继续，但 UI不可列出/激活该账号，Flutter也拿不到 RT。
6. identity不一致、refresh终态失败或旧记录损坏时清除候选 session并要求重新登录。若服务端是否已旋转或新 RT是否已安全落盘无法确定，同样清会话重登，绝不重放旧 RT。

每一阶段都持久化非敏感状态和 generation，进程强杀后只能恢复同一阶段；迟到 refresh、`user.get_current`或`device.register`响应必须通过 generation + session校验，不能复活已退出会话。迁移完成前 `workspace.list`仍只展示 guest，不得从旧记录猜 account id或生成临时 device id。

### 11.3 Re-auth grant

- `auth.session.reauthenticate` 严格接收 `password + purpose + target_device_id`，三者共同参与请求校验；password只进入一次 HTTP request的临时字节/字符串生命周期，不写日志、state、saved instance或 WorkData。
- 服务端 `reauth_token` 只存 Kotlin内存，绑定 session、purpose、target device和到期时间；`registration_pending` 时 actor device可空，但必须额外核对 persisted attempted installation摘要，不能把grant带到另一登录/安装。
- Flutter只拿一次性 `grant_id`；`device.revoke` 消费后立即删除，无论成功、失败或取消都不能重用。
- 进程死亡使 grant失效；不得为便利持久化 server reauth token。

### 11.4 统一终止路径

统一 SessionTerminationCoordinator 顺序：

进入第1步前先按Contracts-02校验cache policy。`force_local + retain_30d`但无同boot可信锚时返回`RETENTION_TRUSTED_TIME_REQUIRED`，保留既有logout review gate且不进入terminating、不推进session generation、不关闭runtime或改缓存。

1. CAS校验expected session generation与调用方观察到的active route tuple，标记terminating并增加session generation；拒绝新账号调用，但不改变local route。
2. 取消/等待session-bound账号的Sync unique chain到达安全点；前台为local也不能取消/清理local runtime或游客提醒。
3. `server_then_local` 先调用服务端 logout；只有 succeeded/already_invalid 才进入本地终止，unreachable立即返回且保持会话。`force_local`只在Flutter显式确认且cache policy已通过前置校验后直接本地终止，不伪造服务端状态。
4. 删除 RT、安全记录、AT与 reauth grant。
5. 关闭账号 runtime并清零 DEK。
6. 取消该账号 Alarm、Notification、Ring与 reminder work。
7. 按Contract cache policy建立非null deadline后保留不可见缓存30天，或先销毁key再删文件；所有destroy记录future transport-fence-required，除非权威device/account永久终态已使旧请求不可能再提交。撤销/账号删除/refresh reuse/identity mismatch/storage corruption固定立即销毁。
8. 若终止前active route是该账号，则原子激活local并推进`active_route_revision`；若原route已是local，则保持该tuple，不做无意义切换，只发布session/workspace-list变化。

任何步骤失败都返回明确状态；不得在安全存储或 runtime未处理时向 Flutter报告“退出完成”。

`auth.session.clear_local` 的固定 reason矩阵为：`normal_logout/session_expired/password_reset/logout_all`在能建立可信deadline时→加密隐藏保留30天；其中normal logout直接使用终态`server_time`，其他不可继续Session的reason若无法从当前可信响应/同boot锚建立期限则按隐私优先立即crypto-destroy，绝不落无deadline retained。`device_revoked/account_deleted/refresh_token_reused/session_account_mismatch/storage_corrupted/user_requested_destroy`固定立即crypto-destroy。Flutter只可在用户确认后请求`user_requested_destroy`，其他reason必须由Broker、可信服务端错误或storage检查派生；本地调用者不能用任意字符串扩大删除范围。

若 termination由正在运行的 SyncWorker因 `DEVICE_REVOKED`/auth终态错误触发，协调器先使 session generation失效并阻止后续 ack/apply，再取消其他 work；不得同步等待当前 Worker自己结束而死锁。任何 registry/Broker锁都不能跨 WorkManager等待、HTTP、JNI close或 Event回调持有。

## 12. Android HTTP transport 与环境隔离

### 12.1 Client 职责

新增统一 Android HTTP transport与窄 client：AuthClient、DeviceClient、SyncExchangeClient。它们共享 Broker、base URL policy、超时、响应上限、JSON codec和脱敏日志，但不共享 Native DTO。

| Backend operation | Path | Kotlin调用者 |
| --- | --- | --- |
| `system.time` | `GET /api/v1/system/time` | RetentionCleanupCoordinator；无bearer、无账号参数，只用于重启后恢复可信时间下界 |
| `auth.token.refresh` | `POST /api/v1/auth/token/refresh` | Broker single-flight |
| `auth.logout` | `POST /api/v1/auth/logout` | SessionTerminationCoordinator |
| `auth.reauthenticate` | `POST /api/v1/auth/reauthenticate` | Broker reauth |
| `user.get_current` | `GET /api/v1/users/me` | `auth.session.adopt` 权威身份交叉校验；安全投影在device注册并开库后交 `profile.accept_server_snapshot` |
| `device.register` | `POST /api/v1/devices` | 首次账号 workspace激活流程 |
| `device.list` | `GET /api/v1/devices` | DeviceClient |
| `device.rename` | `PATCH /api/v1/devices/{device_id}/name` | DeviceClient |
| `device.update_settings` | `PATCH /api/v1/devices/{device_id}/settings` | DeviceSettingsCoordinator上报本机 `receive_reminders` / `sync_enabled` 镜像与 expected version |
| `device.revoke` | `POST /api/v1/devices/{device_id}/revoke` | DeviceClient + reauth grant |
| `sync.device_fence` | `POST /api/v1/sync/device-fence` | WorkspaceLifecycleCoordinator在active clear不可逆删除前，或Broker在同active device fresh recovery开库前调用 |
| `sync.exchange` | `POST /api/v1/sync/exchange` | SyncCoordinator |
| `sync.bootstrap` | `POST /api/v1/sync/bootstrap` | SyncCoordinator bootstrap loop |
| `sync.import.status` | `GET /api/v1/sync/imports/status` | WorkspaceCoordinator：exact batch可取九态终态；source discovery只取当前需恢复handle或empty |
| `sync.import.takeover` | `POST /api/v1/sync/imports/{import_batch_id}/takeover` | WorkspaceLifecycleCoordinator在full-successor前关闭旧range并取得proof；不得由普通Worker自报reason |
| `sync.import.abandon` | `POST /api/v1/sync/imports/{import_batch_id}/abandon` | WorkspaceLifecycleCoordinator严格传nullable`predecessor_batch_id`及完整identity/manifest/range/revision做独立CAS；不走Outbox |
| `sync.import.cleanup_confirm` | `POST /api/v1/sync/imports/{import_lineage_id}/cleanup-confirm` | WorkspaceLifecycleCoordinator按guest同epoch cleanup receipt收尾；不走Outbox/sequence |
| `sync.get_status` | `GET /api/v1/sync/status` | 诊断；不替代本地状态 |
| `sync.conflict.list` | `GET /api/v1/sync/conflicts` | 仅按最终架构需要；UI默认读C++本地镜像 |
| `sync.conflict.get` | `GET /api/v1/sync/conflicts/{conflict_id}` | 同上 |
| `sync.conflict.resolve` | `POST /api/v1/sync/conflicts/{conflict_id}/resolve` | prepared batch的专用 route；仍由 `sync.acknowledge_upload` 落本机终态 |

route由 C++ `sync.prepare_upload_batch` 返回，Kotlin按冻结枚举分发；不能检查任意 payload猜 endpoint。每个mutating sync/import/bootstrap请求必须带Broker与C++一致的current `sync_transport_generation`；账号身份只来自 bearer Principal，请求体不得补写 `account_id/user_id`。Kotlin在发请求前登记`session/device/runtime/transport generation` flight，响应只有四者仍完全匹配才可进入Native；fence一旦提交，旧flight响应无论HTTP内容如何都丢弃并结束旧run。`system.time`不走Broker、不带cookie/bearer/账号或workspace信息，只接受与Release相同的HTTPS/host校验、exact `ServerTimeResponse`和`no-store`响应；它不是普通Sync route，也不能进入Native业务apply。

四类import HTTP DTO必须逐字段消费transport generation、source workspace/epoch、lineage/batch、nullable predecessor batch、完整manifest/count/bytes/range、expected/resulting revision与strict disposition；predecessor参与abandon exact-key、幂等digest与lineage/head校验，不能丢弃。takeover reason不得由UI或Kotlin自行推断：`local_evidence_lost`只在caller=origin且Native明确报告证据丢失时发送，`origin_unavailable`只根据Backend status中的权威revoked资格，`ttl_payload_reclaimed`只回送Backend已持久化状态；非法actor/reason零写。abandon/takeover/capacity响应的`seen_range_closed / never_visible_after_transport_fence / proof=null`排他分支，以及cleanup-confirm的同epoch through水位分别使用strict oneOf。proof-null时保留库必须继续持有原range、补齐前序后重试；never-visible必须绑定已接纳fence且仅用于fresh destructive lifecycle，缺字段不得归unknown后继续。

`ImportStatusDto`严格使用Contracts-02的九态`stage`及三个正交enum；Kotlin不得把HTTP/JNI失败写成`stage=failed`，也不得把`abandon_status=pending/unconfirmed`折叠成stage。带batch id的exact查询可以返回`completed/superseded/abandoned`，无batch的source discovery不得返回completed旧handle。无谱系时batch/head/revision必须null且三个正交字段为`not_applicable/not_required/none`；有谱系时identity/head/revision必填，proof/predecessor/publish/cleanup字段只在对应resume/reconciliation分支非null。HTTP与Native投影冲突时fail closed并保留两侧证据，不选择“进度更靠后”的字符串。

Device settings镜像按当前 session的单一 transport lane串行上报。离线多次修改可合并为最新 typed patch，但必须保留本机 revision和最后已确认 `expected_device_version`；遇到 `DEVICE_VERSION_CONFLICT` 时先重读当前设备版本，再只重放仍然有效的本机意图，绝不能用服务端旧 `sync_enabled` 覆盖 C++状态或无限 CAS循环。`DeviceSettingsReportWorker` 使用独立 unique name/network constraint，可在业务 sync关闭后继续完成这一次镜像上报；它不取得 runtime写 lease、不读取 Outbox、不调用 sync endpoint，logout/revoke立即取消。

### 12.2 Strict transport

- 请求与响应遵循冻结的 HTTP status + `ApiResult<T>`规则；无合法 envelope的4xx/5xx归 transport/protocol failure，不能伪造 Native错误。
- 执行 exact-key、content-type、UTF-8、长度、safe integer、UTC、enum和 response body上限校验；压缩前后上限按 Contract统一。
- `sync.device_fence`使用外部Keystore-AEAD lifecycle journal中的稳定operation id/expected generation；响应只有在完整receipt落journal并被Native接纳（或作为fresh open seed原子消费）后才更新Broker current generation。响应丢失只重放同operation，禁止生成新id连续递增。
- 设置连接、读、写、整体 run budget与取消传播；Worker停止后网络调用和后续 JNI步骤必须尽快停止。
- 可重试429、冻结列表内5xx/DNS/timeout统一使用full jitter：第attempt次（从0开始）`uniform[0,min(15min,5s×2^attempt)]`，一轮最多8次。合法body `retry_after_seconds=1..86400`只把delay提高到`max(jitter,hint)`并封顶24小时；B0若保留HTTP `Retry-After`，它只能是同数值镜像，body/header不一致为非法envelope。无hint仍走基础算法，不能blocked或热循环；手动触发、offline→online或间隔至少30分钟的前台恢复开启新预算，成功exchange清零。证书/hostname/未知envelope立即blocked且不可降级。
- 禁止记录 Authorization、Cookie、token、password、reauth token、cursor、mutation、业务 payload、响应 body或文件路径。
- 不允许自动跨 scheme/host重定向；尤其禁止 HTTPS降级到 HTTP。
- 任一 authenticated请求收到首个401时，把该请求使用的 `access_token_generation`交给 Broker：若已有更新 generation则直接取得它，否则强制加入一次 refresh single-flight；原请求最多重放一次。重放仍401时按 Auth终态处理，不循环 refresh。401响应体若不是冻结 envelope也不能改变“一次重放”上限。

### 12.3 Debug / Release

Debug：

- base URL必须显式配置，允许 `10.0.2.2` 或明确的 RFC1918测试地址使用 HTTP。
- 明文 network security config只存在 `src/debug`；Debug application id继续与生产隔离。
- 仅使用测试账号与测试数据，日志同样不得输出敏感字段。

Release / 公网验收：

- 主 Manifest声明 `android.permission.INTERNET`。
- base URL在构建时必须显式提供；缺失、默认占位、解析失败即构建失败或进程启动 fail closed。
- 公网配置使用证书匹配的受控DNS hostname，不把服务器动态公网IP硬编码进APK；地址变化只通过DNS/受控endpoint配置切换并验证解析、TLS与health。临时endpoint必须有到期策略。
- 只允许 HTTPS，拒绝 HTTP、loopback、私网地址和默认 `10.0.2.2`；禁止 Release overlay开启 cleartext。
- 使用系统信任证书链与 hostname校验，不加入 trust-all、用户证书绕过或调试 CA。
- Release测试必须检查 merged manifest、BuildConfig值和真实握手，而不只测 URI字符串函数。

## 13. SyncCoordinator 与 WorkManager

### 13.1 唯一队列

- 每个当前认证的 `workspace_id + device_id` 只有一条 unique one-time chain；内部 Work名使用固定前缀加不可逆摘要，不含账号明文、邮箱或 token。
- 手动同步、业务写后机会调度、App启动/回前台、网络恢复、periodic trigger全部调用Application级`SyncWakePump.request(workspace)`；业务模块不能直接调用WorkManager。
- one-time统一使用当前WorkManager版本支持的`ExistingWorkPolicy.APPEND_OR_REPLACE`。它只保证同名工作图的追加，以及failed/cancelled前驱后的替换语义，**不合并或去重WorkRequest**；不得使用会忽略新请求的`KEEP`，也不能开第二HTTP/JNI并发路径。
- periodic work只负责机会入队，不直接交换，也不承诺周期精度。
- Worker使用 `NetworkType.CONNECTED`，尊重系统后台/Data Saver；无 FCM、无常驻 foreground service。
- `WorkData`只保存路由所需的非敏感摘要、稳定WorkRequest id与wake token；run intent必须从Broker/C++/lifecycle耐久状态重新裁决，WorkData不是`logout_final`等内部capability。不保存AT/RT、cursor、batch、mutation或业务JSON。
- 登出、关闭同步和撤销按精确 unique name取消并等待安全点；不能取消游客 Reminder work或其他账号清理 work。

`SyncWakePump`按下列协议做有界合并；这些约束是实现要求，不由具体类名决定：

1. 每次触发进入Application级串行临界区，先核对`SyncWakeRecord`与WorkManager状态。若已有ENQUEUED/BLOCKED节点覆盖未来运行，或已有RUNNING加一个successor，本次直接合并为“已覆盖”，不写新journal、不各自产生节点；C++/Broker/lifecycle耐久状态保留真正工作原因。
2. 若没有unfinished one-time节点，Pump生成一组UUIDv4 wake token/WorkRequest id并创建一个请求；若恰有一个RUNNING且没有successor，只生成并追加一个。硬不变量是每workspace最多“一个RUNNING + 一个ENQUEUED/BLOCKED successor”，历史已完成节点不计入并交WorkManager prune。
3. wake token与WorkRequest UUID在enqueue前写入journal，并通过`WorkRequest.Builder.setId`使用同一id。进程死在journal→enqueue之间时恢复代码补交同一请求；死在enqueue提交→状态回写之间时按id查询并接纳已有节点。查询失败不得盲目再追加，进入可重试repair。
4. Worker只确认自己WorkData中的wake token，在预算内排空C++给出的批次/ack/continuation；退出前重读`has_more/pending/ack_watermark_dirty/continuation_required`。仍有工作时只经Pump确保一个successor；全部已排空时只把本节点token记为drained，绝不确认更新的successor token。若successor已存在但当前Worker顺带排空了新写，它最多再运行一次空检查，不会形成几十个空Worker。
5. C++ commit与Kotlin wake journal不是跨库事务；若进程死在两者之间，Outbox仍耐久，App启动/回前台/网络恢复/periodic repair扫描C++ dirty状态并调用Pump。manifest不得把Pump/Worker放到另一进程；未来若启用多进程，必须先增加跨进程锁与相同故障测试。

协调器内部run intent闭包为`normal/logout_final/receipt_ack_flush/reenable_pull_only/clear_rebuild_bootstrap`五态：normal受sync-enabled约束；logout-final是Broker一次性授权，可在paused执行一次完整exchange；receipt-ack-flush只在C++ dirty时恢复，调用prepare的strict空uploads/download-limit 0/null-cursor分支；reenable-pull-only只在C++耐久pull gate存在时运行空uploads的固定上界下载/bootstrap；clear-rebuild只允许已确认clear lifecycle创建，只跑bootstrap begin/pages/finalize、不上传普通Outbox，并在finalize后必要时转ack-flush，完成后回到原paused/idle策略。Flutter和普通Worker不能伪造后四者。phase按Contracts优先级投影；有pending且网络不可用必须是offline-pending，即使WorkManager已排CONNECTED约束也不显示queued。

### 13.2 单次 run 状态机

```text
queued
 → acquire exact workspace/runtime lease
 → check sync_enabled + device/session/transport-generation binding
 → Broker.getValidAccessToken
 → pull-before-push gate（仅首次、重启/重开、重新启用时）
 → JNI sync.prepare_upload_batch
 → HTTP sync.exchange 或 prepared route
 → strict response validation
 → JNI sync.acknowledge_upload
 → JNI sync.apply_download_batch
 → repeat while has_more / pending / ack_watermark_dirty within budget
 → workspace-aware reminder reconcile
 → publish status revision
 → success | scheduled retry | blocked
```

详细约束：

- 重新开启同步时，`sync.set_enabled(true)`已让C++持久化pull-before-push gate；Kotlin调用`sync.prepare_upload_batch(run_intent=reenable_pull_only)`取得由C++提供current cursor/ack的空uploads normal请求，拉完固定上界并逐页normal ack/apply，cursor需要bootstrap则完成bootstrap。只有Native terminal apply/finalize解除gate后，Kotlin才改用normal prepare读取Outbox；UI标志、Kotlin内存状态或直接构造空request都不能绕过，任一点强杀后仍从gate恢复。
- prepared request的identity/hash/route/transport generation/current opaque cursor/download limit/ack均由C++持久化；Kotlin只附Bearer并原样传exchange。响应丢失后水位不进、在同generation重跑同request；fence后旧HTTP handle失效，若保留DB需要继续上传则由C++在new generation返回同一不可变mutation内容的新transport handle，Kotlin不改hash。带effect的terminal ack只有对应group apply/权威bootstrap覆盖后才使水位越过，不生成新sequence。
- normal exchange必须回显prepared identity、transport/account generation、snapshot upper bound、has-more、cursor/cleanup与Backend接受的ack。Kotlin即使results为空也先调用normal acknowledge，再把完整normal response交apply。若本轮又推进local水位，即使has-more=false且Outbox空，loop也必须用`receipt_ack_flush`取得严格ack-only PreparedExchangeRequest；响应只调用ack-only acknowledge，明确跳过apply，直到server-accepted追平或耐久排队continuation。run success、logout-final与active clear fence前门槛均不得提前。App启动、runtime恢复与disable取消链安全点都读取C++ dirty并补排同workspace唯一ack-only work；它可在paused/cursor expired时收尾，但Session/transport必须current。
- 首次逐项终态为`accepted / partially_merged / conflict / rejected / staged`，其中staged仅用于import begin/item；import commit成功是`accepted + import_disposition=server_confirmed + publish metadata`，失败是`rejected + repair_required metadata`。receipt精确重放使用`status=duplicate`并完整携带original status、原terminal result/receipt/effect identity、per-key applied/resulting version及terminal rejected/conflict的`causal_disposition=no_effect + effective_prior_sequence/version`、sequence、mutation与hash；Kotlin只strict校验/透传，不能归一化或丢细节。C++若因仍有非终态后继引用该no-effect sequence而停住ack，Kotlin必须原样发送旧水位，不能按“已收到terminal”自行跨过。
- duplicate只有在 workspace、device、batch、item顺序和上述原始终态字段与当前 prepared batch全部一致时才可交给 `sync.acknowledge_upload`；缺字段、错 original status、receipt/sequence/mutation/hash变化均按 protocol failure阻断，且不消费/跳过本地 sequence。
- `sync.acknowledge_upload`只落terminal/成功causal anchor与隐藏effect gate；普通用户/冲突解决mutation的no-effect rejected由C++同时转为typed failed-local overlay，仍显示但明确未同步、不自动重传。随后`sync.apply_download_batch`原子应用不可拆group、解除gate并按baseline→pending→failed顺序重投影。两者都成功前不使用响应中的cursor发下一页；任一步崩溃后使用C++返回的旧/next-request cursor与稳定batch重放。
- 每页/每批都先校验workspace/device/session/sync transport generation，再校验account generation/upper bound/download union及 `retention_floor_server_sequence/resolved_conflict_cleanup_before`；水位缺失/倒退/代际错配时不交给maintenance且不用本机时钟补值。Kotlin不猜conflict lifecycle。
- `has_more`、本地pending、`ack_watermark_dirty`和时间预算共同决定循环；达到预算时保存权威状态并串行追加continuation，dirty不得因Outbox=0被丢掉。
- Worker取消、logout generation变化、runtime lease撤销时停止；迟到 HTTP响应不得写入新会话或新 workspace。
- `sync.conflict.resolve` mutation由 C++ prepared route发到专用 Backend endpoint，但仍占用同一 device sequence并用普通 acknowledge闭环。
- import begin/items/commit的source epoch、manifest count/total canonical bytes、ordinal、hash与terminal results均来自C++ prepared batch并原样传输；Kotlin不得自行计数、拆分publish chunk或宣布确认。C++ commit只有在guest `reserved→account receipt→active(batch/manifest/range, epoch)`完成后才返回可入队handle，Kotlin必须核对active disposition后才enqueue；reserved恢复中或`IMPORT_SOURCE_OWNED`时网络零调用、账号零新增写且绝不泄露owner。Backend对active route mismatch返回请求级永久错误；abandon/takeover/capacity early terminal携带range-close proof时先交Native原子终结matching本地range，再按dirty走ack-only。`server_confirmed`只触发继续下载；只有C++返回`publish_applied`后才进入guest精确清理/cleanup-confirm/account reconcile。
- publish-applied后Kotlin不得先取消guest提醒：先让C++在guest单事务按source epoch compare-and-retire整张live snapshot。完全匹配时，C++原子退休live图并以`source_migrated`终结非终态Reminder/prepared attempt、保留终态审计anchor、写同epoch cleanup receipt，再推进current epoch/previous-epoch gate。Kotlin只消费返回的affected identities取消精确平台任务，然后按“读取exact guest receipt→独立HTTP cleanup-confirm→把同epoch disposition/revision/through交Native→finalize lease”推进；Search History不在affected集合且保持guest。只有Native completed才解除源设备account reminder suppression。
- 若compare-and-retire返回`IMPORT_SOURCE_CHANGED`，本次零退休、epoch不进、guest提醒继续；只按same-epoch/same-lineage/new-batch/predecessor覆盖“当前图∪该epoch历史mapping”，Kotlin不搬运delta或跨epoch复用mapping。已有未cleanup predecessor时reconciliation successor没有普通取消路径；privacy destroy可停止本机，但未来登录须按source workspace + receipt/current epoch恢复。
- full-successor恢复固定顺序为：读取guest source/current或receipt epoch与`sync.import.status` → 依据服务端资格调用HTTP takeover；若旧证据来自已销毁runtime且status为absent/never-visible-required，先完成`sync.device_fence` → strict校验seen/never-visible proof → `workspace.import_accept_range_close` → seen proof且origin为当前device时完成/耐久排队ack-only，never-visible只采用同一fence sequence bundle且不伪ack → 以proof resulting revision调用Native commit完整successor。proof接纳前、需要的ack状态未持久化前、或sequence/transport generation exhausted时普通writer/新import保持门禁；每个HTTP/Native/ack强杀点从journal幂等恢复。旧commit先赢转publish，CAS stale合并current状态，绝不直接用status revision分配新sequence。
- `workspace.import_abandon`由lifecycle协调器调用独立HTTP CAS。已有begin或begin恰为server next时confirmed结果携seen proof并按上述Native/ack闭环；batch absent且有前序gap时服务端只持久identity fence并返回`proof=null/sequence_advanced=false`，保留库必须保持原range、先让更早Outbox终结后用同operation重试，不能删除/逐项发送被fence的range或猜highest。matching迟到请求的request-level abandoned不产生可供C++确认的sequence receipt。privacy destroy无响应/无proof可记unconfirmed并继续销毁；未来同active device重登必须先transport fence并恢复never-visible proof。外部Keystore-AEAD lifecycle journal必须保留不含业务payload/账号明文的source workspace/epoch、opaque owner、origin transport generation、operation、absent/confirmed-abandon/range-proof/finalize intent与destroy-final receipt，直到`workspace.import_finalize_source_lease`成功才删除；普通logout/revoke/clear/30天到期不得擅自释放lease。

### 13.3 Bootstrap

收到 `SYNC_CURSOR_EXPIRED` 或 `SYNC_CURSOR_GENERATION_MISMATCH` 时：

1. 停止普通 exchange，不把 cursor重置为空。
2. 先以Broker/C++一致的current sync transport generation与`bootstrap_cursor=null`串行请求 HTTP `sync.bootstrap`。Backend创建或复用同一未过期active materialized session，并在首响应返回服务端生成的bootstrap id、transport/account generation、upper bound、device highest/client-confirmed/nullable-next/exhausted严格bundle、两个冻结cleanup水位、trigger reason和首页；首响应丢失后相同请求必须复用该session。Kotlin不生成id、不从普通cursor猜造bootstrap token。
3. strict校验首响应及bundle与当前account/device/fence seed单调一致后，原样调用 JNI `sync.begin_bootstrap` 建立/恢复该服务端 identity的 staging，再把首页面交给 `sync.apply_bootstrap_page`；C++ begin成功前不能保存“已应用首页”，Kotlin不能自行推进ack水位。任一时刻transport fence提交都使旧bootstrap response/token失效。
4. 后续仅使用Backend opaque cursor分页；每页strict校验identity/token/order/hash及`fact/tombstone/deleted_entity_anchor/unresolved_conflict/import_publish_marker/requesting_device_causal_anchor` union和Contract单项/页面hard-cap后原样调用C++。Kotlin不拆候选、不另拉冲突、不把部分页当live事实；oversize单项是Contract failure，不能热重试同cursor。
5. 只在完整facts、tombstones、deleted anchors、全部unresolved-conflict、device anchors与marker/provenance集合、final cursor合法且transport generation仍current时调用`sync.finalize_bootstrap`；C++以snapshot为baseline重放pending与failed-local overlay，fresh DB同时恢复旧receipt确认基线/causal anchors，原子发布facts/conflicts/publish-applied/receipts/cursor并返回notice/affected ids。
6. finalize成功后先确保device receipt recovery/本轮尾部ack通过ack-only flush被Backend接受；即使恢复的C++ policy为paused也执行这一housekeeping。然后仅在policy允许时继续普通exchange上传本地未确认Outbox，再做提醒reconcile；Kotlin不得仅凭import status的server-confirmed清guest。
7. `SYNC_BOOTSTRAP_EXPIRED` 或 `SYNC_BOOTSTRAP_GENERATION_CHANGED` 时，只让 C++丢弃对应未发布 staging，再回到第2步发起全新 null-cursor请求；不得先自行 `begin`、续传旧 token、复用部分快照或改动 live事实。
8. 当前 TTL候选为24小时，最终值与服务器清理竞态仍以 Sync Protocol ADR为准；Kotlin从响应/错误驱动恢复，不能用本机墙钟提前假定 session已过期。
9. 客户端/Backend进程强杀、重复页、乱序、漏页、过期、generation变化均可恢复；live事实不会暴露半快照。

### 13.4 错误与退避

| 类别 | Android动作 |
| --- | --- |
| `SYNC_PROTOCOL_VERSION_UNSUPPORTED`、`SYNC_BATCH_TOO_LARGE`、`SYNC_PAYLOAD_INVALID` | protocol永久分支先经`sync.record_transport_terminal`耐久blocked；批量/载荷请求级错误按Schema分类并保留数据，不得自动无限重试或删本地数据 |
| `SYNC_CHANGE_GROUP_TOO_LARGE` | 作为已消费sequence的逐项rejected落ack，保留本机意图并提示缩短内容/诊断；不改hash重发旧sequence |
| `SYNC_CLIENT_SEQUENCE_GAP` | 停止上传，保留 Outbox，只有本机 sequence诊断/修复完成后才重试；禁止猜号补洞 |
| `SYNC_SEQUENCE_REPLAY_MISMATCH` | 先经`sync.record_transport_terminal`冻结当前device并进入blocked；不得改payload/hash重放同一sequence，重启后仍不可prepare/write |
| `SYNC_SEQUENCE_ROUTE_MISMATCH` | active import保留range收到错batch/ordinal/普通route；零写且不推进highest，先经`sync.record_transport_terminal`耐久blocked，不能把错误请求改装成合法ordinal |
| `SYNC_CLIENT_SEQUENCE_EXHAUSTED`、`SYNC_SERVER_SEQUENCE_EXHAUSTED` | 先经本地allocator或`sync.record_transport_terminal`耐久永久blocked；保持本地事实/Outbox与只读能力，V1不回绕、不自动换device或伪造降级上传 |
| `SYNC_TRANSPORT_GENERATION_MISMATCH` | 当前HTTP属于已被fence关闭的旧lifecycle：丢弃整个响应/停止旧run，读取Broker journal并恢复同一fence/new runtime；零Native ack/apply，不把workspace标数据损坏 |
| `SYNC_TRANSPORT_GENERATION_EXHAUSTED` | active clear在不可逆前失败并零删除；隐私销毁仍可完成但future同device不得开可写账号库，进入只读/支持出口，不回绕generation |
| `WORKSPACE_ROUTE_REVISION_EXHAUSTED` | Registry保留最后稳定route并停止activate/switch；只开放诊断导出与安全终止，不换workspace identity或重复发布同revision Event |
| `LOCAL_SETTINGS_REVISION_EXHAUSTED`、`WORKSPACE_LIFECYCLE_REVISION_EXHAUSTED` | 需新revision的settings/clear/logout事务零跨owner写；已经提交的同revision lifecycle journal仍按原operation幂等收尾，不生成新operation绕过 |
| `AUTH_TOKEN_GENERATION_EXHAUSTED` | Broker在发布下一token snapshot前终止本地Session family并进入安全退出/重登录；不回0、不继续使用无法排序的token，也不伪造Backend generation |
| `SYNC_POLICY_REVISION_EXHAUSTED`、`SYNC_STATUS_REVISION_EXHAUSTED` | policy toggle零写并保留现有策略/Outbox/提醒；status owner只接纳MAX的durable blocked终态，此后不再发布同revision Event或伪造queued/success |
| `SYNC_NOTICE_SEQUENCE_EXHAUSTED` | 继续同步、保留unresolved count/冲突列表和旧notice；停止创建新一次性提示，Aggregator不得自造notice id/sequence |
| `SYNC_COUNTER_EXHAUSTED` | 按strict `counter_kind`把Backend能力标为永久只读/blocked并保留当前快照；不自动重试、换identity、重建版本或将其映射成普通网络错 |
| `SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_GENERATION_MISMATCH` | 进入“HTTP null首请求→C++ begin”的 bootstrap，不把 cursor置空后普通 exchange |
| `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH` | strict校验后经`sync.record_transport_terminal`耐久fail closed并进入诊断；不解析、不拼接、不跨账号/设备重试；ack-only null-cursor分支不产生这些错误 |
| `SYNC_BOOTSTRAP_EXPIRED`、`SYNC_BOOTSTRAP_GENERATION_CHANGED` | 让C++丢弃未发布 staging后重新发 HTTP null首请求；live事实保持 |
| `DEVICE_LIMIT_REACHED` | Broker持久化 `registration_pending`但不开账号库；只开放 list→reauth→revoke→register恢复流，进程重启可继续 |
| `SYNC_NOT_ENABLED_FOR_ACCOUNT` | 清除pending adoption，保持guest active；不创建设备、账号DB/Outbox或重试sync，展示测试资格不可用 |
| `DEVICE_NOT_REGISTERED`、`DEVICE_NOT_FOUND` | 停止sync；只允许通过冻结的注册/恢复流程取得有效binding，禁止临时device id |
| `DEVICE_REVOKED` | 停止所有账号请求，立即执行token、key、cache与提醒自毁生命周期 |
| `DEVICE_VERSION_CONFLICT` | 重读当前设备版本并有界rebase仍有效的本机settings意图；不让server镜像覆盖本机owner |
| `SYNC_POLICY_VERSION_CONFLICT`、`LOCAL_SETTINGS_VERSION_CONFLICT` | 返回并重读current enabled/policy/local-settings revision，保留尚未提交的用户意图；本次不调整Work/reconcile、Registry owner或remote reporter，是否以新revision重试由用户/协调器明确决定 |
| `RETENTION_TRUSTED_TIME_REQUIRED` | force-local无同boot可信锚却请求retain；保留logout operation、writer gate、Session、cache与route，不自动重试或静默改为destroy，返回`allowed_cache_policies=[destroy_now]`供用户重选、取消或重试server logout |
| `DEVICE_REAUTH_REQUIRED`、`DEVICE_REAUTH_TARGET_MISMATCH` | 丢弃grant并要求重新验证；不复用密码/token，不自动重试撤销 |
| `WORKSPACE_NOT_FOUND`、`WORKSPACE_ACCOUNT_MISMATCH`、`WORKSPACE_LOCKED`、`WORKSPACE_KEY_UNAVAILABLE`、`WORKSPACE_SWITCH_CONFLICT` | fail closed；保持原可用route或锁定状态，绝不回退游客库执行原调用 |
| `NOTIFICATION_WORKSPACE_AMBIGUOUS` | legacy tap/action缺 workspace且不唯一，拒绝路由；不扫描各库按target猜测 |
| `NOTIFICATION_WORKSPACE_UNAVAILABLE` | payload显式 workspace当前不可见/不可解锁，拒绝路由；不改查active workspace |
| `SYNC_OUTBOX_CORRUPTED` | 停止上传并blocked，保留原库供诊断；不跳过坏mutation |
| `SYNC_ENTITY_SYNC_EFFECT_PENDING` | 透传为对象暂不可写，触发/等待同一effect group下载恢复；保留页面草稿，不绕过C++ gate |
| `SYNC_ENTITY_CONFLICT_BLOCKED` | 本地writer错误原样返回并引导权威冲突详情、保留草稿；若它来自合法upload逐项rejected，仍先exact acknowledge以消费旧sequence，再由用户通过新resolution mutation继续，不能当顶层transport错误重发 |
| `SYNC_FAILED_CHANGE_NOT_FOUND`、`SYNC_FAILED_CHANGE_VERSION_CONFLICT` | 重读本地失败列表/详情；不丢草稿、不把旧payload直接送HTTP。用户另存走全新业务mutation，discard只做本机overlay CAS |
| `SYNC_DIAGNOSTIC_EXPORT_FAILED` | 保持原同步/notice状态，删除半成品后允许用户重试；不显示路径或底层异常 |
| `SYNC_APPLY_FAILED` | 保留旧cursor与响应可重放条件，按冻结的 Native `retryable`分类；不得部分推进 |
| `SYNC_BOOTSTRAP_INCOMPLETE` | 保持live事实，恢复/重启同一bootstrap状态机；不发布半快照 |
| `IMPORT_SOURCE_CHANGED` | 停止原commit并要求重新preview；不混合两个source snapshot |
| `IMPORT_SOURCE_OWNED` | 保持guest/账号零新增写和网络零调用，原样投影可恢复业务态，提示切回持有opaque lease的原账号收尾；不得归unknown/global corruption或泄露owner identity |
| `IMPORT_SOURCE_EPOCH_EXHAUSTED` | 本次已发布epoch仍完成cleanup/lease释放/提醒切换；之后永久禁用该guest的新导入，仅保留本机数据能力，不回绕epoch |
| `IMPORT_LINEAGE_MISMATCH` | fail closed并保留guest/本地证据；不换lineage、不猜mapping或自动重试异identity请求 |
| `IMPORT_VERSION_CONFLICT` | 合并Backend返回的current stage/head/revision并重读`sync.import.status`，保留取消/cleanup用户意图；同终态收敛，其他情况以新revision明确重决策且本次零写 |
| `IMPORT_PUBLISH_INCOMPLETE` | 保留visible cursor和publish staging，按C++返回cursor重拉精确group或进入bootstrap；不得把server-confirmed直接发布 |
| `IMPORT_BATCH_ABANDONED`、`IMPORT_BATCH_SUPERSEDED`、`SYNC_IMPORT_CAPACITY_EXCEEDED` | 有seen range proof/receipt时按proof一次终结本地range并必要ack-only；absent-fence下的request-level迟到错误不消费sequence、不得伪ack，保留库补前序后重取proof，fresh destroy走transport-fenced never-visible恢复。旧handle按status/完整successor收敛；隐私销毁不绑网络成功 |
| `SYNC_CONFLICT_NOT_FOUND`、`SYNC_CONFLICT_ALREADY_RESOLVED` | 重读列表/详情，不重新提交旧resolution |
| `SYNC_CONFLICT_VERSION_MISMATCH` | 保留用户草稿并重新加载最新详情；不自动覆盖 |
| `AUTH_SESSION_EXPIRED`、`AUTH_REFRESH_TOKEN_REUSED` | 停止Sync chain，Broker进入冻结的reauth/termination路径；不盲目refresh |
| `AUTH_SESSION_ACCOUNT_MISMATCH` | 清除pending adoption/session，禁止开库并fail closed |
| `AUTH_REAUTH_FAILED` | 清除password与内部grant，返回用户可重试状态；不后台重放密码 |
| offline | 有pending投影offline-pending；等待CONNECTED，恢复网络开启新8次预算，不计热循环 |
| DNS、timeout、有限5xx、429 | 统一full-jitter基础退避，合法hint只提高delay；无hint仍退避，8次后retryable failed |
| TLS/hostname、无合法HTTP envelope | blocked/诊断；不降级或伪造业务错误 |
| reminder reconcile失败 | 同步事实保持已提交；记录本机待reconcile并排队重试，不向云端回写调度失败 |

WorkManager只承载应用层已计算的`next_retry_at`，不得再叠加另一套指数backoff；虚拟时钟测试必须证明full-jitter边界、8次预算、hint镜像校验和三种预算重置触发。

### 13.5 本地 maintenance

Workspace成功 open后做一次预算内 `sync.run_local_maintenance(max_items=500)`；另设不要求网络的低频 unique maintenance work，按精确 workspace逐批调用并在 `has_more`时有界续跑。安全裁剪水位完全由C++已持久化的 generation/cursor/retention floor决定，Kotlin不传本机“现在时间”冒充服务端时间、不在 `sync.get_status` 中偷偷清理。logout/revoke/close撤销对应 lease；强杀后重复调用只继续已提交小批，不能影响游客或隐藏账号以外的目标。

## 14. 本地写后的机会调度

新增统一的`SyncOpportunityHook`（内部名候选），只向`SyncWakePump`提交低成本唤醒请求，不直接enqueue且不参与业务事务。以下成功写路径都必须接入：

- Flutter触发的 Event/Recurrence/Occurrence/Anniversary/Habit/HabitCheckIn/Category/Reminder intent/Preferences写。
- Habit notification action、Ring完成/稍后提醒等无 Flutter入口的业务写。
- 冲突解决与首次数据导入产生 Outbox后。

规则：

- 仅账号 workspace且 sync enabled时机会入队；游客写不入同步链。
- C++是“是否产生Outbox”的真相源；Kotlin唤醒journal或ensure-scheduled失败不能回滚已成功的本地业务写，必须由恢复扫描补排。
- 重复hook全部调用`SyncWakePump`并通过耐久wake token有界合并；unique chain只负责串行顺序，不能被描述为去重，也不能为每个模块创建自己的Worker。
- Notification投递、Alarm scheduled/failed、recovery、search history等纯本机写不触发 Outbox；即使误触发 enqueue，C++也返回空 batch。
- `failed_local_change`本身不触发上传；用户在详情中编辑并保存后，只有新领域writer实际产生新Outbox才触发机会调度。discard永不调度网络。
- 现有 `MutationScheduleHook` 负责提醒 reconcile，不能被误当同步 hook；两者失败与重试语义分开。

## 15. Reminder、Alarm、Notification 与 workspace identity

### 15.1 拉取后 reconcile

`sync.apply_download_batch`、`sync.finalize_bootstrap`，以及`workspace.import_status/cleanup`中实际发布或退休事实的阶段成功返回affected reminder/entity ids后：

1. 验证 response的 workspace/runtime identity仍与 run lease一致。
2. 按当前设备 `receive_reminders` 与系统权限筛选本机执行资格；账号偏好只决定未来设备注册默认，不是运行时第二道开关。
3. 调用现有 C++ Reminder reconcile能力重新物化/查询调度队列；Kotlin不计算 recurrence。
4. 对精确 workspace更新 Alarm/Notification；系统能力不足只写本机降级状态，不产生云端 mutation。
5. reconcile失败排队 workspace-specific重试；同步 cursor和业务事实不回滚。

本地`sync.conflict.resolve`只返回`queued/resolving`，不承诺affected ids，也不触发reconcile；只有服务端接受后，其effect group或更高版本resolved delta经上述apply/finalize真正改变live事实时才返回affected ids。同步暂停不暂停Reminder；设备`receive_reminders=false`只取消该账号在本机的执行，不删除下载的reminder intent。workspace timezone和`default_reminder_methods`都只影响Event展示/以后新建草稿，不重排既有Reminder；只有OS device timezone变化才reconcile `follow_device`的Habit/Anniversary open Reminder。导入未`publish_applied`时所有设备都不可物化该未发布副本；publish-applied后，只有持有该guest source及cleanup责任的源设备在整条lineage cleanup-confirm completed前继续抑制account提醒并让guest唯一执行，其他账号设备立即按各自receive开关正常reconcile。源设备先由C++原子退休guest live图、以`source_migrated`终结非终态Reminder/prepared attempt并返回affected identities，Kotlin再取消精确Alarm/Notification/Ring/Recovery；终态审计不删、不改挂账号。随后独立HTTP cleanup-confirm→Native completed才解除account抑制；重复执行最终只留一份。

### 15.2 调度身份

- Alarm/PendingIntent identity使用包含 canonical `workspace_id + reminder/dispatcher identity` 的唯一 data URI/extra组合；request code不得作为唯一隔离手段或只用可能碰撞的短 hash。Work unique name与取消键同样绑定 workspace。
- 若继续使用“每workspace一个队首 dispatcher alarm”，游客与当前账号必须拥有不同 PendingIntent；Receiver从不可伪造/严格校验的 payload选择 runtime。
- Notification ID与 tap payload绑定 workspace，避免不同库相同实体ID碰撞；guest通知的可见 subtext/source label 使用本地化“本机”，account通知不显示该标签，TalkBack语义也必须区分。
- Habit `action_id` 的幂等语义保留，但 action payload额外绑定 workspace；Work唯一键也包含 workspace摘要。
- Ring session、snooze、complete与 recovery batch携带 workspace identity；旧广播缺失 identity时 fail closed或走冻结兼容迁移，不能使用 active workspace补全。
- logout只取消账号 Alarm/Notification/Ring，游客提醒继续；切换 UI workspace不等于取消游客提醒。

### 15.3 通知点击

当前 machine tap Contract仍缺少 workspace identity；云同步-02已冻结兼容迁移目标，必须等其 Schema/fixture与 Flutter-06消费路径同步落地后再实现。Android侧要求：

- PendingIntent中的 workspace identity与 notification创建时绑定，不能在点击时读取“当前 workspace”补齐。
- 点击先由 WorkspaceRuntimeRegistry验证目标仍存在且可路由，再向 Flutter发事件。
- 目标是 guest 时，无论账号当前是否 active，都发送显式目标事件并由 Flutter先激活 guest、重建根图再导航；目标是当前已认证且可解锁 account 时同理激活 account。绝不能在当前账号库查询游客ID。账号后台同步可以继续，不因 UI切到 guest而取消。
- legacy payload缺 identity且 registry无法证明唯一时返回 `NOTIFICATION_WORKSPACE_AMBIGUOUS`；显式账号已退出、已撤销、非当前认证或不可解锁时返回 `NOTIFICATION_WORKSPACE_UNAVAILABLE`。两者都不得因缓存仍在30天而重开账号库或跨库搜索。
- payload过期、workspace/object不存在时保持在已安全激活的目标空间首页并返回可读 stale结果；只有 workspace路由成功后才允许检查对象存在性。
- tap/opened Event不携带目录、账号明文或任何同步 payload。

### 15.4 崩溃补偿

必须覆盖“C++已提交下载、进程在 Kotlin reconcile前死亡”。恢复机制由同一 workspace的重试 run、App start、Boot/Package replaced和完整 reconcile共同修复；测试必须证明最终只安排一次通知。不能依赖一次内存回调作为唯一触发。

## 16. 退出、撤销与 30 天缓存清理

### 16.1 正常退出

Flutter只发起/确认动作和展示Kotlin返回的稳定风险快照，不能在logout之外先跑一次sync再用易漂移计数决定：

1. active首次调用`auth.session.logout(mode=server_then_local, final_sync_policy=attempt_once)`，携带expected session generation与observed active route tuple。Broker从session binding解析唯一账号目标，原子建立`logout_operation_id`与lifecycle writer gate，再以`run_intent=logout_final`加入该账号同一链；即使前台route为local或账号sync-disabled也只覆盖这一轮且不改持久策略。
2. final sync失败，或收尾后仍有pending upload、failed-local、非终态import/destroy风险时，Broker在gate仍生效的状态下返回`review_required + logout_operation_id + logout_risk_revision + exact counts/import disposition`。前台local统计绝不能替代它。Flutter可用同operation重试attempt-once，或调用`cancel_after_review`原子释放lane；不得只关闭页面而让gate永久悬挂。
3. 用户确认跳过只调用同operation/revision的`final_sync_policy=skip_after_confirmation`，且`mode`仍为`server_then_local`；revision/identity变化即返回review conflict，不用旧确认。它只跳过final sync，仍必须调用服务端logout。服务端`succeeded/already_invalid`后才进入本地termination，并把该operation首次接纳的`server_time`原子固化为保留锚；响应重放、重启或后续时间查询不得改写这个起点。
4. 服务端不可达时记录并返回同operation的`server_logout_status=unreachable/session_terminated=false`，会话、缓存、gate和原route保持。Broker同时返回当下`allowed_cache_policies`：同boot锚可验证时为`[retain_30d,destroy_now]`，否则为`[destroy_now]`。Flutter可重试server-then-local、cancel，或另一次二次确认后用同operation`mode=force_local`；force-local只做本地终止且明确server未确认，不能与skip混为一个按钮。若旧页面提交当前不允许的retain，先返回`RETENTION_TRUSTED_TIME_REQUIRED`，不得终止session或改缓存。
5. 进入termination后禁止新账号业务调用、取消账号Sync/Settings work、关闭runtime、清凭据并取消账号提醒。`retain_30d`使账号DB与wrapping材料完全不可见并记录固定期限；`destroy_now`先对非终态import best-effort独立HTTP abandon，再密码学销毁且不等待网络，并留下future`transport_fence_required`。verified registration-pending可按可信binding处理旧cache，unverified pending-adoption只能not-applicable。最终返回session/server/cache/abandon/cleanup/lifecycle结果：原route为账号时切到local并推进revision；原route已是local时保持同一local route，不close/清理local。

离线 logout失败与“强制本地退出”必须是两个可测试结果；不能静默把服务器会话已注销与本地已退出混为一谈。

### 16.2 设备撤销

- 撤销其他设备：先通过 `auth.session.reauthenticate`取得一次性内部 grant，再调用 `device.revoke`；V1不允许通过该入口撤销当前设备。
- 当前设备在任一 authenticated响应收到 `DEVICE_REVOKED`：用 compare-and-set确保自毁只执行一次；取消网络、清 token/reauth、关闭 runtime、清 DEK、销毁 key/cache、取消账号提醒，再激活游客。
- 离线时无法主动知道撤销；下次联网第一条响应触发。不得继续处理同一个响应中的任何 change或 upload receipt。

### 16.3 30 天清理

- 在线`server_then_local`只使用Backend logout终态的UTC `server_time`建立不可变`retention_started_at`与`retained_until=server_time+30d`。force-local只有在`BootEpochProvider`确认仍是同一boot且已有可信server anchor时，才可用`server_time_anchor + elapsed delta`建立期限；否则retain选项不可用，绝不落`retained + null deadline`。任何重启、重登或wall-clock变化都不得重算/延长已建立的deadline。
- `BootEpochProvider`是Application级唯一owner。API 24+以`Settings.Global.BOOT_COUNT`检测boot，产生canonical lowercase UUIDv4 `boot_id`；`BootEpochRecord`字段类型固定为positive Int schema、`global_boot_count/process_only`枚举、global分支nonnegative Int boot count、UUID字符串和nonnegative Long elapsed毫秒。记录使用Keystore-AEAD `AtomicFile`保存到`noBackupFilesDir`，AAD绑定installation/schema，并由backup与device-transfer规则明确排除；每次可信读取都原子更新不下降的elapsed值。
- API 24+进程重启仅在installation/AAD合法、boot count相同且当前`SystemClock.elapsedRealtime()`不小于记录值时复用boot id；系统重启导致boot count变化并生成新UUID。Boot receiver只触发同一Provider重验，不能自行发明第二标识。API 23及以下或BOOT_COUNT不可读时只信任当前进程内boot token，进程重启后旧token不可复用。
- Boot记录缺失/损坏、boot count或elapsed倒退、installation变化、同UUID对应不同boot count、读取异常或新UUID重复时fail closed：将既有期限标`untrusted`，elapsed不能授权销毁；备份恢复得到的错绑记录同样拒绝。此时只能用受限、无账号数据、no-store的Backend `GET /api/v1/system/time`合法HTTPS响应评估已经存在的deadline，不能倒推出新起点。普通wall clock只可作为Work唤醒提示，前拨/回拨都不能单独授权删除。
- App启动扫描与低频cleanup work调用同一清理器；WorkManager只提供执行机会，不保证第30天整点运行。已建立deadline但clock untrusted时缓存继续hidden且Flutter不可见，并允许用户立即销毁；可信时间达到deadline后，首次系统允许机会先crypto-destroy key并原子记`deleting`，文件/WAL/SHM可随后重试清理。
- 即使仍有未上传Outbox，可信期限越过后仍销毁；风险必须已在退出确认展示，清理器不得把失败或无网络解释为重新起算。物理文件删除晚于key销毁不构成可恢复缓存，但必须保持deleting且不可重新显示。
- `workspace.clear_account_cache` 复用同一清理器但不等待到期。
- 可信到期/完整destroy后的再次登录按新注册结果处理：fresh C++ policy明确回到`sync_enabled=true/revision=0`，Android`receive_reminders`只从本次register响应一次性播种，并由Flutter提前说明；retain期限内重登与active“立即清缓存”分别保留原owner值，后者按§16.4原地重建。同active device先恢复/执行持久`sync.device_fence`，fresh DB严格使用其transport generation + highest/nullable-next/client-confirmed/exhausted bundle并先bootstrap；revoked device取新id且generation从0开始，绝不从1碰撞或复活旧记录。

### 16.4 Active账号“立即清缓存”重建

该动作不退出session，且只在在线preflight成功后允许发生不可逆删除：

1. 以Broker解析的session-bound account workspace、`expected_session_generation`、调用方观察到的active route tuple/lifecycle revision和用户二次确认CAS进入blocking；前台可为account或local，但只阻写账号runtime，绝不阻断/清理local。确认内容必须包含pending upload、failed-local与非终态import风险。先把settings/import/clear journal复制到账号DB外的Keystore-AEAD lifecycle store，再取消新的账号业务入队。
2. 在旧transport generation内排空唯一sync/settings lane：普通Outbox必须得到terminal并完成effect apply，尾部ack-only必须被Backend接受；settings remote-pending必须完成或以可恢复journal冻结。prepublish import必须在线status/abandon，存在gap时先终结更早Outbox再重复abandon，直到seen-range proof被Native接纳且必要ack-only完成；拿不到proof/发生Auth、网络或Contract错误则退出blocking、恢复原lane并零删除。已server-confirmed/published或cleanup-pending的import可不强行回滚，但必须把source workspace/epoch/lineage/head/publish/cleanup/lease recovery handle完整冻结，账号提醒保持suppressed，供第5步恢复。
3. 全部旧generation lane静止后，以同一`clear_operation_id`调用`sync.device_fence(expected=current generation, reason=clear_rebuild)`。Backend等待任何更早事务并返回new generation、最终sequence bundle、resolved absent-import proofs；Kotlin先把exact receipt持久化，再调用`sync.accept_transport_fence`。response-loss只重放同operation。Auth/网络/generation耗尽、proof或Native接纳失败均零删除并按journal恢复；只有receipt+Native都提交才到不可逆线，此后任何旧HTTP响应都因binding不符被丢弃。
4. 不可逆前把C++权威sync-enabled/policy revision与Registry权威receive-reminders/settings-pending/local revision、reporter desired/expected device version、import recovery handle及fence receipt冻结为operation-bound seed，以`workspace_id + device_id + session_generation + clear_operation_id + resulting_transport_generation`作AAD。随后取消账号提醒、close runtime、持久化deleting阶段，先销毁旧key再删DB/WAL/SHM；从此失败绝不重新发布旧库。保留session/account/device Registry，生成新DEK，以同一fence transport/sequence bundle和policy seed fresh-open；C++ consumed receipt必须逐字段匹配，不能再调用register取值覆盖fence。
5. 用仅由该clear operation授权的`clear_rebuild_bootstrap`执行§13.3完整bootstrap，绝不prepare/upload普通Outbox。bootstrap finalize后仍不开放writer/account提醒：先以guest current/cleanup-receipt epoch恢复`sync.import.status`及source lease。已published必须由bootstrap marker或后续publish group形成`publish_applied`，再执行guest compare-retire→按affected identities取消平台执行→HTTP cleanup-confirm→Native completed/finalize lease；prepublish必须接纳seen或该fence返回的never-visible proof并完成残留终态；account-deleted proof走其专用终结分支。随后用new generation完成必要ack-only、恢复Registry owner/settings reporter，确认sequence/import/lease均安全后才删除外部seed、开放writer并按receive-reminders reconcile；原sync-disabled回paused。任一步网络/storage失败保持`rebuilding/blocked`并从journal继续，guest数据/提醒不受影响。
6. `DEVICE_REVOKED`、`AUTH_REFRESH_TOKEN_REUSED`、`AUTH_SESSION_ACCOUNT_MISMATCH`、account-deleted等可信安全终态在preflight、fence、destroy、open、bootstrap或import恢复任一点都优先抢占clear：终止session、销毁外部seed/新旧key/cache并切到/保持local route，绝不继续发布空账号库。session generation变化也使旧clear operation terminal-invalid并销毁seed；安全终态可为隐私立即销毁而跳过在线fence，但必须留下future fence-required（device/account已永久终止者可由权威终态关闭）。

## 17. 实施阶段

本节只排序第 5–16 节的实现，不重新定义其状态机：

| 阶段 | 工作锚点 | 主要产物 | 退出证据 |
| --- | --- | --- | --- |
| K0 Contract/ADR/spike | §3–§4 | 冻结 Schema/mapping/fixture、Workspace/Encryption/Session/Sync/HTTP/Backup ADR、SQLCipher 三 ABI 与 JCS 转发 spike | 无影响状态、参数、错误、key 或路由的未决项 |
| K1 Workspace 基座 | §5、§8–§10 | Application owner、Registry/runtime、no-backup identity/规则、profile bridge、key lifecycle 和 workspace-local Android state | guest/account 并行，A/B/close/wrong-key 全部 fail closed |
| K2 Broker | §6.1、§11、§16.1–§16.3 | strict HTTP 基座、adopt/register/pending、refresh/reauth/logout、旧凭据迁移与 termination | 100 并发取 token 仅一次 refresh，crash/logout 竞态通过 |
| K3 Device/transport | §6、§12 | device API、settings reporter、fence journal、retry/TLS、Debug/Release Manifest | Backend golden 往返一致，Release 网络边界不可绕过 |
| K4 JNI/Sync chain | §7、§13–§14 | 窄 JNI、唯一 Work chain、耐久有界wake合并、exchange/ack/apply/bootstrap、failed overlay、notice/diagnostic/maintenance | response-loss、10k触发/重复Worker、强杀和网络切换不重复mutation、不跳cursor、不并发refresh，unfinished节点≤2 |
| K5 Reminder/lifecycle | §15–§16 | workspace identity、权威 apply 后 reconcile、import 提醒切换、logout/revoke/retention/clear-rebuild | guest 提醒持续；账号终止只清目标账号；A→B 无可见残留 |
| K6 验证/交接 | §18–§20 | JVM/lint/build/instrumentation、三 ABI、真实 C++ JNI 单设备 smoke、Contract hash 与 M6 待验清单 | 只标记 `LAYER COMPLETE / AWAITING INTEGRATION`，双设备端到端仍由 M6 签署 |

## 18. 测试矩阵

### 18.1 自动化套件与规则追踪

每个套件都消费 Contracts-02 §13 对应 `FX-*`。期望 wire/domain 结果取自 fixture 的 `rule_anchor`；本节只补 Kotlin、Android、JNI 和系统生命周期的可观察证据。

| 套件 | 实现锚点 | Contract fixture | Android 特有证据 |
| --- | --- | --- | --- |
| Contract / DTO | §6–§8 | `FX-TARGET`、`FX-CANONICAL`、`FX-COUNTER`、`FX-CROSS-LAYER` | 每个 Method/Native call strict parse、两个 envelope 隔离、状态/事件 revision、unknown fail closed、`sync.apply` 与 R3 方法不存在性 |
| Broker / Keystore | §10–§11 | `FX-SESSION-DEVICE` | 100 并发 single-flight、提前 401 一次重放、rotation 与旧记录迁移每个文件/Keystore/强杀点、active/pending logout、key/error/secret 隔离 |
| Workspace / JNI | §5、§9–§10 | `FX-WORKSPACE`、`FX-IMPORT-STAGE`、`FX-IMPORT-CLEANUP` | guest/A/B 路径和 route CAS、session×route 正交、runtime close/迟到、binary key、backup/transfer 排除、SQLCipher 文件检查、真实 C++ 调用 |
| HTTP / fence | §12–§13 | `FX-SEQUENCE`、`FX-RUN`、`FX-CURSOR` | strict HTTP/TLS/body/cancel/retry、transport terminal 耐久化、旧请求与 fence 仲裁、prepared/apply union、ack-only 与 confirmed-through 原样转发 |
| Work opportunity | §13–§14 | `FX-RUN`、`FX-MAINTENANCE` | 所有触发源经同一Pump进入`APPEND_OR_REPLACE`链；10,000次并发/批量导入触发下unfinished节点始终≤2，静默后最多一个空successor；覆盖最后空检查→新写、journal/enqueue两侧强杀、查询失败、retry/failed/cancelled前驱和尾部dirty continuation |
| Bootstrap / conflict | §13.2–§13.5 | `FX-BOOTSTRAP`、`FX-CONFLICT`、`FX-FAILED-LOCAL` | null 首请求、page/apply/finalize 强杀点、全部 unresolved conflict、duplicate/failed overlay、notice claim、A/B resolved 收敛和 apply 后 reconcile |
| Import orchestration | §13、§16.4 | 全部 `FX-IMPORT-*` | status→HTTP range close→Native proof→ack-only→successor、server-confirmed/publish-applied 分离、proof 错绑拒绝、cleanup/lease 和 clear-rebuild 每点可重入 |
| Reminder / notification | §15 | `FX-PREFERENCE`、`FX-RETENTION-NOTIFY` | workspace 唯一键、guest 持续运行、tap 安全激活、source_migrated 切换、只对权威 apply/OS timezone/import 触发 reconcile，权限失败不回写云端 |
| Lifecycle / local privacy | §16 | `FX-SESSION-DEVICE`、`FX-RETENTION-NOTIFY`、`FX-MAINTENANCE` | logout/revoke/30天可信时间/active clear-rebuild、无锚force-local destroy-only且retain零副作用拒绝、API24+与API23 boot epoch/进程重启/系统重启/备份恢复fail-closed、Search History guest/A/B隔离、system.time不改deadline、A→B无残留 |

### 18.2 ADB 与真机

- [ ] force-stop / process kill / reboot / package replaced后 session、runtime、sync与提醒恢复符合状态机。
- [ ] 飞行模式、Wi-Fi↔蜂窝、断网恢复、Data Saver、Doze/App Standby与后台限制。
- [ ] 通知权限拒绝、精确闹钟不可用、系统时间/时区变化。
- [ ] `dumpsys jobscheduler` / WorkManager诊断中每账号只有一条同步链、unfinished one-time节点≤2且无敏感input；连续高频写入静默后最多执行一个空successor。`dumpsys alarm`中workspace调度互不覆盖。
- [ ] 一台设备撤销另一台后，被撤销设备下次联网立即停止并清理；离线期间不假装已远程擦除。
- [ ] 两台真机验证A写B拉、同字段冲突、Habit增量去重、退出待上传与cursor bootstrap。

## 19. 构建与完成门禁

至少实际运行并保存结果：

```text
cd flutter_client/android
gradlew.bat :app:testDebugUnitTest
gradlew.bat :app:lintDebug
gradlew.bat :app:assembleDebug
gradlew.bat :app:connectedDebugAndroidTest
```

三 ABI 与 Flutter组合构建：

```text
cd flutter_client
flutter build apk --debug --target-platform android-arm,android-arm64,android-x64
```

Release/公网验收在安全注入签名和显式 base URL的 CI/受控环境执行：

```text
cd flutter_client/android
gradlew.bat :app:verifyReleaseApkSigning
```

还必须把真实 `arm64-v8a`、`armeabi-v7a`、`x86_64` APK/设备加载结果、merged manifest、HTTPS握手、JNI/SQLCipher instrumentation与 ADB矩阵作为证据。仅编译一个 host C++ target不能代替三 ABI。

本层完成必须同时满足：

- [ ] K0–K6 退出条件满足，全部公开调用与事件只使用冻结 Contract；Broker、Registry、Sync chain、settings reporter 和 lifecycle owner 均唯一。
- [ ] 第 18 节自动化与真机矩阵通过，覆盖加密/三 ABI、fence/ack/apply/bootstrap/import 恢复、workspace-aware reminder/tap 和 A→B 隔离。
- [ ] 上述构建、lint、instrumentation、merged manifest、HTTPS 和 Release 网络门禁均有实际证据；未执行项标记 `UNVERIFIED`。
- [ ] 第 20 节交接双方签收同一 Contract hash 与映射，production composition 不含 Fake、旧 RT owner 或默认 guest fallback。
- [ ] 状态只标记 `LAYER COMPLETE / AWAITING INTEGRATION`；真实 Backend/Flutter 双设备验收仍由总计划 M6 完成。

## 20. 跨计划交接

交接只登记边界输入与证据，不复制方法或状态定义：

| 协作方 | Kotlin 接收 | Kotlin 回报 |
| --- | --- | --- |
| Contracts-02 | §8 全部 Schema/error/retry/capability、identity/cache/profile/notification 定义、binary-key 与 sensitive 规则、fixture manifest、validator 和 revision/hash | 第 6–8 节每个 Handler→Coordinator→HTTP/JNI 唯一路径及 Contract 测试 |
| C++-03 | 多 runtime/close、SQLite v6/encrypted open、32-byte binary key、§7 Native calls、affected identities、guest 零 Outbox/account binding/migration 证据 | 三 ABI JNI、并发/强杀/error mapping 和 workspace route 证据 |
| Backend-04 | Auth/Device/Sync/Bootstrap/Conflict 端点、device-fence/sequence/effect receipt、refresh/reauth/revoke/pending 语义、HTTPS 与故障测试入口 | strict DTO/request mapping、TLS/retry/cancel 和无敏感日志证据 |
| Flutter-06 | 第 6 节方法与第 8 节事件的同包切换；移除 Dart RT owner/直接 Sync HTTP；route graph、notification tap、session-bound logout UX | 不暴露 RT/reauth token/cursor/path/alias/key；所有异步结果带 identity/revision |

## 21. 风险清单

| 风险 | 后果 | 计划控制 |
| --- | --- | --- |
| 单一全局 C++ runtime继续存在 | UI、Worker、游客提醒并发串库 | K0阻塞；C++ handle registry或经证明的等价模型 |
| RT双 owner | 并发旋转导致整个 token family撤销 | Broker同包切换、100并发与crash测试 |
| key放入JSON/String | 日志、heap、错误消息泄露 | 独立 JNI ByteArray、finally清零、敏感扫描 |
| SQLCipher与vendored SQLite同时链接 | 重复符号/运行时不确定实现 | 加密spike统一唯一 sqlite provider，三 ABI链接审计 |
| Activity销毁关闭进程级 runtime | 后台 Worker/提醒随机失败 | Application owner + runtime lease |
| 计划文字已修正但机器 Contract未同步 | 各层仍按旧可见性/adopt/profile形状实现 | K0逐项校验 Schema、fixture、YAML和validator hash后才开工 |
| 固定 Alarm/Work key | 游客与账号互相覆盖 | workspace-aware identity与双runtime真机测试 |
| apply后reconcile前强杀 | 提醒延迟或重复 | 幂等apply重放 + 启动/Boot完整reconcile补偿 |
| 两套退避 | 延迟指数膨胀或重试风暴 | SyncCoordinator成为唯一最终调度者 |
| 把`APPEND_OR_REPLACE`误当去重 | 高频写形成长串空Worker并放大后台耗电 | SyncWakePump耐久token合并、unfinished≤2硬门禁及10k触发测试 |
| Release沿用 `10.0.2.2` HTTP | 生产明文或不可用 | 构建时显式URL、merged manifest与真实TLS门禁 |
| 退出清理顺序错误 | 缓存可恢复泄露或误删游客 | 可恢复deleting状态、先密码学销毁、canonical path测试 |
| Kotlin重建 mutation/change JSON | 字段/hash漂移、幂等失效 | 冻结 DTO/原样 payload与跨层 golden round-trip |

## 22. 本计划之外

- 不在 Kotlin实现 Event、Recurrence、Habit、Reminder等领域合并规则。
- 不在 Kotlin写 SQLite业务表、Outbox、Cursor、Conflict或import图。
- 不新增 FCM、常驻服务、服务端提醒、附件、AI、分享、微信或协作同步。
- 不修改 Contracts、C++、Backend或Flutter代码来绕过本层缺口；发现协议问题回到对应计划。
- 不擅自升级 Android Gradle、Kotlin、NDK、HTTP、SQLCipher或序列化依赖；必要升级单独审批和验证。
- 不把 JVM Fake、Mock Backend、Debug HTTP或单ABI编译作为生产集成完成证据。
