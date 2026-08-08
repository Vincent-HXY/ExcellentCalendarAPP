# ExcellentCalendarAPP 当前进度

> 更新时间：2026-08-06

## 总体结论

项目已经从工程骨架进入核心闭环开发阶段，主链路已经基本打通：

```text
Flutter → Dart Gateway → Kotlin MethodChannel → JNI → C++ Core → JSON Storage → Android Alarm/Notification
```

当前最完整的已实现范围仍是“日程 + 一次性提醒 + Android 本地通知 + JSON 本地存储”。核心代码测试和 Debug 构建通过，但还不是功能完整、真机验证充分的 V1 发布版。

重复 Event 与滚动 Reminder 的 Native Contract v2 数据模型、Schema、身份、恢复批次和 Storage 规则已经完成设计；C++ Core、Boundary 与 JSON Storage v2 已实现并通过原生测试，但 Dart、Kotlin、JNI 尚未接入。因此发布状态仍统一标记为 `design_only`，实现状态标记为 `cpp_core_complete_unintegrated`，不能宣称 APK 已支持 v2。

## 已完成

### 协议与架构

- 已建立 `contracts/`，当前包含 112 个 JSON Schema、MethodChannel、JNI 调用、错误码、枚举和返回外壳。
- Dart、Kotlin、C++ 已按 DTO、Boundary、Domain 分层，跨层调用链已建立。
- 已完成 breaking Native Contract v2 设计：Event timed/all-day 互斥时间、不可变 Recurrence revision、Occurrence 状态、确定性滚动 Reminder、两阶段 Notification、72 小时 RecoveryBatch、`runtime.initialize` 与 JSON Storage v2。
- `contracts/identity.yaml` 固定了三个 UUIDv5 namespace、规范化输入和五组跨语言测试向量；`contracts/storage/calendar_core_storage.yaml` 固定了 v1 归档、空 v2 初始化和 workflow journal 规则。
- 已冻结调度确认 CAS、occurrence reopen successor 暂存、`ReminderStatus.expired`、prepared attempt 接管/废弃和 v2 发布/实现状态分离语义。
- 已修正 v2 finalize/list 边界一致性：adopted frozen attempt 的 `resolved_by_recovery_batch_id` 与 `recovery_batch_id` 同样要求返回 `recovery_batch`；`reminder.list.status` 已允许精确查询 `expired`。

### C++ Core 与存储

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

### Flutter

- 已完成 Inbox/Today 日程列表和 active/completed 展示。
- 已完成新建日程页面、日期/时间选择器、重复和提醒选择 UI。
- 已完成日程详情页、完成操作和列表刷新。
- 已接入 Application Layer、Gateway、DTO 和 NativeResult 解析。
- 已完成“倒数纪念日”Flutter Fake 原型：列表/筛选、详情纸张卡、备注/主题/分享占位、新建/编辑/删除、固定时钟、共享内存 Gateway，以及 loading/empty/error/submitting 状态。该功能未接入真实 Native，后续接口缺口记录在 `docs/anniversary_frontend_contract_requirements.md`。

### Android Native

- 已完成 MethodChannel、Kotlin Contract 校验、JNI/C++ Bridge。
- 已完成通知 Channel、权限申请、系统设置跳转和通知点击 EventChannel。
- 已完成 Dispatcher Alarm、开机/时间变化恢复、WorkManager 看门狗和失败重试。
- 已完成 Reminder reconcile 和 Popup 通知投递。
- Kotlin v2 validator 已按 Recovery 双归属字段校验 finalize response，并复用完整 `ReminderStatus` 集合校验 list request，避免已提交成功被误报为 `CONTRACT_VALIDATION_FAILED`。

## 正在完成

- 通知点击后根据 ID 读取真实日程并进入详情页。
- 按已定稿 v2 Contract 实现 `notification_id`、`delivery_id`、`delivery_attempt_id` 和 prepare/display/finalize 两阶段协议。
- 通知初始化失败后的调度状态机。
- 日程修改、完成、重新打开后的调度一致性。
- 将已实现的 C++ v2 链路接入 JNI/Kotlin validator、Android 调度和 Dart DTO/Gateway。
- exact/inexact alarm 策略和批量失败反馈。
- 真实 Android 设备上的通知、Alarm、JNI 连续验证。

## 尚未完成

- Habit/HabitCheckIn、Anniversary、Category。
- 完整月/周/日历视图、搜索、全文索引和四象限。
- Notification 历史、点击记录、Event 编辑和完整删除/恢复交互。
- AI 导入/OCR、微信、账号登录、云同步、云备份和多设备同步。
- SQLite、FTS、附件存储迁移。

Contract 或目录中已有设计，不代表对应生产功能已经完成。

## 当前风险

- 通知点击冷启动可能进入占位页面。
- 现有 v1 Android payload 中的 `notification_id` 暂时使用 Reminder ID。
- 现有 v1 运行时投递协议缺少完整幂等键和两阶段提交；v2 Contract 方案尚未实施。
- 点击事件读取后立即清除，存在丢失风险。
- 重复提醒消费闭环尚未完成。
- 真实设备和国产 Android 后台限制尚未验证。
- Native v2 仍为发布设计态；C++/Storage 已实现不等于 APK 已集成。任何中间版本都不能让 v2 writer 写入正式用户目录，也不能把 v1/v2 payload 或 Storage 混读。
- 现有 all-day Event 代码仍依赖 `start_at/end_at`，切换到 v2 互斥时间结构必须与全部读写层和测试原子完成。
- C++ 已锁定 Howard Hinnant `date v3.0.4`；Android 目标平台与真机 TZDB 行为仍需在 native smoke test 验证。
- Habit/Anniversary 重复语义仍缺独立协议，不能从 Event v2 静默推导。

## 验证结果

- 2026-08-03 Contract v2 静态审计：111 个 Draft 2020-12 Schema 元模式通过，111 个 `$id` 唯一，61 个 `$ref` 可解析。
- 7 个 YAML 文档通过解析与重复键检查；MethodChannel/JNI 映射路径、Native v2 版本、53 个 NativeError 定义与 9 个新增稳定错误码一致。
- 5 组 UUIDv5 namespace/固定向量重新计算一致；timed/all-day、v1 拒绝、未知字段、Recurrence、Reminder、Notification 和 RecoveryBatch 代表性正反例通过。
- `git diff --check`：通过。
- 2026-08-04 C++ 配置后执行 `excellent_calendar_check`：3/3 通过；最新 `excellent_calendar_recurrence_tests`（含 Boundary JSON 断言）通过。
- 2026-08-04 共 112 个 Contract JSON Schema 通过 JSON 语法解析；CAS、reopen、expired、prepared attempt resolution 和逻辑 journal store 名均有 C++ 回归覆盖。
- 2026-08-04 finalize/list 一致性修复验证：112 个 Schema 可解析、62 个本地 `$ref` 闭合；Kotlin adopted finalize 与 `status=["expired"]` 回归通过；Android 全量 JVM 单测和 Debug APK 构建通过；C++ `excellent_calendar_check` 3/3、Flutter analyze 和 68 个 Flutter 测试通过。
- 2026-08-06 倒数纪念日 Flutter Fake 原型验证：`flutter analyze` 通过，Flutter 完整测试 156/156 通过，`flutter build apk --debug` 通过。定向测试覆盖五条固定数据、筛选、详情、创建/编辑/删除、共享 Fake、错误恢复、360×800 和 1.3 字体缩放。真实 Anniversary MethodChannel/Kotlin/JNI/C++/存储/农历/通知链路未验证且尚未实现。
- 以下代码验证为 2026-08-01 的 v1 基线，本次纯文档/Contract 设计没有重跑：C++ `excellent_calendar_check` 2/2、`flutter analyze`、68 个 Flutter 测试、Kotlin `:app:testDebugUnitTest` 和 Android Debug APK 均曾通过。
- 真机通知、Alarm、JNI、点击路由完整链路：未验证。

## 下一步

1. 同步实现 JNI/Kotlin validator 与 Android 调度，再实现 Dart DTO/Gateway；保持 `design_only` 直到同一 APK 全链路就绪。
2. Android 必须传递 `expected_remind_at`，对 `REMINDER_SCHEDULE_CONFLICT` 触发 reconcile，并根据 `prepared_attempt_resolutions` 取消已废弃 delivery tag。
3. 执行 Flutter analyze/test、Kotlin 测试、Android Debug 与 native smoke test；验证 v1 归档、v2 初始化、journal 重放、Alarm CAS 和 Recovery 接管/废弃后才能激活 v2。
4. 完成通知点击到真实详情页、真机 Alarm/reconcile；Habit/Anniversary 重复规则另立协议任务。
