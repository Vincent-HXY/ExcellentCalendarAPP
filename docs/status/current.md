# ExcellentCalendarAPP 当前状态与 R2 入口基线

> 研判时间：2026-08-31（Asia/Shanghai）
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
- 主界面已经形成“日程 / 日历 / 搜索 / 我的”四 Tab 结构，其中“我的”接入真实个人资料，“日历”和“搜索”仍是 R2 占位入口；
- Habit V1 已完成 Contract、C++ Core、SQLite v5、Kotlin/JNI/Android、Flutter/Appearance 和真实 production composition；白盒复核及后续黑盒确认的运行时、UI、分页与默认期限缺陷均已返修，主机门禁、production Habit JNI/SQLite v5 和已执行实机主链路通过。产品负责人于 2026-08-31 接受剩余设备矩阵为非阻断发布验证债后，Habit/Appearance 与 Storage v5 已统一为 `integrated + active`。

R2 可以开始，但 R1 遗留的 Contract 状态、生产部署、设备矩阵和若干产品闭环必须并行偿还，不能因阶段切换而从发布门禁中消失。

## 二、完成度研判

| 维度 | 当前研判 | 主要依据 |
| --- | ---: | --- |
| 工程与跨层基础 | 约 90% | Contract、typed DTO、模块化 Kotlin Handler、JNI/C++ Boundary、SQLite v5、测试链路均已建立 |
| 本地核心业务 | 约 85% | Event/Recurrence/Reminder/Anniversary/Category/Ring/Habit 已落地并激活，完整日历与搜索仍待 R2 |
| 用户可见产品功能 | 约 60% | 日程、纪念日、Habit、认证、个人资料、响铃与四 Tab 外壳已有真实页面；Habit 已关闭本轮 UI 反馈，日历/搜索/通知历史等仍未闭环 |
| 账号与云端 | 约 30% | 认证/资料后端和客户端代码已实现；Contract 未激活，云同步/设备/备份未开始 |
| 整体产品范围 | **约 60%** | 按可交付功能闭环加权，不按文件数量计算；Habit 已按发布能力计入，日历、搜索、同步等大项仍未闭环 |

该百分比只用于阶段判断。R2 的完成度仍应以每个 active plan 的验收清单、Contract 状态和实际验证结果为准。

## 三、已实现并可作为 R2 基座的能力

### 1. 本地 Calendar Core

- Event 支持创建、查询、详情、更新、软删除、完成、重新打开、分页筛选与排序；Flutter 普通日程详情目前只完整开放“完成”，其余 Native 能力尚未全部产品化。
- Recurrence 支持 occurrence 展开、完成、重开、跳过、取消，以及系列编辑和生命周期操作。
- Reminder 支持创建、更新、取消、调度 CAS、投递准备/完成、失败恢复和重启/时间变化后的对账。
- Anniversary 支持公历一次性/年度重复、CRUD、倒计时、Reminder R1、date-only occurrence 查询和通知点击详情。
- Category 的 list/create、Event 关联、SQLite 事务写入与真实生产入口已接通，当前领域与机器 Contract 状态为 `integrated + active`。
- Calendar Core 的 Storage v5 writer、v4→v5 migration 和四个 Habit Store/八个索引已落地并激活；机器 Storage Contract 声明 v5 为当前 `integrated + active` writer。JSON v1/v2/v3 不再作为运行时双 writer，继续承担连续迁移来源与降级 guard。

### 2. Android 通知与响铃

- Popup 通知具备权限、渠道、AlarmManager、系统事件恢复、点击路由和 C++ 投递状态回写。
- Ring 支持铃声设置/选择、声音与振动、活动会话、关闭、完成、固定 10 分钟稍后、五分钟安全停止和进程恢复。
- 七个 `ring.*` MethodChannel、`ring.state_changed` EventChannel 与内部 `reminder.snooze` 已统一为 `integrated + active`。
- 一期发布门禁使用 realme RMX5100 / Android 16（API 36）真机完成；API 24/31/33/34/35 被批准为后续兼容债务，不应描述为已经验证。

### 3. 认证、账号与个人资料代码

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

重要边界：`contracts/backend_api.yaml` 顶层及 16 个端点仍标记为 `implementation_status: planned`，四个 `auth.refresh_token.*` MethodChannel 也仍为 `planned`。因此这些能力应描述为**代码已实现并完成开发联调，但机器 Contract 尚未激活**，不能写成正式发布状态已经 active。本次只同步文档，不越权修改 Contract 状态。

### 4. 工程验证基线

最近的分层验证证据包括：

- 2026-08-31：Habit 发布状态切换复验通过；默认创建范围按首尾计数为 30 天，Habit/Appearance validator 为 194 Schema、46 fixture、4 identity vector、12 个公开方法、11 个 internal call 且状态 `integrated+active`，Anniversary 共享回归通过；C++ build-after-test 10/10、Flutter 全量 447/447、`flutter analyze`、Debug APK、Android unit/lint/androidTest APK 和 Native smoke test/analyze/APK 均通过；
- 2026-08-31：Habit 卡片背景改为完成率、101+ 列表按 cursor 续页并按 ID 去重、数量型快捷圆圈显示剩余量/达标态、详情隐藏 occurrence 内部身份；Habit Application/Widget 定向 29/29、Flutter 全量 444/444、`flutter analyze` 与 Debug APK 通过；
- 2026-08-29：Habit 黑盒与异常数据复核中，Habit validator 通过 194 个 Schema、46 个 Habit fixture、4 个 identity vector、12 个公开方法和 11 个 internal call；Anniversary/Reminder 共享回归通过 194 个 Schema、56 个 fixture 与 20 个 vector；
- 2026-08-29：C++ 重新 configure 后 build-after-test `excellent_calendar_check` 10/10 通过；Flutter Habit 定向 36/36、全量 440/440、`flutter analyze` 与 Debug APK 通过；Android Habit/Reminder 定向与全量 unit、`lintDebug`、androidTest APK 通过；Native smoke 的 test/analyze/APK 通过；APK 三种 ABI 的 Habit JNI 均为 11/11；
- 2026-08-28：最终白盒 Review 发现的跨午夜投递、DST date-only、skipped、continuation cursor 和 partial 文案问题完成返修并通过独立复核；生产 composition 使用真实 MethodChannel/JNI/SQLite v5，无 Habit runtime Fake fallback；
- 2026-08-28：realme RMX5100 / Android 16 真机复现并修复“开启提醒后创建返回协议不兼容”，修复后完成型 21 天、09:00 每日提醒创建成功并按精确时间调度；另真机确认卡片圆环中心显示 current streak、详情删除与跳过入口可见，但未执行跳过或删除；
- 2026-08-27：SQLite v4 Anniversary/Category 隔离真机用例在 Android 13 设备通过，部分 ColorOS 二次安装用例中止，未计为通过；
- 2026-08-27：Cloud Backend `mvnw verify` 通过，91 个 JVM/上下文测试和 58 个 PostgreSQL 集成测试通过；开发环境 SMTP 日志确认向真实邮箱发信；
- 2026-08-27：R1 Flutter 回归为 400/400、`flutter analyze` 无问题、Debug APK 构建成功，并完成 RMX5100 冷启动检查；
- 2026-08-23：Ring 的 API 36 真机 quick、five-minute、restart prepare/verify 验收通过。

Habit 最近一次主机门禁已经覆盖 Contract、C++、Flutter、Android、APK、JNI 符号与 Native smoke。真实设备已通过 production JNI 11/11 与 SQLite v5、创建/打卡/撤销/持久化、权限关闭提示、同日补发和 Binary 通知快捷完成；仍未覆盖重新授权自动 reconcile、跨午夜、进程死亡/设备重启、时区/系统时间变化、数量型/重复/陈旧 action、通知点击真实详情和完整 TalkBack。产品负责人已将这些项目接受为 `OPEN-HAB-001` 非阻断发布债；主机或 Robolectric 结果仍不能把它们改写为已验证。

## 四、R1 遗留债务

### 1. Contract 与发布状态

- Backend API 与 Auth Refresh Token MethodChannel 存在“代码已实现、Contract 仍 planned”的明确差异；进入同步开发前必须专项审查并由负责人决定是否激活。
- `notification.list` 有 MethodChannel 声明和 C++ 能力，但 Kotlin `NotificationMethodHandler` 未注册，Flutter 也没有通知历史页。
- Habit 的代码、真实生产接线和机器 capability 已统一为 `integrated + active`；其剩余设备验证债见 `OPEN-HAB-001`，计划/ADR 状态尾项见 `OPEN-HAB-002`。Sync、AI 等仍不得因为只有 Schema 或能力名就计为已实现。

### 2. 本地产品闭环

- 普通日程详情只接入完成操作；编辑、删除、重新打开等 Native 能力尚未形成与重复日程同等级的完整 UI。
- 日历与搜索 Tab 是明确的开发中占位；两者均已建立 active 主计划并冻结产品需求，但页面、统一 Contract、真实查询链和必要设备验收尚未实施。独立搜索页、历史、筛选和 SQLite FTS 仍未实现。
- 通知历史、统一提醒管理、设置/更多、Category update/delete/reorder 未实现。
- Anniversary 分享仍使用 Fake Gateway；农历、节日模板和完整日历聚合未实现。
- 全文索引、附件、操作日志、备份/恢复产品流程尚未形成生产实现。

### 3. 生产与兼容验证

- Backend 尚无正式生产部署、生产 JWT 密钥轮换、生产 SMTP 运维验收或多实例限流方案；当前限流为单实例内存实现。
- API 24/31/33/34/35、更多国产 ROM、权限拒绝/恢复、时区/DST、陈旧 Alarm、重启和长离线矩阵不完整。
- SQLite v5 尚未完成物理断电、磁盘耗尽和长期压力测试；进程强杀测试不能替代硬件掉电。

## 五、R2 当前范围与开发拓扑

### R2-A：Habit V1（已发布，进入维护轨）

`docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md` 所定义的生产功能已发布，`习惯-03`、`习惯-04`、`习惯-05` 已完成各层实现并接入同一真实生产链；并行期运行时 preview/Fake composition 已删除，测试专用 Fake 保留为回归资产。本轮黑盒确认的卡片进度表达、超过 100 条列表分页、数量型圆圈剩余量、occurrence 技术文本和默认 30 天问题已关闭。未完成的真机系统行为矩阵继续由 `OPEN-HAB-001` 验证，计划与 ADR 的局部状态清理由 `OPEN-HAB-002` 处理，二者均不改变当前 `integrated + active` 状态。

### R2-B：日历、四象限与搜索

- 月/周/日视图统一消费 Event occurrence、Anniversary occurrence 和 Habit 日状态；
- 四象限基于既有领域字段筛选，不建立第二套 Event 状态源；
- 搜索先定义三类聚合、date/datetime、occurrence、中文匹配、cursor 和历史验收；V1 先查询 canonical 数据，只有代表性性能门禁不达标时才进入 SearchIndex/FTS Schema 与迁移轨道；
- 月/周分类日历已建立 active 主计划 `docs/plan/active/日历-01-月周分类视图与三类数据聚合开发计划.md`，需求已冻结并判定为 `SPECIALIST_SPLIT / Contract Pending`；下一步按 Contract/数据、C++/SQLite、Kotlin/JNI、Flutter、真实集成和独立 Review 分轨实施。
- 独立搜索已建立 active 主计划 `docs/plan/active/搜索-01-三类聚合搜索与本地历史开发计划.md`，两轮需求已冻结并判定为 `SPECIALIST_SPLIT / Contract Pending`；下一步先完成 Search Contract/数据投影，再按 C++/SQLite、Kotlin/JNI/本地历史、Flutter、真实集成/性能和独立 Review 分轨实施。四象限仍没有 active 实施计划。

### R2-C：Local-first 云同步

同步必须晚于本地实体/身份和操作日志冻结，并先解决 Backend/Auth Contract planned 状态。至少需要独立定义：变更序列、幂等键、客户端操作日志、增量游标、删除语义、冲突策略、设备身份、离线重试、加密与备份边界。当前没有生产同步 API、服务端日历业务表或客户端同步引擎。

### 并行维护轨

R2 开发期间持续偿还 R1 债务：Auth Contract 状态校准、通知历史缺口、普通日程管理 UI、备份/恢复演练和设备兼容矩阵。维护轨不得无计划地扩大 R2 单个功能的修改范围。

## 六、当前不应宣称完成的能力

- 月/周/日历、四象限、独立搜索、FTS；
- Local-first 同步、设备管理、云备份与冲突解决；
- 账号/后端 Contract 已 active 或后端已生产发布；
- 通知历史、完整提醒管理、普通日程完整编辑管理；
- AI/OCR/分享接收、附件、微信、Widget、农历和完整节假日库；
- API 24–36 与主流 ROM 的完整兼容矩阵。

## 七、最终判断

当前仓库已经具备进入 R2 所需的本地核心、账号代码基座、已激活的 SQLite v5、通知/响铃和主导航结构。Habit V1 已完成分层实现、真实集成、产品反馈返修和发布状态切换，当前进入带明确开放验证债的维护阶段；月/周分类日历与独立搜索均已建立 active 主计划并冻结需求，当前分别等待 Calendar/Search Contract 与分层子计划后启动实现；同步仍应先建立 active plan 和 Contract 门禁。

阶段切换的准确表述是：**R1 主体工程完成，项目进入 R2 开发；R1 的 Contract 激活、生产部署和兼容验证债务继续跟踪。**
