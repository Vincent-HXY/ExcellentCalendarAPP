# 纪念日 C++ Core / JNI 开发完成记录

> 模块：纪念日（Anniversary）
>
> 层面：C++ Core / JNI / JSON Storage
>
> 主要开发时间：2026-08-09—2026-08-10
>
> 使用流程：`cpp-core-feature` 为主，按授权补充 `calendar-data-contracts` 与 `android-kotlin-native-feature`

## 最开始的开发要求

前两个阶段已经完成 Anniversary Contract，以及 Flutter MethodChannel 到 Kotlin JNI declaration 的接线，但 C++ 侧仍没有可执行实现。本阶段要求把六条已声明能力真正打通：

- `anniversary.create`
- `anniversary.update`
- `anniversary.delete`
- `anniversary.detail`
- `anniversary.list`
- `anniversary.preview_countdown`

目标链路必须达到：

```text
Flutter / Dart Gateway
→ Kotlin Handler
→ JniNativeCalendarCoreBridge
→ C++ JNI Adapter
→ Boundary Request
→ Workflow / Query Service
→ Repository
→ Calendar Core JSON Storage
→ NativeResult<T>
```

实现必须延续现有 Event、Reminder、Recurrence 的 C++17 分层方式，保持 Boundary、Domain、Application、Repository 和 Storage 分离；使用真实 JSON 持久化和真实 JNI library，不允许用 Stub、Fake 成功结果或 JNI 占位函数冒充完成。

业务要求包括：公历 date-only、一次性和每年重复、动态倒计时、跨年、当天为 0、2 月 29 日处理、分类/重要性过滤、排序、软删除、重启读取、损坏数据拒绝和统一 `NativeResult` 错误返回。用户另外授权了完成 JNI 闭环所需的 Android 接线，以及最小范围的 Contract、Dart、Kotlin `timezone` 同步。

## 为什么改

当时 Flutter 和 Kotlin 表面上已经有 Anniversary API，但调用走到 Kotlin `external` 后没有对应 C++ JNI export，也没有 Anniversary Domain、Workflow、Repository 或正式 Store。实际生产请求无法进入 C++，只能落入 native library/symbol 异常边界，最终返回 `NATIVE_INTERNAL_ERROR`。

同时，Anniversary 是 date-only 领域对象。创建或更新成功后必须立即返回 countdown，如果请求没有明确的 IANA timezone，C++ 无法稳定确定“用户本地今天”，各端可能因设备 offset、时区缩写或 UTC 午夜换算产生不同结果。因此 create/update 也需要与 detail/list/preview 一样显式携带 timezone。

另外，Anniversary 与专属年度规则需要原子写入。如果只增加两个普通 JSON 文件而没有事务恢复机制，进程在写入中断时可能留下 Anniversary 已引用规则但规则不存在，或规则已创建而 Anniversary 未提交的半状态。

## 探索过什么

1. **现有 C++ 架构**：检查了 Event/Reminder 的 Boundary API、`NativeResult`、process-global runtime、Repository、JSON codec、原子文件替换和六 Store workflow journal，确认 Anniversary 应复用同一套分层和错误机制。
2. **事务接入方式**：比较了“把 Anniversary 加入 Event/Reminder 六 Store journal”和“建立 Anniversary 专用窄事务”两种方案。最终选择后者，使 Anniversary 只原子协调 `anniversaries` 与 `anniversary_recurrences`，避免扩大现有核心事务的失败面。
3. **timezone 来源**：比较了隐式读取系统时区、使用 Dart `DateTime.timeZoneName`、持久化 timezone 和请求显式传入。最终复用已有设备时区 Gateway，将 IANA timezone 放入 create/update 请求，但不写入领域实体。
4. **旧 v2 目录兼容**：确认不需要重写 Event/Reminder 数据，也不需要提升整个 Storage 版本；bootstrap 可以在确认现有 v2 数据合法后，幂等创建三个空 Anniversary Store。
5. **JNI 真机入口**：最初尝试在 App 进程中创建另一套临时 storage bridge，随后发现它会与 App/WorkManager 使用的 process-global C++ runtime 竞争并产生 `STORAGE_NOT_INITIALIZED` 假阴性。改为复用正式 `AndroidNativeBridgeFactory` 后问题消失。
6. **Android 验收方式**：AndroidTest APK 已成功构建，但 realme 锁屏时 OEM 阻止首次安装测试 APK，因此补充了仅存在于 Debug 构建、受 `android.permission.DUMP` 保护的 ADB Receiver，仍然调用正式 factory 和真实 `.so`。
7. **静态检查**：`lintDebug` 暴露出 Anniversary Kotlin validator 使用 API 26 `java.time`，而项目 minSdk 为 24；随后改成纯整数日期、闰年和 UTC 时分秒校验。最终 diff 审计还发现 Debug Manifest 的 Flutter `INTERNET` 权限曾被覆盖，已恢复。

## 拒绝了什么

- 拒绝把 Anniversary 做成 Event 的特殊类型，继续保持独立领域对象。
- 拒绝修改 Event/Reminder 既有六 Store journal；Anniversary 使用独立两 Store journal。
- 拒绝在 Kotlin/JNI 中实现倒计时、重复规则或日期业务逻辑；JNI 只做字符串传输和异常封装。
- 拒绝持久化 `timezone`、`days`、`relation`、`target_occurrence_date`、`iso_weekday`、`calculated_at` 等查询投影。
- 拒绝为 Anniversary 单独引入 SQLite、ORM、第二套 Repository 框架或新依赖。
- 拒绝 hard delete；删除继续遵循 `deleted_at` 软删除约定。
- 拒绝伪造农历计算。`calendar_type=lunar` 明确返回 `ANNIVERSARY_CALENDAR_UNSUPPORTED`。
- 拒绝顺带实现 Reminder。当前 Contract 没有 Reminder configuration，occurrence identity、幂等键、重试和 reconciliation 尚未冻结，因此该交互为 `not_required`。
- 拒绝自行发明 list cursor 编码；V1 非空 cursor 明确返回 `FEATURE_NOT_IMPLEMENTED`。
- 拒绝用 Fake Bridge 代替最终验收，也没有通过降低断言、吞错误或默认值让链路看似成功。

## 验证过什么

| 验证层 | 实际结果 |
| --- | --- |
| Contract | 129 个 JSON、7 个 YAML 可解析；129 个唯一 `$id`、72 个本地 `$ref` 闭合；14/14 Anniversary Schema 为 `integrated` |
| C++ | 重新配置后执行 `excellent_calendar_check`，5/5 通过 |
| Anniversary C++ 测试 | 覆盖创建、更新、删除、详情、列表、preview、当天/已过/跨年、2 月 29 日、非法日期、软删除、规则切换、journal 中断重放、旧 v2 增量初始化和损坏 Store |
| Dart/Flutter | Anniversary 定向测试 7 项通过；全量 179/179；`flutter analyze` 无问题 |
| Kotlin | Anniversary Handler/JNI 定向测试和全量 `:app:testDebugUnitTest` 通过；补充缺失/空 timezone、非法日期和非法 UTC Instant 回归 |
| Android 构建 | Debug APK、AndroidTest APK、arm64-v8a/armeabi-v7a/x86_64 Native 构建与 `flutter build apk --debug` 通过 |
| JNI symbol | arm64 Debug `.so` 精确导出 6/6 个 Anniversary member JNI symbol |
| 真机 smoke | realme RMX5100、Android 16/API 36、arm64-v8a：create → JSON 持久化 → detail 重读同一 ID → soft-delete 通过 |
| Lint | Anniversary/Smoke 文件 0 finding；全项目仍被范围外既有 29 errors/20 warnings 阻断 |
| Diff | `git diff --check` 通过；没有暂存、提交或覆盖工作区既有修改 |

最终真机写入数据为：

```text
title = JNI smoke anniversary
date = 2020-02-29
recurrence = yearly + interval 1
timezone = Asia/Shanghai
```

detail 重新读取到相同 ID，随后按 Contract 软删除。测试没有使用 Fake Native Bridge 代替真实 JNI 验收。

## 当时有哪些限制

- V1 只支持公历；农历、春节模板和农历转换均未实现。
- Anniversary Reminder、通知调度、Reminder occurrence identity 和 reconciliation 未设计，不在本轮范围。
- 非空 list cursor 没有冻结编码，保持显式 `FEATURE_NOT_IMPLEMENTED`。
- Flutter 原型中的非默认 kind、Reminder plan 和高层 preview recurrence 签名仍存在边界差异，适配器会在 transport 前显式失败，不静默丢字段。
- 真机只验证了 realme Android 16/API 36、arm64-v8a；另外两个 ABI 仅完成构建，没有对应物理设备验证。
- OEM 阻止了当次 AndroidTest APK 真机安装；最终真实 JNI 证据来自受权限保护的 debug-only Receiver。
- 全项目 `lintDebug` 仍有范围外历史问题，不能记录为全仓 lint 通过。
- smoke 遵循领域软删除，因此 Debug Store 中会留下已删除 tombstone，普通查询不可见。
- create/update 新增必填 timezone 相对早期 planned 草案属于形状变化，但当时 Anniversary 尚未激活、没有历史调用方或持久化 timezone，因此同批首次激活，无需迁移。

## 最终结果

Anniversary 公历 V1 的六条 Native 调用全部实现并切换为 `integrated`。C++ 新增独立 Domain、Application Workflow/Query、Repository abstraction、Boundary JSON/API、JSON codec、专用事务和测试；Android JNI Adapter 精确连接既有 Kotlin external declaration。

最终 Store 为：

```text
anniversaries.json
anniversary_recurrences.json
anniversary_workflow_transactions.json
```

create/update/delete 通过 prepared/committed journal 原子修改 Anniversary 与专属年度规则；detail/list 默认排除软删除数据；preview 不写 Store。年度重复固定为 `yearly + interval=1`，年度到年度保留规则 ID，一次性切年度创建新规则，年度切一次性会原子解除引用并软删除旧规则。

倒计时统一由 C++ 根据请求 IANA timezone 和本地自然日动态计算。真正持久化的只有 Anniversary、AnniversaryRecurrence 的事实字段与生命周期时间；所有 countdown 字段均为查询投影。

最终真实链路已证明：

```text
Kotlin 正式 Factory
→ JniNativeCalendarCoreBridge
→ C++ JNI export
→ Anniversary Boundary / Workflow
→ JSON Storage
→ C++ Response
→ NativeResult success
```

开发中发现的 process-global runtime 测试组装问题、minSdk 日期校验问题和 Debug Receiver 权限问题均已修复并记录。Reminder、农历和 cursor 没有被伪装为完成，保持明确的后续边界。
