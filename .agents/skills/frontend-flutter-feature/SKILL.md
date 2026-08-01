---
name: frontend-flutter-feature
description: 使用 Flutter 和 Dart 在 flutter_client 中实现或修改 Android 优先的前端功能，包括页面、组件、用户交互、页面状态、Application Layer、Dart Gateway 接口接入及相关测试。用于 Flutter 页面、表单、交互和功能开发；不用于修改 Kotlin、C++、contracts、构建工具或执行纯代码审查。

---

# Goal

在现有架构和 Contract 约束下，用 Flutter 与 Dart 实现稳定、可测试、低耦合、高内聚的客户端功能。

任务必须完成：现状定位、需求拆分、可行性判断、最小范围实现、场景测试、格式与静态分析、完整测试、Android Debug 构建、最终 diff 检查和如实报告。生成代码不等于完成；未实际执行的验证必须标记“未验证”。

# Scope and sources of truth

## Writable scope

只允许修改受版本控制的：

```text
flutter_client/lib/**
flutter_client/test/**
```

`.dart_tool/`、`build/` 等工具产物可生成，但不得手工修改或提交。

其余内容只读，包括 `AGENTS.md`、`README.md`、`contracts/**`、`android/**`、`cpp_core/**`、`pubspec.yaml`、Manifest 和工具链配置。若需求必须修改只读内容、增加依赖、配置 assets 或扩展 Native 能力，停止受影响部分并报告；不得绕过 Gateway、伪造能力或创建临时协议。

## Sources of truth

开始开发前按需核对：

1. 当前目录及父目录的 `AGENTS.md`；
2. 目标功能附近的 Dart 代码、路由、测试和命名；
3. `contracts/method_channels.yaml`、`error_codes.yaml` 及相关 schema；
4. 现有 DTO、Gateway interface、adapter、状态管理和测试替身；
5. Git 状态和用户已有修改。

先搜索标题、键名和符号，再读取相关片段，不因“需要核对”而全量读取。

跨层方法名、字段、enum、错误码、时间格式、版本和 `NativeResult<T>` 以 `contracts/` 为唯一协议真相源。用户需求、本 Skill、README、Contract 或实际代码存在实质冲突时，报告冲突、影响和方案，等待用户决定，不得猜测。

## Technical defaults

除非项目或用户另有明确要求：

- 使用 ` .\docs\DEV_ENV_INSTALL.md `中**团队统一版本**已验证的 Flutter、Dart、Android SDK、JDK、NDK 和 CMake 版本；
- Android 优先，不执行 `flutter upgrade`，不升级工具链；
- 复用现有状态管理、导航、Theme、组件、错误模型和测试方式；
- 不新增第三方 UI、图标、路由、序列化、状态管理或测试依赖；
- 只做满足需求的最小可维护修改，不做无关重构、全局格式化或未来功能。

# Context discipline

上下文是有限工作内存，仓库是外部存储。默认采用“先定位、按需加载、及时压缩”，禁止无目的全量读取大型仓库、长文件或完整日志。

## Progressive retrieval

1. **看结构**：目录、标题、路由和测试入口；
2. **搜符号**：目标 Page、Widget、Controller、Gateway、DTO、Contract、错误码的定义、调用方和测试；
3. **读局部**：只读完成当前判断所需的最小范围；
4. **追直接依赖**：UI state、Application、Gateway interface、adapter、DTO、Contract、Fake；
5. **有证据再扩展**：仅在发现跨层、共享状态、导航、生命周期或协议依赖时扩大范围；
6. **压缩结论**：记录调用链、职责、缺口和待验证项，不反复读取不变内容；
7. **最终读 diff**：实现完成后再完整检查本次 Flutter diff。

例如处理 `createReminder`，先定位定义、调用点、测试，以及直接依赖的 DTO、Contract、Gateway、Controller 和页面入口。每次扩大范围前，必须说明缺少的信息及其影响的判断，不得沿无关引用无限扩散。

完整读取仅适用于：短文件；必须整体核对的 schema、enum、错误码、状态机；或局部内容不足以判断资源所有权、异步竞态、导航和兼容性。

## Logs and working memory

- 失败时先保留首个根因及附近必要上下文，修复后重跑再处理级联错误；
- 不反复读取相同完整日志，只记录命令、退出状态、根因和未验证项；
- 不得因截断日志隐瞒关键错误；
- 分析中维护简短证据表：入口、状态、跨层能力、测试、证据位置和状态；
- 已确认且未变化的内容压缩为结论，不持续占用上下文。

# Architecture and coupling

```text
Presentation
    ↓
Application / State
    ↓
Dart Gateway Interface
    ↓
Gateway Adapter / Contract DTO
    ↓ MethodChannel / EventChannel
Android / Kotlin → JNI → C++ Core
```

遵循现有目录，不为匹配示例强制重组。

| 层级                | 负责                                         | 禁止                                         |
| ------------------- | -------------------------------------------- | -------------------------------------------- |
| Presentation        | Widget、布局、交互、导航、可见状态           | Native 调用、原始 Map、I/O、核心规则         |
| Application / State | 用户流程、状态转换、重试、并发控制、错误映射 | 具体 MethodChannel、Native 实现、C++ 规则    |
| Gateway interface   | 类型安全业务接口、测试替换点                 | Map、MethodCall、PlatformException、平台细节 |
| Adapter / DTO       | Contract 序列化、解析、版本与错误转换        | UI 状态、页面流程、重复业务规则              |
| Tests               | 用户行为和可观察结果                         | 真实数据、脆弱内部细节、伪跨层验证           |

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

# Layer invariants

## Presentation

- 展示 loading、empty、ready、error、submitting 等状态，接收交互并调用 Application 命令；
- `build()` 无副作用，不执行 I/O、Native 调用或状态写入；
- 不直接调用 MethodChannel、EventChannel、JNI、Kotlin、C++；
- 不构造或解析跨层 `Map<String, dynamic>`；
- 不复制 Contract 字段、enum、Native 规则，也不根据错误字符串决定业务行为。

## Application and state

- 编排提交、刷新、重试、取消和恢复；
- 通过窄 Gateway interface 获取能力；
- 将结果映射为不可变、可解释的页面状态；
- 防止重复提交、stale response 和旧结果覆盖新状态；
- 将类型化技术错误映射为页面失败类型，不暴露 `PlatformException` 或原始 Map。

状态必须能回答：当前展示什么、用户能做什么、哪些操作禁用、失败如何恢复、输入是否保留、旧请求是否会覆盖新结果。避免用多个冲突 bool 表达状态，优先使用项目现有 immutable state、enum、sealed type 或等价模式。

## Gateway, adapter and DTO

Gateway interface 必须类型安全、按业务能力划分、可使用 Fake/Stub，并隐藏平台细节。

只有 adapter 和 Native Contract DTO 可以调用 MethodChannel/EventChannel、转换 Contract Map、校验 `NativeResult<T>`/版本/字段/enum，以及将 Native error 映射为 Dart 类型化错误。

不得向上层暴露 `Map<String, dynamic>`、`MethodCall`、`PlatformException` 或 Kotlin/JNI 细节。未知 enum、缺失字段、错误类型、非法版本和 malformed response 必须明确失败，不得用默认值或空对象伪装成功。

# Workflow

## Phase 0 — Safety

写文件前检查：

```text
git status --short
git diff --stat
git diff -- flutter_client/lib flutter_client/test
```

识别用户已有修改、当前状态管理、可复用组件、测试组织和边界。不得覆盖、回滚或全量格式化无法确认归属的修改。

## Phase 1 — Focused audit

1. 从目录、路由、Contract 索引和测试入口定位功能；
2. 搜索目标符号的定义、调用方、测试和直接依赖；
3. 建立最小调用链：

```text
用户操作 → Page/Widget → Controller/State
→ Gateway interface → Adapter/DTO → Contract/Native
→ 可见结果 → Tests
```

4. 标记每段为 `implemented-and-used`、`implemented-not-wired`、`placeholder`、`missing`、`contract-mismatch` 或 `unverified`；
5. 仅在证据不足或发现跨层依赖时扩大范围。

## Phase 2 — Decomposition

编码前记录：

| 用户行为 | 页面状态 | 归属层 | 现有入口 | 最小修改 | 依赖   | 验收场景 |
| -------- | -------- | ------ | -------- | -------- | ------ | -------- |
| [行为]   | [状态]   | [层级] | [文件]   | [修改]   | [能力] | [结果]   |

同时明确输入、错误、权限、取消、重试、本次不实现内容、Contract/Gateway/Native 是否存在、组件职责、耦合拆分和测试层级。

## Phase 3 — Feasibility gate

编码前给出：

```text
GO
DECISION_REQUIRED
BLOCKED
```

- **GO**：可在允许目录完成，相关 Contract、DTO、Gateway、Native 能力真实存在且可验证；
- **DECISION_REQUIRED**：存在协议冲突或显著架构取舍。说明选择点、方案、优缺点、影响文件、推荐理由，并提出一个明确问题，等待用户决定；
- **BLOCKED**：必须越界、增加依赖、升级工具链，或缺少 schema、enum、error code、DTO、Gateway、Native、版本 API、可识别 Git 状态或必要环境。

阻塞报告必须包含已检查内容、具体缺口、涉及文件、继续开发的最小条件和已产生修改。

## Phase 4 — Design and implementation

编码前设计适用的页面状态、交互、输入与失败、权限与重试、异步生命周期、组件职责、Gateway 类型和测试场景。

推荐顺序：

1. 类型与 UI state；
2. Application / Controller / ViewModel；
3. Gateway interface；
4. DTO 和 adapter；
5. Presentation；
6. loading、empty、error、权限和恢复路径；
7. tests。

每完成一个小阶段运行最相关检查。失败时优先修复首个根因，避免到最后才首次验证。

# Engineering rules

## Input and Contract

用户输入按功能检查：必填与空白、长度、数值与范围、日期关系、重复规则、ID、route arguments、重复提交、弹窗取消、软键盘、返回和未保存输入。前端验证只改善体验，不能代替 Native 最终校验。

发送跨层请求前确认方法、schema、必填/nullable、`snake_case`、enum、error code、UTC datetime、date-only 和临时字段；解析时确认 `NativeResult<T>` 结构、`contract_version`、response schema、enum、时间和错误码。malformed response 必须成为明确 contract failure。

```text
datetime = 精确时间点，跨层使用 UTC
date     = 用户本地日期，不代表 UTC 时间点
```

展示 datetime 前按时区转换；不把 date-only 转为 UTC 午夜；不用字符串截取代替正式解析；不在 Presentation 重算复杂重复规则；时间测试使用现有 clock、参数或可替换抽象，并覆盖适用的时区/夏令时边界。

## Lifecycle and async

- 跨 `await` 使用 `BuildContext` 前检查 mounted；销毁后不 `setState`；
- 搜索、刷新、保存处理 stale response 和重复提交；
- 释放拥有的 controller、focus、animation、scroll、subscription、timer；
- 长期监听在销毁时取消或交给现有状态框架；
- 列表局部状态使用稳定、具业务意义的 Key；
- Widget 是否存活不得充当业务真相。

## UI, accessibility and performance

覆盖需求适用的 loading、empty、ready、error、submitting、success、permission denied、retry、disabled 和 unsaved changes。

- 复用现有 Theme、组件和文案模式，避免无理由硬编码；
- 支持常见 Android 小屏、inset、软键盘、长文本和字体放大；
- 交互元素有明确标签、状态和合理点击区域，必要时使用 `Semantics`；
- 不只用颜色表达含义；空、失败、loading 均有可见状态和恢复路径；
- 保存失败默认保留输入；
- 不在 `build()` 做昂贵计算或同步 I/O；大列表用现有惰性构建；静态 Widget 合理 `const`；
- 避免无关重建和反复创建生命周期对象；无可复现证据不做大规模性能重构。

# Independent testing

先按真实用户场景定义：

```text
Given  初始页面或业务状态
When   用户操作
Then   用户可见结果和状态变化
And    不应发生的副作用
```

所有新增或改变行为都必须有与风险匹配的测试：

- **Unit**：Application、Controller/ViewModel、状态、输入、DTO、错误、时间、Fake Gateway 流程；
- **Widget**：页面状态、用户操作、表单、提交、防重复、重试、权限、返回/取消和关键布局；
- **Gateway/Contract**：方法名、payload、nullable、enum、时间、结果、版本、缺失字段和 malformed 返回；
- **Integration**：真实 Android、MethodChannel、C++ 链路，仅在现有设施和设备可用时执行。

至少覆盖适用的：成功、输入/业务失败、可重试错误、重复提交、旧结果不覆盖新状态、失败后保留输入、未知 enum/error/version、malformed response、取消/返回。

Widget 测试使用 Fake Gateway、Fake Application service 或现有替身，不调用真实 Native；测试用户行为和可见结果，不依赖内部 Widget 结构。

测试必须隔离：不修改真实数据，不依赖顺序或真实时间，非集成测试不依赖真实 MethodChannel，清理临时状态，不用任意延时掩盖竞态，不删除/跳过/弱化测试，不把 Mock 称为跨层验证，也不为单个功能额外引入 Golden 工具链。

# Verification and final review

从 `flutter_client` 执行：

```powershell
flutter test test/<相关测试文件>
dart format <本次修改的 Dart 文件>
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

真实跨层功能且设备可用时，再执行项目现有集成测试或手工验证。仅诊断环境时使用：

```powershell
flutter --version
flutter doctor -v
flutter devices
```

不得通过升级工具链解决环境问题。每条命令记录是否执行、退出结果、失败阶段、首个根因、是否由本次修改引起和未验证行为。

完成后检查：

```text
git status --short
git diff --stat
git diff -- flutter_client/lib flutter_client/test
git diff --check
```

确认无越界、无关修改、用户修改覆盖、重复实现、调试代码、新依赖、循环依赖、大接口或跨层违规；Contract、状态、生命周期、恢复路径和测试保持一致；报告与命令结果相符。

# Failure guards

严禁：

- 先全量读取仓库再定位，或反复读取相同长文件和日志；
- Widget 直接调用 Native、解析 Map 或复制 C++ 规则；
- 创建 Contract 中不存在的方法、字段、enum 或错误码；
- 用默认值、空对象或吞异常制造虚假成功；
- 用全局单例、万能 Gateway、循环依赖或跨层访问掩盖职责问题；
- 为通过测试删除断言、跳过测试或改变既有语义；
- 声称未执行的分析、测试、构建或跨层验证已经通过；
- 未经用户选择处理重大协议冲突或架构取舍；
- 执行 `git reset --hard`、`git clean`、强制 checkout、提交、推送或修改 Git 历史，除非用户明确要求。

# Completion and report

仅当需求已实现、修改未越界、可行性为 `GO`、职责与依赖正确、格式和分析成功、相关及完整测试通过、Android Debug 构建通过、最终 diff 无无关修改时，才能标记“完整完成”。真实 Native 链路未验证时必须单独说明，不能由 Widget 或 Mock 测试替代。

否则使用：

```text
部分完成
实现完成但验证未完成
被决策阻塞
被 Contract / Native / 环境阻塞
```

最终报告包含：

1. **结果状态**：完整、部分、未验证或阻塞及原因；
2. **分析与拆分**：调用链、复用基础、状态与层级、依赖和耦合、本次不实现内容；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：按验收标准说明完成度和解除阻塞的最小条件；
5. **架构与 Contract**：状态管理、Application、Gateway、DTO、MethodChannel、错误码和协议一致性；
6. **测试与验证**：真实场景、覆盖风险、实际命令、退出结果和首个根因；
7. **App 查看方式**：入口、操作、预期状态、权限或 Native 前提；
8. **局限**：未验证设备、跨层行为、环境限制和后续必要决策。