# Sync Protocol v1：身份与同步事实投影

状态由 `contracts/sync/ct0_gate_status.json` 唯一登记；封版摘要见 `contracts/sync/sync_v1_revision_lock.json`。本文记录云同步-01、云同步-02 和 Accepted Sync ADR 的目标投影；现有 Native v2 与 SQLite v5 保持不变，新增生产能力仍为 planned。下文有日期的检查点保留其当时范围，当前验收及 5d8fb0a 的 11 类问题闭合见[Review复核与兼容修订记录](../plan/active/云同步-02-Review复核与兼容修订记录.md)，首次冻结记录只保留历史范围。

## 机器入口与边界

- 身份、旧 reader 解释及图映射：[sync_identity_registry.yaml](../../contracts/sync/sync_identity_registry.yaml)。
- 字段方向、nullable、create/update/clear/import 权限及 merge key：[sync_field_registry.yaml](../../contracts/sync/sync_field_registry.yaml)。
- 强类型事实与原子字段组 patch：[sync/v1](../../contracts/sync/v1/)。当前覆盖 12 个 target、14 个具体事实形状；ReminderIntent 的三个 owner 分支不能互换。
- 默认提醒方式：[default_reminder_method_applicability.yaml](../../contracts/reminder/default_reminder_method_applicability.yaml)。颜色复用现有 appearance 的七个 preset token，不转成任意 RGB；方法数组保留原顺序，无合法候选则不创建默认提醒。

这些事实 Schema 与普通 Native UI DTO 分开。现已新增 mutation、逐项终态、因果链、bootstrap/import、会话/设备/保留期限的 planned Schema，以及 SQLite v6/PostgreSQL 逻辑模型。owned dependency 的完整事务证据、冲突解决与 failed-local 的事务闭环、capability 的四语言消费与运行时映射仍需闭合；文件存在不表示这些门禁已通过。`account_profile` 事实绝不允许形成 upload mutation。

## 与现有模型的具体衔接

### HabitCheckIn

当前 `docs/domains/habit_check_in.md` 的业务唯一键是 `(habitId, checkDate)`，而 `HabitService` 在各本机首次创建逻辑行时分配 UUIDv4。两个离线设备对同一天首次操作可能产生不同的行号。若直接用该行号做同步 entity ID，会绕过每日唯一性，导致增量重复和 clear 不能命中另一设备的事实。

同步 ID 使用 registry 中独立 namespace 的 UUIDv5，name 是明确的紧凑 UTF-8 数组 `[habit_id,check_date]`。Sync fact 不上传本机 `id`；下载按业务唯一键 upsert，已有 UUIDv4 行号保持不变，新本机行才分配 UUIDv4。现有 Native response 仍返回本机行号，所有现有按习惯和日期操作的入口继续按原规则解释。clear、恢复、时区变化和网络重试都不改变当地日期或同步 ID。

Habit 的 `first_check_in_at` 位于当前 SQLite v5 存储事实中，普通 `HabitResponse` 未投影它。Sync fact 明确携带该保护标记；clear/tombstone 清理不能清除它，更不能重新开放目标、单位和开始日编辑。普通 patch 不可写该字段，导入须保留已经存在的历史保护证据。实际跨 Habit/CheckIn 的事务归属还需由完整 mutation 和存储模型验证。

### ReminderIntent

Anniversary 的模板 key 包含提前量和 local time；Habit 的本机模板 key 在身份相关设置变化时换新。它们都是现有本机调度图的身份，不适合作为跨设备“正在编辑同一份提醒设置”的冲突对象。

Sync 使用每个 `owner_type + owner_id` 唯一的 ReminderIntent，上传该 owner 的完整用户配置，并把 schedule 作为原子 merge key。Event 使用 typed template 数组，Anniversary 最多五个模板，Habit 使用至多一个专属模板。实际 Reminder、模板调度 key、投递状态、Notification、Alarm、Ring、Recovery 由各 workspace 的 Core/Android reconcile 管理，不上传、不跨 workspace 改挂。已有 `contracts/identity.yaml` 的 occurrence/reminder/delivery namespace 和算法不变。

### 导入映射和 opaque 引用

总计划只有 lineage 明确指定 UUIDv5；新 Category 仍要求 UUIDv4。本次采用持久化分配表解释“确定性映射”：`(lineage_id, source target, source id)` 查找唯一、不可变的已分配 target ID，不把固定 hash 的字节伪装成随机 UUIDv4。

Preview 只读账号现有映射、事实版本和分配器，在临时规划库计算完整图；preview token 对应的 guest 恢复材料不包含明文账号身份，账号映射、staging、Outbox 和 sequence 均零写。可保留无碰撞的 canonical UUIDv4 source ID，碰撞或非 canonical UUIDv4 则分配真正的随机 UUIDv4，并重映射完整引用图。commit 先保留 guest source lease，再在账号同一事务安装映射、冻结 manifest/Outbox、operation receipt 和 allocator；source snapshot 或账号读取基线改变时拒绝旧 preview。相同 preview、重试和 successor 复用已存在映射；本机证据丢失后将保留的 typed mapping 与服务端同 lineage manifest/proof 逐项核对，不能由丢失的 Outbox 推造 terminal receipt。Backend canonical commit 再校验 target 所有权，冲突时零写，不能覆盖无关账号事实或悄悄换已冻结 ID。

Event/Anniversary 的现有 UUID checker 比 Category/Habit 宽，能接受大小写等历史 UUID 文本。它们作为 source key 逐字保留；导入产生新的 canonical target ID，不在原游客图中小写化或按 UUID 数值合并两个不同文本键。

弱 Category 引用只在 source 图中存在**完全相同字符串的 Category key** 时跟随已登记映射。缺失、已删除、空字符串、大小写和 Unicode 组合形式均原样保留；不补造分类、不置空。Anniversary 经已接受的 Native v3 revision 承载这些值，v2 的窄 reader 和 fixture 保留。

### Recurrence 和 occurrence

Event recurrence 仍以 `(recurrence_id, revision)` 标识不可变版本，Sync target ID 明确编码为 `recurrence_id#decimal_revision`。这不是 entity_version。Occurrence 继续使用原 `contracts/identity.yaml` 的 UUIDv5 算法；Sync fact 增加经 Core 证明的 `original_local_start`，导入更换 Event ID 时据此重算 key，不能简单 hash 旧 key，也不能把 DST gap 后时间当成 identity 输入。

合法 v5 状态需通过 Core 的有界 occurrence 重建取得恰好一个匹配旧 key 的原始 civil 时间；无法证明则迁移/导入零写。15 个固定场景已由实际 Core/TZDB 验证，包含 gap/fold、半小时偏移与跳日后同 UTC 不同原始 key。并发离线修改可能各自产生同一数字 revision 的不同候选，独立 owned graph 实验现已验证完整 coherence component 冲突与独立根字段合并；已有 tuple 永不覆盖，独立 orphan child 创建拒绝。该组件与完整 child 因果链/transport 的组合仍待验证。

`legacy_events/legacy_reminders/legacy_notifications` 中 v1 opaque 实体已经过实际 Core 迁移和 19 个转换条件用例审计。v1 source ID 使用 `legacy-v1/event/` 加原始 UTF-8 的规范无 padding Base64URL，明确区别于现代 UUID key；目标仍由耐久 UUIDv4 ledger 一次分配。可转换的 live Event 必须是非重复 timed，并保存了合法 IANA 时区；旧版没有保存的日期、规则和版本不能猜测。非终态提醒只投影配置，终态投递历史继续留在 guest。任何不支持的 live 行使整批预览在 lease/mapping/Outbox/退休之前失败，保留源数据，不截断 ID 或静默跳过。

## 验证的实际范围

`run_domain_spike.py` 运行 22 项测试、61 个固定事实边界向量，检查 missing/null/未知字段、字段组 patch、引用图、UUIDv4 碰撞映射、响应丢失后重读映射、epoch 删除闭包、日期/时区、默认提醒合法性及 220 份旧机器定义不漂移。新 Sync UUID 为 canonical 小写；旧 guest lexeme 与弱分类引用不归一化。打卡快照须匹配历史保护下的目标/单位并位于有效结束日内，单位沿用已有 32 字符上限。报告带参与源文件 hash。

`run_protocol_spike.py` 的 51 项测试验证严格协议形状、真实 SQLite sequence/causal/ack/notice 事务与纯生命周期决策。回执绑定本机 device，duplicate 外壳必须与原回执一致；确认水位等待 effect group 及其准确末序号应用后才推进。import commit 有独立严格结果：成功须携完整发布证据，拒绝须携 repair 状态、typed error 与下一 revision。`run_storage_spike.py` 的 9 项 SQLite 检查调用当前未修改的 C++ v5 checker，逐一注入 113 个新增 DDL/history/commit 回滚点；验证 20 个原表、24 个原索引及原 payload/position/generation/history 保留，并实际调用旧运行时验证 v6 拒写。v6 checker 的旧图校验使用临时副本投影，只是实验复用手段，生产实现必须原位复用冻结 checker，不复制账号库。

PostgreSQL 实验在隔离的 17.11 容器中先应用当前 V1–V3，再执行 planned DDL，核对 36 张新增表、125 个字段映射、36 个约束用例和 MAX−1 的真实并发分配。新增游标签发范围只保存非敏感元数据，常规轮换不能提前删除验证所需记录；bootstrap identity/item 不可原位改写。该证据不表示生产 migration、账号加密完整图、Android 迁移、完整 Sync 状态机或双设备功能通过。

游标的私有认证格式见 [sync_cursor_protocol.yaml](../../contracts/sync/sync_cursor_protocol.yaml)，33 个用例已由 Java 与 Python 得到相同字节和错误结果。完整重建的摘要与分页规则见 [sync_bootstrap_protocol.yaml](../../contracts/sync/sync_bootstrap_protocol.yaml)：新增 planned 快照条目数、完整条目摘要、总页数和固定单页条目上限，纳入 HTTP/Native identity 和两端逻辑存储。7 项 SQLite 参考测试覆盖六类 union、500 条分页、快照稳定性、10 个真实强杀点及 fresh DB 确认恢复。已有 pending、failed-local 或 effect gate 时仍须组合重放验证，不凭该单独组件标记整条 bootstrap 链路完成。

冻结 v4/v5 节点不变；根存储声明只新增 `planned_format_contract=calendar_core_v6`、`latest_declared_format_version=6` 和独立 v6 节点，active 仍为 v5。旧基线验证器按精确历史投影验证原 hash，绝不重建旧基线。Habit 验证器只放行这一 planned 后继，其余 v5 检查保持原样。`run_sync_v1_validation.py --stage drafts --self-test` 只检查当前草案；默认入口仍拒绝冻结。

## Native v3 和 Backend 修订的调用边界

`contracts/sync/capability_graph.yaml` 导航到独立 Native v3 方法/调用注册表及 Backend sync-v1 修订。当前 107 个公开方法（含保留的 blocked 墓碑）、90 个内部 Native 调用、35 个 HTTP 声明均逐项标记 planned/blocked；其中 18 个 HTTP 声明是本计划新增，当前真实 Controller 仍为旧 16 个。根 methods/native/API/enums/errors 仅追加精确 planned 链接，原节点和版本不变，历史投影仍对原 220 项摘要校验。

既有 workspace 业务方法在 v3 使用 `workspace_id + expected_active_route_revision + typed payload`，响应回显 workspace/runtime/route 与 typed payload；Kotlin 在稳定 route CAS 后绑定不可复用的 runtime。Native 的业务入口用 typed binding 与 typed payload，重复 identity 必须逐项等于所绑定 runtime。纯时间换算、权限与设备外观等全局本机能力保留其已有 payload。新生命周期方法采用各自严格 Schema，不把 Flutter 请求当作内部 lifecycle 授权。DTO、bridge、JNI translation unit 和 C++ boundary 的名称只作为 03/05/06 的 planned 实现锁，不伪称已有符号。

Category 的 update/delete/restore 使用 `expected_native_state_revision` 做本机编辑 CAS，类别列表/创建响应提供该 revision；排序属于 Category 内独立 merge group，服务端 reorder revision 仍由 Backend checked increment。本机 CAS 不替代服务端 merge/ordering。删除保留引用，恢复提交相同 ID 的完整合法候选；颜色请求仍接受大小写并由领域规范化，nullable 字段沿用原语义。

当前 C++ Event/Recurrence/OccurrenceState/Reminder 的 recurrence revision 是 `int`/`optional<int>`，而旧 v2 Schema 没有声明最大值；这不证明旧 reader 支持大整数。总计划要求新同步 counter 使用安全整数上限，因此 `native_v3/business_compatibility.yaml` 为这些字段及全部传递读取路径显式登记 checked int64/Long/int/long，最大 9007199254740991。v6 对 events、recurrence_versions、event_occurrence_states、reminders 分别增加 4/4/4/5 的 payload codec 元数据版本，只授权 recurrence counter 位宽变化；旧 v5 定义和旧 payload 字节不变。生产新 codec 和宽计数器完整图的验证仍归后续实现，旧 v5 临时投影实验不能证明新宽值可经 int32 decoder 读取。

通知兼容 reader 允许 workspace identity 成对缺失或成对提供；v6 writer 必须同时写 workspace_id/workspace_kind。旧通知仅能命中唯一明确的 legacy workspace；歧义拒绝，已退出隐藏账号不可路由，不按 target ID 扫描多个库。Ring 活跃项携带 workspace identity，避免游客与账号投递同处一个 Ring session 时丢失来源。

`run_capability_spike.py` 运行 17 项测试及 28 个固定边界用例，验证 Schema/映射引用、旧版本保护、route/runtime 拒绝、二进制 key 参数形状、Category patch、通知 action 身份、DTO 名称隔离及完整事件列表。这里只验证边界，不能凭 shape check 授权打开加密库，也不认证签名或代替四语言消费者。


## Habit operation 语义与耐久身份（2026-09-06）

本次以总计划 01 §9.3 为业务依据，以 02 §7.1–7.3 的逐字段因果证据及既有 HabitCheckIn 领域正数/快照规则约束边界。唯一机器定义为 [sync_habit_operation_protocol.yaml](../../contracts/sync/sync_habit_operation_protocol.yaml)。修正草案中 completion-only 无法表达 clear/recreate 删除状态及快照依赖的问题：增减操作声明 completion/deleted_at/snapshot，replace_total 另含 note，clear 声明 completion/deleted_at。没有变化的成员仍返回 no-effect；clear 的 completion 版本承担非增量屏障，tombstone 内保留最后合法数量。

独立增减在没有未观察到的 replace/clear 屏障、且中间结果可表示时累计。减到 0、负数或超过 safe integer 不截断，不存伪 partial，也不隐式改成 clear；按现有领域约束返回可恢复的 HABIT_CHECK_IN_STATE_INVALID。明确清空仍使用 clear。客户端时钟只描述来源和发生时间，不决定并发先后；当前设备日期检查属于 Core writer，服务端不从诊断时间猜测当地今天。

operation_id 绑定认证账号及完整 typed operation digest，跨 mutation/sequence/base/recovery-snapshot 重建保持稳定。已应用操作重试引用原 effect ID/sequence，不重复累计、不产生成功 anchor；未应用的失败意图可由用户在新 sequence 上重试。相同 operation_id 改变内容返回仅限 Habit operation 的 SYNC_HABIT_OPERATION_ID_REUSED，私有 context 绑定原 operation_id，公开失败摘要移除该传输身份。原 v2 错误表不变。

SQLite v6 新增 operation hash 和 effect 对，保护 immutable identity/成功结果并保留到账号库销毁；PostgreSQL 新增账号限定 operation ledger 与 completion barrier，允许 rejected target 不存在，避免把日志 identity 误当作事实外键。普通 receipt/change payload 清理不删除 operation 去重记录；账号删除仍级联清理。首次成功打卡与 Habit.first_check_in_at、字段版本、group、receipt、sequence 在同一事务提交。该组件是 Contract 参考验证，生产 owner、完整 bootstrap 重放和四语言消费者另行验收。

### 2026-09-06 本机意图与 ordinary download / bootstrap 组合验证

以 01 §8.2 与 02 §6.2–6.3、§7.3、§7.5、§10 为依据，`contracts/sync/sync_local_intent_protocol.yaml` 给出冻结意图、效果覆盖、草稿和替换记录的唯一候选机器规则。baseline 与 presentation 分离，pending/failed/awaiting-effect 按原 sequence 重投影；无法满足领域图、删除锚点或 unresolved 门禁时保留 typed candidate 与原 mutation/hash，不伪造对象或上传结果。

已进入发送准备的请求若遇到重叠 after-image，但缺少自己的确切 receipt，单凭下载事实不能判定其中是否已包含本机增量。参考实现耐久保留该不确定状态和原草稿，待 receipt 或完整 bootstrap 的 device highest 消除歧义。bootstrap highest 不得替代旧库未确认 receipt；fresh DB 只能在完整 finalize 原子初始化确认基线。效果覆盖必须是已应用的 exact group，或具备相同/更新 generation、充分 upper bound 与 device highest 的完整快照。

参考组合执行 29 项测试、8 个固定历史及 18 个 `os._exit` 实际强杀点，覆盖 journal / ordinary apply / bootstrap finalize。真实 Habit SQLite 结果验证回执丢失后 500+100 经下载、重建和重启仍为 600；普通后继 pending 对前驱 receipt 的 pin 不会提前释放。失败替换的旧记录只有新项实际应用了其全部语义键且效果已应用才清除；无效果替换及再次失败均保留草稿。未签署生产 owner、导入发布与完整冲突解决 writer 或四语言实现。


### 2026-09-06 12:10 冲突与通知组合证据（未冻结）

冲突规则见 `contracts/sync/sync_conflict_protocol.yaml`；通知发现、不可变队列、水位及清理见 `contracts/sync/sync_notice_protocol.yaml`。16 项冲突测试验证 root 的四种选择、四类已消费拒绝、删除锚点及失败手动草稿；9 项通知测试把 queue/journal 接入普通下载和 bootstrap 的现有事务，14 个真实退出点验证它们与事实/游标全有或全无。百万窗口容量的实际队列/成员上限均为 1，terminal discovery 不残留；1,000 次有界批次提交与独立强杀原子性证据分别记录。

未完成下载由 bootstrap 替代时，未通知且仍未解决的发现集属于同一逻辑发现流程；这避免把已经发布到本机、但尚未到 terminal 的新冲突误认为历史已通知项。该工程细化依据总计划 §9.5 和本计划 §8.2 的净新增及不可丢后继要求，仅作用于本次 planned 协议。产品 Native/status/UI owner、owned 规则和 import 组合不由这些报告认证。

### 2026-09-06 主对象与子项冲突候选修订（未冻结）

发现的冲突：本次 planned `sync_conflict_detail.schema.json` 及 Native v3 detail 原来只有 value/deleted 分支；主对象的原子组件被另一设备占先时，附带的新 recurrence 或 reminder intent 可能从未发布，既不存在值，也不存在删除版本。依据总计划 01 §9.1、§9.4 及分计划 02 §7.1–7.3 的原子组件与不可变修订要求，在这两份新草案的 server candidate 中增加仅含 `kind=absent` 的分支，限定为四种 owned child。不得生成假 tombstone、版本 0 或删除序号；local candidate 不接受 absent。原 Native v2、当前 active reader/writer、220 份受保护定义均不因此改变。

主对象与 owned child 使用同一 device sequence、receipt 和字段 anchor；成功前驱及已消费 no-effect 前驱都必须匹配完整 target/id/owner/merge key。事实、各自字段版本、完整 typed group、冲突与 device highest 同事务提交。具体机器规则见 `contracts/sync/sync_owned_protocol.yaml`。新增参考组件曾通过 12 项、7 个固定历史和 7 个实际退出点；后续公共 helper 修订后须重新执行证据报告，不能沿用该历史通过状态。

手动冲突候选必须保留 identity、audit、server-owned 字段和 Habit 历史保护；已删除实体不能同时选择部分删除、部分恢复。为合法 resolution envelope 的此类领域拒绝新增 planned `SYNC_RESOLUTION_CANDIDATE_INVALID`，只允许 resolution terminal，不允许 import 或普通 mutation 借用；拒绝消费本次 sequence、保留草稿和 no-effect receipt，业务事实不变。该修订来自 02 §7.5 对领域失败终态的要求，不修改旧 v2 错误注册表。owned 解决和不可变新 revision 的参考组合正在验证，尚未由此认证导入、完整生产 owner 或四语言消费。

## 2026-09-06 导入摘要、超限证明与 MAX epoch 修订（未冻结）

本轮按总计划 §6.3 游客导入及 §8.1 的 source epoch 定义、02 §7.6 IMP-03/07/09/11/12 校准 planned V1；没有改动 active Native v2、SQLite v5 或历史 migration。

- `sync_import_protocol.yaml` 唯一定义 item 的 JCS 投影为 target_type/target_id/operation_type/payload，按 target type/source ID 的 UTF-16 顺序排列。manifest_hash 对“删除自身 hash 字段的 manifest + ordered_item_hashes（ordinal/item_hash）”计算，避免运输外壳内 import_manifest_hash 的循环依赖。该规则把同长度的内容替换纳入摘要；source_snapshot_hash 只承担 guest compare-and-retire 绑定。
- 冲突：原 `proof_reference.py` 把 manifest_hash 重新算为纯 metadata 摘要；范围关闭证明可能在任何 item 到达前产生，根本没有内容 hash 列表。按 IMP-07/08/12，消费者验证原声明、source/lineage/range/CAS 和完整签名覆盖，不能伪称复算了未提供的 item 内容。只有持有完整 typed staging 的 commit 才复算内容摘要。固定公开签名样本使用实际 typed item 生成的新摘要。
- 冲突：原 `sync_import_manifest.schema.json` 把 total_item_count/total_canonical_bytes 的 wire 最大值设为 50,000/128 MiB，导致 IMP-11 要求的超限拒绝证明无法原样携带合法 safe-integer 声明。planned Schema 现在允许完整 safe-integer 声明；运行上限仍固定在机器 invariants，C++ allocation 前及 Backend reservation 事务分别强制，绝不扩大可导入容量。缺失/少报/累计超限仍须稳定终结范围。
- 冲突：原 planned v6 `workspace_metadata` 只允许 pending epoch 小于 current epoch，且没有 durable exhausted 位；MAX epoch 成功退休后无法再递增，不能落下清理 gate。新增 guest-only `source_epoch_exhausted`，仅在 current=MAX 时允许置位，pending=current 也仅在 MAX+exhausted 下合法。未到 MAX 仍严格要求旧 epoch 小于 current；账号 workspace 三个源状态字段均为 null。原 v5 checker 输入和全部继承节点保持冻结。

影响范围：仅同步草案 Schema、证明/存储参考消费者与相应 fixture。以上行为需新增实际事务与负例验证，重新生成相关 source-hash evidence；现有历史通过记录不等于新草案冻结。完整 import repair/range/cleanup、四语言消费及最终整合继续保留未完成状态。

### 导入租约和清理恢复的存储细化（2026-09-06，未冻结）

按 01 §6.3、02 IMP-01/07/09/10，同步草案补齐账号 batch 的 lease_operation_id、protected_owner_binding_digest、outbox_mutation_digest，以及 guest active lease 的 manifest hash。owner binding 使用 installation 私有 256-bit key 对 `ExcellentCalendar.GuestImportOwner.v1`、LF、canonical account UUID 的 HMAC-SHA256；guest 只保存摘要，既不保存账号 UUID，也不从普通认证失败推断 owner 已被删除。

所有双库路径固定先取得 guest writer，再读取或写入 account receipt；从 reserved 恢复时，在检查 receipt 到 active CAS/never-active release 之间保持同一 guest 锁。否则另一个恢复线程可能在账号事务提交前误释放租约，使两个账号同时持有同一源。参考测试使用两个真实 SQLite 库和实际进程退出，未把跨库动作声称为单一 SQLite 原子事务。

planned v6 新增 `guest_import_source_lease_terminals`，仅保存 source/epoch、opaque lineage/owner digest、原 lease revision、四类 proof kind 和摘要。旧 lease 删除后仍能判断同一 release 重放，且不触碰后续 epoch 的租约或新写入。无业务 payload 的 retired audit anchor 支撑留在 guest 的终态 Reminder/Notification 引用；源设备账号提醒要等实际 guest 退休回执，单独的 server-confirmed 或 publish-applied 不授权双边同时物化。

seen-range proof 的 origin generation 不随 fresh transport fence 改写；其 recovery bundle 可以来自当前更高 generation，但接纳该分支的 fresh runtime 必须先接纳 transport fence。保留旧运行实例不能利用新 generation 的 bundle 删除旧 Outbox。以上是已授权计划内的兼容草案修正，Native v2 与冻结 SQLite v5 不变。

### 导入 HTTP 状态和存储容量冲突处置（2026-09-06，未冻结）

原 planned `sync/import_status_response` 与 Native 共用九态和完整 guest cleanup receipt，但 `sync.import.cleanup_confirm` 仅向 Backend 发送摘要，没有发送 cleaned_at；服务器也无法拥有本机 staged 数量或 publish-applied。依据总计划 01 §6.3 和 02 IMP-04/06/09，HTTP 改为六个服务器阶段，completed 携精确 `cleanup_confirmation`；Native 保留九态、双侧数量和实际 guest receipt。HTTP 不得伪造本机应用或清理证据。公开 MethodChannel 继续投影既定九态，不向 UI 暴露证明内容。

原 planned PostgreSQL `sync_import_batches` 的硬容量 CHECK 与 IMP-11 的“超限 begin 保存最小 rejected batch/range”冲突。新增仅私有存储使用的 capacity_rejected 位：正常 reservation 继续受 50,000/128 MiB 限制；超限声明只能进入无 published_at 的 repair_required/superseded/abandoned 记录。本机 allocation 前已能拒绝超限，SQLite 账号 batch 仍保留原容量上限。原 SQLite active-source 唯一索引又把 published/repair 旧批算作可上传批，阻止 IMP-05 的完整 successor；现限制为 local_staging/server_staging。同 epoch 的唯一上传者仍由 guest lease、lineage CAS 和 range proof 门禁共同保证。

## 后继图、删除锚点与离线导入状态的修正

2026-09-06，依据总计划 01 §6.3 与本计划 02 IMP-03/04/05/06，以下修正只属于 planned Sync/Native v3 与隔离参考验证，不改 Native v2 或冻结 Storage v5：

- 冲突：`sync_identity_registry.yaml#import_mapping.successor_delete_set` 及早期 `MappingLedger.successor_deletes` 只覆盖 published mapping；IMP-05 明确要求当前完整源图与同 lineage 历史 mapping 的并集。本次按任务指定的上位计划修正为全部历史 typed assignment，排除仅作 ID 分配的 private recurrence-family key。未发布 staging 的源身份也不能被后继静默遗漏；其他 epoch 的映射不进入删除闭包。`ImportGraphPlanner` 在一个 SQLite 事务内持久化映射与完整 frozen batch，失败不残留半张映射图；文本内容和不匹配的弱分类引用保持原样。
- 后继发布使用显式 lineage current-head/revision CAS；云端同字段更新可生成 typed conflict，独立字段可与其同事务合并。已存在 unresolved conflict 继续阻断受影响写入，Habit 历史保护不能通过整图替换绕过。每个已发布批次的 publication metadata 保持不变，精确旧 batch status 返回 current head 指针。
- 组合测试发现：本机旧 marker 的 `snapshot_provenance_count/digest` 在同 epoch 新增映射后仍指向旧集合。它们是当前快照的派生信息，在后继 apply 事务中重新计算；原 publish digest、manifest、sequence 区间及已应用回执不改写。
- 组合测试同时发现：保留的主对象 tombstone 可以引用有真实身份/版本/删除序号的 compact deleted anchor，但初始图校验要求依赖仍保留业务 payload。canonical snapshot 和本地 projection 现在显式提供已验证的删除 anchor 集合；只有已删除主对象或已停用配置可采用相应历史引用，live 强引用仍要求 live typed 事实，完全缺失依赖仍拒绝。普通 guest preview 不具有这项 canonical 删除证据，继续执行完整源图校验。
- 冲突：Native status 直接复用要求 `published_at` 的 HTTP publication shape，而 import commit receipt 根本不携带该时间，造成仅收到成功回执后离线 status 无法表达。Native 私有状态现在允许 `published_at=null`（尚未观测到服务端元数据），取得 HTTP status 后缓存服务端时间；HTTP `import_publication_evidence` 仍要求真实非空时间。本机时间不能补值，commit/status 也仍不能代替 canonical apply 证据授权 guest 退休。

上述服务端组件报告的范围不追溯扩大；后续本机组合证据由独立 runner 登记，crypto-destroy 释放及完整四端验收仍须分别闭合。

## 完整导入、fresh 恢复与存储约束（2026-09-06）

`import_client_reference.py` 将 10 类 typed source、持久映射、reserved→account receipt→active、后继发布与 compare-and-retire 组合到实际隔离 SQLite 事务。当前源事实数量与包含历史 delete 的 manifest 总数不同，v6 `sync_import_batches.source_fact_count` 单独保存真实源数量；退休按源 hash、epoch、该数量和精确 source identity 验证，不能用 manifest 总数或 target 类别替代。

同 epoch successor 替换 active lease 前，`guest_import_source_lease_replacements` 保存经过独立 Schema/JCS hash 校验的旧 lease。新账号 receipt 缺失时恢复旧 active lease并递增 lease revision，存在时完成新 active；不能删除旧所有权证据。v6/PG mapping 的 unpublished 状态使用 nullable first/last publication 与 provenance 0，发布后版本单调，first publication 不变。target 在整个账号内唯一；Event recurrence family 另有永久分配表。普通 maintenance 不删除映射，账号库销毁或服务端 account deletion 才结束其生命周期。

`import_fresh_reference.py` 先以实际编译的验签器验证 device fence 和 optional range-close proof，再恢复独立 import control 及映射，绝不重建旧 Outbox 或伪造逐项 terminal。完整 bootstrap/finalize 提供事实、marker 和设备确认基线，必要 ack-only 完成后开放 writer。已发布但本机丢失成功回执的批次由精确 bootstrap marker 授权退休；其他 origin 的 range proof 不能覆盖当前调用设备的 allocator；never-visible proof 不确认或占用未上传的旧序号。reserved successor 遭遇账号缓存丢失时，先恢复其 predecessor 控制记录，再幂等恢复旧 lease，最后按最新 guest 图生成完整 successor。

独立测试实际通过完整导入 8 项（8 个强杀点）和 fresh 恢复 6 项（5 个强杀点）。`run_client_recovery_spike.py` 将这些测试与后述 policy/maintenance 纳入同一源摘要证据；只有该报告与统一 validator 在相同源码上通过，才能作为本轮验收。SQLite 最新逻辑模型实验为 11 项、128 个回滚边界；PostgreSQL 为 40 张新增表、66 个约束用例。历史 v4/v5 hash 和 220 个 protected 定义均保留，不以新结果重建历史基线。

## 策略回执与维护的事务边界

`policy_maintenance_reference.py` 使用 planned v6 的 singleton `sync_policy_operation_receipts` DDL。一次 operation 对应 stable workspace/device、expected revision 与 enabled；runtime handle 先独立验证，重启后合法的新 handle 不改变逻辑 operation。相同 operation/payload 重试返回原结果，同 id 异 payload 或旧 CAS 零写拒绝；新操作原子替换 latest receipt，空间为 O(1)。false→true 与 pull gate 同事务持久化，普通 prepare 在该 gate 下拒绝。下载页记录发起时的 policy revision，只有当前 revision 的完整 terminal pull 或对应 bootstrap finalize 才解除 gate，旧请求的迟到响应不能解除新 gate。paused 仍允许有真实 dirty watermark 的 ack-only。

维护按服务端已持久化的 resolved cutoff 和当前 generation/cursor/retention floor 查询，每次最多检查一批可删除记录并最多删除 500 项。未获服务端确认的 effect receipt 继续 pin change receipt；已确认水位保留其应用证据，删除明细后重开库不会重新建立 gate。未完成 bootstrap、未知 generation 或非法水位拒绝维护；不推进 cursor、不写 Outbox、不删除 mapping。以上是 Contract 隔离事务证据，Android 调度、诊断文件生命周期和加密设备缓存的产品 owner 继续属于下游实施范围。

## 永久发布历史与私有终态边界

依据 01/02 IMP-08–IMP-10，`sync_import_lineages.ever_published` 在首次发布事务（含空图）置为 true，只能在账号权威删除时随 lineage 删除。SQL 保护不允许回退、换 source/epoch/owner 或独立清除 lineage；签名 range proof 必须携带 `lineage_ever_published`。已发布 epoch 的 privacy abandon 可阻止后续上传，但不能解除 source lease；普通取消 reconciliation successor 被拒绝。遗漏/伪造前驱不能绕过永久历史。

`sync_private_lifecycle_protocol.yaml` 冻结 final receipt、远端设备缓存和诊断清理规则。prepublish crypto-destroy 释放依赖两个相互独立的证明：Backend 已签名的从未发布 abandon，以及可信 lifecycle owner 认证、完整绑定的本机 final journal。公开 hash 仅是索引，不把缺 DB、缺 key、布尔声称或已经发布的响应当成允许释放的证明。Kotlin 必须在其私有 workflow 中认证并匹配 final journal 后才调用 guest finalize；C++ 接续验证 Backend proof、source lease 与 CAS，Flutter 没有该私有 Native call 的直接入口。参考模型通过传入受认证的 journal 展开这一 owner 协作，不声称 C++ 可以自行访问 Android Keystore。

设备快照以 account/workspace/installation/schema 作 AEAD 绑定，当前 route/account/device 校验先于读取；离线只能投影 stale，从未获取则 unavailable。普通索引无设备内容，生命周期销毁同时清该缓存密钥。safe-export 有精确 Schema，900 秒 TTL 使用 boot-bound elapsed time，重启后不可信即过期，系统分享完成也清理并撤销 grant。实际 Android FileProvider 和生产 owner 由 05 验收。
