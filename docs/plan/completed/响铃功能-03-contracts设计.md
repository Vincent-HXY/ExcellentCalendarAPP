# 计划 1：Contracts 层
负责范围：contracts/**、相关docs\domains\领域文档。
该计划完成前，其他层只能使用草案和 Fake 开发。
## 执行任务
1. 冻结领域规则：
   - 仅普通、非全天、非重复 Event 支持 ring。
   - popup 与 ring 互斥。
   - ring 的 sent 必须表示：控制通知已经展示，并且声音或振动至少一种真正启动。
   - stop 只关闭 Android 会话，不完成 Event、不保存关闭历史。
   - snooze 固定 10 分钟，由 C++ Clock 计算。
   - 恰好迟到 5 分钟仍允许响铃，超过 5 分钟进入摘要。
2. 修改 Reminder、Notification、Recovery Schema：
   - 普通 Reminder 成功态仅 [popup] 或 [ring]。
   - 重复 Reminder 保持 [popup]。
   - list_schedulable.supported_methods 支持 popup/ring。
   - prepare_delivery 的普通 Reminder 支持 ring；Recovery summary 保持 popup。
   - 冻结新的 Recovery 计数不变量。
3. 新增 Ring Contract：
   - RingSettings
   - RingCapabilitySnapshot
   - ActiveRingSession
   - ActiveRingItem
   - RingStateSnapshot
   - RingStateChangedEvent
   ActiveRingItem 不携带 Event 标题、正文或 Reminder message；Flutter 解锁后通过现有 Event Gateway 获取详情。铃声原始 URI 只保存在 Kotlin，本层仅向 Flutter 暴露显示名称和可用状态。
4. 冻结公共方法：
   ring.get_state
   ring.pick_ringtone
   ring.update_settings
   ring.test                 // action=start|stop
   ring.stop_active
   ring.snooze_active
   ring.complete_item
   ring.state_changed
   扩展现有 notification.open_settings，增加：
   ring_channel
   full_screen_intent
   Kotlin→C++ 内部调用新增：
   reminder.snooze
5. 冻结幂等身份：
   snoozed_reminder_id =
   UUIDv5(reminder namespace, [source_delivery_id, "snooze", 10])
6. 补齐稳定错误码、Golden JSON、UUID 向量、正反例 fixture 和兼容性矩阵。
## 完成标准
- Schema 引用闭合，字段、nullable、枚举、错误码全部冻结。
- 4:59、5:00、5:01 Recovery fixture 齐全。
- Ring DTO 不包含锁屏敏感内容。
- snooze 重放始终生成同一个 Reminder。
- 架构师批准 Contract revision 后，其余三层正式开工。