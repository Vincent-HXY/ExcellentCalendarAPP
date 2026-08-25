# 计划 4：Flutter 层
负责范围：flutter_client/lib/** 和 flutter_client/test/**。
当前提交 ring 时实际发送的是 ['popup','ring']，参见 [create_schedule_controller.dart (line 222)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/create_schedule_controller.dart:222)。
## 执行任务
1. 新增类型化 DTO、Gateway 和 Adapter：
   - Ring settings/capability/session/event DTO。
   - 严格解析 enum、UTC 时间、未知字段和 NativeResult。
   - UI 不直接接触 Map、URI、MethodChannel 或 PlatformException。
2. 新增两个 Controller：
   - RingSettingsController
   - ActiveRingSessionController
   启动顺序使用“先订阅 EventChannel，再 get_state”；按 runtime instance、sequence、session revision 防止旧事件覆盖新状态。
3. 修正创建日程：
   - ring OFF：提交 ['popup']。
   - ring ON：提交 ['ring']。
   - 全天、重复、无提醒时间时禁止开启。
   - 开关时和保存前各检查一次 capability。
   - 权限失败保留用户草稿。
   - Flutter 只消费 Kotlin 给出的阻断/降级原因，不复制 Android 版本判断。
4. 新增页面和全局接线：
   - /settings/ring
   - /ring/active
   - 响铃设置入口
   - App 级 RingSessionHost
   - 冷启动发现活动 session 时只打开一次活动页
5. 页面行为：
   - 设置页：铃声名称、系统选择器、测试/停止测试、强提醒和权限状态。
   - 活动页：单条关闭/稍后/完成；多条关闭全部/稍后全部/逐条完成。
   - 不提供“全部完成”。
   - 操作中防重复点击，部分 snooze 失败时只保留失败项。
   - Flutter 不负责播放、振动或维护 Android session。
## 完成标准
通过 DTO/Gateway、Controller、Widget、路由、冷启动恢复、重复事件和无障碍测试，以及 flutter test、flutter analyze 和 Debug APK 构建。