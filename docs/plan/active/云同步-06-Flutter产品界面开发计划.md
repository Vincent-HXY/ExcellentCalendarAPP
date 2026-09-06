# 云同步-06：Flutter 产品界面开发计划

> 状态：ACTIVE PLAN / CONTRACT FROZEN / IMPLEMENTATION NOT STARTED
> 建立时间：2026-09-04
> 上位统筹：[云同步-01：Local-first 多设备同步开发计划](./云同步-01-Local-first多设备同步开发计划.md)
> 协议基线：[云同步-02：Contracts 与数据模型开发计划](./云同步-02-Contracts与数据模型开发计划.md)
> 负责范围：`flutter_client/lib/**`、`flutter_client/test/**`、必要的 `flutter_client/integration_test/**`
> 不负责：Kotlin/Android、JNI、C++ Core、SQLite、Backend、Contract 机器文件的实现或修改
> 文内语义锚点：第 5–13 节定义 Flutter 架构、状态与交互；第 14–18 节只登记实施、测试和交接证据，不得重新解释 Contract 或原生生命周期。

> 协议输入锁：`contracts/sync/sync_v1_revision_lock.json` 中的 `06_flutter` 与其他三端锁定同一 revision/hash/fixture manifest。只在 `contracts/run_sync_v1_validation.py` 默认入口通过后按该机器版本实施；本层生产 implementation/release status 仍为 planned。

## 1. 目标与完成口径

本计划负责把云同步-01 已规定的产品要求，以及云同步-02 待冻结的 Contract，投影为 Flutter 侧可使用、可测试、可恢复且不泄露跨账号数据的用户流程。主要交付包括：

- 游客本机空间的完整入口，以及账号 workspace 的登录、注册、启动恢复和切换流程。
- Kotlin `SessionCredentialBroker` 单一 Refresh Token owner 下的 Flutter 认证接线。
- “我的 → 数据与同步”、本机数据迁移、冲突管理、设备管理、提醒同步策略、缓存清理和退出确认。
- 严格 Dart DTO、窄 Gateway、MethodChannel Adapter、Application Controller 和不可变 UI State。
- workspace-aware 的根 UI graph、路由、通知点击、恢复状态、个性化和页面内存隔离。

本计划的完成不等于云同步完成。Flutter 以 Contract fixture 和测试 Fake 完成独立验证后，最高只能标记为 `Layer Complete / Awaiting Integration`；只有在真实 Kotlin、JNI、C++ SQLite v6、Backend 和至少两台真机上完成总计划的端到端矩阵，整体能力才可进入 `integrated + active`。

## 2. 上位原则和 Flutter 边界

冲突裁决统一引用云同步-01 §1.1：判断当前行为时按 active machine Contract/Schema → 当前领域不变量 → Accepted ADR → active 计划 → 架构 → 实现；本次目标如改变前三者，必须先修订 ADR、领域文档、Contract 与迁移。云同步-02 在 `CONTRACT FROZEN` 前只是协调草案，不能用 planned/blocked Schema 覆盖现有 active 行为；冻结后机器 Contract 才是 Flutter DTO/Adapter 的直接接口真相源。发现冲突时回流 01–06，不在 Dart 中兼容两套字段、枚举或默认值。

### 2.1 必须继承的规则

1. SQLite 是客户端离线业务真相源；Flutter 不直接读写 SQLite，也不以页面状态代替 Core 状态。
2. 游客 workspace 和账号 workspace 物理隔离；游客数据永不上传。
3. Flutter 不生成 Outbox、`client_sequence`、`entity_version`、`server_sequence` 或 cursor，也不维护第二份待上传计数。
4. 字段合并、delete-vs-edit、Habit 增量去重和 recurrence revision 处理不在 Flutter 实现。
5. Flutter 只通过 Gateway 消费 `NativeResult<T>` 或已校准 Backend Auth/Profile 的 `ApiResult<T>`，两种 envelope 不混用。
6. 同步状态、设备顺序和冲突顺序来自权威响应；Flutter 不用本机时间重新裁决。
7. 提醒只展示同步的用户意图和每设备开关，不上传或展示为云端事实的 Alarm、Notification、权限、铃声 URI 和投递历史。
8. V1 没有 FCM；页面不宣称 App 关闭后能分钟级实时同步。
9. 不为方便 UI 增加任意 Map、自由文本错误、未声明枚举或临时 MethodChannel 方法。

### 2.2 Flutter 只负责的事情

- 用户流程编排、页面状态、表单校验、单飞提交、重试入口、路由与可访问性。
- 将严格 DTO 投影为 UI ViewData，根据稳定错误码选择安全的用户文案。
- 在 workspace/session 世代变化时废弃过期异步结果并重建所有业务 UI 状态。
- 向 Kotlin 唯一协调器发出“运行一次”、“切换 workspace”、“解决冲突”等用户意图，不自己实现底层流程。

### 2.3 Flutter 明确不负责

- `sync.prepare_upload_batch`、`sync.acknowledge_upload`、`sync.apply_download_batch`、bootstrap 分页和 cursor 推进。
- HTTP sync exchange、WorkManager、网络恢复监听、指数退避和 jitter。
- workspace 目录、数据库密钥、加密、数据库打开/关闭和跨库 ID 重映射。
- 通知调度、提醒 reconcile、设备撤销后物理清理和 token 轮换。

## 3. 当前基线与差距证据

| 项目 | 当前事实 | V1 必需变化 |
| --- | --- | --- |
| Sync 运行时 | `contracts/method_channels.yaml` 只有无实现的 `sync.apply`；`flutter_client/lib` 中无 Sync Gateway/DTO/Controller/页面 | 新建严格分层；不为 `sync.apply` 补实现 |
| 启动入口 | `startup_auth_check_use_case.dart` 把无 token 导向登录，把断网 refresh 导向恢复失败 | 无账号直接安全打开游客 workspace；已登录账号按 Session/Workspace ADR 支持本地离线进入 |
| 登录后流程 | `login_page.dart` 和注册验证成功后直接 `goToHome()` | 先 `auth.session.adopt`（Kotlin 内部完成 identity 校验/设备注册/binding），再准备/激活账号 workspace 并完成首次导入决策 |
| Refresh owner | `main.dart` 组合 Dart `TokenRefreshCoordinator` 和原始 Refresh Token store/read | 迁移为 Kotlin `SessionCredentialBroker` 单 owner；Flutter 不再读回 Refresh Token |
| “我的” | `main.dart` 把 `ProfilePage` 直接作为第四 Tab | 改为游客/账号均可用的 My 首页，个人资料变为账号入口 |
| 内存隔离 | `main.dart` 长期持有 Calendar/Search/Appearance/Notification 等 Controller；`MainTabPage` 使用 `IndexedStack` 保留子树 | workspace 切换必须销毁整个 workspace-bound graph，不仅刷新当前页 |
| Profile cache | `user_profile_file_cache.dart` 在普通临时目录使用单一 `cached_current_user_v1.json`，不按账号分区 | 账号生产路径改读 C++ `account_profile_cache`，Flutter 只调用 `profile.get_cached` / `profile.accept_server_snapshot`；不得在换号时读到旧账号 |
| Appearance | `appearance.get_local` / `appearance.update_local` 是 active Kotlin-local 能力，页面明示不同步 | 保持旧方法语义，新 V1 使用 `preferences.get` / `preferences.update` 实现 workspace-aware 白名单 |
| locale/timezone | `app_localization.dart` 固定 `zh-CN`；Calendar/Search/Habit 组合只读设备 timezone | V1 locale 保持不可写常量；建立 workspace timezone 与 OS device timezone 双轴，不把二者合并 |
| 通知点击 | `NotificationTapPayloadDto` 和 `NotificationTapRouter` 只按 `target_id` 导航，无 workspace identity | 先验证/激活 payload 所属 workspace，再打开详情；不得在当前账号库猜测查询 |
| 网络配置 | `BackendApiConfig` 所有构建默认 `http://10.0.2.2:8080` | 如 Auth/Profile 仍用 Dart Dio，Release/公网包同样必须显式 URL + HTTPS fail-closed |
| 个性化 DTO | `UserSettingsDto` 是开放标量 Map，reminder methods 仍接受 `wechat` | 消费 02 冻结的 typed 白名单；V1 界面不激活 wechat |
| 测试基座 | 已有 DTO、Dio、Auth/Session、Router、Profile、Composition 和 Widget Fake 测试；默认使用 `ChangeNotifier + ListenableBuilder` | 继续现有模式；未经明确批准不新增状态管理依赖 |

现有代码的存在只是迁移输入，不能证明同步页面、隔离或后台协调已经完成。

## 4. 开发前置与可行性闸门

Flutter 业务实现必须等待云同步-02 达到 `CONTRACT FROZEN`，并完成以下输入确认：

- [ ] Workspace Lifecycle ADR 明确游客/账号打开、切换、锁定、退出、撤销、30 天清理和通知路由语义。
- [ ] SessionCredentialBroker ADR 明确 adopt、Access Token 获取/401 处理、旋转崩溃窗、logout 和 clear-local 的唯一终止路径。
- [ ] 账号 SQLite 加密 spike 通过；否则不开放“保留账号缓存”、离线账号 workspace 或与之相关的完成声明。
- [ ] `contracts/method_channels.yaml`、所有 request/response Schema、`enums.yaml`、`error_codes.yaml` 和 Sync fixtures 已冻结且 validator 实际通过。
- [ ] 旧 `auth.refresh_token.*` 的兼容窗口已决定；任何兼容 adapter 都不能让 Dart 恢复为第二 Refresh owner。
- [ ] 登录后设备注册闭环已明确。02 §8.2 有意不暴露 Flutter `device.register`；Kotlin 必须把 Backend `device.register` 作为 `auth.session.adopt` 内部、identity 交叉校验后且账号 workspace ready 前的固定步骤，Flutter 不得自创新方法或直连 Sync Device API。
- [ ] `auth.session.get_access_token` 对“服务端已拒绝但本地尚未过期的 Access Token”如何触发 Broker 单飞刷新已在 request/错误语义中闭合；Flutter 不用伪造 `minimum_validity_seconds` 绕过。
- [ ] Notification tap Contract 已增加足以安全定位 workspace 的稳定身份，并定义锁定账号、游客空间和过期通知的失败行为。
- [ ] `user_preferences` 的四项精确白名单 `timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 `ring`、`popup`）、`auto_enable_reminders_on_other_devices`，以及 locale 仅兼容读、timezone 双轴、默认提醒适用矩阵、revision 和更新所有者已冻结。
- [ ] download-only `account_profile`、C++ `account_profile_cache`、现有资料 API 的 revision 响应，以及 `profile.get_cached` / `profile.accept_server_snapshot` 的 exact Schema、freshness 和 not-applicable 语义已冻结。

上述任一条会改变 wire shape 或安全边界时，本计划对应部分保持 `DECISION REQUIRED`；可继续页面结构设计和基于正式 fixture 的测试，不得接入运行时 Fake。

## 5. 目标架构

### 5.1 根级 Session / Workspace 链路

```text
AppStartupHost
  → SessionWorkspaceController
      → SessionCredentialGateway
          → auth.session.get_status / auth.session.get_access_token
      → WorkspaceGateway
          → workspace.state_changed 订阅
          → workspace.get_state / workspace.list / workspace.activate
      → WorkspaceBoundAppGraph(key = workspace identity + runtime instance + active-route revision)
          → Calendar / Search / Habit / Anniversary / Appearance / Profile / Notification UI
```

根协调器只保留身份、阶段和错误投影，不缓存业务列表。每次workspace identity、`runtime_instance_id`或Registry权威`active_route_revision`变化时：

1. 立即遮罩旧业务页，禁止新写入。
2. 取消Flutter侧订阅和页面计时器，把本地`workspaceEpoch`推进为该active-route revision的派生generation（不作为wire/owner）。
3. 等待 `workspace.activate` 成功和新 `workspace.get_state` 确认。
4. 丢弃所有 epoch 不匹配的迟到 Future/Event 结果。
5. 销毁并重建 `IndexedStack` 及其 Calendar、Search、Profile、表单草稿、头像和通知导航状态。

不允许只调用各 Controller 的 `refresh()` 来代替 UI graph 重建，因为 `IndexedStack`、Navigator/restoration、搜索输入、分页 cursor 和正在编辑的表单都可能持有旧 workspace 数据。

### 5.2 同步状态链路

```text
sync.status_changed
  → MethodChannel/Event adapter 严格解析
  → SyncStatusController 按 identity + revision 去重
  → SyncStatusViewData
  → “我的”红点 / 数据与同步页 / 一次性冲突提示
```

Flutter先订阅`sync.status_changed`，再调用`sync.get_status`，只接纳当前`(workspace_id,runtime_instance_id,active_route_revision)`且Kotlin-owned `status_revision`更新的状态。EventChannel可丢失、重复，因此页面恢复、App resume和identity异常时都以get-status重建；同步开关CAS另使用`sync_policy_revision`。

### 5.3 交互与后台的边界

- 手动同步只调用 `sync.run_now`，消费`run_id + disposition(queued/already_running) + status_revision`后由状态事件更新页面。
- App 回到前台时，只有当前状态表明账号 workspace ready、同步启用且具备绑定设备时才机会调用同一 `sync.run_now`；依赖 Kotlin 唯一队列合并，不另起 Dart 定时器或 HTTP 任务，游客/暂停/blocked 不伪造成功。
- 网络恢复、WorkManager、退避和 Data Saver 归 Kotlin；Flutter 不新增 connectivity/WorkManager 依赖。
- 页面从 `sync.get_status` 读待上传数，不根据按钮点击或本地 writer 次数推测。

## 6. Flutter 分层与建议代码结构

### 6.1 Presentation

建议新建或重构：

```text
presentation/profile/pages/my_page.dart
presentation/sync/pages/data_and_sync_page.dart
presentation/sync/pages/local_data_page.dart
presentation/sync/pages/local_data_import_page.dart
presentation/sync/pages/sync_conflict_list_page.dart
presentation/sync/pages/sync_conflict_detail_page.dart
presentation/sync/pages/device_management_page.dart
presentation/sync/widgets/...
```

Presentation 只消费 ViewData/State，不引入 Contract DTO、原始 JSON、Dio 或 MethodChannel。对话框只收集用户选择，不实现底层补偿。

### 6.2 Application

建议按单一流程拆分：

```text
application/workspace/session_workspace_controller.dart
application/workspace/workspace_switch_controller.dart
application/sync/sync_status_controller.dart
application/sync/local_data_import_controller.dart
application/sync/sync_conflict_list_controller.dart
application/sync/sync_conflict_detail_controller.dart
application/sync/device_management_controller.dart
application/sync/logout_flow_controller.dart
application/preferences/workspace_preferences_controller.dart
application/profile/account_profile_controller.dart
```

每个 Controller 必须：

- 拥有显式、尽量不可变的 State，不用多个互相矛盾的 bool 表示阶段。
- 记录controller operation generation和由active-route revision派生的app-level `workspaceEpoch`。
- 对提交、迁移、解决、改名、退出进行 single-flight。
- 将 Gateway DTO 转换为 ViewData，不把 DTO 暴露给 Widget。
- 只依据 Contract 错误码和 context 映射文案，不显示 Backend/Native 自由文本。

### 6.3 Gateway Interfaces

建立窄接口，不建立包含所有能力的 `SyncGateway`：

- `SessionCredentialGateway`
- `WorkspaceGateway`
- `EventGateway`
- `SyncControlGateway`
- `LocalDataImportGateway`
- `SyncConflictGateway`
- `SyncFailedChangeGateway`
- `DeviceManagementGateway`
- `WorkspacePreferencesGateway`
- `AccountProfileCacheGateway`

Gateway failure 保留 `code`、`retryable`、经 Schema 校验的 details/context 和 `request_id`，但不保留或打印 token、password、cursor、目录、密钥或整个 conflict payload。

### 6.4 DTO 与 Adapter

按 Contract 模块建立：

```text
native_contract/auth/session_*.dart
native_contract/workspace/*.dart
native_contract/sync/*.dart
native_contract/device/*.dart
native_contract/preferences/*.dart
native_contract/profile/*.dart
boundary_adapters/dart_method_channel/method_channel_session_adapter.dart
boundary_adapters/dart_method_channel/method_channel_workspace_adapter.dart
boundary_adapters/dart_method_channel/method_channel_sync_adapter.dart
boundary_adapters/dart_method_channel/method_channel_device_adapter.dart
boundary_adapters/dart_method_channel/method_channel_preferences_adapter.dart
boundary_adapters/dart_method_channel/method_channel_profile_adapter.dart
```

要求：

- 所有 request 使用 `snake_case`，所有 response 校验 exact keys、必填/null、枚举、safe integer、UTC/date/IANA timezone 和 identity。
- discriminated union 必须在 DTO/mapper 层闭合，不把未判别 Map 传到 Application。
- 未知字段/枚举按 02 兼容矩阵拒绝或升版，Flutter 不自行采用“忽略看起来可用”的分支。
- 原始 Map 只允许出现在 Adapter/normalizer 内部。
- 除失联恢复读`workspace.get_state`外，所有mutating/workspace-scoped业务request严格携带Schema规定的`workspace_id + expected_active_route_revision`，需要业务CAS时再另带policy/entity/import/preferences/failed-change revision；Adapter不从当前页面、单例或最后一次调用隐式猜测。`workspace.get_state`只可带nullable `known_active_route_revision`作诊断并始终返回权威current tuple，不能因调用方不知道新revision形成恢复死锁。
- `auth.session.adopt`、`auth.session.get_access_token`、`auth.session.reauthenticate` 的 request/result 均标记敏感，测试也不快照真实秘密。

## 7. 与 Contracts-02 的精确方法映射

本计划只使用云同步-02 §8.2 的方法名；如 02 在冻结评审中改名，必须在同一次 Contract 变更中同步本表和所有消费层。

| MethodChannel 方法 | Flutter 消费方 | UI/Application 用途 | 禁止扩展 |
| --- | --- | --- | --- |
| `auth.session.adopt` | `SessionCredentialGateway` | 提交完整 AuthenticationResponse；成功绑定后继续账号准备，设备超限则进入可跨重启的 `registration_pending` 清理流 | 不提交裸 token pair、另传未验证 account id、解析 opaque token，或回传/缓存 Refresh Token |
| `auth.session.get_access_token` | `SessionCredentialGateway` / Backend client | 请求含 minimum validity与nullable rejected generation，消费 token generation；401路径最多一次Broker重取/请求重放 | 不实现 Dart refresh或401无限循环 |
| `auth.session.get_status` | `SessionCredentialGateway` | 消费七态及nullable `session_generation`，pending logout原样回传该CAS值 | 不将状态等同workspace、不忽略受限态或自增generation |
| `auth.session.logout` | `SessionCredentialGateway` | active首次attempt-once，消费operation-bound review id/revision、精确风险与`allowed_cache_policies`；retry/cancel/skip复用同operation，skip仍server-then-local，只有已记录server unreachable后才另行确认force-local。无可信锚时只呈现destroy-now或取消/重试；pending只传session generation | 前台local时不把local当账号目标；不在logout外先跑sync/读易漂移计数，不把skip与force合并，不在unreachable时假装服务端退出或自行开放retain |
| `auth.session.clear_local` | `SessionCredentialGateway` | 消费可信终止 reason；Flutter只可在二次确认后请求 `user_requested_destroy` | 不伪造revoked/corruption reason或用普通cache clear冒充成功 |
| `auth.session.reauthenticate` | `SessionCredentialGateway` | 设备撤销前提交 password + `purpose=device_revoke` + `target_device_id`，只持有绑定该目标的 Kotlin 内部 grant handle | 不返回 server `reauth_token`，grant 不得换目标复用 |
| `workspace.get_state` | `WorkspaceGateway` | 无CAS恢复读，仅可传nullable known route revision作诊断；消费`ready/locked/empty` strict union、active-route revision和可见统计，切换中仍读上个稳定分支 | 不要求expected revision，不发明switching第四态，不暴露目录或密钥别名 |
| `workspace.list` | `WorkspaceGateway` | 只展示 local 与当前已认证且可解锁的账号 | 其他账号保留缓存完全不可见，不显示任何摘要、标题或业务内容 |
| `workspace.activate` | `WorkspaceGateway` | 使用target workspace id + expected active-route revision执行串行切换 | 失败时不隐式回退游客库 |
| `workspace.import_preview` | `LocalDataImportGateway` | 请求携source/target workspace与route CAS；消费稳定source epoch/snapshot、proposed batch/lineage、typed counts/bytes、提醒影响和过期时间 | 不读取具体业务记录；previous-epoch pending不创建新preview |
| `workspace.import_commit` | `LocalDataImportGateway` | 原样传`preview_token + import_batch_id + target workspace + expected_active_route_revision + expected_import_revision`幂等启动；takeover只消费Kotlin聚合后的已接纳proof分支 | 不等待整个网络确认，不自行生成predecessor/proof/revision |
| `workspace.import_status` | `LocalDataImportGateway` | 传workspace/route CAS、nullable batch及source workspace + current/cleanup-receipt epoch；exact batch可展示九态终态，source无batch只恢复当前handle或empty | 不用本地计数猜测阶段，不把completed旧epoch当current或提前宣称完成 |
| `workspace.import_abandon` | `LocalDataImportGateway` | 传workspace/route CAS、batch/lineage + expected import revision；用户取消/隐私销毁时消费独立HTTP CAS的confirmed/unconfirmed/already-confirmed结果 | 不构造Outbox/sequence，不让网络失败阻止明确销毁 |
| `workspace.clear_account_cache` | `WorkspaceGateway` | 传`workspace_id + expected_session_generation + observed active-route tuple + expected_lifecycle_revision + confirmation_id`；session绑定账号原地drain/fence/销毁/fresh-open/bootstrap/import recovery，session保持active，前台可为local | workspace必须等于Kotlin session binding；不可删除游客、不得当logout；常规fence失败零删除，安全销毁例外必须明确future-fence required |
| `sync.get_status` | `SyncControlGateway` | 完整消费 02 §8.2 冻结的状态快照字段与 phase 闭包，展示待上传、冲突、运行、时间和错误 | 不遗漏字段、不自造 phase，不向 UI 暴露 cursor 原文 |
| `sync.claim_conflict_notice` | `SyncControlGateway` | 一次性提示即将呈现前提交exact head notice id/sequence；只有claimed才显示，no-longer-actionable只刷新状态 | 不按active run或内存bool猜已读，不改未解决总数 |
| `sync.export_diagnostics` | `SyncControlGateway` | backlog告警中由用户显式触发脱敏导出/系统分享，消费export id/hash/time/disposition | 不接收文件路径、内容、payload或身份明文 |
| `sync.set_enabled` | `SyncControlGateway` | 请求workspace/expected active-route revision/enabled/expected sync-policy revision，接收完整状态快照；关闭只停网络不丢Outbox/不停本机提醒 | 不用聚合status revision做policy CAS，不让Flutter自行控制Worker |
| `sync.run_now` | `SyncControlGateway` | 请求当前workspace + expected active-route revision；消费`run_id + disposition(queued/already_running) + status_revision` | 游客、暂停、未绑定设备或blocked错误不得伪装queued；不另开并发路径 |
| `sync.conflict.list` | `SyncConflictGateway` | 离线读冲突摘要与稳定分页 | 不从 Backend 直读临时列表 |
| `sync.conflict.detail` | `SyncConflictGateway` | 展示对象、字段组、本机候选、云端值、设备和接收时间 | 不由 Flutter 再次合并 |
| `sync.conflict.resolve` | `SyncConflictGateway` | `expected_conflict_version` + Contract mode 的 typed resolution | 不传自由 JSON patch |
| `sync.failed_change.list` | `SyncFailedChangeGateway` | 离线分页展示未同步失败意图的安全摘要 | 不把它计作待上传、不读取任意payload Map |
| `sync.failed_change.detail` | `SyncFailedChangeGateway` | 展示typed本机候选/草稿、当前云端baseline与失败原因，提供修改另存/丢弃 | 不用旧sequence直接重试，不自行rebase业务值 |
| `sync.failed_change.discard` | `SyncFailedChangeGateway` | `failed_change_id + expected_failed_change_revision + route CAS`；成功刷新业务投影与完整status | 零网络/零Outbox；修改另存必须走原业务Gateway生成新mutation |
| `device.list` | `DeviceManagementGateway` | 消费remote fresh/stale/unavailable快照，并从current local projection恢复本机提醒/同步/remote-pending；pending态无current marker | 不把unavailable当空列表，不用remote sync镜像覆盖本机 |
| `device.rename` | `DeviceManagementGateway` | 更名 + expected device version | 不做无 CAS 覆盖 |
| `device.update_settings` | `DeviceManagementGateway` | strict oneOf一次只更新receive-reminders或sync-enabled；离线展示local-saved + remote-pending | Kotlin用journal跨owner原子恢复；Backend sync镜像不得反向覆盖本机 |
| `device.revoke` | `DeviceManagementGateway` | 普通态撤销；registration-pending时消费 `registration_outcome=registered/still_limited`，registered后等待Kotlin继续准备 | 不新增register方法、不持有旧AuthenticationResponse；V1不撤销当前设备 |
| `preferences.get` | `WorkspacePreferencesGateway` | 只读 `timezone`、`habit_progress_color`、`default_reminder_methods`、`auto_enable_reminders_on_other_devices` 与 revision | V1 reminder methods仅`ring/popup`；新DTO不含locale，旧`user.get_current`中的locale只作兼容元数据 |
| `preferences.update` | `WorkspacePreferencesGateway` | 上述四字段的 typed patch + expected revision；账号生成 Outbox，游客不生成 | 不提交 locale、`wechat`、任意 key，或调用 Backend profile 快捷覆盖 |
| `search.get_workspace_history` | `SearchHistoryGateway` | `workspace_id + expected_active_route_revision`，消费同 identity/history revision 的规范化关键词列表 | 不读取其他 workspace，不回退旧全局文件 |
| `search.replace_workspace_history` | `SearchHistoryGateway` | 上述 route 字段 + 有序关键词 + `expected_history_revision`；按 CAS 原子替换 | 不上传历史，不并存第二个可写 store |
| `profile.get_cached` | `AccountProfileCacheGateway` | 从当前账号 workspace 的 C++ `account_profile_cache` 读取安全资料投影、profile revision 与 freshness；页面进入、同步完成和 App resume 时重读 | 游客只接收 not-applicable；不回退全局普通文件缓存 |
| `profile.accept_server_snapshot` | `AccountProfileCacheGateway` | 将严格校验的既有 `user.get_current/update_current`、头像或已确认邮箱 API 成功响应按 revision 幂等交给 C++ 缓存 | 不生成 Outbox，不让旧 revision 覆盖新值，不把 locale/timezone 当作 profile |

EventChannel 严格使用：

- `sync.status_changed`：按`(workspace_id,runtime_instance_id,active_route_revision,status_revision)`去重；收到新冲突只更新红点/可claim提示。
- `workspace.state_changed`：按`route_state + active_route_revision`及ready/locked/empty nullable identity union拒绝畸形/旧事件；收到切换、锁定或撤销信号后重读`workspace.get_state`，不直接把event当完整快照。

两个 EventChannel 都不得携带业务 payload、token、cursor、目录或密钥；事件可能重复、丢失或迟到，权威恢复只能来自对应 `workspace.get_state` / `sync.get_status` 快照。

## 8. Application 状态机

### 8.1 启动、登录与空间状态

Flutter 内部状态可使用下列名称，但 wire enum 以 02 冻结值为准：

```text
checkingSession
  ├─ sessionEmpty → openingLocal → localReady
  ├─ pendingAdoption → resumingAdopt
  ├─ registrationPending → deviceLimitRecovery
  │      └─ list → reauthenticate → revoke → retryRegister → preparingAccount
  ├─ sessionActive → restoringWorkspaceState（无CAS get-state）
  │      ├─ activeRoute=local → localReady + accountSessionAvailable
  │      └─ activeRoute=account → preparingAccount / rebuilding
  │             ├─ noLocalData → accountReady
  │             └─ hasLocalData → importDecision
  ├─ sessionRefreshing → checkingSession
  └─ reauthRequired / workspaceBlocked → blockedRecovery
```

规则：

- 无会话不等于应用不可用；必须显式打开 local workspace 并进入完整主页。
- Session与active workspace正交。已登录用户显式切到local后，冷启动/Event丢失必须通过无CAS`workspace.get_state`恢复`sessionActive + localReady`，不能自动切回account；账号后台同步可继续。只有用户点“返回账号”或账号通知完成显式activate后才改变route。
- local workspace ready 后可使用现有 Today、Calendar、Search、Habit、Anniversary、提醒与本机个性化能力；登录/注册是 My 页账号入口，不再是冷启动阻断页。只有 Profile、账号安全、云同步、设备和账号偏好属于账号 guard。
- 游客从登录/注册返回或取消时恢复同一个 local workspace graph；认证页面不得先销毁游客数据页，也不得把游客编辑计入账号 Outbox。
- 游客“我的”显示当前空间、本机数据和登录/注册入口，不请求账号 Profile API。
- 登录/注册验证成功后先把完整且严格校验的 `AuthenticationResponse` 交给 `auth.session.adopt`；Flutter 不拆成裸 token pair，也不另传自报 account id。
- adopt 内部的权威 `user.get_current` identity 交叉校验、设备注册和 session/account/device binding，以及后续 workspace 创建/解锁，都是账号 ready 的前置；Flutter 不自创 `device.register` 方法，也不用临时“先进主页再补”。
- 若adopt返回`SYNC_NOT_ENABLED_FOR_ACCOUNT`，保持原guest graph，显示“云同步测试暂未向此账号开放”；不得展示空账号页、重复注册、创建设备/账号workspace或把它归为网络错误。
- `DEVICE_LIMIT_REACHED`后Kotlin安全接管受限会话；恢复时Kotlin先自动register，仍满才给Flutter device list/reauth/revoke投影。进程重启由registration-pending恢复，不依赖旧AuthenticationResponse；revoke提交响应丢失也只等待内部register/刷新结果。期间不构造业务graph或sync/profile写，但允许pending logout。
- Fresh账号DB即使复用同一active device，也必须等待Kotlin完成transport fence、以其服务端next-sequence seed开库、bootstrap及import/lease恢复；Flutter只显示准备/重建态，不提供提前进入可写主页的按钮。
- 密钥、account binding 或 schema 失败必须 fail closed，不能静默回落到游客库并让用户以为已进账号。
- 已登录用户打开“本机数据”时是显式 workspace 切换；返回账号时同样重走 `workspace.activate`。

### 8.2 同步状态

`SyncStatusDto`必须完整消费02 §8.2快照：workspace/device identity、`sync_enabled/sync_policy_revision`、phase、`pending_upload_count`、`failed_local_change_count/next_failed_local_change_id`、unresolved/unclaimed counts、nullable next-notice id、必填非负next-notice count、nullable next-notice sequence、backlog/reasons/export、时间/failure/retryable、Kotlin-owned`status_revision`与active run。空notice严格为`0/null/0/null`，非空时id/sequence必填且head count>0。不得漏字段、给malformed默认或另存第二份计数；failed-local不并入pending upload，policy CAS绝不使用status revision。

`phase` 只接受 02 冻结的字符串闭包：`local_only / idle / queued / syncing / offline_pending / paused / auth_required / rebuilding / blocked / failed`。Flutter 可以另外保存“首次请求中/刷新中”这类 Controller request lifecycle，但不得把它定义成另一套同步 phase 或回传给 Kotlin。

展示不变量：

- `local_only` 固定显示“仅保存在本机”，不展示伪待上传数；调用 `sync.run_now` 必须呈现冻结错误而非假 queued。
- `idle`只有在权威pending count为0且无failure时显示“已同步”；queued与syncing分别显示排队和运行。有pending且网络不可用必须显示offline-pending，即使系统内部已有联网约束任务也不显示queued。
- `offline_pending` 展示精确待上传数；`paused` 展示“已暂停”及继续增长的待上传数，均不禁止业务编辑、不暂停本机提醒。
- `failed_local_change_count>0`独立显示“有 N 项修改未能同步”，可进入失败项列表查看、修改另存或丢弃；不得把它显示成仍会自动上传。新另存项才进入pending，旧失败项在权威成功apply前仍可恢复。
- `auth_required` 进入会话恢复/登录提示；`rebuilding` 展示bootstrap，不导向空列表或无限手动重试。完成后冲突页必须从同一原子快照看到服务端全部未解决冲突，不另发Flutter网络hydrate。
- `blocked` 提供诊断/升级入口且禁用无意义重复触发；`failed` 根据冻结的 `retryable` 和 `failure_code` 决定重试入口，不能只按网络在线状态猜测。
- 状态中的 `last_success_at`、下次重试和阻塞原因只用于展示，不参与冲突裁决。
- 新冲突提示只由持久化next-notice id/count/sequence驱动：即将呈现前调用exact `sync.claim_conflict_notice`，只有claimed才绘制；no-longer-actionable只刷新。后台完成/重启均可恢复，新notice排在旧head之后，旧claim不能清新notice；不以active-run或内存bool去重。未解决数始终取权威unresolved count。
- C++投影的`awaiting_server_adjudication`只是本机pending与远端baseline竞争状态；在Backend `conflict_delta.created`被apply前，Flutter不得提前创建冲突卡片、增加unresolved计数或显示冲突toast，仍按pending/同步中表达。
- `backlog_state=warning/critical`显示非阻塞/高优先告警和“导出脱敏诊断”入口；阈值来自Contract，Flutter不重算。导出只消费处置结果并交系统分享，不读取文件或展示底层路径。

### 8.3 本机数据导入状态

```text
previewLoading
  ├─ previousEpochCleanupPending → resumingCleanup
  ├─ sourceOwned / sourceEpochExhausted
  └─ decisionRequired(epoch, proposed batch, import revision)
      ├─ keepLocal → accountReady
      └─ commit → local_staging → server_staging
                       ├─ repair_required → fullSuccessorRequired
                       │                    ├─ resumable → new successor
                       │                    └─ evidenceLost/originUnavailable/ttlReclaimed
                       │                         → closingOldRange → new successor
                       │                    old handle → superseded
                       └─ server_confirmed → publish_applied → cleanup_pending → completed

ordinary prepublish batch + abandon_status=pending → stage=abandoned | stage=server_confirmed
```

- `ImportStatusDto.stage`只接受`local_staging/server_staging/repair_required/server_confirmed/publish_applied/cleanup_pending/completed/superseded/abandoned`；方法/网络失败不是stage。`abandon_status`、`reconciliation_status`、`resume_disposition`按02独立解析，proof/predecessor/publish/cleanup字段只在对应分支非null；无谱系使用固定null矩阵。Flutter不得按字符串“进度大小”合并HTTP与Native冲突快照。
- 首次登录与稍后从“本机数据”发起使用同一 Controller。
- preview 只展示 Contract 的source epoch、typed counts、portable preference数量、warnings、提醒影响和过期信息；不接触manifest/range proof或业务payload。`previous_epoch_cleanup_pending`时只显示“正在完成上次迁移”并调用status恢复，不创建新preview/batch；`IMPORT_SOURCE_EPOCH_EXHAUSTED`表示此本机空间永久不可再发起新导入，但不影响继续使用本机数据或旧epoch收尾。
- 用户选择不合并时，本机数据继续留在 local workspace，不进入 Outbox。
- `workspace.import_commit`必须原样使用preview给出的`import_batch_id + expected_import_revision`；首次只接受revision 0。重复点击复用同一batch，`IMPORT_VERSION_CONFLICT`则保留用户意图、用返回的current stage/head/revision重读status后再明确决策，不能用旧revision盲重试。
- 屏幕旋转、页面返回、进程重启后通过`workspace.import_status`按source workspace + current/cleanup-receipt epoch重新附着，不创建新批次，也不把completed旧epoch误认作当前数据。
- server-confirmed只能显示“云端已接收，正在应用权威版本”；只有publish-applied后才可开始清游客，只有completed显示“迁移完成”。
- missing ordinal、rejected或manifest mismatch进入repair-required业务状态，明确显示“本机数据仍保留、账号副本尚未完成”。后继必须是同epoch/lineage的完整successor；Flutter只触发Contract允许的继续动作，Kotlin负责status→takeover/range-close proof→Native接纳→必要ack-only。`IMPORT_BATCH_SUPERSEDED`使旧handle只读并切到current successor，绝不拿旧batch重试或自行生成id。
- ordinary prepublish批可由用户取消并调用`workspace.import_abandon`；abandoned/already-abandoned结束旧handle，proof-null/网络不确定显示“取消待确认”而不是完成，already-confirmed继续下载publish group。有未cleanup published predecessor的reconciliation successor没有普通取消按钮；只有明确privacy destroy可停止本机，后续仍按lineage恢复。
- `IMPORT_SOURCE_OWNED`只显示“这批本机数据正由另一个已登录账号的迁移流程占用，请切回原流程完成”，不得显示/推断账号身份；此状态零新账号写/网络commit，且不能提供“强制接管”。
- 同epoch successor的mapping保持稳定并覆盖当前图与该epoch历史映射闭包；Flutter不展示或计算这一集合。cleanup compare-and-retire成功只退休guest live业务图并原子推进source epoch；非终态Reminder/prepared Notification以`source_migrated`终结，终态审计继续留在guest的不可见anchor中，Search History保持guest且不参与导入。新epoch数据与旧epoch lineage严格隔离，旧迁移/cleanup不得触及新数据或账号中旧target。
- publish-applied前guest提醒继续；源设备在cleanup-confirm/Native completed前account提醒仍suppressed，其他设备按权威account事实正常调度。Flutter只展示阶段，不用页面生命周期取消/启用提醒。
- `IMPORT_SOURCE_CHANGED` 必须回到新 preview，不重用旧快照强行提交。

### 8.3.1 Event 重复编辑的 R2-C 边界

R2-C 只保留当前领域的重复 Event 整系列 `event.update`，并继续消费已有 occurrence cancel/complete/reopen 能力；Flutter 不新增“仅本次／本次及以后／整个系列”选择器，也不注册 `event_recurrence.update_occurrence/split_future/update_series`。三作用域编辑整体延后到路线图 R3，必须先有 Event Recurrence 专项 ADR、领域文档和机器 Contract；云同步冲突详情可以展示 recurrence revision 竞争，但不得借冲突 UI 激活未冻结的编辑能力。

### 8.4 冲突列表和详情

列表状态：`initialLoading / ready / empty / refreshing / loadingMore / loadMoreError / failed`。日程、纪念日、习惯筛选使用各自的分页快照；“全部”必须能展示 Contract 声明的其他可见冲突，不能因没有专属筛选而隐藏 Category 等对象。

详情状态：

```text
loading → ready → submitting → resolving
                    ├─ staleVersion → reloadRequired
                    └─ failed
resolving → resolved (仅在exact effect apply或resolved delta)
```

要求：

- 展示对象标题、冲突字段组数、设备名、服务端接收时间、本机候选和云端当前值。
- 已自动合并字段折叠展示，不允许二次修改。
- 保留本机、保留云端、逐字段选择和手动编辑必须映射 02 的 `keep_local / keep_remote / per_field / manual_edit`。
- delete-vs-edit、Habit clear/replace-vs-increment、recurrence revision 冲突使用 Contract discriminated UI，不抽象成一个自由 JSON 编辑器。
- `SYNC_CONFLICT_VERSION_MISMATCH` 或 `SYNC_CONFLICT_ALREADY_RESOLVED` 不自动重提；保留尚未送出的表单草稿，明确提示后重新读详情。
- 提交成功只进入resolving，不从unresolved列表移除；只有对应effect group/更高版本resolved delta被C++应用后才进入resolved并随新status snapshot移除，绝不手工减总数。
- 另一设备解决后，本设备下一次普通增量通过权威resolved delta移除对应项；列表/红点随新status snapshot收敛，Flutter不轮询Backend或从实体值猜测已解决。

### 8.4.1 未同步失败修改

列表只展示`sync.failed_change.list`返回的对象类型、安全标题投影、失败原因和时间；详情通过`sync.failed_change.detail`展示“本机未同步内容”与“当前云端版本”，并明确它不会自动重试。用户操作只有两类：

- “修改并重新保存”：把typed草稿预填到对应领域编辑页，重新加载当前baseline/expected revision，由正常create/update/resolve Gateway提交全新mutation；旧failed id只作UI关联，不进入请求payload。
- “丢弃本机修改”：二次确认后调用`sync.failed_change.discard(expected_failed_change_revision)`，成功后重读对象和status；该操作零网络，不能手工减少计数。

页面返回、进程重启、download或bootstrap都不得让失败项静默消失。若对象此时已有权威unresolved conflict，修改入口转到冲突详情并保留草稿；Flutter不得用failed overlay伪造`conflict_id`。

### 8.5 设备和重新验证

```text
loadingDevices → ready
ready → renaming → ready | versionConflict | failed
ready → reauthenticating → revoking → ready | failed
```

- 列表显示当前设备标记、脱敏名称、平台、最近活动/同步时间和 Contract 允许的状态。
- 离线时显示remote snapshot的“上次更新/暂不可用”状态，同时本设备开关与remote-pending仍从本机权威投影恢复；从未取得快照时不显示“没有其他设备”。
- 更名使用 response-authoritative 值；`DEVICE_VERSION_CONFLICT` 后重新加载，不覆盖别处的修改。
- 当前设备提醒开关提交 `device.update_settings(receive_reminders=...)`；它只控制本设备是否物化账号提醒，不改变账号默认策略。
- 同步总开关以 `sync.set_enabled` / `sync.get_status` 的 C++ workspace 状态为功能真相；Kotlin 必须让 `sync.set_enabled` 与携带 `sync_enabled` patch 的 `device.update_settings` 进入同一个 `DeviceSettingsCoordinator`，只把 Backend 字段作为诊断镜像，Flutter 不维护第二个值，也不因镜像旧值回滚本机开关。
- 两种设备设置均展示 Contract 的 `local_saved + remote_pending` 离线结果；即使本机同步已关闭，独立settings reporter仍可联网清除此标记，但不得上传业务数据。远端镜像待上报不是本机保存失败，CAS 冲突须刷新 device version 后由同一协调器重报。
- 撤销其他设备前调用 `auth.session.reauthenticate`，密码提交后立即从 TextController、Controller State 和 restoration 中清除。
- Flutter 只保留 Contract 允许的 Kotlin 内部 grant handle，不持有 Backend `reauth_token`。
- `DEVICE_LIMIT_REACHED` 不是普通 toast；在 `registration_pending`阻塞页展示脱敏设备列表，允许重验证并撤销旧设备、退出受限会话；revoke响应为registered时等待Kotlin继续准备，为still-limited时刷新列表。Flutter不触发register、不保留旧AuthenticationResponse，页面也不可假装有“当前设备”标记，因为此时 `current_device_id=null`。

### 8.6 退出、撤销和缓存清理

```text
idle
  → logoutAttemptOnce
      ├─ completed → clearingWorkspaceGraph → localReady
      └─ reviewRequired(operation, riskRevision, counts/import)
           ├─ retryAttemptOnce
           ├─ cancelAfterReview → idle
           └─ skipFinalSyncConfirmed → serverLogout
                  ├─ completed → clearingWorkspaceGraph → localReady
                  └─ serverUnreachable
                       ├─ retryServerLogout
                       ├─ cancelAfterReview → idle
                       └─ forceLocalConfirm(allowedCachePolicies) → clearingWorkspaceGraph → localReady
```

流程：

1. active账号首次只调用`auth.session.logout(mode=server_then_local, final_sync_policy=attempt_once)`；Kotlin Broker针对session-bound账号耐久阻写并启动logout-final，即使当前route为local或同步已暂停也仅覆盖这一轮。Flutter不在此前调用普通run-now/读计数，也不要求先切回账号。
2. 若直接完成就消费typed终态；若返回review-required，只展示其同一operation绑定的pending、failed-local与import风险及risk revision。重试、取消、skip都必须原样回传operation/revision；页面返回/关闭须显式cancel或保持可恢复的review页，不能遗留不可见writer gate。
3. `skip_after_confirmation`只跳过final sync，`mode`仍为server-then-local；risk revision失效就重载review，不盲确认。服务端unreachable保持账号session/cache/gate及原route，只有该operation已有unreachable证据后才出现独立“强制仅本机退出”确认；force-local不显示服务端已注销。
4. pending态只使用expected session generation；verified registration-pending的destroy结果可能包含旧retained cache/abandon处置，unverified pending-adoption为not-applicable。初始`server_then_local`可明确选择`retain_30d`或二次确认`destroy_now`；服务端不可达后必须重读该operation的`allowed_cache_policies`。无同boot可信锚时只显示“取消/重试”与“立即清除并仅本机退出”，不得显示可选retain；旧页面提交retain得到`RETENTION_TRUSTED_TIME_REQUIRED`时保持原确认页、Session、cache和route，不乐观退出或静默改选。已合法建立的`retain_30d`是预计30天目标窗口，不是第30天整点物理删除承诺；Flutter原样展示非null deadline及`retention_clock_state`，暂不可验证时保持隐藏并提供立即清除。password reset/logout-all/revoked只消费Kotlin派生clear-local结果，Flutter不伪造reason。
5. 只有token、账号runtime/Worker/提醒和账号UI graph已安全清理/锁定后才完成退出；原route为账号时导航local，原route已是local时保持当前graph，不重建/清理local。
6. “立即清除此设备缓存”是独立active-session账号原地重建：二次确认后携带expected session generation、observed route tuple、expected lifecycle revision与confirmation id调用`workspace.clear_account_cache`；workspace id取当前session-bound账号投影而非当前local route，Kotlin还会再次校验binding。

安全存储、workspace 锁定或精确清理失败时，页面不得显示“已完成”。可以先遮蔽账号业务 UI，但必须显示可恢复/诊断状态。

立即清缓存的UI状态为`preflighting → fencing → destroying → rebuilding → recoveringImport → accountReady | blockedRecovery`。drain/ack/import proof、网络/Auth/device-fence或Native接纳预检失败时保留原账号graph并显示零删除；一旦Kotlin已毁key便保持遮罩和rebuilding/blocked，session仍active，重启继续同一operation-bound fence/policy seed、clear-rebuild bootstrap与import/lease收尾，不上传已销毁Outbox。只有sequence、bootstrap、source lease和提醒切换全部安全后才重建账号graph并恢复原本机策略。可信`DEVICE_REVOKED/AUTH_REFRESH_TOKEN_REUSED/AUTH_SESSION_ACCOUNT_MISMATCH/account-deleted`可在任一阶段抢占并终止session、销毁缓存、切到/保持local；这是唯一不维持rebuilding账号态的例外。游客数据和提醒始终不受影响。

### 8.7 个性化、locale 与 timezone 双轴

- V1 新流程使用 `preferences.get` / `preferences.update`，不改写已发布 `appearance.get_local` / `appearance.update_local` 的旧语义。
- 升级时历史全局appearance值由Kotlin一次性迁入guest；Flutter不把它预填给首个登录账号。导入preview若含 `portable_preferences_count=1`，须明确告诉用户颜色会随本机数据复制；选择保留本机则账号使用自己的/default颜色。
- `WorkspacePreferencesDto/Patch` 的 V1 可写白名单只能有四个字段：`timezone`、`habit_progress_color`、`default_reminder_methods`、`auto_enable_reminders_on_other_devices`；缺失表示不修改，显式 null/default 语义只能来自冻结 Schema。
- 账号 workspace 更新 `habit_progress_color` 时由 C++ workspace 事务与 Outbox 一起提交；游客 workspace 更新同一 UI 偏好但不生成 Outbox。
- 根 Theme 消费当前 workspace 的 `habit_progress_color`；切换 workspace 时不得短暂显示上一账号颜色。
- `locale` 当前只有真实可用的 `zh-CN`，因此不是 V1 可写同步偏好，也不显示切换控件；现有Profile编辑页的自由文本locale输入必须移除，旧`user.get_current`响应中的locale只按兼容矩阵解析为非权威元数据，不驱动App语言、Profile ViewData或写回。当前注册DTO仍按active Auth Contract提交固定`zh-CN`兼容常量，页面不允许编辑且该值不进入preferences change/Outbox。只有第二个locale已完成完整本地化、真实UI切换和Contract revision后才可重新准入。
- `workspace_timezone`来自当前workspace偏好，只用于Event展示/范围查询、日期文案和新建定时Event的默认候选；首次创建workspace可从OS播种一次，此后设备时区不得自动覆盖用户选择。偏好变化只定向刷新Event Calendar/Search投影，不触发Reminder reconcile。
- `device_timezone`来自Kotlin注入的当前OS IANA timezone，用于Habit/Anniversary当地日期以及`timezone_mode=follow_device`的提醒。OS时区变化才刷新Habit/Anniversary投影并由Android重排其open Reminder；Flutter不得拿workspace值覆盖该轴，也不修改UTC/date-only事实。
- `default_reminder_methods`是有序、去重、长度0..2的默认候选优先级，不是真实Reminder的多渠道值。Flutter按机器适用矩阵选择首个合法候选：非全天非重复Event允许ring/popup，全天非重复Event与定时重复Event仅popup，全天重复Event无Reminder，Habit/Anniversary仅popup。无交集时显示“无默认”、不自动预选且不阻止对象以无提醒保存；偏好变化不修改既有Reminder。
- `auto_enable_reminders_on_other_devices` 的标签固定表达“以后在新设备上默认开启提醒”：默认false，账号生命周期首个成功注册设备例外为true（撤销全部设备后也不会重置），改变它不影响既有开关；当前设备receive-reminders与本机sync-enabled分开展示、分开保存。
- V1 不显示或提交 `wechat`、任意 settings key、未实现的 week start/calendar view/holiday 等偏好。

### 8.8 账号资料缓存状态

```text
guestNotApplicable
accountLoadingCached → cacheEmpty | cachedReady | cacheFailed
cachedReady/cacheEmpty → refreshingServer → acceptingServerSnapshot
  → ready
  └─ serverCommittedCachePending → refetchAndAccept | blockingContractFailure
```

- 游客不构造账号资料请求；`profile.get_cached` 的 not-applicable 是正常分支，不映射为错误页。
- 账号 Profile 页先用 `profile.get_cached` 读取当前 workspace 的安全投影、`profile_revision` 和 freshness；freshness 只决定是否提示/刷新，不决定身份或授权。
- 仍由既有 `user.get_current`、`user.update_current`、头像和已确认邮箱 API 完成资料读写；其 Dart HTTP client 每次通过 `auth.session.get_access_token` 获取 AT，不持有 Refresh Token。
- 上述 API 成功响应必须先完成 `ApiResult`、identity、`account_profile_revision` 与安全字段校验，再调用 `profile.accept_server_snapshot`；只有接纳成功或确认本地已有更新 revision 后才发布为缓存权威 UI State。
- 若服务端写已成功但 snapshot 本地接纳失败，不能把资料操作显示成“服务端未保存”或回写旧值；进入 `serverCommittedCachePending`，重新 `user.get_current` 并幂等接纳。
- 下载的 `account_profile` change 由 C++ apply 直接更新同一缓存且零 Outbox。Flutter 不解析 raw change；页面进入、App resume，以及当前 workspace 一次 sync run 到达更新终态后重读 `profile.get_cached`，仅接受同 workspace/epoch 且 revision 不倒退的结果。
- timezone、颜色和提醒默认策略只来自 `preferences.get` / `preferences.update`，不得复制进 Profile ViewData 或通过 `user.update_current` 写回；locale在V1不经这两个可写路径。
- 现有全局 `cached_current_user_v1.json` 不再用于账号生产组合；迁移/删除失败必须 fail closed，不能作为新 workspace 的 fallback。

## 9. 页面和导航规划

### 9.1 “我的”首页

新 My 页不再等同于 Profile 页，必须按`Session状态 × 当前workspace kind`组合显示，不能只看route：

- 当前空间：“本机”或脱敏账号身份。
- `session=empty + local`：登录/注册、本机数据、本机个性化；不显示伪同步或 Profile 错误。
- `session=active + account`：个人资料、数据与同步、账号安全、个性化，并可切到本机。
- `session=active + local`：本机数据/个性化，同时显示“返回账号”和“退出登录”；不得再显示登录/注册，也不得为展示账号信息隐式切route。退出由Broker处理隐藏账号链，local保持active。
- pending-adoption/registration-pending：只显示冻结的恢复/退出能力，不伪装成任一ready账号页。
- 数据与同步卡片显示简要状态和未解决冲突可访问标识；不仅使用红色圆点表达数量。

现有 `ProfilePage` 保留为账号资料子页，不在游客状态构造 `ProfileController`。

账号资料子页的首屏只能来自 `profile.get_cached` 或已经通过 `profile.accept_server_snapshot` 接纳的同 revision 数据；网络刷新、用户名/显示名修改、头像操作和邮箱确认均沿用既有专用 API。页面必须区分缓存 freshness、网络刷新失败和“服务端已提交但本机缓存待接纳”，不得回退到跨账号全局文件。

### 9.2 “数据与同步”

页面必须包含：

- 当前空间和同步总开关。
- 正在同步、已同步、离线待上传、已暂停、需要登录、重建中、发生错误等状态。
- 待上传数、独立“未能同步的本机修改”数量/入口、最近成功时间和手动同步；failed项不得伪装成仍在队列。
- 队列 `warning/critical`告警、原因的安全文案和用户显式“导出脱敏诊断”入口；normal不制造恐慌提示。
- 本机数据/迁移、冲突管理及数量、设备管理。
- `default_reminder_methods`（仅 ring/popup）、“新设备默认开启提醒”、本设备 `receive_reminders`、本机同步总开关四种独立意图及远端诊断镜像待上报状态。
- “立即清除此设备缓存”及未上传修改不可恢复、需在线重建的警告；执行后保持登录并显示重建进度。

手动同步按钮在已 queued/running 时不重复入队，同步开关更新期间禁止快速反向重复提交。

### 9.3 冲突页

- 列表支持全部、日程、纪念日、习惯筛选和稳定分页。
- 列表项显示对象标题、冲突字段组数、设备名、发现/接收时间。
- 详情对照云端当前值和本机候选值，对已自动合并内容折叠展示。
- 所有解决模式提交前显示将要采用的结果，危险的删除/恢复需要二次确认。
- 冲突未解决时对象可查看；从普通详情页继续编辑时导向冲突详情的“编辑并解决”，不调普通 update 绕过。

### 9.4 本机数据与首次登录

- 首次登录发现本机数据时，展示日程、纪念日、习惯、打卡、分类和提醒统计及提醒影响。
- 只提供“全量合并”和“保留本机、暂不合并”，V1 不做逐条选择。
- 导入中可离开页面，但返回时必须恢复同一 batch 状态。
- 导入失败展示 Contract 允许的重试/重新 preview/诊断路径，不给出“手动复制一部分”。

### 9.5 设备管理

- 显示最多 10 台活跃设备的稳定列表和当前设备标识。
- 支持改名、当前设备 `receive_reminders`、本机 `sync_enabled` 状态/远端诊断镜像和撤销其他设备；两个开关不得合并，服务端镜像不得作为 Work 调度开关。
- 撤销前完成密码重验证；失败密码不保留。
- 本设备被其他端撤销时，当前任意账号页面立即进入遮罩/终止流程，不继续显示缓存标题。

### 9.6 路由

最终 route 字符串以 Flutter 实现命名规范为准，但必须为以下意图提供显式解析和权限 guard：

- 数据与同步。
- 本机数据/导入状态。
- 未同步失败修改列表/详情。
- 冲突列表/冲突详情。
- 设备管理。
- 账号资料和账号安全。

冲突 ID、import batch ID 和通知详情路由必须使用 typed route arguments 或严格 URI parser，并验证当前 workspace。不匹配时导向安全的空间首页/解锁提示，不直接 fallback 到可查业务数据的 `/today`。

## 10. Workspace-aware 通知点击

由于总计划明确游客提醒在账号登录期间继续执行，通知点击必须按以下顺序：

1. 严格解析含 workspace identity 的 Notification tap payload；所有 v6 新通知必须携带 `workspace_id`，legacy payload 仅在 Contract 判定唯一无歧义时兼容，否则 fail closed。
2. 与 `workspace.get_state` 当前 identity 比较。
3. 目标为 guest时显式调用 `workspace.activate`、等待根图重建后导航（系统通知已显示“本机”来源）；目标为当前已认证且可解锁account时同样先激活再导航。切到guest不取消account后台sync。
4. legacy payload 缺 workspace identity 且无法唯一确定时映射 `NOTIFICATION_WORKSPACE_AMBIGUOUS`；拒绝导航且不跨库搜索。
5. 如显式目标账号已锁定、已退出、已撤销、不是当前认证账号或当前不可解锁，映射 `NOTIFICATION_WORKSPACE_UNAVAILABLE`；只显示登录/无法打开提示，不显示缓存业务内容。
6. 如 payload 过期、workspace 不存在或对象已删除，回到目标空间的安全首页并显示可读提示；只有 workspace 已成功激活后才允许查询对象。

在 `workspace.activate` 完成前不能先打开详情。Flutter 不以 target ID 是否“刚好能查到”作为 workspace 判断，也不在账号库失败后隐式改查游客库。

## 11. 错误、并发和恢复策略

| Contract 类别 | Flutter 行为 |
| --- | --- |
| `SYNC_PROTOCOL_VERSION_UNSUPPORTED`、`SYNC_BATCH_TOO_LARGE`、`SYNC_PAYLOAD_INVALID` | 进入协议/诊断错误；不无限重试，不用自行缩减字段绕过 |
| `SYNC_CHANGE_GROUP_TOO_LARGE` | 该旧sequence已终结；保留本机意图并提示缩短内容/诊断后另存新修改，不反复重发 |
| `SYNC_CLIENT_SEQUENCE_GAP` | 显示本机同步需要修复；只调用 Contract 后续状态/操作，不计算序号 |
| `SYNC_SEQUENCE_REPLAY_MISMATCH` | 设备同步 blocked，停止自动/手动无限重试，给出诊断入口 |
| `SYNC_SEQUENCE_ROUTE_MISMATCH` | 显示导入序列路由损坏并进入blocked诊断；不把普通修改改造成ordinal或跳过sequence |
| `SYNC_CLIENT_SEQUENCE_EXHAUSTED`、`SYNC_SERVER_SEQUENCE_EXHAUSTED` | 当前设备/账号同步只读blocked，保留本机内容并提供诊断；不回绕序号、不自动注册新device或声称已上传 |
| `SYNC_TRANSPORT_GENERATION_MISMATCH` | 这是旧生命周期请求被栅栏拒绝；忽略旧操作结果、显示当前Kotlin快照/重建进度，不把它渲染为业务数据损坏 |
| `SYNC_TRANSPORT_GENERATION_EXHAUSTED` | 清缓存不可逆前显示零删除失败；若隐私销毁已完成则提示该设备无法重建可写账号库并提供重新登录/支持路径，不回绕generation |
| `WORKSPACE_ROUTE_REVISION_EXHAUSTED` | 保持最后稳定空间只读，禁用切换/激活；只提供诊断导出和安全退出，不用新workspace id绕过 |
| `LOCAL_SETTINGS_REVISION_EXHAUSTED`、`WORKSPACE_LIFECYCLE_REVISION_EXHAUSTED` | 保留当前设置与会话状态；本次设置/清理/退出未提交就显示零变更失败，已提交operation只展示其恢复进度，不重复创建操作 |
| `AUTH_TOKEN_GENERATION_EXHAUSTED` | 遮蔽账号业务并进入安全重登录/终止投影；不把旧token当仍可用，也不显示普通离线 |
| `SYNC_POLICY_REVISION_EXHAUSTED`、`SYNC_STATUS_REVISION_EXHAUSTED` | 保留当前开关与数据，禁用新的同步控制并展示durable blocked诊断；不乐观翻转、不伪造新状态revision |
| `SYNC_NOTICE_SEQUENCE_EXHAUSTED` | 不再弹新的一次性冲突提示，但红点、未解决计数和冲突列表继续可用；不由Dart补造notice identity |
| `SYNC_COUNTER_EXHAUSTED` | 按strict `counter_kind`说明对应服务端能力已只读并保留表单/当前快照，提供诊断；不自动重试、换对象ID或归类为网络错 |
| `SYNC_ENTITY_SYNC_EFFECT_PENDING` | 暂时禁用该对象保存并显示“正在应用云端结果”，触发/等待同一同步恢复；不丢草稿或绕过门禁 |
| `SYNC_ENTITY_CONFLICT_BLOCKED` | 打开/引导到该对象的权威冲突详情；普通编辑草稿不直接提交 |
| `SYNC_FAILED_CHANGE_NOT_FOUND`、`SYNC_FAILED_CHANGE_VERSION_CONFLICT` | 重读失败列表/详情并保留表单；不手工减count、不把旧payload重发 |
| `SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_GENERATION_MISMATCH` | 显示 rebuilding/bootstrap，保留本地未确认修改；Flutter不参与首请求/page顺序 |
| `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH` | fail closed，不回第一页、不跨号/设备重试 |
| `SYNC_BOOTSTRAP_EXPIRED`、`SYNC_BOOTSTRAP_GENERATION_CHANGED` | 保留 live 数据和未确认修改，显示重新构建将重启；Flutter 不清 staging、不自行重放页面，只等待 Kotlin/C++ 重新 begin 后的新状态 |
| `DEVICE_LIMIT_REACHED` | 进设备管理阻塞流程 |
| `SYNC_NOT_ENABLED_FOR_ACCOUNT` | 保持游客页面并提示云同步测试尚未开放；不当网络失败反复重试 |
| `DEVICE_NOT_REGISTERED` | 阻止账号 workspace 写入/同步，回到 adopt 的设备绑定恢复流程；不生成临时 device id |
| `DEVICE_NOT_FOUND` | 刷新设备列表；若是当前设备则进入 session/device binding 诊断，不伪造新记录 |
| `DEVICE_VERSION_CONFLICT` | 刷新对应设备，不自动覆盖 |
| `SYNC_POLICY_VERSION_CONFLICT`、`LOCAL_SETTINGS_VERSION_CONFLICT` | 重读完整status/device本机投影并保留未提交选择；本次不乐观翻转开关，由用户基于新revision重试 |
| `RETENTION_TRUSTED_TIME_REQUIRED` | 保持当前logout operation、确认页、Session、cache与route；按返回的`allowed_cache_policies=[destroy_now]`移除retain选项，只让用户取消/重试server logout或重新二次确认立即清除，不自动重试或静默改选 |
| `DEVICE_REAUTH_REQUIRED`、`DEVICE_REAUTH_TARGET_MISMATCH` | 清除本机 grant/password 投影并重新完成目标绑定的重验证；不复用 grant 撤销另一设备 |
| `DEVICE_REVOKED` | 立即遮蔽账号 UI，走 `auth.session.clear_local`/统一终止路径 |
| `WORKSPACE_NOT_FOUND`、`WORKSPACE_ACCOUNT_MISMATCH`、`WORKSPACE_LOCKED`、`WORKSPACE_KEY_UNAVAILABLE`、`WORKSPACE_SWITCH_CONFLICT` | 显式阻塞/重试/登录提示；不隐式切到其他库 |
| `NOTIFICATION_WORKSPACE_AMBIGUOUS` | 拒绝 legacy 歧义通知，停留安全入口；不按 target id 跨库猜测 |
| `NOTIFICATION_WORKSPACE_UNAVAILABLE` | 不打开不可见/不可解锁 workspace，不展示缓存业务数据；给出登录或无法打开提示 |
| `SYNC_OUTBOX_CORRUPTED`、`SYNC_APPLY_FAILED`、`SYNC_BOOTSTRAP_INCOMPLETE` | 保留原数据和安全诊断态；不清空列表伪装恢复 |
| `SYNC_DIAGNOSTIC_EXPORT_FAILED` | 同步/notice状态不变，提示可重试；不展示路径、异常或半成品 |
| `IMPORT_SOURCE_CHANGED` | 丢弃旧 preview，重新预览 |
| `IMPORT_SOURCE_OWNED` | 保留guest与账号零新写，提示切回原导入流程收尾；不显示owner身份、不提供强制接管 |
| `IMPORT_SOURCE_EPOCH_EXHAUSTED` | 旧epoch收尾继续；禁用此local workspace的新导入并解释本机数据仍可使用，不把它当可重试网络错 |
| `IMPORT_LINEAGE_MISMATCH`、`IMPORT_PUBLISH_INCOMPLETE` | 保留guest与本地staging，分别重新发现同epoch lineage或继续/重启权威publish/bootstrap；不得清源或显示完成 |
| `IMPORT_VERSION_CONFLICT` | 采用返回的current stage/head/revision重读status，保留用户取消/继续意图；不得自动覆写或用旧revision循环 |
| `IMPORT_BATCH_ABANDONED`、`IMPORT_BATCH_SUPERSEDED`、`SYNC_IMPORT_CAPACITY_EXCEEDED` | 旧handle只读并按status转当前完整successor/取消态；proof-null显示待确认，capacity提示释放/恢复，guest源始终保留 |
| `SYNC_CONFLICT_NOT_FOUND`、`SYNC_CONFLICT_VERSION_MISMATCH`、`SYNC_CONFLICT_ALREADY_RESOLVED` | 重新读详情/列表，不覆盖其他设备刚完成的解决 |
| `AUTH_SESSION_EXPIRED`、`AUTH_REFRESH_TOKEN_REUSED` | 停止账号同步、遮蔽账号 UI，进统一终止/重登录流程 |
| `AUTH_SESSION_ACCOUNT_MISMATCH` | 清除 pending adoption 并 fail closed，不打开账号 workspace、不回退旧 Profile cache |
| `AUTH_REAUTH_FAILED` | 留在重验证页，清空密码，不调 `device.revoke` |
| offline/DNS/timeout/可重试429与有限5xx | 显示离线待上传或稍后重试；退避归 Kotlin，手动同步不绕过预算 |
| TLS/hostname、无合法HTTP envelope | blocked/安全诊断；不显示普通离线、不允许降级HTTP或连续手动重试 |
| 未知 enum、非法 envelope、未知错误码 | Contract failure；不冒充网络错误或静默默认 |

并发要求：

- 每个异步操作捕获`workspace_id + active_route_revision`、controller generation和必要的业务expected revision；status revision只排序快照，policy revision才提交同步开关。
- 手动同步、开关、迁移 commit、冲突 resolve、设备 rename/revoke 和 logout 禁止双击重入。
- 同一页面的分页请求只接纳当前 filter/snapshot/cursor 链的结果。
- dispose 后不更新 UI；切换 workspace 时主动使未完成任务的结果失效。
- 订阅后快照恢复与 Event revision 比较必须有乱序测试。
- Dart Auth/Profile client每次请求记录Broker返回的token generation；首个401以该generation再取token并最多重放一次，第二个401交会话终止UI。不得以时间阈值、Dio interceptor递归或并发队列形成第二refresh owner。

## 12. 隐私、安全与缓存

- Refresh Token 不从 `auth.refresh_token.read` 返回 Dart；旧 gateway 从 production composition 移除。
- Access Token 只在请求所需的内存边界存活，不进入 ChangeNotifier state、Widget、restoration、普通 cache 或日志。
- password、Kotlin reauth grant、request header、cursor、workspace 目录、密钥和 conflict 完整 payload 不打印。
- 普通 `UserProfileFileCache` 不得继续作为跨账号单文件生产缓存；账号生产组合只通过 `profile.get_cached` / `profile.accept_server_snapshot` 使用 C++ `account_profile_cache`，并受 workspace 锁定、退出和到期策略约束。
- 退出、换号和撤销时清理 Profile、Calendar、Search、Appearance、表单草稿、ImageCache 中已知账号头像、Navigator 和 restoration 投影。
- 其他已退出/锁定账号的预计30天目标保留缓存对 Flutter 完全不可见；retained状态必须带已建立的非null deadline，force-local无可信锚时不存在无期限隐藏保留分支。`workspace.list`只返回local与当前已认证且可解锁账号，Flutter不展示任何其他账号摘要、标题、搜索历史、通知、组件或冲突候选。系统不能保证整点运行；只有Kotlin返回可信到期/销毁终态后才显示已清除。
- Search History固定按workspace加密保留，不再提供“保留或清空”实现分支：旧全局历史只迁guest一次；guest独立保存，account在Keystore-AEAD存储中按workspace隔离。切换、锁定、退出立即清内存并隐藏，retain窗口内同账号重登可恢复，revoke/destroy/可信到期随key销毁；历史只有规范化关键词，不含对象ID/标题引用，也不随guest导入复制。
- Release/公网包中如仍存在 Dart Dio Auth/Profile，Backend URL 必须构建时显式提供，且拒绝 HTTP、loopback、私网和默认占位地址。Debug 的 HTTP 放行不得进入 Release 路径。
- Debug `LocalTestAccount` 固定映射为 local-only/同步不可用，不注册 Backend device、不创建可上传 workspace、不生成 Sync 网络请求。

## 13. 无障碍、文案与性能

### 13.1 无障碍

- 所有开关具有独立 label、value、hint 和 enabled 语义；账号默认提醒与本设备提醒不合并为一个 Switch。
- 红点同时提供“有 N 个待处理冲突”的可读语义，不仅靠颜色。
- 同步状态变化使用克制的 live-region/announcement；后台小步进度不反复打断 TalkBack。
- 冲突对比以文字标记“本机”、“云端”和选中值，不只用左右位置/颜色。
- 分页、折叠、重试、手动同步、危险确认和密码重验证的焦点顺序可预测。
- 目标尺寸、对比度和 200% 大字下布局不遮挡关键操作。
- 表单错误与字段关联；密码失败后焦点回到密码框且值已清空。

### 13.2 用户文案

- 不使用“实时”、“云端备份”、“永不丢失”等与 V1 不符的词。
- 内测入口固定展示“测试期间数据可能被清除；云同步不是备份”，在用户首次启用/导入确认前可见；不得用成功态文案削弱此限制。
- 同步关闭文案明确“仍保存本机修改，但暂停上传和下载”。
- 退出和清缓存区分“账号仍在云端”、“本机缓存将删除”和“未上传修改可能丢失”。
- 冲突时间显示服务端接收时间，不暗示它是设备编辑先后的绝对时间。

### 13.3 性能

- Flutter 不解析 100 mutation 上传批次、500 change 下载页或 20,000 条导入业务事实。
- 导入页只读进度摘要；冲突列表使用 Contract 分页和惰性列表。
- EventChannel 更新应按 revision 去重并合并不影响用户的中间帧，避免频繁重建整个主页。
- 大型 conflict detail 不得在 build 期间重复做 JSON 解析或深拷贝。

## 14. 分阶段实施计划

### F0：Contract 对齐与只读盘点

- [ ] 逐项将本计划第 7 节方法映射到 02 冻结 Schema、enum、error 和 fixture。
- [ ] 确认完整 adopt/设备注册与registration-pending、`sync_transport_generation`栅栏、token-generation 401单次重放、Notification workspace identity、locale仅兼容读、timezone双轴和缓存不可见语义。
- [ ] 确认 download-only `account_profile`、两条 profile MethodChannel、资料 API revision，以及四字段 preferences 白名单、默认提醒适用矩阵的同一 fixture 映射。
- [ ] 确认`failed_local_change`独立于pending/conflict的状态、列表、详情、discard与编辑另存语义，以及source epoch、lineage、manifest revision、range-close proof和cleanup-confirm导入闭包。
- [ ] 列出现有 Auth/Profile/Appearance/Calendar/Search/Notification 组合的迁移点和回归测试。

退出：02 达到 `CONTRACT FROZEN`，无 Flutter 需要猜测的 wire 行为。

### F1：DTO、Gateway、Adapter 与 fixture Fake

- [ ] 实现第 6、7 节的 strict DTO、Gateway 和 MethodChannel/EventChannel Adapter。
- [ ] 每个 DTO 消费同一 Contract golden 的正例、边界和反例。
- [ ] 建立测试专用 Fake，支持 revision、乱序、重复、迟到、断网和冲突场景。
- [ ] 为 `profile.get_cached` / `profile.accept_server_snapshot` 建立窄 Gateway/Adapter，证明 account profile 与 preferences revision 独立推进。
- [ ] 为失败修改summary/detail/discard、import status完整判别联合、transport fence/rebuilding投影建立strict DTO；禁止以nullable缺省把未知状态降级成成功或空列表。
- [ ] 为WorkspaceState/Event ready/locked/empty union、notice四元组和ImportStatus九态+三个正交enum建立required/null/exact-key DTO；R3三个`event_recurrence.*`方法必须在R2-C生产Adapter中不存在。

退出：Adapter/DTO 定向测试通过；Fake 未进入 production composition。

### F2：Session Broker 迁移与根 Workspace Graph

- [ ] 用 `auth.session.*` 替换 production 中 Dart Refresh Token owner，改造 Auth/Profile HTTP client 获取 Access Token 的方式，并将完整 `AuthenticationResponse` 原样交给 adopt 的 strict DTO。
- [ ] 实现无会话游客主页，重构 Auth check/login/registration success 流程。
- [ ] 实现 `SessionWorkspaceController`、`workspace.state_changed` 恢复协议和 keyed workspace-bound graph。
- [ ] 将当前长寿命 Calendar/Search/Appearance/Notification 组合移入当前 workspace graph。
- [ ] 将账号 Profile 改接 C++ account profile cache；资料 API 成功 snapshot 必须经 `profile.accept_server_snapshot` 后再发布，游客不构造 Profile graph。
- [ ] 处理换号、撤销、密钥失效和迟到 Future/Event。
- [ ] 实现非entitled保持guest、registration-pending跨重启设备清理页及verified旧cache logout分支；fresh DB bootstrap完成前不创建可写业务graph。
- [ ] 覆盖“Session仍active但active route为local”的冷启动/Event丢失恢复：保持local graph并允许账号后台同步，只有显式返回账号才activate；退出登录始终作用于session绑定账号而非当前local route。

退出：A → local → B 切换的 Widget/Controller 回归中不存在 A 的可见内容、cursor、表单草稿或恢复路由。

### F3：“我的”与同步状态

- [ ] 实现游客/账号 My 首页和数据与同步页。
- [ ] 实现 `sync.status_changed` + `sync.get_status` 恢复、同步开关和 `sync.run_now`。
- [ ] 实现红点、待上传数、最近成功、离线/暂停/需登录/重建/诊断投影。
- [ ] 实现持久化conflict notice展示前exact claim，以及backlog三态/人工脱敏诊断导出结果。
- [ ] 实现失败修改独立计数、列表、详情、丢弃和“编辑后另存为新修改”；旧失败项在新修改权威成功apply前仍可恢复，不把它计为待上传或冲突。
- [ ] 在 App resume 复用唯一 `sync.run_now` 协调语义。

退出：所有状态和事件乱序/重复测试通过；UI 不直接触及 HTTP/Worker/Cursor。

### F4：本机数据和导入

- [ ] 实现首次登录 preview/选择和“本机数据”后续入口。
- [ ] 实现`workspace.import_preview/commit/status/abandon`的完整状态闭包与`source_workspace_id + source_epoch`无batch恢复；UI只消费Kotlin聚合后的Backend lifecycle与Native staging投影。
- [ ] 覆盖preview过期、source changed/owned/epoch exhausted、manifest revision冲突、repair successor、旧batch superseded、重复commit、server-confirmed→publish-applied、seen/never-visible range-close、proof-null等待、独立abandon竞态、提醒切换、guest compare-and-retire、终态审计保留与cleanup-confirm。

退出：Flutter 不搬运业务 payload，导入完成文案只在 Contract completed 状态出现。

### F5：冲突管理

- [ ] 实现筛选、稳定分页、详情、自动合并折叠和四种解决方式。
- [ ] 实现删除/编辑、Habit 操作、recurrence 等 discriminated detail。
- [ ] 实现 expected conflict version 失效重载和未提交草稿保护。
- [ ] 实现跨run持久notice的展示前claim，以及resolve提交→resolving→resolved delta流程。

退出：冲突解决不绕过 Outbox/sequence，红点与权威 status revision 一致。

### F6：设备、提醒策略和可移植偏好

- [ ] 实现 `device.list`、`device.rename`、`device.update_settings`、`device.revoke` 和 `auth.session.reauthenticate` 流程。
- [ ] 实现 `preferences.get` / `preferences.update` 四字段白名单、workspace-aware theme、timezone双轴和默认提醒适用矩阵；locale固定zh-CN且不进入可写偏好，`default_reminder_methods` 只接收有序唯一的ring/popup候选。
- [ ] 实现`search.get_workspace_history/replace_workspace_history`及旧全局历史→guest一次迁移后的UI接入；切换/锁定清内存，导入不复制。
- [ ] 区分账号生命周期首台默认、未来设备策略、当前receive-reminders、本机sync-policy revision、服务端诊断镜像和系统能力；Method设置一次只改一字段。
- [ ] 将历史appearance只投影为guest；显式导入portable preference之外不向账号泄漏颜色。
- [ ] 完成 Notification tap workspace identity 路由、异 workspace 激活和锁定/过期安全失败。

退出：不存在任意 settings Map、wechat UI、跨 workspace 通知误导航或切换瞬间颜色/时区泄露。

### F7：退出、缓存和生产组合收口

- [ ] 实现Broker logout-final的attempt-once→operation-bound review→retry/cancel/skip→server-unreachable→独立force-local，以及active/pending oneOf、`allowed_cache_policies`、无锚destroy-only/retain稳定拒绝、verified pending旧cache、30天保留与立即销毁typed结果；active+local退出时保留原local route直到session终止成功。
- [ ] 实现active立即清缓存的preflight/drain/fence/destroy/rebuilding/bootstrap/import-recovery/accountReady投影；常规路径在transport fence失败时零删除并保持session，只有Contract定义的隐私/安全终止例外可先销毁且必须显示future-fence required，不回退或覆盖guest。
- [ ] 移除账号生产路径的全局 Profile 文件缓存，收口 C++ account profile cache、Navigator/restoration、ImageCache、Search History 和所有 workspace-bound Controller 隔离。
- [ ] 更新 production composition，证明使用真实 MethodChannel Adapter，没有 runtime Fake。
- [ ] 保证 `sync.apply` 在 Flutter 无调用路径，Dart 不再是 Refresh Token owner。
- [ ] 完成全量 Flutter 测试、静态分析和 Debug APK 构建。

退出：达到 `Layer Complete / Awaiting Integration`；尚未宣称真实多设备同步完成。

## 15. 测试矩阵

### 15.1 自动化套件与规则追踪

所有 DTO/Adapter 套件消费 Contracts-02 §13 对应 `FX-*`；业务期望由 fixture 的 `rule_anchor` 决定。本节只规定 Flutter 投影、Controller、Widget 和可访问性证据。

| 套件 | 实现锚点 | Contract fixture | Flutter 特有证据 |
| --- | --- | --- | --- |
| DTO / Adapter | §6–§7、§11 | `FX-TARGET`、`FX-CANONICAL`、`FX-COUNTER`、`FX-CROSS-LAYER` | strict request/result/error、两个 envelope 隔离、未知值 fail closed、敏感数据不进日志、R3 方法不存在 |
| Session / root graph | §8.1、§8.6、§9 | `FX-SESSION-DEVICE`、`FX-WORKSPACE` | no-session/active/local-route/locked/rebuilding、adopt/pending、双击和迟到 Future/Event、session-bound logout |
| Sync / failed / conflict | §8.2、§8.4、§9.2–§9.3 | `FX-RUN`、`FX-CONFLICT`、`FX-FAILED-LOCAL`、`FX-MAINTENANCE` | snapshot/event 恢复、十 phase、红点/notice/backlog/export、稳定分页、草稿保留与 A/B resolved 收敛 |
| Import | §8.3、§9.4 | 全部 `FX-IMPORT-*` | 九 stage/三个正交 enum、source discovery、repair/range proof、server-confirmed/publish-applied、cleanup 文案和重启恢复；不搬业务 payload |
| Device / preferences / profile | §8.5、§8.7–§8.8、§9.5 | `FX-PREFERENCE`、`FX-SESSION-DEVICE` | list fresh/stale/unavailable、oneOf settings、四字段白名单、timezone 双轴、默认提醒矩阵、profile 双入口 revision 与 committed-cache-pending |
| Logout / clear | §8.6、§9.1–§9.2 | `FX-SESSION-DEVICE`、`FX-RETENTION-NOTIFY` | attempt/review/force-local、active/pending、allowed policies、无锚retain拒绝且状态零变、retained非null deadline、30天不承诺整点删除、preflight/fence零删除和session-active rebuilding |
| Widget / navigation | §9–§10、§13 | `FX-RETENTION-NOTIFY` | guest/account My、同步/导入/冲突/设备全部可见状态、notification workspace 安全回退、guest“本机”来源和后台账号 sync 不改 route |
| Accessibility / copy | §13 | 适用 `FX-*` | 200% 字体、明暗主题、TalkBack/focus/非颜色信息、危险操作语义，以及“云同步不是备份”等关键文案断言 |

### 15.2 隔离回归

建立专项用例：

1. 账号 A 打开 Calendar/Search/Profile/Conflict，输入草稿并保留头像。
2. 退出或切到 local，再登录账号 B。
3. 证明 Widget tree、Controller state、Navigator/restoration、ImageCache、搜索历史、通知点击和所有 Fake/Adapter 请求中不再出现 A 的标题、邮箱、ID 或 conflict candidate。
4. 在 A 旧请求迟到后再验证一次，确保 epoch 防护生效。

### 15.3 Production Composition

- [ ] `buildProductionApp` 及相关组合使用真实 Session/Workspace/Sync/Device/Preferences/Profile MethodChannel Adapter。
- [ ] production 不构造 `TokenRefreshCoordinator` 为 Refresh owner，不调用 `auth.refresh_token.read`。
- [ ] production 不调用/实现 `sync.apply`，所有 runtime preview/fake 不存在。
- [ ] Debug `LocalTestAccount` 的同步能力显式不可用，且没有 device/sync HTTP 请求。
- [ ] Release Backend URL 配置测试证明 HTTP/loopback/私网/缺省值 fail closed，Debug 例外不泄漏到 Release。

### 15.4 实际执行门禁

```text
flutter test
flutter analyze
flutter build apk --debug
```

另需运行：

- 02 冻结的 `contracts/run_sync_v1_validation.py`。
- 受影响的 Auth、Profile、Appearance、Calendar、Search、Notification 现有回归测试。
- 具有真实 Kotlin Handler 的 Android Debug 集成冒烟；如 Kotlin 尚未完成，该项明确标记为跨层未验证，不以 Fake 替代。

任一命令未实际执行时，不得报告 Flutter 分计划完成。

## 16. 跨计划协调清单

| 上/下游 | Flutter 依赖 | Flutter 交付/回报 |
| --- | --- | --- |
| Contracts-02 | §8.2/8.4 方法、Schema、enum、error、fixture、兼容矩阵；完整 AuthenticationResponse、transport generation、failed-local、source epoch/lineage/range-close、四字段 preferences、timezone双轴、默认提醒矩阵、Search History、download-only account profile、Notification workspace identity | 每个 DTO/Gateway/Adapter/状态的精确映射，需改 Contract 时先回流 02 |
| C++/SQLite 计划 | workspace state、import status、sync status、conflict、preferences 与 `account_profile_cache` 的真实语义 | 不解析内部批次；profile snapshot/apply 零 Outbox、revision 不倒退；用 fixture 验证 UI 投影足够且无敏感泄露 |
| Backend 计划 | Auth/Profile HTTP 校准、`account_profile_revision`、download-only change、reauth/device 错误、稳定冲突顺序和服务端时间 | Flutter 只直连既有 Auth/Profile 专用 API；不直连 device/sync/conflict API，成功 profile response 必须交 native cache |
| Kotlin/Android 计划 | Broker、workspace registry/coordinator、adopt identity/device binding、Profile cache bridge、唯一 DeviceSettingsCoordinator、SyncCoordinator/Worker、MethodChannel/EventChannel、提醒 reconcile/撤销/清理 | 先订阅后 snapshot、revision/epoch 防护、安全用户流程、严格 profile/preferences DTO 和 production adapter 消费 |
| 跨层集成 | 同一 APK、真实 SQLite v6、真实 Backend、两台设备、弱网/强杀/撤销环境 | 提供可见验收流程和无障碍可观测状态；不以单层测试申请 active |

协调不变量：

- Backend `ApiResult` → Kotlin HTTP DTO → C++/Native DTO 可以有不同 envelope，但同一业务字段的名称、类型、null、enum、顺序和错误不得漂移。
- Flutter 公开给 UI 的是 Native UI 投影，不是 Backend sync exchange payload。
- Kotlin 对同步批次的 HTTP/JNI 编排不反向泄露到 Flutter Controller。
- `preferences.update` 的账号写、`sync.conflict.resolve` 和普通领域写都必须由 C++ 产生正式 Outbox；Flutter 不在操作成功后补记 SyncOperation。
- `account_profile` 只从 Backend 下载；Flutter 既有资料 API 的成功 snapshot 只经 `profile.accept_server_snapshot` 幂等入缓存，不构造该 target 的 upload mutation。
- `sync_enabled` 的功能 owner 是 C++ `sync.set_enabled` / `sync.get_status`；Kotlin 统一协调 Work 与 Backend 诊断镜像，Flutter 不从 `DeviceResponse.sync_enabled` 反向覆盖本机状态。

## 17. 风险与阻塞

| 风险 | 影响 | 控制/退出条件 |
| --- | --- | --- |
| Contract 尚未 frozen | 各层可能自创 payload | F0 只读对齐；冻结前不写 production 协议代码 |
| Flutter 无独立 `device.register` | 若 Kotlin adopt 漏掉内部注册会使 workspace ready 断链 | Contract/Kotlin 测试证明 adopt 按 identity 校验→register→session/device binding 顺序完成；Flutter 不猜测或新增旁路 |
| `get_access_token` 未闭合有效 token 被 401 拒绝的强制刷新 | 可重复使用旧 Access Token | Session ADR/Schema 明确后才迁移 Dio 401 路径 |
| 现有根 Controller + IndexedStack 保留 | 换号泄露列表、搜索和草稿 | keyed workspace graph + A/local/B 专项回归 |
| Notification payload 无 workspace | 游客通知可打开账号同 ID 对象 | Contract additive revision + activate-before-route 测试 |
| 单一普通 Profile cache / Search History | 退出、换号或异常恢复泄露 | Profile 账号生产路径改用 C++ `account_profile_cache`；Search History workspace 隔离，并覆盖删除/锁定失败测试 |
| Profile 专用 API 成功但 `profile.accept_server_snapshot` 失败 | 服务端事实已变而 UI/缓存仍旧 | 进入 committed-cache-pending，重新 get current + 幂等 accept；不回滚服务端、不发布旧 revision |
| `sync_enabled` 本机事实与 Backend 镜像双 owner | Work 状态被旧云端值反转 | Kotlin 单一 DeviceSettingsCoordinator；Flutter 以 sync status 为准并显式显示 remote pending |
| locale 字段与实际本地化脱节 | 服务端显示已改，App 行为不变 | V1从可写同步偏好移除，只保留zh-CN兼容读；第二语言完成后再走Contract revision |
| workspace/device timezone 混为一值 | Event展示或follow-device提醒跨设备漂移 | DTO/查询明确双轴；workspace只刷新Event投影，OS变化才驱动Habit/Anniversary与提醒 |
| Dart Dio 仍允许 Release HTTP 默认值 | 绕过 Kotlin 网络政策 | Auth/Profile 也增加 Release fail-closed composition 门禁 |
| Flutter早期ROM仍可能偏差 | 根生命周期、Broker迁移、Search History和隔离回归被压缩 | 当前只采用18–30人日、±40%的规划ROM；Contract/ADR冻结后按F2–F7重新基线化，不作为承诺或范围上限 |

## 18. 完成定义

只有以下条件全部满足，本计划才可标记 `Layer Complete / Awaiting Integration`：

- [ ] F0–F7 的退出条件满足，Flutter 只使用冻结 Contract 与第 7 节方法；Dart 不再拥有 Refresh Token、Sync HTTP、设备注册旁路或 `sync.apply`。
- [ ] 第 8–13 节的 guest/account、session×route、sync/failed/conflict/import/device/preferences/profile/notification 流程均有真实 production Adapter，并通过第 15 节测试和 A/local/B 隔离回归。
- [ ] Widget、文案、导航和无障碍状态完整；fresh/clear-rebuild 在 fence/bootstrap/import 恢复前不发布可写账号 graph，30 天目标窗口不被描述为整点删除 SLA。
- [ ] Contract validator、Flutter 定向/全量测试、`flutter analyze`、Debug APK 和真实 Kotlin Handler 冒烟均有记录；未执行的跨层项明确为 `UNVERIFIED`。
- [ ] 第 16 节交接双方签收同一 Contract hash；状态仅为 `Layer Complete / Awaiting Integration`，不把 Fake 或单层结果描述为多设备完成。

## 19. 本计划之外

- 不实现 V1.1 单条历史或 V2 整账号备份/恢复 UI。
- 不实现 FCM、服务端提醒、邮件/微信提醒、附件同步、共享日历或多人协作。
- 不在 Flutter 实现 Sync HTTP client、WorkManager、SQLite、Outbox、merge engine、recurrence engine、设备物理擦除或加密。
- 不为了同步页面擅自升级 Flutter/Dart/Dio、引入新状态库或修改已发布 Contract。
- 不在 Contract 冻结前为临时 UI 效果发明字段、错误、方法或运行时 Fake。
