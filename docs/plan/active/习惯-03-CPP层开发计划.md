# 习惯-03：Habit V1 C++ Core、SQLite v5 与 Reminder Workflow 开发计划

Status: Active / Layer Complete / Integrated / Awaiting Final Release Gate

建立日期：2026-08-28

状态同步：2026-08-31

上游：

- `docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`
- `docs/plan/completed/习惯-02-Contracts层开发计划.md`

同批分层计划（已集成）：

- `docs/plan/active/习惯-04-Kotlin层开发计划.md`
- `docs/plan/active/习惯-05-Flutter层开发计划.md`

当前收口：C++ Core、SQLite v5、Boundary 与真实 JNI 已完成集成，`excellent_calendar_check` 构建后测试 10/10 通过。本计划暂留 active，仅等待主计划的真机系统行为矩阵与 Storage/capability 状态校准完成后统一归档。

## 1. 目标、权限与非目标

本计划在 `cpp_core/**` 内实现 Habit 的领域、Application、Repository、SQLite v5、Reminder/Notification workflow、Boundary API 和测试。C++ 是生命周期、日期、统计、fixed-point、identity、事务、文案和幂等规则的唯一 owner。

并行开发阶段，本轨只依赖已冻结的 Contract，不依赖 Kotlin 或 Flutter 代码即可独立开发、构建和验收。Kotlin/Flutter 当时使用各自的 Contract Fake；C++ 未为这些 Fake 增加临时字段、兼容分支或第二套业务语义。当前三层已完成真实集成。

不修改：`contracts/**`、`flutter_client/**`、Android API、SharedPreferences、Flutter 页面、工具链或第三方版本。发现 Contract 冲突时停止受影响实现并交回 Contract 负责人，不在 C++ 中发明兼容字段。

V1 不实现 weekly/custom/infinite、暂停、多个提醒、ring、云同步、FTS、Widget 或一天多条 entry。

## 2. 开发前基线（历史记录）

以下内容记录 2026-08-28 开工时的缺口，不再代表当前实现状态；当前状态以本文顶部状态同步和已勾选交付项为准。

- `cpp_core/habit_engine/README.md` 只有职责说明，未进入 CMake。
- Domain/Application/Repository/Boundary 均没有 Habit 类型或服务。
- Reminder 枚举认识 `habit`，但当前领域和测试仍拒绝真实 Habit target。
- Recovery 只排除 Anniversary；若不修改会把 Habit 错套入 72 小时/20 条/摘要。
- SQLite v4 有 10 个 modern Store、严格 canonical checker、单连接 `BEGIN IMMEDIATE` transaction、generation 与成熟迁移测试；尚无 v4→v5 入口。
- 可复用 LocalDate、TZDB、UUIDv4/v5、Clock、`Result<T>`、Reminder 两阶段投递、RuntimeStorageLease 和 SQLite adapter 模式。

## 3. 开工门禁

- [x] Habit/Appearance Wire Contract 通过 validator。
- [x] Reminder/Notification 独立 Habit branch 与普通 Recovery 隔离冻结。
- [x] occurrence/reminder/action identity 和测试向量冻结。
- [x] SQLite v5 四表、八索引、per-store codec 与迁移规则冻结。
- [x] integer-hundredths wire、相邻上界向量与统计溢出错误冻结。
- [x] 400 天/文本/分页上限、today progress、生命周期矩阵与 reconciliation 正进展冻结。
- [x] 开工前确认 `git status`，保护用户和其他层的并行修改。

任何 Contract validator 失败时，本计划立即退回 blocked。

### 3.1 独立运行与测试替身策略

- 三条实现轨必须从同一冻结 Contract 基线提交开始，在独立分支或 worktree 中开发；本轨不得合入 Kotlin/Flutter 的中间提交。
- Boundary 正反例直接消费或逐项映射 `contracts/fixtures/habit/`，输出可供最终集成复用的 request/response golden evidence。
- `Clock`、UUID generator、Repository、平台调度 effect port 可在测试中使用 deterministic fake/in-memory/failing 实现；Fake 只能替代外部依赖，不能绕过 Domain/Application 校验。
- Storage 验收必须使用真实 SQLite v5 fresh/migration/failure-recovery 路径；内存 Repository 通过不能替代 SQLite v5 门禁。
- 不在 runtime composition 中加入“假 JNI”“假成功”或演示数据开关。C++ 的独立可运行入口是 build-after-test 与 Boundary fixture harness，而不是伪造 Android 行为。

## 4. C1：Domain、Codec 与 SQLite v5

建议新增：

- `domain/habit.*`
- `domain/habit_recurrence.*`
- `domain/habit_check_in.*`
- `domain/habit_reminder_template.*`
- `repository/habit_transaction.hpp`
- `storage/json/habit_json_codec.*`
- `storage/json/habit_state_validator.*`
- `tests/storage_v5_tests.cpp`

任务：

- [x] 定义百分位整数值对象；Boundary 只接受 `_hundredths` JSON integer，严格拒绝 decimal JSON number、非整数与越界输入。
- [x] 对 `9_007_199_254_740_990/991` 做 Request→DTO→Domain→Response 相邻值 round-trip，证明两值不合并。
- [x] 实现四个实体、闭区间日期、UTC 审计时间、软删除和跨实体验证。
- [x] 持久化 `first_check_in_at` 或 Contract 等价事实，使 clear 后目标/开始日仍锁定。
- [x] 保留完整 v4 checker；已有 v4 必须先全量验证，任何失败零写入。
- [x] 按 v5 Contract 创建四表、八索引、四个 generation、per-store codec metadata 和 migration history；日级 sent 唯一索引必须参与 canonical checker。
- [x] fresh、v1/v2/v3 经 v4 importer、已有 v4 三类入口最终得到合法 v5。
- [x] v4→v5 使用单个 SQLite transaction；不重建旧表、不改写旧 payload、position、generation、history 或 compat row。
- [x] v5 checker 校验 inherited/new canonical SQL、metadata、history、row codec、relationship 和 quick_check。
- [x] C++ runtime 初始化返回 Storage version 5；旧 v4 runtime 对 v5 严格拒写。

验收：

- fresh v5 四个 Habit Store 为空且 generation 为 0；
- populated v4 的所有旧数据逐字节/逐值保留；
- kill/失败点重启只出现完整 v4 或完整 v5；
- 重复初始化不追加第二条 migration；
- 同名错误表/索引、未知版本、混合 metadata/history 和损坏关系均 fail closed。

## 5. C2：Habit、CheckIn、DailyStatus 与 Statistics

建议新增 Application service：

- Habit command workflow；
- Habit query/projection service；
- CheckIn workflow；
- Statistics service；
- `tests/habit_core_tests.cpp`。

任务：

- [x] 实现 create/update/list/detail/end/delete 的窄 use case。
- [x] 执行 title/description/unit/note 的 Unicode code-point 上限与 400 天闭区间上限；不得按 UTF-8 byte 或 UTF-16 code unit 误判。
- [x] create 原子创建 Habit + exclusive recurrence；update 使用 `expected_updated_at` 乐观并发。
- [x] CheckIn 以 `(habit_id, check_date)` set/upsert；clear 幂等 tombstone；recreate 复活同一 ID/created_at。
- [x] 二元、数量型 partial/done、skipped、补签、未来/范围拒绝和数量快照严格实现。
- [x] 第一次 CheckIn 后永久锁定 target/unit/start date；end date 修改遵守今天和最晚历史日期。
- [x] 提前结束不可恢复；自然到期只查询派生；软删除保留审计。
- [x] 严格执行 lifecycle operation matrix：upcoming end、最终日 end、completed/ended mutation 返回冻结错误，自然完成不得延长 end date 重开。
- [x] 动态投影 upcoming/absent/missed，不写空 CheckIn。
- [x] DailyStatus 只投影 `deleted_at=null` CheckIn；detail 的 has-ever/latest 与空/非空 history bounds 双向一致。
- [x] 计算 7/30/all completion、quantity progress、current/longest streak、累计和 half-up 两位日均。
- [x] checked accumulation 超界返回 `HABIT_STATISTICS_OVERFLOW`，不得 clamp/wrap。
- [x] list/detail 返回 Contract 已定义的组合投影和稳定顺序；list 在同一一致性读中计算不受分页/筛选影响的全局 `today_progress`，Category 继续弱引用。

核心测试：

- 首尾包含、跨月末/闰年/未来开始和提前结束进度；
- binary/quantitative/超额/0 路由 clear；
- done-skipped-done streak 为 2，过去 partial 打断，今天 absent/partial 不提前打断；
- clear 后复活同 ID 且目标仍锁定；
- Repository failure、并发 token 冲突和幂等 replay 零半状态。

## 6. C3：Habit Reminder、Reconciliation 与 Notification Action

建议新增：

- Habit Reminder projection/workflow；
- Habit reconciliation service；
- Habit notification action workflow；
- `tests/habit_reminder_tests.cpp`。

同时扩展现有 Reminder/Notification domain、共享 transaction、prepare/finalize、scheduler query、Recovery 排除和 Boundary codec。

任务：

- [x] template 首次开启/关闭/重开/删除；local time 变化软删旧链并生成新 UUIDv4 key。
- [x] 以 `(habit_id, occurrence_date)` 跨 template 执行每天最多一次真实展示：无 attempt 可替换当天；sent/prepared 后新 template 从下一合法日生效。
- [x] 只由 C++ 生成 occurrence/reminder/action UUIDv5，并逐向量验证 canonical JSON。
- [x] create、done、skipped、clear、end、delete、template change 与 Reminder/Notification 在同一 SQLite transaction 联动。
- [x] partial 保留 Reminder，并由 C++ 生成剩余量正文。
- [x] prepare 返回 `habit.detail` tap route 和强类型 direct-complete action；Notification 只由真实 attempt 产生。
- [x] finalize sent 原子终结当前任务并创建首个合法 successor；重放返回原结果。
- [x] `plan_recovery` 显式跳过 Habit。
- [x] 实现最多 100 条/transaction、opaque cursor 的 `habit.reconcile_reminders`：同日逐条 catch-up，次日 expiry，无摘要；response 回显 limit，processed 精确等于四类 outcome 之和，has_more 时必须正进展。
- [x] 跨日/业务取消时原子 abandon 未展示 prepared attempt，且两个 RecoveryBatch 字段为空。
- [x] action 验证当地 today、Habit/date/occurrence/action tuple 后 set-to-done；重复 action 不重复写入。
- [x] clear 时：未 sent 恢复同一确定性 Reminder，时间已过走同日 catch-up；已 sent 不二次展示。

并发与恢复测试必须覆盖 action vs finalize、action vs clear、reconcile vs mutation、sent→改时间、prepared→改时间、pending→改时间、关闭再开启、重复扫描、权限恢复、时间/时区变化、进程重启和陈旧 cursor。

## 7. C4：Boundary、Runtime Composition 与错误元数据

建议新增：

- `boundary/contract/habit_json.*`
- `boundary/api/habit_api.hpp`
- Habit v2 endpoint/runtime service composition。

任务：

- [x] 为 `native_calls.yaml` 的 11 个 call 提供唯一、窄、可测试 endpoint。
- [x] 严格解析 exact keys、snake_case、date、UTC、nullable、enum、timezone、integer-hundredths、文本和 cursor/page 上限。
- [x] 公开 manual request 与内部 CheckIn command 严格分离；C++ 只接受 Kotlin 规范化的 source/action 字段，不接收客户端生成的 Habit/recurrence/template/action identity，通知 action 只接受冻结 tuple。
- [x] response 只返回 DTO/projection，不泄露 Store record 或 sqlite 类型；数量 DTO 必须按 Contract 显式返回 `_hundredths` integer，禁止转换为 decimal JSON number。
- [x] 同步 Core error allow-list 与 retryable metadata，删除 duplicated error。
- [x] runtime 只拥有一个 SQLite v5 connection/lease；不得复用旧 JSON live writer 或建立第二份状态。
- [x] 将新测试目标纳入 `excellent_calendar_check`。

## 8. C++ 独立交付与最终集成交接门禁

独立交付完成时必须提供给总工程集成负责人：

- 11 个可链接 C++ Boundary endpoint 及准确 request/response 示例；
- Storage version 5 初始化与迁移证据；
- prepare 中 Habit route/action payload；
- mutation commit 与 schedule reconciliation flag；
- dedicated reconciliation cursor；
- 全部错误码、identity 和 concurrency 行为测试；
- 11 个 endpoint 的符号/头文件清单、fixture 对照表和真实 JNI adapter 接入说明；Kotlin 不需要提前合入即可审核这些产物。

必须执行：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_storage_v5_tests
cmake --build cpp_core/build-ninja --target excellent_calendar_habit_tests
cmake --build cpp_core/build-ninja --target excellent_calendar_habit_reminder_tests
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

目标名以实际 CMake 落盘为准，但最终必须运行“构建后测试”的 `excellent_calendar_check`，不能只执行已有 CTest 二进制。

独立完成条件已满足：所有 C1–C4 项、Contract validator、迁移/事务/Boundary 回归和 build-after-test 通过；`cpp_core/**` 无 Android/Flutter 类型、运行时 Fake 或无关重构。C++ 层已越过 `Layer Complete / Awaiting Integration` 并接入真实 JNI。

最终集成已经验证真实 Kotlin JNI symbol、同一 APK 的 Storage 5 handshake、调度/action 主机回归和 Native smoke。当前仅因主计划真机系统行为矩阵与 Storage/capability 状态校准尚未完成而暂留 active；测试专用 fake/in-memory repository 保留用于回归，不作为需要删除的运行时假数据。
