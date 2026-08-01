---
name: excellent-calendar-evidence-driven-debug
description: 使用可复现、证据驱动的工作流，诊断并修复 ExcellentCalendarAPP 现有代码中的错误、回归、崩溃、卡死、数据异常、跨语言协议问题、提醒调度故障、并发问题和性能退化。适用于失败测试、错误行为、崩溃堆栈、Sanitizer 输出、可疑日志、MethodChannel/JNI/C++/SQLite 链路故障，以及用户要求定位并修复缺陷的场景。不用于没有已观察故障的新功能开发、大范围重构或纯代码风格审查。

---

# ExcellentCalendarAPP 证据驱动调试

使用本 Skill 调查和修复 ExcellentCalendarAPP 的现有缺陷。

核心目标不是“尽快改一处让现象消失”，而是通过可复现证据找到第一个被破坏的边界或不变量，在正确的架构层完成最小修复，并用回归测试证明缺陷已被捕获。

本 Skill 保留通用证据驱动调试方法的总体结构：

```text
建立仓库上下文
→ 规范化问题
→ 复现并保存证据
→ 找到第一个错误边界
→ 建立并排序假设
→ 运行区分性实验
→ 确认根因
→ 实施最小正确修复
→ 添加回归覆盖
→ 分层扩大验证
→ 检查同类缺陷
```

配套输入格式可以使用 `BUG_REPORT_TEMPLATE.md`。即使用户没有完整填写模板，也应先从仓库、日志、测试和现有实现中收集能够本地确认的信息，再决定是否存在真正阻塞。

# 一、项目真相源

开始诊断前，按以下顺序读取并核对：

1. 当前目录及父目录中的 `AGENTS.md`。
2. 仓库根目录 `README.md`，尤其是：
   - 开发环境基线；
   - C++ Core 构建与测试命令；
   - Flutter Native Smoke Test；
   - 分层架构；
   - Contract Layer 规则。
3. `DATA_MODEL.md` 中与缺陷相关的领域对象、状态和关系。
4. `contracts/method_channels.yaml`：Flutter/Dart 到 Kotlin 的公开 MethodChannel 与 EventChannel 协议。
5. `contracts/native_calls.yaml`：Kotlin 到 C++ 的内部 JNI 调用协议。
6. `contracts/error_codes.yaml`、`contracts/enums.yaml`、相关 request/response/common schema。
7. 缺陷附近的 Dart、Kotlin、JNI、C++、Storage、SQLite 和测试代码。
8. 当前分支、提交、`git status`、最近相关 diff 和最后已知正常版本。

真相源职责必须区分：

```text
DATA_MODEL.md              领域对象和业务不变量
method_channels.yaml       Flutter ↔ Kotlin 公开跨层入口
native_calls.yaml          Kotlin ↔ C++ 内部调用入口
JSON Schema                请求、响应和公共数据结构
error_codes.yaml           跨层错误码
现有代码与测试             当前真实实现行为
README.md                  架构、环境和验证基线
```

`method_channels.yaml` 与 `native_calls.yaml` 不要求机械一一对应。一个公开方法可以在 Kotlin 内部编排多个 Native 调用；Android 系统能力也可能不进入 C++。只有当实际调用违反已声明的职责或协议时，才可判定为边界缺陷。

如果 README、DATA_MODEL、contracts、实际代码或用户期望发生冲突：

- 明确列出冲突；
- 区分“文档过期”“实现偏离”“需求改变”三种可能；
- 不得静默选择其中一种；
- 在无法通过仓库证据确定正确行为时，将结论标记为未确认；
- 只在该冲突会实质改变修复方向时才请求用户决策。

# 二、核心规则

1. 所有分析和报告都必须区分 **已确认事实**、**推断** 和 **未知项**。
2. 实际可行时，先复现再修复。失败测试、稳定脚本、Sanitizer 报告、崩溃转储、可重复错误输出或可观测错误状态都算复现证据。
3. 崩溃行、异常栈顶、错误提示和最终 UI 现象只是观察点，不自动等于根因。
4. 优先执行修改最少、信息增益最高的实验，不做试错式大范围编辑。
5. 诊断阶段一次只改变一个因果变量。
6. 证据未连接“原因—错误状态—可见症状”之前，不得宣称根因已经确认。
7. 根因未确认时，不进行大范围重构、架构迁移或顺手清理。
8. 不得通过以下方式让症状暂时消失：
   - 弱化断言；
   - 吞掉异常；
   - 屏蔽警告；
   - 增加任意 `sleep`；
   - 无限重试；
   - 禁用、跳过或删除测试；
   - 返回伪造成功结果；
   - 把错误状态默认成空对象。
9. 保留用户无关修改。未经明确授权，不执行 `git reset --hard`、`git clean`、强制 checkout、批量格式化全仓库或破坏性数据库操作。
10. 修复后尽可能添加或更新回归测试，使其在错误实现上因正确原因失败，在修复后通过。
11. 所有跨层方法、字段、枚举、错误码、时间格式和返回包装必须以 `contracts/` 为依据。
12. 业务规则必须修复在拥有该规则的层，不得为了方便复制到 Flutter 或 Kotlin。
13. 未实际运行的测试、构建、真机验证或 Sanitizer 检查必须明确标记为“未运行”或“未验证”。
14. 不得通过升级 Flutter、Android SDK、JDK、NDK、CMake 或依赖来掩盖代码缺陷，除非证据确认缺陷就是版本兼容问题且升级已获授权。

# 三、ExcellentCalendarAPP 关键不变量

诊断时优先检查以下项目级不变量。它们不是自动根因，但属于高价值边界。

## 3.1 跨语言 Contract 不变量

- Flutter、Kotlin、C++ 之间的跨层调用必须先在 contracts 中声明。
- Contract 字段使用 `snake_case`。
- 枚举跨层传输使用 contracts 中定义的字符串值。
- `datetime` 使用 ISO 8601 UTC 字符串。
- `date` 表示用户本地日期，不得当成 UTC 午夜时间点。
- 所有调用统一使用 `NativeResult<T>`。
- `ok = true` 时 `error` 必须为 `null`。
- `ok = false` 时 `data` 必须为 `null`，且必须有合法 `error`。
- 错误码必须来自 `error_codes.yaml`。
- 不得把 malformed response 静默转成正常空对象。
- `contract_version`、请求 schema 和响应 schema 必须与方法声明一致。

## 3.2 分层不变量

```text
Flutter Presentation
→ Application / State
→ Dart Gateway Interface
→ Dart DTO / MethodChannel Adapter
→ Kotlin Handler / Android Service
→ JNI Adapter
→ C++ Boundary Contract
→ C++ Domain Engine
→ Storage Repository
→ SQLite
```

- UI 不直接调用 MethodChannel、JNI 或 C++。
- Kotlin 负责 Android 系统能力和桥接，不承载 C++ Core 应负责的领域规则。
- C++ Domain Model 不直接暴露给 Dart/Kotlin，跨层必须经过 Boundary Contract。
- Engine 不应绕过 Storage Repository 随意操作 SQLite。
- 跨层临时字段、临时方法名和各语言自行发明的错误字符串都属于协议漂移风险。

## 3.3 Event 与 occurrence 不变量

- `Event.status` 表示单次 Event 或整个重复系列的生命周期状态。
- 重复日程某一次完成、跳过或取消应写入 `EventOccurrenceState`。
- 不得用 `Event.status` 表达“今天完成”“本次跳过”。
- 同一个有效的 `eventId + occurrenceStartAt` 默认只有一条 occurrence 状态记录。
- 没有状态记录的 occurrence，其 `pending`、`in_progress`、`overdue` 应由计划时间和当前时间动态计算。
- 取消某次完成时，应恢复到动态计算状态，而不是制造另一个互相冲突的稳定状态。

## 3.4 Reminder 与 Notification 不变量

- `Reminder` 是未来待执行的提醒任务。
- `Notification` 是某次提醒投递后的结果日志。
- Reminder 扫描和调度不能以 Notification 为主表。
- Event、Habit、Anniversary 本体不直接保存核心提醒记录；一个业务对象可以关联多条 Reminder。
- 典型链路为：

```text
业务对象
→ Reminder Engine 生成 Reminder
→ Storage 持久化
→ Kotlin 调度协调
→ Android Alarm Scheduler
→ 到点触发
→ Notification Service 投递
→ 写入 Notification
→ 更新或消费 Reminder 状态
```

- `reminder.schedule_pending` 在当前公开 Contract 中已标记为 deprecated 时，不得为修复方便重新依赖它；应优先检查当前 `reminder.reconcile_schedule` 及其内部 Native 调用链，除非仓库实际协议已经更新。
- Reminder 状态、Android 系统闹钟状态和 Notification 日志必须分别检查，不能因某一层“看起来成功”就推断整条链路成功。

## 3.5 Habit 与 HabitCheckIn 不变量

- `Habit` 保存习惯定义。
- 每日完成状态、次数和完成时间保存在 `HabitCheckIn`。
- 连续天数、完成率和总完成天数原则上从 `HabitCheckIn` 计算。
- 同一有效 `habitId + checkDate` 默认只有一条打卡记录。
- `checkDate` 是用户本地日期，不能因 UTC 转换偏移到相邻日期。

## 3.6 软删除不变量

- 软删除实体通过 `deletedAt/deleted_at` 表示。
- 普通查询默认排除软删除记录。
- 恢复、同步、搜索索引、Reminder 调度和 occurrence 查询必须明确处理软删除语义。
- 不得用物理删除修复“重复数据显示”之类的问题，除非数据模型和用户要求明确允许。

# 四、阶段 0：建立仓库与环境上下文

诊断前完成以下检查：

1. 阅读适用的 `AGENTS.md`、README、DATA_MODEL 和相关 contracts。
2. 确认缺陷涉及哪些层：
   - Flutter UI；
   - Application/State；
   - Dart Gateway/DTO；
   - MethodChannel/EventChannel；
   - Kotlin Android Service；
   - JNI；
   - C++ Boundary；
   - C++ Domain Engine；
   - Storage Repository/SQLite；
   - 多层组合。
3. 确认当前开发环境是否符合 README 基线，尤其是 Flutter、Dart、JDK、Android SDK、NDK、CMake。
4. 检查 `git status`，记录但不覆盖无关修改。
5. 记录当前分支、commit、构建类型、ABI、Android API、设备或模拟器信息。
6. 找到相关入口、模块、owner、测试、配置、生成代码边界和日志入口。
7. 若是回归，找到 last-known-good、first-known-bad 或最小可疑 diff。
8. 确认相关方法在 `method_channels.yaml` 和 `native_calls.yaml` 中的职责与映射。

只记录与问题相关的仓库事实，不倾倒整个目录树。

建议的仓库事实记录格式：

```text
已确认：
- 公开入口：event.create
- Flutter 通过 excellent_calendar/native 调用
- Kotlin 内部通过 native_calls.yaml 的 event.create 进入 C++
- 领域规则所有者：C++ Event Engine
- 复现设备：...
- 构建类型：debug/release

未知：
- 首次出现版本
- 是否仅在特定时区出现
```

# 五、阶段 1：规范化缺陷报告

将用户输入整理为内部 Case Record：

- **期望行为**
- **实际行为**
- **影响和严重程度**
- **复现步骤**
- **复现频率**
- **环境和构建配置**
- **最后正常版本 / 首个异常版本**
- **已观察证据**：日志、堆栈、dump、失败测试、Sanitizer、截图、指标
- **相关业务对象**：Event、Occurrence、Reminder、Notification、HabitCheckIn 等
- **相关标识**：`request_id`、`event_id`、`reminder_id`、`notification_id`、`occurrence_start_at`
- **相关跨层入口**：MethodChannel 方法、EventChannel、Native call
- **时间上下文**：用户时区、UTC 时间、本地日期、全天/非全天、夏令时边界
- **Android 上下文**：API、厂商、权限、后台限制、精确闹钟状态、通知渠道
- **最近修改**
- **已经尝试的实验及结果**
- **约束**：兼容性、Contract 稳定性、性能、安全、范围、禁止修改项
- **完成定义**

每一项标记为：

```text
[已确认]
[推断]
[未知]
```

不得默默补全用户没有提供且仓库无法确认的信息。

# 六、阶段 2：复现并保存证据

优先选择最窄、最稳定、最接近缺陷所有层的复现。

## 6.1 复现顺序

1. 运行用户提供的准确失败测试或命令。
2. 若没有，找到最接近的现有测试。
3. 若仍没有，创建最小临时 reproducer 或聚焦测试。
4. 记录：
   - 完整命令；
   - 退出码；
   - 关键输出；
   - 平台、设备、ABI；
   - debug/release；
   - 时区与固定时间；
   - 输入 payload；
   - `request_id` 和业务对象 ID。
5. 对间歇性问题重复运行，估算失败频率，并查找可控触发条件：
   - 线程数；
   - 固定随机种子；
   - 调用顺序；
   - 前后台切换；
   - 设备重启；
   - 时区；
   - 日期边界；
   - 数据量；
   - 优化级别；
   - ABI；
   - 权限状态。

优先使用固定时钟、barrier、latch、fake scheduler、fault injection、固定 seed 或受控回调，不使用任意 `sleep` 强行“等稳定”。

## 6.2 按层选择复现方式

- UI/状态问题：Widget test、Application unit test、Fake Gateway。
- DTO/Contract 问题：序列化测试、schema 校验、MethodChannel mock handler。
- Kotlin/Android 问题：Kotlin unit test、instrumentation test、真实设备、`adb logcat`。
- JNI/ABI 问题：Flutter Native Smoke Test、最小 JNI 调用、APK so 检查。
- C++ 领域问题：聚焦 C++ unit test、直接调用 Engine/Boundary 的最小程序。
- SQLite/Repository 问题：Repository test、临时数据库、事务与查询结果检查。
- Reminder 调度问题：固定未来时间、测试 Reminder 状态、系统闹钟、触发 receiver、Notification 记录的完整链路。
- 性能问题：固定数据集、稳定基准、CPU/分配/锁/I/O profile。

## 6.3 无法在当前环境复现时

可以继续使用静态证据，但必须：

- 将根因结论标记为“暂定”或“领先假设”；
- 说明缺少哪种运行时证据；
- 不得声称修复已被真实设备或完整链路验证；
- 给出下一项信息增益最高的实验。

# 七、阶段 3：找到第一个错误边界

从输入到症状追踪数据流和控制流，找到“正确状态第一次变成错误状态”的位置。

## 7.1 通用跨层追踪路径

```text
用户输入
→ Flutter 表单/页面状态
→ Application Layer
→ Dart Gateway Request DTO
→ MethodChannel payload
→ Kotlin Contract/Handler
→ JNI 参数
→ C++ Boundary Request
→ C++ Domain Engine
→ Storage Repository
→ SQLite
→ 反向 Response / EventChannel
→ Flutter UI
```

在每个边界比较：

- 字段名；
- 字段类型；
- enum；
- nullability；
- UTC datetime；
- local date；
- ID；
- 状态；
- error code；
- `contract_version`；
- `request_id`；
- 业务不变量。

## 7.2 Reminder/Notification 专项追踪

提醒类缺陷至少区分以下状态：

```text
A. Reminder 是否正确生成并持久化
B. Reminder 是否处于可调度状态
C. Kotlin 是否读取到可调度 Reminder
D. AlarmManager 是否成功注册
E. 系统是否实际触发 receiver
F. Notification Service 是否成功展示/发送
G. Notification 是否写入投递结果
H. Reminder 是否正确标记 sent/failed/消费并生成下一次
I. EventChannel/UI 是否收到并正确展示状态变化
```

“数据库中 Reminder 为 scheduled”不能证明系统闹钟仍存在；“系统通知出现”也不能证明 Notification 日志和 Reminder 状态一致。

## 7.3 时间与重复规则专项追踪

重点比较：

- 原始用户本地时间；
- 传输 UTC；
- C++ 计算时区；
- recurrence 起点；
- occurrence 的计划开始时间；
- Reminder 的 `remind_at`；
- Android 调度时间；
- 实际触发时间；
- 展示时转换后的本地时间。

优先找到第一个发生日期偏移、时区丢失、夏令时误算、全天事件误转或 occurrence 键不一致的位置，而不是只在 UI 上加减小时数。

## 7.4 回归边界

当存在回归窗口时，使用：

- `git log`；
- `git show`；
- `git blame`；
- 最小相关 diff；
- 可自动化时使用 `git bisect`。

优先检查“最后正常与首个异常之间最小改动”，不要一开始审查整个模块。

# 八、阶段 4：建立并排序假设

维护 3 到 5 个活跃候选。每个候选记录：

| 字段             | 内容                 |
| ---------------- | -------------------- |
| 候选根因         | 具体代码路径或不变量 |
| 支持证据         | 已观察事实           |
| 反对/缺失证据    | 尚未解释的事实       |
| 为真时预测       | 应观察到什么         |
| 为假时预测       | 应观察到什么         |
| 最低成本区分实验 | 能区分竞争假设的实验 |
| 当前置信度       | 低 / 中 / 高         |

项目常见候选类别包括：

- Flutter stale response、重复提交、生命周期或状态机错误；
- Dart DTO 字段、enum、nullability、时间序列化错误；
- MethodChannel 方法名、参数或 `NativeResult<T>` 解析错误；
- Kotlin Handler 路由错误、线程切换、权限或 Android 生命周期错误；
- JNI 签名、ABI、对象生命周期、局部/全局引用、线程附着问题；
- C++ ownership、use-after-free、越界、UB、并发或异常传播问题；
- 领域不变量错误：Event/Occurrence、Reminder/Notification、Habit/CheckIn 混淆；
- recurrence、时区、夏令时、全天事件、local date 边界错误；
- Storage transaction、软删除过滤、唯一性、索引一致性、缓存失效；
- AlarmManager 注册、取消、重启恢复、权限、后台限制问题；
- Notification 渠道、权限、PendingIntent 身份冲突或重复投递；
- 构建配置、ABI 打包、依赖版本或 debug/release 差异；
- 性能退化：算法复杂度、重复展开、分配、I/O、锁竞争、全量扫描。

不得因为某段代码“看起来可疑”就将其排在首位。排序依据是证据、预测能力和解释范围。

# 九、阶段 5：运行区分性实验

每个实验前必须写清：

1. 正在测试哪个假设；
2. 若假设为真，预测结果是什么；
3. 若假设为假，预测结果是什么；
4. 观察结果允许得出什么结论。

可使用的实验包括：

## 9.1 跨层实验

- 使用同一 `request_id` 记录 Dart、Kotlin、JNI、C++ 各边界的关键字段。
- 比较进入边界前后的 payload，不记录敏感内容。
- 用 Fake Gateway 绕过 Native，判断问题是否留在 Flutter。
- 直接调用 C++ Boundary/Engine，绕过 Flutter/Kotlin，判断问题是否在 Core。
- 用固定 JSON request 测试 Dart/Kotlin/C++ 序列化一致性。
- 对 `NativeResult<T>` 构造成功、业务失败、malformed 三类响应。
- 比较公开 MethodChannel 调用与实际内部 native call 序列。

## 9.2 C++ 实验

- 条件断点、watchpoint、完整线程 backtrace。
- AddressSanitizer、UndefinedBehaviorSanitizer、ThreadSanitizer、MemorySanitizer 或项目已支持的等价工具。
- Debug 与 Release、不同优化级别对比。
- 单线程与多线程对比。
- 固定 seed、受控 executor、barrier/latch。
- allocation、CPU、锁、I/O、系统调用 profiling。
- 对输入做二分缩减或 delta debugging。

只使用仓库现有或明确可配置的 Sanitizer/构建方式；不要未经确认重写整个构建系统。

## 9.3 时间实验

- 固定 clock，不依赖真实当前时间。
- 固定 `timezone`，分别测试 UTC、Asia/Singapore 和存在夏令时的时区。
- 测试午夜前后、月末、年末、闰日、夏令时切换、全天事件。
- 比较 `datetime` 与 `date` 路径，防止 local date 被转成 UTC 时间点。
- 对 recurrence 使用固定起点和有限展开窗口。

## 9.4 Reminder/Android 实验

- 检查 Reminder 持久化状态与调度筛选条件。
- 检查 Kotlin 是否调用当前有效的 reconcile 流程。
- 检查系统权限、通知渠道、精确闹钟和后台限制。
- 使用 `adb logcat` 关联 reminder/request ID。
- 必要时检查系统 AlarmManager 状态，但不能把系统 dump 单独当作业务成功证据。
- 强制一个受控的近期提醒，验证：注册、触发、投递、Notification 记录、Reminder 消费/更新。
- 模拟设备重启或 App 进程被杀后的恢复流程。
- 检查 PendingIntent 的 request code、action、data 和 flags 是否造成互相覆盖。

## 9.5 Storage 实验

- 使用隔离临时数据库。
- 比较事务提交前后状态。
- 验证软删除过滤。
- 验证唯一键语义，例如 occurrence 与 HabitCheckIn。
- 验证失败路径是否留下半完成状态。
- 对 Reminder 调度状态转换测试幂等性和重试语义。

不要把“某次编辑后 bug 消失”当作证据。编辑可能改变内存布局、时序、优化或调度。

# 十、阶段 6：确认根因

只有大部分以下条件满足时，根因才算确认：

1. 原因能够解释症状及其环境条件。
2. 证据显示错误事件或错误状态确实发生。
3. 区分性实验按预测改变了结果。
4. 因果链指出了第一个被破坏的不变量或边界。
5. 隔离或回退责任改动后恢复正确行为，实际可行时。
6. 回归测试能够捕获缺陷。
7. 对跨层问题，能够说明错误是在发送前、边界转换中、领域处理时、持久化时还是返回时首次出现。

使用以下形式描述根因：

> 当 **触发条件** 发生时，**组件/代码路径** 违反了 **项目不变量或 Contract**，产生 **第一个错误状态**，该状态经过 **后续链路** 最终表现为 **用户可见症状**。

示例结构，不代表真实结论：

> 当用户在本地日期午夜附近完成重复日程时，Dart DTO 将 occurrence 的本地日期错误转换为 UTC 午夜，违反 `date` 与 `datetime` 分离规则，导致 C++ 使用不同的 `occurrence_start_at` 查询不到既有状态，最终在 UI 中重复显示未完成项。

# 十一、阶段 7：实施最小正确修复

编辑前先定义：

- 要恢复的不变量或 Contract；
- 为什么该层拥有修复职责；
- 兼容性、性能、并发和数据迁移约束；
- 预计修改文件；
- 预计新增或修改的测试。

然后：

1. 做最小但完整的因果修复，不只隐藏症状。
2. 保留公开行为，除非公开行为本身就是缺陷。
3. 处理由根因直接推出的相邻边界情况。
4. 不混入无关重构、重命名、格式化或依赖升级。
5. 仅在原因或不变量不明显时添加注释。
6. 保留用户无关修改。

## 11.1 修复层归属

- 页面展示、按钮、错误文案、loading：Flutter Presentation/Controller。
- 用户流程编排、重复提交、状态过渡：Application Layer。
- DTO、字段映射、NativeResult 解析：Dart/Kotlin/C++ Boundary Adapter。
- MethodChannel 或 native call 声明错误：contracts 及所有受影响实现必须原子更新。
- Android 权限、AlarmManager、Notification、Receiver：Kotlin Android Layer。
- recurrence、提醒合法性、Event/Occurrence、搜索排序：C++ Domain Engine。
- SQL、事务、软删除、持久化一致性：Storage Repository/SQLite。

不得把 C++ 领域规则复制到 Flutter 或 Kotlin 来快速修复。

## 11.2 Contract 变更规则

若根因确实在 Contract：

- 先更新真相源；
- 同步检查 `method_channels.yaml`、`native_calls.yaml`、schema、enums、error codes；
- 更新 Dart DTO/Gateway adapter；
- 更新 Kotlin Contract/Handler；
- 更新 C++ Boundary；
- 更新示例与测试；
- 评估 `contract_version` 和向后兼容性。

不得只改其中一层制造新的协议漂移。

## 11.3 并发修复规则

明确验证：

- 所有权；
- callback 生命周期；
- cancellation；
- lock 范围与顺序；
- 原子性和内存序；
- 线程附着和 JNI 引用；
- shutdown 顺序；
- stale response；
- 幂等和重复投递。

禁止使用时间型修复。

# 十二、阶段 8：添加回归覆盖

优先的回归测试必须：

- 在错误实现上因预期原因失败；
- 修复后通过；
- 可重复、确定性强；
- 断言外部可见行为或稳定不变量；
- 不依赖任意 sleep、日志文案、内存地址或非契约执行顺序；
- 覆盖触发边界，并在有价值时覆盖一个邻近正常案例。

## 12.1 按缺陷层选择测试

- Flutter UI：Widget test。
- Application/State：unit test，使用 Fake Gateway。
- DTO/Contract：序列化、反序列化、malformed response、schema 契约测试。
- MethodChannel：mock channel handler，验证方法名和 payload。
- Kotlin Android：unit/instrumentation test。
- JNI：smoke test 或最小边界测试。
- C++ Domain：聚焦 unit test。
- Repository/SQLite：临时数据库集成测试。
- Reminder 调度：fake scheduler + 真实设备验证，二者职责分开。
- 并发：barrier、latch、hook、fake executor 或受控 scheduler。
- 性能：固定输入基准和明确退化阈值，避免脆弱绝对时间断言。

## 12.2 日历项目高价值回归案例

根据根因选择适用项：

- UTC 与本地时区转换；
- local date 不跨日；
- 全天 Event；
- 夏令时切换；
- 重复日程某一次完成/取消；
- 同一 occurrence 唯一状态；
- 多 Reminder 绑定同一 Event；
- Reminder 与 Notification 状态不混淆；
- App 重启后的 Reminder reconcile；
- 重复投递幂等；
- 软删除记录不进入普通查询和调度；
- HabitCheckIn 同日唯一性；
- malformed NativeResult 不返回假成功。

若无法建立可靠自动化测试，说明原因，并提供最强的可重复验证命令或手工步骤。

# 十三、阶段 9：按比例扩大验证

按以下顺序运行：

1. 新增或修改的回归测试；
2. 最近的单元测试；
3. 相关组件或集成测试；
4. 格式化、静态分析、lint；
5. 适用于改动代码的 Sanitizer；
6. C++ Core 检查；
7. Flutter 完整测试；
8. Android Debug 构建；
9. Flutter Native Smoke Test；
10. 原始复现重复运行；
11. 真实 Android 行为验证，尤其是通知、权限、AlarmManager、重启恢复。

## 13.1 C++ Core 基线

从仓库根目录执行：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

不要把单独执行：

```powershell
ctest --test-dir cpp_core/build-ninja
```

当成完整验收，因为它可能运行遗留的旧测试程序而没有编译当前源码。

## 13.2 Flutter 基线

在实际 Flutter 应用目录执行仓库适用命令，例如：

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

优先先运行相关测试文件，再运行完整测试。

## 13.3 Native Smoke Test

按 README 的当前路径与环境执行：

```powershell
cd test_environment/flutter_native_smoke
flutter test
flutter analyze
flutter build apk --debug
flutter run
```

成功时应验证实际 Dart → Kotlin → JNI → C++ 链路，而不只是 Mock。

必要时检查 APK 是否包含目标 ABI 的 C++ so。

## 13.4 结果分类

每条命令必须报告准确结果：

- 通过；
- 因本次修改失败；
- 因既有或无关问题失败；
- 未运行：环境、设备、权限或成本限制；
- 部分验证：只验证了某一层。

不得声称未运行的测试通过。

# 十四、阶段 10：检查同类缺陷

根因确认后，在附近或共享代码中窄范围搜索相同模式：

- 相同 Contract 字段漂移；
- 相同 enum 或 error code 映射错误；
- 相同 UTC/local date 混淆；
- 相同 Event/Occurrence 状态误用；
- 相同 Reminder/Notification 职责混淆；
- 相同 JNI 生命周期或签名问题；
- 相同未检查返回值；
- 相同软删除遗漏；
- 相同 transaction/幂等问题；
- 相同 PendingIntent 身份冲突；
- 相同不安全算术或转换。

只有在以下条件同时满足时才修复额外实例：

- 明确属于同一缺陷类型；
- 因果关系清楚；
- 改动范围安全；
- 能够验证。

否则将其作为后续风险报告，不混入当前修复。

# 十五、阻塞处理

以下情况可能阻塞确认或完整修复：

- 缺少可复现输入、设备、日志、dump 或失败数据库；
- contracts 与实现冲突，仓库无法判断谁正确；
- 需要真实 Android 权限、AlarmManager 或厂商后台行为，但无设备；
- 需要生产数据或服务端行为，当前环境不可访问；
- 用户限制修改范围，但根因属于受限层；
- 当前源码无法按 README 基线构建；
- 无法区分用户已有改动与本次改动。

遇到阻塞时：

1. 先完成所有不依赖该信息的本地调查；
2. 报告已确认事实；
3. 报告领先假设及置信度；
4. 说明缺少的最小证据；
5. 给出下一项最高价值实验；
6. 不伪造完整结论或测试结果。

# 十六、完成标准

只有满足所有适用条件，才能称为“缺陷已修复”：

- 原始症状已稳定复现，或已明确说明为什么无法复现；
- 根因由证据确认，而不是猜测；
- 找到第一个被破坏的边界或不变量；
- 修复位于正确架构层；
- 修改范围最小且无无关重构；
- contracts 与各层实现保持一致；
- 回归测试在旧实现上失败、修复后通过，实际可行时；
- 相关测试、静态分析和构建已通过；
- 跨层缺陷完成对应的真实链路验证，或明确标记未验证；
- 原始复现重复运行通过；
- 已检查窄范围同类缺陷；
- 所有风险、限制和未验证环境已报告。

若条件未全部满足，使用准确表述：

```text
已确认根因，修复已实现，但真实 Android 调度链路未验证。
领先假设已缩小到 Kotlin Alarm Scheduler，仍缺少设备运行证据。
部分修复：Contract 已统一，C++ 回归测试通过，Flutter 完整构建因环境问题未运行。
```

# 十七、最终报告格式

返回紧凑但可审计的报告。

## 1. 诊断

- 症状；
- 已确认根因，或尚未确认时的领先假设；
- 第一个错误边界；
- 因果链；
- 根因置信度。

## 2. 证据

- 复现命令与结果；
- 关键运行时或静态证据；
- 跨层 payload/状态比较；
- 区分性实验及其排除/支持的候选；
- 相关 `request_id` 或业务对象 ID，必要时脱敏。

## 3. 修改

- 修改文件；
- 每项修改恢复了哪个不变量；
- 为什么该层拥有修复职责；
- Contract 是否变化；
- 有意延期的工作。

## 4. 验证

- 实际执行的测试和检查命令；
- 每条命令的准确结果；
- 回归测试在修复前后的行为；
- 原始复现重复结果；
- 未验证设备、ABI、时区或环境。

## 5. 风险

- 兼容性；
- 数据迁移或历史脏数据；
- 性能；
- 并发；
- 安全与隐私；
- Android 厂商差异；
- 发布监控指标；
- 回滚信号和回滚边界。

不得夸大置信度。若根因仍未确认，明确说明下一项信息增益最高的实验。

# 十八、BUG_REPORT_TEMPLATE.md 映射

模板字段映射如下：

- `Expected behavior` / `Actual behavior` → 阶段 1 Case Record。
- `Reproduction` / `Frequency` → 阶段 2。
- `Environment` → 阶段 0 和阶段 2。
- `Evidence` → 阶段 2 和阶段 3。
- `Regression window` / `Recent changes` → 阶段 3。
- `Ownership` / `Threading` / `State machine` → 阶段 3 和阶段 4。
- `Experiments already tried` → 阶段 4；除非可靠性可疑，否则不重复。
- `Contracts / MethodChannel / Native call` → 阶段 0、3、5。
- `Timezone / local date / recurrence` → 阶段 1、3、5。
- `Constraints and requested scope` → 阶段 7。
- `Definition of done` → 阶段 8、9 和完成标准。

模板存在占位符或缺失字段时，先检查仓库。只询问无法本地得到、且会实质改变下一步行动的信息。