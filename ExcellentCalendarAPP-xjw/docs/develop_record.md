# ExcellentCalendarAPP 当前进度

> 更新时间：2026-08-01

## 总体结论

项目已经从工程骨架进入核心闭环开发阶段，主链路已经基本打通：

```text
Flutter → Dart Gateway → Kotlin MethodChannel → JNI → C++ Core → JSON Storage → Android Alarm/Notification
```

当前最完整的范围是“日程 + 一次性提醒 + Android 本地通知 + JSON 本地存储”。核心代码测试和 Debug 构建通过，但还不是功能完整、真机验证充分的 V1 发布版。

## 已完成

### 协议与架构

- 已建立 `contracts/`，包含 68 个 JSON Schema、MethodChannel、JNI 调用、错误码、枚举和 `NativeResult`。
- Dart、Kotlin、C++ 已按 DTO、Boundary、Domain 分层，跨层调用链已建立。

### C++ Core 与存储

- Event：创建、更新、删除、搜索、完成、重新打开和基础校验。
- Reminder：创建、按 ID 查询、列表、取消、启用、禁用和状态流转。
- Reminder 支持时间/目标/提醒方式校验、游标分页和批量调度查询。
- Event 与 Reminder 创建支持事务回滚；完成 Event 会取消未触发提醒，重新打开可恢复符合条件的提醒。
- Notification 已支持创建、失败记录、投递消费、重复消费保护和事务回滚。
- 已实现 JSON Repository、原子写入、软删除、重启恢复、UTF-8 和损坏文件检测。
- Android 正式数据目录已统一为 `calendar_core_storage_json`。

### Flutter

- 已完成 Inbox/Today 日程列表和 active/completed 展示。
- 已完成新建日程页面、日期/时间选择器、重复和提醒选择 UI。
- 已完成日程详情页、完成操作和列表刷新。
- 已接入 Application Layer、Gateway、DTO 和 NativeResult 解析。

### Android Native

- 已完成 MethodChannel、Kotlin Contract 校验、JNI/C++ Bridge。
- 已完成通知 Channel、权限申请、系统设置跳转和通知点击 EventChannel。
- 已完成 Dispatcher Alarm、开机/时间变化恢复、WorkManager 看门狗和失败重试。
- 已完成 Reminder reconcile 和 Popup 通知投递。

## 正在完成

- 通知点击后根据 ID 读取真实日程并进入详情页。
- `notification_id`、`delivery_id`、`delivery_attempt_id` 的统一设计。
- 通知投递 prepare/display/finalize 两阶段协议。
- 通知初始化失败后的调度状态机。
- 日程修改、完成、重新打开后的调度一致性。
- 重复规则持久化、Occurrence 展开和下一次提醒生成。
- exact/inexact alarm 策略和批量失败反馈。
- 真实 Android 设备上的通知、Alarm、JNI 连续验证。

## 尚未完成

- Habit/HabitCheckIn、Anniversary、Category。
- 完整月/周/日历视图、搜索、全文索引和四象限。
- Notification 历史、点击记录、Event 编辑和完整删除/恢复交互。
- AI 导入/OCR、微信、账号登录、云同步、云备份和多设备同步。
- SQLite、FTS、附件存储迁移。

Contract 或目录中已有设计，不代表对应生产功能已经完成。

## 当前风险

- 通知点击冷启动可能进入占位页面。
- Android payload 中的 `notification_id` 暂时使用 Reminder ID。
- 投递协议缺少完整幂等键和两阶段提交。
- 点击事件读取后立即清除，存在丢失风险。
- 重复提醒消费闭环尚未完成。
- 真实设备和国产 Android 后台限制尚未验证。

## 验证结果

- C++ `excellent_calendar_check`：2/2 测试通过。
- `flutter analyze`：通过。
- `flutter test`：68 个测试通过。
- Kotlin `:app:testDebugUnitTest`：成功。
- Flutter Android Debug APK：构建成功。
- 真机通知、Alarm、JNI、点击路由完整链路：未验证。

## 下一步

1. 完成通知点击到真实详情页的闭环。
2. 完善通知投递 ID、幂等和调度协议。
3. 完成提醒 reconcile 的真机验证。
4. 收尾 Event 编辑、重复规则和通知历史。
5. 再进入 Habit、纪念日、分类、搜索等功能。
