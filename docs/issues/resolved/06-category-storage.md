# 已解决：Category、Storage 与发布门禁

## RES-CAT-001 `implemented_unintegrated + blocked` 与生产 Composition 冲突

- 严重程度：P1（源文档）
- 产生原因：Contract 已正确标记 Category 尚未发布，但 Flutter `buildProductionApp()` 提前无条件注入 Native Repository，发布状态和生产依赖不同步。
- 解决方式：设备门禁前用 blocked Repository 隔离；隔离 JNI、正式 Flutter 全链、Event 关联和强停重启通过后，在同一变更中统一切换 MethodChannel、Native Call、Store 和默认/Release composition 为 `integrated + active`，随后删除临时开关。
- 可吸取的教训：发布状态是可执行门禁，不是说明文字；生产入口与 Contract 状态必须原子切换。
- 来源：`[P1] implemented_unintegrated + blocked 与生产 Composition 冲突`。

## RES-CAT-002 Category 回滚失败后新快照仍可见

- 严重程度：P1（源文档）
- 产生原因：原子 replace 后 directory fsync 失败时只做一次脆弱回滚；若回滚 replace/fsync/verify 再失败，Repository 仍可能读取新文件，API failure 与磁盘事实分裂。
- 解决方式：Category opt-in 写入持久 prepared/committed sidecar，保存旧快照或“旧文件不存在”事实；read/write/initialize/load 先收敛未完成恢复，持续失败则保留状态并拒读。覆盖三类回滚故障、即时读取、runtime/子进程重建和安全重试。
- 可吸取的教训：文件 replace 成功不等于事务提交；若 Contract 承诺失败后旧快照权威，恢复状态也必须可持久化且失败时 fail-closed。
- 来源：`[P1] Category 回滚自身失败时，旧快照权威保证失效`。真实断电验证仍在 `open.md`。

## RES-CAT-003 Kotlin 漏登记 `CATEGORY_SORT_ORDER_EXHAUSTED`

- 严重程度：P1（源文档）
- 产生原因：Contract/C++/Dart 已加入稳定错误码，但 Kotlin 常量和允许集合漏项，合法领域错误会被重写为 `CONTRACT_VALIDATION_FAILED`。
- 解决方式：补齐常量与 All 集合，Native Schema/Kotlin 注册表 56/56 对齐；Handler 精确保留错误外壳，真机独立 Store max→null 返回目标错误且文件零变化。
- 可吸取的教训：稳定错误码是跨层协议的一部分；新增时必须有注册表等价性测试和至少一个真实透传负例。
- 来源：`[P1] Kotlin 未登记 CATEGORY_SORT_ORDER_EXHAUSTED`。

## RES-CAT-004 Category 跨层审查整改项未闭环

- 严重程度：P1/P2（综合评估）
- 产生原因：Category 从 Fake 原型进入 Native/Storage 时，Event 引用、三态投影、安全整数、规范化 owner、DTO/Domain/Storage 分离和 JNI ABI 分散演进。
- 解决方式：Event create/update/read/search 统一传输稳定 `category_id`；detail 支持未分类、活动命中、悬空/软删除三态；`sort_order` 上界统一；C++ 单点规范化；Request/Response/Domain/Storage 分离；MethodChannel、Native Call、JNI 与 ABI 一致。
- 可吸取的教训：新领域上线前需要按 Contract→Boundary→Domain→Storage→聚合展示逐层验收，不能只证明 create/list 底层可调用。
- 来源：Category“已关闭的整改项”。产品语义与后续生命周期仍在 `open.md`。
