# ADR-Sync-02：Workspace 生命周期

Status: Accepted (design decision; final Contract evidence is recorded in ct0_gate_status.json)
Date: 2026-09-05

Acceptance: 按用户授权自主落实总计划的 workspace 隔离、生命周期与导入规则。工程决策由本次任务记录；不代表已实现双 runtime 或已通过设备验收。

## Context

当前 Core 为进程级单 runtime，生产目录仍为 `files/local_storage/calendar_core_storage_json`。游客/账号隔离、游客提醒继续运行是云同步-01 §3/§6 已确定的目标，不能从旧单 runtime 推导为登录后暂停游客提醒。

## Decision

- Kotlin 唯一分配 workspace UUID 和拥有 Registry/route revision；C++ 持久化不可变 metadata 并分配不可跨 close/restart 复用的 runtime identity。前台路由和账号 Session 正交。
- Registry 仅公开云同步-02 §8.2 的 ready/locked/empty 三态。恢复读 `workspace.get_state` 不要求 CAS；变更按 workspace/route 与专属 revision 校验。游客提醒 runtime 可与当前账号 runtime 同时存活。
- 退出、clear、revoke 和 retention 严格采用 §6.1、§8.2 的同一 lifecycle journal、writer gate、transport fence 和 seed。常规 active clear 必须先在线收敛并接纳 fence，之后才毁 key。安全/隐私销毁保留无业务 payload 的 future fence 恢复证据。
- 保留缓存只能是已建立可信 deadline 的隐藏加密缓存。30 天为目标窗口；不以本机 wall clock 延长或授权销毁。无可信锚的 force-local 拒绝 retain，保留原操作状态，等待明确 destroy/cancel/retry。BootEpochProvider 按 §8.2 API 24+/process-only 分支实现。
- 导入仅在 publish-applied 后按 IMP-09 精确退休游客 live graph。采用 `guest_import_audit_anchors` 承接终态审计引用；非终态 Reminder/attempt 用 `source_migrated` 不可恢复终结。现有枚举/方法的变更必须另有兼容 Schema 后才能实施。
- source lease 的释放仅允许 IMP-10 的证明闭包。Search History 和投递事实不复制；source epoch、旧 cleanup gate 与新游客写入彼此隔离。

## Compatibility and Gates

v5→v6 先校验本次基线摘要以及完整 runtime checker。v5 的 20 个表、payload、索引、generation、history 和旧 JSON guard 原样保留；账号库单独新建，游客库不在原地改挂账号。

新通知 writer 带 workspace identity，旧 reader 的未知字段行为必须实测后选择兼容 adapter 或同包新入口，不能仅凭“可选字段”宣布兼容。新 workspace query 同时保留 workspace/device 两条时区轴；旧 Calendar/Search 方法继续原语义。

需通过双库 saga、同时存活 runtime、clear/retention 每一强杀点、审计 FK 与 notification 旧载荷场景。当前仅有现状审计，无生命周期实现或设备验收证据。
