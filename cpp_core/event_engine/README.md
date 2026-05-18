# Event Engine

负责日程的核心增删改查和基础校验。

## 具体任务

- 校验日程标题、时间、地点、重要性、分类、完成状态等字段。
- 创建、修改、删除、查询 Event。
- 处理事件时间冲突、非法时间、缺失必填项。
- 与 Reminder Engine、Recurrence Engine、Sync Log Engine 协作。

## 交付标准

- 不处理页面表单显示。
- 不直接注册系统通知。
- 所有核心校验需要单元测试。
