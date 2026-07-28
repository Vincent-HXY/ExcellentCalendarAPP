- Contract 缺口
当前有 reminder.cancel，可实现取消链路。
但缺少按 id 查询单条 Reminder 的正式方法；现在只能用 reminder.list 做预检并在前 200 条内查找。建议补 reminder.get 或让 list_reminders_request 支持 id 过滤。

- ~~创建EVENT CPP部分存在问题~~
~~在create_event_request.hpp里面~~
~~没有相关的reminders字段，但是在通过flutter和，kotlin传下来的字段是有的~~
~~在event_api.cpp中如果存在了reminders这个字段，反而会报错failure(feature_not_implemented("reminders"))~~
~~这个部分应该是之前还没有弄好“提醒”这个模块时，为了避免产生错误，所以传的时候没有使用reminders~~
~~然后也是因为我们在之前的flutter层和kotlin层，因为我们还没有设计好提醒的前端页面，所有的reminders字段我们默认都是一个空数组，所以这里也没有报错~~
~~reminder可以为空，表示不需要提醒，但是还是需要接受里面的数据啊~~

- ~~创建提醒的时候的上下层不统一~~
~~reminder里面的有一个字段  "is_enabled",表示这个提醒是否是启动的。~~
~~存在的问题便是在于，我创建了一个is_enabled=false提醒，表示这个提醒不需要启动，但是他又必须存在。~~
~~在前面的flutter和kotlin验证的时候，他们是运行is_anabled=false这样的存在，但是最后放在了CPP的时候，又不允许这样的存在了~~
~~所以在create_reminder_request.schema.json这里面，严格按照要求，默认创建的时候就是true，后面再通过reaminder.update修改才可以改为false~~

- ~~目前协议存在漏洞~~
~~只要是涉及到了跨层的调用或者说数据的传输，我们就一定需要走contracts~~
~~但是我们有几个函数 `markReminderScheduled` 和 `markReminderFailed`他们是没有走method_channel里面的方法的，我们应该提前在method_channel里面约束好这两个方法需要传输的字段和规范~~

- 我们把reminder里面如果涉及到了不支持的wechat提醒方式就会直接报错，然后整个提醒的调度就会直接失败

- 查询提醒的方式存在问题
目前我们我们查询提醒的方式就是在于把所有的提醒这个表里面的数据挨个查一遍，然后看看是否有我们对应的提醒任务，因为目前我们还只是定义了这个函数，所以我们要新建一个getreminderbyid的新的接口，让上层可以根据直接查看id是否中存在来看看是否有这个提醒。

- ~~允许创建过去时间的提醒~~
~~我们的这个时间的提醒，只会验证时间是UTC格式，应该加一个验证环节，reminder > 当前时间。在reminder_service.cpp 225~~

- 现在完成日志这个选项还没有做，需要正式实现这个功能
- 现在还没有正式接入通知这个任务，需要接入这个通知，然后通知发生之后，我们可以点击完成选项完成或者日程。
- 现在点击之后，不能查看日志的一个详细情况
- 现在的日程都是默认即将到来的一个状态，我们需要设置好恰当的时间线去调整


缺少投递前生成的稳定 notification_id
[notification_tap_payload.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\notification\\notification_tap_payload.schema.json:9) 要求点击 PendingIntent 必须包含 notification_id。
但 [consume_reminder_after_delivery_request.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\consume_reminder_after_delivery_request.schema.json:9) 和 [create_notification_request.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\notification\\create_notification_request.schema.json:9) 都不接收预先生成的 notification_id。
这会产生顺序矛盾：
先弹系统通知：构造 PendingIntent 时还没有 Notification ID。
先调用 consume：数据库已经记录 sent，但系统通知可能随后展示失败。
建议增加两阶段协议：
notification.prepare_delivery
→ 返回 notification_id / delivery_attempt_id / tap_payload
→ Android NotificationManager.notify
→ reminder.finalize_delivery
finalize_delivery 根据成功或失败原子更新 Notification 和 Reminder。

投递流程缺少幂等键
Alarm Receiver 可能因为进程重启、系统重投或异常恢复重复执行。当前 consume_after_delivery 只有 reminder_id，无法准确区分同一次投递重试。
建议增加：
delivery_attempt_id
schedule_generation
expected_remind_at
同一个 delivery_attempt_id 重复提交应返回之前结果，而不是 REMINDER_ALREADY_CONSUMED 错误。

~~ 无法防止旧 Alarm 消费更新后的 Reminder
[get_reminder_request.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\get_reminder_request.schema.json:9) 只包含 ID。如果提醒从 08:00 修改到 09:00，而旧的 08:00 Alarm 仍然触发，它可能读取并消费已经更新的 Reminder。
建议 Alarm PendingIntent 和后续请求携带 expected_remind_at 或 schedule_generation，C++ 必须验证它与当前 Reminder 一致。~~



reminder.get 不足以生成实际通知内容
[reminder_response.schema.json (line 20)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\reminder_response.schema.json:20) 只有目标 ID 和提醒 message，没有 Event/Habit/Anniversary 的标题。而 consume_after_delivery 又要求 Kotlin提供非空 title。
建议增加内部聚合接口：
reminder.get_delivery_context
返回 Reminder、目标标题、通知正文、目标类型和 ID。它只是 Boundary DTO，不应把标题冗余写进 Reminder 领域模型。

通知点击只读一次并立即清除，不够可靠
[notification_tap_payload_response.schema.json (line 5)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\notification\\notification_tap_payload_response.schema.json:5) 规定读取成功后立即清除。Flutter 取到 payload 后如果在完成导航前崩溃，该点击会永久丢失。
EventChannel 也可能在 Flutter 订阅前发出事件。
建议改成持久化的小型点击队列：
notification.peek_pending_taps
notification.ack_tap
payload 增加 tap_id，Flutter 完成导航后再确认消费。

启动恢复来源没有进入协议
reminder.schedule_pending 不仅会由 App 启动触发，还应由这些 Android 场景触发：
BOOT_COMPLETED
MY_PACKAGE_REPLACED
系统时间调整
时区调整
手动重试
建议请求增加 trigger_source。同时 Kotlin 应复用同一个调度服务，不能依赖 Flutter MethodChannel 才能恢复提醒。

批量调度错误信息不足
[schedule_pending_reminders_response.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\schedule_pending_reminders_response.schema.json:9) 只有失败 ID 和数量，没有每条失败的错误码、原因及可重试状态。
建议改成：
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

精确提醒还是近似提醒尚未明确
权限 Contract 同时提供 notification permission 和 exact-alarm permission，这很好；但 Reminder 没有声明是否必须精确触发。
需要明确：
所有 Reminder 都要求 exact alarm；或者
支持 exact / inexact 调度策略，并在无精确权限时降级。
否则 schedule_pending 遇到缺少精确闹钟权限时，各平台实现可能采取不同策略。

重复提醒尚未进入消费闭环
delete_after_sent 当前固定为 true，[consume_reminder_after_delivery_request.schema.json (line 41)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\consume_reminder_after_delivery_request.schema.json:41)，所以 V1 只覆盖一次性 Reminder。
如果要支持重复日程，消费成功后还需要由 C++ 生成下一条 Reminder，或者响应中返回 next_reminder。当前流程还没有定义。


二、notification_id 的生成时机冲突
正常投递顺序是：
Alarm 到点
→ 构造 Android Notification 和点击 PendingIntent
→ NotificationManager.notify()
→ C++ consume_after_delivery
→ C++ 创建 NotificationResponse.id
问题是，Android Notification 在调用 notify() 前就必须准备好点击 payload；但真正的 NotificationResponse.id 要到之后调用 C++ 才生成。
也就是说：
需要 notification_id 的时间
早于
C++ 生成 notification_id 的时间
当前实现使用稳定的 reminder_id 作为点击 payload 的 notification_id 去重键。它能保证同一条通知重复点击不会重复导航，但它不等于 C++ 中持久化的 NotificationResponse.id。
当前影响：
Flutter 只使用 payload 打开 target_id 对应页面：没有问题。
Flutter 把 notification_id 只当作不透明去重键：没有问题。
Flutter 使用该 ID 查询 Notification 记录：会查询不到。
埋点需要把点击和 Notification 表记录严格关联：会关联失败。
将来一个 Reminder 可以重复投递多次时，只用 reminder ID 会错误地把后续投递视为重复点击。
当前 V1 是一次性提醒，且 delete_after_sent=true，所以短期风险较低。
推荐的长期解决方案
建议在 contract 中把两个概念分开：
{
  "delivery_id": "稳定的单次投递去重键",
  "notification_id": "C++ NotificationResponse.id，可为 null"
}
更完整的方案是增加原生两阶段流程：
notification.prepare_delivery
→ C++ 提前生成 notification_id / delivery_id
→ Kotlin 展示系统通知
→ reminder.consume_after_delivery 使用同一个 ID 完成持久化
这样可以同时保证：
点击 payload 使用真实 Notification ID；
重试具有幂等键；
Flutter 点击事件能关联 C++ 记录；
系统通知失败时不会被错误记录为 sent。
结论
目前可以继续开发，前提是：
V1 UI 暂时只开放 popup。
Flutter 将点击 payload 的 notification_id 只用于去重，不用于查询 C++ Notification。
在支持 ring、重复提醒或通知历史点击关联前，先完成一次独立 Contract 变更。


[P1] 通知点击后没有进入可用页面。
[notification_tap_router.dart (line 36)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/routing/notification_tap_router.dart:36) 将日程通知路由到详情页，但 [app_router.dart (line 20)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/routing/app_router.dart:20) 只是固定显示“日程不存在或已删除”，没有读取日程，也没有进入用户描述的主页面。当前闭环在最后一步实际中断。

~~ [P1] 部分提醒可能永远没有注册 Android Alarm。
[schedule_pending_reminders_use_case.dart (line 5)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/reminder/schedule_pending_reminders_use_case.dart:5) 每次只扫描未来 7 天、最多 128 条，并且不处理返回结果中的 has_more。[BootCompletedReceiver.kt (line 19)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/alarm/BootCompletedReceiver.kt:19) 同样只执行一次，没有发现周期扫描机制。因此：
7 天内超过 128 条时，后续提醒不会注册。
超过 7 天的提醒进入窗口后，如果用户没有重新打开 App、重启手机或修改日程，也不会注册。~~

已修复：Android 改为由 Reminder 持久队列驱动的单 Dispatcher Alarm；C++ 调度查询支持无界 keyset cursor，Alarm/Boot/前台与 WorkManager 看门狗统一进入 `ReminderScheduleCoordinator`，不再依赖 7 天窗口或 128 条批次。

~~ [P1] 过期 Alarm 会先显示错误通知，再由 C++ 拒绝。
[ReminderDeliveryService.kt (line 51)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/ReminderDeliveryService.kt:51) 使用 Alarm 中的旧 plannedAt 直接弹通知，到第 83 行才调用 C++ 消费；而 C++ 在 [notification_service.cpp (line 236)](/A:/calendar/ExcellentCalendarAPP/cpp_core/src/application/notification_service.cpp:236) 才检查时间是否仍匹配。用户可能看到或听到本不应该触发的旧提醒。~~

这个并不是一个大问题，首先我们到点之后，不是直接触发一个通知，而是说先进入一个dispatcher，先reconcile这表里面是否有我需要存在的通知还没有提醒。所以哪怕我们修改了通知提醒时间，旧的Alarm依旧不会触发一个通知。
所以我们日后的开发时，如果涉及到了要修改一个提醒时间，我们需要在修改后的时间重新设立一个reconcile。

~~ [P1] 完成日程不会处理尚未触发的提醒。
[complete_event_use_case.dart (line 11)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/complete_event_use_case.dart:11) 只完成 Event；C++ 的 [event_service.cpp (line 326)](/A:/calendar/ExcellentCalendarAPP/cpp_core/src/application/event_service.cpp:326) 也只修改 Event 状态。关联 Reminder 仍然是 scheduled，因此用户提前完成日程后，提醒依然可能照常弹出。 ~~
已经着手修复


~~ [P2] 创建日程成功会掩盖提醒调度失败。
[create_event_use_case.dart (line 19)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/create_event_use_case.dart:19) 等待调度调用，但最终始终返回日程创建结果。无论 schedule_pending 整体失败，还是返回 failed_count > 0，上层看到的仍是创建成功。~~
这个本身不是问题，问题的出现在于我们之后是否有可靠的reconcile机制，因为我们无法保证一个提醒哪怕他已经是scheduled了，但是我们不能保证他之后一定会提醒，比如设备的重启，后台的关掉。

[P2] notification_id 实际保存的是 Reminder ID。
[NotificationDisplayService.kt (line 85)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/notification/NotificationDisplayService.kt:85) 将 notification_id 和 reminder_id 都设置为 content.reminderId。这与 DATA_MODEL 中 Notification 和 Reminder 是两个独立实体、各自具有独立 ID 的设计不一致，也使点击载荷无法追踪 C++ 创建的真实 Notification 记录。

~~[P2] 不同提醒可能覆盖彼此的系统通知。
[NotificationDisplayService.kt (line 131)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/android/notification/NotificationDisplayService.kt:131) 使用 Java 字符串哈希作为 Android Notification ID。哈希存在碰撞，例如 "Aa" 与 "BB" 会得到同一个 ID，后一条通知会覆盖前一条。~~

[P2] Notification 初始化失败后仍继续注册提醒。
[app_notification_bootstrap.dart (line 88)](/A:/calendar/ExcellentCalendarAPP/flutter_client/lib/app/bootstrap/app_notification_bootstrap.dart:88) 将状态设为 degraded 后没有终止流程，第 93 至 94 行仍检查权限并执行调度。这不符合所定义的初始化先决顺序。

~~[P3] 存在会长期误导开发的命名。
[NativeEventBridge.kt (line 11)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/native/NativeEventBridge.kt:11) 已承担 Event、Reminder、Notification 三类能力，但仍叫 NativeEventBridge。[AndroidNativeBridgeFactory.kt (line 8)](/A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/native/AndroidNativeBridgeFactory.kt:8) 的正式数据目录仍叫 test_storage_json。~~ 已通过 Native Calendar Core Bridge 拆分和 `calendar_core_storage_json` 目录迁移解决；`test_storage_json` 仅保留为旧版本升级迁移来源。

当前自动化测试没有真正验证整个三端闭环。
Flutter 和 Kotlin 测试使用 Fake Gateway/Fake Native Bridge/Fake Notification Service；C++ 测试独立运行。它们不能证明真实 MethodChannel、JNI、文件、AlarmManager、系统通知及点击 Intent 能在设备上连续工作。
