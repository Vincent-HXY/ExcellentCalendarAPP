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

无法防止旧 Alarm 消费更新后的 Reminder
[get_reminder_request.schema.json (line 9)](A:\\calendar\\ExcellentCalendarAPP\\contracts\\reminder\\get_reminder_request.schema.json:9) 只包含 ID。如果提醒从 08:00 修改到 09:00，而旧的 08:00 Alarm 仍然触发，它可能读取并消费已经更新的 Reminder。
建议 Alarm PendingIntent 和后续请求携带 expected_remind_at 或 schedule_generation，C++ 必须验证它与当前 Reminder 一致。

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