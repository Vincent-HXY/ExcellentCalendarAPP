# C++ Core Engine 核心引擎层

负责项目中最稳定、最核心、最需要测试的业务规则和算法。

## 负责范围

- 日程、习惯、提醒、重复规则、搜索、日历聚合、四象限、AI 结果校验、同步日志、加密导出、统一存储访问。

## 不负责

- 不写 Flutter 页面。
- 不调用 Android UI 或微信 SDK。
- 不直接处理 MethodChannel。

## 子目录

- `event_engine`
- `reminder_engine`
- `recurrence_engine`
- `search_engine`
- `habit_engine`
- `calendar_query_engine`
- `quadrant_engine`
- `ai_result_validator`
- `sync_log_engine`
- `crypto_export_engine`
- `storage_repository`
