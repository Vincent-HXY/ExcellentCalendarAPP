# Anniversary Reminder / Occurrence Contract R1

Status: Frozen design / implementation blocked

Native envelope: v2

Calendar Core JSON target: v3 (`planned`, `blocked`)

本包冻结 Anniversary Reminder、date-only occurrence 查询、catch-up 聚合 delivery 与 Storage migration 的跨层真相源。Schema 冻结不表示生产能力已经接线；`method_channels.yaml` 与 `native_calls.yaml` 的受影响方法在三层实现和真实验收前保持 blocked。

## Stable schema IDs

| 能力 | Schema `$id` / 引用 |
| --- | --- |
| Reminder template input | `https://excellent-calendar.local/contracts/anniversary/anniversary_reminder_template_input.schema.json` |
| Reminder plan input | `https://excellent-calendar.local/contracts/anniversary/anniversary_reminder_plan_input.schema.json` → template input |
| Reminder template response | `https://excellent-calendar.local/contracts/anniversary/anniversary_reminder_template_response.schema.json` |
| Reminder settings response | `https://excellent-calendar.local/contracts/anniversary/anniversary_reminder_settings_response.schema.json` → template response |
| C++ detail aggregate | `https://excellent-calendar.local/contracts/anniversary/anniversary_detail_response.schema.json` → Anniversary / Recurrence / Countdown / Reminder settings |
| Public mutation result | `https://excellent-calendar.local/contracts/anniversary/anniversary_mutation_response.schema.json` → detail + schedule capability |
| Public detail result | `https://excellent-calendar.local/contracts/anniversary/anniversary_detail_view_response.schema.json` → detail + schedule capability |
| Occurrence query | `https://excellent-calendar.local/contracts/anniversary/list_anniversary_occurrences_request.schema.json` |
| Occurrence summary | `https://excellent-calendar.local/contracts/anniversary/anniversary_occurrence_summary_response.schema.json` |
| Occurrence page | `https://excellent-calendar.local/contracts/anniversary/anniversary_occurrence_list_response.schema.json` → summary |
| Toggle | `https://excellent-calendar.local/contracts/anniversary/set_anniversary_reminders_enabled_request.schema.json` |
| Delete commit/public result | `https://excellent-calendar.local/contracts/anniversary/anniversary_delete_commit_response.schema.json` / `anniversary_delete_operation_response.schema.json` |
| Reminder target branch | `https://excellent-calendar.local/contracts/reminder/reminder_response.schema.json` |
| Catch-up group | `https://excellent-calendar.local/contracts/reminder/anniversary_catch_up_group_response.schema.json` |
| Notification/tap | `https://excellent-calendar.local/contracts/notification/notification_response.schema.json` / `prepared_notification_payload.schema.json` / `notification_tap_payload.schema.json` |

## Missing / null / empty semantics

| Payload | Missing | Explicit `null` | Empty array / false |
| --- | --- | --- | --- |
| Create `reminder_plan` | 仅为旧 v2 writer 兼容：关闭且空模板 | 非法 | `templates=[]` 合法；`reminders_enabled=false` 不物化任务 |
| Update `reminder_plan` | 保留总开关与全部模板 | 非法 | `templates=[]` 删除全部模板；false + 非空模板表示暂停并保留 |
| Template `is_enabled` | 非法 | 非法 | false 保留模板但不物化任务 |
| Occurrence filters | 字段必须出现 | 非法 | 空数组表示不筛选 |
| Occurrence cursor | 字段必须出现 | 第一页 | 非空值必须满足 opaque cursor 格式并绑定原查询快照 |
| Target-specific Reminder fields | 所有字段必须出现 | 仅不适用分支使用 null | 不使用空字符串/默认值代替 null |
| Notification `covered_reminder_ids` | 非法 | 非法 | 非 aggregate 固定空数组；aggregate 至少一项 |

## Method capability matrix

| Public MethodChannel | Kotlin 行为 | Native call | Request | Public / native response | 状态 |
| --- | --- | --- | --- | --- | --- |
| `anniversary.create` | 调 Native commit，成功后 reconcile 并包装 capability | 同名 | `create_anniversary_request` | mutation / detail | implemented_unintegrated, blocked |
| `anniversary.update` | 同上；省略 plan 保留，传 plan 整体替换 | 同名 | `update_anniversary_request` | mutation / detail | implemented_unintegrated, blocked |
| `anniversary.delete` | commit 软删除与未来任务取消，之后 reconcile | 同名 | `delete_anniversary_request` | delete operation / delete commit | implemented_unintegrated, blocked |
| `anniversary.detail` | 组合 C++ detail 与当前 Android capability | 同名 | `get_anniversary_detail_request` | detail view / detail | implemented_unintegrated, blocked |
| `anniversary.set_reminders_enabled` | commit pause/resume，之后 reconcile | 同名 | `set_anniversary_reminders_enabled_request` | mutation / detail | planned, blocked |
| `anniversary.list_occurrences` | 严格透传一页 | 同名 | `list_anniversary_occurrences_request` | occurrence page | planned, blocked |

`reminder.prepare_delivery/finalize_delivery/plan_recovery` 继续是 Kotlin 内部调用，不暴露给 Flutter。Kotlin 不生成 occurrence/template/reminder/delivery UUID，不重算 membership、72 小时窗口、Ring 五分钟边界或 Anniversary 日末边界。

## Identity and time

- 所有 namespace、canonical compact JSON 和 UUIDv5 vectors 位于 `contracts/identity.yaml`。
- `occurrence_key = UUIDv5(anniversary_occurrence, [anniversary_id, occurrence_date])`。
- `template_key = UUIDv5(anniversary_reminder_template, [anniversary_id, advance_days, local_time, "follow_device", "popup"])`。
- `reminder_id = UUIDv5(anniversary_reminder, ["anniversary", anniversary_id, occurrence_key, template_key])`。
- catch-up `delivery_id` 绑定 Anniversary、occurrence、排序后的完整 covered IDs 与 popup；prepare 后 membership 不变。
- `occurrence_date` 是当地 date；`remind_at` 是由 C++ 使用当前设备 IANA timezone 物化的 UTC Instant。gap 前移，fold 取较早 Instant。

## Error and partial-success matrix

具体 `module/retryable/boundaries/data_saved_allowed` 位于 `error_codes.yaml`。主要分组：

| 场景 | Stable code / response |
| --- | --- |
| 模板 shape 非法 | `ANNIVERSARY_REMINDER_CONFIG_INVALID` |
| 重复 / 超过五条 | `ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE` / `ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED` |
| occurrence range/filter | `ANNIVERSARY_OCCURRENCE_RANGE_INVALID` / `...TOO_LARGE` / `...FILTER_INVALID` |
| cursor | `ANNIVERSARY_OCCURRENCE_CURSOR_INVALID` / `...CURSOR_EXPIRED` |
| 目标删除 / identity 陈旧 / 日末过期 | `ANNIVERSARY_TARGET_DELETED` / `ANNIVERSARY_OCCURRENCE_STALE` / `ANNIVERSARY_REMINDER_OCCURRENCE_EXPIRED` |
| aggregate / idempotency | `ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT` / `REMINDER_IDEMPOTENCY_CONFLICT` / `DELIVERY_ATTEMPT_INVALID` |
| workflow commit/recovery | `CALENDAR_WORKFLOW_COMMIT_FAILED` / `CALENDAR_WORKFLOW_RECOVERY_FAILED` |
| 已保存、调度待恢复 | 成功 `AnniversaryMutationResponse(data_saved=true, schedule_status=pending_*)`；底层直接 reconcile 可使用 `SCHEDULER_RECONCILIATION_PENDING` |

保存失败必须是 `NativeResult(ok=false,data=null,error=...)`。权限缺失、近似调度或调度待恢复不能伪装为保存失败，也不能删除已保存数据。

## Reader / writer ownership

| 定义 | Writer owner | Reader owner |
| --- | --- | --- |
| Reminder plan / template | Flutter request mapper | Kotlin validator、C++ boundary/domain/storage |
| occurrence page/cursor | C++ query service | Kotlin passthrough、Dart gateway/application |
| Reminder target branch | C++ workflow/storage | C++ scheduler query、Kotlin contract/scheduler；Flutter 仅必要投影 |
| Notification / covered IDs | C++ prepare/finalize | Kotlin display/finalize、C++ audit/recovery |
| tap identity | C++ prepare，Android 仅追加 `opened_at` | Kotlin EventChannel、Flutter router |
| RecoveryBatch groups | C++ recovery planner | C++ prepare/finalize、Kotlin 顺序执行 |
| v3 roots / migration | C++ JSON storage adapter | C++ bootstrap/repositories |
| schedule capability | Kotlin platform coordinator | Flutter application/UI |

不存在孤立、无 owner 的新字段。未来 Backend、导入导出和备份有独立版本域，不复用 Native v2 或 Calendar Core v3。

## Requirement traceability

| 上位计划 | 本包交付 | 下游 owner |
| --- | --- | --- |
| §3.1～3.2 支持、创建、权限/降级 | plan/template、create/update/detail、mutation/capability、toggle | Flutter、Kotlin、C++ |
| §3.3 补发与聚合 | catch-up group、Notification kind、covered/fulfillment、identity、outcome vectors | Kotlin、C++ |
| §3.4 生命周期 | update replacement、toggle、delete commit、取消/过期枚举 | Flutter、C++；Kotlin reconcile |
| §3.5 内容与导航 | prepared/tap occurrence identity、route、target-deleted error、note 禁止 | Flutter、Kotlin、C++ |
| §4 occurrence 查询 | 半开区间 request、summary/page、cursor/order、400/500 边界 | Flutter、Kotlin、C++ |
| §5 身份与时间 | 四个 namespace、canonical names、golden vectors、DST policy | 三层共同消费 |
| §6 Reminder/Notification | target-specific `oneOf`、catch-up attempt、fulfillment 审计 | Kotlin、C++ |
| §7 Workflow/Repository | ADR、v3 shared coordinator、commit-before-reconcile response | Kotlin、C++ |
| §8.3 errors | 15 个稳定错误/部分成功元数据 | 三层映射 |
| §8.4 compatibility | `contracts/README.md` 两张矩阵、Storage v2→v3 连续迁移 | 三层同 APK、C++ Storage |
| §12.1 | Anniversary + Ring 回归 manifests、semantic/storage vectors、validator | 三层测试直接复用 |
| §14～17 门禁 | 能力维持 blocked；激活条件写入 Storage 与能力图 | 最终集成 owner |

## Fixtures and validation

- Anniversary 正反实例：`contracts/fixtures/anniversary/manifest.json`。
- Event/Ring/普通 Recovery 回归：`contracts/fixtures/ring/manifest.json`。
- 领域、DST、补发、finalize、tap、migration oracle：`semantic_vectors.golden.json`。
- v2→v3 字段保留 golden：`storage_v2_to_v3.golden.json`。
- 验证入口：`python contracts/validate_anniversary_r1.py`（验证环境需提供 `jsonschema` 与 `PyYAML`；它们不是产品依赖）。

激活前，各语言必须把同一 fixtures 作为独立 round-trip/negative tests；Schema parse 不能替代真实 C++ migration、JNI、APK、Alarm/Notification 或真机验证。
