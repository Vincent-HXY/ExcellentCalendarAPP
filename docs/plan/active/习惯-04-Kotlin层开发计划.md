# 习惯-04：Habit V1 Kotlin、JNI 与 Android 系统接线开发计划

Status: Active / Implementation Integrated / Host Gates Passed / Device Gate Open

建立日期：2026-08-28

状态同步：2026-08-31

上游：

- `docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`
- `docs/plan/completed/习惯-02-Contracts层开发计划.md`

同批分层计划（已集成）：

- `docs/plan/active/习惯-03-CPP层开发计划.md`
- `docs/plan/active/习惯-05-Flutter层开发计划.md`

当前收口：`JniHabitBridge` 已接到真实 C++ Boundary，生产装配无 Fake fallback；Android unit、lint、Debug APK、androidTest APK、Native smoke 与三 ABI JNI 符号门禁已通过。实际设备上的完整 instrumentation/系统行为矩阵仍未执行，因此本计划暂留 active。

## 1. 目标与范围

本计划仅在 `flutter_client/android/**` 内实现：

- 10 个 Habit MethodChannel 方法和 2 个 Appearance 本地方法；
- 11 个 C++ call 的窄 bridge、Kotlin external 签名和 production adapter，以及最终真实 C++ JNI export 接线；
- mutation commit 后的 Android schedule reconciliation；
- Habit Reminder/Notification target branch、点击和后台 direct-complete action；
- SharedPreferences 本机 Appearance；
- Kotlin unit、JNI instrumentation、APK 和设备验证。

Kotlin 只负责编排 Android 系统能力和边界校验，不计算 recurrence、lifecycle、streak/rate、remaining amount、identity 或事务结果，不保存第二份 Habit/Reminder 真相源。

并行开发阶段，本轨只依赖冻结 Contract 即可独立实现和运行；开发、单测和专用测试通过可注入的 `FakeNativeHabitBridge` 消费脚本化 `NativeResult`。最终生产组合现已切换到真实 C++ symbol，Fake 只保留在测试范围。

不修改：`contracts/**`、`cpp_core/**`、Flutter/Dart；不新增 Scheduler、云同步、Widget、多个提醒、ring 或第三方依赖。

## 2. 开发前可复用基础与缺口（历史记录）

以下缺口是 2026-08-28 的开工快照，均已由 K1–K3 和最终真实接线处理；当前剩余项以本文顶部状态同步及 K4 设备门禁为准。

可复用：

- `AndroidNativeBridgeFactory` 的 application-context 正式 runtime，可供 Receiver/Worker 在无 Flutter Engine 时初始化。
- `NativeMethodChannelHandler`、模块 Handler、单线程 `NativeCallExecutor` 和一次性结果完成保护。
- `V2ReminderScheduleCoordinator`、Dispatcher Alarm、Boot/Update/Date/Time/Timezone receiver、WorkManager recovery。
- prepare → Android post → finalize 两阶段投递。
- Notification click identity、PendingIntent tag 和 SharedPreferences 的 Ring persistent store 模式。

当前缺口：

- Kotlin Reminder validator 仍拒绝 Habit occurrence/template/date identity。
- `NativeCalendarCoreBridge`、JNI external/export 和 Handler 没有 Habit。
- Storage handshake 仍硬编码 v4。
- Notification 只有 content intent，没有 Habit action receiver。
- Appearance store/handler/schema mapper 尚不存在。
- Flutter Habit 点击仍进入占位详情；该页面由下游计划处理。

## 3. 并行开工与独立运行门禁 K0

- [x] Contract validator 和共享 Reminder 回归通过。
- [x] 12 个公开方法、11 个 internal call、错误、枚举、route、action 和 capability 冻结。
- [x] 三层实现消费同一冻结 Contract 基线；最终增量在同一工作树完成真实接线和独立 Review。
- [x] 先冻结 `NativeHabitBridge` 窄接口；production `JniHabitBridge` 与测试 `FakeNativeHabitBridge` 必须实现同一接口。
- [x] 建立由 `contracts/fixtures/habit/` 派生的脚本化 response/error 场景，并保留 fixture 名称或来源映射。
- [x] 确认 Fake 仅用于 `src/test`、`src/androidTest`；`src/main` production factory 无静默回退 Fake。

Kotlin 可在 C++ 尚未完成时交付 DTO、Handler、Android 调度/通知/Receiver、Appearance 和可构建 APK。Fake 只返回预制 C++ 投影或错误，不计算 lifecycle、statistics、identity、“今天是否已提醒”等 C++ 规则；真实 JNI symbol、Storage v5 数据和端到端状态留到最终集成验证。任何阶段都不得把 capability 改为 active。

## 4. K1：Typed Contract、Handler 与窄 JNI Bridge

任务：

- [x] 新增 Habit request/response/aggregate validators，严格 exact fields、snake_case、date、UTC、nullable、enum、IANA timezone、integer-hundredths 与文本/分页/cursor 上限。
- [x] 新增 `NativeHabitBridge`，由现有 Calendar Core bridge 聚合；production `JniHabitBridge` 和测试 Fake 共享接口，不建立第二个 runtime owner。
- [x] 为 11 个 `native_calls.yaml` 入口冻结 Kotlin external/override 签名与 production adapter，并由最终集成验证真实 C++ JNI export 可链接。
- [x] 新增 `HabitMethodHandler` 和 mutation orchestrator；公开 `habit.check_in` 只解析 manual Schema并补成内部 command 的 `source=manual + null identity`，查询直接调用，mutation 在 C++ commit 成功后执行 scheduler side effect。
- [x] 注册 10 个公开 Habit 方法，更新 Native error allow-list 并删除 duplicated 语义。
- [x] 将集成候选 runtime 的 expected Storage format 从 4 同步为 5；初始化返回其他版本时严格失败。
- [x] 对 malformed NativeResult、today_progress 计数关系、detail 空历史/锁定对称、executor rejection、JNI unavailable 和一次性完成进行回归。

边界要求：

- `data_saved=true` 后 Android 调度失败必须返回 pending capability，不得伪造领域回滚。
- Kotlin 不生成 Habit、recurrence、template、occurrence、Reminder 或 action ID。
- Kotlin 数量 wire 只使用 `Long` integer hundredths，不接收 `Double`/decimal JSON number；必须证明 `9_007_199_254_740_990/991` 经 JSON/JNI/JSON 相邻 round-trip 不合并。

## 5. K2：Reminder、Reconciliation 与 Notification Action

任务：

- [x] 更新 Reminder/Notification/prepare/tap validator，接受严格 Habit branch，继续拒绝 cross-target 字段。
- [x] 复用现有 Dispatcher Alarm 和两阶段投递；未创建 Habit 专属 Alarm 数据库或第二 Scheduler。
- [x] mutation response 标记 reconcile 时运行现有 schedule coordinator；默认关闭提醒不请求权限或创建 Alarm。
- [x] popup 先尝试 exact；无 exact 权限时允许 approximate 并返回显式 degradation。通知权限拒绝保留业务数据并进入 pending。
- [x] 系统启动、升级、日期/时间/时区变化和权限恢复先续跑 `habit.reconcile_reminders` cursor，再运行共享 schedule reconciliation；同一唤醒最多 20 页/2000 条，达到预算后续约 WorkManager，不阻塞线程。
- [x] 每页验证 request_limit、processed 与四类 outcome；`has_more=true` 时拒绝 processed=0、空/超长/重复/不前进 cursor，记录诊断并停止本次唤醒，避免无限循环或耗电。
- [x] prepare 读取 C++ 生成的 action payload，创建 immutable、无碰撞的 Android “完成” action。
- [x] 新增 `exported=false` 的 `HabitNotificationActionReceiver`；入口只校验系统 payload、安排唯一工作并委托正式 bridge。
- [x] Receiver/Worker 不启动 Flutter Engine；只由该非导出路径把 C++ 生成的 payload 映射为内部 `habit.check_in` notification-action command，公开 MethodChannel 不接受 action identity。
- [x] action 成功或幂等 replay 后取消对应 Android delivery tag并 reconcile；expired/mismatch/ended/deleted 不伪造成功。
- [x] 跨日或业务取消的 prepared attempt 服从 C++ 返回的 abandoned 状态；Kotlin 不创建 RecoveryBatch 或摘要。
- [x] 点击 intent 原样保留 `habit.detail + target_id + occurrence_key`。

安全与并发：

- PendingIntent request code/data URI 必须由稳定 delivery/action identity 派生，不能只用 Habit ID。
- Receiver 不导出、不接收任意 completed count、不信任可伪造的自由文本。
- action 与 finalize/reconcile 的并发结果完全由 C++ transaction 仲裁。
- Android 不自行判断“今天是否已提醒”；sent/prepared→改时间或关闭再开启的下一日生效结果完全消费 C++ 返回，且旧 prepared delivery tag 必须取消。
- `OPEN-NOT-001` 的点击 peek/ack 债务仍独立存在，本计划不宣称顺带关闭。

## 6. K3：本机 Appearance

任务：

- [x] 新增 application-context、版本化、线程安全的 `AppearancePreferencesStore`。
- [x] 只保存 `teal/blue/indigo/green/orange/rose/purple`；不接受任意 ARGB。
- [x] 缺值返回 teal；磁盘未知/损坏 token 回退 teal，并记录不含用户内容的诊断。
- [x] update 未知 token 返回 `APPEARANCE_COLOR_TOKEN_INVALID` 且不写入。
- [x] 真实持久化失败返回 `APPEARANCE_STORAGE_FAILED`；不得吞异常或假成功。
- [x] 新增并注册 `appearance.get_local/update_local` Handler；不进入 JNI、不新增 EventChannel。

## 7. K4：独立测试、APK 与集成预留门禁

单元/Contract 测试至少覆盖：

- 12 个 MethodChannel 正例和缺失/多余字段、错误类型、未知 enum/error、malformed envelope；
- Storage v5 handshake response、11 个预期 JNI symbol manifest、后台线程和一次性 result；真实 symbol 可链接性归最终集成；
- create/check-in/end/delete/set-reminder 的 post-commit schedule 结果；
- permission denied、exact→approximate、scheduler retry；
- same-day catch-up、next-day expiry、cursor continuation、zero progress、重复 cursor、20 页/2000 条预算和重复 recovery；
- sent/prepared/pending 后改时间、关闭再开启均不得造成同日第二次真实通知；
- integer-hundredths 相邻最大值、decimal number 拒绝、400 天与文本/cursor/page 上限；
- binary/quantitative direct-complete、重复/过期/错误 action；
- Appearance 默认、七 token、非法、损坏、I/O 失败和重启保持。
- 同一组 Handler/Coordinator/Receiver 测试可在 scripted Fake 和 production bridge adapter 之间替换，业务代码不得按 Fake/real 分叉。

必须执行实际可用的 Gradle 目标：

```powershell
cd flutter_client/android
.\gradlew.bat :app:testDebugUnitTest
.\gradlew.bat :app:lintDebug
.\gradlew.bat :app:assembleDebug
.\gradlew.bat :app:assembleDebugAndroidTest
```

独立轨可运行门禁：

- unit 与 instrumentation 使用 `FakeNativeHabitBridge` 驱动 success、domain error、malformed、pending schedule、reconcile continuation 和 action replay；
- 如需交互演示，只允许显式 Debug harness 注入 Fake，Release/默认 production factory 不得包含兜底开关；
- `assembleDebug` 不要求真实 Habit JNI symbol 已存在，但不得用返回固定成功的 native stub 欺骗链接或运行验证。

最终集成设备门禁（不阻塞本轨达到 Layer Complete）：

- 从 `adb devices -l` 与 instrumentation 查询获取真实 serial/component，不猜路径或 application id；
- 使用隔离 Debug Store，不操作正式用户数据；
- 覆盖通知允许/拒绝/恢复、App 前后台/未启动、强杀、设备重启、时间/时区变化；
- 观察同日补发、跨日过期、direct-complete、重复 action 和真实详情点击；
- 检查目标 ABI 的 native library 与 Habit JNI symbols。

## 8. Kotlin 独立交付与总工程合并门禁

独立交付给总工程集成负责人：

- 12 个公开方法的 Handler/MethodChannel 链、准确 payload 示例和 Fake fixture 映射；
- schedule capability/pending/degradation 行为；
- Habit tap occurrence identity；
- Appearance get/update 与重启保持；
- 后台 action 成功后 Flutter 刷新可观察的 C++ 最终状态；
- production `JniHabitBridge` 接线清单、11 个预期 symbol、Storage 5 handshake 与需要由真实 C++ 重跑的测试清单。

独立完成条件已满足：K0–K4 的 Kotlin-owned 项、unit/lint/Debug APK、基于 Fake 的测试与 Android 行为测试通过；`src/main` 无 Fake fallback，Kotlin 不复制 C++ 规则。当前已越过 `Layer Complete / Awaiting Integration` 并完成真实 JNI 集成，但 capability 仍不标为 active。

最终合并已由总工程师完成：production adapter 已接到真实 C++，运行时无 Fake/harness，主机 JNI、C++ `excellent_calendar_check`、scheduler/action 回归和 APK 门禁已重跑。`src/test`/`src/androidTest` 的 Fake 保留为回归资产；真实设备上的 instrumentation、通知与恢复矩阵通过后，本计划才移入 `docs/plan/completed/`。
