# Storage Repository

负责统一访问 SQLite，避免各个 Engine 直接散落 SQL。

## 具体任务

- 封装 Event、Habit、Reminder、Category、Recurrence、Notification、SearchIndex、SyncOperation、UserData、DatedMessage、Anniversary 的读写。
- 维护事务边界。
- 提供查询接口给各个 Engine。
- 管理 schema 版本迁移调用。

## 交付标准

- SQL 集中管理。
- 所有写操作要考虑事务。
- 不包含 UI 和 Android SDK 逻辑。
