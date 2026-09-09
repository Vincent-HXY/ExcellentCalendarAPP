---
name: frontend-flutter-feature
description: 在 flutter_client/lib 与 flutter_client/test 内实现或修改 Flutter/Dart 页面、交互、状态和应用层接入。用于单层前端功能开发；不用于修改 Native、C++、Contract、构建配置或执行纯代码审查。
---

# Flutter Frontend Feature

## 目标

在现有架构和已声明能力内，交付可维护、可测试且真实接入生产组合的 Flutter 功能。Skill 只规定稳定的工作方法、范围、停止条件和验证纪律；项目状态、领域规则、方法名和版本不得从本文推断。

## 范围

默认可修改：

```text
flutter_client/lib/**
flutter_client/test/**
docs/log.md
test_note/**  # 仅记录本次实际通过的设备或模拟器验收
```

其他路径默认只读。若功能需要修改 `pubspec.yaml`、assets 配置、路由生成配置、Contract、Kotlin、C++ 或工具链，停止受影响部分并说明最小前置工作。不得用 Fake、临时方法或自造字段伪装缺失能力。

`docs/log.md` 是项目级强制记录例外，只追加本次任务记录，不重写历史。`test_note/**` 仅在按 `AGENTS.md` 实际完成设备验收后新增对应记录。

## 强制项目导航

开始规划或修改前，严格按以下顺序加载最小上下文：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 解析用户行为、验收标准、范围外内容、相关层级和验证范围；
4. `docs/index.md`，据此定位当前 Domain、Accepted ADR、Active Plan、Machine Contract、状态、问题和验证入口；
5. 目标 Flutter 代码、直接调用者/被调用者和相关测试。

Source of Truth、冲突处理和文档优先级完全遵循 `AGENTS.md`。本文不覆盖或重述领域/Contract 规则。README 只有在 index 指示或当前资料不足时才作为兜底背景。

## 稳定边界

- Presentation 负责展示、输入、导航和可见交互状态，不直接执行平台调用、持久化或核心领域规则。
- Application/State 负责编排用户流程、异步状态、重试和恢复，通过窄接口依赖能力。
- Gateway/Adapter 负责类型化边界、序列化和错误转换，不向页面扩散原始平台对象或未校验数据。
- 跨层名称、字段、枚举、错误和版本只能来自当前 Machine Contract。
- 测试替身仅用于测试；不得进入默认或 Release production composition，也不得复制下层业务规则。
- 保持现有状态管理、导航、主题和依赖注入方式；没有明确需求不新增框架、依赖或全局单例。

## 工作流

### 1. 安全与现状

- 检查 Git 状态和目标范围 diff，保护用户已有修改。
- 追踪最小调用链：用户入口 → Presentation → Application/State → Gateway/Adapter → 已声明能力 → 可见结果。
- 区分已接线、仅实现未接线、占位、缺失、协议不匹配和未验证状态。

### 2. 拆分与可行性

编码前明确：用户行为、页面状态、归属层、现有入口、最小修改、失败/恢复路径和验收测试。

只在以下判定下继续：

- `GO`：目标可在允许范围内完成，所需 Contract、Gateway 和真实下层能力存在。
- `DECISION_REQUIRED`：存在会改变协议、兼容性或职责边界的真实取舍。
- `BLOCKED`：必须越界、能力缺失、当前权威资料冲突或关键行为无法安全验证。

后两种情况报告具体证据、影响、仍可继续部分和解除条件，不创建临时兼容分支。


用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。

### 3. 实现

- 选择最小但完整的方案，复用现有模式，不做无关重构或全局格式化。
- 覆盖适用的 loading、empty、ready、error、提交中、取消和恢复状态。
- 正确处理异步生命周期、重复提交、旧响应覆盖和资源释放。
- 在不可信边界严格解析失败；不得通过默认值、空对象或吞异常制造成功。
- 为新增或改变的行为补充与风险匹配的 unit、widget 或 adapter/contract 测试。

## High cohesion and low coupling

- 一个 Widget、Controller、Gateway 或 DTO 只围绕一个清晰职责；
- 模块只依赖完成职责所需的最小接口；
- 同一校验、状态转换或错误映射只有一个权威实现；
- Presentation 映射 UI state 并转发事件；Application 依赖 Gateway interface；adapter 隐藏平台和序列化细节；
- 不为每个函数创建接口，也不为未确认的未来需求搭框架。

发现以下异味时先分析拆分：

- Widget 同时承担布局、流程、序列化和 Native 调用；
- Controller 依赖多个无关 Gateway；
- 同一规则在多层重复，或小改动牵连多个无关模块；
- Gateway 变成“大接口”，DTO 直接充当页面状态；
- 循环依赖、全局单例、隐式共享可变状态；
- 单文件混合多个独立用户流程并持续膨胀。

按现有架构拆分：视觉与交互归 Presentation；流程和状态归 Application；跨层抽象归 Gateway interface；序列化和 Native 错误归 adapter/DTO；稳定复用 Widget 放入项目现有公共位置。

拆分只解决已证实的问题，不借机大改。若“局部最小补丁”和“结构化拆分”在范围、兼容性或维护成本上存在显著取舍，列出方案、优缺点和影响文件，让用户决定后继续。

## 停止条件

出现以下任一情况，暂停受影响实现：

- 当前 Machine Contract 没有所需能力或与实际适配器不一致；
- 需要修改本 Skill 允许范围之外的生产文件；
- 领域、ADR、Active Plan、Machine Contract 或用户目标之间存在未裁决冲突；
- 方案依赖未实现的下层行为、版本升级或未经批准的新依赖；
- 无法保护或区分用户已有修改。

## 验证纪律

按照 `docs/index.md` 指向的当前验证指南和仓库实际入口，执行与改动风险相称的检查：

- 格式化本次修改的 Dart 文件；
- 运行定向测试，再运行受影响范围的回归测试；
- 执行 `flutter analyze`；
- 对进入实际 App 生产路径的变更执行适用的 Android Debug 构建；
- 涉及真实跨层行为时执行现有 smoke/integration 验证，不能用 Mock 代替。

完成后检查 Git diff/status，确认没有越界、无关修改、调试代码或遗漏文件。当前 `AGENTS.md` 和验证指南要求但未执行、失败或受环境限制的检查必须标记为未验证；不得据代码审查推断通过，也不得自行扩大设备矩阵。


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
5. **架构与一致性**：状态管理、Application、Gateway、DTO、MethodChannel、错误码和协议一致性；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **局限**：只读边界、缺失基础、未验证 Android/JNI/设备行为和后续决策。