# ExcellentCalendarAPP 开放问题登记册

> 最近整理：2026-08-14  
> 来源：`A:\calendar\ExcellentCalendarAPP\docs\problems.md`  
> 状态依据：同文件后续关闭记录、`docs/develop_record.md`（2026-08-14）以及关键 Contract/运行时代码的只读核对。

本文只记录当前仍存在的已知工程问题、技术债、缺陷和风险。原 `problems.md` 中已经解决或已被后续实现取代的条目，已按模块迁入 `resolved/`。源文档未标注优先级的条目使用以下整理评估：P0 为数据或发布阻断，P1 为主链路/一致性高风险，P2 为局部功能或验证债，P3 为低影响维护风险。

## P1：高优先级

### OPEN-REM-001 不支持的 WeChat 提醒方式会使整个调度失败

- 类型：缺陷 / 能力降级缺失
- 现状：Reminder 中出现尚未支持的 `wechat` 方式时，当前策略会让整条提醒调度失败，而不是隔离不支持的投递方式或给出可恢复的部分成功结果。
- 触发条件：提醒 payload 包含 `wechat`，并进入当前 Android/Native 调度链。
- 影响：同一 Reminder 的已支持 popup 能力也可能无法调度，用户可能完全收不到提醒。
- 关闭条件：先冻结多投递方式的失败隔离语义和错误 Contract；实现后验证 popup 不受 WeChat 失败牵连，并覆盖重试与状态回写。
- 来源：`problems.md`“不支持的微信提醒方式会导致整个调度失败”。

### OPEN-NOT-001 点击 payload 读取后立即清除，缺少确认消费

- 类型：可靠性缺陷
- 现状：冷启动点击 payload 仍采用读取即清除；EventChannel 也可能在 Flutter 订阅前发送。Flutter 在完成导航前崩溃时，点击会永久丢失。
- 影响：用户点击通知后可能没有任何页面打开，且无法恢复该次点击。
- 关闭条件：改为持久化点击队列，使用稳定 `tap_id`，提供 peek/ack 语义，并在导航成功后确认消费；覆盖冷启动、热启动、崩溃重启和重复 ack。
- 来源：`problems.md`“通知点击只读一次并立即清除，不够可靠”；`develop_record.md` 当前风险仍确认存在。

### OPEN-NOT-002 exact / inexact Alarm 产品与降级策略未冻结

- 类型：架构决策缺口
- 现状：权限 Contract 能表达通知权限和精确闹钟权限，但 Reminder 没有声明“必须精确”还是“允许降级为近似提醒”。
- 影响：无精确闹钟权限时，各平台或 ROM 可能采取不同策略，用户无法预期提醒时效，错误与重试语义也不稳定。
- 关闭条件：冻结调度策略、权限缺失时的降级/拒绝行为、UI 提示和稳定错误码，再完成 Android 版本与 ROM 回归。
- 来源：`problems.md`“精确提醒还是近似提醒尚未明确”。

### OPEN-VAL-001 通知点击到真实详情页尚未完成真机闭环验收

- 类型：端到端验证风险
- 现状：原先固定显示“不存在或已删除”的代码缺陷已修复，Event 路由已接入真实 `EventDetailFlowPage`；但冷启动、热启动和 occurrence 路由仍未在真机完成验收。
- 影响：代码单测通过仍不能证明 PendingIntent → Activity → Flutter → 真实详情加载连续可用。
- 关闭条件：在物理设备验证冷/热启动、普通 Event、重复 occurrence、目标缺失和重复点击去重，并保存证据。
- 来源：原 `[P1] 通知点击后没有进入可用页面` 的剩余验证风险；代码修复见 resolved。

### OPEN-VAL-002 Alarm 到点真实触发尚未观察

- 类型：端到端验证风险
- 现状：Dispatcher Alarm 注册、reconcile、两阶段投递和 sent 记录已在真机局部验证，但尚未观察一次由系统在真实到点时刻唤醒并完成展示、finalize、重试和状态回写的完整过程。
- 影响：后台限制、时间漂移或系统唤醒问题可能只在真实到点时暴露。
- 关闭条件：物理设备完成至少一次正常到点、一次失败重试和状态回写核对，并记录系统 Alarm 与 Storage 证据。
- 来源：Native v2 关闭条目的“剩余未验证项”及 `develop_record.md` 当前风险。

### OPEN-VAL-003 崩溃重放、Recovery abandoned 分支和重复提醒恢复验证不足

- 类型：一致性 / 恢复验证风险
- 现状：journal、RecoveryBatch、重复 Reminder successor 已实现并有单元测试，真机也验证过部分 Recovery 接管；但进程崩溃/被杀后的 journal 重放、`abandoned_to_summary`、`abandoned_outside_window` 以及 frozen attempt 的异常恢复尚未完整覆盖。
- 影响：极端时序下可能出现重复通知、永久滞留 Reminder、错误 finalize 或恢复摘要不一致。
- 关闭条件：使用可控故障点分别覆盖 prepare、系统通知、finalize 和 journal 提交阶段的进程终止，验证重启后的幂等结果与唯一 successor。
- 来源：Native v2、重复提醒消费闭环的残余风险及 `develop_record.md`。

### OPEN-VAL-004 国产 ROM Doze / 后台限制缺少长周期验证

- 类型：兼容性风险
- 现状：realme Android 16 已完成首轮 smoke，但尚未覆盖 Doze、后台冻结、省电白名单变化、长时间不打开 App 等场景。
- 影响：提醒可能延迟或漏发，短时 smoke 无法发现。
- 关闭条件：定义长周期测试矩阵，在至少一款国产 ROM 覆盖 Doze、重启、时间/时区变化与多日滚动窗口。
- 来源：Native v2 剩余未验证项及自动化测试章节。

### OPEN-DATA-001 v2 切换不迁移、不归档 v1 数据，回滚会丢失本地数据

- 类型：已接受的数据兼容风险
- 现状：根据既定用户决策，bootstrap 识别 v1 后直接清理；Kotlin 也不再迁移 `test_storage_json`。此行为不是实现遗漏，但风险仍长期存在。
- 触发条件：带 v1 本地数据升级到 v2，或激活 v2 后回滚旧版。
- 影响：旧本地数据不可恢复；回滚旧版也无法读取 v2 数据。
- 关闭条件：若产品未来要求保留数据，必须设计、测试并发布显式迁移/备份方案；否则应在发布说明和回滚流程中持续标记为已接受风险。
- 来源：`[P0] Native Contract v2` 关闭记录中的兼容性决策。

### OPEN-DOM-001 Habit 重复语义缺少独立协议

- 类型：领域设计缺口
- 现状：Habit/HabitCheckIn 尚未形成闭环，不能套用 Event occurrence 与滚动 Reminder 语义。
- 影响：提前实现可能造成 occurrence 身份、打卡统计、提醒滚动和恢复语义漂移。
- 关闭条件：先冻结 Habit recurrence、check-in 身份、Reminder 目标与幂等规则，再实施 Contract 和各层代码。
- 来源：Native v2 剩余风险。

### OPEN-ANN-001 Anniversary Reminder 的 occurrence、幂等和调度语义未设计

- 类型：领域 / Contract 缺口
- 现状：Anniversary 基础年度规则、查询和 Storage 已完成，但 Reminder 关联尚未冻结 occurrence identity、唯一键、滚动 successor、reconciliation 与 Recovery 语义。
- 影响：不得把 Event v2 的规则静默套用到 Anniversary；当前无法安全提供纪念日提醒闭环。
- 关闭条件：完成独立 Contract 设计、跨层实现和真机调度验证。
- 来源：Anniversary 年度规则条目的残余门禁与 `develop_record.md` 当前风险。

### OPEN-ANDROID-001 全仓 Android lint 仍被既有问题阻断

- 类型：质量门禁失败 / 技术债
- 现状：最近记录为 29 个 error、20 个 warning；首个问题位于 Reminder Alarm API 兼容路径。Category/Anniversary 本轮文件为零 finding，不等于全仓 lint 通过。
- 影响：无法把 lint 作为可靠的发布门禁，且 minSdk/API 兼容缺陷可能继续潜伏。
- 关闭条件：逐项归属和整改全部 lint error，明确 warning 策略，并在 CI 中执行全仓 `lintDebug`。
- 来源：Category“验证结果与残余风险”、Anniversary minSdk 修复记录。

### OPEN-TEST-001 部分 Flutter 集成测试命令会卸载正式包并删除设备数据

- 类型：测试基础设施 / 数据破坏风险
- 现状：`flutter test integration_test` 与 `flutter drive` 曾在收尾卸载正式 application id，删除不可恢复的私有沙盒数据。当前仅形成了人工规避流程。
- 影响：在带真实数据的设备上重跑会造成数据丢失，并污染验收结论。
- 关闭条件：为设备测试使用独立 application id 和独立 Store，或加入自动保护检查；在此之前禁止对正式 Store 使用会卸载应用的命令。
- 来源：Category“验证结果与残余风险”。

## P2：中优先级

### OPEN-NOT-003 批量调度失败反馈仍不完整

- 类型：可观测性 / 错误处理债
- 现状：v1 批量 Schema 已被 v2 的逐次稳定错误替代，但上层仍缺少面向一批 reconcile 结果的逐项错误码、原因、可重试性和汇总反馈。
- 影响：部分提醒调度失败时难以定位、展示或制定精确重试策略。
- 关闭条件：冻结批次级结果模型或持久化诊断模型，保持底层稳定错误码，并覆盖混合成功/失败场景。
- 来源：`problems.md`“批量调度错误信息不足”；`develop_record.md` 仍列为正在完成。

### OPEN-NOT-004 通知缺少直接完成 Reminder / Event 的操作入口

- 类型：功能缺口
- 现状：本地 popup 通知已经接入，但“在通知上点击完成”尚未形成 Contract、Android action、领域 workflow 与幂等闭环。
- 影响：用户必须打开应用后完成事项，且未来若直接在 Android 侧改状态容易绕过 Application/Contract 边界。
- 关闭条件：冻结 action payload、鉴权/幂等/过期处理和 Event/Reminder 状态规则，再实现跨层链路。
- 来源：`problems.md`“其他基础功能”第二项；其中“通知尚未接入”部分已经解决。

### OPEN-LOG-001 完成日志尚未正式实现

- 类型：功能缺口 / 可审计性债
- 现状：完成操作已有领域状态变化，但独立完成日志、查询 Contract 和持久化模型尚未落地。
- 影响：无法可靠追踪谁在何时完成、撤销或恢复事项，也不利于统计和问题排查。
- 关闭条件：先区分领域状态、操作日志和 Notification 投递日志，再完成数据模型、Contract、Repository 与 UI。
- 来源：`problems.md`“其他基础功能”第一项。

### OPEN-LOG-002 日志详情不可查看

- 类型：功能缺口
- 现状：当前没有面向用户或开发诊断的完整日志详情入口。
- 影响：用户无法理解状态变化，工程排障也需要直接检查底层文件。
- 关闭条件：在日志模型完成后提供权限和字段受控的详情查询与页面。
- 来源：`problems.md`“其他基础功能”第三项。

### OPEN-EVT-001 Event 时间线与派生状态尚未完善

- 类型：领域/UI 技术债
- 现状：源问题指出日程默认表现为“即将到来”；当前仍缺统一的时间线规则来动态计算 upcoming、in_progress、overdue 等展示状态。
- 影响：列表和详情可能在边界时间展示错误或各自计算不同结果。
- 关闭条件：在 C++ 冻结派生状态规则和时区边界，Flutter 只消费稳定结果；覆盖全天、定时、跨日和 DST。
- 来源：`problems.md`“其他基础功能”第四项。

### OPEN-TEST-002 自动化测试仍未覆盖完整三端系统闭环

- 类型：测试债
- 现状：已有 Flutter、Kotlin、C++ 单测和多个真机 smoke，但仍没有一个可重复的自动化测试连续覆盖 MethodChannel、JNI、真实文件、AlarmManager、系统通知、点击 Intent 和真实详情页。
- 影响：层间协议、进程生命周期和 Android 系统行为的回归可能绕过现有 Fake/单层测试。
- 关闭条件：建立隔离 application id/Store 的全链测试，覆盖创建、调度、到点、投递、点击、重启和恢复。
- 来源：`problems.md`“自动化测试与端到端验证”。

### OPEN-CAT-001 Category 产品语义和变更生命周期尚未冻结

- 类型：产品/领域决策缺口
- 现状：create/list 已发布，但用户归属、系统默认项、名称唯一性、update/delete/reorder/sync 的并发、引用和迁移规则仍未定义；当前也没有公开 delete API。
- 影响：悬空/软删除三态只能用 C++ fixture 验证，后续扩展若先写代码会造成 Contract 和历史引用漂移。
- 关闭条件：产品决策完成后先更新 Data Model/Contract，再实现生命周期 API、迁移和端到端测试。
- 来源：Category“用户归属、默认项、名称唯一性和变更生命周期尚未冻结”及残余风险。

### OPEN-CAT-002 Category 原子存储尚未做真实断电或介质故障验证

- 类型：持久化可靠性验证风险
- 现状：故障注入、runtime/子进程重建和回滚回归已通过，但没有真实断电、文件系统异常或介质损坏测试。
- 影响：sidecar、replace 和 directory fsync 在真实设备文件系统上的极端行为仍有不确定性。
- 关闭条件：在隔离测试数据上设计可恢复的物理故障验证，核对旧快照权威、拒读和单次安全重试。
- 来源：Category 回滚问题关闭记录与残余风险。

### OPEN-CAT-003 Category CTest 曾出现一次无日志瞬时崩溃

- 类型：不稳定测试信号
- 现状：随后 50 次定向重跑和完整 check 均稳定通过，尚无可复现根因。
- 影响：可能是环境噪声，也可能是低概率未定义行为；当前证据不足以关闭观察。
- 关闭条件：保留重复运行和崩溃产物；若再次出现，立即固化随机种子/环境并进入专项调试。
- 来源：Category“验证结果与残余风险”。

### OPEN-TOOL-001 缺少完整 JSON Schema metaschema / 实例校验环境

- 类型：工具链债
- 现状：当前已验证 JSON 语法、Draft、唯一 `$id`、本地 `$ref` 和专项 oracle，但环境缺少 `jsonschema`/Ajv，未执行完整 metaschema 与代表性实例校验。
- 影响：复杂组合关键字或实例兼容问题可能未被当前静态脚本发现。
- 关闭条件：在固定版本依赖的正式校验环境或 CI 中加入完整 Schema 校验并记录版本。
- 来源：Category“验证结果与残余风险”。

## P3：低优先级

### OPEN-CAT-004 真机 Debug Store 留有验收数据

- 类型：测试数据污染
- 现状：设备中保留以 `CodexCategoryAcceptance-` 开头的 Category 及关联 Event，且当前无公开 delete API。
- 影响：后续 smoke 可能重复创建记录、干扰人工查看或扩大 Store。
- 关闭条件：优先复用现有记录；待 delete/lifecycle 规则完成后安全清理，或始终使用隔离测试 application id/Store。
- 来源：Category“验证结果与残余风险”。

## 维护规则

- 问题关闭时，从本文件移除并迁入对应 `resolved/*.md`，保留原 ID 或在归档中记录替代 ID。
- “代码已实现但缺真机/故障验证”仍属于开放风险，不能仅因单元测试通过而关闭。
- 新问题至少记录：根因或当前假设、触发条件、影响、严重程度、关闭条件和证据位置。
