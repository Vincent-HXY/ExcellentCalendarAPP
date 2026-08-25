# 纪念日 Reminder 与日历 Occurrence — 白盒 Review 计划

> 状态：Completed / 发布复审通过；剩余设备矩阵由产品负责人接受为非阻断验证债
> 对应开发计划：`docs/plan/completed/纪念日-02-Reminder与Occurrence开发计划.md`
> Contract 阶段子计划：`docs/plan/completed/纪念日-03-contracts设计.md`
> 审查对象：Anniversary、Reminder、Notification、Recovery、Occurrence projection 从 Contract 到 Flutter/Android/C++/JSON Storage 的完整实现增量
> 审查性质：以代码控制流、状态机、数据流、事务、并发、失败恢复和跨层契约为核心的白盒审查；本文不把通用 Review 流程当作重点

## 1. 审查目标与判定基线

本次审查不是确认“页面上能新增提醒”或“单元测试绿了”，而是证明以下两条真实链路在正常、失败、重试、并发、崩溃、重启、迁移和系统能力受限时都保持一致：

```text
Anniversary create/update/delete/toggle
  → Reminder plan 与确定性链
  → JSON 可恢复提交
  → 提交后 Scheduler reconciliation
  → Dispatcher Alarm
  → prepare_delivery
  → Android Notification
  → finalize_delivery
  → Notification / covered Reminders / successors 原子闭环
```

```text
bounded local-date window
  → anniversary.list_occurrences
  → C++ date-only 动态展开
  → 稳定 cursor 分页
  → Flutter Application 拉取完整窗口
  → 日历消费者收到不重不漏的 typed summaries
```

开发后的 Source of Truth 按以下方式裁定：

1. 当前开发任务明确要求改变旧 Contract 与旧实现，因此以开发计划冻结的目标行为为验收目标。
2. Contract 阶段子计划负责把上位计划转化为可并行交接的冻结协议；其停止条件仍未解决时，受影响实现不能自行选择语义。
3. 开发完成后更新的 JSON Schema、`method_channels.yaml`、`native_calls.yaml`、`identity.yaml`、`enums.yaml` 和 `error_codes.yaml` 是机器可验证协议真相源；它们必须与开发计划一致。
4. Anniversary、Reminder、Notification、Recovery 的领域文档与 Accepted ADR 约束实体边界、身份、事务和派生状态。
5. 实际代码和测试只能证明实现状态，不能用偶然旧行为覆盖新任务要求。
6. 若更新后的 Contract、领域文档、ADR、计划和实现仍冲突，受影响能力不得判定完成；必须指出冲突双方、采用的真相源和暂停范围。

当前实现基线必须被审查者独立确认，至少包括：

- `AnniversaryWorkflowService` 当前只通过 Anniversary 两 Store transaction 处理 Anniversary/Recurrence；开发后必须形成同时覆盖 Reminder plan 的窄 Workflow Repository 闭环。
- `AnniversaryQueryService` 当前只有 detail/list/preview；开发后 `list_occurrences` 必须进入真实 C++ query path。
- C++ `Reminder` 当前主要表达 Event occurrence 的 `recurrence_revision/occurrence_start_at/advance_minutes`；Anniversary 分支必须使用独立强类型条件字段，不能把 Event 字段借来凑数。
- `NativeAnniversaryGateway._validateSupportedPlan` 当前会拒绝非空 Reminder plan；开发完成后生产 gateway 不得继续拒绝、丢弃或 Fake 掉该输入。
- 现有 Reminder/Notification/Recovery 两阶段投递、Ring、Dispatcher Alarm 和 JSON journals 已在生产路径使用；新增 Anniversary 分支必须扩展它们而不是复制第二条旁路。
- `NotificationTapRouter` 已识别 `target_type=anniversary`，但开发后仍需证明 PendingIntent、EventChannel、冷/热启动和真实详情加载的完整闭环，不能把已有 switch 分支当成端到端证据。

## 2. 发布阻断红线

以下任一项成立，结论至少为 `CHANGES REQUIRED`；发生数据损坏、静默丢失或不可恢复覆盖时按 P0 处理。

| 红线 | 必须判错的实现 | 直接后果 |
| --- | --- | --- |
| 跨 Store 非原子 | Anniversary 已保存但 Reminder plan 半写，或 finalize 逐文件/逐 Reminder 顺序提交 | 重启后出现孤儿、漏提醒、重复 successor 或虚假 sent |
| 共享 `reminders.json` 无统一协调 | Anniversary journal、Event/Recovery/Delivery journal 各自保存旧 after-image 并可交叉重放 | 后提交数据被旧 journal 覆盖，属于真实数据损坏 |
| 旧 Alarm 先展示后校验 | Android 先 `notify`，再让 C++ 判断 target/date/remind_at 是否陈旧 | 改期、暂停或删除后仍弹出错误纪念日 |
| 聚合履约造假 | 未真实展示一个聚合 Notification 就把 covered Reminders 标为 sent，或为每条 covered Reminder 伪造 Notification | 审计与用户实际看到的通知不一致 |
| 聚合非幂等 | 同一 occurrence 的重试/重启生成新 delivery ID、变更 frozen membership 或展示多个 tag | 重复通知、successor 重复、批次不可审计 |
| 身份不稳定 | title/note/category/importance、当前时钟、输入顺序或平台 JSON 序列化影响 UUIDv5 | 编辑、重试或跨端后同一逻辑任务变成新任务 |
| Scheduler 成为真相源 | 调度失败回滚/删除已保存 Reminder，或 Alarm 状态反写决定业务是否存在 | 权限、ROM 或进程故障导致用户配置丢失 |
| bootstrap 顺序错误 | journal/migration 未恢复完成就开放 Query、JNI 或 Scheduler | 暴露半提交快照，随后调度错误数据 |
| migration 静默默认 | v2 旧记录通过 codec 默认值“看起来能读”，没有显式 v2→v3 迁移 | 旧 Event/Reminder/Notification 语义被悄悄改变 |
| 破坏既有投递 | Event popup、Ring、72 小时 Recovery、snooze 或 Dispatcher 语义回归 | 新功能以牺牲已激活功能为代价 |
| 假生产链路 | UI 只在 Fake Gateway 可用、Native 返回占位成功、Android 不真实调度 | 功能表面存在但不可交付 |
| 过早激活 Contract | smoke、构建、迁移或真机未通过就标记 `integrated/active` | 协议状态对调用方和发布判断说谎 |

## 3. 跨层能力闭环

每个公开或内部能力都必须沿真实调用链闭合。只新增 Schema、DTO、Handler 或 C++ 函数中的任意一端都属于未完成。

| 能力 | 必须存在且一致的代码面 |
| --- | --- |
| create Anniversary + Reminder plan | Schema/fixture → Dart DTO/Gateway/Application → MethodChannel → Kotlin Contract/Handler/JNI → C++ Boundary/Workflow → Workflow Repository → Anniversary/Recurrence/Reminder Stores → commit 后 reconciliation |
| update Anniversary + Reminder plan | 同上；额外覆盖 optimistic concurrency、旧新 template diff、旧 Alarm CAS、保留/终结/替换链 |
| delete Anniversary | C++ workflow 同一 logical commit 软删除目标、终结未来 Reminder、保留 Notification 历史；提交后取消/对账 Alarm |
| pause/resume | 独立 Contract 与真实 workflow；保留配置，只终结或重新物化未来任务，不复活已过期任务 |
| detail | 返回提醒总开关与配置摘要；不暴露内部 Scheduler/attempt 噪音；旧消费者兼容策略明确 |
| list occurrences | Request/response/cursor Schema → Dart 自动分页 → MethodChannel/Kotlin/JNI → C++ 有界 date-only projection → 稳定排序与筛选 |
| plan recovery | C++ 根据当前事实选择 Anniversary 候选、按 occurrence 分组、冻结 membership；Kotlin 不重算业务边界 |
| prepare aggregate delivery | expected identity/CAS、target 复核、membership 冻结、唯一 prepared attempt、冻结 payload |
| finalize aggregate delivery | 一个 Notification、全部 covered Reminders、共同 fulfillment、每模板 successor、Recovery 状态在一个可恢复提交中终结 |
| timezone/time change | Android 系统入口 → reconciliation → C++ 重算 open Reminder UTC projection → CAS 淘汰旧 Alarm |
| notification tap | C++ frozen payload → Kotlin PendingIntent/事件 → Dart typed payload → 冷/热启动 router → Anniversary detail / deleted state |

必须检查所有新增方法是否同时完成：声明、实现、注册、调用方、构建源列表、JNI export、错误映射、状态标记和测试。特别留意“方法已经写了但未注册”“测试直接调用 private service 绕过 Boundary”“Debug receiver 可调用但正式 APK 不可调用”。

## 4. 架构与职责边界

### 4.1 Anniversary 不能被 Event 模型污染

- Anniversary 必须继续是独立实体，不能创建影子 Event、复用 Event `recurrence_revision` 或把 Anniversary 写进 Event Store。
- `AnniversaryRecurrence` 继续只表达 `yearly + interval=1`，不复制月、日、时区、RRULE 或 target 反向关系。
- Anniversary occurrence 是当地 `date`；不得伪造 `occurrence_start_at`、全天 Event start/end Instant 或 `EventOccurrenceState`。
- Anniversary V1 不增加 complete/skip/cancel/reopen 状态，也不预生成多年 occurrence。
- 2 月 29 日规则、`years_elapsed`、下一 occurrence 和 occurrence identity 只能由 C++ 权威实现；Dart/Kotlin 不得复制一套“看起来相同”的日期算法。

高频错误是直接复用 Event recurring Reminder 的 nullable 字段，通过 `target_type` 分支勉强运行。审查时必须查看 Domain constructor/validator、Schema 条件分支和 Storage codec，确认 Anniversary 与 Event 是互斥、强约束的合法形状，而不是“任何字段都可空”的大对象。

### 4.2 业务规则必须留在 C++

- 最多 5 条、重复模板、0～365 天、补发日末、successor、暂停/恢复、陈旧任务拒绝、聚合 membership 和 `sent` 履约规则属于 C++ Domain/Application。
- Kotlin 只负责严格边界映射、JNI、Alarm/WorkManager/Notification/系统回调；不得决定某条 Reminder 是否过期或把多条任务自行分组。
- Flutter 只做输入反馈、流程编排和展示；UI 校验不能替代 C++ 防御性校验。
- Scheduler reconciliation 是 commit 后副作用，不能进入 Repository transaction，也不能让 C++ Application 依赖 AlarmManager。
- Application/Domain 不得包含 JSON 文件名、journal phase、SQLite、Android Context、MethodChannel Map 或 UI 文案组件。

### 4.3 Repository 必须窄且可替换

- Workflow Repository 应按 create/update/delete/toggle/query/prepare/finalize/recovery/timezone 意图提供能力，不暴露可被任意改写的巨大 `CalendarCoreState`。
- JSON 特有锁、after-image、journal、原子文件替换只能在 Storage adapter/coordinator。
- 未来 SQLite adapter 必须能复用同一 Application port；如果 port 参数或返回值包含 JSON object、文件路径、journal status，则边界已经泄漏。
- 不得为本功能新建跨所有 Calendar 实体的大型全局事务抽象；允许 storage-level commit coordinator 统一物理提交，但它不能成为业务万能仓库。

### 4.4 上层类型边界

- Dart UI/Controller 不得接触原始 `Map<String, dynamic>`、MethodChannel 字段名或 Native error envelope。
- Kotlin Handler 不得保存 Reminder/Anniversary 的业务副本；进程重建后必须从 C++ 权威状态恢复。
- 不允许通过 `dynamic`、通用 `Map`、自由文本 `kind/status/error` 或 catch-all default 绕开新增 typed DTO/enum。
- 新依赖边必须有职责理由；不得借此任务升级 SDK、Gradle、Flutter、NDK、第三方依赖或改造无关模块。

## 5. Contract 与严格边界审查

### 5.1 Schema 形状与条件分支

- Anniversary reminder draft 只允许 `advance_days/local_time/method/is_enabled` 及已冻结的必要字段；绝对 UTC `remind_at`、Event `advance_minutes/recurrence_revision/occurrence_start_at`、ring/wechat 必须被 Schema 拒绝。
- 单条 `is_enabled`、Anniversary 级总开关、空模板数组、字段省略和显式 null 的组合必须只有一种解释；总开关关闭时保留模板，不能形成“总开关关闭但单条仍被调度”的矛盾状态。
- Reminder response 必须按 `target_type` 建立互斥分支：Event 分支与 Anniversary 分支各自要求正确字段并禁止对方字段。不能只新增一批 optional properties。
- Notification 聚合分支必须显式表达 kind、target、occurrence、covered IDs、Recovery 归属和稳定 attempt/delivery identity；不能伪装成普通单 Reminder Notification。
- `additionalProperties: false`、`required`、`oneOf/if-then` 必须真正关闭未知字段和歧义分支；重点检查 `allOf` 组合后是否仍允许未知字段或同时命中两个分支。
- null 与字段缺失必须按兼容矩阵处理；Anniversary 新分支的必填字段不得用 null/缺失默认值补齐。
- 所有数组必须同时约束数量、元素类型、重复值和稳定顺序；Kotlin/Dart 数值解析不得把 `double`、负数或溢出值当合法整数。

### 5.2 方法、版本和状态

- `anniversary.list_occurrences` 必须同时出现在 MethodChannel 与 native call 清单，并指向正确 request/response Schema。
- create/update/detail 的 shape、Reminder/Notification/Recovery 扩展必须在两份调用清单完全同步。
- 实现前或仅单层完成时保持 `planned/blocked/unintegrated`；只有正式生产入口、跨层 smoke 和要求的真实验证完成后才允许 `integrated/active`。
- 所有失败均返回合法 `NativeResult<T>`；禁止 `{ok: true, data: null}`、裸异常字符串、空成功、PlatformException 代替已声明业务错误或 catch-all 默认数据。
- 稳定错误码至少覆盖计划列出的非法配置、超过上限、非法窗口、cursor、陈旧 identity、过期、membership/attempt 冲突、时区、幂等、migration/journal 和调度待恢复类别。
- 错误码语义必须跨 C++、Kotlin、Dart 一致；Kotlin 不得把多个可区分错误压成 `NATIVE_INTERNAL_ERROR`，Flutter 不得把部分成功压成保存失败。

### 5.3 Identity golden vectors

必须从 `identity.yaml` 独立计算并跨语言核验：

- `occurrence_key = UUIDv5(namespace, [anniversary_id, occurrence_date])`；
- `template_key = UUIDv5(namespace, [anniversary_id, advance_days, local_time, "follow_device", "popup"])`；
- `reminder_id = UUIDv5(namespace, ["anniversary", anniversary_id, occurrence_key, template_key])`；
- aggregate delivery 绑定 anniversary、occurrence、稳定排序后的 covered IDs 和 popup。

重点检查 canonical JSON 的 UTF-8、数组顺序、数字格式、日期格式、当地时间秒/分钟格式、UUID 大小写和字符串 escaping。不得使用平台默认 `Map.toString()`、locale 格式、集合迭代顺序、当前时钟或随机 UUID 生成确定性身份。title、note、category、importance 和 message 不得进入身份。

### 5.4 Wire 与 Storage 兼容是两件事

- Wire Contract 的旧 Event/普通 Reminder reader/writer 与新 Anniversary 分支要有显式兼容矩阵。
- Local Storage v2→v3 要有独立迁移矩阵；不能因为 wire 字段 optional 就推断旧 Store 可直接由新 codec 读取。
- 新版本不得让旧 Event/Reminder/Notification 的合法记录突然需要 Anniversary 字段。
- 未知更高版本、未知枚举、损坏字段必须失败，不能自动降级。

## 6. Occurrence projection 白盒审查

### 6.1 窗口和日期边界

- 请求是当地日期半开区间 `[range_start_date, range_end_date)`；开始等于结束、结束早于开始、超过 400 个自然日都必须使用稳定错误失败。
- 400 天按当地自然日计算，不能用 UTC duration 除以 24 小时；DST 切换不能把 400 日误判为 399/401。
- 一次性只在原始日期位于窗口时返回一次；年度从 source year 起动态展开，绝不能返回早于 source date 的历史 occurrence。
- 2 月 29 日非闰年落 2 月最后一天；必须覆盖 1900 非闰、2000 闰、2100 非闰等世纪规则。
- `years_elapsed = occurrence_year - source_year` 且不得为负；0 保留在数据中，UI 只是不显示“第 0 周年”。
- timezone 必须是有效 IANA ID；不能接受缩写、设备 locale 或静默回落 UTC。

### 6.2 当前事实投影

- 修改 Anniversary.date 后，过去与未来 occurrence 都按当前 date 重算；V1 不保留旧 revision 幻象。
- 删除/软删除后，过去与未来 occurrence 都不进入普通列表。
- 标题、分类、importance、Reminder 摘要来自同一查询时刻的当前事实；不得先查 Anniversary、再逐项无锁查 Reminder 产生混合快照。
- `has_active_reminders` 与 `reminder_count` 表达配置/总开关的冻结语义，不能错误地按当前物化 open Reminder 数量计算，否则年度链终结到 successor 的瞬间会闪烁。
- note、Notification 历史、任务明细、创建/更新时间、本地化文案不得泄漏进轻量 summary。

### 6.3 排序、筛选和 cursor

- 总排序必须是 `(occurrence_date, anniversary_id, occurrence_key)` 升序；任何分页 query 都必须复用完全相同的比较器。
- `category_ids` 重复、非法 ID 形状、`importance` 未知值必须显式失败；空筛选与未提供筛选的语义要按 Contract 区分。
- 不得保留旧 Anniversary list 的 200 条总上限；批次大小可以限制，完整窗口结果不能截断。
- cursor 必须不可伪造或可严格验证，并绑定足以继续同一排序/筛选/窗口的状态；malformed、query mismatch、过期 cursor 不能从头静默重跑。
- 必须评估翻页期间数据修改：要么 cursor 绑定稳定快照/版本，要么检测变更并返回 expired；不能在修改后继续导致漏项、重复或顺序倒退。
- Flutter 自动分页必须检测 cursor 不前进、重复 cursor、空页但 `has_more=true`、重复 item 和页数失控，避免 Native bug 造成死循环或内存失控。

### 6.4 性能与资源

- 审查算法是否按 Anniversary 数量和窗口内实际年度 occurrence 线性扩展，不能逐日×全部实体重复全表扫描。
- 使用大量 Anniversary、400 日窗口和多页结果压测 payload、JSON 编解码、JNI 局部引用、主线程阻塞和 Flutter 内存。
- C++ 查询和 Kotlin Handler 不应在 Android 主线程执行长时间 Store 扫描；异常/cancel 后不得泄漏 cursor/session 资源。

## 7. Reminder 模板、身份与时间模型

### 7.1 配置约束

- 一个 Anniversary 最多 5 条配置；全局暂停不能被用来绕过数量限制后保存第 6 条。
- `(advance_days, local_time, method)` 在同一 Anniversary 下唯一；输入顺序不同不影响 template identity。
- `advance_days` 允许 0 和 365，拒绝负数、366、浮点和整型溢出；`local_time` 精确到分钟并严格拒绝非法日期时间文本。
- V1 method 只能 popup；ring/wechat 必须在 Schema、Kotlin Contract 和 C++ Domain 都失败，不能只靠 UI 隐藏选项。
- 默认提醒总开关关闭；旧 Anniversary 迁移后配置为空，不能自动生成“当天 09:00”。

### 7.2 用户意图与 UTC 投影

- Reminder 同时保存稳定用户意图 `advance_days/local_time/timezone_mode` 和当前投影 `occurrence_date/remind_at`；两者不得混为单一 UTC 字段。
- 换算顺序必须是 occurrence 当地日期减天数 → 拼 local_time → 使用当前设备 IANA zone 解析 → UTC；不能先把 occurrence date 当 UTC 再减 duration。
- DST gap 前移到首个合法 Instant，fold 选择较早 Instant；必须复用项目现有 C++ `LocalTimeResolver` 规则，不允许 Kotlin `ZonedDateTime` 或 Dart `DateTime` 自行采用不同默认。
- advance 跨月、跨年和闰日时做日历减法；不能用固定毫秒数导致 DST 前后墙上时间漂移。
- 时区变化只重算未终结 Reminder 的 UTC projection，保持 occurrence/template/reminder identity；旧 expected `remind_at` Alarm 必须失效。

### 7.3 初次物化和补发窗口

- 创建时本次 `remind_at` 已过去：一次性不建过去任务、不立即补发；年度直接找下一 occurrence。
- 正常 reconciliation 的历史补发有效期是 `[remind_at, occurrence 次日当地 00:00)`；恰好次日 00:00 已失效。
- “occurrence 次日 00:00”必须在当前设备时区解析，不能用 occurrence UTC + 24h。
- 提前 365 天可能跨越前一个自然年；identity 仍绑定目标 occurrence，而不是 remind_at 所在年份。
- 普通 create/update workflow 不得创建过去 Reminder；只有恢复 workflow 可以按冻结规则处理到期任务。

## 8. 生命周期、编辑与并发状态机

审查时必须逐条追踪旧状态、目标状态、同事务写入、提交后副作用和旧 Alarm 行为。

| 操作 | Reminder/身份预期 | 最易出错点 |
| --- | --- | --- |
| 创建一次性 | 每模板至多一个未来 Reminder，无 successor | 把已过去提醒立即补发；先存 Anniversary 后存 Reminder |
| 创建年度 | 每模板物化首个有意义 occurrence | 为所有未来年份预生成；本年已过仍创建历史任务 |
| 改 title/note/category/importance | identity 与 remind_at 不变，未来未 prepare 内容读最新事实 | 把展示字段纳入 ID；改写历史 Notification；note 泄漏锁屏 |
| 改 date | 旧 occurrence 的未来链终结，新 date 确定性重建 | 只改 Anniversary；旧 Alarm 仍展示；改回旧日期发生 ID 冲突 |
| 改 advance/local_time | 旧 template 链终结，新 template 链物化 | 原地改 ID 对应的业务含义；留下两个 open 链 |
| 年度→一次性 | 原始日期未来才保留一次任务，否则无未来任务 | 按“下一周年”错误保留年度 successor |
| 一次性→年度 | 从首个未来 occurrence 物化 | 复活过去一次性任务或复用已软删除 recurrence |
| pause | 保留所有模板，终结/取消未来调度任务 | 删除配置；把 pause 当 `is_enabled=false` 后仍被 recovery 选中 |
| resume | 从首个仍有意义 occurrence 重新物化 | 恢复过期旧 Reminder；同模板出现两条 open task |
| 删除单模板 | 仅终结该 template 链 | 误删同 occurrence 的其他 template；聚合 attempt membership 被静默修改 |
| 删除 Anniversary | 软删除目标、终结未来 Reminder、保留 Notification | 硬删历史；点击历史通知崩溃；旧 Alarm 先展示 |
| timezone change | 保持当地意图与身份，重算 open remind_at | 修改 template/occurrence ID；终结记录被重写；旧 CAS 仍通过 |

必须特别审查以下竞态：

- update/delete/pause 与 Alarm Receiver 同时执行；`prepare_delivery` 必须在展示前重新读取 target、occurrence、template 状态和 expected `remind_at`。
- prepare 完成后再编辑标题：prepared Notification 内容已冻结；未 prepare 的未来通知使用最新标题。不能在 finalize 时重新读取并改写 payload。
- date 改回原值时确定性 ID 恢复；若 Store 中已有 cancelled/expired/sent 同 ID 记录，workflow 必须按冻结幂等规则安全复用、恢复或拒绝冲突，不能插入重复主键或把历史 sent 改 pending。
- 两个 update 并发使用同一旧 `updated_at`；只有一个提交成功，另一个必须稳定冲突，不能 last-write-wins 覆盖新 Reminder plan。
- pause 与 resume 快速连续、重复请求重放、Scheduler 尚未完成前再次编辑；最终权威 queue 必须由当前 C++ 状态收敛。
- 删除 Anniversary 后旧 prepared attempt finalize；必须拒绝或按已冻结规则终结，绝不能重新生成 successor。

## 9. 聚合补发与两阶段投递

### 9.1 候选分组与 membership

- 只能把相同 `(anniversary_id, occurrence_key)` 的逾期 Anniversary popup Reminder 分为一组；不同 Anniversary、不同 occurrence、Event/ Ring/普通 popup 不得混入。
- 候选必须仍启用、未删除、状态可投递、已到期且未超过该 occurrence 日末；pause/delete/改期/陈旧 `remind_at` 必须排除。
- `covered_reminder_ids` 去重并按 Contract 比较器稳定排序；不能依赖 repository、hash set 或文件中的偶然顺序。
- membership 在 prepare 后冻结。随后新到期 Reminder 必须进入新的合法 attempt/下一次规划，不能加入已 prepared 的集合。
- 相同 recovery request、相同逻辑 group 或进程重启必须找到并复用原 batch/delivery/attempt；不得按新的 now 重新选 membership。

### 9.2 一个真实 Notification 的审计闭环

- 聚合只创建一个 Notification attempt、一个稳定 delivery ID 和一个 Android `notify(tag=deliveryId,id=0)`。
- covered Reminder 不得各建一条伪 Notification；`status=sent` 只能表示其义务由共同真实 delivery 履行。
- Notification 的 `covered_reminder_ids` 与每条 Reminder 的 `fulfillment_delivery_id` 必须双向一致；batch/membership 记录可从任一方向恢复审计关系。
- 点击 payload 仍绑定单个 Anniversary target 与 occurrence；不能路由到无明确详情对象的全局 recovery summary。
- 该聚合 kind 不得与现有跨目标 `recovery_summary` 混淆。两者的 target、文案、covered 语义、点击路径和 identity 必须有清晰条件分支。
- Anniversary 日末补发与既有 72 小时 Recovery window 的优先级、候选选择和分组关系必须已在冻结 Contract 中形成唯一答案；如果仍需要 Kotlin/C++ 各自猜测，按 Contract 子计划停止条件判定为阻塞，不能继续审查为“实现偏差”。

### 9.3 finalize 状态转移

- success：一个 logical commit 内完成 Notification sent、全部 covered Reminders sent、相同 fulfillment、每个年度 template 各自 successor、batch/group 完成。
- retryable failure：attempt 失败但 covered Reminders 保持可重试，不创建 successor，不改变 frozen membership；下一 attempt 复用 delivery ID。
- permanent failure：attempt 失败，所有 covered Reminders 按同一 frozen 决策进入失败终态，每个年度 template 各自创建 successor。
- expired：超过 occurrence 日末的本年 Reminder 进入 expired，每个年度 template 各自滚动；不能继续补发，也不能丢链。
- 同一 finalize 重放必须返回相同结果；不同 outcome/failure 字段重放必须冲突，不能二次改状态。
- 同模板任何时刻最多一个 open successor；聚合包含 5 个模板时必须检查 5 条链分别滚动，而不是只返回/保存一个 `successor`。

### 9.4 崩溃窗口

至少审查并故障注入以下位置：

1. membership 计算后、journal prepare 前；
2. journal prepared 后、第一个 Store 写前；
3. 每个 Store 写后；
4. prepare 已持久化并返回 Kotlin 后、Android `notify` 前；
5. Android `notify` 成功后、finalize 调用前；
6. finalize journal prepared 后、covered Reminders 写入中间；
7. commit marker 写后、journal 清理前；
8. successor 保存后、Scheduler reconciliation 前。

重启后的 oracle：不出现第二个可见 tag；prepared attempt/ID/membership 不变；sent/failed/expired 和 successors 最终收敛；没有半组 sent；没有旧 after-image 覆盖新数据；Scheduler 最终依据权威 open queue 对账。

## 10. JSON Storage、迁移与恢复

### 10.1 `reminders.json` 多 writer 是最高风险点

当前 Event create/update、recurring delivery、Recovery、snooze、Anniversary workflow 等路径可能共同写 `reminders.json`。审查不能只看到每个 transaction 自己有 mutex/journal 就判定安全，必须证明：

- 所有生产 writer 共用同一 storage directory lease、进程内串行化和 storage-level commit/recovery coordinator；不能每个类各有一把互不相识的锁。
- 任一 prepared commit 未恢复前，其他 writer 不能基于旧快照提交。
- coordinator 能识别所有 journal 类型及其 touched Stores，不遗漏 Event、Reminder、Notification、Recovery、Anniversary、snooze 等既有路径。
- after-image 或 delta 的基线验证足以阻止陈旧 journal 覆盖后来已提交的 `reminders.json`。
- 多进程测试/runtime 继续遵守正式 factory 和独立测试进程约束，不因测试直接 new transaction 绕开正式 lease。

必须构造交叉 journal 反例：Anniversary transaction prepared → 另一个 Reminder writer 试图提交 → 进程终止 → bootstrap。最终结果必须包含两个合法业务变更或让后一个 writer 在前一个恢复前明确失败；绝不能由重放顺序决定丢哪个。

### 10.2 提交协议

- create/update/delete 至少一致覆盖 anniversaries、anniversary recurrences、reminders；聚合 finalize 至少一致覆盖 reminders、notifications、recovery batches。
- journal 写入、Store 原子替换、commit marker、cleanup 的每个 phase 都有稳定 failure hook 和幂等 recovery。
- logical commit 失败不能把部分 after-image 暴露给 query；commit 已成立后即使 cleanup 失败也必须重放到同一 committed 结果。
- recovery 不得再次调用业务 workflow、Clock 或 ID generator；只能重放已经冻结的数据。
- Store 损坏、journal 损坏、版本冲突、missing touched Store 必须显式失败并阻止 runtime 开放，不能删除 journal 后继续。
- 正式目录仍为 `files/local_storage/calendar_core_storage_json`，不得为了绕迁移另起一个“anniversary reminder”目录。

### 10.3 v2→v3 migration

- 使用完整 v2 fixtures 覆盖 Event、普通/repeating Reminder、Ring、Notification、RecoveryBatch、Anniversary、Recurrence、软删除和审计字段。
- 迁移必须显式生成 v3 shape；旧 Anniversary 配置为空，不生成 Reminder；旧 fulfillment/covered 关系按兼容规则为空。
- 迁移重复执行幂等；中途失败/进程终止后只能恢复为完整 v2 或完整 v3，不允许 mixed version Stores。
- v3 codec 对新记录严格校验；不能以“旧数据兼容”为名给损坏 v3 记录默认值。
- migration 必须在任何 repository/query/scheduler 初始化前完成；Scheduler 不得在迁移期间读取旧 queue。
- 升级后旧数据逐字段 round-trip；未知 Store version 和未来字段按冻结策略失败。
- 旧 App 无法安全读取 v3 的降级风险必须进入发布说明和验证矩阵，不能声称支持回滚。

## 11. C++ Core 重点

### 11.1 Domain 与 Application

- `AnniversaryOccurrence`、Reminder template/chain、aggregate membership 应为强类型，而不是散落 string/JSON object。
- validator 同时覆盖结构和领域不变量；Boundary 校验通过不代表 Domain 可省略校验。
- Clock、ID generator、timezone resolver 必须可注入，使边界、DST、幂等和崩溃测试可重复。
- 时间计算检查整数溢出、非法 ISO date/time、IANA zone failure、闰年和极值年份；失败不能通过异常穿过 C ABI。
- create/update/delete/toggle 的跨实体 diff 在 C++ workflow 内完成；Flutter/Kotlin 不得逐条调用 Reminder API补偿。
- `schedule_reconciliation_required` 只在 logical commit 成功后返回；保存失败不能触发 Scheduler，调度失败也不能反向回滚提交。
- aggregate finalize 的返回模型必须能表达所有 covered Reminders/successors 或明确声明批量审计结果；不能沿用“最多一个 reminder + 一个 successor”的旧返回形状而悄悄丢数据。

### 11.2 Boundary、runtime 和并发

- decoder 严格拒绝未知/缺失/类型错误；encoder 不漏字段、不把 date 编成 datetime、不生成自由文本枚举。
- C++ Boundary 新 API 在 runtime 中注册真实 service dependency；不能直接绕过 Application 调 Storage。
- runtime bootstrap 完成 migration + 所有 journal recovery 后才发布 ready；初始化失败后所有 API 稳定失败，不能部分服务可用。
- JNI 并发调用 create/update/query/reconcile/prepare 时，Repository snapshot 和 transaction serialization 可证明安全；不得用单测串行执行掩盖 race。
- 检查 CMake source/test registration、链接符号和 APK `.so`；只有 host C++ 测试通过不证明 Android 加载了新代码。

## 12. Kotlin / Android 重点

### 12.1 Contract、JNI 与线程

- Method 名称、Kotlin interface、JNI function/descriptor、C++ export、package/class 名、static/instance receiver 完全一致。
- nullable、List、Map、boolean、Int/Long、UTF-8、date/time 字符串在两端一致；严格拒绝 `1.0` 冒充 integer、null 冒充缺失和未知 enum。
- Native error 必须映射到稳定 `NativeResult`；pending JNI exception、native exception 和 parse error 不能被 catch 后返回空成功。
- JNI 调用的线程 attachment、局部引用数量、长列表分页 payload 和 runtime 生命周期安全；进程重建后不持有失效 native handle。
- Kotlin Contract 做边界校验但不重新计算 occurrence key、successor、补发日末或 timezone projection。

### 12.2 Scheduler reconciliation

- 保存成功后统一 reconciliation；notification permission 拒绝、exact alarm 不可用或 AlarmManager 异常都保留 Reminder。
- exact alarm 不可用时真实使用允许的近似路径，并把 capability/降级状态返回 UI；不能只显示提示却仍调用会抛 `SecurityException` 的精确 API。
- App 启动、回前台、设备重启、升级、日期/时间/时区变化、权限恢复都触发幂等对账；重复事件不得注册重复 Dispatcher。
- 继续使用“一个最早 Dispatcher Alarm”模型，不能为 Anniversary 每条 Reminder 各注册 Alarm。
- `mark_scheduled(expected_remind_at)` 与 Dispatcher identity/CAS 对齐；旧 Alarm 被 Native 拒绝后必须在 `notify` 前停止。
- WorkManager unique work、重试/backoff、进程恢复和并发 receiver 不造成两次 drain 或 prepare。
- 批量 reconcile 的部分失败要有可诊断的稳定结果；不能吞掉单项错误后统一报告成功。

### 12.3 Notification 与点击

- `NotificationManager.notify` 的 tag 必须是稳定 delivery ID，`id=0`；不能用 hashCode/requestCode 导致碰撞或重试新条目。
- 只在系统调用成功后 finalize sent；permission/ROM/API exception 映射 retryable/permanent 的规则一致。
- 聚合 membership 只由 Native response 提供，Android 不按时间重新分组。
- PendingIntent identity、flags、extras 在 API 版本上正确，且同 delivery 重试覆盖；不同 Anniversary 不互相覆盖。
- title/body/payload 来自 frozen Notification；锁屏不包含 note、原始异常、Store path 或调试字段。
- 点击覆盖 App 已运行、冷启动、进程被杀、重复点击、目标删除、目标改期；重复点击去重不能误伤不同 delivery。
- 已删除目标显示明确 unavailable state；不能 fallback 到空白页、Today 页假装成功或用缓存伪造详情。

## 13. Dart / Flutter 重点

### 13.1 DTO、Gateway 与 Application

- 移除当前生产 gateway 对非空 Anniversary Reminder plan 的硬拒绝，并把所有字段通过 typed DTO 发送；不得简单删校验后继续丢字段。
- create/update/detail/list occurrences 的 Gateway interface、Native gateway、MethodChannel adapter 和 mapper 同步；原始 Map 只在 adapter 内。
- date-only 使用严格 `YYYY-MM-DD` 语义；不能让 Dart 本地/UTC `DateTime` 自动转换把 occurrence 改到前一天/后一天。
- malformed NativeResult、unknown enum、缺失 data、错误 cursor 必须失败；不得映射为空列表/默认关闭/保存成功。
- occurrence Application 自动拉完所有页，保持 Native 顺序，检测 cursor 环和重复；Calendar 消费者不需要理解分页细节。
- “已保存但调度待恢复”是独立结果状态；不能在 catch 中当完整失败，也不能当无警告完整成功。

### 13.2 表单与详情状态

- 默认关闭、当天/1天/7天 09:00、自定义 0～365 天、分钟级时间、最多 5 条和重复项反馈与 Contract 一致。
- UI 即时校验只改善体验；手工构造 Gateway request 仍由 C++ 拒绝非法输入。
- 首次开启权限请求失败后保留设置；权限回调与保存请求并发时，不能把已保存配置覆盖为空。
- exact alarm 降级只提示“可能稍有延迟”，不阻止保存。
- 编辑页正确回填全局 pause 与全部模板；关闭再打开不丢排序、不重复模板、不把 pause 当删除。
- async submit/load/toggle/pagination 在 dispose 后不更新状态；防重复提交覆盖按钮、回调和快速导航返回。
- 详情快速 pause/resume 与完整编辑共享同一 Application/Native 真相源，不能两套 Controller 分别维护本地提醒状态。

### 13.3 生产装配与路由

- `main.dart`/composition root 正式注入 Native Anniversary Gateway；Fake 只能留在测试或明确 prototype，不得由 debug flag/异常 fallback 自动进入生产。
- 新 occurrence port 只提供未来 Calendar Application 消费能力；本任务不得顺便实现/修改完整周月年 UI 或统一 `calendar.list_items`。
- Notification tap DTO 必须保留 Anniversary target/occurrence identity；router 最终打开真实 detail。是否把 occurrence key 放入 route 由 Contract/页面需要决定，但不得在边界解析时丢失或改写 payload。
- Scheduler pending warning、权限入口和 deleted state 都有用户可见且可恢复的状态，不用 debug 文案替代。

## 14. 既有功能回归保护

新增 target-specific 分支很容易让共享 Reminder/Notification 代码出现条件遗漏。以下回归必须独立核验：

- 普通 Event popup/ring 的合法 shape、UUIDv4/UUIDv5、prepare/finalize、snooze 与完成联动不变。
- 重复 Event 仍使用 `recurrence_revision/occurrence_start_at/advance_minutes`，Anniversary 字段为空；Anniversary 不反向污染 Event。
- Ring 仍只支持活动、非全天、非重复普通 Event；Anniversary 永远不能通过宽松 validator 获得 ring。
- 现有 72 小时 Recovery、5 分钟 Ring 宽限、全局 20 条明细上限、`abandoned_to_summary/outside_window` 和 recovery summary 语义不变。
- Dispatcher 仍扫描 Reminder 真相源，Notification 不进入 future queue。
- Notification 同一 delivery 最多一个 sent attempt，abandoned 旧 attempt 不能 finalize。
- Anniversary 原有 CRUD、倒计时、2 月 29 日规则、两 Store transaction、分类弱引用和软删除行为不回归。
- Category、Event、Reminder、Notification 的旧 v2 fixtures 迁移后逐字段一致。
- 已激活 Ring/Notification/Reminder Contract 状态不得因新方法批量替换或复制 YAML 时被降级、漏项或改错 Schema。

若开发 diff 修改共享 validator、codec、runtime factory、transaction coordinator、Reminder recovery/delivery workflow、Kotlin Dispatcher 或 Notification DTO，必须扩大到相关全量回归；不能以“只新增 Anniversary 分支”为由只跑新测试。

## 15. 独立测试 oracle

测试预期必须先从计划、Contract、ADR 和公开接口冻结，不能复制实现分支或私有常量。已有测试只能用于 harness，不得用它们证明自身预期正确。

### 15.1 Contract 与 identity

- 全部 JSON/YAML 可解析，`$id/$ref` 唯一闭合；完整 metaschema/实例校验实际执行，不只做 JSON 语法检查。
- 每个 request/response 提供 valid、缺字段、未知字段、null、未知 enum、错误版本和 target 条件字段混用 fixture。
- Dart、Kotlin、C++ 对同一 golden vector 计算/传输完全相同 UUID；改变 title/note/输入顺序不改 ID，改变日期/template/membership 按规则改变 ID。
- method/native call 到 Schema、Handler、JNI、Boundary 的静态闭包检查。

### 15.2 Date/occurrence/timezone 表

至少冻结以下独立案例：

| 案例 | 预期 |
| --- | --- |
| 一次性 source date 在窗口开始 | 返回 |
| 一次性 source date 等于窗口结束 | 不返回 |
| 年度窗口早于 source year | 不返回 |
| 400 日窗口 | 接受；401 日拒绝 |
| 2024-02-29 → 2025 | occurrence 2025-02-28 |
| 1900/2000/2100 | 分别按非闰/闰/非闰 |
| source year occurrence | `years_elapsed=0` |
| DST gap local_time | 前移到首个合法 Instant |
| DST fold local_time | 选择较早 Instant |
| advance 365 跨年 | 绑定目标 occurrence，墙上时间不漂移 |
| catch-up 恰好 occurrence 次日 00:00 | 不补发 |
| timezone change | identity 不变、UTC remind_at 改变、旧 Alarm CAS 失败 |

### 15.3 生命周期组合

- 一次性/年度 × 1条/5条 × future/current-past remind_at。
- title/date/repeat/template edit、pause/resume、逐模板删除、target 删除。
- 同一 request 重放、改回旧 date、两个并发 update、update 与 prepare 竞态。
- 每个组合检查 Anniversary、Recurrence、Reminder、Notification、Recovery、successor 和 Scheduler flag，而不是只断言 API response。
- 对每个失败确认无半提交、无额外 ID、无旧 Alarm 展示。

### 15.4 聚合与失败矩阵

- 同 occurrence 2～5 条逾期 → 一个 Notification、全部共同 fulfillment、各自 successor。
- 同 Anniversary 不同 occurrence、不同 Anniversary、Event + Anniversary 混合 → 必须分组正确。
- 新 Reminder 在 prepare 后到期 → 不加入 frozen membership。
- retryable、permanent、expired、相同 finalize 重放、冲突 finalize。
- Android notify 前崩溃、notify 后 finalize 前崩溃、finalize 每个 Store 写点崩溃。
- 重启后检查可见通知 tag 数、prepared attempt identity、Store 最终状态和 successor 唯一性。

### 15.5 Storage/migration/concurrency

- 所有 v2 fixture → v3，重复迁移、损坏数据、未知版本、每阶段 failure hook。
- Anniversary prepared journal 与 Event/Recovery/snooze writer 交错；不同重放顺序不得丢数据。
- bootstrap 未完成时并发 JNI/query/scheduler 必须阻塞或稳定失败。
- 多线程 create/update/reconcile/prepare/finalize，使用 barrier 形成真实交错；不能用顺序 future 冒充并发。
- 正式 storage factory、正式 runtime 和真实文件测试；仅内存 repository 不足以验证 journal。

### 15.6 Kotlin/Flutter/真机

- Kotlin Contract/JNI valid/invalid/大列表/Unicode/空值/整数类型；正式 `.so` symbol 与注册检查。
- notification permission 允许、拒绝、永久拒绝、后续授权；exact alarm allow/deny 和近似降级。
- App 启动/前台/boot/upgrade/time/timezone/date events 重复触发的幂等 reconcile。
- Flutter Controller/widget 覆盖默认值、上限、重复、回填、部分成功、dispose、重复点击和 cursor 环。
- 真机完整链：创建 → Store → Alarm → 到点 → prepare → notify → finalize → 点击真实详情。
- 真机补发：纪念日前、纪念日当天、次日边界；同 occurrence 多 Reminder 只一个系统通知。
- 真机改期/暂停/删除后让旧 Alarm 到点，确认完全不展示。
- 进程终止、设备重启、Doze/后台冻结、权限恢复、时区切换，并核对 Store/Alarm/Notification 脱敏证据。

## 16. 测试质量审查

测试存在不等于覆盖。重点识别：

- 测试复用生产 identity helper 计算 expected UUID，导致 helper 错了测试也绿；golden expected 必须是外部冻结常量。
- 只测 Boundary decoder 或 Fake Repository，没有跑真实 workflow + JSON files + recovery。
- Mock 掉 Scheduler/Notification 后只断言“调用过一次”，没有验证权限、异常、tag、payload 和 finalize outcome。
- 所谓并发测试实际逐个 `await`；所谓崩溃测试只是抛异常后销毁对象，没有新进程/bootstrap 重放。
- 只断言 list 长度，不断言每条 identity、顺序、membership、状态和双向审计关联。
- 只跑快乐路径；非法 target 字段组合、unknown enum、null/缺失和 v2 migration 未覆盖。
- widget 测试只 `pump` 不崩溃，没有断言用户看到“已保存但调度待恢复”、权限警告和回填状态。
- 真机命令使用会卸载正式 application id 的测试入口并删除用户数据。必须使用隔离 application id/Store 或明确安全的 smoke 方案。
- 测试为适配实现而修改计划预期、放宽 Schema 或把失败改成默认成功；这是 oracle 被污染，不是修复。

## 17. AI/赶工实现高频错误速查表

| 极易犯错点 | 代码症状 | 审查判定 |
| --- | --- | --- |
| 复用 Event occurrence | Anniversary 出现 revision/start Instant/Event state | 架构与 Contract 违规 |
| nullable 大对象 | 所有 target 字段 optional，只在一处 if 判断 | 条件不变量无法跨 codec 保证 |
| Dart/Kotlin 算 UUID | 三端各自有 identity helper | C++ 非唯一 producer，漂移风险 |
| title 进入 ID | 改标题后生成新 Reminder | 幂等与链断裂 |
| random template/reminder ID | 每次重试新 UUID | 重复任务/重复通知 |
| `advance_days * 1440` | 用 minutes/Duration 代替当地日历减法 | DST/跨日墙上时间错误 |
| date 当 UTC DateTime | `toUtc()` 后序列化 occurrence | 日期偏移 |
| catch-up 使用 `<= nextDay` | 次日 00:00 仍补发 | 半开边界错误 |
| pause 删除 templates | resume 无法恢复原配置 | 产品语义错误 |
| resume 直接 enable 旧任务 | 过去 Reminder 被重新调度 | 过期误发 |
| date edit 只改 Anniversary | Reminder/Alarm 未 replacement | 旧日期弹窗 |
| 改回旧日期直接插入 | 确定性 ID 与历史记录冲突 | 主键冲突或历史被篡改 |
| 全局合并补发 | 多个 Anniversary 一条摘要 | 无法路由真实详情 |
| set/hash 顺序做 membership | 重启后 delivery ID 改变 | 聚合非幂等 |
| prepare 后重新选组 | 新到期任务加入旧 attempt | frozen membership 失效 |
| 先标 sent 再 notify | 系统调用失败仍显示 sent | 虚假履约 |
| finalize 循环逐条 save | 中间崩溃出现半组 sent | 跨实体非原子 |
| retry 新 delivery tag | 通知栏出现多条 | 用户可见重复 |
| 一个 successor 返回值 | 5 个模板只滚动 1 条链 | 永久漏提醒 |
| per-transaction mutex | 各 journal 自己安全但互相覆盖 | `reminders.json` 数据损坏 |
| codec 默认新字段 | 旧/损坏数据都“兼容” | migration 被绕过 |
| Scheduler 先于 recovery | Alarm 读取半提交 queue | 错误/重复调度 |
| 权限拒绝清配置 | 用户设置被平台能力改变 | Scheduler 变真相源 |
| exact alarm 仅提示不降级 | UI 说可用，实际从未调度 | 假能力 |
| Android 自行判断过期 | Kotlin 与 C++ 边界不同 | 双重业务规则 |
| `hashCode()` 作 notification ID | 碰撞覆盖其他纪念日 | 错误通知消失/串位 |
| router 只测热启动 | 冷启动 extras 未消费 | 真机点击断链 |
| note 进入 body | 锁屏泄露隐私 | P1 隐私问题 |
| 复用 200 条 list 上限 | 400 日窗口被静默截断 | 日历漏项 |
| cursor 从头重跑 | 自动分页重复/死循环 | 查询不完整 |
| Fake fallback | Native 失败时悄悄切 Fake | 生产数据不真实 |
| 提前 active | 只改单层就激活 Contract | 状态与生产能力不符 |
| 测试复制实现常量 | 错误算法与测试同时通过 | 非独立验证 |

## 18. 完成度与审查输出要求

最终 Review 报告必须 findings 优先，按 P0→P3 排序；每条包含代码位置、Contract/计划/ADR 依据、观察到的控制流或数据流、实际影响、最小修复和可复现验证。不能只写“建议增加测试”“可能有并发问题”。

必须单独给出以下完成度矩阵，每项标记 `完成 / 偏差 / 未完成 / 未验证`：

1. Contract/identity/error/version；
2. occurrence date-only projection 与完整分页；
3. create/update/delete/pause/resume workflows；
4. Reminder template/chain/timezone；
5. aggregate recovery/prepare/finalize；
6. JSON shared commit/recovery coordinator；
7. v2→v3 migration；
8. C++ Boundary/runtime/JNI；
9. Kotlin Scheduler/permission/exact-alarm fallback；
10. Android Notification/tap；
11. Dart/Flutter typed Gateway/UI/partial success；
12. Event/Ring/Recovery/Anniversary 既有回归；
13. 构建、静态分析、单元、集成、smoke；
14. 物理设备正常到点、补发、崩溃、旧 Alarm、权限、时区和点击。

真实构建与测试至少包括开发计划第 13 节门禁：C++ 构建后 `excellent_calendar_check`、Flutter test/analyze/debug APK、Android JVM/lint/Debug 与适用 androidTest、`test_environment/flutter_native_smoke`、APK `.so`/JNI symbol 和物理设备验收。工作树测试覆盖的是最终 working-tree 状态；若 index 与 working tree 不同，必须说明 would-be commit 未被同样验证。

以下内容不能被“代码审查上看起来正确”替代：migration、每阶段崩溃重放、真实 JNI/`.so`、Alarm 到点、权限/近似降级、系统通知、冷启动点击、时区切换、旧 Alarm 拒绝和国产 ROM 后台行为。任何一项未实际执行，必须明确标为未验证。Anniversary R1 已具备 migration、真实 JNI/`.so`、正常 Alarm 到点、系统通知和点击证据；产品负责人于 2026-08-25 明确批准将其余设备矩阵作为已接受风险，因此 Contract 切换为 `active`，但未验证项目不得被描述为通过。
