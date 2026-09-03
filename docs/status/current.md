# ExcellentCalendarAPP 当前状态与 R2 入口基线

> 研判时间：2026-09-02 22:31（Asia/Shanghai）
>
> 研判口径：以当前生产代码、机器 Contract、调用链、自动化测试和 `docs/log.md` 中最近一次实际验证记录为依据。计划归档不等于 Contract 已激活，代码存在也不等于生产环境或完整设备矩阵已经通过。
>
> 状态定义：**已实现/已激活**＝生产链存在且对应 Contract 为 `integrated + active`；**代码已实现/待激活**＝实现和测试存在，但机器 Contract 仍为 `planned` 或缺少发布校准；**部分实现**＝只有部分层级、部分入口或部分场景；**未实现**＝只有 Schema、说明或占位页面。

## 一、阶段结论

项目已经完成 R1 的主体工程建设，**从 2026-08-28 起进入 R2 开发阶段**。当前不是“R1 所有发布债务清零”，而是以下前置能力已经足以支撑 R2 的 Habit、日历视图、搜索和后续同步开发：

- Flutter → Kotlin → JNI → C++ → SQLite Storage v5 → Android Alarm/Notification/Ring 本地主链路已形成；Storage v5 机器 Contract 已为 `integrated + active`；
- Event、Recurrence、Reminder、Anniversary、Category 已有真实本地闭环；
- 响铃一期 Contract 已激活，并完成一台国产 ROM 真机门禁；
- 认证与个人资料的 Cloud Backend、Flutter 页面、会话恢复和 Android Keystore 代码已实现；
- 主界面已经形成“日程 / 日历 / 搜索 / 我的”四 Tab 结构，其中“我的”接入真实个人资料，Calendar 与 Search Tab 均已接入真实 production composition，并已按 2026-09-02 产品发布决定激活；
- Habit V1 已完成 Contract、C++ Core、SQLite v5、Kotlin/JNI/Android、Flutter/Appearance 和真实 production composition；白盒复核及后续黑盒确认的运行时、UI、分页与默认期限缺陷均已返修，主机门禁、production Habit JNI/SQLite v5 和已执行实机主链路通过。产品负责人于 2026-08-31 接受剩余设备矩阵为非阻断发布验证债后，Habit/Appearance 与 Storage v5 已统一为 `integrated + active`。
- Calendar V1 已完成此前独立 Review 问题返修和复验；产品负责人明确接受 `OPEN-CAL-001` 的七项正式签名、设备与恢复矩阵为非阻断发布债，`calendar.*` 已统一为 `integrated + active`。Release 签名门禁已 fail-closed，但当前没有生产密钥签名或商店校验过的正式产物。
- Search V1 Revision 2 已完成 C++/SQLite、Kotlin/JNI/AtomicFile History、Flutter 页面和真实生产链路汇整；独立 Review 与 Android 13 真机门禁已完成。产品负责人明确接受 `OPEN-SEA-001` 的搜索框 TalkBack 语义和正式签名链为发布后债，统一 Search Query 与 History 能力已切换为 `integrated + active`；SearchIndex/FTS 仍为 deferred/planned。
- Local-first 云同步已完成产品决策并建立 active 总计划，当前为 `ACTIVE PLAN / CONTRACT PENDING`；仍无生产同步 Contract、服务端日历业务表或客户端同步引擎，尚未进入实现阶段。

R2 当前工作重心已经从 Habit、Calendar、Search 的功能交付转为“已发布能力维护 + 开放验证债收口 + Local-first 云同步 ADR/Contract”。R1 遗留的 Contract 状态、生产部署、设备矩阵和若干产品闭环仍需并行偿还，不能因阶段切换而从发布门禁中消失。

## 二、完成度研判

| 维度 | 当前研判 | 主要依据 |
| --- | ---: | --- |
| 工程与跨层基础 | 约 92% | Contract、typed DTO、模块化 Kotlin Handler、JNI/C++ Boundary、SQLite v5、Calendar/Search 查询链与测试入口均已建立 |
| 本地核心业务 | 约 92% | Event/Recurrence/Reminder/Anniversary/Category/Ring/Habit/Calendar View/Search 已落地并激活；开放验证债持续跟踪 |
| 用户可见产品功能 | 约 70% | 日程、纪念日、Habit、Calendar View、认证、个人资料、响铃与 Search 均有真实页面；发布后矩阵和通知历史等仍未闭环 |
| 账号与云端 | 约 30% | 认证/资料后端和客户端代码已实现；Contract 未激活；云同步只完成需求与架构盘点，设备/备份尚未实现 |
| 整体产品范围 | **约 66%** | 按可交付功能闭环加权，不按文件数量计算；Habit、Calendar 与 Search 按带已接受验证债的发布能力计入，同步等大项仍未闭环 |

该百分比只用于阶段判断。R2 的完成度仍应以对应计划（若已建立）的验收清单、Contract 状态和实际验证结果为准。

## 三、已实现并可作为 R2 基座的能力

### 1. 本地 Calendar Core

- Event 支持创建、查询、详情、更新、软删除、完成、重新打开、分页筛选与排序；Flutter 普通日程详情目前只完整开放“完成”，其余 Native 能力尚未全部产品化。
- Recurrence 支持 occurrence 展开、完成、重开、跳过、取消，以及系列编辑和生命周期操作。
- Reminder 支持创建、更新、取消、调度 CAS、投递准备/完成、失败恢复和重启/时间变化后的对账。
- Anniversary 支持公历一次性/年度重复、CRUD、倒计时、Reminder R1、date-only occurrence 查询和通知点击详情。
- Category 的 list/create、Event 关联、SQLite 事务写入与真实生产入口已接通，当前领域与机器 Contract 状态为 `integrated + active`。
- Calendar Core 的 Storage v5 writer、v4→v5 migration 和四个 Habit Store/八个索引已落地并激活；机器 Storage Contract 声明 v5 为当前 `integrated + active` writer。JSON v1/v2/v3 不再作为运行时双 writer，继续承担连续迁移来源与降级 guard。

### 2. Calendar View 与 Search 已激活

- Calendar View 已通过 `calendar.range_summary`、`calendar.list_day_items` 聚合 Event occurrence、Habit 日状态和 Anniversary occurrence，并完成 Flutter → Kotlin → JNI → C++ → SQLite v5 的真实生产接线；2026-09-02 产品负责人接受 `OPEN-CAL-001` 的七项发布后债务后，机器状态为 `integrated + active`。
- Search V1 已完成 `search.query` 的三类 canonical 查询链、独立 section pagination、Kotlin `AtomicFile + noBackupFilesDir` 本地历史、Flutter 搜索/筛选/历史/详情回流页面和 production composition；主机与 Android 13 设备门禁通过，机器状态为 `integrated + active`。
- Calendar 与 Search 的激活来自完整生产接线、已有主机/设备证据和产品负责人对剩余矩阵的明确接受，不表示 `OPEN-CAL-001` 或 `OPEN-SEA-001` 已验证关闭。

### 3. Android 通知与响铃

- Popup 通知具备权限、渠道、AlarmManager、系统事件恢复、点击路由和 C++ 投递状态回写。
- Ring 支持铃声设置/选择、声音与振动、活动会话、关闭、完成、固定 10 分钟稍后、五分钟安全停止和进程恢复。
- 七个 `ring.*` MethodChannel、`ring.state_changed` EventChannel 与内部 `reminder.snooze` 已统一为 `integrated + active`。
- 一期发布门禁使用 realme RMX5100 / Android 16（API 36）真机完成；API 24/31/33/34/35 被批准为后续兼容债务，不应描述为已经验证。

### 4. 认证、账号与个人资料代码

Cloud Backend 已实现 16 个认证/个人信息端点：

- 注册、重发验证码、验证、登录、Refresh Token 原子轮换、logout/logout_all；
- 忘记/重置/修改密码，修改邮箱申请与确认；
- 当前用户读取与局部更新；
- 头像上传、删除和内部下载；
- PostgreSQL + Flyway V1–V3、JWT、Argon2id、幂等、限流和 SMTP 适配。

Flutter/Android 已实现：

- 登录、注册、邮箱验证、忘记/重置/修改密码；
- 启动会话恢复、401 单飞刷新、失败统一清态；
- Android Keystore AES-256-GCM 保存 Refresh Token；
- 个人资料查看/编辑、修改邮箱、账号安全和头像展示/删除；
- “我的”主 Tab 使用真实 AuthService/ProfileController 数据链路。

重要边界：`contracts/backend_api.yaml` 顶层及 16 个端点仍标记为 `implementation_status: planned`，四个 `auth.refresh_token.*` MethodChannel 也仍为 `planned`。因此这些能力应描述为**代码已实现并完成开发联调，但机器 Contract 尚未激活**，不能写成正式发布状态已经 active。

### 5. 工程验证基线

最近且仍代表当前工作树的分层验证证据包括：

- 2026-09-02 Calendar：独立复审确认 Reminder recovery、completed-series cutoff、历史日期 Event、全天提醒、23 点默认时间、Native 错误映射和创建按钮布局等返修生效；Calendar Contract、C++ build-after-test 13/13、Flutter 全量 592/592、`flutter analyze`、Android unit/lint/androidTest/Debug、三 ABI，以及 RMX3687 Android 13 隔离 JNI/SQLite/基础 UI 路径通过。旧 Release APK 复用 Debug 证书的问题已修复为正式配置与固定指纹 fail-closed，并以一次性非生产密钥验证 APK/AAB；激活后 Calendar validator 为 `213 schemas / 19 fixtures / 2 public methods / 2 native calls / integrated+active`。生产密钥、商店上传及其余设备/恢复矩阵仍由 `OPEN-CAL-001` 跟踪。
- 2026-09-02 Search：completed-series cutoff、History CAS、Unicode/空白、Tab/lifecycle、有界 recurrence、seeded 三类查询、6 秒撤销、本地化、AtomicFile 强杀恢复、中文 IME、旋转和代表设备性能均完成返修或复审；Search Flutter 定向 41/41、全量 592/592、`flutter analyze`、Android unit/lint/三 ABI/Debug/androidTest、C++ build-after-test 13/13 通过。RMX3687 Android 13 上连续通过 Event/Habit/Anniversary Unicode 查询与清理，Awake 状态 10k warm P95 为 `207.769 ms`；激活后 Search validator 为 `213 schemas / 31 fixtures / 3 public methods / 1 native call / integrated+active`。搜索框控件角色 TalkBack 语义和正式签名链继续由 `OPEN-SEA-001` 跟踪。
- 2026-09-02 共享 Contract 回归：Calendar、Search、Habit、Anniversary validator 均通过；Habit 为 `213 schemas / 46 fixtures / 4 identity vectors / 12 public methods / 11 native calls / integrated+active`，Anniversary 为 `213 schemas / 56 fixtures / 20 identity vectors`。这次发布状态校准未重复执行 Habit 全量主机或真机矩阵。
- 2026-08-31 Habit：发布前主机门禁通过 C++ build-after-test 10/10、Flutter 全量 447/447、`flutter analyze`、Debug APK、Android unit/lint/androidTest、Native smoke 和三 ABI 11/11 JNI 导出；此前 Android 13/16 真机已覆盖 production JNI/SQLite v5、创建/打卡/撤销/持久化、同日补发和 Binary 通知快捷完成。剩余系统行为矩阵仍由 `OPEN-HAB-001` 跟踪。
- 2026-08-27 Cloud Backend：`mvnw verify` 通过 91 个 JVM/上下文测试和 58 个 PostgreSQL 集成测试，开发环境 SMTP 日志确认真实邮箱投递；正式生产部署、密钥轮换、SMTP 运维和多实例限流仍未验证。
- 2026-08-23 Ring：realme RMX5100 / Android 16 真机 quick、five-minute、restart prepare/verify 验收通过；API 24/31/33/34/35 仍是兼容债。

Habit 最近一次主机门禁已经覆盖 Contract、C++、Flutter、Android、APK、JNI 符号与 Native smoke。真实设备已通过 production JNI 11/11 与 SQLite v5、创建/打卡/撤销/持久化、权限关闭提示、同日补发和 Binary 通知快捷完成；仍未覆盖重新授权自动 reconcile、跨午夜、进程死亡/设备重启、时区/系统时间变化、数量型/重复/陈旧 action、通知点击真实详情和完整 TalkBack。产品负责人已将这些项目接受为 `OPEN-HAB-001` 非阻断发布债；主机或 Robolectric 结果仍不能把它们改写为已验证。

## 四、R1 遗留债务

### 1. Contract 与发布状态

- Backend API 与 Auth Refresh Token MethodChannel 存在“代码已实现、Contract 仍 planned”的明确差异；进入同步开发前必须专项审查并由负责人决定是否激活。
- `notification.list` 有 MethodChannel 声明和 C++ 能力，但 Kotlin `NotificationMethodHandler` 未注册，Flutter 也没有通知历史页。
- Habit、Calendar 与 Search 的代码、真实生产接线和机器 capability 已统一为 `integrated + active`；剩余验证债分别见 `OPEN-HAB-001`、`OPEN-CAL-001` 与 `OPEN-SEA-001`。Sync、AI 等仍不得因为只有 Schema 或能力名就计为已实现。

### 2. 本地产品闭环

- 普通日程详情只接入完成操作；编辑、删除、重新打开等 Native 能力尚未形成与重复日程同等级的完整 UI。
- Calendar View 已完成页面、真实查询链、production composition、独立返修复验与发布状态切换；正式签名、设备、无障碍和恢复矩阵由 `OPEN-CAL-001` 继续跟踪。
- Search V1 Revision 2 已完成独立搜索页、筛选、本地历史、三类 canonical 查询、production composition、Contract/C++/Flutter/Android 主机门禁和 Android 13 设备复审；已激活能力的两项发布后债由 `OPEN-SEA-001` 跟踪。SQLite FTS 因 canonical 查询达到性能门禁而继续 deferred，不属于已发布能力。
- 通知历史、统一提醒管理、设置/更多、Category update/delete/reorder 未实现。
- Anniversary 分享仍使用 Fake Gateway；农历、节日模板未实现。
- 全文索引、附件、操作日志、备份/恢复产品流程尚未形成生产实现。

### 3. 生产与兼容验证

- Backend 尚无正式生产部署、生产 JWT 密钥轮换、生产 SMTP 运维验收或多实例限流方案；当前限流为单实例内存实现。
- API 24/31/33/34/35、更多国产 ROM、权限拒绝/恢复、时区/DST、陈旧 Alarm、重启和长离线矩阵不完整。
- SQLite v5 尚未完成物理断电、磁盘耗尽和长期压力测试；进程强杀测试不能替代硬件掉电。

## 五、R2 当前范围与开发拓扑

### R2-A：Habit V1（已发布，进入维护轨）

`docs/plan/completed/习惯-01-Habit与HabitCheckIn闭环开发计划.md` 所定义的生产功能已发布，`习惯-02/03/04/05` 均已归档到 `docs/plan/completed/` 并接入同一真实生产链；并行期运行时 preview/Fake composition 已删除，测试专用 Fake 保留为回归资产。本轮黑盒确认的卡片进度表达、超过 100 条列表分页、数量型圆圈剩余量、occurrence 技术文本和默认 30 天问题已关闭。未完成的真机系统行为矩阵继续由 `OPEN-HAB-001` 验证，Review 与 ADR 的局部状态清理由 `OPEN-HAB-002` 处理，二者均不改变当前 `integrated + active` 状态。

### R2-B：日历、四象限与搜索

- 月/周/日视图统一消费 Event occurrence、Anniversary occurrence 和 Habit 日状态；
- 四象限基于既有领域字段筛选，不建立第二套 Event 状态源；
- 搜索先定义三类聚合、date/datetime、occurrence、中文匹配、cursor 和历史验收；V1 先查询 canonical 数据，只有代表性性能门禁不达标时才进入 SearchIndex/FTS Schema 与迁移轨道；
- 月/周分类日历已按 Contract/数据、C++/SQLite、Kotlin/JNI、Flutter 四轨完成代码实现并接入真实 production composition；独立复审确认此前代码 Finding 已返修，已有主机、三 ABI、Android 13 隔离 JNI/SQLite/基础 UI，以及 Release 签名 fail-closed 与一次性非生产密钥 APK/AAB 验签证据。产品负责人于 2026-09-02 接受 `OPEN-CAL-001` 七项为发布后债，能力已切换为 `integrated + active`，计划和 Review 归档；当前仍没有生产密钥签名或商店校验过的正式包。
- 独立搜索已完成 Search V1 Contract Revision 2、C++/SQLite、Kotlin/JNI/AtomicFile History、Flutter 页面和真实 production composition。History CAS、Unicode、Tab/lifecycle、recurrence 有界展开、completed-series cutoff、seeded 三类查询、撤销时限、本地化、History 强杀恢复、中文 IME、旋转与代表设备性能均已返修或验证；产品负责人接受 `OPEN-SEA-001` 两项发布后债后，`search.*` 已为 `integrated + active`。SearchIndex/FTS 继续 deferred/planned，四象限仍没有 active 实施计划。

### R2-C：Local-first 云同步

2026-09-03 已完成多轮产品访谈并建立 `docs/plan/active/云同步-01-Local-first多设备同步开发计划.md`。游客/账号 workspace、退出缓存、同步实体闭包、提醒意图与设备投递、个性化白名单、字段级冲突、180 天 tombstone、无 FCM 弱网策略及内测发布边界已经冻结；当前状态切换为 `ACTIVE PLAN / CONTRACT PENDING`，尚未进入产品代码实现。

工程上下一步必须先完成计划中的 ADR、账号数据库加密 spike 和 Backend/Auth Contract 状态校准，再冻结与本地业务写同事务的 Outbox、服务端 change sequence/cursor、设备顺序号、实体/字段版本、删除 tombstone、服务端日历业务表及正式迁移。现有 `sync.apply`、`SyncOperation`、`SyncResult` 和 Backend `sync/calendar` 包仍只是概念占位；当前没有生产同步 API、账号分区、本地 Outbox、设备注册或客户端同步引擎。Appearance 的账号同步必须通过显式 Contract revision，游客设置继续保持本机所有权。

### 并行维护轨

R2 开发期间持续偿还 R1 债务：Auth Contract 状态校准、通知历史缺口、普通日程管理 UI、备份/恢复演练和设备兼容矩阵。维护轨不得无计划地扩大 R2 单个功能的修改范围。

## 六、当前不应宣称完成的能力

- 四象限、SearchIndex/FTS；已激活的独立搜索不等于 `OPEN-SEA-001` 两项债务已关闭，也不代表已有正式签名商店产物；
- 已完成正式签名、商店上传、完整时区/DST、TalkBack、大字体/减少动画、强杀恢复、升级回滚/密钥恢复和正式 Release UI 全链验证的 Calendar 分发产物；
- Local-first 同步、设备管理、云备份与冲突解决；
- 账号/后端 Contract 已 active 或后端已生产发布；
- 通知历史、完整提醒管理、普通日程完整编辑管理；
- AI/OCR/分享接收、附件、微信、Widget、农历和完整节假日库；
- API 24–36 与主流 ROM 的完整兼容矩阵。

## 七、最终判断

当前仓库已经具备 R2 所需的本地核心、账号代码基座、已激活的 SQLite v5、通知/响铃和主导航结构。Habit V1、月/周分类日历与独立搜索均已完成分层实现、真实集成、问题返修和发布状态切换，当前进入带明确开放验证债的维护阶段；Local-first 云同步已经完成产品决策并建立 active 总计划，当前处于 ADR、加密可行性和生产 Contract 门禁，尚未开始分层实现。

阶段切换的准确表述是：**R1 主体工程完成，项目进入 R2 开发；R1 的 Contract 激活、生产部署和兼容验证债务继续跟踪。**
