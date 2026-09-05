# 习惯 Habit 与 HabitCheckIn 闭环 — 白盒 Review 计划

> 状态：Active / Host Review Completed / Device Gates Open
> 状态同步：2026-08-31
> 对应主计划：`docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`
> 对应分计划：`docs/plan/completed/习惯-02-Contracts层开发计划.md`、`docs/plan/active/习惯-03-CPP层开发计划.md`、`docs/plan/active/习惯-04-Kotlin层开发计划.md`、`docs/plan/active/习惯-05-Flutter层开发计划.md`
> 关键真相源：`contracts/habit/`、`contracts/method_channels.yaml`、`contracts/native_calls.yaml`、`contracts/identity.yaml`、`contracts/storage/calendar_core_storage.yaml`、`contracts/enums.yaml`、`contracts/error_codes.yaml`、`contracts/habit/habit_lifecycle_operation_matrix.yaml`
> 审查对象：Habit、HabitRecurrence、HabitCheckIn、HabitReminderTemplate、Reminder/Notification 扩展、SQLite v5、Kotlin 调度与通知动作、Flutter Habit/Appearance 的最终生产增量
> 审查性质：以代码控制流、状态机、数值与日期语义、事务、并发、崩溃恢复和真实跨层接线为核心的白盒审查；本文不把通用 Review 流程当作重点

## 0. 当前执行结论

- 2026-08-28 已执行首轮白盒 Review，结论为 `CHANGES REQUIRED`；发现的跨午夜投递、DST date-only、skipped、continuation cursor、partial 文案和计划数值口径问题随后完成返修。
- 2026-08-28 的独立复核确认上述返修已进入真实生产调用链；Contract、C++ build-after-test、Flutter、Android、APK、Native smoke 与三 ABI JNI 主机门禁通过。
- 2026-08-29 黑盒复核发现的卡片进度、101+ 分页、数量型圆圈和 occurrence 技术文本问题已于 2026-08-31 返修并通过 Flutter 444/444、analyze 与 Debug APK 验证。
- 本次文档同步已关闭“计划和状态文档落后于代码”的 P3：主计划、三份分层计划、current、roadmap、索引和本 Review 均以当前集成事实为准。
- Review 仍保持 active，因为通知权限拒绝/恢复、跨午夜、进程死亡/设备重启、通知快捷动作及时区/系统时间变化的完整真机矩阵尚未执行；机器 capability 继续保持 `planned + blocked`。

## 1. 审查目标与最终判定对象

本次 Review 不是确认“页面能创建习惯”或“各层单元测试都绿了”，而是证明以下真实生产链在正常、非法输入、重复调用、并发、进程终止、重启、迁移、权限受限和系统时间变化时仍保持同一套业务事实：

```text
Flutter typed request
  → MethodChannel
  → Kotlin strict Contract / orchestration
  → JNI
  → C++ Boundary / Application / Domain
  → 同一个 SQLite v5 transaction
  → Kotlin commit 后 Scheduler reconciliation
  → Flutter typed result 与持久化事实一致
```

```text
Alarm / WorkManager / notification action（不依赖 Flutter Engine）
  → Kotlin 校验不可伪造的系统输入
  → JNI
  → C++ 复核 Habit、日期、occurrence、template 和当前状态
  → prepare / finalize 或 set-to-done transaction
  → Notification 审计、Reminder successor、CheckIn 与 UI 后续刷新一致
```

最终判定对象必须是三条并行开发轨合并后的**同一个工作树、同一个正式 APK、同一个生产 composition**。单独 C++、Kotlin Contract Fake、Flutter Gateway Fake 或 preview 入口通过，只能证明分层开发阶段完成，不能证明 Habit 已完成。

开发后的裁定基线如下：

1. 机器可验证 Contract 和 Schema 是跨层字段、类型、枚举、错误码、身份与存储格式的第一真相源。
2. Habit 领域文档和 Accepted ADR 是实体边界、生命周期、派生状态、提醒工作流与职责归属的真相源。
3. 当前 active 主计划与分计划定义本次交付范围；实现存在、旧测试通过或 UI 看起来可用，均不能覆盖上述约束。
4. `docs/index.md`、上位主计划和三份分层计划现已统一记录“分层开发已结束、真实生产链已接通、主机门禁通过、设备与状态校准待完成”。后续 Review 继续把最终真实接线和统一验收作为硬门禁；文档状态不得再次用旧的并行开发快照覆盖当前事实。
5. 若 Contract、领域不变量、计划、代码或测试冲突，受影响能力不得判定通过；报告必须说明冲突双方、采用的真相源、影响范围和需要暂停的能力。

优先级定义：

- **P0**：可能造成数据损坏、静默丢失、不可恢复覆盖、越权系统动作或同一业务事实永久分叉。
- **P1**：发布阻断；真实功能不可用、重复通知、事务不完整、生产链仍走 Fake、严格 Contract 被绕过或关键状态机错误。
- **P2**：重要但可局部规避；错误反馈、竞态体验、分页遗漏、可访问性、性能或维护性风险。
- **P3**：低风险一致性、命名、覆盖补强或非阻断债务。

## 2. 发布阻断红线

以下任一项成立，结论至少为 `CHANGES REQUIRED`。不要因为“主路径能跑”或“已有测试覆盖”而放行。

| 红线 | 必须判错的实现 | 直接后果 |
| --- | --- | --- |
| 定点数退化 | 任一层把 `*_hundredths` 转成 `double`、JSON 小数或字符串后再浮点解析 | `9007199254740990` 与 `9007199254740991` 等相邻大值失真，打卡、统计和回读不一致 |
| 假生产链路 | `lib/**` 或 Android `src/main/**` 存在 Habit Fake、种子数据、preview fallback；JNI 失败后返回伪成功 | Debug 看似可用，正式包没有真实持久化或系统行为 |
| 跨 Store 非原子 | Habit、Recurrence、CheckIn、Template、Reminder、Notification 分次提交，或业务事务跨多个 SQLite connection | 重启后出现孤儿、漏打卡、重复 successor、提醒与模板分叉 |
| 迁移先写后验 | v4 完整校验前已经创建表、改 metadata 或改 `user_version` | 损坏的 v4 被部分升级，失去可恢复基线 |
| v5 部分升级 | 四表、八索引、metadata、generation、history 不是同一 `BEGIN IMMEDIATE` 原子事务 | 打开后处于既不是合法 v4 也不是合法 v5 的状态 |
| 旧运行时写 v5 | 旧 binary 接受、默认或降级写入 v5 数据库 | 新字段、索引语义或 Habit 数据被旧 codec 破坏 |
| 业务规则上移 | Kotlin/Flutter 自行决定 eligible、生命周期、streak、today X/Y、提醒是否应发送或 UUID | 三层在时区、边界日和重试时产生不同事实 |
| Scheduler 成为真相源 | Alarm/权限失败回滚已经提交的 Habit/Template，或 Android 已调度被当作业务存在依据 | ROM、权限或进程故障导致配置丢失或响应造假 |
| 旧 Alarm 先展示后校验 | Kotlin 先 `notify()`，再让 C++ 判断 template/date/occurrence 是否陈旧 | 改时间、结束、删除或当日已完成后仍弹错误通知 |
| 同日重复展示 | 同一 `habit_id + occurrence_date` 因模板换 key、clear、reconcile 或重启展示第二个真实通知 | 用户遭遇重复提醒，且审计链无法解释 |
| 两阶段履约造假 | prepare 后未真实展示就写 `sent`，或展示成功后未 finalize 却创建 successor | 审计记录、真实通知和下一次提醒互相矛盾 |
| 通知动作可伪造 | Receiver 可导出、PendingIntent 可变、缺少 identity/date/current-state 复核，或直接信任 extras | 外部应用可代替用户完成习惯，旧动作可污染今天数据 |
| 后台动作依赖 Flutter | 快捷完成必须启动 Flutter Engine、Activity 或 Dart 才能提交 | 冷进程、锁屏、系统回收后动作失效 |
| Recovery 污染 | Habit 被加入普通 72 小时 `ReminderRecoveryBatch` 或普通汇总通知 | Habit 的同日语义被跨日补发并混入错误审计模型 |
| 响应内部矛盾 | mutation 内嵌 `reminder_settings.schedule_reconciliation_required` 与公开 capability 表达不同最终状态 | Dart 严格 DTO 拒绝成功响应，用户看到“协议不兼容” |
| 错误被默认成功 | 未知字段、未知枚举、异常 JNI 返回、`ok=false` 携带 data 被吞掉并转为默认对象 | 不兼容或损坏被静默掩盖，后续写入扩大问题 |
| 提前激活协议 | 真实 JNI、SQLite v5、正式 APK、设备提醒矩阵未过就把 Habit 标为 `integrated/active` | 发布状态对调用方和产品判断说谎 |
| 测试污染真实数据 | 自动化测试连接正式数据库、真实用户 profile 或使用清库方式做隔离 | Review 本身造成用户数据损坏 |

## 3. 跨层能力必须逐条闭环

每个能力都要从 Contract 一直跟到最终副作用或查询结果。只存在 DTO、Handler、Service、SQL adapter 中的一部分，或测试直接绕过上一层调用内部函数，都属于未完成。

| 能力 | 白盒必须追踪的完整代码面 | 最容易漏的点 |
| --- | --- | --- |
| `habit.create` | Schema/fixture → Dart DTO/Gateway/Form → MethodChannel → Kotlin Handler/Orchestrator → JNI → C++ create transaction → SQLite v5 → commit 后 reconcile → 最终公开 response | Habit 与 Recurrence、Template、首个 Reminder 是否一个 logical commit；调度结果是否回写最终 capability 投影 |
| `habit.update` | 同上；额外追踪旧值、乐观并发、start/end/target/unit/template diff | 第一次打卡后仍改 start date；target 改动污染历史 snapshot；改提醒时间复活同日提醒 |
| `habit.list` | Request/filter/page/cursor → C++ snapshot query → `items + today_progress + pagination` → Flutter list | `today_progress` 被当前页、筛选或累计页数计算；分页过程中快照漂移 |
| `habit.detail` | id/timezone/as-of → C++ detail/statistics/history/reminder projection → typed UI | detail 嵌套对象分支校验不严；deleted/not-found 混同；历史日超范围 |
| `habit.end` | 生命周期矩阵 → C++ atomic end + future reminder cancellation → post-commit reconcile | final day 错误允许结束；upcoming 错误允许结束；进度冻结日期不正确 |
| `habit.delete` | 全生命周期 soft delete → template/reminder cancellation → audit 保留 → UI 路由 | 物理删除 CheckIn/Notification；重复 delete 非幂等；旧通知动作仍可写 |
| `habit.check_in` | public request → Kotlin 增补受信 `source`/时间 → native command → C++ lifecycle/date/value validation → CheckIn + reminder cancellation transaction | Kotlin 伪造业务默认；部分/完成数量分支混乱；重复调用换 id；完成后旧 Alarm 仍显示 |
| `habit.clear_check_in` | date identity → tombstone/revive policy → conditional same-day reminder restore → response/UI | 物理删除；重建新 id/created_at；已 sent/prepared 的当天被再次提醒 |
| `habit.list_daily_statuses` | 对称历史窗口 → C++ daily projection → stable result → day page | 把 `missed` 持久化；未来日/非 eligible 日误标 absent；边界少一天 |
| `habit.set_reminder` | Template transaction → deterministic occurrence/reminder identity → scheduler reconciliation | disable/re-enable、改时间、跨模板同日重复；调度失败回滚业务设置 |
| `habit.reconcile_reminders`（internal） | Kotlin budget loop → JNI → C++ current-fact query/materialization → schedule/cancel → cursor continuation | 重复/空 cursor 死循环；统计不守恒；并发旧页覆盖新状态；超过每次预算 |
| `appearance.get_local` | Dart → MethodChannel → Kotlin SharedPreferences → strict response | 误走 C++/云 profile；未知 token 被静默默认而非按 Contract 处理 |
| `appearance.update_local` | typed request → Kotlin local atomic write → response → app theme/language refresh | 只更新内存、重启丢失；部分字段写入；Habit 开发顺带破坏全局外观启动顺序 |
| notification action | immutable PendingIntent → non-exported Receiver → JNI → C++ set-to-done transaction → cancel display → 后续 UI refresh | Receiver 启 Flutter；直接 increment；旧日期/旧 occurrence 被接受；成功后通知 tag 未取消 |
| reminder delivery | Alarm/Worker → CAS/current-fact validation → prepare → Android display → finalize → successor | 先 display 后校验；prepare 即 sent；崩溃窗口重复 display；successor 重复 |
| notification tap | frozen payload → Android intent/event → Flutter router → real Habit detail/deleted state | 仅热启动可用；错误解析为 Event；删除后卡死或打开假详情 |

对上述每个方法还要核对：声明、实现、注册、构建源列表、JNI export、调用方、线程调度、错误映射、capability 状态与测试入口。高频错误是“函数已经写好但没有进入 CMake/JNI 注册”“Debug smoke 可调用但 release APK 符号缺失”“测试直接调用 C++ Service，完全绕过真实 Boundary”。

## 4. 领域模型与职责边界

### 4.1 五类业务对象不可揉成一个大对象

- `Habit` 只表达挑战配置、生命周期与聚合身份；不能内嵌可变的每日完成状态或 Android 调度状态。
- `HabitRecurrence` 独立存在并固定表达 `daily + interval=1 + follow_device`；不能复用 Event recurrence 的 revision、RRULE、start time 或 occurrence state。
- `HabitCheckIn` 是每日事实和审计；`missed` 只能查询派生，不能持久化成 CheckIn。
- `HabitReminderTemplate` 表达每日本地时间配置；真正可调度项仍进入共享 `Reminder`，真实展示仍进入共享 `Notification`。
- Reminder/Notification 审计可以比 Habit 活得更久，不能用 SQLite 外键级联删除历史。

重点查看 Domain constructor、validator、codec 和 SQL relation checker，防止出现“所有字段都 nullable、靠 `target_type` 后置猜分支”的万能对象。Habit 分支必须与 Event/Anniversary 分支互斥，非法字段组合必须在不可信边界或聚合校验处失败。

### 4.2 C++ 是唯一业务事实拥有者

以下逻辑只能由 C++ Domain/Application 决定：

- 生命周期和允许操作；
- eligible 日期、今日、本地日期边界、400 天上限；
- CheckIn 唯一性、tombstone/revive、status/value/snapshot；
- 当前连续、最长连续、完成率、数量统计与 today progress；
- occurrence/reminder/action identity；
- 是否创建、取消、过期、恢复或拒绝某条 Habit Reminder；
- 同日一次真实展示、prepare/finalize、successor 和通知动作竞态裁定。

Kotlin 只处理严格边界、JNI、AlarmManager/WorkManager/Notification/系统回调和 commit 后协调；Flutter 只负责输入收集、请求状态和展示。若 Kotlin 或 Dart 出现日期循环、streak 算法、eligible 判断、UUIDv5、Reminder 过期规则或“为了 UI 方便”复制的统计逻辑，应按 P1/P2 评估并要求收回 C++。

### 4.3 Storage 与 runtime 不得泄漏到业务层

- Domain/Application 不得引用 `sqlite3*`、SQL、`payload_json`、Android Context、MethodChannel Map 或 Flutter 类型。
- Repository/Transaction port 必须按业务意图收窄，不能把整个 Calendar 数据库状态作为可任意改写的公开对象。
- SQLite adapter 可以统一物理事务，但不能成长为包含生命周期和提醒决策的第二业务层。
- 整个进程只能有一个 Calendar Core runtime/数据库 lease/连接所有者；嵌套工作流必须复用同一 recursive transaction 上下文，不能各自再开 connection。
- Dart UI/Controller 不得直接接触原始 `Map<String, dynamic>`；Kotlin Android service 不得自行拼接未经 Contract validator 的 JSON。

### 4.4 Fake 与预览代码隔离

重点全仓检查 `FakeHabit`、`HabitPreview`、seed、fallback、demo repository 和 debug-only composition：

- 允许测试目录存在 Fake；允许明确的测试 runner 注入 Fake。
- `flutter_client/lib/**`、Android `src/main/**` 和 release manifest/build config 不得导入或运行 Fake。
- JNI 初始化、数据库打开或 MethodChannel 失败必须暴露真实错误，不能自动降级为内存实现。
- preview 入口若曾用于并行开发，最终集成时必须删除或保证不进入任何 production target、deep link、launcher 或构建 source set。
- 测试必须至少有一组断言 production composition 的运行时具体类型和动态链接符号，防止未来重构重新接回 Fake。

## 5. 严格 Contract 与跨语言数值

### 5.1 字段必须逐项对照，不接受“语义差不多”

对 Habit 全部 Schema、10 个公开 Habit 方法、2 个 Appearance 方法和 11 个 internal native call 做字段级映射表，逐项核对：

- 字段名严格 `snake_case`；不得在 Dart/Kotlin 侧临时接受 camelCase 别名。
- required、nullable、字段缺失是三种不同状态；不得用 `?: 0`、`?: false`、空串或默认 enum 掩盖缺失。
- `NativeResult` 必须严格满足成功有合法 data、失败有合法 error、`ok=false` 不得携带 data、未知额外字段按 Contract 处理。
- 所有 enum、错误码、状态、原因、method 和 target-specific branch 必须穷举；未知值必须失败，不得 `else -> default`。
- 请求和响应的 `contract_version`、capability status、implementation/release status 必须与 registry 一致。
- Kotlin public response 与 C++ commit response 是不同边界模型；Orchestrator 增加调度 capability 时不得遗漏或保留提交前的旧嵌套状态。
- JSON date-time 必须是 Contract 要求的 UTC 秒精度形式；本地日期和本地时间不得伪装成 Instant。

### 5.2 `*_hundredths` 是本功能最危险的跨层字段

必须沿 `JSON integer → Dart int → Kotlin Long → JNI 字符串/JSON → C++ checked integer → SQLite JSON integer → 原路返回` 逐层检查。特别验证：

- `1`、`99`、`100`、`125`、`9007199254740990`、`9007199254740991` 全部精确 round-trip；最后两个相邻最大值不能合并。
- `0`、负数、超过最大值、指数形式、小数 JSON、`NaN`、`Infinity`、前后空格、空串和超长数字被正确拒绝。
- Flutter 表单允许用户输入 `1.25` 时，只在表单边界用十进制词法转为 `125`；不得先 parse 为 double 再乘 100。
- C++ 累计数量使用 checked arithmetic；总和溢出返回 `HABIT_STATISTICS_OVERFLOW`，不能 wrap、饱和或转浮点。
- 平均值用十进制定点 `round-half-up`；不能受 C++ integer truncation、Dart `round()` 或 Kotlin 二进制浮点舍入影响。
- `quantity_progress_rate_*` 虽是 0～1 number，也不能反向参与持久化数量或业务完成判定。

这部分必须有跨语言相同 golden vectors，而不是每层自己写一组看似合理但彼此不同的样例。

### 5.3 Unicode 长度不是 UTF-8 字节数或 UTF-16 code unit 数

标题 80、描述 2000、单位 32、备注 500 的限制必须按 Contract 要求的 Unicode code point 计数。至少覆盖：

- 中英文、emoji、代理对、组合字符、零宽连接序列；
- 恰好上限和上限加一；
- Dart `String.length`、Kotlin `String.length` 和 C++ UTF-8 byte length 产生不同结果的案例；
- UI 提示与 C++ 最终校验一致，但 UI 校验失败不能成为 C++ 省略防御性校验的理由。

## 6. 日期、生命周期与每日事实

### 6.1 本地日期边界

- `today` 必须由请求携带的合法 IANA timezone 与 C++ Clock/日期服务计算，不能使用 UTC midnight、Android 当前 Date 默认值或 Flutter 本地 `DateTime.now()` 作为权威。
- `start_date`、`end_date` 和每日 eligible 区间均为闭区间；重点检查所有 `<`/`<=` 和 SQL range predicate。
- 挑战天数最大 400 天时，恰好 400 合法、401 失败；跨月、跨年、闰年、2 月 29 日和 DST 日仍按 local date 计数。
- 修改系统时区、自动时区、手动时间后，旧请求的 `as_of_date`、Alarm 和新查询不能互相污染。
- 历史日查询窗口必须对称且有界，不能只限制过去不限制未来，或在分页时越界追加一天。

### 6.2 生命周期矩阵必须逐格映射到同一实现

以 `habit_lifecycle_operation_matrix.yaml` 为独立 oracle，至少核对 `update/end/delete/check_in/clear_check_in/set_reminder` 对 `upcoming/active/completed/ended/deleted` 的所有组合：

- 自然完成只在 `today > end_date` 后成立；最终日当天仍是 active，不是 completed。
- 最终日调用提前结束必须返回 `HABIT_END_NOT_EARLY`；upcoming 不能提前结束。
- completed/ended 只能 delete；不能更新、打卡、清除、改提醒或 reopen。
- completed 不能通过延长 `end_date` 被复活；ended 也不能恢复。
- deleted 对所有 mutation 都拒绝；重复删除的精确语义必须与矩阵/错误码一致。
- “重新开始”必须 create 新 Habit，生成新 Habit/Recurrence/Template/CheckIn/Reminder 身份，不能清空旧对象后复用 id。
- end/delete 与未来 Reminder cancellation 必须在一个业务事务中提交；Android cancel 只是提交后对账副作用。

高频实现错误是每个 Service 各写一组 `if`，导致 `set_reminder`、`clear` 和 `check_in` 对相同生命周期给出不同判断。Review 要定位共享 policy/guard，确认没有绕过入口。

### 6.3 CheckIn 的逻辑身份与 tombstone

- 每个 `habit_id + check_date` 在活动行和 tombstone 范围内都只有一个逻辑身份。
- clear 只设置 `deleted_at`；重新打卡必须复用原 `id` 与 `created_at`，更新 `updated_at`，不得 insert 新行。
- `first_check_in_at` 只在首次成功 CheckIn 设置一次；clear、再次打卡、改状态或迁移都不得清空或后移。
- `missed` 只能由 eligible 且无有效 CheckIn 的历史日期派生；数据库、Schema response 的 CheckIn status 不能持久化 `missed`。
- binary：done 数量和 snapshot 均为 null；skipped 的数量、snapshot、unit、completed_at 均为 null。
- quantitative：partial/done 必须有正整数数量、target snapshot、unit snapshot；done 的完成判定与目标关系必须和领域文档一致。
- 修改当前 target/unit 后，历史 CheckIn snapshot 和历史统计不能被回填；新打卡使用新 snapshot。
- `completed_count=0` 若产品语义是 clear，必须只通过明确 clear command，不能同时作为合法 partial、隐式 delete 和 UI no-op。

### 6.4 streak、完成率和 today progress 最容易被重复实现

重点验证：

- skipped 不进入 eligible 分母，并作为 streak 的桥接日；不能记作 done，也不能直接打断连续。
- 昨日 partial/absent 会打断 current streak；今天 absent/partial 尚未结束时是否打断，必须严格按领域定义实现。
- 最长连续、当前连续、7/30/all 完成率的窗口、分母、边界日和生命周期截止日一致。
- `today_progress` 的 `active_count = eligible_count + skipped_count`，`eligible_count = done + partial + absent`；所有 count 非负且同一 `as_of_date`。
- 今日 X/Y 的 X 只能是 done，Y 只能是 eligible；skipped 不进入 Y，partial 不能误算 done。
- `today_progress` 是列表响应的全局同快照摘要，与页码、page_size、cursor 和 UI 筛选无关。Flutter 不得通过当前页 `where(done).length` 重新计算。
- detail 中 summary、statistics、daily statuses、reminder settings 必须来自同一数据库快照；不能一个字段查询前、另一个字段在并发 mutation 后。

## 7. Reminder 身份、同日配额与系统时间

### 7.1 三种 UUIDv5 不能混用

逐一对照 `contracts/identity.yaml` 和 golden vector：

- Habit occurrence：`[habit_id, template_key, occurrence_date]`。
- Habit Reminder：`["habit", habit_id, template_key, occurrence_date]`。
- 通知完成动作：`["habit_complete", habit_id, check_date, occurrence_key]`。

timezone、local_time、remind_at、title、target amount、scheduler state 均不能进入 UUID 名称。C++ 是唯一 producer，Dart/Kotlin 只能 transport/compare。所有 canonical JSON、字符串编码、UUID 小写格式和字段顺序必须和 golden vector 完全一致。

### 7.2 template identity 与“每天最多一次展示”是两套约束

修改 `local_time` 会软删除旧 template 并创建新 `template_key`，因此 occurrence/reminder identity 会改变；但用户层面的每日展示配额仍是 `habit_id + occurrence_date`。必须同时检查：

- `ux_habit_reminder_identity` 保证模板内业务 tuple 唯一。
- `ux_habit_sent_display_per_day` 和 C++ transaction guard 保证跨历史 template 每天最多一个真实 sent display。
- prepared attempt 在换模板期间必须保守占用当日展示权，直到被原子确认 abandon；否则 prepare 后崩溃再换时间可能出现第二次通知。
- 同日 sent 后 disable/re-enable、改时间、clear CheckIn、重启、reconcile 均不能创建或展示第二条。
- 同日尚未 sent 且只是 pending/failed 时，更新模板后的旧链必须被正确取消，新链能否补发必须由当前事实和 Contract 决定，不能简单“凡有旧 row 就禁止”。
- 第二天必须生成新 occurrence；不能因为前一天的全局 guard 错误永久屏蔽后续提醒。

### 7.3 CheckIn 与 Reminder 的联动

- done/skipped 提交必须和当前/未来相关 Reminder cancellation 在一个 SQLite transaction 内完成。
- partial 保留当日提醒；但达到 target 后究竟是 done 还是 partial 必须由 C++ 统一裁定。
- clear 后只有当天仍合法、未 sent、未被 prepared 保守占用且提醒仍启用时才允许恢复；不能跨日恢复过期提醒。
- notification action 是 set-to-done，不是 increment；quantitative done 写当前 target snapshot，不能用 PendingIntent 里的旧目标数值。
- end/delete/update 与 Alarm 同时发生时，C++ current-fact 复核必须淘汰旧 Alarm，而不是依赖 Android cancel 恰好先执行。

### 7.4 时间、时区与 reconcile

- `local_time` 固定为精确 `HH:mm`，`timezone_mode=follow_device`；Reminder 保存的 UTC projection 可以变，但本地语义不能变。
- 时区改变、系统时间改变、重启、应用更新、精确闹钟权限改变、通知权限改变都必须进入同一 reconcile 体系，不得各写一套补偿规则。
- 当天提醒时间已过时，同日 catch-up 与次日失效边界必须采用半开区间，避免 00:00 重复归属。
- reconcile response 的 `examined/scheduled/cancelled/deferred/failed` 等计数必须守恒并回显 limit；`has_more=true` 时 cursor 必须正向推进。
- Kotlin 每次 wake 的 20 页/2000 条预算必须真实限制工作量；超过预算使用唯一 WorkManager continuation，不得在主线程无限循环。
- 重复 cursor、空 cursor、零进展且 `has_more=true`、页码倒退必须被识别为协议错误/安全中止，防止耗电死循环。
- 并发 reconcile 的旧页不得在新 mutation 后重新安排已取消 Alarm；schedule/cancel 必须携带可比较的 identity/CAS 信息。
- Habit 不能进入普通 72 小时 Recovery 聚合，`ReminderRecoveryBatch` 的所有 membership 字段都必须拒绝 Habit identity。

## 8. 两阶段投递、崩溃窗口与通知动作并发

### 8.1 prepare / display / finalize 顺序不能简化

正确顺序必须能够从代码控制流和持久化状态中证明：

```text
Alarm/Worker 到达
  → C++ 校验当前 Habit/template/date/occurrence/Reminder 状态
  → prepare：冻结 payload 与唯一 attempt，但不写 sent
  → Kotlin 使用冻结 payload 调用 NotificationManager
  → 展示成功后 finalize
  → 同一 transaction 写 Notification 审计、Reminder sent/fulfilled 与 successor
```

重点检查：

- prepare 重放返回同一 attempt/frozen payload，不生成新 delivery id。
- `NotificationManager.notify()` 抛错、权限拒绝或 channel 不可用时，不得 finalize 为 sent；失败原因和重试状态需可审计。
- finalize 重放幂等；同一 prepared attempt 只产生一个 Notification 审计和一个 successor。
- successor 的 date、identity、状态和本地时间来自当前 template 规则，但不能把当前编辑内容偷偷改入已冻结的历史 Notification payload。
- Notification tag/request code 应基于稳定 delivery/occurrence identity；不能使用当前时间、字符串 hash 冲突或自增内存计数。

### 8.2 必须推演的崩溃窗口

| 崩溃点 | 重启后的必要结果 | 常见错误 |
| --- | --- | --- |
| prepare 事务前 | 没有 attempt，可按当前事实重新处理 | 留下内存占位但数据库无记录 |
| prepare commit 后、notify 前 | 同一 attempt 可重试，不能创建第二 attempt | 把 prepared 当 sent，永远漏通知 |
| notify 成功后、finalize 前 | 保守避免第二次真实展示，并能收敛审计状态 | 重启后再次 notify，用户看到重复 |
| finalize 事务中 | SQLite 回滚到完整 prepared 或完整 sent，不得半个 Notification/半个 successor | 多 connection/分次写导致半提交 |
| finalize commit 后、Android 回调前 | 重放只读取既有 sent 事实 | 重复 successor 或重复 cancel |
| action transaction 中 | 要么完整 CheckIn+cancel，要么零写 | CheckIn 成功但 Reminder 仍 active |

仅用异常 mock 不能证明进程崩溃安全；Storage transaction 测试至少要在真实 SQLite 上注入各步故障，并有进程级/重开数据库验证。

### 8.3 通知快捷完成安全检查

- Receiver 必须 `exported=false`；PendingIntent 必须 immutable，并使用显式 component/package。
- extras 只能作为 untrusted request；C++ 必须复核 `habit_id + check_date + occurrence_key + action_id`、当前 device-local date 和当前生命周期。
- 动作只允许 set-to-done；重复点击、并发点击、旧通知点击必须幂等，不得累加数量。
- ended/completed/deleted、非 today、identity 不匹配、模板已替换或 Reminder 已 abandon 时必须零写失败。
- action 与手工 CheckIn、clear、end、delete、finalize、reconcile 并发时，数据库唯一约束和业务 transaction 必须给出确定结果。
- 成功后只取消对应 notification tag；不得 `cancelAll()` 误删 Event/Anniversary/Ring 通知。
- Receiver/Worker 不能启动 Flutter Engine；Flutter 下次 resume/冷启动必须从真实 detail/list 重新读取，避免页面保留动作前缓存。

## 9. SQLite v5、codec 与迁移安全

### 9.1 v5 拓扑必须精确，不接受“等价 SQL”猜测

逐项对照 `contracts/storage/calendar_core_storage.yaml`：

- 继承 v4 的 16 张表、16 个索引、row bytes、position、generation、legacy compatibility row 和 migration history 必须保持规定语义；迁移不得 rebuild-and-copy 或重写旧 payload。
- 新增恰好四张表：`habit_recurrences`、`habits`、`habit_check_ins`、`habit_reminder_templates`。
- 新增恰好八个索引，包括 recurrence owner、CheckIn logical identity、active template、Habit Reminder identity、同日 sent display guard 和三类查询索引。
- 总数、表名、normalized CREATE SQL、partial-index predicate、`WITHOUT ROWID`、JSON path、CAST、collation 与顺序必须通过同一 canonical checker；同名但 SQL 不同必须判腐坏。
- 不允许用 `IF NOT EXISTS` 掩盖已有错误对象；不能因为 SQLite 能打开就认为 schema 合法。

### 9.2 v4 → v5 只能是一个相邻原子迁移

必须白盒检查完整顺序：

1. 获取既有进程 lease 和数据库 recursive mutex。
2. 在任何写入前运行冻结的完整 v4 checker。
3. `BEGIN IMMEDIATE` 后在 writer lock 下复核 `user_version` 与 metadata。
4. 创建四表、八索引；插入四个零 generation 和完整 per-store codec metadata。
5. 更新 storage format metadata 与 `PRAGMA user_version=5`。
6. 用注入 Clock 追加恰好一条 migration history。
7. commit 前运行完整 v5 schema/metadata/history/relation/row-codec/quick_check。
8. 只 commit 一次，成功后才向 runtime 报 initialization 成功。

任一步失败或进程终止，重开只能得到完整合法 v4 或完整合法 v5。不能存在 v4.5、重复 history、四表只有一部分或 generation 丢失。

### 9.3 codec 版本与旧数据兼容

- v5 每个 Store 使用自己的 `payload_codec_version.*`；不得用遗留全局 `record_payload_version=3` 解码 Habit，或把 Reminder/Notification v4 当 v3。
- 缺失/未知 per-store key 必须 `STORAGE_DATA_CORRUPTED`，不能自动补默认版本后继续写。
- Habit v1 payload exact fields、nullable fields、canonical UUID、date/time、Unicode 长度和分支不变量必须在打开数据库与提交前都校验。
- Reminder v4/Notification v4 的 Habit branch 必须严格，Event/Anniversary-only 字段对 Habit 为 null，Habit-only 字段对其他 target 非法。
- fresh v5、fresh v4→v5、JSON v1/v2/v3→v4→v5 的合法 history prefix/suffix 都要验证；禁止从旧 JSON 直接发明一条 v5 捷径。
- 旧 runtime 打开 v5 必须拒绝且零写；rollback 只能通过外部备份和明确用户授权，不能偷偷把 v5 导出成旧格式覆盖。

### 9.4 关系与事务不变量

- 每个非删除 Habit 恰好拥有一个合法非删除 recurrence，且不能共享 recurrence。
- CheckIn（含 tombstone）必须引用历史存在的 Habit，日期位于该 Habit 历史有效挑战区间；删除 Habit 不删除 CheckIn。
- 每个非删除 Template 引用非删除 Habit，且一个 Habit 最多一个 active template。
- Habit Reminder tuple、occurrence/reminder UUIDv5 和同日展示配额必须在打开数据库和 transaction commit 前校验。
- create+first Reminder、CheckIn+cancel、clear+conditional restore、end/delete+cancel、action+CheckIn、finalize+successor 必须共用同一 connection/transaction。
- 幂等 replay 若没有状态变化，不得无意义增加 store generation；否则 cursor/cache 会把重复请求误判为新快照。
- Category 是弱引用；删除 Category 后 Habit 的 `category_id` 处理必须与现有弱引用政策一致，不能借 Habit 引入 SQLite FK。

### 9.5 存储测试必须使用真实 SQLite

至少覆盖：

- fresh v5 创建与 reopen；
- 合法 v4 带真实旧数据迁移，旧 payload byte-for-byte/语义保持；
- v4 schema、index、metadata、history、generation、row JSON 各类损坏在写前失败；
- 四表/八索引任一缺失或定义漂移；
- 每个迁移步骤和 commit 前后故障注入；
- 两个 runtime/两个线程争抢同一路径；
- nested transaction、异常 rollback、reopen 后 generation 与 relation 一致；
- 同日跨 template 并发插入 sent 的唯一约束；
- 最大 hundredths、Unicode 上限、tombstone revive round-trip；
- 磁盘满、只读目录、锁超时、corrupt database、旧 runtime 拒绝 v5。

## 10. C++ Core 白盒重点

重点入口包括但不限于：

- `cpp_core/include/excellent_calendar/domain/habit.hpp` 与 `cpp_core/src/domain/habit.cpp`
- `cpp_core/include/excellent_calendar/application/habit_service.hpp` 与 `cpp_core/src/application/habit_service.cpp`
- `cpp_core/include/excellent_calendar/repository/habit_transaction.hpp`
- `cpp_core/include/excellent_calendar/boundary/contract/habit_json.hpp` 与对应实现
- `cpp_core/include/excellent_calendar/boundary/api/habit_api.hpp`、`cpp_core/src/boundary/api/habit_v2_endpoint.cpp`
- `cpp_core/include/excellent_calendar/storage/json/habit_json_codec.hpp`、`habit_state_validator.hpp` 与对应实现
- `cpp_core/include/excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp`、`sqlite_repository_adapters.hpp` 与对应实现
- 共享 Reminder/Notification delivery、reconcile、recovery workflow 及其 transaction adapter
- CMake source/test registration 和 Habit/Storage v5 测试

需要重点寻找的实现味道与错误：

- 一个超大 `HabitService` 同时做 JSON parsing、领域判断、SQL、时区、统计和提醒副作用，导致事务边界无法证明。
- Boundary 只校验 Schema 表面，Domain constructor 可以被测试或其他入口绕过并创建非法对象。
- `now/today/timezone` 直接调用系统全局函数，测试无法稳定控制，或一次请求中多次读时钟跨过午夜。
- 使用 `size_t/int/double` 承载 Contract `int64`，或累加前未做 checked overflow。
- 日期计算用秒数除以 86400，DST 日产生偏移。
- list/detail/statistics 多次独立读取数据库，不能保证 snapshot consistency。
- tombstone revive 走 remove+insert，改变 id、created_at、position 或 generation。
- 异常转成空列表/默认 detail，丢失 `NativeError` 的 code/message/details。
- prepare/finalize/notification action 通过 Repository 单方法拼接多个 transaction，表面封装但物理不原子。
- runtime 初始化次序允许 Boundary 在 v5 migration/check 完成前被 JNI 调用。
- 头文件声明和 `.cpp` 已存在但 CMake 没有编译；测试链接到旧 build 目录仍绿。
- 同一 SQLite connection 被多个线程无序使用，或 callback 捕获已经释放的 runtime/service。

Review 不能只看 happy-path API；必须从每个 public Boundary 反向确认所有返回分支都有确定错误映射和 transaction outcome，并检查所有 private helper 是否被其他入口绕开。

## 11. Kotlin / Android 白盒重点

重点入口包括：

- `HabitMethodHandler.kt`、`HabitMutationOrchestrator.kt`、`HabitContracts.kt`
- `NativeHabitBridge.kt`、`JniHabitBridge.kt`、生产 Native bridge factory/runtime composition
- `HabitReminderReconciler.kt`、共享 Reminder schedule/delivery/recovery 组件
- `HabitNotificationActionReceiver.kt`、相关 Worker/Alarm receiver/notification display
- `AppearanceMethodHandler.kt`、`AppearanceContracts.kt`、`AppearancePreferencesStore.kt`
- `flutter_client/android/app/src/main/cpp/boundary/adapter/jni/habit_jni.cpp`
- `MainActivity`、Native MethodChannel 总 Handler、Manifest、CMake/Gradle source set

### 11.1 JNI 11 条 internal call 必须逐条做 ABI 核对

- Kotlin external 方法名、参数、返回类型与 C++ JNI export/mangled name 完全一致。
- 每条 native call 都进入 CMake 并存在于 release `.so` 的 arm64-v8a、armeabi-v7a、x86_64 目标 ABI；不能只验证宿主或一个 ABI。
- hundredths 使用 `Long`/JSON integer，不经过 `Double`、`Number.toDouble()` 或 `JSONObject.getDouble()`。
- UTF-8/UTF-16 转换、null、空串、异常、超长 JSON 和 C++ error envelope 不丢字段。
- JNI 抛异常、返回 null、返回非法 UTF-8/JSON 或 native runtime 未初始化时，Handler 只能完成一次 `result`，且不会卡住 Flutter future。
- JNI 调用不在 Android 主线程做数据库/迁移/大范围统计；executor 取消、Activity 销毁和 callback 回主线程的生命周期安全。

### 11.2 mutation orchestration 最容易出现“提交成功但响应旧”

- C++ commit 成功后，再执行 schedule reconciliation；调度失败不能 rollback Habit 数据。
- Kotlin 拼装 public response 时，`schedule_capability` 与 detail 内 `reminder_settings.schedule_reconciliation_required` 必须来自同一最终协调结果。
- 精确调度、近似调度、权限拒绝、通知权限拒绝、系统异常、无 Reminder 的各分支都要有确定 capability 和用户可重试状态。
- C++ commit 失败时绝不能调度；Kotlin schedule 成功但 response delivery 失败时，下次查询仍能读取真实已提交状态。
- 同一 mutation 被 UI 连点或 MethodChannel 重试时，native idempotency 与 Android schedule identity 共同防重复。

### 11.3 Alarm、Worker、Receiver 的安全与并发

- action Receiver 非导出、显式、immutable；不接受普通 implicit broadcast 伪造。
- Alarm/Worker 到达后必须先调 C++ prepare/current-fact 校验，再调用 NotificationManager。
- WorkManager 名称、ExistingWorkPolicy、backoff 和 continuation cursor 稳定；重启不会并行启动无限 reconcile。
- 20 页/2000 条预算、重复 cursor、失败重试与电量限制在实现中真实存在，不是测试假对象口头保证。
- 取消只按稳定 tag/identity 操作，不误删 Event、Anniversary、Ring 或其他 Habit 日期通知。
- boot/timezone/time/package replace/permission change 的入口不会漏注册，也不会在 migration/runtime ready 前开始 reconcile。
- receiver/worker 获得 runtime 的生命周期与进程单例一致；不能每次新建第二个 SQLite connection 或在销毁后继续回调。

### 11.4 Appearance 必须保持本地、独立和严格

- 只使用应用私有 SharedPreferences/等价本地存储，不借 Auth/Profile/cloud sync。
- 写入应原子更新完整合法状态；进程重启、Activity 重建、暗色模式/语言切换后可恢复。
- 未知 enum/token、损坏值、缺字段的 fallback/错误行为与 Contract 一致，不能静默把损坏写回默认值。
- Appearance 初始化不能阻塞 Habit runtime，也不能因 Habit 初始化失败覆盖已有外观偏好。

## 12. Flutter / Dart 白盒重点

重点入口包括：

- `flutter_client/lib/native_contract/habit/**`
- `flutter_client/lib/gateway_interfaces/habit_gateway.dart`
- `flutter_client/lib/boundary_adapters/dart_method_channel/method_channel_habit_adapter.dart`
- `flutter_client/lib/application/habit/**`
- `flutter_client/lib/presentation/habit/**`
- Appearance gateway/adapter/controller/page
- `flutter_client/lib/main.dart`、生产 composition、路由和 notification tap router

### 12.1 typed boundary 与表单转换

- raw Map 只能存在于 MethodChannel adapter/mapper 边界；Controller/Page 必须消费强类型 DTO/domain projection。
- mapper 对 required/null/unknown enum/additional field/互斥分支严格失败，不能通过 `as num` 后随意 `toInt()` 截断小数。
- 用户十进制输入采用字符串词法转换 hundredths，覆盖小数位、前导零、中文输入法、粘贴、最大值和 overflow。
- 文本计数按 Unicode code point；输入组件显示的剩余字数与 native 最终限制一致。
- UI 校验只是即时反馈；错误仍要展示来自 native 的权威 error，不得假定“前端已经挡住”。

### 12.2 Controller 的异步竞态

- list/detail/day/form 都要有 request generation 或等价 stale-response guard；旧请求不能覆盖新筛选、新分页或 mutation 后结果。
- `dispose` 后 future 完成不能 `setState`/notify；页面切换和 notification tap 冷启动不产生悬挂 callback。
- create/update/end/delete/check-in/clear/skip/set reminder 有明确 mutation lock；双击、返回键、旋转和网络/Native 慢响应不重复提交。
- 乐观 UI 如存在，必须有 token/版本，失败只回滚自己的变更，不能覆盖随后成功的新 mutation。
- 分页 cursor 必须防重复页、重复 item、零进展和 stale generation；刷新清除旧 cursor，不把不同 filter 的页拼在一起。
- background notification action 后 resume/重新进入 detail 必须拉取 native 事实；内存 cache 不得长期显示未完成。

### 12.3 UI 不得重新计算业务事实

- list 顶部今日 X/Y 直接显示 `HabitListResponse.today_progress`，不数当前 page，也不跟 filter 变化。
- card 的 completion rate、current streak、daily status、详情统计都使用 C++ projection；Dart 不遍历历史重算。
- 生命周期按钮由 native response/lifecycle projection 驱动，不能只靠当前手机日期猜 completed/active。
- deleted、not found、contract incompatible、storage corrupted、permission blocked、schedule degraded 是不同状态；不能都落入空白页或“未找到”。
- 跳过今天、完成、部分打卡、clear 的按钮与表单必须发送准确 status/value；binary/quantitative 分支不能共用不完整 payload。

### 12.4 生产 composition、路由和可用性

- `main.dart`/production composition 只创建真实 MethodChannel HabitGateway；测试 Fake 只能从测试注入。
- release 构建不得包含 `main_habit_preview.dart` 或 seed route；失败时显示真实初始化错误，不自动切内存模式。
- notification tap 在冷启动、热启动、后台、重复事件下只导航一次；Habit 已删除时显示稳定 deleted state，不转成 Event detail。
- 小屏、横竖屏、字体放大、深色主题、中文长标题、数量最大显示不溢出。
- card/button/progress ring 有可访问性标签；圆环视觉表达完成率时，中心连续天数的语义不能让读屏误认为同一个数值。
- 大量 Habit/400 天历史时，build 中不做 O(N×days) 重算；列表滚动、分页和详情图表不阻塞 UI isolate。

## 13. 共享功能回归边界

Habit 扩展了共享 Reminder、Notification、SQLite、JNI runtime 和 Flutter composition，因此以下既有能力必须做定向回归，不能以“未改业务代码”为理由跳过：

- Event popup Reminder：创建、更新、取消、一次性/重复、Dispatcher Alarm、prepare/finalize。
- Event Ring：前后台、全屏/通知、停止、snooze、Service 生命周期和 channel。
- Anniversary Reminder：template、occurrence、时区变化、catch-up、聚合投递、notification tap。
- 普通 72 小时 Recovery：20 条上限、batch membership、聚合 Notification、replay；确认 Habit 永不进入 batch。
- Reminder snooze、Notification audit、共享 enum/error/codec 的所有 target-specific 分支。
- Category 创建/排序/删除与 Habit 弱引用；不能因为 Habit 增加 SQL index 或 validator 破坏现有 Category exhaustion 行为。
- SQLite v1/v2/v3→v4 的既有迁移，再串接 v4→v5；不能只测 fresh v5。
- Auth/Profile/Appearance 启动顺序和本地数据库路径；Habit runtime 初始化失败不能误清用户 session。
- 现有 notification tap 的 Event/Anniversary 分流；新增 Habit case 不能用宽泛 default 抢走其他 target。
- C++ runtime shared ownership、JNI initialization/reinitialization 和所有既有 capability registry。

若项目仍有已知但未归属 Habit 的历史问题，报告必须明确“本次引入/本次暴露/既有问题”，避免把既有债务误算为 Habit 回归，也不能借“既有”忽略被本次改动放大的风险。

## 14. 独立测试 Oracle 与高价值用例矩阵

独立测试期望必须从 Contract、领域不变量、生命周期矩阵和计划冻结，不得调用生产 identity helper、日期 helper、streak helper 或 serializer 来生成 expected。否则实现和测试会一起错。

### 14.1 Contract 与跨语言映射矩阵

- 10 个 public Habit 方法、2 个 Appearance 方法、11 个 native calls 全部 success/failure envelope。
- required 缺失、required 为 null、nullable 缺失、额外字段、未知 enum、错误 target branch。
- hundredths：`1/99/100/125/9007199254740990/9007199254740991` 精确 round-trip；小数/指数/overflow 拒绝。
- Unicode：ASCII、中文、emoji、组合序列在上限/上限+1。
- identity：三个 Habit UUIDv5 golden vector，以及相邻日期、换 template key、不相关字段变化。
- Kotlin commit response → public response 的 capability/details 一致性。
- Dart/Kotlin/C++ 分别读取同一 fixture，再串真实 MethodChannel/JNI 读取同一 fixture。

### 14.2 日期、生命周期与统计矩阵

- start=today、end=today、today=end+1、upcoming、active、completed、ended、deleted。
- 400/401 天；普通年/闰年；跨 DST；Asia/Shanghai 与有 DST 的 IANA zone。
- 生命周期矩阵每个 operation×state 单元格的精确 success/error code/zero-write。
- binary/quantity × done/partial/skipped/absent/missed × clear/revive。
- 修改 target/unit 前后历史 snapshot；first_check_in_at 永久锁定。
- skipped bridge、昨日 partial、昨日 absent、今天 partial/absent 对 current/longest streak。
- 7/30/all 的窗口首尾、分母为零、round-half-up、累计 overflow。
- today progress 守恒、分页/筛选不变、并发 mutation 前后 snapshot 一致。

### 14.3 Reminder 与并发矩阵

- create with reminder、create without reminder、enable/disable/re-enable、改 local time。
- 当日提醒前/正好/已过；当天完成/partial/skipped/clear；次日边界。
- 同日 sent 后换 template；prepared 后换 template；failed 后换 template；pending 后 disable。
- Alarm vs update/end/delete/check-in/clear/finalize/reconcile 的两两竞态。
- action vs manual check-in、重复 action、过期 action、伪造 extras、旧 occurrence。
- prepare/finalize 重放、notify 抛错、权限拒绝、进程在每个窗口被终止。
- timezone/time/reboot/app update/permission change 触发 reconcile。
- cursor 正常推进、重复、空、倒退、零进展、预算耗尽和 continuation 唯一性。
- 同一 Habit/date 跨两个 template、两个线程、两个 wake 竞争，最终最多一个真实 sent display。

### 14.4 Storage 与恢复矩阵

- fresh v5、合法 v4→v5、各旧 JSON 合法链到 v5。
- v4 每一类 schema/metadata/history/generation/row 损坏均在零写状态失败。
- 每个迁移步骤故障注入与 process reopen，只得到完整 v4 或完整 v5。
- 四表/八索引 exact checker；同名不同 SQL、partial predicate/collation/JSON path 漂移。
- transaction 中每个 Store 写失败、commit 失败、nested transaction、并发 connection。
- old runtime 拒绝 v5；backup/restore 只在隔离测试数据执行。

### 14.5 Flutter、APK 与真实设备矩阵

- widget：loading/empty/error/data、binary/quantity、upcoming/active/completed/ended/deleted、schedule exact/approx/pending。
- controller：快速换筛选、快速翻页、退出页面、双击 mutation、旧响应晚到、后台 action 后 resume。
- production composition 静态测试：`lib/**`/`src/main/**` 无 Fake/preview import 或 fallback。
- Debug 与 release-like APK 都加载真实 `.so`，11/11 Habit JNI 在目标 ABI 可见。
- 真机：通知允许/拒绝/恢复、精确闹钟允许/拒绝、前台/后台/强杀/重启、当天补发/跨日过期、通知快捷完成、改时区/系统时间。
- 真实设备测试必须使用隔离应用数据或专用测试 profile，不清理用户真实数据；未执行的设备组合必须明确标成未验证，不能从 Robolectric/host test 推断通过。

## 15. 测试本身的高频失真模式

| 失真模式 | 为什么危险 | Review 要求 |
| --- | --- | --- |
| expected 调生产 helper | identity、日期和统计实现错时测试一起错 | 用 Contract golden 或独立小 oracle |
| 只测 Fake | Handler/UI 很完整但真实 JNI/SQLite 不可用 | 至少一条真实 APK 全链 smoke |
| 只测 Service | 绕过 Boundary strict parsing、JNI、线程和 composition | 从公开入口追加 black-box/bridge test |
| 只测 in-memory repository | 无法证明 SQLite index、事务、migration 和 crash | 真实临时 SQLite + reopen |
| 并发测试按顺序调用 | 没有真正形成竞态窗口 | barrier/latch/故障注入控制交错 |
| 崩溃只抛异常 | exception unwinding 不等于进程被杀 | 子进程/重开数据库验证 |
| 只断言列表长度 | 重复 item、排序、cursor、today_progress 错误仍通过 | 断言完整 identity、顺序、守恒与快照 |
| Widget 只 `pump()` | 没点按钮、没等待异步、没断言 outgoing request | 驱动真实交互并检查 gateway call/result state |
| 只测小数值/ASCII | 最大定点数和 Unicode 跨语言 bug 被隐藏 | 固定最大相邻值和代理对样例 |
| 只测同一个 template | 漏掉“换时间后同日第二次通知” | 跨 template/date 的展示配额矩阵 |
| 测试清真实数据库 | Review 造成不可逆用户损失 | 临时目录、测试 app id、可审计隔离 |
| 为通过测试修改 oracle | 实现缺陷被重新定义成正确 | 任何 oracle 变化必须回到真相源说明 |

## 16. 现实开发中最容易混淆的速查表

| 容易混淆的两件事 | 正确区分 | 典型错误后果 |
| --- | --- | --- |
| Habit 与 HabitCheckIn | 配置/生命周期 vs 某日本地事实 | 清打卡时误改 Habit；历史不可审计 |
| CheckIn 缺失与 `missed` | 缺失是存储事实，missed 是历史派生展示 | 预生成大量 missed、未来日错误 |
| clear 与 delete | CheckIn tombstone/revive vs Habit soft delete | id/created_at 变化或整段历史消失 |
| completed 与 ended | 自然超过 end date vs 用户提前结束 | 最终日错误关闭、可操作矩阵混乱 |
| done 与 partial 达标 | 业务 status 与用户数值输入 | streak/提醒取消和统计分叉 |
| skipped 与 done | 跳过不进 eligible 分母且桥接 streak | 今日 X/Y、完成率虚高 |
| current target 与 snapshot | 新配置 vs 历史打卡当时目标 | 修改目标后历史统计被改写 |
| `template_key` 与每日展示 key | 配置链 identity vs `habit_id+date` 用户配额 | 换时间后同日双通知 |
| occurrence id 与 reminder id | 业务发生 identity vs 可调度实体 identity | PendingIntent/CAS/审计串错 |
| prepared 与 sent | 已冻结尝试 vs 已真实展示并 finalize | 漏通知或重复通知 |
| 保存成功与调度成功 | 业务 commit vs 系统副作用 | 权限失败导致用户配置丢失 |
| pending 与 failed | 等待对账/能力 vs 已尝试失败 | 无限重试或永不重试 |
| 本地日期与 UTC instant | 每日语义 vs 调度投影 | DST/时区变化错日 |
| 400 天与 400×24 小时 | local-date 闭区间长度 vs 秒数 | 跨 DST 少/多一天 |
| Unicode code point 与字符串 length | Contract 长度单位 vs UTF-8/UTF-16 实现单位 | 中英文/emoji 各层验收不一致 |
| hundredths int 与显示小数 | 精确 wire/storage vs UI 文本 | 浮点精度丢失 |
| list page summary 与全局 today progress | 当前页 items vs 同快照全局聚合 | X/Y 随翻页变化 |
| C++ commit response 与 public response | 逻辑提交结果 vs 加上 Android 调度结果 | 嵌套状态互相矛盾 |
| Scheduler state 与业务 truth | 可恢复副作用 vs 持久化配置 | AlarmManager 状态反写删除数据 |
| ordinary Recovery 与 Habit catch-up | 72h 聚合补偿 vs 同日每日提醒 | Habit 被跨日补发 |
| Fake layer complete 与产品完成 | 并行阶段证明 vs 单 APK 真实链 | 发布包仍走 Fake |
| build success 与注册成功 | 编译通过 vs symbol/source/manifest 真正接入 | 方法存在但运行时不可达 |

## 17. Review 输出与放行标准

最终 Review 报告必须先给 Findings，再给摘要。每条 Finding 至少包含：

- P0～P3 优先级；
- 精确文件与紧凑行号；
- 触发输入、状态、并发或崩溃窗口；
- 违反的 Contract/领域/计划条款；
- 可观察后果和数据影响；
- 建议的最小修复方向；
- 独立复现或测试证据；
- 是否为本次引入、既有问题或本次放大。

只有同时满足以下条件才可给出 `APPROVED`：

1. 本文发布红线全部关闭，未解决 P0/P1 为零。
2. 10 个 public Habit、2 个 Appearance、11 个 native call 和后台提醒/动作链全部真实闭环。
3. Contract validators、identity vectors、storage v5 checker/fixtures 全部通过，且没有用默认/兼容分支掩盖失败。
4. C++ 使用构建后测试目标，不运行陈旧二进制：

   ```text
   cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
   cmake --build cpp_core/build-ninja --target excellent_calendar_check
   ```

5. Kotlin 单元/集成、lint、APK、androidTest 构建通过；三个目标 ABI 的 11 个 Habit JNI 符号和真实 runtime handshake 通过。
6. Flutter format/analyze、相关与全量测试、Debug APK 通过；production composition 无 Fake/preview/seed/fallback。
7. SQLite fresh/migration/corruption/crash/concurrency/reopen 真实测试通过，且未触碰用户数据。
8. Event、Anniversary、Recovery、Ring、Category、notification tap 和旧 migration 定向回归通过。
9. 必要真机矩阵实际执行。无法执行的项必须列为**未验证**并说明风险接受人；不得用 host/Robolectric/smoke 推断真机通过。
10. `method_channels.yaml`、`native_calls.yaml`、`identity.yaml` 的 Habit capability 仅在以上激活门禁满足后改为与真实状态一致。

允许的结论只有：

- `APPROVED`：无未解决 P0/P1，真实链与必要验证完整。
- `APPROVED WITH RESIDUAL RISK`：仅存在明确、可接受、有人负责的 P2/P3 或设备矩阵债务，且不涉及数据、重复通知、Fake 生产链或协议造假。
- `CHANGES REQUIRED`：存在任何 P0/P1、真实链未闭合、迁移/事务/身份无法证明、必要验证失败，或 capability 状态早于事实。

本计划执行完成后，应把实际 Findings、验证证据、未验证设备矩阵和最终结论写入同一 Review 文档或配套报告；完成并关闭全部阻断项后，再将文档从 `docs/reviews/active/` 移入 `docs/reviews/archive/`。
