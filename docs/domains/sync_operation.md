## SyncOperation：同步操作

同步操作记录本地与云端之间的数据变更，用于冲突处理和增量同步。

> 当前状态（2026-09-07）：Sync v1 的 Accepted ADR、机器 Contract、fixtures 与 revision lock 已冻结，机器状态为 `CONTRACT FROZEN`；03–06 的生产实现、跨层集成和多设备验收仍未完成。旧 `sync.apply` 与下列表格仅是兼容墓碑和历史概念形状，不能作为当前生产语义；当前语义入口是 [Sync v1 模型](./sync_v1_model.md) 与 `contracts/sync/ct0_gate_status.json`。

当前冻结模型已经确定游客数据归属、退出/换号后的本地隔离、同步实体闭包、提醒用户意图与每设备投递状态的边界、冲突处理、删除 tombstone/恢复窗口、设备身份、增量游标、弱网后台策略和加密边界。实现必须逐项消费当前 Machine Contract，不得由某一层重新解释。Outbox 必须与本地业务写处于同一 SQLite 事务，不能在 Flutter、Kotlin 或 Backend 事后拼接操作日志。

2026-09-05 CT0 历史记录：旧 `sync.apply` 和两个 Sync 概念 Schema 已明确封存为 deprecated/blocked，保留形状只供兼容墓碑；不允许按下表构造上传。当时新 typed Sync Protocol 尚未冻结，后续冻结结果以 [Sync v1 模型](./sync_v1_model.md)、[冻结验收记录](../plan/active/云同步-02-冻结验收与交付记录.md) 和机器 gate 为准。

当前入口：七项 Sync ADR 的设计方向已接受，完整强类型目标见 [Sync v1 模型](./sync_v1_model.md)、`contracts/sync/sync_field_registry.yaml` 与 [冻结验收记录](../plan/active/云同步-02-冻结验收与交付记录.md)。唯一状态为 `contracts/sync/ct0_gate_status.json`，封版摘要为 `sync_v1_revision_lock.json`。以下旧表仅为历史占位，不能作为新 payload；开头的日期记录保留其当时状态。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 同步操作 ID |
| `operationType` | `SyncOperationType` | 是 | 操作类型 |
| `targetType` | `string` | 是 | 目标对象类型 |
| `targetId` | `string` | 是 | 目标对象 ID |
| `payload` | `object` | 否 | 变更内容 |
| `baseVersion` | `number` | 否 | 变更前版本 |
| `nextVersion` | `number` | 否 | 变更后版本 |
| `deviceId` | `string` | 否 | 发起设备 ID |
| `userId` | `string` | 是 | 用户 ID |
| `status` | `string` | 是 | 同步状态，例如 `pending`、`synced`、`conflict`、`failed` |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `syncedAt` | `datetime` | 否 | 同步完成时间 |

## 枚举定义

### SyncOperationType

同步操作类型。

| 值 | 说明 |
| --- | --- |
| `create` | 新增 |
| `update` | 更新 |
| `delete` | 删除 |
| `restore` | 恢复 |

