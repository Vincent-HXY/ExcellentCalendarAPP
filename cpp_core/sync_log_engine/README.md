# Sync Log Engine

负责本地操作日志，为云同步和冲突处理做准备。

## 具体任务

- 记录 Event、Habit、Category、Reminder、UserData 等对象的增删改操作。
- 生成 SyncOperation。
- 支持操作重放、压缩和冲突检测所需的元数据。
- 标记已同步、待同步、失败重试状态。

## 交付标准

- 不直接调用云端 API。
- 操作日志必须幂等。
- 删除和恢复场景要有明确记录。
