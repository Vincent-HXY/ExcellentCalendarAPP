## UserSyncState：用户同步状态

> 当前状态（2026-09-03）：产品决策已经冻结，并建立 `docs/plan/active/云同步-01-Local-first多设备同步开发计划.md`；仍无生产 Schema、Repository、SQLite Store、设备注册、服务端游标或客户端同步引擎。字段必须由同步 Contract 分计划重新审查，不能直接据此实现。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联用户 ID |
| `syncCursor` | `string` | 否 | 服务端增量同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近一次成功同步时间 |
| `updatedAt` | `datetime` | 是 | 状态更新时间 |

该模型属于同步内部状态，不进入当前用户资料响应，也不参与认证判断。总计划已经确定 Cursor 按账号 workspace + device 分区，并携带服务端 generation/sequence；本页单个 `syncCursor` 字段仍未表达完整身份，必须在生产 Schema 中拆清后才能实现。

