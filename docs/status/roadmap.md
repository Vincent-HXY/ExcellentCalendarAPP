# ExcellentCalendarAPP 产品路线图

> 阶段基线：2026-08-31。R0 已完成，R1 主体完成并转入维护轨，**R2 为当前开发阶段**。
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
- 总入口为 `docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`；`习惯-03-CPP层开发计划.md`、`习惯-04-Kotlin层开发计划.md`、`习惯-05-Flutter层开发计划.md` 作为已实施并已发布、等待统一文档归档的交付记录，状态清理见 `OPEN-HAB-002`；Contract 完成证据归档于 `docs/plan/completed/习惯-02-Contracts层开发计划.md`。

### R2-B｜日历、四象限与搜索

- 实现月/周/日历视图，统一聚合 Event occurrence、Anniversary occurrence 与 Habit 日状态；
- 实现四象限视图，复用既有领域字段完成筛选和状态变更；
- 建立独立搜索页、设备本地历史和三类筛选；V1 先基于 canonical 数据完成统一查询与性能基线，只有门禁不达标时才冻结索引重建、tokenizer 与迁移规则并接入 SQLite FTS；
- 月/周分类日历已建立 active 主计划并冻结产品范围；下一步建立统一 Calendar range/day projection Contract，再按 C++/SQLite、Kotlin/JNI、Flutter Fake 并行、真实三类集成和独立 Review 收口。
- 独立搜索已建立 active 主计划 `docs/plan/active/搜索-01-三类聚合搜索与本地历史开发计划.md`，冻结 1s debounce、三类分组、中文原文/ASCII case-insensitive/token AND、业务日期筛选、完成映射、20 条分组分页、右上筛选浮层和本地 20 条历史；下一步建立 Search Contract/数据投影，并按 C++/SQLite、Kotlin/JNI/历史、Flutter、真实集成/性能和独立 Review 收口。四象限仍需建立 active plan、数据源边界和验收门禁。

### R2-C｜Local-first 云同步

- 先冻结客户端操作日志、变更序列、设备身份、删除语义和冲突策略；
- 再实现增量上传/拉取、幂等、游标、离线重试、设备管理和备份边界；
- 同步开发前必须解决 Backend/Auth Contract planned 状态，并补齐服务端日历数据模型和正式迁移；
- 不允许后端复制或绕过 C++ Core 的领域规则。

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
