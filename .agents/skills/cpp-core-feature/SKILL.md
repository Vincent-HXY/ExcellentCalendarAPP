---
name: cpp-core-feature
description: 在 cpp_core 内实现、修改或修复 C++ Core 的领域、应用、工作流、Repository、Storage、Boundary 与相关测试。仅用于 C++ Core 单层开发；不用于修改客户端、Contract 或后端。
---

# C++ Core Feature

## 目标

在 `cpp_core/**` 内完成稳定、可测试且符合当前架构与 Contract 的核心功能。Skill 不固定当前存储格式、领域方法、类名或版本；这些动态事实必须从当前 Machine Contract、权威文档和实现确认。

## 范围

默认可修改：

```text
cpp_core/**
docs/log.md
test_note/**  # 仅记录本次实际通过的设备或模拟器验收
```

`contracts/**`、`flutter_client/**`、`cloud_backend/**` 和其他文档默认只读。构建目录可由工具生成，但不得手工修改或用旧产物证明当前源码通过。`docs/log.md` 只追加任务记录；`test_note/**` 仅在按 `AGENTS.md` 实际完成设备或模拟器验收后新增对应记录。

若需求必须改变跨层 Contract、领域真相源、客户端或后端，停止受影响实现并报告前置任务。不得在 Boundary、Storage 或测试替身中发明临时协议或第二套业务规则。

## 强制项目导航

开始规划或修改前，按顺序读取：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 解析目标行为、验收标准、事务/持久化影响、范围外内容和验证范围；
4. `docs/index.md`，据此定位当前 Domain、Accepted ADR、Active Plan、Machine Contract、存储格式、问题和验证入口；
5. 目标 C++ 公共接口、实现、直接调用链、构建登记和测试。

Source of Truth 和冲突裁决完全遵循 `AGENTS.md`。不得从 Skill、README、历史计划、旧存储目录或代码偶然行为推断当前协议和发布状态。

## 稳定边界

- Domain 保存技术无关的稳定业务语义，不依赖 Boundary、Storage 或平台实现。
- Application/Workflow 负责编排用例和跨实体一致性；跨实体原子行为使用项目当前声明的事务边界。
- Repository 定义窄持久化抽象；Storage 实现当前 active 格式及其迁移/恢复，不把 SQL、文件或 codec 细节扩散到领域层。
- Boundary 负责不可信跨层输入、Request/Response 转换、错误封装和异常隔离，不复制 Application/Domain 规则。
- Runtime/Composition 负责具体实现装配，不把测试替身接入生产。
- 跨层字段、枚举、错误、版本和返回外壳只能来自当前 Machine Contract。

## 工作流

### 1. 安全与现状

- 检查 Git 状态和 `cpp_core` diff，识别用户修改和现有半成品。
- 追踪 Contract/调用入口 → Boundary → Application/Workflow → Domain/Repository → active Storage → 返回结果 → 测试。
- 核对当前 active 存储节点、迁移链、公开接口、构建目标和生产装配；区分已接线、占位、缺失和未验证。



### 2. 可行性闸门

- `GO`：任务可在 `cpp_core/**` 内完成，所需 Contract、领域基础、Repository/Transaction 和验证入口存在。
- `DECISION_REQUIRED`：协议、兼容性、事务边界、数据迁移或职责拆分存在实质取舍。
- `BLOCKED`：必须越界、当前权威资料冲突、基础能力不存在、迁移无法安全设计或关键行为无法验证。

后两种情况暂停受影响实现，报告证据、影响、仍可继续部分和最小解除条件。

用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。


### 3. 实现

- 复用现有类型、错误、时钟、ID、Repository、Transaction 和测试设施。
- 把规则放在拥有它的层，保持依赖方向，不合并 Domain、Boundary DTO 与 Storage Entity。
- 新增源文件必须进入当前构建目标；Storage 变化必须遵循当前 active 格式和连续迁移策略。
- 严格拒绝 malformed input、未知枚举、损坏数据和不兼容版本，不用默认值或吞异常制造成功。
- 为改变的行为补充 Service/Workflow、Repository/Storage、Boundary 或兼容迁移测试中适用的层级。

## 停止条件

暂停受影响实现，当：

- Machine Contract 没有对应能力或状态不允许实现；
- 需要修改 `cpp_core/**` 之外的生产文件；
- 领域规则、ADR、Active Plan、存储 Contract 或用户目标无法按 `AGENTS.md` 直接裁决；
- 当前 active writer、迁移输入或生产 composition 无法确认；
- 无法保护用户已有修改或隔离测试数据。
## Cohesion and coupling

### Required properties

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

### Coupling smells

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

### Splitting guide

- 单实体业务规则 → 对应 Application Service；
- 跨实体原子流程 → 专用 Workflow + Transaction；
- 持久化访问 → 窄 Repository；
- JSON/文件细节 → `storage/json`；
- 跨语言转换 → Boundary；
- 稳定业务概念 → Domain；
- 多模块真实共享且稳定的能力 → `common`。

拆分只解决当前已证实的依赖问题，不借机大规模重构。若“局部最小修改”和“结构化拆分”在范围、兼容性或长期维护上存在显著取舍，列出两种方案的优缺点并询问用户，不能默认选择最简单或最宏大的方案。


## 验证纪律

C++ 必须执行项目级规定的“构建后测试”目标：

```text
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

先运行可用的定向测试，再运行上述目标。涉及 Storage、迁移、事务或 Boundary 时，覆盖成功、非法输入、失败/回滚、重载/恢复和兼容场景中适用的部分。跨语言行为只有在当前 smoke/integration 路径实际通过后才可称为已验证。

完成后检查 `cpp_core/**`、`docs/log.md` 与本次实际新增的 `test_note/**` 记录。当前 `AGENTS.md`、验收标准和验证指南要求但未执行或失败的检查标记为未验证。




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
2. **分析与拆分**：调用链、可复用基础、模块归属、依赖与耦合处理、本次不实现内容；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：逐项说明完成度和阻塞的最小解除条件；
5. **架构与一致性**：Domain、Service、Workflow、Repository、Transaction、Boundary、错误码和兼容策略；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **局限**：只读边界、缺失基础、未验证 Android/JNI/设备行为和后续决策。