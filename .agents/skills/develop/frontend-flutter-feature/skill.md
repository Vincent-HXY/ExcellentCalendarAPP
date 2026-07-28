---

name: frontend-flutter-feature 

description: 使用 Flutter 和 Dart 在 flutter_client 中实现或修改 Android 优先的前端功能，包括页面、组件、用户交互、页面状态、Application Layer、Dart Gateway 接口接入及相关测试。用于 Flutter 页面、表单、交互和功能开发；不用于修改 Kotlin、C++、contracts、构建工具或执行纯代码审查。

---

# Goal

根据项目现有架构、contracts 和开发要求，使用 Flutter 与 Dart 实现稳定、可测试、可维护的客户端功能。

生成代码不代表任务完成。

任务必须经过格式检查、静态分析、相关测试和 Android Debug 构建。凡是没有实际执行的验证，都必须明确标记为“未验证”。

# Sources of truth

开始开发前，依次阅读并遵守：

1. 当前目录及父目录中的 `AGENTS.md`。
2. 仓库根目录 `README.md` 中的开发环境基线和架构说明。
3. 当前功能附近的现有 Dart 代码、测试和命名习惯。
4. `contracts/method_channels.yaml`。
5. `contracts/error_codes.yaml`。
6. 与本次功能有关的 request、response、enum 和 common schema。
7. Dart 侧现有 DTO、Gateway interface 和 Gateway adapter。

跨层字段、方法名、错误码、枚举值和时间格式，以 `contracts/` 为唯一协议真相源。

当 README、contracts、实际代码或用户需求之间出现冲突时，不得自行猜测或私自创造兼容方案。停止相关实现并报告冲突位置、影响范围和所需决策。

# Technical defaults

除非项目已有明确约定或用户明确要求，否则遵守以下规则：

- 使用 README 中已经验证的 Flutter、Dart、Android SDK、JDK、NDK 和 CMake 版本。
- 禁止执行 `flutter upgrade` 或升级现有开发工具。
- 目标平台优先 Android。
- 使用项目现有的状态管理方式，不额外引入新的状态管理框架。
- 不额外引入第三方 UI、图标、路由、序列化、测试或工具依赖。
- 优先复用现有 Theme、颜色、字体、间距、组件、错误模型和导航方式。
- 优先进行最小范围修改，禁止进行与需求无关的重构。
- 仅允许修改受版本控制的以下源码目录：
  - `flutter_client/lib`
  - `flutter_client/test`
- Flutter 工具执行过程中允许生成 `.dart_tool/`、`build/` 等构建产物，但不得手动修改或提交这些生成目录。
- 如果实现必须修改 `pubspec.yaml`、assets 配置、Android Manifest、Kotlin、C++、contracts 或其他受限目录，应停止对应实现并报告阻塞条件。

# Logical architecture

本项目逻辑分层如下：

```text
Presentation Layer
    ↓
Application Layer / State Management
    ↓
Dart Gateway Interface
    ↓
Dart Gateway Adapter / Native Contract DTO
    ↓ MethodChannel / EventChannel
Android / Kotlin
    ↓ JNI
C++ Core
```

除非仓库已有不同且稳定的组织方式，否则一个 Flutter 功能通常包含以下职责：

```text
Feature
├── Presentation
│   ├── Page / View
│   ├── Reusable Widgets
│   └── Dialog / Sheet / Visual State
│
├── Application
│   ├── Use Case / Controller / ViewModel
│   └── User-flow orchestration
│
├── State
│   ├── Immutable UI state
│   └── State transition logic
│
├── Gateway Interface
│   └── Typed Dart interface
│
└── Tests
    ├── Application and state tests
    ├── Widget tests
    └── Gateway and contract tests
```

不要为了匹配该示例而强制重组已有目录。优先遵循仓库现有结构和命名。

# Architecture rules

## Presentation Layer

Presentation Layer 可以：

- 构建 Widget 树。
- 展示数据和页面状态。
- 接收点击、输入、滚动、选择和返回操作。
- 调用 Application Layer 暴露的命令。
- 处理布局、动画、主题和页面导航。
- 展示面向用户的错误信息、确认信息和 loading 状态。

Presentation Layer 不得：

- 直接调用 `MethodChannel`、`EventChannel`、JNI、Kotlin 或 C++。
- 直接构造跨层 `Map<String, dynamic>`。
- 直接解析 Native 返回的原始 Map。
- 承担核心业务规则。
- 直接管理持久化格式。
- 在 `build()` 方法中执行 I/O、跨层调用或会改变状态的副作用。
- 根据 Native 错误字符串判断业务行为。
- 复制 contracts 中已经定义的枚举或字段名称。

Widget 应尽量保持轻量，只负责将当前 UI state 映射为界面，并将用户事件转发给 Application Layer 或状态控制器。

## Application Layer

Application Layer 负责：

- 编排用户业务流程。
- 调用一个或多个 Gateway interface。
- 将 Gateway 返回结果转换为页面需要的状态。
- 控制提交、刷新、重试、取消和错误恢复流程。
- 防止重复提交和过期异步结果覆盖新状态。
- 将技术错误映射为页面可处理的失败类型。

Application Layer 不得：

- 直接依赖具体 MethodChannel 实现。
- 直接修改 Kotlin、C++ 或 SQLite 数据。
- 重新实现应由 C++ Core 负责的领域规则。
- 将原始 Native Map 或 `PlatformException` 直接暴露给 Widget。

## State Management

页面状态应明确表达实际页面阶段。

根据功能需要，从以下状态中选择适用项：

```text
initial
loading
empty
ready
editing
submitting
success
error
permissionDenied
offline
```

不得为了省事将多个互相冲突的布尔值组合成非法状态，例如：

```text
isLoading = true
isSubmitting = true
isSuccess = true
hasError = true
```

状态应尽量不可变。

每个状态变化必须能够回答：

- 当前页面展示什么？
- 用户现在可以做什么？
- 哪些操作必须禁用？
- 失败后用户如何重试？
- 用户输入是否需要保留？
- 新请求是否可能被旧请求覆盖？

## Dart Gateway Interface

Gateway interface 必须：

- 使用类型安全的 Dart 参数和返回类型。
- 按业务模块划分职责。
- 便于在测试中使用 Fake 或 Stub 实现。
- 隐藏 MethodChannel 和序列化细节。
- 只暴露 contracts 中已经存在的能力。

Gateway interface 不得暴露：

- `Map<String, dynamic>`
- `MethodCall`
- `PlatformException`
- Kotlin 或 JNI 的实现细节

## Gateway Adapter and DTO

只有 Gateway adapter 和 Native Contract DTO 可以：

- 调用 MethodChannel 或 EventChannel。
- 将类型安全对象序列化成符合 contracts 的 Map。
- 将 Native 返回数据解析成 Dart DTO。
- 校验 `NativeResult<T>`。
- 将 Native error 转换为 Dart 的类型化错误。

DTO 和 Adapter 必须严格遵守：

- contract 方法名；
- contract 字段名；
- contract enum 字符串；
- `contract_version`；
- `NativeResult<T>` 成功和失败约束；
- UTC datetime 与本地 date 的区别。

未知枚举值、缺失必填字段、字段类型错误和非法 `NativeResult` 不得静默使用默认值掩盖。

# Workflow

1. 阅读并理解用户需求。
2. 将需求划分为：
   - 用户操作；
   - 页面状态；
   - 业务规则；
   - 输入边界；
   - 错误和权限状态；
   - 跨层依赖；
   - 验收标准；
   - 本次明确不实现的内容。
3. 在修改前检查：
   - `git status`；
   - 当前相关文件；
   - 用户已有未提交修改；
   - 当前使用的状态管理方式；
   - 可复用页面、Widget、Theme 和工具类；
   - 现有测试组织方式。
4. 检查所需跨层能力是否已经存在：
   - contracts 中是否声明方法；
   - request 和 response schema 是否存在；
   - error code 是否存在；
   - Dart DTO 是否存在；
   - Gateway interface 是否存在；
   - Gateway adapter 是否已经实现；
   - Android 和 C++ 是否已经提供对应能力。
5. 如果跨层能力不完整：
   - 不得临时创造 MethodChannel 方法；
   - 不得绕过 Gateway；
   - 不得修改 Native 层；
   - 不得伪造已经可用的返回数据；
   - 应停止依赖该能力的实现并报告缺少的具体条件。
6. 在编码前设计：
   - 页面状态矩阵；
   - 用户交互流程；
   - 失败和重试流程；
   - 组件职责；
   - Application Layer 调用流程；
   - Gateway 输入和返回类型；
   - 需要新增或修改的测试。
7. 优先复用已有组件和模式，选择满足需求的最小可维护方案。
8. 按照以下顺序实现：
   1. 类型和 UI state；
   2. Application Layer 或状态控制逻辑；
   3. Gateway interface 接入；
   4. DTO 和 adapter 接入；
   5. Presentation Layer；
   6. 错误、空状态和 loading 状态；
   7. 测试。
9. 每完成一个小阶段，运行最相关的测试或静态检查。
10. 完成实现后检查：
    - 是否存在无关修改；
    - 是否重复实现已有功能；
    - 是否违反分层；
    - 是否直接操作原始 Map；
    - 是否遗漏异常页面状态；
    - 是否存在异步生命周期问题；
    - 是否需要更新测试。
11. 执行完整验证流程。
12. 汇报文件变更、功能完成情况、验证结果和未验证内容。

# Input and boundary validation

## 表单和用户输入

根据功能检查：

- 必填字段是否为空或只包含空白字符；
- 字符串长度是否合理；
- 数值是否能够解析；
- 数值是否在允许范围内；
- 日期和时间是否有效；
- 开始时间是否早于或等于结束时间；
- 重复规则是否填写完整；
- 选中的 ID 是否为空或失效；
- route arguments 是否存在且类型正确；
- 用户是否重复点击提交按钮；
- 保存期间是否允许再次提交；
- 用户取消选择器或弹窗后是否被误认为成功；
- 软键盘、返回键和页面离开行为是否正确。

前端验证主要用于改善用户体验，不能代替 C++ Core 或 Native 层的最终业务校验。

## Contract 请求验证

发送跨层请求前检查：

- 使用的 MethodChannel 方法名是否存在于 `method_channels.yaml`；
- request DTO 是否与对应 schema 匹配；
- 必填字段是否存在；
- 字段名是否使用 contract 中的 `snake_case`；
- enum 是否来自 contracts；
- datetime 是否使用 contract 规定的 UTC 格式；
- date-only 字段是否保持本地日期语义；
- nullable 字段是否按照 schema 处理；
- 没有添加未声明的临时字段。

## Contract 响应验证

解析返回值时检查：

- 返回值是否满足 `NativeResult<T>`；
- `ok == true` 时 `error` 是否为空；
- `ok == false` 时 `data` 是否为空；
- 失败时是否存在合法 error；
- `contract_version` 是否受支持；
- data 是否符合目标 response schema；
- enum 是否为已知值；
- 时间和日期字段是否能够正确解析；
- Native error code 是否存在于 `error_codes.yaml`；
- malformed response 是否转换为明确的 contract failure。

不得因为解析失败而返回一个看似正常的空对象。

## 时间规则

本项目是日历应用，时间处理属于高风险区域。

必须区分：

```text
datetime = 精确时间点，跨层使用 UTC
date     = 用户本地日期，不代表 UTC 时间点
```

遵守以下规则：

- 展示精确时间前，根据用户时区转换。
- 不要把 date-only 字段强行转换成 UTC 午夜。
- 不要使用字符串截取代替正式日期解析。
- 不要在 Presentation Layer 重新计算复杂重复规则。
- 时间相关测试不得依赖测试运行时的真实当前时间。
- 需要“当前时间”时，应通过可替换的 clock、参数或现有项目抽象注入。
- 涉及时区或夏令时边界时，应添加明确测试案例。

# Flutter lifecycle and async rules

- `build()` 必须保持无副作用。
- 不得在 `build()` 中发起 Native 调用、网络请求或状态写入。
- 跨 `await` 使用 `BuildContext` 前，必须确认对应 context 仍然 mounted。
- 异步完成后不得对已经销毁的 State 调用 `setState`。
- 页面销毁后，过期异步请求不得覆盖新页面或新请求状态。
- 搜索、刷新等可能并发发生的操作必须处理 stale response。
- 保存操作必须防止重复提交。
- 必须正确释放由当前对象拥有的资源，包括适用的：
  - `TextEditingController`
  - `FocusNode`
  - `AnimationController`
  - `ScrollController`
  - `StreamSubscription`
  - `Timer`
- 长期监听必须在销毁时取消，或由现有状态管理框架统一管理生命周期。
- 列表项需要保存身份或局部状态时，使用稳定且有业务意义的 Key。
- 不得依赖 Widget 当前存在来保存业务真相。

# UI and interaction requirements

根据本次功能覆盖适用状态：

- loading；
- empty；
- ready；
- error；
- submitting；
- success；
- permission denied；
- retry；
- disabled；
- unsaved changes。

UI 必须：

- 优先复用现有 Theme 和公共组件；
- 保持颜色、字体、间距、按钮和弹窗风格一致；
- 避免无理由硬编码颜色、字体大小和业务文案；
- 支持小屏幕和常见 Android 屏幕尺寸；
- 避免软键盘遮挡主要输入或提交按钮；
- 正确处理 `SafeArea` 和系统 inset；
- 在长文本和系统字体放大时不发生明显溢出；
- 为可交互元素提供明确标签和状态；
- 不只依靠颜色表达成功、失败、选中或重要性；
- 自定义可点击控件必须具有合理的点击区域；
- 必要时提供 `Semantics`；
- loading、失败和空状态不能只显示空白页面；
- 错误后应提供恢复路径或重试入口；
- 保存失败时，除非需求明确要求，不得丢弃用户尚未保存的输入。

# Performance rules

- 不在 `build()` 中执行昂贵计算、同步 I/O 或复杂数据转换。
- 大型列表优先使用惰性构建方式，例如现有项目采用的 builder 形式。
- 对静态 Widget 合理使用 `const`。
- 避免一个无关状态变化导致整页不必要重建。
- 避免在 Widget 树中反复创建生命周期对象。
- 不为了微小性能收益牺牲代码清晰度。
- 没有证据时不要进行大规模“性能优化”重构。
- 性能敏感页面应先通过 DevTools 或可复现数据确认问题。

# Testing requirements

所有因本次需求新增或改变的行为，都必须有与风险匹配的测试。

## Unit tests

适用于：

- Application Layer；
- Use Case；
- Controller 或 ViewModel；
- 状态转换；
- 输入验证；
- DTO 序列化与反序列化；
- Native error 映射；
- 时间和日期转换；
- Gateway Fake 下的流程编排。

至少测试适用的：

- 正常成功路径；
- 输入不合法；
- Gateway 返回业务错误；
- Gateway 返回可重试错误；
- malformed contract response；
- 重复提交；
- 旧异步结果不会覆盖新状态；
- 保存失败后用户输入得到保留。

## Widget tests

Widget 测试使用 Fake Gateway、Fake Application service 或项目现有测试替身，不调用真实 Native 层。

根据页面功能测试：

- 初始状态；
- loading 状态；
- empty 状态；
- 正常内容；
- error 状态；
- retry 操作；
- 输入和选择操作；
- 表单错误提示；
- 提交按钮启用和禁用；
- submitting 状态；
- 防止重复提交；
- 成功反馈；
- 权限拒绝状态；
- 返回或取消行为；
- 用户可见文本和主要控件；
- 小屏幕或较大字体下的关键布局。

测试用户行为和可见结果，不要过度依赖 Widget 内部实现细节。

## Gateway and contract tests

当本次修改涉及 Gateway、DTO 或 adapter 时，测试：

- MethodChannel 方法名完全正确；
- request payload 字段名和字段值正确；
- nullable 字段行为正确；
- enum 序列化正确；
- UTC datetime 和 date-only 格式正确；
- `NativeResult<T>` 成功解析；
- Native error 正确映射；
- 未知错误码的处理；
- 不支持的 contract version；
- 字段缺失；
- 字段类型错误；
- 非法或 malformed Native 返回值。

## Integration verification

当功能依赖真实 Android、MethodChannel 或 C++ 时，Widget 测试不能代替跨层验证。

如果仓库已有集成测试基础设施且允许修改对应位置，应运行相关集成测试。

如果集成测试目录不在允许修改范围内，或当前没有设备、模拟器、Android 支撑或 Native 实现：

- 不得伪造集成测试已通过；
- 不得把 Mock 测试称为真实跨层测试；
- 必须在最终报告中标记为“跨层行为未验证”；
- 明确说明所需设备、环境或下层能力。

## Test isolation

- 测试不得修改用户真实数据。
- 测试不得依赖执行顺序。
- 测试不得依赖真实当前时间。
- 测试不得依赖真实 MethodChannel，除非它明确属于集成测试。
- 测试产生的临时状态必须清理。
- 不得通过增加任意延时掩盖异步竞态。
- 不得删除、跳过或弱化现有测试来使结果通过。
- 除非项目已经使用 Golden Test，否则不要为了单个功能额外引入 Golden Test 工具链。

# Verification workflow

从 `flutter_client` 目录执行。

优先运行与本次修改最相关的测试：

```powershell
flutter test test/<相关测试文件>
```

格式化本次修改的 Dart 文件：

```powershell
dart format <本次修改的 Dart 文件>
```

检查允许修改目录中的格式：

```powershell
dart format --output=none --set-exit-if-changed lib test
```

执行静态分析：

```powershell
flutter analyze
```

执行完整 Flutter 测试：

```powershell
flutter test
```

执行 Android Debug 构建：

```powershell
flutter build apk --debug
```

如果本次功能涉及真实跨层行为，并且设备或模拟器可用，再执行项目已有的集成测试或手工验证流程。

如果需要确认环境，可执行：

```powershell
flutter --version
flutter doctor -v
flutter devices
```

不得通过升级 Flutter、Android SDK、JDK、NDK 或 CMake 来修复环境问题。

每条命令必须记录：

- 是否实际执行；
- 退出结果；
- 失败阶段；
- 失败是否由本次修改引起；
- 哪些行为仍未验证。

# Safety rules

- 禁止额外引入第三方 UI、图标、路由、状态管理或测试依赖。
- 禁止修改 Kotlin、C++、SQLite、contracts 和 Android 配置。
- 禁止修改或升级 Flutter 及现有开发工具版本。
- 禁止 Widget 直接调用 MethodChannel、EventChannel、JNI、Kotlin 或 C++。
- 禁止 Widget 直接构造或解析跨层 `Map<String, dynamic>`。
- 禁止创建 contracts 中不存在的临时 MethodChannel 方法。
- 禁止使用未在 contracts 中声明的字段、枚举值和错误码。
- 禁止把核心领域规则复制到 Flutter UI。
- 禁止吞掉异常后返回虚假的成功状态。
- 禁止将底层调试错误直接展示给用户。
- 禁止输出 token、密钥、用户隐私数据或敏感 Native payload。
- 禁止为了通过测试而删除断言、跳过测试或降低验证标准。
- 禁止删除无关文件。
- 禁止修改与需求无关的代码。
- 禁止覆盖或撤销无法确认归属的用户已有修改。
- 禁止执行 `git reset --hard`、`git clean` 或其他破坏性 Git 命令。
- 禁止在未执行测试和构建时声称任务已经完成。
- 禁止将“代码可以编译”描述为“已经编译通过”。
- 禁止在未告知用户的情况下隐瞒受限目录、环境或下层能力造成的未完成内容。

# Blocker handling

出现以下情况时，应停止受影响部分的开发：

- contracts 中不存在所需方法或 schema；
- Dart Gateway interface 不存在；
- Android 或 C++ 尚未提供所需能力；
- 必须修改 Kotlin、C++、contracts、Android Manifest 或 `pubspec.yaml`；
- 必须新增依赖；
- 当前 Flutter 版本不支持所需 API；
- 构建环境缺少必要 SDK、设备或工具；
- 用户需求和现有架构相互冲突；
- 无法区分用户已有修改与本次修改。

报告中必须说明：

1. 已完成的检查；
2. 具体阻塞点；
3. 涉及的文件或接口；
4. 缺少的 contract、Gateway 或 Native 能力；
5. 继续开发所需的最小条件；
6. 是否产生了任何修改。

应优先在写入文件前发现阻塞。

不要为了满足“撤销修改”而自动回滚无法确认归属的文件。

# Completion criteria

只有满足以下所有适用条件，任务才算完成：

- 用户需求和验收标准已经实现；
- 代码符合现有分层和 contracts；
- 没有越过允许修改的源码范围；
- 页面覆盖必要的 loading、empty、ready 和 error 状态；
- 用户输入和跨层边界得到验证；
- 相关单元测试或 Widget 测试已经添加；
- 修改文件已经正确格式化；
- `flutter analyze` 成功；
- 相关测试成功；
- 完整 `flutter test` 成功；
- `flutter build apk --debug` 成功；
- 涉及真实 Native 能力时，已完成跨层验证，或者明确标记未验证；
- 最终 diff 不包含无关修改；
- 所有未验证行为和限制均已明确报告。

如果任何必需条件没有满足，不得使用“已完成”表述。

可以使用：

```text
实现已完成，但构建未验证
实现已完成，但真实 Native 链路未验证
部分完成，受 contracts 缺失阻塞
```

# Final response format

请按照以下格式汇报：

## 1. 总结

简要说明实现了什么，以及任务是完整完成、部分完成还是存在未验证内容。

## 2. 文件修改情况

逐项列出：

- 修改文件；
- 新增文件；
- 每个文件的修改原因。

## 3. 需求完成情况

按照用户的验收标准逐项说明：

- 已完成；
- 未完成；
- 部分完成；
- 被什么条件阻塞。

## 4. 架构与 Contract

说明：

- 使用了哪个 Application Layer；
- 使用了哪个状态管理方式；
- 使用了哪个 Gateway interface；
- 使用了哪些 DTO；
- 对应哪个 MethodChannel 方法；
- 是否完全遵守现有 contracts。

## 5. 测试和验证

列出实际执行的命令及结果：

- 格式检查；
- `flutter analyze`；
- 相关测试；
- 完整 `flutter test`；
- Android Debug 构建；
- 集成测试或真机验证。

不得列出未执行的命令作为已完成结果。

## 6. 如何在 App 中查看变化

说明：

- 从哪个页面进入；
- 点击什么控件；
- 正常情况下应看到什么；
- 错误或空状态如何触发；
- 是否需要设备权限或 Native 支撑。

## 7. 局限和未验证内容

说明：

- 缺少的下层能力；
- 未覆盖的设备场景；
- 未执行的集成验证；
- 当前已知限制；
- 建议的后续工作。