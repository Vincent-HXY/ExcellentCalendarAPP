---
name: calendar-data-contracts
description: 为 ExcellentCalendarAPP 设计、审查并实施数据领域模型、跨层 Contract、Dart/Kotlin/C++ 数据映射、本地 JSON/SQLite 持久化、版本兼容和历史迁移。用于新增或修改实体、字段、枚举、时间与重复规则、JSON Schema、MethodChannel/EventChannel/JNI 协议、DTO、Boundary Model、Repository、存储格式、导入导出格式及相关测试；也用于诊断跨层字段漂移、序列化错误和数据迁移风险。

---

# Calendar Data Contracts

# Goal

围绕“数据”完成可持续的数据设计和跨层传输变更，并使领域语义、传输协议、语言映射、持久化结构、历史数据和测试证据保持闭环。

不要把生成 schema、DTO 或迁移脚本视为完成。只有相关层同步、迁移可执行、验证实际通过且未验证项已明确报告时，才将实现描述为完成。

# Scope

根据用户请求执行架构设计、代码实施或审查。用户只要求分析或设计时，不修改代码；用户要求实现时，负责完整数据变更，可修改：

- `.\docs\domains\`；
- `contracts/` 下的 schema、枚举、错误码、`method_channels.yaml` 和 `native_calls.yaml`；
- Dart DTO、Gateway interface 与 adapter；
- Kotlin contract、MethodChannel/EventChannel handler 与 JNI bridge；
- C++ boundary request/response、Domain Model、workflow、Repository 与序列化；
- JSON/SQLite schema、索引、迁移、导入导出和备份恢复格式；
- 与上述变更直接相关的单元、契约、迁移和集成测试。

不要负责普通 Flutter 页面、视觉样式、Android 通知展示、权限 UI 或与数据边界无关的业务功能。数据变更导致这些层必须适配时，列出影响并只修改用户请求授权的范围。

# Sources of truth

开始工作前,按照任务需求读取核对：

1. 用户当前确认的需求和验收标准；
2. 当前目录及父目录中的 `AGENTS.md`；
3. `.\docs\domains\`；
4. `contracts/` 中相关 schema、公共包装、枚举、错误码、`method_channels.yaml` 和 `native_calls.yaml`；
5. 持久化 schema、格式版本和完整 migration 链；



按以下职责解释事实源：

```text
用户确认的需求
→ .\docs\domains\：领域语义真相源
→ contracts/：跨层传输协议真相源
→ schema / migration：持久化真相源
→ Dart / Kotlin / C++ 实现与测试：落地证据
```

不要把“优先级”理解为允许层间不一致。发现冲突时，先列出具体字段、方法、版本、历史数据和调用方影响；在关键语义未明确前停止受影响的写入，不要自行认定代码或文档天然正确。

# Non-negotiable data semantics

## Field and type conventions

- 使用稳定、单义、与现有模型一致的命名和类型。
- 在 Contract payload 中使用 `snake_case`；各语言内部可按既有习惯使用本土命名。
- 使用字符串传输枚举值，并以 `contracts/enums.yaml` 为协议定义。
- 区分缺失、显式 `null`、空字符串、空数组和默认值；不要用默认值掩盖 malformed data。
- 区分 Domain Model、Request、Response、Storage Entity 和 View Model；不要让一个万能对象承担全部职责。
- 不要把数据库表、C++ Domain Model 或 Flutter ViewModel 直接暴露为跨层协议。
- 仅将稳定且有明确校验、版本和迁移策略的数据保存为无类型 `object`/JSON blob；核心业务字段优先强类型化。
- 区分事实数据、派生数据、缓存和投递日志。派生数据默认重算；必须持久化时，说明失效和重建策略。
- 延续 UUID、时间戳、软删除、来源字段、快照字段等现有约定；若要改变，先给出全项目迁移方案。

## Event time

严格区分普通 Event 与全天 Event：

| 场景       | 字段                      | 语义                                                       |
| ---------- | ------------------------- | ---------------------------------------------------------- |
| 普通 Event | `start_at` / `end_at`     | ISO 8601 UTC 精确时间点，使用半开区间 `[start_at, end_at)` |
| 全天 Event | `start_date` / `end_date` | 用户本地日期，使用半开区间 `[start_date, end_date)`        |

- 对 timezone 使用 IANA timezone ID，例如 `Asia/Singapore`；不要使用 `CST` 等含糊缩写或仅保存固定 offset。
- 不要把全天日期转换成 UTC 午夜，也不要继续用 datetime 字段承载新的全天 Event。
- 将现有全天 Event 从 `start_at/end_at` 或 `startAt/endAt` 迁移到 date-only 字段视为 breaking change。显式设计旧数据判定、用户时区来源、不可判定记录的处理、回滚与测试；不要静默重新解释旧值。
- 将所有 `created_at`、`updated_at`、`deleted_at`、实际完成时间、投递时间等精确时间点规范为 ISO 8601 UTC。

## Recurrence and occurrence

- 使用当地墙上时间与 IANA timezone 展开重复规则，再将生成的 occurrence 精确时间点转换为 UTC。
- 将 `days_of_week` 定义为 ISO 8601：Monday=1，Sunday=7。
- 使用半开区间处理 recurrence 有效范围和 occurrence 时间范围。
- 显式测试 DST 跳时、DST 重叠、跨日、跨月、闰年、月末、时区变更和结束边界。
- 不要预生成无限未来 occurrence。区分重复规则、展开结果、稀疏 occurrence 状态和提醒任务。

## Existing domain boundaries

- 保持 `Event`、`Reminder` 和 `Notification` 独立：Event 是业务事项，Reminder 是未来任务，Notification 是每次投递结果。
- 保持 `Habit` 与 `HabitCheckIn` 独立；历史统计以 check-in 和必要快照为依据。
- 保持重复 Event 的单次状态位于 `EventOccurrenceState`，不要把“今天完成”等瞬时状态写入整个 Event。
- 将跨实体生命周期变更放入 C++ workflow/transaction，不要让 Flutter 或 Kotlin 分散补偿。
- 让 `event.complete` 在同一 Event/Reminder transaction 中完成 Event 并取消未触发 Reminder。
- 让 `event.reopen` 只恢复因 `event_completed` 自动取消且仍在未来的 Reminder。
- 使用 `Reminder.cancellation_reason` 区分 `user_cancelled` 与 `event_completed`；不要让 Android Alarm 或 Notification 成为额外真相源。

# Contract boundaries

## Public and internal capability maps

按以下关系解释两份 YAML：

```text
contracts/method_channels.yaml
= Flutter ↔ Kotlin 的公开能力

contracts/native_calls.yaml
= Kotlin ↔ C++ 的内部能力
```

不要要求两者的方法名或数量一一相等。对每个公开方法验证一条可解释的实现路径：

1. Kotlin 本地系统能力；
2. 一个 JNI 调用；
3. 多个 JNI 调用组成的 workflow；
4. 明确标记且不会伪装成功的未实现预留能力。

允许内部接口比公开接口更窄、更细。新增 JNI 模块能力时，延续按模块拆分的 bridge；让聚合接口只继承窄接口，让只需单模块能力的服务依赖窄接口。

## Request, response, error, and event rules

- 在任何 Dart/Kotlin/C++ 跨层调用前先声明 Contract；不要创建临时方法、字段、枚举或错误字符串。
- 为不同意图分别设计 Create、Update、Query、Response 和 Detail/Aggregate DTO。
- 只在组合查询 response 中聚合关联对象，不因页面方便而污染核心实体。
- 使用 `NativeResult<T>` 统一函数返回：
  - `ok == true` 时 `error == null` 且 `data` 符合声明的 response；
  - `ok == false` 时 `data == null` 且 `error` 合法；
  - error code 来自 `error_codes.yaml`；
  - `contract_version` 属于调用方支持范围。
- 为 EventChannel 数据声明稳定 schema、事件身份、排序和重复投递语义。
- 不要在 UI、普通 service 或 Domain Model 中扩散原始 `Map<String, dynamic>`、`JSONObject` 或无校验 JSON。
- 将未知枚举、缺失必填字段、错误类型、非法 `NativeResult` 和不支持的版本转成明确 contract failure，不要返回看似正常的空对象。

# Compatibility and versioning

先识别被修改的是哪一种版本域，再使用对应策略：

| 边界或数据                | 策略                                         |
| ------------------------- | -------------------------------------------- |
| Flutter ↔ Kotlin ↔ C++    | 在同一提交、同一发行版本中同步升级全部相关层 |
| 本地 JSON/SQLite 历史数据 | 提供显式、可测试、连续的 migration 链        |
| 未来 App ↔ Cloud Backend  | 至少支持 N−1                                 |
| 数据导入、导出、备份恢复  | 使用独立文件格式版本，提供更长期迁移         |
| 第三方公开接口            | 独立版本化，并在发布前规定弃用周期           |

将以下情况视为 breaking change：

- 新增必填字段；
- 字段删除、重命名、类型或单位变化；
- `null`/缺失/default 语义变化；
- 时间、时区、区间或 recurrence 语义变化；
- 枚举删除、重命名或改变既有值语义；
- ID、排序、分页、幂等、错误码或状态机语义变化；
- 改变持久化数据的解释方式。

新增可选字段通常可保持当前版本，但仍需验证所有 reader 对未知字段、缺失字段和默认行为的处理。不要用“解析失败后给默认值”冒充兼容。

对 breaking change 明确记录：

1. 受影响版本域和版本号；
2. 新旧 reader/writer 兼容矩阵；
3. 本地历史数据迁移；
4. 调用方升级顺序；
5. 回滚或失败恢复方案；
6. 弃用窗口；
7. 证明兼容性的测试。

# Persistence and migration

将当前正式持久化阶段视为 JSON，将 SQLite 视为未来目标，除非仓库实际代码和用户最新要求明确改变该状态。

保护当前目录约定：

- 正式 Android Calendar Core JSON 目录：`files/local_storage/calendar_core_storage_json`；
- 历史 `files/local_storage/test_storage_json`：只作为旧版本迁移来源，不再作为新代码正式目录。

发现代码与上述状态或路径不一致时，停止迁移相关写入并报告差异。

为每种持久化和交换格式维护独立版本。迁移必须：

- 使用显式连续步骤，例如 `v1 -> v2 -> v3`，不要只支持“任意旧版直接猜到最新版”；
- 能从当前支持范围内每个历史版本到达最新版；
- 保留未知但应保留的数据，拒绝无法安全解释的数据；
- 在写入前完成校验，避免半迁移状态；
- 具有确定性、可重复运行行为，或明确阻止重复运行；
- 对多实体不变量使用 transaction 或等效原子替换；
- 记录迁移失败原因，不吞错、不重置用户数据；
- 使用脱敏历史 fixture 测试字段保留、默认补全、枚举、时间、软删除、索引重建和失败恢复；
- 为 JSON → SQLite 迁移明确主键、外键、唯一约束、索引、事务边界和回退策略；
- 让备份恢复和数据导入根据独立文件格式版本选择迁移链，不直接复用 App 内部 contract version。

# Mandatory design gate for recurring and multi-channel reminders

当任务触及重复提醒、Reminder 身份、多渠道投递、事件完成/恢复/取消或调度恢复时，先解决以下问题再实现：

1. occurrence 是否具有稳定身份，例如 `occurrence_start_at`、`occurrence_key` 或等价设计；
2. 重复展开、系统重启、重试和 reconciliation 如何保持幂等；
3. 多个 `methods` 部分成功、部分失败时如何表达每个渠道状态；
4. Notification 是否按 occurrence、渠道和投递尝试生成独立记录；
5. Event 改期、完成、恢复、取消或删除时，哪些 Reminder 被取消、重建或恢复；
6. 领域事务完成后，Android 调度如何 reconcile，而不成为第二真相源；
7. 唯一键、重试键、取消原因、过期规则和历史记录保留策略是什么。

这些是强制设计门禁，不是立即要求重构所有现有模型。若当前任务触发门禁但需求不足以形成唯一安全设计，停止相关实现并向用户提出最小必要问题。

# Workflow

## 1. Inspect before designing

- 检查 `git status`，保护用户已有修改。
- 定位仓库实际目录、构建方式、测试入口和当前存储实现。
- 阅读本次实体及其关系、所有相关 schema、枚举、错误码和公开/内部方法。
- 沿 Dart → Kotlin → JNI → C++ → Repository → Storage 追踪真实读写路径。
- 搜索字段和枚举的全部 reader、writer、fixture、排序、索引、缓存、导入导出及通知调度用法。
- 核对历史 migration 和仍可能存在于用户设备上的最旧格式版本。

不要仅凭 README 示例或单个 schema 推断代码现状。

## 2. Classify the change

明确本次任务涉及：

- 领域语义；
- Contract；
- 语言边界映射；
- 持久化；
- 版本与迁移；
- workflow/transaction；
- 时间或 recurrence；
- 导入导出、备份、同步或第三方接口；
- 测试与发布。

标记新增、兼容扩展、breaking change、派生数据变更和纯实现修复。

## 3. Produce an impact matrix

在修改前列出：

| 层                    | 文件/符号 | 当前语义 | 目标变更 | 兼容/迁移 | 验证 |
| --------------------- | --------- | -------- | -------- | --------- | ---- |
| Data Model            |           |          |          |           |      |
| Contract              |           |          |          |           |      |
| Dart                  |           |          |          |           |      |
| Kotlin/JNI            |           |          |          |           |      |
| C++ Domain/Boundary   |           |          |          |           |      |
| Storage/Migration     |           |          |          |           |      |
| Import/Backup/Backend |           |          |          |           |      |

小型非 breaking 修复可压缩矩阵，但不得遗漏实际受影响层。

## 4. Design for long-term invariants

在写代码前定义：

- 业务对象职责、关系、所有权和生命周期；
- 字段含义、类型、单位、必填/可空、默认值和不变量；
- ID、唯一性、引用完整性、软删除和级联行为；
- 时间、时区、区间、recurrence 和 occurrence 身份；
- transaction、幂等、并发和失败恢复；
- Request/Response 与 Domain/Storage 映射；
- 版本、兼容矩阵、迁移链和弃用计划；
- 验收测试和不可接受的数据损失。

优先与现有模型匹配。不要为当前页面便利新增短命字段；先判断它是领域事实、查询参数、组合 response、派生值还是 UI state。

## 5. Implement in dependency order

对已授权的完整数据变更，按以下顺序实施：

1. 更新 `.\docs\domains\` 的领域语义、关系、不变量和迁移说明；
2. 更新公共 schema、枚举、错误码和版本；
3. 更新 `method_channels.yaml` 与 `native_calls.yaml`，并验证公开方法实现路径；
4. 更新 C++ Domain、workflow、Boundary 和 Repository；
5. 更新持久化格式及显式 migration；
6. 更新 Kotlin contract、模块 bridge、handler 和 JNI；
7. 更新 Dart DTO、Gateway interface 和 adapter；
8. 更新导入导出、备份、同步和缓存等受影响 reader/writer；
9. 添加并运行测试。

允许根据仓库构建依赖微调代码落地顺序，但最终必须在同一提交、同一发行版本内完成 Flutter/Kotlin/C++ 协议同步。

## 6. Review the final diff

- 排除无关重构、格式噪音和用户已有修改。
- 逐字段检查所有 reader/writer，不只检查 writer。
- 检查文档、schema、实现和 migration 是否描述同一语义。
- 检查 deprecated 字段是否仍由旧 reader 正确处理。
- 检查数据失败路径不会清空、覆盖或伪造成功。

# Verification

使用仓库已有工具和 README 指定命令；不要为单次变更擅自引入新的生成器、序列化库、数据库框架或测试依赖。

至少执行适用的：

- JSON Schema/YAML 语法、`$ref` 闭合、枚举和错误码引用校验；
- `method_channels.yaml` 每个公开方法的实现路径检查；
- `native_calls.yaml` 与 JNI 导出、Kotlin bridge、C++ boundary 的一致性检查；
- Dart、Kotlin 和 C++ serialization/deserialization round-trip；
- 字段名、nullable、未知字段、未知枚举、malformed payload 和 `NativeResult<T>` 不变量测试；
- 普通时间、全天日期、半开区间、UTC、IANA timezone、DST gap/fold 和 recurrence 边界测试；
- migration 的每个相邻版本和最旧支持版本到最新版测试；
- migration 重复运行、失败恢复、事务原子性、引用完整性和数据保留测试；
- Repository、workflow、幂等、并发和软删除测试；
- 真实 MethodChannel/JNI/Storage 集成测试；
- README 规定的格式、静态分析、单元测试、Native 构建和 Android Debug 构建。

不要把 mock、schema 校验或编译分别称为完整跨层验证。没有设备、SDK、历史 fixture 或真实下层实现时，明确标记具体未验证行为和继续验证所需条件。

# Blockers and safety

遇到以下情况时停止受影响的实现：

- 用户需求与 `.\docs\domains\`、contracts、migration 或已落地代码冲突；
- 无法确定旧字段、旧版本、用户时区或历史数据的安全解释；
- breaking change 缺少版本、迁移、调用方升级或弃用方案；
- 重复/多渠道提醒触发强制门禁但身份、幂等或状态语义未明确；
- 迁移可能丢失或覆盖用户数据，且没有可靠恢复策略；
- 无法区分用户已有修改与本次修改；
- 必需工具、fixture、设备或下层能力缺失。

不要：

- 静默删除或重命名已使用字段；
- 通过 catch-all、空对象或默认值吞掉旧数据；
- 直接修改历史 migration；
- 让 JSON 和 SQLite 同时成为可写真相源；
- 将 Android Alarm 状态当成 Reminder 领域真相；
- 绕过 Contract 直接跨层传输；
- 为通过测试而删除、跳过或弱化断言；
- 声称未实际执行的测试或构建已经通过。

# Completion report

按以下顺序汇报：

1. 结果：完整完成、部分完成、仅设计完成或被阻塞；
2. 数据设计：实体、关系、不变量和 `.\docs\domains\` 变化；
3. 跨层影响：Contract、Dart、Kotlin/JNI、C++、Storage 的修改矩阵；
4. 兼容与迁移：版本域、migration 链、旧数据和回滚/恢复；
5. 验证：逐条列出实际命令及结果；
6. 未验证与风险：说明缺少的 fixture、设备、环境或后续决策。

只有所有适用层已同步、历史迁移已测试、关键验证已通过且 diff 无无关修改时，才使用“已完成且验证通过”。