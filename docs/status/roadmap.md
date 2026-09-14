# ExcellentCalendarAPP 产品路线图

> 阶段基线：2026-09-02 22:31（Asia/Shanghai）。R0 已完成，R1 主体完成并转入维护轨，**R2 为当前开发阶段**。
>
> 阶段切换不等于历史债务清零；能力是否可发布仍以机器 Contract、active plan 和实际验证为准。

## R0｜本地核心闭环（已完成）

- 打通 Flutter → Kotlin → JNI → C++ → SQLite Storage v4 → Android Alarm/Notification 主链路。
- 完成 Event、Recurrence、Reminder、Anniversary 公历 V1 与 Category list/create 的真实本地闭环。
- Calendar Core 从 JSON writer 切换到 SQLite v4，并保留 JSON v1/v2/v3 迁移、兼容与降级 guard。
- Anniversary Reminder R1、Category 和相关 occurrence 查询进入 `integrated + active`。

## R1｜账号基础与本地 V1 增强（主体完成，转维护轨）

已经完成：

- Ring 一期跨层链路、稍后提醒、活动会话、进程恢复和 API 36 国产 ROM 真机门禁，Contract 已激活；
- Spring Boot + PostgreSQL 的 16 个认证/个人信息端点、Flyway V1–V3、安全与测试基础；
- Flutter 登录、注册、验证、密码、个人资料、修改邮箱、账号安全与 Android Keystore Refresh Token；
- “日程 / 日历 / 搜索 / 我的”四 Tab 主导航结构，“我的”接入真实账号数据；
- SQLite v4 审查缺陷修复、迁移回归和部分隔离真机验证。

随 R2 并行偿还：

- `backend_api.yaml` 与四个 `auth.refresh_token.*` MethodChannel 仍为 `planned`，需专项审查和发布状态校准；
- 普通日程编辑/删除/重开 UI、通知历史、统一提醒管理仍未闭环；
- FTS、备份/恢复产品流程、长期存储压力和物理掉电验证未完成；
- API 24/31/33/34/35、多 ROM、权限/时区/陈旧 Alarm/长离线矩阵仍不完整；
- Backend 正式部署、生产密钥轮换、生产 SMTP 运维与多实例限流未完成。

## R2｜核心效率产品与 Local-first 同步（当前阶段）

### R2-A｜Habit V1（已发布，进入维护轨）

- **已完成实现与真实集成**：Habit、HabitRecurrence、HabitCheckIn、HabitReminderTemplate 的领域与 Contract、SQLite v5、C++ Core/Boundary、Kotlin/JNI/Android、Flutter Application/UI、Appearance 和正式 production composition 已接通；并行期运行时 Fake/preview 已删除；
- **已完成主机门禁**：Contract、C++ build-after-test、Flutter 全量、Android unit/lint/APK/androidTest 构建、Native smoke 和三 ABI 11/11 JNI 导出均通过；白盒 Review 的运行时缺陷完成返修和独立复核；
- **本轮产品反馈已关闭**：卡片背景使用完成率、超过 100 条时按 cursor 续页并按 ID 去重、数量型圆圈显示剩余量/达标态、详情隐藏 occurrence 技术身份；Flutter 全量测试、静态分析和 Debug APK 构建通过；
- **发布后验证债**：重新授权自动 reconcile、跨午夜、杀进程/重启、时区/系统时间变化、数量型/重复/陈旧通知 action、真实详情导航和完整 TalkBack 继续由 `OPEN-HAB-001` 跟踪，不得描述为已验证通过；
- **发布状态**：产品负责人于 2026-08-31 接受上述矩阵为非阻断发布债后，Habit/Appearance capability 与 Storage v5 已统一切换为 `integrated + active`；
- 支持打卡型与数量型、有效期内补签、严格 streak/rate、同日提醒补发和通知快捷完成；
- 总入口为 `docs/plan/completed/习惯-01-Habit与HabitCheckIn闭环开发计划.md`；`习惯-02/03/04/05` 均已归档于 `docs/plan/completed/`。剩余设备验证见 `OPEN-HAB-001`，active Review 与 ADR 的状态清理见 `OPEN-HAB-002`。

### R2-B｜日历、四象限与搜索

- **Calendar V1 已发布并进入维护轨**：月/周分类视图统一聚合 Event occurrence、Anniversary occurrence 与 Habit 日状态，Contract、C++/SQLite、Kotlin/JNI、Flutter 与 production composition 已接通；
- **Calendar 发布状态**：独立返修复验未发现七项已知债务以外的新硬缺陷；产品负责人于 2026-09-02 接受 `OPEN-CAL-001` 的正式签名/商店上传、时区/DST、TalkBack、200% 字体/减少动画、强杀恢复、升级回滚/密钥恢复和正式 Release UI 全链为非阻断债，`calendar.*` 已切换为 `integrated + active`。Release 签名已 fail-closed 并通过一次性非生产密钥的 APK/AAB 验签，但尚无生产密钥产物或商店证据；
- Calendar 总计划、四份分层计划和 Review 已分别归档到 `docs/plan/completed/` 与 `docs/reviews/archive/`；
- 实现四象限视图，复用既有领域字段完成筛选和状态变更；
- **Search V1 已发布并进入维护轨**：统一三类 canonical 查询、独立分页、AtomicFile 本地历史、Flutter 页面与 production composition 已接通，并完成主机及 Android 13 设备门禁；
- **Search 发布状态**：产品负责人于 2026-09-02 接受 `OPEN-SEA-001` 的搜索框 TalkBack 语义和正式签名链为非阻断发布债，`search.*` 已切换为 `integrated + active`。SearchIndex/FTS 因 canonical 查询达到性能基线而继续 deferred/planned；
- Search 总计划和四份分层计划已归档到 `docs/plan/completed/`。后续优先偿还 `OPEN-SEA-001`，四象限仍需建立 active plan、数据源边界和验收门禁。

### HXY-AI 分支方向

本分支用于 AI 开发与实践，保留本地业务、现有账号/个人资料、后端框架与界面改进；云同步不在本分支实施范围，原同步计划已移除。AI 具体功能与验收标准按后续任务确定。

## R3｜日程与纪念日增强

- 扩展地点能力：地图选点、地理信息保存、地点搜索与隐私控制。
- 完善自定义/年度重复、例外日期、系列拆分和跨时区行为。
- 扩展 Anniversary：农历、节日模板、系统预设、完整日历聚合与高级提醒。
- 建立服务端渠道提醒、账号绑定和失败补偿。

## R4｜智能导入与生态能力

- 建立 OCR、文本提取、自然语言时间解析、推荐和 Candidate Event 确认流。
- 完成 Android 分享接收、图片/文件附件管理和消息导入。
- 接入微信登录、分享、消息导入与推送。
- 完成主题、通知、默认提醒、时区、隐私和同步偏好。

## R5｜桌面入口与发布质量

- 实现今日、未来三天、习惯等桌面小组件。
- 建立 API 24–最新 Android、主流国产 ROM、屏幕、深浅色和无障碍兼容矩阵。
- 完成性能、耗电、存储膨胀、弱网、崩溃恢复、备份恢复和长周期提醒压力测试。
- 建立签名、数据迁移演练、灰度发布、监控告警和回滚基线。
