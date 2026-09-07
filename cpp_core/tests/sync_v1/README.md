# 云同步-03：测试先行交接（2026-09-07）

状态：**C0 输入门禁阻塞；C1–C8 未实施；不是 Layer Complete**。

目标来自 `docs/plan/active/云同步-03-CPP与SQLite-v6开发计划.md`。
本轮先写测试和预期，没有修改生产实现。手机不可连接；后续设备替代测试使用冻结输入，实际 OS、加密 APK 与消费方签收不能由这些数据证明。

## 已写成可执行代码的测试与预期

| 代码 | Given / When | 预期结果 | 证明范围 |
| --- | --- | --- | --- |
| `run_preflight.py` | 对当前工作区检查所有锁定来源，再调用官方默认入口 | 所有来源摘要一致、官方返回 0 才允许 C1；任意不一致返回非零并输出路径/两个摘要 | C0 输入门禁，不是同步功能验收 |
| `test_contract_input.py` | 遍历 manifest 中全部 751 条固定 fixture | 每个指针可解析，case ID 和原始预期与 manifest 一致；四端使用同一 manifest/hash | 测试输入闭合，不代表已执行 751 项业务行为 |
| 同上 | 修改一份 ack-only 输入副本，再取重试副本 | 原始 cursor=null、uploads=[]、download_limit=0 不变；未知 fixture ID 明确失败 | 供迟到、重复、损坏输入测试复用；不实现 Backend |
| 同上 | 对 JCS 已冻结的预期 bytes 求 SHA-256 | 等于预期 hash | golden 输入自洽；不冒充实际 C++ JCS 实现测试 |
| `../sync_v1_storage_baseline_tests.cpp` | 两个真实 v5 SQLite 使用同一个 Category ID、不同名称，关闭重开 | 两份事实分别保留，无跨库覆盖 | 现有存储连接隔离前提，不代表多 runtime 已实现 |
| 同上 | A 内层写入后注入失败，B 独立提交，然后重开 | A 零事实，B 保留提交，错误传回调用方 | 现有事务回滚隔离前提，不代表 Outbox 原子性 |
| 同上 | 嵌套 lease 结束后重复 revoke | 旧 writer 被拒绝，其他/新 lease 正常 | 现有 lease 基础；在途 close 并发仍待 C1 测试 |

运行方式（仓库根目录）：

```text
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
cmake --build cpp_core/build-ninja --target excellent_calendar_sync_v1_preflight
```

`excellent_calendar_check` 包含既有回归、新增 C++ 基础测试与 fixture 准备测试。
`excellent_calendar_sync_v1_preflight` 是单独的 C0 退出门禁；回归通过不能覆盖它的失败。
没有跳过正式校验、允许 drift、把失败视为通过或重新生成冻结基线的选项。

## C0 调用链与 writer 初步盘点

现有链：`*_v2_endpoint → current_*_service → Application/Workflow → 窄 Repository/Transaction → SqliteCalendarDatabase`。
`native_runtime.cpp` 仍是全局 `RuntimeState g_state`；各 repository 使用 `RuntimeStorageLease`。
数据库是 v5，SQL 集中于 `src/storage/sqlite/sqlite_calendar_database.cpp`，绑定实现位于 `sqlite_repository_adapters.cpp`。
不能通过把 `kCalendarCoreSqliteStorageVersion` 改成 6 或加一个 Boundary 分发器完成本计划。

以下是实施入口清单，不是“逐 writer 同步验收已通过”的清单。所有账号 LocalUser writer 都还缺少 trusted origin、typed mutation plan、fact/history/generation/entity state/Outbox 同事务和故障注入证明。

| 闭包 | 已有 Application 入口（头文件位于 `include/excellent_calendar/application/`） | 事务/持久化 | 目标缺口与测试要求 |
| --- | --- | --- | --- |
| Category | `category_service.hpp`: create；其余目前仅 list | CategoryRepository → SqliteCategoryRepository | update/delete/restore/reorder 按 Native v3 新增；每种 writer 账号原子 Outbox、游客零 Outbox；不改弱引用含义 |
| Event 主体与整系列 | `recurring_event_workflow_service.hpp`: create_event/update_event/delete_event/complete_event/reopen_event/create_series/update_series/complete_series/reopen_series/cancel_series | RecurringEventTransaction | recurrence revision CAS、owned child 原子图；恢复入口以冻结 Contract 核对；不加入 R3 三作用域编辑 |
| Event occurrence | 同上：complete_occurrence/reopen_occurrence/skip_occurrence/cancel_occurrence | 同一 RecurringEventTransaction | occurrence 原始 civil identity、revision/exception、完成时间；普通写与设备执行分开 |
| Anniversary | `anniversary_workflow_service.hpp`: create/update/remove/set_reminders_enabled | AnniversaryTransaction | 专属 yearly recurrence 与 reminder intent；restore 能力按冻结入口补齐，不能复用 Event recurrence |
| Habit | `habit_service.hpp`: create/update/end/remove/set_reminder | HabitTransaction | end/reopen/restore 的实际可调用路径仍需按 v3 核对；定义与 recurrence/history/模板图原子 |
| HabitCheckIn | 同上：check_in/clear_check_in | HabitTransaction | increment/decrement/replace/clear 和 Android action 对应的同一 workflow；每日业务唯一键、operation 幂等、first_check_in_at 历史保护 |
| Event Reminder 用户设置 | `reminder_service_v2.hpp`: create/update/cancel/enable/disable | RecurringEventTransaction 的提醒写入口 | 只投影用户 intent，不上传 Reminder 整行；每种 target 使用冻结模板字段 |
| 旧 Event/Reminder 链 | `event_service.hpp`、`create_event_workflow_service.hpp`、`event_lifecycle_workflow_service.hpp` 与 `reminder_service.hpp` | EventRepository/EventReminderTransaction 等旧 repository 适配器 | 保留旧 v5/历史迁移；不得把旧 JSON/legacy writer 自动视为新账号同步入口，先完成 legacy 转换审计 |
| 设备执行 | delivery prepare/finalize、recovery、snooze、mark_scheduled、Habit reconcile 等 | 现有专用 workflow/transaction | DeviceLocalEffect 零 Outbox；snooze/投递状态不能当用户同步模板 |
| Preferences | 生产 workspace owner 缺失 | v6 workspace_preferences 待实现 | timezone/颜色/有序默认 methods/跨设备提醒四项 CAS；游客零 Outbox、账号原子 Outbox；不接管 Kotlin display |
| Profile cache | 生产 owner 缺失 | v6 account_profile_cache 待实现 | server-only、单调 revision、账号隔离、零 Outbox |
| Conflict resolution | 生产 owner 缺失 | 专用 intent + Outbox transaction | queued/resolving 不提前改变 live fact/unresolved；服务端 effect/delta 才发布 |
| Import | 生产 owner 缺失 | guest lease + account staging/Outbox saga | 独立 begin/items/commit 路由，publish 前 live 零写，cleanup/abandon 不分配 sequence |

身份与字段 owner 必须继续消费 `contracts/sync/sync_identity_registry.yaml`、`sync_field_registry.yaml`，不能由上述入口名称推导：

- Category/Habit 等 canonical UUIDv4；legacy Event/Anniversary 源文本逐字保留，不做大小写归一化。
- Event recurrence 由 `(recurrence_id, revision)` 标识；它不是 entity_version。
- HabitCheckIn 同步身份来自 `(habit_id, check_date)` 的固定 UUIDv5，本机行号不是同步 ID。
- ReminderIntent 按 owner 唯一；本机 Reminder、Notification、Alarm、调度 key 和投递记录不上传。
- account_profile 仅下载；user_preferences 不接管 Android display、铃声 URI、搜索历史或权限。
- Import 映射必须持久化并遵守 source epoch/lineage；不把确定性 hash 伪装成 UUIDv4。

这份盘点是 C0 初步交接；ID/字段逐 writer 闭合和所有新入口的完整调用链仍未完成，不能勾选整个 C0。

## 后续章节的预期验收（尚未全部写成可执行测试）

严格按 C0 → C1 → … → C8 实施。每阶段生产编码前，先把该行转为针对真实 owner 的可执行测试；不以本表代替测试代码。

| 阶段 / 章节 | 必须预先实现的关键断言 |
| --- | --- |
| C1 / §5–6、8 | fresh-v6、完整 v5 checker 后原子迁移；每个失败点保留 v5 字节/历史；双 runtime 同 ID 不串库；旧 handle/关闭在途/错误 account/key/path 零写；fresh account bootstrap 前禁止业务写 |
| C2 / §7–9、14 | 每个 writer 事实+history+generation+entity state+Outbox 原子；故障后无半提交；guest/remote/device/profile 零 Outbox；MAX 最后一次可分配、随后零写；entity conflict/effect gate；preferences CAS/profile 单调 |
| C3 / §9 | prepared identity/items/hash 重试不变；100 项/1 MiB/连续 prefix/route 隔离；五种 original status 与 duplicate 完全一致；旧 fence response 零写；ack-only 不改变 cursor/fact；causal anchor 与 effect gate 约束确认水位 |
| C4 / §10、12 | 非法任一项整批回滚；baseline+pending+failed overlay 同事务；普通 group 不拆；import 双 cursor；created→resolved 同窗口净零 notice；exact head claim 幂等；resolved 后迟到 created 不复活；maintenance 仅用服务器水位 |
| C5 / §11 | bootstrap 固定 identity/upper bound；页 hash 重复幂等/异 hash 拒绝；20,000 条与强杀重开；finalize 前 live 不换；pending/failed/causal/deleted anchors 保留；fresh/exhausted allocator 正确 |
| C6 / §13 | 全部 FX-IMPORT-*（包括 manifest 的 generated_suites）；guest reserved/account commit/guest active 强杀恢复；publish 前不可见；range proof 与 allocator/ack 原子；compare-and-retire/CAS/epoch/审计/previous gate；源与账号提醒不双发 |
| C7 / §6、8、14 | 单一 SQLCipher ABI provider；key 错误零覆盖；DB/WAL/SHM/temp 不含业务明文；内存 key 清理；三 ABI 构建及主机可替代测试；不可替代的实际 OS 行为如实未验证 |
| C8 / §17–19 | 完整构建后测试、性能实测、全部实际 owner 场景、Kotlin/Backend 消费方签收；禁止把 fixture parser 或原型实验计为生产同步完成 |

当前冲突、摘要和最小解除条件见 `docs/issues/problem-cpp.md` 的 `CPP-SYNC-001`。

## 本次实测结果

2026-09-07：Ninja 配置成功；`excellent_calendar_check` 构建后 **15/15 通过，50.63 秒**，其中新 C++ 程序执行上述 3 个场景，新 Python 套件 5 项通过并核对 751 条固定输入的引用和预期。
`excellent_calendar_sync_v1_preflight` **退出 1 / BLOCKED**，两个 Appearance 来源与冻结锁不一致，官方默认验证同样退出 1。
未执行 C1–C8 实际 owner、性能、三 ABI 加密和跨层签收测试；后续表格不是已执行证据。
