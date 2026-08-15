## UserSyncState：用户同步状态

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联用户 ID |
| `syncCursor` | `string` | 否 | 服务端增量同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近一次成功同步时间 |
| `updatedAt` | `datetime` | 是 | 状态更新时间 |

该模型属于同步内部状态，不进入当前用户资料响应，也不参与认证判断。

