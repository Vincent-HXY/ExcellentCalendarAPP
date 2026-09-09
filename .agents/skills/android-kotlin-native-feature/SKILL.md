---
name: android-kotlin-native-feature
description: 在 flutter_client/android 内实现或修改 Kotlin/Android 平台能力、跨层适配和相关测试。用于 MethodChannel/EventChannel、JNI 适配、通知、调度、权限和系统回调；不用于修改 Flutter、根 C++ Core、Contract 或后端。
---

# Android Kotlin Native Feature

## 目标

在现有 Contract 和架构边界内交付稳定、可测试的 Android 原生能力。Skill 不保存当前版本、具体业务方法或领域规则；这些信息必须从当前权威资料和实现读取。

## 范围

默认可修改：

```text
flutter_client/android/**
docs/log.md
test_note/**  # 仅记录本次实际通过的设备或模拟器验收
```

Flutter/Dart、根 `cpp_core/**`、`contracts/**`、`cloud_backend/**` 和其他文档默认只读。`docs/log.md` 只作为项目级强制追加记录；`test_note/**` 仅在按 `AGENTS.md` 实际完成设备验收后新增对应记录，不预写未执行环境。

不得借 Android 任务改变领域规则、扩展协议、升级工具链或把测试替身接入生产。若需求需要越界修改，停止受影响部分并报告所需上游变更。

## 强制项目导航

开始规划或修改前，按顺序读取：

1. 生效的 `AGENTS.md`；
2. `docs/architecture/overview.md`；
3. 解析目标行为、验收标准、系统副作用、范围外内容和验证矩阵；
4. `docs/index.md`，据此定位相关 Domain、Accepted ADR、Active Plan、Machine Contract、状态、问题和验证指南；
5. 目标 Kotlin/Android/JNI 代码、直接调用链、Manifest/构建入口和测试。

Source of Truth 与冲突裁决遵循 `AGENTS.md`。README、历史计划和旧实现只在 index 允许的兜底层级使用。

## 稳定边界

- Kotlin 拥有 Android 系统能力、生命周期适配和跨层桥接，不复制 C++ 或其他领域 owner 的业务规则。
- Handler/入口只做不可信输入校验、类型转换、委托和结果映射；系统执行放在职责明确、可替换测试的组件中。
- Flutter↔Kotlin 与 Kotlin↔C++ 的调用只能使用当前 Machine Contract 声明的边界。
- JNI 实现集中处理装载、类型转换、生命周期和错误隔离，不向 Handler、Receiver 或 Service 扩散底层细节。
- Android 系统状态不是领域真相源；重启、重连和重复回调必须遵循当前权威文档定义的恢复与幂等语义。
- 外部 Intent、Bundle、URI、系统回调和 Native 返回均是不可信输入。

## 工作流

### 1. 安全与调用链

- 检查 Git 状态和 Android 范围 diff，保护用户已有修改。
- 追踪最小链路：Flutter/系统入口 → Contract 解析 → Handler/Service → Android 或 JNI 能力 → 状态/事件/系统副作用 → 调用方。
- 确认线程、生命周期、所有权、权限、幂等和失败返回由哪一层负责。

### 2. 可行性闸门

- `GO`：所需 Contract 和下层能力存在，任务可在允许范围完成。
- `DECISION_REQUIRED`：协议、兼容性、权限/组件暴露或职责归属存在实质选择。
- `BLOCKED`：必须修改 Contract/Flutter/C++、缺少真实下层能力、需要未经批准的依赖/升级，或关键安全语义无法确认。

发生阻塞时列出证据、影响、已完成部分和最小解除条件；不得增加私有协议、假数据或运行时 Fake 绕过。

用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。

### 3. 实现

- 复用现有 Bridge、执行器、依赖组装、错误模型和测试设施。
- 主线程只执行必要的轻量工作；耗时 I/O、数据库、网络或 JNI 按现有线程模型调度。
- 资源、监听、回调和异步任务必须有明确所有者和清理路径。
- Android 组件、权限和导出边界只在需求确实需要时修改，并校验不可信输入。
- 对重复调用、进程重建、系统重试和并发回调实现可证明的幂等/单次完成语义。
- 为改变的行为添加与风险匹配的 JVM、instrumented、Contract adapter 或真实系统测试。


## High cohesion and low coupling

- 一个 Handler、Contract、Bridge、Scheduler 或 Service 只围绕一个清晰职责；
- 模块只依赖完成职责所需的最小接口；同一校验、错误映射或状态转换只有一个权威实现；
- Android 系统能力通过窄接口被 Handler/协调器使用；JNI 实现隐藏 `external` 方法和库加载细节；
- 不为每个函数机械创建接口，也不为未确认的未来需求搭框架。

出现以下异味时先分析拆分：

- `MainActivity` 同时处理 channel、权限、通知、Alarm 和 JNI；
- 一个 Handler 覆盖多个无关模块，或直接操作 Android API 与原始 JSON；
- Service 依赖 MethodChannel，Native Bridge 依赖 Activity；
- 同一字段校验、错误映射或状态机在 Handler、Service、JNI 多处重复；
- 全局单例持有 Activity、循环依赖、隐式共享可变状态；
- 修改一个功能牵连多个无关模块或一个文件持续膨胀。

拆分只解决已证实的问题。若“局部补丁”和“结构化拆分”在兼容性、范围、测试或长期维护上存在显著取舍，进入 `DECISION_REQUIRED`：列出两种方案、优缺点、影响文件和推荐理由，不默认选择最省事或最宏大的方案。

## 停止条件

暂停受影响实现，当：

- 当前 Machine Contract 缺失、状态不允许实现或与代码不一致；
- 领域/平台职责需要跨越现有边界；
- Manifest、依赖、SDK、ABI 或权限变更超出用户目标；
- 设备专属行为没有可验证条件，且这会改变实现方向；
- 无法保护用户已有修改。

## 验证纪律

通过 `docs/index.md` 定位当前版本和验证指南，并使用项目现有 Gradle/Flutter 入口：

- 先运行最相关的 Android 单元测试；
- 执行适用的 lint、Debug 构建和 instrumentation 测试；
- JNI 或跨语言变更执行当前 smoke test 和 ABI/打包检查；
- 通知、调度、权限、Intent 或进程生命周期等系统行为，按当前 `AGENTS.md` 和验证指南规定的设备验收范围执行；记录实际通过的环境，不自行扩大设备矩阵。

不得用任意延时、宽松断言、旧构建产物或 Mock 证明真实系统行为。完成后检查 diff/status，逐项报告命令结果、环境限制和本次要求但未完成的验证；未记录的设备环境不得宣称通过。


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
5. **架构与一致性**：MethodChannel/EventChannel、Contract、Android capability、Native Bridge/JNI、错误和线程一致性；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **局限**：只读边界、缺失基础、未验证 Android/JNI/设备行为和后续决策。