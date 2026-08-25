# 计划 4：纪念日 Reminder 与 Occurrence C++ Core 层

> 状态：Completed / C++ Core/Storage 并行交付已完成并接入生产链；Storage v3 与 Anniversary R1 均 active
> 上位计划：[`纪念日-02-Reminder与Occurrence开发计划.md`](./纪念日-02-Reminder与Occurrence开发计划.md)
> 前置交付：[`纪念日-03-contracts设计.md`](./纪念日-03-contracts设计.md) 的冻结提交、fixture、identity vector、Storage 版本与兼容矩阵
> 负责范围：`cpp_core/**`；`docs/log.md` 只追加记录
> 必须使用 Skill：`cpp-core-feature`
> 并行策略：使用内存 Repository、固定 Clock/ID/TZDB 与 Contract fixture 独立实现；只暴露冻结 Boundary API，不等待 Kotlin/Flutter

## 1. 任务目标

在 C++ Core 内实现 Anniversary date-only occurrence projection、Reminder template/rolling chain、生命周期 workflow、日末补发聚合、两阶段 delivery、时区重算、窄 Repository、JSON Storage 目标版本/migration/recovery 及 Boundary API。

上位计划第 2～17 节对本工作流全部适用；本文件的追踪表只标识 C++ Core/Storage 的主要责任，不构成对共同回归、风险、范围或最终验收要求的删减。

C++ 是以下规则的唯一生产实现：

- Anniversary occurrence 展开、2 月 29 日、历史窗口和周年数；
- occurrence/template/reminder/aggregate delivery identity；
- 当地日期减 advance days、DST gap/fold 与 UTC `remind_at`；
- create/update/delete/pause/resume 的跨实体一致性；
- 日末补发资格、按 occurrence 分组、covered membership 与 successor；
- Reminder/Notification/Recovery 的状态机、幂等、prepare/finalize；
- JSON transaction、migration、journal replay 与 bootstrap gate。

Flutter/Kotlin 不得补偿这些规则，因此 C++ 交付必须是完整领域能力，不能只为 Boundary 返回示例数据。

## 2. 当前实现基线

开始前按真实代码复核。当前已知基线：

- `AnniversaryWorkflowService` 只协调 Anniversary 与 AnniversaryRecurrence；`AnniversaryTransaction::AnniversaryState` 只有两个集合。
- `AnniversaryQueryService` 已有 detail/list/countdown，可复用 date-only、时区与 2 月 29 日逻辑。
- `Reminder` 枚举识别 `target_type=anniversary`，但 `is_supported_reminder_target_type` 只返回 Event。
- Reminder 当前只有 Event recurrence 的 `recurrence_revision/occurrence_key/occurrence_start_at/advance_minutes` 形状，没有 Anniversary template/date/time/fulfillment 字段。
- Notification/Recovery/prepare/finalize/rolling Reminder/JSON transaction 已存在，必须扩展而不是旁路重写。
- `JsonAnniversaryTransaction` 使用独立两 Store journal；现有 Event/Reminder workflow 共享 `reminders.json`，上位计划要求引入安全的 storage-level shared commit/recovery coordinator 或等价机制。
- Native runtime 已组装 Anniversary workflow/query 和 Reminder services；Boundary 现有六个 Anniversary v2 API。

## 3. 文件所有权与协作边界

主要修改入口预计包括：

- `cpp_core/include|src/excellent_calendar/domain/anniversary*`、`reminder*`、`notification*`、`reminder_recovery_batch*`
- `cpp_core/include|src/excellent_calendar/application/anniversary_*`
- Reminder delivery/recovery/rolling/timezone 相关 Application/Workflow
- `cpp_core/include/excellent_calendar/repository/**` 中本功能窄 port/transaction
- `cpp_core/include|src/excellent_calendar/storage/json/**`
- `cpp_core/include|src/excellent_calendar/boundary/contract/**`
- `cpp_core/include|src/excellent_calendar/boundary/api/**`
- `cpp_core/src/boundary/api/native_runtime.cpp` 及对应 header
- `cpp_core/tests/anniversary_core_tests.cpp`、`reminder_core_tests.cpp` 与必要的新测试文件
- `cpp_core/CMakeLists.txt` 或直接构建清单

禁止修改：

- `contracts/**`：发现协议缺口立即提交 change request；
- `flutter_client/**`，包括 Android JNI adapter；最终 JNI thunk 由集成/Kotlin 工作流接入；
- 完整 Calendar UI/聚合、SQLite 主存储、Backend、ring/wechat、多渠道部分成功；
- 用巨大 `CalendarCoreState` 暴露所有 Store 给 Application；
- 为通过测试添加 catch-all 默认、损坏 Store 清空或伪成功 Boundary。

## 4. 独立开发与 Test Double 规则

C++ 工作流不等待 Flutter/Kotlin。先建立或扩展测试用内存 Repository/transaction、固定 Clock、固定 ID generator、固定 timezone/TZDB fixture 和 failure hook。

Test double 必须：

- 实现与生产相同的窄 Repository port；
- 支持成功、预期版本/CAS 冲突、原子失败、重试和幂等 replay；
- 记录 logical commit 涉及的 Anniversary/Recurrence/template/Reminder/Notification/Recovery 变化；
- 不出现在 Native runtime 生产组装；
- 不跳过 Domain 校验或 identity 生成；
- 不把内存测试通过冒充 JSON migration/recovery 通过。

建议按“Domain/Application 内存门禁 → JSON adapter/migration → Boundary/runtime”顺序在本工作流内部推进。

## 5. 实施任务

### 5.1 Domain Value 与不变量

新增或扩展强类型：

- `AnniversaryOccurrence`/projection：`anniversary_id`、`occurrence_key`、`occurrence_date`、source date、years elapsed 和摘要事实；
- Anniversary Reminder template：`template_key`、advance days、local time、timezone mode、method、enabled；
- Anniversary Reminder instance/chain：occurrence date/key、template key、UTC projection、fulfillment delivery；
- aggregate delivery membership；
- Contract 冻结的 cancellation/expiration/notification kind/error enum。

强制不变量：

- occurrence 是 date-only，不设置 Event recurrence revision/start instant；
- advance days `0..365`，V1 method 只能 popup，每 Anniversary 最多 5 条活动 template，组合唯一；
- 用户意图与当前 UTC projection 分开；
- 一次性无 successor，年度每 template 同时最多一个 open successor；
- Reminder sent 可由一个真实 aggregate delivery 履约，但每条 covered Reminder 必须指向同一 `fulfillment_delivery_id`；
- Notification 是实际 attempt，不为未展示的 covered Reminder 伪造多条记录；
- title/note/category/importance 不进入 identity；日期/template/membership 按冻结规则影响 identity；
- Domain 入口重复执行 Contract 合法性之外的防御性校验。

### 5.2 Occurrence Query

扩展 `AnniversaryQueryService` 或新增窄 `AnniversaryOccurrenceQueryService`：

- 输入当地半开窗口 `[start,end)`、IANA timezone、category/importance filter、cursor/page size；
- 单次窗口最大 400 日，拒绝空/逆序/超限；
- 重复 `category_ids`/`importance`、非法枚举、malformed/expired cursor 显式失败；默认只查询活动、未删除 Anniversary；
- 一次性只返回原始 date 落窗的一次；
- 年度从 source year 起展开，不返回 source date 以前 occurrence；
- 历史窗口按当前事实返回，删除后不返回；
- 日期修改后历史投影随当前事实变化，不创建 revision；
- 复用既有 2 月 29 日落到 2 月最后一天规则；
- `years_elapsed=occurrence_year-source_year`，拒绝负数；
- `occurrence_key` 使用冻结 UUIDv5；
- 按 `(occurrence_date, anniversary_id, occurrence_key)` 稳定升序；
- cursor 可验证、稳定、无泄漏存储细节，支持 >500 项多页且不重不漏。

摘要中的 `has_active_reminders/reminder_count` 从当前 template/Reminder 事实投影，不把任务明细或 Notification 历史返回给 Calendar consumer。

### 5.3 本地时间与 Reminder 物化

实现：

```text
occurrence_date
→ local date - advance_days
→ + local_time
→ current device IANA timezone
→ DST gap/fold resolution
→ UTC remind_at
```

沿用项目既有规则：gap 前移到首个合法 Instant，fold 选较早 Instant。覆盖 00:00、09:00、23:59、跨月/跨年、advance 365、DST gap/fold 和时区改变。

创建时：

- 一次性 remind_at 已过去：不建过去任务、不补发；
- 年度 remind_at 已过去：跳到下一年度首个有意义 occurrence；
- 一次性只物化当前 occurrence；
- 年度每个 template 物化首个合法 open Reminder。

时区变化：保持 template/occurrence identity，重算所有未终结 Reminder 的 UTC `remind_at`；后续 expected value/CAS 使旧 Alarm 无法投递。

### 5.4 Anniversary 生命周期 Workflow

扩展 Create/Update/Delete，并新增或明确 Toggle/Pause/Resume：

#### Create

- 原子保存 Anniversary、必要 recurrence、template plan 和首批 Reminder；
- 默认关闭/空 plan 不生成 Reminder；
- logical commit 后只返回 `schedule_reconciliation_required`，不调用 Android。

#### Update

- 标题/note/category/importance：保留 identity 与 Reminder 时间，未来 prepare 读取最新内容；
- date：终结旧未来链，按新日期确定性物化；
- advance/local time：终结旧 template chain，创建新 chain；
- yearly→one-time：未来原始日期才保留一次性任务；过去不建；
- one-time→yearly：从首个未来 occurrence 开始；
- 日期改回原值：识别原确定性 ID 的旧终结记录并按冻结规则安全恢复/替换；
- 用 expected updated_at/revision/CAS 防止并发覆盖。

#### Pause/Resume

- pause 取消/终结未来 open Reminder，但保留 template；
- resume 从首个有意义 occurrence 重新物化；
- 不调用普通 `reminder.enable` 分散恢复。

#### Delete

- 软删除 Anniversary/必要 recurrence；
- 终结全部未来 Reminder；
- 保留 Notification 历史；
- 任何一步失败不得出现半提交。

### 5.5 补发、Recovery 与聚合 Planner

实现 Anniversary target-specific 有效窗口：

```text
[original remind_at, occurrence_date 在当前设备时区的次日 00:00)
```

要求：

- occurrence 当天仍可补发，次日 00:00 起不补发；
- 按 `(anniversary_id, occurrence_key)` 分组，不同 occurrence 分开；
- 同组所有当前合格的 overdue Reminder 形成稳定排序的 frozen membership；
- aggregate delivery identity 绑定 target、occurrence、covered IDs、popup；
- 相同 recovery/reconcile/retry 重放复用原 batch/delivery/prepared attempt；
- prepare 后新到期 Reminder 不静默加入旧 membership；
- 每条年度 template 在 sent/permanent/expired 后分别创建 successor；
- retryable failure 不创建 successor，covered Reminder 保持可重试；
- 超过日末进入 expired，保留审计并滚动年度 successor；
- prepared stale target/date/repeat/template/expected remind_at 在展示前拒绝。

必须明确与既有 72 小时 Event/Ring Recovery 的共存：延续其 5 分钟 Ring、安全上限、summary 和 prepared attempt resolution，不让 Anniversary 分支改变普通行为。分组与裁决只依据 Contract/C++，Kotlin 不二次计算。

### 5.6 Prepare / Finalize Delivery

扩展现有两阶段投递：

#### Prepare

- 重新读取 Anniversary 当前事实与 Reminder identity；
- 校验 target 活动、occurrence/template 未陈旧、expected remind_at 相等、处于有效窗口；
- normal popup 与 aggregate popup 生成/复用唯一 prepared attempt；
- 冻结 title/body/planned/prepared、tap payload 和 membership；
- 准时提前提醒表达 `距离“{title}”还有 N 天`，当天表达 `今天是“{title}”`；年度 occurrence 可附加第 N 周年，但 `years_elapsed=0` 不输出“第 0 周年”；聚合补发使用投递时当前事实，可附带原计划时间或覆盖数量；
- prepare 使用当前 Anniversary 标题等事实生成未来展示快照，已经持久化的历史 Notification 文案保持冻结；任何 title/body/tap payload 都不包含 note；
- 已 sent/冲突/过期/stale 使用稳定错误，不返回空成功。

#### Finalize sent

在同一 Repository logical commit 中：

- 一个真实 aggregate Notification → sent；
- 所有 covered Reminder → sent；
- covered Reminder 写相同 fulfillment delivery；
- 每条年度 template 创建自己的 successor；
- RecoveryBatch/membership 更新完成。

#### Finalize failure

- retryable：attempt failed/retryable，Reminder 保持可重试，不建 successor；
- permanent：attempt permanent，covered Reminder 进入失败终态，每条年度 template 建 successor；
- 相同 finalize 幂等，冲突 finalize 明确失败；
- 不生成多条伪 Notification attempt。

### 5.7 窄 Repository 与事务

定义或拆分 `AnniversaryReminderWorkflowRepository` 等窄 port，覆盖上位计划 §7.2 的业务意图。Application 不能感知 JSON 文件、journal、SQLite 或 Android Alarm。

Repository 必须提供一致性边界：

- create/update/delete/pause/resume 的 Anniversary/Recurrence/template/Reminder；
- occurrence query 的只读 snapshot；
- prepare/finalize 的 Reminder/Notification/Recovery；
- recovery planner 与 timezone recalculation；
- expected updated_at/identity/CAS；
- logical commit 后 reconciliation flag。

不要把 `AnniversaryState` 直接扩展成包含全 Calendar 所有实体的万能 mutable state；允许按业务意图组合更窄 repository/transaction。

### 5.8 JSON Storage 目标版本与 Migration

严格依据 Contracts 阶段冻结的 Storage 版本实施，不自行改变版本决定。

若目标为 v3，至少完成：

- Anniversary/template、Reminder、Notification、RecoveryBatch codec 的严格新字段；
- `v2 -> v3` 连续 migration；
- 现有 Event/Reminder/Ring/Notification/Anniversary/软删除/审计字段无损保留；
- 现有 Anniversary 模板为空、提醒默认关闭；
- 旧 fulfillment/covered 字段按 Contract 缺失规则处理；
- migration 写前验证、原子替换、幂等/重复运行保护；
- 损坏/无法解释记录显式失败，不清空用户数据；
- 失败恢复与回滚/不安全降级说明；
- 正式目录保持 `files/local_storage/calendar_core_storage_json`。

实现 storage-level shared commit/recovery coordinator 或等价安全机制：

- 所有写 `reminders.json` 的 workflow 共用目录锁和恢复门禁；
- prepared commit 未恢复前禁止另一个 writer 基于旧 after-image 提交；
- coordinator 只协调本次触及 Store，不向 Domain 暴露巨大 state；
- bootstrap 在任何 Query/Scheduler/JNI 能力开放前恢复 migration 与全部 prepared commit；
- failure hooks 覆盖 prepare 后、每个 Store 写后、commit 后、cleanup 前；
- replay 确定、幂等，不重新生成 Reminder/Notification ID。

SQLite 仅保持未来 port/字段兼容，不在本计划实现数据库主存储。

### 5.9 Boundary、Native Runtime 与 Contract Mapping

扩展：

- create/update/detail 的 reminder plan/result decoder/encoder；
- `list_anniversary_occurrences_v2` 或冻结名称的 Boundary API；
- Reminder/Notification/Recovery Anniversary 分支 mapping；
- Native runtime 的 workflow/repository/storage dependency；
- 所有 failure 的合法 `NativeResult<T>`、contract version 和稳定 error code。

Boundary 必须严格拒绝缺失字段、未知字段/enum、非法 local date/time/cursor/version 和跨 target 字段混用。C++ Domain Model/Storage Record 不直接暴露为 response。

C++ 交付应提供 Kotlin 集成所需的 public header、函数签名和 fixture，但不修改 Android `event_jni.cpp`。最终集成人只添加薄 JNI thunk，不得在 thunk 中加入业务逻辑。

## 6. 测试矩阵

### Domain/Application

- 一次性/年度；1/5 条、6 条、重复 template；
- advance 0/1/7/365 与非法值；00:00/09:00/23:59；
- DST gap/fold、跨日/月/年、时区变化；
- 2 月 29 日闰/非闰；
- create 已过期的一次性/年度分支；
- 编辑所有字段组合、pause/resume/delete、并发 expected version；
- 日期改回原值与确定性 ID；
- occurrence 历史/source year/400 日/cursor/排序/多页；
- stale Alarm、重复 recovery/reconcile/prepare/finalize。

### Aggregation/Delivery

- 提前提醒日、纪念日前一天、当天、次日 00:00 边界；
- 同 occurrence 多 Reminder 合并、不同 occurrence 分开；
- membership stable sort/freeze/conflict；
- 一个 Notification、所有 covered sent、shared fulfillment、各自 successor；
- retryable/permanent/expired；
- crash/replay 不重复 ID 或 delivery。

### Storage/Migration

- 所有冻结 v2 fixture 到目标版本；
- 重复 migration、失败恢复、损坏拒绝；
- 每个 Store 写边界 failure hook；
- Anniversary commit 后、Scheduler 前退出；
- foreign prepared workflow 阻止 stale `reminders.json` writer；
- Event/Reminder/Ring/Recovery/Notification/tombstone 回归。

### Boundary/Runtime

- 所有 Contract valid/invalid fixture；
- NativeResult invariant、unknown/null/missing/version；
- runtime bootstrap migration/journal gate；
- public header/API 与冻结 `native_calls.yaml` 对齐。

必须使用构建后测试目标：

```text
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不得只运行可能陈旧的 CTest 二进制。还应运行本次测试的定向目标和适用 sanitizer/failure-hook 测试；实际命令与结果逐条记录。

## 7. Requirement 追踪

| 上位计划 | C++ 交付 |
| --- | --- |
| §3.1～3.4 | template/chain、create/update/delete/pause/resume/successor |
| §3.3、§6 | 日末补发、aggregate membership、履约/finalize 审计 |
| §3.5 | 冻结 notification content/tap identity；不含 note |
| §4 | bounded date-only occurrence query/cursor/summary |
| §5 | 全部 UUIDv5、local time/DST/UTC 物化与 CAS |
| §7 | 窄 Repository、logical commit、shared storage recovery、reconcile flag |
| §8.4 | Storage 目标版本、migration、兼容/失败恢复 |
| §12.2～12.3 | Domain/Application/Storage/Boundary 测试 |

## 8. 并行交付清单

C++ 负责人交付：

1. Domain/Application/Repository/Storage/Boundary 修改清单；
2. public Boundary header、函数签名和 Kotlin JNI symbol 对照；
3. identity/golden vector 实测结果；
4. migration 支持版本、fixture、回滚/失败恢复说明；
5. shared coordinator/journal 的 Store 与 failure-hook 矩阵；
6. `excellent_calendar_check` 和定向测试原始结果；
7. 需要最终 Android JNI/调度/真机验证的项目；
8. 上位计划 §9、§12.2、§12.3 的逐条勾选状态。

## 9. 停止条件

遇到以下情况停止受影响开发并报告：

- Contract 未冻结 occurrence/template/aggregate identity 或 Storage version；
- Anniversary 日末窗口与现有 Recovery 不能形成唯一安全 planner；
- 多 Store logical commit 无法防止 prepared journal/stale after-image 覆盖；
- 日期改回原值时旧确定性记录无法安全恢复/替换；
- migration 无法无损解释现有 v2 数据；
- 需要修改 Flutter/Kotlin/Contract 才能让单元测试通过；
- 需要巨大 Calendar state、顺序裸写、吞错或清空数据才能实现。

## 10. 本计划完成定义

达到“并行交付就绪”需满足：

- [x] Domain/Application/Repository/JSON/Boundary 全部按冻结 Contract 实现；
- [x] occurrence、identity、lifecycle、aggregation、delivery、timezone 和 migration 测试通过；
- [x] 构建后 `excellent_calendar_check` 通过；
- [x] Event Reminder、Ring、Recovery、Notification 和 Anniversary V1 回归通过；
- [x] production runtime 使用真实 JSON Repository，无内存 Fake/占位成功；
- [x] C++ 交付本身只修改 `cpp_core/**` 与追加 `docs/log.md`；
- [x] Android JNI/设备待验收项已明确交接。

上述 C++ Core/Storage 交付已完成，且真实 JNI、AlarmManager、Notification 与 Flutter UI 生产链已整合。Anniversary R1 已在 2026-08-25 经发布复审和产品负责人风险接受后激活；完整物理设备矩阵继续作为非阻断验证债。

## 11. 实施交付总结（2026-08-24）

### 已完成

- 完成 Anniversary date-only occurrence、一次性/年度规则、2 月 29 日、周年数、过滤、稳定排序与 cursor 分页。
- 完成最多 5 条 popup template、当地时间投影、DST gap/fold、首个 Reminder 物化，以及 create/update/pause/resume/delete 联动。
- 完成 Anniversary 日末补发、同 occurrence 聚合、covered membership、两阶段 prepare/finalize，以及 sent、permanent、retryable、expired 各类 successor。
- `FinalizeDeliveryCommand` 增加可选 `timezone`，`PlanReminderRecoveryCommand` 增加 `timezone`；Boundary 严格解析，并仅在加载事实后对 Anniversary 强制校验当前 IANA timezone。
- 完成 finalize 与 journal replay 幂等：已提交结果直接重放冻结 after-image，不重新读取时区或计算 successor；未提交重试使用 Kotlin 当次提供的时区。
- 扩展 Anniversary/Reminder/Notification/Recovery 的 Boundary、JSON codec、状态验证和 v2 journal 兼容；未写入 `projection_timezone`，未改变普通 Event、Ring 和普通 72 小时 Recovery 规则。
- 正式激活严格 Storage v3 读写与启动校验；完成无损、幂等、可中断恢复的 v2→v3 migration，两类遗留 v2 journal 均先恢复再迁移。
- 完成统一 `calendar_workflow_transactions.json` 协调器、冻结 after-image、Store generation 与 CAS；Event、Anniversary、Recovery、Delivery、Snooze 等共享写入统一接线。
- Runtime 已固定按 migration、严格校验、journal recovery、service construction 顺序启动，并报告 Storage format v3。

### 验证结果

- 执行构建后目标 `excellent_calendar_check`，最终 7/7 测试套件通过。
- 覆盖 Asia/Shanghai、DST gap/fold、prepare 后切换时区、成功后换时区重放、missing/invalid timezone、聚合 membership、各类 finalize outcome，以及 Event/Ring/普通 Recovery 回归。
- Storage v3 测试覆盖 golden、真实旧存储复现、11 个替换点中断恢复、严格字段、幂等、跨 Workflow 与陈旧 CAS。
- `git diff --check -- cpp_core` 通过，仅有既有 LF/CRLF 提示。

### 剩余发布门禁与交接

- C++ Core 与 Storage v3 当前没有额外实现阻塞；Storage v3 为 `integrated + active`，v2 仅作为迁移源与降级拒绝边界。
- Flutter→Kotlin→JNI→C++→Storage v3→Alarm→Notification 生产链已整合，Anniversary R1 当前为 `integrated + active`。隔离 device-test 应用与 Store 的完整真机矩阵、进程中断恢复和物理设备时区/DST 验收仍需继续，但不再阻断本次发布。

### 注意事项

- 不得从系统环境、UTC offset、`remind_at` 或 `timezone_mode` 推测当前时区，也不得新增或持久化 `projection_timezone`。
- 普通 Event recurring successor、Ring 五分钟规则和普通 Recovery 必须继续走既有 UTC Instant 逻辑。
- 当前 C++ 与 Android runtime 必须使用已激活的严格 Storage v3 启动门槛；完整 v2 目录只允许经恢复后迁移，pre-v3 旧版必须拒绝且保留 v3 目录。
