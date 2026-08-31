# 习惯-02：Habit V1 Contracts 层开发计划

Status: Completed / Director Review Corrections Integrated / Downstream Capabilities Planned and Blocked

完成日期：2026-08-28

上位计划：`docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`

下游计划：

- `docs/plan/active/习惯-03-CPP层开发计划.md`
- `docs/plan/active/习惯-04-Kotlin层开发计划.md`
- `docs/plan/active/习惯-05-Flutter层开发计划.md`

## 1. 目标与完成边界

本计划负责在任何 Habit 生产代码开工前，冻结 Flutter ↔ Kotlin ↔ JNI/C++、Reminder/Notification 共享模型和 SQLite v5 目标格式。完成表示协议可验证、下游任务可执行；不表示 Habit 已有 C++、Kotlin、Flutter 或 SQLite v5 运行时实现。

本轮明确完成：

- Habit、HabitRecurrence、HabitCheckIn、HabitReminderTemplate 的领域边界；
- 10 个公开 Habit 方法、2 个 Kotlin-local Appearance 方法和 11 个内部 Habit call；
- request、response、聚合、mutation commit/platform capability 的分离 Schema；
- date-only、timezone、integer-hundredths、nullable、文本/分页上限、枚举、错误和乐观并发规则；
- Habit occurrence、Reminder、notification action 的 UUIDv5 identity；
- Habit Reminder/Notification target-specific 分支、跨 template 日级单展示、同日补发、跨日过期和 action 幂等；
- SQLite v5 的四表、八索引、per-store payload codec、v4→v5 原子迁移和 downgrade gate；
- 专项 validator、合法/非法/边界/兼容 fixture 与既有 Reminder 回归。

范围外：任何 `cpp_core/**`、`flutter_client/android/**`、Flutter/Dart 生产实现、构建工具升级、第三方依赖升级或 capability 激活。

## 2. 开工时发现并关闭的硬冲突

| 冲突 | 旧状态 | 冻结结果 |
| --- | --- | --- |
| Habit Reminder identity | `reminder_response` 把 Habit 当 ordinary target，要求 occurrence/template/date 为空 | 新增独立 `HabitReminder` 分支，三个身份字段必填 |
| CheckIn 重放 | 旧错误保留 `HABIT_CHECK_IN_DUPLICATED` | 冻结为 `(habit_id, check_date)` 幂等 set/upsert，删除 duplicated error |
| Recurrence | planned 通用规则混入 Event anchor/rrule | 使用 Habit 专属 `daily + interval=1 + follow_device` 输入和响应 |
| 日期判断 | 旧 request 无设备 timezone | 所有 date-sensitive Habit call 显式传当前 IANA timezone |
| Recovery | 未排除 Habit，会落入 72 小时/20 条/摘要 | `plan_recovery` 机器声明排除 Habit；新增独立、最多 100 条一事务的 cursor workflow |
| 通知 action | 无稳定 action identity，Dart/Kotlin 还拒绝 Habit occurrence key | 冻结 set-to-done payload、UUIDv5 action ID、当地日期和 tuple 校验 |
| 数量精度 | JSON decimal number 在上界会让相邻百分位经 IEEE-754 合并 | 所有数量 wire 改为 `_hundredths` JSON integer `0..9007199254740991`；UI 才格式化两位小数 |
| 每日单展示 | occurrence identity 包含 template_key，改时间可在当天生成第二个 occurrence | 增加 `(habit_id, occurrence_date)` 跨 template sent 唯一约束；sent/prepared 后新配置次日生效 |
| 首页 X/Y | list 只有分页 items，Flutter 无法得到全量完成数 | list 必填全局 `today_progress`，明确 done/partial/absent/skipped 分母语义 |
| 资源边界 | 文本、挑战期限、cursor 无上限 | 挑战最多 400 天；文本 80/2000/32/500；page 100、cursor 512 |
| 响应不变量 | tombstone 可进入 DailyStatus，detail 空历史/锁定字段不对称 | 活动 CheckIn 才可投影；空历史边界可空且成对；has-ever 与 latest-date 双向约束 |
| 生命周期 | upcoming/final-day/completed mutation 权限未冻结 | 新增机器矩阵，最终日不可 early-end，结束后除 delete 外只读 |
| Reconciliation | `has_more=true + processed=0` 合法，计数不能关联 request limit | 回显 limit、四类 outcome 精确求和、续页正进展；Kotlin 另有限页/重复 cursor 门禁 |
| Storage payload | 全局 `record_payload_version=3` 无法表达新 Habit 与新 Reminder 语义 | v5 增加 per-store codec；Habit Store 为 v1，Reminder/Notification 为 v4，其余继承版本 |
| 本机外观 | 无 Schema/方法/错误 | 冻结七个 token、两个 Kotlin-local 方法、默认 teal 与损坏诊断回退 |

## 3. 已冻结的领域与 ADR

- `docs/domains/habit.md`：闭区间挑战、生命周期、目标锁定、进度与精确数量。
- `docs/domains/habit_check_in.md`：逻辑唯一行、set/clear、动态 missed、统计与溢出。
- `docs/domains/habit_recurrence.md`：独占不可变 daily recurrence。
- `docs/domains/habit_reminder_template.md`：template replacement、同日 reconciliation 和 sent 去重。
- `contracts/habit/habit_lifecycle_operation_matrix.yaml`：生命周期 × mutation 的机器矩阵和确定性错误。
- `docs/architecture/decisions/ADR-Habit-01-Habit与HabitCheckIn分离.md`。
- `docs/architecture/decisions/ADR-Habit-02-每日挑战与Reminder-Occurrence工作流.md`。

关键不变量：

1. 挑战日期为包含首尾、最多 400 天的当地日期，内部可转半开区间，但不得把 date 当 UTC 午夜。
2. `target_count_hundredths/unit` 同空或同非空；第一次 CheckIn 后目标、单位和开始日永久锁定，clear 不解锁。
3. CheckIn tombstone 继续参与 `(habit_id, check_date)` 唯一性；重建复活同一 ID 和首次创建时间。
4. `missed/absent/upcoming` 只查询派生；持久化状态只有 `done/partial/skipped`。
5. local time 变化软删旧 template/chain，创建新 UUIDv4 template key；timezone 和 remind_at 不参与 occurrence 身份，但 `(habit_id, occurrence_date)` 跨 template 最多一次 sent 展示。
6. same-day catch-up 保持每条独立 popup；次日过期，不进入 ordinary recovery summary。
7. done/skipped 后 clear：从未 sent/prepared 可恢复同日 Reminder；已 sent/prepared 不二次展示。
8. action 是 set-to-done，不执行 `+1`；公开 Flutter request 不含 action source/identity，Kotlin 仅从非导出 Receiver 构造内部 command；错误日期、tuple、ended/deleted target 零写入。

## 4. 已冻结的机器协议

### 4.1 公开 MethodChannel

Habit：

- `habit.create`
- `habit.update`
- `habit.list`
- `habit.detail`
- `habit.end`
- `habit.delete`
- `habit.check_in`
- `habit.clear_check_in`
- `habit.list_daily_statuses`
- `habit.set_reminder`

Kotlin-local：

- `appearance.get_local`
- `appearance.update_local`

所有条目都保持 `implementation_status: planned`、`release_status: blocked`。

### 4.2 内部 Native calls

10 个公开 Habit 方法都有对应窄 C++ call；另有仅供 Kotlin 系统恢复入口使用的 `habit.reconcile_reminders`。`habit.check_in` 的公开 manual request 与 Kotlin→C++ command 使用不同 Schema，阻止 Flutter 注入 notification action identity；Appearance 不进入 JNI/C++。

Mutation 分两段：

```text
C++ logical commit
  → data_saved=true + schedule_reconciliation_required
  → Kotlin 尝试权限/Alarm side effect
  → 公开 capability 返回 exact / approximate / pending
```

业务数据已经 commit 后，权限拒绝或 Alarm 失败不得改写为 NativeResult 业务失败。

### 4.3 Schema 与共享 Reminder/Notification

- `contracts/habit/`：完整 input、fact response、daily/statistics/list/detail、全局 today progress、生命周期矩阵、commit/public mutation、reconciliation 和 action payload；detail 显式投影永久锁定事实，挑战区间外 `today=null`。
- `contracts/appearance/`：本机外观 get/update shape。
- `contracts/reminder/reminder_response.schema.json`：独立 Habit target branch。
- `contracts/reminder/prepare_delivery_response.schema.json`：Habit 必填 action，非 Habit 可继续省略。
- `contracts/notification/*`：Habit occurrence route、popup、prepared attempt 专属终结原因。
- `contracts/reminder/plan_recovery_*` 与 RecoveryBatch：显式排除 Habit。

### 4.4 Identity、错误与枚举

Identity canonical names：

```text
[habit_id, template_key, occurrence_date]
["habit", habit_id, template_key, occurrence_date]
["habit_complete", habit_id, check_date, occurrence_key]
```

四个固定测试向量覆盖同日 occurrence、次日 occurrence、Reminder 和 action。错误表删除 duplicated 语义，增加挑战过长、未开始、最终日非提前结束、日期、锁定、Reminder/action、reconciliation、统计溢出和本机外观错误；NativeError allow-list 同步。

## 5. SQLite v5 目标 Contract

`contracts/storage/calendar_core_storage.yaml#calendar_core_v5` 已冻结但未激活：

- 当前 active writer 仍是 v4；v5 为 `planned + blocked`。
- 使用冻结 `calendar_core_v4` 节点 SHA-256 和完整 v4 checker 作为零写入前置。
- 新表：`habit_recurrences`、`habits`、`habit_check_ins`、`habit_reminder_templates`。
- 新索引覆盖 recurrence 独占、CheckIn tombstone 唯一、单 active template、Habit Reminder tuple、跨 template 日级 sent 唯一、生命周期和日期范围查询。
- 新 Habit Store 使用 payload codec v1；共享 Reminder/Notification 因 Habit target 语义扩展使用 v4；其余 Store 保持原 codec。
- v4→v5 在单个 `BEGIN IMMEDIATE` transaction 内完成；原 v4 行、position、generation、history、compatibility table 和 JSON guard 不改写。
- 迁移中断后只能重开为完整 v4 或完整 v5；fresh v5 不伪造 Habit 数据。
- v4 runtime 看到 `user_version=5/storage_format_version=5` 必须拒写。

## 6. 兼容与激活策略

- Native v2 外壳不提升：旧 Habit 协议从未实现、未激活、无历史 writer 数据；这是首次实现前的 planned revision 修正。
- 已激活 Event/Anniversary Reminder branch 保持原 shape；非 Habit prepare response 继续允许省略 action 字段。
- 冻结 Contract 是三条实现轨唯一共同前置：C++、Kotlin 和 Flutter 可从同一基线并行开发；Kotlin/Flutter 通过 Contract-conformant Fake 独立运行，但不得据此宣称 production integrated。
- Habit 新旧组件不得混跑。并行开发结束后，C++、Kotlin/JNI、Dart/Flutter 和 Storage v5 仍必须在同一 APK 集成窗口切换。
- 运行时/预览 Fake 与种子数据必须在最终真实接线时删除；仅位于单元、Widget、instrumentation 的测试 Fake 和 canonical fixture 应保留为回归资产。
- Contract 冻结和 validator 通过不构成发布激活；只有真实代码、构建、测试、Native smoke 和设备门禁完成后才允许统一改为 `integrated + active`。

## 7. 验证结果

已执行：

```text
python contracts/run_habit_v1_validation.py
validated schemas=194 habit_fixtures=44 habit_identity_vectors=4 public_methods=12 native_calls=11 status=planned+blocked

python contracts/run_anniversary_r1_validation.py
validated schemas=194 fixtures=56 identity_vectors=20
```

专项 validator 覆盖：

- Draft 2020-12 metaschema、唯一 `$id` 和本地 `$ref` closure；
- request/response 正反例、integer-hundredths min/max/相邻上界/非整数/越界；
- 400 天、文本、分页/cursor 上限，全局 today progress 与 detail/DailyStatus 对称不变量；
- timezone、日期逆序、action 过期/identity mismatch；
- Habit Reminder branch、prepare action、Event legacy omission；
- Habit prepared attempt 跨日终结且无伪 RecoveryBatch，改时间/关闭重开遵守日级展示槽；
- lifecycle operation matrix 与 reconciliation 正进展、计数和 request limit；
- 方法/call、错误、枚举、capability 状态和 UUIDv5；
- v4 Contract hash、v5 表/索引、codec map、metadata 与 migration atomicity；
- 既有 Anniversary/Reminder 共享协议回归。

C++、Kotlin、Flutter 构建未执行：本计划没有修改这些层的代码，不能据此宣称生产功能可用。

## 8. 完成清单与下游交接

- [x] 领域文档、ADR 与统计公式冻结。
- [x] Habit/Appearance Schema 与聚合边界冻结。
- [x] 12 个公开方法与 11 个内部 call 冻结且保持 blocked。
- [x] errors、enums、identity 和 fixtures 完成。
- [x] Reminder/Notification/Recovery target 规则收口。
- [x] SQLite v5 target Contract 与 v4 不可变 gate 完成。
- [x] Habit validator 与共享 Reminder 回归通过。
- [x] 下游 C++、Kotlin、Flutter 实施计划建立。

交接拓扑冻结为：

```text
Contracts（本计划完成）
  ├─→ C++ Core + SQLite v5（真实实现，独立验收）
  ├─→ Kotlin/JNI + Android（Contract Fake 驱动，独立验收）
  └─→ Flutter Boundary/Application/UI（Contract Fake 驱动，独立验收）
          ↓ 三轨均为 Layer Complete / Awaiting Integration
      总工程真实接线、删除运行时 Fake、Native smoke、真机与 capability 激活
```

并行启动前还必须由总工程师把当前 Contract 状态固化为所有工作分支共同引用的基线提交（或等价不可变 revision），并在三份分计划交接记录中写明该 revision。当前工作树未提交时不得假定三个 worktree 自动拥有同一基线；这是一项执行准备，不代表 Contract 语义未完成。

任何下游发现字段、身份、迁移或状态冲突时，应先回到本计划和 validator 修订 Contract；不得在各语言里增加猜测兼容层。
