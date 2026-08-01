---
name: android-kotlin-native-feature
description: 在 ExcellentCalendarAPP 的 flutter_client/android 范围内实现或修改 Kotlin/Android 原生功能，包括 MethodChannel/EventChannel、Contract 映射、JNI Bridge、通知、提醒调度、权限、系统回调、分享、桌面组件及相关测试和 ADB 真机验证。不用于修改 Flutter/Dart、根 cpp_core、contracts、后端或执行纯文档任务。

---

# Goal

在项目既有架构和跨层 Contract 约束下，用 Kotlin 实现稳定、可测试、低耦合、高内聚的 Android 原生能力。

任务必须经过：现状定位、需求拆分、可行性判断、最小可维护实现、独立场景测试、静态检查、Android Debug 构建、可用设备上的 ADB 验证、最终 diff 检查和如实报告。生成代码不等于完成；未实际执行的验证必须标记为“未验证”。

# Scope and sources of truth

## Writable scope

只允许修改受版本控制的：

```text
flutter_client/android/**
```

`build/`、`.gradle/`、`.cxx/` 等工具产物可自动生成，但不得手工修改或提交。其余目录均只读，包括 Flutter/Dart、根 `cpp_core/**`、`contracts/**`、`README.md`、`DATA_MODEL.md`、后端和文档。

本 Skill 的主要实现范围是 Kotlin、Android resources、Manifest、Android 测试和该目录内已有的 JNI/构建接线。即使路径可写，也不得借 Kotlin 任务重写根 C++ Core、复制领域规则或擅自扩展协议。

若需求必须修改只读内容，停止受影响部分并报告最小前置修改；不得创建临时 MethodChannel、私有字段或假数据绕过边界。

## Sources of truth

开始开发前按需核对：

1. 当前目录及父目录的 `AGENTS.md`；
2. `DATA_MODEL.md` 的实体职责和当前阶段决策；
3. `contracts/method_channels.yaml`：Flutter → Kotlin 的公开方法与事件流；
4. `contracts/native_calls.yaml`：Kotlin → JNI/C++ 的内部调用；
5. 相关 schema、`error_codes.yaml`、`enums.yaml` 和 `NativeResult<T>`；
6. 目标功能附近的 Kotlin、Manifest、Gradle、JNI、测试和调用方；
7. Git 状态及用户已有修改。

不同问题使用不同真相源：

- 跨层方法、字段、enum、错误码、版本和返回外壳：以 `contracts/**` 为准；
- 领域对象职责：以 `DATA_MODEL.md` 的已确认决策为准；
- 工具版本与构建基线：以根 `README.md` 为准；
- 具体目录、命名和可复用实现：以当前代码与测试为准。

用户需求、本 Skill、Contract、数据模型或实际代码存在影响正确性、兼容性或职责边界的冲突时，不得猜测。进入 `DECISION_REQUIRED` 或 `BLOCKED`，说明冲突、影响和可选方案，等待用户决定或上游补齐后再开发。

## Technical defaults

除非项目或用户另有明确要求：

- 使用 ` DEV_ENV_INSTALL.md` **团队统一版本**中已验证的 Android SDK、JDK、NDK、CMake、Gradle 与 Flutter 版本；不升级工具链；
- 复用现有 coroutine/executor、依赖组装、错误模型、日志、序列化和测试设施；
- 不新增第三方依赖、代码生成器、服务定位器或第二套 Bridge 框架；
- 不做无关重构、全局格式化、包迁移或“顺便现代化”；
- Manifest、Gradle、权限、组件或依赖变更只在当前需求确实需要时进行，并说明兼容性与安全影响；
- 只实现用户明确要求的行为，不预做 AI、云同步、微信、Widget 等未来能力。

# Context discipline

上下文是有限工作内存，仓库是外部存储。默认“先定位、按需加载、及时压缩”，禁止先全量读取大型仓库、长文件、生成目录或完整日志。

## Progressive retrieval

1. **看结构**：目标 package、入口、Manifest 组件、Gradle source set 和测试入口；
2. **搜符号**：MethodChannel 方法、Handler、Contract、Bridge、Service、Receiver、Provider、JNI 声明及测试；
3. **读局部**：只读取完成当前判断所需的最小片段；
4. **追直接依赖**：构造方、接口、调用方、schema、错误码和 Android API 封装；
5. **有证据再扩展**：仅在发现跨模块调用、生命周期、线程、权限、进程恢复或协议依赖时扩大范围；
6. **压缩结论**：记录入口、职责、调用链、缺口、风险和待验证项，不反复读取不变内容；
7. **最终读 diff**：实现完成后完整检查本次 `flutter_client/android` diff。

例如处理 `reminder.reconcile_schedule`：先搜索它在 `method_channels.yaml`、Kotlin Handler、测试和调用方中的位置；再读取其 Contract、AlarmScheduler、NativeReminderBridge 和直接依赖。只有发现状态回写、BootReceiver 或 JNI 依赖时才继续扩展。

## Logs and working memory

- 构建或测试失败时先保留首个根因及附近必要上下文；修复后重跑，再处理级联错误；
- 不反复读取相同完整日志，不因截断而隐瞒关键错误；
- 维护简短证据表：入口、所属模块、Contract、Android/JNI 依赖、测试、证据位置、状态；
- 已确认且未变化的信息压缩为结论；最终阶段再读取完整 diff 和关键命令结果。

# Architecture and dependency direction

项目主链路：

```text
Flutter Application / Dart Gateway
    ↓ MethodChannel / EventChannel
Kotlin Channel Handler / Contract Boundary
    ↓
Android Service / Scheduler / Permission / Receiver
    或 Native Bridge
    ↓ JNI
C++ Boundary / Core
```

遵循现有目录，不为匹配示例强制重组。推荐职责如下：

| 模块                                | 负责                                               | 禁止                                          |
| ----------------------------------- | -------------------------------------------------- | --------------------------------------------- |
| Activity / Plugin bootstrap         | 注册 channel、组装依赖、转发生命周期               | 业务规则、巨大 `when`、直接调度和数据解析     |
| Channel Handler / Router            | 精确分发方法、控制一次性返回、连接模块             | Android 业务实现、JNI 细节、复制 schema       |
| `bridge/contract`                   | 校验和转换 wire 数据、`NativeResult`/`NativeError` | 核心规则、系统副作用、持久化                  |
| `bridge/native`                     | 窄接口、JNI 调用、Native 结果边界                  | Flutter API、Android UI、重复规则和数据库逻辑 |
| Android capability module           | 通知、Alarm、权限、Intent、Widget、系统回调        | Flutter 原始 Map、C++ 领域规则、万能服务      |
| Receiver / Provider / Service entry | 接收系统事件并立即委托                             | 长逻辑、隐式全局状态、阻塞主线程              |
| Tests                               | 用户场景和可观察副作用                             | 真实用户数据、脆弱内部实现、伪造跨层成功      |

依赖应单向：

```text
Bootstrap → Handler → Feature interface
                    → Android implementation
                    → Native Bridge interface → JNI implementation
```

项目文档给出的 Kotlin Bridge 基线应优先复用：

```text
bridge/contract/
├── NativeResult.kt
├── NativeError.kt
├── EventContract.kt
├── ReminderContract.kt
├── RecurrenceContract.kt
└── HabitContract.kt

bridge/native/
├── NativeEventBridge.kt
├── NativeReminderBridge.kt
├── NativeNotificationBridge.kt
├── NativeCalendarCoreBridge.kt
├── JniNativeCalendarCoreBridge.kt
├── CalendarCoreStorageDirectoryResolver.kt
└── AndroidNativeBridgeFactory.kt
```

若实际代码已有不同且稳定的拆分，遵循现状；不得为匹配目录示例大规模搬迁。`NativeCalendarCoreBridge` 不应膨胀为万能接口，优先保留按业务能力划分的窄 Bridge。任何模块都不得依赖 `MainActivity`。长期对象使用 `applicationContext`；只有权限、设置页或需要 UI 的流程才持有短生命周期 `Activity`，且不得泄漏。

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

# Contract and JNI invariants

## Flutter → Kotlin boundary

- 方法名、channel 名和 event channel 必须来自 `method_channels.yaml`；不得继续使用标记为 deprecated 的方法，除非需求明确是兼容或迁移；
- 每次调用必须且只能完成一次：成功、失败或 `notImplemented`；异步路径和异常路径也不得重复回调或悬空；
- EventChannel 必须正确处理 `onListen`、`onCancel`、FlutterEngine detach 和重复订阅；EventSink 不得泄漏，初始点击等一次性事件按现有语义缓存或消费；
- 外部参数按 `Map<*, *>` 等不可信输入处理，逐字段检查必填、nullable、类型、范围、enum、版本和时间格式；禁止无保护强转和对外部值使用 `!!`；
- wire 字段保持 Contract 的 `snake_case`。Kotlin 内部属性可以使用 `camelCase`，但序列化到 Flutter 或 JNI 时必须恢复精确协议键名；
- 返回遵守 `NativeResult<T>`：成功与失败互斥，错误码来自 `error_codes.yaml`，malformed 数据明确返回 contract failure；不得用空对象、默认 enum、`false` 或吞异常伪装成功；
- 不把 stack trace、JNI 异常、设备标识、路径或敏感 payload 暴露给 Flutter。

## Kotlin → JNI/C++ boundary

- 只有 `native_calls.yaml` 已声明的调用可以进入 JNI；公开 MethodChannel 方法和内部 Native 调用不可因名称相似而混为一层；
- JNI 声明、`System.loadLibrary`、JSON/字节转换和异常捕获集中在 Native Bridge 实现，不散落到 Handler、Service 或 Receiver；
- Kotlin Contract 只做边界转换，不实现重复规则、默认提醒、冲突检测、搜索排序、数据库状态机等 C++ 核心规则；
- 阻塞或耗时 JNI 调用不得运行在主线程。复用项目现有受控 coroutine scope/executor；禁止 `GlobalScope`、主线程 `runBlocking` 和无限制线程创建；
- Native 返回值必须校验 null、类型、UTF-8/JSON、`contract_version`、`NativeResult` 互斥关系、enum 和错误码；
- JNI 异常、库加载失败和进程状态异常必须转换为稳定的项目错误，不得使 App 因可恢复输入或 Native 失败直接崩溃；
- 不在 Kotlin 缓存 C++ 指针或跨生命周期句柄，除非现有架构已定义所有权、关闭顺序和测试。

## Domain boundaries

必须保持已确认职责：

- `Reminder` 是未来待调度任务；Android AlarmScheduler 负责注册/取消系统闹钟，不重新计算业务重复规则；
- `Notification` 是投递结果；通知展示完成后按现有协议写回，不把 Notification 当提醒扫描源；
- `EventOccurrenceState` 表示重复事件某次 occurrence 状态，不把“今天完成”写成整个 Event 状态；
- `HabitCheckIn` 是习惯完成记录，Kotlin 不在 Android 层复制连续天数或完成率规则；
- `datetime` 是 UTC 精确时间点；`date` 是用户本地日期。不得把 date-only 强制转为 UTC 午夜。

# Android engineering rules

## Lifecycle, threading and resources

- 不在主线程执行文件 I/O、长 JSON 解析、网络、数据库或耗时 JNI；
- coroutine scope、callback、receiver、listener、executor 和 service connection 必须有明确所有者和取消/关闭时机；
- Activity 重建、FlutterEngine 重连、进程被杀后，不依赖内存单例保存业务真相；
- 同一请求、Alarm 或系统回调需要幂等，避免重复注册、重复投递、重复状态回写；
- 共享状态使用现有同步机制，明确线程可见性；不以 `Thread.sleep` 修复竞态；
- 捕获异常要保留可诊断根因，但日志不得泄露内容、token、用户数据或完整 Native payload。

## Notifications and alarms

仅在需求涉及这些能力时应用：

- NotificationChannel 创建应幂等，稳定 ID 不随意更名；变更重要性、声音或渠道语义时说明迁移影响；
- PendingIntent 使用稳定身份和适当的 immutable/mutable flag，更新与取消必须命中同一身份；
- 通知点击 payload、request code、notification ID 和 Reminder ID 的映射必须可追踪且避免碰撞；
- 权限拒绝、永久拒绝、系统设置返回、通知被禁用等状态必须显式处理；
- Alarm 的注册、更新、取消和触发处理必须幂等；Kotlin 只执行 Contract/C++ 给出的计划，不自行展开 recurrence；
- Boot、时区变化、系统时间变化、Doze、精确闹钟权限或 OEM 后台限制，仅在需求和现有组件支持时实现；否则在报告中列为设备/版本限制，不擅自新增 Receiver 或权限；
- 提醒触发后遵循既有顺序处理通知展示、Notification 记录与 Reminder 状态，防止崩溃重试造成双重投递。

## Permissions, intents and Android components

- 先读取当前 `minSdk`、`targetSdk`、Manifest 和现有封装；使用 `SDK_INT` 或兼容 API 处理版本差异，不通过提高 SDK 版本逃避兼容；
- 只申请当前功能必需的最小权限。新增权限、前台服务、可导出组件、exact alarm、文件或媒体访问时，说明用户体验、审核和安全影响；
- Receiver、Service、Provider、Activity 的 `exported`、intent-filter 和权限边界必须明确；外部 Intent/Bundle/URI 视为不可信输入；
- 组件入口只做解析、鉴权和委托，避免在 `onReceive` 等短生命周期回调中执行不可控长任务；
- 不清除用户数据、不修改系统设置、不静默打开敏感权限页，除非用户明确要求且流程可恢复。

## Gradle, resources and compatibility

- 优先复用现有 plugin、dependency catalog、source set、ProGuard/R8、resource 和 test 配置；
- 不升级 AGP、Gradle、Kotlin、SDK、NDK 或依赖版本；新增依赖若不是不可替代的最小条件，进入 `DECISION_REQUIRED`；
- 资源名、channel ID、action、extra key 和 component 名称遵循现有命名，避免字符串散落；
- 不手改 generated source、merged manifest、APK、AAR、`.so` 或构建缓存；
- 根据本次风险说明未覆盖的 API 等级、ABI、厂商 ROM、后台限制、字体/语言或设备形态，不把单一手机通过等同于全部兼容。

# Workflow

## Phase 0 — Safety

写文件前执行或检查：

```text
git status --short
git diff --stat
git diff -- flutter_client/android
```

识别用户已有修改、目标 package、Manifest/Gradle 状态、可复用模块和测试组织。不得覆盖、回滚、移动或全量格式化无法确认归属的修改。

## Phase 1 — Focused audit

建立最小调用链：

```text
Flutter method / 系统事件
→ Handler / Receiver / Provider
→ Contract parser
→ Android capability 或 Native Bridge
→ Android API / JNI
→ NativeResult / event stream / 可观察系统副作用
→ Tests / ADB evidence
```

将每段标记为：

```text
implemented-and-used
implemented-not-wired
placeholder
missing
contract-mismatch
deprecated
unverified
```

只在证据不足或发现跨层、生命周期、权限、线程、进程恢复依赖时扩大范围。

## Phase 2 — Decomposition

编码前记录：

| 用户/系统场景 | 入口        | 归属模块                 | Contract/Native call | 最小修改 | 风险             | 验收证据   |
| ------------- | ----------- | ------------------------ | -------------------- | -------- | ---------------- | ---------- |
| [场景]        | [方法/组件] | [Handler/Service/Bridge] | [声明]               | [文件]   | [线程/权限/兼容] | [测试/ADB] |

同时明确：输入、输出、权限、错误、重试、幂等、生命周期、线程、版本差异、本次不实现内容，以及是否存在过度依赖或需要拆分的职责。

## Phase 3 — Feasibility gate

编码前给出一个且仅一个判定：

```text
GO
DECISION_REQUIRED
BLOCKED
```

- **GO**：可在允许目录完成；所需 MethodChannel、event channel、Native call、schema、enum、错误码和下层能力真实存在；方案与现有架构一致；
- **DECISION_REQUIRED**：用户需求与本 Skill/现有架构冲突，或局部方案与长期方案存在显著取舍。说明两种方案、优缺点、影响文件和推荐理由，提出一个明确问题并等待用户决定；
- **BLOCKED**：必须修改只读目录、缺少 Contract/C++ 能力、现有代码只是占位、关键输入不明确、需要未批准的依赖/权限/工具链升级，或无法保护用户修改。

设备未连接通常不阻止实现，但会使 ADB/真实系统行为处于“未验证”。阻塞报告必须说明已检查内容、具体缺口、涉及文件、继续开发的最小条件和已产生修改。

## Phase 4 — Design and implementation

仅在 `GO` 后实现。推荐顺序：

1. 冻结场景、Contract 映射和兼容边界；
2. 定义或复用窄接口与类型化 Contract；
3. 实现 Android capability 或 Native Bridge；
4. 实现 Handler/Receiver/Provider 的最薄接线；
5. 补齐错误、权限、幂等、线程与生命周期路径；
6. 添加 unit / instrumented tests；
7. 运行最相关检查，再进行完整验证。

每完成一个小阶段运行对应测试。失败先修复首个根因，不把首次构建和测试拖到最后。

# Independent testing

先按真实使用场景定义测试，而不是反向迎合代码结构：

```text
Given  App、权限、Reminder 或进程的初始状态
When   Flutter 调用或 Android 系统事件发生
Then   返回值、通知、Alarm、状态回写或事件流符合预期
And    不发生重复投递、崩溃、泄漏、越权或错误副作用
```

所有新增或改变行为都必须有与风险匹配的测试。

## Unit tests (`app/src/test`)

适用于纯 Kotlin Contract、Handler、Coordinator、Bridge 接口和 Android API 包装的可替换逻辑。覆盖适用的：

- 成功请求与合法返回；
- 缺字段、错类型、null、未知 enum、非法版本、malformed `NativeResult`；
- Native/Android 错误映射；
- 一次且仅一次回调；
- 幂等、重复调用、并发和取消；
- UTC datetime 与本地 date；
- Fake Native Bridge / Fake Android capability 下的场景流程。

仅在项目已配置时使用 Robolectric、MockK、Mockito、Turbine 等；不得为单个功能另起测试栈。

## Instrumented tests (`app/src/androidTest`)

用于真实 Context、Manifest 组件、NotificationManager、Intent、PendingIntent、资源、权限边界或 JNI 装载。测试必须使用专用测试数据，并清理创建的通知、Alarm、文件和状态。

不稳定或会影响用户数据的系统行为，不得通过任意 sleep 或宽松断言假装稳定；应使用可观察条件、系统查询或明确标记手工验证。

## ADB device verification

有 `device` 状态的真机或模拟器时必须验证本次真实场景。先执行：

```powershell
adb devices -l
```

记录并在报告中脱敏：厂商、型号、Android 版本、API level、ABI。根据功能执行最小验证组合：

```powershell
adb -s <serial> shell getprop ro.product.manufacturer
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
adb -s <serial> shell getprop ro.build.version.sdk
adb -s <serial> shell getprop ro.product.cpu.abilist
```

安装并启动实际构建出的 Debug APK；applicationId、Activity 和 APK 路径从构建配置或输出中读取，不得猜测。验证前清理 logcat，复现场景后只提取应用进程、`AndroidRuntime` 和首个根因附近日志。按需使用：

```powershell
adb -s <serial> install -r <debug-apk-path>
adb -s <serial> logcat -c
adb -s <serial> shell pidof <applicationId>
adb -s <serial> logcat --pid <pid> -d -v threadtime
adb -s <serial> shell dumpsys notification | Select-String <applicationId>
adb -s <serial> shell dumpsys alarm | Select-String <applicationId>
```

ADB 验证至少记录：操作步骤、可见结果、系统副作用、关键日志、是否崩溃、是否重复触发。不得执行 `pm clear`、删除真实文件或修改系统权限/设置，除非用户明确授权。

若设备未连接、`unauthorized`、权限不可授予或 OEM 行为无法复现，报告“设备验证未完成”及最小重试条件，不把单元测试替代为真机结论。

# Verification and final review

从 `flutter_client/android` 使用项目现有 Gradle Wrapper。先运行最相关测试，再依次执行适用项：

```powershell
.\gradlew.bat :app:testDebugUnitTest
.\gradlew.bat :app:lintDebug
.\gradlew.bat :app:assembleDebug
```

若已有对应测试与设备：

```powershell
.\gradlew.bat :app:connectedDebugAndroidTest
```

若项目已配置 ktlint、detekt 或特定测试任务，运行现有任务；不得自行安装插件。需要验证 Flutter 集成构建时，从 `flutter_client` 执行：

```powershell
flutter build apk --debug
```

命令失败时只在需要定位根因时增加 `--stacktrace` 或 `--info`，优先分析首个错误。不得通过升级工具链或删除构建配置解决失败。

每条命令记录：是否执行、退出结果、首个根因、是否由本次修改引起，以及仍未验证的行为。

完成后检查：

```text
git status --short
git diff --stat
git diff -- flutter_client/android
git diff --check
```

确认：无越界和无关修改；未覆盖用户代码；无 generated 文件；无调试代码、敏感日志、新依赖或工具链升级；Contract、线程、生命周期、权限、组件导出、幂等、错误和测试一致；最终报告与实际命令结果相符。

# Failure guards

严禁：

- 先全量读取仓库、生成目录或重复读取长日志；
- 在 `MainActivity`、Handler、Receiver 中堆叠业务和系统实现；
- 创建 Contract 中不存在的方法、字段、enum、错误码或事件流；
- 调用 `native_calls.yaml` 未声明的 JNI 能力；
- 在 Kotlin 重复 C++ 核心规则，或把 Android 系统规则塞进 C++ Contract；
- 用默认值、空对象、吞异常或 `result.error`/`NativeResult` 混用制造虚假成功；
- 主线程阻塞、`GlobalScope`、不受控线程、Activity 泄漏、重复回调；
- 无需求地新增权限、Receiver、Service、Provider、依赖或公共框架；
- 为通过测试删除断言、跳过测试、降低语义或使用任意延时掩盖竞态；
- 声称未执行的测试、构建、JNI、通知、Alarm 或真机验证已经通过；
- 执行 `git reset --hard`、`git clean`、强制 checkout、提交、推送或修改 Git 历史，除非用户明确要求。

# Completion and report

仅当需求已实现、修改未越界、可行性为 `GO`、职责和依赖正确、相关测试/静态检查/Debug 构建通过、最终 diff 无无关修改，并完成适用的真实设备验证时，才能标记“完整完成”。

否则使用准确状态：

```text
部分完成
实现完成但构建未验证
实现完成但设备/JNI/系统行为未验证
被决策阻塞
被 Contract / C++ / 环境阻塞
```

最终报告包含：

1. **结果状态**：完整、部分、未验证或阻塞及原因；
2. **分析与拆分**：最小调用链、模块职责、复用基础、依赖方向、取舍和本次不实现内容；
3. **文件变更**：修改、新增、删除文件及原因；
4. **需求完成情况**：按用户场景/验收标准逐项说明，含解除阻塞的最小条件；
5. **架构与 Contract**：MethodChannel/EventChannel、Contract、Android capability、Native Bridge/JNI、错误和线程一致性；
6. **测试与构建**：场景设计、实际命令、退出结果、首个根因和覆盖风险；
7. **ADB 验证**：设备信息（序列号脱敏）、操作步骤、可见结果、dumpsys/logcat 证据；
8. **兼容性与局限**：未覆盖的 API level、ABI、厂商 ROM、后台限制、权限、进程恢复和未验证内容。