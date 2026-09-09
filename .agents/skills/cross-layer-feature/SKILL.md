---
name: cross-layer-feature
description: 整合 Flutter、Kotlin/Android、JNI、C++ Core 与当前持久化层的既有代码，或实现单一、小规模的端到端功能。用于跨层接线和协议链路修复；不用于大规模重构、多个独立业务模块、Contract 设计或纯代码审查。
---

# Cross-layer Feature

## 目标

在已有 Contract 和下层能力基础上，完成一个边界清晰、可验证的端到端闭环。Skill 不保存当前方法、字段、存储版本或领域规则，只规定跨层整合方法、范围、停止条件和验证纪律。

## 范围

按用户目标可修改直接相关的：

```text
flutter_client/lib/**
flutter_client/test/**
flutter_client/android/**
cpp_core/**
docs/log.md
test_note/**  # 仅记录本次实际通过的设备或模拟器验收
```

`contracts/**`、Domain/ADR/Plan、根文档和 `cloud_backend/**` 默认只读；`docs/log.md` 只追加任务记录，`test_note/**` 仅在按 `AGENTS.md` 实际完成设备验收后新增对应记录。若端到端功能需要改变 Contract、领域真相源或后端协议，停止并拆出相应前置任务，不得临时接线。

## 强制项目导航

开始规划或修改前，按顺序读取：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 解析单一用户闭环、验收标准、涉及层级、范围外内容、开发顺序和验证范围；
4. `docs/index.md`，据此定位当前 Domain、Accepted ADR、Active Plan、Machine Contract、状态、问题和验证入口；
5. 各受影响层的公开接口、直接调用链、生产 composition 和测试。

Source of Truth 与冲突裁决遵循 `AGENTS.md`。README、历史计划和代码偶然行为只作兜底证据，不能覆盖当前 Contract 或领域定义。

## 适用性闸门

适用：

- 单一功能需要连接两个或以上现有层；
- 各层已分别实现，需要统一 production 接线；
- 已声明协议在语言映射、错误处理或调用序列上不一致；
- 小规模跨层缺口可以在一次交付中完整闭环。

不适用并应停止拆分：

- 必须设计或修改 Contract、Domain、ADR 或大规模数据迁移；
- 缺少关键下层能力或当前 Machine Contract 不允许实现；
- 涉及多个可独立交付的业务模块、完整同步/认证系统或核心架构重建；
- 单层工作已明显占主体，应改用对应单层 Skill；
- 用户只要求审查或设计。

## 稳定边界

- Presentation 负责可见交互；Application 负责用户流程；Gateway/Adapter 负责类型化协议映射；Kotlin 负责 Android 系统能力和桥接；C++ 拥有其领域/Application/Storage 规则。
- 跨层调用必须经过当前 Machine Contract 和公开适配边界，不直接访问另一层私有实现。
- 业务规则只存在于权威 owner；其他层只做输入校验、编排、平台执行或展示。
- Domain、Contract DTO、平台模型与 Storage Entity 不合并为万能模型。
- 测试 Fake 可以隔离层级，但不得进入 production composition 或伪造未实现行为。

## 工作流

### 1. 冻结闭环与调用链

- 检查 Git 状态，按文件和层级识别用户已有修改。
- 从用户入口向下、从持久化/系统副作用向上追踪同一条链：入口 → Application → Gateway/Contract → Kotlin/JNI → C++/Storage（按实际适用）→ 返回/事件 → 可见结果。
- 对每段标记已接线、未接线、占位、缺失、协议不匹配或未验证。
- 明确每层的输入、输出、错误、线程/生命周期、数据所有权和测试入口。

### 2. 可行性结论

- `GO`：已有 Contract 和基础能力足够，所有必要层可在本次范围闭环。
- `DECISION_REQUIRED`：存在会改变职责、兼容性或 production composition 的实质取舍。
- `BLOCKED`：Contract/基础能力缺失、必须越界或任务规模超过本 Skill。

未达到 `GO` 时不要留下表面可用的半链路；报告拆分顺序、依赖和最小解除条件。


用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。

### 3. 实施与整合

- 按依赖方向完成最小修改，先保证下层真实能力和边界映射，再接 Application/Presentation。
- 在每个不可信边界校验类型、版本、错误和生命周期；不吞错、不伪造成功。
- 保留层级隔离和可替换接口，删除或隔离仅用于开发预览的运行时 Fake。
- 为每个改变的层补充本层测试，并增加至少一个覆盖真实跨层路径的适用验证。
- 多人修改按最终工作树状态整合；不覆盖归属不明的改动，不以任一分支的假设代替当前权威资料。

## 停止条件

暂停受影响实现，当：

- 当前 Machine Contract、Domain、ADR 或 Active Plan 发生未闭合冲突；
- 需要改动受保护真相源或引入新依赖/工具链；
- 任一关键层只有占位或 Fake，无法形成真实闭环；
- 变更需要大规模重构、跨多个业务模块或新建核心架构；
- 无法区分并保护用户已有修改。

## 验证纪律

通过 `docs/index.md` 定位当前验证指南和各层入口：

- 运行每个受影响层的定向测试与必要回归；
- C++ 变更执行项目规定的 build-after-test 目标；
- Flutter/Android 变更执行适用的分析、单元测试、lint 和 Debug 构建；
- 跨 Flutter/Kotlin/JNI/C++ 时执行当前完整 smoke test；
- Storage、迁移或真实系统副作用按当前 Contract 和环境执行集成/设备验证。

独立层测试通过只证明对应层，不证明 production 闭环。当前 `AGENTS.md`、验收标准和验证指南要求但未执行的跨层、设备、ABI、恢复或失败路径必须明确列出；不要求的设备矩阵不得自行升级为阻塞项。

## 交付

报告结果、完整调用链、各层职责和文件变更、验收标准、实际测试/构建/smoke 证据、未验证项、阻塞和后续拆分，并追加 `docs/log.md`。
