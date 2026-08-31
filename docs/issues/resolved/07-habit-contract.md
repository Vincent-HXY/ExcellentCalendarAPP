# 已解决：Habit Contract

## RES-HAB-001 Habit 重复语义缺少独立协议

- 原 ID：`OPEN-DOM-001`
- 严重程度：P1（领域设计缺口）
- 产生原因：旧 planned Habit 只有通用 recurrence 和少量 Schema 占位，Reminder 又把 Habit 当 ordinary target；没有独立的当地日期 occurrence、CheckIn identity、同日补发或通知 action 幂等规则。
- 解决方式：2026-08-28 冻结 Habit 专属 `daily + interval=1 + follow_device`、`(habit_id, check_date)` set/upsert/tombstone、公开 manual 与内部 notification action 输入隔离、Habit Reminder target branch、occurrence/reminder/action UUIDv5、同日 reconciliation、跨日 expiry、通知 set-to-done 和 SQLite v5 target Contract。总监 review 后同日追加修正：数量 wire 改为 integer hundredths；`(habit_id, occurrence_date)` 跨 template 日级单展示；list 增加全局 today progress；冻结 400 天与文本/分页/cursor 上限、响应对称不变量、生命周期操作矩阵及 reconciliation 正进展/计数上限。专项 validator 通过 194 个 Schema、44 个 Habit fixture、4 个 Habit identity vector、12 个公开方法和 11 个 native call；既有 Anniversary/Reminder 56 个 fixture 同时回归通过。
- 关闭边界：关闭的是“协议未冻结”的设计阻塞，不是 Habit 生产闭环。C++、SQLite v5、Kotlin/JNI、Flutter 与真机仍按四份分层计划实施；相关 capability 保持 `planned + blocked`。
- 可吸取的教训：date-only 领域不能套用 Event instant/revision，也不能套用普通 Reminder 的 72 小时摘要；共享实体必须有 target-specific branch、机器可验证 identity 和明确的未实现状态。
- 证据：`docs/plan/completed/习惯-02-Contracts层开发计划.md`、`contracts/validate_habit_v1.py`、`contracts/fixtures/habit/`、`docs/architecture/decisions/ADR-Habit-02-每日挑战与Reminder-Occurrence工作流.md`。
