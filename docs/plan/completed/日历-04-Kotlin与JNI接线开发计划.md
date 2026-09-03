# 日历-04：Kotlin 与 JNI 接线开发计划

Status: Completed / Delivered / Archived

负责人：Android/Kotlin 下层（`android-kotlin-native-feature`）  
允许修改：`flutter_client/android/**`  
依赖：日历-02 Contract、日历-03 C++ 可调用 endpoint

## 1. 交付目标

在既有单一 Calendar Core runtime owner 上新增窄 Calendar handler/bridge，把两个 MethodChannel 方法严格映射到两个 C++ internal call。Kotlin/JNI 不计算日期重叠、recurrence、Habit 状态、排序、圆点或本地化文案。

本任务不新增权限、Alarm、Notification、Receiver、Worker、后台任务或平台存储。

## 2. 实现清单

### 2.1 Contract DTO 与校验

- [x] `CalendarContracts`（或同职责拆分）覆盖两个 request/response；
- [x] required、显式 null、额外字段、date/timezone/enum/integer/string/array 形状严格校验；
- [x] section discriminated response 只允许对应 typed item；
- [x] `snapshot_token`/cursor 前缀、长度和 nullable 语义严格一致；
- [x] `has_more/next_cursor/items` 条件和 `NativeResult` 互斥不变量校验；
- [x] Calendar 专属错误加入 Kotlin error registry，不把异常映射为空成功。

### 2.2 窄桥接

- [x] 新增 `NativeCalendarViewBridge` 窄接口；
- [x] `NativeCalendarCoreBridge` 只聚合继承/委托，不让 Calendar handler 依赖万能 bridge；
- [x] 新增 `JniCalendarViewBridge`，复用 `AndroidNativeBridgeFactory` 与进程级 runtime；
- [x] JNI 两个函数签名、UTF-8 JSON ownership、null/exception/runtime-not-ready 分支一致；
- [x] C++ 查询运行在既有后台执行器，不阻塞 Android 主线程；
- [x] MethodChannel result 恰好完成一次，engine detach 后安全。

### 2.3 Handler 与注册

- [x] 新增 `CalendarMethodHandler`；
- [x] 路由 `calendar.range_summary` / `calendar.list_day_items`；
- [x] 在 production handler composition 注册，不添加 Fake fallback；
- [x] C++ error code/retryable/details 原样通过类型化 mapper；
- [x] 不修改 Reminder scheduler 或 Notification tap 分流。

### 2.4 JNI 与 ABI

- [x] Android CMake/源清单包含 Calendar JNI adapter；
- [x] Debug 与 release-like 的 arm64-v8a、armeabi-v7a、x86_64 导出两个目标符号；
- [x] 真实 JNI response 与 Calendar fixture 字段逐一一致；
- [x] 超长 cursor、Unicode 标题、大 JSON、native null/exception 无 local-ref 泄漏或 double callback。

## 3. 测试矩阵

- [x] Handler 正常、未知方法、缺字段、null、额外字段、未知 enum；
- [x] snapshot malformed/expired、cursor malformed/mismatch；
- [x] 三个 section typed response 与错误 envelope；
- [x] Fake narrow bridge unit test（只做测试替身）；
- [x] Jni bridge 参数顺序、字符串 ownership、异常与 runtime 未初始化；
- [x] 同一 fixture 经过 Kotlin parser 与真实 JNI；
- [x] 并发请求不在主线程、不 double result；
- [x] 既有 Event/Habit/Anniversary/Reminder handler 回归；
- [x] APK 三 ABI 符号与 native smoke。

## 4. 实施结果（2026-08-31）

- Calendar 定向与 Android 全量 unit、`lintDebug`、Debug 主/测试 APK、三 ABI JNI/C++ 导出均通过；既有 Android 13 设备只读 production bridge smoke 通过。
- 旧临时 runtime seeded runner 曾验证三类真实链，但其进程内热切换全局 runtime 的测试设计已删除。新 runner 仅使用 `.device_test` 默认 production factory 并经真实方法清理数据；代码、APK 与静态安全审计通过。
- 新安全 runner 的“只读 → 三类 seed → 只读”真机复测因 realme/Oppo 安装确认页后设备断连而未验证。正式包及数据从未触碰。
- `assembleRelease` 的 Flutter/native 三 ABI 已通过，最终 Java 编译被既有 release classpath 缺少 `integration_test` plugin 阻塞；该环境问题不归因于 Calendar，但仍阻断发布 APK。

必须执行适用的：Android 定向及全量 unit、`lintDebug`、Debug APK、androidTest APK、Calendar JNI instrumentation、Native smoke test/analyze/APK。

## 5. 完成门禁

- 公开方法到 Handler→窄 bridge→JNI→C++ endpoint 闭环；
- Kotlin 没有领域排序、状态、timezone fallback 或本地化规则；
- production 没有 Fake/seed/fallback；
- 所有实际执行命令和结果可复核；未执行设备/ABI 项明确标记；
- 不自行修改 Contract 或激活 capability。

## 6. 下层回报格式

向总工程师提供：修改文件、注册点、线程模型、JNI 符号、Contract 字段映射表、单元/APK/androidTest/smoke 结果、未验证设备项和剩余风险。
