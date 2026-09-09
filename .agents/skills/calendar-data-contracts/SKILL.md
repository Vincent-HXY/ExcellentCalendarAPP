---
name: calendar-data-contracts
description: 设计、审查或实施 ExcellentCalendarAPP 的领域数据、跨层 Contract、语言映射、持久化格式与迁移。用于实体、字段、枚举、Schema、协议、DTO、Repository 和兼容性变更；不用于普通 UI 或纯平台功能。
---

# Calendar Data Contracts

## 目标

让领域语义、Machine Contract、各语言边界映射、当前持久化格式、迁移链和验证证据形成一致闭环。Skill 只规定数据变更的方法和安全门禁，不保存任何当前字段、版本、存储 writer 或具体领域生命周期副本。

## 范围

本 Skill 可用于只读设计/审查，也可在用户明确要求实现时修改数据变更实际涉及的层，包括：

- 当前领域文档和 Accepted ADR；
- `contracts/**` 中相关 Machine Contract；
- Dart/Kotlin/C++ 的边界模型、映射和适配器；
- Repository、当前持久化格式、迁移、导入导出或备份格式；
- 直接相关的契约、迁移、回归和集成测试；
- `docs/log.md`（只追加记录）。
- `test_note/**`（仅在按 `AGENTS.md` 实际完成设备或模拟器验收后记录通过环境）。

用户只要求分析或设计时不修改生产代码。实现任务也不得顺带修改普通页面、视觉样式、无关平台行为或未授权模块。

## 强制项目导航

开始工作前，按顺序读取：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 明确目标语义、验收标准、版本域、兼容边界、范围外内容和验证范围；
4. `docs/index.md`，据此定位目标 Domain、Accepted ADR、Active Plan、Machine Contract、当前存储格式、状态、问题和验证入口；
5. 所有直接受影响的 reader、writer、mapping、migration、fixture 和测试。

Source of Truth 和冲突裁决严格遵循 `AGENTS.md`：任务未明确改变真相源时，以当前 Machine Contract/Schema 为最高优先级；任务明确要求改变它时，以验收标准定义目标状态，并同步修订必要真相源和迁移证据。README 和历史文档不能覆盖当前定义。

## 稳定的数据边界

- Domain 定义业务含义和不变量；Machine Contract 定义跨层 wire format；持久化 Contract/migration 定义存储解释；语言实现只提供映射和落地证据。
- Domain Model、Request/Response、Storage Entity 和 View Model 保持职责分离，不用一个对象覆盖全部边界。
- 明确字段含义、类型、单位、必填/可空、缺失/default、身份、引用、排序和错误语义。
- 时间点、本地日期、时区、区间、重复和 occurrence 的具体规则只从当前 Domain/ADR/Contract 读取，不在 Skill 中重新定义。
- 事实、派生数据、缓存、同步状态和投递日志必须区分；持久化派生值时要有失效和重建策略。
- 未知字段/枚举、malformed 数据和不兼容版本必须按当前 Contract 明确处理，不以空对象或默认值伪装兼容。

## 工作流

### 1. 建立影响闭包

定位并列出：

```text
目标语义/Contract
→ 所有生产 reader/writer
→ Dart/Kotlin/JNI/C++ 映射
→ Repository/Storage/Migration
→ 导入导出/备份/同步等消费者
→ fixture 与测试
```

对每层记录当前语义、目标变化、兼容策略和验证方式。小改动可以压缩记录，但不得遗漏真实消费者。

### 2. 分类与可行性

区分新增、兼容扩展、breaking change、迁移、纯实现修复和派生数据变化。

- `GO`：目标与版本/迁移策略明确，受影响层可完整同步并验证。
- `DECISION_REQUIRED`：身份、所有权、时间、兼容、迁移、幂等或失败恢复存在多种会改变结果的方案。
- `BLOCKED`：真相源冲突未闭合、历史数据无法安全解释、必须层未授权/缺失或迁移可能造成不可恢复的数据损失。

未达到 `GO` 时，只继续不受影响的审计或测试工作，并报告最小决策/解除条件。

### 3. 设计与实施

- 先定义目标语义、不变量、版本域、reader/writer 兼容矩阵、迁移和回滚/恢复，再修改实现。
- 按依赖关系更新权威定义和消费者；最终状态必须在同一交付中闭环，不允许永久半升级。
- breaking change 必须明确旧数据、旧 reader、新 writer、升级顺序、回退边界和失败恢复。
- 持久化变化只依据当前 active storage contract；不得从目录名或旧实现推断 live writer。
- 跨层名称、字段、枚举、错误和版本必须由 Machine Contract 统一声明。
- 不修改已发布的历史 migration；使用连续、可重复验证的新迁移步骤。


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

## 停止条件

暂停受影响实现，当：

- Domain、ADR、Active Plan、Machine Contract、Storage Contract 和用户目标之间存在未闭合冲突；
- 无法判断旧值、旧版本、身份、时区或历史数据的安全解释；
- breaking change 缺少兼容矩阵、迁移、升级顺序或恢复策略；
- 需要修改未获用户授权的层或依赖尚未实现的消费者；
- 无法保护现有用户数据或用户未提交修改。

## 验证纪律

按 `docs/index.md` 定位当前验证入口，执行与改动适配的检查：

- Machine Contract/Schema 引用、枚举、错误和 capability 状态校验；
- 各语言 serialization/deserialization、边界失败和跨层 fixture 一致性；
- 当前 active Storage、相邻迁移、最旧支持输入、重复执行、回滚/恢复和数据保留；
- Repository/Workflow 的事务、并发、幂等、软删除和引用完整性；
- 真实跨层 smoke/integration 与受影响模块构建。

Mock、Schema 解析或单层编译不能单独证明完整跨层行为。当前 `AGENTS.md`、验收标准和验证指南要求的历史 fixture、真实下层、设备或构建环境缺失时，标记对应验证未完成；不自行扩大设备矩阵。


## 完成标准与交付报告

仅当需求已实现、修改未越界、可行性为 `GO`、职责与依赖正确、测试和 `excellent_calendar_check` 实际通过、最终 diff 无无关修改时，才能标记“完整完成”。否则使用：

```text
部分完成
实现完成但验证未完成
被决策阻塞
被基础能力阻塞
```

报告结果、调用链和职责、文件变更、Contract/存储/兼容影响、实际测试与构建结果、未验证项和风险，并追加 `docs/log.md`。

最终报告必须包含：

1. **结果状态**：完整、部分、未验证或阻塞及原因；
2. 数据设计：实体、关系、不变量和 `.\docs\domains\` 变化；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：逐项说明完成度和阻塞的最小解除条件；
5. 跨层影响：Contract、Dart、Kotlin/JNI、C++、Storage 的修改矩阵；
6. 未验证与风险：说明缺少的 fixture、设备、环境或后续决策。

只有所有适用层已同步、历史迁移已测试、关键验证已通过且 diff 无无关修改时，才使用“已完成且验证通过”。
