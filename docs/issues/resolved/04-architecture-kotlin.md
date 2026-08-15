# 已解决：Kotlin 职责边界与工程命名

## RES-KOT-001 MethodChannel 总入口与 v2 validator 跨模块膨胀

- 严重程度：P2（评估）
- 产生原因：`NativeMethodChannelHandler` 同时承担分发、校验、Android operation、Native 执行、错误适配和调度后置逻辑；单一 validator 覆盖多个领域，形成 God Object。
- 解决方式：保留兼容 façade，按 Runtime/Event/Anniversary/Reminder/Notification 拆分 handler，按领域拆 validator；共享执行和 post-commit reconcile 分别进入 `NativeCallExecutor` 与 `MutationScheduleHook`，模块只依赖窄 Bridge。
- 可吸取的教训：兼容入口可以稳定，但变化职责必须向模块内部收敛；共享模板不应了解具体业务后置动作。
- 来源：`problems.md`“MethodChannel 总入口与 V2 Contract 校验持续跨模块膨胀”。

## RES-ARCH-001 Native Bridge 与正式存储目录命名长期误导

- 严重程度：P3（源文档）
- 产生原因：Event 起步阶段的 `NativeEventBridge` 后来承担多个领域，正式目录仍沿用 `test_storage_json`，历史命名没有随职责演进更新。
- 解决方式：拆分为聚合 `NativeCalendarCoreBridge` 与各领域窄 Bridge；正式目录切换为 `calendar_core_storage_json`，且 v1 决策明确不再把 `test_storage_json` 当迁移来源。
- 可吸取的教训：名字是架构约束的一部分；测试命名进入生产路径会误导数据安全和职责判断，应在边界扩张时及时收敛。
- 来源：`[P3] 存在会长期误导开发的命名`。
