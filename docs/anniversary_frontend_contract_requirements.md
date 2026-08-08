# 倒数纪念日前端原型：下层能力需求

> 状态：Flutter Fake 原型已预留接口；本文不是已发布 Contract，也不表示 Kotlin、JNI、C++、存储、农历或通知能力已实现。

## 1. 当前协议现状

- `contracts/method_channels.yaml` 当前只有 `anniversary.create`。
- `contracts/native_calls.yaml` 当前没有 Anniversary 的 Kotlin → JNI → C++ 调用。
- 仓库已有创建请求、Anniversary response 和分页 list response schema，但没有与 Flutter 列表、详情、更新、删除和倒数预览对应的完整方法声明。
- `docs/DATA_MODEL.md` 的 `Anniversary` 包含 `id/title/date/calendarType/categoryId/recurrenceId/note/importance/createdAt/updatedAt/deletedAt`，没有稳定表达 `kind` 或 `count_mode` 的领域字段。
- Habit/Anniversary 的重复语义仍处于计划态，不能直接复用 Event Native Contract v2 的 occurrence 锚点或滚动 Reminder 规则。

本次 Flutter 原型没有增加 MethodChannel 调用，也没有修改上述 Contract。

## 2. Flutter 已预留的 Port

`AnniversaryGateway` 提供以下类型安全能力：

1. `list(AnniversaryListQuery)`
2. `getById(String id)`
3. `create(CreateAnniversaryPlan)`
4. `update(UpdateAnniversaryPlan)`
5. `delete(String id)`
6. `previewCountdown(AnniversaryDraft)`

`AnniversaryShareGateway` 提供：

7. `share(AnniversarySharePayload)`

`AppClock` 提供可替换的当前时间。Fake 模式固定为本地日期 `2026-08-06`，正式实现不得让 Widget 在 `build()` 中读取 `DateTime.now()`。

## 3. 未来至少需要声明的跨层能力

建议在正式实现时先完成 Contract 评审，再同步实现各层：

| 建议方法 | 目的 | 最低返回内容 |
| --- | --- | --- |
| `anniversary.list` | 按类型、删除状态和分页查询列表 | Anniversary 基本字段与 Countdown snapshot |
| `anniversary.detail` | 按 ID 读取详情 | Anniversary、展示语义、Recurrence 摘要、Reminder 摘要 |
| `anniversary.create` | 原子创建纪念日计划 | 创建后的完整详情 |
| `anniversary.update` | 原子更新纪念日计划 | 更新后的完整详情 |
| `anniversary.delete` | 软删除纪念日并处理关联任务 | 删除后的实体或稳定 operation response |
| `anniversary.preview_countdown` | 在保存前预览倒数结果 | Countdown snapshot |

如果 list/detail response 已稳定返回 `countdown`，仍建议保留预览能力，以支持新建表单尚未持久化的数据。

## 4. 创建与更新的事务边界

Flutter 的 `CreateAnniversaryPlan` / `UpdateAnniversaryPlan` 分开携带：

- Anniversary draft；
- Anniversary 专用 Recurrence draft；
- 多条 Reminder draft；
- 当前仅供 Flutter 原型展示的 kind。

`Reminder` 必须继续作为独立实体，不能向 `Anniversary` 增加 `remind_at`、`advance_minutes`、`reminder_methods` 或 `is_reminder_enabled`。

正式接入时应由 Application / C++ workflow 在一个事务中创建或更新 Anniversary、Recurrence 和 Reminder。不要让 Flutter 先创建 Anniversary、再逐条创建 Reminder，否则中途失败会产生部分提交。

未来还需要明确 Anniversary 对应 Reminder 的：

- 创建和批量替换；
- 查询；
- 修改；
- 取消；
- Anniversary 更新、删除与恢复时的关联状态变化；
- 多提醒失败时的原子性与重试语义。

## 5. 建议新增或确认的展示语义

当前前端 projection 使用：

`AnniversaryKind`

- `anniversary`
- `countdown`
- `birthday`
- `holiday`

`AnniversaryCountMode`

- `auto`
- `countdown`
- `countup`

`CountdownRelation`

- `remaining`
- `elapsed`
- `today`
- `unavailable`

`AnniversaryKind` 和 `AnniversaryCountMode` 尚未进入当前 Data Model/Contract。本次只保留在 Flutter Application/Presentation projection 中；正式增加前需要决定它们是持久化领域事实、查询参数，还是 Query Engine 派生字段。

## 6. 建议的 AnniversarySummaryResponse

未来列表/详情的 summary 至少需要返回：

- Anniversary 基本字段；
- `kind`；
- `count_mode`；
- `countdown`：
  - `relation`
  - `days`
  - `target_occurrence_date`
  - `weekday`
  - `calculated_at`

跨层字段必须使用 `snake_case`。其中：

- `Anniversary.date` 和 `target_occurrence_date` 是用户本地 `date`，不得转换为 UTC 午夜；
- `calculated_at` 是精确时间点，应使用 ISO 8601 UTC；
- `days` 在 `unavailable` 时应为 `null`；
- `weekday` 应明确格式或改为稳定的 ISO weekday 数值，避免多语言文案进入领域层。

## 7. 倒数计算与历法能力

正式下层需要统一负责：

- 公历日期的 count-up / countdown；
- 农历日期到目标公历 occurrence 的换算；
- 年度 recurrence 的下一次 occurrence；
- 2 月 29 日等闰年边界；
- 用户时区变化和本地日期边界；
- `today` 的判定；
- 软删除和不可用数据的返回语义。

Flutter UI 不应正式计算农历、下一次年度 occurrence、闰年或跨时区规则。当前 Fake 只对公历做简单日期差；新建农历数据明确返回 `unavailable`。五条参考种子数据中的“春节 184 天”是固定 UI fixture，不代表农历引擎已经实现。

## 8. 错误映射

当前已有并需要正式 adapter 映射的稳定错误码：

- `ANNIVERSARY_TITLE_EMPTY`
- `ANNIVERSARY_DATE_INVALID`
- `ANNIVERSARY_NOT_FOUND`
- `CONTRACT_VALIDATION_FAILED`
- `NATIVE_INTERNAL_ERROR`

Flutter Presentation 只显示 Application 映射后的中文错误，不直接展示 Native 英文 message，也不根据自由文本决定业务行为。

## 9. 正式接入时的最小验收

1. 先更新 `method_channels.yaml`、`native_calls.yaml`、相关 schema、enum、error code 和版本说明。
2. 同步实现 Dart DTO/adapter、Kotlin validator/bridge、JNI、C++ Boundary/Workflow/Repository。
3. 验证未知 enum、缺失字段、非法版本、malformed response 和 date/datetime 边界会显式失败。
4. 验证 Anniversary、Recurrence、Reminder 的创建/更新/删除为完整事务。
5. 覆盖公历、农历、年度重复、闰年、时区/本地日期边界和真实 Android 链路。

