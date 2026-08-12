# ExcellentCalendarAPP 项目级 Agent 指南

## 1. 项目目的

ExcellentCalendarAPP 是一个 Android 优先、本地优先的日历与个人效率应用。
产品范围包括日程、提醒、习惯、日历视图、搜索、纪念日、通知、四象限、桌面组件，
以及后续的 AI 导入、微信能力、云同步、备份和投送。

工程目标不是堆叠功能，而是先建立稳定的本地核心、清晰的跨语言边界、
可测试的业务规则和可持续演进的架构，避免字段、错误码、时间格式和职责漂移。

## 2. 开发阅读

开始规划或修改代码前，按顺序必须阅读：

1. 从仓库根目录到目标目录范围内的全部 `AGENTS.md`。
2. `docs/develop_record.md`：实时进度的一个详细概述
3. `docs/problems.md`：已知缺陷、未解决风险、历史错误和规避要求。
4. `docs/target.md`：当前目标、未完成内容和下一步重点。

本文件不记录实时进度；实际进度始终以 `docs/develop_record.md` 为准。
不得因为当前代码表面可运行，就忽略 `docs/problems.md` 中已记录的问题。

如果当前任务需求需要更加详细的项目背景，项目配置信息，可以在

1. 仓库根目录下面的readme.md
2. 仓库根目录下面的docs里面的文档。

如果本次开发不需要涉及了解背景信息的时候，无需全量分析读取readme.md的内容。

## 3. 当前方向与计划原则

项目基线方向是 Android 优先、本地优先。
优先打通 Event、Reminder、Recurrence、Category、持久化、查询、通知调度，
以及 Flutter→Kotlin→JNI→C++ 的本地核心闭环。
Habit 与 HabitCheckIn 构成下一条独立业务闭环。
搜索和通知历史应在核心行为稳定后完善。
AI、云同步、云端投送、微信和高级导出可以先保留模型与协议，
不代表当前必须完成生产级实现。

以上仅是长期优先级，不是实时进度。选择任务前必须与
`docs/develop_record.md` 中的当前目标核对。

## 4. 总体架构

```text
Flutter Presentation / State
    ↓
Flutter Application Layer
    ↓
Dart Gateway Interface + Contract DTO
    ↓ MethodChannel / EventChannel
Kotlin Handler / Android Services
    ↓ JNI
C++ Boundary Contract
    ↓
C++ Core Engines
    ↓
Storage Repository / SQLite
```

AI 管道和可选云端属于扩展路径，不得绕过既有 Application、Contract、
Domain 或 Persistence 边界。

### 各层职责

- Flutter Presentation：页面、输入、导航、弹窗、loading 和视觉状态。
- Flutter Application：业务流程编排、重试、状态转换和 Gateway 调用。
- State Management：明确、合法、尽量不可变的 UI 状态。
- Dart Gateway / DTO：类型安全的边界访问、序列化和 NativeResult 解析。
- Kotlin：Android 权限、通知、闹钟、服务、系统回调、桌面组件、分享、
  微信 SDK，以及轻量 MethodChannel/JNI 适配。
- C++ Boundary：Contract 数据与领域命令、领域结果之间的转换。
- C++ Core：校验、重复规则、提醒规则、搜索、习惯、日历聚合、四象限、
  AI 结果校验、同步日志、加密导出等平台无关业务逻辑。
- Storage Repository：SQLite 语句和持久化访问的统一入口。
- SQLite / FTS / 附件 / 日志：保存数据和索引，不承担核心业务规则。

界面规则放 Flutter，用户流程放 Application，领域规则放 C++，
Android 系统能力放 Kotlin，序列化和调用细节放边界适配层。

## 5. Contract Layer 强制规则

`contracts/` 是所有跨语言调用和未来后端边界的协议真相源。
任何 Dart↔Kotlin、Kotlin↔C++、客户端↔后端调用，都必须先在 contracts 中声明。
禁止临时新增未声明的 MethodChannel 方法、JNI 函数、字段、枚举值或错误字符串。

跨层变更应先更新适用的协议文件：

- Flutter 对外方法：`method_channels.yaml`；
- Kotlin 调用 C++：`native_calls.yaml`；
- request / response schema；
- `error_codes.yaml` 与 `enums.yaml`；
- 受影响的协议版本、说明和示例。

随后再同步修改各语言本土化实现及测试。

必须遵守：

- Request、Response、Domain Model、数据库实体和 ViewModel 相互分离。
- 跨层 payload 只能使用 Contract 已声明字段。
- Contract 字段统一 `snake_case`；语言内部可以本土化命名。
- 所有跨层返回统一使用 `NativeResult<T>` 和 `NativeError`。
- 错误码必须来自 `error_codes.yaml`，禁止依赖自由文本判断业务。
- 传输枚举使用稳定字符串，不使用数字序号。
- `datetime` 使用 ISO 8601 UTC 时间点；`date` 是不带时分秒的本地日期。
- 缺少必填字段、未知枚举、非法返回外壳或版本不兼容必须显式失败，
  不得用默认值掩盖协议错误。
- C++ Domain Model 不得直接暴露给 Dart 或 Kotlin。
- 原始 JSON、`Map<String, dynamic>`、`JSONObject` 只应存在于边界适配范围。

## 6. 核心领域不变量

- `Event` 是日程实体；创建请求、更新请求和返回对象必须分离。
- `Reminder` 是未来待执行任务；多个提醒时间对应多条 Reminder。
- `Notification` 是投递结果日志，绝不能作为未来提醒扫描入口。
- `Recurrence` 是独立规则；某次 occurrence 状态不能污染整个系列状态。
- `Habit` 定义习惯；`HabitCheckIn` 记录每日行为并作为统计来源。
- overdue、in_progress 等派生状态应动态计算，除非模型明确要求持久化。
- 软删除数据默认不参与普通查询，除非用例明确要求。
- Engine 不得分散编写 SQL；持久化统一经过 Storage Repository。
- 边界校验不能替代 C++ Core 内部的防御性领域校验。

需求与 `DATA_MODEL.md` 冲突时，不得静默改变模型，必须报告并等待决策。

## 7. 目录与模块职责

- `contracts/`：方法、Native 调用、schema、错误码、枚举和协议版本。
- `flutter_client/`：Flutter UI、Application、状态、Dart Gateway、DTO 和客户端测试。
- Android Native：MethodChannel Handler、JNI Adapter、权限、闹钟、通知、服务、
  Share Receiver、Widget Provider 和 WeChat Bridge。
- `cpp_core/`：边界对象、领域模型、核心 Engine、Repository 和原生测试。
- Local Storage：SQLite、FTS、附件和操作日志，通过 Repository 访问。
- AI Pipeline：OCR、文本提取、时间解析、分类/提醒推荐、候选构建和结果校验。
- Optional Backend：认证、同步、备份、AI Proxy 和微信推送网关。
- `test_environment/flutter_native_smoke/`：Flutter→Kotlin→JNI→C++ 全链路验证。
- `docs/`：实时开发记录、问题记录、决策和补充设计文档。

以仓库实际目录为准，不得为了匹配本摘要而擅自重组项目。

## 8. 工具与环境基线

使用已验证版本：

- Flutter 3.41.9 stable；Dart 3.11.5；DevTools 2.54.2。
- Android Studio AI-253.32098.37.2534.15336583；JBR 21.0.10。
- Android SDK 36 / 36.1；Platform Tools 37.0.0；NDK 28.2.13676358。
- CMake 3.22.1；SQLite CLI 3.50.6；Git 2.53.0.2。

禁止随手执行 `flutter upgrade`，或升级 Android Studio、SDK、NDK、CMake、
Gradle、AGP、Kotlin、JDK 等构建工具。
确实需要升级时，必须先在 `test_environment/flutter_native_smoke` 完成全量验证，
再在同一变更中更新 `README.md`、相关锁定/配置文件、兼容性说明和本节。

## 9. 开发与验证流程

开发前：

1. 检查 `git status`，保护用户现有修改，不覆盖无关内容。
2. 明确需求行为、验收标准、涉及层级和本次不做的内容。
3. 检查 Contract、DTO、Gateway、Kotlin/JNI、C++ Boundary、Domain、Repository、
   测试是否形成完整调用链；缺失时明确阻塞点。
4. 先查找可复用模式，再新增抽象或依赖。
5. 选择最小且完整的方案，避免无关重构和提前设计复杂框架。

实现中：

- 业务规则放在所属层，Adapter 保持轻薄。
- 跨边界实现前先更新 Contract。
- 在不可信边界和核心领域入口都进行防御性校验。
- 未经批准，不实施破坏性协议变更。
- 覆盖正常、边界、非法输入和回归测试。
- 不得伪造 Native 或 Backend 行为来让 UI 看似可用。

实现后：

- 执行格式化、静态分析、相关单元/集成测试和构建。
- C++ 使用构建加测试目标，不能只运行可能陈旧的 CTest 二进制：
  `cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON`
  然后执行 `cmake --build cpp_core/build-ninja --target excellent_calendar_check`。
- Flutter 执行相关测试、`flutter analyze` 和 Android Debug 构建。
- 跨语言、JNI、构建工具或环境变更必须执行完整 smoke test。
- 未实际执行的检查必须明确标记为 **未验证**，不得仅凭代码审查声称通过。
- 在.\docs\log.md中按顺序简要写入：本次的任务所使用的skill，负责的板块，任务目标，任务结果，开发时间，用于可追溯的开发日志记录。


## 10. 默认允许修改的范围

- .\docs\log.md 用于记录开发后的日志记录
- .\docs\temp.md 用于记录任何临时内容

## 11. 冲突、问题

当用户需求、README、Contract、Data Model、代码、测试或文档互相冲突时：

1. 不猜测、不擅自选边、不制作未记录的兼容绕过方案。
2. 指出冲突位置、涉及文件/层级、用户影响和可选方案。
3. 暂停冲突部分并与用户协商；仅继续不受影响且安全的工作。

开发前必须阅读 `docs/problems.md`，主动避免重复错误。
发现缺陷根因后，最终报告必须突出说明根因、触发条件、影响范围、修复、
验证结果和剩余风险。
可复用经验或未解决问题写入 `docs/problems.md`；完成内容、当前状态和下一步
写入 `docs/develop_record.md`。