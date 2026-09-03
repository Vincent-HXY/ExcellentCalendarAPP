# 云同步-01：Local-first 多设备同步开发计划

> 状态：ACTIVE / 产品决策已冻结 / 实现尚未开始
> 建立时间：2026-09-03
> 目标阶段：R2-C
> 首发范围：Android 多设备、小规模内测，协议保持跨平台中立
> 计划入口：docs/plan/active/云同步-01-Local-first多设备同步开发计划.md

## 1. 计划结论

本计划为 ExcellentCalendarAPP 建立同一账号下的 Local-first 多设备同步能力。用户登录同一账号后，可以在多台设备看到一致的个人资料、日程、纪念日、习惯、打卡事实、分类、提醒意图和允许跨设备的个性化设置；离线时仍可编辑，恢复网络后自动收敛。

V1 的核心原则如下：

1. SQLite 仍是客户端业务真相源，云端不是本地 Core 的替代品。
2. 游客本机空间与账号空间物理隔离，本机空间永不上传。
3. 每一次账号空间业务写入，都必须在同一 SQLite 事务中写入 Outbox。
4. 服务端按账号隔离数据，使用设备身份、客户端顺序号、实体版本和增量游标完成幂等同步。
5. 不同字段的并发修改自动合并；相同字段、删除与编辑、清空与增量等真实冲突进入冲突中心。
6. 提醒只同步用户意图和模板，Android 权限、铃声、调度状态和通知历史仍属于设备本地。
7. V1 不接入 FCM，不承诺 App 关闭后的分钟级实时同步。
8. V1 只用于小规模内测。账号注销、灾难恢复备份和基础主动告警完成前，不进入公开发布。

## 2. 当前基线与差距

| 能力 | 当前事实 | 本计划要求 |
| --- | --- | --- |
| 本地业务数据 | C++ Core + SQLite v5，包含 Event、Recurrence、Reminder、Anniversary、Category、Habit、HabitCheckIn 等 | 升级为账号感知的 workspace 与同步元数据存储 |
| 本地数据目录 | Android 生产运行时固定解析到单一 local_storage/calendar_core_storage_json | 拆分游客 workspace 和每账号独立 workspace |
| SQLite 加密 | 当前使用仓库内普通 sqlite3.c，没有账号数据库加密 | 建立每账号独立密钥、Keystore 包装和数据库加密方案 |
| Outbox | 不存在 | 与所有账号空间业务写同事务产生 |
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

## 3. 已冻结的产品需求

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
- [x] 重新开启后先拉取云端变化，再上传和合并本机待同步修改。
- [x] 触发时机包括：本地写入后的机会调度、App 前台启动、回到前台、网络恢复、WorkManager 后台机会和手动同步。
- [x] 无 FCM；后台同步只承诺尽力执行。

### 3.3 退出、缓存和多账号

- [x] 退出前在线时先尝试最后一次同步。
- [x] 有未上传内容时显示具体数量，允许取消退出或确认继续。
- [x] 退出后删除令牌、关闭数据库、清理内存、停止该账号同步任务并取消该账号提醒。
- [x] 保留的账号缓存完全不可见，只能重新登录同一账号后解锁。
- [x] 缓存保留 30 天；到期后在下次 App 启动或系统允许的清理任务中删除。
- [x] 30 天到期仍删除未上传内容，因此退出确认必须明确告知风险。
- [x] 提供“立即清除此设备缓存”。
- [x] 被撤销设备下次联网后退出账号并销毁对应密钥和缓存。

### 3.4 冲突

- [x] 不同字段的并发修改自动合并。
- [x] 同一字段被不同设备修改时生成可见冲突。
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
- [x] 账号级设置关闭时，其他设备仍下载提醒规则，但不安排本机通知。
- [x] Android 通知权限、精确闹钟能力、电池优化、铃声 URI、震动能力、已安排 Alarm、响铃会话和通知历史不上传。
- [x] 云端不负责到期弹窗或响铃。
- [x] 拉取提醒变化后，由 Kotlin 触发现有本地提醒 reconcile。

### 3.7 时间语义

- [x] 普通定时日程保存 UTC instant 和 IANA timezone，跨时区只改变显示，不改变真实时刻。
- [x] 全天日程使用 civil date，不做时区换日。
- [x] 纪念日和习惯打卡日使用 date-only 语义。
- [x] 重复规则绑定规则时区，沿用 Core 既有 gap/fold 规则。
- [x] 不使用设备本地时钟决定并发先后；冲突顺序以服务端版本和接收序列为准。

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
| 账号与用户资料 | email、username、display_name、头像引用、locale、timezone；沿用服务端账号/资料接口 |
| 可移植设置 | 当前已实现并经白名单声明的个性化设置，首项为 habit_progress_color |
| Category | 名称、描述、颜色、图标、排序、删除状态 |
| Event | 标题、内容、开始/结束、全天日期、状态、完成时间、分类、重要性、地点、时区、来源 |
| Event recurrence | 规则版本、系列修订、单次例外、取消/完成 occurrence 状态 |
| Event reminder intent | 提醒模板和业务启用状态 |
| Anniversary | 标题、日期、历法类型、分类、重复规则、备注、重要性、时区、提醒模板 |
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

- 初始必须支持：habit_progress_color、用户明确选择的 locale、账号 timezone、跨设备提醒默认策略。
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
- sync_state：device_id、server_cursor、cursor_generation、last_success_at、暂停状态。
- sync_outbox：device_id、连续 client_sequence、mutation_id、target_type、target_id、base_version、typed patch、状态、尝试次数、下次重试时间。
- sync_entity_state：实体服务端版本、每字段最后版本、最近 server sequence。
- sync_conflicts：冲突 ID、实体、字段集合、云端值、本机候选值、来源设备、状态和保留时间。
- sync_import_batches：首次迁移批次、源快照摘要、计数、阶段和幂等回执。
- habit_check_in_operations：增量、替换、清空命令的稳定身份与已应用状态。

要求：

- 所有账号空间 writer 必须同时更新业务表和 Outbox。
- 游客 workspace 使用相同业务 Schema，但硬性禁止生成可上传 Outbox。
- 下载批次、业务事实、冲突和 Cursor 推进必须在一个事务中提交。
- 只有完整事务成功后才能向服务端确认游标。
- SQLite v5 → v6 迁移必须原子、可重复检测、失败不发布。
- 迁移新增表会改变当前严格 schema shape，因此必须同步更新 validator 和 corruption 测试。

### 6.3 首次本机数据迁移

流程：

1. 读取游客 workspace 的一致性快照并统计各实体。
2. 展示数量和提醒影响，用户确认。
3. 创建 import_batch_id 和不可变源摘要。
4. 按实体依赖顺序导入 Category、Recurrence、Event/Anniversary/Habit、Reminder、OccurrenceState、HabitCheckIn。
5. 发生目标 ID 碰撞时按整张引用图稳定重映射，禁止只改父 ID。
6. 账号数据库在单事务中写入业务事实、Outbox 和 import receipt。
7. 校验数量、引用完整性、重复规则和提醒归属。
8. 上传可重复重试；Backend 按 import_batch_id 幂等。
9. 服务端完整确认后清理游客原记录；崩溃恢复根据 receipt 继续，不产生双份。

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
- entity_id：业务对象身份。
- mutation_id：逻辑修改身份。
- client_sequence：同一 device_id 下严格递增的上传顺序。
- entity_version：服务端接受后的实体版本。
- server_sequence：账号 change feed 中的服务端顺序。
- cursor：封装账号、generation 和最后 server_sequence 的不透明值。

不得把时间戳、数组位置、数据库 rowid 或 recurrence revision 当成同步实体版本。

### 8.2 上传幂等

- 同一设备按 client_sequence 连续上传，不允许跳号提交。
- Backend 保存该设备最高已接受序号和必要的响应摘要。
- 重复序号返回原结果，不重复执行。
- 相同序号不同 payload 返回协议错误并冻结该设备同步，等待人工诊断。
- Habit 增量操作必须同时使用稳定 operation_id，确保网络重试不会重复累计。
- 现有通用 HTTP Idempotency-Key 的 24 小时保留不足以独立承担长期离线同步，必须增加同步专用顺序与去重语义。

### 8.3 下载与游标

- Backend 为账号变化产生单调 server_sequence，允许有空洞但不能倒退。
- 每台设备保存自己的 opaque cursor。
- 响应分页必须固定快照上界，防止翻页期间新增数据造成漏项或重复。
- 客户端只在一页变化完整写入后推进 Cursor。
- Cursor 超过服务端保留窗口或 generation 不匹配时返回明确的 CURSOR_EXPIRED。
- Cursor 过期后执行全量快照，再把本地待上传修改重新基于快照合并。
- 若快照中对象已不存在，本地旧编辑转为“云端删除 / 本机编辑”冲突，不能把对象静默复活。

## 9. 字段级冲突算法

### 9.1 普通实体

每个 mutation 携带 base_version 和只包含实际修改字段的 typed patch。服务端维护实体每个可修改字段最后一次变化的版本：

1. 字段版本不晚于 base_version：接受该字段。
2. 字段版本晚于 base_version，但候选值与云端值相同：视为幂等接受。
3. 字段版本晚于 base_version 且值不同：生成字段冲突。
4. 同一 mutation 中无冲突字段可以提交；冲突字段保持云端当前值并保存本机候选值。
5. 实体版本只由服务端分配；updated_at 只用于展示。

### 9.2 删除与编辑

- 删除产生 tombstone，业务列表立即隐藏。
- 与删除并发的编辑内容进入冲突，不覆盖 tombstone。
- 冲突详情允许确认删除或以候选内容执行 restore。
- restore 是新 mutation 和新 entity_version，不回拨 server_sequence。
- tombstone 保留 180 天。
- Cursor 早于 tombstone 保留下界的设备必须全量重建，避免旧编辑造成数据复活。

### 9.3 HabitCheckIn

- increment/decrement 使用可去重的增量 operation。
- 不同设备的独立增量可交换并累计。
- replace_total、clear 与基线后的其他增量并发时生成冲突。
- 目标值和单位继续使用打卡时快照，不因 Habit 后续修改而重算历史。
- 解决冲突时生成新的聚合版本和 change feed 记录。

### 9.4 重复日程

- 系列规则、规则 revision 和 occurrence exception 使用稳定身份。
- “仅本次”“本次及以后”“整个系列”必须形成不同 typed mutation。
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

云端字段：

- reminder template、提前量、业务方式、启用意图。
- account_auto_enable_reminders_on_other_devices。
- 每设备 receive_reminders。

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
- sync_import_receipts。
- sync_tombstones 或等价删除元数据。

所有业务表必须包含 account_id，并通过 Repository 查询条件和数据库约束共同防止跨账号访问。

### 12.2 建议 API 切片

Contract 阶段应定义以下能力，最终名称以 backend_api.yaml 为准：

- device.register / list / rename / revoke。
- sync.exchange：携带 cursor、ordered upload batch 和下载页请求，一次返回 upload results、conflicts、changes、next_cursor。
- sync.bootstrap 或 cursor=null 的全量快照模式。
- sync.status。
- sync.conflict.list / get / resolve。
- local import preview/commit 属于 Native Contract，不直接作为 Backend API。

建议初始限制：

- 每个上传批次最多 100 个 mutation。
- 每个响应下载最多 500 个 change。
- 单请求解压后大小上限在 Contract 中明确，初始以 1 MiB 为候选并通过真实数据测试校准。
- 所有限制返回机器可识别错误，客户端自动缩小批次或停止重试。

### 12.3 事务要求

Backend 在单个 PostgreSQL 事务中完成：

- 校验账号和设备。
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
- [ ] 定义 batch、cursor、快照 generation、版本和分页上界。
- [ ] 为每种实体建立 typed patch，不使用 additionalProperties=true 的通用业务 payload。
- [ ] 定义上传逐项结果，区分 accepted、partially_merged、conflict、rejected、duplicate。
- [ ] 定义设备撤销、序号跳跃、Cursor 过期、批次过大和协议版本不兼容错误。
- [ ] 定义 180 天 tombstone、冲突保留和客户端重建语义。

### 13.2 Native / MethodChannel / JNI Contract

- [ ] 用批次型内部同步协议替换单条 sync.apply 占位。
- [ ] 定义 prepare_upload_batch、acknowledge_upload、apply_download_batch、get_sync_status。
- [ ] 定义 import_preview、import_commit、import_status。
- [ ] 定义 conflict_list、conflict_detail、conflict_resolve。
- [ ] 定义 workspace_list、workspace_activate、workspace_cleanup。
- [ ] 定义设备管理和同步开关的 Flutter Gateway 边界。
- [ ] 明确敏感字段和禁止日志字段。

### 13.3 Fixtures 与 Validator

- [ ] 正常创建、更新、删除、恢复。
- [ ] 不同字段自动合并。
- [ ] 同字段冲突。
- [ ] delete-vs-edit。
- [ ] Habit 独立增量、重复投递、clear-vs-increment。
- [ ] recurrence revision 和 exception。
- [ ] date-only、UTC instant、IANA timezone、DST gap/fold。
- [ ] 设备序号重复、跳跃和 payload 不一致。
- [ ] cursor tamper、过期、跨账号复用。
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
- [ ] one-time sync 使用 KEEP 或串行 append 语义，避免并发交换。
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
- [ ] 手动同步。
- [ ] 本机数据入口和迁移入口。
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
- [ ] 退出前待同步提示。
- [ ] 30 天缓存说明和立即清理入口。
- [ ] 登录其他账号后不泄露前账号标题、搜索结果、通知和组件内容。

## 17. 分阶段实施清单

### 阶段 0：ADR 与可行性门禁

- [ ] 建立同步版本、字段级合并、设备序号、Cursor、保留策略 ADR。
- [ ] 建立 workspace 生命周期 ADR。
- [ ] 建立账号 SQLite 加密 ADR 和 SQLCipher spike。
- [ ] 建立 Kotlin SessionCredentialBroker ADR。
- [ ] 确认现有实体 ID 是否满足全局稳定身份要求。
- [ ] 确认游客提醒在账号登录期间继续执行的产品假设。
- [ ] 校准 Auth / Backend Contract planned 差异。

退出标准：四项 ADR 接受，加密三 ABI spike 通过，协议不再存在关键所有权冲突。

预计：5–8 人日。

### 阶段 1：Contract 与测试夹具

- [ ] 重构 contracts/sync。
- [ ] 扩展 backend_api.yaml。
- [ ] 扩展 method_channels.yaml、native_calls.yaml、error_codes.yaml、enums.yaml。
- [ ] 修订 Appearance 本机专属语义为 workspace 感知白名单。
- [ ] 建立跨层 golden fixtures 和专项 validator。
- [ ] 冻结 SQLite v6 和 PostgreSQL 数据模型。

退出标准：机器 Contract、正反 fixture、兼容矩阵、错误码和 Validator 全部通过。

预计：8–12 人日。

### 阶段 2：C++ Core 与 SQLite v6

- [ ] workspace metadata 和 account binding。
- [ ] Outbox 与所有业务 writer 同事务。
- [ ] 同步状态、字段版本、冲突、导入批次和 Habit operation store。
- [ ] 上传批次读取与确认。
- [ ] 下载批次原子应用与 Cursor 推进。
- [ ] 字段合并、delete-vs-edit、打卡增量和 recurrence conflict。
- [ ] v5 → v6 原子迁移、失败恢复和严格 schema validator。
- [ ] 游客 → 账号导入图和可恢复状态机。
- [ ] 加密账号数据库接入。

退出标准：excellent_calendar_check 构建后测试通过；断点、重复、崩溃、磁盘失败和迁移矩阵通过。

预计：18–25 人日。

### 阶段 3：Cloud Backend

- [ ] Flyway 新增设备、日历事实、同步、冲突和 change feed 表。
- [ ] userdevice 设备注册、改名、列表、撤销。
- [ ] re-auth。
- [ ] sync exchange、bootstrap、status、conflict API。
- [ ] 账号隔离和 Repository 强制过滤。
- [ ] client_sequence 幂等、实体锁、字段版本合并。
- [ ] tombstone 180 天、resolved conflict 30 天清理任务。
- [ ] Testcontainers 并发、隔离、重试和故障测试。

退出标准：Maven test 与 verify 完整通过，集成测试没有被跳过；跨账号读取和写入均被拒绝。

预计：18–25 人日。

### 阶段 4：Kotlin / Android

- [ ] workspace registry、账号目录和 Keystore 生命周期。
- [ ] SessionCredentialBroker。
- [ ] Sync HTTP client 和 Contract mapping。
- [ ] WorkManager 唯一队列、网络恢复、前台触发和退避。
- [ ] JNI batch adapter。
- [ ] 拉取后的提醒 reconcile。
- [ ] logout、撤销、30 天缓存清理。
- [ ] Debug HTTP / Release HTTPS 网络策略。

退出标准：Kotlin 单测、Gradle test/lint、JNI instrumentation 和后台强杀恢复通过。

预计：12–18 人日。

### 阶段 5：Flutter

- [ ] 同步 Application/Gateway/DTO。
- [ ] 我的页面同步卡片。
- [ ] 本机数据与全量迁移流程。
- [ ] 冲突红点、列表、详情和解决。
- [ ] 设备管理。
- [ ] 提醒同步策略和设备开关。
- [ ] 空间隔离、退出提示和多账号缓存行为。
- [ ] 可移植个性化设置接线。

退出标准：Widget/Controller/Contract 测试、flutter analyze 和 Debug APK 构建通过。

预计：10–15 人日。

### 阶段 6：真实跨层集成

- [ ] 删除运行时占位 sync.apply 路径，保留必要测试 Fake。
- [ ] 同一 APK 接入真实 Kotlin、JNI、C++ SQLite 和 Backend。
- [ ] 两台真实 Android 设备使用同一账号。
- [ ] 覆盖弱网、断网、重试、重复响应、乱序响应和服务器重启。
- [ ] 验证事件、纪念日、习惯、打卡、提醒和设置。
- [ ] 验证冲突红点和逐字段解决。
- [ ] 验证退出隐藏、换号隔离、撤销和缓存清理。

退出标准：端到端验收矩阵全部有真实证据，不以 Fake 或单层测试替代。

预计：15–22 人日。

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

预计：5–8 人日。

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
- Backend、Dart、Kotlin、C++ 消费同一 fixtures。

### 18.2 C++ / SQLite

必须使用构建后测试：

    cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
    cmake --build cpp_core/build-ninja --target excellent_calendar_check

额外覆盖：

- Outbox 原子性。
- apply + cursor 原子性。
- v5 → v6、加密 DB、WAL、崩溃恢复。
- import crash point 全阶段。
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

### 18.4 Flutter / Android

- Flutter 全量相关测试与 flutter analyze。
- Android unit、lint、Debug 构建、三 ABI。
- JNI/SQLite instrumentation。
- 至少两台真实 Android 设备。
- 进程强杀、重启、飞行模式、切换 Wi-Fi/蜂窝、系统省电限制。
- 通知权限拒绝、精确闹钟不可用、设备时区变化。

### 18.5 端到端场景

1. A 创建，B 拉取。
2. A/B 分别修改不同字段，自动合并。
3. A/B 修改相同字段，冲突中心出现红点。
4. A 删除、B 离线编辑，删除可见且编辑候选保留。
5. 两设备分别增加习惯次数，结果正确累计且重试不重复。
6. 一台清空、一台增加，产生冲突。
7. 修改重复系列与单次 occurrence。
8. 全天、纪念日、Habit date-only 不跨时区漂移。
9. 同步暂停期间积累修改，恢复后收敛。
10. 退出时存在待上传内容，提示、保留和30天清理正确。
11. 登录第二账号，第一账号数据完全不可见。
12. 撤销设备后，下次联网清除账号缓存。
13. Cursor 过期后完整重建，不复活已删除记录。
14. 服务器处理响应后断线，客户端重试不重复写。
15. 服务端重启、数据库短暂不可用后客户端安全重试。

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
- 公网端到端验收必须使用系统信任的 HTTPS。
- 公网 IP 是否固定目前未知；计划按“可能动态”处理。
- IP 不稳定时只做短期公网验收，不把该地址写死为长期正式入口。
- 申请 IP 证书时必须自动续期；证书有效期短，续期失败必须在人工测试清单中检查。

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
- 公网 IP 稳定性未知。

### 21.2 公开发布前必须完成

- [ ] 受支持的 Linux 和受支持的容器运行时。
- [ ] 稳定 HTTPS 入口；优先使用域名。
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
| 180 天 tombstone 后旧设备返回 | 删除数据复活 | cursor expiry + bootstrap + delete/edit conflict |
| Habit 重试 | 计数重复 | operation_id + device sequence |
| 拉取后重复安排提醒 | 双通知 | workspace-aware reconcile 和稳定 schedule key |
| SQLCipher 集成失败 | 无法满足加密缓存 | 阶段 0 spike；失败即停止相关交付 |
| CentOS 7 EOL | 公网宿主机安全和容器兼容风险 | 仅短期测试，失败即换受支持系统 |
| 4 GB / 50 GB | OOM、磁盘满 | 预构建镜像、资源上限、日志轮转、容量门禁 |
| 无备份/告警 | 数据丢失发现晚 | 仅测试数据；公开发布前强制补齐 |
| 无 FCM | 后台延迟 | 文案不承诺实时；前台/网络恢复立即同步 |

## 24. 里程碑与工作量

| 里程碑 | 交付 | 预计人日 |
| --- | --- | --- |
| M0 | ADR、加密 spike、Auth 所有权 | 5–8 |
| M1 | Contract、Schema、Fixtures、Validator | 8–12 |
| M2 | C++ / SQLite v6 / workspace / Outbox | 18–25 |
| M3 | Backend 数据、设备、同步、冲突 | 18–25 |
| M4 | Kotlin / Android / WorkManager / Keystore | 12–18 |
| M5 | Flutter 同步、迁移、设备和冲突 UI | 10–15 |
| M6 | 双真机、弱网、恢复和性能集成 | 15–22 |
| M7 | CentOS 测试部署和内测放量 | 5–8 |

单人顺序执行约 91–133 人日。Contract 冻结后，M2、M3 和 M5 的可独立部分可并行，但最终仍必须经过 M4/M6 真实集成。时间估算不包含公开发布前的备份、告警、账号注销和生产基础设施。

## 25. 开发拆分与顺序

进入实现时，从本总计划拆出以下 active 分计划：

1. 云同步-02-Contracts与数据模型。
2. 云同步-03-C++与SQLite-v6。
3. 云同步-04-CloudBackend。
4. 云同步-05-Kotlin-Android与会话调度。
5. 云同步-06-Flutter产品界面。
6. 云同步-07-跨层集成与测试服务器验收。

顺序要求：

- 02 冻结前，其他计划只能做只读盘点和 spike。
- 03 与 04 可在 02 冻结后并行。
- 05 依赖 02，并在会话 ADR 接受后推进。
- 06 可使用 Contract fixture 和测试 Fake 并行，但不得接入运行时 Fake。
- 07 必须使用同一真实 APK、真实 SQLite、真实 Backend 和至少两台设备。

## 26. 完成定义

只有同时满足以下条件，V1 才能报告为“内测完成”：

- [ ] 本计划的 V1 范围均有真实实现，没有占位或运行时 Fake。
- [ ] 机器 Contract 已冻结并与各层一致。
- [ ] 账号空间每条业务写均与 Outbox 原子提交。
- [ ] Backend 每条接受变化均与 change feed 原子提交。
- [ ] 两台真实设备能在离线、并发、删除、冲突和重试场景下收敛。
- [ ] 冲突管理入口、红点、详情和四种解决方式可用。
- [ ] 游客/账号/多账号缓存不存在数据泄露。
- [ ] 退出、撤销和 30 天清理满足已确认语义。
- [ ] 提醒规则同步但系统状态不上传，未出现重复提醒。
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
