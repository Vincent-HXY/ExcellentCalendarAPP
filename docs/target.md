# 目标

## 本周目标

### 后端验证

1. 完整的后端登录和注册的验证功能，使用spring 和 PostgreSQL实现用户账号信息的存储。通过邮箱可以进行注册用户账号
2. 完整的用户信息保存，完成的保存用户的个人信息，登录信息，注册信息等等。

### 个人信息界面
1. 完整的用户登录界面，含盖登录和注册，修改用户信息的的所有的相关的页面。
2. 完整的用户信息的保存，用户头像，账号，等等信息的存储。
3. 完整的用户信息修改流程，用户可以实时上传更改用户信息，可以通过邮箱实现密码的修改。

### 日程详情
1. 完整的日程详情页面，可以通过日程详情页面做到修改日程。
2. 重复日程的设计，解决重复日程的显示问题。
3. ~~需要在 CPP 层新增时区转换服务。~~ 已实现 `LocalTimeResolver`/捆绑 TZDB，待 Android native smoke 验证同源时区行为。

### 重复日程 Native v2

2026-08-04 已完成 Contract/C++/Storage 语义门禁：

- `mark_scheduled` 使用 `expected_remind_at` CAS，阻止旧 Alarm 覆盖新时间。
- occurrence reopen 暂存同模板 successor，确保每模板最多一条 open Reminder。
- Recovery 支持 `expired` 与 prepared attempt 的接管/废弃冻结语义。
- finalize response 与 Kotlin validator 已识别 adopted attempt 的 `resolved_by_recovery_batch_id` 归属；`reminder.list(status=["expired"])` 已在 Schema/Kotlin 请求边界打通。
- C++ Core、Boundary、JSON Storage 与原生回归已完成；发布状态仍为 `design_only`。

下一目标是接入 JNI/Kotlin/Dart：Android 传递 CAS 前置值、冲突时 reconcile、取消 Recovery 已废弃的 delivery tag，并完成 Flutter/Kotlin/Android Debug/native smoke。全部链路在同一 APK 验证前不得激活 v2 或写入正式 v2 数据目录。
