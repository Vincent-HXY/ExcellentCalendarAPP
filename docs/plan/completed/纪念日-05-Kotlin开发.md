# 计划 3：纪念日 Reminder 与 Occurrence Kotlin / Android 层

> 状态：Completed / Kotlin/Android 并行交付已完成并接入生产链；Anniversary R1 integrated / active
> 上位计划：[`纪念日-02-Reminder与Occurrence开发计划.md`](./纪念日-02-Reminder与Occurrence开发计划.md)  
> 前置交付：[`纪念日-03-contracts设计.md`](./纪念日-03-contracts设计.md) 的冻结提交、fixture、能力矩阵与兼容结论  
> 负责范围：`flutter_client/android/**`；`docs/log.md` 只追加记录  
> 必须使用 Skill：`android-kotlin-native-feature`  
> 并行策略：使用 Fake `NativeAnniversaryBridge`、fake scheduler/display service 和冻结 fixture 完成 JVM/Android 单层开发；最终再与真实 C++ Boundary/JNI 链接

## 1. 任务目标

依据冻结 Contract，实现 Anniversary MethodChannel/Kotlin Contract/JNI 映射、保存后的 Reminder reconciliation、exact-alarm 降级、系统事件恢复、正常与聚合 popup 展示，以及 Notification 点击 Anniversary detail。

上位计划第 2～17 节对本工作流全部适用；本文件的追踪表只标识 Kotlin/Android 的主要责任，不构成对共同回归、风险、范围或最终验收要求的删减。

Kotlin/Android 只负责跨层校验和平台副作用：

- 不展开 occurrence、不计算周年数、2 月 29 日、日末补发窗口或 successor；
- 不决定 covered membership，不把多个 Reminder 自行合并；
- 不把 AlarmManager/SharedPreferences/Notification 状态保存成 Reminder 第二真相源；
- 不在数据提交前调度，不因调度失败回滚或清除 C++ 已保存数据；
- 不修改 Flutter UI 或 C++ 领域/持久化规则。

## 2. 当前实现基线

开始前按实际代码复核。当前已知基线：

- `AnniversaryContracts.kt`、`AnniversaryMethodHandler.kt`、`NativeAnniversaryBridge.kt` 已覆盖 create/update/delete/detail/list/countdown 六个方法。
- `JniNativeCalendarCoreBridge.kt` 与 `event_jni.cpp` 已有对应 JNI 入口；没有 `list_occurrences`。
- 现有 Anniversary Handler 主要做校验与 Native 转发，保存后不会主动触发 Reminder reconciliation。
- `AlarmManagerReminderScheduler` 与共享 Dispatcher `ReminderDispatchAlarmScheduler` 在 Android 12+ 缺少 exact-alarm 能力时直接返回 `EXACT_ALARM_PERMISSION_DENIED`，尚无允许的近似调度路径。
- `V2ReminderScheduleCoordinator`、`ReminderRecoveryCoordinator`、`V2ReminderDeliveryService`、`NotificationDisplayService` 已形成 Reminder queue、prepare/finalize、Recovery 和 delivery ID tag 主链，可扩展而不重建第二套调度器。
- Notification tap store/EventChannel 与 Flutter Anniversary detail 路由基础已经存在。

## 3. 文件所有权与协作边界

主要修改入口预计包括：

- `flutter_client/android/app/src/main/kotlin/**/bridge/contract/AnniversaryContracts.kt`
- 直接相关的 Reminder/Notification/Recovery Contract validators
- `bridge/channel/AnniversaryMethodHandler.kt`
- `bridge/channel/NativeMethodChannelHandler.kt`
- `bridge/native/NativeAnniversaryBridge.kt`
- `bridge/native/JniNativeCalendarCoreBridge.kt`
- `bridge/reminder/**`
- `android/alarm/**`
- `android/notification/**`
- 必要的 receiver/worker/factory/manifest 接线
- `flutter_client/android/app/src/main/cpp/boundary/adapter/jni/event_jni.cpp` 的最终薄 JNI thunk
- `src/test/**`、`src/androidTest/**` 和 debug smoke 中直接相关测试

禁止修改：

- `contracts/**`、`cpp_core/**`、`flutter_client/lib/**`；
- C++ workflow、JSON Store 或 identity 生成；
- Anniversary 分享、完整 Calendar UI、ring/wechat、多渠道部分成功或独立 Notification 历史；
- 为通过 JVM 测试而在生产代码返回假成功 NativeResult。

## 4. 独立开发与 Fake 规则

Kotlin 工作流不等待 C++ 分支合并。使用 test source set 的 Fake `NativeAnniversaryBridge` 和 fake Android services，按冻结 valid/invalid fixture 驱动 Handler、orchestrator、scheduler 和 display 测试。

Fake Native 至少覆盖：

- create/update 已保存且无需 reconcile；
- 已保存且 `schedule_reconciliation_required=true`；
- 调度成功、近似降级、notification permission 拒绝、调度失败待恢复；
- list occurrences 单页/多页/错误；
- normal Anniversary popup；
- 同 occurrence 多 Reminder 的一个 aggregate prepared payload；
- stale expected `remind_at`/identity 被 Native 拒绝；
- target deleted、prepared membership conflict、retryable/permanent finalize。

Fake scheduler/display service 必须记录调用次数、delivery ID/tag、payload 和 finalize 结果，证明“一个聚合 attempt 只 post 一次”。

禁止：

- 在 `MainActivity`、`AndroidNativeBridgeFactory`、正式 manifest 或 release source set 注入 Fake Native；
- Kotlin 自行构造未来 Reminder、successor、covered IDs 或 UUIDv5；
- C++ 尚未合并时增加返回成功的 JNI stub。若最终 JNI thunk 依赖并行分支尚不存在的 C++ symbol，应把 thunk 作为明确的集成待办，不用占位实现冒充通过。

## 5. 实施任务

### 5.1 Kotlin Contract 校验与 Response Mapping

依据冻结 schema 扩展 `AnniversaryContracts.kt` 和相关 validators：

- create/update 的 Reminder 总开关和 template plan；
- detail 的 Reminder 配置与 schedule/capability 状态；
- `anniversary.list_occurrences` request/response；
- Reminder Anniversary target-specific 字段；
- aggregate Notification/RecoveryBatch 的 `covered_reminder_ids`、fulfillment/recovery 关系；
- Notification tap 的 Anniversary occurrence identity；
- 新 enum/error/partial-success shape。

要求：

- 对 request 和 Native response 都做严格字段、类型、UUID、date、local time、UTC Instant、数组上限/唯一性、cursor 和版本校验；
- JSON number 的 Contract integer 按项目现有兼容模式验证为精确整数，不能把 `10.0` 一概误判，也不能截断非整数；
- Anniversary date/occurrence date 不填入 Event `occurrence_start_at`；
- 未知字段、未知 enum、非法 NativeResult 返回稳定 Contract failure；
- Handler 只转发 Contract 声明字段，不添加 Kotlin 私有状态。

### 5.2 MethodChannel Handler 与保存后编排

扩展 `AnniversaryMethodHandler`：

- 注册并转发 `anniversary.list_occurrences`；
- create/update/detail 使用新 shape；
- pause/resume 使用冻结的公开方法或 update intent，不拆成普通 Reminder enable/disable；
- create/update/delete/toggle 在 C++ 返回 logical commit 成功后，根据冻结 response 触发统一 Reminder reconciliation；
- reconciliation 失败时保留已保存 data，返回/合并 Contract 规定的“已保存、调度待恢复”状态；
- C++ 保存失败时不得启动调度；
- completion 只调用一次，异常路径不返回空成功。

建议把“Native Anniversary operation + post-commit reconcile”放入窄 orchestrator，Handler 保持薄；不要在多个 case 分支复制补偿逻辑。

### 5.3 Native Bridge 与 JNI 接口

扩展：

- `NativeAnniversaryBridge` 的 `listAnniversaryOccurrences`；
- `JniNativeCalendarCoreBridge` 的 external declaration 与 v2 envelope handling；
- JNI symbol 名、request JSON 和 C++ Boundary API 名严格对齐冻结 `native_calls.yaml`；
- Android/JNI smoke 测试覆盖 create/update/detail/list occurrences 的 valid/invalid round-trip。

并行分支允许先用 Fake Native 完成 Kotlin 逻辑。`event_jni.cpp` 的生产 thunk 只能在 C++ 真实 API 声明可用后接入；若分支隔离导致本阶段无法链接，交付中必须列出 exact symbol/header/thunk，留给最终集成人合并，不得加 production stub。

### 5.4 Post-commit Reminder Reconciliation

复用现有 Reminder queue/coordinator，不为 Anniversary 建第二套 Alarm：

1. C++ logical commit 成功并返回 reconciliation requirement；
2. Kotlin 调权威 queue reconcile；
3. 依据 C++ 返回的 `remind_at`、expected value 和 identity 注册 Dispatcher；
4. 调度成功返回 synced；
5. 调度失败安排现有 WorkManager/生命周期恢复，并返回 pending recovery；
6. App 启动、回前台、权限恢复、系统重启、App 升级、日期/系统时间/时区变化时再次 reconcile。

Kotlin 不得删除或禁用 C++ Reminder 来“回滚”AlarmManager 失败。旧 Alarm 触发后必须先走 Native prepare/CAS；Native 拒绝 stale target/occurrence/expected `remind_at` 时，Android 不展示 Notification。

### 5.5 Exact Alarm 近似降级

修改共享 Dispatcher 调度策略，使冻结 Contract 要求的 popup Reminder 在 exact-alarm 权限不可用时可采用允许的近似路径：

- API/能力判断集中在 Kotlin 平台层；Flutter 只消费 capability/degradation reason；
- exact 可用时延续当前精确 Dispatcher；
- exact 不可用时使用经过架构确认的 inexact Alarm/WorkManager 组合，并返回可展示“可能延迟”的稳定状态；
- notification permission 拒绝不删除任务；后续授权后自动 reconcile；
- 近似调度仍使用同一个逻辑 Dispatcher/expected `remind_at`，不能为每条 Anniversary Reminder 创建第二套私有 Alarm；
- 不改变 Ring 的安全要求和既有 Event Reminder 语义；共享代码变化必须做 Event/Ring/Recovery 回归。

具体 Android API 必须符合 minSdk 24 和当前 target SDK；未经用户授权不升级 Gradle/SDK/依赖。

### 5.6 系统事件与生命周期恢复

核对并补齐 receiver/worker/foreground lifecycle：

- `BOOT_COMPLETED`、package replaced/upgrade；
- timezone changed；
- date changed/system time changed；
- App startup/foreground；
- notification/exact-alarm 权限恢复后的主动 retry。

所有入口调用同一个 reconcile/recovery 编排，幂等 request ID 沿用现有机制。Kotlin 不自行重算 Anniversary occurrence 或日末窗口，只传当前 IANA timezone 和 trigger source 给 C++。

### 5.7 正常与聚合 Popup 投递

扩展 `V2ReminderDeliveryService`/attempt client/`NotificationDisplayService`：

- normal Anniversary popup 使用 C++ prepared payload 的冻结 title/body/target；
- aggregate Anniversary catch-up 由一个 prepared attempt 表达，Kotlin 只调用一次 `NotificationManager.notify`；
- Android tag 固定使用 `delivery_id`，重试覆盖同一条通知栏记录；
- 不为每个 `covered_reminder_id` 创建伪 Notification、PendingIntent 或 Android tag；
- post 成功后只 finalize 同一个 attempt；covered Reminder 的 sent/successor 由 C++ finalize transaction 完成；
- retryable/permanent failure 按 Contract 回传，不在 Kotlin 改 Reminder；
- membership 与文案一经 prepare 冻结，Kotlin 不加入新到期任务；
- 锁屏内容不得包含 Anniversary note。

不同 `(anniversary_id, occurrence_key)` 必须分别 post；不得合并为无详情目标的全局摘要。普通 Event/Recovery summary/Ring 的现有分流保持不变。

### 5.8 Notification 点击

扩展 prepared payload、PendingIntent 和 `NotificationTapPayloadContract`：

- 正常/聚合 Anniversary 点击都包含真实 notification/delivery/attempt、target、occurrence identity；
- 冷启动、热启动、重复点击沿用现有 store/EventChannel；
- target 删除仍把 identity 交 Flutter，由真实 detail 返回缺失状态；
- 不通过 Notification 文案解析路由；
- PendingIntent/request code/tag 继续保证 delivery 级幂等；
- 历史 notification 点击不得重新 finalize 或重复展示。

### 5.9 Runtime/Factory/Manifest 接线

更新真实 `MainActivity`/Handler factory/ReminderCoordinatorFactory/必要 receiver 或 manifest 接线，确保：

- release source set 使用 `AndroidNativeBridgeFactory` 的真实 JNI Bridge；
- 保存后的 reconcile 使用进程级 runtime owner，不创建竞争的 C++ runtime/Store；
- Service/Receiver exported 设置和权限符合现有安全基线；
- bootstrap 在 Scheduler/query 开放前等待 C++ 完成 migration/journal recovery；
- 不新增后台常驻服务或每条 Reminder 独立 Alarm。

## 6. 测试矩阵

### JVM Contract/Handler

- create/update/detail/list occurrences valid/invalid fixture；
- local date/time、array 0/5/6、重复 template、number 精确整数；
- malformed NativeResult、unknown enum/error/version；
- 保存失败不 reconcile；保存成功 reconcile；reconcile 失败返回已保存/pending；
- Handler completion exactly once；
- Fake Native 调用参数与冻结 JSON 完全一致。

### Scheduler/Recovery

- notification permission granted/denied/permanent denied/后续授权；
- exact allow/deny 与 inexact fallback；
- API 24 静态兼容；
- boot/upgrade/timezone/date/time/foreground trigger；
- stale expected `remind_at`/identity 不 post；
- 调度失败进入 retry，数据不清空；
- Event、Ring、普通 Recovery 回归。

### Delivery/Notification

- 一条正常 popup；
- 同 occurrence 1/多 Reminder 只 post 一个 aggregate popup；
- 不同 Anniversary occurrence 分别 post；
- stable delivery tag 重试覆盖；
- post success/failure 与 finalize；
- 冷/热启动、重复点击、target deleted；
- payload/锁屏内容无 note。

### JNI/设备

- JNI method name/symbol/shape；
- create/update/detail/list occurrences round-trip；
- real Alarm 到点、聚合补发、permission/exact 降级、时区变化、旧 Alarm 拒绝和点击详情；
- 进程终止/重启后的 recovery 与幂等。

必须运行适用的 Android JVM 定向和全量测试、`lintDebug`、Debug APK、androidTest APK 和 JNI smoke。最终完整命令按项目 Gradle 入口执行并在完成报告逐条列出。

## 7. Requirement 追踪

| 上位计划 | Kotlin/Android 交付 |
| --- | --- |
| §3.2 | post-commit reconcile、permission 保留、exact inexact 降级 |
| §3.3 | 单 aggregate post、delivery tag、冻结 membership 透传 |
| §3.4 | 保存后 reconcile、stale Alarm 展示前拒绝；核心 replacement 在 C++ |
| §3.5 | prepared content、无 note、Anniversary detail 点击 |
| §4 | MethodChannel/JNI list occurrences 严格透传 |
| §5.4 | 传设备 IANA timezone；不自行算 DST/UTC identity |
| §6 | Reminder/Notification/Recovery mapping 与一个真实系统通知 |
| §7.5 | logical commit 后 reconcile、失败待恢复 |
| §12.4、12.6 | JVM/Android/设备验证；跨层项交最终集成 |

## 8. 并行交付清单

Kotlin 负责人交付：

1. 修改文件、Handler/Bridge/orchestrator/scheduler 接口清单；
2. Fake Native/scheduler/display scenario 与调用证据；
3. JNI external method、期望 C++ API、symbol/thunk 对照表；
4. exact/inexact 策略与 API 24 兼容说明；
5. Android Notification tag/PendingIntent/点击身份说明；
6. JVM/lint/build/androidTest 的实际结果；
7. 因 C++ 分支隔离而留给集成的精确待办；
8. 上位计划 §10、§12.4 的逐条勾选状态。

## 9. 停止条件

遇到以下情况停止受影响开发：

- Contract 未冻结 aggregate kind/membership/finalize 或 partial-success；
- exact-alarm 降级会改变 Ring 或普通 Event 的已接受语义且无明确决策；
- Kotlin 需要计算 occurrence、successor 或 UUID 才能继续；
- 保存成功 response 不足以判断是否 reconcile；
- JNI 名称/shape 与冻结 native call 不一致；
- 需要通过 production stub、吞错或空成功才能构建；
- 平台限制要求升级 SDK/依赖或新增高风险权限，而用户未授权。

## 10. 本计划完成定义

达到“并行交付就绪”需满足：

- [ ] Kotlin Contract/Handler/调度/通知/点击均按冻结 Contract 实现；
- [ ] Fake Native 驱动的 JVM 正反例与共享 Reminder 回归通过；
- [ ] `lintDebug` 通过，Debug/Android test 构建已通过或只因真实 C++ symbol 未合并而准确标记；
- [ ] production source set 没有 Fake Native 或假成功；
- [ ] exact/inexact、permission、system trigger 和聚合一次 post 有测试证据；
- [ ] 未修改 Contract、Flutter 或 cpp_core；
- [ ] `docs/log.md` 已追加真实验证记录。

真实 JNI `.so`、C++ Store、Alarm 到点和 Notification 点击全链必须在最终集成后验证；单层 Fake/JVM 通过不能被报告为功能完成。

## 11. Kotlin/Android 开发交付总结

### 11.1 交付状态

Kotlin/Android 侧功能与时区协同改造已完成，JVM 测试和静态检查通过。受当前 C++ 工作区编译错误及无可用 ADB 设备影响，本轮最新代码的 APK、androidTest、真实 JNI 和真机链路尚未完成验证，因此整体状态为部分完成。

### 11.2 完成内容

- 完成 Anniversary create/update/detail/list occurrences/set reminders enabled 的严格 Contract、MethodChannel Handler、编排器及错误映射。
- 完成 Anniversary 保存后的 Reminder reconciliation；保存成功但调度失败时保留已提交结果，并返回待恢复状态。
- 完成 popup Reminder 的 exact alarm 能力判断与 inexact fallback，保持 Ring 既有 exact 语义不变。
- 完成开机、升级、日期、时间、时区和前台恢复触发，以及过期 Alarm 身份校验和恢复调度。
- 完成 Anniversary 正常通知与 catch-up 聚合通知；冻结 covered Reminder membership，保持 delivery、attempt、点击和详情身份稳定，通知及锁屏内容不包含 note。
- 完成 Anniversary JNI 声明、调用桥接和 native thunk，包括 `set_reminders_enabled` 与 `list_occurrences`。
- 复用 `DeviceTimezoneProvider`，在每次 `reminder.finalize_delivery` 和 `reminder.plan_recovery` 调用时即时读取设备 IANA 时区，不缓存启动时区。
- 所有 Event、Ring、普通 Reminder 和 Anniversary finalize 统一携带 timezone；C++ 返回 timezone 缺失或非法错误时保持失败结果，不展示为成功。
- 更新 Fake Native、JVM Contract/Handler、Reminder pipeline、Event/Ring 回归及 debug JNI smoke 覆盖。

### 11.3 主要修改范围

- Contract：`AnniversaryContracts.kt`、`ReminderDeliveryRequestContracts.kt`、`NotificationContracts.kt`、Reminder V2 相关映射。
- Channel/JNI：`AnniversaryMethodHandler.kt`、`AnniversaryMethodOrchestrator.kt`、`NativeMethodChannelHandler.kt`、`JniNativeCalendarCoreBridge.kt`、`NativeAnniversaryBridge.kt`、`event_jni.cpp`。
- Reminder/Recovery：`ReminderDeliveryAttemptClient.kt`、`V2ReminderDeliveryService.kt`、`ReminderRecoveryCoordinator.kt`、Reminder scheduler/coordinator 及 runtime factory。
- Alarm/Notification：`ReminderDispatchAlarmScheduler.kt`、`ReminderScheduler.kt`、`BootCompletedReceiver.kt`、`RingRuntime.kt`、Notification 编排与点击 Contract。
- 测试：Anniversary MethodChannel/JNI、V2 Boundary、V2 Reminder pipeline、Ring workflow、Notification bridge 及 debug JNI smoke。

### 11.4 验证结果

- Android JVM 全量测试通过：130 项通过、0 失败、1 项既有跳过。
- Anniversary、Reminder pipeline、Event、Ring、Notification 相关定向回归通过。
- `lintDebug` 通过。
- Android 范围差异格式检查通过，仅存在既有换行符提示。
- 本轮组合 APK/androidTest 构建被当前 C++ 构造函数签名不一致阻塞；阻塞文件位于 `cpp_core`，Kotlin 编译与测试未发现对应失败。
- 当前无可用 ADB 设备，Alarm 到点、时区变化、Notification 展示/点击和进程重启恢复未进行真机验证。

### 11.5 交付注意事项

- Kotlin 不计算 occurrence、successor、DST 或 UUID，相关领域计算仍由 C++ 负责。
- timezone 在每次 recovery/finalize 调用时读取；时区变化广播只负责 reconciliation，finalize 不依赖广播已完成。
- finalize 保持统一调用链，不按 target 在 Kotlin 复制分支；timezone 不参与 delivery 或 occurrence identity。
- Native 的 `CONTRACT_VALIDATION_FAILED`、`TIMEZONE_ID_INVALID` 等错误保持失败语义，不吞错、不转换为成功。
- 本次 Kotlin 开发未修改 Flutter、Contract Schema 或 `cpp_core`，并保留了工作区内已有的并行修改。
