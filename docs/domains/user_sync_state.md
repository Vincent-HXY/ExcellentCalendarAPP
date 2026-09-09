## UserSyncState：用户同步状态

2026-09-05 CT0 历史记录：当时已增加[基线审计与决策提案](../plan/active/云同步-02-CT0审计与决策记录.md)，状态为 DECISION REQUIRED / CT0 PARTIAL。该阶段已经结束，后续冻结结果以 `contracts/sync/ct0_gate_status.json` 为准。

> 当前状态（2026-09-07）：Sync v1 的 Accepted ADR、机器 Contract、fixtures 与 revision lock 已冻结，机器状态为 `CONTRACT FROZEN`；03–06 的生产实现、跨层集成和多设备验收仍未完成。下表没有被当前生产 Schema 采用，不能据静态审计、冻结 Contract 或 encoder 探针通过声称同步状态机已经实现；当前字段与状态机以 [Sync v1 模型](./sync_v1_model.md) 和机器 Contract 为准。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 关联用户 ID |
| `syncCursor` | `string` | 否 | 服务端增量同步游标 |
| `lastSyncAt` | `datetime` | 否 | 最近一次成功同步时间 |
| `updatedAt` | `datetime` | 是 | 状态更新时间 |

该历史模型属于同步内部状态，不进入当前用户资料响应，也不参与认证判断。冻结 Contract 已将 Cursor 按账号 workspace + device 分区，并绑定服务端 generation/sequence；本页单个 `syncCursor` 字段没有表达完整身份，生产实现必须使用当前强类型 Schema，不能复用本表。

