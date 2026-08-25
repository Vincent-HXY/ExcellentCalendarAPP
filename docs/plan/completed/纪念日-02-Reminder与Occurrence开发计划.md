# 纪念日 Reminder 与日历 Occurrence 开发计划

> 状态：Released / 四层生产链、Storage v3 与 Anniversary R1 均 integrated + active；剩余设备矩阵由产品负责人接受为非阻断验证债
> 制定日期：2026-08-23（Asia/Shanghai）  
> 负责模块：Anniversary、Reminder、Notification、Recovery、Calendar occurrence projection  
> 使用 Skill：`calendar-data-contracts`  
> 计划性质：跨层总计划；先冻结 Contract，再由 C++、Kotlin、Flutter 三个工作流并行开发，最后统一集成、去除生产 Fake 并完成真机验收

## 0. 拆分执行与真相源

本文件继续作为 Anniversary Reminder 与日历 Occurrence 的唯一产品需求、领域语义和跨层完成标准。四份子计划只拆分执行责任，不得增加、删除、放宽或重新解释本文件第 2～17 节的要求：

1. [纪念日-03-contracts设计.md](./纪念日-03-contracts设计.md)：先完成领域文档、ADR、Schema、能力图、身份、错误码、兼容矩阵和 fixture，并输出冻结的 Contract 基线。
2. [纪念日-04-Flutter开发.md](./纪念日-04-Flutter开发.md)：在 Contract 冻结后实现 Dart DTO/Gateway/Application/UI，可通过测试 Fake 独立开发。
3. [纪念日-05-Kotlin开发.md](./纪念日-05-Kotlin开发.md)：在 Contract 冻结后实现 Kotlin Contract/Handler、Android 调度、通知与点击，可通过测试 Fake Native Bridge 独立开发。
4. [纪念日-06-CPP开发.md](./纪念日-06-CPP开发.md)：在 Contract 冻结后实现 C++ Domain/Application/Repository/JSON Storage/Boundary，可通过内存 Repository、固定 Clock/TZDB 和边界 fixture 独立开发。

执行拓扑固定为：

```text
Contracts 冻结并通过门禁
        ↓
        ├─ Flutter 工作流（typed Fake / widget fixture）
        ├─ Kotlin 工作流（Fake Native Bridge / fake Android service）
        └─ C++ 工作流（in-memory Repository / fake Clock）
        ↓
最终集成：真实 DTO ↔ Handler ↔ JNI ↔ C++ ↔ JSON ↔ Alarm/Notification
        ↓
清除生产组合中的 Fake/占位路径，执行跨层 smoke、迁移、构建与真机验收
```

并行开发的共同规则：

- 三个实现工作流必须从同一个冻结 Contract 提交开始；任何字段、枚举、错误码、身份或状态歧义都提交给 Contract 负责人处理，不得在语言层自行发明兼容写法。
- Fake 只用于单层自动化测试、开发预览或依赖倒置验证；不得返回“看似成功”的伪 Native、伪持久化或伪 Android 调度结果。
- “去除 Fake”指最终生产组合入口不得依赖本功能的 Fake Gateway、Fake Native Bridge、内存 Store 或占位成功。测试 Fake 应保留以支持回归；范围外的 `FakeAnniversaryShareGateway` 不属于本计划，不得借机修改。
- 三个工作流分别达到“并行交付就绪”不等于功能完成。只有最终集成后的真实链路、迁移、构建和真机门禁全部通过，才能满足第 17 节完成定义。
- Contract 冻结提交合入后，Flutter、Kotlin、C++ 负责人从该提交创建相互隔离的分支/worktree；各自只修改子计划声明的目录。最终集成人保留各工作流的 `docs/log.md` 追加记录并解决行尾冲突，不覆盖任一方证据。

责任拆分与需求覆盖如下；空白不表示取消要求，而表示该层不是规则 owner：

| 上位计划 | Contracts | Flutter | Kotlin/Android | C++ Core/Storage | 最终集成 |
| --- | --- | --- | --- | --- | --- |
| §2～3 产品行为与不变量 | 冻结语义/shape/error | 表单、详情、状态反馈 | 权限、调度、通知、点击 | 领域、生命周期、补发、successor | 真实全链验收 |
| §4 occurrence 查询 | request/summary/page/cursor | typed port、自动分页、摘要消费 | MethodChannel/JNI 透传 | 展开、过滤、排序、cursor | 多页与日历消费 smoke |
| §5 身份与时间 | namespace/canonical/golden vector | 只透传 date/time/identity | 只提供设备 IANA timezone | 生成 identity、DST/UTC/CAS | 跨语言向量对齐 |
| §6 Reminder/Notification | target-specific schema/聚合审计 | 消费必要状态 | 单次真实 Android post | Reminder/attempt/batch 原子状态 | Store/通知证据闭环 |
| §7 Workflow/Repository | 事务与 partial-success 语义 | 区分保存/调度 | commit 后 reconcile | 窄 port、JSON commit/recovery | 移除 Fake、真实接线 |
| §8～11 分层清单 | Contract owner | §11 owner | §10 owner | §9 owner | 处理跨层薄适配 |
| §12～13 验证 | Contract fixture | Dart/Widget/analyze/build | JVM/lint/Android/device | build-after-test/migration/crash | smoke/APK/JNI/真机 |
| §14～17 门禁、风险、范围、DoD | 冻结门禁 | 并行交付 | 并行交付 | 并行交付 | 唯一最终完成判定 |

## 1. 目标

在不把 Anniversary 转换为 Event、不预生成多年 occurrence、不建设大型统一 `CalendarTransaction` 的前提下，完成两个能力：

1. Anniversary 接入现有 Reminder → Android Alarm/Notification 主链路，支持一次性与年度纪念日、多个 popup 提醒、补发、时区变化、暂停/恢复、编辑/删除联动和年度 successor。
2. 提供日历周/月/年视图所需的 `anniversary.list_occurrences` 有界区间查询，返回可直接展示的轻量摘要；日历点击摘要后再使用现有 `anniversary.detail` 查询完整内容。

最终链路应达到：

```text
Flutter Anniversary Form / Detail
    ↓
Flutter Application + typed Anniversary Gateway
    ↓ MethodChannel
Kotlin Anniversary Handler
    ↓ JNI
C++ Anniversary Workflow
    ↓
Narrow Workflow Repository
    ↓
JSON Storage（当前）/ SQLite transaction（未来）
    ↓ commit success
Reminder schedule reconciliation
    ↓
AlarmManager Dispatcher → Notification → Anniversary Detail
```

日历读取链路应达到：

```text
Calendar Application（未来聚合方）
    ↓ bounded local-date window
anniversary.list_occurrences
    ↓
C++ Anniversary occurrence projection
    ↓
轻量摘要列表
    ↓ 用户点击“更多详情”
anniversary.detail
```

## 2. 当前基线与约束

### 2.1 已有能力

- Anniversary 已是独立实体，支持公历一次性与 `yearly + interval=1`，原始日期保存在 `Anniversary.date`。
- `AnniversaryRecurrence` 是 Anniversary 专属轻量规则，不使用 Event Recurrence revision。
- Anniversary CRUD、详情、列表、倒计时、JNI 和 JSON 两 Store 事务已经实现。
- 2 月 29 日在非闰目标年落到该年 2 月最后一天。
- Reminder、Notification、RecoveryBatch、AlarmManager Dispatcher、两阶段投递、系统重启与时区变化恢复入口已经存在。
- Reminder/Notification Contract 已预留 `target_type=anniversary`，但 C++ 当前只放行 Event，Anniversary occurrence identity 尚未激活。
- Flutter 原型已有 `ReminderDraft.advanceDays`，但当前生产 adapter 会拒绝非空 Anniversary reminder plan。

### 2.2 必须保护的不变量

- Anniversary 仍是独立领域实体，不复制为 Event。
- Anniversary occurrence 是 date-only 当地自然日，不伪造 UTC `occurrence_start_at`。
- 不持久化无限未来 occurrence，不为 Anniversary 增加完成、跳过、取消等 occurrence 状态。
- Reminder 是未来任务真相源；Notification 是实际投递 attempt/聚合投递日志；Android Alarm 不是第二真相源。
- Scheduler reconciliation 是数据提交后的可重试副作用，不参与领域数据提交。
- 所有跨语言字段、方法、枚举、错误码和身份算法先进入 Contract，再进入实现。
- 现有 Event Reminder、Ring、Recovery 和 Notification 两阶段投递不得发生语义回归。

## 3. 已确认的产品需求

### 3.1 支持范围

- 一次性 Anniversary 和年度 Anniversary 都允许设置 Reminder。
- V1 只支持 `popup`；不支持 ring、wechat。
- 每个 Anniversary 最多 5 条活动提醒。
- 每条配置由 `advance_days + local_time` 表达，例如：
  - 当天 09:00；
  - 提前 1 天 09:00；
  - 提前 7 天 09:00；
  - 用户自定义提前 0～365 天、当地时间精确到分钟。
- 默认不开启提醒；已有 Anniversary 升级后不自动生成 Reminder。
- 相同 Anniversary 下不允许重复的 `(advance_days, local_time, method)` 配置。
- 提醒时区模式固定为跟随设备当前 IANA timezone。

### 3.2 创建与正常调度

- 一次性 Anniversary 只生成本次 occurrence 的 Reminder，不创建 successor。
- 年度 Anniversary 为每条提醒配置物化首个仍有意义的 occurrence Reminder；成功投递、永久失败或过期终结后分别按规则创建下一年 successor。
- 创建时若本次 Reminder 的 `remind_at` 已经过期：
  - 一次性 Anniversary 不立即补发，也不创建过去任务；
  - 年度 Anniversary 跳过本次，直接物化下一年度 Reminder。
- Notification 权限拒绝时仍保存 Anniversary 和提醒设置；页面显示权限警告，后续授权后自动 reconciliation。
- 没有 exact alarm 权限时允许近似调度，并明确提示可能延迟；不因缺少 exact alarm 权限清空 Reminder。

### 3.3 迟到补发

一条 Anniversary Reminder 的补发有效窗口定义为：

```text
[原计划 remind_at, 对应 occurrence_date 在当前设备时区下的次日 00:00)
```

示例：9 月 1 日 Anniversary，提前 7 天提醒原定 8 月 25 日 09:00：

- 8 月 31 日设备恢复：补发；
- 9 月 1 日设备恢复：补发；
- 9 月 2 日设备恢复：不补发；年度链安排下一年。

补发规则：

- 同一 `(anniversary_id, occurrence_key)` 下同时存在多条逾期 Reminder 时，只展示一条聚合 popup Notification。
- 不同 Anniversary occurrence 分别展示，不能合并为无详情目标的全局摘要。
- 聚合文案表达当前事实，例如“明天是……”，可在次要信息说明原计划提醒时间或覆盖数量。
- 聚合 Notification 实际投递成功后，同组所有被覆盖 Reminder 都进入 `sent`。
- 为避免伪造多条系统通知，所有被覆盖 Reminder 必须共同记录同一个实际 `fulfillment_delivery_id`；聚合 Notification/RecoveryBatch 必须保存完整、稳定排序的 `covered_reminder_ids`。
- 每条年度 Reminder 链分别创建自己的下一年 successor，不能因聚合而丢失某个提醒配置。
- 相同聚合投递的重启、重试和重复 reconciliation 必须复用同一 delivery identity，不能再次展示。

### 3.4 编辑、暂停、恢复与删除

- 总开关关闭表示暂停：取消未来待投递任务，但保留全部提醒配置。
- 再次开启时，从第一个仍有意义的 occurrence 重新物化任务。
- 允许逐条删除或修改提醒配置。
- 修改标题、备注、分类、重要性：不改变 Reminder 时间；未来通知使用最新内容，历史 Notification 保留冻结快照。
- 修改日期：旧日期的未来 Reminder 失效，按新日期重新物化。
- 修改 `advance_days`、`local_time`：旧配置链终结，新配置链重新物化。
- 年度改一次性：
  - 原始日期仍在未来时，只保留一次性任务；
  - 原始日期已过去时，不创建未来任务。
- 一次性改年度：从第一个未来 occurrence 开始物化。
- 删除 Anniversary：软删除 Anniversary，取消所有未来 Reminder，保留 Notification 投递历史。
- 修改与旧 Alarm 并发时，prepare 阶段必须校验 target、occurrence identity 和 expected `remind_at`；陈旧任务必须在展示前被拒绝。

### 3.5 Notification 内容与导航

- 准时提前通知：`距离“{title}”还有 N 天`。
- 当天通知：`今天是“{title}”`。
- 年度 occurrence 可附加：`今年是第 N 周年`。
- 原始年份 `years_elapsed=0`，UI 不显示“第 0 周年”。
- 不在锁屏通知中展示 Anniversary.note。
- 点击正常或聚合 Anniversary Notification 均进入真实 Anniversary 详情页。
- Anniversary 已删除时，点击历史通知显示稳定的“纪念日不存在或已删除”状态，不伪造详情。

## 4. Occurrence 查询需求

### 4.1 查询语义

新增公开方法与内部调用：

```text
MethodChannel: anniversary.list_occurrences
Native call:   anniversary.list_occurrences
```

请求使用当地日期半开区间：

```text
[range_start_date, range_end_date)
```

约束：

- `timezone` 为有效 IANA timezone。
- 单次窗口最多覆盖 400 个当地自然日。
- 不设置 200 条总结果硬上限。
- Native 使用稳定 cursor 分批返回，建议每批最大 500 条；Flutter Application 自动读取所有页，日历消费者看到完整窗口结果。
- 可按 `category_ids`、`importance` 筛选；重复值和非法枚举显式失败。
- 默认只返回活动、未删除 Anniversary。

### 4.2 展开规则

- 一次性 Anniversary 仅在 `Anniversary.date` 落入窗口时返回一次。
- 年度 Anniversary 从原始年份开始动态展开，不生成早于原始日期的 occurrence。
- 历史窗口正常返回过去 occurrence，只要 Anniversary 未删除。
- 编辑 Anniversary.date 后，历史 occurrence 按当前事实重新计算；V1 不保留 revision 历史。
- 删除 Anniversary 后，过去和未来 occurrence 都不再返回。
- 2 月 29 日在非闰年落到该年 2 月最后一天。
- `years_elapsed = occurrence_year - source_year`。
- 按 `(occurrence_date, anniversary_id, occurrence_key)` 稳定升序排列。
- Anniversary occurrence 是全天日期，没有 start/end Instant，也没有完成/跳过状态。

### 4.3 摘要响应

每条 `AnniversaryOccurrenceSummary` 至少包含：

- `anniversary_id`；
- `occurrence_key`；
- `occurrence_date`；
- `source_date`；
- `title`；
- `calendar_type`；
- `is_repeating`；
- `years_elapsed`；
- `category_id`；
- `importance`；
- `has_active_reminders`；
- `reminder_count`。

不返回：

- 完整 note；
- Reminder 任务明细；
- Notification 历史；
- 本地化日期、星期和 UI 文案；
- 创建/更新时间等日历摘要不需要的字段。

日历交互边界：

```text
选择周/月/年视图中的日期
→ 展示 Event / Anniversary 摘要
→ 点击 Anniversary 摘要中的“更多详情”
→ anniversary.detail(id, timezone)
```

本计划只提供 Anniversary 摘要查询，不实现完整 Calendar UI，也不新增统一 `calendar.list_items`。

## 5. 身份、幂等与时间模型

### 5.1 Occurrence identity

在 `contracts/identity.yaml` 冻结 Anniversary namespace、canonical JSON 和 UUIDv5 测试向量。候选输入语义为：

```text
occurrence_key = UUIDv5(
  anniversary_occurrence_namespace,
  [anniversary_id, occurrence_date]
)
```

要求：

- 同一 Anniversary、同一当地 occurrence 日期始终得到同一 key。
- 标题、note、category、importance 修改不改变 key。
- 日期修改导致受影响 occurrence key 改变。
- 日期改回原值时恢复同一确定性 key；幂等逻辑必须能够识别并安全恢复/替换旧终结记录。

### 5.2 Reminder configuration identity

每条提醒配置冻结稳定 template identity，候选语义为：

```text
template_key = UUIDv5(
  anniversary_reminder_template_namespace,
  [anniversary_id, advance_days, local_time, "follow_device", "popup"]
)
```

Reminder identity 候选语义为：

```text
reminder_id = UUIDv5(
  reminder_namespace,
  ["anniversary", anniversary_id, occurrence_key, template_key]
)
```

最终字段顺序、namespace 和字符串格式必须在 Contract 阶段冻结并提供 golden vectors，不允许实现阶段自行变化。

### 5.3 聚合补发 identity

同一 occurrence 的聚合补发 identity 至少绑定：

- `anniversary_id`；
- `occurrence_key`；
- 稳定排序后的 `covered_reminder_ids`；
- 固定 method `popup`。

聚合 membership 在 prepare 后冻结；相同请求重放复用原 attempt，不因重试时钟改变。后续新到期但未包含在已冻结 membership 的 Reminder 不能静默加入同一 prepared attempt。

### 5.4 Date-only 与 UTC 物化

Reminder 保存两类信息：

- 用户意图：`advance_days`、`local_time`、`timezone_mode=follow_device`；
- 当前调度投影：`occurrence_date`、`remind_at` UTC Instant。

换算顺序：

```text
occurrence_date
→ 当地日期减 advance_days
→ 拼接 local_time
→ 使用当前设备 IANA timezone 解析当地墙上时间
→ 转换为 UTC remind_at
```

DST gap/fold 延续项目现有规则：gap 前移到首个合法 Instant，fold 选择较早 Instant。时区变化后重算未终结 Reminder 的 `remind_at`，并使用 expected value/CAS 阻止旧 Alarm 投递。

## 6. Reminder 与 Notification 数据语义

### 6.1 Anniversary Reminder 分支

Reminder Contract/Domain 需要增加 Anniversary 专用强类型字段，至少表达：

- `template_key`；
- `occurrence_date`；
- `advance_days`；
- `local_time`；
- `timezone_mode`；
- `fulfillment_delivery_id`；
- 现有 `occurrence_key`。

Anniversary Reminder 不使用：

- Event `recurrence_revision`；
- Event `occurrence_start_at`；
- `advance_minutes`。

目标类型条件必须由 schema、C++ Domain、Storage codec、Kotlin Contract 和 Dart DTO 同时约束，不能用 nullable 字段组合的宽松解析代替。

### 6.2 `sent` 的聚合履约语义

普通 Reminder 继续表示“一条 Reminder 对应一次真实 delivery”。Anniversary 合并补发扩展为：

> `status=sent` 表示该 Reminder 的提醒义务已经由一个真实成功投递的 Notification 履行；多个 Reminder 可以由同一个聚合 delivery 履行，但必须能通过 `fulfillment_delivery_id` 与 `covered_reminder_ids` 证明关联。

要求：

- 不能为未展示的 Reminder 伪造独立 Notification attempt。
- 聚合 Notification 只生成一个真实 attempt 和一个 Android notification tag。
- finalize sent 时，在同一 Repository logical commit 中：
  - 聚合 Notification → `sent`；
  - 所有 covered Reminder → `sent`；
  - 所有 covered Reminder 写入相同 `fulfillment_delivery_id`；
  - 每条年度模板创建各自 successor；
  - RecoveryBatch/聚合 membership 更新为完成。
- retryable failure 时所有 covered Reminder 保持可重试，不生成 successor。
- permanent failure 时聚合 attempt 记失败，covered Reminder 按冻结规则进入失败终态，年度模板分别创建 successor。
- 超过 occurrence 日末仍未投递时，本年度 Reminder 进入 expired，年度模板分别创建 successor。

### 6.3 Notification 聚合分支

优先新增明确的 Anniversary catch-up 聚合分支，而不是把它伪装成普通单 Reminder Notification。Contract 至少需要表达：

- 聚合 Notification kind；
- `target_type=anniversary`；
- `target_id=anniversary_id`；
- `occurrence_key`；
- `covered_reminder_ids`；
- `recovery_batch_id` 或等价恢复归属；
- 稳定 delivery/attempt identity；
- 真实 title/body/planned/prepared/finalized/sent 时间。

点击 payload 必须携带 Anniversary target identity；Flutter 不需要先进入恢复摘要页。

## 7. Application Workflow 与 Repository 方案

### 7.1 已确认架构

不建立包含所有 Calendar 实体的大型 `CalendarTransaction`。使用领域 Workflow + 窄 Repository：

```text
Create/Update/Delete/Toggle Anniversary Workflow
        ↓
AnniversaryReminderWorkflowRepository
        ↓
JSON recoverable commit（当前）
SQLite transaction（未来）
```

Application 层不得感知 JSON 文件、journal、SQLite 或 AlarmManager。

### 7.2 建议的窄 Repository 能力

Repository 接口按业务意图提供窄操作，不暴露万能可变 State：

- `commit_create_plan(anniversary, recurrence, reminder_templates)`；
- `commit_update_plan(expected_updated_at, replacement, reminder_templates)`；
- `commit_delete_plan(anniversary_id, deleted_at)`；
- `set_reminders_enabled(anniversary_id, enabled, now, timezone)`；
- `load_occurrence_query_state(range, filters)`；
- `prepare_anniversary_delivery(expected_identity)`；
- `finalize_anniversary_delivery(attempt, outcome)`；
- `plan_anniversary_recovery(now, timezone)`；
- `recalculate_for_timezone_change(old_timezone, new_timezone, now)`。

允许根据现有代码结构拆成多个更窄 interface，但不能让 Flutter/Kotlin 分散完成跨实体补偿。

### 7.3 当前 JSON 实现

当前 JSON adapter 使用窄范围、可恢复 logical commit，只协调实际受影响 Store；不得用无保护的顺序写替代。

创建/更新/删除至少涉及：

- `anniversaries.json`；
- `anniversary_recurrences.json`；
- `reminders.json`。

聚合投递/恢复至少涉及：

- `reminders.json`；
- `notifications.json`；
- `reminder_recovery_batches.json`。

JSON 可靠性要求：

- 所有写 `reminders.json` 的 JSON workflow 共用同一目录锁和 storage-level commit/recovery coordinator。
- storage coordinator 可以提交“本次触及 Store 的 after image/delta”，但不能向 Domain/Application 暴露巨大 `CalendarCoreState`。
- 进程向任何 Query、Scheduler 或 JNI 能力开放前，bootstrap 必须恢复全部 prepared commit。
- 一个 prepared commit 未恢复前，不允许另一个 journal 基于旧 `reminders.json` 提交并覆盖它。
- failure hooks 覆盖 prepare 后、每个 Store 写后、commit 后和清理前崩溃。
- 重放必须确定、幂等，不能生成新的 Reminder/Notification ID。

### 7.4 SQLite 迁移边界

未来 SQLite 实现保持相同 Application Workflow 和 Repository port：

- create/update/delete 与 Reminder replacement 使用数据库事务；
- finalize 聚合 Notification、covered Reminders 和 successors 使用数据库事务；
- Scheduler 仍在事务提交后 reconciliation；
- JSON journal 实现退出，但领域身份、Contract 和业务状态不变化；
- JSON → SQLite migration 必须读取本计划新增的 Reminder/Notification 字段和聚合关联。

### 7.5 Scheduler reconciliation

数据提交和 Scheduler 同步严格分离：

1. Repository logical commit 成功；
2. Workflow 返回已保存结果和 `schedule_reconciliation_required`；
3. Kotlin coordinator 触发权威 Reminder queue reconciliation；
4. 调度失败时页面提示“已保存，但提醒暂未成功调度”；
5. App 启动、回前台、权限恢复、系统重启、升级、时间或时区变化时重试。

调度失败不得回滚或删除已保存 Anniversary/Reminder，也不得把 Android Alarm 状态写成业务真相。

## 8. Contract 变更清单

### 8.1 领域与 ADR

- [ ] 更新 `docs/domains/anniversary.md`：Reminder ownership、occurrence identity、补发窗口、编辑/删除和历史动态投影。
- [ ] 更新 `docs/domains/reminder.md`：Anniversary 分支、date-only identity、滚动链、聚合 `sent` 语义。
- [ ] 更新 `docs/domains/notification.md`：Anniversary catch-up 聚合 attempt 与 covered Reminder 关系。
- [ ] 更新 `docs/domains/reminder_recovery_batch.md`：按 Anniversary occurrence 分组及 membership 冻结。
- [ ] 新增或更新 Accepted ADR，记录“不使用 Event Recurrence、不建设大型 CalendarTransaction、Repository port + JSON recoverable commit + future SQLite transaction”的决定。

### 8.2 Schema

- [ ] 新增 Anniversary reminder draft/schema，使用 `advance_days/local_time/method/is_enabled`，拒绝绝对 UTC 和 ring/wechat。
- [ ] 扩展 create/update Anniversary request，使 Anniversary 与 reminder plan 由同一 Workflow 接收。
- [ ] 扩展 Anniversary detail response，返回提醒配置与总开关状态，不暴露内部调度审计噪音。
- [ ] 新增 `list_anniversary_occurrences_request`。
- [ ] 新增 `anniversary_occurrence_summary_response`。
- [ ] 新增 `anniversary_occurrence_list_response`。
- [ ] 扩展 Reminder response 的 Anniversary 条件分支。
- [ ] 扩展 Notification/RecoveryBatch response 的聚合覆盖关系。
- [ ] 扩展 Notification tap payload，使聚合通知可路由 Anniversary detail。
- [ ] 更新 `method_channels.yaml` 与 `native_calls.yaml`，在实现和验证前保持准确的 planned/blocked 状态。
- [ ] 更新 `identity.yaml`，提供 occurrence/template/reminder/aggregate delivery golden vectors。
- [ ] 更新 `enums.yaml` 和 `error_codes.yaml`，禁止自由文本状态和错误。

### 8.3 预期稳定错误类别

Contract 阶段冻结具体 code，至少覆盖：

- Anniversary reminder 配置非法；
- 提醒配置重复或超过 5 条；
- occurrence 查询窗口非法或超过 400 天；
- cursor malformed/expired；
- target 已删除或 occurrence identity 陈旧；
- Anniversary reminder 已过本次有效期；
- 聚合 membership/attempt 冲突；
- 时区非法；
- Reminder 幂等冲突；
- JSON workflow recovery/commit 失败；
- Scheduler 已保存但调度待恢复的稳定平台错误。

### 8.4 兼容与版本

- [ ] 形成 Wire Contract 和 Local Storage 两个独立兼容矩阵。
- [ ] 新字段对 Event/普通 Reminder 使用显式 null/缺失兼容策略；Anniversary 分支必须严格必填。
- [ ] 评估并实施 JSON Storage `v2 → v3` 连续迁移；不得让新字段以“解析失败给默认值”进入旧记录。
- [ ] 迁移保留现有 Event、Reminder、Notification、Anniversary、软删除和审计字段。
- [ ] 现有 Anniversary 不自动生成 Reminder；新配置集合为空。
- [ ] 旧 Reminder/Notification 的 `fulfillment_delivery_id/covered_reminder_ids` 按兼容规则为空。
- [ ] 回滚到不识别新 Anniversary Reminder 的旧 App 属于不安全降级，必须在发布说明和测试矩阵中明确。

## 9. C++ Core 实施清单

### 9.1 Domain

- [ ] 新增 `AnniversaryOccurrence`/projection value，保持 date-only。
- [ ] 实现有界年度展开、历史窗口、原始年份下界和 2 月 29 日规则复用。
- [ ] 实现 `years_elapsed` 并拒绝负值 occurrence。
- [ ] 定义 Anniversary reminder template/chain 强类型，不使用自由 JSON object。
- [ ] 实现当地日期减天数、当地时间解析、DST gap/fold 和 UTC 物化。
- [ ] 实现补发有效期 `[remind_at, occurrence 次日 00:00)`。
- [ ] 实现按 `(anniversary_id, occurrence_key)` 聚合逾期 Reminder。
- [ ] 实现所有 covered Reminder 由一个 delivery 履约的 `sent` 不变量。
- [ ] 实现一次性/年度 successor 规则和最多 5 条配置约束。

### 9.2 Application Workflow

- [ ] 扩展 CreateAnniversaryWorkflow：创建 Anniversary/Recurrence 与首批 Reminder plan。
- [ ] 扩展 UpdateAnniversaryWorkflow：比较旧/新日期、repeat 与模板，保留、取消、恢复或替换确定性链。
- [ ] 扩展 DeleteAnniversaryWorkflow：软删除并终结未来 Reminder。
- [ ] 新增 pause/resume workflow，保留配置并只操作未来任务。
- [ ] 新增 `AnniversaryOccurrenceQueryService` 或在现有 QueryService 中增加窄方法。
- [ ] 扩展 Reminder recovery planner：按 occurrence 分组并冻结 covered membership。
- [ ] 扩展 prepare/finalize：聚合 Notification、所有 covered Reminder 和年度 successors 原子/可恢复提交。
- [ ] 投递前重新读取 Anniversary 当前事实，拒绝已删除、改期、切换重复或 expected `remind_at` 不匹配的旧任务。
- [ ] 时区变化 workflow 重算所有 Anniversary open Reminder，并保持 template/occurrence identity。

### 9.3 Repository 与 JSON Storage

- [ ] 定义窄 Workflow Repository ports，不暴露 Storage Record。
- [ ] 实现 storage-level shared commit/recovery coordinator 或等价安全机制。
- [ ] 扩展 Anniversary/Reminder/Notification JSON codec 严格字段校验。
- [ ] 实现 v2→v3 migration、fixture、失败恢复和重复执行保护。
- [ ] bootstrap 在 Scheduler 初始化前完成所有 journal/migration recovery。
- [ ] 覆盖多个 workflow 共享 `reminders.json` 的串行化和陈旧 after-image 风险。
- [ ] 保持正式目录 `files/local_storage/calendar_core_storage_json` 不变。

### 9.4 Boundary 与 Runtime

- [ ] 增加 list occurrences request decoder/response encoder。
- [ ] 扩展 create/update/detail 的 reminder plan mapping。
- [ ] 扩展 Reminder/Notification/Recovery mapping。
- [ ] 注册新的 C++ Boundary API 和 runtime service dependency。
- [ ] 所有失败继续返回合法 `NativeResult<T>`，不返回空成功或 catch-all 默认值。

## 10. Kotlin / Android 实施清单

### 10.1 Contract 与 JNI

- [ ] 更新 Kotlin Anniversary Contracts，严格校验 local date/time、数组上限、分页和聚合字段。
- [ ] 扩展 `NativeAnniversaryBridge` 与 JNI export，新增 list occurrences 并同步 create/update/detail shape。
- [ ] 更新 Reminder/Notification Kotlin mapping，禁止把 Anniversary date 填入 Event Instant 字段。
- [ ] 更新 Handler method registration 和错误映射。

### 10.2 Scheduler

- [ ] Anniversary 保存成功后触发统一 Reminder reconciliation。
- [ ] notification permission 拒绝时保留任务并返回可展示 capability 状态。
- [ ] exact alarm 不可用时使用允许的近似调度路径，并暴露降级提示。
- [ ] 时区、日期、系统时间、重启、升级、App 前台恢复后重算/对账。
- [ ] 旧 Alarm 使用 expected `remind_at`/identity 被 Native 拒绝后，不展示 Android Notification。

### 10.3 Notification 与点击

- [ ] 正常 Anniversary popup 使用冻结 title/body/payload。
- [ ] 同一 occurrence 多条逾期 Reminder 只调用一次 `NotificationManager.notify`。
- [ ] 聚合通知 tag 使用稳定 delivery ID，重试覆盖同一条。
- [ ] 点击 payload 包含 Anniversary target/occurrence identity。
- [ ] 冷启动、热启动和已删除目标均路由到明确页面状态。
- [ ] 锁屏内容不包含 note。

## 11. Dart / Flutter 实施清单

### 11.1 DTO、Gateway 与 Application

- [ ] 新增 Anniversary reminder template DTO 和严格 mapper。
- [ ] 新增 occurrence request/summary/page DTO。
- [ ] 扩展 Anniversary Gateway create/update/detail。
- [ ] 实现 occurrence cursor 自动拉取，直到完整读取 400 日窗口结果。
- [ ] 不把原始 `Map<String, dynamic>` 暴露给 Controller/UI。
- [ ] 区分“数据已保存但调度待恢复”和“数据保存失败”。

### 11.2 创建/编辑页

- [ ] 增加提醒总开关，默认关闭。
- [ ] 增加当天、提前 1 天、提前 7 天快捷项，默认时间 09:00。
- [ ] 支持自定义 0～365 天和分钟级当地时间。
- [ ] 最多 5 条；重复配置即时提示。
- [ ] 首次开启时请求 notification permission；拒绝后保留设置并显示说明。
- [ ] exact alarm 降级时显示“可能稍有延迟”，不阻止保存。
- [ ] 编辑已有 Anniversary 时正确回填暂停状态和所有模板。

### 11.3 详情页

- [ ] 展示提醒开关、活动提醒数量和每条配置摘要。
- [ ] 支持快速暂停/恢复。
- [ ] 完整修改仍进入创建/编辑页，避免两个页面重复实现编辑器。
- [ ] 展示 Scheduler pending recovery 警告及权限入口。

### 11.4 日历消费者边界

- [ ] 提供可供未来 Calendar Application 使用的 typed occurrence API。
- [ ] 摘要支持标题、周年数、分类样式、小铃铛和提醒数量。
- [ ] “更多详情”通过 Anniversary ID 查询 detail。
- [ ] 本计划不实现周/月/年视觉页面和 Event 聚合。

## 12. 测试矩阵

### 12.1 Contract

- [ ] 所有 JSON/YAML 可解析，`$id/$ref` 唯一且闭合。
- [ ] Create/Update/Detail/Occurrence/Reminder/Notification/Recovery 正反例 fixture。
- [ ] 未知字段、缺失必填、null/缺失差异、未知枚举、非法版本全部失败。
- [ ] UUIDv5 golden vectors 覆盖 occurrence、template、Reminder、aggregate delivery。
- [ ] MethodChannel 每个公开能力有明确 JNI/Workflow 路径。

### 12.2 C++ Domain/Application

- [ ] 一次性和年度正常路径。
- [ ] 1 条与 5 条 Reminder，6 条拒绝，重复模板拒绝。
- [ ] advance 0、1、7、365 天与非法负数/超范围。
- [ ] 当地 00:00、09:00、23:59。
- [ ] DST gap/fold、跨日、跨月、跨年和时区变化。
- [ ] 2 月 29 日在闰年/非闰年 occurrence 与 Reminder。
- [ ] 创建时本次提醒已过：一次性不建、年度跳下一年。
- [ ] 补发于提前提醒日、纪念日前一天、纪念日当天和次日边界。
- [ ] 同 occurrence 多 Reminder 合并、不同 Anniversary 分开。
- [ ] 聚合 sent 后所有 covered Reminder sent、共享 fulfillment delivery、分别生成 successor。
- [ ] retryable/permanent failure、过期与 successor。
- [ ] 编辑标题、日期、repeat、模板；暂停、恢复、删除。
- [ ] 陈旧 Alarm、重复 prepare/finalize、重复 recovery/reconciliation。
- [ ] occurrence 历史窗口、原始年份下界、400 天边界、cursor 全量。

### 12.3 Storage/Migration

- [ ] 所有 v2 fixture 到 v3，字段和历史数据无损。
- [ ] migration 重复执行、失败恢复、损坏记录拒绝。
- [ ] journal failure hooks 覆盖每个 Store 写入边界。
- [ ] 进程在 Anniversary commit 后、Scheduler 前退出，重启后数据完整且最终调度。
- [ ] prepared foreign workflow 未恢复时禁止另一个 `reminders.json` writer 覆盖。
- [ ] 旧 Event/Reminder/Notification 与 Anniversary tombstone 回归。

### 12.4 Kotlin/Android

- [ ] Kotlin Contract/JNI mapping 正反例与数值类型兼容。
- [ ] notification permission 允许、拒绝、永久拒绝和后续授权。
- [ ] exact alarm allow/deny 与近似降级。
- [ ] 一条正常 popup、一个 occurrence 聚合 popup、多个 Anniversary 分组 popup。
- [ ] Android notification tag 幂等覆盖。
- [ ] 冷/热启动点击、重复点击、目标删除。
- [ ] 重启、升级、时区/日期/系统时间变化和 WorkManager recovery。

### 12.5 Dart/Flutter

- [ ] Form Controller 默认关闭、快捷项、自定义、上限、重复校验。
- [ ] 权限拒绝仍保存、Scheduler failure 显示部分成功。
- [ ] 详情暂停/恢复和编辑回填。
- [ ] occurrence 自动分页不漏项、不重复、稳定排序。
- [ ] 摘要小铃铛、提醒数量、周年数和更多详情导航。
- [ ] malformed NativeResult/unknown enum 不转成空成功。

### 12.6 真机验收

- [ ] 真实 Flutter → Kotlin → JNI → C++ → JSON → Alarm → Notification → 点击详情。
- [ ] 至少一次正常到点 popup。
- [ ] 设备关闭/进程终止后，在纪念日前恢复并聚合补发。
- [ ] 纪念日当天恢复仍补发，次日恢复不补发。
- [ ] notification permission 拒绝后保存，授权后自动调度。
- [ ] exact alarm 拒绝时观察近似调度和用户提示。
- [ ] 时区切换后 UTC `remind_at` 改变、当地意图不变、旧 Alarm 不展示。
- [ ] 同 occurrence 多条 Reminder 只出现一个系统通知。
- [ ] 删除或改期后旧 Alarm 到点不展示。
- [ ] 年度 successor 在真实 Store 中存在且 identity 正确。

## 13. 验证命令与门禁

实现后至少执行：

```text
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

Flutter/Android：

```text
flutter test
flutter analyze
flutter build apk --debug
```

并执行：

- Android JVM 定向与全量单测；
- `lintDebug`；
- Android Debug APK 和适用的 androidTest APK 构建；
- `test_environment/flutter_native_smoke` 的 Flutter test/analyze/build；
- APK Native `.so`/JNI symbol 检查；
- 物理设备验收。

任何未执行检查必须在完成报告中标记为“未验证”，不得根据代码审查推断通过。

## 14. 实施顺序与阶段门禁

### Phase 0：领域与 Contract 冻结（唯一前置阶段）

- 按 `纪念日-03-contracts设计.md` 完成第 8 节全部领域文档、ADR、Schema、枚举、错误码、identity vectors、fixture 和能力图。
- 明确 Wire Contract/Storage 两个版本域与 v2→目标 Storage 版本 migration。
- 冻结聚合 `sent`、covered membership、补发日末边界和 Scheduler partial-success response。
- 交付冻结提交 SHA、能力矩阵、兼容矩阵和三层共同 fixture。

门禁：Schema/fixture/identity 校验通过；三个实现工作流必须以同一个冻结提交为基线，不得并行发明跨层字段。

### Parallel F：Flutter 工作流

- 按 `纪念日-04-Flutter开发.md` 完成 DTO/Gateway/Application、创建编辑表单、详情暂停恢复、权限反馈、点击路由和 occurrence 自动分页。
- 使用 typed Fake 完成单层测试，但生产 composition 保持真实 MethodChannel Gateway。

并行交付门禁：Dart/unit/widget 测试和 analyze 通过；生产入口无本功能 Fake/占位成功；真实 APK 链路准确标记为待集成。

### Parallel K：Kotlin / Android 工作流

- 按 `纪念日-05-Kotlin开发.md` 完成 Handler、Kotlin Contract、Native Bridge 声明、post-commit reconciliation、exact/inexact 降级、聚合通知与点击。
- 使用 Fake Native Bridge 和 fake platform service 完成 JVM/Android 单层测试，不等待 C++ 分支。

并行交付门禁：JVM、lint 和可独立执行的 Android 测试通过；聚合只 post 一个 Android notification；真实 JNI symbol/设备项准确交接。

### Parallel C：C++ Core / Storage 工作流

- 按 `纪念日-06-CPP开发.md` 完成 date-only occurrence、identity、时间物化、Reminder chain、生命周期/恢复/投递 workflow、窄 Repository、JSON migration/recovery、Boundary 与 runtime。
- 使用内存 Repository、固定 Clock/TZDB 和 Contract fixture 独立开发。

并行交付门禁：正常、边界、非法输入、聚合、时区、2 月 29 日、migration 与 crash replay 测试通过；构建后 `excellent_calendar_check` 通过。

### Phase I：最终合并、真实接线与 Fake 清理

三个并行工作流完成后，集成人按“冻结 Contract → C++ → Kotlin/JNI → Flutter”顺序合并，顺序只用于降低合并风险，不代表开发串行：

1. 确认三个分支基于同一 Contract SHA，拒绝任何未记录的协议漂移。
2. 先合并 C++ Domain/Storage/Boundary，运行 migration 与 `excellent_calendar_check`。
3. 合并 Kotlin，实现/核对薄 JNI thunk、`.so` symbol、Handler、Scheduler、Notification 和系统事件接线。
4. 合并 Flutter DTO/Gateway/Application/UI，核对 MethodChannel payload 和真实生产 composition。
5. 搜索并审计 `main.dart`、`MainActivity`、Native factory、manifest、runtime factory：本功能不得存在 Fake Gateway、Fake Native Bridge、内存 Store、占位成功或 debug-only 生产接线。
6. 测试 Fake 保留在 test/dev 边界；范围外的 `FakeAnniversaryShareGateway` 不在本任务内清理。
7. 合并冲突必须回到所属层修正；若需改变字段/错误/身份，重新走 Contract 变更与三层影响审查，不得在 JNI/adapter 中兼容绕过。

门禁：真实 DTO ↔ Handler ↔ JNI ↔ C++ ↔ JSON round-trip 通过，正式 APK 可构建，Fake/占位不在生产可达路径。

### Phase V：跨层 smoke 与真机验收

- 执行完整数据链、migration、调度、补发、权限、exact/inexact 降级、时区、旧 Alarm、点击与历史 occurrence 查询验收。
- 保存脱敏 Store、Alarm、Notification 和日志证据。
- 运行第 13 节所有适用构建/测试，并逐项记录未验证内容。

默认门禁：第 17 节核心验收全部通过后才能把新方法标记为 `integrated/active`。本次已具备真实 Store、APK、JNI、正常到点 Alarm/Notification 与 Native 更新链证据；产品负责人于 2026-08-25 明确批准带剩余设备矩阵风险发布，因此未覆盖项保留为“未验证、非阻断”，不得改写为已经通过。

## 15. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 多个 JSON workflow 共享 `reminders.json` | prepared journal 重放覆盖新数据 | 统一 storage-level commit/recovery coordinator、目录锁、bootstrap 恢复门禁 |
| 聚合后所有 Reminder 标记 sent | 审计可能误以为展示多条通知 | 单一聚合 Notification + covered IDs + shared fulfillment delivery |
| 设备时区改变 | 旧 Alarm 在错误当地时间触发 | 保存当地意图、重算 UTC、expected remind_at/CAS、旧任务展示前拒绝 |
| 权限或 ROM 后台限制 | Reminder 长期 pending 或延迟 | capability UI、近似降级、前台/启动/系统事件 reconciliation、真机矩阵 |
| 编辑与投递并发 | 旧日期通知误发 | prepare 时重新验证 target/occurrence/remind_at，数据提交先于 Scheduler |
| 400 日无总条数上限 | 单次 MethodChannel payload 过大 | 稳定 cursor、内部批次、Flutter 自动拉全、性能压力测试 |
| JSON→SQLite 即将发生 | 临时实现被存储细节绑死 | Application 依赖窄 Repository，JSON journal 只在 adapter，SQLite 用同一 port |
| Contract v2 已有 Event Reminder | 新字段破坏旧 reader/writer | target-specific schema、显式 v2→v3 migration、全 reader/writer round-trip |

## 16. 明确范围外

- 完整 Calendar 周/月/年页面及视觉实现；
- Event、Anniversary、Habit 的统一 `calendar.list_items`；
- Anniversary occurrence 完成、跳过、取消、重新打开；
- 修改前历史 revision 或“仅修改未来”；
- birthday/holiday 等持久化 kind 和年龄专属文案；
- 农历、节日模板和系统预设；
- ring、wechat、多渠道部分成功；
- 独立 Reminder 管理页和 Notification 历史页；
- 云同步、Backend reminder、账号能力；
- 本任务内完成 SQLite 主存储迁移。

## 17. 完成定义

只有同时满足以下条件才能报告“已完成且验证通过”：

- [ ] 已确认产品规则全部体现在领域文档、Contract 和实现中。
- [ ] Anniversary Reminder/Occurrence 所有相关层同步，无 Fake 或占位成功。
- [ ] JSON v2→v3 migration 和崩溃恢复测试通过，无历史数据静默丢失。
- [ ] 创建、更新、暂停、恢复、删除与 Reminder 保持可恢复一致性。
- [ ] Scheduler failure 正确返回“已保存、调度待恢复”，并可自动对账。
- [ ] 聚合补发只展示一个真实 Notification，covered Reminder 与 successor 审计闭环。
- [ ] occurrence 400 日窗口和自动分页完整、不重不漏。
- [ ] Contract、C++、Kotlin、Dart/Flutter、Android build 和相关回归实际通过。
- [ ] 真机验证正常到点、补发、权限、时区、旧 Alarm 拒绝和点击详情。
- [ ] `git diff`/`git status` 无无关改动，用户既有修改得到保护。
- [ ] `docs/status/current.md`、`docs/status/roadmap.md`、相关 issue/plan 状态与真实结果同步。
- [ ] `docs/log.md` 追加实际开发与验证记录。

未执行项目仍必须明确标记为未验证。本次 Contract 激活属于产品负责人批准的发布风险例外，不代表第 13 节和第 17 节中所有设备组合均已通过；后续由负责人继续维护剩余矩阵。

## 18. 发布决定（2026-08-25）

- P1 正常到点 Alarm 被误归类为 `anniversary_catch_up` 的问题已修复：Alarm 冻结 `planned_at` 继续进入 V2 Coordinator，匹配时刻的 C++ 权威 Reminder 先按普通 `kind=reminder` 投递，之后才恢复更早逾期任务；可重试普通失败不会在同次 Alarm 中落入 Recovery。
- 正常 Anniversary Notification 正文固定为当天“今天是“{title}””或提前“距离“{title}”还有 N 天”；realme RMX3687 / Android 13 已验证进程退出后系统到点唤醒、正文、持久化类型、sent、successor、delivery identity、点击与去重。
- Flutter 设备验收已验证旧 create token 稳定返回 `ANNIVERSARY_UPDATE_CONFLICT` 且 detail/list 零写入，随后使用最新 `disabled.anniversary.updatedAt` 正常更新。
- Contract 162 schemas / 55 fixtures / 16 identity vectors、C++ 7/7、Flutter 240/240、Android JVM 145 tests（0 failure、0 error、1 skip）、Lint 0 error / 37 warning、Debug/androidTest/Release APK 与 Native smoke 均通过。
- 经产品负责人明确批准，八项 Anniversary MethodChannel/native call 与 identity capability 统一切换为 `integrated + active`，解除 `OPEN-ANN-001`。API 24–25、更多 ROM、聚合补发、权限、时区/DST、旧 Alarm、重启与长离线矩阵仍是未验证的已接受风险。
