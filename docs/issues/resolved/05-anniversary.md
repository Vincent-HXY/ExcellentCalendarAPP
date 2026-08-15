# 已解决：Anniversary

## RES-ANN-001 Anniversary 年度规则已设计但未落地

- 严重程度：P1（评估）
- 产生原因：Contract 先冻结了独立 `AnniversaryRecurrence`，但 C++ Domain/Workflow/Repository、双 Store 事务与 JSON Storage 尚未同步实现，存在上层误把 planned 当可用的风险。
- 解决方式：2026-08-10 完成六条公开能力、专用 recurrence Store、workflow journal、C++/JNI/Kotlin/Dart 接入；一次性与年度规则切换保持同事务，真实 Android create/detail/soft-delete 持久化 smoke 通过，状态切换为 integrated。
- 可吸取的教训：设计存在不代表生产可用；Contract 状态必须阻止上层在下层缺失时伪装能力。
- 来源：`problems.md`“Anniversary 年度规则已设计但尚未落地”。Reminder 关联语义仍在 `open.md`。

## RES-ANN-002 同进程第二套 v2 Bridge 竞争全局 C++ runtime

- 严重程度：P1（源文档）
- 产生原因：smoke harness 使用临时目录自行初始化 Bridge，而 Application/Worker 同时通过正式 factory 初始化进程级单例，造成 runtime ownership 竞争。
- 解决方式：Debug Receiver 与 AndroidTest 共用 `AnniversaryJniSmokeRunner`，只从正式 `AndroidNativeBridgeFactory` 取得 Bridge；需要隔离 Store 的测试必须使用独立进程。
- 可吸取的教训：进程级 Native runtime 必须有唯一 owner；测试不能绕过正式 composition 复制第二套生命周期。
- 来源：`[P1] 同一 Android 进程中创建第二套 Calendar Core v2 bridge...`。

## RES-ANN-003 minSdk 24/25 使用 API 26 `java.time`

- 严重程度：P1（源文档）
- 产生原因：Kotlin validator 直接调用 API 26 的 `LocalDate` / `Instant`，项目 minSdk 24 且未启用 desugaring。
- 解决方式：保持固定 wire 格式检查，并以纯整数日期、闰年和时间范围完成边界校验；未把 Anniversary 业务投影移入 Kotlin，也未提高 minSdk。相关 lint、单测和真机 smoke 通过。
- 可吸取的教训：边界 validator 应做最小协议校验；引入平台日期 API前必须核对 minSdk 和 desugaring 配置。
- 来源：`[P1] Anniversary Kotlin Contract validator 在 minSdk 24/25 使用 API 26 java.time`。

## RES-ANN-004 list 排序在 top-level 与 pagination 中不一致

- 严重程度：P2（源文档）
- 产生原因：专属 top-level sort 与公共 Pagination nested sort 同时开放，默认方向和合法 key 不一致，Dart/Kotlin/C++ 各自解释。
- 解决方式：Anniversary pagination 只保留 page/page_size/cursor；排序只允许 top-level，默认 `target_occurrence_date/asc`，各层统一拒绝 nested sort，并增加正反回归。
- 可吸取的教训：同一语义只能有一个协议位置和一个默认值；公共 DTO 不应强行复用到语义更窄的领域接口。
- 来源：`[P2] top-level 与 nested pagination 排序位置和默认值不一致`。
