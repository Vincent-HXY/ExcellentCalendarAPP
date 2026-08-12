前两个阶段已经完成：

1. Anniversary（纪念日）相关 Contract Layer 的补全；
2. Flutter MethodChannel → Kotlin → Kotlin JNI interface 的 Android Bridge 开发。

现在进入第三阶段：

# 实现 Anniversary 的 C++ Core，并真正打通 Kotlin → JNI → C++ → Storage → C++ Response 的完整链路

本阶段目标不是简单增加几个 JNI 函数，而是按照当前项目既有架构，完整实现 Anniversary 在 C++ Core 中当前 Contract 已经定义的能力，使 Flutter 发起的 Anniversary 请求经过 Kotlin 后，可以真正进入 C++ Core 完成业务处理、持久化和查询，并通过统一的 `NativeResult<T>` 原路返回。

最终链路应当形成：

```text
Flutter Anniversary
        ↓
MethodChannel
        ↓
Kotlin Anniversary Handler
        ↓
NativeAnniversaryBridge
        ↓
JniNativeCalendarCoreBridge
        ↓
Kotlin external JNI
        ↓
C++ JNI Adapter
        ↓
C++ Boundary Contract
        ↓
Anniversary Workflow / Core
        ↓
Anniversary Repository
        ↓
当前 Calendar Core Storage
        ↓
Anniversary Domain Result
        ↓
C++ Boundary Response
        ↓
NativeResult<T>
        ↓
JNI
        ↓
Kotlin
        ↓
Flutter
```

本阶段必须真正把这条链路打通。

---

# 一、开始前必须重新检查当前最新实现

不要根据旧文档示例或历史代码直接开始写 Anniversary。

首先完整检查当前工作区中的：

```text
README.md
DATA_MODEL.md

contracts/**
    method_channels.yaml
    native_calls.yaml
    error_codes.yaml
    enums.yaml
    anniversary/**
    reminder/**
    recurrence/**
    category/**
    common/**
```

特别注意：

> 必须以当前工作区中上一阶段已经修改完成的最新 `contracts/**` 为协议真相源。

不要使用历史版本的 Anniversary Contract，也不要根据 README 中的示例猜测当前 API。

然后检查上一阶段已经完成的 Android/Kotlin Anniversary Bridge：

```text
NativeAnniversaryBridge.kt
NativeCalendarCoreBridge.kt
JniNativeCalendarCoreBridge.kt

Anniversary MethodChannel Handler
Anniversary Kotlin Contract / DTO
JNI external declarations
相关 Kotlin tests
```

确认 Kotlin 当前实际上期待哪些 JNI symbol、参数形式和返回形式。

最后检查当前 C++ Core 中已经稳定运行的类似模块，重点参考：

```text
Event
Reminder
Recurrence
Category
Notification
```

现有实现，包括：

```text
JNI Adapter
Boundary Contract
JSON parsing / serialization
NativeResult
Domain Model
Engine / Service
Workflow
Transaction
Repository
Storage implementation
Error mapping
Tests
```

Anniversary 必须延续现有 C++ 架构，不要为 Anniversary 单独建立另一套体系。

---

# 二、实现范围

本阶段主要允许修改：

```text
cpp_core/**
```

包括完成 Anniversary 所必需的：

```text
JNI Adapter
Boundary Contract
Domain Model
Application / Workflow
Repository
当前 Storage Adapter / Storage implementation
Reminder 生命周期协作
Error mapping
C++ tests
JNI integration wiring
```

Android / Kotlin、Flutter 和 contracts 原则上视为已经完成的上游协议实现。

不要重新设计这些层。

如果 C++ 实现过程中发现：

```text
Kotlin JNI declaration
contracts/native_calls.yaml
JSON Schema
C++ 可实现语义
```

之间存在明确冲突，请先确认冲突来源。

只有属于明显 ABI / wiring 错误、并且可以通过极小修改修复时，才允许对 Kotlin JNI 边界做最小修正。

不得借本次任务重新修改 Flutter UI、Flutter Anniversary 业务逻辑或大规模重新设计 Contract。

---

# 三、Contract 和 Kotlin JNI declaration 是 C++ 的入口真相源

不要自行决定 Anniversary 应该有哪些 C++ API。

请读取最新：

```text
contracts/native_calls.yaml
```

找出全部：

```text
anniversary.xxx
```

并逐项实现。

同时与：

```text
JniNativeCalendarCoreBridge
```

中当前 Anniversary JNI external declaration 一一对应。

形成：

```text
native_calls.yaml
        ↕
Kotlin external JNI declaration
        ↕
C++ JNI export
        ↕
C++ Boundary entrypoint
```

必须保证：

```text
方法数量一致
方法语义一致
参数一致
request schema 一致
response schema 一致
错误语义一致
```

禁止：

```text
Kotlin 有 JNI declaration，但 C++ 没有 export
C++ 有 Anniversary entrypoint，但 Contract 没有声明
同一个操作 Kotlin/C++ 使用不同方法名
C++ 私自增加跨层参数
C++ 返回 Contract 未声明字段
```

---

# 四、实现 C++ JNI Adapter

为所有当前 Anniversary native calls 补齐真实 JNI export。

JNI Adapter 只负责：

```text
JNI 参数接收
        ↓
转换成 C++ 可处理的边界输入
        ↓
调用 Anniversary Boundary / Workflow
        ↓
获取 NativeResult
        ↓
转换成 JNI 返回值
```

不要把 Anniversary 核心业务逻辑写在 JNI function 中。

JNI 层不得负责：

```text
计算下一次纪念日
计算周年数
管理 Reminder 生命周期
直接操作 Storage
拼业务 Response
实现 Anniversary 校验规则
```

这些逻辑必须进入对应 C++ 层。

JNI 方法命名、library loading、string/JSON 传输方式以及异常处理必须严格遵循项目现有 Event / Reminder JNI 实现。

不要发明第二种 JNI serialization protocol。

---

# 五、实现 Anniversary Boundary Contract

根据：

```text
contracts/anniversary/**
```

建立 C++ 本土化 Boundary Contract。

需要根据实际 Contract 实现对应：

```text
Request boundary type
Response boundary type
JSON → Request parser
Response → JSON serializer
NativeResult serializer
NativeError mapping
```

具体有哪些 Request / Response 类型，以当前 Contract 为准。

不要机械创建并不存在的：

```text
Create
Update
Delete
Detail
List
Upcoming
```

全部接口。

Contract 有什么就实现什么。

---

## Boundary 与 Domain 必须分开

不要让：

```text
CreateAnniversaryRequest
```

直接充当 Anniversary Domain Model。

正确关系：

```text
JSON
 ↓
Boundary Request
 ↓
Domain Command / Workflow Input
 ↓
Domain Model
 ↓
Domain Result
 ↓
Boundary Response
 ↓
JSON
```

跨语言字段遵守 Contract 的：

```text
snake_case
```

C++ 内部字段命名可以按照项目现有规范。

---

# 六、实现 Anniversary Domain Model

根据最新：

```text
DATA_MODEL.md
+
contracts/**
```

实现当前阶段需要的 Anniversary Domain Model。

Domain Model 只保存稳定业务事实。

例如 Contract 当前存在的：

```text
id
title
date
calendar type
category
recurrence
note
importance
created / updated / deleted timestamps
```

应按照最新 Contract 和 Data Model 决定最终结构。

不要把 UI 派生状态作为核心存储事实，例如：

```text
days_remaining
countdown_text
years_elapsed
is_today
display_subtitle
formatted_date
```

如果 Contract 需要返回这些派生数据，也应该在查询 / workflow 阶段计算，而不是作为 Anniversary 主实体永久保存。

---

# 七、当前不实现农历

本阶段 Anniversary 只实现当前项目已经确定支持的日历能力。

当前明确：

```text
不支持 lunar anniversary
```

不要实现：

```text
农历转换
闰月
lunar occurrence
农历年份计算
```

也不要为了未来农历支持重新修改 Anniversary Domain。

如果 Contract 中仍然残留与当前决策冲突的 lunar 必选行为，请报告 Contract 冲突，而不是自行扩展业务。

---

# 八、实现 Anniversary Workflow / Service

Anniversary 的业务操作不要全部堆在 Repository 或 JNI 中。

按照项目现有架构建立合理的：

```text
AnniversaryService
AnniversaryEngine
AnniversaryWorkflowService
```

或当前项目已有同类命名结构。

具体类名以现有项目风格为准。

Workflow 层负责：

```text
接收 Boundary 转换后的业务输入
执行业务校验
操作 Anniversary Repository
协调 Reminder / Recurrence 等相关领域
保证跨实体生命周期一致性
生成 Domain Result
```

不要为了 Anniversary 创造一套新的 Application Architecture。

---

# 九、Anniversary 与 Reminder 必须在 C++ 中保持一致

继续遵守项目已有模型：

```text
Anniversary
      ↓
Reminder
```

Reminder 是独立实体。

不得把 Reminder 直接嵌入 Anniversary 作为第二个领域真相源。

如果当前 Anniversary Contract 支持创建 / 修改提醒，则最终应保存为：

```text
Reminder.target_type = anniversary
Reminder.target_id = Anniversary.id
```

的一条或多条独立 Reminder。

---

## 生命周期一致性

重点检查以下操作当前 Contract 是否要求 Reminder 联动：

```text
anniversary.create
anniversary.update
anniversary.delete
anniversary.restore（如果存在）
```

例如：

### Create

如果请求中包含 Reminder configuration：

```text
创建 Anniversary
+
创建对应 Reminder
```

应该在一个 C++ workflow 中完成。

### Update

如果 Anniversary 的：

```text
date
recurrence
reminder configuration
```

发生变化，需要根据最新 Contract 和 Reminder 设计更新关联 Reminder。

不能只修改 Anniversary，留下旧 Reminder 指向错误日期。

### Delete

删除 Anniversary 时，需要正确处理仍然有效的关联 Reminder。

不得出现：

```text
Anniversary 已删除
但 Reminder 仍然继续触发
```

---

# 十、跨实体操作必须使用 Workflow / Transaction

如果一个 Anniversary 操作同时修改：

```text
Anniversary
+
Reminder
```

甚至：

```text
Recurrence
```

必须参考当前 Event lifecycle workflow 的 transaction 设计。

目标是：

```text
全部成功
或者
全部失败
```

不能出现：

```text
Anniversary create 成功
Reminder create 失败
```

但 API 仍然返回半成功的情况。

如果当前 Repository / Storage 已经存在 transaction abstraction，应复用。

如果当前存储实现没有通用 transaction，也应按照现有 Event/Reminder workflow 的一致性机制实现最小必要能力。

不要为了 Anniversary 重构整个 Storage subsystem。

---

# 十一、Recurrence 语义不要重新设计

上一阶段 Contract 已经负责确定 Anniversary 与 Recurrence 的关系。

本阶段 C++：

```text
只实现已经确定的 Contract 语义
```

不要重新决定：

```text
Anniversary 是否默认 yearly
recurrence_id 是否应该取消
yearly 是否应该隐式生成
```

如果 Contract 已经规定：

```text
create request
→ recurrence configuration
```

则按照它实现。

如果 Contract 规定 Anniversary 自身表达周期，则按照 Contract 实现。

不要形成：

```text
Anniversary 自己 yearly
+
Recurrence 同时 yearly
```

两个重复规则真相源。

---

# 十二、实现日期和派生值计算

Anniversary 是 date-only 业务对象。

必须遵守项目约定：

```text
date = 用户本地日期
datetime = UTC 精确时间点
```

不要把：

```text
2026-08-09
```

擅自转换成：

```text
2026-08-09T00:00:00Z
```

作为 Anniversary 原始业务日期。

如果当前 Contract 要求返回：

```text
next occurrence
days remaining
years elapsed / anniversary number
```

则由 C++ 使用明确规则动态计算。

必须处理必要边界情况，例如：

```text
今年纪念日已经过去
今天正好是纪念日
跨年
闰年 2 月 29 日
原始年份缺失或存在时的周年数语义
```

具体输出仍然必须符合 Contract。

不要自行增加新的派生字段。

---

# 十三、实现 Anniversary Repository

Anniversary 必须通过 Repository 访问 Storage。

禁止：

```text
JNI 直接读写文件
Workflow 直接拼 Storage JSON
Domain Service 直接操作文件
```

按照现有 C++ Repository 模式实现 Anniversary：

```text
AnniversaryRepository
```

或项目当前同等职责的接口。

至少支持当前 native calls 完成闭环所需要的：

```text
insert
update
find/get
list/query
soft delete
```

具体方法数量根据真实 Contract 决定。

不要为了理论完整性设计当前没有调用方的方法。

---

# 十四、接入当前 Calendar Core Storage

本阶段的目标是：

```text
Anniversary 真正可持久化
```

但不要擅自改变项目当前存储技术路线。

当前项目仍以现有 Calendar Core Storage 为准。

如果当前 Event / Reminder 使用：

```text
JSON Storage Repository
```

则 Anniversary 继续使用同样模式。

不要为了 Anniversary 单独：

```text
引入 SQLite
创建另一套数据库
加入 ORM
创建新的持久化框架
```

当未来整个项目统一迁移 SQLite 时，再统一迁移。

Anniversary Storage 应与现有：

```text
CalendarCoreStorageDirectoryResolver
calendar_core_storage_json
Repository
```

体系兼容。

---

# 十五、软删除

如果最新 Contract / Data Model 继续采用：

```text
deleted_at
```

则 Anniversary 删除应遵循项目现有 soft delete 规则。

普通 query/list 默认不得返回已软删除 Anniversary，除非 Contract 明确要求。

不要：

```text
delete request
→ 直接物理删除记录
```

同时删除或取消关联 Reminder 的策略必须符合当前 Reminder 生命周期约定。

---

# 十六、错误处理

所有 C++ Boundary 失败统一返回：

```text
NativeResult<T>
```

错误码必须来自：

```text
contracts/error_codes.yaml
```

不得在 C++ 中自行发明：

```text
"invalid anniversary"
"create failed"
"date error"
```

作为跨层协议错误。

区分：

```text
Contract parse error
Domain validation error
Not found
Repository / storage error
Internal error
```

并映射到当前已经定义的错误码。

同时：

```text
C++ exception
filesystem exception
JSON parse exception
repository failure
```

不得跨 JNI boundary 直接逃逸导致 Android 进程崩溃。

必须在 C++ boundary / JNI 层转换成合法 NativeResult failure。

但不能使用：

```cpp
catch (...) {
    return {};
}
```

吞掉错误。

---

# 十七、不要影响其他业务模块

本次核心开发范围是：

```text
Anniversary
```

允许为了 Anniversary 复用：

```text
Reminder
Recurrence
Category
common transaction
common storage
common boundary
```

但只允许进行必要的最小增量修改。

不得借本任务：

```text
重构 Event Engine
重写 Reminder Engine
更换 Storage 架构
重新设计 NativeResult
修改整个 JNI API
批量调整 C++ namespace
引入新的 JSON 库
引入新的 ORM
```

如果共享组件必须新增能力，应保持：

```text
向后兼容
不改变原有语义
原有测试继续通过
```

---

# 十八、必须实现真实 JNI 闭环

上一阶段 Kotlin 已经完成 JNI declaration。

因此这次不再接受：

```text
blocked_by_cpp
```

作为最终状态。

需要真正实现对应 C++ JNI symbol，并让现有：

```text
JniNativeCalendarCoreBridge
```

能够加载和调用。

至少选择一个具有代表性的 Anniversary 请求完成真实 smoke test，例如优先：

```text
anniversary.create
```

验证：

```text
Kotlin
 ↓
JNI
 ↓
C++ Boundary
 ↓
Anniversary Workflow
 ↓
Repository
 ↓
Storage
 ↓
NativeResult
 ↓
JNI
 ↓
Kotlin
```

真实成功。

然后验证查询接口能够重新读取刚才写入的数据，证明不是 mock success。

如果当前 Contract 定义 create + detail/list，可以采用：

```text
create
→ get/detail/list
```

完成最小持久化闭环。

---

# 十九、测试要求

Anniversary C++ 不能只依靠 Android 手工测试。

至少补充以下类型的测试。

## Boundary Contract Tests

验证：

```text
JSON
→ Anniversary Request
→ Domain
→ Response
→ JSON
```

字段和类型与 Contract 一致。

覆盖：

```text
required fields
nullable fields
enum
date
array / nested data
invalid request
NativeResult error
```

---

## Domain / Workflow Tests

验证当前实现支持的核心 Anniversary 行为，例如：

```text
create
update
delete
get/detail
list
next occurrence
```

以真实 Contract 为准。

---

## Repository / Storage Tests

至少验证：

```text
创建后可重新读取
更新后持久化
删除后普通查询不可见
重启 / 重新创建 repository 后仍可读取
非法或损坏 storage 能正确返回错误
```

---

## Reminder Lifecycle Tests

如果 Anniversary Contract 当前包含 Reminder：

验证：

```text
创建 Anniversary + Reminder
修改 Anniversary 日期后的 Reminder 一致性
删除 Anniversary 后 Reminder 不继续触发
workflow 失败不会留下半完成状态
```

---

## Edge Case Tests

根据实际功能覆盖：

```text
跨年
今天就是 Anniversary
今年已经过去
2 月 29 日
空标题
非法日期
不存在的 ID
重复更新
软删除
```

---

## JNI / Android Integration Test

必须至少验证一个现有 Kotlin Anniversary JNI 调用能够进入真实 C++ implementation 并返回符合 Contract 的 NativeResult。

不得使用 Fake Bridge 代替这个最终验收。

Fake 可以保留用于 Kotlin unit test，但最终 JNI smoke test 必须使用真实 native library。

---

# 二十、构建与回归验证

按照 README 当前项目基线执行完整 C++ build + test。

不要只运行旧的 CTest binary。

至少执行项目规定的：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

并执行 Android/Kotlin 所需的 native build / integration smoke test，确认：

```text
Kotlin external declaration
↔
C++ JNI symbol
```

不存在 ABI / symbol mismatch。

同时确保现有：

```text
Event
Reminder
Notification
Recurrence
Category
```

相关 C++ 测试没有回归。

---

# 二十一、禁止为了让测试通过制造假实现

不可接受：

```text
JNI 直接返回固定 JSON
Repository 使用仅测试内存假数据替代正式实现
create 成功但没有真正持久化
list 返回 hard-coded sample
Reminder workflow 使用 TODO 跳过
C++ JNI symbol 只作为空 stub
```

本阶段目标是生产实现，不是仅消除 linker error。

如果某项功能确实被当前 Contract 或现有架构阻塞，应明确报告，而不是制造假成功结果。

---

# 二十二、完成后的 Coverage Matrix

最终提供：

```text
Anniversary C++ Coverage Matrix
```

至少包含：

```text
native_call
Kotlin JNI method
C++ JNI symbol
Boundary Request
Boundary Response
Workflow / Service
Repository
Storage
Reminder interaction
Tests
最终状态
```

状态只允许：

```text
implemented
verified
not_required
blocked
```

如果出现 `blocked`，必须说明明确的外部阻塞原因。

不能把尚未完成的功能标记为 implemented。

---

# 二十三、最终端到端验收

完成后逐项确认：

1. 最新 `contracts/native_calls.yaml` 中所有需要 C++ 实现的 Anniversary native calls 均有实现；
2. 每个 Kotlin Anniversary JNI external method 都能找到准确的 C++ JNI symbol；
3. JNI 方法中不存在 Anniversary 业务逻辑；
4. Boundary Request / Response 与最新 JSON Schema 一致；
5. Anniversary Domain 与 Boundary Contract 已分离；
6. Anniversary 核心业务规则位于 C++；
7. Anniversary 通过 Repository 访问 Storage；
8. Anniversary 可以真实持久化并重新读取；
9. 不存在 hard-coded / fake production result；
10. Anniversary 与 Reminder 生命周期保持一致；
11. 跨实体操作不会产生明显半成功状态；
12. soft delete 行为符合当前项目约定；
13. date-only 与 datetime 没有混用；
14. 当前没有实现 lunar；
15. 所有错误通过 NativeResult / NativeError 返回；
16. C++ exception 不会穿过 JNI 导致 Android 崩溃；
17. 原有 Event / Reminder 等功能没有发生回归；
18. `excellent_calendar_check` 通过；
19. Android native build 通过；
20. 至少一个 Kotlin → JNI → C++ → Storage → Response 的真实 Anniversary 请求完成 smoke test；
21. git diff 不包含与 Anniversary 无关的大规模重构。

---

# 二十四、完成后的最终报告

完成后不要只告诉我“已实现”。

请明确报告：

```text
新增了哪些 C++ 文件
修改了哪些 C++ 文件

实现了哪些 anniversary native calls

每个调用的真实链路：
Kotlin
→ JNI
→ Boundary
→ Workflow
→ Repository
→ Storage

Anniversary 与 Reminder 如何保证一致性

哪些派生值由 C++ 动态计算
哪些字段真正持久化

使用了哪个现有 Storage backend

增加了哪些测试
运行了哪些 build / test 命令
测试结果是什么

真实 JNI smoke test 使用了哪个 anniversary 方法
写入了什么
重新读取到了什么

是否修改了任何 Kotlin / Contract 共享文件
为什么

是否仍存在未完成或被阻塞的能力
```

如果发现当前最新 Contract、Kotlin JNI declaration、Data Model 和 C++ 既有架构之间存在不可兼容冲突：

不要静默选择一种实现。

请明确给出：

```text
冲突位置
当前各层分别是什么
为什么无法同时满足
影响范围
推荐修复方案
```

然后继续完成所有不依赖该冲突的工作。

本阶段结束的标准不是“C++ 可以编译”，而是：

```text
Flutter 已定义的 Anniversary 能力
        ↓
Kotlin 已完成的 Bridge
        ↓
真实 JNI
        ↓
真实 C++ Anniversary Core
        ↓
真实本地持久化
        ↓
正确 NativeResult
```

这一整条链路在当前项目架构下真正闭环。
