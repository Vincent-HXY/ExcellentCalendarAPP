# 已解决：Contract、Event 与 Reminder

> 整理时间：2026-08-14。未在源文档标注优先级的条目，其级别为本次按影响范围做的整理评估。

## RES-CTR-001 内部按 ID 查询 Reminder 的 Contract 缺口

- 严重程度：P1（评估）
- 产生原因：早期只有列表查询，Android 调度只能在有限批次内扫描；`reminder.get` 一度只存在于 design-only v2，运行时与协议状态不同步。
- 解决方式：Native Contract v2 激活后，`reminder.get(reminder_id)` 作为 Kotlin→C++ 内部调用进入 `native_calls.yaml`，C++ Boundary/Service、Kotlin Bridge 和回归测试均已接入；它不错误暴露给 Flutter。
- 可吸取的教训：内部调度查询和公开 UI API 应分开设计；按稳定 ID 的关键路径不能用分页列表模拟。
- 来源：`problems.md`“Contract 缺口”。

## RES-CTR-002 Native Contract v2 已定稿但运行时仍是 v1

- 严重程度：P0（源文档）
- 产生原因：重复 Event、滚动 Reminder、两阶段 Notification、Recovery 和 Storage 必须跨 Dart/Kotlin/JNI/C++ 原子切换，任何局部提前上线都会造成混读。
- 解决方式：2026-08-08 将 MethodChannel、Native Call、identity、Storage、Dart、Kotlin、JNI、C++ 和 Android 调度统一切换为 `integrated + active`；按用户决策清理 v1 数据，不做混读或伪迁移；首轮物理设备 smoke 通过。
- 可吸取的教训：破坏性协议升级必须设置统一激活门禁，并把“代码已实现”和“发布可依赖”分开记录；不能长期保留半切换状态。
- 来源：`[P0] Native Contract v2 已定稿但运行时代码仍是 v1`。剩余验证与数据兼容风险见 `open.md`。

## RES-REM-001 重复 Reminder v2 的五个冻结语义缺口

- 严重程度：P1（评估）
- 产生原因：早期 Contract 只描述主流程，未冻结旧 Alarm CAS、occurrence reopen、窗口淘汰、prepared attempt 的 Recovery 裁决和发布状态语义。
- 解决方式：增加 `expected_remind_at` CAS、`occurrence_reopened`、确定性 successor、`expired`、72 小时 Recovery、adopt/abandon attempt 以及实现/发布状态分离；相关 C++ workflow、Storage transaction、Boundary JSON 和回归测试已完成并随 v2 激活。
- 可吸取的教训：异步提醒协议必须先枚举并发、重放、过期和恢复分支，不能只设计成功主流程。
- 来源：`problems.md`“重复 Reminder v2 的五个冻结语义缺口”。

## RES-REM-002 adopted attempt finalize 被 Kotlin 误判失败

- 严重程度：P1（评估）
- 产生原因：Kotlin validator 只看 `recovery_batch_id`，遗漏 frozen attempt 通过 `resolved_by_recovery_batch_id` 归属 Recovery 的语义。
- 解决方式：Contract 与 Kotlin 统一以两个字段任一非空判定 Recovery 归属，并补充 adopted attempt 和非法组合回归。
- 可吸取的教训：跨层 validator 必须复用同一状态不变量；C++ 已提交成功后，上层校验失败会制造最危险的分裂状态。
- 来源：`problems.md`“adopted attempt finalize 被 Kotlin 误判失败”。

## RES-REM-003 `expired` 在 Reminder Contract 内部不一致

- 严重程度：P2（评估）
- 产生原因：Domain/Response 已支持 `expired`，列表 Request Schema 和 Kotlin 枚举集合仍停留在旧状态集。
- 解决方式：Schema 增加 `expired`；Kotlin 改为复用统一 `ReminderStatus`，并覆盖合法/未知状态测试。
- 可吸取的教训：新增枚举值必须检查请求、响应、所有语言 validator、查询过滤和测试，不能只修改领域模型。
- 来源：`problems.md`“`expired` 在 Reminder Contract 内部不一致”。

## RES-EVT-001 Event 创建链路不接收 reminders

- 严重程度：P1（评估）
- 产生原因：提醒模块未完成时，C++ CreateEvent Request 没有 reminders，Boundary 甚至把该字段视为未实现；Flutter/Kotlin 因一直传空数组而掩盖了断链。
- 解决方式：Event 创建/更新的 Reminder draft 已进入 Contract、Boundary 和 C++ workflow；Event 与 Reminder 使用事务写入并在失败时回滚，重复 Event 也使用独立 v2 draft 语义。
- 可吸取的教训：空数组默认值会掩盖跨层能力缺失；验收必须包含至少一个真实子实体，而不能只测空集合。
- 来源：`problems.md`“创建EVENT CPP部分存在问题”。

## RES-REM-004 创建 Reminder 时 `is_enabled` 上下层不一致

- 严重程度：P1（评估）
- 产生原因：Flutter/Kotlin 曾允许创建 `is_enabled=false`，而 C++ 只接受启用的新 pending Reminder，造成各层对创建语义理解不同。
- 解决方式：CreateReminder/ReminderDraft Contract 将 `is_enabled` 固定为 `true`，C++ 防御性校验同一规则；禁用必须通过独立 update/disable 能力完成，并有状态回归测试。
- 可吸取的教训：创建初态属于领域不变量，应在 Schema 和 Core 双重校验；不要用可选布尔值暗示不存在的状态机分支。
- 来源：`problems.md`“创建提醒的时候的上下层不统一”。

## RES-CTR-003 内部 Reminder 调度函数未声明 Contract

- 严重程度：P1（评估）
- 产生原因：早期 `markReminderScheduled` / `markReminderFailed` 被当作实现细节，绕过了跨层协议真相源。
- 解决方式：v2 在 `native_calls.yaml` 和严格 Schema 中声明调度确认、投递 prepare/finalize 与 Recovery；内部 Kotlin→C++ 能力保持不暴露给 Flutter，但仍遵循 NativeResult、错误码和版本校验。
- 可吸取的教训：是否公开给 Flutter不决定它是否需要 Contract；只要跨语言，就必须先声明协议。
- 来源：`problems.md`“目前协议存在漏洞”。

## RES-REM-005 查询 Reminder 需要扫描全部列表

- 严重程度：P1（评估）
- 产生原因：早期缺少按 ID 的内部入口，只能遍历 Reminder 列表，既低效又会受分页上限影响。
- 解决方式：实现并激活 `reminder.get` 的 C++ Service/Boundary、JNI/Kotlin Bridge 和测试；调度链按稳定 ID 查询。
- 可吸取的教训：调度、消费和恢复使用的实体定位必须是确定性点查，不能依赖展示型列表。
- 来源：`problems.md`“查询提醒的方式存在问题”。

## RES-REM-006 允许创建过去时间的 Reminder

- 严重程度：P1（评估）
- 产生原因：早期只验证 UTC 格式，没有把 `remind_at > now` 作为领域入口不变量。
- 解决方式：C++ Reminder Service 解析并比较当前时刻，等于或早于 now 均返回稳定时间错误；覆盖等于当前时刻失败和未来一秒成功的边界测试。
- 可吸取的教训：格式合法不等于业务合法；时间约束必须在 Core 用可注入时钟测试，而不能只靠 UI 校验。
- 来源：`problems.md`“允许创建过去时间的提醒”。
