# ADR-Sync-05：Category 生命周期与弱引用

Status: Accepted (Native v3 compatibility direction; implementation evidence pending)
Date: 2026-09-05
Related: ADR-Category-01；本提案不修改其 Accepted 状态或旧 create/list 能力。

Acceptance: 用户已明确接受“保留现有 Native v2 定义、为 Anniversary 分类弱引用建立 Native v3 兼容修订”。该版本演进纳入云同步-02 的目标状态；旧 active reader/writer 在新版同包验证通过前保持原状。

## Context and Conflict

ADR-Category-01 限定 create/list，尚未接受 update/delete/reorder/sync；云同步-01 §4.1 明确要求这些目标。另有当前机器冲突：Anniversary create/update/response 的 `category_id` 有 UUID format，Event/Habit 与 Category ADR 则允许 opaque weak reference。严格格式 reader 不能直接接受所有历史值。

## Decision

- Category 自身新建 ID 继续 canonical lowercase UUIDv4；旧业务 `category_id` 保留原字符串，不补造 Category、不置空、不级联重写。不新增默认分类或名称唯一约束。
- 账号归属由 workspace/Principal 外壳隔离，不给当前 Category response 强塞必填 `user_id`。新同步 target 的 owner 显式登记。
- name/description/color/icon 各自 merge key；遵守现有 trim、空白/null、颜色规范化和字段限制。update patch 缺失是不修改，显式 null 只用于已允许 nullable 的字段。
- ordering 为实体内原子组 `{sort_order, reorder_revision}`：Backend 按 accepted reorder checked increment；相同分类的并发排序冲突，不在一次排序中重编号其他 Category。相同 sort_order 继续使用现有稳定 tie-breaker。该新增 counter 必须进入 registry，溢出整次零写。
- delete 保存 tombstone，引用保留；restore 使用同一 Category ID 和完整合法候选，形成新 entity version。删除与编辑按同步冲突规则处理。
- Anniversary 的 opaque 弱引用目标以总计划及现有 ADR 为依据；当前 create/update、list filter、occurrence summary 与 Dart/C++ reader 的 UUID 约束共同构成已发布边界。只增加 sync projection 不能闭合兼容性：远端 apply 后，同一条记录仍会由详情、列表和 occurrence 查询返回给旧的严格 reader。

## Accepted Compatibility Direction

为这项不可向旧 reader 返回的新值域建立 **Native v3 兼容修订**，保留原 Native v2 定义，不直接覆盖现有 Anniversary Schema。需要同步修订云同步-02 §5 的目标版本及 03–06 的消费约定；当前 Native v2 仍 active，本文没有激活 v3。

1. v3 为 Anniversary 的写入、读取、筛选以及包含 Anniversary 的组合投影统一定义 opaque `category_id`/`category_ids`；实体自身 ID、null/缺失、recurrence、date-only 规则保持原义。不能只放宽请求而遗漏响应或过滤器。
2. Dart、Kotlin、JNI、C++ 的 v3 reader/writer 必须在同一 APK 一起接入，并使用同一 revision/hash。新 workspace 不能经 v2 reader 返回超出其 UUID 约束的数据，也不允许自动降级或伪造 null。具体 dispatch/rejection 形状在兼容修订中一起冻结。
3. v2 Schema 与 fixture 保留作旧边界基线；新形状放在独立版本路径。Sync Protocol v1 与 SQLite v6 仍是独立版本域，不能把 Native v3 当作它们的版本号。
4. 历史 category 字符串逐字保留，不重写为 UUID、不补造实体；既有 v5 checker 和历史 migration 不变。v5→v6 只迁移已明确解释的数据，异常值给出明确失败，禁止清库恢复。旧 runtime 对 v6 的拒绝继续有效，不提供隐式降级数据库。
5. Contract 冻结前必须列出所有 Anniversary 组合投影和缓存 reader，并补齐 opaque/null/缺失/已删除分类、查询 round trip、v2 fixture 不漂移、旧 runtime 拒绝新版本、迁移失败零写的证据。普通缓存使用独立版本和失效规则，不能把新响应交给旧缓存 reader。

该兼容方向已由用户接受，实际版本迁移仍须完成机器定义和消费验证。它覆盖远端数据进入本地查询后的严格 reader；需要一次明确的 Native 版本迁移和同包全链路验证，不能降低总计划的历史弱引用保护要求。

## Consequences and Gates

现有列表和已删除/缺失 Category 的展示不能改变。新 Category 生命周期只在本 ADR 接受、typed Schema 和 consumer/历史数据回归通过后落地。现有 Anniversary 窄类型冲突是待解决边界，不得用无约束 payload 包装绕过。
