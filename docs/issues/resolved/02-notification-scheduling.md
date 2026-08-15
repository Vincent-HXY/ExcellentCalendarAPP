# 已解决：Notification、Alarm 与调度闭环

## RES-NOT-001 投递前没有稳定 `notification_id`

- 严重程度：P1（评估）
- 产生原因：v1 在系统通知显示后才由 C++ 创建 Notification，点击 PendingIntent 却必须在显示前取得 ID，形成顺序矛盾。
- 解决方式：v2 使用 `prepare_delivery → NotificationManager.notify → finalize_delivery` 两阶段流程，由 C++ 提前返回真实 `notification_id`、`delivery_id`、`delivery_attempt_id` 和冻结 tap payload；真机 sent 记录已验证三类 ID 完整存在。
- 可吸取的教训：涉及外部副作用时，应先持久化/冻结身份，再执行副作用，最后幂等确认结果。
- 来源：`problems.md`“缺少投递前生成的稳定 notification_id”。

## RES-NOT-002 投递流程缺少幂等键

- 严重程度：P1（评估）
- 产生原因：v1 只有 `reminder_id`，无法区分同一次投递重试和新的投递，进程重启或系统重投会被误判。
- 解决方式：v2 分离 `delivery_id` 与 `delivery_attempt_id`；prepare/finalize 可重放，重复 finalize 返回既有结果，并使用 frozen attempt 参与 Recovery 裁决。
- 可吸取的教训：领域实体 ID、逻辑投递 ID和实际尝试 ID不能混用；每一层都应把它们当作不同概念。
- 来源：`problems.md`“投递流程缺少幂等键”。

## RES-ALM-001 旧 Alarm 可能消费更新后的 Reminder

- 严重程度：P1（评估）
- 产生原因：旧请求只携带 Reminder ID，缺少对调度时版本/时间的并发确认。
- 解决方式：PendingIntent/Native 请求携带 `expected_remind_at`，C++ 在事务内 CAS；不匹配返回 `REMINDER_SCHEDULE_CONFLICT` 且不写状态。Dispatcher 在投递前 reconcile 当前持久队列。
- 可吸取的教训：异步回调必须携带它所依据的版本或时间快照，并由领域层做最终 CAS。
- 来源：`problems.md`“无法防止旧 Alarm 消费更新后的 Reminder”。

## RES-NOT-003 `reminder.get` 无法生成通知标题和正文

- 严重程度：P1（评估）
- 产生原因：Reminder 不冗余保存 Event/Habit/Anniversary 标题，而 Kotlin 曾被要求自行拼装非空标题。
- 解决方式：`reminder.prepare_delivery` 由 C++ 读取目标并返回完整、冻结的展示内容与 tap payload；Kotlin 只负责系统投递，不向 Reminder Domain 塞入展示冗余字段。
- 可吸取的教训：展示快照应在拥有领域聚合信息的一侧生成，但通过 Boundary DTO 输出；不要让 Android Adapter 重新推导领域内容。
- 来源：`problems.md`“reminder.get 不足以生成实际通知内容”。

## RES-NOT-004 启动恢复来源没有进入协议

- 严重程度：P1（评估）
- 产生原因：v1 `schedule_pending` 混合 App 启动、设备重启、时间变化和手动重试，来源不可审计，也无法稳定幂等。
- 解决方式：v2 使用 `plan_recovery(recovery_request_id, trigger_source)`，冻结 `app_start`、`device_boot`、`alarm_reconcile`；Android 开机/时间变化/WorkManager/前台统一编排到 Recovery 与 reconcile。
- 可吸取的教训：恢复不是普通查询；必须携带稳定请求 ID 和有限枚举来源，才能审计与幂等重放。
- 来源：`problems.md`“启动恢复来源没有进入协议”。

## RES-NOT-005 重复 Reminder 未进入消费闭环

- 严重程度：P1（评估）
- 产生原因：v1 固定物理消费一次性 Reminder，无法保留历史并滚动到下一 occurrence。
- 解决方式：v2 finalize workflow 在同一 C++ 事务中保留当前历史、创建或复用确定性 successor，并通过 Recovery 处理过期和 prepared attempt；跨端已接入，真机已完成部分投递/Recovery 验证。
- 可吸取的教训：重复提醒的“本次投递历史”和“下一次待执行任务”必须分离并原子推进。
- 来源：`problems.md`“重复提醒尚未进入消费闭环”。异常恢复验证仍在 `open.md`。

## RES-NOT-006 `notification_id` 生成时机冲突

- 严重程度：P1（评估）
- 产生原因：Android 构造 PendingIntent 的时间早于 v1 C++ 创建 Notification 记录的时间，导致只能临时拿 Reminder ID 冒充。
- 解决方式：两阶段投递提前生成三类身份，并把 PreparedNotificationPayload 原样放入 PendingIntent；系统投递失败时 finalize 为 failed，不再误记 sent。
- 可吸取的教训：这是协议时序问题，不能用命名替换或临时 ID 掩盖；需要重排事务与副作用顺序。
- 来源：`problems.md`第三章整体问题；与 RES-NOT-001 同根但保留独立来源记录。

## RES-ALM-002 部分 Reminder 可能永远没有注册 Android Alarm

- 严重程度：P1（源文档）
- 产生原因：旧实现只扫描未来 7 天和最多 128 条，忽略 `has_more`，也没有周期推进窗口。
- 解决方式：改为持久 Reminder 队列驱动的单 Dispatcher Alarm；C++ 使用无界 keyset cursor，Boot/前台/Alarm/WorkManager 统一进入 `ReminderScheduleCoordinator`。
- 可吸取的教训：操作系统 Alarm 应是可重建的派生索引，长期权威状态必须在 Core/Storage；窗口扫描必须有推进和看门狗。
- 来源：`[P1] 部分提醒可能永远没有注册 Android Alarm`。

## RES-ALM-003 过期 Alarm 会先展示错误通知

- 严重程度：P1（源文档）
- 产生原因：旧服务先用 Alarm 中的 plannedAt 弹通知，之后才让 C++ 判断 Reminder 是否仍匹配。
- 解决方式：Dispatcher 到点后先 reconcile 持久状态；`expected_remind_at` CAS 和 prepare_delivery 在显示前拒绝过期任务。修改提醒后重新触发 reconcile。
- 可吸取的教训：任何用户可见副作用都必须发生在最新领域状态校验之后。
- 来源：`[P1] 过期 Alarm 会先显示错误通知，再由 C++ 拒绝`。

## RES-EVT-002 完成 Event 不处理未触发 Reminder

- 严重程度：P1（源文档）
- 产生原因：早期 Event 完成只修改 Event 状态，没有跨实体 workflow 管理 Reminder 生命周期。
- 解决方式：`EventLifecycleWorkflowService` 在完成时取消 open Reminder，在重新打开时恢复仍合法的未来 Reminder，并保持事务与取消原因语义。
- 可吸取的教训：跨实体不变量应由 Application Workflow 统一编排，不能分散在 UI 或单实体 Service。
- 来源：`[P1] 完成日程不会处理尚未触发的提醒`。

## RES-ALM-004 Event 创建成功会掩盖调度失败

- 严重程度：P2（源文档，最终按非缺陷关闭）
- 产生原因：最初把“领域创建成功”和“Android 派生调度成功”错误地期望为同一事务结果。
- 解决方式：明确 Event 持久化成功不因 Android 调度失败回滚；通过持久队列、Dispatcher、reconcile、重试与 WorkManager 看门狗保证最终恢复。
- 可吸取的教训：不可把外部系统副作用纳入本地领域提交事务；正确做法是提交后可观测、可重试、可重建。
- 来源：`[P2] 创建日程成功会掩盖提醒调度失败`。

## RES-NOT-007 `notification_id` 实际保存为 Reminder ID

- 严重程度：P2（源文档）
- 产生原因：v1 为解决点击时序临时把 Reminder ID 同时当作通知记录 ID和去重键，破坏实体身份分离。
- 解决方式：正式 v2 路径从 C++ prepared payload 使用真实 `notification_id`，并独立携带 `delivery_id` / `reminder_id`；Android 系统通知以 delivery tag 标识。旧 `post` 兼容路径不再是正式 v2 投递链。
- 可吸取的教训：临时兼容路径必须明确退出生产主链，不能让同一字符串承担多个实体身份。
- 来源：`[P2] notification_id 实际保存的是 Reminder ID`。

## RES-NOT-008 不同提醒可能因 Android 整数 ID 碰撞互相覆盖

- 严重程度：P2（源文档）
- 产生原因：旧实现只用 Java 字符串哈希作为 Notification ID，哈希碰撞会覆盖通知。
- 解决方式：Android 使用唯一 `reminder:<id>` / `delivery:<id>` tag 加固定整数 ID；NotificationManager 以 tag+id 共同标识，PendingIntent 同时使用唯一 data URI。
- 可吸取的教训：不可把有限位哈希当作全局唯一身份；系统 API 支持复合 identity 时应使用稳定原始 ID 构造 tag。
- 来源：`[P2] 不同提醒可能覆盖彼此的系统通知`。

## RES-NOT-009 Notification 初始化失败后仍继续注册 Reminder

- 严重程度：P2（源文档）
- 产生原因：源问题基于已过期实现，认为 degraded 后没有短路初始化流程。
- 解决方式：当前 `notification.initialize` 失败会立即 return，不再检查权限或 reconcile；回归测试断言调用次数为 0，职责拆分后仍保持。
- 可吸取的教训：问题关闭前必须复核当前代码，避免为过期描述制造无效修改；启动先决条件需要负例测试。
- 来源：`[P2] Notification 初始化失败后仍继续注册提醒`。

## RES-NOT-010 本地 Notification 主链尚未正式接入

- 严重程度：P1（评估）
- 产生原因：早期只有 UI/Fake 与独立 Core 能力，没有真实 Android Alarm/Notification 消费链。
- 解决方式：已接入通知 Channel、权限、Dispatcher Alarm、reconcile、两阶段 popup 投递、Recovery 和点击 EventChannel，并完成首轮真机 sent 记录验证。
- 可吸取的教训：功能“存在”应以真实跨层闭环为准，而不是某一层有接口或 Fake 页面可操作。
- 来源：`problems.md`“其他基础功能”第二项中的“通知尚未正式接入”；通知操作按钮仍在 `open.md`。
