# 已解决：Habit 实现期高价值缺陷

> 复盘时间：2026-08-31。本文从 Habit Contract、C++/SQLite、Kotlin/Android、Flutter、最终白盒 Review、黑盒反馈和首次启动缺陷中，仅保留两条对后续模块具有最高迁移价值的问题。严重程度用于描述当时影响，不等于经验价值排序。

## 候选问题价值评估

| 问题类别 | 背景与根因摘要 | 指导价值 | 本次处理 |
|---|---|---|---|
| 延迟跨日后仍可能投递旧 Habit occurrence | 共享 Dispatcher 把持久 Reminder 视为仍可投递，却没有在用户可见副作用前重新验证 Habit 当地日期语义 | 极高：适用于所有异步调度、重放、恢复和跨实体工作流 | 记录为 `RES-HAB-002` |
| date-only 使用本地 `DateTime + Duration(days)` | Contract 的 civil date 在 Flutter 被降格为带时区时间点，DST 下“一天”不再恒等于 24 小时 | 极高：直接适用于 Calendar、Anniversary、Habit、统计窗口和历史分页 | 记录为 `RES-HAB-003` |
| reconciliation 达到批次预算后未持久化 continuation | 把单次处理上限误当成完整扫描，没有保存 cursor、原 trigger、冻结时区和 dispatcher identity | 高：适用于后台分页、同步和批处理；当前已由 continuation 测试和 Review 计划充分约束 | 本次不另占两条名额，作为首要候补 |
| `_hundredths` 与 decimal number、`skipped` 等跨层语义漂移 | Contract、计划、C++ 和 Flutter 在并行实现时各自沿用局部假设 | 高，但同类教训和防线已经由 `RES-HAB-001`、生命周期机器矩阵及 Contract validator 记录 | 不重复归档 |
| 列表忽略 `has_more/next_cursor`，101+ Habit 不可访问 | 页面只实现了首屏成功路径，Fake 数据规模与测试没有触发第二页 | 中高，但属于成熟的分页闭环错误，指导范围小于前两项 | 保留在测试和开发日志 |
| 完成率/时间进度映射错误、剩余数量缺失、内部 occurrence ID 外泄、默认期限错误 | 产品语义没有转化为逐字段 UI 验收，技术字段与用户字段边界不清 | 中：有产品验收价值，但不构成新的跨层不变量 | 保留在 Widget 回归和 Review 计划 |
| partial 文案暴露内部百分位且丢失用户单位 | 内部定点数表示直接泄漏到展示层，没有统一领域格式化 | 中：应避免内部 wire 表示进入文案，但影响面相对局部 | 保留在 C++ 格式化测试 |
| 首次进入 Habit 页面读取未初始化的 `late` 时区 Gateway | `initState` 中先创建 Future、后初始化依赖；重试时依赖已就绪，所以掩盖了确定性顺序错误 | 中低：用户影响明显，但属于局部初始化顺序错误，生产组合回归已能直接防止复发 | 不因表面阻断级别进入最有价值两条 |
| Review 影响描述扩大、计划与实现状态漂移 | 审阅结论未完全区分已确认事实、推断和验证债；多轨完成后文档未同步收口 | 中：属于审阅与治理质量问题，已由 Review Finding 模板和 `OPEN-HAB-002` 跟踪 | 不作为代码类 resolved issue 重复记录 |

## RES-HAB-002 调度回调未在副作用前重验目标业务合法性

- 严重程度：P1（运行时错误风险）
- 经验价值：极高；这是跨进程、跨时间、跨层异步系统中的通用正确性边界，而不是 Habit 专属补丁。
- 问题背景：Habit Reminder 表示某个当地日期的每日 occurrence。Android Alarm、WorkManager 和进程恢复可能延迟、重放或在设备时区变化后执行，因此回调携带的 `plannedAt` 只能证明“过去曾计划投递”，不能证明“现在仍允许投递”。共享 Reminder v2 已有 `expected_remind_at` CAS，但它只能发现 Reminder 自身被改期，无法判断 Habit occurrence 是否已经跨过当地午夜失效。
- 产生原因：实现把正确性寄托在较早发生的 reconciliation，并默认 Dispatcher 读取到持久 Reminder 就可以进入共享投递；Habit reconciliation 与共享 Dispatcher 之间没有形成强制先后依赖，C++ `prepare_delivery` 也缺少当前设备时区，导致最靠近系统通知副作用的领域入口无法执行目标专属终检。这是典型的检查与使用之间状态变化问题：早先检查正确，不代表稍后执行仍正确。
- 触发条件：Alarm 延迟到 occurrence 次日才触发；应用或设备重启后恢复旧任务；系统杀进程后重放；Habit reconciliation 尚未完成便继续共享投递；设备日期或时区变化使“今天”发生改变。
- 首个错误边界：Android 准备展示系统通知前，没有先取得 C++ 对“该 Habit occurrence 在当前设备当地日期仍合法”的肯定裁决。若只在 Kotlin 隐藏通知，Reminder 和 prepared Notification 状态还会与真实投递结果分裂。
- 解决方式：Dispatcher 在共享提醒投递前先执行 Habit reconciliation，并在 continuation 未完成或 reconciliation 失败时暂缓/失败关闭共享投递；C++ `prepare_delivery` 接收当前设备 IANA timezone，在事务内重新计算当地今天，对跨日 Habit Reminder 标记 `expired`，同时将已 prepared 的 Notification attempt 标记 `abandoned`，然后才允许 Android 执行用户可见通知副作用。这样形成“Android 编排顺序防线 + C++ 最终领域防线”，且状态终结保持原子。
- 防复发约束：任何由 Alarm、WorkManager、Receiver、通知 action、网络重试或进程恢复触发的外部副作用，都必须把回调视为陈旧提示；在副作用前由拥有规则的领域层重新验证目标、版本、当地日期和生命周期。调度层可以提前筛选，但不能替代 Core 的最终裁决；拒绝路径必须在同一事务中终结相关持久状态。
- 后续适用：Event 被完成或改期后的旧提醒、Anniversary 跨日补发、Calendar 后台聚合刷新、通知快捷操作、同步重放及所有 future scheduled jobs。
- 关闭边界：代码缺陷、主机回归和跨层接线已经修复并独立复核；真实设备“延迟 Alarm 恰好跨午夜”、时区/系统时间变化等发布后矩阵仍由 `OPEN-HAB-001` 跟踪，不能由本条 resolved 记录冒充已验证。
- 证据：`flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/HabitReminderReconciler.kt`、`flutter_client/android/app/src/test/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/HabitReminderReconcilerTest.kt`、`cpp_core/src/application/recurring_reminder_delivery_workflow_service.cpp`、`docs/log.md` 的“Habit 最终 Review 问题返修”和“返修独立复核”。

## RES-HAB-003 将 civil date 当作 24 小时时长导致 DST 错日

- 严重程度：P1（日期边界错误）
- 经验价值：极高；ExcellentCalendarAPP 的核心业务大量使用 `date`，该错误可同时污染期限、分页、连续天数、月历网格、年度纪念日和统计窗口。
- 问题背景：Habit 的 `start_date`、`end_date`、`check_date` 和历史分页边界是用户日历上的年月日，不是 UTC instant，也不表示当地午夜后的 24 小时时段。Flutter 早期为了生成期限预设、向前翻历史页和校验连续日期，先把 date-only 字符串转成当地 `DateTime`，再使用 `Duration(days: n)` 加减。
- 产生原因：跨层 Contract 已经区分 `date` 与 `datetime`，但进入 Flutter 后丢失了这种类型差异；通用 `DateTime` API 让代码看起来简洁，却把 civil-date 运算偷偷绑定到设备时区偏移。存在夏令时的地区一天可能是 23 或 25 小时，因此“加减 24 小时”和“移动一个日历日”不是同一操作。既有测试主要在 UTC 或无 DST 环境运行，没有主动覆盖切换日、月末、闰日和夹紧语义。
- 触发条件：Europe/London、America/New_York 等 DST 切换附近；向前翻页跨过 DST 边界；期限预设跨月末、年末或闰日；连续日期检查混入本地时区偏移。
- 首个错误边界：Flutter 将 Contract `date` 解析为用于时长运算的本地 `DateTime`。从这一刻开始，后续格式化即使仍输出 `YYYY-MM-DD`，计算基础也已经错误。
- 解决方式：新增统一 `CivilDate` 值对象，只保存 year/month/day；日增减和 inclusive day count 使用 UTC-backed 的纯日期元组计算，月/年移动显式执行月底夹紧；Habit 期限、历史分页和 DailyStatus 连续性全部改用该类型，不再使用本地 `Duration(days)`。回归覆盖 DST 切换日期、闰日、月底夹紧、负向分页和 400 天边界。
- 防复发约束：Schema/Contract 中格式为 `date` 的字段进入应用层后必须保持 date-only 类型；禁止用本地 `DateTime.add/subtract(Duration(days: ...))`、毫秒差，或把 date 序列化/持久化为 UTC 午夜 instant 来代替日历日运算。`CivilDate` 可以在实现内部借用 `DateTime.utc` 作为不受设备时区影响的 Gregorian 日期计算器，但结果仍是年月日元组，不能跨入 instant API。只有在确实要调度或展示某个瞬间时，才允许结合明确 IANA timezone 和 DST gap/fold 策略把 civil date/time 解析为 instant。
- 后续适用：Calendar 月/周网格与 range cursor、Anniversary 年度 occurrence、Habit streak/history、全天 Event、搜索日期筛选、统计周期和本地同步窗口。
- 关闭边界：已确认的 Flutter Habit 日期运算路径和对应自动化回归已经修复；其他模块若仍自行使用本地 `Duration(days)`，不能因为存在共享 `CivilDate` 就自动视为安全，开发或 Review 时仍需按目标路径定向检查。
- 证据：`flutter_client/lib/native_contract/shared/civil_date.dart`、`flutter_client/test/habit_application_test.dart`、`docs/log.md` 的“Habit 最终 Review 问题返修”和“返修独立复核”。
