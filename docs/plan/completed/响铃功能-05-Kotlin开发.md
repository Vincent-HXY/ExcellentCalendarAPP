# 计划：Kotlin 层
负责范围：flutter_client/android/**。
当前 Kotlin 调度和投递仍写死 popup，参见 [V2ReminderScheduleCoordinator.kt (line 128)](A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/V2ReminderScheduleCoordinator.kt:128) 和 [V2ReminderDeliveryService.kt (line 26)](A:/calendar/ExcellentCalendarAPP/flutter_client/android/app/src/main/kotlin/com/excellentcalendar/excellent_calendar/bridge/reminder/V2ReminderDeliveryService.kt:26)。
## 执行任务
1. 投递分流：
   - schedulable 保留 methods。
   - popup 继续走现有 NotificationDisplayService。
   - ring prepare 后进入 RingSession。
   - 抽出统一 attempt client，负责 prepare/finalize/失败映射。
   - Recovery summary 始终走 popup。
2. RingSession：
   - 使用应用私有、版本化持久化记录，不能只放内存。
   - 状态建议：
   PREPARED → AUDIBLE → QUIET_PENDING → RESOLVED
   - 同一 attempt 只加入一次。
   - 全局只有一个 session、播放器、振动器和控制通知。
   - 响铃期间加入新 item 不延长当前 5 分钟。
   - 静音待处理阶段收到新 ring 时开启新的 audible generation。
   - finalize sent 失败只重试 finalize，绝不重新播放。
3. ReminderRingService：
   - 先展示前台控制通知。
   - 再启动播放器与振动。
   - 至少一种输出成功后才能 finalize sent。
   - 两种输出都失败才 finalize failed。
   - 用 elapsedRealtime 控制最长 5 分钟。
   - 到时停止声音/振动，保留静音待处理通知。
4. Android 输出和交互：
   - Framework MediaPlayer，USAGE_ALARM，不新增 Media3。
   - VibratorManager 和低版本兼容实现。
   - 新建独立静音控制 Channel，不复用现有 sounding Ring Channel；通知 Channel 创建后行为不可由应用可靠重写。Android Notification Channel
   - 单条提供关闭、稍后、完成；多条提供关闭全部、稍后全部、查看及逐条完成。
   - 锁屏只展示“你有一个日程提醒”等通用文案。
   - 全屏权限不可用时降级为高优先级通知，不让普通 ring 整体失败。Android 14 全屏权限规则
5. Ring MethodChannel/EventChannel：
   - 实现冻结的全部 ring.*。
   - ring.complete_item 内部调用现有 Event complete，再更新 RingSession。
   - ring.snooze_active 调用 C++ reminder.snooze，支持逐项成功/失败。
   - EventChannel 丢事件后可通过 ring.get_state 恢复。
   - 系统铃声 URI 失效时回退默认 Alarm ringtone。
6. Manifest 和平台验证：
   - 添加 FGS、振动、全屏等权限和组件。
   - Service、Receiver、Activity 均 exported=false。
   - 完成前述 FGS 类型专项验证。
   - Boot/Worker 不直接启动受限 FGS，必要时转交立即 exact alarm。
## 完成标准
通过 JVM 单测、lint、assemble、JNI smoke，并在 realme RMX5100 / Android 16（API 36）国产 ROM 完成 AlarmManager、Dispatcher、JNI/C++、声音/振动、稍后提醒、五分钟安全停止和进程恢复验收。2026-08-23 已明确批准以该设备验收作为一期发布门禁，豁免一期 API 24、31、33、34、35 完整矩阵；这些版本保留为后续兼容验证，不再阻塞一期发布。API 24 静态 lint 仍必须通过。
