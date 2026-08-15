## SyncOperation：同步操作

同步操作记录本地与云端之间的数据变更，用于冲突处理和增量同步。

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

