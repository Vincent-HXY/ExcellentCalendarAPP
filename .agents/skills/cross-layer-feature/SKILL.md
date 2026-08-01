---
name: cross-layer-feature
description: 在 ExcellentCalendarAPP 中整合 Flutter/Dart、Kotlin/Android、JNI、C++ Core 与 SQLite 的既有代码，或实现单一、小规模的端到端功能。用于跨层联调、多人代码拼接、修复协议链路和小型全栈开发；开始前必须完成架构盘点、逐层拆解与可行性闸门。若需要修改 contracts、docs、根 README，缺少既有协议或关键下层基础，或需要大规模重构、跨多个独立业务模块、新建核心架构，则停止开发并报告拆分建议。不用于单层大型功能或纯代码审查。
compatibility: 面向 ExcellentCalendarAPP；需要访问完整 Git 仓库及 README 中约定的 Flutter、Android、JDK、NDK、CMake、C++ 和测试环境。
metadata:
  version: "1.0"

---

# 目标

贯穿并连接项目已有的 Flutter、Kotlin、JNI、C++ 与 SQLite 实现，完成一个可验证的用户闭环。

本 Skill 的完成标准不是“代码已生成”，而是：

1. 已理解现有架构与实现状态；
2. 已把需求分配到正确层和正确模块；
3. 已确认现有基础足以完成整个闭环；
4. 已完成最小范围实现与跨层连接；
5. 已从真实使用场景独立设计并执行测试；
6. 已如实报告完成度、文件变更、测试结果和限制。

# 适用范围

使用本 Skill：

- 一个需求需要同时修改或连接至少两个层；
- 多名程序员分别提交了 Flutter、Kotlin、JNI、C++、数据库代码，需要统一接线；
- 已有跨层功能字段、方法、错误或序列化不一致，需要定位并修复；
- 实现单一、边界清晰、规模较小的端到端功能；
- 验证 Flutter → Kotlin → JNI → C++ → SQLite → 返回链路。

不要使用本 Skill：

- 只涉及一个层的大型功能；
- 大规模 UI 重做、核心引擎重构、数据库体系重建、同步系统、认证系统或微信完整接入；
- 纯架构讨论、纯代码审查或仅编写文档；
- 需求包含多个可独立交付的业务功能。

单层大型任务应拆给对应 Flutter、Android、C++、数据库或协议负责人。

# 不可违反的边界

## 受保护内容

不得修改、移动、删除或自动格式化：

- 仓库根目录 `docs/**`；
- 仓库根目录 `README.md` 或 `readme.md`；
- 仓库根目录 `contracts/**`。

路径判断按 Windows 大小写不敏感语义执行。上述内容只读。

`DATA_MODEL.md` 默认作为只读领域依据；除非用户明确要求修改它，否则不要改动。

如果完成需求必须修改受保护内容，立即停止开发，报告所需修改及其原因，不得绕过协议临时接线。

## 修改原则

- 只实现用户明确提出的行为，不补做“以后可能需要”的能力。
- 优先最小修改；禁止顺手重构、统一风格或替换技术栈。
- 优先复用现有模块、类型、错误体系、状态管理和测试基础设施。
- 不为单一调用创建通用框架、代码生成器、服务定位器或额外抽象层。
- 默认不新增第三方依赖；确实不可替代时，先确认它是完成当前需求的最小条件，并报告影响。
- 不升级 Flutter、Android Studio、SDK、JDK、NDK、CMake、Gradle 或其他工具链。
- 不覆盖、回滚或整理无法确认归属的用户修改。
- 禁止 `git reset --hard`、`git clean`、强制 checkout 等破坏性命令。
- 不提交、推送、合并分支或修改 Git 历史，除非用户明确要求。

# 项目真相源

开始任务后按顺序读取：

1. 当前目录及父目录中的 `AGENTS.md`；
2. 根 `README.md` 的环境基线、架构和验证命令；
3. `DATA_MODEL.md` 的实体职责、关系和当前阶段决策；
4. `contracts/method_channels.yaml`；
5. `contracts/native_calls.yaml`；
6. 与任务可能相关 request、response、common schema、枚举和错误码；
7. 实际 Flutter、Kotlin、JNI、C++、Storage 与测试代码；
8. 构建文件和 CI 配置中已存在的命令。

优先级：

```text
用户明确需求
  > 受保护 contracts 的跨层协议
  > 已确认领域模型决策
  > 当前可运行代码与测试
  > README 的目标架构
  > 推测
```

出现冲突时不得自行选择一个版本继续开发。记录冲突的文件、字段或方法，判断影响；若冲突影响正确性或兼容性，停止。

# 项目关键约定

必须保持以下职责：

```text
Flutter Presentation
  页面、输入、展示、loading、错误和交互
        ↓
Flutter Application / State
  用户业务流程编排与页面状态
        ↓
Dart Gateway / DTO / MethodChannel Adapter
  类型安全接口、Contract 序列化与错误转换
        ↓
Kotlin Handler / Android Service
  MethodChannel 接入、权限、通知、AlarmManager、系统回调等 Android 能力
        ↓ JNI（需要 C++ 时）
C++ Boundary
  Contract 与领域对象转换
        ↓
C++ Domain / Engine
  核心规则、搜索、重复、提醒计算、业务校验
        ↓
Storage Repository
  统一持久化访问与 SQL
        ↓
SQLite
```

跨 Flutter 与 Kotlin 的入口必须存在于 `method_channels.yaml`。

Kotlin 调用 C++ 的入口必须存在于 `native_calls.yaml`。Kotlin 自己完成的 Android 系统能力可以只有 MethodChannel 声明，不要求虚构 JNI 调用；C++ 内部能力也不要求直接暴露给 Flutter。

所有跨层方法名、字段、枚举、错误码、时间格式、版本和 `NativeResult<T>` 结构以 `contracts/` 为准。不得用临时字段、另一套方法名或自由扩散的原始 Map 绕过协议。

# 领域 Gotchas

- `Reminder` 是未来待执行的提醒任务；`Notification` 是投递后的结果日志。提醒扫描入口是 `Reminder`，不是 `Notification`。
- `Event.status` 表示整个事件或重复系列生命周期；重复事件某次完成、跳过或取消使用 `EventOccurrenceState`。
- `Habit` 保存习惯定义；按日行为与统计来源是 `HabitCheckIn`。
- 精确时间 `datetime` 跨层使用 ISO 8601 UTC；`date` 表示用户本地日期，不能当作 UTC 午夜。
- 软删除实体的普通查询默认排除 `deleted_at` 非空记录。
- 当前阶段以本地能力为先。AI、云同步、云端投送等预留模型不等于已有可用实现。
- C++ Domain Model、跨层 Contract DTO 和 SQLite Entity 不得合并成一个万能模型。

# 第一阶段：架构盘点

任何写入前必须完成以下检查。

## 1. 仓库与修改状态

执行并阅读：

```text
git status --short
git diff --stat
git diff -- <相关路径>
```

确认：

- 用户已有未提交修改；
- 每层实际目录和构建入口；
- 相关测试位置；
- 目标功能是否已有半成品、重复实现或废弃入口；
- 当前分支是否能区分本次修改。

无法区分已有修改归属时，不覆盖该区域；若绕不开，停止并报告。

## 2. 垂直调用链

从用户入口开始向下追踪，再从存储或系统能力向上追踪返回值。至少记录：

```text
页面/入口
→ Application/State
→ Dart Gateway 与 DTO
→ MethodChannel 方法
→ Kotlin Handler/Service
→ JNI 函数（如适用）
→ C++ Boundary/Engine
→ Repository/SQLite（如适用）
→ NativeResult/事件流返回
```

对每一段标记：

- 已实现且被使用；
- 已实现但未接线；
- 仅有接口或占位；
- 缺失；
- 与 Contract 不一致；
- 无法验证。

不要把 README 中的规划目录当成实际实现。

# 第二阶段：需求拆层

在编码前输出内部任务表；必要时向用户展示关键结论。

| 用户行为/规则 | 归属层                         | 具体模块或现有文件 | 跨层入口   | 依赖       | 验收场景     |
| ------------- | ------------------------------ | ------------------ | ---------- | ---------- | ------------ |
| [行为]        | Flutter/Kotlin/JNI/C++/Storage | [定位结果]         | [已有方法] | [已有能力] | [可观察结果] |

使用以下判断：

- 页面显示、按钮状态、表单错误、弹窗、loading：Flutter Presentation / Controller。
- 创建、删除、确认、刷新等用户业务流程：Flutter Application Layer。
- 重复展开、提醒合法性、冲突、搜索排序等核心规则：C++ Domain / Engine。
- 权限、通知、AlarmManager、Widget、分享 Intent、微信 SDK：Kotlin Android Layer。
- MethodChannel、JNI、JSON/DTO、错误转换：Gateway / Boundary Adapter。
- SQL、事务、迁移和持久化映射：Storage Repository；其他 Engine 不直接散写 SQL。

一个规则只保留一个权威实现。前端可做体验性预校验，但不能复制 C++ 的最终领域规则。

# 第三阶段：可行性闸门

完成拆层后，必须给出一个且仅一个判定：

```text
GO                 可以完成整个小型闭环
BLOCKED            基础、协议、环境或需求不足，停止
SPECIALIST_SPLIT   修改规模或风险过大，停止并拆给专业负责人
```

## GO 条件

只有同时满足以下条件才可写代码：

- 需求是一个单一、可独立验收的用户目标；
- 所需跨层方法、schema、枚举和错误码均已在受保护 Contract 中声明；
- 相关层已有可复用的基本入口、构建方式和测试方式；
- 不需要改变核心架构、公共协议或多个既有业务流程；
- 可以在当前仓库和环境中验证完整链路，或明确存在可接受的设备级验证边界；
- 修改范围可局部完成，不依赖猜测未来设计。

## BLOCKED 条件

出现任一情况立即停止，且原则上不产生代码修改：

- 必须修改 `contracts/**`、`docs/**` 或根 README；
- 用户需求与本skill流程环节和要求出现矛盾，需待用户确定怎么样解决矛盾；
- Contract 缺少所需方法、字段、枚举、错误码或版本约定；
- README、DATA_MODEL、Contract 和实际代码存在影响正确性的冲突；
- 必需的下层能力只是占位、Mock 或根本不存在；
- 数据持久化需要迁移，但项目没有可靠迁移机制或兼容策略；
- 关键需求含义不明确，不同理解会改变数据模型、协议或架构；
- 环境、密钥、设备、SDK 或权限缺失导致无法安全实现；
- 无法保护用户已有修改。

报告最小前置任务、责任层、建议接口和完成后如何重新开始；不要临时伪造数据让上层看似可用。

## SPECIALIST_SPLIT 条件

出现任一情况终止全栈开发，并按层拆分任务：

- 同时包含多个独立用户流程；
- 需要重做公共状态管理、Bridge、JNI 框架、Repository 或构建系统；
- 需要新增或重构核心领域模型、复杂多表迁移或大范围历史数据兼容；
- 修改多个公共接口并影响多个已有功能；
- 涉及完整认证、云同步冲突、微信平台接入、加密密钥体系或后台长期任务架构；
- 需要广泛修改现有代码才能“塞进”当前功能；
- 无法由一次独立端到端测试明确覆盖风险。

拆分报告至少给出 Flutter、Kotlin、C++/Storage、Contract/数据负责人各自的输入、输出、验收和依赖顺序。

# 第四阶段：实现顺序

仅在判定为 `GO` 后执行。

默认按照依赖从下到上实现；已有层只做必要接线：

1. 冻结用户验收场景与 Contract 映射；
2. C++ Domain / Engine 与 Storage（若需求涉及）；
3. C++ Boundary 与 JNI Adapter；
4. Kotlin Handler、Service 或 Android 系统能力；
5. Dart DTO、Gateway Adapter 与类型化错误；
6. Flutter Application / State；
7. Flutter Presentation；
8. 跨层集成与回归修复。

若任务的最低依赖是 Kotlin 系统能力而非 C++，可以跳过无关层。不得为了“全栈”而制造空转发代码。

每完成一个依赖层，先运行该层最相关的测试，再继续上层。发现基础判断错误时停止扩散修改。

# 分层实现规则

## Flutter / Dart

- Widget 不直接调用 MethodChannel、JNI 或解析原始 Map。
- Application Layer 编排流程，但不重写 C++ 核心规则。
- Gateway interface 使用类型安全参数和返回值。
- DTO/Adapter 严格使用 Contract 的 `snake_case`、枚举、UTC/date 规则和 `NativeResult<T>`。
- 明确 loading、empty、ready、submitting、error、permission denied 等适用状态。
- 防止重复提交、过期异步结果覆盖新状态和页面销毁后更新状态。
- 沿用项目现有状态管理、导航、主题和组件。

## Kotlin / Android

- MethodChannel Handler 只做路由、轻量转换和错误包装。
- Android Service 承担权限、通知、AlarmManager、系统回调等平台能力。
- 不在 Kotlin 复制重复规则、搜索排序或领域校验。
- 需要 C++ 时只调用 `native_calls.yaml` 已声明入口。
- 保持线程、Coroutine、Activity/Service 生命周期与项目现有模式一致。
- 系统异常映射为 Contract 已有错误码；不得把堆栈或任意异常字符串直接返回 Flutter。

## JNI / Boundary

- 只负责类型、生命周期、所有权和错误边界转换，不承载业务规则。
- JNI 名称、签名和加载库名必须与现有声明一致。
- Java/Kotlin 异常不得越过 JNI 边界；C++ 异常不得逃逸到 JVM。
- 字符串、数组、引用和线程附着必须正确释放或管理。
- Contract DTO 与 C++ Domain Model 显式转换，不暴露 Domain 对象内存布局。

## C++ Core

- 核心校验与领域规则在 Engine/Domain 中只有一份权威实现。
- 对跨层输入做防御性校验；错误使用 Contract 已声明错误码。
- Android API、Flutter 状态和 JSON 细节不得进入 Domain。
- 时间逻辑显式处理 timezone、UTC、date-only、重复和边界条件。
- 不以全局可变状态解决跨层共享问题。
- 保持现有 ABI、命名、错误模型和测试风格。

## Storage / SQLite

- 只有 Repository/Storage Adapter 组织 SQL。
- 使用参数化语句、事务和现有迁移机制；测试使用临时数据库。
- 保持软删除、唯一性、外键和时间语义。
- 不因单个功能预先创建未来表、通用索引或缓存体系。
- 只在有明确查询或约束需求时添加索引。
- 写入失败必须完整回滚并返回真实失败，不得留下半完成跨表状态。

# 多人代码整合规则

整合不同程序员的代码时：

1. 先识别每份实现的入口、输出、依赖和测试，不先重写；
2. 以 Contract 和领域职责裁决跨层差异；
3. 优先补适配和缺失接线，不把多个实现合并成新的大框架；
4. 检查字段、null、枚举、时间、错误码、线程和所有权在每个边界是否一致；
5. 删除重复实现前，先确认调用者和测试均已迁移；
6. 不以“能编译”为整合完成，必须验证数据往返和失败路径；
7. 对无法自动裁决的业务冲突，停止并列出候选决策及影响。

# 独立测试设计

编码前先写黑盒验收场景；编码后以“独立测试者”视角重新执行，不根据实现细节倒推测试。

每个场景包含：

```text
场景名称
前置数据与设备状态
用户实际操作
跨层可观察行为
最终可见结果或持久化结果
失败/权限/边界分支
清理方式
```

至少覆盖：

- 一条正常端到端路径；
- 一条用户输入或领域边界失败路径；
- 一条跨层错误传播路径；
- 一条持久化后重新读取路径（涉及 SQLite 时）；
- 一条权限、进程重启、时区或系统回调路径（涉及相关能力时）；
- 对原有相关功能的回归路径。

时间测试使用固定 clock、明确 timezone 和绝对时间，不依赖测试运行时“现在”。

Mock/Stub 只能证明单层编排，不能称为真实跨层通过。真实 Android 系统能力应在模拟器或真机验证；无法执行时明确标记“设备级未验证”。

# 验证流程

先发现并使用仓库已有命令。不得凭空发明不存在的测试任务。

对涉及的层执行适用项：

## C++ Core

从仓库根目录：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不要仅运行可能使用旧二进制的 `ctest` 作为完整验收。

## Flutter

在实际 Flutter 应用目录执行适用项：

```powershell
dart format --output=none --set-exit-if-changed <修改的 Dart 文件>
flutter analyze
flutter test
flutter build apk --debug
```

先运行相关测试，再运行完整测试。

## Kotlin / Android / JNI

- 使用仓库现有 Gradle Wrapper 和对应测试任务；
- 构建实际 Android Debug APK；
- JNI 变更后确认目标 ABI 的 `.so` 已进入 APK；
- 通知、权限、AlarmManager、启动恢复和系统回调必须按实际设备场景验证。

## 既有 Native Smoke

当跨 Flutter、Kotlin、JNI、C++ 时，执行 README 中的 smoke 流程：

```powershell
cd test_environment/flutter_native_smoke
flutter test
flutter analyze
flutter build apk --debug
```

设备可用时再运行 smoke App，并验证真实返回值。不要把固定的 `pong` smoke 当作业务功能验收。

## 数据库

- 使用临时数据库运行 Repository/迁移测试；
- 验证写入、读取、更新、软删除、事务回滚和兼容读取；
- 不接触用户真实数据库。

每条命令记录：实际执行、退出结果、失败阶段、是否由本次修改引起、仍未验证的行为。

# 完成闸门

只有所有适用项成立，状态才可为“完整完成”：

- 用户验收场景全部实现；
- 跨层调用链每一段都已连接且符合 Contract；
- 没有修改受保护内容或无关代码；
- 各层职责没有漂移或重复规则；
- 相关单元、边界、集成和黑盒场景通过；
- C++ 检查、Flutter analyze/test、Android Debug 构建等适用验证通过；
- 真实 Native/设备行为已验证，或用户明确接受该验证边界；
- 最终 diff 已审查，无调试代码、伪造数据、密钥和无关格式化。

未执行的验证不能写成“通过”；代码存在但无法构建不能写成“已完成”。

# 最终报告格式

```markdown
## 1. 结论
状态：完整完成 / 部分完成 / 被阻塞 / 已终止并建议拆分
一句话说明用户闭环是否可用。

## 2. 架构与调用链
- 需求如何分配到 Flutter、Kotlin、JNI、C++、Storage
- 实际调用链及使用的 MethodChannel/native call
- Contract 与领域约定是否一致

## 3. 需求完成情况
| 验收项 | 状态 | 证据或阻塞 |
| --- | --- | --- |

## 4. 文件变更
| 文件 | 新增/修改/删除 | 原因 |
| --- | --- | --- |

## 5. 独立测试设计与结果
- 场景、前置条件、操作、预期
- 实际执行命令与结果
- Mock、集成、模拟器、真机分别标明

## 6. 局限与未完成
- 未完成内容
- 当前限制和风险
- 缺少的前置任务、负责人层和建议顺序
```

报告必须区分“实现完成”“构建通过”“测试通过”“设备验证通过”，不得合并成含糊的成功表述。