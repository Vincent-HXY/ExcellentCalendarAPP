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