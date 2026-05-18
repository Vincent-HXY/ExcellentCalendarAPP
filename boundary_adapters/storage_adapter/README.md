# Storage Adapter

负责 C++ 领域模型与 SQLite 数据结构之间的转换。

## 具体任务

- 将 Event、Habit、Reminder、Category、Recurrence 等对象映射到表结构。
- 将查询结果还原为领域对象。
- 处理日期时间、枚举、布尔值、重复规则等字段转换。
- 协助 Storage Repository 保持 SQL 访问统一。

## 交付标准

- 不让 Engine 直接依赖 SQLite 行结构。
- 字段转换要有测试用例。
- schema 变更时同步更新映射文档。
