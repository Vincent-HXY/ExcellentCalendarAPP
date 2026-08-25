# 计划：C++ 层
负责范围：cpp_core/**，其他目录只读。
当前 C++ 仍只接受 popup，参见 [reminder_service_v2.cpp (line 81)](A:/calendar/ExcellentCalendarAPP/cpp_core/src/application/reminder_service_v2.cpp:81)。
## 执行任务
1. 修改普通 Reminder 校验：
   - 只接受单一 popup 或单一 ring。
   - 拒绝空数组、多 method、未知 method。
   - wechat 返回稳定的未支持错误。
   - 重复和全天 ring 在领域入口直接拒绝。
2. 扩展调度与投递：
   - schedulable 查询保留并返回 method。
   - prepare_delivery(method=ring) 只允许普通 Reminder。
   - 继续复用既有 delivery_id、attempt 和两阶段 finalize。
   - Kotlin 未确认真实系统副作用前不得 finalize sent。
   - Recovery summary 仍然是 popup。
3. 实现 snooze workflow：
   - 输入 source_delivery_id。
   - 校验源 attempt、Reminder、Event 仍然有效。
   - 用 C++ Clock 创建 now + 10min 的普通 ring Reminder。
   - 使用冻结的 UUIDv5，保证重试和进程恢复不重复创建。
   - 与 Reminder 保存、调度状态放入现有事务。
4. 修改 Recovery：
   - popup 延续现有 72 小时规则。
   - ring 在 [started_at-5min, started_at] 进入明细。
   - 超过 5 分钟但仍在 72 小时内进入摘要。
   - Kotlin 不得再次计算时间窗口。
   - 更新 prepared attempt 的 adopted/abandoned 处理。
5. 更新 JSON Storage 校验：
   - 普通 Notification attempt 允许 ring。
   - Recovery summary 只允许 popup。
   - 不引入 SQLite，不创建新的存储层。
## 完成标准
覆盖 ring CRUD/reload、多 method 拒绝、重复 ring 拒绝、投递幂等、snooze 重放、事务失败、4:59/5:00/5:01 和 popup 回归，并通过 excellent_calendar_check。