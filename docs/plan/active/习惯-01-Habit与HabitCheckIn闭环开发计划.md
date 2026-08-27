# 习惯-01：Habit 与 HabitCheckIn 本地闭环开发计划

Status: Active / Requirements Frozen / Ready for Specialist Split

确认日期：2026-08-27

## 1. 计划定位

本计划实现 Android 优先、本地优先的“固定期限每日习惯挑战”完整闭环，覆盖：

- 创建、查询、编辑、提前结束和软删除 Habit；
- 打卡型与数量型目标；
- 每日 CheckIn、补签、修改、撤销和 skipped；
- 当前连续、最长连续、7 日、30 日和全周期统计；
- Habit 首页、详情、创建/编辑和日期详情页面；
- 每日单提醒、同日补发、通知栏直接完成；
- “我的”页面中的本机 Habit 进度色设置；
- Flutter → Kotlin → JNI → C++ → SQLite 的真实跨层链路。

本计划是多阶段主计划，不按一次小型全栈任务实施。各阶段必须由对应专项负责人完成并通过阶段闸门后，再进入下游阶段。

## 2. 当前仓库基线

### 2.1 已有依据

- `Habit` 与 `HabitCheckIn` 已在领域文档中分离。
- 已有 `create_habit_request`、`habit_response`、`habit_check_in_request`、`habit_check_in_response` 预留 Schema。
- `method_channels.yaml` 仅预留 `habit.create`、`habit.check_in`。
- Reminder/Notification、Android 调度、恢复、投递与通知点击已有生产基础。
- Calendar Core 正式 writer 已是 SQLite Storage v4。
- 当前底部主导航已是“日程 / 日历 / 搜索 / 我的”。

### 2.2 尚未实现

- 没有 Habit/HabitCheckIn/HabitRecurrence 的 C++ Domain、Application、Repository 或 SQLite 表。
- 没有 Habit native calls、JNI bridge、Kotlin handler、Dart DTO/Gateway/Application。
- 没有生产 Habit 页面；通知点击 Habit 仍进入“内容不存在或已删除”占位页。
- 现有 planned Habit recurrence Schema 尚未冻结生产语义。
- 普通一次性 Habit Reminder 预留不能表达每日 occurrence、同日补发和幂等快捷完成。
- “我的”页面没有本机 Habit 进度色设置。

### 2.3 可行性判定

判定：`SPECIALIST_SPLIT`

原因：功能同时包含领域模型、Storage v4→v5 migration、跨层 Contract、C++ 统计与工作流、Android Reminder/Notification、Flutter 多页面和本机偏好设置，不能用一次独立端到端修改安全覆盖。

## 3. 已冻结的产品范围

### 3.1 V1 必须实现

- 每个 Habit 都是有明确开始日、结束日的每日挑战。
- 开始日和结束日都计入挑战；30 天挑战产生 30 个计划日。
- “月”和“年”按自然日历计算；创建页显示计算后的最终结束日。
- V1 recurrence 固定为 `daily + interval=1 + follow_device`。
- 支持打卡型和数量型。
- 数量型 `target_count > 0`，`unit` 必填，最多两位小数，可超过目标。
- 用户可以在有效期内补签、修改和撤销 CheckIn。
- 第一次 CheckIn 后锁定 `target_count` 和 `unit`。
- missing 的过去计划日动态投影为 missed，不批量创建 CheckIn。
- skipped 不计入完成率分母、不增加连续天数、也不打断连续达标。
- 不支持暂停/恢复；支持提前结束，且提前结束不可恢复。
- 自然到期和提前结束后历史只读；“再来一轮”预填新建页面并创建新 Habit。
- 每个 Habit 最多一个每日 popup reminder，默认关闭。
- 拒绝通知权限不阻止 Habit 创建；页面必须显示未调度原因。
- 错过提醒后，只要仍是同一个当地日期且尚未达标，就补发一次。
- 通知栏支持直接完成：打卡型写 done，数量型写入当天目标数量并写 done。
- Habit 从日程页顶部更多菜单进入，不增加或替换底部导航项。
- 标题允许 Emoji，不新增 Habit 图标字段。
- 所有 Habit 共用一个本机进度色，在“我的 → 外观设置”中选择。

### 3.2 明确不在 V1

- 每周指定日期、自定义周期、每月或每年 Habit recurrence；
- 无限期 Habit；
- 暂停区间、恢复和计划例外日；
- 每日多个提醒、微信提醒或 ring；
- 一天多次行为明细 `HabitCheckInEntry`；
- 每个 Habit 独立颜色或图标；
- 手动拖动排序；
- 社交挑战、排行榜、分享卡片、徽章和不透明自律分；
- 桌面组件、云同步、跨设备颜色同步；
- 用超额完成抵消其他日期的未完成。

## 4. 页面与交互规格

### 4.1 入口与页面

```text
日程页顶部更多菜单
  → Habit 首页
      → 创建 Habit
      → Habit 详情
          → 编辑 Habit
          → 日期详情 / 补签
          → 提前结束 / 删除 / 再来一轮

我的
  → 外观设置
      → Habit 进度色
```

### 4.2 Habit 首页

- 顶部显示“今日完成 X/Y”。
- 分组：进行中、即将开始、已结束。
- 进行中顺序：未完成或 partial → skipped → done。
- 同组内按提醒时间升序；无提醒时按创建时间升序。
- 完成操作先播放反馈，再平滑移动卡片，避免点击目标瞬间换位。
- 创建入口使用页面右上角或现有视觉体系中的悬浮按钮。
- loading、empty、ready、refreshing、error 必须有独立状态。

### 4.3 Habit 卡片

```text
┌──────────────────────────────────────────┐
│ [剩 6 杯]  💧 每日喝水        ◯ 12 天    │
│            今日 2 / 8 杯       完成率环   │
│            挑战还剩 18 天                │
└──────────────────────────────────────────┘
```

- 卡片背景从左向右的淡色填充表示“挑战时间进度”，不是今日数量进度。
- 时间进度：即将开始为 0%；进行中按当前是第几个计划日计算；自然到期为 100%；提前结束冻结在 `ended_date` 相对原计划区间的真实比例。
- 右侧圆环弧度表示截至今天的挑战完成率。
- 圆环中心显示当前连续达标天数，例如 `12天`。
- 剩余挑战天数使用单独一行小字，例如“挑战还剩 18 天”。
- 左侧圆圈：
  - 打卡型显示未完成/已完成状态，点击完成或撤销；
  - 数量型显示剩余数量，每次点击增加 1；
  - 长按圆圈或点击今日数量文字打开精确输入面板。
- 卡片空白区域进入 Habit 详情。
- 标题原样显示用户输入的 Emoji；不得从标题解析并持久化另一份 icon。
- 颜色来自本机全局 `habit_progress_color`；必须提供满足浅色背景对比度的预设色。
- 圆环、背景进度和快捷圆圈必须有 Semantics label，不得只靠颜色表达状态。

### 4.4 创建与编辑

- 必填：标题、目标类型、开始日期、期限/结束日期。
- 数量型额外必填：目标数量、单位。
- 可选：描述、Category、每日提醒。
- 默认开始日期为今天；允许选择未来日期。
- 默认期限为 30 天。
- 快捷期限：7 天、21 天、30 天、100 天、1 个月、3 个月、1 年、自定义。
- 创建页实时预览包含首日的结束日期和总计划日数。
- 提醒默认关闭；开启后选择当地 `HH:mm`。
- 首次 CheckIn 后，目标数量与单位在编辑页显示为锁定，并说明“如需更换目标，请提前结束后再来一轮”。
- 标题、描述、Category、提醒时间在 active 期间允许修改。
- 有 CheckIn 后不得修改开始日期。
- 结束日期可以延长或缩短，但不得早于已有 CheckIn 的最晚日期，也不得早于当前日期。

### 4.5 日期详情与精确输入

- 数量输入允许 0.01 精度，展示最多两位小数。
- `completed_count = 0` 等价于清除普通 CheckIn，不保存伪 partial。
- 数量达到或超过目标时自动 done；大于 0 且未达到目标时为 partial。
- skipped 使用独立操作，`completed_count = null`，备注可选。
- 含数量或备注的记录撤销前必须二次确认。
- 未来日期、有效期外日期和已结束 Habit 禁止写入。

## 5. 领域模型与不变量

### 5.1 Habit

保留现有核心字段，收紧以下语义：

- `end_date` 在 V1 必填，表示用户可见的最后一个计划日。
- `ended_date` 可空，只在用户提前结束时保存实际结束的当地日期；不得覆盖原 `end_date`。
- 用户语义为闭区间 `[start_date, end_date]`；内部展开统一转换为半开区间 `[start_date, end_date + 1 day)`。
- `target_count` 和 `unit` 必须同时为 null（打卡型）或同时非 null（数量型）。
- 数量型 `target_count > 0`，最多两位小数。
- `recurrence_id` 必须引用 Habit 专属规则，不得引用 Event recurrence revision。
- `is_active=false` 只表示用户提前结束；自然到期不回写该字段。
- 提前结束原子地写 `ended_date=当地当前日期` 和 `is_active=false`、取消未触发 Reminder，并保留原 `end_date` 与此前 CheckIn。
- 普通查询排除 `deleted_at != null`。
- Category 保持弱引用；Category 缺失或软删除不得使 Habit 不可读。

派生生命周期：

- `upcoming`：当前日期早于 `start_date`；
- `active`：`is_active=true` 且当前日期位于有效期；
- `completed`：`is_active=true` 且当前日期晚于 `end_date`；
- `ended_early`：`is_active=false`、`ended_date != null` 且未软删除；
- `deleted`：`deleted_at != null`。

### 5.2 HabitRecurrence

V1 新增轻量独立实体：

- `id`：UUIDv4；
- `frequency`：固定 `daily`；
- `interval`：固定 `1`；
- `timezone_mode`：固定 `follow_device`；
- `created_at`、`updated_at`、`deleted_at`。

规则在创建后不可变；未来 weekly 通过新 revision 或新规则设计扩展，不修改 V1 记录的解释。

### 5.3 HabitCheckIn

沿用现有字段并冻结：

- 唯一身份：`habit_id + check_date`；同一天始终更新同一逻辑记录。
- `check_date` 是操作时设备当地日期，历史日期不因后续时区变化转换。
- `completed_at`、创建/更新时间为 UTC instant。
- 普通打卡来源为 `manual`；通知快捷完成新增稳定来源 `notification_action`。
- 打卡型：done 时 `completed_count`、目标快照和单位快照均为 null。
- 数量型：partial/done 必须保存 `completed_count`、`target_count_snapshot` 和 `unit_snapshot`。
- 所有数量在 Contract 上仍表现为最多两位小数的 number；C++/Storage 使用百分位 fixed-point 整数归一化，避免浮点比较使 `2.50` 的达标判断漂移。
- skipped 的数量、目标快照、单位快照和 `completed_at` 均为 null。
- missed 默认是查询时对缺失历史日期的派生状态，不主动写入 CheckIn。
- clear 操作保持幂等；重复通知 action 也必须返回同一最终 done 状态。

### 5.4 统计公式

- 已经过的有效日：自然挑战以 `end_date` 为上界，提前结束以 `ended_date` 为上界；通常统计到 `min(昨天, 有效上界)`，若今天已 done 或 skipped，可把今天纳入相应统计。
- 今天 absent 或 partial 尚未在午夜前成为最终失败，不提前打断当前连续达标。
- 挑战完成率：`done / (elapsed eligible days - skipped)`。
- skipped 不进入分子、分母，不增加连续天数，但可桥接前后 done。
- partial 在日期结束后不进入 done 分子，并打断连续达标。
- 当前连续：从最近一个已结算的非 skipped 计划日向前统计连续 done，跨 skipped 继续。
- 最长连续：在全有效期内按同一规则计算。
- 数量目标完成度：对每天计算 `min(completed_count / target_snapshot, 1)` 后取平均；不得让超额抵消其他日期不足。
- 累计完成量使用真实 `completed_count`，允许超过目标。
- 7 日/30 日窗口按设备当地自然日计算；全周期按 Habit 有效期计算。
- 所有统计为查询投影，不写回 Habit；性能不足后才另立缓存设计。

## 6. Reminder、Notification 与幂等设计

### 6.1 HabitReminderTemplate

新增独立配置实体，沿用 Anniversary template 的成熟边界：

- `template_key`：UUIDv4；
- `habit_id`：有效 Habit；
- `local_time`：`HH:mm`；
- `timezone_mode`：固定 `follow_device`；
- `method`：V1 固定 `popup`；
- `is_enabled`；
- 创建、更新、软删除时间。

每个 Habit 最多一个未删除 template。默认关闭提醒时可以没有 template；用户首次开启时创建。

### 6.2 每日 occurrence 身份

- occurrence 业务身份：`habit_id + template_key + occurrence_date`。
- `occurrence_date` 是设备当地计划日期。
- `occurrence_key` 使用 Contract identity 规则确定性生成；重复展开、重启、重试和 reconciliation 得到相同身份。
- Reminder 唯一约束：`target_type=habit + target_id + template_key + occurrence_date`。
- timezone 只参与当地时间到 UTC `remind_at` 的投影，不参与身份。
- 只物化当前需要调度的 occurrence/successor，不预生成整轮未来 Reminder。

### 6.3 生命周期规则

- 创建/开启提醒：C++ transaction 保存 template 和第一个可执行 Reminder。
- 编辑提醒时间：取消旧时间尚未触发的 Reminder，以同一日期和新 template revision/identity 重建。
- 当天已 done：原子取消尚未触发的当天 Reminder。
- partial：Reminder 保持有效，消息显示剩余数量。
- skipped：取消当天 Reminder。
- 提前结束/软删除：取消全部未触发 Habit Reminder，并停止 successor。
- 自然到期：结束日之后不生成 successor。
- Android 调度失败或权限拒绝不得回滚 Habit 和 template；保留真实待协调状态，授权后 reconcile。

### 6.4 同日补发

- 设备启动、进程恢复、权限恢复、时间或时区变化时执行 Habit reconciliation。
- 若 `occurrence_date == 当前当地日期` 且 Habit 未 done/skipped，则即使原提醒时间已过也补发一次。
- 当地次日 `00:00` 后，该 occurrence 过期，不跨日补发。
- 同一 occurrence 的多个恢复扫描必须由 Reminder/Notification identity 去重。

### 6.5 通知快捷完成

- 通知 action payload 必须包含稳定的 `habit_id`、`check_date`、`occurrence_key` 和 action identity。
- Binary：写入 done。
- Quantitative：写入 `completed_count=target_count_snapshot` 并写 done。
- 来源为 `notification_action`。
- Android Receiver 不依赖 Flutter 页面存活，直接通过 Kotlin → JNI → C++ 执行。
- C++ 在一个事务中幂等 upsert CheckIn、取消当天未触发任务并返回最终状态。
- 重复点击、旧通知、错误日期、已结束或已删除 Habit 必须安全拒绝或返回已有完成结果，不得重复累计。

## 7. 本机外观偏好

- 新增本机 `habit_progress_color`，只保存预设色 token，不保存任意未校验 ARGB。
- 建议预设：teal（默认）、blue、indigo、green、orange、rose、purple。
- Flutter 依赖抽象的 `AppearancePreferencesGateway`，不在 Widget 中直接读写文件或平台 API。
- Android 使用内置 SharedPreferences 持久化；通过声明过的 MethodChannel 由 Kotlin 提供 get/update，不新增第三方依赖。
- “我的”页面新增“外观设置 → 习惯进度颜色”。
- 修改后 Habit 页面立即刷新，App 重启后保持。
- V1 不上传账号；未来同步时由独立偏好迁移把本机值合并到账号 `settings`。

## 8. 最小 Contract 变更清单

### 8.1 调整现有 Schema

- [ ] 将 Habit `end_date` 收紧为 V1 必填非 null。
- [ ] 为 Habit 增加可空 `ended_date`，保留原计划结束日并区分提前结束。
- [ ] 用 Habit 专属 daily recurrence input 替换 planned 通用 shape，移除 `start_at/end_at/rrule` 的混淆。
- [ ] 收紧 `target_count/unit` 成对约束与两位小数规则。
- [ ] 将 `habit.check_in` 冻结为按 `(habit_id, check_date)` 幂等 set/upsert，而不是 duplicated failure。
- [ ] 增加 `notification_action` CheckIn source。
- [ ] 为 response 明确所有 date、UTC instant、nullable、派生状态和未知枚举失败行为。

### 8.2 新增公开 MethodChannel 能力

- [ ] `habit.create`
- [ ] `habit.update`
- [ ] `habit.list`
- [ ] `habit.detail`
- [ ] `habit.end`
- [ ] `habit.delete`
- [ ] `habit.check_in`
- [ ] `habit.clear_check_in`
- [ ] `habit.list_daily_statuses`
- [ ] `habit.set_reminder`
- [ ] `appearance.get_local`
- [ ] `appearance.update_local`

`habit.list` 返回卡片所需组合投影；`habit.detail` 返回 Habit、recurrence、reminder、核心统计和首屏历史；`habit.list_daily_statuses` 按日期区间返回热力图/历史投影。不得把统计缓存字段加入 HabitResponse。

### 8.3 新增 Native calls

除 Kotlin 本地处理的 `appearance.*` 外，为上述 Habit 能力声明对应窄 JNI/native calls。后台通知 action 必须能够直接调用 `habit.check_in`，不得要求启动 Flutter Engine 才能完成。

### 8.4 错误码

至少冻结并覆盖：

- [ ] 标题为空；
- [ ] Habit 不存在/已删除；
- [ ] 非法期限或结束日期；
- [ ] 非法目标/单位组合；
- [ ] 目标已锁定；
- [ ] 打卡日期在有效期外；
- [ ] 未来日期打卡；
- [ ] Habit 已结束；
- [ ] CheckIn 不存在；
- [ ] Reminder 时间/模板非法；
- [ ] 通知 action 已过期或 identity 不匹配；
- [ ] 外观颜色 token 非法；
- [ ] Storage/transaction/scheduling 真实失败。

## 9. Storage v4 → v5 迁移

### 9.1 新增表

- [ ] `habit_recurrences`
- [ ] `habits`
- [ ] `habit_check_ins`
- [ ] `habit_reminder_templates`

复用：

- `reminders`
- `notifications`
- 现有 workflow transaction 和 generation 机制

### 9.2 关键约束和索引

- [ ] Habit PK、recurrence 引用和 `recurrence_id` 唯一所有权。
- [ ] `habit_check_ins(habit_id, check_date)` 业务唯一。
- [ ] `habit_reminder_templates(habit_id)` 最多一个未删除模板。
- [ ] Habit Reminder `(target_id, template_key, occurrence_date)` 唯一。
- [ ] active Habit 按 `start_date/end_date/ended_date/is_active/deleted_at` 过滤索引。
- [ ] CheckIn 按 Habit + 日期范围查询索引。
- [ ] Reminder 按 status/remind_at 的既有调度索引继续有效。
- [ ] Category 保持弱引用，不增加会破坏历史可读性的强外键。

### 9.3 迁移要求

- [ ] 不修改已经生效的 v4 schema 定义。
- [ ] 实现显式、可重复验证的 `v4 → v5` migration。
- [ ] v4 所有业务行、migration history、generation 和诊断快照原样保留。
- [ ] 新表初始为空；不得伪造 Habit 数据。
- [ ] schema definition checker 覆盖新表、索引、约束和错误同名对象。
- [ ] v5 downgrade guard 使旧 runtime 拒绝继续写。
- [ ] migration 中断、重启、重复初始化和损坏 schema 必须严格失败或幂等恢复。

## 10. 分阶段实施清单

### Phase 0：领域与 Contract 冻结

负责人：数据/Contract 专项

输入：本计划、Habit ADR、Recurrence ADR、Reminder/Notification ADR、现有 v2 Contract。

- [ ] 更新 `docs/domains/habit.md`、`habit_check_in.md`。
- [ ] 新增 HabitRecurrence、HabitReminderTemplate 的领域说明或 Accepted ADR。
- [ ] 记录统计公式、生命周期、日期边界、目标锁定和补签规则。
- [ ] 更新 Habit Schema、method/native capability maps、errors、enums、identity。
- [ ] 定义 request/response/aggregate DTO，不暴露数据库行。
- [ ] 增加合法、非法、边界和 identity fixtures。
- [ ] 更新 `docs/index.md`、status、roadmap/open issue 的对应状态。

验收：Contract validator 全通过；每个公开方法都有一条明确实现路径；`OPEN-DOM-001` 的 recurrence、check-in identity 和 reminder 幂等关闭条件全部满足。

阻塞：若无法冻结 Reminder occurrence identity、日期闭区间或通知 action 幂等，不得进入 Phase 1。

### Phase 1：SQLite v5 与 C++ 领域核心

负责人：C++ Core / Storage 专项

- [ ] 实现四个 Domain/Storage 模型和 Repository ports。
- [ ] 实现 v4→v5 migration、schema checker、索引和 transaction。
- [ ] 实现 Habit create/update/list/detail/end/delete。
- [ ] 实现 CheckIn set/clear、补签、目标锁定与严格校验。
- [ ] 实现 lifecycle、daily status projection 和统计服务。
- [ ] 使用固定 clock 和明确设备 timezone 测试。
- [ ] 禁止 Application/Domain 直接出现 SQLite、Flutter 或 Android 类型。

验收：Repository round-trip、事务回滚、软删除、统计和迁移测试通过；构建后 `excellent_calendar_check` 通过。

### Phase 2：Habit Reminder Template 与 C++ 工作流

负责人：C++ Core / Reminder Workflow 专项

- [ ] 实现 template create/update/disable/delete。
- [ ] 实现确定性 occurrence identity、滚动 successor 和唯一约束。
- [ ] CheckIn done/skipped、提前结束和删除时原子取消 Reminder。
- [ ] 实现同日 recovery、跨日 expiry、时区重算和幂等 replay。
- [ ] 实现通知快捷完成事务入口。
- [ ] 保证 Notification 只由真实投递产生。

验收：重复扫描、重启、陈旧 Reminder、重复 action、权限恢复和时区切换均不会重复提醒或重复 CheckIn。

### Phase 3：Kotlin/JNI/MethodChannel 接线

负责人：Android/Kotlin Native 专项

- [ ] 新增窄 Habit native bridge、JNI exports 和 handler。
- [ ] 严格映射 snake_case、date、UTC、nullable、enum、NativeResult。
- [ ] 接入现有 Scheduler/Reconciler，不创建第二份 Android 真相源。
- [ ] 新增 Habit notification deep link 和 action receiver。
- [ ] action receiver 在 Flutter 未启动时也能初始化正式 Calendar Core runtime。
- [ ] 权限拒绝、调度失败和恢复使用稳定错误/状态，不吞异常。
- [ ] 使用 SharedPreferences 实现 `appearance.get_local/update_local`。

验收：Kotlin contract tests、JNI instrumentation、后台 action、进程重启和 Debug APK 构建通过。

### Phase 4：Dart DTO、Gateway 与 Application

负责人：Flutter Application / Boundary 专项

- [ ] 建立 Habit、CheckIn、DailyStatus、Statistics、ReminderSettings DTO。
- [ ] 建立类型化 HabitGateway 和 AppearancePreferencesGateway。
- [ ] 实现首页、详情、表单、日期详情 Controller/UseCase。
- [ ] 防止重复提交、过期异步结果覆盖新状态和页面销毁后更新。
- [ ] 只消费 C++ 统计投影，不在多个 Controller 重复实现公式。
- [ ] “再来一轮”只预填新建请求，不复用旧 ID、CheckIn 或 Reminder identity。

验收：DTO round-trip、malformed payload、controller 正常/失败/并发测试通过。

### Phase 5：Flutter Habit 页面与卡片

负责人：Flutter Presentation 专项

- [ ] 日程页顶部更多菜单增加“习惯”。
- [ ] 实现 Habit 首页、卡片、分组、排序和完成后动画。
- [ ] 实现创建/编辑页、期限快捷项和结束日期预览。
- [ ] 实现详情统计、圆环、时间进度背景、热力图和历史列表。
- [ ] 实现数量精确输入、日期详情、补签、skipped、撤销确认。
- [ ] 实现自然到期、提前结束、删除和“再来一轮”流程。
- [ ] 替换 Habit 通知占位页为真实详情路由。
- [ ] 覆盖小屏、文字缩放、深浅色、触控尺寸、Semantics 和无颜色状态表达。

验收：Widget/golden（若仓库已有基线）/navigation/controller tests 通过；页面无溢出，TalkBack 可识别关键状态。

### Phase 6：我的页面外观设置

负责人：Flutter Presentation + Kotlin Local Settings

- [ ] 在“我的”增加外观设置入口。
- [ ] 展示经过对比度验证的预设色。
- [ ] 修改后 Habit 页面实时响应。
- [ ] App 重启后保持；损坏或未知 token 严格回退默认 teal，并记录诊断。
- [ ] 明确标注“保存在本机”，不伪装云同步。

验收：get/update/重启持久化/非法 token/默认值测试通过。

### Phase 7：真实端到端与发布验收

负责人：跨层整合与独立 Review

- [ ] Contract validator、identity fixtures、storage migration tests。
- [ ] C++ 构建后全量检查。
- [ ] Flutter format/analyze/test。
- [ ] Kotlin unit/instrumentation tests。
- [ ] Android Debug APK 和 Native smoke。
- [ ] 真机通知权限、重启、杀进程、时区变化、日期跨越、快捷完成。
- [ ] 审查 dirty worktree，确认无无关重构、依赖升级或用户改动覆盖。
- [ ] 更新 current status、roadmap、open issue、索引和开发日志。

验收：第 11 节所有黑盒场景有真实证据；未执行的设备矩阵必须明确标记未验证，不得报告完整完成。

## 11. 黑盒验收矩阵

### 11.1 创建和生命周期

- [ ] 创建默认 30 天打卡型 Habit，开始/结束日和总天数正确。
- [ ] 创建 1 个月、跨月末、跨闰年和未来开始 Habit。
- [ ] 创建数量型目标 2.50 公里并正确 round-trip。
- [ ] 非法空标题、0 目标、目标无单位、结束早于开始严格失败。
- [ ] upcoming 到开始日自动 active；结束日次日自动 completed。
- [ ] 提前结束保留原计划结束日、写实际 `ended_date`、冻结真实时间进度、取消未来提醒且不可恢复。
- [ ] 再来一轮创建全新 ID 和 identity，不复制 CheckIn。

### 11.2 CheckIn

- [ ] Binary 快捷完成、撤销、重复提交幂等。
- [ ] Quantitative +1、精确输入、partial、done、超额和清零。
- [ ] 补签有效期内过去日期；拒绝未来和有效期外日期。
- [ ] skipped 无数量、可备注并桥接 streak。
- [ ] 首次 CheckIn 后目标和单位锁定。
- [ ] 软删除 CheckIn 后重建仍满足每日唯一。

### 11.3 统计

- [ ] absent past day 动态 missed，数据库不产生空 CheckIn。
- [ ] 今天 absent/partial 在午夜前不提前打断 streak。
- [ ] done-skipped-done 的 streak 为 2。
- [ ] partial 在结算后打断 streak。
- [ ] 7/30/all rate、最长 streak、累计量和日均量正确。
- [ ] 每日数量比例封顶 100%，超额只进入累计量。
- [ ] 卡片背景时间进度、圆环完成率、中心 streak 和剩余天数分别正确。

### 11.4 Reminder 与 Notification

- [ ] 默认关闭提醒时不请求权限、不创建 Alarm。
- [ ] 开启提醒并授权后按当地时间调度。
- [ ] 拒绝权限时 Habit 创建成功，UI 显示待授权，授权后 reconcile。
- [ ] 提醒前 done/skipped 时不通知；partial 时显示剩余数量。
- [ ] 设备当天晚些时候恢复且未达标时补发；跨日后不补发旧 occurrence。
- [ ] 进程重启、重复恢复和时区切换不重复通知。
- [ ] Binary 通知 action 直接 done。
- [ ] Quantitative 通知 action 写目标数量并 done。
- [ ] 重复点击 action 不产生重复 CheckIn；旧 action 不修改错误日期。
- [ ] 通知点击打开真实 Habit 详情。

### 11.5 外观和页面

- [ ] 日程页更多菜单进入 Habit，不改变四项底部导航。
- [ ] 未完成、skipped、done 分组顺序正确并平滑移动。
- [ ] Emoji 标题原样显示。
- [ ] 修改预设进度色立即生效并在重启后保留。
- [ ] 未知颜色 token 回退默认值。
- [ ] loading、empty、error、retry、permission denied 和 deleted deep link 页面正确。
- [ ] 200% 文字缩放、小屏和 TalkBack 下仍可完成核心操作。

### 11.6 Storage 与迁移

- [ ] fresh v5 初始化创建精确表和索引。
- [ ] v4→v5 保留所有 Event/Reminder/Anniversary/Category/Notification 数据。
- [ ] migration 中断和重复初始化安全恢复。
- [ ] 同名错误表/索引被 schema checker 拒绝。
- [ ] 事务失败不留下 Habit、recurrence、template、Reminder 或 CheckIn 半状态。
- [ ] 旧 runtime 因 v5 guard 拒写，不形成双真相。

## 12. 必须执行的验证命令

### Contract

- 仓库现有 Contract validator 和全部 Habit/Reminder/identity fixtures。

### C++

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

### Flutter

```powershell
dart format --output=none --set-exit-if-changed <本次修改的 Dart 文件>
flutter analyze
flutter test
flutter build apk --debug
```

### Native smoke

```powershell
cd test_environment/flutter_native_smoke
flutter test
flutter analyze
flutter build apk --debug
```

### Android 真机

- 通知权限允许/拒绝/恢复；
- App 前台、后台、被杀、设备重启；
- 当日错过提醒补发和跨日过期；
- 通知栏快捷完成；
- 时区切换和系统时间变化；
- APK 中目标 ABI native library 检查。

## 13. 开发提交与评审建议

建议按以下独立可审查单元组织，不把全部工作压入一个提交：

1. Domain/ADR/Contract 冻结；
2. SQLite v5 migration 与 Habit Core；
3. CheckIn 与 Statistics；
4. Habit Reminder Workflow；
5. Kotlin/JNI/MethodChannel；
6. Dart Application/Gateway；
7. Habit 首页与卡片；
8. 表单、详情、热力图与历史编辑；
9. Notification action 与真实设备恢复；
10. 本机外观偏好；
11. 跨层回归、文档状态和发布验收。

每个单元必须附带自己的定向测试；最终阶段再执行全量构建和真机矩阵。不得把“Schema 已存在”“页面能展示”或“Mock 通过”分别称为 Habit 闭环完成。

## 14. 完成定义

只有同时满足以下条件，Habit V1 才能报告完整完成：

- 所有已冻结用户行为真实可用；
- Domain、Contract、Dart、Kotlin/JNI、C++、SQLite 描述同一语义；
- v4→v5 migration 与旧 runtime guard 通过；
- CheckIn、统计和 Reminder identity 在重启/重试下保持幂等；
- Habit 页面不再使用 Fake、占位或伪统计；
- 通知权限、同日补发和通知栏快捷完成经过真机验证；
- C++ check、Flutter analyze/test、Android Debug build 和适用 smoke 全部通过；
- 最终 diff 无无关重构、依赖升级、调试代码或用户修改覆盖；
- 所有未执行设备矩阵和剩余风险被明确记录。
