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
- C++ Core、Boundary、JSON Storage、Kotlin/JNI、Dart 与 Android 调度已完成；发布状态已于 2026-08-08 切换为 `active`（真机首轮验证通过）。

2026-08-08 已激活 v2 并完成首轮真机验证；剩余验证项为 Alarm 到点触发、崩溃 journal 重放、Recovery 废弃分支与国产 ROM 后台限制。V1 数据不再保留。

### 纪念日的设计

纪念日模块需求（V1，公历版）
纪念日应作为独立的 Anniversary 领域对象，不作为 Event 的特殊类型。
分类复用 Category，年度重复复用 Recurrence；未来如需提醒，仍通过独立的 Reminder(target_type=anniversary) 关联。
该设计符合当前项目的领域模型与 Flutter—Kotlin—JNI—C++ Core—Storage 分层架构。需要实现支持纪念日的创建、修改、详情查询、列表查询和软删除；列表可按分类、重要性筛选，并按下一次发生日期或剩余天数排序。核心字段已经在DATA_MODEL.md中声明。V1 仅支持公历，calendar_type 当前只能传入 solar。字段仍予以保留，为后续农历扩展提供稳定协议。支持一次性纪念日和每年重复纪念日。生日、结婚纪念日、周年庆等默认建议设置为每年重复。查询结果应动态返回 next_occurrence_date、days_remaining 和 is_today。剩余天数按用户时区的本地自然日计算，当天为 0，不得按剩余小时数取整。公历 2 月 29 日遇非闰年时，V1 统一按 2 月最后一天处理，避免各端计算结果不一致。元旦可作为只读系统预设，通过稳定的 preset_key 幂等初始化；用户可隐藏或复制后编辑。“本周末”属于动态倒计时工具，不保存为普通纪念日；由当前日期实时计算。日历页面通过区间查询动态生成纪念日 occurrence，返回 target_type=anniversary，不得复制为 Event，也不得提前生成多年记录。农历限制当前版本不支持农历创建、转换、倒计时和重复计算。界面选择农历时应明确提示“当前版本暂不支持农历”；跨层收到 calendar_type=lunar 时统一返回 ANNIVERSARY_CALENDAR_UNSUPPORTED。春节依赖农历计算，因此不纳入 V1 系统预设，也不能用固定公历月日循环替代。暂不实现农历算法、春节等农历节日模板、AI 祝福、通知调度、云同步、桌面组件和完整节假日库；仅保留相应扩展边界。
目前仅支持指定某个日期为纪念日，然后计算时间。

2026-08-10 状态：公历 V1 的 create/update/delete/detail/list/preview_countdown 已完成 Contract、Dart Gateway、Kotlin/JNI、C++ Core 与 JSON Storage 集成并通过真机持久化 smoke。一次性/年度规则切换、动态本地自然日 countdown、2 月 29 日、过滤排序、软删除及专用 journal 重放已实现。农历仍返回 `ANNIVERSARY_CALENDAR_UNSUPPORTED`；元旦 preset、Calendar occurrence 聚合、Reminder、通知、云同步和非空 list cursor 不属于本次完成范围，需后续独立任务。
