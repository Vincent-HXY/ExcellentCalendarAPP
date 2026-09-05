## SyncOperation：同步操作

同步操作记录本地与云端之间的数据变更，用于冲突处理和增量同步。

> 当前状态（2026-09-04）：已建立 active 云同步总计划，产品与架构方向仅作为待冻结目标；ADR、机器 Contract 和 fixtures 尚未冻结，整体状态为 `ACTIVE PLAN / CONTRACT PENDING / IMPLEMENTATION NOT STARTED`。本模型与 `contracts/sync/`、`sync.apply` 仍是概念占位，尚无生产同步 Contract、本地 Outbox、服务端 change feed 或客户端同步引擎。下列字段必须由 Contract 分计划重新设计，不能直接作为生产语义。

进入实现前必须先确定游客数据归属、退出/换号后的本地隔离、同步实体闭包、提醒用户意图与每设备投递状态的边界、冲突 UX、删除 tombstone/恢复窗口、设备身份、增量游标、弱网后台策略和加密边界。Outbox 必须与本地业务写处于同一 SQLite 事务，不能在 Flutter、Kotlin 或 Backend 事后拼接操作日志。

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

