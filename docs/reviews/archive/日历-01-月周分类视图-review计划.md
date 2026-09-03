# 日历月/周分类视图与三类数据聚合 — 独立 Review 计划

Status: Archived / Findings Addressed / Product Release Exception / Open Debt Tracked

建立日期：2026-08-31

对应主计划：`docs/plan/completed/日历-01-月周分类视图与三类数据聚合开发计划.md`

## 0. 当前结论

2026-09-02 最终独立复审确认历次代码 Finding 均已返修，未发现七项已知发布债务以外的新硬缺陷。正式签名/商店上传仍属于分发 P1，设备与恢复矩阵仍未执行，因此本 Review 不倒写为“所有门禁通过”；产品负责人已明确接受这些项目为 `OPEN-CAL-001` 发布后债务并批准发布例外，`calendar.*` 当前为 `integrated + active`。

- Calendar Contract、C++/SQLite、Kotlin/JNI、Dart/Flutter 和 production composition 已完成白盒闭包复读。
- 审查期发现的 Flutter Habit 数量关系、civil-date DST、卡片区手势范围、inactive 跨午夜/时区复位及状态文档漂移均已返修并复核。
- 正式签名/商店上传、完整 Release UI、TalkBack、200% 字体/减少动画、强杀恢复、时区/DST 和升级回滚/签名密钥恢复尚未完成，统一见 `OPEN-CAL-001`。
- `calendar.*` 的 `integrated + active` 来自产品负责人对残余风险的显式接受，不表示这些场景已经通过。
- 工作树内并行 Search 与用户 Habit 计划归档修改不属于 Calendar Finding，均已保留且未被整理或回滚。

## 1. 审查目标与最终判定对象

最终判定对象不是单独的月历页面，而是以下完整生产链：

```text
CalendarPage / widgets
  → CalendarController / immutable state / cache
  → CalendarGateway / typed DTO
  → MethodChannelCalendarAdapter
  → CalendarMethodHandler
  → JniCalendarBridge
  → C++ CalendarViewQueryService / Boundary
  → Event + Recurrence + EventOccurrenceState
     + Habit + HabitCheckIn
     + Anniversary + AnniversaryRecurrence
     + Reminder summary
  → Calendar Core SQLite read transaction
```

Review 必须证明：

1. 冻结的周/月导航、折叠、刷新、圆点、三分组、分页、创建和回跳行为真实可用。
2. Calendar View 只读取并组合三个领域的当前事实，不建立第二套可写事实或复制领域状态机。
3. `date`、UTC Instant、IANA timezone、半开区间、recurrence 和 occurrence identity 在所有层含义一致。
4. 范围摘要、选中日三分组、排序、分页和缓存具有明确的一致性模型，不出现混合快照、漏项、重复或旧响应覆盖。
5. production APK 真实经过 MethodChannel/JNI/C++/SQLite；Fake、seed、preview 只存在于测试或显式开发入口。
6. 42 天范围和高密度数据不会形成 N+1、主线程长查询、无界 recurrence 展开或无界 Flutter 内存增长。
7. 小屏、大字体、深浅色、Semantics、减少动画、进程恢复和真实手势达到发布门槛。
8. Contract、C++、Kotlin/JNI、Flutter、APK、真实 SQLite 和必要设备验证都有可复核证据。

## 2. 判定基线与资料优先级

### 2.1 项目内基线

正式 Review 开始时按以下顺序冻结 oracle：

1. 用户最终确认的需求与主计划冻结验收标准；
2. Calendar 机器 Schema、`method_channels.yaml`、`native_calls.yaml`、错误码、枚举和 fixture；
3. `docs/domains/calendar_view.md` 及 Event、Recurrence、EventOccurrenceState、Habit、HabitCheckIn、Anniversary 领域不变量；
4. Accepted ADR，特别是领域专属 Recurrence 与 Occurrence 状态边界；
5. 当时有效的分层计划、架构文档、状态文档和开放问题；
6. 公开接口、实际 production composition 和最终工作树实现；
7. 既有测试只用于理解 harness，不作为自身正确性的唯一证明。

Calendar Contract 尚未冻结时，下列内容必须在 Track 1 解决，不能由实现自行猜测：

- `range_summary` 与三个 `list_day_items` 调用之间的 snapshot/generation 一致性；
- pull-to-refresh 四个请求的原子替换与部分失败语义；
- 三个 section 的完整排序 tuple、null 排序和 cursor 编码绑定项；
- 跨日 Event 在后续日期的展示字段及用于排序的“当地开始时间”定义；
- snapshot expired、cursor mismatch、malformed data 的精确错误码与恢复动作；
- performance 数据集、参考设备和定量延迟/内存门槛。

这些语义未冻结时可以继续做不依赖它们的 UI 原型，但受影响的 production Contract、分页和发布结论必须暂停。

### 2.2 外部工程经验只作风险依据

外部标准不能覆盖本项目 Contract，但用于解释为什么这些地方必须重点审查：

- [RFC 5545 iCalendar](https://www.rfc-editor.org/rfc/rfc5545.html) 将开始视为包含、结束视为不包含，并区分 DATE 与 DATE-TIME；重复实例通常需要按当地时间和时区保持墙上时间语义。这支持本项目的 date/datetime 分离与半开区间门禁。
- [Google Calendar recurring events](https://developers.google.com/workspace/calendar/api/guides/recurringevents) 区分系列与单次 instance，并保留原始开始时间作为实例身份的一部分。这与本项目禁止“只带 event id 打开重复条目”和禁止 occurrence 状态污染系列一致。
- [Google Calendar incremental sync](https://developers.google.com/workspace/calendar/api/guides/sync) 要求分页期间保持同一查询条件，并在 token 失效后重新建立完整快照。Calendar 虽是本地查询，但 cursor query binding、snapshot expired 和禁止静默从头续页遵循相同工程教训。
- [SQLite isolation](https://www.sqlite.org/isolation.html) 说明显式 read transaction 可维持不变快照；如果分散查询或在同一连接遍历期间交错写入，结果可能出现重复或已删除行。这是三领域组合必须使用清晰 read snapshot 的依据。
- [SQLite query planner](https://www.sqlite.org/queryplanner.html) 说明索引需要同时服务筛选和稳定排序，且 full scan 在数据量增大时会迅速恶化。新增索引必须由查询计划和压力证据驱动，不能凭感觉迁移 Storage。
- [Flutter gesture arena](https://api.flutter.dev/flutter/gestures/GestureArenaManager-class.html) 会在竞争 recognizer 中选出单一胜者；月历水平翻页、列表纵向滚动、下拉展开和下拉刷新不能靠多个互不知情的 GestureDetector 碰运气。
- [Flutter accessibility guidance](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling) 要求在小屏和最大字体下验证布局，并给出可测试的对比度与触控目标建议。日期状态不能只靠三种颜色表达。
- [Android UI state guidance](https://developer.android.com/topic/architecture/ui-layer/stateholders) 强调 UI state holder、配置变化和进程死亡后的可重建性。本项目仍以自己的产品规则为准：只持久化周/月偏好，冷启动选中今天，Tab 切换保留当前会话状态。

## 3. 正式 Review 启动条件

以下条件同时满足后才冻结审查边界：

- [ ] 主计划和 Calendar Contract/数据子计划已确认并冻结。
- [ ] `calendar.range_summary`、`calendar.list_day_items` 及 internal calls 的 capability、Schema、错误、排序、cursor 和 snapshot 语义完整。
- [ ] C++/SQLite、Kotlin/JNI、Dart/Flutter 分层实现已完成开发者自检。
- [ ] production composition 已接真实 MethodChannel/JNI/C++/SQLite，运行时 Fake/seed 已移除。
- [ ] Habit 依赖能力和 Storage 状态已达到主计划允许 Calendar 正式消费的门槛。
- [ ] 所有 Calendar 相关 staged、unstaged、untracked、rename 和 delete 文件相对明确 baseline 可枚举。
- [ ] 开发者提供实际执行的 Contract、构建、测试、APK、JNI 和设备证据；未执行项明确标记。
- [ ] 审查者先从需求、Contract、ADR 和公开接口冻结独立 oracle，再阅读实现主体。

如果实现分支长期较大，开发期间每个 Track 完成时只做“Review readiness 自检”：确认 Contract 没漂移、证据可重放、未把 Fake 接进 production。它不产生正式通过结论。

## 4. 发布阻断红线

出现以下任一情况，最终结论至少为 `CHANGES REQUIRED`：

1. Event、Habit、Anniversary 任一类型仍从 Fake、seed、preview 或内存替代源进入 production 页面。
2. Calendar View 新增可写表、缓存表或状态字段，成为三领域之外的第二事实源，且没有独立 ADR、失效策略和迁移依据。
3. Flutter 或 Kotlin 重新展开 recurrence、计算 Habit daily status、重排领域结果或自行改变 completed/skipped/cancelled 规则。
4. date-only 被转成 UTC 午夜；timed Event 用当地 date 比较；timezone 非法时静默回落 UTC、固定 offset 或设备默认值。
5. 重复条目丢失 `occurrence_key`/revision/计划锚点，只以 `event_id` 打开系列，或单次状态污染整个 Event。
6. range summary 由三个 section 第一页推导，导致分页后的日期圆点漏判。
7. cursor 未绑定日期、时区、section、完整排序条件和 snapshot generation，数据变化后继续追加造成漏项或重复。
8. 快速换日期、换范围、刷新或返回详情时，旧异步响应可覆盖当前选择。
9. 三领域组合查询形成按天×实体、按 occurrence×Reminder 或按 item 再查详情的 N+1；或在 Android 主线程执行大范围 SQLite/JSON/JNI 工作。
10. malformed payload、未知 enum、非法 NativeResult、JNI null/异常被映射为空成功页面。
11. Calendar capability 在真实三类链、APK 和必要验证之前标为 active/integrated。
12. Contract、C++ build-after-test、Flutter analyze/test、Android unit/lint/APK/JNI smoke 中存在未解释失败。
13. 关键真机手势、时区/跨日、进程死亡或无障碍矩阵未执行，却宣称完整发布通过。
14. Review 或测试清理、覆盖、重置了用户现有工作或真实设备数据。

数据错日、数据漏项/重复、生产 Fake、死循环/卡死、跨层协议伪成功和用户数据破坏默认按 P0/P1 处理，不允许作为“残余风险”放行。

## 5. 正式 Review 执行阶段

### Phase A：冻结范围与独立 oracle

- 收集相对 baseline 的完整 working-tree manifest，包含 staged、unstaged、untracked、rename、delete、生成物、构建文件和测试。
- 建立 `path → layer → expected responsibility → task reason` 清单。
- 从主计划、Contract、领域文档和 ADR 生成规则台账；冲突先记录，不从代码反推需求。
- 在阅读实现主体前冻结本文件第 16 节的独立测试矩阵和 expected 值。
- 记录初始 Git 状态；审查测试只使用隔离临时目录、专用 application id 或独立副本。

### Phase B：按层白盒审查

按依赖顺序进行：

1. Contract、fixture、identity、错误、capability；
2. C++ Boundary、Calendar Query Service、Repository 与 SQLite；
3. Kotlin Contract、Handler、JNI bridge、线程和 runtime owner；
4. Dart DTO、Gateway、Application/Controller、cache；
5. Flutter widgets、手势、导航、主题和 Semantics；
6. production composition、APK、ABI 和三类真实数据链。

每个变更文件归类为 `Required / Supporting / Suspicious / Violating`。跨层本身不是错误，但必须能从 Contract 和调用链解释必要性。

### Phase C：独立验证

- 先运行仓库定义的窄测试和构建，再运行冻结的独立黑盒、契约、并发、性能和设备用例。
- 独立 expected 不调用生产 recurrence、overlap、sort、cursor、date 或 identity helper。
- 失败必须区分：产品缺陷、oracle 缺陷、harness/环境问题、既有失败、无法归因。
- 测试 worktree 与待提交 index 不同时，报告“测试覆盖的是哪个状态”。

### Phase D：Finding、返修与复核

- Findings 按 P0→P3 排序，相同根因合并，不报告纯风格偏好。
- 开发者修复后，只复核受影响闭包和必要回归；不得直接相信“测试已通过”的转述。
- oracle 只有在真相源明确改变时才能修改；为匹配实现而放宽 expected 视为审查失败。
- 阻断项清零、证据完整后才给最终判定并归档 Review。

## 6. Contract 与跨语言边界审查

### 6.1 两个公开能力必须形成可解释闭环

对 `calendar.range_summary` 和 `calendar.list_day_items` 逐项追踪：

```text
method_channels.yaml
→ request/response schema
→ Dart DTO / adapter
→ Kotlin DTO / handler
→ native_calls.yaml
→ JNI symbol / bridge
→ C++ boundary model / endpoint
→ CalendarViewQueryService
→ Repository / SQLite
```

逐方法检查 valid、缺字段、required null、nullable 缺失、额外字段、未知 enum、错误类型、错误版本、NativeResult 互斥条件和异常 envelope。

### 6.2 类型和语义必须逐字段一致

- Contract payload 使用 `snake_case`；Dart/Kotlin/C++ 内部命名转换不得改变语义。
- `date` 严格为 `YYYY-MM-DD` civil date；UTC Instant 必须带 UTC/offset；timezone 必须为有效 IANA ID。
- section 是冻结枚举，不接受大小写猜测、未知值默认 event 或空分组。
- `has_more=false` 时 `next_cursor=null`；`has_more=true` 时 cursor 非空且必须产生正进展。
- 缺失、null、空字符串、空数组和默认值分别处理，不能用默认对象掩盖损坏。
- item variant 使用清晰的 discriminated union/条件 Schema；不得设计一个所有字段 nullable 的万能 CalendarItem。
- 本地化文案不进入 Contract；但 UI 所需的原始类型化字段必须足够，不能逼 Flutter 重新查询或猜状态。

### 6.3 Snapshot 与刷新语义必须先冻结

单次 C++ 查询必须来自一个一致 read snapshot。由于范围摘要和三个 section 是四次公开调用，Contract 必须明确选择并验证以下之一：

1. 四个响应携带可比较的 `snapshot_generation`，Controller 只原子接纳同一 generation；或
2. 明确允许跨调用最终一致，并规定刷新期间圆点/分组短暂不一致的 UI 处理；或
3. 调整公开能力，使一个刷新请求在同一 read transaction 中返回原子首屏快照。

不得在文档里承诺“原子刷新”，实现却把四个任意时刻完成的结果逐个覆盖页面。按当前主计划，pull-to-refresh 应在四个结果均成功时原子替换；任一失败保留最近成功快照并显示可重试状态。正式 Contract 若选择其他语义，必须先回到主计划确认。

## 7. 时间、区间、Recurrence 与 Occurrence 审查

### 7.1 必须统一使用的区间公式

定时 Event 与某当地自然日的窗口重叠，当且仅当：

```text
event_start < day_end_instant && event_end > day_start_instant
```

全天 Event 覆盖某日期，当且仅当：

```text
start_date <= selected_date && selected_date < end_date
```

必须覆盖：开始恰好等于日末、结束恰好等于日初、跨午夜、跨月、跨年、多日、DST 23/25 小时日和零长度非法输入。结束在 00:00 的 Event 不能误显示到下一日。

### 7.2 最容易漏掉的 recurrence 情形

- 查询窗口内开始的 occurrence 不等于与窗口重叠的 occurrence。一个在窗口前开始、但持续到窗口内的长 occurrence 也必须出现。
- 月末 `31` 号规则遇短月只能截断当次候选，不能把后续锚点永久漂移成 `30/28`。
- Weekly 使用 ISO Monday=1；不能混用 Dart/Java/C++ 的 Sunday-based weekday。
- DST gap 前移、fold 取较早 Instant 必须与现有领域规则一致；不能依赖设备默认库的偶然选择。
- recurrence 展开有界，不能预生成无限未来，也不能为 42 天视图按“每天×全部系列”暴力重算。
- Event series identity、recurrence revision、occurrence key 和原始计划锚点必须同时保持；修改系列后历史 revision 状态不得套到新 revision。
- 单次 completed/skipped/cancelled 只影响对应 occurrence；整个 series completed/cancelled/archived 的过滤另行处理。

### 7.3 时区和系统日期变化

- 相同 UTC Event 在不同时区可能落到不同当地日；相同 date-only Anniversary/Habit 不应因 UTC 转换漂移。
- 设备 timezone 变化后，旧 range/day cache、cursor 和“today”全部失效；旧请求返回必须被 generation 拒绝。
- 当地午夜跨日后，today、Habit absent/missed/upcoming、日期圆环和默认冷启动选中日更新。
- 时区无效、TZDB 不支持或系统时间异常必须显式失败；不得静默使用 UTC 或上次值伪造成功。

## 8. 三类数据投影审查

### 8.1 Event / occurrence

- 普通 Event 与重复 occurrence 使用同一“非空当地日重叠”规则。
- completed 仍显示并排在组底，但不产生 Event 圆点；skipped 灰显并产生圆点；cancelled 不显示。
- 全天优先、状态 bucket、当地时间、标题、稳定 ID 的总排序在 C++ 定义，并由 cursor 使用完全相同的比较器。
- 多个条目拥有相同标题/时间时仍有稳定唯一 tie-breaker；不得依赖 SQL rowid、hash/map 迭代顺序或 locale collation 的未冻结行为。
- 跨日首日/后续日展示原始字段足以让 Flutter显示“开始时间/进行中/结束时间”，但 UI 不重新判断 overlap。
- `has_active_reminder` 来自 Reminder 真相的同快照投影，不能逐 item 无锁查询或从 Android Alarm 推断。
- 点击重复项携带 occurrence identity 到正确详情；点击非重复项不得伪造 occurrence。

### 8.2 Habit daily status

- 只返回 challenge 有效区间内日期；区间采用已冻结的当地日期语义。
- `done` 条目继续显示但移除圆点；`partial/absent/upcoming/missed/skipped` 继续显示圆点。
- absent、missed、upcoming 是查询投影，不能因 Calendar 需要而持久化伪 CheckIn。
- tombstone CheckIn 不作为活动事实；clear 后今天变 absent、过去变 missed。
- 数量值保持 `_hundredths` 精确整数和 target snapshot，不经过 double 截断。
- 状态 bucket、Reminder local time、created_at、stable id 的完整排序和 null placement 由 C++/Contract 冻结。
- Flutter 不根据当前日期、CheckIn 或页面上已有数据重算 daily status、生命周期、完成量或排序。

### 8.3 Anniversary occurrence

- 一次性只在原始 date 出现；年度 occurrence 从 source year 起展开，不混入“未来 7 天”倒计时列表。
- 2 月 29 日在非闰年按现有领域规则落当年 2 月最后一天；覆盖 1900、2000、2100。
- occurrence 是当地 date，没有 UTC `occurrence_start_at`、Event revision 或 completed/skipped 状态。
- occurrence key 继续由 C++ 根据 `anniversary_id + occurrence_date` 生成；title、note、importance 不参与 identity。
- importance、title、stable id 的排序含 null/枚举顺序必须冻结；Flutter 不按本地化文本重新排序。
- `has_active_reminder` 表达配置事实，不从当前 open Alarm 数量推断。

### 8.4 Range summary 圆点守恒

对每个请求日期必须恰好返回一项、升序、无缺口、无范围外日期。至少验证以下守恒：

- Event 点等于该日存在至少一个“应显示且非 completed”的 Event/occurrence。
- Habit 点等于该日存在至少一个“应显示且非 done”的 Habit day item。
- Anniversary 点等于该日存在至少一个 occurrence。
- summary 结果不依赖 `page_size=20` 或前三组是否加载完成。
- 同一冻结 snapshot 下，圆点布尔与完整分页拉完后的条目集合一致。

## 9. Cursor、排序、分页与缓存审查

### 9.1 Cursor 不变量

- cursor opaque 但可严格验证，不泄漏不稳定内存地址或 SQL rowid 偶然值。
- cursor 绑定 timezone、date、section、page size/排序版本、最后完整排序键和 snapshot generation。
- 用 Event cursor 请求 Habit、换日期、换时区或改 page size 必须返回 query mismatch，而不是空页或从头开始。
- snapshot 被 mutation 改变时返回 expired；Controller 丢弃旧页并刷新第一页，不能把新第一页追加到旧列表。
- 非终页 cursor 每次严格前进；重复 cursor、倒退 cursor、空页且 `has_more=true`、重复 identity 都触发保护，不进入无限循环。

### 9.2 分页边界矩阵

每个 section 独立覆盖 `0/1/19/20/21/40/41/100/101+` 条：

- 第一页最多 20，terminal page 规则正确；
- 相同排序主键的大量并列项跨页无漏项、重复或顺序抖动；
- 快速重复点击“加载更多”最多一个在途请求；
- Event 正在翻页时切到另一日，旧页不追加；
- Event 页失败不破坏 Habit/Anniversary 页状态；刷新成功后旧 cursor 全失效；
- UI 去重保护不能掩盖 Native 重复；重复 identity 必须可诊断并在独立测试中失败。

### 9.3 Cache 与异步竞态

- range key 为 `timezone + range_start + range_end`；day key 为 `timezone + date + section`。
- generation 至少在选中日、可见范围、timezone、刷新、详情修改、新建成功和当地跨日时正确推进或使关联 key 失效。
- 缓存命中可先显示旧内容，但后台失败只能保留明确标识的最近成功内容，不能显示“刷新成功”。
- 四个首次/刷新请求任意顺序完成时，只能产生符合当前 generation 的状态。
- dispose、Tab 切换、路由返回和动画中断后，future/callback 不更新已销毁对象。
- 从详情返回 `changed=false` 不重复查询；`changed=true` 只失效相关范围/日期，但不能遗漏跨日或 recurrence 修改造成的其他可见日期变化。
- 新建/编辑改变跨日范围或 recurrence 时，失效范围不能只包含当前选中日；应使用明确的变更结果或保守刷新当前 visible range。

## 10. C++ Query Service 与 SQLite 审查

### 10.1 架构与事务

- CalendarViewQueryService 只负责组合查询，不承担 Flutter 展示状态或写入业务事实。
- Repository ports 按查询意图保持窄接口；不向 Application 暴露通用 SQL、SQLite handle 或万能 CalendarTransaction。
- 单次 range/day 查询在明确 read transaction/snapshot 中读取三领域和 Reminder 投影。
- 软删除、悬空弱引用、malformed row、未知 Storage 版本不得被静默跳过成“空日历”。
- 默认不新增表、writer 或 Storage 版本。若新增索引，必须有 `EXPLAIN QUERY PLAN`、等价结果、迁移/旧版打开策略和回归证据。

### 10.2 性能与资源

必须提供：

- 固定数据集和固定 clock/timezone 下的 query count、latency、峰值 payload/内存记录；
- 42 天 range summary、三组 20/100 条、100+ 分页、跨日和高密度 recurrence 压测；
- query plan 证明关键筛选/排序不依赖意外 full scan 或 per-item secondary query；
- 数据量增长时 query 数基本固定，不能随 item 数线性增加额外 Repository/JNI 往返；
- recurrence 展开按系列与实际 occurrence 有界增长，不按 42 天逐日全表扫描；
- Kotlin/JNI/JSON 编解码和 Flutter isolate 不接收无界全量对象；
- timeout/cancel/error 后 statement、transaction、cursor/session 和 JNI local reference 全部释放。

主计划目前没有冻结定量 latency、帧预算、heap 和数据库规模门槛。Track 2 开发前必须补充参考设备、small/typical/stress 数据集及 P50/P95/峰值门槛；否则最终 Review 只能判定“功能正确但性能发布门槛未验证”。

### 10.3 C++ 常见实现陷阱

- 用 `BETWEEN` 或闭区间导致日末/分页边界重复。
- 用 `duration / 24h` 计算自然日或 42 天，DST 时少/多一天。
- 只按 occurrence start 落入窗口筛选，漏掉从窗口外跨入的长事件。
- 用三个独立 Store 查询后在没有 snapshot 的情况下拼装混合事实。
- 用 `unordered_map`/set 迭代顺序作为稳定排序或 cursor 顺序。
- 对每个 Event 再查 occurrence/Reminder，形成隐蔽 N+1。
- malformed row 被 catch 后跳过，用户看到错误的“当天为空”。
- cursor 解码整数溢出、Base64/JSON 任意大输入导致 CPU/内存放大。

## 11. Kotlin、JNI 与 MethodChannel 审查

- Handler 只做严格 parsing、线程切换和 `NativeResult` 透传，不计算 overlap、排序、Habit status 或本地化文案。
- 两个公开方法与 internal call 的 required/null/enum/integer/string/array 形状逐字段对照。
- `JSONObject` 的整数类型、Boolean、null、Unicode、超长 cursor 和错误 envelope 不丢字段、不窄化。
- JNI symbol、签名、参数顺序、返回 ownership、UTF-8/UTF-16、exception/null 和 runtime-not-ready 分支一致。
- 每次 Flutter call 只完成一次 result；异常路径不挂起 future，也不 double callback。
- SQLite/recurrence/大 JSON 工作不在 Android 主线程；回调回到正确线程，Activity 销毁或 engine detach 后安全。
- 复用单一 Calendar Core runtime owner，不因每个 Calendar request 新建 SQLite connection/runtime。
- 不新增权限、Alarm、Notification、Worker 或 Receiver；若 diff 出现这些修改，默认列为 suspicious 并要求任务级依据。
- Debug/release-like APK 的目标 ABI 都包含 Calendar JNI 导出，真实 handshake 与 Contract fixture 一致。

## 12. Dart Application、Flutter 页面与手势审查

### 12.1 typed boundary 与 Controller

- raw `Map<String, dynamic>` 和 `PlatformException` 只停留在 adapter/mapper；Page/Controller 只消费 typed result。
- Controller 维护单向状态流和不可变页面状态，不在 widget `build` 中启动查询或持久化。
- range、三个 section、refresh、load-more 分别有 request identity；mutation 后的旧 response 不能回写。
- 分组状态真实区分 initial/loading/ready/refreshing/error/loadingMore，不用一个全页 boolean 混淆。
- 本地化文案由 Flutter 根据类型化字段生成，但日期重叠、业务状态和排序不得在 Dart 重算。
- 周/月偏好是唯一跨冷启动持久化项；选中日期冷启动回到新的 today。Tab 切换保留会话中的选中日期、折叠和滚动位置。

### 12.2 日期网格与导航

- 星期一为首列；周/月范围、标题和选中日由同一 civil-date 模型驱动。
- 水平周翻页保持同 weekday；月翻页保持同 day-of-month，目标月不足时夹到最后合法日。
- 1→12 月跨年、12→1 月、闰年 2 月、六周月历、相邻月弱化日和年月选择器正确。
- 今天未选中为圆环、选中日为实心；两者重合时只有一个清晰状态。
- 点击相邻月份日期应切换 visible month 并选中，不能先发旧月请求再覆盖新月。

### 12.3 手势状态机

必须把以下竞争建模为一个可测试状态机，而不是堆叠 recognizer：

```text
idle
→ horizontal paging
→ vertical list scroll
→ collapsing month to selected week
→ expanding week to full month
→ pull-to-refresh armed/refreshing
→ animating/cancelled
```

审查重点：

- 方向锁定阈值、防斜滑误判和触点取消；
- 月历上滑与内容列表滚动的 ownership 转移；
- 周视图顶部下拉必须先完全展开月历，只有继续下拉的新阈值才触发刷新；
- 同一次 gesture 不同时触发展开和 refresh；
- 动画中反向手势、快速多次拖动、页面切换和 dispose 不留下半折叠状态；
- 系统减少动画时直接到合法终态，不能把 duration=0 引发 divide-by-zero 或漏 callback；
- 水平翻页与日期点击、纵向滚动、Android back gesture 不互相吞事件；
- Widget 测试驱动真实 drag 序列，真机验证手感和边界，不只调用 Controller 方法。

### 12.4 布局、主题和无障碍

- 360dp、小高度、系统 inset、横竖屏/窗口变化、200% 字体、中文长标题和三组加载更多不溢出。
- FAB 不遮挡最后一条、加载更多或底部导航；滚动到底可访问所有内容。
- 浅/深主题对比度可测试；不要硬编码截图颜色破坏 Appearance。
- 日期 Semantics 同时说明日期、今天/已选中和包含的类型；圆点不能是唯一信息来源。
- 图标按钮有中文 tooltip、可访问标签和足够触控目标；读屏焦点顺序符合标题→日期网格→分组→FAB。
- 文本视觉截断时可访问标签保留完整内容；删除线/弱化不能成为 completed 的唯一语义。
- 时间线和更多按钮只显示冻结的暂不支持提示，不导航到空页面或暗中实现 V1 范围外功能。

## 13. 生产装配、导航与刷新闭环

- `main.dart`/composition root 注入真实 CalendarGateway；测试 Fake 只通过测试依赖注入。
- Native 初始化失败显示真实错误与重试，不自动切换 Fake 或空数据。
- Event、Habit、Anniversary 详情 route 使用正确 target 和 occurrence identity；重复点击只导航一次。
- 详情无变更返回保留 cache；有变更返回刷新可见范围和相关 section，错误不能悄悄显示旧成功。
- 新建 Event/Anniversary 预填选中日；Habit 在历史日回退 today，今天/未来预填选中日。
- 保存成功后保持目标日期；取消/失败不伪造 mutation，也不无条件刷新所有缓存。
- Calendar 页面不得修改 Notification tap 既有 Event/Anniversary/Habit 分流。

## 14. 共享回归边界

Calendar 是只读消费者，但为了聚合可能修改共享查询、DTO、runtime、SQLite 索引和路由。以下变化一旦被触及必须扩大回归：

- Event CRUD/detail/search、普通全天/定时、series 与 occurrence complete/skip/cancel/reopen。
- Event Reminder `has_active_reminder`、popup/ring、prepare/finalize 和 notification tap。
- Anniversary CRUD、2 月 29 日、occurrence cursor、Reminder summary、soft delete 和详情路由。
- Habit list/detail/daily status、CheckIn clear/tombstone、数量精度、Reminder summary 和 lifecycle。
- Category 弱引用和排序；悬空/软删除分类不能使 Calendar item 消失或查询失败，除非 Contract 明确。
- Calendar Core SQLite fresh v4、v5 集成候选、旧 JSON→SQLite migration、runtime bootstrap 和 capability registry。
- Flutter 四 Tab 状态、Theme/Appearance、Event/Habit/Anniversary 原详情页和新建页。
- 共享 Contract validator、错误码、enum、NativeResult、JNI runtime factory 被修改时的全量目标分支。

无关共享模块不得因为“顺手重构”进入 Calendar diff。若确有必要，应单独说明需求、风险和回归闭包。

## 15. 开发中高频错误与提前规范

| 高频错误 | 常见代码症状 | 用户后果 | Review 判定 |
| --- | --- | --- | --- |
| date 当 UTC datetime | `DateTime.parse(date).toUtc()` | Habit/Anniversary 前后错一天 | P1 时间语义错误 |
| 结束边界写成闭区间 | `end >= dayStart` 或 SQL `BETWEEN` | 午夜结束的 Event 多显示一天 | P1 漏/重复项 |
| occurrence 只按 start 筛选 | `start in [rangeStart, rangeEnd)` | 跨入窗口的长事件漏掉 | P1 数据不完整 |
| 把三种 Recurrence 合并 | 通用 nullable rule/万能 item | identity、状态和闰日规则互相污染 | P1 架构/Contract |
| 只传 event id | route 缺 occurrence key/revision | 点击单次条目打开整个系列 | P1 行为错误 |
| 圆点由第一页推导 | `items.isNotEmpty` | 20 条外数据不显示圆点 | P1 聚合错误 |
| completed 直接过滤 | query `status != completed` | 日程卡片底部缺少已完成项 | P1 产品错误 |
| Habit done 直接过滤 | done 不返回 day item | 用户无法查看当天已完成 Habit | P1 产品错误 |
| Flutter 重算状态 | UI 根据 today/check-in 推导 | C++ 与页面文案/圆点不一致 | P1 双真相源 |
| Offset 分页 | `LIMIT/OFFSET` + 并发修改 | 跨页漏项/重复/抖动 | P1 分页错误 |
| cursor 从头重跑 | malformed/expired 当 null | 旧页后追加第一页、死循环 | P1/P0 |
| 只用非唯一排序键 | 只按时间或标题 | 并列项跨页不稳定 | P1 分页错误 |
| 四请求逐个覆盖 | 每个 future 单独 set ready | 圆点与卡片来自不同快照 | P1 一致性错误 |
| 全页一个 loading | 任一 section 失败清空全部 | 可恢复内容丢失、重试混乱 | P2 状态模型 |
| 去重掩盖 Native bug | UI `toSet()` 后静默继续 | 数据缺失但测试看似通过 | P1 可诊断性 |
| per-item Reminder 查询 | 循环内 Repository/JNI call | 42 天页面卡顿 | P1 性能 |
| SQLite 主线程查询 | Handler 直接 native call | 丢帧、ANR | P1 可用性 |
| 多个 GestureDetector 竞争 | 水平/纵向/刷新分别监听 | 手势随机失效或双触发 | P1/P2 |
| animation 作为事实 | 动画进度决定 viewMode | 中断后按钮与网格错位 | P2 状态一致性 |
| Fake fallback | native error 后返回 seed | 生产数据虚假 | P0/P1 |
| 测试调用生产 helper | expected 由同一 sort/date 代码生成 | 实现和测试一起错 | 无效验证 |
| 只测 Fake/Widget | 没有真实 JNI/SQLite/APK | 页面绿但生产不可达 | 发布阻断 |
| 提前激活 capability | Schema/单层完成即 active | 状态与产品事实不符 | 发布阻断 |

## 16. 独立测试 Oracle 与高价值矩阵

### 16.1 Contract 与映射

- 两个 public method、两个 internal call 的 success/failure envelope 全覆盖。
- valid、required 缺失/null、nullable 缺失、unknown enum、额外字段、错误版本、非法 timezone/date/page size/cursor。
- Dart/Kotlin/C++ 分别读取同一 fixture，再通过真实 MethodChannel/JNI 读取同一 fixture。
- 公开方法→Handler→JNI→C++ endpoint 的静态闭包，所有目标 ABI symbol 可见。
- capability 在 planned/blocked/integrated/active 各状态与实际 production 可达性一致。

### 16.2 日期、区间和 recurrence golden cases

| 案例 | 独立预期 |
| --- | --- |
| timed Event `23:00–01:00` | 两个当地日都显示 |
| timed Event 结束恰好次日 `00:00` | 只显示首日 |
| Event 开始恰好 day end | 当日不显示 |
| 全天 `[2026-08-31, 2026-09-01)` | 只显示 8 月 31 日 |
| 三日全天 `[D, D+3)` | D、D+1、D+2 显示，D+3 不显示 |
| occurrence 在范围前开始但跨入范围 | 在重叠日显示 |
| 月重复锚点 31 经过 2 月 | 2 月截断，3 月恢复 31 锚点 |
| 2024-02-29 Anniversary → 2025 | 2025-02-28 |
| 1900/2000/2100 | 非闰/闰/非闰 |
| DST gap recurrence | 按领域规则前移到首个合法 Instant |
| DST fold recurrence | 按领域规则选择较早 Instant |
| Asia/Shanghai ↔ America/Los_Angeles | timed Event 可能换日，date-only 不漂移 |
| 42 天范围 | 接受且恰好 42 summary |
| 43 天、空、反向范围 | 稳定错误、零成功数据 |

### 16.3 状态与排序

- Event：普通/重复 × pending/in-progress/overdue/completed/skipped/cancelled × all-day/timed/multi-day。
- Habit：binary/quantity × absent/partial/done/skipped/missed/upcoming × challenge 边界内外。
- Anniversary：一次性/年度 × importance/null × reminder on/off × soft-deleted/dangling rule malformed。
- 大量相同标题、相同开始时间、相同 reminder time 的 tie-breaker golden vectors。
- 完整分页结果与一次性参考排序完全一致；range dot 与完整 items 集合满足第 8.4 节守恒。

### 16.4 Cursor、刷新和竞态

- 每 section `0/1/19/20/21/40/41/100/101+`。
- cursor 正常推进、重复、倒退、空、query mismatch、timezone mismatch、section mismatch、snapshot expired。
- page 1 后插入、更新、删除排序前/中/后条目；必须 expired 或保持冻结 snapshot，不得漏/重。
- 快速点击 A→B→C 日期，按 C→A→B 响应；最终只能显示 C。
- range R1 请求中切换 R2；R1 summary 和任何 section 均不得覆盖 R2。
- loadMore 中刷新、刷新中返回详情、详情修改中时区变化、Tab 切走后 future 完成。
- pull-to-refresh 四请求一项失败、两项迟到、全部成功的原子替换与缓存保留。
- duplicate identity、empty page + has_more、cursor loop 触发保护且不会无界请求。

### 16.5 Flutter 交互、布局与无障碍

- 冷启动 week/today；偏好 month 后重启为 month/today；Tab 切换保留会话状态。
- 周/月翻页、年月选择、今天、相邻月日期、1/12 月跨年、月底夹取。
- 月上滑折叠、周下拉展开、完全展开后第二阶段刷新、反向中断、斜滑和连续快速 drag。
- 系统减少动画、360dp、200% 字体、深浅色、中文长标题、三组 21+ 条、FAB/底栏避让。
- Semantics 节点包含日期、今天、选中、类型；按钮 tooltip、触控目标、读屏顺序和截断完整标签。
- 新建三类型预填规则；详情 changed true/false；初始化/无缓存错误/有缓存错误/分组错误。

### 16.6 C++/SQLite、APK 与设备

- 真实临时 SQLite，固定 snapshot，并发 writer 与四查询交错；不只测 in-memory repository。
- 42 天高密度 recurrence/Habit/Anniversary，记录 query plan、query count、P50/P95、payload、JNI 和 UI frame evidence。
- Debug 与 release-like APK 加载真实 `.so`；所有目标 ABI 的 Calendar symbol 与 handshake。
- 真机：前台/后台、强杀/重启、旋转/窗口变化、系统日期跨日、改时区、减少动画、深浅色、200% 字体和 TalkBack。
- 真机测试使用专用 application id/隔离数据，不卸载、清空或迁移用户真实数据库。

## 17. 测试质量审查

| 失真模式 | 为什么不算证明 | Review 要求 |
| --- | --- | --- |
| expected 调生产 overlap/date helper | 同一边界错误会一起通过 | 手写半开区间 golden/table oracle |
| expected 调生产 sort comparator | 错误排序与分页测试同时绿 | 独立 tuple 和固定 expected ids |
| 只测 20 条以内 | cursor、21+ 和稳定 tie-breaker 未触发 | 覆盖所有分页边界与 101+ |
| 并发测试顺序 await | 没形成 response 乱序或 snapshot 竞争 | completer/barrier 控制交错 |
| 只断言 list length | 身份、顺序、重复、状态都可能错 | 断言完整 ids/order/fields/dots |
| Widget 只 pump 不 drag | 手势 arena、阈值和中断未执行 | 真实 pointer/drag 序列 + 真机 |
| 只测 Fake Gateway | production adapter/JNI/SQLite 不可达 | 至少一条真实 APK 全链 smoke |
| 只测 Boundary decoder | workflow/query/repository 可能未注册 | 从公开入口 black-box 到 SQLite |
| 性能只计总耗时 | 小数据隐藏 N+1，设备噪声难归因 | 同时记录 query count/plan/规模曲线 |
| expired cursor 当普通空页 | 漏数据被当正常结束 | 精确错误和 UI 全量刷新 |
| 只测无 DST 时区 | 24 小时假设未暴露 | 至少一无 DST、一 gap/fold zone |
| 为过测试改 Schema/计划 | oracle 被实现反向污染 | 必须回到真相源审批并记录 |

## 18. Review 输出格式与严重级别

最终报告按以下顺序：

1. Findings（P0→P3）；
2. Review scope、baseline、changed-file inventory 和使用的规则；
3. Architecture/boundary assessment；
4. Contract/data/time/cursor completion matrix；
5. Existing tests 与独立 tests 的命令、结果和 attribution；
6. APK/JNI/SQLite/真机证据；
7. Residual risks；
8. Uncertainties and assumptions（必须最后）。

每条 Finding 必须包含：

- 精确文件和紧凑行号；
- P0～P3 与 High/Medium confidence；
- 触发日期、输入、状态、手势、并发或数据规模；
- 违反的 Contract/领域/计划/架构条款；
- 可观察后果、数据/性能/可访问性影响；
- 最小修复方向；
- 独立复现、测试或静态证据；
- 本次引入、既有问题或本次放大。

严重级别：

- `P0`：用户数据破坏、生产伪数据、不可恢复死循环/崩溃、广泛错误日期或发布灾难。
- `P1`：主链路错误、漏项/重复、跨层 Contract 破坏、错误 snapshot/cursor、明显 ANR/卡死、关键无障碍不可用或实现未闭环。
- `P2`：有具体后果的性能、可维护性、状态恢复、边界体验或测试证据缺口。
- `P3`：低风险但可行动的问题；不报告纯审美或无依据的风格偏好。

## 19. 放行标准

最终只允许以下结论：

- `PASS`：无未解决 P0/P1；所有硬门禁和必要真实验证完成；P2/P3 已关闭或不影响发布且有明确记录。
- `PASS WITH RISKS`：无 P0/P1；只剩明确、有限、有负责人和接受人的 P2/P3 或非关键设备债务。
- `CHANGES REQUIRED`：存在任一 P0/P1、真实链未闭合、snapshot/cursor/time 语义无法证明、production Fake、必要构建测试失败或 capability 提前激活。
- `BLOCKED`：baseline、Contract、必要下层能力、设备或环境缺失，导致无法形成可靠判定；不能把 blocked 写成 pass。

给出 `PASS` 前必须同时满足：

1. Calendar Contract validator、fixture、跨层闭包和旧 Event/Habit/Anniversary/Reminder Contract 回归通过。
2. C++ 重新 configure，并通过构建后 `excellent_calendar_check`；独立时间、重叠、排序、cursor、snapshot 和压力测试通过。
3. Kotlin unit/lint、JNI/Handler integration、Debug/release-like APK、androidTest 构建和目标 ABI symbol/handshake 通过。
4. Flutter format/analyze、Calendar 定向、全量测试和 Debug APK 通过。
5. production composition 无运行时 Fake/seed/preview/fallback；同一 APK 展示三类真实 SQLite 数据并正确进入详情。
6. 42 天摘要、每组 101+、跨日/重复/DST/闰日/时区变化无漏项、重复或错误圆点。
7. 快速异步、refresh/loadMore、详情返回、Tab 切换和进程/配置变化无 stale response 或非法状态。
8. 无 N+1、无主线程大查询；定量性能门槛有记录并通过。
9. 360dp、200% 字体、深浅色、减少动画、Semantics/TalkBack 和关键真机手势完成。
10. capability、status、plan、index 和 log 与真实证据同步；未验证项没有被写成已完成。
11. 最终 diff 无无关重构、调试代码、依赖升级、用户修改覆盖或审查临时文件残留。

Review 阻断项关闭并完成复核后，才将本文件与主计划、分层计划一并归档。

## 20. 正式 Review 执行结果（2026-08-31，已被后续 Review 取代）

结论：`PASS WITH RISKS`。当前快照没有开放 P0、P1、P2 或 P3 Finding；该结论允许代码进入后续发布门禁，不代表 capability 已发布。

审查期间发现并关闭：

1. Flutter Habit quantity `partial/done` 关系未在不可信边界完整校验；已补严格关系与 Unicode code-point 长度测试。
2. Flutter 曾以本机 local `DateTime` 计算自然日，在 DST 周可能误判 42/43 天；已改为 Calendar 专属 civil-date 坐标，并锁定 Los Angeles spring/fall 回归。
3. 原始 pointer observer 只覆盖日期网格，从 section card 起手无法折叠/展开；已提升到整个滚动主体，且仍不加入 gesture arena。
4. Calendar Tab inactive 跨午夜或时区变化后重激活可能沿用旧 today/token；已在 activation 先 probe temporal context，统一推进 generation、清缓存并只重取一次。
5. `docs/status/current.md` 残留“Calendar 仍为占位”的旧结论；已与真实四层实现和 blocked 发布状态统一。

独立证据：

- Calendar validator：`213 schemas / 19 fixtures / 2 public / 2 native`，状态 `implemented_unintegrated + blocked`；Anniversary 与 Habit 共享 validator 回归通过。
- Flutter Calendar 定向 76 项通过；实现方全量 535 项、`flutter analyze` 与 Debug APK 通过。
- Android Calendar 三个 JVM 测试类 16 项通过；三 ABI/JNI、Debug 主/测试 APK 与既有只读设备 smoke 证据有效。
- C++ Calendar Query 独立测试 1/1 通过；实现方构建后 `excellent_calendar_check` 11/11 通过。
- `git diff --check` 无 whitespace error，仅有既有 LF/CRLF 提示。

保留风险与发布阻断：

- `adb devices -l` 无设备；新安全 `CalendarSeededIntegrationSmokeRunner` 的真实三类“只读 → seeded → 只读”序列未执行。
- 同一 APK 的真实三类 UI、真机滚动手感、TalkBack、200%/动态主题、进程恢复、设备时区/DST 与 Android 16 参考设备性能未闭环。
- Release 的 Flutter/native 三 ABI 已编译，最终 Java 打包仍被既有 release classpath 缺少 `integration_test` plugin 阻塞。
- Contract bootstrap runner 因本机代理无法重装已清理的临时依赖；使用仓库现存隔离验证环境直接执行同一 validator 已通过。

Capability 维持 `implementation_status: implemented_unintegrated`、`release_status: blocked`。上述门禁关闭并复审前，本文件、主计划和四份分层计划继续留在 active，不归档。

## 21. 后续 Finding 与开发侧返修（2026-09-01）

后续独立 Review 结论为 `CHANGES REQUIRED`，确认两项 Finding：

1. P1：completed 重复系列仍继续展开 `completed_at` 之后的未来 occurrence。
2. P2：Calendar 已感知设备时区变化后，新建 Habit 仍复用应用启动时缓存的时区。

开发侧没有直接接受报告结论，而是先补失败回归复现。两项均能在修复前稳定失败，因此判定为真实缺陷，并按下列冻结边界返修：

- completed 重复系列只保留 occurrence 锚点严格早于 `completed_at` 的实例；timed 锚点为 `occurrence_start_at`，all-day 锚点为 recurrence timezone 当地日初。锚点等于截止时刻时排除；截止前已开始的跨时/多日实例保留完整区间。
- 同一过滤同时进入 `range_summary` 与 `list_day_items`，避免摘要和日列表分叉；保留实例继续遵守显式 occurrence state 优先级，否则显示为 completed 且不产生圆点。
- Calendar 新建 Habit 不再读取 `_habitTimezoneFuture`，而是在进入创建页前重新调用真实设备 timezone provider；表单提交使用这次刷新得到的值。

开发侧验证：Calendar validator `213/19/2/2` 通过；重新 configure 后 `excellent_calendar_check` 13/13 通过；新增 C++ 回归覆盖未来实例、精确截止、跨越截止和 all-day 当日边界；Flutter 新增真实 composition widget 回归，修复前提交 `America/Los_Angeles`、修复后提交 `Asia/Tokyo`；`flutter analyze` 无问题、全量 575/575、Debug APK 构建通过。正式结论仍等待独立复审，设备与 Release 阻断保持不变。

## 22. 最终独立复审与产品发布例外（2026-09-02）

最终独立复审确认历次代码问题真实存在且均已返修，包括 Reminder recovery 引用校验、历史日期 Event 默认提醒、全天一次性提醒 UTC 锚点、23 点默认时间跨日、Native 错误中文映射、创建按钮布局，以及更早的 completed-series cutoff 与 Calendar→Habit 时区刷新。复验未发现下列七项之外的新硬缺陷：

1. 正式生产签名 APK/AAB 与目标商店上传校验；旧 Release-mode APK 的 Debug signer Finding 已通过 fail-closed 配置和固定证书指纹门禁修复，并以一次性非生产密钥验证 APK/AAB，但尚无生产密钥产物或商店证据。
2. 真机时区切换与 DST gap/fold。
3. TalkBack 人工焦点顺序与听读。
4. 200% 字体和减少动画真机验证。
5. 强杀、进程回收与冷启动恢复。
6. 完整升级、回滚及签名密钥恢复矩阵。
7. 正式 Release 包的三类真实数据 UI 全链验证。

独立证据包括：Calendar Contract `213 schemas / 19 fixtures / 2 public methods / 2 native calls`；C++ 构建后测试 `13/13`；Flutter 全量 `592/592`、`flutter analyze` 0 issue；Android unit、Lint、三 ABI androidTest APK、Debug 构建；realme RMX3687 / Android 13 上隔离 `.device_test` 的真实 JNI/SQLite 三类数据与周/月、今天、未支持入口基础 UI 路径。签名复审先确认旧 Release-mode APK 为 `CN=Android Debug`，后续返修已移除 Debug fallback、建立生产密钥/固定指纹的构建前后门禁，并以一次性非生产密钥验证 APK/AAB；该临时密钥和产物均已删除。

按本 Review 原规则，生产密钥保管/恢复、正式产物和商店上传缺口仍属于发布运营 P1，不能把 Review 历史改写成完整 `PASS`。产品负责人于 2026-09-02 明确接受上述七项为 Calendar V1 发布后的非阻断债务并批准例外激活；因此机器 capability 切换为 `integrated + active`，但所有未执行项继续以“未验证”表述，统一由 `OPEN-CAL-001` 跟踪。本文件随主计划和四份分层计划归档。
