# 问题清单

## 一、Contract、Reminder 与基础能力

### Contract 缺口

当前有 `reminder.cancel`，可实现取消链路。

design-only v2 已在 `native_calls.yaml` 声明 Kotlin→C++ 内部 `reminder.get(reminder_id)`，供 Alarm/Notification 调度链按 ID 读取；它不暴露给 Flutter。现有 v1 运行时代码若仍通过 `reminder.list` 在前 200 条内预检，必须在 v2 实施时切到该内部调用。若未来 Flutter 也需要直接按 ID 读取，再单独评审是否增加公开 MethodChannel，而不是复用调度接口。

### ~~Anniversary 年度规则已设计但尚未落地~~

2026-08-09 已独立冻结 Anniversary V1 的 `AnniversaryRecurrence` / `anniversary_recurrences` 语义，避免继续套用 Event v2：规则只保存 `yearly + interval=1` 与生命周期时间，原始日期及月/日锚点只保存在 `Anniversary.date`，下一次日期由 C++ 查询时动态计算，不预生成未来 occurrence。

当前风险不是协议歧义，而是实现尚未完成：相关 Anniversary Schema 和 MethodChannel/JNI 能力仍标记 `implementation_status: planned`，Calendar Core JSON 尚未增加 Anniversary/AnniversaryRecurrence store，C++ Domain/Workflow/Repository 也未落地。任何上层不得因 Contract 已存在而伪装成 Native 已可用。

生命周期实现必须保持同一事务：年度重复保持开启时保留原 `recurrence_id`；一次性切到年度重复时新建规则；年度重复切到一次性时清空引用并软删除旧规则。Anniversary Reminder 仍受 recurrence/reminder 强制设计门禁约束，occurrence identity、幂等、唯一键和 reconciliation 未冻结前不得接入。

### ~~[P0] Native Contract v2 已定稿但运行时代码仍是 v1~~

根因：重复 Event、滚动 Reminder、两阶段 Notification、72 小时恢复和 JSON 事务必须跨 Dart、Kotlin、JNI、C++ 与 Storage 同步切换，无法安全拆成允许 v1/v2 混读的中间版本。

触发条件：任何一层提前发送/接受 v2 payload，或在全部 v2 reader/writer 就绪前创建 v2 writer。

影响：字段解释漂移、all-day 时间丢失、重复 Reminder 重复投递、旧数据不可读，最坏情况下会把正式 v1 数据误当作 v2 重写。

已于 2026-08-08 关闭：用户决策激活 v2 且不再保留 v1 数据。`method_channels.yaml`、`native_calls.yaml`、`identity.yaml` 与 Storage map 已切换为 `release_status: active` / `implementation_status: integrated`；Dart、Kotlin、JNI 与 Android 调度已全部切换到 v2，真机（realme RMX5100, Android 16 / API 36）首轮验证通过（记录见 `docs/develop_record.md`）。C++ bootstrap 改为“确认 v1 后直接清理”，不再创建时间戳归档；Kotlin 不再迁移 `test_storage_json`。

剩余未验证项（不阻止激活，但需要继续覆盖）：

- Alarm 到点真实触发（下一次调度 2026-08-09 11:45 北京时间）与投递/重试行为。
- 进程崩溃或被杀后的 journal 重放。
- Recovery `abandoned_to_summary` / `abandoned_outside_window` 真机分支。
- 国产 ROM（realme）Doze/后台限制的长周期行为。
- Habit 的重复语义不能套用 Event v2；Anniversary 基础年度规则已另立协议，但其 C++/Storage 实现与 Reminder 重复语义仍未完成。

> 状态更新：2026-08-08 v2 已激活并完成首轮真机验证。下文其余条目中关于“v1 运行时仍未切换”的描述仅作为历史背景，不再代表当前 APK 状态。

### ~~重复 Reminder v2 的五个冻结语义缺口~~

根因：最初 Contract 只描述主流程，没有冻结异步 Alarm 确认、occurrence reopen、恢复窗口淘汰和已 prepared 投递跨 Recovery 的并发裁决；同时把“发布可用”和“某一层已实现”混为一个状态。

触发条件包括旧 Alarm 在 Reminder 改时后回写、reopen 时已有同模板 successor、已物化 Reminder 严格落到 72 小时窗口外，以及 frozen prepared attempt 在 Recovery 重新分流。

影响是旧调度覆盖新时间、同模板出现两条 open Reminder、窗口外记录永久滞留调度队列，或 Android 继续 finalize 已被恢复摘要取代的旧 payload。

已于 2026-08-04 修复：

- `reminder.mark_scheduled` 强制携带 `expected_remind_at` 并在事务内 CAS；不匹配返回可重试 `REMINDER_SCHEDULE_CONFLICT`，不产生写入。
- 新增 `occurrence_reopened` 取消原因；reopen 原子暂存较晚 open successor，再恢复原 Reminder，后续滚动复用确定性 ID。
- 新增 `ReminderStatus.expired`、`recovery_window_elapsed` 和 `expired_at`；仅 `planRecovery` 可终结严格早于窗口的已物化 open Reminder，重复项在同一事务确保首个未来 successor。
- prepared payload 保持冻结；Recovery 通过 `adopted_detail`、`abandoned_to_summary`、`abandoned_outside_window` 原子接管或废弃 attempt。被废弃 attempt 的旧 finalize 返回 `DELIVERY_ATTEMPT_INVALID` 且不修改状态。
- v2 当时保持 `release_status: design_only`，另以 `implementation_status: cpp_core_complete_unintegrated` 表达 C++/Storage 完成但跨端未接入（该状态已于 2026-08-08 切换为 active / integrated）。

验证：C++ `excellent_calendar_check` 3/3 通过；CAS 无写入、reopen 单 open、expired 边界/计数/successor、attempt 幂等裁决/旧 finalize 拒绝、Boundary JSON 和 journal 逻辑 store 名均有回归测试。本项剩余风险集中在 JNI/Kotlin/Dart/Android 集成门禁，不能据此激活 v2。

### ~~adopted attempt finalize 被 Kotlin 误判失败~~

根因：`finalize_delivery_response` 与 Kotlin validator 只用 `notification.recovery_batch_id` 判断 response 是否必须携带 `recovery_batch`，遗漏了 frozen prepared attempt 通过 `resolved_by_recovery_batch_id` 归属 Recovery 的既定语义。

触发条件：Recovery 接管旧 prepared attempt 后，C++ 成功 finalize 并返回 RecoveryBatch；此时旧 attempt 保持 `recovery_batch_id = null`，同时写入 `resolved_by_recovery_batch_id`。

影响：C++ 事务已经提交为成功，但 Kotlin 将合法 response 转成不可重试的 `CONTRACT_VALIDATION_FAILED`，造成领域状态与 Android 编排状态分裂，并可能阻止 Recovery request 正常清理。

已于 2026-08-04 修复：Contract 和 Kotlin 统一把 `recovery_batch_id` 或 `resolved_by_recovery_batch_id` 任一非空视为 Recovery 归属；两者都为空时仍强制 `recovery_batch = null`。新增 validator 与 delivery pipeline 回归，覆盖 adopted attempt 返回 completed RecoveryBatch，并保留不一致 response 的拒绝行为。

### ~~`expired` 在 Reminder Contract 内部不一致~~

根因：`ReminderStatus`、response 和 C++ 已支持 `expired`，但 `list_reminders_request.status` 与 Kotlin v2 request validator 仍保留旧的五状态集合。

触发条件：调用 `reminder.list` 并显式传入 `status = ["expired"]`。

影响：请求在 JNI 前被拒绝，恢复历史、过期统计和 Recovery 审计无法精确查询，但不影响 Dispatcher 调度。

已于 2026-08-04 修复：list request Schema 增加 `expired`；Kotlin 改为复用统一的 `ContractEnums.ReminderStatus`，并新增接受 `expired`、拒绝未知状态的回归测试。该变更只放宽合法查询输入，不改变持久化数据、状态机或默认列表行为。

### ~~创建EVENT CPP部分存在问题~~

~~在create_event_request.hpp里面~~

~~没有相关的reminders字段，但是在通过flutter和，kotlin传下来的字段是有的~~

~~在event_api.cpp中如果存在了reminders这个字段，反而会报错failure(feature_not_implemented("reminders"))~~

~~这个部分应该是之前还没有弄好“提醒”这个模块时，为了避免产生错误，所以传的时候没有使用reminders~~

~~然后也是因为我们在之前的flutter层和kotlin层，因为我们还没有设计好提醒的前端页面，所有的reminders字段我们默认都是一个空数组，所以这里也没有报错~~
~~reminder可以为空，表示不需要提醒，但是还是需要接受里面的数据啊~~

### ~~创建提醒的时候的上下层不统一~~

~~reminder里面的有一个字段  "is_enabled",表示这个提醒是否是启动的。~~

~~存在的问题便是在于，我创建了一个is_enabled=false提醒，表示这个提醒不需要启动，但是他又必须存在。~~

~~在前面的flutter和kotlin验证的时候，他们是运行is_anabled=false这样的存在，但是最后放在了CPP的时候，又不允许这样的存在了~~
~~所以在create_reminder_request.schema.json这里面，严格按照要求，默认创建的时候就是true，后面再通过reaminder.update修改才可以改为false~~

### ~~目前协议存在漏洞~~

~~只要是涉及到了跨层的调用或者说数据的传输，我们就一定需要走contracts~~
~~但是我们有几个函数 `markReminderScheduled` 和 `markReminderFailed`他们是没有走method_channel里面的方法的，我们应该提前在method_channel里面约束好这两个方法需要传输的字段和规范~~

### 不支持的微信提醒方式会导致整个调度失败

我们把reminder里面如果涉及到了不支持的wechat提醒方式就会直接报错，然后整个提醒的调度就会直接失败

### 查询提醒的方式存在问题

目前我们我们查询提醒的方式就是在于把所有的提醒这个表里面的数据挨个查一遍，然后看看是否有我们对应的提醒任务，因为目前我们还只是定义了这个函数，所以我们要新建一个getreminderbyid的新的接口，让上层可以根据直接查看id是否中存在来看看是否有这个提醒。

### ~~允许创建过去时间的提醒~~

~~我们的这个时间的提醒，只会验证时间是UTC格式，应该加一个验证环节，reminder > 当前时间。在reminder_service.cpp 225~~

### 其他基础功能

- 现在完成日志这个选项还没有做，需要正式实现这个功能
- 现在还没有正式接入通知这个任务，需要接入这个通知，然后通知发生之后，我们可以点击完成选项完成或者日程。
- 现在点击之后，不能查看日志的一个详细情况
- 现在的日程都是默认即将到来的一个状态，我们需要设置好恰当的时间线去调整

## 二、通知投递与消费链路

### 缺少投递前生成的稳定 `notification_id`

[notification_tap_payload.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\notification\\notification_tap_payload.schema.json:9) 要求点击 PendingIntent 必须包含 `notification_id`。

v1 的 `consume_reminder_after_delivery` 与 `notification.create` 协议都不接收预先生成的 `notification_id`。这两个 v1 Schema 已在 design-only Contract v2 中移除并由 `reminder.prepare_delivery/finalize_delivery` 替代；C++/Storage v2 已实现，但现有 Dart/Kotlin/JNI 与 Android 投递链仍未切换，因此 APK 运行时问题仍未关闭。

这会产生顺序矛盾：

- 先弹系统通知：构造 PendingIntent 时还没有 Notification ID。
- 先调用 consume：数据库已经记录 sent，但系统通知可能随后展示失败。

design-only v2 已采用两阶段协议：

```text
reminder.prepare_delivery
→ 返回 notification_id / delivery_attempt_id / tap_payload
→ Android NotificationManager.notify
→ reminder.finalize_delivery
```

`finalize_delivery` 根据成功或失败原子更新 Notification 和 Reminder。

### 投递流程缺少幂等键

Alarm Receiver 可能因为进程重启、系统重投或异常恢复重复执行。当前 consume_after_delivery 只有 reminder_id，无法准确区分同一次投递重试。

design-only v2 已增加：

- `delivery_id`
- `delivery_attempt_id`
- `expected_remind_at`

同一个 `delivery_attempt_id` 重复提交应返回之前结果，而不是 `REMINDER_ALREADY_CONSUMED` 错误。

### ~~无法防止旧 Alarm 消费更新后的 Reminder~~

[get_reminder_request.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\get_reminder_request.schema.json:9) 只包含 ID。如果提醒从 08:00 修改到 09:00，而旧的 08:00 Alarm 仍然触发，它可能读取并消费已经更新的 Reminder。

建议 Alarm PendingIntent 和后续请求携带 `expected_remind_at` 或 `schedule_generation`，C++ 必须验证它与当前 Reminder 一致。

### `reminder.get` 不足以生成实际通知内容

[reminder_response.schema.json (line 20)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\reminder_response.schema.json:20) 只有目标 ID 和提醒 message，没有 Event/Habit/Anniversary 的标题。而 consume_after_delivery 又要求 Kotlin提供非空 title。

design-only v2 不再让 Kotlin 用 `reminder.get` 拼装正文；`reminder.prepare_delivery` 由 C++ 返回已持久化的 Notification、展示内容和 PreparedNotificationPayload：

```text
reminder.prepare_delivery
```

标题仍不冗余写进 Reminder 领域模型。现有 v1 运行时在切换前仍有本问题。

### 通知点击只读一次并立即清除，不够可靠

[notification_tap_payload_response.schema.json (line 5)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\notification\\notification_tap_payload_response.schema.json:5) 规定读取成功后立即清除。Flutter 取到 payload 后如果在完成导航前崩溃，该点击会永久丢失。

EventChannel 也可能在 Flutter 订阅前发出事件。

建议改成持久化的小型点击队列：

```text
notification.peek_pending_taps
notification.ack_tap
```

payload 增加 `tap_id`，Flutter 完成导航后再确认消费。

### 启动恢复来源没有进入协议

v1 `reminder.schedule_pending` 不仅会由 App 启动触发，还会涉及 Android 重启、包替换、时间/时区调整和手动重试。design-only v2 已删除该方法并增加 `reminder.plan_recovery(recovery_request_id, trigger_source)`；稳定来源为：

- `app_start`
- `device_boot`
- `alarm_reconcile`

Kotlin 把包替换、时间/时区变化和手动重试统一编排到 `alarm_reconcile`，并持久化 `recovery_request_id`；该内部能力不依赖 Flutter MethodChannel。运行时实现尚未落地。

### 批量调度错误信息不足

v1 `schedule_pending_reminders` 返回只有失败 ID 和数量，没有每条失败的错误码、原因及可重试状态。该 Schema 已从 design-only v2 删除；v2 通过逐次 `prepare_delivery/finalize_delivery` 的稳定错误码与 `failure_class` 表达，但运行时代码仍待实现。

建议改成：

```json
{
  "failures": [
    {
      "reminder_id": "...",
      "code": "ALARM_SCHEDULE_FAILED",
      "message": "...",
      "retryable": true
    }
  ]
}
```

### 精确提醒还是近似提醒尚未明确

权限 Contract 同时提供 notification permission 和 exact-alarm permission，这很好；但 Reminder 没有声明是否必须精确触发。

需要明确：

- 所有 Reminder 都要求 exact alarm；或者
- 支持 exact / inexact 调度策略，并在无精确权限时降级。

否则 schedule_pending 遇到缺少精确闹钟权限时，各平台实现可能采取不同策略。

### 重复提醒尚未进入消费闭环

v1 `consume_reminder_after_delivery` 的 `delete_after_sent` 当前固定为 true，所以 APK 已接入链路只覆盖一次性 Reminder。design-only v2 删除物理消费语义，改为保留历史并在 finalize workflow 原子生成 successor；C++/Storage 已实现该行为，但 JNI/Kotlin/Dart 尚未接入，因此运行时问题仍然存在。

v2 已在同一 C++ workflow transaction 中实现保留当前历史并创建确定性 successor；当前缺口是跨端接入与 Android/native smoke 验证，而不是继续新增另一套 `next_reminder` 协议。

## 三、`notification_id` 的生成时机冲突

正常投递顺序是：

```text
Alarm 到点
→ 构造 Android Notification 和点击 PendingIntent
→ NotificationManager.notify()
→ C++ consume_after_delivery
→ C++ 创建 NotificationResponse.id
```

问题是，Android Notification 在调用 notify() 前就必须准备好点击 payload；但真正的 NotificationResponse.id 要到之后调用 C++ 才生成。

也就是说：

需要 notification_id 的时间

早于

C++ 生成 notification_id 的时间

当前实现使用稳定的 reminder_id 作为点击 payload 的 notification_id 去重键。它能保证同一条通知重复点击不会重复导航，但它不等于 C++ 中持久化的 NotificationResponse.id。

### 当前影响

- Flutter 只使用 payload 打开 target_id 对应页面：没有问题。
- Flutter 把 notification_id 只当作不透明去重键：没有问题。
- Flutter 使用该 ID 查询 Notification 记录：会查询不到。
- 埋点需要把点击和 Notification 表记录严格关联：会关联失败。

将来一个 Reminder 可以重复投递多次时，只用 reminder ID 会错误地把后续投递视为重复点击。

当前 V1 是一次性提醒，且 delete_after_sent=true，所以短期风险较低。

### v2 已定稿的长期解决方案

design-only v2 已在 Contract 中把三个概念分开：

```json
{
  "delivery_id": "稳定的单次投递去重键",
  "delivery_attempt_id": "每次实际尝试唯一",
  "notification_id": "本次 Notification attempt 的真实 ID"
}
```

已定稿的原生两阶段流程为：

```text
reminder.prepare_delivery
→ C++ 提前生成 notification_id / delivery_id / delivery_attempt_id
→ Kotlin 展示系统通知
→ reminder.finalize_delivery 使用同一 attempt 完成持久化
```

这样可以同时保证：

- 点击 payload 使用真实 Notification ID；
- 重试具有幂等键；
- Flutter 点击事件能关联 C++ 记录；
- 系统通知失败时不会被错误记录为 sent。

### 结论

目前可以继续开发，前提是：

- V1 UI 暂时只开放 popup。
- Flutter 将点击 payload 的 notification_id 只用于去重，不用于查询 C++ Notification。
- 在支持 ring、重复提醒或通知历史点击关联前，先完成一次独立 Contract 变更。

## 四、端到端功能、调度与状态问题

### [P1] 通知点击后没有进入可用页面

[notification_tap_router.dart (line 36)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/routing/notification_tap_router.dart:36) 将日程通知路由到详情页，但 [app_router.dart (line 20)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/routing/app_router.dart:20) 只是固定显示“日程不存在或已删除”，没有读取日程，也没有进入用户描述的主页面。当前闭环在最后一步实际中断。

### ~~[P1] 部分提醒可能永远没有注册 Android Alarm。~~

[schedule_pending_reminders_use_case.dart (line 5)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/reminder/schedule_pending_reminders_use_case.dart:5) 每次只扫描未来 7 天、最多 128 条，并且不处理返回结果中的 has_more。[BootCompletedReceiver.kt (line 19)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/alarm/BootCompletedReceiver.kt:19) 同样只执行一次，没有发现周期扫描机制。因此：

- 7 天内超过 128 条时，后续提醒不会注册。
- 超过 7 天的提醒进入窗口后，如果用户没有重新打开 App、重启手机或修改日程，也不会注册。

已修复：Android 改为由 Reminder 持久队列驱动的单 Dispatcher Alarm；C++ 调度查询支持无界 keyset cursor，Alarm/Boot/前台与 WorkManager 看门狗统一进入 `ReminderScheduleCoordinator`，不再依赖 7 天窗口或 128 条批次。

### ~~[P1] 过期 Alarm 会先显示错误通知，再由 C++ 拒绝。~~

[ReminderDeliveryService.kt (line 51)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/ReminderDeliveryService.kt:51) 使用 Alarm 中的旧 plannedAt 直接弹通知，到第 83 行才调用 C++ 消费；而 C++ 在 [notification_service.cpp (line 236)](/A:/calendar/ExcellentCalendarAPP/cpp_core/src/application/notification_service.cpp:236) 才检查时间是否仍匹配。用户可能看到或听到本不应该触发的旧提醒。

这个并不是一个大问题，首先我们到点之后，不是直接触发一个通知，而是说先进入一个dispatcher，先reconcile这表里面是否有我需要存在的通知还没有提醒。所以哪怕我们修改了通知提醒时间，旧的Alarm依旧不会触发一个通知。

所以我们日后的开发时，如果涉及到了要修改一个提醒时间，我们需要在修改后的时间重新设立一个reconcile。

### ~~[P1] 完成日程不会处理尚未触发的提醒。~~

[complete_event_use_case.dart (line 11)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/complete_event_use_case.dart:11) 只完成 Event；C++ 的 [event_service.cpp (line 326)](/A:/calendar/ExcellentCalendarAPP/cpp_core/src/application/event_service.cpp:326) 也只修改 Event 状态。关联 Reminder 仍然是 scheduled，因此用户提前完成日程后，提醒依然可能照常弹出。

已经着手修复

### ~~[P2] 创建日程成功会掩盖提醒调度失败。~~

[create_event_use_case.dart (line 19)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/create_event_use_case.dart:19) 等待调度调用，但最终始终返回日程创建结果。无论 schedule_pending 整体失败，还是返回 failed_count > 0，上层看到的仍是创建成功。

这个本身不是问题，问题的出现在于我们之后是否有可靠的reconcile机制，因为我们无法保证一个提醒哪怕他已经是scheduled了，但是我们不能保证他之后一定会提醒，比如设备的重启，后台的关掉。

### [P2] notification_id 实际保存的是 Reminder ID。

[NotificationDisplayService.kt (line 85)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/notification/NotificationDisplayService.kt:85) 将 notification_id 和 reminder_id 都设置为 content.reminderId。这与 DATA_MODEL 中 Notification 和 Reminder 是两个独立实体、各自具有独立 ID 的设计不一致，也使点击载荷无法追踪 C++ 创建的真实 Notification 记录。

### ~~[P2] 不同提醒可能覆盖彼此的系统通知。~~

[NotificationDisplayService.kt (line 131)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/notification/NotificationDisplayService.kt:131) 使用 Java 字符串哈希作为 Android Notification ID。哈希存在碰撞，例如 "Aa" 与 "BB" 会得到同一个 ID，后一条通知会覆盖前一条。

### ~~[P2] Notification 初始化失败后仍继续注册提醒。~~

[app_notification_bootstrap.dart (line 88)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/bootstrap/app_notification_bootstrap.dart:88) 将状态设为 degraded 后没有终止流程，第 93 至 94 行仍检查权限并执行调度。这不符合所定义的初始化先决顺序。

2026-08-09 核对当前实现后确认该描述已过期：`notification.initialize` 失败后会立即 `return`，不会检查权限或执行 Reminder reconcile；`app_notification_bootstrap_test.dart` 明确断言初始化失败时 reconcile 调用次数为 0。本轮职责拆分继续保留并通过该回归行为。

### ~~[P3] 存在会长期误导开发的命名~~

[NativeEventBridge.kt (line 11)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/native/NativeEventBridge.kt:11) 已承担 Event、Reminder、Notification 三类能力，但仍叫 NativeEventBridge。[AndroidNativeBridgeFactory.kt (line 8)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/native/AndroidNativeBridgeFactory.kt:8) 的正式数据目录仍叫 test_storage_json。

已通过 Native Calendar Core Bridge 拆分和 `calendar_core_storage_json` 目录切换解决；`test_storage_json` 不再作为迁移来源（V1 数据不保留，2026-08-08 用户决策）。

## 五、自动化测试与端到端验证

当前自动化测试没有真正验证整个三端闭环。

Flutter 和 Kotlin 测试使用 Fake Gateway/Fake Native Bridge/Fake Notification Service；C++ 测试独立运行。它们不能证明真实 MethodChannel、JNI、文件、AlarmManager、系统通知及点击 Intent 能在设备上连续工作。

2026-08-10 补充：Anniversary 已通过 debug-only ADB Receiver 验证正式 Kotlin factory → JNI → C++ → JSON Storage 的 create/detail/soft-delete 子链路，因此该模块不再属于“仅 Fake/独立测试”。该 smoke 不覆盖 Flutter MethodChannel UI 驱动、AlarmManager、系统通知或点击 Intent，上述全链路风险仍然存在。

## 六、Kotlin 职责边界整改记录

### ~~MethodChannel 总入口与 V2 Contract 校验持续跨模块膨胀~~

根因：`NativeMethodChannelHandler` 同时承担顶层分发、各域请求/响应适配、Android operation、Native 执行、错误归一化和 mutation 后调度；`V2BoundaryContracts` 同时实现 Event、Occurrence、Recurrence 与 Reminder 规则。新增 Anniversary 时仍需修改中心 Handler，证明变化面已经跨越模块边界。

触发条件：新增领域方法、调整任一模块 Contract、修改通知权限或 Reminder reconcile 策略时，都要修改中心对象，并共同承担线程切换、exactly-once completion 和 post-commit 语义风险。

影响：模块变化相互牵连，回归矩阵扩大；通用 Native 执行模板了解 Reminder 后置调度，新增域容易继续形成 God Object。

已于 2026-08-09 修复：保留 `NativeMethodChannelHandler` 与 `V2RequestContracts` / `V2ResponseContracts` 兼容 façade；按 Runtime、Event、Anniversary、Reminder、Notification 拆分模块 handler，按 Event、Occurrence、Recurrence、Reminder 拆分 v2 validator；共享执行、错误适配和 post-commit reconcile 分别进入 `NativeCallExecutor` 与 `MutationScheduleHook`。各模块 handler 依赖窄 Bridge，只有 composition/dispatch 入口依赖聚合 `NativeCalendarCoreBridge`。

验证：相关定向 JVM 测试通过；`:app:testDebugUnitTest` 全量 78 项为 0 failure、0 error、1 skipped；`flutter analyze` 和不排除 Flutter 编译任务的 Android Debug 构建通过。项目 lint 仍有既有错误，ADB 无设备，均未伪报为通过。

## 七、Anniversary JNI 集成测试运行时组装记录

### ~~[P1] 同一 Android 进程中创建第二套 Calendar Core v2 bridge 会竞争 process-global C++ runtime~~

根因：Calendar Core v2 runtime 是进程级单例；最初的 Anniversary smoke harness 另外创建临时 storage bridge，同时 App 启动的 WorkManager/正式 `AndroidNativeBridgeFactory` 也会初始化 runtime。两个不同目录的初始化存在时序竞争，测试调用可能在另一套 runtime 状态下执行并返回 `STORAGE_NOT_INITIALIZED`。

触发条件：Android instrumentation、debug receiver 或其他进程内测试绕过正式 factory，自行实例化使用不同 storage/tzdb 目录的 v2 JNI bridge，同时 Application/Worker 仍可能启动。

影响：会制造与生产路径无关的假阴性，也可能让测试误读另一目录的数据；不能用重试掩盖，因为根因是 runtime ownership 冲突。

已于 2026-08-10 修复：Anniversary debug Receiver 与 AndroidTest instrumentation 共用 `AnniversaryJniSmokeRunner`，runner 只通过正式 `AndroidNativeBridgeFactory.create(context)` 取得 bridge，并使用正式 v2 storage 目录。测试创建的记录在验证持久化重载后立即软删除。

验证：realme RMX5100（Android 16 / API 36）上重新安装当前 Debug APK 后，正式 factory → Kotlin JNI bridge → C++ → JSON Storage 路径完成 create/detail/soft-delete，返回 `PASS`。后续所有进程内 JNI 集成测试都必须复用正式 factory/runtime owner；需要隔离目录时应使用独立测试进程，不能在同一进程创建竞争 runtime。

### ~~[P1] Anniversary Kotlin Contract validator 在 minSdk 24/25 使用 API 26 `java.time`~~

根因：Anniversary 的日期与 UTC Instant 校验最初直接调用 `LocalDate.parse`、`Instant.parse` 和 `DateTimeParseException`；项目 minSdk 为 24，且当前未启用 core library desugaring，因此这些调用在 API 24/25 不安全。`lintDebug` 对该文件报告 6 个 `NewApi` error。

已于 2026-08-10 修复：validator 继续先检查固定 wire 格式，再使用纯整数月日范围、Gregorian 闰年规则和时分秒范围校验，不在 Kotlin 计算 Anniversary 业务投影，也不增加依赖或提高 minSdk。新增非法 `2021-02-29` 与非法 UTC 日期回归测试。debug-only ADB Receiver 同时增加 `android.permission.DUMP`，保留 shell 真机验收能力并阻止普通第三方 App 调用。

验证：Anniversary Kotlin 定向测试、Debug APK 构建和受保护 Receiver 真机 smoke 通过；复跑 lint 后 Anniversary/Smoke 零 finding。全项目 lint 仍有 29 个既有 error、20 个既有 warning，均不在 Anniversary/Smoke 文件，本轮未越界处理。

## 八、Anniversary list 排序 Contract

### ~~[P2] top-level 与 nested pagination 排序位置和默认值不一致~~

根因：`list_anniversaries_request.schema.json` 同时声明 Anniversary 专属 top-level `sort_by/sort_direction`，又引用允许任意 nested `sort_by`、默认 `sort_direction=desc` 的公共 Pagination Schema；Dart 公共 `PaginationRequestDto` 复现同一宽松输入与默认值。Kotlin 接受任意 nested sort，C++ 则以 top-level 优先并最终只允许 `target_occurrence_date/countdown_days`，导致 Schema、调用方默认和运行时不一致。

触发条件：调用方只使用公共 Pagination DTO，或发送 `pagination.sort_by=title`，或同时在 top-level 与 nested 位置提交不同排序。

影响：Schema 合法请求可能在 C++ 返回 `CONTRACT_VALIDATION_FAILED`；仅依赖公共 DTO 默认值的 Anniversary list 还会从文档约定的升序变为显式降序；双位置请求的实际优先级只能从实现推断。

已于 2026-08-10 修复：Anniversary 专用 `pagination` 只允许 `page/page_size/cursor`，排序唯一位于 request top-level，缺失默认 `target_occurrence_date/asc`。Dart 改用不含 sort 的专用分页 DTO；Kotlin 与 C++ 同步拒绝 nested sort。新增默认升序、top-level 降序、非法 nested key 和双位置冲突回归。

验证：Contract 129 个 JSON 的语法、唯一 `$id`、本地 `$ref` 与 Anniversary sort 结构断言通过；Dart 定向/全量、Kotlin 定向/全量 JVM、C++ `excellent_calendar_check` 5/5、Flutter analyze、主 APK Debug 和 Native Smoke 构建均通过。该变更不涉及持久化或 migration；未重复执行真机 Anniversary list。

## 九、Category Native/Storage 已实现，但发布仍阻断

### [P1] `implemented_unintegrated + blocked` 与生产 Composition 冲突

根因：Contracts 已正确把 `category.list` / `category.create`、Native Call 和 Category Store 从不准确的 `planned` 收敛为 `implemented_unintegrated + blocked`，但 Flutter `buildProductionApp()` 已无条件注入 `NativeCategoryRepository(MethodChannelCategoryAdapter())`。发布状态整改与生产 Composition 切换没有在同一激活门禁中完成。

触发条件：当前 Production Composition 启动、打开 Category 页面或创建 Category 时，会直接调用仍被正式 Contract 标为 blocked 的 Native 能力。

影响：同一工作区同时表达“上层不得依赖”和“生产入口已启用”两种事实。底层 JNI smoke 或单元测试成功不能消除该冲突；当前状态不能按已发布能力合并或交付。

当前要求：在状态保持 blocked 期间，生产入口不得无条件依赖 Native Category；如果当前工作区不做中间合并，则必须先关闭下述 C++、Kotlin 和完整设备 smoke 门禁，再在同一集成变更中把 MethodChannel、Native Call、Store/schema 和正式文档统一切换为 `integrated + active`。禁止为配合已提前接入的生产代码而提前修改 Contract 状态。

验收：静态 release-gate 必须保证二选一——blocked 时生产不依赖 Native；生产依赖 Native 时所有正式状态均为 active。最终同一 APK 还必须完成 Flutter UI→MethodChannel→Kotlin→JNI→C++→Storage 全链验证。

### [P1] Category 回滚自身失败时，旧快照权威保证失效

根因：`AtomicJsonFileStore` 在 replace 后第一次 directory fsync 失败时会尝试恢复旧文件，但 rollback replace、恢复后的第二次 directory fsync 或 rollback 字节验证再次失败时，只返回组合 `STORAGE_IO_ERROR`。`JsonCategoryRepository::initialize/load` 不识别未完成的 `.rollback` 状态，仍可能读取已替换的新 `categories.json`。

触发条件：原子 replace 已成功，提交点 directory fsync 失败，随后 rollback 文件丢失、rollback replace 失败、第二次目录同步失败或恢复字节验证失败。

已复现结果：独立双故障探针得到 `api_failed=1 error=STORAGE_IO_ERROR immediate_count=2 restart_count=2 rollback_exists=0`。即第二次 Category 创建返回失败，但新 Category 当场可见，runtime/进程重建后仍可见。

影响：违反 `calendar_core_storage.yaml` 和 `DATA_MODEL.md` 中“目录同步成功才提交；任何验证或 I/O 失败后旧快照仍权威”的正式保证。调用方在收到失败后安全重试可能创建重复记录，API 结果与磁盘事实不一致。

当前要求：replace 前写入并持久化可恢复事务状态，记录旧快照或“旧文件不存在”事实；Repository 初始化和读取必须先完成未结束回滚。若恢复仍无法完成，runtime 必须拒绝把目标文件作为权威状态，不能继续暴露新快照。若要改成“提交结果不确定”，必须先修改正式 Contract，不得让其他语言层适配当前缺陷。

验收：新增 `rollback_replace`、`rollback_directory_fsync`、`rollback_verify` 故障注入；任何返回失败的场景在即时读取、runtime 重建和进程重启后都保持旧文件字节与旧列表；恢复后单次重试只创建一条记录。

### [P1] Kotlin 未登记 `CATEGORY_SORT_ORDER_EXHAUSTED`

根因：Contract、NativeError Schema、C++ 和 Dart 已加入 `CATEGORY_SORT_ORDER_EXHAUSTED`，但 Kotlin `NativeErrorCodes` 常量及 `All` 集合仍只有 `CATEGORY_NAME_EMPTY` 和 `CATEGORY_NOT_FOUND`。`NativeResultContract` 会拒绝不在 `All` 中的错误码，`NativeCallExecutor` 随后把它改写为 `CONTRACT_VALIDATION_FAILED`。

触发条件：已有活动 Category 的 `sort_order=9007199254740991`，随后使用 `sort_order=null` 请求自动追加。

影响：C++ 正确返回的稳定领域错误无法到达 Flutter，CAT-008 仅完成数值范围同步，没有完成跨层错误语义闭环。独立 JVM 负例已确认合法耗尽错误会触发 `NativeContractViolation`。

当前要求：Kotlin 增加同名常量并加入 `NativeErrorCodes.All`，把该码加入 Category MethodChannel 错误透传参数测试，并增加隔离 Store 下 max→null 的 JNI 验收。成功标准是 Flutter 收到精确的 `CATEGORY_SORT_ORDER_EXHAUSTED`，且失败请求不写入 Store；请求 `9007199254740992` 仍应作为非法输入失败。

### Category 用户归属、默认项、名称唯一性和变更生命周期尚未冻结

当前 Flutter 需求只冻结了 active list、创建和按稳定 ID 选择。分类是否按用户隔离、“默认日程”是否是不可删除系统记录、名称是否在某个作用域唯一，以及 update/delete/reorder/sync 的并发、引用和迁移规则仍未定义。不得从旧 Fake 的默认记录或 owner 文案反推领域事实，也不得临时增加 `user_id`、`is_default`、名称唯一索引或未声明 API。

当前最小语义保持不变：新 Category writer 生成 canonical lowercase UUIDv4；Event/Habit/Anniversary 的 nullable `category_id` 继续作为 opaque weak reference 读取。缺失或软删除分类不改写历史引用，聚合 Category 可以为空。既有非 UUID Event 引用不得被 reader 擅自拒绝。

### 已关闭的整改项

- Flutter 生产代码已移除 `FakeCategoryRepository` 和 `vin_star` 耦合；新建默认未分类，选择器区分取消、未分类和具体分类，编辑可显式清空引用。
- Event create/update/read/search 均传输稳定 `category_id`；C++ Event detail 已实现未分类、活动命中、悬空和软删除三态，Flutter 普通/重复详情均展示三态。
- Kotlin Event validator 已校验 `category_id`、`category_ids`、EventResponse 和 Event detail Category 投影；`NativeCategoryBridge` 默认 throwing stub 已删除。
- `sort_order` 已冻结为 `0..9007199254740991`，C++/Kotlin/Dart 的数值范围和 Flutter null-last 排序已同步；剩余问题仅是上述 Kotlin 错误码漏项。
- C++ Application/Domain 是唯一 Category 规范化负责人；Flutter/Kotlin 原样转发 Schema-valid 输入。
- Category Request、Response DTO、Domain Model、Repository 和 Storage Record 已分离；Category list/create 的 MethodChannel、Native Call、JNI 签名和三个 ABI 导出一致。

### 验证残余风险与发布门禁

- 已通过 Flutter Category/Event 定向 52 项、Flutter 全量 206 项、`flutter analyze`、Debug APK；Kotlin 定向 25 项、全量 JVM 105 项、Debug/Test APK；C++ `excellent_calendar_check` 6/6。
- RMX5100 上 Factory→JNI→C++→JSON Store 的 Category create/list、runtime 重建和新 instrumentation 进程恢复已通过，但该 smoke 绕过 Flutter 和 Kotlin MethodChannel Handler，也没有覆盖 Event 关联。
- 尚未完成同一正式 APK 的 Category 创建→列表→Event 创建→详情→编辑清空/替换→按 Category 搜索→杀进程重启→再次列表/详情/搜索。未完成前不能证明 Category 产品链路已闭合。
- 当前只验证了 runtime/进程级恢复，没有执行物理设备重启。
- 当前无公开 Category delete API，因此悬空/软删除三态只通过 C++ fixture 验证；这不是要求临时新增 delete API 的理由。
- 当前环境缺少 `jsonschema`/Ajv，已完成 JSON、Draft、唯一 `$id`、本地引用和专项 oracle，但完整 metaschema/实例校验仍需在具备依赖的正式校验环境补跑。
- Android `lintDebug` 仍因既有、范围外的 Reminder API 兼容问题失败；Category/Event 本轮整改文件为 0 finding。该结果不能被记录成全仓 lint 通过。
- 真机 Debug Store 保留一个 smoke Category：`JNI 分类重启🗓️`，ID `a70bbcb3-daf3-4a25-83a0-41bc1c909eee`。当前无 delete API，后续 smoke 应复用该幂等记录，避免重复污染。

### 发布处理顺序

1. C++ 先关闭可恢复回滚缺口。
2. Kotlin 同步并透传 `CATEGORY_SORT_ORDER_EXHAUSTED`。
3. 使用同一正式 APK 完成 Flutter→MethodChannel→Kotlin→JNI→C++→Storage、Event 关联和进程重启 smoke。
4. 更新 `contracts/README.md`、`docs/develop_record.md`、本问题记录和 Category 审查结果，使已关闭项与剩余门禁一致。
5. 最后在同一集成变更中把 Category 从 `implemented_unintegrated + blocked` 切为 `integrated + active`，并确保生产 Composition 与该状态同时生效。

可复用规则：实现状态和发布状态必须分开记录。`planned` 只用于没有可依赖实现的能力；已有代码但端到端或一致性门禁未通过时使用 `implemented_unintegrated + blocked`；只有全部门禁通过才使用 `integrated + active`。不得用“底层可调用”替代发布判断，也不得用放宽 Contract 的方式迁就不满足事务、类型或错误码保证的实现。
