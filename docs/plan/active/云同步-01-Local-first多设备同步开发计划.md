# 云同步-01：Local-first 多设备同步开发计划

> 状态：ACTIVE PLAN / CONTRACT PENDING / IMPLEMENTATION NOT STARTED
> 建立时间：2026-09-03
> 目标阶段：R2-C
> 首发范围：Android 多设备、小规模内测，协议保持跨平台中立
> 计划入口：docs/plan/active/云同步-01-Local-first多设备同步开发计划.md

## 1. 计划结论

本计划为 ExcellentCalendarAPP 建立同一账号下的 Local-first 多设备同步能力。用户登录同一账号后，可以在多台设备看到一致的个人资料、日程、纪念日、习惯、打卡事实、分类、提醒意图和允许跨设备的个性化设置；离线时仍可编辑，恢复网络后自动收敛。

V1 的核心原则如下：

1. SQLite 仍是客户端业务真相源，云端不是本地 Core 的替代品。
2. 游客本机空间与账号空间物理隔离，本机空间永不上传。
3. 账号空间的普通用户业务写、冲突解决以及导入 begin/items/commit 必须分别按冻结事务模型写入 Outbox；游客写、远端 apply、账号资料缓存和设备本机设置必须零 Outbox，导入只在服务端完整发布后作为权威 change 进入账号 live 事实。
4. 服务端按账号隔离数据，使用设备身份、客户端顺序号、实体版本和增量游标完成幂等同步。
5. 不同 merge key 的并发修改自动合并；同一 merge key 只有来自不同设备或无法证明因果关系时才是冲突，同设备合法前驱链不得与自己冲突；删除与编辑、清空与增量等真实竞争进入冲突中心。
6. 提醒只同步用户意图和模板，Android 权限、铃声、调度状态和通知历史仍属于设备本地。
7. V1 不接入 FCM，不承诺 App 关闭后的分钟级实时同步。
8. V1 只用于小规模内测。账号注销、灾难恢复备份和基础主动告警完成前，不进入公开发布。

### 1.1 唯一冲突裁决顺序

本组计划把“当前事实”与“本次要达到的目标状态”分开裁决，所有分计划必须引用本节，不得另排一套优先级：

1. 判断**当前行为**时：已激活且机器可验证的 Contract/Schema → 当前领域不变量 → Accepted ADR → active 计划 → 架构文档 → 当前实现与历史材料。
2. 判断**目标行为**时：本次明确的用户验收目标决定需要改变什么；但它不能靠计划文字静默覆盖上项真相源。凡改变 active Contract、当前领域不变量或 Accepted ADR，必须先记录冲突、修订相应 ADR/领域文档/Contract、给出兼容与迁移方案，再允许实现。
3. 云同步-02 在 `CONTRACT FROZEN` 前只是协调草案；其中 planned/blocked 的机器文件只证明当前基线，不能反向压过本次目标。任何未决冲突一律标为 `DECISION REQUIRED`，受影响层停止实现。
4. 云同步-02 达到 `CONTRACT FROZEN` 后，冻结的机器 Contract 是四个实现层的直接接口真相源；计划中的示例、参数或状态若与之不符，必须先同步修正文档，实施者不得任选一方兼容。

因此，总计划负责范围和验收目标，Accepted ADR/领域文档负责已决语义，冻结 Contract 负责可执行接口；不存在“总计划永远压过 ADR”或“尚未冻结的占位 Contract 永远压过新目标”的解释空间。

## 2. 当前基线与差距

| 能力 | 当前事实 | 本计划要求 |
| --- | --- | --- |
| 本地业务数据 | C++ Core + SQLite v5，包含 Event、Recurrence、Reminder、Anniversary、Category、Habit、HabitCheckIn 等 | 升级为账号感知的 workspace 与同步元数据存储 |
| 本地数据目录 | Android 生产运行时固定解析到单一 local_storage/calendar_core_storage_json | 拆分游客 workspace 和每账号独立 workspace |
| SQLite 加密 | 当前使用仓库内普通 sqlite3.c，没有账号数据库加密 | 建立每账号独立密钥、Keystore 包装和数据库加密方案 |
| Android系统备份/迁移 | 主Manifest未声明`allowBackup/dataExtractionRules/fullBackupContent`，仓库无规则XML；平台默认恢复与Keystore、installation/workspace identity不是同一事务 | 敏感、账号和guest库全部从Auto Backup/任何cloud backup排除；device-to-device direct transfer默认也排除，只有ADR证明非云通道并能在开放前安全re-home新workspace/source identity时才可单独允许guest迁移 |
| Outbox | 不存在 | 普通账号写/冲突解决及 import staging+manifest 都与其专用 Outbox 同事务；guest、remote apply、profile cache、device-local 设置零 Outbox |
| 同步 Contract | contracts/sync 和 sync.apply 是宽松概念占位 | 以强类型批量交换、冲突、设备和状态 Contract 替换 |
| Backend API Contract | contracts/backend_api.yaml 整体仍为 planned | 先校准已实现认证能力，再增加并冻结同步 API |
| 云端认证/资料 | Spring Boot 代码已实现，Contract 尚未激活 | 复用账号和资料能力，统一后台刷新令牌所有权 |
| 云端日历表 | 不存在 | 建立账号分区的强类型事实表、版本、change feed 和 tombstone |
| 设备管理 | 不存在 | 注册、改名、列表、撤销、10 台上限、重新验证 |
| 后台执行 | Android 已有提醒相关 WorkManager 模式 | 新增唯一同步工作链、网络约束和指数退避 |
| 冲突界面 | 不存在 | 我的 → 数据与同步 → 冲突管理 |
| 个性化 | habit_progress_color 明确为 Kotlin 本机配置 | 游客继续本机；账号空间按白名单同步 |
| 测试部署 | Compose 只有 API + PostgreSQL，无 HTTPS；PostgreSQL 映射主机端口 | 增加仅测试用安全部署覆盖和公网 HTTPS 验收 |

任何已有 SyncOperation、SyncResult、sync.apply 或 Backend 空包均不得作为完成证据。

## 3. 已确认的产品基线（仍受 ADR / Contract 门禁）

### 3.1 空间与登录

- [x] 未登录时使用游客本机空间，功能保持完整。
- [x] 登录后默认进入账号空间。
- [x] 我的页面提供“本机数据”入口，两个空间不在同一日历中无提示混合。
- [x] 首次登录检测到本机数据时，先展示日程、纪念日、习惯等数量预览。
- [x] 用户选择合并时执行全量迁移，不在 V1 提供逐条选择。
- [x] 用户选择不合并时，本机数据继续留在本机空间，永不进入同步 Outbox。
- [x] 后续允许用户从“本机数据”再次发起迁移。
- [x] 一台设备同一时刻只有一个活跃账号，但允许为多个账号保留相互隔离的加密缓存。

### 3.2 同步开关与触发

- [x] 同步总开关按设备生效，不影响同账号其他设备。
- [x] 关闭后停止网络上传和下载，但账号空间仍可编辑，修改进入待同步队列。
- [x] 重新开启事务先建立耐久pull-before-push gate；C++只返回带current cursor/ack且uploads为空的pull-only prepared request，完成固定上界全部normal apply或bootstrap finalize后才解除gate并允许normal prepare读取Outbox，强杀/重启不得绕过。
- [x] 触发时机包括：本地写入后的机会调度、App 前台启动、回到前台、网络恢复、WorkManager 后台机会和手动同步。
- [x] 无 FCM；后台同步只承诺尽力执行。

### 3.3 退出、缓存和多账号

- [x] active退出首次调用由Broker建立耐久operation/writer gate，并对Session绑定账号执行一次`logout_final/attempt_once`；即使前台route为local或账号`sync_enabled=false`也只覆盖这一轮且不改持久开关。
- [x] final sync失败，或仍有待上传、未同步失败修改/非终态导入时，返回同operation绑定的精确risk revision/数量/状态；用户只能用同operation重试、取消或明确`skip_after_confirmation`，避免检查到确认之间继续写入。skip仍走server-then-local；只有服务端已返回unreachable后才可单独确认`force_local`。
- [x] Session 与当前前台 workspace 正交：已登录后可显式停留游客空间并继续账号后台同步；final-sync/review/server-unreachable均保持Session、账号缓存和原route。成功或明确force-local后，原route为local仍保持同一local graph，原route为账号才切到local。
- [x] 退出后删除令牌、关闭数据库、清理内存、停止该账号同步任务并取消该账号提醒。
- [x] 保留的账号缓存完全不可见，只能重新登录同一账号后解锁。
- [x] 账号缓存采用“30 天目标保留窗口”：退出后立即锁定并对 Flutter 不可见，在可信时间确认已越过期限后的首次 App 启动或系统允许的清理机会先销毁密钥，再异步删除文件；WorkManager 不承诺第 30 天整点执行，因此这不是严格物理删除 SLA。
- [x] `retention_started_at/retained_until` 一经建立不得因重启、重登或系统时间回拨重新起算。正常在线退出使用 Backend logout终态的`server_time`建立可信UTC锚；同一次开机可用`elapsedRealtime`推进时间下界，重启后只可通过无账号数据、限流、HTTPS的`GET /api/v1/system/time`评估**已经建立**的deadline。已建立deadline但时间暂不可验证时保持缓存隐藏并标记`retention_clock_untrusted`，不得用可回拨wall clock擅自销毁或延长。隐私优先规则固定为：`force_local`当下没有同boot可信服务端锚时，`retain_30d`不可选且不得产生“无deadline无限隐藏”的缓存；用户只能取消/重试服务端退出，或二次确认`destroy_now`。旧UI仍提交`retain_30d`时应零终止、零缓存变更并返回稳定错误。
- [x] 可信期限越过后仍销毁待上传内容、未同步失败修改和相关非终态导入本机证据，因此退出确认必须明确告知风险；服务端range/lease收尾仍需按不含业务payload的持久lifecycle journal恢复。
- [x] 提供“立即清除此设备缓存”。
- [x] active 账号常规立即清理必须先阻写、收敛同步/import、完成 ack-only 并在线取得 transport fence，fence 失败零删除；若transport generation到MAX无法increment，返回`SYNC_TRANSPORT_GENERATION_EXHAUSTED`且常规清理零销毁。隐私/安全终止仍可先销毁，但该device以后不得再次打开可写账号库，且未永久终止时保留future fence gate。
- [x] 被撤销设备下次联网后退出账号并销毁对应密钥和缓存。

### 3.4 冲突

- [x] 不同可独立维护不变量的 merge key 并发修改自动合并；一个原子字段组不能按 JSON key 强拆。
- [x] 同一 merge key 被不同设备并发修改，或因果链无法证明且候选值不同时生成可见冲突；同设备连续离线编辑使用前驱/no-effect receipt，不与自己冲突。
- [x] 删除与编辑并发时，列表先表现为已删除，同时保留编辑版本供恢复。
- [x] 习惯打卡的独立增量自动累计；清空、直接替换总量与并发增量发生竞争时生成冲突。
- [x] 重复日程同步系列规则和例外，不展开未来所有 occurrence。
- [x] 冲突对象仍可查看；进一步修改必须通过冲突详情中的“编辑并解决”完成。
- [x] 未解决冲突持续保留；解决后保留 30 天。
- [x] 冲突解决不阻塞其他对象继续同步。

### 3.5 冲突管理界面

- [x] 固定入口：我的 → 数据与同步 → 冲突管理。
- [x] 有未解决冲突时，入口卡片右上角显示红点。
- [x] 卡片副标题显示待处理数量；最后一项解决后红点立即消失。
- [x] 新冲突被本次同步发现时，显示一次性应用内提示，不发送系统通知。
- [x] 列表支持全部、日程、纪念日、习惯筛选。
- [x] 详情显示对象、字段、本机候选值、云端当前值、设备名称和服务端接收时间。
- [x] 支持保留本机、保留云端、逐字段选择和手动编辑后保存。

### 3.6 提醒

- [x] 同步提醒规则、提前量、方式等用户意图。
- [x] 账号级设置决定“其他设备是否默认开启提醒”。
- [x] 每台设备另有“在此设备接收提醒”开关。
- [x] 账号级设置关闭时，未来新注册设备仍下载提醒规则，但其“在此设备接收提醒”初值为关闭；既有设备不因账号级设置变化被回写，仍只按各自设备开关与系统能力决定是否安排本机通知。
- [x] Android 通知权限、精确闹钟能力、电池优化、铃声 URI、震动能力、已安排 Alarm、响铃会话和通知历史不上传。
- [x] 云端不负责到期弹窗或响铃。
- [x] 拉取提醒变化后，由 Kotlin 触发现有本地提醒 reconcile。

### 3.7 时间语义

- [x] 普通定时日程保存 UTC instant 和 IANA timezone，跨时区只改变显示，不改变真实时刻。
- [x] 全天日程使用 civil date，不做时区换日。
- [x] 纪念日和习惯打卡日使用 date-only 语义。
- [x] 重复规则绑定规则时区，沿用 Core 既有 gap/fold 规则。
- [x] 不使用设备本地时钟决定并发先后；冲突顺序以服务端版本和接收序列为准。
- [x] `user_preferences.timezone` 是 workspace 的日历展示/查询时区及新建定时 Event 的默认候选；创建 workspace 时可从设备时区播种一次，之后 OS 时区变化不得自动覆盖。
- [x] Anniversary/Habit Reminder 的 `timezone_mode=follow_device` 始终跟随当前设备 OS IANA timezone，不跟随同步的 workspace timezone。OS 时区变化触发其 open Reminder 重算及设备当地日期投影；workspace timezone 变化不得重排既有 `follow_device` Reminder，也不得改变 date-only 事实。
- [x] 混合 Calendar/Search 查询同时需要展示时区与设备时区时，Contract 必须分别命名并传递两条轴，不能复用一个 `timezone` 让各层自行猜测。

### 3.8 设备、范围和规模

- [x] 每账号最多 10 台活跃设备。
- [x] 设备默认名称为品牌 + 型号，允许用户改名。
- [x] 移除其他设备前要求重新验证密码。
- [x] V1 只支持同一账号的个人多设备同步，不支持跨账号分享或多人协作。
- [x] V1 不同步日程图片、文件或录音附件；用户头像继续使用既有媒体接口。
- [x] 首轮按 100 个测试账号、每账号最多 10 台设备、每账号 20,000 条以上组合业务记录进行设计和压测。

## 4. V1 同步数据闭包

### 4.1 必须同步

| 类型 | 同步内容 |
| --- | --- |
| 账号与用户资料 | email、username、display_name、头像引用；沿用服务端账号/资料接口，并仅以下行的 download-only `account_profile` change 通知其他设备 |
| 可移植设置 | `timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 ring/popup）、`auto_enable_reminders_on_other_devices`；统一由 `user_preferences` 同步 owner 管理 |
| Category | 名称、描述、颜色、图标、排序、删除状态 |
| Event | 标题、内容、开始/结束、全天日期、状态、完成时间、分类、重要性、地点、时区、来源 |
| Event recurrence | 规则版本、系列修订、单次例外、取消/完成 occurrence 状态 |
| Event reminder intent | 提醒模板和业务启用状态 |
| Anniversary | 标题、date-only日期、历法类型、分类、重复规则、备注、重要性、提醒模板及提醒自身的timezone mode；V1不为Anniversary实体新增timezone字段 |
| Habit | 标题、描述、分类、目标、单位、起止日期、结束状态、重复规则、提醒模板 |
| HabitCheckIn | 日期、状态、完成量、目标/单位快照、完成时间、备注、来源及增量操作身份 |
| 同步元数据 | 实体版本、字段版本、设备顺序号、游标、Outbox、冲突、tombstone、导入批次 |

### 4.2 明确不上传

- Notification 投递历史、点击历史和失败记录。
- Android AlarmManager / WorkManager 实际任务状态。
- RingSettings、原始铃声 URI、正在响铃的会话。
- Android 权限、通知渠道状态、精确闹钟能力、电池优化状态。
- 本机搜索历史。
- 桌面组件尺寸、系统字体缩放和其他硬件/系统相关设置。
- 业务附件、录音和图片。
- AI 输入输出、分享数据、微信提醒。
- 游客本机空间中的任何业务数据。

账号安全字段不进入日历同步 Outbox：密码、密码摘要、Access Token、Refresh Token、验证码、会话和密钥永远不作为可同步用户资料。邮箱修改继续使用既有验证码安全流程，不采用普通设置的最后写入覆盖。

### 4.3 个性化白名单规则

V1 只允许同步已有真实 UI 和本地行为支撑的设置，不提前为未实现功能制造可写字段：

- 初始固定四字段：`timezone`、`habit_progress_color`、`default_reminder_methods`（V1 仅 `ring`、`popup`）和 `auto_enable_reminders_on_other_devices`；不接受任意 settings Map。
- V1 Flutter 只有真实可用的 `zh-CN`，因此 `locale` 只保留为既有 Auth/UserPreferences 聚合的兼容字段，不是可写同步偏好，也不进入 `preferences.update` 或 Sync Outbox。为兼容当前必填的注册 Contract，注册流程只能提交固定常量 `zh-CN`；这不是用户选择，Backend 不为它产生 locale change，`user.update_current` 也不得再修改。只有第二个 locale 已完成完整本地化、实际 UI 切换和 Contract revision 后，才可重新申请加入白名单。
- week_start_day、default_calendar_view、show_lunar、show_holidays、time_format 等只能在对应本地功能实现并拥有 Contract 后增量加入。
- Backend 当前允许任意标量 settings key 的实现必须在 Contract 激活前收紧为版本化白名单。
- 用户资料和白名单设置使用服务端接收顺序，不进入业务冲突中心；界面可显示最近修改设备和时间。
- 现有 planned 偏好 Contract 中的 wechat 提醒方式不得在 V1 激活；它属于后续服务器渠道提醒，必须等独立 Contract 和投递闭环。

## 5. 目标架构与职责

数据链路：

    Flutter 页面和 Controller
        ↓ 只调用 Gateway / MethodChannel
    Kotlin 协调层
        ↓ JNI 命令
    C++ Application / Domain
        ↓ 同一个 SQLite 事务
    业务事实 + Sync Outbox
        ↓ Kotlin WorkManager 获取上传批次
    HTTPS Sync Exchange
        ↓
    Spring Boot Sync / Calendar 模块
        ↓ 同一个 PostgreSQL 事务
    账号事实 + 版本 + Change Feed + Conflict
        ↓ 增量响应
    C++ 原子应用下载变化并推进 Cursor
        ↓
    Kotlin 重建受影响提醒，Flutter 刷新状态

职责边界：

| 层 | 责任 | 禁止事项 |
| --- | --- | --- |
| Flutter | 登录引导、空间切换、同步状态、设备管理、冲突 UI | 不直接读写 SQLite，不自行合并业务字段 |
| Kotlin | workspace 生命周期、Keystore、HTTP、令牌 Broker、WorkManager、网络状态、提醒 reconcile | 不复制日程/重复/打卡领域规则 |
| C++ | 本地业务事务、Outbox、下载应用、冲突候选、导入图、同步状态查询 | 不持有 Android 权限或 HTTP 实现 |
| SQLite | 本地 canonical facts、Outbox、Cursor、Conflict、Import receipt | 不依赖事后扫描推测变更 |
| Backend | 账号隔离、认证、设备、幂等、字段版本合并、change feed、冲突和保留策略 | 不生成本地 occurrence，不成为提醒调度器 |
| PostgreSQL | 云端事实、版本、序列、设备状态和审计真相源 | 不暴露给客户端 |

## 6. Workspace 与本地数据设计

### 6.1 目录和所有权

- 游客 workspace 继续使用现有生产数据目录，升级后明确写入 workspace_kind=local。
- 每个账号使用独立目录，目录名使用账号 UUID 的不可逆摘要，不直接暴露邮箱或用户名。
- 每个账号数据库内写入不可变 account_id、workspace_id 和 schema version。
- 打开账号数据库时必须校验当前认证账号与数据库 account_id 一致；不一致时拒绝加载。
- AndroidNativeBridgeFactory 当前缓存单一进程级 Bridge，必须改造成显式 open / close / switch workspace 生命周期。
- 后台 Worker、提醒 Receiver 和前台页面必须通过同一 workspace registry 获取正确实例，不允许隐式回到游客库。

### 6.2 SQLite v6 目标表

在实施前通过 Contract/数据分计划冻结实际 SQL。至少需要：

- workspace_metadata：workspace 身份、类型、账号绑定、创建时间。
- sync_state：device/session/transport binding、server cursor/account generation、确认水位、cleanup 水位、同步策略和终态诊断。
- sync_outbox：device_id、连续 client_sequence、mutation_id、target_type、target_id、base version、per-key causal predecessor、typed patch/hash、状态与恢复证据。
- sync_entity_state：实体服务端版本、每字段最后版本、最近 server sequence。
- sync_conflicts：冲突 ID、实体、字段集合、云端值、本机候选值、来源设备、状态和保留时间。
- sync_failed_local_changes：已消费 sequence 但业务零效果的本机 typed 意图、候选/草稿、revision 与 supersede 状态；不再自动上传。
- sync_import_batches：source workspace/epoch、lineage、batch/predecessor、源快照/manifest、隔离 staging、range-close、发布与 cleanup 回执。
- sync_change_receipts、causal/deleted anchors、bootstrap staging：支撑 ack→apply、无效果前驱、删除防复活和物化快照恢复。
- habit_check_in_operations：增量、替换、清空命令的稳定身份与已应用状态。

要求：

- 普通 LocalUser mutation、conflict-resolution intent 及 Import 的隔离 staging/manifest 必须分别与其普通或专用 Outbox 同事务；GuestLocal、RemoteApply、ProfileCache/ServerSnapshot 和 device-local effect 均零 Outbox，具体 writer registry 以 Contracts-02 为唯一基线。
- 游客 workspace 使用相同业务 Schema，但硬性禁止生成可上传 Outbox。
- 下载批次、业务事实、冲突和 Cursor 推进必须在一个事务中提交。
- 只有完整事务成功后才能向服务端确认游标。
- SQLite v5 → v6 迁移必须原子、可重复检测、失败不发布。
- 迁移新增表会改变当前严格 schema shape，因此必须同步更新 validator 和 corruption 测试。

### 6.3 首次本机数据迁移

流程：

1. Preview 读取游客 workspace 当前 `source_epoch` 的一致性快照并统计各实体，同时检查已有 source-level lease；它不提前占有长期 lease，但已返回C++生成/计算的 proposed `import_batch_id`、稳定 `import_lineage_id`、源摘要与完整 manifest。已有其他 owner 的 reserved/active lease则拒绝。
2. 展示数量、可移植偏好和提醒影响；用户确认 commit 后才以 guest reserved→account receipt→guest active 的可恢复 saga 取得独占 lease，并严格复用 preview 的 batch/lineage/snapshot/manifest，不重新生成身份。同一 source 不能被另一账号并发导入。
3. C++ 按实体依赖顺序把 Category、Recurrence、Event/Anniversary/Habit、Reminder、OccurrenceState、HabitCheckIn 写入账号库的隔离 staging，并在同一账号事务写入专用 begin/items/commit Outbox；此阶段不改 live 业务事实。
4. 发生目标 ID 碰撞时按整个引用图和同一 source epoch 的历史 mapping 稳定重映射，禁止只改父 ID；repair successor 必须闭合当前源图与历史映射。
5. Kotlin 原样上传 begin、连续 item 和 terminal commit；Backend 按 lineage/batch/manifest/ordinal/sequence 幂等接收 staging，只有完整 commit 才在单个 PostgreSQL 事务发布 canonical facts 与连续 change group。
6. commit HTTP 终态只把批次标为 `server_confirmed`；客户端随后从正常 cursor 下载完整 publish group，或在materialized bootstrap中验证等价 publish marker，C++原子apply后才标记`publish_applied`。HTTP响应本身不能让账号live提前可见。
7. 不可续传批次先经Backend HTTP takeover/abandon range-close，且只能消费冻结的`ImportRangeCloseProof` oneOf：`seen_range_closed`或`never_visible_after_transport_fence`；后者仅允许已销毁旧runtime并完成device fence的fresh lifecycle。Kotlin再把proof交`workspace.import_accept_range_close`原子接纳，并在seen分支按需完成ack-only，之后才可按resulting revision建立完整successor；存在sequence gap时保持`proof=null`与persistent absent fence，禁止猜号、跳号或另开后继。
8. `publish_applied`后在游客库单一事务重算整张source引用图并做全图compare-and-retire；仅当epoch/hash/count/version与该lineage当前published head全部一致时，才一次退休整个live业务图、按下述规则终结本机执行记录、写cleanup receipt并推进epoch。任一后续新建/修改都使本次零退休，并要求同epoch/lineage的完整successor，禁止逐条部分清理。若source epoch已达safe-integer上限，仍完成退休和receipt但不递增，持久标记exhausted；旧epoch的confirmation、lease释放和提醒切换继续完成，之后新preview/commit均返回`IMPORT_SOURCE_EPOCH_EXHAUSTED`且零lease/staging。
9. Guest cleanup receipt产生后立即置`previous_epoch_cleanup_pending`，允许新本机写但禁止新preview。Kotlin调用Backend `sync.import.cleanup_confirm`；C++仅在接纳exact disposition/revision后把旧epoch标为completed并解除preview gate，随后`workspace.import_finalize_source_lease`凭严格proof释放lease。任一环节崩溃、退出、撤销、清缓存或跨账号切换都按receipt/status继续，不能凭UI或单次HTTP状态判定完成。

这里的“全图 compare-and-retire”只针对可迁移业务事实的**游客 live 图**，不等于级联删除本机执行/审计图：

- `Notification`、Alarm/Work、Ring/Recovery、搜索历史从不上传，也不改挂到账号 workspace；搜索历史是规范化关键词列表，并不持有业务对象标题引用。
- 成功退休游客 live 图时，全部非终态游客 Reminder 与已 prepared 的 Notification attempt 先以 Contract 新增的 `source_migrated` 原因原子终结/废弃，C++返回精确 workspace-bound affected identities，Kotlin随后取消相应 Alarm、Notification、Ring 与恢复任务；迟到 finalize 必须被 CAS 拒绝。
- 已终态 Reminder、Notification 与当前领域要求保留的审计历史继续留在游客分区，不复制到账号、不因源事实退休而物理级联删除。SQLite v6 Contract 必须冻结“不可见 migrated anchor 或等价紧凑审计锚”的唯一表示，保证无悬空引用且普通游客业务查询看不到已迁走对象。
- 游客搜索历史仍归游客 workspace；导入不复制、不清空它。若用户另行销毁游客空间，才按独立隐私流程处理。

`ImportStatus` 的业务阶段固定为九态 `local_staging/server_staging/repair_required/server_confirmed/publish_applied/cleanup_pending/completed/superseded/abandoned`；`abandon_status/reconciliation_status/resume_disposition` 是三个正交枚举，网络或本机错误不得伪装成第十个 stage。按 exact batch 查询必须能恢复九态中的终态；按 source/epoch 无 batch 发现只返回当前仍需处理的 handle，不能把 completed 旧 epoch 当成当前导入。

跨两个数据库无法依赖一个普通 SQLite 事务保证物理原子，因此实现必须使用快照、导入回执和可恢复状态机提供用户可见的全有或全无语义。

### 6.4 本机提醒假设

本计划采用以下默认行为：

- 游客空间保留下来的提醒继续只在当前设备执行，并在通知中标记“本机”。
- 账号空间提醒只在登录该账号、设备接收开关打开且系统能力允许时执行。
- 同步暂停不暂停本机提醒。
- 退出账号只取消该账号提醒，不影响游客空间提醒。

如果产品后续要求登录后暂停游客提醒，需要单独修改本条，不得由实现层自行决定。

## 7. 账号数据库加密门禁

当前仓库使用普通 SQLite，不能直接声称退出后的账号缓存已加密。

建议方案：

1. 每个账号首次创建 workspace 时生成独立 256-bit 随机数据密钥。
2. 使用 Android Keystore 中不可导出的包装密钥保护账号数据密钥。
3. 使用 SQLCipher 兼容数据库加密，使数据库、WAL 和临时页统一受保护。
4. 退出时关闭连接并清除内存中的明文密钥。
5. 清理缓存、设备撤销或账号删除时先销毁包装材料，再删除数据库文件。
6. 不把密钥、账号明文标识、令牌写入日志或备份。

该方案引入新的 Native 依赖，必须先建立 ADR 并完成：

- [ ] 许可证审查。
- [ ] Android 三 ABI 构建验证。
- [ ] 与当前 sqlite3 API 和 defensive/WAL 配置兼容性验证。
- [ ] v5 明文游客库与 v6 加密账号库迁移验证。
- [ ] 进程强杀、磁盘耗尽、WAL 恢复和密钥丢失测试。
- [ ] 20,000 条数据的打开、查询、写入和同步性能测试。

若该依赖未获批准或验证失败，则 3B/17A 的“保留加密缓存”不能交付；不得用“Android 私有目录”冒充账号数据库加密。

## 8. 同步身份、版本与游标

### 8.1 必须区分的身份

- account_id：服务端账号所有权。
- workspace_id：本地数据空间身份。
- device_id：服务端注册设备身份。
- installation_id：一次安装实例，重装后变化。
- sync_transport_generation：同一 active device 的服务端 HTTP 生命周期栅栏，清库/销毁前后 checked increment；不是 cursor/account generation。
- entity_id：业务对象身份。
- mutation_id：逻辑修改身份。
- client_sequence：同一 device_id 下严格递增的上传顺序。
- entity_version：服务端接受后的实体版本。
- server_sequence：账号 change feed 中的服务端顺序。
- cursor：Backend签发并认证、绑定账号、设备、account generation、snapshot upper bound与已覆盖server sequence的不透明值；客户端不得解析。
- source_epoch：guest workspace持久化、从0开始的非负safe integer，只在同epoch全图compare-and-retire成功时推进；MAX按上文进入exhausted终态。
- import_lineage_id：`UUIDv5(冻结namespace, canonical account_id + LF + source_workspace_id + LF + decimal(source_epoch))`；同三元组永久复用，C++生成、Backend复算并以跨端golden验证。
- import_batch_id：每次preview/repair由C++生成的UUIDv4不可变尝试id；不得与lineage互相替代。

不得把时间戳、数组位置、数据库 rowid 或 recurrence revision 当成同步实体版本。

### 8.2 上传幂等

- 同一设备按 client_sequence 连续上传，不允许跳号提交。
- Backend 保存该设备最高已接受序号和必要的响应摘要。
- 重复序号返回原结果，不重复执行。
- 相同序号不同 payload 返回协议错误并冻结该设备同步，等待人工诊断。
- 每个 merge key 还携带同设备前驱链；有业务效果的前驱指向 resulting version，无业务效果但已消费 sequence 的终态以 no-effect receipt 继续链，不能仅靠整个实体的 `base_version` 判断本设备连续离线编辑。
- 上传终态 receipt 与其 change group 必须执行 ack→apply 门禁：本地未 apply 权威效果前不得越过确认水位或开放该对象新写；run 尾部用严格 ack-only 分支刷新确认水位。
- 已消费 sequence 但普通用户写/冲突解决业务零效果的 rejected，不得静默删除本机输入：ack事务先采用权威server baseline，再与Outbox终结原子保存typed `failed_local_change` overlay。该overlay不进入Outbox、Backend、bootstrap payload或成功causal anchor，不自动重传；download/bootstrap始终按baseline→pending→仍适用failed重投影。用户可丢弃或以全新mutation/sequence另存，旧记录可先标`superseded_pending`，但只有新项取得有业务效果的terminal且完成apply后才能清除。
- Habit 增量操作必须同时使用稳定 operation_id，确保网络重试不会重复累计。
- 现有通用 HTTP Idempotency-Key 的 24 小时保留不足以独立承担长期离线同步，必须增加同步专用顺序与去重语义。

### 8.3 下载与游标

- Backend 为账号变化产生单调 server_sequence，允许有空洞但不能倒退。
- C++按设备保存`visible_committed_cursor`；导入publish组跨页时另有临时`import_staging_transport_cursor`，两者不得互相覆盖。
- 响应分页必须固定快照上界，防止翻页期间新增数据造成漏项或重复。
- 普通不可拆change group整页原子apply后才推进visible cursor；导入publish中间页只推进staging transport cursor，收到完整commit并校验全组后才在同一事务发布live事实并推进visible cursor。
- Cursor 篡改/形状错误、超过保留窗口、跨账号、跨设备和 account generation 不匹配必须分别返回 `SYNC_CURSOR_INVALID`、`SYNC_CURSOR_EXPIRED`、`SYNC_CURSOR_ACCOUNT_MISMATCH`、`SYNC_CURSOR_DEVICE_MISMATCH`、`SYNC_CURSOR_GENERATION_MISMATCH`；只有 expired/generation mismatch 进入 bootstrap，其余 fail closed。
- Bootstrap 是独立的物化、固定上界、可分页 session，不是 `cursor=null` 的普通 exchange；完成全部 facts、tombstones/deleted anchors、unresolved conflicts、import markers 和 requesting-device causal/sequence recovery 后，再原子发布并重放本地 pending/failed overlay。
- Bootstrap session/token过期与创建后account generation变化分别返回`SYNC_BOOTSTRAP_EXPIRED`、`SYNC_BOOTSTRAP_GENERATION_CHANGED`，丢弃未发布staging后从null bootstrap cursor重建，不能续用部分快照。
- 若快照中对象已不存在，本地旧编辑转为“云端删除 / 本机编辑”冲突，不能把对象静默复活。

## 9. 字段级冲突算法

### 9.1 普通实体

每个 mutation 携带 base_version、每个实际 merge key 的 causal predecessor 和只包含实际修改字段的 typed patch。服务端维护实体每个可修改字段/字段组最后一次变化版本，并校验同设备 predecessor 链：

1. `causal_predecessors`必须与实际 touched merge keys 精确一致。非空前驱只能引用同device/target/key已验证的成功receipt/紧凑anchor，或同一链上携带effective prior version的terminal no-effect receipt；跨对象、未来值、未触及字段或链断裂一律fail closed。
2. 有合法前驱且当前field version精确等于其resulting/effective prior version时，视为同设备因果后继并接受，即使整个实体的`base_version`较旧；这避免连续离线编辑与自己冲突。
3. 无前驱时，字段版本不晚于`base_version`则接受；若候选值已等于云端值则按冻结fixture视为幂等无效果终态。
4. 当前field version晚于合法前驱/effective baseline（或无前驱时晚于base）且值不同，才是其他设备或不可证明因果的真实并发，生成该merge key冲突。
5. 同一 mutation 中无冲突字段可以提交；冲突字段保持云端当前值并保存本机候选值。实体版本只由服务端分配，`updated_at`只用于展示。
6. 同设备前序 mutation 无业务效果时，后继必须沿no-effect receipt继承有效基线；不得因前序 rejected 而自冲突，也不得把rejected伪成成功anchor或绕过其已消费 sequence。

C++计算`acknowledged_client_sequence_through`时必须停在仍被任一非终态本机Outbox的`causal_predecessor`引用的最早terminal sequence之前；只有后继终结或新的成功anchor接管后才可跨越，保证Backend持续pin对应no-effect receipt。duplicate receipt必须完整回放每个merge key的resulting/effective version及原terminal identity，不能折叠为通用accepted。

### 9.2 删除与编辑

- 删除产生 tombstone，业务列表立即隐藏。
- 与删除并发的编辑内容进入冲突，不覆盖 tombstone。
- 冲突详情允许确认删除或以候选内容执行 restore。
- restore 是新 mutation 和新 entity_version，不回拨 server_sequence。
- tombstone业务payload至少保留180天；被unresolved conflict引用时继续pin到解决后满足30天与安全cursor。无业务payload的deleted anchor保留至账号删除，以持续支撑causal、bootstrap防复活和导入marker/provenance证明。
- Cursor 早于 tombstone 保留下界的设备必须全量重建，避免旧编辑造成数据复活。

### 9.3 HabitCheckIn

- increment/decrement 使用可去重的增量 operation。
- 不同设备的独立增量可交换并累计。
- replace_total、clear 与基线后的其他增量并发时生成冲突。
- 目标值和单位继续使用打卡时快照，不因 Habit 后续修改而重算历史。
- 解决冲突时生成新的聚合版本和 change feed 记录。

### 9.4 重复日程

- 系列规则、规则 revision 和 occurrence exception 使用稳定身份。
- R2-C 沿用当前领域：`event.update` 对重复 Event 只修改整个系列；已有 occurrence cancel/complete/reopen 继续使用既有 typed 操作。
- “仅本次编辑”“本次及以后拆分”“整个系列编辑”的新增三作用域 UI/operation 属于路线图 R3，在 Event Recurrence 专项 ADR、领域文档和机器 Contract 接受前明确不进入云同步 V1。
- 系列规则变化与旧 revision 例外并发时，能安全重放的例外挂接到新 revision；无法证明等价时生成冲突。
- 服务端不展开 occurrence，也不重新实现 C++ recurrence engine。

### 9.5 冲突生命周期

- unresolved：无限期保留并计入红点。
- resolved：保留 30 天，不计入红点。
- expired：后台清理解决记录及冗余候选 payload。
- 所有解决操作要求 expected_conflict_version，避免两台设备同时解决时互相覆盖。

## 10. 设备与会话设计

设备记录至少包含：

- device_id、account_id、installation_id 摘要。
- display_name、platform、app_version、protocol_version。
- registered_at、last_seen_at、last_sync_at。
- receive_reminders、sync_enabled。
- revoked_at、revoked_reason。
- highest_client_sequence、last_cursor 摘要。

规则：

- 第 11 台设备注册时返回设备上限错误，并引导移除旧设备。
- 修改设备名只影响展示。
- 移除其他设备需要重新验证密码；当前认证体系需增加或复用明确的 re-auth Contract。
- 被移除设备的 access/refresh 会话同时撤销。
- 离线设备无法被瞬间物理擦除；下次请求收到 revoked 后执行本地销毁。
- 设备身份用于幂等和审计，不作为账号授权的替代品。

## 11. 提醒同步与本机调度

云端字段按owner分开：

- target-specific reminder intent/template、提前量、业务方式和启用意图。
- `user_preferences.default_reminder_methods`（V1 仅 `ring/popup`）。
- `user_preferences.auto_enable_reminders_on_other_devices`。
- `user_devices.receive_reminders`。

本机字段：

- 通知权限、Alarm 权限、铃声 URI、震动能力。
- Android notification channel。
- scheduled/pending/prepared/delivered 状态。
- 响铃会话、通知历史和恢复批次。

拉取后处理顺序：

1. C++ 原子写入业务提醒意图。
2. 返回受影响 reminder / entity ID 集合。
3. Kotlin 按 workspace、账号策略和设备开关调用现有 reconcile。
4. 系统能力不足时只更新本机降级状态，不回写云端业务规则。
5. 调度唯一键必须包含 workspace 身份，防止游客与账号提醒互相覆盖。

`default_reminder_methods` 是有序、去重、长度 `0..2` 的**默认候选优先级**，不是一个真实 Reminder 的多渠道值。所有端按同一机器适用矩阵选“第一个被目标允许的候选”：非全天非重复 Event 允许 `ring/popup`，全天非重复 Event 仅 `popup`，定时重复 Event 仅 `popup`，全天重复 Event 不支持 Reminder，Habit/Anniversary 仅 `popup`。无交集时不自动创建或预选 Reminder，由用户显式选择目标允许的方法；不得静默回退、阻止保存无提醒对象，或把偏好数组`[ring,popup]`原样持久化为单个真实Reminder的多方法值。偏好变更只影响以后新建草稿，不修改或 reconcile 既有 Reminder。

## 12. Backend 数据与 API

### 12.1 PostgreSQL 目标模型

实际表名由 Backend 分计划冻结，至少覆盖：

- user_devices。
- sync_device_state。
- calendar_events、event_recurrence_versions、event_occurrence_states。
- categories。
- anniversaries、anniversary_recurrences、anniversary_reminder_templates。
- habits、habit_recurrences、habit_check_ins、habit_check_in_operations、habit_reminder_templates。
- reminder_intents。
- sync_entity_field_versions。
- sync_changes。
- sync_conflicts。
- sync_import_lineages、batches、staging、receipts、publish markers、absent fences。
- sync_device_fence_receipts、materialized bootstrap sessions/items。
- sync mutation receipts、device causal anchors、deleted entity anchors与确认/清理水位。
- sync_tombstones 或等价删除元数据。

所有业务表必须包含 account_id，并通过 Repository 查询条件和数据库约束共同防止跨账号访问。

### 12.2 建议 API 切片

Contract 阶段应定义以下能力，最终名称以 backend_api.yaml 为准：

- `device.register/list/rename/update_settings/revoke`，以及session-bound `auth.reauthenticate`。
- sync.device_fence：在清库、fresh recovery 或 force-local 后以幂等 operation checked increment transport generation，并返回序列恢复 bundle。
- sync.exchange：wire normal携带transport generation、cursor、receipt ack、ordered upload batch和下载页请求；重新开启的本机pull-only映射为uploads为空但cursor/download有效的normal请求。ack-only严格为空上传、零下载、null cursor，仅刷新确认水位且客户端只落ack、不调用download apply。
- sync.bootstrap：独立的物化快照 session/page/finalize 协议；不能用 `cursor=null` 的普通 exchange 冒充。
- sync.get_status。
- sync.conflict.list / get / resolve。
- local import preview/commit/status/abandon 的 UI 入口属于 Native/MethodChannel；Kotlin内部按Contracts-02精确调用Backend `sync.import.status`、`sync.import.takeover`、`sync.import.abandon`、`sync.import.cleanup_confirm`与exchange staging/publish生命周期，Flutter不直连这些API。

建议初始限制：

- 每个上传批次最多 100 个 mutation。
- 每个响应下载最多 500 个 change。
- 单请求解压后大小上限在 Contract 中明确，初始以 1 MiB 为候选并通过真实数据测试校准。
- 所有限制返回机器可识别错误。C++ 必须在冻结 batch 前按 Contract 上限装箱；已 prepare/freeze 的 batch、sequence、payload 和 hash 不可因服务端错误自动缩小或改写，客户端按错误分类停止、诊断或以新合法操作恢复。

### 12.3 事务要求

Backend 在单个 PostgreSQL 事务中完成：

- 按固定锁序锁定并重验有效 Session、账号设备、transport generation 与同步状态；Controller 入口认证不能替代提交事务内验证。
- 去重 client_sequence。
- 锁定目标实体版本。
- 合并无冲突字段。
- 写业务事实、字段版本、tombstone、change feed 和 conflict。
- 更新设备最高序号。
- 提交后才返回 accepted 结果。

不得先写业务表、再通过异步任务补 change feed。

## 13. Contract 工作清单

现有 sync_operation.schema.json 允许任意 payload，无法承担生产边界，必须重做。

### 13.1 Backend Contract

- [ ] 先审查已经实现的 16 个认证/资料端点，使 implementation_status 与代码事实一致。
- [ ] 冻结设备 API、同步交换 API、冲突 API 和 re-auth API。
- [ ] 定义 transport fence、normal/ack-only exchange、materialized bootstrap、batch、cursor、account generation、版本、确认/cleanup 水位和分页上界。
- [ ] 为每种实体建立 typed patch，不使用 additionalProperties=true 的通用业务 payload。
- [ ] 定义上传逐项结果，区分 accepted、partially_merged、conflict、rejected、staged、duplicate，并冻结 effect group、ack→apply、per-key predecessor/no-effect receipt 和 failed-local 转换语义。
- [ ] 定义 import source epoch/lease/lineage/manifest/range-close/publish/compare-and-retire/cleanup-confirm 的完整闭包。
- [ ] 定义设备撤销、transport/序列耗尽与旧generation、序号跳跃、五类 Cursor 错误、批次过大和协议版本不兼容错误；以机器`counter_registry`冻结route/settings/lifecycle/token/policy/status/notice及Backend各业务revision的唯一owner、max−1→MAX、MAX后零写/终态和稳定错误context。
- [ ] 定义 180 天 tombstone、冲突保留和客户端重建语义。

### 13.2 Native / MethodChannel / JNI Contract

- [ ] 禁止生产调用旧`sync.apply`并保留`deprecated + blocked/notImplemented`兼容墓碑；新能力使用批次型内部同步协议。
- [ ] 定义`sync.accept_transport_fence`、`sync.prepare_upload_batch`的normal/logout/pull-only/ack-only完整request union、`sync.acknowledge_upload`的normal/ack-only union、仅normal的`sync.apply_download_batch`完整response、`sync.record_transport_terminal`、`sync.begin_bootstrap/apply_bootstrap_page/finalize_bootstrap`、`sync.get_status`与`sync.run_local_maintenance`。
- [ ] 定义 `sync.failed_change.list/detail/discard`，以及 rejected 后编辑另存必须走新普通 writer 的语义。
- [ ] 定义`workspace.import_preview/commit/status/abandon/import_accept_range_close/import_cleanup_confirm/import_finalize_source_lease`及严格range-close/cleanup proof。
- [ ] 定义`sync.conflict.list/detail/resolve`。
- [ ] 保持现有重复 Event 整系列 `event.update` 与 occurrence cancel/complete/reopen Contract；把三作用域编辑明确标记为 R3 deferred，不在 R2-C 新增 Method/Native入口。
- [ ] 定义`workspace.get_state/list/activate/clear_account_cache`。
- [ ] 定义`preferences.get/update`、`profile.get_cached/accept_server_snapshot`。
- [ ] 定义 additive `search.get_workspace_history/replace_workspace_history`，请求与响应都绑定 `workspace_id + expected_active_route_revision`；旧 `search.*_local_history` 只供一次性迁移到 guest 后退出生产组合。
- [ ] 冻结 timezone 双轴与 `default_reminder_methods` 目标适用矩阵；Machine fixture 必须覆盖顺序保留、无交集、全天重复 Event 和既有 Reminder 零变更。
- [ ] 定义`auth.session.adopt/get_access_token/get_status/logout/clear_local/reauthenticate`，以及`sync.set_enabled/run_now`、`device.list/rename/update_settings/revoke`的Flutter Gateway边界。
- [ ] 冻结退出保留的`allowed_cache_policies`、`RETENTION_TRUSTED_TIME_REQUIRED`、retained必有非null deadline，以及Kotlin-local `BootEpochRecord`的UUID格式、BOOT_COUNT/process-only来源、no-backup存储与fail-closed矩阵。
- [ ] 明确敏感字段和禁止日志字段。

### 13.3 Fixtures 与 Validator

- [ ] 正常创建、更新、删除、恢复。
- [ ] 不同可独立merge key自动合并；同一原子字段组不可拆。
- [ ] 同merge key不同设备真实并发冲突；同设备合法predecessor/no-effect链不自冲突。
- [ ] delete-vs-edit。
- [ ] Habit 独立增量、重复投递、clear-vs-increment。
- [ ] recurrence revision 和 exception。
- [ ] date-only、UTC instant、IANA timezone、DST gap/fold。
- [ ] 设备序号重复、跳跃和 payload 不一致。
- [ ] cursor tamper、过期、跨账号、跨设备与 generation mismatch 的不同恢复路径；物化 bootstrap 分页/强杀/重启。
- [ ] transport fence与旧HTTP请求竞态、sequence recovery、PreparedExchange normal/logout/pull-only/ack-only及ApplyResponse完整字段、ack-only只ack不apply、重新开启强杀仍先pull、ack→apply强杀和failed-local overlay。
- [ ] counter registry全部owner的max−1→MAX、MAX后重试、同operation response-loss与并发双写；不得回绕、换identity、借时间戳替代version或重复发布同revision Event。
- [ ] import source epoch/lease、完整 staging/publish、range gap/proof、repair successor、compare-and-retire 和 cleanup-confirm。
- [ ] 无可信锚force-local只能destroy-now且retain请求零副作用；API 24+进程/系统重启、API 23 process-only、backup restore与boot标识异常全部fail closed。
- [ ] 未知枚举、额外字段、超限批次、非法引用。
- [ ] 旧客户端忽略新增响应字段的版本策略，或明确拒绝不兼容协议。

Contract 冻结前，C++、Backend、Kotlin 和 Flutter 不得分别发明 payload。

## 14. 会话与后台同步前置改造

当前 Flutter 负责前台 Token 刷新，Kotlin Keystore 保存 Refresh Token。后台 WorkManager 若独立刷新，将与旋转 Refresh Token 产生竞争并可能触发 token family 撤销。

必须先建立 ADR，推荐：

- Kotlin SessionCredentialBroker 成为 Refresh Token 读取、刷新、轮换和删除的唯一 owner。
- Flutter Backend adapter 向 Broker 请求有效 Access Token，不再自行并发刷新。
- WorkManager 与前台请求共享同一个 single-flight 刷新协调器。
- Refresh 成功后先原子保存新 Refresh Token，再发布 Access Token。
- 进程崩溃、服务端已旋转但本机未落盘的恢复策略必须有集成测试。
- logout、logout_all、device revoke 和 auth failure 使用同一会话终止路径。

该项是后台同步的硬前置，不能通过让两个刷新器“尽量错开”规避。

## 15. Android 网络与调度

### 15.1 环境隔离

Debug：

- 允许显式配置 10.0.2.2 或 RFC1918 私网 HTTP。
- 仅使用测试账号和测试数据。
- 明文允许规则只能存在于 Debug source set。

Release / 公网验收包：

- 主 Manifest 必须包含 INTERNET 权限。
- 强制 HTTPS，拒绝 HTTP、loopback、私网和默认占位地址。
- Backend base URL 必须构建时显式提供。
- 证书链必须由系统信任，不允许关闭证书校验。

### 15.2 WorkManager

- [ ] 建立按 active account + device 唯一命名的同步工作链。
- [ ] one-time sync 使用每 workspace 串行 `APPEND_OR_REPLACE`，但该策略只定义唯一链的追加/失败替换语义，**不负责去重**。Android必须增加耐久有界唤醒合并器：高频触发只更新最新请求标记，同一workspace未完成节点硬上限为“一个running + 一个queued/blocked successor”；Worker退出前读取C++耐久pending/ack-dirty/continuation状态，进程死亡遗漏的入队由启动、前台、网络恢复和periodic机会修复。业务写后触发不能被旧Worker退出竞态丢弃，也不能积累几十个空Worker。
- [ ] periodic sync 只作为机会触发，不向用户承诺周期精度。
- [ ] 需要网络约束；尊重系统 Data Saver 和后台限制。
- [ ] 认证错误停止重试并提示重新登录。
- [ ] 429/5xx/网络错误指数退避并加入 jitter。
- [ ] Contract/数据错误不无限重试，进入诊断状态。
- [ ] App 回前台和网络恢复时触发立即同步。
- [ ] 手动同步复用同一协调器，不另开并发路径。

## 16. Flutter 产品页面

### 16.1 我的 → 数据与同步

- [ ] 当前空间：本机或账号。
- [ ] 同步总开关。
- [ ] 最近成功同步时间。
- [ ] 正在同步、已同步、离线待上传、已暂停、需要登录、发生错误等状态。
- [ ] 待上传数量。
- [ ] 未同步失败修改数量、详情、丢弃和编辑另存入口；与待上传和冲突红点分开显示。
- [ ] 手动同步。
- [ ] 本机数据入口和按 source epoch 恢复的迁移入口。
- [ ] 冲突管理入口及红点。
- [ ] 设备管理入口。
- [ ] 提醒跨设备账号策略。
- [ ] 此设备接收提醒开关。
- [ ] 清除此设备缓存。

### 16.2 冲突页

- [ ] 类型筛选和稳定分页。
- [ ] 对象标题、冲突字段数、设备和发现时间。
- [ ] 云端当前值与本机候选值逐字段对照。
- [ ] 已自动合并字段折叠展示。
- [ ] 保留本机、保留云端、逐字段选择、手动编辑。
- [ ] expected_conflict_version 失效时重新加载，不覆盖其他设备刚完成的解决。
- [ ] 解决后从待处理列表移除，红点计数同步更新。

### 16.3 首次登录和退出

- [ ] 首次登录展示本机数据数量预览。
- [ ] 合并或保留本机的明确选择。
- [ ] 迁移状态、失败重试和完成摘要。
- [ ] 退出前分别展示待同步、未同步失败修改和非终态导入状态/风险。
- [ ] 30 天缓存说明和立即清理入口；force-local无可信锚时只显示取消/重试或立即销毁，不提供无限期隐藏保留。
- [ ] 登录其他账号后不泄露前账号标题、搜索结果、通知和组件内容。

## 17. 分阶段实施清单

### 阶段 0：ADR 与可行性门禁

- [ ] 建立同步版本、字段级合并、设备序号、Cursor、保留策略 ADR。
- [ ] 建立 workspace 生命周期 ADR。
- [ ] 建立账号 SQLite 加密 ADR 和 SQLCipher spike。
- [ ] 建立 Kotlin SessionCredentialBroker ADR。
- [ ] 建立 Category Sync Lifecycle ADR，先闭合 update/delete/reorder、弱引用和冲突语义。
- [ ] 建立 Backend HTTP Contract Calibration ADR，冻结 HTTP status、ApiResult、Retry-After 与幂等摘要规则。
- [ ] 建立 Android Backup / Device Transfer ADR，冻结Manifest规则；敏感、账号和guest数据库全部排除cloud backup，direct device-to-device默认排除，若单独允许guest direct-transfer则证明非云通道与开放前安全re-home。
- [ ] 完成RFC 8785/JCS + SHA-256跨Windows C++、Android三ABI与Java可行性spike，覆盖官方/等价Unicode、对象键排序、数字/null/array/safe-integer向量；不得把`identity.yaml`紧凑数组规则当JCS。
- [ ] 确认现有实体 ID 是否满足全局稳定身份要求。
- [ ] 将已经确认的“游客提醒在账号登录期间继续执行”写入 Workspace Lifecycle ADR、Contract 与跨runtime fixture，不再把它标为待确认产品假设。
- [ ] 校准 Auth / Backend Contract planned 差异。

退出标准：七项 ADR 接受，加密三 ABI与JCS/hash跨端spike通过，协议与Android备份/直连迁移不再存在关键所有权冲突。

早期 ROM：15–25 人日；完成 ADR/Spike 分解后重估。

### 阶段 1：Contract 与测试夹具

- [ ] 重构 contracts/sync。
- [ ] 扩展 backend_api.yaml。
- [ ] 扩展 method_channels.yaml、native_calls.yaml、error_codes.yaml、enums.yaml。
- [ ] 修订 Appearance 本机专属语义为 workspace 感知白名单。
- [ ] 建立跨层 golden fixtures 和专项 validator。
- [ ] 冻结 SQLite v6 和 PostgreSQL 数据模型。
- [ ] 冻结 transport generation/fence、ack→apply/ack-only、per-key causal/no-effect、failed-local 与 source epoch/import lifecycle 的跨层状态机。

退出标准：机器 Contract、正反 fixture、兼容矩阵、错误码和 Validator 全部通过。

早期 ROM：15–25 人日；Contract shape 冻结后重估。

### 阶段 2：C++ Core 与 SQLite v6

- [ ] workspace metadata 和 account binding。
- [ ] 普通账号业务 writer/冲突解决与 Outbox 同事务，并以 writer registry 验证全部零 Outbox 例外。
- [ ] 同步状态、transport binding、确认/cleanup 水位、字段/causal/deleted anchors、failed-local、冲突、bootstrap/import staging 和 Habit operation store。
- [ ] 上传批次读取与确认。
- [ ] 下载批次原子应用与 Cursor 推进。
- [ ] 字段合并、delete-vs-edit、打卡增量和 recurrence conflict。
- [ ] v5 → v6 原子迁移、失败恢复和严格 schema validator。
- [ ] 游客 → 账号的 source epoch/lease、隔离 staging、publish apply、compare-and-retire、cleanup-confirm 和可恢复状态机。
- [ ] 加密账号数据库接入。

退出标准：excellent_calendar_check 构建后测试通过；断点、重复、崩溃、磁盘失败和迁移矩阵通过。

早期 ROM：25–40 人日；SQLite v6 DDL 与加密 spike 后重估。

### 阶段 3：Cloud Backend

- [ ] Flyway 新增设备、日历事实、同步、冲突和 change feed 表。
- [ ] userdevice 设备注册、改名、列表、撤销。
- [ ] re-auth。
- [ ] sync exchange、bootstrap、status、conflict API。
- [ ] sync device-fence、import status/takeover/abandon/cleanup-confirm API 与全部 Session→device→sync-state 事务内重验。
- [ ] 账号隔离和 Repository 强制过滤。
- [ ] client_sequence 幂等、实体锁、字段版本合并。
- [ ] per-key causal/no-effect receipt、ack确认水位、materialized bootstrap、import隔离发布与保留水位。
- [ ] tombstone 180 天、resolved conflict 30 天清理任务。
- [ ] Testcontainers 并发、隔离、重试和故障测试。

退出标准：Maven test 与 verify 完整通过，集成测试没有被跳过；跨账号读取和写入均被拒绝。

早期 ROM：25–40 人日；强类型 DDL、迁移与冲突算法冻结后重估。

### 阶段 4：Kotlin / Android

- [ ] workspace registry、账号目录和 Keystore 生命周期。
- [ ] SessionCredentialBroker。
- [ ] Sync HTTP client 和 Contract mapping。
- [ ] WorkManager 唯一队列、网络恢复、前台触发和退避。
- [ ] JNI batch adapter。
- [ ] 拉取后的提醒 reconcile。
- [ ] logout、撤销、30 天缓存清理。
- [ ] transport fence、active+local Session路由、ack-only尾部与import lifecycle恢复。
- [ ] Debug HTTP / Release HTTPS 网络策略。

退出标准：Kotlin 单测、Gradle test/lint、JNI instrumentation 和后台强杀恢复通过。

早期 ROM：25–40 人日；Broker、加密、Work 与生命周期 spike 后重估。

### 阶段 5：Flutter

- [ ] 同步 Application/Gateway/DTO。
- [ ] 我的页面同步卡片。
- [ ] 本机数据与全量迁移流程。
- [ ] 冲突红点、列表、详情和解决。
- [ ] 设备管理。
- [ ] 提醒同步策略和设备开关。
- [ ] 空间隔离、退出提示和多账号缓存行为。
- [ ] failed-local 独立处理、active+local 恢复、transport重建与完整import状态投影。
- [ ] 可移植个性化设置接线。

退出标准：Widget/Controller/Contract 测试、flutter analyze 和 Debug APK 构建通过。

早期 ROM：18–30 人日；根图、迁移与隔离回归清单冻结后重估。

### 阶段 6：真实跨层集成

- [ ] 删除所有生产`sync.apply`调用意图，不为其补Handler；Contract保留`deprecated + blocked/notImplemented`墓碑，仅保留新批次协议所需测试Fake。
- [ ] 同一 APK 接入真实 Kotlin、JNI、C++ SQLite 和 Backend。
- [ ] 两台真实 Android 设备使用同一账号。
- [ ] 覆盖弱网、断网、重试、重复响应、乱序响应和服务器重启。
- [ ] 验证事件、纪念日、习惯、打卡、提醒和设置。
- [ ] 验证冲突红点和逐字段解决。
- [ ] 验证退出隐藏、换号隔离、撤销和缓存清理。

退出标准：端到端验收矩阵全部有真实证据，不以 Fake 或单层测试替代。

早期 ROM：20–35 人日；各层 Layer Complete 后按剩余集成风险重估。

### 阶段 7：测试服务器部署与容量验证

- [ ] 建立测试部署 compose override。
- [ ] PostgreSQL 不发布宿主机公网端口。
- [ ] API 8080 只绑定本机或容器网络。
- [ ] 80 只做 ACME/跳转，443 提供 HTTPS。
- [ ] 配置日志轮转和磁盘阈值。
- [ ] 部署预构建 Backend 镜像，不在 4 GB 服务器上长期执行 Maven 构建。
- [ ] 执行 100 账号容量、长游标、180 天 tombstone 模拟和重启恢复。
- [ ] 记录可重复部署、回滚和清库步骤。

退出标准：测试环境可重建；TLS、数据库隔离、容量和真实设备通过。

早期 ROM：8–15 人日；测试宿主机与 TLS 路径验证后重估。

### 阶段 8：内测发布

- [ ] 同步功能默认只对测试账号白名单开放。
- [ ] 首批 5–10 个账号观察，再扩大到 100 个。
- [ ] 根据服务器日志人工检查错误率、积压和磁盘。
- [ ] 明确标注测试数据可能清空，云同步不是备份。
- [ ] 收集冲突数量、平均解决时间、同步失败类型和耗电反馈。
- [ ] 稳定观察窗口结束后再决定是否进入公开发布准备。

## 18. 验证矩阵

### 18.1 Contract

- Schema/ref 可解析。
- 所有请求 exact keys。
- typed patch 与实体类型严格匹配。
- UTC/date-only/timezone 语义。
- 枚举、错误码和能力状态一致。
- counter registry 的 owner、strict `counter_kind`、耗尽零写/只读/安全终止语义跨 Backend、Dart、Kotlin、C++一致。
- Backend、Dart、Kotlin、C++ 消费同一 fixtures。

### 18.2 C++ / SQLite

必须使用构建后测试：

    cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
    cmake --build cpp_core/build-ninja --target excellent_calendar_check

额外覆盖：

- Outbox 原子性。
- ack→apply gate、failed-local overlay、确认水位与 ack-only 尾部恢复。
- apply + cursor 原子性；materialized bootstrap staging/finalize 与 pending/failed rebase。
- v5 → v6、加密 DB、WAL、崩溃恢复。
- import source epoch/lease、range-close、隔离 staging/publish、compare-and-retire/cleanup-confirm 的全阶段 crash point。
- 20,000 / 50,000 条性能。

### 18.3 Backend

    cloud_backend/mvnw.cmd test
    cloud_backend/mvnw.cmd verify

必须确认 Testcontainers PostgreSQL 测试实际执行，覆盖：

- 账号隔离。
- 并发 entity_version。
- 重复和跳跃 client_sequence。
- partial merge。
- delete-vs-edit。
- Habit increment 去重。
- cursor snapshot pagination。
- tombstone 清理和过期设备 bootstrap。
- 设备撤销和第 11 台设备。
- Session→device→transport固定锁序、device fence与旧请求并发、transport/sequence上限零写。
- receipt确认/清理水位、deleted anchor、物化bootstrap与import lifecycle保留竞态。

### 18.4 Flutter / Android

- Flutter 全量相关测试与 flutter analyze。
- Android unit、lint、Debug 构建、三 ABI。
- JNI/SQLite instrumentation。
- 至少两台真实 Android 设备。
- 进程强杀、重启、飞行模式、切换 Wi-Fi/蜂窝、系统省电限制。
- 高频写/批量导入10,000次唤醒仍只有一个running加一个successor，静默后最多一个空Worker；journal/enqueue两侧强杀可恢复。
- 通知权限拒绝、精确闹钟不可用、设备时区变化。
- uninstall/reinstall、Auto Backup/cloud restore、device-to-device transfer与Keystore key缺失；账号/敏感/guest文件不得进入cloud backup，direct-transfer若获准则证明非云通道且开放前安全换新workspace/source identity。

### 18.5 端到端场景

1. A 创建，B 拉取。
2. A/B 分别修改不同merge key，自动合并；同一原子字段组不被强拆。
3. A/B 修改相同merge key，冲突中心出现红点；同设备连续离线前驱链不自冲突。
4. A 删除、B 离线编辑，删除可见且编辑候选保留。
5. 两设备分别增加习惯次数，结果正确累计且重试不重复。
6. 一台清空、一台增加，产生冲突。
7. 修改重复系列与单次 occurrence。
8. 全天、纪念日、Habit date-only 不跨时区漂移。
9. 同步暂停期间积累修改，恢复后收敛。
10. 退出时存在待上传、failed-local和/或非终态import，分类提示、保留/销毁和30天清理恢复正确；force-local无可信锚时retain被零副作用拒绝且只允许destroy-now或取消/重试。
11. 登录第二账号，第一账号数据完全不可见。
12. 撤销设备后，下次联网清除账号缓存。
13. Cursor 过期后完整重建，不复活已删除记录。
14. 服务器处理响应后断线，客户端重试不重复写。
15. 服务端重启、数据库短暂不可用后客户端安全重试。
16. 普通修改被终态拒绝后进入可恢复 failed-local；丢弃或以新 mutation 另存均不丢输入、不复用序号。
17. active Session 停留游客 route 时重启/退出，账号后台链和游客 UI 不互相误路由。
18. active 账号清缓存与在途旧请求竞态满足 transport fence；fresh bootstrap/import recovery 完成前不开放写入。
19. 导入跨强杀、响应丢失、range gap、repair、跨账号尝试和重复 epoch 时不双份、不误删游客新数据。

## 19. 性能与容量验收

测试基线：

- 100 个账号。
- 每账号最多 10 个设备记录。
- 每账号 20,000 条组合业务事实；附加 50,000 条单账号压力样本。
- 单批 100 个上传 mutation。
- 单页 500 个下载 change。

建议验收目标，最终以测试环境基线校准：

- 空增量同步不产生业务写。
- 100 mutation 的服务端处理在 20 个并发同步客户端下 p95 不高于 1 秒。
- 500 change 客户端应用不造成 ANR，事务失败可完整回滚。
- 20,000 条首次同步可分页恢复，不要求一次载入内存。
- 同步队列无界增长有明确告警状态和人工导出诊断。
- 服务器磁盘使用达到 70% 提示人工关注，达到 85% 暂停压力写入并清理测试数据。

这些是内测目标，不是未经测量的生产 SLA。

## 20. CentOS 7 测试服务器方案

已知规格：

- CentOS 7。
- 4 核 CPU。
- 4 GB 内存。
- 50 GB 磁盘。
- 当前主要用于测试，不作为正式生产服务器。

### 20.1 可行性结论

规格足以进行 100 账号以内的功能和中低并发测试，但不适合在服务器上同时执行大型 Maven 构建、压力发生器和全部服务。建议在开发机或 CI 构建镜像，服务器只运行制品。

CentOS Linux 7 已于 2024-06-30 结束维护，当前 Docker 官方文档也不再把 CentOS 7 列为受支持系统。因此：

- 可以复用已经稳定运行的现有容器环境完成短期测试。
- 不得为了本计划在该机上盲目升级 Docker、内核或系统组件。
- 如果现有 Docker/Compose 无法运行当前 Java 21 与 PostgreSQL 镜像，停止部署并更换受支持的测试系统。
- 即使容器镜像是新的，EOL 宿主机暴露公网仍有风险。
- 正式环境必须迁移到仍受支持的 Linux。

参考：

- https://www.centos.org/centos-linux/
- https://docs.docker.com/engine/install/centos/

### 20.2 初始资源预算

以下只作为测试起点，必须用实测调整：

| 组件 | 初始预算 |
| --- | --- |
| Spring Boot API | 容器上限约 1.5 GB，JVM 堆先从 256 MB / 1 GB 起测 |
| PostgreSQL | 约 1 GB，连接池初始最大 5 |
| HTTPS 入口 | 128–256 MB |
| OS、容器运行时和文件缓存 | 至少预留 1 GB |
| Redis | V1 单实例同步测试不启用；当前没有需要它的已实现能力 |

磁盘要求：

- PostgreSQL、容器镜像和日志分别统计。
- API 和入口日志必须轮转。
- 不保存请求/响应业务 payload。
- 41B 已明确不做灾难恢复备份，因此测试数据必须可由 fixtures 重建。

### 20.3 网络

- 私网开发继续使用 Debug HTTP。
- 公网端到端验收和Release只接受项目可控的DNS hostname；证书链必须由系统信任，SAN必须精确覆盖该hostname。
- 公网IP按“可能动态”处理，只作为DNS A/AAAA记录的当前解析结果；不得把IP literal写入APK、长期配置或证书身份。
- 地址变化通过受控DNS更新，验收必须覆盖TTL收敛、真实解析、TLS hostname校验和health；没有可控hostname/DNS更新权限时，公网端到端与Release门禁保持阻塞，私网Debug不受影响。
- hostname证书必须自动续期并告警；人工测试清单验证续期失败和过期前告警，不申请或依赖IP证书。

### 20.4 现有 Compose 必须修正的测试覆盖

- 当前 postgres 的 5432 映射不得用于公网测试配置。
- 当前 api 的 8080 不直接暴露公网。
- 增加独立 test-server override，避免破坏本地开发 compose。
- Secret 只从服务器环境或受限文件注入，不提交仓库。
- 测试账号和正式账号环境完全分离。

## 21. 内测可接受风险与公开发布门槛

### 21.1 当前接受的内测风险

- 单机故障会中断同步。
- 41B：没有灾难恢复备份，服务器磁盘损坏可能丢失全部云端测试数据。
- 43B：没有主动监控平台，主要依赖日志和人工检查。
- 22C：没有账号自助注销。
- 无 FCM，后台同步可能延迟。
- CentOS 7 宿主机已 EOL。
- 受控DNS hostname与更新权限尚未提供；公网IP可能动态，因此公网端到端与Release入口仍阻塞。

### 21.2 公开发布前必须完成

- [ ] 受支持的 Linux 和受支持的容器运行时。
- [ ] 提供受控DNS hostname及更新权限，证书SAN匹配hostname，并通过真实解析、自动续期和HTTPS握手门禁；IP literal不是可接受入口。
- [ ] 离机加密数据库备份和实际恢复演练。
- [ ] 证书、服务、5xx、数据库、磁盘、备份和同步积压告警。
- [ ] 账号注销与云端个人数据删除。
- [ ] 生产密钥生成、轮换和恢复流程。
- [ ] 生产 SMTP、限流和滥用防护。
- [ ] 至少一次安全审查和跨账号渗透测试。
- [ ] 完整隐私说明、数据保留说明和用户可见删除流程。
- [ ] 更广 Android 版本、ROM、弱网、耗电和无障碍矩阵。

未满足时，版本只能标记为测试或邀请制内测。

## 22. V1.1 与 V2

### V1.1：单条数据 30 天历史

- 每次服务端接受修改后保存不可变 revision snapshot 或可验证 patch。
- 用户可查看日程、纪念日、习惯和打卡的最近 30 天历史。
- 恢复历史生成新的 mutation、entity_version 和 change feed。
- 不允许回拨 Cursor 或直接覆盖在线数据库。
- 与 conflict resolved 记录分开存储。

### V2：整账号备份

- 定期生成不可变账号快照。
- 快照拥有独立格式版本、校验摘要和加密策略。
- 恢复先进入隔离 staging，校验引用和 Contract，再产生新 generation。
- 恢复期间其他设备必须收到 generation 变化并重新 bootstrap。
- 用户备份与服务器灾难恢复备份是两套能力，不能相互替代。

## 23. 风险清单

| 风险 | 影响 | 控制 |
| --- | --- | --- |
| Auth Contract planned 与代码已实现不一致 | 同步依赖不稳定 | 阶段 0 先校准 |
| Refresh Token 双 owner | 并发刷新导致整个会话族失效 | Kotlin Broker 单一所有权 |
| 现有单一 Bridge / 数据目录 | 换号时读错账号数据 | workspace registry 与显式关闭切换 |
| 事后生成 Outbox | 崩溃后业务数据永远不上传 | 与 writer 同事务 |
| 通用 payload | 跨版本字段漂移和非法数据 | typed patch + exact keys |
| 客户端时钟漂移 | 错误覆盖 | server version/sequence，不按本机时间排序 |
| 180 天 tombstone payload清理后旧设备返回 | 删除数据复活 | cursor expiry + bootstrap + delete/edit conflict；deleted anchor保留至账号删除，unresolved引用继续pin payload |
| Habit 重试 | 计数重复 | operation_id + device sequence |
| 拉取后重复安排提醒 | 双通知 | workspace-aware reconcile 和稳定 schedule key |
| SQLCipher 集成失败 | 无法满足加密缓存 | 阶段 0 spike；失败即停止相关交付 |
| Android默认Auto Backup/设备迁移恢复账号DB、registry、installation或guest事实 | 违反游客永不上传、旧DB与缺失Keystore/new device identity错配，或两个设备复用guest source/lineage | Backup/Device Transfer ADR；敏感/账号/guest强制排除cloud backup，direct-transfer默认排除，获准时仅以非云通道+开放前安全re-home进入Android门禁 |
| CentOS 7 EOL | 公网宿主机安全和容器兼容风险 | 仅短期测试，失败即换受支持系统 |
| 4 GB / 50 GB | OOM、磁盘满 | 预构建镜像、资源上限、日志轮转、容量门禁 |
| 无备份/告警 | 数据丢失发现晚 | 仅测试数据；公开发布前强制补齐 |
| 无 FCM | 后台延迟 | 文案不承诺实时；前台/网络恢复立即同步 |

## 24. 里程碑与工作量

| 里程碑 | 交付 | 冻结前早期 ROM（人日） |
| --- | --- | --- |
| M0 | ADR、加密/JCS spike、身份/历史/备份/可信时间审计 | 15–25 |
| M1 | Contract、Schema、Fixtures、Validator | 15–25 |
| M2 | C++ / SQLite v6 / workspace / Outbox | 25–40 |
| M3 | Backend 数据、设备、同步、冲突 | 25–40 |
| M4 | Kotlin / Android / WorkManager / Keystore | 25–40 |
| M5 | Flutter 同步、迁移、设备和冲突 UI | 18–30 |
| M6 | 双真机、弱网、恢复和性能集成 | 20–35 |
| M7 | 测试服务器部署和内测放量 | 8–15 |

当前合计 `151–250` 人日只是一名有相关经验开发者等价投入的冻结前 ROM，不是排期承诺，预期误差可达 ±40%。它包含实现、测试、文档和评审，不包含等待决策/外部审批，也不包含公开发布前的备份、主动告警、账号注销和生产高可用基础设施；并行只能缩短日历时间，不能直接减少人日。

M0 内部至少单列：七项 ADR 与真相源冲突审计、SQLCipher 三 ABI/WAL/性能、JCS 三端、身份/历史数据/Backup、可信时间与生命周期恢复。M0 的 ADR/Spike完成并形成决策日志后第一次重估；M1 的 Schema/fixture/DDL 达到 `CONTRACT FROZEN` 后第二次基线化 M2–M6。任何分计划不得把旧 `5–8/12–18/10–15/18–25` 区间当作削减安全门禁或测试范围的上限。

M0 的 `15–25` 人日必须在排期时按下列互不重复的工作包登记实际负责人和产出，不能只保留一个总数：

| M0 工作包 | 早期 ROM（人日） | 完成证据 |
| --- | --- | --- |
| 七项 ADR、真相源冲突记录与决策评审 | 4–7 | Accepted ADR / `DECISION REQUIRED` 清单及影响层 |
| SQLCipher 三 ABI、WAL、defensive、密钥丢失与 20,000 条性能 spike | 4–6 | 可复现实验、许可证结论与 go/no-go |
| RFC 8785/JCS + SHA-256 三运行时 golden | 2–4 | Dart/Kotlin/C++ 与 Backend 共同 fixture |
| stable identity、历史数据、Backup/Device Transfer 审计 | 3–5 | inventory、迁移/隔离结论与失败路径 |
| 可信时间、退出保留与生命周期恢复桌面推演 | 2–3 | 状态机、crash-point 与时间回拨矩阵 |

上述合计仍为 `15–25`。±40% 是冻结前认知不确定性，不是可随意消耗的进度缓冲；第一次重估时必须把基础工作量、风险预留、外部等待和集成缓冲分列，第二次基线化后才允许形成日历排期。

## 25. 开发拆分与顺序

本总计划按实现 owner 拆为以下五个 active 分计划：

1. [`云同步-02-Contracts与数据模型开发计划.md`](./云同步-02-Contracts与数据模型开发计划.md)：协议、字段 owner、跨层方法、错误、fixture、SQLite/PostgreSQL 逻辑模型的唯一协调基线。
2. [`云同步-03-CPP与SQLite-v6开发计划.md`](./云同步-03-CPP与SQLite-v6开发计划.md)：本地业务事务、Outbox、apply、bootstrap、冲突、导入、runtime 与加密存储。
3. [`云同步-04-CloudBackend开发计划.md`](./云同步-04-CloudBackend开发计划.md)：认证校准、设备、同步交换、字段合并、change feed、冲突、保留与测试部署。
4. [`云同步-05-Kotlin-Android与会话调度开发计划.md`](./云同步-05-Kotlin-Android与会话调度开发计划.md)：SessionCredentialBroker、workspace/Keystore、JNI、HTTPS、WorkManager、提醒 reconcile 与撤销清理。
5. [`云同步-06-Flutter产品界面开发计划.md`](./云同步-06-Flutter产品界面开发计划.md)：游客/账号流程、同步/导入/冲突/设备/退出 UI 与 workspace-bound 状态。

### 25.1 五计划协调基线

| 业务链 | Contracts-02 | C++-03 | Backend-04 | Kotlin-05 | Flutter-06 |
| --- | --- | --- | --- | --- | --- |
| 登录与空间 | 完整 AuthenticationResponse adopt、权威身份复核、设备绑定、workspace identity | 仅在 account/device binding 完整后 open 可写账号 runtime | `user.get_current` + `device.register`，Session 与 Device 原子绑定 | Broker 单 owner，校验→注册→绑定→开库 | 不再读 Refresh Token；成功前不进入账号业务页 |
| 本地写与上传 | typed mutation、field registry、per-key predecessor/no-effect、RFC 8785 + SHA-256、严格 sequence/receipt | LocalUser/冲突解决intent及import staging分别与对应Outbox同事务；guest/remote/profile/device零Outbox；rejected转failed overlay | 账号事实 + field/causal version + change/receipt 同 PostgreSQL 事务 | 原样搬运 prepared batch，不重算hash/不改payload；run尾部ack-only | 只发业务 Gateway 命令；pending、failed、conflict三类状态分开投影 |
| 下载与重建 | 固定上界 cursor；materialized bootstrap session/items；五类cursor错误；ack→apply/确认水位 | facts/conflicts/receipts/cursor 原子 apply；完整bootstrap staging后publish/rebase pending+failed | 固定generation/upper bound，稳定物化分页，无跨HTTP长事务 | response先ack后apply，旧transport响应零写；崩溃靠duplicate receipt/旧cursor恢复 | 只展示rebuilding，不能清staging或自行重放 |
| 计数器边界 | 机器counter registry冻结每个owner、MAX动作与strict error context | client/source/policy/native-state/notice按本地规则零写或耐久终态 | server/account/device/entity/field/conflict/profile/preferences/import revision checked increment且能力事务零写 | route/settings/lifecycle/token/status唯一owner；只映射其他层错误，不重建版本 | 保留安全只读/退出/诊断入口；不回绕、换ID或把永久错误当网络错 |
| 本机数据导入 | source epoch/lease、lineage/batch/manifest、range-close proof、publish/cleanup状态 | 双库可恢复协调；账号隔离staging；权威change apply后compare-and-retire guest live图并确认cleanup | begin/item隔离接收；完整commit原子发布；status/takeover/abandon/cleanup-confirm幂等CAS | 独占lease、HTTP/JNI编排、proof接纳、提醒切换；不解析业务payload | 只显示聚合状态；无batch按source+epoch恢复，不凭HTTP响应宣称完成 |
| 冲突 | merge key、typed candidate、四种 resolution、expected version | 离线查询；resolution + Outbox 同事务 | 服务端版本/接收序列裁决，解决生成新 version/change | 不复制领域合并，仅映射/排队 | typed UI，不编辑自由 JSON，不按本机时间排序 |
| 资料与偏好 | `account_profile` 仅下行；四项 preference、timezone双轴与默认提醒适用矩阵 | profile cache no-Outbox；preference 账号写入 Outbox | 专用资料 API 原子产生 profile change；拒绝 profile upload并保留偏好顺序 | 严格 profile cache bridge 与 preference/device owner | API success 接纳 profile snapshot；偏好走 workspace Gateway，locale保持zh-CN常量 |
| 提醒 | 只同步 target-specific intent；tap/schedule 必带 workspace | apply 只返回 affected identity，不写 Android 状态 | 不展开 occurrence、不执行到期投递 | workspace-aware reconcile/Alarm/Notification/Work | 点击先验证/切换 workspace，再导航详情 |
| 退出、清库与撤销 | Session/route正交、logout oneOf、transport fence与安全销毁例外 | close/zeroize精确账号库；常规clear接纳fence后才毁库，fresh bootstrap/import recovery前阻写 | 撤销设备与其Session同事务；所有mutating事务锁内重验transport generation | logout作用于session绑定账号；active+local保留local route；30天/立即销毁记录future-fence gate | 展示pending+failed风险；退出成功后账号不可见，已有local route不被误切换 |
| 发布状态 | capability 逐项 planned→active | Layer Complete / Awaiting Integration | Layer Complete / Awaiting Integration | Layer Complete / Awaiting Integration | Layer Complete / Awaiting Integration |

### 25.2 当前一致性结论与显式门禁

本节记录的是截至 2026-09-04 的计划级协调结果，不是已经完成的 Contract 一致性证明。此次审阅既细化责任，也纠正了会违反当前领域/路线图的范围和未闭合分支；机器 Contract、ADR 与 fixture 未冻结前，下面任何一句都不能被当作实现完成证据。

- 旧 `sync.apply` 和宽松 Sync Schema 只是 blocked 占位，不在任何层补运行时实现。
- 当前 C++ 单一全局 runtime 必须改为多实例 registry，以同时支持账号 UI 与游客提醒；Kotlin 不得通过默认 factory 回退游客库。
- 其他账号的 30 天目标保留缓存对 Flutter 完全不可见，只能由 Kotlin 内部清理索引管理；可信期限越过后的首次允许机会先毁key，不能承诺系统在第30天整点运行。`force_local`无同boot可信时间锚时不允许`retain_30d`，不得用null deadline形成无限保留分支。
- 账号资料沿用专用服务端接口，但通过 download-only `account_profile` change 通知其他设备；V1同步偏好只有timezone等四项，locale因只有zh-CN而不进入同步白名单。
- `NotificationTapPayload`、Alarm/Work/Notification 唯一键和 reminder affected identity 都带 workspace；旧 payload 只有唯一无歧义时兼容。
- Refresh Token 只有 Kotlin Broker 一个 owner；旧 token 记录必须受控迁移，旋转结果不确定时 fail closed。
- Session 与 active workspace 是正交状态；显式位于游客空间时账号后台链可继续，logout/clear/revoke 仍按 Broker 绑定账号寻址，不能用当前页面猜目标。
- transport generation/fence 关闭清库前后旧HTTP提交窗口；sequence/cursor/account generation各有独立owner和错误，任何层不得混用。
- route/settings/lifecycle/token/policy/status/notice及服务端业务revision全部进入Contracts counter registry；每层只能推进自己拥有的计数器，MAX后按冻结作用域零写、只读或安全终止，禁止换identity/时间戳绕过。
- 上传采用per-key causal/no-effect链、ack→apply gate和ack-only尾部确认；rejected本机意图进入可恢复failed-local，不被当作pending或权威conflict。
- 本机导入使用source epoch独占lease、隔离staging、完整服务端publish、权威change apply、guest compare-and-retire和cleanup-confirm；HTTP commit成功不等于本机完成。
- Anniversary 保持 date-only，不擅自新增实体 timezone；Category sync 在新生命周期 ADR 接受前保持 blocked。
- 当前 HTTP status、`ApiResult`、`Retry-After`、通用 Idempotency-Key 与实现漂移进入 Backend HTTP Calibration ADR，客户端在冻结前不得选择其中一套写死。
- 当前 Flutter 根级长期 Controller、单一 Profile cache和全局 Search History 都被列为 workspace 隔离任务；Search History 固定采用workspace-scoped方案，旧全局v1只迁入guest一次，不再保留“隔离或清空”二选一。
- WorkManager唯一链采用`APPEND_OR_REPLACE`并以Android耐久有界唤醒合并器及C++状态恢复兜底；该policy不被描述为去重，同一workspace最多保留一个running与一个successor，不再允许KEEP/append或队列上限由实现者任选。
- workspace timezone与OS device timezone是两条明确轴；`follow_device`只跟OS。默认提醒方式按目标适用矩阵选择首个合法候选，无交集时不自动预选，不静默回退。
- guest导入只退休可迁移live图；非终态本机执行用`source_migrated`终结，终态Reminder/Notification审计留在guest且保持引用完整，不复制到账号。
- 重复Event三作用域编辑退回R3；R2-C只同步当前整系列update与已有occurrence状态能力。
- SQLCipher、三 ABI、WAL、密钥丢失和性能仍是生产账号 workspace 的硬门禁；未通过时只允许算法层测试，不得声称加密缓存可交付。
- Android当前没有显式备份规则；Backup/Device Transfer ADR签署并验证前，不能依赖平台默认值宣称重装后新installation、账号缓存隔离或游客恢复语义成立。

这些目标与 `docs/architecture/overview.md` 的 Local-first、Contract-first、薄边界、C++ 领域真相源、Kotlin 平台副作用和真实适配器发布规则一致。§1.1给出唯一裁决顺序；Contracts-02列出的ADR、DDL表示和fixture仍是显式门禁。只有这些门禁关闭并由validator证明后，才能把“无实现层自由分支”作为完成结论；当前只能说已把已知分支收口为单一目标。

跨层集成、双真机、弱网、恢复、性能和测试服务器验收不再拆成第六个模块计划，由本总计划 §17.6–§17.8、§18–§21 和 §26 统一统筹。五个实现层各自完成时只能标记 `Layer Complete / Awaiting Integration`。

顺序要求：

- 02 冻结前，其他计划只能做只读盘点和 spike。
- 03 与 04 可在 02 冻结后并行。
- 05 依赖 02，并在会话 ADR 接受后推进。
- 06 可使用 Contract fixture 和测试 Fake 并行，但不得接入运行时 Fake。
- 最终统筹验收必须使用同一真实 APK、真实 SQLite、真实 Backend 和至少两台设备。

## 26. 完成定义

只有同时满足以下条件，V1 才能报告为“内测完成”：

- [ ] 本计划的 V1 范围均有真实实现，没有占位或运行时 Fake。
- [ ] 机器 Contract 已冻结并与各层一致。
- [ ] 普通账号 LocalUser mutation、冲突解决 intent、Import staging/manifest 均与各自 Outbox 原子提交；GuestLocal、RemoteApply、ProfileCache/ServerSnapshot、device-local effect 的零 Outbox 例外全部由 writer registry 验证。
- [ ] transport fence、ack→apply/ack-only、per-key causal/no-effect、failed-local 和 source epoch/import lifecycle 已通过跨层强杀与竞态验收。
- [ ] counter registry全部owner已通过max−1→MAX、MAX后重试、并发和response-loss跨层验收，稳定错误与安全出口一致。
- [ ] Backend 每条接受变化均与 change feed 原子提交。
- [ ] 两台真实设备能在离线、并发、删除、冲突和重试场景下收敛。
- [ ] 冲突管理入口、红点、详情和四种解决方式可用。
- [ ] 游客/账号/多账号缓存不存在数据泄露。
- [ ] 退出、撤销和 30 天清理满足已确认语义。
- [ ] 提醒规则同步但系统状态不上传，未出现重复提醒。
- [ ] Android备份/设备迁移规则已验证：账号、敏感生命周期材料和guest库均未进入cloud backup；direct-transfer若获准则证明非云通道、开放前安全re-home及双目标不复用lineage/lease。
- [ ] 100 账号容量基线通过。
- [ ] Contract、C++、Backend、Kotlin、Flutter、Android 和端到端验证全部实际执行。
- [ ] git diff 和 git status 证明没有覆盖用户已有修改或混入无关变更。
- [ ] docs/log.md 记录每个阶段的真实结果和未验证项。

内测完成仍不等于公开发布；第 21.2 节门槛必须另行完成并验收。

## 27. 本计划之外

- 不在本任务中实现 V1.1 历史版本或 V2 用户备份。
- 不实现 FCM、服务端到期提醒、邮件/微信提醒。
- 不实现附件同步、共享日历或多人协作。
- 不升级到高可用集群。
- 不把 CentOS 7 测试部署包装成生产部署。
- 不在 Contract 冻结前直接修改业务代码。
