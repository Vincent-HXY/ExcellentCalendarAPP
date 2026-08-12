# ExcellentCalendarAPP 当前进度

> 更新时间：2026-08-11
>
> description ：用来描述项目当前的一个进度，每日进行总结。按照总体结论，已完成，正在完成，未完成（结合target.md），尚未验证进行分类。并指出当前可以支持完成哪些具体的操作和内容。

## 总体结论

项目已经从工程骨架进入核心闭环开发阶段，主链路已经基本打通：

```text
Flutter → Dart Gateway → Kotlin MethodChannel → JNI → C++ Core → JSON Storage → Android Alarm/Notification
```

当前最完整的已实现范围仍是“日程 + 一次性提醒 + Android 本地通知 + JSON 本地存储”。核心代码测试和 Debug 构建通过，但还不是功能完整、真机验证充分的 V1 发布版。

重复 Event 与滚动 Reminder 的 Native Contract v2 数据模型、Schema、身份、恢复批次和 Storage 规则已经完成设计并激活；C++ Core、Boundary、JSON Storage v2、Kotlin/JNI、Dart DTO/Gateway 与 Android 调度均已接入，发布状态统一标记为 `release_status: active`、`implementation_status: integrated`（2026-08-08）。

Anniversary V1 的六条公开能力已于 2026-08-10 接入 Flutter → Kotlin → JNI → C++ Core → JSON Storage，Contract 状态切换为 `implementation_status: integrated`。Anniversary 使用独立两 Store 事务和专用 journal，不改变 Event/Reminder 六 Store journal；真实 Android create → detail 持久化 → soft-delete smoke 已通过。

Category 的稳定领域模型、`category.list` / `category.create` 传输协议、Flutter typed Gateway/MethodChannel/Repository，以及 Kotlin Contract/Handler/窄 Bridge 已于 2026-08-10 补齐；2026-08-11 又冻结了独立 `categories.json` 的 Storage v2 根包络与严格记录 Schema。当前工作区已存在真实 C++ Domain/Repository/codec/bootstrap、JNI 和磁盘读写实现，因此状态不再写作 `planned`，统一改为 `implemented_unintegrated + blocked`。正式 App 仍注入 Fake，Event detail 聚合、Kotlin Event Category 校验、原子写 post-replace 失败语义、跨层数值/规范化一致性和设备 smoke 尚未完成，Category 不能宣称已发布闭环。

真实设备（realme RMX5100, Android 16 / API 36）首轮验证通过：冷启动、runtime 初始化、TZDB 2026c 解压、7 个 v2 store、事件/提醒读写、CAS 调度、Dispatcher Alarm 注册、两阶段通知投递与 Recovery 接管均正常，无崩溃。V1 数据不再保留：C++ bootstrap 确认 v1 目录后直接清理，不再创建时间戳归档；Kotlin 不再迁移 `test_storage_json`。

## 已完成

### 协议与架构

- 已建立 `contracts/`，当前包含 131 个 JSON Schema、MethodChannel、JNI 调用、错误码、枚举和返回外壳。
- Dart、Kotlin、C++ 已按 DTO、Boundary、Domain 分层，跨层调用链已建立。
- 已完成 breaking Native Contract v2 设计：Event timed/all-day 互斥时间、不可变 Recurrence revision、Occurrence 状态、确定性滚动 Reminder、两阶段 Notification、72 小时 RecoveryBatch、`runtime.initialize` 与 JSON Storage v2。
- `contracts/identity.yaml` 固定了三个 UUIDv5 namespace、规范化输入和五组跨语言测试向量；`contracts/storage/calendar_core_storage.yaml` 固定了 v1 清理（不再归档）、空 v2 初始化和 workflow journal 规则。
- 2026-08-08 已激活 Native Contract v2：`method_channels.yaml`、`native_calls.yaml`、`identity.yaml` 与 Storage map 切换为 `release_status: active` / `implementation_status: integrated`；Dart、Kotlin、JNI 与 Android 调度已全部切换到 v2。
- V1 数据不保留（用户决策）：`prepare_calendar_core_v2_storage` 在确认目录属于 v1 后直接清理，不再重命名为时间戳归档；Kotlin `CalendarCoreStorageDirectoryResolver` 不再把 `test_storage_json` 作为迁移来源。
- 已冻结调度确认 CAS、occurrence reopen successor 暂存、`ReminderStatus.expired`、prepared attempt 接管/废弃和 v2 发布/实现状态分离语义。
- 已修正 v2 finalize/list 边界一致性：adopted frozen attempt 的 `resolved_by_recovery_batch_id` 与 `recovery_batch_id` 同样要求返回 `recovery_batch`；`reminder.list.status` 已允许精确查询 `expired`。
- 2026-08-10 已实现并激活 Anniversary V1 专属 `AnniversaryRecurrence` / `anniversary_recurrences`：一次性使用 `recurrence_id=null`，年度重复只允许 `yearly + interval=1`，月/日锚点仅来自 `Anniversary.date`，未来 occurrence 由 C++ 查询时动态计算；规则创建、保留、解除与软删除均由专用两 Store 事务保证原子性。
- 2026-08-10 已冻结 Category 基础 Contract：新写 Category ID 为 canonical lowercase UUIDv4，颜色为 canonical `#RRGGBB`，active list 按 `sort_order null-last → created_at → id` 稳定排序；Event 既有 `category_id` 保持 nullable opaque string 以兼容历史值，未擅自引入用户归属、系统默认或名称唯一性语义。
- 2026-08-11 已冻结 Category JSON Storage v2 Contract：逻辑 Store `categories` 对应独立 `categories.json`，精确空根为 `{"storage_version":2,"categories":[]}`，记录格式由严格 `category_store.schema.json` 声明；同一状态按 ID 稳定序列化，单文件 mutation 使用完整快照原子替换，不扩展现有两个 journal。
- 2026-08-11 根据分类审查收紧 Category Contract：`sort_order` 固定为 `0..9007199254740991`，增加 `CATEGORY_SORT_ORDER_EXHAUSTED`；C++ Application/Domain 单点负责规范化；Event detail 冻结未分类、活动命中、悬空/软删除三态；Category 状态统一为 `implemented_unintegrated + blocked`。

### C++ Core 与存储

- 2026-08-09 完成 C++ 职责专项复核：将 Contract v2 Boundary 从单一 1887 行实现拆为稳定兼容 façade、共享 JSON/result support、Runtime/Event/Reminder 模块端点；将 recurring aggregate 校验从 codec 中移至独立 state validator，并保留公开 API、错误顺序、JSON/Storage 和领域语义。
- Event：创建、更新、删除、搜索、完成、重新打开和基础校验。
- Reminder：创建、按 ID 查询、列表、取消、启用、禁用和状态流转。
- Reminder 支持时间/目标/提醒方式校验、游标分页和批量调度查询。
- Event 与 Reminder 创建支持事务回滚；完成 Event 会取消未触发提醒，重新打开可恢复符合条件的提醒。
- Notification 已支持创建、失败记录、投递消费、重复消费保护和事务回滚。
- 已实现 JSON Repository、原子写入、软删除、重启恢复、UTF-8 和损坏文件检测。
- Android 正式数据目录已统一为 `calendar_core_storage_json`。
- 已实现重复 Event/Occurrence、滚动 Reminder、两阶段 Notification、72 小时 RecoveryBatch、Storage v2 bootstrap 与跨 store workflow journal；journal v1 使用严格完整 after-state codec 和逻辑 store 名。
- `reminder.mark_scheduled` 以 `expected_remind_at` 执行事务内 CAS；旧 Alarm 确认冲突返回可重试的 `REMINDER_SCHEDULE_CONFLICT`，不修改 Reminder。
- occurrence reopen 会以 `occurrence_reopened` 暂存同模板较晚 open successor，再恢复原 Reminder；滚动链复用确定性 successor，维持每模板最多一条 open Reminder。
- Recovery 会把严格早于窗口的已物化 open Reminder 终结为 `expired`；对既有 frozen prepared attempt 原子选择接管明细、废弃到摘要或废弃到窗口外，旧 attempt 不再允许 finalize。
- Anniversary 已实现 Domain、workflow/query service、Boundary、Repository、JSON codec/storage、prepared/committed journal 和六条 Native API；支持日期校验、动态 countdown、2 月 29 日、过滤排序、软删除、重启恢复与损坏数据显式失败。
- Category 已存在 Domain、Application Service、Repository、JSON codec/Store、runtime bootstrap、Boundary/JNI 和重启/损坏文件测试。当前 C++ 阻断项是 Event detail 仍无条件返回空 Category，以及原子替换后目录同步失败不能保证旧快照继续权威；安全整数上界也需同步到 codec/service。

### Flutter

- 已完成 Inbox/Today 日程列表和 active/completed 展示。
- 已完成新建日程页面、日期/时间选择器、重复和提醒选择 UI。
- 已完成日程详情页、完成操作和列表刷新。
- 已接入 Application Layer、Gateway、DTO 和 NativeResult 解析。
- 已完成“倒数纪念日”Flutter 原型及 Native Gateway 接入：六个 typed operation 已连接 MethodChannel；create/update/detail/list 使用既有设备时区 Gateway 提供显式 IANA timezone。非默认 kind、Reminder plan 与高层 preview recurrence 签名差异仍在 transport 前显式失败，不静默丢字段。
- 2026-08-09 已完成 Flutter 职责审查整改：新建日程的时区/DST/DTO workflow 移入 `CreateScheduleController`；重复日程详情拆为状态 façade、Detail Loader、Occurrence/Series Action UseCase；通知启动拆出 permission controller 与 Reminder schedule lifecycle coordinator。未修改 Contract、MethodChannel、JNI 或领域语义。
- Category 已具备严格 Request/Response/List DTO、Domain mapper、typed Native Gateway、MethodChannel adapter 与 Native repository；Fake fixtures 和新建 ID 也遵守正式 Contract。UI 仍通过既有 `CategoryRepository`/Application controller 工作，不直接调用 MethodChannel。

### Android Native

- 已完成 MethodChannel、Kotlin Contract 校验、JNI/C++ Bridge。
- 已完成通知 Channel、权限申请、系统设置跳转和通知点击 EventChannel。
- 已完成 Dispatcher Alarm、开机/时间变化恢复、WorkManager 看门狗和失败重试。
- 已完成 Reminder reconcile 和 Popup 通知投递。
- Kotlin v2 validator 已按 Recovery 双归属字段校验 finalize response，并复用完整 `ReminderStatus` 集合校验 list request，避免已提交成功被误报为 `CONTRACT_VALIDATION_FAILED`。
- Anniversary Kotlin handler/validator、窄 Native bridge 和六个 JNI external/export 已接入；Debug-only ADB smoke 与 AndroidTest instrumentation 共用正式 factory runner，release 不暴露 smoke 入口。
- Category 已增加 Kotlin request/response validator、MethodChannel handler、独立 `NativeCategoryBridge`、聚合 bridge 签名和真实 JNI 调用。Event validator 仍漏检 `category_id/category_ids/category`，窄 Bridge 仍有默认 throwing stub，且安全整数上界尚未同步。

## 正在完成

- 通知点击冷启动/热启动路由到真实详情页的真机验证（代码已接入 `EventDetailFlowPage`）。
- Alarm 到点真实触发（下一次调度为 2026-08-09 11:45 北京时间）与投递/重试行为验证。
- 进程崩溃或被杀后的 journal 重放真机验证。
- Recovery `abandoned_to_summary` / `abandoned_outside_window` 分支的真机验证。
- exact/inexact alarm 策略、批量失败反馈与国产 ROM（realme）Doze/后台限制的长周期行为。

## 尚未完成

- Habit/HabitCheckIn；Category 的 Event detail 聚合、Kotlin 边界、原子写失败一致性、安全整数/规范化跨层同步、生产 composition 与真机 smoke。
- 完整月/周/日历视图、搜索、全文索引和四象限。
- Notification 历史、点击记录、Event 编辑和完整删除/恢复交互。
- AI 导入/OCR、微信、账号登录、云同步、云备份和多设备同步。
- SQLite、FTS、附件存储迁移。

Contract 或目录中已有设计，不代表对应生产功能已经完成。

## 当前风险

- 通知点击冷启动路由仍待真机点击验证。
- v2 两阶段投递已在真机产生 sent 记录，但 Alarm 到点真实触发尚未观察。
- 点击事件读取后立即清除，存在丢失风险。
- 重复提醒消费闭环已部分真机验证，崩溃场景仍待补充。
- 真实设备与国产 Android 后台限制仍待长周期验证。
- V2 已激活；V1 数据不再保留（用户决策），升级路径不迁移、不归档旧数据。任何回滚到旧版都会失去本地数据。
- 全天/定时互斥时间结构已在 v2 激活，DST 边界仍需更多测试与真机场景覆盖。
- C++ 已锁定 Howard Hinnant `date v3.0.4`；Android 目标平台与真机 TZDB 行为仍需在 native smoke test 验证。
- Habit 重复语义仍缺独立协议；Anniversary 基础年度查询与 Storage 已实现，但 Reminder occurrence 身份、幂等与调度语义仍未设计，不能从 Event v2 静默推导。
- Category 的基础 JSON Store 格式、弱引用与 create/list 写读边界已经冻结，但用户归属、系统默认分类、名称唯一性、更新/删除语义仍无产品决策。实现当前 list/create 时不得自行加入这些语义；扩展 update/delete/sync 前必须先完成对应决策。

## 验证结果

- 2026-08-11 Category Contracts 审查整改：131 个 JSON Schema 均可解析、Draft 声明正确、`$id` 唯一，73 个本地 `$ref`/JSON Pointer 闭合；7 个 YAML 通过禁重键解析。专项断言覆盖 `9007199254740991`/`9007199254740992` 边界、C++ 规范化 owner/raw wire 示例、Event detail 三个正例与七组正反 oracle，以及 MethodChannel/JNI/Store 的 `implemented_unintegrated + blocked` 一致状态；重新配置后的 C++ `excellent_calendar_check` 6/6、`git diff --check` 通过。非 Contract 层仍未整改，整体发布结论保持 BLOCK。
- 2026-08-11 Category Storage v2 设计验证（当时状态，已被本日后续审查更新）：131 个 JSON Schema 全部通过语法、Draft 2020-12 声明、`$id` 唯一和 73 个本地 `$ref`/JSON Pointer 闭合检查；新增 Category Store 的严格根字段、九字段记录、非空 canonical `color/sort_order`、UUIDv4 和示例断言通过。7 个 YAML 清单使用禁重键设置解析成功，当时 per-store/API 的 `planned` 断言通过；按项目命令执行 C++ check 5/5。随后 C++/JNI/Store 实现进入工作区，当前状态与风险以上方最新记录为准。
- 2026-08-10 Category Contract/边界设计验证（历史状态）：130 个 JSON Schema、7 个 YAML、Dart/Flutter/Kotlin/Android/C++ 基线检查通过；当时 Category C++/JSON Storage/JNI export 尚未实现，因此未执行真实持久化或真机端到端验证。该代码存在状态已被 2026-08-11 的实现与审查记录替代。
- 2026-08-10 Anniversary C++/JNI 集成验证：重新配置并构建 `excellent_calendar_check`，5/5 通过；`flutter analyze` 无问题，Flutter 全量 179/179 通过；Android Anniversary 定向测试、`:app:testDebugUnitTest`、`:app:assembleDebug`、`:app:assembleDebugAndroidTest` 与 `flutter build apk --debug` 通过。arm64 Debug `.so` 精确导出 6/6 Anniversary JNI symbol；realme RMX5100 上正式 factory 路径完成 create → detail JSON 重载 → soft-delete，结果为 `PASS`。Contract 共 129 个 JSON、7 个 YAML 完成语法与本地引用闭合校验。`:app:lintDebug` 已执行，Anniversary/Smoke 零 finding；全项目仍被 29 个既有 error、20 个既有 warning 阻断，首项位于 `AlarmManagerReminderScheduler.kt`。
- 2026-08-09 Anniversary 年度规则设计验证：129 个 Contract Schema 完成 JSON 语法、Draft 声明、`$id` 唯一与 72 个 `$ref` 闭合检查；7 个 Contract YAML 可解析；15 项 Anniversary recurrence 结构语义断言与 `git diff --check` 通过。Flutter Anniversary MethodChannel/Gateway 定向测试 6/6 通过；Kotlin `AnniversaryMethodChannelHandlerTest` 通过。C++/Storage/真实 JNI 未实现，未执行端到端 Anniversary 验证。
- 2026-08-09 C++ 职责整改验证：重新配置后执行 `cmake --build cpp_core/build-ninja --target excellent_calendar_check`，4/4 通过；新增 Boundary v2 characterization 目标覆盖公开端点 malformed object、模块 unknown-field、`event.update` runtime-first 既有错误优先级和 11 组 compatibility wrapper 等价性。
- 2026-08-03 Contract v2 静态审计：111 个 Draft 2020-12 Schema 元模式通过，111 个 `$id` 唯一，61 个 `$ref` 可解析。
- 7 个 YAML 文档通过解析与重复键检查；MethodChannel/JNI 映射路径、Native v2 版本、53 个 NativeError 定义与 9 个新增稳定错误码一致。
- 5 组 UUIDv5 namespace/固定向量重新计算一致；timed/all-day、v1 拒绝、未知字段、Recurrence、Reminder、Notification 和 RecoveryBatch 代表性正反例通过。
- `git diff --check`：通过。
- 2026-08-04 C++ 配置后执行 `excellent_calendar_check`：3/3 通过；最新 `excellent_calendar_recurrence_tests`（含 Boundary JSON 断言）通过。
- 2026-08-04 共 112 个 Contract JSON Schema 通过 JSON 语法解析；CAS、reopen、expired、prepared attempt resolution 和逻辑 journal store 名均有 C++ 回归覆盖。
- 2026-08-04 finalize/list 一致性修复验证：112 个 Schema 可解析、62 个本地 `$ref` 闭合；Kotlin adopted finalize 与 `status=["expired"]` 回归通过；Android 全量 JVM 单测和 Debug APK 构建通过；C++ `excellent_calendar_check` 3/3、Flutter analyze 和 68 个 Flutter 测试通过。
- 2026-08-06 倒数纪念日 Flutter Fake 原型验证：`flutter analyze` 通过，Flutter 完整测试 156/156 通过，`flutter build apk --debug` 通过。定向测试覆盖五条固定数据、筛选、详情、创建/编辑/删除、共享 Fake、错误恢复、360×800 和 1.3 字体缩放。真实 Anniversary MethodChannel/Kotlin/JNI/C++/存储/农历/通知链路未验证且尚未实现。
- 2026-08-08 V2 真机验证（realme RMX5100, Android 16 / API 36）：冷启动约 2.1s，无崩溃；`notification.initialize`、`permission_status`、`event.search`、`runtime.localize_instants`、`reminder.reconcile_schedule`、`get_initial_tap_payload` 全部 ok=true；`files/tzdb/2026c` 与 7 个 v2 store 就绪；`mark_scheduled` CAS 生效（reminder `49a18b73…` 写入 scheduled）；系统注册唯一 RTC_WAKEUP Dispatcher Alarm；通知栏存在 `delivery:<uuid>` 标签的 v2 通知；`notifications.json` 中 6 条 sent 记录包含完整的 notification_id/delivery_id/delivery_attempt_id；RecoveryBatch `9063f247`（device_boot）接管 4 条明细并完成投递。
- 2026-08-09 Flutter 职责整改验证：相关定向测试 35 项通过；`flutter analyze` 通过；Flutter 全量测试 165/165 通过；`flutter build apk --debug` 通过。全库 formatter 检查另发现未修改的 `native_contract/category/category_response_dto.dart` 存在既有格式差异，本轮未制造无关 diff。
- 以下代码验证为 2026-08-01 的 v1 基线，本次纯文档/Contract 设计没有重跑：C++ `excellent_calendar_check` 2/2、`flutter analyze`、68 个 Flutter 测试、Kotlin `:app:testDebugUnitTest` 和 Android Debug APK 均曾通过。
- 真机通知、Alarm、JNI、点击路由完整链路：未验证。

## 下一步

1. 完成 Alarm 到点真实触发验证（2026-08-09 11:45 北京时间）并确认通知展示、重试与状态回写。
2. 补做崩溃/杀进程 journal 重放与 Recovery `abandoned_*` 分支的真机验证；继续覆盖国产 ROM 后台限制。
3. 完成通知点击到真实详情页的真机验证；Habit 与 Anniversary Reminder 重复/occurrence 语义另立协议任务。
4. 按已冻结的 Category Contract 依次修复 C++ Event detail/原子写、Kotlin Category 关联校验、Flutter null-last/原样转发/生产 composition，完成跨层和设备 smoke 后再统一切换 `integrated + active`；update/delete/sync 继续等待对应产品规则。
5. 保持契约状态、代码与 `docs/develop_record.md` 同步；后续协议变更按破坏性变更流程提升版本。

## 2026-08-09 Kotlin 职责审查整改

- `NativeMethodChannelHandler` 已收敛为 MethodChannel registry、exactly-once completion 与共享资源生命周期入口；Runtime、Event、Anniversary、Reminder、Notification 的解析、调用和响应选择已迁移到各自模块 handler。
- Native JSON 执行与错误归一化集中到无业务模块知识的 `NativeCallExecutor`；mutation 后 Reminder reconcile 独立为 `MutationScheduleHook`，保持“领域提交成功不因 Android 调度失败回滚，只排队重试”的既有语义。
- `V2RequestContracts` / `V2ResponseContracts` 保持兼容 façade；Event、Occurrence、Recurrence、Reminder validator 与公共 primitives 已分模块，未修改 Contract、MethodChannel、JNI 或 JSON wire format。
- Kotlin 定向测试与 Android 全量 JVM 测试通过（78 项、0 failure、0 error、1 skipped）；`flutter analyze` 与完整 Android Debug 构建通过。lint 仍有 35 个既有 error / 20 个 warning，ADB 无连接设备；详见 `docs/review/审查职责功能.md`。

## 2026-08-10 Anniversary C++ Core / JNI 完成记录

- 选择独立 Anniversary 事务方案：新增 `anniversaries.json`、`anniversary_recurrences.json`、`anniversary_workflow_transactions.json`，合法旧 v2 目录增量初始化空 Store，Event/Reminder 既有六 Store journal 保持不变。
- create/update 请求新增显式 `timezone`；Dart Gateway 复用既有设备时区 Gateway，Kotlin 只做 Contract 校验，C++ 负责本地自然日 countdown。timezone 不持久化。
- 兼容性：必填 timezone 在 Anniversary planned 草案首次激活前完成全层同步，没有已发布调用方或需要迁移的持久化字段；Store 扩展保持 storage version 2，并通过可重复的缺失空 Store 初始化兼容既有合法 v2 目录。
- 六条 Contract、MethodChannel、Native Call、Kotlin external、JNI export 与 C++ Boundary API 均已激活并验证；`NativeResult<T>`、稳定错误码、未知字段拒绝和 malformed payload 显式失败保持一致。
- Reminder 交互本轮为 `not_required`；农历为稳定 unsupported；非空 list cursor 暂返回 `FEATURE_NOT_IMPLEMENTED`。
- 真机 smoke 初版测试桥与 App 启动 factory 竞争 process-global C++ runtime，曾触发 `STORAGE_NOT_INITIALIZED`；测试改为复用正式 `AndroidNativeBridgeFactory` 单例路径后通过。该问题属于测试 harness 组装错误，不是生产调用失败。

## 2026-08-10 Anniversary list 排序 Contract 收敛

- 已确认 `list_anniversaries_request` 同时开放 top-level sort 与公共 `pagination.sort_*` 会形成可验证歧义：公共 Schema/DTO 接受任意 nested `sort_by` 且默认 `desc`，C++ 最终只接受 Anniversary 两个 sort key 并以 top-level 优先。
- Anniversary list 现只允许 top-level `sort_by/sort_direction`；缺失分别使用 `target_occurrence_date/asc`。其专用 `pagination` fragment 与 Dart DTO 只保留 `page/page_size/cursor`，Kotlin/C++ 对 nested sort 和双位置请求统一返回 Contract failure。
- 本项只收敛查询传输协议与边界映射，不改变 Anniversary Domain、JNI 方法签名、JSON Storage、历史数据或 migration。相关 Anniversary request/DTO/端点尚未纳入 Git 跟踪，因此作为同一批未提交实现的提交前修复，不提升 Native Contract v2 版本。
- 验证：129 个 Contract JSON 可解析、`$id` 唯一且本地 `$ref` 闭合，Anniversary sort 结构断言通过；Dart 定向 10 项与全量 187 项、Kotlin Anniversary 定向与 Android 全量 JVM 测试、C++ `excellent_calendar_check` 5/5、`flutter analyze`、主 APK Debug 构建及 Native Smoke test/analyze/Debug 构建通过。未重复执行真机 Anniversary list。

## 2026-08-10 Category 数据模型与跨层契约补齐

- `DATA_MODEL.md` 已明确 Category 字段、软删除、稳定排序、Event/Anniversary/SearchIndex 关系，以及 `category_id=null` 的未分类语义；页面 loading、选中状态和 Fake 默认项没有进入领域模型。
- 新增 `CategoryListResponse`，收紧 `CreateCategoryRequest` / `CategoryResponse`，并为 `category.list` / `category.create` 建立 MethodChannel 与 Native Call 映射。两条能力保持 `planned`，没有在 C++ 缺失时伪装为已集成。
- Flutter 增加 typed DTO/Gateway/adapter/native repository，既有 Application controller 和 UI 继续只依赖 `CategoryRepository`；Kotlin 增加严格 Contract、Handler、窄 Bridge 与显式 unsupported JNI stub。
- 兼容策略：新 Category writer 使用 UUIDv4；Event/Anniversary 的既有 nullable `category_id` 不收紧，历史非 UUID 引用继续可读。分类被删除或引用无法解析时，关联 ID 保留，聚合展示可返回空 Category。
- 未冻结项：用户归属、系统默认、名称唯一性、update/delete/reorder API。它们需要产品与存储决策后再扩展 Contract。

## 2026-08-11 Category JSON Storage v2 格式冻结

- 新增严格 `contracts/storage/category_store.schema.json`，根对象只允许 `storage_version=2` 与 `categories`，每条 `CategoryStorageRecord` 精确保存九个稳定字段；Request/Response/Domain/Storage 继续分离。
- `calendar_core_storage.yaml` 新增 `categories -> categories.json`、根包络、唯一 ID、规范化、初始化、弱引用、完整快照原子替换和未来跨 Store journal 门禁；Category Store 以 per-store override 保持 `planned`，不改变顶层已集成 Store 的事实。
- 兼容选择为 Storage v2 可加性文件：现有 v2 Store codec 与 journal 均不变，旧 runtime 忽略并保留未知文件；没有 Category v1 数据或 Flutter Fake migration，也不初始化“默认日程”。
- 当前 create/list 只需一个 Category 文件，使用目录级写锁和原子替换，不新增 journal。Event/Habit/Anniversary 的历史 `category_id` 仍是弱 opaque reference，缺失或软删除 Category 不级联改写。
- 该轮当时实际 C++ Repository、codec、bootstrap、JNI export 与磁盘写入尚未完成；后续实现已经出现，但在统一发布门禁通过前仍不得将 Store 或两条 API 改为 `integrated`。
- 验证：131 个 JSON Schema/唯一 `$id`/73 个本地引用闭合，7 个 YAML 禁重键解析与 Category Storage 专项断言通过；C++ `excellent_calendar_check` 5/5、`git diff --check` 通过。Flutter/Android 未因纯 Storage Contract 设计重复构建，真实 Category 落盘未验证。

## 2026-08-11 Category Contracts 审查整改

- 逐项复核 `docs/review/分类功能审查/分类功能审查结果.md` 的 CAT-001～CAT-010，十项均有当前代码证据，不存在可直接驳回的误报；只修改 Contracts 主责/协作范围。
- CAT-001 不采用提前激活：正式资料从含义错误的 `planned/future/未实现` 收敛为 `implemented_unintegrated + blocked`，区分“代码存在”和“发布可依赖”。
- CAT-008 将 Request、Response、Store 的 `sort_order` 上界统一为 `9007199254740991`，首个非法值为 `9007199254740992`；补请求、磁盘和自动追加耗尽三类稳定错误语义。
- CAT-009 统一 C++ Application/Domain 为唯一规范化 owner；Flutter/Kotlin 必须原样转发 Schema-valid 前后空白文本与小写颜色。
- CAT-004 协作项在 Event detail Schema 中冻结未分类、活动命中、悬空/软删除三态，并补正反 oracle；CAT-006 保留旧快照权威保证，明确目录同步成功才是提交点。
- Contracts 主责语义已冻结，但 Category 整体仍为 BLOCK；C++、Kotlin、Flutter 和设备 smoke 完成后才可最终激活。
