# 云同步-02：5d8fb0a Review 复核与兼容修订

复核基准为 `5d8fb0a6debe3dc4e99e8aed5213ed9d3b43731d`。2026-09-06 至 2026-09-07 在独立分支 `codex/cloud-sync-02-review` 复现后修订；字体、外观与界面的并行修改不在范围内。使用 calendar-data-contracts、debug Skill。唯一冻结状态仍由 `contracts/sync/ct0_gate_status.json` 表达，机器锁记录本次修订的实际输入摘要。

## 判断依据与范围

11 类问题均成立。原交付保护了 220 份历史 Contract，并不能据此推断新增协议之间已经闭合。本次以 02 明确的目标要求及 01 §1.1 的裁决顺序为依据，修订尚未产品接入的 Sync v1、Native v3 和 planned SQLite v6；不修改 Native v2、旧 Notification/Reminder reader 或 active SQLite v4/v5。

其中第 3 项需要区分：旧 Notification v2 拒绝 `source_migrated` 符合旧定义，应保留。缺陷是新流程没有独立的新 reader；本次补充 v3 兼容定义。第 6、10 项分别是参考门禁和验证探针的错误，不是已经观察到产品切换或产品日期解析故障。

| 编号 | 基准提交的可复现事实 | 修订及检查入口 |
| --- | --- | --- |
| 1 | 合法 `import_begin`、`import_commit` 通过消息 Schema 和原 payload codec，写入原始 Outbox DDL 触发 target_type CHECK；业务 mutation 对照可写入。 | planned v6 Outbox 加入 `workspace_import`，限定其控制操作和 `import_range` 路由；`test_sync_review_regressions.py` 对完整导入 begin/item/commit 及普通 mutation 执行正式 DDL 插入，并拒绝错误路由。 |
| 2 | 实际 Category 冲突产生的 resolution 请求、响应符合 HTTP Schema，却被 Outbox codec、Native prepare、Native ack 拒绝。 | 独立 `sync_outbox_mutation` union；prepare 返回 `route=conflict_resolution` 及专用 HTTP 原始请求；ack 接收该接口原始响应。真实冲突服务参考程序与完整 Native wrapper、正式 Outbox 在同一回归用例串联，普通 exchange 定义保留。 |
| 3 | 新流程要求的 `source_migrated` 被 Reminder/Notification reader 拒绝；简化通知表使用真实协议没有的 `cancelled` 状态。 | 新 Reminder/Notification v3 分支；Reminder 终结为 cancelled、关闭调度，Notification 终结为 abandoned。参考退休改用实际 `record_key/position/payload_json` 记录表及完整审计对象，保留送达和 attempt 标识、历史终态原字节；迟到 finalize 零写入。 |
| 4 | Native import status 各状态禁止额外属性，且没有受影响执行标识出口。 | Native 专有 `affected_execution`，包含 guest workspace、epoch、退休回执摘要、Reminder/Notification/RecoveryBatch 标识。guest 退休事务持久化结果，account observe 事务复制，重开两库及完成清理后仍返回同一集合。Backend/public status 不传输本机执行标识。 |
| 5 | 三种混合 Calendar/Search Native 请求仍只有 `timezone`。 | 新 v3 请求区分 C++ 读取偏好的 workspace 轴与 Kotlin 注入的 OS device 轴；三种返回值携带两个实际时区，查询快照和游标绑定两轴。SQLite 偏好为上海、设备为洛杉矶的回归不会相互覆盖。 |
| 6 | 当前 guest A、目标账号 B、正确当前 route revision 的激活请求符合 Schema，却被通用当前 workspace 相等校验拒绝。 | `target_workspace_with_current_route_cas` 只校验稳定路由和当前 revision；请求 workspace_id 选择目标。普通当前 workspace 操作继续要求身份相等；目标可用性与 close/open 仍由后续 Coordinator 实现。 |
| 7 | 正式 sync_state 没有普通 apply 的 UTC 清理截止时间，维护参考程序却读取简化状态中的 cleanup。 | 正式 `sync_state.resolved_conflict_cleanup_before`，绑定 account_generation；随普通 apply/bootstrap 状态事务持久化。maintenance 直接读取正式列，缺值或 generation 不匹配拒绝；重开不使用本机时间或临时状态补值。 |
| 8 | Native 冲突解决返回要求 Kotlin 拥有的 status_revision，而拒绝 native_state_revision。 | Native payload 使用必填 `native_state_revision`；公开聚合响应保留 `status_revision`。相同 queued/resolving 样本在正确 owner 字段下通过，错误 owner 字段被拒绝。 |
| 9 | 完整 Event fact 的 completed_at/created_at/updated_at/deleted_at 可接受 +08:00；start_at 已拒绝。 | 新 Sync fact/patch 的生命周期时间统一 UTC `Z`，并显式排除年份 0000；nullable 保留。旧 v2 Schema 不收紧。固定反例经 Python 和四语言探针执行。 |
| 10 | 实际 Java 接受 habit.start_date=`0000-01-01`，Dart、Python 拒绝；Kotlin 与 Java 的实现相同。 | Java/Kotlin 日期显式要求四位年份且至少为 1，date-time 格式检查与已有 C++/Dart 的日期和时分秒检查对齐；加入正常日期、年份 0000/0001/9999、合法/非法闰日和 UTC 反例。 |
| 11 | 30 个复制进 v3 的 payload 残留 integrated，注册表仍为 planned。 | 生成器在合并旧 schema 之后统一写入 planned；回归扫描全部 Native v3 internal payload，避免再次被继承注解覆盖。 |

对应实现入口均在 `contracts/spikes/sync_v1/`。本次的表和 Schema 修订在生成器维护，生成物必须与生成器输出相等，不能仅手改 JSON/YAML 后绕过生成检查。

统一门禁另发现本轮日期修订的共享对象副作用：fact 遍历直接改变公共 DATE_TIME 字典，使后续协议生成依赖调用顺序。已在收紧字段前复制 fact 图并使用固定 UTC 模式；回归对连续两次 domain 生成、前后 protocol 生成和共享常量不变进行断言。组合运行与单独生成须一致后才能重新冻结。

## 需要下游准确遵循的边界

### Outbox 与专用冲突解决发送

Outbox 的 `import_range` 表示同一 sequence 中的导入消息，HTTP 仍使用 exchange。`conflict_resolution` 表示单条专用 route；`wire_request` 直接引用 `backend_resolve_sync_conflict_request.schema.json`。Kotlin 不将其放进普通 upload_mutations，也不重建 mutation、hash 或服务端返回值。Native acknowledge 使用同一持久化 prepared_exchange_id 接受 `backend_sync_conflict_resolution_response.schema.json`。

专用冲突接口没有报告 receipt-ack 水位，因此该 ack 分支的 `reported_acknowledged_client_sequence_through` 必须是 null；真实单个 result 交给 C++ 接纳本机终态，后续 receipt_ack_flush 继续使用普通 exchange。不能根据一次 resolution 成功凭空推进整个设备的 accepted ack 水位。

### 双时区的所有者

公开 v3 混合查询不允许 Flutter 传入单个 timezone 覆盖两轴。Native 请求使用 `workspace_timezone: null` 表示由 Core 在同一查询快照内读取当前 workspace 的持久偏好，`device_timezone` 必须由 Kotlin 从 OS 注入。这里的 null 是输入指令，不是缺失的最终时区；响应中的两个字段均为实际时区字符串。

例如同一 UTC 时刻在上海已进入 9 月 6 日、洛杉矶仍在 9 月 5 日时，Event 按 workspace 轴投影，Habit/Anniversary 按 device 轴确定当地日期。任一轴变化都使原查询 snapshot/cursor 失效。02 验证协议形状、所有者和持久偏好读取；具体日期查询与 OS 监听分别由 03、05 实现。

### 完整退休审计与持久取消结果

Reminder 的存储记录比 Native 响应多 `source` 与 `recovery_batch_id`，不可直接拿 Native Schema 当完整存储 codec。本次新增 `storage/v6/reminder_record.schema.json`，保留这两个私有字段；Notification 使用独立 v3 完整审计 Schema。两个已有记录表结构不变，v6 codec 升至 5，v5 codec 和迁移历史不变。

退休与 `guest_import_execution_retirements` 在 guest 同一事务提交；account 的 `sync_import_execution_cancellations` 随观察退休回执事务保存相同结果。集合外层绑定 source workspace、epoch 和 receipt hash；Kotlin 只能取消该结果中的执行对象，不能扫描后取消整个新激活 workspace。取消本身可重试，重启后的 import_status 保留所需身份，迟到的旧 attempt 不能再次发送。

参考程序现在实际验证完整审计 JSON 和原有记录表 DDL。它仍是隔离的 Plan 02 事务 oracle，不代表产品 v6 数据库打开器、Android 通知管理器已实现；迁移 suite 中的旧 C++ v5 checker 专门验证继承 v5 数据与拒绝降级，不能用于宣称旧 reader 支持新退休状态。

## 验收与交接

复核期间先将机器状态改为 DECISION REQUIRED，待受影响证据重新执行、保护检查与默认门禁通过后才重新封版。本记录的最终结果和 HXY 交接信息在实际验收后追加，不能沿用基准提交原有的冻结摘要。


## 最终验收与 HXY 交付

2026-09-07 00:42 +0800，本轮 11 类问题修订通过默认统一入口，重新进入 `CONTRACT FROZEN / CT0–CT4 PASSED`；所有新产品 capability 继续为 planned。目标交付分支为 HXY，版本位置以包含本记录的 Git 提交为准。

- 最新机器锁：`cloud-sync-v1-contracts-2026-09-06`；SHA-256 `888fee7a8767eed7ac95eb3c7a76707e8bd3ed3264695ebdf750cc837d3643a9`；1197 份机器输入、961 Schema、220 protected Contracts。此摘要取代基准提交的旧摘要，03–06 锁定同一版本。
- 统一入口：CONTRACT FROZEN；5 runtime fixtures、17 Backend 声明/16 Controller、13 canonical integrity checks；43 项门禁反例全部通过。
- 四语言：1376 项通过且输出摘要一致。其中 751 个固定 fixture transport、444 个 Schema 边界、56 个 Native v2/v3 兼容输入、61 个 target 形状、64 个 JCS 边界；不将 transport 当作产品业务实现。
- 协议与定向复核：53 项协议测试、22 项能力/Review 回归、62 个固定 capability 样本。包含精确 Outbox DDL、真实 resolution HTTP 与完整 Native wrapper、双时区 owner、跨 workspace 激活、revision owner、UTC/date 和生成器一致性。
- 事务与存储：最新 54 项导入组件、27 项组合恢复；SQLite 11 项与134个回滚边界；PostgreSQL 70 个用例；20k/50k 实际完整发布与 mapping/receipt 数量核对通过。
- 证明：Java、Windows CNG 与手机 arm64/arm32 各49项 capsule 验证通过。未改变的 SQLCipher、JCS、Android key 等已有证据保留原记录并校验来源摘要。
- 范围：本轮没有修改 C++、Flutter、Kotlin、Backend 产品业务代码，未重复执行完整产品应用构建。实际编译并执行的是受影响的 Contract 探针；产品 v6 打开器、平台取消和真实多设备集成仍由后续分计划负责。

HXY 的33个其他任务文件及其原有日志已建立独立备份/摘要记录，交接时继续保留为未提交修改。本次提交快照的验收不能扩展为包含这些修改的整个工作目录已经通过。
