---
name: cpp-core-feature
description: 在 ExcellentCalendarAPP 的 cpp_core 内实现、修改或修复 C++17 核心功能，覆盖 Domain、Application Service、跨实体 Workflow/Transaction、Repository、JSON Storage、Boundary Contract/API 与测试。仅允许修改 cpp_core/**，其余目录只读。开始前必须按需检索现状、拆分需求并完成可行性判断；遇到协议冲突、关键架构取舍或基础能力缺失时，停止并向用户确认。

---

# Goal

在 `cpp_core/**` 内，基于项目现有架构实现稳定、可测试、低耦合、高内聚的 C++ Core 功能。

任务完成必须同时包含：

1. 用最小必要上下文确认项目现状；
2. 将需求拆到正确模块并检查依赖；
3. 判断可实现性及阻塞；
4. 复用现有基础设施完成最小范围实现；
5. 从真实使用场景独立设计并执行测试；
6. 检查最终 diff；
7. 如实报告完成度、变更、测试证据和局限。

# Hard boundaries

## Writable scope

只允许修改、创建或删除：

```text
cpp_core/**
```

路径按 Windows 大小写不敏感语义判断。构建工具可生成 `cpp_core/build-*`，但不得手工修改、提交或用旧产物证明新代码已通过。

## Read-only scope

仓库内其他内容均只读，包括：

```text
AGENTS.md
README.md
.\docs\domains\
contracts/**
flutter_client/**
android/**
test_environment/**
```

若实现必须修改只读内容，停止受影响部分并报告。不得绕过 Contract、伪造接口、添加临时跨层字段，或私自兼容未确认的新协议。

# Context discipline

上下文是有限工作内存，仓库是外部存储。默认采用“先定位、按需加载、及时压缩”，禁止无目的全量读取大型仓库、长文件或完整日志。

## Progressive retrieval

按以下顺序收集信息：

1. **看结构**：目录、文件名、标题、索引、CMake 目标、测试入口；
2. **搜符号**：目标函数、类型、错误码、Contract 方法、定义、调用方和测试；
3. **读局部**：只读命中位置及完成判断所需的最小上下文；
4. **追直接依赖**：Command、Boundary Contract、Service、Repository、Transaction、测试 Fake；
5. **有证据再扩展**：仅在发现跨模块调用、共享状态、存储兼容或协议依赖时扩大范围；
6. **压缩结论**：记录调用链、职责、缺口和待验证项，不反复读取不变内容；
7. **最终读 diff**：实现完成后再完整检查本次 `cpp_core` diff。

优先定位：

```text
定义位置
所有调用点
直接接口与实现
CMake 登记
相关测试与 Fake
对应 Contract / enum / error code
```

每次扩大范围前，必须能说明“缺少哪项信息，以及它影响哪个判断”。不得因为文件名相似就批量读取目录，也不得沿无关引用无限扩散。

以下情况可以读取完整文件：

- 文件较短且整体语义不可拆分；
- schema、枚举、错误码、Transaction、恢复逻辑或存储格式需要完整核对；
- 局部片段不足以判断生命周期、所有权、异常安全或冲突来源。

## Logs

- 失败时先提取首个根因错误及附近必要上下文；
- 级联错误先不展开，修复根因后重跑；
- 不反复读取相同完整日志；
- 只记录命令、退出状态、根因和未验证项；
- 不因截断日志而隐藏关键错误。

## Working summary

分析期间维护精简证据表，只保留会影响当前任务的事实：

| 项目   | 已确认事实               | 证据位置           | 状态             |
| ------ | ------------------------ | ------------------ | ---------------- |
| 入口   | [方法/符号]              | [文件]             | 已使用/占位/缺失 |
| 规则   | [权威位置]               | [Service/Workflow] | 单一/重复        |
| 持久化 | [Repository/Transaction] | [文件]             | 可用/缺失        |
| 测试   | [场景]                   | [测试文件]         | 已覆盖/待补      |

# Sources of truth

开始开发前按开发任务需求定位并核对：

1. 当前目录及父目录中的 `AGENTS.md`；
2. `.\docs\domains\`的与任务相关的实体职责和阶段决策；
3. `contracts/method_channels.yaml`、`native_calls.yaml`；
4. 当前功能相关的 request、response、common schema、枚举和错误码；
5. `cpp_core/CMakeLists.txt`；
6. 目标符号附近的 `include/`、`src/`、`tests/`、`tests/support/`；
7. Git 状态和用户已有未提交修改。

“核对”不等于完整读取全部文件。先搜索标题、键名和符号，再读相关片段。

跨层方法名、字段、枚举、错误码、时间格式、版本和 `NativeResult<T>` 以只读 `contracts/` 为协议真相源。


# Current baseline

每次任务均重新确认。当前基线：

- C++17、CMake 3.22.1、现有 `picojson`；
- 当前以 `storage/json` 持久化，不能默认 SQLite 已可用；
- 内部使用 `common::Result<T>`，跨边界使用 `NativeResult<T>`；
- clock、ID generator 等可注入；
- 测试使用项目自有 `require`/`main`，没有 GoogleTest；
- 已有 Event、Reminder、Notification、Boundary API、JSON Repository、事务日志和恢复机制；
- 已有 `excellent_calendar_core_tests`、`excellent_calendar_reminder_tests`、`excellent_calendar_check`；
- Event/Reminder 创建、完成和重开已有 Workflow/Transaction 模式。

不得为了“更标准”整体替换现有 JSON、测试、错误、依赖注入或服务组织方式。

# Architecture and module ownership

```text
JSON request
    ↓
boundary/api + boundary/contract
    Contract 校验、Request ↔ Command/Response
    ↓
application
    单实体 Service / 跨实体 Workflow
    ↓
domain + repository interfaces
    领域语义 / 持久化与事务抽象
    ↓
storage/json
    JSON 映射 / 原子写入 / 日志 / 回滚 / 恢复
    ↓
NativeResult JSON
```

| 模块                 | 核心职责                                     | 不得承担                             |
| -------------------- | -------------------------------------------- | ------------------------------------ |
| `domain/`            | 稳定业务对象、常量、枚举语义、技术无关校验   | JSON、文件、Boundary、平台依赖       |
| `application/`       | 单实体 Service；跨实体 Workflow              | 具体 `Json*Repository`、传输协议细节 |
| `repository/`        | 窄持久化和事务抽象                           | Boundary DTO、万能查询框架           |
| `storage/json/`      | JSON、文件、锁、原子写入、回滚恢复           | UI/Contract 规则、重复业务规则       |
| `boundary/contract/` | C++ Request/Response 与 JSON 表示            | Domain/存储万能模型                  |
| `boundary/api/`      | 解析、协议校验、Command 转换、调用和异常边界 | 文件读写、领域规则、跨实体补偿       |
| `common/`            | 真正跨模块且稳定的基础能力                   | 一次性工具、未来假设、职责垃圾桶     |
| `tests/`             | 用户场景和可观察结果                         | 真实用户数据、脆弱实现细节           |

不要因为 README 出现 “Engine” 就创建与现有 Service 平行的新框架。

# Cohesion and coupling

## Required properties

- 一个 Service、Workflow、Repository 或文件只围绕一个清晰职责；
- 模块只依赖完成职责所需的最小接口；
- 同一业务规则只有一个权威实现；
- 跨实体协作由 Workflow/Transaction 显式表达；
- 核心层不反向依赖 Boundary、Storage 或平台层；
- 不为每个函数创建接口，也不为未确认的未来需求搭框架。

保持依赖方向：

```text
boundary → application → domain/repository abstractions
storage → repository abstractions + domain
runtime → concrete construction
```

## Coupling smells

发现以下情况时，先分析拆分，不能继续堆代码：

- 一个类同时承担 JSON、业务规则和文件读写；
- 单模块 Service 依赖多个无关 Repository；
- 一个规则变更要求修改多个不相关模块；
- 同一校验或状态转换在多层重复；
- Domain include Boundary、Storage 或平台头文件；
- Boundary 知道具体文件名、锁或事务日志；
- Repository 暴露 Boundary DTO 或平台类型；
- 为单一能力依赖包含所有模块的“大接口”；
- 循环 include、双向依赖或全局单例隐藏依赖。

## Splitting guide

- 单实体业务规则 → 对应 Application Service；
- 跨实体原子流程 → 专用 Workflow + Transaction；
- 持久化访问 → 窄 Repository；
- JSON/文件细节 → `storage/json`；
- 跨语言转换 → Boundary；
- 稳定业务概念 → Domain；
- 多模块真实共享且稳定的能力 → `common`。

拆分只解决当前已证实的依赖问题，不借机大规模重构。若“局部最小修改”和“结构化拆分”在范围、兼容性或长期维护上存在显著取舍，列出两种方案的优缺点并询问用户，不能默认选择最简单或最宏大的方案。

# Non-negotiable domain invariants

## Domain and boundary separation

```text
JSON request
→ C++ Boundary Request
→ Domain Model / Command
→ Application / Workflow
→ Domain Result
→ Boundary Response
→ JSON result
```

跨层字段必须来自现有 Contract。不得把 Domain 字段顺便加入 JSON，也不得让 Domain 依赖 Contract 命名。

## Event lifecycle

必须保留：

1. `event.complete` 对外仍返回 `EventResponse`；
2. 内部调用 `EventLifecycleWorkflowService`；
3. Event 与 Reminder 变化位于同一个 `EventReminderTransaction`；
4. 完成 Event 时取消关联且未触发的开放 Reminder，并写入 `cancellation_reason = event_completed`；
5. `event.reopen` 同样经过该 Workflow/Transaction；
6. 只恢复因 `event_completed` 自动取消且 `remind_at` 仍在未来的 Reminder；
7. `user_cancelled` Reminder 不得自动恢复；
8. Android Alarm/Notification 只依据当前 Reminder 状态，不保存第二套领域真相。

## Other invariants

- `Reminder` 是调度任务和扫描入口；`Notification` 是投递结果日志；
- `Event.status` 表示整个事件或重复系列，单次 occurrence 状态属于 `EventOccurrenceState`；
- `Habit` 保存定义，某日行为和统计来源是 `HabitCheckIn`；
- `datetime` 是 UTC 时间点，`date` 是用户本地日期；
- 普通查询默认排除软删除记录；
- 时间比较使用正式解析，不用字符串截取或未经证明的字典序。

# Workflow

## Phase 0 — Safety

写文件前检查：

```text
git status --short
git diff --stat
git diff -- cpp_core
```

确认用户修改、已有半成品、重复入口、CMake/测试入口和本次修改边界。不得覆盖、回滚或全量格式化无法确认归属的修改。

## Phase 1 — Focused audit

1. 从目录、CMake 和 Contract 索引定位入口；
2. 搜索目标符号的定义、调用方、测试和直接依赖；
3. 最小化读取并建立调用链：

```text
Contract/native call
→ boundary
→ command/query
→ service/workflow
→ repository/transaction
→ storage
→ NativeResult
→ tests
```

4. 对每段标记：

```text
implemented-and-used
implemented-not-wired
placeholder
missing
contract-mismatch
unverified
```

5. 仅在证据不足或出现跨层依赖时扩大范围。

## Phase 2 — Requirement decomposition

编码前形成任务表：

| 用户行为或规则 | 归属模块 | 现有入口    | 所需修改   | 依赖       | 验收场景     |
| -------------- | -------- | ----------- | ---------- | ---------- | ------------ |
| [行为]         | [模块]   | [文件/类型] | [最小修改] | [已有能力] | [可观察结果] |

同时明确：本次实现与不实现内容、规则权威位置、直接依赖、事务边界、公开 Boundary/存储影响、所需测试，以及过度耦合的最小拆分。

## Phase 3 — Feasibility gate

编码前给出一个判定：

```text
GO
DECISION_REQUIRED
BLOCKED
```

### `GO`

仅当需求可在 `cpp_core/**` 内完成，相关 Contract、错误码和基础模块真实存在，不依赖未确认模型或迁移，且可可靠验证时写代码。

### `DECISION_REQUIRED`

出现协议冲突，或方案选择会实质影响范围、兼容性、耦合和长期维护时，停止并询问用户。问题必须包含：

1. 冲突或选择点；
2. 两种可行方案；
3. 各自优缺点和影响文件；
4. 推荐方案及理由；
5. 一个明确选择问题。

提出问题后等待用户答复，不得擅自继续。

### `BLOCKED`

以下情况停止受影响实现：

- 必须修改只读目录；
- 缺少方法、schema、enum、error code 或 native 声明；
- 必需 Domain/Repository/Transaction 只是占位或不存在；
- 需要迁移但没有可靠兼容机制；
- 依赖尚未实现的 Recurrence、Habit、SQLite、AI、同步等基础；
- 无法区分用户修改；
- 环境缺失导致关键行为无法安全实现。

报告已检查内容、缺口、涉及文件、继续开发的最小前提和已产生修改。

## Phase 4 — Implementation

推荐顺序：

1. Domain（必要时）；
2. Command/Query/Result；
3. Repository/Transaction 抽象（必要时）；
4. Service/Workflow；
5. Storage 与兼容读取；
6. Boundary Contract/API；
7. Runtime 接线；
8. CMake 登记；
9. 测试；
10. 构建与 diff 检查。

每完成一个小阶段运行最相关的编译或测试。失败时先处理首个根因，不要积累大量修改后才首次验证。

# Engineering rules

- 只实现用户明确要求的行为，不顺手增加未来功能；
- 优先复用现有类型、错误、Repository、Transaction、解析器和测试基础；
- 不做无关重命名、目录迁移、全局格式化或技术栈替换；
- 不新增第三方依赖或升级工具链，除非用户明确批准；
- 新增源文件必须登记到现有 CMake 目标；
- 内部返回 `common::Result<T>`，Boundary 返回合法 `NativeResult<T>`；
- 错误码来自 `contracts/error_codes.yaml`，并区分协议、领域、I/O、损坏数据和内部错误；
- malformed input、未知 enum 和损坏数据必须明确失败，不得默认降级；
- 跨 Repository 原子操作使用已有 Transaction，并测试提交、回滚和适用的恢复；
- 不绕过 Repository 直接散写 JSON；存储格式变化必须有旧数据兼容策略；
- 时间和 ID 使用现有注入点；排序使用稳定 tie-breaker；
- 不用真实时间、sleep、全局单例或万能接口换取短期方便。

# Independent testing

先设计真实场景，再选择测试层级：

```text
Given  初始业务状态
When   用户或系统动作
Then   外部可观察结果
And    不应发生的副作用
```

## Test levels

- **Service**：规则、边界、幂等、错误传播、过滤排序、clock/ID；
- **Workflow**：多实体最终状态、提交、回滚、不相关实体不受影响；
- **Repository/Storage**：初始化、重载、UTF-8、optional、损坏数据、兼容、原子写入、恢复；
- **Boundary**：JSON、完整 `NativeResult<T>`、字段、enum、时间、未知字段、错误码、版本。

所有被改变行为至少覆盖正常路径、关键边界、输入或领域失败、Repository/Transaction 失败、重复调用，以及适用的重载/重启场景。

Event 生命周期变更还应验证：

1. complete 后 Event completed；
2. 开放 Reminder 被取消且原因为 `event_completed`；
3. sent、其他 target 和其他 Event Reminder 不受影响；
4. 任一更新失败时 Event 与 Reminder 均回滚；
5. reopen 只恢复未来且原因为 `event_completed` 的 Reminder；
6. `user_cancelled`、已过去和其他 target Reminder 不恢复；
7. 重复 complete/reopen 符合现有幂等约定；
8. Boundary 仍返回合法 `EventResponse`。

测试使用独立临时目录并清理状态。不得删除、跳过或弱化现有测试，也不得把 Mock 测试称为真实 Android/JNI 验证。

# Verification

从仓库根目录执行：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

`excellent_calendar_check` 会先构建再运行 CTest。不能只运行 `ctest` 并把旧二进制结果当作本次验证。

需要失败细节时可执行：

```powershell
ctest --test-dir cpp_core/build-ninja --output-on-failure
```

只保留首个根因和必要上下文，修复后重新构建。每条命令记录是否执行、退出状态、失败阶段、根因和未验证行为；未执行时明确标记“未执行”。

# Final review

完成后执行：

```text
git status --short
git diff --stat
git diff -- cpp_core
git diff --check
```

确认：

- 无越界源码修改或用户修改被覆盖；
- 无无关重构、调试输出、临时代码或遗漏的 CMake 登记；
- 职责清晰，无新增循环依赖、万能接口或重复规则；
- 跨实体变更经过 Workflow/Transaction；
- Contract 字段、enum 和错误码没有漂移；
- 测试覆盖成功、失败和回滚；
- 报告与实际命令结果一致。

# Codex failure guards

严禁：

- 全量读取仓库后才开始定位问题；
- 反复读取相同长文件或完整日志；
- 看到规划文档就创建整套 Engine、SQLite 或代码生成框架；
- 合并 Domain、Boundary DTO 和存储实体；
- 在 Boundary 复制 Service 规则；
- 跨 Repository 顺序写入却不使用 Transaction；
- 用默认值掩盖未知 enum、损坏数据或 malformed response；
- 用全局单例、万能接口、循环依赖或跨层访问掩盖职责问题；
- 只测 happy path，或为通过测试删除断言、跳过测试、改变既有语义；
- 声称未实际执行的构建或测试已经通过；
- 未经用户选择处理重大冲突或架构取舍；
- 执行 `git reset --hard`、`git clean`、强制 checkout、提交、推送或修改 Git 历史，除非用户明确要求。

# Completion and report

仅当需求已实现、修改未越界、可行性为 `GO`、职责与依赖正确、测试和 `excellent_calendar_check` 实际通过、最终 diff 无无关修改时，才能标记“完整完成”。否则使用：

```text
部分完成
实现完成但验证未完成
被决策阻塞
被基础能力阻塞
```

最终报告必须包含：

1. **结果状态**：完整、部分、未验证或阻塞及原因；
2. **分析与拆分**：调用链、可复用基础、模块归属、依赖与耦合处理、本次不实现内容；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：逐项说明完成度和阻塞的最小解除条件；
5. **架构与一致性**：Domain、Service、Workflow、Repository、Transaction、Boundary、错误码和兼容策略；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **局限**：只读边界、缺失基础、未验证 Android/JNI/设备行为和后续决策。