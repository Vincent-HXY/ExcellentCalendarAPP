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

## RES-ANN-005 Anniversary Reminder R1 发布门禁关闭

- 严重程度：P1（发布门禁）
- 产生原因：四层生产链已集成，但首次真机正常到点时 Alarm Receiver 丢失冻结的 `planned_at`，V2 Coordinator 先执行 Recovery，把准时 Reminder 错误消费为 `anniversary_catch_up`；完整设备矩阵也尚未逐项完成。
- 解决方式：Receiver 继续传递 `planned_at`，Coordinator 先普通投递匹配时刻的 C++ 权威 Reminder，再恢复更早逾期项；可重试普通失败不会在同次 Alarm 中改类。realme RMX3687 / Android 13 已验证进程退出后的正常到点、系统正文、持久化 `kind=reminder`、sent、年度 successor、delivery identity、点击与去重；Contract/C++/Flutter/Android/Lint/Release APK 回归通过。产品负责人于 2026-08-25 明确接受其余设备矩阵风险并批准 `integrated + active`。
- 可吸取的教训：Dispatcher Alarm 必须携带并使用冻结计划身份；发布风险接受只能改变门禁结论，不能把未执行设备矩阵写成已通过。
- 来源：原 `OPEN-ANN-001`、纪念日总计划与 2026-08-25 发布复审。

## RES-ANN-006 Anniversary 设备集成测试与正式应用隔离

- 严重程度：P1（测试数据安全）
- 产生原因：历史 Flutter 集成测试曾复用正式 application ID，测试工具卸载应用时连同正式私有数据一起清除。
- 解决方式：Debug/device integration 固定使用 `.device_test` application ID、独立 `calendar_core_device_test_storage_json`，Application 在首个业务副作用前同时校验包名与 Store；Release 保持正式 ID。realme Android 13 已运行完整 Native 集成测试与 Alarm 验收，测试数据和通知可清理，正式应用及其数据未被操作。
- 可吸取的教训：设备测试隔离必须由构建 ID、存储根和运行时 fail-fast 三重保证，不能依赖操作人员记忆。
- 来源：原 `OPEN-TEST-001` 与 2026-08-25 真机复验。
