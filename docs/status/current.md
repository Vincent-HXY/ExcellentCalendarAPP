# ExcellentCalendarAPP 实时代码进度研判

> 研判时间：2026-08-14（Asia/Shanghai）  
> 研判口径：结论来自当前代码、生产组合入口、跨层调用链、持久化实现、自动化测试和本次实际构建结果；项目进度类文档未作为“已完成/未完成”的判断依据。  
> 状态定义：**已实现**表示生产代码存在真实调用链且有自动化验证；**部分实现**表示仅部分层级、部分场景或仅测试环境可用；**未实现**表示只有协议/目录说明/占位包，或没有生产代码。

## 一、总体结论

项目已经越过“工程骨架”阶段，进入了**本地核心功能成形、产品外围功能仍大量缺失**的阶段。

当前最完整的产品闭环是：

```text
Flutter 今日/收件箱与日程页面
  → Dart Application / typed Gateway
  → Kotlin MethodChannel
  → JNI
  → C++ Core
  → JSON 本地存储
  → Android AlarmManager / Notification
```

从整个产品规划范围衡量，建议把当前总体完成度理解为：

| 维度 | 代码完成度研判 | 说明 |
| --- | ---: | --- |
| 工程与跨层基础 | 约 80% | Flutter/Kotlin/JNI/C++ 分层、统一返回、时区和测试体系已经建立 |
| 本地核心业务 | 约 65%–70% | Event、Recurrence、Reminder、Anniversary 较完整；Category 尚未解除发布阻断；Habit 未开始 |
| 用户可见产品功能 | 约 35% | 目前主要是今日列表、日程创建/详情、重复日程操作、分类选择、纪念日 |
| 云端与扩展能力 | 约 5%–10% | 只有 Spring Boot 基础设施和协议，业务 API、数据库表与客户端接入均未实现 |
| 整体产品范围 | **约 40%** | 这是按功能闭环和可交付性加权的工程研判，不是按文件数量计算 |

因此，当前版本可以视为“本地日程核心的开发版”，还不能视为功能完整或具备正式发布条件的 V1。

## 二、已经实现的内容

### 1. 日程 Event 主链路

- 已有真实生产调用链：Flutter → Kotlin → JNI → C++ → JSON Storage。
- 支持日程创建、查询、详情读取、更新、软删除、完成和重新打开。
- 支持定时日程与全天日程，保存 UTC 时间点、本地日期和 IANA 时区。
- 支持标题、内容、地点、状态、分类、重要程度、时间范围、来源、是否重复等条件过滤，并支持分页和排序。
- 今日/收件箱页面会真实读取活动日程和已完成日程，不依赖假数据。
- 普通日程详情与完成操作已接入；重复日程详情提供更完整的编辑和生命周期操作。

主要代码证据：`flutter_client/lib/main.dart`、`flutter_client/lib/presentation/inbox/`、`flutter_client/lib/presentation/event_detail/`、`cpp_core/src/application/event_service.cpp`、`cpp_core/src/storage/json/json_event_repository.cpp`。

### 2. 重复日程 Recurrence

- C++ Core 已实现重复规则、occurrence 动态展开和 occurrence 独立状态。
- 支持 occurrence 的完成、重新打开、跳过和取消。
- 支持整个系列的完成、重新打开、取消和删除。
- Flutter 已有重复日程详情、occurrence 操作和整个系列编辑页面。
- 新建页面当前开放一次、每天、每周、每月规则。

主要代码证据：`cpp_core/src/application/recurrence_service.cpp`、`cpp_core/src/application/recurring_event_*`、`flutter_client/lib/application/event/recurring_event_*`、`flutter_client/lib/presentation/new_schedule/edit_recurring_event_*`。

### 3. 提醒 Reminder 与 Android 通知

- 支持提醒创建、更新、取消、列表和调度对账。
- C++ 已实现可调度提醒查询、调度 CAS、投递准备/完成、失败与恢复批次等核心流程。
- Android 已实现 AlarmManager 调度、开机/升级/时区变化/系统时间变化后的恢复入口。
- 已实现通知渠道、通知权限查询与申请、设置页跳转、通知展示和通知点击路由。
- 日程变更后会触发提醒调度对账；应用恢复前台时也会安排调度检查。

主要代码证据：`cpp_core/src/application/*reminder*`、`flutter_client/android/app/src/main/kotlin/.../android/alarm/`、`.../android/notification/`、`flutter_client/lib/app/bootstrap/`。

### 4. 时区与本地时间

- 已接入设备时区读取、本地日期时间解析、UTC instant 本地化。
- C++ 内置 TZDB 与本地时间解析器，可处理夏令时 gap/fold。
- Flutter 新建和编辑流程会通过时区服务处理时间，而不是直接假定设备偏移量。

主要代码证据：`cpp_core/src/infrastructure/time/tzdb_local_time_resolver.cpp`、`flutter_client/lib/application/timezone/`、Kotlin `bridge/runtime/`。

### 5. 纪念日 Anniversary V1

- 生产入口使用真实 Native Gateway，不使用假纪念日仓库。
- 支持创建、修改、软删除、详情、列表和倒计时预览。
- 支持一次性与每年重复纪念日，倒计时按用户时区的本地自然日计算。
- Flutter 已有列表、新建、详情、编辑和删除页面。
- 使用独立 C++ Domain、Application Service、JNI 接口和 JSON 事务存储。

主要代码证据：`flutter_client/lib/application/anniversary/`、`flutter_client/lib/presentation/anniversary/`、`cpp_core/src/application/anniversary_*`、`cpp_core/src/storage/json/json_anniversary_transaction.cpp`。

### 6. 工程与测试基础

- Contract、Dart DTO、Kotlin Contract、JNI Boundary、C++ Domain/Repository 已形成较清晰的分层。
- NativeResult/NativeError、稳定错误码、snake_case payload 和版本化 JSON Storage 已落地。
- Spring Boot 后端具备 API/Worker/Scheduler 运行角色、基础安全配置、CORS、request id、UTC/JPA/Flyway 配置和 PostgreSQL 集成测试框架。
- 主 Android Debug APK 当前可以成功构建。

## 三、部分实现、尚不能视为完成的内容

### 1. Category 分类

已经存在：

- Flutter 分类列表、选择器、新建分类页；
- `category.list`、`category.create` 的 Dart/Kotlin/JNI/C++ 实现；
- 独立 `categories.json` 存储；
- Event 与 Category ID 的关联展示和查询过滤。

尚未完成：

- Contract 中两项能力仍标记为 `implemented_unintegrated + blocked`，但生产入口已经注入 NativeCategoryRepository，代码状态与发布状态不一致；
- 只有 list/create，没有 update/delete/reorder；
- 尚未完成可靠性与正式 APK 全链路发布门禁；
- Category 原子写入/错误语义仍需要专项收口后才能解除 blocked。

结论：**代码已接通，但不能按稳定已发布功能计算。**

### 2. 搜索

- C++ Event Search 已支持关键字和多条件过滤，Flutter 今日列表也借用 `event.search` 读取数据。
- 但没有独立搜索页面、搜索入口交互、搜索历史或结果聚合。
- 当前是内核查询能力，不是完整产品搜索功能；也没有 SQLite FTS。

### 3. 普通日程编辑与管理体验

- Native 层具备 update/delete/reopen 等能力。
- 重复日程详情已接入完整编辑和系列操作。
- 普通日程详情页面当前只明确接入“完成”，没有像重复日程一样接入编辑、删除、重新打开等完整 UI 流程。

### 4. 重复规则的产品开放范围

- 新建流程明确拒绝“每年”和“自定义”重复规则。
- 全天重复日程提醒、重复日程响铃提醒也存在产品限制。
- 因此底层重复引擎能力不能等同于所有重复规则均已在 App 中开放。

### 5. 提醒和通知产品能力

- 调度与投递链路已经实现，但缺少独立的提醒管理页和通知历史页。
- `notification.list` 出现在协议中，但当前 Kotlin MethodChannel Handler 没有注册该方法，Flutter 也没有通知历史界面。
- 尚未在本次研判中完成真实设备的到点触发、重启恢复、权限拒绝和国产 ROM 后台限制验证。

### 6. 纪念日扩展能力

- 农历明确未实现。
- “分享”按钮存在，但生产代码注入的是 `FakeAnniversaryShareGateway`，并没有真正调用 Android 分享能力。
- 纪念日尚未接入 Reminder/Notification、日历视图 occurrence 聚合、系统节日预设或云同步。

### 7. 本地存储

- 当前真实持久化方案是版本化 JSON 文件及事务日志，不是目标中的 SQLite 主存储。
- `local_storage/sqlite`、`sqlite_fts`、`attachment_store`、`operation_log` 目录只有说明文件，没有实现代码。
- 适合作为当前本地核心验证方案，但还不是完整的结构化存储、全文索引、附件和同步日志体系。

### 8. App 导航与页面体系

- 生产路由只有 Today、Event Detail、Anniversary List/Detail 等少量页面。
- 底部导航中的 Calendar、Location、Search、More 均是静态占位，点击回调为空。
- Habit 通知路由只会显示“内容不存在或已删除”的通用占位页。

## 四、尚未实现、应放到后续的功能

以下功能目前没有可交付的生产实现；若存在代码，也仅限 Schema、README、空 package 或基础配置。

### 本地产品功能

- Habit 与 HabitCheckIn：只有 Contract Schema，没有 Dart/Kotlin/C++/Storage/UI 实现。
- 完整日历视图：月/周/日视图、日期区间聚合、纪念日 occurrence 合并均未实现。
- 四象限页面和业务聚合未实现。
- 独立搜索页、搜索历史、SQLite FTS 未实现。
- Location 页面或地图/地点管理未实现。
- 通知历史、统一提醒管理页未实现。
- Category 修改、删除、重排和完整生命周期未实现。
- 用户设置、更多页、数据导入导出、备份恢复未实现。

### 账号与云端

- 登录、注册、邮箱验证、Token 刷新、登出、找回/修改密码未实现。
- 用户资料、偏好设置、头像上传/删除未实现。
- 后端没有 Controller、业务 Service、Repository、JPA Entity 或正式 Flyway 迁移。
- 云同步、冲突处理、设备管理、云备份、云提醒/推送均未实现。
- Flutter 没有任何登录、注册、个人资料或云端 Gateway/UI。

### AI、导入与平台扩展

- OCR、文本提取、自然语言时间解析、AI 候选日程、分类/提醒推荐未实现。
- Android Share Receiver、图片/文件导入和 Attachment Store 未实现。
- 微信登录、分享、消息导入和推送未实现。
- 桌面小组件未实现。
- 高级导出、完整节假日库、农历和春节模板未实现。

## 五、当前发布阻断与风险

### P0：Android 最低版本兼容性未通过

本次实际运行 `lintDebug` 得到 **29 errors / 20 warnings**：

- 27 个 `NewApi`：项目最低支持 API 24，但多处直接使用 API 26 的 `java.time`，另有 API 31 的精确闹钟检查；
- 2 个 `PropertyEscape`：Windows `local.properties` 路径转义问题。

这意味着 Debug APK 虽能构建，但 API 24–25 设备存在运行时风险，当前不能按可发布版本判断。

### P0：Category 发布状态与生产接线不一致

生产 App 已调用 Native Category，但协议仍明确 blocked。必须先收口存储事务、错误码和端到端验证，再统一切换发布状态。

### P0：缺少本轮真实设备验证

本次 `adb devices -l` 没有发现连接设备。因此本轮只验证了编译、单元测试和宿主机测试，没有验证真实 Android 的通知到点、进程终止恢复、设备重启、精确闹钟权限和数据持久化交互。

### P1：协议能力与真实入口存在缺口

- `notification.list` 有协议但没有 Kotlin Handler/Flutter UI；
- Habit、AI、Sync 有协议，但没有实现；
- 纪念日分享是 Fake；
- 底部导航四个入口为空操作。

这些内容不能因为“有 Schema”而计入已完成功能。

## 六、建议的后续实现顺序

### 阶段 1：先把现有本地核心变成可发布闭环

1. 修复 Android API 24–25 兼容性和全部阻断级 Lint；重新执行 Debug 构建与低版本设备验证。
2. 完成 Category 的事务可靠性、错误码透传和正式 APK 全链路 smoke，解除 blocked。
3. 在真实设备完成 Event → Reminder → Alarm → Notification → 点击回详情，以及重启/时区变化/权限拒绝恢复验证。
4. 补齐普通日程编辑、删除、重新打开 UI；完善提醒管理和失败反馈。
5. 清理协议存在但运行时未注册的能力，尤其是 `notification.list`。

### 阶段 2：补齐本地 V1 的主要产品页面

1. 实现日历月/周/日视图和 Event/Anniversary occurrence 聚合。
2. 实现独立搜索页，先复用现有 Event Search，再评估 SQLite FTS。
3. 完成 Category update/delete/reorder。
4. 实现 Habit + HabitCheckIn 独立闭环及统计页面。
5. 实现通知历史、设置/更多页和完整底部导航。

### 阶段 3：升级持久化与账号云端

1. 设计并迁移至 SQLite Repository，补齐 FTS、附件和操作日志。
2. 实现 Spring Boot 登录/注册/邮箱验证、用户资料和头像，并创建正式 Flyway migration。
3. Flutter 接入安全 Token 存储、认证页面和个人信息页面。
4. 在本地模型稳定后实现 Local-first 同步、冲突处理、设备管理和备份。

### 阶段 4：扩展能力

1. AI/OCR/文本导入与候选日程确认流。
2. Android 分享接收、真实纪念日分享、桌面小组件。
3. 微信能力、农历、节假日、高级导出和其他增值功能。

## 七、最终判断

当前仓库已经具备可靠的跨语言架构和较强的 Event/Recurrence/Reminder/Anniversary 本地核心，自动化测试基础也明显超过普通原型；但产品界面、Habit、日历视图、搜索页、账号云端、SQLite/FTS、AI 和平台扩展仍有大面积空白，并且存在 Android 低版本兼容与 Category 发布门禁两个明确阻断。

最合理的下一里程碑不是立刻扩展云端或 AI，而是先把“日程 + 重复 + 提醒通知 + 分类 + 纪念日”收敛成一套在真实 Android 设备上稳定、可恢复、可发布的本地 V1。
