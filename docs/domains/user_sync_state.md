## UserSyncState：用户同步状态

> HXY-AI 分支：本页仅保留早期概念说明；本分支不包含 Sync v1 协议、同步引擎和实施计划，不据此开启同步开发。



| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联用户 ID |
| `syncCursor` | `string` | 否 | 服务端增量同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近一次成功同步时间 |
| `updatedAt` | `datetime` | 是 | 状态更新时间 |
