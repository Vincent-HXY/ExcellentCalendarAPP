# SQLite

负责结构化数据持久化。当前运行时实现位于 `cpp_core`：使用单个
`calendar_core.sqlite3`、schema/user version 4、WAL 与数据库事务，并从既有
Calendar Core JSON v1/v2/v3 连续迁移。

## 具体任务

- 设计并维护表结构。
- 管理 schema 版本和迁移脚本。
- 存储日程、习惯、提醒、分类、重复规则、用户数据、纪念日、投送消息等结构化数据。
- 为 Storage Repository 提供稳定数据基础。
- 保留现有 Repository port 和领域行为；不得把 `sqlite3` handle 暴露给 Application/UI。
- 迁移成功后只把 JSON 根作为带 `storage_version=4` 的诊断快照和防降级标记，不再作为 live data。

## 交付标准

- schema 变更要有迁移方案。
- 字段含义需要文档化。
- 不存放大附件内容。
