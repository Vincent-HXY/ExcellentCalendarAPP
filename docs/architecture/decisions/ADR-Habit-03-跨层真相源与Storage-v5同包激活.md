# ADR-Habit-03：跨层真相源与 Storage v5 同包激活

Status: Accepted
Date: 2026-08-31

## Context

Habit 同时涉及 Flutter 页面、Kotlin 系统调度、JNI/C++ 领域工作流和 SQLite 迁移。分层并行开发若各自计算生命周期、统计或身份，或让 Fake、Alarm 状态和多个存储 writer 进入生产链，会形成不可恢复的多真相源和新旧组件混跑。

## Decision

- Contract、identity 和生命周期矩阵先冻结；Flutter、Kotlin/JNI、C++ 与 Storage 在同一 APK revision 中同步升级。早期 Habit 仅为从未激活的 planned 草案，因此首次落地继续使用 Native v2，不制造无历史数据的伪迁移。
- C++ Domain/Workflow 是生命周期、统计、Reminder/action identity 和跨实体事务的唯一业务 owner。Flutter 只提交意图并消费组合投影；Kotlin 只负责严格边界、Android side effect、reconciliation 和明确声明为本机数据的 Appearance。
- Calendar Core SQLite v5 是唯一活动 writer。已有 v4 必须先通过冻结 checker，再用单个事务迁移；旧行、generation、history 和兼容数据必须保留。禁止 JSON/SQLite 双写，旧 runtime 对 v5 必须拒写。
- 开发期 Fake 只能存在于测试或显式预览入口，production composition 不允许 fallback。MethodChannel、Native call、Schema、identity 与 Storage capability 必须在同一发布决策中原子激活；发布例外只能登记为开放风险，不能写成测试通过。

## Consequences

- 后续 Calendar/Search/Sync 使用 Habit 数据时必须复用稳定 Contract 或 C++ 投影，不能在 Dart/Kotlin 重算 streak、rate、lifecycle 或 occurrence identity。
- Android 权限或 Alarm 失败只改变类型化调度 capability，不回滚已经提交的 Habit/CheckIn 业务事务。
- 未来新增 weekly、自定义周期、云端偏好或新持久化字段时，必须先设计新的 Contract revision 和连续 Storage migration；不能静默改变 V1 数据解释。
