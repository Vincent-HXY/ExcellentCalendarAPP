# 计划 1：纪念日 Reminder 与 Occurrence Contracts 层

> 状态：Completed / Contract R1 已冻结并完成生产接线；Anniversary R1 与 Storage v3 均 integrated / active
> 上位计划：[`纪念日-02-Reminder与Occurrence开发计划.md`](./纪念日-02-Reminder与Occurrence开发计划.md)  
> 负责范围：`docs/domains/**`、相关 Accepted ADR、`contracts/**`、Contract fixture 与 Contract 校验  
> 必须使用 Skill：`calendar-data-contracts`  
> 交付性质：冻结跨层真相源，并向 Flutter、Kotlin、C++ 三个负责人提供同一可执行基线

## 1. 任务目标与约束

本计划负责把上位计划第 2～8、12.1、14、15、16、17 节转化为机器可验证的领域与跨层协议。它不改变产品行为，只冻结实现必须共同遵守的字段、条件分支、身份、错误、版本、兼容和测试向量。

完成后，Flutter、Kotlin、C++ 三个工作流必须能够在不互相读取未合并代码的情况下，分别依据同一份 Contract 和 fixture 开发。任何实现层不得再自行决定：

- Anniversary occurrence、template、Reminder 或聚合 delivery 的身份算法；
- 缺失、`null`、空数组与默认值语义；
- date-only 与 UTC Instant 的映射；
- 多条 Reminder 被一个真实 Notification 履约时的状态和审计关系；
- Scheduler “数据已保存、调度待恢复”的成功/降级/错误表达；
- Wire Contract 与 Calendar Core Storage 的版本和兼容策略。

## 2. 开发基线

执行前必须核对实际仓库，不能只按本计划机械改文件。当前基线为：

- Native MethodChannel/JNI Contract 为 v2，Anniversary 六个现有方法是 `integrated`；新能力尚未声明。
- Calendar Core 正式存储为 JSON v2，正式目录是 `files/local_storage/calendar_core_storage_json`。
- Anniversary create/update/detail 尚不接收或返回 Reminder plan。
- Reminder/Notification 已允许 `target_type=anniversary` 作为枚举值，但当前 schema 仍把 Anniversary occurrence 视为空；这不代表能力已经实现。
- `identity.yaml` 只有 Event occurrence、recurring Reminder、snooze 和普通 delivery 向量。
- `OPEN-ANN-001` 已在 2026-08-25 发布复审与负责人风险接受后关闭；未覆盖设备矩阵继续作为非阻断验证债。

权威输入按以下顺序解释：

1. 用户已确认且记录在上位计划的需求与验收标准；
2. `docs/domains/anniversary.md`、`reminder.md`、`notification.md`、`reminder_recovery_batch.md`；
3. Accepted ADR；
4. `contracts/**` 的机器可验证定义；
5. 当前实现只作为落地现状证据，不能覆盖目标需求。

发现冲突时必须列出具体文件、字段/方法、双方语义、影响层和建议真相源；关键语义未形成唯一安全答案前停止受影响 Contract，不得让三层实现各自猜测。

## 3. 允许与禁止修改的范围

允许修改：

- `docs/domains/anniversary.md`
- `docs/domains/reminder.md`
- `docs/domains/notification.md`
- `docs/domains/reminder_recovery_batch.md`
- `docs/architecture/decisions/` 中本功能的新增或修订 ADR
- `contracts/README.md`
- `contracts/anniversary/**`
- `contracts/reminder/**`
- `contracts/notification/**`
- `contracts/storage/calendar_core_storage.yaml` 及其直接引用
- `contracts/method_channels.yaml`
- `contracts/native_calls.yaml`
- `contracts/identity.yaml`
- `contracts/enums.yaml`
- `contracts/error_codes.yaml`
- 本功能的 `contracts/fixtures/**` 与现有 Contract 校验入口
- `docs/log.md`，只允许追加本任务记录

禁止修改 Dart、Kotlin、Android、JNI、C++ 生产实现。不得为方便某一语言而把 Domain、Request、Response、Storage Record 或 ViewModel 合并成万能对象。

## 4. 必须交付的 Contract 包

### 4.1 领域语义与 ADR

更新领域文档并新增或修订 Accepted ADR，完整记录：

- Anniversary 继续是独立实体，不转换为 Event，不使用 Event Recurrence revision。
- Anniversary occurrence 是用户当地 `date`，无 UTC `occurrence_start_at`，无完成/跳过/取消状态，不无限预生成。
- Reminder 是未来任务真相源，Notification 是真实投递 attempt/履约审计，Android Alarm 不是第二真相源。
- 创建、更新、删除、暂停/恢复、补发、prepare/finalize 和时区重算属于 C++ workflow；Kotlin 只做平台副作用，Flutter 只做用户流程和展示。
- 使用窄 `AnniversaryReminderWorkflowRepository` 或等价拆分；当前 JSON 使用可恢复 logical commit，未来 SQLite 使用相同 port 的数据库事务；不建立大型 `CalendarTransaction`。
- 数据提交先完成，Scheduler reconciliation 后执行且可重试；调度失败不得删除或回滚已保存 Reminder。

领域文档必须覆盖上位计划 §3～7 的全部不变量，包括：一次性/年度 successor、最多 5 条、0～365 天、分钟级 `local_time`、跟随设备时区、日末补发窗口、同 occurrence 聚合、编辑/暂停/恢复/删除和历史动态 occurrence 投影。

### 4.2 Anniversary Reminder 输入与详情输出

新增强类型 Anniversary Reminder template/draft schema。最终命名可以按既有目录约定调整，但必须在交付清单中给出稳定 `$id` 和引用关系。

输入至少表达：

- `advance_days`：整数，`0..365`；
- `local_time`：当地分钟级时间，精确格式必须冻结；
- `method`：V1 固定 `popup`，不能接受 ring/wechat；
- `is_enabled`：单条配置状态如何与总开关配合必须单义；
- Anniversary 级提醒总开关；
- 最多 5 条且 `(advance_days, local_time, method)` 唯一。

Create/Update 必须把 Anniversary、recurrence 选择、Reminder plan 和总开关交给同一个 C++ workflow。需要明确：

- 字段缺失、显式 `null`、空数组分别表示什么；
- create 默认关闭且空配置是否合法；
- update 省略、空配置、关闭总开关、删除全部模板之间的区别；
- 标题/备注/分类/重要性变化不替换提醒身份，日期/repeat/template 变化如何触发替换；
- 已有 Anniversary 升级后配置为空且不会自动生成 Reminder。

Detail response 返回 UI 所需的总开关、模板列表、活动数量和调度恢复/能力提示，但不得暴露 JSON journal、Alarm ID 或内部投递审计噪音。部分成功响应必须让 Flutter 严格区分：

1. 数据未保存；
2. 数据已保存且调度成功；
3. 数据已保存但需要后续 reconciliation；
4. 权限缺失导致降级或待恢复，而不是业务数据失败。

### 4.3 Anniversary occurrence 查询

新增并闭合：

- `list_anniversary_occurrences_request`；
- `anniversary_occurrence_summary_response`；
- `anniversary_occurrence_list_response`。

请求必须严格表达当地日期半开区间 `[range_start_date, range_end_date)`、有效 IANA timezone、最大 400 个自然日、稳定 cursor，以及可选 `category_ids`、`importance` 过滤。重复过滤值、非法 enum、逆序/空窗口、超过 400 天、malformed/expired cursor 都必须明确失败。

响应每项至少覆盖上位计划 §4.3 的 12 个字段，按 `(occurrence_date, anniversary_id, occurrence_key)` 稳定升序。分页协议需保证 Flutter 自动拉取全部页面时不重不漏；不得设置 200 条总结果上限。不得返回完整 note、Reminder 明细、Notification 历史、本地化文案或 start/end Instant。

### 4.4 Reminder 的 Anniversary 条件分支

扩展 Reminder schema，以 `target_type` 条件分支严格约束，而不是接受任意 nullable 字段组合。

Anniversary 分支至少表达：

- `template_key`
- `occurrence_key`
- `occurrence_date`
- `advance_days`
- `local_time`
- `timezone_mode=follow_device`
- `fulfillment_delivery_id`

Anniversary 分支必须拒绝或要求为空：

- `recurrence_revision`
- `occurrence_start_at`
- `advance_minutes`
- ring/wechat 或多 method

Event 普通/重复 Reminder 与 Ring 的既有合法 payload 必须继续通过；旧 reader/writer 对新字段的缺失/`null` 行为必须在兼容矩阵中显式说明。

### 4.5 聚合 Notification 与 RecoveryBatch

优先定义明确的 Anniversary catch-up 聚合 Notification kind，而不是把多 Reminder 伪装为普通单 Reminder attempt。冻结：

- `target_type=anniversary`、`target_id=anniversary_id`；
- `occurrence_key`；
- 完整、唯一、稳定排序的 `covered_reminder_ids`；
- `recovery_batch_id` 或等价恢复归属；
- `delivery_id`、`delivery_attempt_id`、真实时间与状态；
- 每个 covered Reminder 的 `fulfillment_delivery_id` 指向同一真实 delivery；
- membership 在 prepare 后冻结，重放不得加入后来到期成员；
- sent/retryable/permanent/expired 四类结果如何同时更新 attempt、covered Reminder、successor 和 batch。

Notification tap payload 必须能携带 Anniversary occurrence identity 并直接路由真实 Anniversary detail；目标已删除时由消费者得到稳定缺失状态。锁屏 payload/内容不得包含 note。

现有 Event Reminder、Ring 五分钟恢复规则、全局 20 条明细上限和普通 Recovery summary 语义不得被修改。Anniversary 日末补发是独立 target-specific 规则，Contract 必须说明它与既有 72 小时 Recovery window 的选择/分组关系，禁止 Kotlin 二次推导。

### 4.6 身份、幂等与 Golden Vector

在 `contracts/identity.yaml` 冻结独立 namespace、canonical JSON、字段顺序、大小写/格式和 UUIDv5 golden vectors。至少覆盖：

1. Anniversary occurrence：`anniversary_id + occurrence_date`；
2. Reminder template：`anniversary_id + advance_days + local_time + follow_device + popup`；
3. Anniversary Reminder：target、occurrence、template；
4. Anniversary catch-up aggregate delivery：target、occurrence、稳定排序的 covered IDs、popup；
5. 相同输入重放；
6. 标题/备注/分类/重要性变化不改变 identity；
7. 日期、模板或 membership 变化产生预期的新 identity；
8. 日期改回原值时恢复原确定性 identity。

上位计划 §5 中给出的是候选语义。本阶段必须冻结最终 namespace 和 exact name，不得把仍含“建议/候选”的 identity 交给实现团队。

### 4.7 方法、状态、枚举与错误

在 `method_channels.yaml` 和 `native_calls.yaml` 增加 `anniversary.list_occurrences`，并同步 create/update/detail 的新 shape。公共方法与内部调用不要求数量一一相等，但每个公开方法必须有可解释路径。

新方法和扩展能力在三层实现与跨层验收前必须保持准确的 `implementation_status: planned` 或 `implemented_unintegrated`、`release_status: blocked`。不得因为 Schema 已存在而标记 active。

更新 `enums.yaml` 与 `error_codes.yaml`，至少覆盖上位计划 §8.3 的十类稳定失败。每个错误必须冻结：code、module、retryable、适用边界和是否允许“数据已保存”结果。禁止自由文本状态、catch-all 空成功或用 `NATIVE_INTERNAL_ERROR` 掩盖已知业务失败。

### 4.8 Wire 与 Storage 版本/迁移

分别输出两张兼容矩阵：

| 版本域 | 必须回答的问题 |
| --- | --- |
| Native Wire | 新旧 Dart/Kotlin/C++ reader/writer 如何处理新增方法、target-specific 必填字段、详情新增字段和聚合 kind；是否保持 v2，若提升版本需说明同一 APK 升级顺序 |
| Calendar Core JSON | 是否按上位计划评估结果执行 `v2 -> v3`；每个 Store 的新字段、默认/缺失规则、迁移顺序、失败恢复、重复运行与旧 App 回滚风险 |

若采用 JSON v3，更新 `contracts/storage/calendar_core_storage.yaml`，明确：

- `anniversaries.json`/相关配置记录如何保存总开关和模板；
- `reminders.json`、`notifications.json`、`reminder_recovery_batches.json` 新字段；
- Event/普通 Reminder/Ring/旧 Anniversary v2 数据逐字段保留；
- 现有 Anniversary 迁移后模板集合为空、提醒默认关闭；
- 旧 `fulfillment_delivery_id`/`covered_reminder_ids` 缺失如何合法解释；
- 连续迁移、原子替换、journal/shared coordinator、bootstrap 恢复门禁和损坏数据拒绝；
- 降级旧 App 不安全，且不得静默清空 v2 用户数据。

不得把 App 内部 Storage version 与 Native Contract version、导入/导出或未来 Backend version 混为一体。

## 5. Requirement 追踪矩阵

交付时必须提供逐条追踪表，至少包含：

| 上位计划要求 | Contract 负责人交付 | 下游负责人 |
| --- | --- | --- |
| §3.1～3.2 支持、创建、权限/降级 | Anniversary draft、create/update/detail、partial-success schema | Flutter、Kotlin、C++ |
| §3.3 补发与聚合 | Notification/Recovery 聚合 schema、membership、delivery identity | Kotlin、C++ |
| §3.4 生命周期 | 更新/暂停/恢复/删除 command/response 语义 | Flutter、C++；Kotlin 只 reconcile |
| §3.5 内容与导航 | prepared/tap payload、目标缺失错误 | Flutter、Kotlin、C++ |
| §4 occurrence 查询 | request/summary/page/cursor schema | Flutter、Kotlin、C++ |
| §5 身份与时间 | identity vectors、date/time/timezone enum/format | 三层共同消费 |
| §6 Reminder/Notification | target-specific oneOf/if-then、履约审计字段 | Kotlin、C++，Flutter 仅消费必要投影 |
| §7 workflow/storage/scheduler | Storage contract、commit/reconcile response | Kotlin、C++ |
| §12.1 | 正反 fixture、malformed payload、version、golden vectors | 三层 round-trip 测试 |

每个 schema/enum/error/identity 必须至少有一个实际 reader 和 writer 的责任归属；孤立定义不得交付。

## 6. Fixture 与验证要求

至少新增并验证：

- create/update/detail：提醒关闭、开启 1 条、开启 5 条、6 条、重复配置、非法 method、非法 local time；
- occurrence：一次性、年度、历史窗口、原始年份下界、2 月 29 日、400 天边界、多页、稳定排序、非法 cursor；
- Reminder：Event 普通/重复/Ring 既有正例、Anniversary 正例、跨 target 字段混用反例；
- aggregate delivery：单成员、多成员、stable sort、membership 冲突、重复 prepare/finalize、retryable/permanent/expired；
- tap payload：Anniversary 正常/聚合、occurrence key、目标删除；
- Storage：每种 v2 fixture 到目标版本、重复迁移、损坏记录、未知字段、软删除和审计字段保留；
- 所有 UUIDv5 golden vector 在至少一个独立脚本/测试中重算并匹配。

实际执行仓库已有的 JSON/YAML 解析、`$id/$ref` 闭合、枚举/错误引用、能力图路径和 fixture 校验。不得擅自引入新生成器或依赖。未具备完整 metaschema 工具时，必须把缺口标记为未验证，不能把普通 JSON parse 称为 Schema 验证。

## 7. 并行开工门禁与交接包

只有同时满足以下条件，才允许宣布“Contract 已冻结，三层可以并行开工”：

- [x] 四份领域文档与 ADR 描述同一套 occurrence、Reminder、Notification、Recovery 和 Repository 语义。
- [x] 所有新增/修改 Schema 可解析，`$id/$ref` 唯一且闭合。
- [x] create/update/detail/list occurrences/Reminder/Notification/Recovery/tap 的正反 fixture 完整。
- [x] identity namespace、canonical name 和 golden vectors 不再含候选项。
- [x] error code、retryable 和 partial-success 语义已冻结。
- [x] Wire/Storage 兼容矩阵和版本决定已记录。
- [x] 新能力状态保持 planned/blocked，未提前激活。
- [x] Event Reminder、Ring、普通 Recovery 的既有 Contract fixture 回归通过。
- [x] `git diff` 无 Dart/Kotlin/C++ 实现或无关改动。

交接包必须包含：

1. 冻结 Contract 的提交 SHA；
2. 本次新增/修改文件清单；
3. 方法 → request → response → error → identity 的能力矩阵；
4. Wire/Storage 版本与兼容矩阵；
5. 供三层直接复用的 valid/invalid fixture 与 golden vectors；
6. 已执行验证及原始结果；
7. 明确的未验证项和仍被阻塞能力；
8. 上位计划 §2～17 的逐条追踪结果。

## 8. 停止条件

出现以下任一情况，停止受影响部分并报告，不得把歧义下放给实现者：

- Anniversary 日末补发与既有 72 小时 Recovery planner 无法形成唯一分组/优先级；
- aggregate Notification kind、RecoveryBatch ownership 或 covered membership 无法同时满足真实投递与审计闭环；
- Wire v2 的兼容方式需要调用方猜测缺失字段；
- JSON v2→目标版本可能丢失、覆盖或静默重置用户数据；
- “已保存、调度待恢复”无法用合法 NativeResult/response 表达；
- 日期改回原值时确定性 ID 与旧终结记录的恢复/替换规则不明确；
- Contract 与上位计划或 Accepted ADR 冲突且无法按 Source of Truth 规则解决。

## 9. 本计划完成定义

本计划只有在第 7 节门禁全部满足并交付冻结提交后，才可标记“Contracts 层完成”。这只表示三层可以并行开发，不表示 Anniversary Reminder/Occurrence 已集成、可发布或通过真机验收。

完成记录：Contract R1 初始冻结提交为 `7217523`，Anniversary finalize 可选 timezone、条件语义必填、跨时区幂等重放与自举验证门禁的兼容修正提交为 `1961953`；实现层必须使用包含后者的 Contract 基线。Schema/fixture/identity 验证结果与兼容、能力、责任和需求追踪矩阵见 `contracts/anniversary/README.md`。Dart/Kotlin/C++、JSON migration、跨层 smoke 与真机行为仍需按当前 Contract 完成实现或验证，所有新能力继续保持 blocked。

## 10. 向上交付总结

### 10.1 交付结果

Contracts 层已完成。Contract R1 初始基线为 `7217523`，本次 finalize 时区兼容修正为 `1961953`。修正解除 C++ 生成 Anniversary 年度 successor 时缺少实际 IANA 时区的协议阻塞，且未破坏 Event、Ring 和普通 Recovery 的旧请求。

### 10.2 完成内容

- 在共享 `finalize_delivery` 请求中新增结构可选、非空的 `timezone`；Anniversary Reminder 和 `anniversary_catch_up` 在加载 prepared attempt 后语义必填，缺失返回 `CONTRACT_VALIDATION_FAILED`，非法 IANA ID 返回 `TIMEZONE_ID_INVALID`。
- 冻结 finalize 幂等规则：首次成功提交使用当前时区持久化 successor；提交后重放返回原结果，不因新时区重新计算；timezone 不参与 Reminder、delivery 或 attempt identity；retryable failure 不生成 successor。
- 保持 `plan_recovery.timezone` 必填，明确其负责 Anniversary 日末边界、expired successor 和 Recovery 重物化；`prepare_delivery` 不增加 timezone。
- 补齐有效、缺失、非法、Event/Ring 兼容和跨时区重放 fixture，并新增可自行准备 `jsonschema`、`PyYAML`、`tzdata` 的 Contract 验证入口。
- 同步更新 Contract 说明、兼容矩阵、Reminder/Recovery 领域文档和 Accepted ADR；未修改 Flutter、Kotlin、JNI 或 C++ 实现代码。

### 10.3 验证结果

实际执行 `python contracts/run_anniversary_r1_validation.py`：162 个 Draft 2020-12 Schema、49 个 Anniversary/Ring fixture、16 个 UUIDv5 golden vector 全部通过；JSON 解析、`$id/$ref` 闭合和相关 `git diff --check` 通过，仅有仓库既有行尾提示。

### 10.4 状态边界

本次仅表示 Contract 决策与验证门禁完成。Anniversary Reminder/Occurrence 整体能力仍需完成实现层接线、JSON v3 migration、跨层 smoke 和真机验收，相关能力继续保持 blocked，不能据此宣布已集成或可发布。
